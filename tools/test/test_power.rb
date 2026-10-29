require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager 글로벌 파워랭킹 (pwtPts / subPts / lgPts / powerScore / powerRanking).
class TestPower < Minitest::Test
  P = FM::Power

  def test_score_weighs_the_last_three_seasons
    w = TestPlayer.new("x").world
    c = w.clubs["P"]
    c.history[1] = { pos: 1, pwt: :champion }                 # 40 + 100
    c.history[2] = { pos: 3, cup: [:pet, :final] }           # 36 + 10
    c.history[3] = { pos: 10, pwt: :swiss, pwt_wins: 2 }      # 22 + 10
    c.history[4] = { pos: 20 }                                # 2
    assert_in_delta 2 * 1.0 + 32 * 0.6 + 46 * 0.3, P.score(c), 0.05
    assert_equal 0, P.league_points(nil)
    assert_equal 0, P.sub_points([:pet, :champion]), "the champion counts its PWT"
  end

  def test_ranking_orders_everyone
    w = TestPlayer.new("x").world
    w.clubs["A"].history[1] = { pos: 1 }
    r = P.ranking(w)
    assert_equal w.clubs.size, r.size
    assert_equal "A", r.first[:club]
    assert_equal (1..w.clubs.size).to_a, r.map { |x| x[:rank] }
    assert_equal w.regions.size, P.coefficients(w).size
  end
end
