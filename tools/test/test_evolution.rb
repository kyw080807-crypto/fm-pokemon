require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager evolve / evoOptions / useEvolve and the evolution items.
class TestEvolution < Minitest::Test
  POOL = {
    "EEVEE" => { bst: 325, evo: [["VAPOREON", 27, :WATERSTONE], ["JOLTEON", 27, :THUNDERSTONE]] },
    "VAPOREON" => { bst: 525, evo: [] }, "JOLTEON" => { bst: 525, evo: [] },
    "PIDGEY" => { bst: 251, evo: [["PIDGEOTTO", 18]] }, "PIDGEOTTO" => { bst: 349, evo: [] },
    "TYROGUE" => { bst: 210, evo: [["HITMONLEE", 20], ["HITMONCHAN", 20]] },
    "HITMONLEE" => { bst: 455, evo: [] }, "HITMONCHAN" => { bst: 455, evo: [] }
  }.freeze

  def mon(sp, level, branch: 0) = FM::Mon.new(species: sp, bst: POOL[sp][:bst], level: level, stars: 3, branch: branch)

  def test_the_ai_takes_its_branch_and_pays_for_the_item
    paid = []
    m = FM::Growth.evolve(mon("EEVEE", 30, branch: 1), POOL, pay: ->(it) { paid << it })
    assert_equal "JOLTEON", m.species
    assert_equal [:THUNDERSTONE], paid
    assert_equal "EEVEE", FM::Growth.evolve(mon("EEVEE", 20), POOL).species, "the level first"
  end

  def test_the_players_mon_waits_for_a_choice
    assert_equal "PIDGEOTTO", FM::Growth.evolve(mon("PIDGEY", 20), POOL, hold: true).species, "one item-free option"
    assert_equal "EEVEE", FM::Growth.evolve(mon("EEVEE", 30), POOL, hold: true).species
    assert_equal "TYROGUE", FM::Growth.evolve(mon("TYROGUE", 30), POOL, hold: true).species, "two branches"
  end

  def test_use_evolve_takes_the_item_or_the_level
    w = TestPlayer.new("x").world
    c = w.clubs["P"]
    e = mon("EEVEE", 5)
    c.squad << e
    assert_equal :no_item, FM::Items.use_evolve(c, e, 0, POOL)
    FM::Items.buy(c, :WATERSTONE, date: [1, 1, 1])
    assert_equal :ok, FM::Items.use_evolve(c, e, 0, POOL), "an item needs no level"
    assert_equal "VAPOREON", e.species
    assert_equal 0, FM::Items.count(c, :WATERSTONE)
    t = mon("TYROGUE", 10)
    c.squad << t
    assert_equal :level, FM::Items.use_evolve(c, t, 1, POOL)
    t.level = 20
    assert_equal :ok, FM::Items.use_evolve(c, t, 1, POOL)
    assert_equal "HITMONCHAN", t.species
  end

  def test_evolution_item_prices
    w = TestPlayer.new("x").world
    c = w.clubs["P"]
    assert_equal 8000, FM::Items.price(c, :FIRESTONE)
    assert_equal 15_000, FM::Items.price(c, :OVALSTONE)
    assert_equal 12_000, FM::Items.price(c, :LINKINGCORD)
    assert_equal 10_000, FM::Items.price(c, :SOOTHEBELL)
    assert_equal 15_000, FM::Items.price(c, :METALCOAT)
    refute FM::Items.held?(:FIRESTONE), "not a held item"
  end
end
