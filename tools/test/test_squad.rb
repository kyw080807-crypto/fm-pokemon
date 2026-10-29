require_relative "test_helper"

class TestSquad < Minitest::Test
  SPECIES = {
    "CHARMANDER" => { bst: 309, fb: 534, tier: 0, region: "KANTO", basic: true, evo: [["CHARMELEON", 16]] },
    "CHARMELEON" => { bst: 405, fb: 534, tier: 0, region: "KANTO", basic: false, evo: [["CHARIZARD", 36]] },
    "CHARIZARD"  => { bst: 534, fb: 534, tier: 0, region: "KANTO", basic: false, evo: [] },
    "PIDGEY"     => { bst: 251, fb: 479, tier: 0, region: "KANTO", basic: true, evo: [] },
    "SNORLAX"    => { bst: 540, fb: 540, tier: 0, region: "KANTO", basic: true, evo: [] },
    "MEWTWO"     => { bst: 680, fb: 680, tier: 2, region: "KANTO", basic: true, evo: [] },
    "TOTODILE"   => { bst: 314, fb: 530, tier: 0, region: "JOHTO", basic: true, evo: [] }
  }.freeze

  def mon(species: "CHARMANDER", level: 10, ev: 0, age: 0, stars: 3)
    FM::Mon.new(species: species, bst: SPECIES[species][:bst], level: level, stars: stars, ev: ev, age: age)
  end

  def test_grow_seasons_and_weekly_ev_from_poke_manager
    assert_in_delta 5.0, FM::Growth.grow_seasons(1), 1e-9
    assert_in_delta 3.0, FM::Growth.grow_seasons(10), 1e-9
    # A year of training fills 510 / growSeasons.
    m = mon
    # Real weeks: condition first (trains until 60, rests back to 85), then
    # growth; plus a match every other week. Rest weeks give no EVs, so a year comes
    # close to the 510 / growSeasons target.
    52.times do |w|
      FM::Growth.condition_week(m)
      FM::Growth.week(m, train_level: 10, species: SPECIES)
      next unless w.even?                                    # squads rotate: a match every other week
      FM::Growth.drain(m, FM::Growth::MATCH_COND)
      m.played = true
    end
    assert_in_delta 510 / 3.0, m.ev, 510 / 3.0 * 0.2
    assert m.cond.between?(FM::Growth::COND_MIN, 100)
  end

  def test_ev_never_exceeds_510
    m = mon(ev: 509)
    10.times { FM::Growth.week(m, train_level: 5, species: SPECIES) }
    assert_equal 510, m.ev.round
  end

  def test_levels_rise_and_trigger_evolution
    m = mon(level: 15)
    20.times { FM::Growth.week(m, train_level: 3, species: SPECIES) }
    assert m.level > 15
    assert_equal "CHARMELEON", m.species
    assert_equal 405, m.bst
  end

  def test_better_training_grows_faster
    a = mon(level: 10)
    b = mon(level: 10)
    30.times do
      FM::Growth.week(a, train_level: 1, species: SPECIES)
      FM::Growth.week(b, train_level: 5, species: SPECIES)
    end
    assert b.level > a.level
    assert b.ev > a.ev
  end

  def test_season_rollover_ages_and_retires_at_ten
    squad = [mon(age: 9), mon(age: 3)]
    retired = FM::Growth.rollover(squad)
    assert_equal 1, retired.size
    assert_equal [4], squad.map(&:age)
  end

  def test_fame_drifts_toward_forty
    assert_in_delta 40 + (60 - 40) * 0.92, FM::Growth.fame_drift(60), 1e-9
    assert FM::Growth.fame_drift(150) < 150 - (150 - 40) * 0.08
  end

  def test_candidates_follow_scouting_level
    rng = Random.new(4)
    pool = SPECIES
    low  = Array.new(400) { FM::Scout.candidate(pool, region: "KANTO", scout_level: 1, avg_level: 30, rng: rng) }
    high = Array.new(400) { FM::Scout.candidate(pool, region: "KANTO", scout_level: 5, avg_level: 30, rng: rng) }
    fb = ->(cs) { cs.sum { |c| pool[c[:base]][:fb] }.fdiv(cs.size) }
    assert fb.(high) > fb.(low)
    assert low.none? { |c| c[:base] == "MEWTWO" }, "legendaries are never scouted"
    (low + high).each do |c|
      assert_equal 0, c[:cost] % 500
      assert c[:cost].positive?
      assert c[:mon].stars.between?(1, 5)
      assert c[:mon].ev.between?(0, 510)
    end
  end

  def test_candidate_is_evolved_to_its_level
    rng = Random.new(1)
    c = Array.new(200) { FM::Scout.candidate(SPECIES, region: "KANTO", scout_level: 5, avg_level: 60, rng: rng) }
    evolved = c.select { |x| x[:base] == "CHARMANDER" && x[:mon].level >= 36 }
    evolved.each { |x| assert_equal "CHARIZARD", x[:mon].species }
  end
end

class TestCondition < Minitest::Test
  def mon(cond) = FM::Mon.new(species: "PIDGEY", bst: 251, level: 20, stars: 3).tap { |m| m.cond = cond }

  def test_rest_below_sixty_until_eighty_five
    m = mon(55)
    FM::Growth.condition_week(m)
    assert m.resting
    assert_equal 55 + (10 + 45 * 0.2).round, m.cond
    m.cond = 80
    FM::Growth.condition_week(m)
    assert m.resting, "keeps resting until 85"
    m.cond = 90
    FM::Growth.condition_week(m)
    refute m.resting
    assert_equal 87, m.cond
  end

  def test_floor_and_old_saves
    m = mon(22)
    FM::Growth.drain(m, 10)
    assert_equal FM::Growth::COND_MIN, m.cond
    m.remove_instance_variable(:@cond)
    assert_equal 100, m.cond
  end

  def test_condition_lowers_team_strength
    fresh = [{ bst: 500, level: 50, stars: 3, cond: 100 }] * 3
    tired = [{ bst: 500, level: 50, stars: 3, cond: 20 }] * 3
    assert FM::Rating.team(fresh) > FM::Rating.team(tired)
    assert_in_delta FM::Rating.team(fresh) * FM::Rating.cond_eff(20), FM::Rating.team(tired), 0.01
  end

  # condDebuff tiers: under 50 speed -1, under 35 + main attack, under 25 + both defences.
  def test_condition_stat_drops_follow_the_original_tiers
    assert_equal [], FM::Rating.debuff(50)
    assert_equal %i[spe], FM::Rating.debuff(49)
    assert_equal %i[spe main], FM::Rating.debuff(34)
    assert_equal %i[spe main def spd], FM::Rating.debuff(24)
    assert_in_delta 0.95 * 0.9 * 0.96 * 0.96, FM::Rating.debuff_mul(FM::Rating.debuff(20)), 1e-9
  end

  def test_light_injury_adds_its_stat
    m = mon(80)
    FM::Injury.injure(m, :battle, Random.new(1), :bruise)
    assert_equal %i[def], m.debuffs
    m.cond = 40
    assert_equal %i[spe def], m.debuffs
  end
end

class TestTravelFatigue < Minitest::Test
  def club(id, city)
    { id: id, name: id, region: "KANTO", city: city, role: "T", canon: true, level: 30, potential: 3,
      stadium: 1, pokemon: Array.new(3) { { bst: 450, level: 30, stars: 3 } } }
  end

  def test_away_side_tires_by_its_city_transport
    cities = [{ id: "FAR", name: "FAR", region: "KANTO", form: "SOLO", size: 1, buildings: [] },       # transport Lv0: 3 days
              { id: "NEAR", name: "NEAR", region: "KANTO", form: "SOLO", size: 3, buildings: [[:TRANSPORT, 8]] }]
    w = FM::World.new_game([club("F", "FAR"), club("N", "NEAR"), club("F2", "FAR"), club("N2", "NEAR")], seed: 1, cities: cities)
    assert_equal 3 * 2 + 3, w.send(:travel_fatigue, w.clubs["F"], w.clubs["N"])
    assert_equal 1 * 2 + 3, w.send(:travel_fatigue, w.clubs["N"], w.clubs["F"])
    assert_equal 0, w.send(:travel_fatigue, w.clubs["F"], w.clubs["F2"]), "same city: no travel"
  end
end
