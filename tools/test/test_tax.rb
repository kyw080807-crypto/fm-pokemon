require_relative "test_helper"

class TestTax < Minitest::Test
  def city(**opts)
    FM::City.new({ id: "C", name: "C", region: "KANTO", form: "SOLO", size: 2, free_plots: 1,
                   buildings: [[:TRANSPORT, 1]] }.merge(opts))
  end

  def test_defaults_and_old_saves
    c = city
    assert_equal 1.0, c.tax_rate
    assert_equal FM::Civic::SATISFACTION_START, c.satisfaction
    c.remove_instance_variable(:@tax_rate) if c.instance_variable_defined?(:@tax_rate)
    assert_equal 1.0, c.tax_rate
  end

  def test_high_tax_lowers_satisfaction_over_time
    c = city
    c.tax_rate = 1.4
    52.times { c.drift_satisfaction }
    assert c.satisfaction < 45
    c.tax_rate = 0.6
    104.times { c.drift_satisfaction }
    assert c.satisfaction > 70
  end

  def test_failed_votes_hurt_and_mood_scales_crowds
    c = city
    before = c.satisfaction
    c.vote_failed
    assert_equal 1, c.unrest
    assert_in_delta before - FM::Civic::FAILED_VOTE_HIT, c.satisfaction
    c.satisfaction = 0
    assert_in_delta 0.85, c.crowd_mood
    c.satisfaction = 100
    assert_in_delta 1.15, c.crowd_mood
    d_low = FM::Economy.demand(home_fame: 50, away_fame: 50, wins: 2, capacity: 9999, mood: 0.85)
    d_high = FM::Economy.demand(home_fame: 50, away_fame: 50, wins: 2, capacity: 9999, mood: 1.15)
    assert d_high > d_low
  end

  def test_vote_leanings
    civic = { civic: 0.8, commercial: -0.5, cooperative: 0.3, competitive: 0 }
    merchant = { civic: -0.5, commercial: 0.9, cooperative: 0, competitive: 0 }
    assert FM::Vote.tax_yes?(civic, raise: true)
    refute FM::Vote.tax_yes?(merchant, raise: true)
    assert FM::Vote.tax_yes?(merchant, raise: false)
  end

  def club(id)
    { id: id, name: id, region: "KANTO", city: "S", role: "G1", canon: true, level: 30, potential: 3,
      type: "PSYCHIC", stadium: 1, clubhouse: 1, facilities: { TRAINING: 1 },
      pokemon: Array.new(3) { { bst: 450, level: 30, stars: 3 } } }
  end

  def test_broke_city_votes_on_raising_tax
    w = FM::World.new_game([club("S1"), club("S2"), club("S3"), club("S4")], seed: 2,
                           cities: [{ id: "S", name: "S", region: "KANTO", form: "LONDON", size: 2, free_plots: 0,
                                      buildings: [[:TRANSPORT, 2]] }])
    s = w.cities["S"]
    s.budget.record(-s.budget.balance, category: :drain, date: [1, 1, 1])
    w.clubs.each_value { |c| c.wallet.record(-c.wallet.balance, category: :drain, date: [1, 1, 1]) }
    events = w.advance_days(40)
    m = events.find { |e| e[:kind] == :meeting && e[:agenda] == :tax }
    refute_nil m
    assert_equal :raise, m[:target]
    assert_in_delta(m[:passed] ? 1.1 : 1.0, s.tax_rate)
  end

  def test_unhappy_city_votes_on_cutting_tax
    w = FM::World.new_game([club("S1"), club("S2"), club("S3"), club("S4")], seed: 2,
                           cities: [{ id: "S", name: "S", region: "KANTO", form: "LONDON", size: 1, free_plots: 0,
                                      buildings: [[:TRANSPORT, 2]] }])
    s = w.cities["S"]
    s.tax_rate = 1.3
    s.satisfaction = 20
    events = w.advance_days(40)
    m = events.find { |e| e[:kind] == :meeting && e[:agenda] == :tax }
    refute_nil m
    assert_equal :lower, m[:target]
  end
end
