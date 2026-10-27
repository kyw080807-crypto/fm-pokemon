#===============================================================================
# FM::Season — where a season's fixed events fall on the 365-day calendar.
# Pure Ruby.
#
# Decided 2026-10-27: pre-season is January 1-31; league matches are on
# Sundays, and in two-match weeks on Wednesday and Sunday. The league runs
# 33 Monday-Sunday weeks from the first Sunday in February: 28 one-match
# weeks + 5 two-match weeks = 38 rounds (docs/design/05_travel_season.md).
#===============================================================================
module FM
  module Season
    PRESEASON_LAST_DAY = [1, 31].freeze   # [month, day]
    LEAGUE_WEEKS       = 33
    # 1-based league weeks with two matches. The design doc proposes season
    # weeks 10/16/22/28/34 (= league weeks 6/12/18/24/30) pending headless
    # simulation, so treat these as tunable.
    DOUBLE_WEEKS       = [6, 12, 18, 24, 30].freeze

    module_function

    # League match dates for `year`, in order, as [year, month, day].
    def league_dates(calendar, year)
      first_sunday = calendar.date_after([year, *PRESEASON_LAST_DAY], 1)
      first_sunday = calendar.date_after(first_sunday, 1) until calendar.weekday_of(first_sunday) == :sun
      (1..LEAGUE_WEEKS).flat_map do |week|
        sunday = calendar.date_after(first_sunday, 7 * (week - 1))
        DOUBLE_WEEKS.include?(week) ? [calendar.date_after(sunday, -4), sunday] : [sunday]
      end
    end

    # Season weeks follow the design doc's 52-week table: weeks 1-4 are
    # pre-season and league week k is season week k + 4.
    def season_week_sunday(calendar, year, week)
      league_start = league_dates(calendar, year).first
      calendar.date_after(league_start, 7 * (week - 5))
    end

    # Post-league tournaments, one round per Sunday (design table):
    # weeks 38-39 travel, 40-43 PET·PENT, 44-48 PWT Swiss, 49-52 PWT knockout.
    def tournament_dates(calendar, year)
      week = ->(w) { season_week_sunday(calendar, year, w) }
      { pet:          (40..43).map(&week),
        pwt_swiss:    (44..48).map(&week),
        pwt_knockout: (49..52).map(&week) }
    end

    def preseason?(date)
      ([date[1], date[2]] <=> PRESEASON_LAST_DAY) <= 0
    end
  end
end
