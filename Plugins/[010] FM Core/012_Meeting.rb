#===============================================================================
# FM::Meeting — the monthly city meeting (design 02). Pure Ruby. On the 1st of
# each month every ordinary city whose clubs are held back by its size (a
# clubhouse already at size + 1) votes on expanding. The city budget pays up
# to Civic::CITY_SHARE of the cost and the clubs split the rest by fame. A
# strict majority passes it; a single-club city simply decides. A failed vote
# adds to citizens' unrest. Capitals are left to the league committee
# (quarterly, not built yet) and are already at the top size.
#===============================================================================
module FM
  module Meeting
    module_function

    def monthly(world, date:)
      world.cities.each_value.filter_map do |city|
        next if city.capital? || city.project || city.club_ids.empty?
        cost = Civic.expansion_cost(city.size) or next
        members = city.club_ids.map { |id| world.clubs[id] }
        next unless members.any? { |c| blocked?(c, city) }
        expansion(world, city, members, cost, date)   # nil when unaffordable
      end
    end

    def blocked?(club, city)
      club.clubhouse >= Build.clubhouse_max(city.size)
    end

    def expansion(world, city, members, cost, date)
      available = city.budget.balance - city.weekly_upkeep * Civic::BUDGET_RESERVE_WEEKS
      city_part = available.clamp(0, cost)
      # Nobody tables a project the city and its clubs can't pay for at all.
      return nil if city_part + members.sum { |c| [c.spare, 0].max } < cost
      shares = split(cost - city_part, members)
      votes = members.to_h do |c|
        v = { traits: c.traits, spare: c.spare, blocked: blocked?(c, city), relation: 0.0 }
        [c.id, { yes: Vote.expansion_yes?(v, share: shares[c.id]), share: shares[c.id],
                 reason: Vote.expansion_reason(v, share: shares[c.id]) }]
      end
      passed = votes.count { |_, v| v[:yes] } * 2 > members.size
      if passed
        city.budget.record(-city_part, category: :expansion, date: date) if city_part.positive?
        members.each do |c|
          s = shares[c.id]
          c.wallet.record(-s, category: :city, date: date, memo: "expand #{city.id}") if s.positive?
        end
        weeks = Civic::EXPANSION_WEEKS.fetch(city.size)
        city.project = { kind: :expansion, to: city.size + 1, done: world.calendar.date_after(date, 7 * weeks) }
      else
        city.unrest += 1
      end
      { kind: :meeting, agenda: :expansion, city: city.id, date: date, cost: cost,
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
