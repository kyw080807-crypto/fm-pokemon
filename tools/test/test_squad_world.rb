require_relative "test_helper"
require_relative "test_squad"   # TestSquad::SPECIES

class TestSquadWorld < Minitest::Test
  SPECIES = TestSquad::SPECIES

  def club(id, train:, scout:)
    { id: id, name: id, region: "KANTO", city: "C", role: "T", canon: false, level: 20, potential: 3,
      stadium: 1, clubhouse: 3, facilities: { TRAINING: train, SCOUTING: scout },
      pokemon: [{ species: "CHARMANDER", bst: 309, level: 14, stars: 3 },
                { species: "PIDGEY", bst: 251, level: 12, stars: 3 },
                { species: "TOTODILE", bst: 314, level: 12, stars: 3 }] }
  end

  def world(seed = 1)
    clubs = [club("HI", train: 5, scout: 5), club("LO", train: 1, scout: 1), club("X", train: 2, scout: 2),
             club("Y", train: 2, scout: 2)]
    FM::World.new_game(clubs, seed: seed, species: SPECIES)
  end

  def test_squads_grow_and_ratings_rise
    w = world
    before = w.clubs["HI"].rating
    w.advance_days(180)
    assert w.clubs["HI"].rating > before
    assert w.clubs["HI"].squad.any? { |m| m.species == "CHARMELEON" }, "Charmander levels into Charmeleon"
  end

  def test_better_training_makes_a_stronger_team
    w = world
    # Rich enough that friendly tours (no training that week) are rare.
    w.clubs.each_value { |c| c.wallet.record(50_000_000, category: :grant, date: [1, 1, 1]) }
    w.advance_days(200)
    hi = w.clubs["HI"].squad.sum(&:ev)
    lo = w.clubs["LO"].squad.sum(&:ev)
    assert hi > lo
  end

  def test_clubs_scout_and_sign_to_fill_squads
    w = world
    events = w.advance_days(365)
    signed = events.select { |e| e[:kind] == :signed }
    refute_empty signed
    w.clubs.each_value do |c|
      assert c.squad.size <= FM::Build.squad_size(c.clubhouse)
    end
    assert w.clubs.values.any? { |c| c.wallet.totals.key?(:scout) }
    assert w.clubs.values.any? { |c| c.wallet.totals.key?(:sign) }
  end

  def test_emergency_youth_fills_a_squad_below_three
    w = world
    lo = w.clubs["LO"]
    lo.wallet.record(-lo.wallet.balance - 500_000, category: :drain, date: [1, 1, 1])   # broke
    lo.squad.pop(2)
    w.advance_days(7)
    assert lo.squad.size >= 3
    assert lo.squad.last(2).all? { |m| m.stars >= 3 }
  end

  def test_short_of_money_releases_low_value_mons
    w = world
    c = w.clubs["X"]
    6.times { c.squad << FM::Mon.new(species: "PIDGEY", bst: 251, level: 12, stars: 1) }
    c.wallet.record(-c.wallet.balance, category: :drain, date: [1, 1, 1])
    top = c.squad.max_by(3, &:rating)
    w.advance_days(7)
    assert c.squad.size < 9
    assert c.squad.size >= 4
    top.each { |m| assert_includes c.squad, m, "the best three are kept" }
  end

  def test_mons_retire_after_ten_seasons
    w = world
    w.clubs["LO"].squad.first.age = 9
    events = w.advance_days(365)
    assert events.any? { |e| e[:kind] == :retired && e[:club] == "LO" }
  end
end
