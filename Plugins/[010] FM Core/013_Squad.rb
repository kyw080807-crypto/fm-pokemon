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

    # Career record (Poké Manager ko / gp / sko / sgp / titles / awards):
    # coach quality (FM::Coach) and the season's KO king.
    attr_writer :ko, :gp, :sko, :sgp
    def ko = @ko || 0
    def gp = @gp || 0
    def sko = @sko || 0
    def sgp = @sgp || 0
    def titles = @titles ||= []
    def awards = @awards ||= []
    # Retired: coaching (FM::Coach) and the food it ate when it retired.
    attr_accessor :coach, :food_fixed

    # declineMul: the last two seasons of its life play at x0.96, then x0.92.
    def decline_mul = @age >= @life - 1 ? 0.92 : @age >= @life - 2 ? 0.96 : 1.0

    # FM::Morale: morale 0-100, bond 0-255 (set by World when it first
    # sees the mon), the season it joined, this week's mood, recent KOs.
    attr_writer :mor, :bond, :form_ko
    attr_accessor :bond_year
    def mor = @mor || 60
    def bond = @bond || Morale::BOND_START
    def bond? = !@bond.nil?
    def form_ko = @form_ko || 0

    def set_mood(kind, week)
      @md = [kind, week]
    end

    def mood(week) = @md && @md[1] == week ? @md[0] : nil

    # On a friendly tour this week (FM::Tour): no training or rest.
    attr_accessor :tour

    # Days spent travelling this week (Club#travel): no training on them.
    attr_accessor :away_days
    def hurt? = @inj.to_i.positive?
    # 빨간 부상 (severity 2-3): heals resting; out of the entry unless the
    # player plays it through (ptp, 무리 출전).
    def red? = hurt? && @injd && @injd[:sev] >= 2
    attr_accessor :ptp
    def out? = red? && !@ptp
    def yellow? = hurt? && !red?

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
      return list + %i[spe main] if red? && @ptp   # 무리 출전: speed and main attack -1 more
      yellow? ? list + [Injury.stat(@injd[:k])] : list
    end

    # monStr's condition part: condMul x condDebuffMul.
    def strength_mul = Rating.cond_mul(cond) * Rating.debuff_mul(debuffs) * decline_mul

    def to_rating
      { bst: @bst, level: @level, stars: @stars, ev: @ev, cond: cond,
        mul: Rating.debuff_mul(debuffs) * decline_mul * Morale.mor_mul(self) * Morale.mood_mul(self, Morale.week) }
    end

    # Rating.mon of to_rating, kept until something it reads changes (it
    # is asked for constantly: entry, food, running costs).
    def rating
      key = [@species, @bst, @level, @stars, @ev, @age].hash   # (cond and injuries don't change Rating.mon)
      return @rating_v if @rating_k == key
      @rating_k = key
      @rating_v = Rating.mon(to_rating)
    end
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
    # rest_mul: the hotel's rest multiplier while staying at a tournament.
    def condition_week(mon, rest_mul: 1.0)
      played = mon.played
      mon.played = false
      if Scout.pool && Scout.legend?(Scout.pool, mon.species)   # legDebuffed: always rests
        mon.resting = true
        mon.cond = [mon.cond + [rest_gain(mon, played: played).round, 1].max, 100].min
        mon.fat = [mon.fat - (played ? 2 : 14), 0].max
        return
      end
      if mon.tour   # touring: fatigue eases (fatWeek), nothing else this week
        mon.resting = false
        mon.fat = [mon.fat - (played ? 2 : 9), 0].max
        return
      end
      mon.resting = mon.red? || mon.cond < 60 || (mon.resting && mon.cond < 85)
      if mon.resting
        g = rest_gain(mon, played: played) * (mon.red? ? 0.8 : 1) * rest_mul
        mon.cond = [mon.cond + [g.round, 1].max, 100].min
      else
        mon.cond = [mon.cond - TRAIN_COND, COND_MIN].max
      end
      mon.fat = [mon.fat - (played ? 2 : mon.resting ? 14 : 9), 0].max
    end

    # A week's rest (condGain): 10 + 20% of what's missing, less with
    # fatigue, half if it played last week.
    def rest_gain(mon, played: false)
      (10 + (100 - mon.cond) * 0.2) * (1 - mon.fat / 200.0) * (played ? 0.5 : 1)
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
    # fx: FM::Coach.fx multipliers ({ lv:, ev: }).
    def week(mon, train_level:, species:, fx: nil)
      home = (7 - mon.away_days.to_i).clamp(0, 7) / 7.0   # design 05: travel days stop training
      mon.away_days = nil
      touring = mon.tour
      mon.tour = nil
      return mon if mon.hurt?   # injured: recovery only, no training
      t = original_level(train_level)
      g = [0.35, 1.15 - mon.level / 110.0].max * (0.3 + 0.03 * t) * home * (fx ? fx[:lv] : 1)
      legend = Scout.pool && Scout.legend?(Scout.pool, mon.species)
      if touring || legend   # a tour week: half the level progress, no EVs; a legend: full, no EVs
        mon.prog += legend ? g : 0.5 * g
        while mon.prog >= 1 && mon.level < 100
          mon.prog -= 1
          mon.level += 1
        end
        mon.prog = 0.0 if mon.level >= 100
        return evolve(mon, species)
      end
      tired = mon.cond < 40
      mon.prog += mon.resting ? g * 0.5 : g * (tired ? 0.6 : 1)
      while mon.prog >= 1 && mon.level < 100
        mon.prog -= 1
        mon.level += 1
      end
      mon.prog = 0.0 if mon.level >= 100
      # EV_RATE: a full 510 over growSeasons, counting ~75% training weeks.
      unless mon.resting
        mon.ev = [mon.ev + EV_MAX / (52.0 * TRAIN_SHARE * grow_seasons(t)) * (tired ? 0.5 : 1) * home * (fx ? fx[:ev] : 1), EV_MAX].min
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

    # The world's species pool, for rules that need a mon's types
    # (FM::Specialty); World sets it when built or loaded.
    class << self
      attr_accessor :pool
    end

    # finalTypes: its types and those of the first evolution line (cached
    # per pool, like the original's FT_CACHE; not saved).
    def self.final_types(pool, species)
      @ft_cache = {} unless @ft_pool.equal?(pool)
      @ft_pool = pool
      @ft_cache[species] ||= final_types_uncached(pool, species)
    end

    def self.final_types_uncached(pool, species)
      out = []
      s = species
      5.times do
        d = pool[s] or break
        out.concat(d[:types] || [])
        nxt = d[:evo]&.first or break
        s = nxt.first
      end
      out.uniq
    end

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
    # BASICS_R: first stages of a region, legends left out (cached per pool).
    def basics_in(pool, region)
      @basics = {} unless @basics_pool.equal?(pool)
      @basics_pool = pool
      @basics[region] ||= pool.select { |_, s| s[:basic] && s[:region] == region && !LEGEND_TIERS.include?(s[:tier]) }
    end

    # type: only species of that type now or after evolving (PICK_TYPE),
    # from every region when the region has fewer than 4.
    def pick_species(pool, region, target, sub_weight, rng, type: nil)
      basics = basics_in(pool, region)
      if type
        typed = basics.select { |id, _| Scout.final_types(pool, id).include?(type) }
        if typed.size < 4
          typed = pool.select do |id, s|
            s[:basic] && !LEGEND_TIERS.include?(s[:tier]) && Scout.final_types(pool, id).include?(type)
          end
        end
        basics = typed unless typed.empty?
      end
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
    # bonus: genCand's scoutBonus (Recruit.scout_bonus), added to the
    # quality level for the target strength and stars only.
    # orig_level: the original 1-10 scouting level to use instead (scGen's
    # lvDown).
    def candidate(pool, region:, scout_level:, avg_level:, rng:, bonus: 0, type: nil, orig_level: nil)
      q = orig_level || Growth.original_level(scout_level)
      ql = q + bonus
      target = 455 + ql * 8 + ri(rng, -50, 50)
      sub_weight = q >= 5 ? 0.05 * (q - 4) : 0
      base = pick_species(pool, region, target, sub_weight, rng, type: type)
      stars = roll_stars(2.3 + ql * 0.17, rng)
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

    # monValue: what a mon is worth, life left aside.
    def mon_value(mon, pool)
      fb = pool.dig(mon.species, :fb) || mon.bst
      fb * (0.75 + 0.1 * mon.stars) * (0.8 + 0.4 * mon.ev / Growth::EV_MAX)
    end

    # remainF: seasons left, weighing the last six.
    def remain_f(age) = 0.5 + 0.5 * [1.0, (Growth::LIFE - age) / 6.0].min

    # famOf: the first stage of its evolution family (via Prev).
    def family(pool, species)
      s = species
      5.times do
        prev = pool.dig(s, :prev) or break
        s = prev
      end
      s
    end

    # isHome: it or an earlier stage comes from `region` (dex range).
    def home?(pool, species, region)
      s = species
      6.times do
        return true if pool.dig(s, :region) == region
        s = pool.dig(s, :prev) or return false
      end
      false
    end

    # LEGT: legendary / mythical (tier 2, 3); SUBT tier 1 = 준전설.
    def legend?(pool, species) = [2, 3].include?(pool.dig(species, :tier))

    # monValue x share of life left: how much a mon is worth keeping.
    def value(mon, pool)
      fb = pool.dig(mon.species, :fb) || mon.bst
      fb * (0.75 + 0.1 * mon.stars) * (0.8 + 0.4 * mon.ev / Growth::EV_MAX) *
        [(mon.life - mon.age).fdiv(mon.life), 0.1].max
    end
  end
end
