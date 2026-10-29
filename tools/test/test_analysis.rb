require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# The opponent analysis report (Poké Manager anaReport, in part).
class TestAnalysis < Minitest::Test
  A = FM::Analysis
  # Water beats fire, fire beats grass, grass beats water; the rest x1.
  CHART = lambda do |atk, df|
    { %w[WATER FIRE] => 2.0, %w[FIRE GRASS] => 2.0, %w[GRASS WATER] => 2.0,
      %w[FIRE WATER] => 0.5, %w[GRASS FIRE] => 0.5, %w[WATER GRASS] => 0.5 }.fetch([atk, df], 1.0)
  end

  def setup
    @w = TestPlayer.new("x").world
    @p = @w.clubs["P"]
    @a = @w.clubs["A"]
  end

  def mon(sp) = FM::Mon.new(species: sp, bst: 400, level: 30, stars: 3)

  def test_type_edge_and_strength
    pool = { "SQUIRTLE" => { types: %w[WATER] }, "CHARMANDER" => { types: %w[FIRE] } }
    w, f = mon("SQUIRTLE"), mon("CHARMANDER")
    assert_in_delta 1.0, A.edge(pool, w, f, CHART), 1e-9, "x2 against x0.5, same strength"
    assert_in_delta(-1.0, A.edge(pool, f, w, CHART), 1e-9)
    assert_equal 1.0, A.best_mul([], %w[FIRE], CHART)
  end

  def test_next_match_and_report
    nm = A.next_match(@w, @p)
    assert nm
    opp = @w.clubs[nm[:opp]]
    r = A.report(@w, @p, opp, chart: CHART)
    assert_equal opp.lineup, r[:expect]
    assert_equal [@p.entry.size, opp.entry.size], [r[:grid].size, r[:grid].first.size]
    assert_equal [3, @p.entry.size].min, r[:best].size
    assert r[:win].between?(0, 1)
    assert_equal opp.entry.size, r[:threats].size
  end
end
