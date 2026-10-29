require_relative "test_helper"

class TestCityRules < Minitest::Test
  C = FM::Civic

  def test_size_table_from_design
    assert_equal [4, 6, 8, 10, 12], (1..5).map { |s| C.public_plots(s) }
    assert_equal [4, 6, 8, 10, 10], (1..5).map { |s| C.public_cap(s) }
  end

  def test_expansion_cost_multipliers_from_design
    base = C::EXPANSION_BASE
    assert_equal base, C.expansion_cost(1)            # 1 -> 2: x1
    assert_equal (base * 2.5).round, C.expansion_cost(2)
    assert_equal base * 6, C.expansion_cost(3)
    assert_nil C.expansion_cost(4), "size 5 is capitals only"
  end

  def test_weekly_tax_grows_with_size
    assert C.weekly_tax(3) > C.weekly_tax(1)
  end
end

class TestTraits < Minitest::Test
  def test_traits_are_deterministic_and_bounded
    a = FM::Traits.generate(name: "마티스", role: "G3", type: "ELECTRIC")
    b = FM::Traits.generate(name: "마티스", role: "G3", type: "ELECTRIC")
    assert_equal a, b
    assert_equal %i[civic commercial cooperative competitive], a.keys
    a.each_value { |v| assert v.between?(-1.0, 1.0) }
  end

  def test_roles_lean_as_described
    champ = FM::Traits.generate(name: "x", role: "C", type: "DRAGON")
    trainer = FM::Traits.generate(name: "x", role: "T", type: "DRAGON")
    assert champ[:competitive] > trainer[:competitive]
  end
end

class TestVote < Minitest::Test
  def voter(civic:, spare:, blocked:)
    { traits: { civic: civic, commercial: 0.0, cooperative: 0.0, competitive: 0.0 },
      spare: spare, blocked: blocked, relation: 0.0 }
  end

  def test_blocked_civic_club_with_money_votes_yes
    assert FM::Vote.expansion_yes?(voter(civic: 0.5, spare: 2_000_000, blocked: true), share: 200_000)
  end

  def test_broke_club_votes_no
    refute FM::Vote.expansion_yes?(voter(civic: 0.5, spare: 50_000, blocked: true), share: 400_000)
  end

  def test_reason_is_given_on_no
    v = voter(civic: -0.8, spare: 0, blocked: false)
    refute FM::Vote.expansion_yes?(v, share: 300_000)
    assert_equal :no_money, FM::Vote.expansion_reason(v, share: 300_000)
  end
end

class TestAwayFans < Minitest::Test
  # transport / hotel: the design 05 tier; the building's level is 2x.
  def city(id, transport: nil, hotel: nil)
    b = [[:RESIDENTIAL, 1]]
    b << [:TRANSPORT, transport * 2] if transport
    b << [:HOTEL, hotel * 2] if hotel
    FM::City.new(id: id, name: id, region: "KANTO", form: "SOLO", size: 2, buildings: b)
  end

  def fans(from, to, fame: 60, cap: 20_000)
    FM::Civic.away_fans(away_fame: fame, from: from, to: to, capacity: cap)
  end

  # Design 05 example table: away fame 60 = 1,500 fans at L = 1.
  def test_transport_factor_uses_the_lower_city
    big_hotel = city("H", transport: 3, hotel: 5)
    assert_in_delta 600, fans(city("A"), big_hotel)[:fans], 1            # Lv0: 0.4
    assert_in_delta 1200, fans(city("B", transport: 2), big_hotel)[:fans], 1
    assert_in_delta 1500, fans(city("C", transport: 3), big_hotel)[:fans], 1
    assert_in_delta 1500, fans(city("D", transport: 4), big_hotel)[:fans], 1, "host Lv3 caps the factor"
  end

  def test_same_city_derby_bonus
    c = city("X", transport: 5, hotel: 5)
    assert_in_delta 1500 * 1.4 * 1.3, fans(c, c)[:fans], 1
  end

  # Design 05: 1,200 from a Lv2 city (2 days, everyone lodges) into an inn
  # (400 beds) -> 400; hotel Lv2 (1,500) -> all 1,200.
  def test_hotel_capacity_limits_lodging_fans
    from = city("F", transport: 2)
    assert_in_delta 400, fans(from, city("I", transport: 3))[:fans], 1
    r = fans(from, city("J", transport: 3, hotel: 2))
    assert_in_delta 1200, r[:fans], 1
    assert_in_delta 1200, r[:lodging], 1
  end

  def test_one_day_trip_lodges_sixty_percent
    r = fans(city("F", transport: 3), city("H", transport: 3, hotel: 5))
    assert_in_delta 1500 * 0.6, r[:lodging], 1
  end

  def test_away_section_cap
    c = city("H", transport: 5, hotel: 5)
    assert fans(c, c, fame: 300, cap: 2000)[:fans] <= 600
  end
end
