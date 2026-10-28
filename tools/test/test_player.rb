require_relative "test_helper"
require_relative "test_squad"   # TestSquad::SPECIES

class TestPlayer < Minitest::Test
  SPECIES = TestSquad::SPECIES

  def club(id)
    { id: id, name: id, region: "KANTO", city: "C", role: "G1", canon: false, level: 20, potential: 3,
      stadium: 1, clubhouse: 2, city_size: 2, facilities: { TRAINING: 2, SCOUTING: 2 },
      pokemon: [{ species: "CHARMANDER", bst: 309, level: 14, stars: 3 },
                { species: "PIDGEY", bst: 251, level: 12, stars: 3 },
                { species: "TOTODILE", bst: 314, level: 12, stars: 3 }] }
  end

  def world
    w = FM::World.new_game(%w[P A B C].map { |id| club(id) }, seed: 4, species: SPECIES)
    w.player_club = "P"
    w.clubs.each_value { |c| c.wallet.record(20_000_000, category: :grant, date: [1, 1, 1]) }
    w
  end

  def test_ai_leaves_the_player_club_alone
    w = world
    events = w.advance_days(365)
    p = w.clubs["P"]
    refute p.wallet.totals.key?(:invest), "AI must not build for the player"
    refute p.wallet.totals.key?(:sign)
    assert events.none? { |e| %i[signed released].include?(e[:kind]) && e[:club] == "P" }
    assert w.clubs["A"].wallet.totals.key?(:invest), "other clubs still invest"
  end

  def test_build_options_and_start
    w = world
    p = w.clubs["P"]
    opts = FM::Invest.options(p)
    targets = opts.map { |o| o[1] }
    assert_includes targets, :TRAINING
    assert_includes targets, :STADIUM
    assert_includes targets, :MEDICAL, "new buildings on free plots"
    refute_includes targets, :CLUBHOUSE, "clubhouse 3 is over city size 2 + 1? no: needs fame 45" if p.fame < 45
    choice = opts.find { |o| o[1] == :TRAINING }
    FM::Invest.start(p, choice, date: w.calendar.date, calendar: w.calendar)
    assert_raises(ArgumentError) { FM::Invest.start(p, choice, date: w.calendar.date, calendar: w.calendar) }
    w.advance_days(7 * (FM::Build.build_weeks(:building, 2) + 1))
    assert_equal 3, p.facilities[:TRAINING]
  end

  def test_scout_and_sign
    w = world
    p = w.clubs["P"]
    cands = w.player_scout("KANTO")
    assert cands.size >= 3
    assert_equal(-FM::Scout::FEE, p.wallet.totals[:scout])
    e = FM::Recruit.sign(p, cands.first, date: w.calendar.date)
    assert_equal 4, p.squad.size
    assert_equal cands.first[:mon].species, e[:species]
  end

  def test_full_squad_needs_a_release
    w = world
    p = w.clubs["P"]
    cap = FM::Build.squad_size(p.clubhouse)
    p.squad << FM::Mon.new(species: "PIDGEY", bst: 251, level: 12, stars: 1) while p.squad.size < cap
    cand = w.player_scout("KANTO").first
    assert_raises(ArgumentError) { FM::Recruit.sign(p, cand, date: w.calendar.date) }
    out = p.squad.last
    FM::Recruit.sign(p, cand, date: w.calendar.date, release: out)
    assert_equal cap, p.squad.size
    refute_includes p.squad, out
  end

  def test_state_passes_player_club_to_world
    s = FM::State.new_game(world: world)
    s.player_club = "A"
    assert_equal "A", s.world.player_club
  end
end

class TestPlayerMatchHook < Minitest::Test
  def test_hook_decides_only_the_players_matches
    w = TestPlayer.new("x").world
    calls = []
    FM::World.player_match = lambda do |home, away, _world, neutral:|
      calls << [home.id, away.id, neutral]
      home.id == "P" ? { res: 1, ko_a: 3, ko_b: 0 } : { res: -1, ko_a: 0, ko_b: 3 }
    end
    w.advance_days(364)
    assert calls.any?
    assert(calls.all? { |h, a, _| [h, a].include?("P") })
    t = w.leagues["KANTO"].table["P"]
    assert_equal t[:p], t[:w], "the hook made P win every game"
  ensure
    FM::World.player_match = nil
  end

  def test_nil_from_hook_falls_back_to_the_formula
    w = TestPlayer.new("x").world
    FM::World.player_match = ->(*_, **_) { nil }
    w.advance_days(200)
    assert w.leagues["KANTO"].table["P"][:p].positive?
  ensure
    FM::World.player_match = nil
  end
end
