#===============================================================================
# FM::MatchSim — formula result for matches nobody watches (design: "다른
# 클럽끼리의 경기는 계산식으로 처리"). Pure Ruby. Format follows Poké Manager:
# each side brings 3 of its 6 (all Lv50); a win means knocking out all 3.
#
# Strength is a team rating on the scale of its picked mons' base stat totals
# (~300-700). All constants are first guesses, to be calibrated against real
# battle results by headless runs (roadmap stage 1).
#===============================================================================
module FM
  module MatchSim
    SCALE     = 55.0    # rating gap that moves win odds by a factor of e
    HOME_EDGE = 8.0     # home advantage in rating points
    DRAW_RATE = 0.03    # both sides left standing at the turn cap

    module_function

    def win_probability(home, away, neutral: false)
      1.0 / (1.0 + Math.exp(-(home - away + (neutral ? 0 : HOME_EDGE)) / SCALE))
    end

    # -> { res: 1 home win / -1 away win / 0 draw, ko_a:, ko_b: }
    # neutral: tournament games at a third venue, no home edge.
    def play(home, away, rng: Random.new, neutral: false)
      p = win_probability(home, away, neutral: neutral)
      if rng.rand < DRAW_RATE
        ko = Array.new(2) { rng.rand(3) }
        return { res: 0, ko_a: ko[0], ko_b: ko[1] }
      end
      home_wins = rng.rand < p
      # Closer matches leave the loser with more knockouts (0-2).
      closeness = 1.0 - (p - 0.5).abs * 2
      loser_ko = Array.new(2).count { rng.rand < 0.2 + 0.45 * closeness }
      home_wins ? { res: 1, ko_a: 3, ko_b: loser_ko } : { res: -1, ko_a: loser_ko, ko_b: 3 }
    end
  end
end
