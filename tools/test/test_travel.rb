require_relative "test_helper"
require_relative "test_squad"   # TestSquad::SPECIES

class TestTravel < Minitest::Test
  City = Struct.new(:id, :transport, :region, :cap) do
    def capital? = cap ? true : false
  end

  def test_land_trip_follows_the_departing_city
    far = City.new("FAR", 0, "KANTO")
    near = City.new("NEAR", 8, "KANTO")
    assert_equal({ days: 3, cond: 3 * 2 + 3, fat: 3 * 3 + 2, cost: 300 }, FM::Travel.land(far, near))
    assert_equal({ days: 1, cond: 2, fat: 3, cost: 1000 }, FM::Travel.land(near, far, arrive_before: false))
    assert_equal FM::Travel::NONE, FM::Travel.land(far, far)
    airport = City.new("CAP", 10, "KANTO")
    assert_equal 0, FM::Travel.land(airport, far)[:days], "Lv9-10: same day"
  end

  def test_flights_use_the_design_table
    assert_equal 3, FM::Travel.flight_days("KANTO", "UNOVA")
    assert_equal 1, FM::Travel.flight_days("GALAR", "KALOS")
    assert_equal 2, FM::Travel.flight_days("ALOLA", "JOHTO")
    assert_equal({ days: 3, cond: 6, fat: 8, cost: 800 + 900 * 3 }, FM::Travel.flight("KANTO", "UNOVA"))
    assert_equal FM::Travel::NONE, FM::Travel.flight("KANTO", "KANTO")
  end

  # Design 05 example: 보라타운 (transport Lv0) to a tournament in Unova:
  # 3 days over land, 3 flying, condition -12 and fatigue +17 on the way,
  # plus arriving the day before.
  def test_cup_trip_matches_the_design_example
    town = City.new("LAVENDER", 0, "KANTO")
    caps = { "KANTO" => City.new("KCAP", 5, "KANTO", true), "UNOVA" => City.new("UCAP", 5, "UNOVA", true) }
    t = FM::Travel.to_cup(town, "KANTO", "UNOVA", caps)
    assert_equal 6, t[:days]
    assert_equal 12 + FM::Travel::ARRIVE_BEFORE_COND, t[:cond]
    assert_equal 17 + FM::Travel::ARRIVE_BEFORE_FAT, t[:fat]
    assert_equal 300 + 3500, t[:cost]
    home = FM::Travel.to_cup(caps["UNOVA"], "UNOVA", "UNOVA", caps)
    assert_equal FM::Travel::NONE, home, "the host capital's own clubs don't travel"
  end

  def test_travel_days_stop_training
    a = FM::Mon.new(species: "PIDGEY", bst: 251, level: 20, stars: 3)
    b = Marshal.load(Marshal.dump(a))
    b.away_days = 7
    FM::Growth.week(a, train_level: 3, species: TestSquad::SPECIES)
    FM::Growth.week(b, train_level: 3, species: TestSquad::SPECIES)
    assert_operator a.prog + a.level, :>, b.prog + b.level
    assert_equal 20, b.level
    assert_in_delta 0.0, b.prog, 1e-9
    assert_nil b.away_days, "counted per week"
  end

  def cities
    [{ id: "FAR", name: "FAR", region: "KANTO", form: "SOLO", size: 1, buildings: [] },
     { id: "NEAR", name: "NEAR", region: "KANTO", form: "SOLO", size: 3, buildings: [[:TRANSPORT, 8]] }]
  end

  def club(id, city)
    { id: id, name: id, region: "KANTO", city: city, role: "T", canon: true, level: 30, potential: 3,
      stadium: 1, pokemon: Array.new(6) { { bst: 450, level: 30, stars: 3 } } }
  end

  def test_away_clubs_pay_fares_and_carry_fatigue_home
    w = FM::World.new_game([club("F", "FAR"), club("N", "NEAR"), club("F2", "FAR"), club("N2", "NEAR")],
                           seed: 1, cities: cities)
    w.advance_days(w.calendar.days_until(FM::Season.league_dates(w.calendar, 1).first) + 21)   # a few rounds
    paid = w.clubs.values.sum { |c| c.wallet.totals.fetch(:travel, 0) }
    assert paid.negative?, "someone travelled"
    assert(w.clubs.values.flat_map(&:squad).any? { |m| m.fat.positive? })
  end
  def test_hub_cuts_days_to_the_capital
    town = City.new("T", 0, "KANTO")
    cap = City.new("C", 10, "KANTO", true)
    other = City.new("O", 6, "KANTO")
    assert_equal 3, FM::Travel.land(town, cap)[:days]
    assert_equal 2, FM::Travel.land(town, cap, hub: 4)[:days], "Lv4 hub: -1 day"
    assert_equal 1, FM::Travel.land(town, cap, hub: 10)[:days]
    assert_equal 3, FM::Travel.land(town, other, hub: 8)[:days], "only trips to the capital"
    assert_equal 0, FM::Travel.land(other, cap, hub: 8)[:days]
  end

  def test_a_night_at_a_better_hotel_rests_more_and_costs_more
    w = FM::World.new_game([club("F", "FAR"), club("N", "NEAR")], seed: 1, cities: cities)
    f, n = w.clubs["F"], w.clubs["N"]
    [f, n].each { |c| c.squad.each { |m| m.cond = 50 } }
    inn = w.cities["FAR"]
    hotel = w.cities["NEAR"]
    hotel.buildings << [:HOTEL, 10]
    f.stay_night(inn, date: [1, 2, 1])
    n.stay_night(hotel, date: [1, 2, 1])
    assert_operator n.entry.first.cond, :>, f.entry.first.cond
    assert_equal(-FM::Travel.hotel_fee(0), f.wallet.totals[:travel])
    assert_equal(-FM::Travel.hotel_fee(10), n.wallet.totals[:travel])
  end

  def test_rest_multiplier_scales_a_resting_week
    a = FM::Mon.new(species: "PIDGEY", bst: 251, level: 20, stars: 3)
    a.cond = 40
    b = Marshal.load(Marshal.dump(a))
    FM::Growth.condition_week(a)
    FM::Growth.condition_week(b, rest_mul: 1.4)
    assert_operator b.cond, :>, a.cond
  end

end
