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
          { species: m.species, level: m.level, stars: m.stars, age: m.age, rating: m.rating.round,
            cond: m.cond, resting: m.resting ? true : false,
            injury: m.hurt? ? { kind: m.injd && m.injd[:k], sev: m.injd && m.injd[:sev], weeks: m.inj } : nil,
            rehab: m.rehab, debuffs: m.debuffs }
        end,
        last_year: c.history[world.calendar.year - 1],
        signs: { used: c.signs_used(world.calendar.year), limit: Recruit.sign_limit(c, world.calendar.year) } }
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

    # A city and the clubs in it; relation is toward `viewer` (a club id).
    def city(world, id, viewer: nil)
      c = world.cities.fetch(id)
      { id: id, name: c.name, region: c.region, form: c.form, size: c.size, free_plots: c.free_plots,
        budget: c.budget.balance, tax_rate: c.tax_rate, satisfaction: c.satisfaction.round,
        transport: c.transport, hotel: c.hotel, buildings: c.buildings.map(&:dup), project: c.project,
        clubs: c.club_ids.map do |cid|
          club = world.clubs[cid]
          { id: cid, name: club.name, fame: club.fame.round, relation: viewer && cid != viewer ? world.relations.get(viewer, cid).round(2) : nil }
        end,
        log: c.log.map { |e| e.slice(:agenda, :target, :date, :cost, :passed).merge(yes: e[:votes].count { |_, v| v[:yes] }, members: e[:votes].size) },
        promises: world.promises.select { |pr| pr[:by] == viewer && pr[:city] == id }.map { |pr| { to: world.clubs[pr[:to]].name, made: pr[:made] } } }
    end

    def committee(world, region)
      cm = world.committees[region] or return nil
      cap = world.cities[cm.city_id]
      { region: region, city: cap.name, budget: cap.budget.balance, facilities: cm.facilities.dup,
        project: cm.project && cm.project.slice(:target, :to, :done),
        members: cm.members(world).uniq.map { |id| { id: id, name: world.clubs[id].name, gym_rep: cm.gym_reps.include?(id) } },
        log: cm.log.map { |e| e.slice(:target, :date, :cost, :passed).merge(yes: e[:votes].values.count(true), members: e[:votes].size) } }
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
