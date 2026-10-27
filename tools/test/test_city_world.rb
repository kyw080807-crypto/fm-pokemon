require_relative "test_helper"

class TestCityWorld < Minitest::Test
  def club(id, city, clubhouse: 2)
    { id: id, name: id, region: "KANTO", city: city, role: "G1", canon: true, level: 30, potential: 3,
      type: "NORMAL", stadium: 1, stadium_shared: false, clubhouse: clubhouse,
      facilities: { TRAINING: 3, SCOUTING: 3, MEDICAL: 3, DAYCARE: 1 },
      pokemon: Array.new(3) { { bst: 450, level: 30, stars: 3 } } }
  end

  def city(id, form:, size: 1)
    { id: id, name: id, region: "KANTO", form: form, size: size, free_plots: 1,
      buildings: [[:RESIDENTIAL, 1], [:SHOPPING, 1]] }
  end

  def world
    cities = [city("SOLO", form: "SOLO"), city("SHARED", form: "LONDON"), city("CAP", form: "LEAGUE", size: 5)]
    clubs = [club("S1", "SOLO"), club("L1", "SHARED"), club("L2", "SHARED"), club("K1", "CAP")]
    FM::World.new_game(clubs, seed: 2, cities: cities)
  end

  def test_cities_collect_tax_and_pay_upkeep_weekly
    w = world
    w.advance_days(7)
    t = w.cities["SOLO"].budget.totals
    assert t[:tax].positive?
    assert t[:upkeep].negative?
  end

  def test_clubs_contribute_part_of_gate
    w = world
    w.advance_days(w.calendar.days_until(FM::Season.league_dates(w.calendar, 1).first))
    contributed = w.clubs.values.sum { |c| c.wallet.totals.fetch(:city, 0) }
    received = w.cities.values.sum { |c| c.budget.totals.fetch(:contribution, 0) }
    assert contributed.negative?
    assert_equal(-contributed, received)
  end

  def test_rich_blocked_solo_city_expands_and_lifts_clubhouse_cap
    w = world
    s1 = w.clubs["S1"]
    s1.fame = 80
    s1.wallet.record(30_000_000, category: :grant, date: [1, 1, 1])
    assert_equal 1, w.cities["SOLO"].size
    events = w.advance_days(365)
    assert events.any? { |e| e[:kind] == :meeting && e[:city] == "SOLO" && e[:passed] }
    assert w.cities["SOLO"].size >= 2
    assert_equal w.cities["SOLO"].size, s1.city_size
  end

  def test_shared_city_needs_a_majority
    w = world
    w.clubs["L1"].wallet.record(30_000_000, category: :grant, date: [1, 1, 1])
    w.clubs["L1"].fame = 80
    # L2 is broke: with two members, one yes is not a majority.
    l2 = w.clubs["L2"]
    l2.wallet.record(-l2.wallet.balance - 1_000_000, category: :drain, date: [1, 1, 1])
    events = w.advance_days(60)
    meetings = events.select { |e| e[:kind] == :meeting && e[:city] == "SHARED" }
    refute_empty meetings
    meetings.each { |m| refute m[:passed] }
    assert_equal 1, w.cities["SHARED"].size
    assert meetings.first[:votes]["L2"][:reason]
  end

  def test_capital_does_not_hold_monthly_expansion_meetings
    w = world
    events = w.advance_days(120)
    assert events.none? { |e| e[:kind] == :meeting && e[:city] == "CAP" }
    assert_equal 5, w.cities["CAP"].size
  end
end

class TestInfrastructure < Minitest::Test
  def club(id, city)
    { id: id, name: id, region: "KANTO", city: city, role: "G1", canon: true, level: 30, potential: 3,
      type: "NORMAL", stadium: 1, clubhouse: 1, facilities: { TRAINING: 1 },
      pokemon: Array.new(3) { { bst: 450, level: 30, stars: 3 } } }
  end

  def city(id, form:, size: 2, free: 1, buildings: [[:RESIDENTIAL, 1], [:TRANSPORT, 1]])
    { id: id, name: id, region: "KANTO", form: form, size: size, free_plots: free, buildings: buildings }
  end

  def test_infra_step_rules
    c = FM::City.new(city("A", form: "SOLO", size: 2))
    step = FM::Civic.infra_step(c)
    assert_equal :HOTEL, step[:target], "the lower one first: hotel Lv0 (inn) before transport Lv1"
    assert_equal 0, step[:from]
    full = FM::City.new(city("B", form: "SOLO", size: 1, free: 0, buildings: [[:TRANSPORT, 2]]))
    assert_nil FM::Civic.infra_step(full), "size 1 caps at Lv2 and no plot for a hotel"
    big = FM::City.new(city("C", form: "SOLO", size: 4, buildings: [[:TRANSPORT, 4], [:HOTEL, 4]]))
    assert_equal :HOTEL, FM::Civic.infra_step(big)[:target], "transport Lv5 (airport) is capitals only"
  end

  def test_solo_city_builds_a_hotel_and_it_completes
    w = FM::World.new_game([club("S1", "S"), club("X1", "X"), club("X2", "X"), club("X3", "X")], seed: 3,
                           cities: [city("S", form: "SOLO"), city("X", form: "LONDON")])
    w.clubs["S1"].wallet.record(10_000_000, category: :grant, date: [1, 1, 1])
    events = w.advance_days(200)
    m = events.find { |e| e[:kind] == :meeting && e[:agenda] == :infrastructure && e[:city] == "S" && e[:passed] }
    refute_nil m
    assert w.cities["S"].hotel >= 1
    assert_equal 0, w.cities["S"].free_plots
    assert events.any? { |e| e[:kind] == :city_built && e[:city] == "S" }
  end

  def test_capitals_do_not_hold_infrastructure_meetings
    w = FM::World.new_game([club("K1", "K"), club("K2", "K"), club("K3", "K"), club("K4", "K")], seed: 3,
                           cities: [city("K", form: "LEAGUE", size: 5)])
    events = w.advance_days(120)
    assert events.none? { |e| e[:kind] == :meeting }
  end
end
