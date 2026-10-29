require_relative "test_helper"

class TestCommittee < Minitest::Test
  # Kanto: a capital with 4 clubs and a town with 4 clubs.
  def world(seed: 1)
    clubs = (0...8).map do |i|
      { id: "K#{i}", name: "K#{i}", region: "KANTO", city: i < 4 ? "CAP" : "TOWN", role: i < 4 ? "E1" : "G1",
        canon: true, level: 30, potential: 3, type: "NORMAL", stadium: 3, clubhouse: 3,
        facilities: { TRAINING: 2 }, pokemon: Array.new(3) { { bst: 450 + i, level: 30, stars: 3 } } }
    end
    cities = [{ id: "CAP", name: "CAP", region: "KANTO", form: "LEAGUE", size: 5, free_plots: 6,
                buildings: [[:TRANSPORT, 10], [:HOTEL, 6]] },
              { id: "TOWN", name: "TOWN", region: "KANTO", form: "LONDON", size: 2, free_plots: 1,
                buildings: [[:TRANSPORT, 2]] }]
    FM::World.new_game(clubs, seed: seed, cities: cities)
  end

  def test_one_committee_per_capital_with_design_start_levels
    w = world
    cm = w.committees.fetch("KANTO")
    assert_equal 1, w.committees.size
    assert_equal 6, cm.facilities[:SIDE_STADIUM]
    assert_equal %w[K0 K1 K2 K3], cm.members(w)
  end

  def test_weekly_dues_hq_income_and_broadcast
    w = world
    w.advance_days(7)
    c = w.clubs["K5"]
    assert_equal(-(c.fame * FM::Committee::DUES_PER_FAME).round, c.wallet.totals[:dues])
    assert_equal 4 * FM::Committee::BROADCAST_PER_LEVEL, c.wallet.totals[:broadcast]
    t = w.cities["CAP"].budget.totals
    assert t[:dues].positive?
    assert_equal 6 * FM::Committee::HQ_INCOME_PER_LEVEL, t[:league_hq]
  end

  def test_side_stadium_first_and_capital_clubs_move_up
    w = world
    w.cities["CAP"].budget.record(20_000_000, category: :grant, date: [1, 1, 1])
    events = w.advance_days(200)
    first = events.find { |e| e[:kind] == :committee && e[:passed] }
    refute_nil first
    assert_equal :SIDE_STADIUM, first[:target]
    assert events.any? { |e| e[:kind] == :committee_built && e[:what] == :SIDE_STADIUM }
    assert_equal 4, w.clubs["K0"].stadium
    assert_equal 3, w.clubs["K5"].stadium, "non-capital clubs keep their own stadium"
  end

  def test_meetings_only_in_quarter_months
    w = world
    w.cities["CAP"].budget.record(20_000_000, category: :grant, date: [1, 1, 1])
    w.advance_days(365).select { |e| e[:kind] == :committee }.each do |e|
      assert_includes FM::Committee::QUARTER_MONTHS, e[:date][1]
    end
  end

  def test_gym_reps_after_season
    w = world
    w.advance_days(364)
    reps = w.committees["KANTO"].gym_reps
    assert_equal 2, reps.size
    assert(reps.all? { |id| w.clubs[id].city == "TOWN" })
    assert_equal 6, w.committees["KANTO"].members(w).size
  end

  def test_world_without_committee_ivar_builds_them_on_use
    w = world
    w.remove_instance_variable(:@committees) if w.instance_variable_defined?(:@committees)
    refute_empty w.committees
  end
end

class TestCommitteeDistribution < Minitest::Test
  def test_surplus_goes_to_the_bottom_half
    w = TestCommittee.new("x").world
    w.cities["CAP"].budget.record(50_000_000, category: :grant, date: [1, 1, 1])
    w.advance_days(364)
    standings = w.leagues["KANTO"].standings
    got = standings.map { |id| w.clubs[id].wallet.totals.fetch(:distribution, 0) }
    assert got.first(4).all?(&:zero?), "top half gets nothing"
    assert got.last.positive?
    assert got.last >= got[-2], "last place gets the most"
    assert w.cities["CAP"].budget.totals[:distribution].negative?
  end
end
