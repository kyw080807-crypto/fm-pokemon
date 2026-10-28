#===============================================================================
# FM::MatchSim — formula result for matches nobody watches (design: "다른
# 클럽끼리의 경기는 계산식으로 처리"). Pure Ruby. Format follows Poké Manager:
# each side brings 3 of its 6 (all Lv50); a win means knocking out all 3.
#
# Strength is a team rating on the scale of its picked mons' base stat totals
# (~300-700). SCALE and DRAW_RATE are fitted to 1,000 real AI-vs-AI battles
# (smoke check battle_calibration, docs/design/README.md 실전 보정); real
# battles have no home side, so neither does the formula (no home
# advantage anywhere, by design decision 2026-10-28).
#===============================================================================
module FM
  module MatchSim
    SCALE     = 90.0    # rating gap that moves win odds by a factor of e (real battles, below)
    DRAW_RATE = 0.006   # both sides left standing at the turn cap

    module_function

    def win_probability(home, away)
      1.0 / (1.0 + Math.exp(-(home - away) / SCALE))
    end

    # -> { res: 1 home win / -1 away win / 0 draw, ko_a:, ko_b: }
    def play(home, away, rng: Random.new)
      p = win_probability(home, away)
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
