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

  # Worlds-style: 3 wins and you're through with no more games, 3 losses and
  # you're out; at most 5 rounds; 32 players give exactly 16 qualifiers
  # (4 at 3-0, 6 at 3-1, 6 at 3-2: 32 -> 16 -> 8 -> 4 unbeaten, and so on).
  def test_swiss_three_wins_advance_three_losses_out
    sw = T::Swiss.new((1..32).to_a, rng: Random.new(1))
    rounds = 0
    until sw.done?
      sw.play_round(&strong_wins)
      rounds += 1
    end
    assert_equal 5, rounds
    q = sw.qualifiers(16)
    assert_equal 16, q.size
    assert(q.all? { |p| sw.wins[p] == 3 })
    assert(((1..32).to_a - q).all? { |p| sw.losses[p] == 3 })
    assert_equal({ 0 => 4, 1 => 6, 2 => 6 }, q.map { |p| sw.losses[p] }.tally.sort.to_h)
    # Nobody plays after reaching 3 wins or 3 losses.
    sw.players.each { |p| assert_equal sw.wins[p] + sw.losses[p], sw.opponents[p].size }
  end

  def test_swiss_pairs_only_same_record_and_active_players
    sw = T::Swiss.new((1..32).to_a, rng: Random.new(2))
    3.times { sw.play_round(&strong_wins) }
    sw.pairs.each do |a, b|
      assert sw.active?(a) && sw.active?(b)
      assert_equal [sw.wins[a], sw.losses[a]], [sw.wins[b], sw.losses[b]]
    end
  end

  def test_qualifier_order_puts_three_oh_first
    sw = T::Swiss.new((1..32).to_a, rng: Random.new(3))
    sw.play_round(&strong_wins) until sw.done?
    q = sw.qualifiers(16)
    assert_equal 0, sw.losses[q.first]
  end

  def test_pwt_slots_add_to_30
    coef = { "KANTO" => 9, "JOHTO" => 8, "HOENN" => 7, "SINNOH" => 6, "UNOVA" => 5, "KALOS" => 4,
             "ALOLA" => 3, "GALAR" => 2, "PALDEA" => 1 }
    slots = T.pwt_slots(coef)
    assert_equal 30, slots.values.sum, "30 league places + PET and PENT winners = 32"
    assert_equal [4, 4, 4], slots.values_at("KANTO", "JOHTO", "HOENN")
    assert_equal 3, slots["SINNOH"]
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
