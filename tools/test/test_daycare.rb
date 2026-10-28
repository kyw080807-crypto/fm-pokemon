require_relative "test_helper"

# Poké Manager 키우미집 (dcCompat / dcMother / dcBabySp / dcBaby / dcWeek).
class TestDaycare < Minitest::Test
  POOL = {
    "CHARMANDER" => { bst: 309, fb: 534, tier: 0, region: "KANTO", basic: true, evo: [["CHARMELEON", 16]], types: %w[FIRE],
                      eggs: %w[Monster Dragon], gender: "FemaleOneEighth" },
    "CHARMELEON" => { bst: 405, fb: 534, tier: 0, region: "KANTO", basic: false, evo: [], types: %w[FIRE], prev: "CHARMANDER",
                      eggs: %w[Monster Dragon], gender: "FemaleOneEighth" },
    "SNORLAX" => { bst: 540, fb: 540, tier: 0, region: "KANTO", basic: true, evo: [], types: %w[NORMAL],
                   eggs: %w[Monster], gender: "FemaleOneEighth" },
    "MUNCHLAX" => { bst: 390, fb: 540, tier: 0, region: "SINNOH", basic: true, evo: [["SNORLAX", 20]], types: %w[NORMAL],
                    eggs: %w[Undiscovered], gender: "FemaleOneEighth" },
    "DITTO" => { bst: 288, fb: 288, tier: 0, region: "KANTO", basic: true, evo: [], types: %w[NORMAL],
                 eggs: %w[Ditto], gender: "Genderless" },
    "MAGNEMITE" => { bst: 325, fb: 535, tier: 0, region: "KANTO", basic: true, evo: [], types: %w[ELECTRIC STEEL],
                     eggs: %w[Mineral], gender: "Genderless" },
    "MEWTWO" => { bst: 680, fb: 680, tier: 2, region: "KANTO", basic: true, evo: [], types: %w[PSYCHIC],
                  eggs: %w[Undiscovered], gender: "Genderless" }
  }.freeze

  def mon(species, gender: nil, stars: 3)
    m = FM::Mon.new(species: species, bst: POOL[species][:bst], level: 30, stars: stars)
    if gender   # find a seed that gives this gender
      s = 0
      s += 1 until (m.instance_variable_set(:@seed, s); FM::Daycare.gender(POOL, m) == gender)
    end
    m
  end

  def club(daycare: 2)
    c = FM::Club.new({ id: "X", name: "X", region: "KANTO", city: "C", role: "T", canon: false, level: 20, potential: 3,
                       stadium: 1, clubhouse: 3, facilities: { DAYCARE: daycare }, pokemon: [] })
    c.wallet.record(1_000_000, category: :grant, date: [1, 1, 1])
    c
  end

  def test_compat_rules
    m, f = mon("CHARMANDER", gender: :M), mon("CHARMELEON", gender: :F)
    assert_equal 0.1, FM::Daycare.compat(POOL, m, f)[:rate], "same family"
    assert_equal 0.06, FM::Daycare.compat(POOL, mon("SNORLAX", gender: :M), f)[:rate], "egg group Monster"
    assert_equal :same_gender, FM::Daycare.compat(POOL, m, mon("CHARMANDER", gender: :M))[:why]
    assert_equal 0.04, FM::Daycare.compat(POOL, mon("MAGNEMITE"), mon("DITTO"))[:rate], "genderless with Ditto"
    assert_equal :genderless, FM::Daycare.compat(POOL, mon("MAGNEMITE"), f)[:why]
    assert_equal :two_dittos, FM::Daycare.compat(POOL, mon("DITTO"), mon("DITTO"))[:why]
    assert_equal :legend, FM::Daycare.compat(POOL, mon("MEWTWO"), mon("DITTO"))[:why]
  end

  def test_baby_is_the_mothers_first_stage
    f = mon("CHARMELEON", gender: :F)
    assert_equal "CHARMANDER", FM::Daycare.baby_species(POOL, f)
    with_ditto = FM::Daycare.mother(POOL, mon("DITTO"), mon("SNORLAX", gender: :M))
    assert_equal "SNORLAX", with_ditto.species, "the non-Ditto parent"
    assert_equal "SNORLAX", FM::Daycare.baby_species(POOL, mon("MUNCHLAX")), "incense baby hatches a stage up"
  end

  def test_baby_inherits_from_parent_stars
    c = club
    rng = Random.new(1)
    hi = Array.new(40) { FM::Daycare.baby(POOL, c, mon("CHARMANDER", gender: :M, stars: 5), mon("CHARMELEON", gender: :F, stars: 5), rng, year: 1) }
    lo = Array.new(40) { FM::Daycare.baby(POOL, c, mon("CHARMANDER", gender: :M, stars: 1), mon("CHARMELEON", gender: :F, stars: 1), rng, year: 1) }
    assert_operator hi.sum(&:stars), :>, lo.sum(&:stars)
    b = hi.first
    assert_equal [1, 120, "X"], [b.level, b.bond, b.hatched_by]
  end

  def test_week_costs_lays_and_hatches
    c = club(daycare: 5)
    w = Struct.new(:species, :calendar) do
      def ai?(_) = false
    end.new(POOL, FM::Calendar.new)
    a, b = mon("CHARMANDER", gender: :M), mon("CHARMELEON", gender: :F)
    c.retire(a)
    c.retire(b)
    FM::Daycare.state(c)[:pairs] << [a, b]
    events = []
    rng = Random.new(3)
    60.times do
      events.concat(FM::Daycare.week(w, c, rng))
      w.calendar.advance(7)
    end
    assert(events.any? { |e| e[:kind] == :egg })
    assert(events.any? { |e| e[:kind] == :hatched })
    assert(c.squad.any? { |m| m.hatched_by == "X" })
    assert_operator c.wallet.totals[:daycare], :<, 0
    assert FM::Recruit.home?(c, c.squad.find { |m| m.hatched_by }, POOL), "homegrown"
  end

  def test_no_building_no_breeding
    c = club(daycare: 0)
    w = Struct.new(:species, :calendar) { def ai?(_) = true }.new(POOL, FM::Calendar.new)
    a, b = mon("CHARMANDER", gender: :M), mon("CHARMELEON", gender: :F)
    c.retire(a)
    c.retire(b)
    FM::Daycare.ai_pick(w, c, 1)
    assert_empty FM::Daycare.state(c)[:pairs]
  end
end
