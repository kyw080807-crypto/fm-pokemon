require_relative "test_helper"

class TestInvest < Minitest::Test
  def data(id, role: "T", clubhouse: 2, city_size: 2, facilities: { TRAINING: 2, SCOUTING: 1 }, stadium: 1)
    { id: id, name: id, region: "KANTO", city: "C1", role: role, canon: true, level: 30, potential: 3,
      stadium: stadium, stadium_shared: false, clubhouse: clubhouse, city_size: city_size,
      facilities: facilities, pokemon: Array.new(3) { { bst: 450, level: 30, stars: 3 } } }
  end

  def world(*clubs) = FM::World.new_game(clubs + [data("Z1"), data("Z2"), data("Z3")].first(4 - clubs.size), seed: 3)

  def rich!(club, amount = 50_000_000) = club.wallet.record(amount, category: :grant, date: [1, 1, 1])

  def test_poor_club_does_not_invest
    w = world(data("A"))
    a = w.clubs["A"]
    a.wallet.record(-a.wallet.balance, category: :drain, date: [1, 1, 1])   # spend the start funds
    w.advance_days(14)
    assert_nil w.clubs["A"].project
    refute w.clubs["A"].wallet.totals.key?(:invest)
  end

  def test_rich_club_builds_and_waits_for_completion
    w = world(data("A", role: "G1"))
    a = w.clubs["A"]
    rich!(a)
    w.advance_days(7)                       # first Monday: decides
    p = a.project
    refute_nil p
    assert_equal :TRAINING, p[:target], "gym leaders train first (original order)"
    assert_equal(-FM::Build.building_cost(2), a.wallet.totals[:invest])
    assert_equal 2, a.facilities[:TRAINING], "not finished yet"
    w.advance_days(7 * FM::Build.build_weeks(:building, 2))
    assert_equal 3, a.facilities[:TRAINING]
  end

  def test_one_project_at_a_time
    w = world(data("A"))
    rich!(w.clubs["A"])
    w.advance_days(8)
    first = w.clubs["A"].project
    w.advance_days(3)
    assert_equal first, w.clubs["A"].project
  end

  def test_buildings_never_exceed_clubhouse_cap_and_clubhouse_respects_city
    w = world(data("A", clubhouse: 1, city_size: 1))
    a = w.clubs["A"]
    a.fame = 300
    rich!(a, 500_000_000)
    w.advance_days(365 * 3)
    assert a.clubhouse <= FM::Build.clubhouse_max(1), "town clubs stop at clubhouse 2"
    a.facilities.each_value { |lv| assert lv <= FM::Build.building_cap(a.clubhouse) }
    assert a.facilities.size <= FM::Build.club_plots(a.clubhouse)
  end

  def test_clubhouse_needs_fame
    w = world(data("A", clubhouse: 2, city_size: 4, facilities: { TRAINING: 3, SCOUTING: 3, MEDICAL: 3, DAYCARE: 1 }))
    a = w.clubs["A"]
    a.fame = 40                              # below 45 needed for clubhouse 3
    rich!(a, 500_000_000)
    w.advance_days(7 * 12)
    assert_equal 2, a.clubhouse
  end

  def test_shared_stadium_is_not_upgraded_by_a_club
    d = data("A").merge(stadium_shared: true)
    w = world(d)
    a = w.clubs["A"]
    rich!(a, 500_000_000)
    w.advance_days(365)
    assert_equal 1, a.stadium
  end
end
