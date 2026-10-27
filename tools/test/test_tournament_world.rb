require_relative "test_helper"

class TestTournamentWorld < Minitest::Test
  # 9 regions x 20 clubs; within a region club 0 is strongest.
  def world(seed = 1)
    clubs = FM::Tournament::ALL_REGIONS.flat_map do |region|
      (0...20).map do |i|
        { id: format("%s_%02d", region, i), name: "#{region}#{i}", region: region, city: "C", role: i.zero? ? "C" : "T",
          canon: true, level: 40 - i, potential: 3, stadium: 1,
          pokemon: Array.new(3) { { bst: 650 - i * 12, level: 50, stars: 3 } } }
      end
    end
    FM::World.new_game(clubs, seed: seed)
  end

  def test_full_year_runs_all_three_tournaments
    w = world
    events = w.advance_days(364)                    # Dec 31, year 1
    pets = events.select { |e| e[:kind] == :cup_champion }
    assert_equal %i[pent pet pwt], pets.map { |e| e[:cup] }.sort
    pwt = events.find { |e| e[:kind] == :cup_champion && e[:cup] == :pwt }
    sub_champs = pets.reject { |e| e[:cup] == :pwt }.map { |e| e[:club] }
    entrants = w.cups[:pwt][:players]
    assert_equal 36, entrants.size
    sub_champs.each { |c| assert_includes entrants, c }
    champ = w.clubs[pwt[:club]]
    assert champ.wallet.totals[:prize] >= FM::Tournament::CHAMPION_PRIZE
    assert_equal :champion, champ.history[1][:pwt]
  end

  def test_pwt_entrants_pay_travel_and_league_toppers_qualify
    w = world
    w.advance_days(364)
    entrants = w.cups[:pwt][:players]
    FM::Tournament::ALL_REGIONS.each do |r|
      assert entrants.count { |id| w.clubs[id].region == r } >= 3
    end
    assert(entrants.all? { |id| w.clubs[id].wallet.totals.fetch(:travel, 0) <= -FM::Tournament::PWT_FEE })
  end

  def test_coefficient_uses_last_seasons
    w = world
    w.advance_days(365 * 2)
    coef = w.league_coefficients
    assert_equal FM::Tournament::ALL_REGIONS.sort, coef.keys.sort
    assert coef.values.any?(&:positive?)
  end
end
