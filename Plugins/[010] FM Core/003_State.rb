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
    attr_reader :player_club   # club id the player manages; nil until chosen
    # Design 06 기본값 설정: how the player's matches are played unless the
    # match is important (then always asked). :ask, :direct, :auto, :skip.
    MATCH_MODES = %i[ask direct auto skip].freeze
    attr_writer :match_mode, :match_fast
    def match_mode = @match_mode || :ask
    # 속도 옵션: battle animations off in FM battles.
    def match_fast = @match_fast || false

    def player_club=(id)
      @player_club = id
      @world.player_club = id if @world
    end

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
    # A dismissed manager (FM::Credit :dismissed) no longer has a club.
    def advance_days(days)
      if @world
        events = @world.advance_days(days)
        self.player_club = nil if @player_club && events.any? { |e| e[:kind] == :dismissed && e[:club] == @player_club }
        return events
      end
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
      h[:match_mode] = @match_mode if @match_mode
      h[:match_fast] = @match_fast if @match_fast
      h
    end

    def self.from_h(h)
      version = h[:schema_version] || 0
      raise ArgumentError, "unknown FM state schema #{version}" if version > SCHEMA_VERSION
      s = new(calendar: Calendar.from_h(h[:calendar]), finance: Finance.from_h(h[:finance]), world: h[:world])
      s.player_club = h[:player_club]
      s.match_mode = h[:match_mode]   # absent in older saves: default :ask
      s.match_fast = h[:match_fast]
      s
    end
  end
end
