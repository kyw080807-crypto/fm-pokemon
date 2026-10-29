require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager 팬 만족도 (fsAdd / fsAtt / fsMerch / fsCap / fsResult /
# fsSetPrice / fsWeek, the demand wrapper) and 시즌 목표 (goalSet / goalBonus /
# goalCheck).
class TestFans < Minitest::Test
  F = FM::Fans
  G = FM::Goals

  def setup
    @w = TestPlayer.new("x").world
    @p = @w.clubs["P"]
    @a = @w.clubs["A"]
  end

  def test_effects_scale_with_satisfaction
    assert_equal 60, F.of(@p)
    @p.fsat = 100
    assert_in_delta 1.4, F.att_mul(@p), 1e-9
    assert_in_delta 1.5, F.merch_mul(@p), 1e-9
    assert_equal (FM::Economy.price(@p.fame) * 1.7).round, F.cap(@p)
    @p.fsat = 0
    assert_in_delta 0.6, F.att_mul(@p), 1e-9
    assert_equal %i[ecstatic happy normal unhappy angry], [90, 70, 50, 30, 10].map { |v| F.mood(v) }
  end

  def test_results_weigh_the_gap_and_series
    @p.fsat = 50
    F.result(@p, @a, 1)
    win = @p.fsat - 50
    assert_in_delta 2 + ((F.team_ovr(@a) - F.team_ovr(@p)) / 10.0).clamp(-1, 1.5), win, 1e-9
    @p.fsat = 50
    F.result(@p, @a, 1, series: true)
    assert_in_delta win * 1.6, @p.fsat - 50, 1e-9
    @p.fsat = 50
    F.result(@p, @a, -1)
    assert_operator @p.fsat, :<, 50
    assert_includes %i[loss upset_loss], @p.fs_log.first[:why]
  end

  def test_ticket_price_moves_fans_and_demand
    ref = FM::Economy.price(@p.fame)
    @w.ticket_price = ref
    @p.fsat = 50
    assert_equal ref + 1, F.set_price(@p, @w, ref + 1)
    assert_in_delta 50 - 6.0 / ref, @p.fsat, 1e-9
    assert_equal :capped, F.set_price(@p, @w, 20), "above the fans' cap"
    F.home_game(@p, ref * 2)
    assert_operator @p.fsat, :<, 50 - 6.0 / ref
    dear = FM::Economy.gate(home_fame: 50, away_fame: 50, wins: 2, stadium: 6, rng: Random.new(1), price: 20)
    fair = FM::Economy.gate(home_fame: 50, away_fame: 50, wins: 2, stadium: 6, rng: Random.new(1))
    assert_operator dear[:attendance], :<, fair[:attendance]
    assert_equal 20, dear[:price]
  end

  def test_week_drifts_to_55_and_cuts_a_price_over_the_cap
    @p.fsat = 95
    @w.ticket_price = 20
    events = F.week(@p, @w, date: [1, 3, 1])
    assert_in_delta 95 + (55 - 95) * 0.05, @p.fsat, 1e-9
    assert(events.any? { |e| e[:kind] == :fans_price_cut })
    assert(events.any? { |e| e[:kind] == :fans_love })
    assert_equal F.cap(@p), @w.ticket_price
    assert_empty F.week(@p, @w, date: [1, 3, 8]).select { |e| e[:kind] == :fans_love }, "once a year"
  end

  def test_only_the_player_has_fans
    @w.advance_days(200)
    assert @p.fsat, "the player's fans moved"
    assert_nil @a.fsat
    assert @p.goal, "a season goal"
    assert_nil @a.goal
  end

  def test_goal_bonus_and_check
    assert_equal ((21**1.5 * 1500 + 20_000) / 1000.0).round * 1000, G.bonus(1)
    @p.goal = { year: @w.calendar.year, region: @p.region, t: 3, bonus: 50_000, done: false }
    @p.fsat = 50
    fame = @p.fame
    e = G.check(@w, @p, 1)
    assert e[:goal][:ok]
    assert_equal 60_000, e[:goal][:paid], "two places better: +20%"
    assert_in_delta 55, @p.fsat, 1e-9
    assert_in_delta fame + 3, @p.fame, 1e-9
    assert_nil G.check(@w, @p, 1), "once"
    @p.goal = { year: @w.calendar.year, region: @p.region, t: 1, bonus: 1, done: false }
    refute G.check(@w, @p, 2)[:goal][:ok]
  end

  def test_goal_target_mixes_last_place_and_strength
    year = @w.calendar.year
    @p.history[year - 1] = { pos: 4 }
    e = G.set(@w, @p)
    assert_equal (4 * 0.5 + G.strength_rank(@w, @p) * 0.5).round.clamp(1, 2), e[:goal][:t], "4 clubs: at most 2nd"
  end
end
