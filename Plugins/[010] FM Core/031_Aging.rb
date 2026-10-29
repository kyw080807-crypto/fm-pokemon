#===============================================================================
# FM::Aging — 시설 노후화 (Poké Manager: FAC_LIFE, FAC_WARN, RENOV, facA,
# facEsc, renovCost, renovFac, facAgeWeek). Pure Ruby.
# - A club's training ground or scouting office at the top level (design
#   Lv5 = the original's Lv10) wears out: after LIFE weeks it drops a
#   level, unless renovated first (35% of the original's last step, x the
#   escalation), which starts the clock again. Each renovation or rebuild
#   raises the escalation by 25%, to x2; a rebuild after a drop costs the
#   original's last step (9 -> 10) x the escalation, as a drop there loses
#   one original level. The AI renovates in the last 13 weeks if it
#   can afford three times the bill plus 10 weeks' costs; the player is
#   warned WARN weeks in.
# - Our levels pair the original's, so a drop is Lv5 -> Lv4 (the original
#   loses one of its ten).
# Only club buildings age, as in the original. (Ageing the league
# committee's capital facilities too was tried: in 20-year runs the
# committee kept rebuilding and the clubs' median balance halved.)
#===============================================================================
module FM
  module Aging
    LIFE = 130
    WARN = LIFE - 52
    RENOV = 0.35
    AI_LEAD = 13
    BUILDINGS = %i[TRAINING SCOUTING].freeze
    TOP = 5

    module_function

    def esc(age) = [2.0, 1 + 0.25 * age[:n]].min
    def renov_cost(age) = (Build.up_cost(9) * RENOV * esc(age) / 1000.0).round * 1000

    # Lv4 -> Lv5 once it has dropped (facCost at 9): the original's last
    # step x the escalation; else `base`.
    def step_cost(base, age)
      age && age[:n].positive? ? (Build.up_cost(9) * esc(age) / 1000.0).round * 1000 : base
    end

    def age(holder, building) = (holder.fac_age ||= {})[building] ||= { w: 0, n: 0 }

    def renovate(club, building, date:)
      a = age(club, building)
      cost = renov_cost(a)
      return false if club.facilities[building].to_i < TOP || club.wallet.balance < cost
      club.wallet.record(-cost, category: :invest, date: date, memo: "renovate #{building}")
      a[:w] = 0
      a[:n] += 1
      true
    end

    # facAgeWeek for one club -> events
    def club_week(world, club)
      date = world.calendar.date
      BUILDINGS.filter_map do |b|
        next unless club.facilities[b].to_i >= TOP
        a = age(club, b)
        a[:w] += 1
        if world.ai?(club) && a[:w] >= LIFE - AI_LEAD &&
           club.wallet.balance > renov_cost(a) * 3 + club.weekly_cost * 10
          renovate(club, b, date: date)
          next
        end
        next { kind: :aging_warning, club: club.id, what: b, weeks: LIFE - a[:w], cost: renov_cost(a), date: date } if a[:w] == WARN
        next unless a[:w] >= LIFE
        club.facilities[b] = TOP - 1
        a[:w] = 0
        a[:n] += 1
        if b == :TRAINING
          club.coaches.drop(Coach.slots(club)).each { |m| m.coach = false }
        end
        { kind: :aged, club: club.id, what: b, cost: step_cost(Build.building_cost(TOP - 1), a), date: date }
      end
    end
  end
end
