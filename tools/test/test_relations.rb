require_relative "test_helper"

class TestRelations < Minitest::Test
  def test_basics_symmetric_and_bounded
    r = FM::Relations.new
    assert_equal 0.0, r.get("A", "B")
    r.change("A", "B", 0.3)
    assert_in_delta 0.3, r.get("B", "A")
    r.change("A", "B", 5)
    assert_equal 1.0, r.get("A", "B")
    assert_equal 0.0, r.get("A", "A")
  end

  def test_derby_and_meetings
    r = FM::Relations.new
    r.derby("W", "L")
    assert_in_delta FM::Relations::DERBY + FM::Relations::DERBY_WIN_GLOAT, r.get("W", "L")
    r.meeting({ "A" => true, "B" => true, "C" => false }, passed: true)
    assert_in_delta FM::Relations::PASSED, r.get("A", "B")
    assert_in_delta FM::Relations::PASSED + FM::Relations::SPLIT_VOTE, r.get("A", "C")
    r.meeting({ "A" => false, "B" => false }, passed: false)
    assert_in_delta FM::Relations::PASSED + FM::Relations::FAILED, r.get("A", "B")
  end

  def test_season_decay
    r = FM::Relations.new
    r.change("A", "B", 0.5)
    r.season_decay
    assert_in_delta 0.4, r.get("A", "B")
    20.times { r.season_decay }
    assert_equal 0, r.size
  end

  def test_vote_term
    r = FM::Relations.new
    r.change("A", "B", 0.4)
    r.change("A", "C", -0.2)
    assert_in_delta (0.4 - 0.2) / 2 * FM::Relations::VOTE_WEIGHT, r.vote_term("A", %w[A B C])
    assert_equal 0.0, r.vote_term("A", %w[A])
  end

  def test_relation_can_flip_a_vote
    t = { civic: 0.0, commercial: 0.0, cooperative: 0.0, competitive: 0.0 }
    v = { traits: t, spare: 1_000_000, relation: 0.0 }
    share = 250_000     # cost term 0.5 = gain 0.5 -> score 0
    refute FM::Vote.infrastructure_yes?(v, share: share)
    assert FM::Vote.infrastructure_yes?(v.merge(relation: 0.1), share: share)
    refute FM::Vote.infrastructure_yes?(v.merge(relation: -0.1), share: share - 1000)
  end

  def club(id, city)
    { id: id, name: id, region: "KANTO", city: city, role: "G1", canon: true, level: 30, potential: 3,
      type: "NORMAL", stadium: 1, clubhouse: 1, facilities: { TRAINING: 1 },
      pokemon: Array.new(3) { { bst: 450, level: 30, stars: 3 } } }
  end

  def test_derbies_in_a_shared_city_cool_relations
    w = FM::World.new_game([club("A", "X"), club("B", "X"), club("C", "Y"), club("D", "Y")], seed: 1)
    w.advance_days(364)
    assert w.relations.get("A", "B").negative?, "two derbies a season between A and B"
    assert_equal 0.0, w.relations.get("A", "C")
  end

  def test_old_world_without_relations
    w = FM::World.new_game([club("A", "X"), club("B", "X"), club("C", "Y"), club("D", "Y")], seed: 1)
    w.remove_instance_variable(:@relations) if w.instance_variable_defined?(:@relations)
    assert_equal 0.0, w.relations.get("A", "B")
  end
end
