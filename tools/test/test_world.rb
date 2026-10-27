require_relative "test_helper"

class TestWorld < Minitest::Test
  REGIONS = %w[KANTO JOHTO].freeze

  # Two small regions of 4 clubs; club 0 of each region is much stronger.
  def club_data
    REGIONS.flat_map do |region|
      (0...4).map do |i|
        bst = i.zero? ? 650 : 380
        { id: "#{region}_#{i}", name: "#{region} #{i}", region: region, city: "C_#{region}",
          role: i.zero? ? "C" : "T", canon: true, level: i.zero? ? 40 : 20, potential: 3, stadium: i % 3,
          facilities: { TRAINING: 3, MEDICAL: 2 },
          pokemon: Array.new(3) { { bst: bst, level: 40, stars: 3 } } }
      end
    end
  end

  def world(seed = 1) = FM::World.new_game(club_data, seed: seed)

  def test_new_game_sets_up_clubs_and_leagues
    w = world
    assert_equal 8, w.clubs.size
    assert_equal REGIONS.sort, w.leagues.keys.sort
    c = w.clubs["KANTO_0"]
    assert_equal FM::Economy.initial_fame(level: 40, role: "C", canon: true), c.fame
    assert_equal FM::Economy.start_funds(c.fame), c.wallet.balance
    assert c.rating > w.clubs["KANTO_1"].rating
  end

  def test_no_matches_in_preseason
    w = world
    events = w.advance_days(31)
    assert events.none? { |e| e[:kind] == :league_round }
    assert_equal [1, 2, 1], w.calendar.date
  end

  def test_league_days_play_rounds_and_move_money
    w = world
    first = FM::Season.league_dates(w.calendar, 1).first
    events = w.advance_days(w.calendar.days_until(first))
    rounds = events.select { |e| e[:kind] == :league_round }
    assert_equal 2, rounds.size, "one round per region on the first league Sunday"
    assert_equal 1, w.leagues["KANTO"].next_round
    gate = w.clubs.values.sum { |c| c.wallet.totals.fetch(:gate, 0) }
    bonus = w.clubs.values.sum { |c| c.wallet.totals.fetch(:bonus, 0) }
    assert gate.positive?, "home clubs take gate money"
    assert bonus >= 2 * FM::Economy::DRAW_BONUS, "winners (or drawers) get a bonus"
  end

  def test_full_season_finishes_and_pays_prizes
    w = world
    events = w.advance_days(365)
    ends = events.select { |e| e[:kind] == :league_end }
    assert_equal 2, ends.size
    # A 4-club league is a 6-round double round robin; the rest of the 38
    # league dates go unused.
    assert w.leagues.values.all?(&:done?) || w.calendar.date == [2, 1, 1]
    champion = ends.find { |e| e[:region] == "KANTO" }[:standings].first
    assert_equal "KANTO_0", champion, "the much stronger club should win its league"
    assert w.clubs["KANTO_0"].wallet.totals[:prize] >= FM::Economy.league_prize(1)
  end

  def test_new_year_starts_new_leagues
    w = world
    w.advance_days(365)
    assert_equal [2, 1, 1], w.calendar.date
    assert(w.leagues.values.all? { |l| l.next_round.zero? })
  end

  def test_weekly_economy_charges_and_pays_on_mondays
    w = world
    w.advance_days(6)                        # Jan 7, Sunday: no week boundary yet
    assert w.clubs.values.none? { |c| c.wallet.totals.key?(:food) }
    w.advance_days(1)                        # Jan 8, Monday
    c = w.clubs["KANTO_0"]
    t = c.wallet.totals
    assert t[:food].negative?
    assert t[:std].negative?
    assert t[:merch].positive?
    assert_equal 1, c.wallet.entries.count { |e| e.category == :food }
  end

  def test_deterministic_for_a_seed
    a = world(5).tap { |w| w.advance_days(200) }
    b = world(5).tap { |w| w.advance_days(200) }
    assert_equal a.clubs.values.map { |c| [c.fame, c.wallet.balance] },
                 b.clubs.values.map { |c| [c.fame, c.wallet.balance] }
  end
end
