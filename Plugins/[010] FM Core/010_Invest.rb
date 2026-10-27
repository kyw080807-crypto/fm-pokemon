#===============================================================================
# FM::Invest — what an AI club builds next, decided every Monday. Pure Ruby.
# Follows Poké Manager's AI (gym leaders train first, others scout first; a
# step only when funds exceed 1.5x its cost; medical trails training at 4x;
# stadium grows when home games sell out) within the design's limits
# (building cap and plots from the clubhouse, clubhouse from city size and
# fame, one project at a time, build time in weeks).
#===============================================================================
module FM
  module Invest
    RESERVE_WEEKS = 20     # original aiBudget keeps 20 weeks of running costs
    MARGIN        = 1.5
    MEDICAL_MARGIN = 4.0
    SELLOUT       = 0.92

    module_function

    def decide(club, date:, calendar:)
      return if club.project
      spare = club.spare
      return if spare <= 0
      choice = stadium_step(club, spare) || building_step(club, spare) || clubhouse_step(club, spare)
      return unless choice
      start(club, choice, date: date, calendar: calendar)
    end

    # Pays for a step and starts building it. choice = [kind, target, from, cost].
    def start(club, choice, date:, calendar:)
      kind, target, from, cost = choice
      raise ArgumentError, "already building" if club.project
      raise Finance::InsufficientFunds, "need #{cost}" if club.wallet.balance < cost
      club.wallet.record(-cost, category: :invest, date: date, memo: "#{target} #{from}->#{from + 1}")
      done = calendar.date_after(date, 7 * Build.build_weeks(kind, from))
      club.project = { kind: kind, target: target, to: from + 1, done: done }
    end

    # Every step the rules allow right now, cheapest first, regardless of the
    # AI's money margins (for the player's own decisions).
    def options(club)
      out = []
      unless club.stadium_shared || club.stadium >= Build::STADIUM_COST.size
        out << [:stadium, :STADIUM, club.stadium, Build.stadium_cost(club.stadium)]
      end
      cap = Build.building_cap(club.clubhouse)
      Build::CLUB_BUILDINGS.each { |b| (st = step_for(club, b, cap)) && out << st }
      next_lv = club.clubhouse + 1
      if next_lv <= Build.clubhouse_max(club.city_size) && club.fame >= Build.clubhouse_fame(next_lv)
        out << [:clubhouse, :CLUBHOUSE, club.clubhouse, Build.clubhouse_cost(club.clubhouse)]
      end
      out.sort_by(&:last)
    end

    def stadium_step(club, spare)
      return if club.stadium_shared || club.stadium >= Build::STADIUM_COST.size
      return if club.home_fill.size < 5 || club.home_fill.sum / club.home_fill.size < SELLOUT
      cost = Build.stadium_cost(club.stadium)
      [:stadium, :STADIUM, club.stadium, cost] if spare > cost * MARGIN
    end

    def building_step(club, spare)
      cap = Build.building_cap(club.clubhouse)
      order = club.role.start_with?("G") ? %i[TRAINING SCOUTING] : %i[SCOUTING TRAINING]
      order.each do |b|
        step = step_for(club, b, cap)
        return step if step && spare > step.last * MARGIN
      end
      med = step_for(club, :MEDICAL, cap)
      return med if med && club.facilities.fetch(:MEDICAL, 0) < club.facilities.fetch(:TRAINING, 0) &&
                    spare > med.last * MEDICAL_MARGIN
      nil
    end

    # [:building, name, current level, cost] if it can go up one level.
    def step_for(club, building, cap)
      lv = club.facilities.fetch(building, 0)
      return if lv >= cap
      return if lv.zero? && club.facilities.size >= Build.club_plots(club.clubhouse)
      [:building, building, lv, Build.building_cost(lv)]
    end

    # Worth it once the core buildings have hit the clubhouse's cap or the
    # plots are full.
    def clubhouse_step(club, spare)
      next_lv = club.clubhouse + 1
      return if next_lv > Build.clubhouse_max(club.city_size) || club.fame < Build.clubhouse_fame(next_lv)
      cap = Build.building_cap(club.clubhouse)
      capped = %i[TRAINING SCOUTING].all? { |b| club.facilities.fetch(b, 0) >= cap } ||
               club.facilities.size >= Build.club_plots(club.clubhouse)
      return unless capped
      cost = Build.clubhouse_cost(club.clubhouse)
      [:clubhouse, :CLUBHOUSE, club.clubhouse, cost] if spare > cost * MARGIN
    end
  end
end
