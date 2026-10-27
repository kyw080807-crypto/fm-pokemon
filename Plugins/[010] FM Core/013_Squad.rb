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

    # ev nil = what makeMon's pretrain gives a mon of this level.
    def initialize(species:, bst:, level:, stars:, ev: nil, age: 0, life: Growth::LIFE, canon: false, branch: 0)
      @species, @bst, @level, @stars = species, bst, level, stars
      ev ||= Growth::EV_MAX * ((level - 8) / 62.0).clamp(0.0, 1.0)
      @prog, @ev, @age, @life, @canon, @branch = 0.0, ev.to_f, age, life, canon, branch
    end

    def to_rating
      { bst: @bst, level: @level, stars: @stars, ev: @ev }
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

    # One week for an AI mon. train_level is the club's TRAINING design level.
    def week(mon, train_level:, species:)
      t = original_level(train_level)
      g = [0.35, 1.15 - mon.level / 110.0].max * (0.3 + 0.03 * t)
      mon.prog += g * (TRAIN_SHARE + (1 - TRAIN_SHARE) * 0.5)
      while mon.prog >= 1 && mon.level < 100
        mon.prog -= 1
        mon.level += 1
      end
      mon.prog = 0.0 if mon.level >= 100
      mon.ev = [mon.ev + EV_MAX / (52.0 * grow_seasons(t)), EV_MAX].min
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
