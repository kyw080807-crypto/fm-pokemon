require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world (P is the player's club)

# Poké Manager 원정 친선 투어 (tourPay / canTour / goTour / aiTourP).
class TestTour < Minitest::Test
  def setup
    @w = TestPlayer.new("x").world
    @c = @w.clubs["P"]
    # canTour needs an entry of three: a trainer (no specialty rule cutting
    # the entry) with room for an injury.
    @c.instance_variable_set(:@role, "T")
    3.times { |i| @c.squad << FM::Mon.new(species: "PIDGEY", bst: 251, level: 12 + i, stars: 3) }
  end

  def test_pay_formula
    @c.fame = 60
    ovr = FM::Tour.team_ovr(@c)
    expected = ((6000 + FM::Economy.fame_eff(60) * 110 + [0, ovr - 100].max * 100) / 100.0).round * 100
    assert_equal expected, FM::Tour.pay(@c)
  end

  def test_ai_tours_more_when_short
    rich = FM::Tour.ai_chance(@c)
    @c.wallet.record(-@c.wallet.balance - 1, category: :drain, date: [1, 1, 1])
    assert_equal 0.9, FM::Tour.ai_chance(@c)
    assert_operator rich, :<, 0.9
  end

  def test_a_tour_costs_condition_and_the_week
    before = @c.entry.map(&:cond)
    fee = FM::Tour.go(@c, date: [1, 1, 8])
    assert fee.positive?
    assert_equal fee, @c.wallet.totals[:tour]
    assert_equal before.map { |x| [x - FM::Tour::COND, FM::Growth::COND_MIN].max }.sort, @c.entry.map(&:cond).sort
    m = @c.entry.first
    ev, cond = m.ev, m.cond
    FM::Growth.condition_week(m)
    assert_equal cond, m.cond, "no rest or training on tour"
    FM::Growth.week(m, train_level: 3, species: TestPlayer::SPECIES)
    assert_equal ev, m.ev, "no EVs"
    assert_nil m.tour
  end

  def test_no_tour_in_a_league_week
    first = FM::Season.league_dates(@w.calendar, 1).first
    @w.advance_days(@w.calendar.days_until(first) - 3)
    assert @w.official_match_week?(@c)
  end

  def test_player_tours_only_when_asked
    @w.advance_days(1)   # preseason, no matches
    events = @w.advance_days(14)
    refute(events.any? { |e| e[:kind] == :tour && e[:club] == "P" })
    @w.tour_next = true
    events = @w.advance_days(7)
    assert(events.any? { |e| e[:kind] == :tour && e[:club] == "P" })
    refute @w.tour_next, "one week only"
  end
end
