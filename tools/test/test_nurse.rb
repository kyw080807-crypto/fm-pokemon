require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world
require_relative "test_scouting" # TestScouting::POOL

# Poké Manager nurse Pokémon (NURSE_SP / nurseQ / nurseSlots / nursePow /
# nurseWeek / aiNurses / toggleNurse / the injHeal-injRecovered-injRisk
# wrappers) and the special scouting (sendSpecScout / SPEC_POOL).
class TestNurse < Minitest::Test
  N = FM::Nurse

  def setup
    @w = TestPlayer.new("x").world
    @p = @w.clubs["P"]
    @a = @w.clubs["A"]
  end

  def mon(species, stars: 3, ko: 0)
    m = FM::Mon.new(species: species, bst: 450, level: 40, stars: stars)
    m.ko = ko
    m
  end

  def retired(club, species, **opts)
    m = mon(species, **opts)
    club.retire(m)
    m
  end

  def rng(value) = Struct.new(:v) { def rand(*) = v }.new(value)

  def test_quality_grade_and_slots
    assert_equal 3.0, N.quality(mon("BLISSEY"))
    assert_equal 3.4, N.quality(mon("BLISSEY", stars: 5, ko: 100))
    assert_equal 3.5, N.quality(mon("BLISSEY", stars: 7, ko: 100)), "at most 3.5"
    assert_equal 1.3, N.quality(mon("JIGGLYPUFF"))
    assert_equal 2.5, N.quality(mon("AUDINO_1")), "a form nurses as its species"
    refute N.can?(mon("PIDGEY"))
    assert_equal %w[S A B C], [3.0, 2.5, 1.6, 1.0].map { |q| N.grade(q) }
    @p.facilities[:MEDICAL] = 0
    assert_equal 1, N.slots(@p)
    @p.facilities[:MEDICAL] = 4
    assert_equal 2, N.slots(@p)
    @p.facilities[:MEDICAL] = 8
    assert_equal 3, N.slots(@p)
  end

  def test_power_counts_active_nurses_at_seventy_percent
    @p.facilities[:MEDICAL] = 8
    @p.squad << (active = mon("CHANSEY"))
    assert_equal :on, N.toggle(@p, active)
    assert_in_delta 2.5 * 0.7, N.pow(@p), 1e-9
    assert_equal :on, N.toggle(@p, retired(@p, "BLISSEY"))
    assert_in_delta 1.75 + 3.0, N.pow(@p), 1e-9
    assert_equal :on, N.toggle(@p, retired(@p, "AUDINO"))
    assert_equal 5, N.pow(@p), "at most 5"
  end

  def test_toggle_rules
    nurse = retired(@p, "CHANSEY")
    assert_equal :cannot, N.toggle(@p, retired(@p, "PIDGEY"))
    nurse.coach = true
    assert_equal :busy, N.toggle(@p, nurse)
    nurse.coach = false
    assert_equal :on, N.toggle(@p, nurse)
    assert_equal :full, N.toggle(@p, retired(@p, "HAPPINY")), "one slot without a medical center"
    assert_equal :off, N.toggle(@p, nurse)
  end

  def test_food_only_for_retired_nurses_and_trimmed_to_slots
    @p.facilities[:MEDICAL] = 4
    @p.squad << (active = mon("CHANSEY"))
    old = retired(@p, "BLISSEY")
    [active, old].each { |m| N.toggle(@p, m) }
    assert_equal old.food_fixed, N.weekly_food(@p)
    @p.facilities[:MEDICAL] = 1
    paid = N.week(@p, date: [1, 1, 8])
    assert_equal [active], N.of(@p), "the last one steps down"
    assert_equal 0, paid
  end

  def test_ai_names_its_best_retired_nurses_and_coaches_skip_them
    @a.facilities[:MEDICAL] = 4
    happy = retired(@a, "HAPPINY")
    bliss = retired(@a, "BLISSEY")
    retired(@a, "PIDGEY")
    N.ai_pick(@a)
    assert bliss.nurse && happy.nurse
    FM::Coach.ai_pick(@a)
    refute bliss.coach || happy.coach, "nurses don't coach"
    refute_includes FM::Daycare.candidates(@w.species, @a), bliss, "nurses don't breed"
  end

  def test_nurses_heal_faster_cut_rehab_and_rehab_risk
    m = mon("PIDGEY")
    m.inj = 4
    m.injd = { k: :sprain, sev: 2, w0: 4, cause: :battle }
    b0 = m.bond
    FM::Injury.heal_week(m, 0, rng(0.0), nurse: 3.0)
    assert_equal 1, m.inj, "a week, the center's extra week and the nurses'"
    assert_in_delta b0 + 0.5, m.bond, 1e-9
    FM::Injury.heal_week(m, 0, rng(0.99), nurse: 3.0)
    assert_equal 1, m.rehab, "power 2.5+: a week of rehab"
    r = mon("PIDGEY")
    r.rehab = 2
    assert_in_delta FM::Injury.match_risk(r, 0) * (1 - 0.18), FM::Injury.match_risk(r, 0, 3.0), 1e-12
    h = mon("PIDGEY")
    assert_equal FM::Injury.match_risk(h, 0), FM::Injury.match_risk(h, 0, 3.0), "only mons in rehab"
  end

  def test_special_scout_brings_nurses_or_ditto
    extra = %w[HAPPINY CHANSEY AUDINO IGGLYBUFF JIGGLYPUFF DITTO].to_h do |s|
      [s, { bst: 300, fb: 300, tier: 0, region: "KANTO", basic: true, evo: [], types: %w[NORMAL] }]
    end
    w = TestScouting.new("x").world(pool: TestScouting::POOL.merge(extra))
    p = w.clubs["P"]
    assert_nil w.send_scout(nil, spec: :nurse)
    assert_equal(-FM::Scouting::SPEC_FEE, p.wallet.totals[:scout])
    events = w.advance_days(14)
    rep = events.find { |e| e[:kind] == :scout_report && e[:spec] == :nurse }
    assert rep
    assert(rep[:species].all? { |s| N.can?(FM::Mon.new(species: s, bst: 1, level: 1, stars: 3)) }, rep[:species].inspect)
    p.squad << FM::Mon.new(species: "DITTO", bst: 288, level: 30, stars: 3)
    assert_equal :blocked, w.send_scout(nil, spec: :ditto), "one Ditto per squad"
  end
end
