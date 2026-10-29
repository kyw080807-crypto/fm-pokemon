require_relative "test_helper"
require_relative "test_squad"   # TestSquad::SPECIES

# Poké Manager 지방 이적 (movePartner / moveWhy / moveNow / moveDo).
class TestTransfer < Minitest::Test
  T = FM::Transfer

  def club(id, region, city, role: "T", canon: false, bst: 450)
    { id: id, name: id, region: region, city: city, role: role, canon: canon, level: 30, potential: 3, stadium: 3,
      stadium_shared: city.end_with?("C"), clubhouse: 3, city_size: 2, facilities: { TRAINING: 6, SCOUTING: 6, MEDICAL: 4 },
      pokemon: Array.new(3) { { species: "PIDGEY", bst: bst, level: 30, stars: 3 } } }
  end

  def city(id, region, form: "SOLO", size: 2)
    { id: id, name: id, region: region, form: form, size: size, free_plots: 1, buildings: [] }
  end

  def world
    clubs = [club("P", "KANTO", "K1", role: "G1"), club("K2", "KANTO", "K2"), club("K3", "KANTO", "K2"),
             club("KC", "KANTO", "KC"),
             club("J1", "JOHTO", "J1", bst: 300), club("J2", "JOHTO", "J2", bst: 500, canon: true),
             club("J3", "JOHTO", "J2", bst: 400), club("JC", "JOHTO", "JC", role: "C")]
    cities = [city("K1", "KANTO"), city("K2", "KANTO"), city("KC", "KANTO", form: "LEAGUE", size: 5),
              city("J1", "JOHTO"), city("J2", "JOHTO"), city("JC", "JOHTO", form: "LEAGUE", size: 5)]
    w = FM::World.new_game(clubs, seed: 3, cities: cities, species: TestSquad::SPECIES)
    w.player_club = "P"
    w
  end

  def test_before_the_season_it_happens_at_once
    w = world
    p = w.clubs["P"]
    fame = p.fame
    assert T.now?(w)
    assert_equal "J1", T.partner(w, p, "JOHTO").id, "the weakest non-canon T"
    assert_equal :moved, T.request(w, p, "JOHTO")
    assert_equal "JOHTO", p.region
    assert_equal "J1", p.city
    assert_equal "T", p.role, "roles swap"
    j1 = w.clubs["J1"]
    assert_equal ["KANTO", "K1", "G1"], [j1.region, j1.city, j1.role]
    assert_includes w.cities["J1"].club_ids, "P"
    refute_includes w.cities["K1"].club_ids, "P"
    assert_in_delta fame * 0.7, p.fame, 1e-6
    assert_equal [1, 1, 4], p.facilities.values_at(:TRAINING, :SCOUTING, :MEDICAL)
    assert_equal 0, p.stadium
    assert_in_delta 50.5, p.fsat, 1e-9
    assert_includes w.leagues["JOHTO"].table.keys, "P"
    refute_includes w.leagues["KANTO"].table.keys, "P"
    assert_equal :moved, T.why_not(w, p), "once a season"
  end

  def test_during_the_season_it_waits_for_the_new_year
    w = world
    p = w.clubs["P"]
    w.advance_days(w.calendar.days_until(FM::Season.league_dates(w.calendar, 1).first) + 1)
    refute T.now?(w)
    assert_equal :requested, T.request(w, p, "JOHTO")
    assert_equal :pending, T.why_not(w, p)
    assert_equal "KANTO", p.region
    events = w.advance_days(400)
    assert(events.any? { |e| e[:kind] == :region_moved && e[:club] == "P" })
    assert_equal "JOHTO", p.region
    assert_includes w.leagues["JOHTO"].table.keys, "P"
  end

  def test_into_a_capital_uses_the_side_stadium
    w = world
    p = w.clubs["P"]
    w.clubs.each_value { |c| c.instance_variable_set(:@role, "C") unless %w[P JC].include?(c.id) }
    w.clubs["JC"].instance_variable_set(:@role, "T")
    assert_equal :moved, T.request(w, p, "JOHTO")
    assert_equal "JC", p.city
    assert p.stadium_shared
    jc = w.clubs["JC"]
    refute jc.stadium_shared, "out of the capital: renting"
    assert_equal 0, jc.stadium
  end

  def test_rules
    w = world
    p = w.clubs["P"]
    assert_equal :same, T.request(w, p, "KANTO")
    w.advance_days(w.calendar.days_until(FM::Season.league_dates(w.calendar, 1).first) + 1)
    T.request(w, p, "JOHTO")
    T.cancel(p)
    assert_nil T.why_not(w, p)
  end
end
