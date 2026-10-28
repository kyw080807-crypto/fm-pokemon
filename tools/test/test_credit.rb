require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

class TestCredit < Minitest::Test
  def setup
    @w = TestPlayer.new("x").world
    @c = @w.clubs["P"]
    @cal = @w.calendar
  end

  def week(n = 1)
    out = []
    n.times { |i| out.concat(FM::Credit.week(@c, date: @cal.date_after([1, 1, 1], 7 * i), calendar: @cal)) }
    out
  end

  def go_red(by = 500_000)
    @c.wallet.record(-@c.wallet.balance - by, category: :drain, date: [1, 1, 1])
  end

  def test_limit_is_by_fame_and_one_loan_at_a_time
    @c.fame = 60
    assert_equal 300_000, FM::Credit.limit(@c)
    refute FM::Credit.can_borrow?(@c, 300_001)
    before = @c.wallet.balance
    FM::Credit.borrow(@c, 200_000, date: [1, 1, 1])
    assert_equal before + 200_000, @c.wallet.balance
    refute FM::Credit.can_borrow?(@c, 10_000), "one loan at a time"
  end

  def test_loan_is_repaid_weekly_with_interest
    @c.fame = 60
    FM::Credit.borrow(@c, 52_000, date: [1, 1, 1])
    start = @c.wallet.balance
    week(52)
    assert_nil @c.loan
    paid = start - @c.wallet.balance
    assert_operator paid, :>, 52_000
    assert_operator paid, :<, 52_000 * 1.1
  end

  def test_repay_early
    @c.fame = 60
    FM::Credit.borrow(@c, 100_000, date: [1, 1, 1])
    week(3)
    owed = @c.loan[:owed]
    b = @c.wallet.balance
    FM::Credit.repay_all(@c, date: [1, 1, 22])
    assert_nil @c.loan
    assert_equal b - owed, @c.wallet.balance
  end

  def test_ladder_warning_austerity_bailout
    go_red
    stages = week(FM::Credit::BAILOUT_WEEKS).select { |e| e[:kind] == :crisis }.map { |e| e[:stage] }
    assert_equal %i[warning austerity], stages
    assert_nil @c.crisis, "bailed out"
    assert @c.bailed
    assert_operator @c.wallet.balance, :>=, 0
    assert_equal 1, FM::Credit.sign_penalty(@c, @c.bailed[0] + 1)
  end

  def test_austerity_stops_ai_building_and_signing
    go_red
    week(FM::Credit::AUSTERITY_WEEKS)
    assert FM::Credit.austerity?(@c)
    assert_nil FM::Recruit.weekly(@c, pool: @w.species, regions: ["KANTO"], avg_level: 20, window: true,
                                      date: [1, 3, 1], rng: Random.new(1))
  end

  def test_red_again_after_a_bailout_brings_pressure_then_dismissal
    go_red
    week(FM::Credit::BAILOUT_WEEKS)
    go_red
    events = []
    (2 * FM::Credit::AUSTERITY_WEEKS).times do |i|
      events.concat(FM::Credit.week(@c, date: @cal.date_after([1, 5, 1], 7 * i), calendar: @cal))
    end
    assert(events.any? { |e| e[:kind] == :crisis && e[:stage] == :pressure })
    assert(events.any? { |e| e[:kind] == :dismissed && e[:club] == "P" })
  end

  def test_state_drops_a_dismissed_player
    s = FM::State.new_game(world: @w)
    s.player_club = "P"
    FM::Credit.stub(:week, ->(c, **) { c.id == "P" ? [{ kind: :dismissed, club: "P" }] : [] }) do
      s.advance_days(7)
    end
    assert_nil s.player_club
    assert_nil @w.player_club
  end
end
