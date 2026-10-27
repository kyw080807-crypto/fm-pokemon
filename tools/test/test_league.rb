require_relative "test_helper"

class TestLeague < Minitest::Test
  CLUBS = (1..20).to_a.freeze

  def setup
    @league = FM::League.new(CLUBS, rng: Random.new(1))
  end

  def test_double_round_robin_shape
    assert_equal 38, @league.fixtures.size
    @league.fixtures.each do |round|
      assert_equal 10, round.size
      assert_equal CLUBS.sort, round.flatten.sort, "every club plays once per round"
    end
  end

  def test_each_pair_meets_home_and_away
    games = @league.fixtures.flatten(1)
    assert_equal 380, games.size
    assert_equal games.uniq.size, games.size
    CLUBS.combination(2).each do |a, b|
      assert_includes games, [a, b]
      assert_includes games, [b, a]
    end
  end

  def test_second_half_mirrors_first
    19.times { |r| assert_equal @league.fixtures[r].map(&:reverse), @league.fixtures[r + 19] }
  end

  def test_rejects_odd_club_count
    assert_raises(ArgumentError) { FM::League.new([1, 2, 3]) }
  end

  def test_points_and_table
    @league.record(1, 2, res: 1, ko_a: 3, ko_b: 1)
    @league.record(3, 4, res: 0, ko_a: 2, ko_b: 2)
    t1 = @league.table[1]
    assert_equal [1, 1, 0, 0, 3, 3, 1], t1.values_at(:p, :w, :d, :l, :pts, :kf, :ka)
    assert_equal [1, 0, 0, 1, 0], @league.table[2].values_at(:p, :w, :d, :l, :pts)
    assert_equal 1, @league.table[3][:pts]
    assert_equal 1, @league.table[4][:pts]
  end

  # Original order: points, then KO difference, then KOs for, then id.
  def test_standings_tiebreaks
    @league.record(1, 2, res: 1, ko_a: 3, ko_b: 2)   # 1: +1, kf 3
    @league.record(3, 4, res: 1, ko_a: 3, ko_b: 0)   # 3: +3
    @league.record(5, 6, res: 1, ko_a: 2, ko_b: 1)   # 5: +1, kf 2
    top = @league.standings.first(3)
    assert_equal [3, 1, 5], top
  end

  def test_play_round_uses_given_resolver
    @league.play_round(0) { |a, b| { res: a < b ? 1 : -1, ko_a: 3, ko_b: 0 } }
    assert_equal 0, @league.next_round - 1
    assert_equal 10, @league.table.values.count { |r| r[:w] == 1 }
    assert_equal 1, @league.next_round
  end

  def test_save_round_trip
    @league.play_round(0) { { res: 1, ko_a: 3, ko_b: 1 } }
    h = Marshal.load(Marshal.dump(@league.to_h))
    copy = FM::League.from_h(h)
    assert_equal @league.to_h, copy.to_h
    assert_equal @league.standings, copy.standings
  end
end
