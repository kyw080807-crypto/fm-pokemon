require_relative "test_helper"

class TestRating < Minitest::Test
  def mon(bst, level: 50, stars: 3) = { bst: bst, level: level, stars: stars }

  def test_ivs_and_evs_add_to_base_stats
    # ★3 IVs average 21 per stat -> +63; level 70 -> full 510 EVs -> +63.75
    assert_in_delta 600 + 63 + 63.75, FM::Rating.mon(mon(600, level: 70)), 0.01
    # Level 8 or lower has no pre-training.
    assert_in_delta 300 + 63, FM::Rating.mon(mon(300, level: 8)), 0.01
  end

  def test_more_stars_rate_higher
    assert FM::Rating.mon(mon(500, stars: 5)) > FM::Rating.mon(mon(500, stars: 1))
  end

  def test_team_uses_best_three
    team = [mon(300), mon(500), mon(400), mon(600), mon(200)]
    expected = [600, 500, 400].sum { |b| FM::Rating.mon(mon(b)) } / 3.0
    assert_in_delta expected, FM::Rating.team(team), 0.01
  end

  def test_short_team_is_padded_with_zeroes
    assert_in_delta FM::Rating.mon(mon(600)) / 3.0, FM::Rating.team([mon(600)]), 0.01
  end
end

class TestEconomy < Minitest::Test
  def test_initial_fame_matches_poke_manager
    assert_equal 84, FM::Economy.initial_fame(level: 40, role: "C", canon: true)    # 64+20
    assert_equal 66, FM::Economy.initial_fame(level: 34, role: "E1", canon: true)   # 54.4+12
    assert_equal 27, FM::Economy.initial_fame(level: 12, role: "G1", canon: true)   # 19.2+8
    assert_equal 36, FM::Economy.initial_fame(level: 16, role: "T", canon: true)    # 25.6+10
    assert_equal 26, FM::Economy.initial_fame(level: 16, role: "T", canon: false)
    assert_equal 15, FM::Economy.initial_fame(level: 2, role: "T", canon: false)     # floor 15
  end

  def test_start_funds
    assert_equal 252_000, FM::Economy.start_funds(84)
  end

  def test_stadium_capacity
    assert_equal 1000, FM::Economy.capacity(0)
    assert_equal 2000, FM::Economy.capacity(1)
    assert_equal 12_000, FM::Economy.capacity(4)
  end

  def test_gate_is_capped_and_scales_with_fame
    rng = Random.new(1)
    small = FM::Economy.gate(home_fame: 30, away_fame: 30, wins: 2, stadium: 0, rng: rng)
    assert_equal 1000, small[:attendance], "rental stadium sells out"
    big = FM::Economy.gate(home_fame: 80, away_fame: 60, wins: 5, stadium: 4, rng: rng)
    assert big[:attendance] > small[:attendance]
    assert big[:attendance] <= 12_000
    assert_equal big[:attendance] * big[:price], big[:revenue]
  end

  def test_away_share_limited_to_away_section
    # Away fans can fill at most 30% of the seats (design 05).
    capped = FM::Economy.demand(home_fame: 15, away_fame: 300, wins: 2, capacity: 2000)
    assert capped <= (500 + FM::Economy.fame_eff(15) * 45 + 0.3 * 2000) * 1.0
  end

  def test_weekly_costs_match_poke_manager
    # 60 * lv^1.4: 60 * 2^1.4 = 158, 60 * 10^1.4 = 1507.
    assert_equal 60, FM::Economy.facility_keep(1)
    assert_equal 158, FM::Economy.facility_keep(2)
    assert_equal 1507, FM::Economy.facility_keep(10)
    assert_equal 800, FM::Economy.stadium_keep(0)
    assert_equal 4000, FM::Economy.stadium_keep(4)
    # OVR 100 mon (o = 150): 100 + 150^2/90 = 350; fame 50 -> x1.0
    assert_equal 350, FM::Economy.food(ovr: 100, fame: 50)
    # Expensive star: OVR 150 (o = 225): 100 + 562.5 + 78.1 = 740.6 -> x1.45 at fame 100+
    assert_equal 1070, FM::Economy.food(ovr: 150, fame: 120)
  end

  def test_merch_and_interest
    assert_equal 314, FM::Economy.merch(50)               # 50^1.6 * 0.6 = 313.7
    assert_equal 0, FM::Economy.debt_interest(1000)
    assert_equal 500, FM::Economy.debt_interest(-100_000)
    assert_equal 10, FM::Economy.debt_interest(-100)       # at least 10
  end

  def test_ovr_from_rating
    # Lv50 stat total ~= rating + 30 (+5 per stat) + 55 (HP's extra), / 6.
    assert_equal 100, FM::Economy.ovr(515)
  end

  def test_prizes
    assert_equal 150_000, FM::Economy.league_prize(1)
    assert_equal 90_000, FM::Economy.league_prize(20)
    assert_equal 0, FM::Economy.rebuild_aid(14)
    assert_equal 25_000, FM::Economy.rebuild_aid(15)
    assert_equal 150_000, FM::Economy.rebuild_aid(20)
  end
end
