#===============================================================================
# FM::Fans, FM::Goals — 팬 만족도 and 시즌 목표 (Poké Manager: FS_BASE, fsOf,
# fsAdd, fsAtt, fsMerch, fsCap, fsMood, fsResult, fsSetPrice, fsWeek, the
# demand/gate wrappers; goalOvrRank, goalBonus, goalLabel, goalSet,
# goalCheck). Pure Ruby. As in the original, only the player's club has
# fans' satisfaction and a season goal; AI clubs play at x1.
# - Satisfaction 0-100 (60 at start) moves with official results (a win
#   +2, a loss -2, a draw +0.3, each shifted up to about 1.5 by the gap in
#   team OVR: an upset counts more; a best-of-3 series x1.6 for its
#   result alone, a rival game x1.4), with the ticket price (each home game above 1.05x the
#   reference loses (ratio - 1) x 5, at 0.8x or less gains 0.8; raising it
#   loses 6 x the rise / reference at once, cutting gains 2 x), and drifts
#   5% a week toward 55. At 80+ fame +0.15 a week, below 25 -0.2.
# - Effects: home crowd demand x0.6-1.4, merchandise x0.5-1.5, ticket price
#   at most the reference x (0.7 + satisfaction / 100), forced down when
#   over. Fans protest below 20, are ecstatic at 90+ (news once a year).
# - The ticket price changes demand x (reference / price)^1.3 (demand).
# - Season goal (January): the expected place = half last season's place +
#   half the strength rank in the region (all strength if no last season),
#   between 1 and clubs - 2. Bonus round((22 - t)^1.5 x 1,500 + 20,000) to
#   ₽1,000; met: the bonus +10% per place better (at most +50%), fame +3,
#   fans +5; missed: fans -4, fame -1.
# The press conference (기자회견) belongs to the original's events, still
# to come.
#===============================================================================
module FM
  module Fans
    BASE = 55
    START = 60
    DRIFT = 0.05
    LOG_SIZE = 12
    PRICES = [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20].freeze   # the price picker
    PRICE_ELASTICITY = 1.3

    module_function

    def of(club) = club.fsat || START

    # fsAdd -> the new value; `why` lands in the club's log (merged with
    # the same reason in the same week).
    def add(club, d, why = nil, date: nil)
      return of(club) if d.zero?
      club.fsat = (of(club) + d).clamp(0.0, 100.0)
      if why && d.abs >= 0.5
        log = (club.fs_log ||= [])
        last = log.first
        if last && last[:why] == why && last[:date] == date
          last[:d] = (last[:d] + d).round(1)
        else
          log.unshift({ why: why, d: d.round(1), date: date })
          log.pop while log.size > LOG_SIZE
        end
      end
      club.fsat
    end

    def att_mul(club) = 0.6 + 0.8 * of(club) / 100.0
    def merch_mul(club) = 0.5 + of(club) / 100.0
    def cap(club) = [1, (Economy.price(club.fame) * (0.7 + of(club) / 100.0)).round].max
    def mood(v) = v >= 85 ? :ecstatic : v >= 65 ? :happy : v >= 45 ? :normal : v >= 25 ? :unhappy : :angry

    # tOvr: the mean OVR of the three it would field.
    def team_ovr(club)
      ms = club.lineup
      ms.empty? ? 0 : (ms.sum { |m| Economy.ovr(m.rating) } / ms.size.to_f).round
    end

    # fsResult for `club` against `opp`: my = +1 win, -1 loss, 0 draw.
    # rival: a game against the player's rival (x1.4).
    def result(club, opp, my, series: false, date: nil, rival: false)
      g = (team_ovr(opp) - team_ovr(club)) / 10.0
      d = if my.positive? then 2 + g.clamp(-1, 1.5)
          elsif my.negative? then -(2 - g.clamp(-1.5, 1))
          else 0.3 + g.clamp(-1, 1) * 0.5
          end
      why = my.positive? ? :win : my.negative? ? :loss : :draw
      why = :upset_win if my.positive? && g >= 1
      why = :upset_loss if my.negative? && g <= -1
      if series
        d *= 1.6
        why = my.positive? ? :series_win : :series_loss
      end
      if rival
        d *= 1.4
        why = my.positive? ? :rival_win : :rival_loss
      end
      add(club, d, why, date: date)
    end

    # The gate wrapper: a home game at `price` against the reference.
    def home_game(club, price, date: nil)
      ratio = price / [1, Economy.price(club.fame)].max.to_f
      if ratio > 1.05 then add(club, -(ratio - 1) * 5, :dear_tickets, date: date)
      elsif ratio <= 0.8 then add(club, 0.8, :cheap_tickets, date: date)
      end
    end

    # fsSetPrice -> :capped or the new price
    def set_price(club, world, p, date: nil)
      ref = [1, Economy.price(club.fame)].max
      old = world.ticket_price
      return :capped if p > old && p > cap(club)
      world.ticket_price = p
      if p > old then add(club, -(p - old).fdiv(ref) * 6, :price_up, date: date)
      elsif p < old then add(club, (old - p).fdiv(ref) * 2, :price_down, date: date)
      end
      p
    end

    # fsWeek -> events
    def week(club, world, date:)
      v = of(club)
      club.fsat = (v + (BASE - v) * DRIFT).clamp(0.0, 100.0)
      club.fame = Economy.add_fame(club.fame, 0.15) if v >= 80
      club.fame = Economy.add_fame(club.fame, -0.2) if v < 25
      events = []
      c = cap(club)
      if world.ticket_price > c
        events << { kind: :fans_price_cut, club: club.id, from: world.ticket_price, to: c, date: date }
        world.ticket_price = c
      end
      year = date[0]
      if v < 20 && club.fs_riot != year
        club.fs_riot = year
        events << { kind: :fans_riot, club: club.id, date: date }
      end
      if v >= 90 && club.fs_love != year
        club.fs_love = year
        events << { kind: :fans_love, club: club.id, date: date }
      end
      events
    end
  end

  module Goals
    module_function

    def strength_rank(world, club)
      world.clubs.values.select { |c| c.region == club.region }.sort_by { |c| [-c.rating, c.id.to_s] }.index(club) + 1
    end

    def bonus(t) = (((22 - t)**1.5 * 1500 + 20_000) / 1000.0).round * 1000

    # goalLabel -> [:kind, t] (the UI words it)
    def label(world, t, region)
      slots = Tournament.pwt_slots(world.league_coefficients).fetch(region, 3)
      kind = if t == 1 then :title
             elsif t <= slots then :pwt
             elsif t <= 4 then :top
             elsif t <= 10 then :upper_half
             elsif t <= 15 then :mid
             else :place
             end
      [kind, t]
    end

    # goalSet -> the event
    def set(world, club)
      year = world.calendar.year
      prev = club.history.dig(year - 1, :pos)
      ovr = strength_rank(world, club)
      n = world.clubs.values.count { |c| c.region == club.region }
      exp = prev ? prev * 0.5 + ovr * 0.5 : ovr
      t = exp.round.clamp(1, [1, n - 2].max)
      club.goal = { year: year, region: club.region, t: t, prev: prev, ovr: ovr, bonus: bonus(t), done: false }
      { kind: :goal_set, club: club.id, goal: club.goal.dup, label: label(world, t, club.region), date: world.calendar.date }
    end

    # goalCheck, when the club's league ends -> the event or nil
    def check(world, club, pos)
      g = club.goal
      return unless g && !g[:done] && g[:year] == world.calendar.year
      g[:done] = true
      g[:pos] = pos
      date = world.calendar.date
      if pos <= g[:t]
        extra = [5, g[:t] - pos].min
        amt = (g[:bonus] * (1 + extra * 0.1) / 1000.0).round * 1000
        g[:ok] = true
        g[:paid] = amt
        club.wallet.record(amt, category: :goal, date: date)
        club.fame = Economy.add_fame(club.fame, 3)
        Fans.add(club, 5, :goal_met, date: date)
      else
        g[:ok] = false
        Fans.add(club, -4, :goal_missed, date: date)
        club.fame = Economy.add_fame(club.fame, -1)
      end
      { kind: :goal_result, club: club.id, goal: g.dup, date: date }
    end
  end
end
