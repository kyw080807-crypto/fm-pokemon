#===============================================================================
# FM::Tournament — PET, PENT and PWT (Poké Manager createSub/createWorld,
# swissPairs/swissRound, koRound, KO_PRIZE, pwtPts, leagueCoef; design 03/05
# for hosts and dates). Pure Ruby.
#
# PWT: 30 league places split 4/3 by region coefficient + the PET and PENT
# winners = 32 (PWT_SIZE). Swiss stage like LoL Worlds: single games between
# players on the same record; 3 wins and a player goes straight through with
# no more games, 3 losses and they're out; at most 5 rounds, which leaves
# exactly 16 for a seeded best-of-3 knockout. PET (east: Kanto, Johto, Hoenn, Sinnoh)
# and PENT (the other five): 16 league finishers not going to the PWT,
# single games with a best-of-3 final. PET/PENT prizes are not in the
# original data we extracted: drafts.
#===============================================================================
module FM
  module Tournament
    PET_REGIONS  = %w[KANTO JOHTO HOENN SINNOH].freeze
    PENT_REGIONS = %w[UNOVA KALOS ALOLA GALAR PALDEA].freeze
    ALL_REGIONS  = (PET_REGIONS + PENT_REGIONS).freeze
    PWT_LEAGUE_PLACES = 30
    SWISS_GOAL = 3
    SWISS_PRIZE = 25_000   # seedKnockout: non-qualifiers not out on 3 losses
    PWT_FEE = 10_000
    SUB_FEE = 3000
    SWISS_ROUNDS = 5
    KO_PRIZE = [40_000, 60_000, 90_000, 130_000].freeze   # losers of R16, QF, SF, final
    CHAMPION_PRIZE = 200_000
    SUB_PRIZE = [10_000, 15_000, 25_000, 40_000].freeze  # draft
    SUB_CHAMPION_PRIZE = 60_000                           # draft
    SEED = [0, 15, 7, 8, 3, 12, 4, 11, 1, 14, 6, 9, 2, 13, 5, 10].freeze
    STAGES = %i[r16 qf sf final].freeze

    module_function

    def host(kind, year)
      list = { pet: PET_REGIONS, pent: PENT_REGIONS, pwt: ALL_REGIONS }.fetch(kind)
      list[(year - 1) % list.size]
    end

    # Regions ranked by coefficient: the top three get 4 places, the rest 3.
    def pwt_slots(coef)
      ranked = ALL_REGIONS.sort_by { |r| [-coef.fetch(r, 0), ALL_REGIONS.index(r)] }
      extra = PWT_LEAGUE_PLACES - 3 * ALL_REGIONS.size
      ranked.each_with_index.to_h { |r, i| [r, i < extra ? 4 : 3] }
    end

    # pwtPts: power-ranking points for a PWT result.
    def pwt_points(result, wins: 0)
      { champion: 100, final: 70, sf: 50, qf: 35, r16: 22 }.fetch(result) { 4 + wins * 3 }
    end

    # First to win `best_of / 2 + 1` games; a tied series goes to KOs, then a coin.
    def series(a, b, best_of:, rng: Random.new)
      return yield(a, b) if best_of == 1
      wa = wb = ka = kb = 0
      need = best_of / 2 + 1
      while wa < need && wb < need && wa + wb < best_of
        r = yield(a, b)
        ka += r[:ko_a]; kb += r[:ko_b]
        wa += 1 if r[:res] == 1
        wb += 1 if r[:res] == -1
        break if wa + wb == 0 && ka + kb > 3 * best_of   # all draws: stop
      end
      res = wa > wb ? 1 : wb > wa ? -1 : ka > kb ? 1 : kb > ka ? -1 : (rng.rand < 0.5 ? 1 : -1)
      { res: res, ko_a: wa, ko_b: wb }
    end

    class Knockout
      attr_reader :bracket, :results, :champion

      def initialize(seeded_players)
        raise ArgumentError, "need 16 players" unless seeded_players.size == 16
        @bracket = [SEED.map { |i| seeded_players[i] }]
        @results = []
        @champion = nil
      end

      def round_index = @results.size
      def done? = !@champion.nil?
      def finalists = @bracket[3]

      # Yields (a, b) per game; returns [[a, b, winner, loser, series], ...].
      def play_round(best_of:, rng: Random.new, &match)
        cur = @bracket.last
        res = cur.each_slice(2).map do |a, b|
          s = Tournament.series(a, b, best_of: best_of, rng: rng, &match)
          w, l = s[:res].positive? ? [a, b] : [b, a]
          [a, b, w, l, s]
        end
        @results << res
        nxt = res.map { |x| x[2] }
        if nxt.size == 1 then @champion = nxt.first
        else @bracket << nxt
        end
        res
      end
    end

    class Swiss
      attr_reader :players, :wins, :losses, :kd, :opponents, :round

      def initialize(players, rng:)
        @players = players.dup
        @rng = rng
        @wins = players.to_h { |p| [p, 0] }
        @losses = players.to_h { |p| [p, 0] }
        @kd = players.to_h { |p| [p, 0] }
        @opponents = players.to_h { |p| [p, []] }
        @round = 0
      end

      def buchholz(p) = @opponents[p].sum { |o| @wins[o] }

      def active?(p) = @wins[p] < SWISS_GOAL && @losses[p] < SWISS_GOAL

      def done?
        @round >= SWISS_ROUNDS || @players.none? { |p| active?(p) }
      end

      # Active players only, in same-record groups, best first; round 1
      # shuffled, later by Buchholz and KO difference; skip opponents already
      # met where possible.
      def pairs
        groups = @players.select { |p| active?(p) }.group_by { |p| [@wins[p], @losses[p]] }
        keys = groups.keys.sort_by { |w, l| [-w, l] }
        out = []
        carry = []
        keys.each do |k|
          arr = carry + groups[k]
          carry = []
          arr = @round.zero? ? arr.shuffle(random: @rng) : arr.sort_by { |p| [-buchholz(p), -@kd[p], p.to_s] }
          while arr.size > 1
            a = arr.shift
            i = arr.rindex { |b| !@opponents[a].include?(b) } || arr.size - 1
            out << [a, arr.delete_at(i)]
          end
          carry = arr
        end
        out
      end

      def play_round
        res = pairs.map do |a, b|
          r = yield(a, b)
          w = r[:res].positive? ? a : r[:res].negative? ? b : (@rng.rand < 0.5 ? a : b)
          l = w == a ? b : a
          @wins[w] += 1
          @losses[l] += 1
          @kd[a] += r[:ko_a] - r[:ko_b]
          @kd[b] += r[:ko_b] - r[:ko_a]
          @opponents[a] << b
          @opponents[b] << a
          [a, b, w, l, r]
        end
        @round += 1
        res
      end

      # swissOrder: wins, fewer losses, Buchholz, KO difference.
      def standings
        @players.sort_by { |p| [-@wins[p], @losses[p], -buchholz(p), -@kd[p], p.to_s] }
      end

      # seedKnockout: the 3-win players in order, topped up from the rest if
      # fewer than n made it.
      def qualifiers(n)
        top = standings.select { |p| @wins[p] >= SWISS_GOAL }
        (top + (standings - top)).first(n)
      end
    end
  end
end
