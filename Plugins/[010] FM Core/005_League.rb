#===============================================================================
# FM::League — one region's league: 20-club double round robin (38 rounds)
# and its table. Pure Ruby. Mirrors Poké Manager's makeLeague()/standings():
# circle-method fixtures from a shuffled club order, home/away alternating by
# round, the second half the first with home and away swapped; 3 points for a
# win, 1 for a draw; ties broken by KO difference, then KOs for, then id.
#===============================================================================
module FM
  class League
    SCHEMA_VERSION = 1
    WIN_POINTS     = 3
    DRAW_POINTS    = 1

    attr_reader :fixtures, :table, :next_round

    def initialize(club_ids, rng: Random.new)
      raise ArgumentError, "need an even number of clubs" if club_ids.empty? || club_ids.size.odd?
      @fixtures   = self.class.round_robin(club_ids.shuffle(random: rng))
      @table      = club_ids.to_h { |id| [id, self.class.empty_row] }
      @next_round = 0
    end

    def self.empty_row
      { p: 0, w: 0, d: 0, l: 0, kf: 0, ka: 0, pts: 0 }
    end

    def self.round_robin(ids)
      n = ids.size
      arr = ids.dup
      first = (0...n - 1).map do |r|
        pairs = (0...n / 2).map { |i| r.even? ? [arr[i], arr[n - 1 - i]] : [arr[n - 1 - i], arr[i]] }
        arr = [arr[0], arr[n - 1], *arr[1...n - 1]]
        pairs
      end
      first + first.map { |round| round.map(&:reverse) }
    end

    def rounds
      @fixtures.size
    end

    def done?
      @next_round >= rounds
    end

    # res: 1 home win, -1 away win, 0 draw.
    def record(home, away, res:, ko_a:, ko_b:)
      a = @table.fetch(home)
      b = @table.fetch(away)
      a[:p] += 1; b[:p] += 1
      a[:kf] += ko_a; a[:ka] += ko_b
      b[:kf] += ko_b; b[:ka] += ko_a
      case res
      when 1  then a[:w] += 1; b[:l] += 1; a[:pts] += WIN_POINTS
      when -1 then b[:w] += 1; a[:l] += 1; b[:pts] += WIN_POINTS
      else         a[:d] += 1; b[:d] += 1; a[:pts] += DRAW_POINTS; b[:pts] += DRAW_POINTS
      end
    end

    # Plays one round; the block resolves a match (home, away) -> result hash.
    # Returns [[home, away, result], ...].
    def play_round(round = @next_round)
      results = @fixtures.fetch(round).map do |home, away|
        r = yield(home, away)
        record(home, away, res: r[:res], ko_a: r[:ko_a], ko_b: r[:ko_b])
        [home, away, r]
      end
      @next_round = round + 1
      results
    end

    def standings
      @table.keys.sort_by do |id|
        r = @table[id]
        [-r[:pts], -(r[:kf] - r[:ka]), -r[:kf], id]
      end
    end

    def position(id)
      standings.index(id) + 1
    end

    def to_h
      { schema_version: SCHEMA_VERSION, fixtures: @fixtures,
        table: @table.transform_values(&:dup), next_round: @next_round }
    end

    def self.from_h(h)
      version = h[:schema_version] || 0
      raise ArgumentError, "unknown league schema #{version}" if version > SCHEMA_VERSION
      league = allocate
      league.instance_variable_set(:@fixtures, h[:fixtures])
      league.instance_variable_set(:@table, h[:table].transform_values(&:dup))
      league.instance_variable_set(:@next_round, h[:next_round])
      league
    end
  end
end
