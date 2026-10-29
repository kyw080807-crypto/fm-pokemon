#===============================================================================
# FM::Daycare — 키우미집 (Poké Manager: DC, dcSlots, dcEggMax, dcRateMul,
# dcCompat, dcMother, dcBabySp, dcBaby, dcHatchW, dcWeek, aiDaycare).
# Pure Ruby; egg groups and gender ratios are Essentials' (fm_species).
# - Parents: a club's retired mons that don't coach, and Ditto (retired or
#   in the squad). A male and a female sharing an egg group (10% an egg a
#   week if the same family, else 6%), or anything with a Ditto (4%).
#   Never legends or sub-legends, the Undiscovered group, two Dittos, or a
#   genderless mon except with a Ditto.
# - The facility (original level from DAYCARE): pairs 1 + level / 4, eggs
#   kept 2 + level / 5, egg chance x(1 + 0.05 (level - 1)); a pair costs
#   ₽3,000 a week. An egg hatches after max(2, 3 + (final BST - 400) / 80
#   in 3-8 weeks, one fewer from level 6).
# - The baby: the mother's first stage (the other parent's with a Ditto;
#   incense babies hatch one stage up; Nidoran♀ and Illumise half the other
#   kind), level 1, bond 120, homegrown for the club. Our IVs are a ★
#   level, so each parent's six IVs are drawn from its ★ range; the baby
#   takes 3 of them (4 from level 10), the rest random, back to ★.
# - It joins when there is room (and no family twice, specialty rule);
#   the player's egg waits, the AI's is lost (it keeps one place spare).
# - AI clubs pair their best match every 13 weeks with ₽90,000 to spare
#   and let the pairs go below ₽30,000.
# Design 01 makes 키우미집 a club building: only a club that has built it
# breeds (the original gives everyone one).
# Not carried over (no data here): held items (Everstone, Destiny Knot),
# abilities and egg moves, nurses.
#===============================================================================
module FM
  module Daycare
    FEE = 3000
    EGG_MAX = 2
    INCENSE = %w[AZURILL WYNAUT MIMEJR BONSLY HAPPINY MUNCHLAX CHINGLING MANTYKE BUDEW].freeze
    FEMALE = { "AlwaysMale" => 0.0, "FemaleOneEighth" => 0.125, "Female25Percent" => 0.25, "Female50Percent" => 0.5,
               "Female75Percent" => 0.75, "FemaleSevenEighths" => 0.875, "AlwaysFemale" => 1.0 }.freeze
    IV_LO = [4, 10, 16, 21, 26].freeze
    IV_HI = [16, 21, 26, 30, 31].freeze

    module_function

    def built?(club) = club.facilities.fetch(:DAYCARE, 0).positive?
    def level(club) = Growth.original_level(club.facilities.fetch(:DAYCARE, 0))
    def slots(club) = 1 + level(club) / 4
    def egg_max(club) = EGG_MAX + level(club) / 5
    def rate_mul(club) = 1 + 0.05 * (level(club) - 1)

    def state(club) = club.daycare ||= { pairs: [], eggs: [] }

    # genderOf: :M, :F or :N (genderless), fixed per mon by its seed.
    def gender(pool, mon)
      ratio = pool.dig(mon.species, :gender) || "Female50Percent"
      return :N if ratio == "Genderless"
      (mon.seed % 1000) / 1000.0 < FEMALE.fetch(ratio, 0.5) ? :F : :M
    end

    # Species IDs are Strings in tools and tests, Symbols in the game.
    def key(pool, name) = pool.key?(name) ? name : pool.key?(name.to_sym) ? name.to_sym : nil
    def ditto?(pool, mon) = Scout.family(pool, mon.species).to_s == "DITTO"
    def eggs(pool, mon) = pool.dig(mon.species, :eggs) || []
    def special?(pool, mon) = [1, 2, 3, 4, 5].include?(pool.dig(mon.species, :tier))

    # dcCompat -> { ok:, rate: } or { ok: false, why: }
    def compat(pool, a, b)
      return { ok: false, why: :pick_two } if a.nil? || b.nil? || a.equal?(b)
      return { ok: false, why: :legend } if special?(pool, a) || special?(pool, b)
      return { ok: false, why: :undiscovered } if (eggs(pool, a) + eggs(pool, b)).include?("Undiscovered")
      da, db = ditto?(pool, a), ditto?(pool, b)
      return { ok: false, why: :two_dittos } if da && db
      return { ok: true, rate: 0.04 } if da || db
      ga, gb = gender(pool, a), gender(pool, b)
      return { ok: false, why: :genderless } if ga == :N || gb == :N
      return { ok: false, why: :same_gender } if ga == gb
      return { ok: false, why: :egg_group } if (eggs(pool, a) & eggs(pool, b)).empty?
      { ok: true, rate: Scout.family(pool, a.species) == Scout.family(pool, b.species) ? 0.1 : 0.06 }
    end

    def mother(pool, a, b)
      return b if ditto?(pool, a)
      return a if ditto?(pool, b)
      gender(pool, a) == :F ? a : b
    end

    # dcBabySp
    def baby_species(pool, mom, rng = nil)
      s = Scout.family(pool, mom.species)
      evo = pool.dig(s, :evo) || []
      s = evo.first.first if INCENSE.include?(s.to_s) && !evo.empty?
      if rng
        other = { "NIDORANfE" => "NIDORANmA", "ILLUMISE" => "VOLBEAT" }[s.to_s]
        alt = other && key(pool, other)
        s = alt if alt && rng.rand < 0.5
      end
      s
    end

    def ivs(stars, rng) = Array.new(6) { rng.rand(IV_LO[stars - 1]..IV_HI[stars - 1]) }

    # ivStars
    def iv_stars(ivs)
      a = ivs.sum / 6.0
      a >= 27 ? 5 : a >= 23.25 ? 4 : a >= 18.25 ? 3 : a >= 12.75 ? 2 : 1
    end

    def hatch_weeks(pool, species, club)
      [2, (3 + ((pool[species][:fb] - 400) / 80.0).round).clamp(3, 8) - (level(club) >= 6 ? 1 : 0)].max
    end

    # dcBaby
    def baby(pool, club, a, b, rng, year:)
      mom = mother(pool, a, b)
      sp = baby_species(pool, mom, rng)
      pa, pb = ivs(a.stars, rng), ivs(b.stars, rng)
      n = [3 + (level(club) >= 10 ? 1 : 0), 6].min
      keep = (0..5).to_a.shuffle(random: rng).first(n)
      iv = (0..5).map { |i| keep.include?(i) ? (rng.rand < 0.5 ? pa : pb)[i] : rng.rand(0..31) }
      m = Mon.new(species: sp, bst: pool[sp][:bst], level: 1, stars: iv_stars(iv), ev: 0, age: 0)
      m.bond = 120
      m.bond_year = year
      m.hatched_by = club.id
      m.parents = [mom.species, (mom.equal?(a) ? b : a).species]
      m
    end

    def candidates(pool, club)
      club.retired.reject { |m| m.coach || m.nurse } + club.squad.select { |m| ditto?(pool, m) && !m.nurse }
    end

    def paired?(club, mon) = state(club)[:pairs].any? { |x, y| x.equal?(mon) || y.equal?(mon) }

    def room?(club, mon, pool, ai:)
      cap = Build.squad_size(club.clubhouse) - (ai ? 1 : 0)
      club.squad.size < cap && !Recruit.fam_dup?(club, mon.species, pool) && !Specialty.block?(club, mon, pool)
    end

    # dcWeek -> events
    def week(world, club, rng)
      pool = world.species
      st = state(club)
      return [] if st[:pairs].empty? && st[:eggs].empty?
      date = world.calendar.date
      ai = world.ai?(club)
      events = []
      st[:pairs].select! do |x, y|
        ok = [x, y].all? { |m| !m.coach && !m.nurse && (club.retired.include?(m) || club.squad.include?(m)) } && compat(pool, x, y)[:ok]
        ok
      end
      st[:pairs].clear unless built?(club)
      st[:pairs].pop while st[:pairs].size > slots(club)
      club.wallet.record(-FEE * st[:pairs].size, category: :daycare, date: date) unless st[:pairs].empty?
      st[:pairs].each do |x, y|
        break if st[:eggs].size >= egg_max(club)
        next unless rng.rand < compat(pool, x, y)[:rate] * rate_mul(club)
        m = baby(pool, club, x, y, rng, year: world.calendar.year)
        st[:eggs] << { mon: m, hatch: world.calendar.date_after(date, 7 * hatch_weeks(pool, m.species, club)) }
        events << { kind: :egg, club: club.id, species: m.species, date: date }
      end
      st[:eggs].select! do |e|
        next true if (e[:hatch] <=> date).positive?
        if room?(club, e[:mon], pool, ai: ai)
          club.squad << e[:mon]
          club.refresh_rating
          events << { kind: :hatched, club: club.id, species: e[:mon].species, stars: e[:mon].stars,
                      parents: e[:mon].parents, date: date }
          false
        else
          events << { kind: :egg_waiting, club: club.id, species: e[:mon].species, date: date } if !ai && !e[:waiting]
          e[:waiting] = true
          !ai   # the player's egg waits; the AI's is lost
        end
      end
      events
    end

    # aiDaycare: every 13 weeks the best pair (mother's final BST, stars,
    # egg chance), if money allows.
    def ai_pick(world, club, week_no)
      pool = world.species
      st = state(club)
      unless st[:pairs].empty?
        st[:pairs].clear if club.wallet.balance < FEE * 10
        return
      end
      return unless built?(club) && week_no % 13 == 1 && club.wallet.balance >= FEE * 30
      cands = candidates(pool, club).reject { |m| special?(pool, m) }.first(14)
      best = nil
      score = 0
      cands.combination(2) do |x, y|
        c = compat(pool, x, y)
        next unless c[:ok]
        mom = mother(pool, x, y)
        next if Recruit.fam_dup?(club, baby_species(pool, mom), pool)
        v = pool[mom.species][:fb] + 12 * (x.stars + y.stars) + 300 * c[:rate]
        if v > score
          score = v
          best = [x, y]
        end
      end
      st[:pairs] << best if best && score >= 560
    end
  end
end
