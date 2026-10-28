#===============================================================================
# FM::Mon, FM::Growth, FM::Scout — the squad: weekly growth, aging and
# scouting, carried over from Poké Manager (weekGrowth, EV_RATE, growSeasons,
# seasonRollover, genCand, pickSpecies, rollStars). Pure Ruby.
#
# Species data is a Hash of species ID => { bst:, fb: (best BST reachable by
# evolving), tier:, region:, basic:, evo: [[to_id, level], ...] }, from
# PBS/fm_species.txt. Club building levels are design levels 1-5; the
# original formulas take its 1-10 levels, so they get 2 x level.
# AI training is averaged: about 75% of weeks training, 25% resting
# (resting weeks give half the level progress and no EVs).
#===============================================================================
module FM
  class Mon
    attr_accessor :species, :bst, :level, :prog, :stars, :ev, :age, :life, :canon, :branch
    attr_writer :cond
    attr_accessor :resting, :played   # this week's focus; played a match since the last week

    # Condition 20-100 (Poké Manager cond); older saves have none = 100.
    def cond = @cond || 100

    # Hidden fatigue 0-100 (fatOf): builds up with matches played, slows
    # rest and raises injury risk. Not shown to the player.
    attr_writer :fat
    def fat = @fat || 0

    # FM::Injury: weeks left, { k:, sev:, w0:, cause: }, rehab weeks left.
    attr_accessor :inj, :injd, :rehab
    def hurt? = @inj.to_i.positive?
    def out? = hurt? && @injd && @injd[:sev] >= 2   # 빨간 부상: not in the entry
    def yellow? = hurt? && !out?

    # injProne: fixed hidden injury proneness 0.7-1.5, from a stable hash
    # (String#hash changes between runs).
    def prone
      @prone ||= (0.7 + ((seed * 2_654_435_761) % 1000) / 1000.0 * 0.8).round(2)
    end

    # natureOf: the same nature every battle (0-24, an index into the
    # engine's nature list), fixed the first time it is asked.
    def nature_index
      @nature_index ||= (seed >> 3) % 25
    end

    # Stable per-mon number, fixed once taken.
    def seed
      @seed ||= "#{@species}/#{@stars}/#{@life}/#{@branch}/#{@level}".bytes.reduce(7) { |a, b| (a * 31 + b) & 0xffffffff }
    end

    # ev nil = what makeMon's pretrain gives a mon of this level.
    def initialize(species:, bst:, level:, stars:, ev: nil, age: 0, life: Growth::LIFE, canon: false, branch: 0)
      @species, @bst, @level, @stars = species, bst, level, stars
      ev ||= Growth::EV_MAX * ((level - 8) / 62.0).clamp(0.0, 1.0)
      @prog, @ev, @age, @life, @canon, @branch = 0.0, ev.to_f, age, life, canon, branch
    end

    # Stat stages down for the whole battle: low condition (Rating.debuff)
    # plus a light injury's stat (FM::Injury::TYPES).
    def debuffs
      list = Rating.debuff(cond)
      yellow? ? list + [Injury.stat(@injd[:k])] : list
    end

    # monStr's condition part: condMul x condDebuffMul.
    def strength_mul = Rating.cond_mul(cond) * Rating.debuff_mul(debuffs)

    def to_rating
      { bst: @bst, level: @level, stars: @stars, ev: @ev, cond: cond, mul: Rating.debuff_mul(debuffs) }
    end

    def rating = Rating.mon(to_rating)
  end

  module Growth
    LIFE = 10
    EV_MAX = 510
    TRAIN_SHARE = 0.75

    module_function

    def original_level(design_level) = (2 * design_level).clamp(1, 10)

    # Seasons to fill 510 EVs: 5 at original level 1, 3 at level 10.
    def grow_seasons(original_level)
      5 - (original_level.clamp(1, 10) - 1) * 2 / 9.0
    end

    COND_MIN = 20
    TRAIN_COND = 3
    MATCH_COND = 4

    # Weekly condition and focus (weekGrowth/condGain, AI rule): rest below
    # 60 and keep resting until 85; resting recovers 10 + 20% of what's
    # missing (half if it played last week, less with fatigue, x0.8 while
    # out injured); training costs 3. Fatigue then eases (fatWeek): 2 if it
    # played, 14 resting, 9 training.
    def condition_week(mon)
      played = mon.played
      mon.played = false
      mon.resting = mon.out? || mon.cond < 60 || (mon.resting && mon.cond < 85)
      if mon.resting
        g = (10 + (100 - mon.cond) * 0.2) * (1 - mon.fat / 200.0) * (played ? 0.5 : 1) * (mon.out? ? 0.8 : 1)
        mon.cond = [mon.cond + [g.round, 1].max, 100].min
      else
        mon.cond = [mon.cond - TRAIN_COND, COND_MIN].max
      end
      mon.fat = [mon.fat - (played ? 2 : mon.resting ? 14 : 9), 0].max
    end

    def drain(mon, amount)
      mon.cond = [mon.cond - amount, COND_MIN].max
    end

    # A match played (drainCond): costs more with fatigue, and 70% of it
    # becomes fatigue.
    def match_drain(mon, amount)
      d = amount * (1 + mon.fat / 150.0)
      mon.cond = [(mon.cond - d).round, COND_MIN].max
      mon.fat = [mon.fat + d * 0.7, 100].min
    end

    # One week of growth after condition_week: resting gives half the level
    # progress and no EVs; tired mons (under 40) train at half effect.
    # train_level is the club's TRAINING design level.
    def week(mon, train_level:, species:)
      return mon if mon.hurt?   # injured: recovery only, no training
      t = original_level(train_level)
      g = [0.35, 1.15 - mon.level / 110.0].max * (0.3 + 0.03 * t)
      tired = mon.cond < 40
      mon.prog += mon.resting ? g * 0.5 : g * (tired ? 0.6 : 1)
      while mon.prog >= 1 && mon.level < 100
        mon.prog -= 1
        mon.level += 1
      end
      mon.prog = 0.0 if mon.level >= 100
      # EV_RATE: a full 510 over growSeasons, counting ~75% training weeks.
      unless mon.resting
        mon.ev = [mon.ev + EV_MAX / (52.0 * TRAIN_SHARE * grow_seasons(t)) * (tired ? 0.5 : 1), EV_MAX].min
      end
      evolve(mon, species)
    end

    def evolve(mon, species)
      loop do
        evo = species.fetch(mon.species)[:evo]
        break if evo.empty?
        to, lv = evo[mon.branch % evo.size]
        break if mon.level < lv
        mon.species = to
        mon.bst = species.fetch(to)[:bst]
      end
      mon
    end

    # Jan 1: everyone ages; those at the end of their life retire.
    def rollover(squad)
      squad.each { |m| m.age += 1 }
      retired = squad.select { |m| m.age >= m.life }
      squad.reject! { |m| m.age >= m.life }
      retired
    end

    # Fame relaxes toward 40 each season; very high fame decays faster.
    def fame_drift(fame)
      (fame + (40 - fame) * 0.08 - [0, fame - 100].max * 0.05).clamp(1, Economy::FAME_MAX)
    end
  end

  module Scout
    FEE = 3000
    AGE_WEIGHTS = [40, 28, 18, 9, 5].freeze   # ages 0-4 for young prospects
    SUB_TIERS = [1, 4, 5].freeze              # sub-legendary, ultra beast, paradox
    LEGEND_TIERS = [2, 3].freeze

    module_function

    def weighted(items, rng)
      weights = items.map { |i| yield(i) }
      x = rng.rand * weights.sum
      items.each_with_index do |item, i|
        x -= weights[i]
        return item if x <= 0
      end
      items.last
    end

    def ri(rng, a, b) = a + rng.rand(b - a + 1)

    # pickSpecies: basic forms of the region, weighted toward a final BST.
    def pick_species(pool, region, target, sub_weight, rng)
      basics = pool.select { |_, s| s[:basic] && s[:region] == region && !LEGEND_TIERS.include?(s[:tier]) }
      weighted(basics.keys, rng) do |id|
        s = pool[id]
        d = (s[:fb] - target) / 70.0
        w = Math.exp(-d * d) + 0.002
        SUB_TIERS.include?(s[:tier]) ? w * sub_weight : w
      end
    end

    def roll_stars(mean, rng)
      (mean + (rng.rand + rng.rand + rng.rand - 1.5) * 1.2).round.clamp(1, 5)
    end

    # genCand. scout_level is the club's SCOUTING design level.
    def candidate(pool, region:, scout_level:, avg_level:, rng:)
      q = Growth.original_level(scout_level)
      target = 455 + q * 8 + ri(rng, -50, 50)
      sub_weight = q >= 5 ? 0.05 * (q - 4) : 0
      base = pick_species(pool, region, target, sub_weight, rng)
      stars = roll_stars(2.3 + q * 0.17, rng)
      vet = rng.rand < 0.15
      level = vet ? (avg_level * (0.45 + rng.rand * 0.25)).round : ri(rng, 5, 10) + q
      age = vet ? ri(rng, 3, 8) : weighted((0..4).to_a, rng) { |a| AGE_WEIGHTS[a] }
      frac = age.positive? ? [1.0, age / Growth.grow_seasons(ri(rng, 3, 7))].min * (0.85 + rng.rand * 0.15) : 0.0
      mon = Mon.new(species: base, bst: pool[base][:bst], level: level, stars: stars,
                    ev: Growth::EV_MAX * frac, age: age, branch: rng.rand(10_000))
      Growth.evolve(mon, pool)
      s = pool[base]
      cost = (200 + [0, s[:fb] - 380].max * 2.2 + stars * stars * 120 + level * 30) *
             (s[:tier].zero? ? 1 : 3) * (1 + 1.2 * frac) * (age >= Growth::LIFE - 2 ? 0.7 : 1) *
             (0.85 + rng.rand * 0.3) * 12
      { base: base, mon: mon, cost: [(cost / 500).round * 500, 500].max }
    end

    # monValue x share of life left: how much a mon is worth keeping.
    def value(mon, pool)
      fb = pool.dig(mon.species, :fb) || mon.bst
      fb * (0.75 + 0.1 * mon.stars) * (0.8 + 0.4 * mon.ev / Growth::EV_MAX) *
        [(mon.life - mon.age).fdiv(mon.life), 0.1].max
    end
  end
end
