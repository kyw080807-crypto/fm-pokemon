#===============================================================================
# FM::Meeting — the monthly city meeting (design 02). Pure Ruby. On the 1st of
# each month every ordinary city puts one agenda to its clubs:
#   1. expansion, when a club's clubhouse is held back by the city's size;
#   2. otherwise infrastructure, the next transport/hotel step (Civic.infra_step).
# The city budget pays what it can above its upkeep reserve and the clubs
# split the rest by fame; nothing is tabled that the city and its clubs can't
# pay for. A strict majority passes it; a single-club city simply decides
# (design: 단독 도시는 협의 없이). A failed vote adds to citizens' unrest.
# Capitals are left to the league committee (quarterly, not built yet).
#===============================================================================
module FM
  module Meeting
    module_function

    def monthly(world, date:)
      world.cities.each_value.filter_map do |city|
        next if city.capital? || city.project || city.club_ids.empty?
        members = city.club_ids.map { |id| world.clubs[id] }
        expansion(world, city, members, date) || infrastructure(world, city, members, date) ||
          tax(world, city, members, date)
      end
    end

    # Agenda 3 (design 02 공공 예산 배분과 세율): cut tax when citizens are
    # unhappy, raise it when the budget can't pay for the next public step.
    def tax(world, city, members, date)
      rate = city.tax_rate
      raise_it = if city.satisfaction < Civic::LOW_SATISFACTION && rate > Civic::TAX_RATE_RANGE.min then false
                 elsif rate < Civic::TAX_RATE_RANGE.max && (step = Civic.infra_step(city)) &&
                       city.budget.balance - city.weekly_upkeep * Civic::BUDGET_RESERVE_WEEKS < step[:cost]
                   true
                 end
      return nil if raise_it.nil?
      target = raise_it ? :raise : :lower
      hold(world, city, members, date, agenda: :tax, cost: 0, target: target) do |c, _|
        yes = Vote.tax_yes?(c.traits, raise: raise_it, relation: world.relations.vote_term(c.id, city.club_ids))
        [yes, yes ? nil : (raise_it ? :prefers_team : :no_need)]
      end.tap do |e|
        next unless e && e[:passed]
        delta = raise_it ? Civic::TAX_STEP : -Civic::TAX_STEP
        city.tax_rate = (rate + delta).round(2).clamp(Civic::TAX_RATE_RANGE.min, Civic::TAX_RATE_RANGE.max)
      end
    end

    def blocked?(club, city)
      club.clubhouse >= Build.clubhouse_max(city.size)
    end

    def expansion(world, city, members, date)
      cost = Civic.expansion_cost(city.size) or return nil
      return nil unless members.any? { |c| blocked?(c, city) }
      hold(world, city, members, date, agenda: :expansion, cost: cost) do |c, share|
        v = { traits: c.traits, spare: c.spare, blocked: blocked?(c, city),
              relation: world.relations.vote_term(c.id, city.club_ids) }
        [Vote.expansion_yes?(v, share: share), Vote.expansion_reason(v, share: share)]
      end.tap do |e|
        next unless e && e[:passed]
        weeks = Civic::EXPANSION_WEEKS.fetch(city.size)
        city.project = { kind: :expansion, to: city.size + 1, done: world.calendar.date_after(date, 7 * weeks) }
      end
    end

    def infrastructure(world, city, members, date)
      step = Civic.infra_step(city) or return nil
      hold(world, city, members, date, agenda: :infrastructure, cost: step[:cost], target: step[:target]) do |c, share|
        v = { traits: c.traits, spare: c.spare, relation: world.relations.vote_term(c.id, city.club_ids) }
        yes = Vote.infrastructure_yes?(v, share: share)
        reason = if yes then nil
                 elsif c.spare <= share then :no_money
                 elsif c.traits[:civic] < 0 then :prefers_team
                 else :too_expensive
                 end
        [yes, reason]
      end.tap do |e|
        next unless e && e[:passed]
        city.free_plots -= 1 if step[:from].zero?
        city.project = { kind: :building, target: step[:target], to: step[:from] + 1,
                         done: world.calendar.date_after(date, 7 * step[:weeks]) }
      end
    end

    # Funding, votes and payment shared by every agenda. The block gives
    # [yes?, reason] for a club and its share. Returns the meeting event, or
    # nil when the project is unaffordable and so never tabled.
    def hold(world, city, members, date, agenda:, cost:, target: nil)
      available = city.budget.balance - city.weekly_upkeep * Civic::BUDGET_RESERVE_WEEKS
      city_part = available.clamp(0, cost)
      return nil if city_part + members.sum { |c| [c.spare, 0].max } < cost
      shares = split(cost - city_part, members)
      votes = members.to_h do |c|
        yes, reason = yield(c, shares[c.id])
        [c.id, { yes: yes, share: shares[c.id], reason: reason }]
      end
      passed = votes.count { |_, v| v[:yes] } * 2 > members.size
      world.relations.meeting(votes.transform_values { |v| v[:yes] }, passed: passed) if members.size > 1
      if passed
        city.budget.record(-city_part, category: agenda, date: date) if city_part.positive?
        members.each do |c|
          s = shares[c.id]
          c.wallet.record(-s, category: :city, date: date, memo: "#{agenda} #{city.id}") if s.positive?
        end
      else
        city.vote_failed
      end
      { kind: :meeting, agenda: agenda, target: target, city: city.id, date: date, cost: cost,
        city_part: city_part, passed: passed, votes: votes }
    end

    # Split by fame; rounding leftovers go to the most famous club.
    def split(amount, members)
      total = members.sum(&:fame)
      shares = members.to_h { |c| [c.id, (amount * c.fame / total).floor] }
      top = members.max_by(&:fame)
      shares[top.id] += amount - shares.values.sum
      shares
    end
  end
end
