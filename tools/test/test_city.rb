require_relative "test_helper"

class TestCityRules < Minitest::Test
  C = FM::Civic

  def test_size_table_from_design
    assert_equal [4, 6, 8, 10, 12], (1..5).map { |s| C.public_plots(s) }
    assert_equal [2, 3, 4, 5, 5], (1..5).map { |s| C.public_cap(s) }
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
