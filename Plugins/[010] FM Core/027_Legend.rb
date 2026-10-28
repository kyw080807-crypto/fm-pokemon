#===============================================================================
# FM::Legend — legendary and mythical Pokémon (Poké Manager: LEG_LINES,
# initLegends, legNerf, makeLegendMon, legendCand, legRight, aiLegendClaim,
# legendSeasonEnd, legAcquire / legRelease). Pure Ruby.
# - Each legendary line (a first stage of tier 2 or 3) exists once in the
#   world, a club holds at most one, and it stays LEG_YEARS seasons, then
#   leaves (it won't return to the club it just left).
# - A symbol, not a fighter (the original's default 전설 디버프): no EVs,
#   ★1, it can't train — it rests and gains full level progress.
# - A club with one sells merchandise x1.6 and gains fame +0.1 a week.
# - Only the PWT champion finds one, the next season: the AI champion
#   takes one free at the new year; the player gets one free as a gift,
#   then scout reports bring an owner-less one now and then (SCOUT_CHANCE)
#   at the legend price.
#===============================================================================
module FM
  module Legend
    LEG_YEARS = 3
    MERCH_MUL = 1.6
    FAME_WEEK = 0.1
    SCOUT_CHANCE = 0.12
    HOME_WEIGHT = 4
    GIFT_WEEKS = 16

    module_function

    def lines(pool)
      pool.select { |_, s| s[:basic] && Scout::LEGEND_TIERS.include?(s[:tier]) }.keys
    end

    def line_of(pool, species) = Scout.family(pool, species)

    def held(club, pool) = club.squad.find { |m| Scout.legend?(pool, m.species) }

    # legNerf
    def nerf(mon)
      mon.ev = 0.0
      mon.stars = 1
      mon
    end

    def make(pool, line, level)
      nerf(Mon.new(species: line, bst: pool[line][:bst], level: level.clamp(1, 100), stars: 1, ev: 0, age: 0))
    end

    # The registry, built on first use from who holds what (initLegends).
    def registry(world)
      world.legends ||= begin
        reg = lines(world.species).to_h { |l| [l, { owner: nil, since: nil, last: nil }] }
        world.clubs.each_value do |c|
          c.squad.each do |m|
            next unless Scout.legend?(world.species, m.species)
            nerf(m)
            l = reg[line_of(world.species, m.species)] or next
            next if l[:owner]
            l[:owner] = c.id
            l[:since] = world.calendar.year
          end
        end
        reg
      end
    end

    # freeLegLines
    def free_lines(world, club)
      registry(world).select { |_, l| l[:owner].nil? && l[:last] != club.id }.keys
    end

    def pick_line(world, club, region, rng)
      pool = free_lines(world, club)
      return nil if pool.empty?
      Scout.weighted(pool, rng) { |l| world.species[l][:region] == region ? HOME_WEIGHT : 1 }
    end

    # legendCand: priced from its final BST, at least ₽150,000.
    def candidate(world, club, region, rng)
      line = pick_line(world, club, region, rng) or return nil
      level = [40, world.avg_level(club.region).round].max
      fb = world.species[line][:fb]
      { mon: make(world.species, line, level), cost: [150_000, ((150_000 + (fb - 580) * 2500) / 10_000.0).round * 10_000].max,
        legend: true }
    end

    def acquire(world, club, mon)
      l = registry(world)[line_of(world.species, mon.species)] or return
      l[:owner] = club.id
      l[:since] = world.calendar.year
      { kind: :legend_joined, club: club.id, species: mon.species, date: world.calendar.date }
    end

    # Signing it: free line, and no other legend at the club (signBlock).
    def block?(world, club, species)
      return false unless Scout.legend?(world.species, species)
      l = registry(world)[line_of(world.species, species)]
      held(club, world.species) || l.nil? || l[:owner]
    end

    # legendSeasonEnd: after LEG_YEARS seasons it leaves.
    def season_end(world)
      year = world.calendar.year
      registry(world).filter_map do |line, l|
        next unless l[:owner]
        c = world.clubs[l[:owner]]
        m = c && c.squad.find { |x| line_of(world.species, x.species) == line }
        unless m
          l[:owner] = nil
          next
        end
        next if year - l[:since] + 1 < LEG_YEARS
        c.squad.delete(m)
        c.refresh_rating
        l[:last] = c.id
        l[:owner] = l[:since] = nil
        { kind: :legend_left, club: c.id, species: m.species, date: world.calendar.date }
      end
    end

    # aiLegendClaim (the new year after a PWT title). A full squad lets its
    # weakest go (not a canon mon or a legend).
    def ai_claim(world, rng)
      right = world.leg_right
      return nil unless right && !right[:used]
      club = world.clubs[right[:club]]
      return nil if club.nil? || !world.ai?(club)
      right[:used] = true
      return nil if held(club, world.species)
      line = pick_line(world, club, club.region, rng) or return nil
      lv = club.lineup.empty? ? 30 : (club.lineup.sum(&:level) / club.lineup.size.to_f).round
      mon = make(world.species, line, lv)
      club.squad << mon
      while club.squad.size > Build.squad_size(club.clubhouse)
        out = club.squad.reject { |x| x.canon || Scout.legend?(world.species, x.species) }
                    .min_by { |x| Scout.mon_value(x, world.species) }
        break unless out
        club.squad.delete(out)
      end
      club.refresh_rating
      acquire(world, club, mon)
    end
  end
end
