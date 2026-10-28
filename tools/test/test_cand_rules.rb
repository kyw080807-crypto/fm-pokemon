require_relative "test_helper"

# Poké Manager aiCandOk / aiCandScore / hgBlock / famDup ported to Recruit.
class TestCandRules < Minitest::Test
  POOL = {
    "CHARMANDER" => { bst: 309, fb: 534, tier: 0, region: "KANTO", basic: true, evo: [["CHARMELEON", 16]], types: %w[FIRE] },
    "CHARMELEON" => { bst: 405, fb: 534, tier: 0, region: "KANTO", basic: false, evo: [], types: %w[FIRE], prev: "CHARMANDER" },
    "PIDGEY"     => { bst: 251, fb: 479, tier: 0, region: "KANTO", basic: true, evo: [], types: %w[NORMAL FLYING] },
    "ONIX"       => { bst: 385, fb: 510, tier: 0, region: "KANTO", basic: true, evo: [], types: %w[ROCK GROUND] },
    "GEODUDE"    => { bst: 300, fb: 495, tier: 0, region: "KANTO", basic: true, evo: [], types: %w[ROCK GROUND] },
    "TOTODILE"   => { bst: 314, fb: 530, tier: 0, region: "JOHTO", basic: true, evo: [], types: %w[WATER] },
    "ARTICUNO"   => { bst: 580, fb: 580, tier: 1, region: "KANTO", basic: true, evo: [], types: %w[ICE FLYING] },
    "ZAPDOS"     => { bst: 580, fb: 580, tier: 1, region: "KANTO", basic: true, evo: [], types: %w[ELECTRIC FLYING] }
  }.freeze

  def club(role: "G1", type: "ROCK", squad: %w[PIDGEY], clubhouse: 2, canon: false)
    c = FM::Club.new({ id: "X", name: "X", region: "KANTO", city: "C", role: role, canon: canon, level: 20,
                       potential: 3, stadium: 1, clubhouse: clubhouse, type: type,
                       pokemon: squad.map { |s| { species: s, bst: POOL[s][:bst], level: 20, stars: 3 } } })
    c
  end

  def cand(species, stars: 3, age: 0)
    { mon: FM::Mon.new(species: species, bst: POOL[species][:bst], level: 20, stars: stars, age: age), cost: 1000 }
  end

  def test_family_and_home
    assert_equal "CHARMANDER", FM::Scout.family(POOL, "CHARMELEON")
    assert FM::Scout.home?(POOL, "CHARMELEON", "KANTO")
    refute FM::Scout.home?(POOL, "TOTODILE", "KANTO")
  end

  def test_no_second_of_a_family_or_a_second_sub_legend
    c = club(squad: %w[CHARMANDER ARTICUNO])
    refute FM::Recruit.cand_ok?(c, cand("CHARMELEON"), POOL)
    refute FM::Recruit.cand_ok?(c, cand("ZAPDOS"), POOL)
    assert FM::Recruit.cand_ok?(c, cand("ONIX"), POOL)
  end

  def test_gym_leaders_want_their_type
    gym = club(role: "G1", type: "ROCK")
    trainer = club(role: "T", type: "ROCK")
    rock = FM::Recruit.cand_score(gym, cand("ONIX"), POOL)
    water = FM::Recruit.cand_score(gym, cand("TOTODILE"), POOL)
    assert_operator rock, :>, water
    # Kanto G1 = rock specialty: 510 x 1.05 x 1.25 x 1.35, another type 530 x 1.05 x 0.6 x 0.75.
    assert_in_delta 510 * 1.05 * 1.25 * 1.35, rock, 1e-6
    assert_in_delta 530 * 1.05 * 0.6 * 0.75, water, 1e-6
    assert_in_delta 530 * 1.05, FM::Recruit.cand_score(trainer, cand("TOTODILE"), POOL), 1e-6, "non-canon trainers: no type"
    canon = club(role: "T", type: "ROCK", canon: true)
    assert_in_delta 530 * 1.05 * 0.95, FM::Recruit.cand_score(canon, cand("TOTODILE"), POOL), 1e-6
  end

  def test_types_already_covered_and_seasons_left
    c = club(role: "T", squad: %w[GEODUDE])
    assert_in_delta 510 * 1.05 * 0.92, FM::Recruit.cand_score(c, cand("ONIX"), POOL), 1e-6
    old = FM::Recruit.cand_score(c, cand("TOTODILE", age: 8), POOL)
    assert_in_delta 530 * 1.05 * FM::Scout.remain_f(8), old, 1e-6
    assert_in_delta 1.0, FM::Scout.remain_f(4)
    assert_in_delta 0.5 + 0.5 * 2 / 6.0, FM::Scout.remain_f(8)
  end

  def test_homegrown_cap_for_outsiders
    # Clubhouse 2 -> squad size; outsiders at most that minus HG_MIN.
    cap = FM::Build.squad_size(2) - FM::Recruit::HG_MIN
    c = club(squad: %w[PIDGEY])
    cap.times { |i| c.squad << FM::Mon.new(species: "TOTODILE", bst: 314, level: 10 + i, stars: 3) }
    assert FM::Recruit.hg_block?(c, cand("TOTODILE")[:mon], POOL)
    refute FM::Recruit.hg_block?(c, cand("ONIX")[:mon], POOL), "a home mon is always fine"
    outsider = c.squad.last
    refute FM::Recruit.hg_block?(c, cand("TOTODILE")[:mon], POOL, replacing: outsider), "replacing an outsider"
    assert_equal :homegrown, FM::Recruit.sign_block(c, cand("TOTODILE"), POOL)
  end

  def test_player_sign_is_blocked_with_a_reason
    c = club(squad: %w[CHARMANDER])
    c.wallet.record(1_000_000, category: :grant, date: [1, 1, 1])
    assert_raises(FM::Recruit::Blocked) { FM::Recruit.sign(c, cand("CHARMELEON"), date: [1, 2, 1], pool: POOL) }
    FM::Recruit.sign(c, cand("ONIX"), date: [1, 2, 1], pool: POOL)
    assert_equal 2, c.squad.size
  end
end
