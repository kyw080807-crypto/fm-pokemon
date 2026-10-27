require_relative "test_helper"

class TestFinance < Minitest::Test
  DATE = [1, 1, 1].freeze

  def setup
    @ledger = FM::Finance.new(balance: 1000)
  end

  def test_income_and_expense_change_balance
    @ledger.record(500, category: :prize, date: DATE)
    @ledger.record(-200, category: :wages, date: DATE)
    assert_equal 1300, @ledger.balance
    assert_equal 2, @ledger.entries.size
  end

  def test_spend_refuses_when_short
    assert_raises(FM::Finance::InsufficientFunds) { @ledger.spend(1500, category: :transfer, date: DATE) }
    assert_equal 1000, @ledger.balance
    assert_empty @ledger.entries
  end

  def test_spend_and_can_afford
    assert @ledger.can_afford?(1000)
    refute @ledger.can_afford?(1001)
    @ledger.spend(400, category: :facility, date: DATE, memo: "체육관 수리")
    assert_equal 600, @ledger.balance
    assert_equal(-400, @ledger.entries.last.amount)
    assert_equal "체육관 수리", @ledger.entries.last.memo
  end

  def test_record_allows_debt
    @ledger.record(-1500, category: :fine, date: DATE)
    assert_equal(-500, @ledger.balance)
  end

  def test_zero_and_non_integer_amounts_rejected
    assert_raises(ArgumentError) { @ledger.record(0, category: :x, date: DATE) }
    assert_raises(ArgumentError) { @ledger.record(1.5, category: :x, date: DATE) }
    assert_raises(ArgumentError) { @ledger.spend(-10, category: :x, date: DATE) }
  end

  def test_weekly_recurring_applies_on_new_week
    @ledger.add_recurring(:sponsor, amount: 300, category: :sponsor, every: :week)
    @ledger.add_recurring(:rent, amount: -100, category: :rent, every: :month)
    @ledger.on_calendar_event(:new_week, DATE)
    assert_equal 1300, @ledger.balance
    assert_equal [:sponsor], @ledger.entries.map(&:category)
  end

  def test_recurring_driven_by_calendar
    @ledger.add_recurring(:sponsor, amount: 300, category: :sponsor, every: :week)
    @ledger.add_recurring(:rent, amount: -100, category: :rent, every: :month)
    cal = FM::Calendar.new(month: 1, day: 1)
    cal.advance(31).each { |kind, snap| @ledger.on_calendar_event(kind, [snap[:year], snap[:month], snap[:day]]) }
    # Jan 1 is a Monday: 4 new weeks (8, 15, 22, 29) and one new month (Feb 1).
    assert_equal 1000 + 4 * 300 - 100, @ledger.balance
  end

  def test_remove_recurring
    @ledger.add_recurring(:sponsor, amount: 300, category: :sponsor, every: :week)
    @ledger.remove_recurring(:sponsor)
    @ledger.on_calendar_event(:new_week, DATE)
    assert_equal 1000, @ledger.balance
  end

  def test_recurring_rejects_unknown_period
    assert_raises(ArgumentError) { @ledger.add_recurring(:x, amount: 1, category: :x, every: :day) }
  end

  def test_totals_by_category_within_dates
    @ledger.record(500, category: :prize, date: [1, 1, 3])
    @ledger.record(200, category: :prize, date: [1, 2, 1])
    @ledger.record(-50, category: :wages, date: [1, 2, 5])
    assert_equal({ prize: 200, wages: -50 }, @ledger.totals(from: [1, 2, 1], to: [1, 2, 28]))
    assert_equal({ prize: 700, wages: -50 }, @ledger.totals)
  end

  def test_save_round_trip
    @ledger.add_recurring(:sponsor, amount: 300, category: :sponsor, every: :week)
    @ledger.record(-200, category: :wages, date: DATE, memo: "선수 급여")
    copy = FM::Finance.from_h(@ledger.to_h)
    assert_equal @ledger.to_h, copy.to_h
    copy.on_calendar_event(:new_week, DATE)
    assert_equal 1100, copy.balance
  end

  def test_rejects_future_schema
    assert_raises(ArgumentError) { FM::Finance.from_h(schema_version: 99, balance: 0) }
  end
end
