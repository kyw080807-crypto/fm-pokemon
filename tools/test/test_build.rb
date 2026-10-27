require_relative "test_helper"

class TestBuildRules < Minitest::Test
  B = FM::Build

  def test_clubhouse_table_from_design
    assert_equal [3, 4, 4, 5, 6], (1..5).map { |l| B.club_plots(l) }
    assert_equal [2, 3, 4, 5, 5], (1..5).map { |l| B.building_cap(l) }
    assert_equal [8, 9, 10, 11, 12], (1..5).map { |l| B.squad_size(l) }
    assert_equal [0, 30, 45, 60, 75], (1..5).map { |l| B.clubhouse_fame(l) }
  end

  def test_clubhouse_limited_by_city_size
    assert_equal [2, 3, 4, 5, 5], (1..5).map { |s| B.clubhouse_max(s) }
  end

  def test_building_cost_spans_two_original_levels
    # design 1 -> 2 = original 2 -> 4 = upCost(2) + upCost(3)
    up = ->(lv) { (8000 * lv**1.8 / 1000.0).round * 1000 }
    assert_equal up.(2) + up.(3), B.building_cost(1)
    assert_equal up.(8) + up.(9), B.building_cost(4)
    assert_equal up.(0) + up.(1), B.building_cost(0)   # building from scratch = original 0 -> 2
  end

  def test_build_weeks_grow_with_level
    assert B.build_weeks(:building, 4) > B.build_weeks(:building, 1)
    assert B.build_weeks(:clubhouse, 1) >= B.build_weeks(:building, 1)
  end

  def test_stadium_costs_from_poke_manager
    assert_equal 400_000, B.stadium_cost(0)    # rental -> Lv1
    assert_equal 1_500_000, B.stadium_cost(3)  # Lv3 -> Lv4
  end
end
