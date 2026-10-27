require_relative "test_helper"

class TestMatchSim < Minitest::Test
  def sample(a, b, n = 4000, seed: 7)
    rng = Random.new(seed)
    Array.new(n) { FM::MatchSim.play(a, b, rng: rng) }
  end

  def test_result_shape
    sample(500, 500, 300).each do |r|
      assert_includes [-1, 0, 1], r[:res]
      assert r[:ko_a].between?(0, 3)
      assert r[:ko_b].between?(0, 3)
      assert_equal 3, r[:ko_a] if r[:res] == 1   # winner knocks out all 3
      assert_equal 3, r[:ko_b] if r[:res] == -1
      assert r[:ko_a] < 3 && r[:ko_b] < 3 if r[:res].zero?
    end
  end

  def test_equal_teams_are_balanced_with_home_edge
    rs = sample(500, 500)
    wins = rs.count { |r| r[:res] == 1 }.fdiv(rs.size)
    losses = rs.count { |r| r[:res] == -1 }.fdiv(rs.size)
    assert_in_delta 0.5, wins, 0.08
    assert wins > losses, "home side should have a small edge"
  end

  def test_stronger_team_wins_more_but_not_always
    rs = sample(560, 480)
    wins = rs.count { |r| r[:res] == 1 }.fdiv(rs.size)
    assert wins > 0.7
    assert wins < 0.98, "upsets must still happen"
  end

  def test_draws_are_rare
    rs = sample(500, 500)
    assert rs.count { |r| r[:res].zero? }.fdiv(rs.size) < 0.08
  end

  def test_deterministic_with_seeded_rng
    assert_equal sample(520, 500, 50, seed: 3), sample(520, 500, 50, seed: 3)
  end
end
