require_relative "test_helper"
require_relative "test_tournament_world"   # TestTournamentWorld#world: 9 regions x 20 clubs

class TestView < Minitest::Test
  def world = TestTournamentWorld.new("x").world

  def test_standings_rows
    w = world
    w.advance_days(60)
    rows = FM::View.standings(w, "KANTO")
    assert_equal 20, rows.size
    assert_equal (1..20).to_a, rows.map { |r| r[:pos] }
    assert rows.first[:pts] >= rows.last[:pts]
    assert_equal %i[pos id name p w d l kf ka pts rating], rows.first.keys
  end

  def test_club_summary
    w = world
    s = FM::View.club(w, "KANTO_00")
    assert_equal "KANTO0", s[:name]
    assert s[:balance].is_a?(Integer)
    assert_equal 3, s[:squad].size
    assert(s[:squad].all? { |m| m.key?(:species) && m.key?(:level) })
  end

  def test_season_phase_and_next_event
    w = world
    st = FM::View.season(w)
    assert_equal :preseason, st[:phase]
    assert_equal :league, st[:next][:kind]
    w.advance_days(60)
    assert_equal :league, FM::View.season(w)[:phase]
    w.advance_days(265)
    assert_includes %i[cups offseason], FM::View.season(w)[:phase]
  end

  def test_cups_view_after_draw
    w = world
    w.advance_days(300)
    c = FM::View.cups(w)
    refute_nil c
    assert_equal 32, c[:pwt][:players].size
  end
end

require_relative "test_committee"

class TestViewCity < Minitest::Test
  def test_city_and_committee_views
    w = TestCommittee.new("x").world
    w.cities["CAP"].budget.record(20_000_000, category: :grant, date: [1, 1, 1])
    w.clubs.each_value { |c| c.wallet.record(5_000_000, category: :grant, date: [1, 1, 1]) }
    w.advance_days(200)
    v = FM::View.city(w, "TOWN", viewer: "K4")
    assert_equal 4, v[:clubs].size
    assert_nil v[:clubs].find { |c| c[:id] == "K4" }[:relation]
    assert v[:clubs].find { |c| c[:id] == "K5" }[:relation].is_a?(Float)
    refute_empty v[:log], "town held meetings"
    assert(v[:log].all? { |e| e.key?(:agenda) && e.key?(:yes) })
    assert_operator v[:log].size, :<=, FM::City::LOG_SIZE
    cm = FM::View.committee(w, "KANTO")
    assert_equal 6, cm[:members].size
    refute_empty cm[:log]
    assert_equal 4, cm[:facilities][:SIDE_STADIUM]
    assert_nil FM::View.committee(w, "JOHTO")
  end
end
