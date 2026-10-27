require_relative "test_helper"

class TestSponsor < Minitest::Test
  S = FM::Sponsor
  TABLE = [
    { id: "SILPH", name: "실프", region: "KANTO", tier: "BIG", kind: "STABLE", min_fame: 55 },
    { id: "MACRO", name: "매크로", region: "GALAR", tier: "BIG", kind: "STRICT", min_fame: 60 },
    { id: "FANCLUB", name: "팬클럽", region: "KANTO", tier: "LOCAL", kind: "STABLE", min_fame: 0 },
    { id: "SAFARI", name: "사파리", region: "KANTO", tier: "LOCAL", kind: "BUZZ", min_fame: 10 },
    { id: "MUSEUM", name: "박물관", region: "KANTO", tier: "LOCAL", kind: "FAME", min_fame: 0 },
    { id: "SUBWAY", name: "서브웨이", region: "UNOVA", tier: "LOCAL", kind: "PERF", min_fame: 5 },
    { id: "DEPT", name: "백화점", region: "KANTO", tier: "SHOP", kind: "SHOP", min_fame: 0 }
  ].freeze

  def test_deal_amounts_follow_poke_manager
    stable = S.deal(TABLE[2], fame: 50)        # local stable: max(30000, 50*1500)
    assert_equal 75_000, stable[:base]
    big = S.deal(TABLE[0], fame: 50)           # x1.35
    assert_equal 101_000, big[:base]
    strict = S.deal(TABLE[1], fame: 70)
    assert_equal((70 * 1200 * 1.35 / 1000.0).round * 1000, strict[:base])
    assert_equal((70 * 2400 * 1.35 / 1000.0).round * 1000, strict[:bonus])
    low = S.deal(TABLE[2], fame: 5)            # fame floor 10 and minimum base
    assert_equal 30_000, low[:base]
  end

  def test_offers_respect_region_fame_and_clubhouse
    rng = Random.new(1)
    offers = S.offers(TABLE, region: "KANTO", fame: 20, clubhouse: 2, bans: {}, year: 1, rng: rng)
    assert offers.size.between?(1, 3)
    offers.each do |o|
      assert_equal "KANTO", o[:region]
      refute_equal "BIG", o[:tier], "big sponsors need fame and clubhouse 3"
    end
    assert_equal offers.map { |o| o[:kind] }.uniq.size, offers.size, "one offer per kind"
  end

  def test_famous_clubs_with_big_clubhouse_get_big_offers
    found = Array.new(30) do |i|
      S.offers(TABLE, region: "KANTO", fame: 80, clubhouse: 3, bans: {}, year: 1, rng: Random.new(i))
    end.flatten
    assert found.any? { |o| o[:id] == "SILPH" }
    assert found.any? { |o| o[:id] == "MACRO" }, "big sponsors from other regions at fame >= min + 10"
  end

  def test_banned_sponsor_is_not_offered
    offers = Array.new(20) do |i|
      S.offers(TABLE, region: "KANTO", fame: 50, clubhouse: 2, bans: { "FANCLUB" => 2 }, year: 2, rng: Random.new(i))
    end.flatten
    assert offers.none? { |o| o[:id] == "FANCLUB" }
  end

  def world_with_sponsors
    clubs = (0...4).map do |i|
      { id: "K#{i}", name: "K#{i}", region: "KANTO", city: "C", role: i.zero? ? "C" : "T", canon: true,
        level: i.zero? ? 40 : 20, potential: 3, stadium: 1, clubhouse: 3,
        pokemon: Array.new(3) { { bst: i.zero? ? 650 : 380, level: 40, stars: 3 } } }
    end
    FM::World.new_game(clubs, seed: 1, sponsors: TABLE)
  end

  def test_world_signs_sponsors_and_pays_weekly
    w = world_with_sponsors
    assert(w.clubs.values.all?(&:sponsor))
    w.advance_days(7)
    c = w.clubs["K1"]
    assert_equal (c.sponsor[:base] / 52.0).round, c.wallet.totals[:spon]
  end

  def test_season_end_bonus_and_strict_ban
    w = world_with_sponsors
    champ = w.clubs["K0"]
    champ.sponsor = S.deal(TABLE[1], fame: champ.fame)            # STRICT
    loser = w.clubs["K3"]
    loser.sponsor = S.deal(TABLE[1], fame: loser.fame)
    w.advance_days(364)                                           # through the league, before Jan 1
    assert champ.wallet.totals[:spon] >= champ.sponsor[:bonus] if champ.sponsor
    pos = w.leagues["KANTO"].position("K3")
    assert loser.sponsor_bans.key?("MACRO") if pos > FM::Sponsor::BONUS_POSITION
  end

  def test_ai_picks_base_plus_part_of_bonus
    a = { base: 50_000, bonus: 0 }
    b = { base: 30_000, bonus: 60_000 }
    assert_equal b, S.ai_pick([a, b])
  end
end
