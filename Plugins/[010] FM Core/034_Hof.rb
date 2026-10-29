#===============================================================================
# FM::Hof — 명예의 전당 and season awards (Poké Manager: addHof, seasonAwards,
# hofAdd, hofWorthy, viewRecords). Pure Ruby.
# - The world's records: every league champion (points, W-D-L), every
#   region's KO king, PWT champions and runners-up, PET/PENT champions;
#   the most points in each league and the most KOs in a season.
# - A club's own hall (30 at most, newest first): mons that retire worthy
#   (400 career KOs, a PWT title, 3 titles, 2 awards, or an award and 250
#   KOs) and the legends that leave it.
# - News (seasonAwards): the champion (a streak from 2 in a row, a new
#   points record), the KO king (the player's region), and in the player's
#   region a gym leader in the top 4 for the first time and the season's
#   riser (8+ places up).
# - Design 09 (명예의 전당, a capital facility): records the region's
#   retired mons (the clubs' halls), and draft effects: a club whose mon is
#   inducted gains fame 0.2 x the hall's level; the capital's budget earns
#   tourism ₽100 x level a week.
#===============================================================================
module FM
  module Hof
    CLUB_MAX = 30
    FAME_PER_LEVEL = 0.2
    TOURISM_PER_LEVEL = 100
    RISER = 8

    module_function

    def of(world) = world.hof ||= { league: [], ko: [], world: [], cups: [], records: {} }

    # hofWorthy (titles / awards are [year, kind] here)
    def worthy?(m)
      m.ko >= 400 || m.titles.any? { |_, k| k == :pwt } || m.titles.size >= 3 || m.awards.size >= 2 ||
        (m.awards.size >= 1 && m.ko >= 250)
    end

    # hofAdd -> the entry; fame from the region's hall (design 09).
    def induct(world, club, m, kind)
      year = world.calendar.year
      e = { species: m.species, y0: year - m.age.to_i, y1: year, ko: m.ko, gp: m.gp, titles: m.titles.dup,
            awards: m.awards.dup, stars: m.stars, kind: kind }
      (club.hof ||= []).unshift(e)
      club.hof.pop while club.hof.size > CLUB_MAX
      lv = world.committees[club.region]&.facilities&.fetch(:HALL_OF_FAME, 0).to_i
      club.fame = Economy.add_fame(club.fame, FAME_PER_LEVEL * lv) if lv.positive?
      e
    end

    # On retiring (retireMon) -> the induction event or nil
    def retired(world, club, m)
      return unless worthy?(m)
      induct(world, club, m, :retired)
      { kind: :hof_inducted, club: club.id, species: m.species, ko: m.ko, date: world.calendar.date }
    end

    # seasonAwards -> events
    def season_awards(world, region, league, standings)
      h = of(world)
      year = world.calendar.year
      date = world.calendar.date
      champ = standings.first
      t = league.table[champ]
      h[:league].unshift({ year: year, region: region, club: champ, pts: t[:pts], w: t[:w], d: t[:d], l: t[:l] })
      key = :"pts_#{region}"
      rec = h[:records]
      new_rec = rec[key].nil? || t[:pts] > rec[key][:pts]
      first_season = rec[key].nil?
      rec[key] = { pts: t[:pts], year: year, club: champ } if new_rec
      streak = 0
      h[:league].select { |x| x[:region] == region }.each { |x| x[:club] == champ ? streak += 1 : break }
      events = [{ kind: :league_champion, region: region, club: champ, w: t[:w], l: t[:l], pts: t[:pts], streak: streak,
                  record: new_rec && !first_season, date: date }]
      best = nil
      standings.each do |id|
        world.clubs[id].squad.each { |m| best = [m, id] if m.sko.positive? && (best.nil? || m.sko > best[0].sko) }
      end
      if best
        m, id = best
        h[:ko].unshift({ year: year, region: region, species: m.species, club: id, ko: m.sko })
        rec[:ko] = { ko: m.sko, year: year, species: m.species, club: id, region: region } if rec[:ko].nil? || m.sko > rec[:ko][:ko]
        events << { kind: :ko_king, region: region, club: id, species: m.species, ko: m.sko, gp: m.sgp, date: date }
      end
      pc = world.player_club && world.clubs[world.player_club]
      return events unless pc && pc.region == region
      standings.first(4).each_with_index do |id, i|
        c = world.clubs[id]
        next unless c.role.start_with?("G")
        before = c.history.reject { |y, _| y == year }.values
        next if before.any? { |x| x[:pos] && x[:pos] <= 4 }
        events << { kind: :first_top4, club: id, pos: i + 1, date: date }
      end
      mover = nil
      standings.each_with_index do |id, i|
        prev = world.clubs[id].history.dig(year - 1, :pos) or next
        d = prev - (i + 1)
        mover = { club: id, d: d, from: prev, to: i + 1 } if d >= RISER && (mover.nil? || d > mover[:d])
      end
      events << mover.merge(kind: :riser, date: date) if mover
      events
    end

    def pwt_champion(world, champ, runner_up)
      h = of(world)
      year = world.calendar.year
      h[:world].unshift({ year: year, club: champ, region: world.clubs[champ].region, runner_up: runner_up })
      titles = h[:world].count { |x| x[:club] == champ }
      { kind: :pwt_hof, club: champ, runner_up: runner_up, titles: titles, date: world.calendar.date }
    end

    def cup_champion(world, cup, club)
      of(world)[:cups].unshift({ year: world.calendar.year, cup: cup, club: club, region: world.clubs[club].region })
    end

    # The capital's tourism from its hall (design 09, draft).
    def tourism(cm) = TOURISM_PER_LEVEL * cm.facilities.fetch(:HALL_OF_FAME, 0).to_i
  end
end
