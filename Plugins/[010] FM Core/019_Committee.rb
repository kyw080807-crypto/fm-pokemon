#===============================================================================
# FM::Committee — each region's league committee, which runs its capital
# (design 09 리그 관리위원회 / 수도 전용 시설). Pure Ruby.
#
# Members: the capital's clubs + two gym representatives (the two best
# non-capital clubs in last season's league). Quarterly meeting (Jan, Apr,
# Jul, Oct 1st): one agenda, majority of members, the chair decides a tie.
# Budget: the capital city's own budget (the design: the capital uses the
# committee budget instead of a public budget) — tax, upkeep and the capital
# clubs' gate contributions already flow there; on top come every region
# club's league dues (by fame) and income from the league HQ.
# Capital-only facilities start at the design's levels. Effects so far: the
# side stadium is the capital clubs' league stadium, the broadcast center
# pays every club in the region, the HQ adds committee income. Hub (travel)
# and hall of fame have no effect yet. Money figures are drafts.
#===============================================================================
module FM
  class Committee
    START = { SIDE_STADIUM: 6, LEAGUE_HQ: 6, HUB: 4, BROADCAST: 4, HALL_OF_FAME: 2 }.freeze   # (design levels x2)
    MAX_LEVEL = 10
    DUES_PER_FAME = 10              # ₽ per fame point per week (draft)
    HQ_INCOME_PER_LEVEL = 750       # ₽ per week (draft: broadcast rights, league sponsors)
    BROADCAST_PER_LEVEL = 75        # ₽ per club per week (draft)
    COST_MUL = 4.0                  # x club building step cost (draft)
    QUARTER_MONTHS = [1, 4, 7, 10].freeze
    GYM_SEATS = 2

    attr_reader :region, :city_id, :facilities, :gym_reps

    LOG_SIZE = 12

    # Recent meetings, newest first (for screens). Older saves start empty.
    def log = (@log ||= [])

    def record(event)
      log.unshift(event)
      log.pop while log.size > LOG_SIZE
      event
    end
    attr_accessor :project
    attr_accessor :fac_age   # FM::Aging

    def initialize(region:, city_id:)
      @region = region
      @city_id = city_id
      @facilities = START.dup
      @gym_reps = []
      @project = nil
    end

    def city(world) = world.cities.fetch(@city_id)

    # The capital clubs' stadium level (0-6) for a side stadium level (0-10).
    def self.stadium_of(level) = Civic.tier(level)

    def members(world)
      city(world).club_ids + @gym_reps
    end

    def region_clubs(world)
      world.clubs.values.select { |c| c.region == @region }
    end

    def weekly(world, date)
      budget = city(world).budget
      region_clubs(world).each do |c|
        dues = (c.fame * DUES_PER_FAME).round
        c.wallet.record(-dues, category: :dues, date: date)
        budget.record(dues, category: :dues, date: date)
        bc = @facilities[:BROADCAST] * BROADCAST_PER_LEVEL
        c.wallet.record(bc, category: :broadcast, date: date)
      end
      budget.record(@facilities[:LEAGUE_HQ] * HQ_INCOME_PER_LEVEL, category: :league_hq, date: date)
      t = Hof.tourism(self)
      budget.record(t, category: :tourism, date: date) if t.positive?
    end

    # The next step: the side stadium first (design: its upgrade is the
    # committee's first long-term agenda), then the lowest facility; the
    # capital's hotel counts too (its public buildings are the committee's).
    def next_step(world)
      cands = @facilities.filter_map do |f, lv|
        next if lv >= MAX_LEVEL
        cost = Aging.step_cost((Build.building_cost(lv) * COST_MUL).round, @fac_age&.dig(f), lv + 1)
        { target: f, from: lv, cost: cost, weeks: Build.build_weeks(:building, lv),
          kind: :facility }
      end
      hotel = Civic.infra_step(city(world))
      cands << hotel.merge(kind: :city) if hotel
      side = cands.find { |c| c[:target] == :SIDE_STADIUM }
      side || cands.min_by { |c| [c[:from], c[:cost]] }
    end

    def quarterly(world, date)
      return nil if @project
      step = next_step(world) or return nil
      c = city(world)
      available = c.budget.balance - c.weekly_upkeep * Civic::BUDGET_RESERVE_WEEKS
      return nil if available < step[:cost]
      ids = members(world).uniq
      votes = ids.to_h do |id|
        club = world.clubs[id]
        [id, Vote.infrastructure_yes?({ traits: club.traits, spare: club.spare,
                                         relation: world.relations.vote_term(id, ids) }, share: 0)]
      end
      yes = votes.values.count(true)
      passed = yes * 2 > ids.size || (yes * 2 == ids.size)   # tie: the chair decides, and backs the agenda
      world.relations.meeting(votes, passed: passed) if ids.size > 1
      if passed
        c.budget.record(-step[:cost], category: :committee, date: date)
        @project = step.merge(to: step[:from] + 1, done: world.calendar.date_after(date, 7 * step[:weeks]))
      end
      record({ kind: :committee, region: @region, target: step[:target], cost: step[:cost], passed: passed,
               votes: votes, date: date })
    end

    def finish(world, date)
      p = @project or return nil
      return nil if world.calendar.days_until(p[:done]).positive?
      @project = nil
      if p[:kind] == :city
        b = city(world).buildings.find { |x, *| x == p[:target] }
        b ? b[1] = p[:to] : city(world).buildings << [p[:target], p[:to]]
        Aging.built(city(world), p[:target], p[:to])
      else
        @facilities[p[:target]] = p[:to]
        Aging.built(self, p[:target], p[:to])
        if p[:target] == :SIDE_STADIUM
          city(world).club_ids.each { |id| world.clubs[id].stadium = Committee.stadium_of(p[:to]) }
        end
      end
      { kind: :committee_built, region: @region, what: p[:target], level: p[:to], date: date }
    end

    # Gym representatives for next season: the best non-capital finishers.
    def seat_gym_reps(world, standings)
      capital = city(world).club_ids
      @gym_reps = standings.reject { |id| capital.include?(id) }.first(GYM_SEATS)
    end

    # Design 04 균형 장치: at the end of the league, the committee hands part
    # of its surplus to the bottom half of the table, more to the lower
    # places. Surplus = budget above a year of upkeep plus the next step.
    DISTRIBUTION_SHARE = 0.5        # draft
    def distribute(world, standings, date)
      c = city(world)
      step = next_step(world)
      reserve = c.weekly_upkeep * 52 + (step ? step[:cost] : 0)
      pot = ((c.budget.balance - reserve) * DISTRIBUTION_SHARE).floor
      return nil unless pot.positive?
      bottom = standings.last(standings.size / 2)
      weights = bottom.each_index.map { |i| i + 1 }          # last place gets the most
      total = weights.sum
      paid = 0
      bottom.each_with_index do |id, i|
        amount = pot * weights[i] / total
        next unless amount.positive?
        world.clubs[id].wallet.record(amount, category: :distribution, date: date)
        paid += amount
      end
      return nil unless paid.positive?
      c.budget.record(-paid, category: :distribution, date: date)
      { kind: :distribution, region: @region, amount: paid, date: date }
    end
  end
end
