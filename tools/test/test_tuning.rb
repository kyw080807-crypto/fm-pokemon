require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager 기술변경권 / 민트 / 특성캡슐 (TICKETS, movesetOf, natureOf, abilityOf).
class TestTuning < Minitest::Test
  T = FM::Tuning
  D = [1, 1, 1].freeze

  def setup
    @w = TestPlayer.new("x").world
    @p = @w.clubs["P"]
    @m = @p.squad.first
  end

  def test_ticket_sets_learnable_moves_for_a_price
    pool = %i[TACKLE EMBER FLAMETHROWER SCRATCH GROWL]
    bal = @p.wallet.balance
    assert_equal :not_learnable, T.set_moves(@p, @m, %i[SURF], pool: pool, date: D)
    assert_equal :count, T.set_moves(@p, @m, pool, pool: pool, date: D), "four at most"
    assert_equal :ok, T.set_moves(@p, @m, %i[EMBER FLAMETHROWER], pool: pool, date: D)
    assert_equal %i[EMBER FLAMETHROWER], @m.moves
    assert_equal bal - 20_000, @p.wallet.balance
    assert_equal :same, T.set_moves(@p, @m, %i[EMBER FLAMETHROWER], pool: pool, date: D), "no charge for nothing"
  end

  def test_mint_changes_nature_and_temperament
    old = FM::Morale.nature(@m)
    new_nature = (FM::Morale::NATURES - [old]).first
    assert_equal :ok, T.mint(@p, @m, new_nature, date: D)
    assert_equal new_nature, FM::Morale.nature(@m)
    assert_equal FM::Morale::TEMPER_OF.fetch(new_nature), FM::Morale.temper(@m)
    assert_equal :unknown, T.mint(@p, @m, :GRUMPY, date: D)
    assert_equal(-15_000, @p.wallet.totals[:shop])
  end

  def test_capsule_and_the_shop_sponsor
    assert_equal :same, T.capsule(@p, @m, 0, count: 3, current: 0, date: D)
    assert_equal :unknown, T.capsule(@p, @m, 3, count: 3, current: 0, date: D)
    @p.sponsor = { kind: "SHOP" }
    assert_equal 20_000, T.price(@p, :ability)
    assert_equal :ok, T.capsule(@p, @m, 2, count: 3, current: 0, date: D)
    assert_equal 2, @m.ab
    @p.wallet.record(-@p.wallet.balance, category: :drain, date: D)
    assert_equal :money, T.mint(@p, @m, :JOLLY, date: D)
  end
end
