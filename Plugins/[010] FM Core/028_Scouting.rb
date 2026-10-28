#===============================================================================
# FM::Scouting — the player's scouting office (Poké Manager: sendScout,
# scoutWeek, maxScouts, sendTypeScout, scGen, scoutPassive, ageGuess and
# the shown-stars accuracy in genCand). Pure Ruby; state lives on the
# World (player only — AI clubs scout with FM::Recruit.weekly).
# - A scout (₽3,000) goes to a region and reports next week: 3-5
#   candidates, kept 4 weeks. Scouts in the field at once: 1 + original
#   scouting level / 3 (+1 at 10).
# - A type scout (₽8,000) looks for one type (now or after evolving) in a
#   region or everywhere: 3-5 candidates next week, kept 6 weeks.
# - A regular report comes free every max(2, 5 - (level - 1) / 3) weeks:
#   2 candidates (3 from level 7) from anywhere, scouted 2 levels lower,
#   kept 6 weeks.
# - Reports never repeat an evolution family already in the squad or the
#   list (8 re-rolls). Stars are shown right with chance 0.45 + 0.055 x
#   level (+0.1 in the club's own region), else one off; age is a range
#   that narrows with the level.
# - Design 05 (스카우팅 범위): with transport below 3 a club scouts only its
#   own region.
#===============================================================================
module FM
  module Scouting
    FEE = Scout::FEE
    TYPE_FEE = 8000
    KEEP_WEEKS = 4
    TYPE_KEEP_WEEKS = 6
    WORLD_TRANSPORT = 3
    PASSIVE_DOWN = 2

    module_function

    def orig(club) = Growth.original_level(club.facilities.fetch(:SCOUTING, 0))
    def max_scouts(club) = 1 + orig(club) / 3 + (orig(club) >= 10 ? 1 : 0)
    def report_size(club) = 3 + (orig(club) >= 7 ? 1 : 0) + (orig(club) >= 10 ? 1 : 0)
    def passive_gap(club) = [2, 5 - (orig(club) - 1) / 3].max
    def passive_size(club) = 2 + (orig(club) >= 7 ? 1 : 0)

    # Regions this club may send scouts to (design 05).
    def regions(world, club)
      city = world.cities[club.city]
      city && city.transport < WORLD_TRANSPORT ? [club.region] : world.regions
    end

    def state(world) = world.scouting ||= { assign: [], cands: [], next_passive: nil }

    def send(world, club, region, type: nil, date:)
      st = state(world)
      fee = type ? TYPE_FEE : FEE
      return :busy if st[:assign].size >= max_scouts(club)
      return :region if region && !regions(world, club).include?(region)
      return :region if region.nil? && regions(world, club).size == 1   # anywhere needs world range
      return :money if club.wallet.balance < fee
      club.wallet.record(-fee, category: :scout, date: date)
      st[:assign] << { region: region, type: type, due: world.calendar.date_after(date, 7) }
      nil
    end

    # ageGuess
    def age_guess(age, level, rng)
      h = [0, ((9 - level) / 3.0).ceil].max
      return [age, age] if h.zero?
      lo = age - rng.rand(0..2 * h)
      hi = lo + 2 * h
      if lo.negative?
        hi -= lo
        lo = 0
      end
      if hi > Growth::LIFE - 1
        lo -= hi - (Growth::LIFE - 1)
        hi = Growth::LIFE - 1
      end
      [[lo, 0].max, hi]
    end

    # scGen: n candidates as the club's scouts see them.
    def generate(world, club, n, region:, type: nil, down: 0, keep:, date:, rng:)
      st = state(world)
      pool = world.species
      level = [orig(club) - down, 1].max
      year = world.calendar.year
      mul = Recruit.recovery_mul(club, year)
      sig = Specialty.of(club)
      taken = (club.squad.map(&:species) + st[:cands].map { |c| c[:mon].species }).map { |s| Scout.family(pool, s) }
      out = []
      n.times do
        c = nil
        9.times do
          r = region || world.regions[rng.rand(world.regions.size)]
          t = type || (sig && rng.rand < Specialty::SCOUT_SHARE ? sig : nil)
          c = Scout.candidate(pool, region: r, scout_level: 0, orig_level: level, avg_level: world.avg_level(r), rng: rng,
                                    bonus: Recruit.scout_bonus(club, year), type: t)
          c[:region] = r
          f = Scout.family(pool, c[:mon].species)
          break unless taken.include?(f) || out.any? { |o| Scout.family(pool, o[:mon].species) == f }
        end
        c = c.merge(full: c[:cost], cost: Recruit.disc_cost(c[:cost], mul)) if mul < 1
        acc = (0.45 + 0.055 * level + (c[:region] == club.region ? 0.1 : 0)).clamp(0.2, 0.98)
        shown = rng.rand > acc ? (c[:mon].stars + (rng.rand < 0.5 ? -1 : 1)).clamp(1, 5) : c[:mon].stars
        lo, hi = age_guess(c[:mon].age, level, rng)
        out << c.merge(shown: shown, age_lo: lo, age_hi: hi, until: world.calendar.date_after(date, 7 * keep))
      end
      st[:cands].concat(out)
      out
    end

    # Monday: due reports come in, the regular report when due, old
    # candidates go. -> events
    def week(world, club, date:, rng:)
      st = state(world)
      events = []
      st[:cands].reject! { |c| (c[:until] <=> date) <= 0 }
      due, st[:assign] = st[:assign].partition { |a| (a[:due] <=> date) <= 0 }
      due.each do |a|
        if a[:type]
          got = generate(world, club, report_size(club), region: a[:region], type: a[:type], keep: TYPE_KEEP_WEEKS,
                                                         date: date, rng: rng)
        else
          got = generate(world, club, report_size(club), region: a[:region], keep: KEEP_WEEKS, date: date, rng: rng)
          right = world.leg_right
          if right && right[:club] == club.id && (!right[:used] || rng.rand < Legend::SCOUT_CHANCE) &&
             (l = Legend.candidate(world, club, a[:region], rng))
            right[:used] = true
            st[:cands] << l.merge(shown: l[:mon].stars, age_lo: 0, age_hi: 0, region: a[:region],
                                  until: world.calendar.date_after(date, 7 * KEEP_WEEKS * 2))
            got << l
          end
        end
        events << { kind: :scout_report, club: club.id, region: a[:region], type: a[:type],
                    species: got.map { |c| c[:mon].species }, date: date }
      end
      st[:next_passive] ||= world.calendar.date_after(date, 7 * passive_gap(club))
      if (st[:next_passive] <=> date) <= 0
        st[:next_passive] = world.calendar.date_after(date, 7 * passive_gap(club))
        got = generate(world, club, passive_size(club), region: nil, down: PASSIVE_DOWN, keep: TYPE_KEEP_WEEKS,
                                                        date: date, rng: rng)
        events << { kind: :scout_report, club: club.id, region: nil, passive: true,
                    species: got.map { |c| c[:mon].species }, date: date }
      end
      events
    end

    def take(world, cand) = state(world)[:cands].delete(cand)
  end
end
