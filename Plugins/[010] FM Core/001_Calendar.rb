#===============================================================================
# FM::Calendar — in-game day counter. Pure Ruby: no RGSS / Essentials symbols,
# so tools/test can require this file with system Ruby.
#===============================================================================
module FM
  class Calendar
    SCHEMA_VERSION        = 1
    DEFAULT_MONTH_LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze
    WEEKDAYS              = %i[mon tue wed thu fri sat sun].freeze

    attr_reader :year, :month, :day, :elapsed_days, :month_lengths

    # elapsed_days counts from the start date, which is always a Monday.
    def initialize(year: 1, month: 1, day: 1, elapsed_days: 0, month_lengths: DEFAULT_MONTH_LENGTHS)
      @month_lengths = month_lengths.dup.freeze
      raise ArgumentError, "month out of range: #{month}" unless month.between?(1, @month_lengths.size)
      raise ArgumentError, "day out of range: #{day}" unless day.between?(1, @month_lengths[month - 1])
      @year         = year
      @month        = month
      @day          = day
      @elapsed_days = elapsed_days
    end

    def weekday
      WEEKDAYS[@elapsed_days % 7]
    end

    # Advances the date and returns the boundary events crossed, in order,
    # e.g. [[:new_year, snapshot], [:new_month, snapshot], [:new_week, snapshot]].
    # Callers (Bridge) turn these into league fixtures, salaries, news and so on.
    def advance(days = 1)
      raise ArgumentError, "days must be >= 0" if days.negative?
      events = []
      days.times do
        @elapsed_days += 1
        @day += 1
        if @day > @month_lengths[@month - 1]
          @day = 1
          @month += 1
          if @month > @month_lengths.size
            @month = 1
            @year += 1
            events << [:new_year, to_h]
          end
          events << [:new_month, to_h]
        end
        events << [:new_week, to_h] if weekday == :mon
      end
      events
    end

    def to_s
      format("%d년 %d월 %d일", @year, @month, @day)
    end

    def to_h
      { schema_version: SCHEMA_VERSION, year: @year, month: @month, day: @day,
        elapsed_days: @elapsed_days, month_lengths: @month_lengths }
    end

    def self.from_h(h)
      version = h[:schema_version] || 0
      raise ArgumentError, "unknown calendar schema #{version}" if version > SCHEMA_VERSION
      new(year: h[:year], month: h[:month], day: h[:day],
          elapsed_days: h[:elapsed_days] || 0,
          month_lengths: h[:month_lengths] || DEFAULT_MONTH_LENGTHS)
    end
  end
end
