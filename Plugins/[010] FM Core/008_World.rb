#===============================================================================
# FM::World — every club and regional league, advanced one day at a time.
# Pure Ruby. On a league date each region plays its next round: results from
# FM::MatchSim, gate money to the home club, win/draw bonuses, fame changes
# (Poké Manager playRound). When a league ends: prize money, rebuild aid and
# fame by position (finalizeLeague). January 1 starts new leagues.
#
# Club data comes in as plain hashes (tools/sim reads PBS/fm_clubs.txt; the
# game will read compiled GameData), each with :pokemon as
# [{bst:, level:, stars:}].
#===============================================================================
module FM
  class Club
    attr_reader :id, :name, :region, :city, :role, :canon, :level, :potential,
                :facilities, :mon_ratings, :rating, :wallet, :form, :city_size, :stadium_shared,
                :home_fill
    attr_accessor :fame, :stadium, :clubhouse, :project

    def initialize(data)
      @id, @name, @region, @city = data.values_at(:id, :name, :region, :city)
      @role, @canon, @level, @potential = data.values_at(:role, :canon, :level, :potential)
      @stadium = data[:stadium]
      @stadium_shared = data.fetch(:stadium_shared, false)
      @clubhouse = data.fetch(:clubhouse, 1)
      @city_size = data.fetch(:city_size, 1)
      @facilities  = (data[:facilities] || {}).dup
      @project   = nil   # { kind:, target:, to:, done: [y, m, d] }
      @home_fill = []    # attendance / capacity, last 5 home games
      @mon_ratings = data[:pokemon].map { |m| Rating.mon(m) }
      @rating  = Rating.team(data[:pokemon])
      @fame    = Economy.initial_fame(level: @level, role: @role, canon: @canon)
      @wallet  = Finance.new(balance: Economy.start_funds(@fame))
      @form    = []
    end

    def push_form(result)
      @form << result
      @form.shift while @form.size > 5
    end

    def recent_wins
      @form.empty? ? 2 : @form.count(:w)   # demand() assumes 2 without a table
    end

    def push_fill(ratio)
      @home_fill << ratio
      @home_fill.shift while @home_fill.size > 5
    end

    def weekly_cost
      @mon_ratings.sum { |r| Economy.food(ovr: Economy.ovr(r), fame: @fame) } +
        @facilities.values.sum { |lv| Economy.facility_keep(lv) } + Economy.stadium_keep(@stadium)
    end
  end

  class World
    attr_reader :calendar, :clubs, :leagues

    def self.new_game(club_data, seed:)
      new(club_data.map { |d| Club.new(d) }, seed: seed)
    end

    def initialize(clubs, seed:)
      @calendar = Calendar.new
      @clubs    = clubs.to_h { |c| [c.id, c] }
      @rng      = Random.new(seed)
      @league_dates = {}
      start_leagues
    end

    def regions
      @clubs.values.map(&:region).uniq
    end

    def advance_days(days)
      Array.new(days) { advance_day }.flatten
    end

    # Moves to the next day and plays whatever happens on it.
    def advance_day
      events = []
      @calendar.advance(1).each do |kind, _|
        case kind
        when :new_year
          start_leagues
          events << { kind: :new_year, year: @calendar.year }
        when :new_week
          weekly_economy
          events.concat(finish_projects)
          @clubs.each_value { |c| Invest.decide(c, date: date, calendar: @calendar) }
        end
      end
      round = league_dates.index(@calendar.date)
      if round
        @leagues.each do |region, league|
          next if league.done? || league.next_round != round
          events << play_league_round(region, league)
          events << finish_league(region, league) if league.done?
        end
      end
      events
    end

    private

    def league_dates
      @league_dates[@calendar.year] ||= Season.league_dates(@calendar, @calendar.year)
    end

    def start_leagues
      @leagues = regions.to_h do |region|
        ids = @clubs.values.select { |c| c.region == region }.map(&:id)
        [region, League.new(ids, rng: @rng)]
      end
    end

    def date
      @calendar.date
    end

    def play_league_round(region, league)
      round = league.next_round
      before = league.standings
      # Early on the table means little; rank by strength instead (original).
      ranking = round < 3 ? before.sort_by { |id| -@clubs[id].rating } : before
      results = league.play_round do |home_id, away_id|
        home, away = @clubs[home_id], @clubs[away_id]
        gate = Economy.gate(home_fame: home.fame, away_fame: away.fame, wins: home.recent_wins,
                            stadium: home.stadium, rng: @rng)
        home.wallet.record(gate[:revenue], category: :gate, date: date) if gate[:revenue].positive?
        home.push_fill(gate[:attendance].fdiv(Economy.capacity(home.stadium)))
        r = MatchSim.play(home.rating, away.rating, rng: @rng)
        settle(r, home, away, ranking)
        r.merge(attendance: gate[:attendance])
      end
      { kind: :league_round, region: region, round: round + 1, date: date, results: results }
    end

    def settle(r, home, away, ranking)
      if r[:res].zero?
        [home, away].each do |c|
          c.wallet.record(Economy::DRAW_BONUS, category: :bonus, date: date)
          c.push_form(:d)
        end
        return
      end
      winner, loser = r[:res].positive? ? [home, away] : [away, home]
      gap = [ranking.index(winner.id) - ranking.index(loser.id), 0].max
      winner.wallet.record(Economy::WIN_BONUS + gap * Economy::UPSET_PER_RANK, category: :bonus, date: date)
      upset = loser.fame > winner.fame + 15 ? 0.25 : 0
      winner.fame = Economy.add_fame(winner.fame, 0.4 + upset)
      loser.fame  = Economy.add_fame(loser.fame, -0.15)
      winner.push_form(:w)
      loser.push_form(:l)
    end

    # Poké Manager econWeek, every Monday: interest, food, building and
    # stadium upkeep out; merchandise in. Sponsors wait for the design's
    # contract system.
    def weekly_economy
      @clubs.each_value do |c|
        w = c.wallet
        interest = Economy.debt_interest(w.balance)
        w.record(-interest, category: :interest, date: date) if interest.positive?
        food = c.mon_ratings.sum { |r| Economy.food(ovr: Economy.ovr(r), fame: c.fame) }
        w.record(-food, category: :food, date: date) if food.positive?
        keep = c.facilities.values.sum { |lv| Economy.facility_keep(lv) }
        w.record(-keep, category: :fac, date: date) if keep.positive?
        w.record(-Economy.stadium_keep(c.stadium), category: :std, date: date)
        merch = Economy.merch(c.fame)
        w.record(merch, category: :merch, date: date) if merch.positive?
      end
    end

    def finish_projects
      @clubs.each_value.filter_map do |c|
        p = c.project
        next unless p && @calendar.days_until(p[:done]) <= 0
        case p[:kind]
        when :building  then c.facilities[p[:target]] = p[:to]
        when :clubhouse then c.clubhouse = p[:to]
        when :stadium   then c.stadium = p[:to]
        end
        c.project = nil
        { kind: :built, club: c.id, what: p[:target], level: p[:to], date: date }
      end
    end

    def finish_league(region, league)
      standings = league.standings
      standings.each_with_index do |id, i|
        pos = i + 1
        c = @clubs[id]
        c.wallet.record(Economy.league_prize(pos), category: :prize, date: date)
        aid = Economy.rebuild_aid(pos)
        c.wallet.record(aid, category: :aid, date: date) if aid.positive?
        c.fame = Economy.add_fame(c.fame, (11 - pos) * 0.6 + (pos == 1 ? 5 : 0))
      end
      { kind: :league_end, region: region, date: date, standings: standings }
    end
  end
end
