#===============================================================================
# FM::Cups — runs the season's PET, PENT and PWT inside FM::World. Pure Ruby.
# Set up once every league has finished; each round is played on its date
# from FM::Season.tournament_dates. Games are at neutral venues.
#===============================================================================
module FM
  module Cups
    KO_STAGE_RESULT = %i[r16 qf sf final].freeze

    module_function

    def setup(world, rng:)
      year = world.calendar.year
      coef = world.league_coefficients
      slots = Tournament.pwt_slots(coef)
      final = world.leagues.transform_values(&:standings)
      pwt = final.flat_map { |region, order| order.first(slots.fetch(region, 3)) }
      events = []
      pwt.each { |id| enter(world, id, Tournament::PWT_FEE, 2) }

      subs = { pet: Tournament::PET_REGIONS, pent: Tournament::PENT_REGIONS }.to_h do |cup, regions|
        entries = regions.flat_map do |r|
          (final[r] || []).reject { |id| pwt.include?(id) }.first(4).map { |id| [id, final[r].index(id) + 1, -coef.fetch(r, 0)] }
        end
        players = entries.sort_by { |id, pos, c| [pos, c, id] }.first(16).map(&:first)
        players.each { |id| enter(world, id, Tournament::SUB_FEE, 1) }
        ko = players.size == 16 ? Tournament::Knockout.new(players) : nil
        [cup, { players: players, ko: ko, host: Tournament.host(cup, year) }]
      end
      world.set_cups(subs.merge(pwt: { players: pwt, swiss: nil, ko: nil, host: Tournament.host(:pwt, year) },
                                dates: Season.tournament_dates(world.calendar, year)))
      events << { kind: :cups_drawn, year: year, pwt: pwt.size, pet: subs[:pet][:players].size,
                  pent: subs[:pent][:players].size, date: world.calendar.date }
    end

    def enter(world, id, fee, fame)
      c = world.clubs[id]
      c.wallet.record(-fee, category: :travel, date: world.calendar.date)
      c.fame = Economy.add_fame(c.fame, fame)
    end

    def play_day(world, rng:)
      cups = world.cups
      d = world.calendar.date
      dates = cups[:dates]
      events = []
      if (i = dates[:pet].index(d))
        %i[pet pent].each { |cup| events.concat(sub_round(world, cup, i, rng)) }
      end
      if (i = dates[:pwt_swiss].index(d))
        events.concat(swiss_round(world, i, rng))
      end
      if (i = dates[:pwt_knockout].index(d))
        events.concat(pwt_ko_round(world, i, rng))
      end
      events
    end

    def game(world, rng)
      lambda do |a, b|
        r = MatchSim.play(world.clubs[a].rating, world.clubs[b].rating, rng: rng, neutral: true)
        world.clubs[a].drain_lineup(Growth::MATCH_COND)
        world.clubs[b].drain_lineup(Growth::MATCH_COND)
        r
      end
    end

    def sub_round(world, cup, i, rng)
      c = world.cups[cup]
      ko = c[:ko] or return []
      res = ko.play_round(best_of: i == 3 ? 3 : 1, rng: rng, &game(world, rng))
      date = world.calendar.date
      res.each do |_, _, _, loser, _|
        world.clubs[loser].wallet.record(Tournament::SUB_PRIZE[i], category: :prize, date: date)
        hist(world, loser)[:cup] = [cup, KO_STAGE_RESULT[i]]
      end
      events = [{ kind: :cup_round, cup: cup, round: KO_STAGE_RESULT[i], date: date }]
      if ko.done?
        champ = world.clubs[ko.champion]
        champ.wallet.record(Tournament::SUB_CHAMPION_PRIZE, category: :prize, date: date)
        hist(world, ko.champion)[:cup] = [cup, :champion]
        pwt = world.cups[:pwt][:players]
        unless pwt.include?(ko.champion)
          pwt << ko.champion
          enter(world, ko.champion, Tournament::PWT_FEE, 2)
        end
        events << { kind: :cup_champion, cup: cup, club: ko.champion, date: date }
      end
      events
    end

    def swiss_round(world, i, rng)
      pwt = world.cups[:pwt]
      return [] if pwt[:players].size < 16   # small test worlds: no PWT
      pwt[:swiss] ||= Tournament::Swiss.new(pwt[:players], rng: rng)
      sw = pwt[:swiss]
      return [] if sw.done?
      sw.play_round(&game(world, rng))
      events = [{ kind: :cup_round, cup: :pwt, round: :"swiss#{i + 1}", date: world.calendar.date }]
      if sw.done?
        q = sw.qualifiers(16)
        (sw.players - q).each do |id|
          hist(world, id).merge!(pwt: :swiss, pwt_wins: sw.wins[id])
          next if sw.losses[id] >= Tournament::SWISS_GOAL
          world.clubs[id].wallet.record(Tournament::SWISS_PRIZE, category: :prize, date: world.calendar.date)
        end
        pwt[:ko] = Tournament::Knockout.new(q)
      end
      events
    end

    def pwt_ko_round(world, i, rng)
      pwt = world.cups[:pwt]
      ko = pwt[:ko] or return []
      date = world.calendar.date
      res = ko.play_round(best_of: 3, rng: rng, &game(world, rng))
      res.each do |_, _, _, loser, _|
        c = world.clubs[loser]
        c.wallet.record(Tournament::KO_PRIZE[i], category: :prize, date: date)
        c.fame = Economy.add_fame(c.fame, i == 3 ? 5 : 3) if i >= 2
        hist(world, loser)[:pwt] = KO_STAGE_RESULT[i]
      end
      events = [{ kind: :cup_round, cup: :pwt, round: KO_STAGE_RESULT[i], date: date }]
      if ko.done?
        champ = world.clubs[ko.champion]
        champ.wallet.record(Tournament::CHAMPION_PRIZE, category: :prize, date: date)
        champ.fame = Economy.add_fame(champ.fame, 10)
        hist(world, ko.champion)[:pwt] = :champion
        events << { kind: :cup_champion, cup: :pwt, club: ko.champion, date: date }
      end
      events
    end

    def hist(world, id)
      world.clubs[id].history[world.calendar.year] ||= {}
    end
  end
end
