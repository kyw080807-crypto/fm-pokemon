require_relative "test_helper"

class TestCalendar < Minitest::Test
  def test_starts_on_monday
    assert_equal :mon, FM::Calendar.new.weekday
  end

  def test_month_rollover
    cal = FM::Calendar.new(month: 1, day: 31)
    events = cal.advance
    assert_equal [2, 1], [cal.month, cal.day]
    assert_includes events.map(&:first), :new_month
  end

  def test_year_rollover_emits_year_then_month
    cal = FM::Calendar.new(year: 3, month: 12, day: 31)
    kinds = cal.advance.map(&:first)
    assert_equal 4, cal.year
    assert_equal %i[new_year new_month], kinds.first(2)
  end

  def test_new_week_every_seven_days
    cal = FM::Calendar.new
    weeks = cal.advance(21).count { |kind, _| kind == :new_week }
    assert_equal 3, weeks
  end

  def test_custom_month_lengths
    cal = FM::Calendar.new(month_lengths: [28] * 4)
    cal.advance(28 * 4)
    assert_equal [2, 1, 1], [cal.year, cal.month, cal.day]
  end

  def test_save_round_trip
    cal = FM::Calendar.new(year: 2, month: 5, day: 9)
    cal.advance(40)
    copy = FM::Calendar.from_h(cal.to_h)
    assert_equal cal.to_h, copy.to_h
  end

  def test_rejects_invalid_date
    assert_raises(ArgumentError) { FM::Calendar.new(month: 2, day: 30) }
  end

  def test_year_is_365_days
    cal = FM::Calendar.new
    assert_equal 365, cal.days_in_year
    cal.advance(365)
    assert_equal [2, 1, 1], cal.date
  end

  def test_day_of_year
    assert_equal 1, FM::Calendar.new.day_of_year
    assert_equal 32, FM::Calendar.new(month: 2, day: 1).day_of_year
    assert_equal 365, FM::Calendar.new(month: 12, day: 31).day_of_year
  end

  def test_weekday_carries_across_years
    cal = FM::Calendar.new
    cal.advance(365)
    # 365 = 52 weeks + 1 day, so year 2 starts one weekday later.
    assert_equal :tue, cal.weekday
  end

  def test_date_after_and_days_between
    cal = FM::Calendar.new
    assert_equal [1, 2, 1], cal.date_after([1, 1, 31], 1)
    assert_equal [2, 1, 2], cal.date_after([1, 12, 31], 2)
    assert_equal [1, 12, 31], cal.date_after([2, 1, 1], -1)
    assert_equal 3, cal.days_between([1, 12, 30], [2, 1, 2])
    assert_equal(-3, cal.days_between([2, 1, 2], [1, 12, 30]))
  end

  def test_days_until
    cal = FM::Calendar.new(month: 3, day: 10)
    assert_equal 5, cal.days_until([1, 3, 15])
    assert_equal 0, cal.days_until(cal.date)
  end

  def test_rejects_future_schema
    assert_raises(ArgumentError) { FM::Calendar.from_h(schema_version: 99, year: 1, month: 1, day: 1) }
  end
end
