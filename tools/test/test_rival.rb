require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager rivals (S.h2h / pickRival / isRival / rivalResult / taunt).
class TestRival < Minitest::Test
  R = FM::Rival

  def setup
    @w = TestPlayer.new("x").world
    @p = @w.clubs["P"]
  end

  def zero = Struct.new(:x) { def rand(*) = 0.0 }.new(0)

  def test_pick_prefers_the_closest_place_and_old_foes
    year = @w.calendar.year
    @p.history[year - 1] = { pos: 2 }
    { "A" => 1, "B" => 4, "C" => 8 }.each { |id, pos| @w.clubs[id].history[year - 1] = { pos: pos } }
    e = R.pick(@w, @p, zero)
    assert_includes %w[A B], e[:rival], "one place off"
    R.h2h(@w)["C"] = { w: 1, d: 0, l: 4 }   # (5 x 1.5 + 4 x 1.5) + 2 = 15.5
    assert_equal "C", R.pick(@w, @p, zero)[:rival]
    assert R.rival?(@w, "C")
    refute R.rival?(@w, "A")
  end

  def test_league_results_move_fame_and_the_taunt_raises_the_stakes
    @w.rival = { club: "A", year: @w.calendar.year, w: 0, l: 0, since: 1 }
    fame = @p.fame
    e = R.result(@w, @p, "A", 1)
    assert_equal 3, e[:fame]
    assert_in_delta fame + 3, @p.fame, 1e-9
    assert_equal(-2, R.result(@w, @p, "A", 0)[:fame], "a draw counts as not winning")
    @w.taunt = { club: "A", year: @w.calendar.year }
    assert_equal(-4, R.result(@w, @p, "A", -1)[:fame])
    assert_nil @w.taunt
    assert_equal [1, 2], @w.rival.values_at(:w, :l)
    assert_nil R.result(@w, @p, "B", 1), "not the rival"
  end

  def test_fans_count_rival_games_more
    @p.fsat = 50
    FM::Fans.result(@p, @w.clubs["A"], 1)
    plain = @p.fsat - 50
    @p.fsat = 50
    FM::Fans.result(@p, @w.clubs["A"], 1, rival: true)
    assert_in_delta plain * 1.4, @p.fsat - 50, 1e-9
  end

  def test_a_season_picks_a_rival_and_counts_head_to_head
    events = @w.advance_days(200)
    assert(events.any? { |e| e[:kind] == :rival_set })
    assert R.current(@w)
    refute_empty R.h2h(@w)
    assert(R.h2h(@w).values.all? { |h| h.values.sum.positive? })
  end
end
