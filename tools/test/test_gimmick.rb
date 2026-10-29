require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager battle gimmicks (GIM_REG / pwtHost / GIM_HELD / gimItemKind /
# gimItemOK / gimLive / aiGimmick / gimPickBonus).
class TestGimmick < Minitest::Test
  G = FM::Gimmick
  CATALOG = { mega: { CHARIZARDITEX: ["CHARIZARD"], CHARIZARDITEY: ["CHARIZARD"], VENUSAURITE: ["VENUSAUR"] },
              primal: { REDORB: "GROUDON" }, z: { FIRIUMZ: "FIRE", WATERIUMZ: "WATER", NORMALIUMZ: "NORMAL" },
              gmax: ["CHARIZARD"] }.freeze

  def setup
    @saved = G.catalog
    G.catalog = CATALOG
    @w = TestPlayer.new("x").world
    @p = @w.clubs["P"]
    @a = @w.clubs["A"]
  end

  def teardown = G.catalog = @saved

  def mon(sp, item = nil)
    m = FM::Mon.new(species: sp, bst: 500, level: 50, stars: 3)
    m.item = item
    m
  end

  def test_regions_and_items
    assert_equal %i[mega z], G.of_region("ALOLA")
    assert_equal [], G.of_region("KANTO")
    assert_equal :mega, G.kind(:CHARIZARDITEX)
    assert_equal :mega, G.kind(:REDORB)
    assert_equal :z, G.kind(:FIRIUMZ)
    assert_equal :dmax, G.kind(:MAXMUSHROOM)
    assert_equal :tera, G.kind(:FIRETERACRYSTAL)
    assert_nil G.kind(:LEFTOVERS)
    assert_equal [40_000, 100_000, 20_000, 25_000, 40_000, 20_000],
                 %i[VENUSAURITE REDORB FIRIUMZ MAXMUSHROOM GMAXMUSHROOM WATERTERACRYSTAL].map { |id| G.price(id) }
  end

  def test_who_may_hold_what
    pool = {}
    assert G.ok?(pool, mon("CHARIZARD"), :CHARIZARDITEX)
    refute G.ok?(pool, mon("VENUSAUR"), :CHARIZARDITEX), "its own Mega Stone only"
    assert G.ok?(pool, mon("CHARIZARD"), :GMAXMUSHROOM)
    refute G.ok?(pool, mon("VENUSAUR"), :GMAXMUSHROOM), "G-Max species only"
    assert G.ok?(pool, mon("VENUSAUR"), :MAXMUSHROOM)
    assert G.live?(pool, mon("CHARIZARD", :CHARIZARDITEX), %i[mega])
    refute G.live?(pool, mon("CHARIZARD", :CHARIZARDITEX), %i[dmax]), "no effect in other games"
    refute G.unique?(:MAXMUSHROOM)
  end

  def test_side_multiplier
    pool = {}
    one = [mon("CHARIZARD", :CHARIZARDITEX), mon("PIDGEY"), mon("PIDGEY")]
    two = [mon("CHARIZARD", :CHARIZARDITEX), mon("VENUSAUR", :VENUSAURITE), mon("PIDGEY")]
    assert_equal 1.04, G.side_mul(pool, one, %i[mega])
    assert_equal 1.05, G.side_mul(pool, two, %i[mega])
    assert_equal 1.0, G.side_mul(pool, two, %i[tera])
  end

  def test_pwt_hosts_alternate_and_do_not_repeat
    hosts = (1..10).map { |y| G.pwt_host(@w, y) }
    assert(hosts.each_with_index.all? { |h, i| (i.even? ? G::HOST_GIM : G::HOST_PLAIN).include?(h) })
    assert_equal G::HOST_GIM.sort, hosts.values_at(0, 2, 4, 6, 8).sort, "each gimmick region once"
    assert_equal hosts.first, G.pwt_host(@w, 1), "kept"
  end

  def test_items_take_the_held_slot_with_their_rules
    pool = { "CHARIZARD" => { types: %w[FIRE FLYING] } }
    c = mon("CHARIZARD")
    v = mon("VENUSAUR")
    @p.squad.push(c, v)
    FM::Items.buy(@p, :CHARIZARDITEX, date: [1, 1, 1])
    assert_equal :wrong_mon, FM::Items.equip(@p, v, :CHARIZARDITEX, pool: pool)
    assert_equal :ok, FM::Items.equip(@p, c, :CHARIZARDITEX, pool: pool)
    FM::Items.buy(@p, :MAXMUSHROOM, 2, date: [1, 1, 1])
    assert_equal :ok, FM::Items.equip(@p, v, :MAXMUSHROOM, pool: pool)
    assert_equal :ok, FM::Items.equip(@p, @p.squad.first, :MAXMUSHROOM, pool: pool), "several may hold one"
  end

  def test_ai_sets_up_two_holders_for_its_gimmick
    pool = { "CHARIZARD" => { types: %w[FIRE], base: [78, 84, 78, 109, 85, 100] }, "VENUSAUR" => { types: %w[GRASS] },
             "PIDGEY" => { types: %w[NORMAL] } }
    @a.instance_variable_set(:@role, "T")   # no specialty: all three in the entry
    @a.squad.replace([mon("CHARIZARD"), mon("VENUSAUR"), mon("PIDGEY")])
    @a.squad.first.item = :LEFTOVERS
    bought = []
    G.ai_prepare(@a, pool, %i[mega]) { |id| bought << id }
    assert_equal :CHARIZARDITEY, @a.squad.first.item, "Y for a special attacker"
    assert_equal :LEFTOVERS, @a.squad.first.prev_item
    assert_equal :VENUSAURITE, @a.squad[1].item
    G.ai_prepare(@a, pool, %i[tera]) { |id| bought << id }
    assert_equal :LEFTOVERS, @a.squad.first.prev_item, "the old item waits behind the new gimmick item"
    assert(@a.squad.count { |m| G.kind(m.item) == :tera } == 2)
    assert_includes @a.gbag, :CHARIZARDITEY, "kept for later"
    G.ai_prepare(@a, pool, %i[mega]) { |id| bought << id }
    assert_equal 1, bought.count(:CHARIZARDITEY), "the bag first"
  end
end
