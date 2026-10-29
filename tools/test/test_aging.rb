require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager 시설 노후화 (FAC_LIFE / renovCost / facEsc / facAgeWeek),
# here on every facility and level (higher levels wear out sooner).
class TestAging < Minitest::Test
  A = FM::Aging

  def setup
    @w = TestPlayer.new("x").world
    @p = @w.clubs["P"]          # the player's club
    @a = @w.clubs["A"]          # an AI club
    [@p, @a].each do |c|
      c.project = nil
      c.facilities.clear
      c.facilities[:TRAINING] = 10
    end
  end

  def weeks(n, club = @p)
    out = []
    n.times { out.concat(A.club_week(@w, club)) }
    out
  end

  def broke!(club) = club.wallet.record(-club.wallet.balance, category: :drain, date: [1, 1, 1])

  def test_life_shortens_with_level
    assert_equal 260, A.life(1)
    assert_equal 130, A.life(10)
    assert_operator A.life(5), :<, A.life(4)
  end

  def test_costs_and_escalation
    a = { w: 0, n: 0, top: 0 }
    up9 = FM::Build.up_cost(9)
    assert_equal (up9 * 0.35 / 1000.0).round * 1000, A.renov_cost(a, 10)
    assert_equal (FM::Build.up_cost(2) * 0.35 / 1000.0).round * 1000, A.renov_cost(a, 3), "the step into Lv3"
    a[:n] = 2
    assert_equal 1.5, A.esc(a)
    a[:n] = 9
    assert_equal 2.0, A.esc(a), "at most x2"
    assert_equal 777, A.step_cost(777, { w: 0, n: 0, top: 10 }, 10), "no drop yet: the usual cost"
    assert_equal 1_000, A.step_cost(800, { w: 0, n: 1, top: 10 }, 10), "rebuilding a lost level"
    assert_equal 800, A.step_cost(800, { w: 0, n: 1, top: 6 }, 7), "a level never reached: the usual cost"
  end

  def test_warning_then_drop
    broke!(@p)
    events = weeks(A.life(10))
    assert(events.any? { |e| e[:kind] == :aging_warning && e[:weeks] == 52 && e[:level] == 10 })
    assert(events.any? { |e| e[:kind] == :aged && e[:level] == 9 })
    assert_equal 9, @p.facilities[:TRAINING]
    assert_equal 1, A.age(@p, :TRAINING)[:n]
    weeks(A.life(9))
    assert_equal 8, @p.facilities[:TRAINING], "lower levels age too"
  end

  def test_low_levels_last_longer
    broke!(@p)
    @p.facilities[:TRAINING] = 1
    weeks(A.life(10))
    assert_equal 1, @p.facilities[:TRAINING]
    weeks(A.life(1) - A.life(10))
    assert_equal 0, @p.facilities[:TRAINING], "Lv0: the plot is kept"
    assert @p.facilities.key?(:TRAINING)
  end

  def test_renovation_resets_the_clock
    weeks(100)
    assert A.renovate(@p, :TRAINING, date: [1, 1, 1])
    assert_equal [0, 1], A.age(@p, :TRAINING).values_at(:w, :n)
    weeks(A.life(10) - 1)
    assert_equal 10, @p.facilities[:TRAINING]
  end

  def test_a_new_level_starts_a_fresh_clock
    weeks(100)
    @p.facilities[:TRAINING] = 9
    A.built(@p, :TRAINING, 9)
    assert_equal 0, A.age(@p, :TRAINING)[:w]
  end

  def test_ai_renovates_when_it_can
    @a.wallet.record(10_000_000, category: :grant, date: [1, 1, 1])
    events = weeks(A.life(10) + 5, @a)
    refute(events.any? { |e| e[:kind] == :aged })
    assert_equal 10, @a.facilities[:TRAINING]
    assert_equal 1, A.age(@a, :TRAINING)[:n]
  end

  def test_a_drop_trims_the_coaching_staff
    broke!(@p)
    @p.facilities[:TRAINING] = 2   # two slots; Lv1 has one
    4.times do
      m = FM::Mon.new(species: "PIDGEY", bst: 251, level: 40, stars: 3)
      @p.retire(m)
      m.coach = true
    end
    weeks(A.life(2))
    assert_equal 1, @p.facilities[:TRAINING]
    assert_operator @p.coaches.size, :<=, FM::Coach.slots(@p)
  end

  def test_cities_and_committees_age_and_renovate_from_the_budget
    city = FM::City.new(id: "T", name: "T", region: "KANTO", form: "SOLO", size: 3, buildings: [[:TRANSPORT, 4]])
    lv = city.transport
    city.budget.record(-city.budget.balance, category: :drain, date: [1, 1, 1])
    A.life(lv).times { A.city_week(@w, city) }
    assert_equal lv - 1, city.transport
    city.budget.record(50_000_000, category: :grant, date: [1, 1, 1])
    (A.life(lv - 1) + 5).times { A.city_week(@w, city) }
    assert_equal lv - 1, city.transport, "renovated"
  end
end
