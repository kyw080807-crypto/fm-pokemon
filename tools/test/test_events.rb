require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager choice events (EVENTS / rollEvent / resolveEvent) and the
# press conference.
class TestEvents < Minitest::Test
  E = FM::Events

  def setup
    @w = TestPlayer.new("x").world
    @p = @w.clubs["P"]
  end

  def rng(*vals)
    q = vals.dup
    Struct.new(:q) { def rand(n = nil) = n.is_a?(Integer) ? 0 : (q.shift || 0.0) }.new(q)
  end

  def test_rolls_respect_weeks_gap_and_chance
    @w.advance_days(14)   # week 3
    assert_nil E.roll(@w, @p, rng(0.5)), "18%"
    ev = E.roll(@w, @p, rng(0.1))
    assert_equal E::KEYS.first, ev[:key]
    @w.event = nil
    assert_nil E.roll(@w, @p, rng(0.0)), "3 weeks apart"
  end

  def test_an_unanswered_event_takes_its_last_option
    @w.event = { key: :camp, year: 1, week: 3 }
    bal = @p.wallet.balance
    out = E.week(@w, @p, rng(1.0))
    assert_equal :event_done, out.first[:kind]
    assert_equal 1, out.first[:choice]
    assert_equal bal, @p.wallet.balance, "the last option: nothing"
  end

  def test_options_change_what_they_say
    @p.squad.each { |m| m.cond = 90 }
    fame = @p.fame
    @w.event = { key: :tv }
    E.resolve(@w, @p, 0)
    assert_in_delta fame + 3, @p.fame, 1e-9
    assert(@p.entry.all? { |m| m.cond == 82 })
    @w.event = { key: :fans }
    bal = @p.wallet.balance
    E.resolve(@w, @p, 0)
    assert_equal bal + E.fan_cash(@p), @p.wallet.balance
    @w.event = { key: :camp }
    ev0 = @p.entry.map(&:ev)
    E.resolve(@w, @p, 0)
    assert_equal ev0.map { |e| [e + 8, FM::Growth::EV_MAX].min }, @p.entry.map(&:ev)
  end

  def test_rumor_brings_two_candidates
    @w.event = { key: :rumor, region: "KANTO" }
    out = E.resolve(@w, @p, 0)
    assert_equal 2, out[:species].size
    assert_equal(-FM::Scouting::FEE, @p.wallet.totals[:scout])
  end

  def test_boasts_cost_on_the_next_loss
    @w.event = { key: :interview }
    E.resolve(@w, @p, 0)
    fame = @p.fame
    E.result(@w, @p, -1, league: true)
    assert_in_delta fame - 4, @p.fame, 1e-9
    assert_nil @w.boast
    @w.event = { key: :press_win }
    @p.fsat = 50
    E.resolve(@w, @p, 2)
    E.result(@w, @p, -1, league: false)
    assert_in_delta 50 + 3 - 5, @p.fsat, 1e-9
  end

  def test_press_follows_last_weeks_official_match
    @w.advance_days(21)
    @w.ev_last = [@w.calendar.year, E.week_no(@w)]   # no ordinary event this week
    @w.last_official = { date: @w.calendar.date, my: -1 }
    ev = E.roll(@w, @p, rng(0.1, 0.1))
    assert_equal :press_loss, ev[:key]
    assert_nil E.roll(@w, @p, rng(0.1, 0.1)), "once a week"
  end
end
