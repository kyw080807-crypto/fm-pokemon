#===============================================================================
# FM::Tour — 원정 친선 투어 (Poké Manager tourPay / canTour / goTour /
# aiTourP / tourWeek). Pure Ruby. In a week with no official match the
# entry can tour other regions for appearance fees: 6,000 + effective fame
# x 110 + (team OVR - 100) x 100, rounded to ₽100. The entry loses 10
# condition and that week neither trains nor rests (only half the level
# progress, from playing; Growth.condition_week / Growth.week).
# The AI tours the more often the shorter it is of money (in debt 90%,
# under 20 weeks' costs 60%, under 40 weeks 25%, else 5%), but not with a
# tired entry (any under 55) while it isn't in debt. The player asks for
# it a week at a time, or always (World#tour_next / #tour_auto).
#===============================================================================
module FM
  module Tour
    COND = 10
    TIRED = 55

    module_function

    # tOvr: the mean overall of the three who play.
    def team_ovr(club)
      ms = club.lineup
      ms.empty? ? 0 : (ms.sum { |m| Economy.ovr(m.rating) } / ms.size.to_f).round
    end

    def pay(club)
      ((6000 + Economy.fame_eff(club.fame) * 110 + [0, team_ovr(club) - 100].max * 100) / 100.0).round * 100
    end

    def ai_chance(club)
      f = club.wallet.balance
      wc = [club.weekly_cost, 1].max
      f.negative? ? 0.9 : f < wc * 20 ? 0.6 : f < wc * 40 ? 0.25 : 0.05
    end

    # goTour -> the fee.
    def go(club, date:)
      fee = pay(club)
      club.wallet.record(fee, category: :tour, date: date)
      club.entry.each do |m|
        m.cond = [m.cond - COND, Growth::COND_MIN].max
        m.tour = true
      end
      club.refresh_rating
      fee
    end
  end
end
