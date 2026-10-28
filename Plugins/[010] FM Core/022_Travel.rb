#===============================================================================
# FM::Travel — what a trip costs a club (design 05 교통과 원정, 이동 규칙,
# 공항과 해외 이동). Pure Ruby. A trip is { days:, cond:, fat:, cost: }:
# - Over land, days and fare follow the departing city's transport level
#   (same city: nothing); each land day costs condition 2 and hidden
#   fatigue 3. The AI arrives the day before a match: another -3 / +2.
# - Abroad (tournaments in another region), clubs go over land to their
#   region's capital, then fly: 800 + 900 a flight day, and condition /
#   fatigue by flight days (FLIGHT_FATIGUE). Capital to capital is the
#   design's table of real flight times between the motif regions.
# Travel days are days without training (Club#travel, Growth.week).
#===============================================================================
module FM
  module Travel
    LAND_COST = [300, 400, 500, 700, 1000, 1400].freeze   # by transport level 0-5
    LAND_COND_PER_DAY = 2
    LAND_FAT_PER_DAY = 3
    ARRIVE_BEFORE_COND = 3
    ARRIVE_BEFORE_FAT = 2
    FLIGHT_BASE = 800
    FLIGHT_PER_DAY = 900
    FLIGHT_FATIGUE = { 1 => [2, 2], 2 => [4, 5], 3 => [6, 8] }.freeze   # days => [cond, fat]

    REGIONS = %w[KANTO JOHTO HOENN SINNOH UNOVA KALOS ALOLA GALAR PALDEA].freeze
    FLIGHT_DAYS = [
      [0, 1, 1, 1, 3, 3, 2, 3, 3],
      [1, 0, 1, 1, 3, 3, 2, 3, 3],
      [1, 1, 0, 1, 3, 3, 2, 3, 3],
      [1, 1, 1, 0, 3, 3, 2, 3, 3],
      [3, 3, 3, 3, 0, 2, 2, 2, 2],
      [3, 3, 3, 3, 2, 0, 3, 1, 1],
      [2, 2, 2, 2, 2, 3, 0, 3, 3],
      [3, 3, 3, 3, 2, 1, 3, 0, 1],
      [3, 3, 3, 3, 2, 1, 3, 1, 0]
    ].freeze

    NONE = { days: 0, cond: 0, fat: 0, cost: 0 }.freeze

    module_function

    def flight_days(a, b)
      i, j = REGIONS.index(a), REGIONS.index(b)
      i && j ? FLIGHT_DAYS[i][j] : 0
    end

    # From one city to another in the same region.
    def land(from, to, arrive_before: true)
      return NONE if from.nil? || to.nil? || from.id == to.id
      days = Civic::TRANSPORT_DAYS[from.transport]
      early = arrive_before && days.positive?
      { days: days, cond: days * LAND_COND_PER_DAY + (early ? ARRIVE_BEFORE_COND : 0),
        fat: days * LAND_FAT_PER_DAY + (early ? ARRIVE_BEFORE_FAT : 0), cost: LAND_COST[from.transport] }
    end

    def flight(from_region, to_region)
      days = flight_days(from_region, to_region)
      return NONE if days.zero?
      cond, fat = FLIGHT_FATIGUE.fetch(days)
      { days: days, cond: cond, fat: fat, cost: FLIGHT_BASE + FLIGHT_PER_DAY * days }
    end

    def sum(*trips)
      trips.each_with_object(NONE.dup) { |t, s| t.each { |k, v| s[k] += v } }
    end

    # To a tournament in `host` region (its games are at the capital):
    # over land to the home capital, then a flight if abroad, arriving the
    # day before. `capital` = { region => City }.
    def to_cup(city, region, host, capital)
      land_leg = land(city, capital[region], arrive_before: false)
      fly = flight(region, host)
      trip = sum(land_leg, fly)
      return trip if trip[:days].zero?
      trip.merge(cond: trip[:cond] + ARRIVE_BEFORE_COND, fat: trip[:fat] + ARRIVE_BEFORE_FAT)
    end
  end
end
