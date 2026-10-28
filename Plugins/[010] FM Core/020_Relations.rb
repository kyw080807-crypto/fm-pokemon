#===============================================================================
# FM::Relations — how much clubs like each other, -1..1, 0 to start (design
# 02 관계도). Pure Ruby. Changed by derbies (league games between clubs of
# the same city) and by meetings (협의 성공·실패: a passed agenda warms
# every pair at the table, a failed one cools them; voting differently
# cools a little more); each season it relaxes toward 0. In a vote a
# club's mood toward the rest of the meeting shifts its score. Promise
# keeping (also in the design) needs promises first. All numbers are drafts.
#===============================================================================
module FM
  class Relations
    DERBY = -0.02          # both sides, after a derby
    DERBY_WIN_GLOAT = -0.01  # extra cooling after a decided derby
    PASSED = 0.04          # an agenda passed: everyone at the table warms
    FAILED = -0.01         # it failed: everyone cools
    SPLIT_VOTE = -0.01     # extra, between clubs that voted differently
    SEASON_DECAY = 0.8
    VOTE_WEIGHT = 0.5      # mean relation x this is the vote's relation term

    def initialize
      @values = {}
    end

    def key(a, b) = a.to_s < b.to_s ? [a, b] : [b, a]

    def get(a, b)
      return 0.0 if a == b
      @values.fetch(key(a, b), 0.0)
    end

    def change(a, b, delta)
      return if a == b
      k = key(a, b)
      @values[k] = (@values.fetch(k, 0.0) + delta).clamp(-1.0, 1.0)
    end

    def derby(winner, loser, draw: false)
      change(winner, loser, DERBY + (draw ? 0 : DERBY_WIN_GLOAT))
    end

    # votes: { club_id => true/false }
    def meeting(votes, passed:)
      votes.keys.combination(2).each do |a, b|
        change(a, b, (passed ? PASSED : FAILED) + (votes[a] == votes[b] ? 0 : SPLIT_VOTE))
      end
    end

    def season_decay
      @values.transform_values! { |v| v * SEASON_DECAY }
      @values.reject! { |_, v| v.abs < 0.005 }
    end

    # The relation term for `id` voting in a meeting of `others`.
    def vote_term(id, others)
      others = others - [id]
      return 0.0 if others.empty?
      others.sum { |o| get(id, o) } / others.size * VOTE_WEIGHT
    end

    def size = @values.size
    def values = @values.values
  end
end
