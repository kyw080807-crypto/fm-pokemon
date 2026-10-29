#===============================================================================
# FM::Aging — 시설 노후화 (Poké Manager: FAC_LIFE, FAC_WARN, RENOV, facA,
# facEsc, renovCost, renovFac, facAgeWeek). Pure Ruby.
# - The original ages only a club's training ground and scouting office at
#   Lv10. Here (2026-10-29, user: 전 레벨에 걸쳐 노후화, 높을수록 빨리) every
#   facility ages at every level: club buildings, a city's transport and
#   hotel, the league committee's capital facilities. A level lasts
#   life(lv) weeks, 260 at Lv1 down to the original's 130 at Lv10, then
#   drops one level, unless renovated first (35% of the step into that
#   level, x the escalation), which starts the clock again. Each renovation
#   or drop raises the escalation by 25%, to x2; rebuilding a lost level
#   costs its step x the escalation. A new level starts a fresh clock.
# - AI clubs renovate in the last 13 weeks if they can afford three times
#   the bill plus 10 weeks' costs; the player is warned WARN weeks before.
#   Cities and committees renovate from the city budget in the last 13
#   weeks if it keeps its reserve (Civic::BUDGET_RESERVE_WEEKS of upkeep).
# - A building that drops from Lv1 stands at Lv0: it keeps its plot, has
#   no effect or upkeep, and is rebuilt for the usual first step.
#===============================================================================
module FM
  module Aging
    LIFE_LOW = 260      # weeks at Lv1
    LIFE = 130          # weeks at Lv10 (the original's FAC_LIFE)
    WARN_LEAD = 52      # the player hears this many weeks before a drop
    RENOV = 0.35
    AI_LEAD = 13
    CLUB = Build::CLUB_BUILDINGS
    CITY = Civic::INFRA

    module_function

    def life(level) = (LIFE_LOW - (level.to_i.clamp(1, 10) - 1) * (LIFE_LOW - LIFE) / 9.0).round
    def esc(age) = [2.0, 1 + 0.25 * age[:n]].min

    # The step into `level` (Build.building_cost(level - 1)) x `mul`.
    def renov_cost(age, level, mul = 1.0)
      (Build.building_cost(level - 1) * mul * RENOV * esc(age) / 1000.0).round * 1000
    end

    # Cost of the step to `to`: x the escalation when it rebuilds a lost level.
    def step_cost(base, age, to = nil)
      return base unless age && age[:n].positive? && (to.nil? || to <= age[:top].to_i)
      (base * esc(age) / 1000.0).round * 1000
    end

    def age(holder, building) = (holder.fac_age ||= {})[building] ||= { w: 0, n: 0, top: 0 }

    # A facility reached a new level: a fresh clock.
    def built(holder, building, level)
      a = age(holder, building)
      a[:w] = 0
      a[:top] = [a[:top].to_i, level].max
    end

    def renovate(club, building, date:)
      lv = club.facilities[building].to_i
      return false if lv < 1
      a = age(club, building)
      cost = renov_cost(a, lv)
      return false if club.wallet.balance < cost
      club.wallet.record(-cost, category: :invest, date: date, memo: "renovate #{building}")
      a[:w] = 0
      a[:n] += 1
      true
    end

    # One week of wear on a facility at `lv`; yields to decide renovating in
    # the last AI_LEAD weeks. -> :renovated, :warn, :aged or nil
    def wear(a, lv)
      a[:w] += 1
      left = life(lv) - a[:w]
      return :renovated if left < AI_LEAD && yield
      return :warn if left == WARN_LEAD
      return unless left <= 0
      a[:w] = 0
      a[:n] += 1
      a[:top] = [a[:top].to_i, lv].max
      :aged
    end

    def renewed(a)
      a[:w] = 0
      a[:n] += 1
    end

    # facAgeWeek for one club -> events
    def club_week(world, club)
      date = world.calendar.date
      ai = world.ai?(club)
      CLUB.filter_map do |b|
        lv = club.facilities[b].to_i
        next if lv < 1 || (club.project && club.project[:target] == b)
        a = age(club, b)
        r = wear(a, lv) { ai && club.wallet.balance > renov_cost(a, lv) * 3 + club.weekly_cost * 10 }
        case r
        when :renovated
          renovate(club, b, date: date)
          nil
        when :warn
          { kind: :aging_warning, club: club.id, what: b, level: lv, weeks: WARN_LEAD, cost: renov_cost(a, lv), date: date }
        when :aged
          club.facilities[b] = lv - 1
          club.coaches.drop(Coach.slots(club)).each { |m| m.coach = false } if b == :TRAINING
          { kind: :aged, club: club.id, what: b, level: lv - 1,
            cost: step_cost(Build.building_cost(lv - 1), a, lv), date: date }
        end
      end
    end

    # Money a city budget can spend and keep its reserve.
    def city_spare(city) = city.budget.balance - city.weekly_upkeep * Civic::BUDGET_RESERVE_WEEKS

    # A city's transport and hotel (a capital's too: the committee's
    # budget is the city's) -> events
    def city_week(world, city)
      date = world.calendar.date
      CITY.filter_map do |b|
        lv = city.level(b)
        next if lv < 1 || (city.project && city.project[:target] == b)
        a = age(city, b)
        cost = renov_cost(a, lv)
        case wear(a, lv) { city_spare(city) > cost }
        when :renovated
          city.budget.record(-cost, category: :renovate, date: date)
          renewed(a)
          nil
        when :aged
          city.buildings.find { |x, l, *| x == b && l == lv }[1] = lv - 1
          { kind: :city_aged, city: city.id, what: b, level: lv - 1, date: date }
        end
      end
    end

    # The committee's capital facilities, paid from the capital's budget at
    # the committee's cost multiplier -> events
    def committee_week(world, cm)
      date = world.calendar.date
      city = cm.city(world)
      cm.facilities.keys.filter_map do |f|
        lv = cm.facilities[f].to_i
        next if lv < 1 || (cm.project && cm.project[:target] == f)
        a = age(cm, f)
        cost = renov_cost(a, lv, Committee::COST_MUL)
        case wear(a, lv) { city_spare(city) > cost }
        when :renovated
          city.budget.record(-cost, category: :renovate, date: date)
          renewed(a)
          nil
        when :aged
          cm.facilities[f] = lv - 1
          if f == :SIDE_STADIUM
            city.club_ids.each { |id| world.clubs[id].stadium = Committee.stadium_of(lv - 1) }
          end
          { kind: :committee_aged, region: cm.region, what: f, level: lv - 1, date: date }
        end
      end
    end
  end
end
