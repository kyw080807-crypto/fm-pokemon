#===============================================================================
# FM::Meeting — the monthly city meeting (design 02). Pure Ruby. On the 1st of
# each month every ordinary city puts one agenda to its clubs:
#   1. expansion, when a club's clubhouse is held back by the city's size;
#   2. otherwise infrastructure, the next transport/hotel step (Civic.infra_step).
# The city budget pays what it can above its upkeep reserve and the clubs
# split the rest by fame; nothing is tabled that the city and its clubs can't
# pay for. A strict majority passes it; a single-club city simply decides
# (design: 단독 도시는 협의 없이). A failed vote adds to citizens' unrest.
# Capitals are left to the league committee (FM::Committee).
#
# The player (design 02 플레이어는 대화 선택지로 설득한다): when their club
# sits at the table, Meeting.player_hook gets a Proposal and answers with
# a decision: vote yes/no after taking on `extra` of the other clubs'
# shares (the AI votes are re-evaluated on the new shares), or pay the
# whole club part (전액 부담: passes without a vote; relations and fame
# reward the contribution). A club may also petition the next meeting's
# agenda (petition / petition_options); otherwise the agenda is chosen as
# above.
#
# 대가 제안 (design 02): the player can offer one club something for its
# yes, which adds to that club's vote score; it is carried out only if
# that club ends up voting yes:
#   :loan    — lend it one of the player's mons for World::LOAN_WEEKS
#              (worth more if the mon would make its top three);
#   :support — promise to vote yes at the city's next meeting
#              (World#promises: kept warms the pair, broken cools it and
#              the player's standing with the whole table);
#   :favor   — ask on good relations (우호, 0.2+): the relation itself is
#              the bonus, and FAVOR_COST of it is spent.
#===============================================================================
module FM
  module Meeting
    FULL_PAY_RELATION = 0.08     # with every other club at the table
    FULL_PAY_FAME_PER = 50_000   # +1 fame per this much paid...
    FULL_PAY_FAME_MAX = 6        # ...at most
    OFFER_LOAN = 0.4             # vote-score bonus for a loan...
    OFFER_LOAN_TOP3 = 1.0        # ...of a mon that would play for them
    OFFER_SUPPORT = 0.3
    FAVOR_MIN = 0.2
    FAVOR_COST = 0.1
    PROMISE_KEPT = 0.05
    PROMISE_BROKEN = -0.15       # with the club promised...
    PROMISE_BROKEN_TABLE = -0.05 # ...and with every other club at the table

    # What the player hook is given. evaluate.(extra, offers = []) ->
    # [shares, votes] with the player paying `extra` more, taken from the
    # others pro rata, and these offers ({ club:, kind:, mon: }) made.
    Proposal = Struct.new(:city, :agenda, :target, :cost, :city_part, :members, :player, :evaluate, :full_cost,
                          keyword_init: true)

    class << self
      # hook.(Proposal) -> { vote: true/false, extra: Integer, offers: [...] } / { full: true } / nil (AI votes)
      attr_accessor :player_hook
    end

    module_function

    def monthly(world, date:)
      world.cities.each_value.filter_map do |city|
        next if city.capital? || city.project || city.club_ids.empty?
        members = city.club_ids.map { |id| world.clubs[id] }
        if (pt = city.petition)
          city.petition = nil
          e = case pt[:agenda]
              when :expansion then expansion(world, city, members, date, forced: true)
              when :infrastructure then infrastructure(world, city, members, date, only: pt[:target])
              when :tax then tax(world, city, members, date, want: pt[:target])
              end
          next e.merge(petition: pt[:by]) if e
        end
        expansion(world, city, members, date) || infrastructure(world, city, members, date) ||
          tax(world, city, members, date)
      end
    end

    # Agendas a club can put to its city's next meeting: what the city
    # could table now (cost known; tax respects the cooldown).
    def petition_options(world, city)
      return [] if city.capital? || city.project
      out = []
      if (cost = Civic.expansion_cost(city.size))
        out << { agenda: :expansion, target: nil, cost: cost }
      end
      Civic::INFRA.each do |b|
        step = Civic.infra_step(city, only: b) or next
        out << { agenda: :infrastructure, target: b, cost: step[:cost], from: step[:from] }
      end
      cooled = city.tax_changed.nil? ||
               world.calendar.days_between(city.tax_changed, world.calendar.date) >= Civic::TAX_COOLDOWN_DAYS
      if cooled
        out << { agenda: :tax, target: :raise, cost: 0 } if city.tax_rate < Civic::TAX_RATE_RANGE.max
        out << { agenda: :tax, target: :lower, cost: 0 } if city.tax_rate > Civic::TAX_RATE_RANGE.min
      end
      out
    end

    def petition(city, option, by:)
      city.petition = { agenda: option[:agenda], target: option[:target], by: by }
    end

    # Vote-score bonus an offer gives `club`; 0 when it can't be made.
    def offer_bonus(world, me, club, offer)
      case offer[:kind]
      when :loan
        mon = offer[:mon]
        return 0.0 unless mon && me.squad.include?(mon) && !mon.out?
        third = club.lineup[2]
        third.nil? || mon.rating * mon.strength_mul > third.rating * third.strength_mul ? OFFER_LOAN_TOP3 : OFFER_LOAN
      when :support then OFFER_SUPPORT
      when :favor
        r = world.relations.get(me.id, club.id)
        r >= FAVOR_MIN ? r : 0.0
      else 0.0
      end
    end

    def bonuses(world, me, offers)
      (offers || []).each_with_object(Hash.new(0.0)) do |o, h|
        h[o[:club].id] += offer_bonus(world, me, o[:club], o)
      end
    end

    # Offers to clubs that voted yes are carried out.
    def carry_out(world, me, city, offers, votes, date)
      (offers || []).filter_map do |o|
        c = o[:club]
        next unless votes[c.id] && votes[c.id][:yes] && offer_bonus(world, me, c, o).positive?
        case o[:kind]
        when :loan then world.loan(o[:mon], from: me, to: c)
        when :support then world.promises << { by: me.id, to: c.id, city: city.id, kind: :support, made: date }
        when :favor then world.relations.change(me.id, c.id, -FAVOR_COST)
        end
        { club: c.id, kind: o[:kind], species: o[:mon]&.species }
      end
    end

    # The player's promises to vote yes at this city's next meeting.
    def settle_promises(world, me, city, members, yes, date)
      due, rest = world.promises.partition { |pr| pr[:by] == me.id && pr[:city] == city.id && pr[:made] != date }
      world.promises.replace(rest)
      due.map do |pr|
        if yes
          world.relations.change(me.id, pr[:to], PROMISE_KEPT)
        else
          world.relations.change(me.id, pr[:to], PROMISE_BROKEN)
          members.each { |c| world.relations.change(me.id, c.id, PROMISE_BROKEN_TABLE) unless c.id == pr[:to] }
        end
        { to: pr[:to], kept: yes }
      end
    end

    # Agenda 3 (design 02 공공 예산 배분과 세율): cut tax when citizens are
    # unhappy, raise it when the budget can't pay for the next public step.
    def tax(world, city, members, date, want: nil)
      rate = city.tax_rate
      if city.tax_changed && world.calendar.days_between(city.tax_changed, date) < Civic::TAX_COOLDOWN_DAYS
        return nil
      end
      raise_it = if want then want == :raise
                 elsif city.satisfaction < Civic::LOW_SATISFACTION && rate > Civic::TAX_RATE_RANGE.min then false
                 elsif rate < Civic::TAX_RATE_RANGE.max && (step = Civic.infra_step(city)) &&
                       city.budget.balance - city.weekly_upkeep * Civic::BUDGET_RESERVE_WEEKS < step[:cost]
                   true
                 end
      return nil if raise_it.nil?
      target = raise_it ? :raise : :lower
      hold(world, city, members, date, agenda: :tax, cost: 0, target: target) do |c, _, bonus|
        yes = Vote.tax_yes?(c.traits, raise: raise_it,
                                      relation: world.relations.vote_term(c.id, city.club_ids) + bonus.to_f)
        [yes, yes ? nil : (raise_it ? :prefers_team : :no_need)]
      end.tap do |e|
        next unless e && e[:passed]
        delta = raise_it ? Civic::TAX_STEP : -Civic::TAX_STEP
        city.tax_rate = (rate + delta).round(2).clamp(Civic::TAX_RATE_RANGE.min, Civic::TAX_RATE_RANGE.max)
        city.tax_changed = date
      end
    end

    def blocked?(club, city)
      club.clubhouse >= Build.clubhouse_max(city.size)
    end

    def expansion(world, city, members, date, forced: false)
      cost = Civic.expansion_cost(city.size) or return nil
      return nil unless forced || members.any? { |c| blocked?(c, city) }
      hold(world, city, members, date, agenda: :expansion, cost: cost) do |c, share, bonus|
        v = { traits: c.traits, spare: c.spare, blocked: blocked?(c, city),
              relation: world.relations.vote_term(c.id, city.club_ids) + bonus.to_f }
        [Vote.expansion_yes?(v, share: share), Vote.expansion_reason(v, share: share)]
      end.tap do |e|
        next unless e && e[:passed]
        weeks = Civic::EXPANSION_WEEKS.fetch(city.size)
        city.project = { kind: :expansion, to: city.size + 1, done: world.calendar.date_after(date, 7 * weeks) }
      end
    end

    def infrastructure(world, city, members, date, only: nil)
      step = Civic.infra_step(city, only: only) or return nil
      hold(world, city, members, date, agenda: :infrastructure, cost: step[:cost], target: step[:target]) do |c, share, bonus|
        v = { traits: c.traits, spare: c.spare, relation: world.relations.vote_term(c.id, city.club_ids) + bonus.to_f }
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
    def hold(world, city, members, date, agenda:, cost:, target: nil, &vote)
      available = city.budget.balance - city.weekly_upkeep * Civic::BUDGET_RESERVE_WEEKS
      city_part = available.clamp(0, cost)
      return nil if city_part + members.sum { |c| [c.spare, 0].max } < cost
      base = split(cost - city_part, members)
      ballot = lambda do |sh, bonus = {}|
        members.to_h do |c|
          yes, reason = vote.call(c, sh[c.id], bonus.fetch(c.id, 0.0))
          [c.id, { yes: yes, share: sh[c.id], reason: reason }]
        end
      end
      me = world.player_club && members.find { |c| c.id == world.player_club }
      decision = nil
      if me && player_hook
        evaluate = lambda do |extra, offers = []|
          sh = shift(base, me, extra)
          [sh, ballot.call(sh, bonuses(world, me, offers))]
        end
        decision = player_hook.call(Proposal.new(city: city, agenda: agenda, target: target, cost: cost,
                                                 city_part: city_part, members: members, player: me,
                                                 evaluate: evaluate, full_cost: cost - city_part))
      end
      full = decision && decision[:full]
      if full
        shares = members.to_h { |c| [c.id, c.equal?(me) ? cost - city_part : 0] }
        votes = { me.id => { yes: true, share: shares[me.id], reason: nil } }
        passed = true
        (members - [me]).each { |c| world.relations.change(me.id, c.id, FULL_PAY_RELATION) }
        me.fame = Economy.add_fame(me.fame, [shares[me.id] / FULL_PAY_FAME_PER, FULL_PAY_FAME_MAX].min)
      else
        shares = decision ? shift(base, me, decision[:extra].to_i) : base
        offers = decision && decision[:offers]
        votes = ballot.call(shares, me ? bonuses(world, me, offers) : {})
        votes[me.id] = votes[me.id].merge(yes: decision[:vote] ? true : false, reason: nil) if decision
        passed = votes.count { |_, v| v[:yes] } * 2 > members.size
        world.relations.meeting(votes.transform_values { |v| v[:yes] }, passed: passed) if members.size > 1
        deals = me ? carry_out(world, me, city, offers, votes, date) : []
      end
      promises = me ? settle_promises(world, me, city, members, votes[me.id][:yes], date) : []
      if passed
        city.budget.record(-city_part, category: agenda, date: date) if city_part.positive?
        members.each do |c|
          s = shares[c.id]
          c.wallet.record(-s, category: :city, date: date, memo: "#{agenda} #{city.id}") if s.positive?
        end
      else
        city.vote_failed
      end
      city.record({ kind: :meeting, agenda: agenda, target: target, city: city.id, date: date, cost: cost,
                    city_part: city_part, passed: passed, votes: votes, full: full ? me.id : nil,
                    deals: deals || [], promises: promises })
    end

    # The player takes `extra` more (capped at the others' total), taken
    # from the others in proportion to their shares.
    def shift(shares, me, extra)
      others = shares.reject { |id, _| id == me.id }
      pool = others.values.sum
      extra = extra.to_i.clamp(0, pool)
      return shares if extra.zero?
      out = others.to_h { |id, s| [id, s - (extra * s / pool.to_f).floor] }
      out[me.id] = shares[me.id] + (pool - out.values.sum)
      out
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
