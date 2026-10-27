#===============================================================================
# FM::View — read-only data for screens. Pure Ruby. Returns plain hashes and
# symbols; the UI plugin turns them into text with _INTL (Core has no
# user-facing strings).
#===============================================================================
module FM
  module View
    module_function

    def standings(world, region)
      league = world.leagues.fetch(region)
      league.standings.each_with_index.map do |id, i|
        t = league.table[id]
        c = world.clubs[id]
        { pos: i + 1, id: id, name: c.name, p: t[:p], w: t[:w], d: t[:d], l: t[:l],
          kf: t[:kf], ka: t[:ka], pts: t[:pts], rating: c.rating.round }
      end
    end

    def club(world, id)
      c = world.clubs.fetch(id)
      league = world.leagues[c.region]
      { id: id, name: c.name, region: c.region, city: c.city, role: c.role,
        fame: c.fame.round(1), balance: c.wallet.balance, rating: c.rating.round,
        position: league&.position(id), clubhouse: c.clubhouse, stadium: c.stadium,
        facilities: c.facilities.dup, project: c.project, sponsor: c.sponsor && c.sponsor.slice(:name, :kind, :base, :bonus),
        squad: c.squad.sort_by { |m| -m.rating }.map do |m|
          { species: m.species, level: m.level, stars: m.stars, age: m.age, rating: m.rating.round }
        end,
        last_year: c.history[world.calendar.year - 1] }
    end

    # Where we are in the season and what comes next.
    def season(world)
      cal = world.calendar
      year = cal.year
      league = Season.league_dates(cal, year)
      cups = Season.tournament_dates(cal, year)
      upcoming = [[:league, league], [:pet, cups[:pet]], [:pwt_swiss, cups[:pwt_swiss]],
                  [:pwt_knockout, cups[:pwt_knockout]]].flat_map { |k, ds| ds.map { |d| [k, d] } }
      nxt = upcoming.select { |_, d| cal.days_until(d) >= 0 }.min_by { |_, d| cal.ordinal(d) }
      phase = if Season.preseason?(cal.date) then :preseason
              elsif cal.days_until(league.last) >= 0 then :league
              elsif cal.days_until(cups[:pwt_knockout].last) >= 0 then :cups
              else :offseason
              end
      { date: cal.date, weekday: cal.weekday, phase: phase,
        next: nxt && { kind: nxt[0], date: nxt[1], in_days: cal.days_until(nxt[1]) } }
    end

    def cups(world)
      cups = world.cups or return nil
      ko = ->(k) { k && { round: k.round_index, champion: k.champion, bracket: k.bracket.map(&:dup) } }
      { pet: { players: cups[:pet][:players].dup, host: cups[:pet][:host], ko: ko.(cups[:pet][:ko]) },
        pent: { players: cups[:pent][:players].dup, host: cups[:pent][:host], ko: ko.(cups[:pent][:ko]) },
        pwt: { players: cups[:pwt][:players].dup, host: cups[:pwt][:host], ko: ko.(cups[:pwt][:ko]),
               swiss: cups[:pwt][:swiss] && cups[:pwt][:swiss].standings.map do |id|
                 { id: id, wins: cups[:pwt][:swiss].wins[id], losses: cups[:pwt][:swiss].losses[id] }
               end } }
    end
  end
end
