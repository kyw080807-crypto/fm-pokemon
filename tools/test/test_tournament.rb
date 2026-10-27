require_relative "test_helper"

class TestTournament < Minitest::Test
  T = FM::Tournament

  # Lower id = stronger; the stronger side always wins.
  def strong_wins = ->(a, b) { a < b ? { res: 1, ko_a: 3, ko_b: 1 } : { res: -1, ko_a: 1, ko_b: 3 } }

  def test_seeded_bracket_meets_top_seeds_last
    ko = T::Knockout.new((1..16).to_a)
    assert_equal [1, 16], ko.bracket.first.first(2)
    4.times { |i| ko.play_round(best_of: 1, &strong_wins) }
    assert_equal 1, ko.champion
    assert_equal [1, 2], ko.finalists.sort
    assert_equal 4, ko.results.size
  end

  def test_best_of_three_series
    calls = 0
    flip = ->(a, b) { calls += 1; calls.odd? ? { res: 1, ko_a: 3, ko_b: 2 } : { res: -1, ko_a: 2, ko_b: 3 } }
    r = T.series(1, 2, best_of: 3, &flip)
    assert_equal 3, calls
    assert_includes [1, -1], r[:res]
  end

  def test_swiss_stage_qualifies_sixteen_and_avoids_rematches
    sw = T::Swiss.new((1..36).to_a, rng: Random.new(1))
    5.times { sw.play_round(&strong_wins) }
    q = sw.qualifiers(16)
    assert_equal 16, q.size
    assert_equal (1..36).to_a, sw.players
    # Like swissPairs, a rematch is allowed only when a group leaves no one
    # else, so they must be rare.
    rematches = sw.opponents.values.sum { |opps| opps.size - opps.uniq.size } / 2
    assert rematches <= 2, "#{rematches} rematches"
    assert q.include?(1)
    refute q.include?(36)
  end

  def test_pwt_slots_add_to_34
    coef = { "KANTO" => 9, "JOHTO" => 8, "HOENN" => 7, "SINNOH" => 6, "UNOVA" => 5, "KALOS" => 4,
             "ALOLA" => 3, "GALAR" => 2, "PALDEA" => 1 }
    slots = T.pwt_slots(coef)
    assert_equal 34, slots.values.sum
    assert_equal 4, slots["KANTO"]
    assert_equal 3, slots["PALDEA"]
  end

  def test_points_for_results
    assert_equal 100, T.pwt_points(:champion)
    assert_equal 22, T.pwt_points(:r16)
    assert_equal 4 + 2 * 3, T.pwt_points(:swiss, wins: 2)
  end

  def test_hosts_rotate
    assert_equal FM::Tournament::PET_REGIONS[0], T.host(:pet, 1)
    assert_equal FM::Tournament::PET_REGIONS[1], T.host(:pet, 2)
    assert_equal 9, (1..9).map { |y| T.host(:pwt, y) }.uniq.size
  end
end
