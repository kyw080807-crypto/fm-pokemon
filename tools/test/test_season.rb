require_relative "test_helper"

class TestSeason < Minitest::Test
  def setup
    @cal = FM::Calendar.new   # year 1 starts on a Monday
  end

  def league(year = 1)
    FM::Season.league_dates(@cal, year)
  end

  def test_thirty_eight_rounds_in_order
    dates = league
    assert_equal 38, dates.size
    assert_equal dates.sort_by { |d| @cal.ordinal(d) }, dates
    assert_equal dates.uniq, dates
  end

  def test_league_starts_on_first_sunday_after_preseason
    first = league.first
    assert_equal :sun, @cal.weekday_of(first)
    assert_equal 2, first[1]
    assert first[2].between?(1, 7)
  end

  def test_only_sundays_and_double_week_wednesdays
    days = league.map { |d| @cal.weekday_of(d) }
    assert_equal 33, days.count(:sun)
    assert_equal 5, days.count(:wed)
    assert_empty days - %i[sun wed]
  end

  def test_double_week_wednesday_is_four_days_before_its_sunday
    dates = league
    dates.each_with_index do |d, i|
      next unless @cal.weekday_of(d) == :wed
      assert_equal 4, @cal.days_between(d, dates[i + 1])
    end
  end

  def test_no_league_match_in_preseason
    assert league.none? { |d| d[1] == 1 }
  end

  def test_later_years_shift_weekdays_but_keep_rules
    dates = league(2)   # year 2 starts on a Tuesday
    assert_equal 38, dates.size
    assert_equal :sun, @cal.weekday_of(dates.first)
    assert_equal [2, 2], dates.first[0, 2]
    assert(dates.all? { |d| d[0] == 2 })
  end

  def test_season_week_sunday_lines_up_with_league
    # Season week 5 is league week 1 (weeks 1-4 are pre-season).
    assert_equal league.first, FM::Season.season_week_sunday(@cal, 1, 5)
    assert_equal league.last, FM::Season.season_week_sunday(@cal, 1, 37)
  end

  def test_tournament_dates
    t = FM::Season.tournament_dates(@cal, 1)
    assert_equal 4, t[:pet].size     # PET/PENT: R16, QF, SF, final (weeks 40-43)
    assert_equal 5, t[:pwt_swiss].size
    assert_equal 4, t[:pwt_knockout].size
    all = t[:pet] + t[:pwt_swiss] + t[:pwt_knockout]
    assert(all.all? { |d| @cal.weekday_of(d) == :sun })
    assert_equal all.sort_by { |d| @cal.ordinal(d) }, all
    # Two travel weeks (38-39) between the last league match and PET/PENT.
    assert_equal 21, @cal.days_between(league.last, t[:pet].first)
    assert_equal 1, all.last[0]
    assert_equal 12, all.last[1]
  end

  def test_weekday_of
    assert_equal :mon, @cal.weekday_of([1, 1, 1])
    assert_equal :sun, @cal.weekday_of([1, 1, 7])
    assert_equal :tue, @cal.weekday_of([2, 1, 1])
  end
end
