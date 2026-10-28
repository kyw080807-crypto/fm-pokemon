#===============================================================================
# FM::Civic, FM::City, FM::Traits, FM::Vote — cities, their public budget and
# the monthly meeting that decides expansion (design 01, 02, 04). Pure Ruby.
#
# The design gives the size table (plots, building cap, expansion multipliers
# x1 / x2.5 / x6) and the vote formula; population, tax, base cost, build time,
# contribution rate and starting budget are first guesses (EXPANSION_BASE etc.)
# to tune with headless runs. Only the expansion agenda exists so far.
#===============================================================================
module FM
  module Civic
    POPULATION   = [5_000, 15_000, 40_000, 100_000, 100_000].freeze   # by size (draft)
    PUBLIC_PLOTS = [4, 6, 8, 10, 12].freeze                             # design 01
    PUBLIC_CAP   = [2, 3, 4, 5, 5].freeze                               # design 01
    TAX_PER_HEAD = 0.25         # ₽ per resident per week (draft; 0.5 left budgets at a ₽20M median after 20 years)
    EXPANSION_BASE = 1_000_000  # draft
    EXPANSION_MUL  = { 1 => 1.0, 2 => 2.5, 3 => 6.0 }.freeze           # design 01: to sizes 2/3/4
    EXPANSION_WEEKS = { 1 => 8, 2 => 12, 3 => 16 }.freeze              # draft
    CONTRIBUTION_RATE = 0.05    # share of each home gate paid into the city budget (draft)
    START_BUDGET_WEEKS = 26     # a new game's budget = half a year of tax (draft)
    # The budget pays as much of a project as it can while keeping this many
    # weeks of public upkeep; clubs split the rest. (A 50% cap left budgets
    # idle and clubs short: 53 of 17,279 meetings passed in a 20-year run.)
    BUDGET_RESERVE_WEEKS = 26

    # Tax rate and satisfaction (design 04; numbers are drafts).
    TAX_RATE_RANGE = (0.5..1.5).freeze
    TAX_STEP = 0.1
    SATISFACTION_START = 60.0
    SATISFACTION_BASE = 60.0       # where satisfaction settles at the normal rate
    SATISFACTION_PER_TAX = 50.0    # x1.2 tax -> settles 10 lower
    SATISFACTION_DRIFT = 0.05      # share of the gap closed each week
    FAILED_VOTE_HIT = 2.0
    LOW_SATISFACTION = 40.0
    TAX_COOLDOWN_DAYS = 182        # at most one tax change per half year (draft)

    # Design 05, by transport level 0-5 (0 = no transport building).
    TRANSPORT_DAYS = [3, 2, 2, 1, 1, 0].freeze
    FAN_FACTOR     = [0.4, 0.6, 0.8, 1.0, 1.2, 1.4].freeze
    SAME_CITY_D    = 1.3
    SAME_REGION_D  = 1.0
    # Design 05, by hotel level 0-5 (0 = the inn every city has).
    HOTEL_CAP      = [400, 800, 1500, 2500, 4000, 6000].freeze
    LODGE_SPEND    = 4      # ₽ per lodging fan per night, to the host city budget

    module_function

    # Share of away fans who must stay the night, by one-way trip days.
    def lodge_share(days) = days >= 2 ? 1.0 : days == 1 ? 0.6 : 0.3

    # Away fans for a league game (design 05 팬 이동과 입장 수입):
    # fame x 25 x L, L = T (the lower transport of the two cities) x D, at
    # most the away section; those who must lodge are capped by the host's
    # hotel. Same region only (league games); D for flights comes with travel.
    def away_fans(away_fame:, from:, to:, capacity:)
      same = from.id == to.id
      t = FAN_FACTOR[[from.transport, to.transport].min]
      base = Economy.fame_eff(away_fame) * 25 * t * (same ? SAME_CITY_D : SAME_REGION_D)
      base = [base, capacity * Economy::AWAY_SECTION].min
      days = same ? 0 : TRANSPORT_DAYS[from.transport]
      wanting = base * lodge_share(days)
      lodging = [wanting, HOTEL_CAP[to.hotel]].min
      { fans: base - wanting + lodging, lodging: lodging }
    end

    # Infrastructure the meeting can build: those with an effect so far.
    INFRA = %i[TRANSPORT HOTEL].freeze
    CAPITAL_ONLY_LEVEL = { TRANSPORT: 5 }.freeze   # design 05: Lv5 (airport) needs size 5

    # Next public building step for a city, or nil: the lowest of INFRA
    # (transport first on a tie), under the size's public cap, a free plot
    # for a new one. Cost and weeks follow club buildings (draft).
    def infra_step(city)
      cap = public_cap(city.size)
      steps = INFRA.filter_map do |b|
        lv = city.level(b)
        next if lv >= cap
        next if CAPITAL_ONLY_LEVEL[b] && lv + 1 >= CAPITAL_ONLY_LEVEL[b] && city.size < 5
        next if lv.zero? && city.free_plots < 1   # a new building takes a plot (the inn is free)
        { target: b, from: lv, cost: Build.building_cost(lv), weeks: Build.build_weeks(:building, lv) }
      end
      steps.min_by { |s| [s[:from], INFRA.index(s[:target])] }
    end

    def population(size)  = POPULATION.fetch(size - 1)
    def public_plots(size) = PUBLIC_PLOTS.fetch(size - 1)
    def public_cap(size)  = PUBLIC_CAP.fetch(size - 1)
    def weekly_tax(size)  = (population(size) * TAX_PER_HEAD).round

    # Cost of growing from `size` to size + 1; nil when ordinary cities can't.
    def expansion_cost(size)
      mul = EXPANSION_MUL[size] or return nil
      (EXPANSION_BASE * mul).round
    end
  end

  class City
    attr_reader :id, :name, :region, :form, :budget, :buildings, :club_ids
    attr_accessor :size, :free_plots, :project, :unrest
    attr_writer :tax_rate, :satisfaction
    attr_accessor :tax_changed   # date of the last tax change, nil if never

    # Defaults cover cities saved before these existed.
    def tax_rate = @tax_rate || 1.0
    def satisfaction = @satisfaction || Civic::SATISFACTION_START

    # Weekly drift toward the level the tax rate allows (design 04: higher
    # tax, lower satisfaction).
    def drift_satisfaction
      target = Civic::SATISFACTION_BASE - (tax_rate - 1.0) * Civic::SATISFACTION_PER_TAX
      @satisfaction = (satisfaction + (target - satisfaction) * Civic::SATISFACTION_DRIFT).clamp(0.0, 100.0)
    end

    # A failed vote leaves citizens unhappy (design 02: 방치하면 시민 불만).
    def vote_failed
      @unrest += 1
      @satisfaction = (satisfaction - Civic::FAILED_VOTE_HIT).clamp(0.0, 100.0)
    end

    # Home crowds scale with satisfaction: 0.85 at 0, 1.0 at 50, 1.15 at 100 (draft).
    def crowd_mood = 0.85 + 0.3 * satisfaction / 100.0

    LOG_SIZE = 12

    # Recent meetings, newest first (for screens). Older saves start empty.
    def log = (@log ||= [])

    def record(event)
      log.unshift(event)
      log.pop while log.size > LOG_SIZE
      event
    end

    def initialize(data)
      @id, @name, @region, @form = data.values_at(:id, :name, :region, :form)
      @size       = data[:size]
      @free_plots = data.fetch(:free_plots, 0)
      @buildings  = (data[:buildings] || []).map(&:dup)
      @budget     = Finance.new(balance: Civic.weekly_tax(@size) * Civic::START_BUDGET_WEEKS)
      @club_ids   = []
      @project    = nil
      @unrest     = 0
    end

    def capital? = @form == "LEAGUE"

    def level(building)
      @buildings.select { |b, *| b == building }.map { |_, lv, *| lv }.max || 0
    end

    def transport = level(:TRANSPORT)
    def hotel = level(:HOTEL)

    def weekly_upkeep
      @buildings.sum { |_, lv| Economy.facility_keep(lv) }
    end
  end

  # Personality axes, -1..1 (design 02): civic (team-minded -1 .. city-minded
  # +1), commercial (conservative -1 .. commercial +1), cooperative
  # (independent -1 .. cooperative +1), competitive. Generated from role and
  # type plus a fixed per-name variation; hand-tune key people later.
  module Traits
    AXES = %i[civic commercial cooperative competitive].freeze
    ROLE = {
      "C" => { civic: 0.1, commercial: 0.0, cooperative: 0.0, competitive: 0.6 },
      "E" => { civic: 0.0, commercial: 0.0, cooperative: 0.1, competitive: 0.4 },
      "G" => { civic: 0.4, commercial: 0.0, cooperative: 0.2, competitive: 0.1 },
      "T" => { civic: -0.2, commercial: 0.1, cooperative: 0.0, competitive: 0.0 }
    }.freeze
    TYPE = {
      "STEEL" => { commercial: 0.2 }, "ELECTRIC" => { commercial: 0.2 },
      "GRASS" => { cooperative: 0.2 }, "FAIRY" => { cooperative: 0.2 }, "WATER" => { cooperative: 0.1 },
      "DARK" => { cooperative: -0.2 }, "POISON" => { cooperative: -0.2 },
      "FIGHTING" => { competitive: 0.2 }, "DRAGON" => { competitive: 0.2 },
      "GHOST" => { commercial: -0.2 }, "PSYCHIC" => { civic: 0.1 }
    }.freeze

    module_function

    def generate(name:, role:, type:)
      h = fnv1a(name)
      base = ROLE.fetch(role[0])
      AXES.each_with_index.to_h do |axis, i|
        noise = ((h >> (8 * i)) & 0xFF) / 255.0 * 0.6 - 0.3
        v = base[axis] + TYPE.fetch(type, {}).fetch(axis, 0.0) + noise
        [axis, v.clamp(-1.0, 1.0).round(3)]
      end
    end

    # 32-bit FNV-1a: stable across Ruby versions (String#hash is seeded).
    def fnv1a(str)
      str.each_byte.reduce(0x811c9dc5) { |h, b| ((h ^ b) * 0x01000193) & 0xFFFFFFFF }
    end
  end

  # Design 02: yes when trait fit + expected gain - cost share + relation > 0.
  module Vote
    module_function

    def expansion_score(v, share:)
      t = v[:traits]
      fit = 0.5 * t[:civic] + 0.2 * t[:commercial] + 0.2 * t[:cooperative]
      score(fit: fit, gain: v[:blocked] ? 1.0 : 0.3, share: share, spare: v[:spare], relation: v.fetch(:relation, 0.0))
    end

    # Transport and hotels bring away fans and tourism: commercial and
    # city-minded trainers like them (draft weights).
    def infrastructure_yes?(v, share:)
      t = v[:traits]
      fit = 0.3 * t[:civic] + 0.4 * t[:commercial] + 0.2 * t[:cooperative]
      score(fit: fit, gain: 0.5, share: share, spare: v[:spare], relation: v.fetch(:relation, 0.0)).positive?
    end

    # Raising tax funds the city but cools crowds; lowering it the reverse.
    # City-minded, cooperative trainers back raises; commercial ones back cuts
    # (draft weights).
    def tax_yes?(traits, raise:, relation: 0.0)
      t = traits
      score = if raise then 0.1 + 0.4 * t[:civic] + 0.2 * t[:cooperative] - 0.3 * t[:commercial]
              else 0.2 + 0.3 * t[:commercial] - 0.2 * t[:civic]
              end
      (score + relation).positive?
    end

    def score(fit:, gain:, share:, spare:, relation:)
      cost = if share.zero? then 0.0
             elsif spare <= 0 then 3.0
             else [share * 2.0 / spare, 3.0].min
             end
      fit + gain - cost + relation
    end

    def expansion_yes?(v, share:)
      expansion_score(v, share: share).positive?
    end

    # Why a club says no, for the dialogue line.
    def expansion_reason(v, share:)
      return nil if expansion_yes?(v, share: share)
      t = v[:traits]
      if v[:spare] <= share then :no_money
      elsif t[:civic] < 0 then :prefers_team
      elsif !v[:blocked] then :no_need
      else :too_expensive
      end
    end
  end
end
