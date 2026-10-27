#===============================================================================
# FM::State — everything FM keeps in a save file, as one object. Pure Ruby.
# Calendar and finance go in as plain data. The world (FM::World: clubs,
# cities, leagues, cups, Random state) goes in as Ruby objects: rebuilding
# that much state by hand is error-prone, and Marshal keeps it exact. The
# cost is that renaming World/Club/City/... fields needs a step in from_h
# keyed on SCHEMA_VERSION, so bump it whenever their layout changes.
# Version 1: calendar + finance. Version 2: + world.
#===============================================================================
module FM
  class State
    SCHEMA_VERSION = 2
    # Placeholder until docs/design/05_finance.md fixes the real number.
    START_BALANCE  = 10_000

    attr_reader :calendar, :finance, :world
    attr_accessor :player_club   # club id the player manages; nil until chosen

    def self.new_game(balance: START_BALANCE, world: nil)
      new(calendar: Calendar.new, finance: Finance.new(balance: balance), world: world)
    end

    def initialize(calendar:, finance:, world: nil)
      @calendar = calendar
      @finance  = finance
      @world    = world
    end

    def date
      @calendar.date
    end

    # Moves time forward and routes calendar boundary events to the systems
    # that react to them. Returns the events for callers (UI, news) to use.
    # With a world, the world's own calendar is the clock.
    def advance_days(days)
      return @world.advance_days(days) if @world
      events = @calendar.advance(days)
      events.each do |kind, snap|
        @finance.on_calendar_event(kind, [snap[:year], snap[:month], snap[:day]])
      end
      events
    end

    def to_h
      h = { schema_version: SCHEMA_VERSION, calendar: @calendar.to_h, finance: @finance.to_h }
      h[:world] = @world if @world
      h[:player_club] = @player_club if @player_club
      h
    end

    def self.from_h(h)
      version = h[:schema_version] || 0
      raise ArgumentError, "unknown FM state schema #{version}" if version > SCHEMA_VERSION
      s = new(calendar: Calendar.from_h(h[:calendar]), finance: Finance.from_h(h[:finance]), world: h[:world])
      s.player_club = h[:player_club]
      s
    end
  end
end
