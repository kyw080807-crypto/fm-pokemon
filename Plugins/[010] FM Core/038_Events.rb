#===============================================================================
# FM::Events — the player's choice events (Poké Manager: EVENTS, rollEvent,
# resolveEvent, fanCash, eventCash, slumpMon; the press conference and the
# fan-satisfaction add-ons from 팬 만족도). Pure Ruby; texts are the UI's.
# - Monday, weeks 2-50, at least 3 weeks after the last one: 18% for one
#   of tv, fans, rumor (signings left), event, camp (₽30,000+ in hand),
#   slump, interview (during the league). If none came, a press conference
#   with chance 30% from week 3 when the club played an official match
#   last week (its options follow a win or a loss).
# - An event left unanswered takes its last option the next Monday.
# - Options (entry = the six it would field; condition never below 20):
#   tv: fame +3, entry condition -8, fans +2 | nothing.
#   fans: merchandise ₽(3,000 + 250 famE) to ₽1,000, entry -5, fans +5 |
#     fans -1.
#   rumor: ₽3,000, two candidates now from that region (scout bonus +3) |
#     nothing.
#   event: ₽(6,000 + 350 famE), entry -6 | nothing.
#   camp: ₽20,000, entry EVs +8 (to the cap), condition -10 | nothing.
#   slump (the first entry mon under condition 70, else the first): rest,
#     condition +25 | push: half EVs +10, half condition -15.
#   interview: fame +3, fans +2, the next league loss fame -4 | fame +1,
#     fans +1.
#   press after a win: fans +4 | fans +2, fame +1 | fame +2, fans +3, the
#     next official loss fans -5. After a loss: fans +3, fame -1 | fans +2
#     | fans -4 | fans -2.
# The rival's taunt is left out (no rivals yet).
#===============================================================================
module FM
  module Events
    CHANCE = 0.18
    PRESS_CHANCE = 0.3
    GAP_WEEKS = 3
    WEEKS = (2..50).freeze
    COND_MIN = 20
    CAMP_FEE = 20_000
    CAMP_NEED = 30_000
    KEYS = %i[tv fans rumor event camp slump interview].freeze
    OPTIONS = { tv: 2, fans: 2, rumor: 2, event: 2, camp: 2, slump: 2, interview: 2, press_win: 3, press_loss: 4 }.freeze

    module_function

    def week_no(world) = (world.calendar.day_of_year - 1) / 7 + 1

    def fan_cash(club) = ((3000 + Economy.fame_eff(club.fame) * 250) / 1000.0).round * 1000
    def event_cash(club) = ((6000 + Economy.fame_eff(club.fame) * 350) / 1000.0).round * 1000

    def slump_mon(club)
      party = club.entry
      party.find { |m| m.cond < 70 } || party.first
    end

    def league_on?(world, club)
      lg = world.leagues[club.region]
      lg && lg.next_round.positive? && !lg.done?
    end

    def possible(world, club)
      year = world.calendar.year
      KEYS.select do |k|
        case k
        when :rumor then Recruit.signs_left(club, year).positive?
        when :camp then club.wallet.balance > CAMP_NEED
        when :slump then !club.entry.empty?
        when :interview then league_on?(world, club)
        else true
        end
      end
    end

    # rollEvent (+ the press conference) -> the new event or nil
    def roll(world, club, rng)
      ev = nil
      w = week_no(world)
      year = world.calendar.year
      last = world.ev_last
      recent = last && last[0] == year && w - last[1] < GAP_WEEKS
      if WEEKS.cover?(w) && !recent && rng.rand <= CHANCE
        keys = possible(world, club)
        k = keys[rng.rand(keys.size)] unless keys.empty?
        if k
          ev = { key: k, year: year, week: w }
          ev[:region] = world.regions[rng.rand(world.regions.size)] if k == :rumor
          ev[:mon] = slump_mon(club) if k == :slump
        end
      end
      lo = world.last_official
      if ev.nil? && w >= 3 && lo && world.calendar.days_until(lo[:date]) > -8 && world.press_week != [year, w] &&
         rng.rand < PRESS_CHANCE
        world.press_week = [year, w]
        ev = { key: lo[:my].negative? ? :press_loss : :press_win, year: year, week: w }
      end
      return unless ev
      world.ev_last = [year, w] unless ev[:key].to_s.start_with?("press")
      world.event = ev
    end

    def tire(club, d) = club.entry.each { |m| m.cond = [COND_MIN, m.cond - d].max }

    def add_ev(m, n)
      m.ev = [m.ev + n, Growth::EV_MAX].min if m.ev < Growth::EV_MAX && !m.resting
    end

    # resolveEvent -> { kind: :event_done, key:, choice:, ... }
    def resolve(world, club, i, rng: Random.new)
      ev = world.event or return
      world.event = nil
      i = i.clamp(0, OPTIONS.fetch(ev[:key]) - 1)
      date = world.calendar.date
      fame = ->(d) { club.fame = Economy.add_fame(club.fame, d) }
      fans = ->(d, why) { Fans.add(club, d, why, date: date) }
      out = { kind: :event_done, club: club.id, key: ev[:key], choice: i, date: date }
      case [ev[:key], i]
      when [:tv, 0]
        fame.(3)
        tire(club, 8)
        fans.(2, :tv)
      when [:fans, 0]
        cash = fan_cash(club)
        club.wallet.record(cash, category: :merch, date: date)
        tire(club, 5)
        fans.(5, :signing)
        out[:cash] = cash
      when [:fans, 1] then fans.(-1, :no_signing)
      when [:rumor, 0]
        if club.wallet.balance >= Scouting::FEE
          club.wallet.record(-Scouting::FEE, category: :scout, date: date)
          got = Scouting.generate(world, club, 2, region: ev[:region], keep: Scouting::KEEP_WEEKS, date: date, rng: rng,
                                                  extra_bonus: 3)
          out[:species] = got.map { |c| c[:mon].species }
        end
      when [:event, 0]
        cash = event_cash(club)
        club.wallet.record(cash, category: :spon, date: date)
        tire(club, 6)
        out[:cash] = cash
      when [:camp, 0]
        club.wallet.record(-CAMP_FEE, category: :fac, date: date)
        club.entry.each do |m|
          add_ev(m, 8)
          m.cond = [COND_MIN, m.cond - 10].max
        end
      when [:slump, 0]
        if (m = ev[:mon]) && club.squad.any? { |x| x.equal?(m) }
          m.cond = [100, m.cond + 25].min
          m.resting = true
        end
      when [:slump, 1]
        if (m = ev[:mon]) && club.squad.any? { |x| x.equal?(m) }
          if rng.rand < 0.5
            add_ev(m, 10)
            out[:pushed] = :better
          else
            m.cond = [COND_MIN, m.cond - 15].max
            out[:pushed] = :worse
          end
        end
      when [:interview, 0]
        fame.(3)
        fans.(2, :interview)
        world.boast = world.calendar.year
      when [:interview, 1]
        fame.(1)
        fans.(1, :interview)
      when [:press_win, 0] then fans.(4, :press)
      when [:press_win, 1]
        fans.(2, :press)
        fame.(1)
      when [:press_win, 2]
        fame.(2)
        fans.(3, :press)
        world.fs_boast = true
      when [:press_loss, 0]
        fans.(3, :press_sorry)
        fame.(-1)
      when [:press_loss, 1] then fans.(2, :press)
      when [:press_loss, 2] then fans.(-4, :press_excuse)
      when [:press_loss, 3] then fans.(-2, :press_skip)
      end
      club.refresh_rating
      out
    end

    # Monday, the player's club: an unanswered event takes its last option,
    # then maybe a new one. -> events
    def week(world, club, rng)
      out = []
      if world.event
        (r = resolve(world, club, OPTIONS.fetch(world.event[:key]) - 1, rng: rng)) && out << r.merge(auto: true)
      end
      e = roll(world, club, rng)
      out << { kind: :event, club: club.id, key: e[:key], date: world.calendar.date } if e
      out
    end

    # After an official result of the player's (World#fan_result): the press
    # conference's and the interview's boasts.
    def result(world, club, my, league:)
      world.last_official = { date: world.calendar.date, my: my }
      if world.fs_boast
        Fans.add(club, -5, :boast_loss, date: world.calendar.date) if my.negative?
        world.fs_boast = nil
      end
      return unless league && world.boast
      club.fame = Economy.add_fame(club.fame, -4) if my.negative? && world.boast == world.calendar.year
      world.boast = nil
    end
  end
end
