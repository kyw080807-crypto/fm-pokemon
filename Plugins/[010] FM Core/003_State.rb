#===============================================================================
# FM::State — everything FM keeps in a save file, as one object. Pure Ruby.
# to_h returns plain data (Hash/Array/Integer/Symbol/String only), so saves
# don't depend on FM class layouts; schema_version guards future changes.
#===============================================================================
module FM
  class State
    SCHEMA_VERSION = 1
    # Placeholder until docs/design/05_finance.md fixes the real number.
    START_BALANCE  = 10_000

    attr_reader :calendar, :finance

    def self.new_game(balance: START_BALANCE)
      new(calendar: Calendar.new, finance: Finance.new(balance: balance))
    end

    def initialize(calendar:, finance:)
      @calendar = calendar
      @finance  = finance
    end

    def date
      @calendar.date
    end

    # Moves time forward and routes calendar boundary events to the systems
    # that react to them. Returns the events for callers (UI, news) to use.
    def advance_days(days)
      events = @calendar.advance(days)
      events.each do |kind, snap|
        @finance.on_calendar_event(kind, [snap[:year], snap[:month], snap[:day]])
      end
      events
    end

    def to_h
      { schema_version: SCHEMA_VERSION,
        calendar:       @calendar.to_h,
        finance:        @finance.to_h }
    end

    def self.from_h(h)
      version = h[:schema_version] || 0
      raise ArgumentError, "unknown FM state schema #{version}" if version > SCHEMA_VERSION
      new(calendar: Calendar.from_h(h[:calendar]), finance: Finance.from_h(h[:finance]))
    end
  end
end
