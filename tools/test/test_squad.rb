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
    52.times { FM::Growth.week(m, train_level: 5, species: SPECIES) }   # design 5 = original 10
    assert_in_delta 510 / 3.0, m.ev, 3
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
