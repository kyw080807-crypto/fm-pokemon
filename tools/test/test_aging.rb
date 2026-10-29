require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager 시설 노후화 (FAC_LIFE / renovCost / facEsc / facAgeWeek).
class TestAging < Minitest::Test
  def setup
    @w = TestPlayer.new("x").world
    @p = @w.clubs["P"]          # the player's club
    @a = @w.clubs["A"]          # an AI club
    [@p, @a].each { |c| c.facilities[:TRAINING] = 5 }
  end

  def weeks(n, club = @p)
    out = []
    n.times { out.concat(FM::Aging.club_week(@w, club)) }
    out
  end

  def test_costs_and_escalation
    a = { w: 0, n: 0 }
    assert_equal (FM::Build.up_cost(9) * 0.35 / 1000.0).round * 1000, FM::Aging.renov_cost(a)
    a[:n] = 2
    assert_equal 1.5, FM::Aging.esc(a)
    a[:n] = 9
    assert_equal 2.0, FM::Aging.esc(a), "at most x2"
    assert_equal 777, FM::Aging.step_cost(777, { w: 0, n: 0 }), "no drop yet: the usual cost"
    assert_equal (FM::Build.up_cost(9) * 1.25 / 1000.0).round * 1000, FM::Aging.step_cost(777, { w: 0, n: 1 })
  end

  def test_warning_then_drop
    @p.wallet.record(-@p.wallet.balance, category: :drain, date: [1, 1, 1])
    events = weeks(FM::Aging::LIFE)
    assert(events.any? { |e| e[:kind] == :aging_warning && e[:weeks] == 52 })
    assert(events.any? { |e| e[:kind] == :aged })
    assert_equal 4, @p.facilities[:TRAINING]
    assert_equal 1, FM::Aging.age(@p, :TRAINING)[:n]
  end

  def test_renovation_resets_the_clock
    weeks(100)
    assert FM::Aging.renovate(@p, :TRAINING, date: [1, 1, 1])
    assert_equal [0, 1], FM::Aging.age(@p, :TRAINING).values_at(:w, :n)
    weeks(FM::Aging::LIFE - 1)
    assert_equal 5, @p.facilities[:TRAINING]
  end

  def test_ai_renovates_when_it_can
    events = weeks(FM::Aging::LIFE + 5, @a)
    refute(events.any? { |e| e[:kind] == :aged })
    assert_equal 5, @a.facilities[:TRAINING]
    assert_equal 1, FM::Aging.age(@a, :TRAINING)[:n]
  end

  def test_a_drop_trims_the_coaching_staff
    @p.wallet.record(-@p.wallet.balance, category: :drain, date: [1, 1, 1])
    4.times do
      m = FM::Mon.new(species: "PIDGEY", bst: 251, level: 40, stars: 3)
      @p.retire(m)
      m.coach = true
    end
    weeks(FM::Aging::LIFE)
    assert_operator @p.coaches.size, :<=, FM::Coach.slots(@p)
  end
end
