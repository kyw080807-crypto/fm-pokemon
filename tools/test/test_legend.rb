require_relative "test_helper"
require_relative "test_squad"   # TestSquad::SPECIES has MEWTWO (tier 2)

# Poké Manager legends: one per line in the world, one per club, three
# seasons, a ★1 no-EV symbol, found by the PWT champion.
class TestLegend < Minitest::Test
  POOL = TestSquad::SPECIES.merge(
    "MEW" => { bst: 600, fb: 600, tier: 3, region: "KANTO", basic: true, evo: [] }
  ).freeze

  def club(id, mons)
    { id: id, name: id, region: "KANTO", city: "C", role: "T", canon: false, level: 20, potential: 3,
      stadium: 1, clubhouse: 3, facilities: { TRAINING: 2, SCOUTING: 2 },
      pokemon: mons.map { |s| { species: s, bst: POOL[s][:bst], level: 40, stars: 5 } } }
  end

  def world
    w = FM::World.new_game([club("A", %w[MEWTWO PIDGEY CHARMANDER]), club("B", %w[PIDGEY TOTODILE SNORLAX])],
                           seed: 3, species: POOL)
    w.player_club = nil
    w.clubs.each_value { |c| c.wallet.record(10_000_000, category: :grant, date: [1, 1, 1]) }
    w
  end

  def test_rosters_register_and_nerf_their_legends
    w = world
    reg = FM::Legend.registry(w)
    assert_equal "A", reg["MEWTWO"][:owner]
    assert_nil reg["MEW"][:owner]
    m = w.clubs["A"].squad.find { |x| x.species == "MEWTWO" }
    assert_equal [1, 0.0], [m.stars, m.ev]
  end

  def test_one_per_club_and_per_line
    w = world
    a, b = w.clubs["A"], w.clubs["B"]
    assert FM::Legend.block?(w, a, "MEW"), "A already has one"
    assert FM::Legend.block?(w, b, "MEWTWO"), "the line has an owner"
    refute FM::Legend.block?(w, b, "MEW")
    refute FM::Legend.block?(w, b, "PIDGEY")
  end

  def test_legends_rest_and_never_gain_evs
    m = FM::Legend.make(POOL, "MEW", 40)
    saved = FM::Scout.pool
    FM::Scout.pool = POOL
    m.cond = 50
    FM::Growth.condition_week(m)
    assert m.resting
    assert_operator m.cond, :>, 50
    lv = m.level + m.prog
    FM::Growth.week(m, train_level: 3, species: POOL)
    assert_equal 0.0, m.ev
    assert_operator m.level + m.prog, :>, lv
  ensure
    FM::Scout.pool = saved
  end

  def test_three_seasons_then_it_leaves_and_not_back
    w = world
    events = w.advance_days(365 * 3)
    left = events.find { |e| e[:kind] == :legend_left }
    assert left
    assert_equal "A", left[:club]
    refute(w.clubs["A"].squad.any? { |m| m.species == "MEWTWO" })
    refute_includes FM::Legend.free_lines(w, w.clubs["A"]), "MEWTWO"
    assert_includes FM::Legend.free_lines(w, w.clubs["B"]), "MEWTWO"
  end

  def test_ai_pwt_champion_takes_one_at_the_new_year
    w = world
    w.leg_right = { club: "B", year: 1, used: false }
    events = w.advance_days(365)
    joined = events.find { |e| e[:kind] == :legend_joined }
    assert joined
    assert_equal "B", joined[:club]
    assert_equal "MEW", joined[:species]
    assert w.leg_right[:used]
  end

  def test_merchandise_and_fame_with_a_legend
    w = world
    w.advance_days(7)
    a = w.clubs["A"].wallet.totals[:merch]
    expected = (FM::Economy.merch(w.clubs["A"].fame) * FM::Legend::MERCH_MUL).round
    assert_in_delta expected, a, expected * 0.05
  end
end
