#===============================================================================
# FM::Analysis — 상대 분석 보고서, in part (Poké Manager: anaReport's entry,
# expected picks, threats, matchup grid, team style, best pick and win
# chance). Pure Ruby; the type chart comes from the caller (Essentials').
# The original works these out from Showdown sets (moves, duelP, the AI's
# pickThree2) and keeps a pick plan for auto matches; we have neither, so:
# - expected picks: the three it fields (Club#lineup, our AI's pick);
# - a matchup g(i, j) of my i against its j: half the log2 of the best
#   type multiplier each side's types get on the other, plus twice the log
#   of the rating ratio, clamped to -1..1;
# - threats: its entry by the sum of its matchups against my entry;
# - best pick: my three with the best sum against its expected three;
# - win chance: the formula match's (FM::Morale.win_p).
#===============================================================================
module FM
  module Analysis
    module_function

    # The next league game: { opp:, round:, home: } or nil.
    def next_match(world, club)
      lg = world.leagues[club.region] or return
      return if lg.done?
      pair = lg.fixtures[lg.next_round]&.find { |h, a| h == club.id || a == club.id } or return
      home = pair[0] == club.id
      { opp: home ? pair[1] : pair[0], round: lg.next_round + 1, home: home }
    end

    def types(pool, mon) = (pool&.dig(mon.species, :types) || []).map(&:to_s)

    # The best multiplier any of `atk` types gets on the `defs` types.
    def best_mul(atk, defs, chart)
      return 1.0 if atk.empty? || defs.empty?
      atk.map { |t| defs.reduce(1.0) { |m, d| m * chart.call(t, d) } }.max
    end

    def edge(pool, a, b, chart)
      ta = types(pool, a)
      tb = types(pool, b)
      atk = best_mul(ta, tb, chart)
      dfn = best_mul(tb, ta, chart)
      x = 0.5 * Math.log2([atk, 0.25].max / [dfn, 0.25].max) + 2 * Math.log([a.rating, 1].max / [b.rating, 1].max.to_f)
      x.clamp(-1.0, 1.0)
    end

    # anaReport -> the report hash
    def report(world, club, opp, chart:)
      pool = world.species
      mine = club.entry
      foes = opp.entry
      g = mine.map { |a| foes.map { |b| edge(pool, a, b, chart) } }
      expect = opp.lineup
      ej = expect.map { |m| foes.index { |x| x.equal?(m) } }.compact
      threats = foes.each_with_index.map { |m, j| [m, -mine.each_index.sum { |i| g[i][j] }] }.sort_by { |_, s| -s }
      score = mine.each_with_index.map { |m, i| [m, ej.sum { |j| g[i][j] }] }
      best = score.sort_by { |m, s| [-s, -m.rating] }.first(3).map(&:first)
      style = foes.flat_map { |m| types(pool, m) }.tally.sort_by { |t, n| [-n, t] }.first(3)
      { opp: opp.id, mine: mine, foes: foes, grid: g, expect: expect, threats: threats, best: best, style: style,
        win: Morale.win_p(club, opp), rating: [club.rating, opp.rating] }
    end
  end
end
