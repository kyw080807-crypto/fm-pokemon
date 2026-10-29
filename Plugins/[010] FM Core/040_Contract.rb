#===============================================================================
# FM::Contract — 스폰서 계약 2.0 (Poké Manager: SP2_LEN, SP2_AMB, SP2_LENMUL,
# SP2_SIGN, SP2_IMP, SP2_POOL, SP2_FOCUS_KIND / _ID, sp2Offer, sp2Terms,
# sp2Make, sp2Exps, sp2Season, sp2Now, sp2SatAdd, sp2Quit, sp2Bridge,
# sp2Match, sponBuzz, sp2Review, sp2Eval, sp2RenewOffer, sp2NewYear*,
# sp2AutoPick, sp2Penalty, sp2PlayerQuit). Pure Ruby; texts are the UI's.
# - An offer is signed for 1-3 seasons (a shop 1-2) at a target level
#   (low / normal / high): longer adds base +5% / +10% and a signing fee
#   of 8% / 15% of it, the amount fixed for the contract; higher targets
#   pay base +15% and bonuses +45% but ask more and swing satisfaction.
# - Each season 2-3 expectations by the sponsor's kind (or company):
#   league place, a PWT place, fame, fans, home attendance, buzz stories,
#   weeks in debt; key / normal / bonus, sharing the season's bonus pool.
#   The AI has the league place one only.
# - Satisfaction 0-100 (60): league results, a review every 4 rounds
#   from round 8, buzz, debt; a warning under 30, the sponsor leaves under
#   15 (not during the first season), and a season ending at 50+ in the
#   last contract year brings a better renewal offer. A STRICT sponsor
#   whose key expectation fails leaves at once (and for two seasons).
#   RISKY: 13th or lower after round 19, it leaves.
# - The player picks among the offers before the league (the renewal,
#   else a STABLE one, is taken at the first round), may break a
#   contract in the preseason for 25% of the base left, and gets a
#   stopgap local sponsor (base x0.6, no expectations) when one leaves.
# - BUZZ sponsors pay ₽8,000 a buzz story. Buzz stories here are our big
#   events (a title, the KO king, the season's riser, a gym leader's first
#   top 4, an upset win): the original counts its news items.
#===============================================================================
module FM
  module Contract
    LEN = { "BIG" => [1, 3], "LOCAL" => [1, 3], "SHOP" => [1, 2] }.freeze
    AMB = {
      -1 => { base: 0.88, bon: 0.7, pos: 2, fame: -2, fans: -5, att: -0.08, buzz: -1, debt: 2, sat: 0.75 },
      0 => { base: 1.0, bon: 1.0, pos: 0, fame: 0, fans: 0, att: 0.0, buzz: 0, debt: 0, sat: 1.0 },
      1 => { base: 1.15, bon: 1.45, pos: -2, fame: 3, fans: 5, att: 0.08, buzz: 2, debt: -2, sat: 1.3 }
    }.freeze
    LEN_MUL = { 1 => 1.0, 2 => 1.05, 3 => 1.1 }.freeze
    SIGN = { 1 => 0.0, 2 => 0.08, 3 => 0.15 }.freeze
    IMP = { k: { w: 3, ok: 12, ng: -18, mon: 1.5 }, n: { w: 2, ok: 7, ng: -8, mon: 1 },
            b: { w: 1.5, ok: 5, ng: 0, mon: 0.5 } }.freeze
    POOL = { "STABLE" => 0.12, "PERF" => 1.3, "STRICT" => 0.9, "FAME" => 0.3, "BUZZ" => 0.3, "SHOP" => 0.2,
             "RISKY" => 0.2 }.freeze
    FOCUS_KIND = { "STABLE" => [%i[pos n], %i[debt n]], "PERF" => [%i[pos k], %i[pwt b]],
                   "STRICT" => [%i[pos k], %i[pwt k], %i[debt n]], "FAME" => [%i[fame k], %i[pos n]],
                   "BUZZ" => [%i[buzz k], %i[pos n]], "SHOP" => [%i[att k], %i[fans n]],
                   "RISKY" => [%i[pos k], %i[debt n]] }.freeze
    FOCUS_ID = { "FANCLUB" => [%i[fans k], %i[pos b]], "SAFARI" => [%i[buzz k], %i[att n]],
                 "MUSICAL" => [%i[buzz k], %i[fans n]], "JOINAVE" => [%i[fans n], %i[att n]],
                 "HOLO" => [%i[buzz n], %i[pos n]], "AETHER" => [%i[fame k], %i[fans n]],
                 "MC_BANK" => [%i[pos k], %i[debt k]], "SILPH" => [%i[pos n], %i[fame n], %i[pwt b]],
                 "LUMIOSE" => [%i[att k], %i[fame n]], "MC_AIR" => [%i[pos n], %i[fame b]],
                 "RADIO" => [%i[buzz k], %i[fame n]], "POKEWOOD" => [%i[buzz k], %i[fame n]],
                 "SUBWAY" => [%i[pos k], %i[buzz b]], "POKETCH" => [%i[pos n], %i[fans b]] }.freeze
    SAT_START = 60
    SAT_WARN = 30
    SAT_QUIT = 15
    SAT_RENEW = 50
    BUZZ_PAY = 8000
    PENALTY = 0.25
    BRIDGE_MUL = 0.6
    RISKY_ROUND = 19
    RISKY_POS = 13
    FAME_MAX = 300
    BUZZ_KINDS = %i[league_champion ko_king first_top4 riser pwt_hof cup_champion].freeze

    module_function

    def r(x) = (x / 1000.0).round * 1000
    def amb(a) = AMB.fetch(a.to_i.clamp(-1, 1))
    def v2?(s) = s && s[:v] == 2
    def track?(s) = v2?(s) && !s[:sat].nil?

    # sp2Offer: the negotiation defaults.
    def offer(o)
      o = o.dup
      o[:base0] ||= o[:base]
      o[:lens] = o[:bridge] ? [1, 1] : LEN.fetch(o[:tier], [1, 2])
      o[:len] = (o[:tier] == "BIG" ? 2 : 1).clamp(*o[:lens]) unless o[:len]&.between?(*o[:lens])
      o[:amb] ||= 0
      o
    end

    # sp2Terms -> { base:, sign:, pool: }
    def terms(o, len, a)
      return { base: o[:base], sign: 0, pool: 0 } if o[:bridge]
      b0 = o[:base0] || o[:base]
      { base: r(b0 * amb(a)[:base] * LEN_MUL.fetch(len, 1.0)), sign: r(b0 * SIGN.fetch(len, 0)),
        pool: r(b0 * POOL.fetch(o[:kind], 0.2) * amb(a)[:bon]) }
    end

    def region_size(world, club) = world.clubs.values.count { |c| c.region == club.region }

    # sp2Proj: as the season goal.
    def proj(world, club)
      g = club.goal
      return g[:t] if g && g[:year] == world.calendar.year && g[:region] == club.region
      prev = club.history.dig(world.calendar.year - 1, :pos)
      ovr = Goals.strength_rank(world, club)
      (prev ? prev * 0.5 + ovr * 0.5 : ovr).round
    end

    # sp2Make -> { k:, imp:, t:, ... } or nil
    def make(world, club, k, imp, o, a)
      am = amb(a)
      n = [region_size(world, club), 2].max
      pj = proj(world, club)
      q = ((n - pj) / [1.0, n - 1].max).clamp(0.0, 1.0)
      case k
      when :pos
        t = pj + (o[:kind] == "STABLE" ? 2 : o[:kind] == "STRICT" ? -1 : 0) + (o[:tier] == "BIG" ? -1 : 0) + am[:pos]
        lo = o[:kind] == "STRICT" || a.to_i == 1 ? 1 : 2
        { k: k, imp: imp, region: club.region, t: t.round.clamp(lo, [lo, n - 2].max) }
      when :pwt
        ps = Tournament.pwt_slots(world.league_coefficients).fetch(club.region, 3)
        pj > ps + 3 ? nil : { k: k, imp: imp, region: club.region, t: ps }
      when :fame
        f0 = club.fame.round
        { k: k, imp: imp, f0: f0, t: (f0 + (16 * q - 3).round + am[:fame]).clamp(15, FAME_MAX) }
      when :fans
        { k: k, imp: imp, t: ([37 + 30 * q, Fans.of(club)].min - 3 + am[:fans]).round.clamp(35, 80) }
      when :att
        cap = Economy.capacity(club.stadium)
        d = Economy.demand(home_fame: club.fame, away_fame: 0, wins: club.recent_wins, capacity: cap, away: 1250) * 1.25
        { k: k, imp: imp, t: [200, ([cap, d].min * (0.85 + am[:att]) / 50).round * 50].max }
      when :buzz then { k: k, imp: imp, t: [1, (0.5 + 3 * q).round + am[:buzz]].max }
      when :debt then { k: k, imp: imp, t: [0, 3 + am[:debt]].max }
      end
    end

    def focus(o) = FOCUS_ID[o[:id].to_s] || FOCUS_KIND[o[:kind]] || [%i[pos n]]

    # sp2Exps
    def exps(world, club, o, a, pool, human:)
      return [] if o[:bridge]
      f = focus(o)
      list = []
      if human
        f.each do |k, imp|
          e = make(world, club, k, imp, o, a)
          next if e.nil? || list.any? { |x| x[:k] == e[:k] }
          p = list.find { |x| x[:k] == :pos }
          next if k == :pwt && p && p[:t] <= e[:t]
          list << e
        end
        if list.size < 2 && (e = make(world, club, list.any? { |x| x[:k] == :fame } ? :fans : :fame, :b, o, a))
          list << e
        end
      else
        pf = f.find { |x| x[0] == :pos }
        list << make(world, club, :pos, pf && pf[1] == :k ? :k : :n, o, a)
      end
      w = list.sum { |e| IMP[e[:imp]][:w] }.nonzero? || 1
      list.each { |e| e[:bonus] = r(pool * IMP[e[:imp]][:w] / w.to_f) }
    end

    # signSponsor (the 2.0 wrapper) -> the contract
    def sign(world, club, o, len: nil, amb: nil)
      o = offer(o)
      len = (len || o[:len]).clamp(*o[:lens])
      a = (amb || o[:amb]).to_i.clamp(-1, 1)
      tm = terms(o, len, a)
      year = world.calendar.year
      old = club.sponsor
      s = o.reject { |k, _| %i[lens renew sat0].include?(k) }
      sat = o[:bridge] ? nil : (o[:renew] ? o[:sat0].to_f.clamp(60, 75) : SAT_START)
      s.merge!(v: 2, len: len, amb: a, since: year, until: year + len - 1, base: tm[:base], bonus: 0, sign: tm[:sign],
               pool: tm[:pool], sat: sat, sat_log: [], evals: o[:renew] && old && old[:evals] ? old[:evals].first(3) : [],
               human: !world.ai?(club))
      club.sponsor = s
      season(world, club, fresh: true)
      club.wallet.record(tm[:sign], category: :spon, date: world.calendar.date) if tm[:sign].positive?
      s
    end

    # sp2Season
    def season(world, club, fresh:)
      s = club.sponsor
      return unless v2?(s)
      year = world.calendar.year
      return if !fresh && s[:exp_y] == year
      s[:sat] = ((s[:sat] + (55 - s[:sat]) * 0.2) * 10).round / 10.0 if !fresh && s[:sat]
      s[:exp_y] = year
      s[:exp] = exps(world, club, s, s[:amb], s[:pool], human: s[:human])
      s[:cnt] = { debt_w: 0, debt_run: 0, buzz: 0 }
      s[:review] = nil
    end

    def progress(world, club)
      lg = world.leagues[club.region]
      return 0.0 unless lg
      (lg.next_round / lg.fixtures.size.to_f).clamp(0.0, 1.0)
    end

    def place(world, club)
      year = world.calendar.year
      h = club.history.dig(year, :pos)
      return h if h
      lg = world.leagues[club.region]
      return nil unless lg && lg.next_round.positive?
      lg.standings.index(club.id) + 1
    end

    # sp2Now -> [:ok / :near / :bad / :wait, the value now]
    def now(world, club, e, fin)
      c = club.sponsor && club.sponsor[:cnt] || {}
      case e[:k]
      when :pos, :pwt
        cur = place(world, club)
        return [:wait, nil] unless cur
        [cur <= e[:t] ? :ok : !fin && cur <= e[:t] + 2 ? :near : :bad, cur]
      when :fame
        cur = club.fame.round
        return [cur >= e[:t] ? :ok : :bad, cur] if fin
        need = e[:f0] + (e[:t] - e[:f0]) * progress(world, club)
        [cur >= e[:t] || cur >= need.round ? :ok : cur >= need - 3 ? :near : :bad, cur]
      when :fans
        cur = Fans.of(club).round
        [cur >= e[:t] ? :ok : !fin && cur >= e[:t] - 5 ? :near : :bad, cur]
      when :att
        att = club.att
        return [fin ? :bad : :wait, nil] unless att && att[:n].positive?
        a = (att[:sum] / att[:n].to_f).round
        [a >= e[:t] ? :ok : !fin && a >= e[:t] * 0.92 ? :near : :bad, a]
      when :buzz
        cur = c[:buzz].to_i
        return [:ok, cur] if cur >= e[:t]
        return [:bad, cur] if fin
        [cur >= (e[:t] * progress(world, club)).floor ? :near : :bad, cur]
      when :debt
        cur = c[:debt_w].to_i
        [cur <= e[:t] ? :ok : :bad, cur]
      else [:wait, nil]
      end
    end

    # sp2SatAdd
    def sat_add(club, d, why, date: nil)
      s = club.sponsor
      return unless track?(s) && !d.zero?
      s[:sat] = ((s[:sat] + d).clamp(0, 100) * 10).round / 10.0
      return unless why && s[:human]
      log = s[:sat_log] ||= []
      if (l = log.first) && l[:why] == why && l[:date] == date
        l[:d] = (l[:d] + d).round(1)
      else
        log.unshift({ why: why, d: d.round(1), date: date })
        log.pop while log.size > 12
      end
    end

    # sp2Quit -> the event
    def quit(world, club, why, fame: 0)
      s = club.sponsor or return
      year = world.calendar.year
      club.fame = Economy.add_fame(club.fame, -fame) if fame.positive?
      club.sponsor_bans[s[:id]] = year + (s[:kind] == "STRICT" ? 2 : 1) unless s[:bridge]
      club.sponsor = nil
      lg = world.leagues[club.region]
      world.sponsor_offers = [bridge(world, club)] if !world.ai?(club) && lg && !lg.done? && world.sponsor_offers.nil?
      { kind: :sponsor_quit, club: club.id, sponsor: s[:id], name: s[:name], why: why, date: world.calendar.date }
    end

    # sp2Bridge
    def bridge(world, club)
      row = { id: :BRIDGE, name: nil, region: club.region, tier: "LOCAL", kind: "STABLE", min_fame: 0 }
      o = Sponsor.deal(row, fame: club.fame)
      base = r(o[:base] * BRIDGE_MUL)
      offer(o.merge(base: base, base0: base, bridge: true))
    end

    # sp2Match: a league result of the player's.
    def match(club, my, date:)
      s = club.sponsor
      return unless track?(s) && s[:human] && !my.zero?
      e = (s[:exp] || []).find { |x| %i[pos pwt].include?(x[:k]) }
      sens = e ? { k: 1.0, n: 0.6, b: 0.35 }.fetch(e[:imp]) : 0.3
      sat_add(club, (my.positive? ? 0.5 : -0.5) * sens * amb(s[:amb])[:sat], my.positive? ? :league_win : :league_loss,
              date: date)
    end

    # sponBuzz (+ the 2.0 wrapper): one a week per club.
    def buzz(world, club)
      s = club.sponsor or return
      wk = world.calendar.date
      return if s[:buzz_w] == wk
      s[:buzz_w] = wk
      club.wallet.record(BUZZ_PAY, category: :spon, date: wk) if s[:kind] == "BUZZ"
      return unless track?(s) && s[:human]
      lg = world.leagues[club.region]
      s[:cnt][:buzz] += 1 if s[:cnt] && lg && !lg.done? && s[:eval_y] != world.calendar.year
      sat_add(club, (s[:exp] || []).any? { |e| e[:k] == :buzz } ? 3 : 1.5, :buzz, date: wk)
    end

    # sp2Review -> events
    def review(world, club, round)
      s = club.sponsor
      return [] unless track?(s) && s[:exp]&.any?
      d = 0.0
      ok = bad = 0
      s[:exp].each do |e|
        st, = now(world, club, e, false)
        i = IMP[e[:imp]]
        if st == :ok
          d += i[:mon]
          ok += 1
        elsif st == :bad
          d -= 1.5 * i[:mon] unless e[:imp] == :b
          bad += 1
        end
      end
      d *= amb(s[:amb])[:sat]
      s[:review] = { round: round, ok: ok, bad: bad, n: s[:exp].size }
      date = world.calendar.date
      sat_add(club, d, :review, date: date)
      year = world.calendar.year
      return [quit(world, club, :low_sat, fame: 3)] if s[:sat] < SAT_QUIT && year > s[:since]
      if s[:sat] < SAT_WARN && s[:warn_y] != year
        s[:warn_y] = year
        return [{ kind: :sponsor_warn, club: club.id, name: s[:name], sat: s[:sat].round, date: date }]
      end
      bad.positive? ? [{ kind: :sponsor_review, club: club.id, name: s[:name], ok: ok, bad: bad, sat: s[:sat].round, date: date }] : []
    end

    # The player's Monday during the league: debt weeks, RISKY, reviews.
    def week(world, club)
      s = club.sponsor
      lg = world.leagues[club.region]
      return [] unless track?(s) && s[:human] && lg && lg.next_round.positive? && !lg.done?
      date = world.calendar.date
      c = s[:cnt]
      out = []
      if club.wallet.balance.negative?
        c[:debt_w] += 1
        c[:debt_run] += 1
        e = s[:exp].find { |x| x[:k] == :debt }
        sat_add(club, e ? (e[:imp] == :k ? -1.5 : -1) : -0.5, :debt, date: date)
        if c[:debt_run] == 4
          sat_add(club, -8, :debt4, date: date)
          return [quit(world, club, :debt4, fame: 3)] if s[:sat] < SAT_QUIT
        end
      else
        c[:debt_run] = 0
      end
      rp = lg.next_round
      if s[:kind] == "RISKY" && rp >= RISKY_ROUND && !s[:risky_done]
        s[:risky_done] = true
        pos = place(world, club)
        return [quit(world, club, :risky, fame: 3)] if pos && pos >= RISKY_POS
      end
      if rp >= 8 && (rp % 4).zero? && s[:review_round] != rp
        s[:review_round] = rp
        out.concat(review(world, club, rp))
      end
      out
    end

    # sp2Eval, when the club's league ends -> events
    def evaluate(world, club, pos)
      s = club.sponsor
      year = world.calendar.year
      return [] unless v2?(s) && s[:eval_y] != year
      s[:eval_y] = year
      club.fame = Economy.add_fame(club.fame, Sponsor::FAME_BONUS) if s[:kind] == "FAME"
      return [] if s[:sat].nil?
      human = s[:human]
      res = (s[:exp] || []).map do |e|
        ok = human ? now(world, club, e, true)[0] == :ok : %i[pos pwt].include?(e[:k]) && pos <= e[:t]
        e[:ok] = ok
        e.slice(:k, :t, :imp, :bonus).merge(ok: ok)
      end
      pay = res.sum { |e| e[:ok] ? e[:bonus].to_i : 0 }
      d = res.sum { |e| e[:ok] ? IMP[e[:imp]][:ok] : IMP[e[:imp]][:ng] } * amb(s[:amb])[:sat]
      date = world.calendar.date
      club.wallet.record(pay, category: :spon, date: date) if pay.positive?
      if human
        sat_add(club, d, :season, date: date)
      else
        s[:sat] = (s[:sat] + d).clamp(0, 100)
      end
      ok_n = res.count { |e| e[:ok] }
      key_fail = res.any? { |e| !e[:ok] && e[:imp] == :k }
      (s[:evals] ||= []).unshift({ year: year, pos: pos, ok: ok_n, n: res.size, pay: pay, sat: s[:sat].round })
      s[:evals].pop while s[:evals].size > 3
      out = []
      out << { kind: :sponsor_eval, club: club.id, name: s[:name], ok: ok_n, n: res.size, pay: pay, sat: s[:sat].round, date: date } if human && res.any?
      return out << quit(world, club, :strict_fail, fame: 2) if s[:kind] == "STRICT" && key_fail
      return out << quit(world, club, :low_sat, fame: 3) if s[:sat] < SAT_QUIT && s[:until] > year
      if s[:until] <= year
        s[:renew_ok] = s[:sat] >= SAT_RENEW
        club.sponsor_bans[s[:id]] = year + 1 unless s[:renew_ok]
        out << { kind: :sponsor_renewal, club: club.id, name: s[:name], yes: s[:renew_ok], sat: s[:sat].round, date: date } if human
      end
      out
    end

    def row_for(world, s) = world.sponsor_table&.find { |x| x[:id] == s[:id] }

    # sp2RenewOffer -> the offer or nil
    def renew_offer(world, club)
      s = club.sponsor
      return unless v2?(s) && s[:renew_ok] && !s[:bridge] && club.sponsor_bans.fetch(s[:id], 0) < world.calendar.year
      row = row_for(world, s) or return
      o = Sponsor.deal(row, fame: club.fame)
      up = 1 + ((s[:sat] - 50) / 200.0).clamp(0.0, 0.25)
      base = r(o[:base] * up)
      offer(o.merge(base: base, base0: base, renew: true, sat0: s[:sat], len: s[:len], amb: s[:amb]))
    end

    def offers_for(world, club)
      Sponsor.offers(world.sponsor_table, region: club.region, fame: club.fame, clubhouse: club.clubhouse,
                                          bans: club.sponsor_bans, year: world.calendar.year, rng: world.rng)
             .map { |o| offer(o) }
    end

    # sp2NewYear: contracts carry on with new expectations; ended ones get
    # offers (the AI signs at once, 1-3 seasons at random).
    def new_year(world)
      year = world.calendar.year
      world.sponsor_offers = nil
      world.clubs.each_value do |c|
        s = c.sponsor
        if v2?(s) && s[:until] >= year
          season(world, c, fresh: false)
          next
        end
        ren = renew_offer(world, c)
        c.sponsor = nil
        if world.ai?(c)
          o = ren || Sponsor.ai_pick(offers_for(world, c))
          sign(world, c, o, len: rand_len(world, offer(o))) if o
        else
          offs = offers_for(world, c)
          offs = ([ren] + offs.reject { |o| o[:id] == ren[:id] }).first(4) if ren
          world.sponsor_offers = offs
        end
      end
    end

    def rand_len(world, o) = (1 + world.rng.rand(3)).clamp(*o[:lens])

    # sp2AutoPick
    def auto_pick(offs)
      offs.find { |o| o[:renew] } || offs.find { |o| o[:kind] == "STABLE" } || offs.first
    end

    # The player signs one of world.sponsor_offers.
    def take(world, club, i, len:, amb:)
      offs = world.sponsor_offers or return
      o = offs[i] or return
      world.sponsor_offers = nil
      sign(world, club, o, len: len, amb: amb)
    end

    def penalty(world, s) = r(s[:base] * [1, s[:until] - world.calendar.year + 1].max * PENALTY)

    # sp2CanQuit
    def can_quit?(world, club)
      s = club.sponsor
      lg = world.leagues[club.region]
      track?(s) && s[:since] < world.calendar.year && lg && lg.next_round.zero? && world.sponsor_offers.nil?
    end

    # sp2PlayerQuit -> the penalty paid or nil
    def player_quit(world, club)
      return unless can_quit?(world, club)
      s = club.sponsor
      pen = penalty(world, s)
      club.wallet.record(-pen, category: :spon, date: world.calendar.date)
      club.sponsor = nil
      world.sponsor_offers = offers_for(world, club)
      pen
    end

    # Saves from before 2.0: an AI contract becomes a one-season 2.0 one.
    def fix(world, club)
      s = club.sponsor
      return if s.nil? || v2?(s) || !world.ai?(club)
      o = offer(s)
      club.sponsor = s.merge(v: 2, len: 1, amb: 0, since: world.calendar.year, until: world.calendar.year, sign: 0,
                             pool: r(o[:base0] * POOL.fetch(s[:kind], 0)), bonus: 0, sat: SAT_START, sat_log: [],
                             evals: [], human: false, base0: o[:base0])
      season(world, club, fresh: true)
    end
  end
end
