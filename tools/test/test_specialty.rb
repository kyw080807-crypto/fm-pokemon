require_relative "test_helper"
require_relative "test_cand_rules"   # TestCandRules::POOL

# 전문 타입 규정 (Poké Manager SIG_BY / sigBlock / sigParty / genCand).
class TestSpecialty < Minitest::Test
  POOL = TestCandRules::POOL.merge(
    "RHYHORN" => { bst: 345, fb: 485, tier: 0, region: "KANTO", basic: true, evo: [["RHYDON", 42]], types: %w[GROUND ROCK] },
    "RHYDON"  => { bst: 485, fb: 485, tier: 0, region: "KANTO", basic: false, evo: [], types: %w[GROUND ROCK], prev: "RHYHORN" },
    "MAGIKARP" => { bst: 200, fb: 540, tier: 0, region: "KANTO", basic: true, evo: [["GYARADOS", 20]], types: %w[WATER] },
    "GYARADOS" => { bst: 540, fb: 540, tier: 0, region: "KANTO", basic: false, evo: [], types: %w[WATER FLYING], prev: "MAGIKARP" }
  ).freeze

  def setup
    @saved = FM::Scout.pool
    FM::Scout.pool = POOL
  end

  def teardown
    FM::Scout.pool = @saved
  end

  def club(role, squad, clubhouse: 3)
    FM::Club.new({ id: "X", name: "X", region: "KANTO", city: "C", role: role, canon: false, level: 20, potential: 3,
                   stadium: 1, clubhouse: clubhouse, type: "ROCK",
                   pokemon: squad.map { |s, lv| { species: s, bst: POOL[s][:bst], level: lv || 20, stars: 3 } } })
  end

  def test_types_belong_to_the_post
    assert_equal "ROCK", FM::Specialty.of(club("G1", []))
    assert_equal "ICE", FM::Specialty.of(club("E1", []))
    assert_nil FM::Specialty.of(club("C", []))
    assert_nil FM::Specialty.of(club("T", []))
  end

  def test_evolved_types_count
    assert FM::Specialty.mon?(POOL, "MAGIKARP", "FLYING"), "Gyarados is flying"
    refute FM::Specialty.mon?(POOL, "TOTODILE", "ROCK")
  end

  def test_squad_cap_for_other_types
    cap = FM::Specialty.other_cap(club("G1", []))
    assert_equal FM::Build.squad_size(3) - FM::Specialty::SQUAD_SHARE, cap
    c = club("G1", [["ONIX"]] + Array.new(cap) { ["TOTODILE"] })
    pidgey = FM::Mon.new(species: "PIDGEY", bst: 251, level: 20, stars: 3)
    assert FM::Specialty.block?(c, pidgey, POOL)
    refute FM::Specialty.block?(c, FM::Mon.new(species: "GEODUDE", bst: 300, level: 20, stars: 3), POOL)
    refute FM::Specialty.block?(club("T", c.squad.map { |m| [m.species] }), pidgey, POOL), "trainers are free"
    assert_equal :specialty, FM::Recruit.sign_block(c, { mon: pidgey, cost: 1 }, POOL) unless
      FM::Recruit.hg_block?(c, pidgey, POOL)
  end

  def test_entry_keeps_at_most_two_others
    # Strong water mons, weaker rock ones: the entry still has 4 rock.
    c = club("G1", [["GYARADOS", 60], ["GYARADOS", 60], ["GYARADOS", 60], ["TOTODILE", 60],
                    ["ONIX", 20], ["GEODUDE", 20], ["RHYDON", 20], ["RHYHORN", 20]], clubhouse: 4)
    e = c.entry
    others = e.count { |m| !FM::Specialty.mon?(POOL, m.species, "ROCK") }
    assert_equal 6, e.size
    assert_equal FM::Specialty.entry_other_cap, others
    t = club("T", c.squad.map { |m| [m.species, m.level] }, clubhouse: 4)
    assert_equal 4, t.entry.count { |m| !FM::Specialty.mon?(POOL, m.species, "ROCK") }, "no rule for trainers"
  end

  def test_scouting_brings_specialty_candidates_about_half_the_time
    c = club("G1", [["ONIX"]])
    c.wallet.record(10_000_000, category: :grant, date: [1, 1, 1])
    rng = Random.new(5)
    cands = Array.new(40) { FM::Recruit.scout(c, pool: POOL, region: "KANTO", avg_level: 20, rng: rng, date: [1, 2, 1]) }.flatten
    share = cands.count { |cd| FM::Specialty.mon?(POOL, cd[:mon].species, "ROCK") }.fdiv(cands.size)
    assert_operator share, :>, 0.4
  end
end
