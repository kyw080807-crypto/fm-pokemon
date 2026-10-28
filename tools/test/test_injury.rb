require_relative "test_helper"
require_relative "test_player"   # TestPlayer#club / #world

class TestInjury < Minitest::Test
  def mon(cond: 100)
    m = FM::Mon.new(species: "PIDGEY", bst: 251, level: 30, stars: 3)
    m.cond = cond
    m
  end

  def test_medical_center_cuts_match_risk
    m = mon
    assert_operator FM::Injury.match_risk(m, 5), :<, FM::Injury.match_risk(m, 1)
    assert_in_delta 0.18, FM::Injury.risk_cut(5), 1e-9   # original Lv10 cap
    assert_in_delta 0.0, FM::Injury.risk_cut(nil), 1e-9
  end

  def test_low_condition_fatigue_and_rehab_raise_risk
    base = FM::Injury.match_risk(mon, 1)
    assert_in_delta base * 2, FM::Injury.match_risk(mon(cond: 45), 1), 1e-9
    tired = mon
    tired.fat = 75
    assert_in_delta base * 1.5, FM::Injury.match_risk(tired, 1), 1e-9
    r = mon
    r.rehab = 2
    assert_in_delta base * 1.6, FM::Injury.match_risk(r, 1), 1e-9
  end

  def test_serious_injury_takes_a_mon_out_of_the_entry_and_rating
    w = TestPlayer.new("x").world
    c = w.clubs["A"]
    best = c.entry(1).first
    before = c.rating
    FM::Injury.injure(best, :battle, Random.new(1), :fracture)
    c.refresh_rating
    assert best.out?
    refute_includes c.entry, best
    assert_operator c.rating, :<, before
  end

  def test_light_injury_still_plays_at_reduced_strength
    w = TestPlayer.new("x").world
    c = w.clubs["A"]
    m = c.entry(1).first
    before = c.rating
    FM::Injury.injure(m, :battle, Random.new(1), :bruise)
    c.refresh_rating
    assert m.yellow?
    assert_includes c.entry, m
    assert_operator c.rating, :<, before
  end

  def test_healing_then_rehab_and_lv5_shortens_rehab
    rng = Random.new(3)
    m = mon(cond: 95)
    FM::Injury.injure(m, :battle, rng, :sprain)
    weeks = m.inj
    n = 0
    n += 1 until FM::Injury.heal_week(m, 1, rng) == :recovered
    assert_operator n, :<=, weeks
    refute m.hurt?
    assert_equal FM::Injury::REHAB_WEEKS, m.rehab
    assert_operator m.cond, :<=, FM::Injury::REHAB_COND
    m2 = mon
    FM::Injury.injure(m2, :battle, rng, :sprain)
    nil until FM::Injury.heal_week(m2, 5, rng) == :recovered
    assert_equal 1, m2.rehab
  end

  def test_injured_mons_rest_and_do_not_grow
    m = mon(cond: 90)
    FM::Injury.injure(m, :battle, Random.new(1), :ligament)
    FM::Growth.condition_week(m)
    assert m.resting
    lv = m.level
    5.times { FM::Growth.week(m, train_level: 5, species: TestSquad::SPECIES) }
    assert_equal lv, m.level
  end

  def test_matches_build_fatigue_and_rest_clears_it
    m = mon
    FM::Growth.match_drain(m, 4)
    assert_in_delta 2.8, m.fat, 1e-9
    m.fat = 50
    c = m.cond
    FM::Growth.match_drain(m, 4)
    assert_operator c - m.cond, :>, 4   # tired mons lose more
    m.played = false
    m.cond = 50
    FM::Growth.condition_week(m)   # rests under 60
    assert_in_delta 50 + 4 * (1 + 50 / 150.0) * 0.7 - 14, m.fat, 0.01
  end

  def test_a_season_produces_injury_events_and_recoveries
    w = TestPlayer.new("x").world
    kinds = w.advance_days(365).map { |e| e[:kind] }
    assert_includes kinds, :injured
    assert_includes kinds, :recovered
  end

  def test_real_battle_result_names_who_fainted
    w = TestPlayer.new("x").world
    p = w.clubs["P"]
    victim = p.lineup.first
    FM::World.player_match = lambda do |home, away, _world, **|
      mine = home.id == "P"
      fa = mine ? [victim] * 1 : []
      fb = mine ? [] : [victim]
      { res: mine ? -1 : 1, ko_a: 3, ko_b: 3, fainted_a: fa, fainted_b: fb }
    end
    events = FM::Injury.stub(:match_risk, ->(m, _) { m.equal?(victim) ? 1.0 : 0.0 }) { w.advance_days(200) }
    battle = events.select { |e| e[:kind] == :injured && e[:cause] == :battle }
    refute_empty battle
    assert(battle.all? { |e| e[:club] == "P" }, "only the named mon could be hurt in a match")
  ensure
    FM::World.player_match = nil
  end
end
