require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world (species pool)

# Poké Manager signLimit / scoutBonus / recoveryMul, by last season's
# league position (player and AI alike).
class TestSignLimit < Minitest::Test
  def setup
    @w = TestPlayer.new("x").world
    @c = @w.clubs["P"]
  end

  def finished(pos, year: 1)
    (@c.history[year] ||= {})[:pos] = pos
  end

  def test_limit_by_last_position
    assert_equal 3, FM::Recruit.sign_limit(@c, 1), "no position yet"
    { 1 => 2, 4 => 2, 5 => 3, 10 => 3, 11 => 4, 20 => 4 }.each do |pos, n|
      finished(pos)
      assert_equal n, FM::Recruit.sign_limit(@c, 2), "pos #{pos}"
    end
  end

  def test_discount_and_scout_bonus_for_the_bottom
    finished(16)
    assert_in_delta 0.6, FM::Recruit.recovery_mul(@c, 2)
    assert_equal 2, FM::Recruit.scout_bonus(@c, 2)
    finished(12)
    assert_in_delta 0.8, FM::Recruit.recovery_mul(@c, 2)
    finished(3)
    assert_in_delta 1.0, FM::Recruit.recovery_mul(@c, 2)
    assert_equal 0, FM::Recruit.scout_bonus(@c, 2)
    @c.wallet.record(-@c.wallet.balance - 1, category: :drain, date: [2, 1, 1])
    assert_in_delta 0.8, FM::Recruit.recovery_mul(@c, 2), 1e-9, "in the red: at least 20% off"
    assert_equal 500, FM::Recruit.disc_cost(400, 0.8)
    assert_equal 6000, FM::Recruit.disc_cost(10_000, 0.6)
  end

  def test_player_scout_shows_discounted_prices
    finished(18)
    cands = FM::Recruit.scout(@c, pool: @w.species, region: "KANTO", avg_level: 20, rng: Random.new(3), date: [2, 1, 8])
    assert(cands.all? { |c| c[:full] && c[:cost] < c[:full] })
  end

  def test_signing_stops_at_the_limit
    finished(2)   # top 4: two a season
    cands = FM::Recruit.scout(@c, pool: @w.species, region: "KANTO", avg_level: 20, rng: Random.new(3), date: [2, 1, 8])
    2.times { |i| FM::Recruit.sign(@c, cands[i], date: [2, 1, 8]) }
    assert_equal 0, FM::Recruit.signs_left(@c, 2)
    assert_raises(FM::Recruit::LimitReached) { FM::Recruit.sign(@c, cands[2], date: [2, 1, 8]) }
    finished(7, year: 2)
    assert_equal 3, FM::Recruit.signs_left(@c, 3), "a new season resets it"
  end

  def test_ai_signings_respect_the_limit
    signed = Hash.new(0)
    @w.player_club = nil
    @w.advance_days(365).each { |e| signed[e[:club]] += 1 if e[:kind] == :signed }
    assert(signed.values.all? { |n| n <= 3 }, signed.inspect)
  end
end
