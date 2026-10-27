#===============================================================================
# FM::Build — rules for clubhouses, club buildings and stadiums (design 01,
# costs from Poké Manager). Pure Ruby.
#
# Club buildings (TRAINING, MEDICAL, SCOUTING, DAYCARE, SHOP) use design
# levels 1-5; each spans two of Poké Manager's 1-10 levels, so a step costs
# two of its upCost steps. Clubhouse cost and all build times are not in the
# design doc yet: first guesses, tune by headless runs.
#===============================================================================
module FM
  module Build
    CLUB_BUILDINGS = %i[TRAINING MEDICAL SCOUTING DAYCARE SHOP].freeze
    # Index = clubhouse level - 1 (design 01, 클럽하우스 단계별 효과).
    CLUB_PLOTS     = [3, 4, 4, 5, 6].freeze
    BUILDING_CAP   = [2, 3, 4, 5, 5].freeze
    SQUAD_SIZE     = [8, 9, 10, 11, 12].freeze
    CLUBHOUSE_FAME = [0, 30, 45, 60, 75].freeze
    CLUBHOUSE_COST_MUL = 2.0     # draft: a clubhouse step costs 2x a building step
    STADIUM_COST = [400_000, 500_000, 900_000, 1_500_000, 2_500_000, 4_000_000].freeze   # to Lv1..Lv6
    STADIUM_WEEKS = 8            # draft

    module_function

    def club_plots(clubhouse)     = CLUB_PLOTS.fetch(clubhouse - 1)
    def building_cap(clubhouse)   = BUILDING_CAP.fetch(clubhouse - 1)
    def squad_size(clubhouse)     = SQUAD_SIZE.fetch(clubhouse - 1)
    def clubhouse_fame(level)     = CLUBHOUSE_FAME.fetch(level - 1)
    # Design: clubhouse up to city size + 1, max 5.
    def clubhouse_max(city_size)  = [city_size + 1, 5].min

    # Poké Manager upCost: original level lv -> lv + 1.
    def up_cost(lv)
      (8000 * lv**1.8 / 1000.0).round * 1000
    end

    # Design level -> level + 1 (0 = build new).
    def building_cost(level)
      up_cost(2 * level) + up_cost(2 * level + 1)
    end

    def clubhouse_cost(level)
      (building_cost(level) * CLUBHOUSE_COST_MUL).round
    end

    # From stadium level (0 = rental) to the next.
    def stadium_cost(level)
      STADIUM_COST.fetch(level)
    end

    # Weeks to go from `level` to level + 1. Draft: buildings level + 1,
    # clubhouse twice that, stadium a flat STADIUM_WEEKS.
    def build_weeks(kind, level)
      case kind
      when :building  then level + 1
      when :clubhouse then 2 * (level + 1)
      when :stadium   then STADIUM_WEEKS
      end
    end
  end
end
