require_relative "test_helper"
require_relative "test_specialty"   # TestSpecialty::POOL (types, families)

# Poké Manager's scouting office (sendScout / scoutWeek / sendTypeScout /
# scoutPassive / ageGuess / shown stars) and design 05's scouting range.
class TestScouting < Minitest::Test
  POOL = TestSpecialty::POOL

  def world(transport: 6, scouting: 4, pool: POOL)
    cities = [{ id: "C", name: "C", region: "KANTO", form: "SOLO", size: 3, buildings: [[:TRANSPORT, transport]].reject { |_, l| l.zero? } },
              { id: "J", name: "J", region: "JOHTO", form: "SOLO", size: 1, buildings: [] }]
    club = lambda do |id, city, region|
      { id: id, name: id, region: region, city: city, role: "T", canon: false, level: 20, potential: 3, stadium: 1,
        clubhouse: 3, facilities: { TRAINING: 2, SCOUTING: scouting },
        pokemon: [{ species: "PIDGEY", bst: 251, level: 20, stars: 3 }] }
    end
    w = FM::World.new_game([club.("P", "C", "KANTO"), club.("A", "C", "KANTO"), club.("J1", "J", "JOHTO"), club.("J2", "J", "JOHTO")],
                           seed: 2, cities: cities, species: pool)
    w.player_club = "P"
    w.clubs.each_value { |c| c.wallet.record(5_000_000, category: :grant, date: [1, 1, 1]) }
    w
  end

  def test_scouts_in_the_field_and_fees
    w = world(scouting: 2)   # one scout
    assert_equal 1, FM::Scouting.max_scouts(w.clubs["P"])
    assert_nil w.send_scout("KANTO")
    assert_equal :busy, w.send_scout("KANTO")
    assert_equal(-FM::Scouting::FEE, w.clubs["P"].wallet.totals[:scout])
    assert_equal 5, FM::Scouting.max_scouts(world(scouting: 10).clubs["P"]), "Lv10: 1 + 3 + 1"
  end

  def test_low_transport_scouts_only_at_home
    w = world(transport: 4)
    assert_equal ["KANTO"], FM::Scouting.regions(w, w.clubs["P"])
    assert_equal :region, w.send_scout("JOHTO")
    assert_nil w.send_scout(nil, type: "ROCK")
    assert_equal "KANTO", FM::Scouting.state(w)[:assign].last[:region], "a type scout stays home below the world range"
    assert_nil world(transport: 5).send_scout("JOHTO")
  end

  def test_report_next_week_then_expiry
    w = world
    w.send_scout("KANTO")
    w.advance_days(3)
    assert_empty FM::Scouting.state(w)[:cands].reject { |c| c[:passive] }
    events = w.advance_days(8)
    rep = events.find { |e| e[:kind] == :scout_report && !e[:passive] }
    assert rep
    assert_equal FM::Scouting.report_size(w.clubs["P"]), rep[:species].size
    w.advance_days(7 * FM::Scouting::KEEP_WEEKS + 7)
    refute(FM::Scouting.state(w)[:cands].any? { |c| rep[:species].include?(c[:mon].species) && c[:region] == "KANTO" &&
                                                     c[:until] && (c[:until] <=> w.calendar.date) <= 0 })
  end

  def test_type_scout_brings_that_type
    w = world
    assert_nil w.send_scout("JOHTO", type: "ROCK")
    assert_nil FM::Scouting.state(w)[:assign].last[:region], "everywhere: no region to choose"
    assert_equal(-FM::Scouting::TYPE_FEE, w.clubs["P"].wallet.totals[:scout])
    events = w.advance_days(14)
    rep = events.find { |e| e[:kind] == :scout_report && e[:type] }
    assert(rep[:species].all? { |s| FM::Specialty.mon?(POOL, s, "ROCK") })
  end

  def test_regular_reports_come_on_their_own
    w = world
    events = w.advance_days(7 * 12)
    passive = events.select { |e| e[:kind] == :scout_report && e[:passive] }
    assert_operator passive.size, :>=, 12 / FM::Scouting.passive_gap(w.clubs["P"]) - 1
  end

  def test_no_family_twice_in_a_report
    w = world
    got = FM::Scouting.generate(w, w.clubs["P"], 3, region: "KANTO", keep: 4, date: w.calendar.date, rng: Random.new(4))
    fams = got.map { |c| FM::Scout.family(POOL, c[:mon].species) }
    assert_equal fams.uniq.size, fams.size
    refute_includes fams, "PIDGEY", "already in the squad"
  end

  def test_age_guess_narrows_with_level
    rng = Random.new(1)
    lo, hi = FM::Scouting.age_guess(4, 2, rng)
    assert_operator hi - lo, :>, 0
    assert_includes lo..hi, 4
    assert_equal [4, 4], FM::Scouting.age_guess(4, 9, rng)
  end
end
