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

  def test_rejects_future_schema
    assert_raises(ArgumentError) { FM::Calendar.from_h(schema_version: 99, year: 1, month: 1, day: 1) }
  end
end
