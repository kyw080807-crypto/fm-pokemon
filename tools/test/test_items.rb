require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager held items (HELD / itemPrice / shopMul / buyItem / equipItem /
# returnItem / consumeItems / pickItemFor / aiMetaTeam's items).
class TestItems < Minitest::Test
  I = FM::Items
  D = [1, 1, 8].freeze

  def setup
    @w = TestPlayer.new("x").world
    @p = @w.clubs["P"]
    @a = @w.clubs["A"]
  end

  def test_prices_and_the_shop_sponsor
    assert_equal 39, I::HELD.size
    assert_equal 30_000, I.price(@p, :LEFTOVERS)
    @p.sponsor = { kind: "SHOP" }
    assert_equal 24_000, I.price(@p, :LEFTOVERS)
    assert_equal 2400, I.price(@p, :SITRUSBERRY)
  end

  def test_buy_equip_swap_and_one_per_team
    m1, m2 = @p.squad
    assert_equal 30_000, I.buy(@p, :LEFTOVERS, date: D)
    assert_equal 6000, I.buy(@p, :SITRUSBERRY, 2, date: D)
    assert_equal(-36_000, @p.wallet.totals[:shop])
    assert_equal :ok, I.equip(@p, m1, :LEFTOVERS)
    assert_equal :none, I.equip(@p, m2, :LEFTOVERS), "the bag has no second one"
    I.buy(@p, :LEFTOVERS, date: D)
    assert_equal :taken, I.equip(@p, m2, :LEFTOVERS), "no two of the team hold the same item"
    assert_equal :ok, I.equip(@p, m1, :SITRUSBERRY)
    assert_equal 2, I.count(@p, :LEFTOVERS), "the old one went back"
    assert_equal :ok, I.equip(@p, m1, nil)
    assert_nil m1.item
    assert_equal 2, I.count(@p, :SITRUSBERRY)
  end

  def test_a_leaving_mon_returns_its_item
    m = @p.squad.first
    I.buy(@p, :LIFEORB, date: D)
    I.equip(@p, m, :LIFEORB)
    @p.squad.delete(m)
    @p.retire(m)
    assert_nil m.item
    assert_equal 1, I.count(@p, :LIFEORB)
  end

  def test_used_consumables_go_and_the_bag_refills
    m = @p.squad.first
    I.buy(@p, :FOCUSSASH, 2, date: D)
    I.equip(@p, m, :FOCUSSASH)
    I.consumed(@p, [m])
    assert_equal :FOCUSSASH, m.item, "the next one goes straight on"
    assert_equal 0, I.count(@p, :FOCUSSASH)
    I.consumed(@p, [m])
    assert_nil m.item
    lefty = @p.squad[1]
    lefty.item = :LEFTOVERS
    I.consumed(@p, [lefty])
    assert_equal :LEFTOVERS, lefty.item, "only consumables are used up"
  end

  def test_pick_for_follows_the_original_order
    pool = { "X" => { base: [100, 120, 100, 50, 100, 60], evo: [], types: %w[NORMAL] },
             "Y" => { base: [50, 50, 50, 50, 50, 110], evo: [["Z", 30]], types: %w[POISON] } }
    x = FM::Mon.new(species: "X", bst: 530, level: 50, stars: 3)
    y = FM::Mon.new(species: "Y", bst: 360, level: 20, stars: 3)
    assert_equal :LEFTOVERS, I.pick_for(pool, x, [])
    assert_equal :CHOICEBAND, I.pick_for(pool, x, [:LEFTOVERS])
    assert_equal :EVIOLITE, I.pick_for(pool, y, [])
    assert_equal :BLACKSLUDGE, I.pick_for(pool, y, [:EVIOLITE])
    assert_equal :CHOICESCARF, I.pick_for(pool, y, %i[EVIOLITE BLACKSLUDGE])
  end

  def test_ai_spends_at_most_half_its_spare_money
    @a.wallet.record(-@a.wallet.balance + @a.weekly_cost * 20 + 70_000, category: :set, date: D)
    spent = I.ai_shop(@a, @w.species, date: D)
    assert_operator spent, :<=, 35_000 + 1
    @a.wallet.record(5_000_000, category: :grant, date: D)
    I.ai_shop(@a, @w.species, date: D)
    held = @a.squad.filter_map(&:item)
    assert_equal held.uniq, held, "one of each"
    assert(@a.entry.all?(&:item), "the entry (partyOf) gets items")
  end

  def test_a_held_item_counts_in_the_rating
    m = @p.squad.first
    base = m.to_rating[:mul]
    m.item = :LEFTOVERS
    assert_in_delta base * I::RATING_MUL, m.to_rating[:mul], 1e-12
  end
end
