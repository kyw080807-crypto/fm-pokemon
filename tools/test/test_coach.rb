require_relative "test_helper"
require_relative "test_specialty"   # TestSpecialty::POOL (types, no base stats)

# Poké Manager coaches (coachSlots / coachQ / coachSpec / coachFx /
# coachFood / aiCoaches) and declineMul.
class TestCoach < Minitest::Test
  POOL = TestSpecialty::POOL.transform_values { |s| s.merge(base: [50, 60, 120, 40, 50, 80]) }
                            .merge("PIDGEY" => TestSpecialty::POOL["PIDGEY"].merge(base: [40, 45, 40, 35, 35, 56]))

  def club(training: 4)
    FM::Club.new({ id: "X", name: "X", region: "KANTO", city: "C", role: "T", canon: false, level: 20, potential: 3,
                   stadium: 1, clubhouse: 3, type: "NORMAL", facilities: { TRAINING: training },
                   pokemon: [{ species: "ONIX", bst: 385, level: 20, stars: 3 }] })
  end

  def retired(species, stars: 3, ko: 0)
    m = FM::Mon.new(species: species, bst: POOL[species][:bst], level: 50, stars: stars, age: 10)
    m.ko = ko
    m
  end

  def test_slots_by_training
    assert_equal 1, FM::Coach.slots(club(training: 2))
    assert_equal 2, FM::Coach.slots(club(training: 4))
    assert_equal 4, FM::Coach.slots(club(training: 10))   # 1 + 2 + 1
  end

  def test_quality
    assert_equal 1.0, FM::Coach.quality(retired("ONIX"))
    m = retired("ONIX", stars: 5, ko: 150)
    m.titles << [3, :league]
    m.awards << [3, :ko_king]
    assert_in_delta 1 + 1 + 0.3 + 0.2 + 0.4, FM::Coach.quality(m), 1e-9
    assert_equal 3.0, FM::Coach.quality(retired("ONIX", stars: 5, ko: 900)), "capped at 3"
    assert_equal "S", FM::Coach.grade(2.9)
  end

  def test_spec_is_the_best_base_stat
    assert_equal 2, FM::Coach.spec(POOL, retired("ONIX"))     # Def 120
    assert_equal 5, FM::Coach.spec(POOL, retired("PIDGEY"))   # Spe 56
  end

  def test_fx_and_shared_type_bonus
    c = club
    coach = retired("GEODUDE", stars: 5)   # quality 1.4, rock/ground
    c.retire(coach)
    coach.coach = true
    rock = FM::Coach.fx(c, c.squad.first, POOL)
    other = FM::Coach.fx(c, FM::Mon.new(species: "PIDGEY", bst: 251, level: 20, stars: 3), POOL)
    assert_in_delta (1 + 0.025 * 1.4) * (1 + 0.04 * 1.4), rock[:lv], 1e-9
    assert_in_delta 1 + 0.025 * 1.4, other[:lv], 1e-9
    assert_in_delta 1 + 0.2 * 1.4 / 6, rock[:ev], 1e-9, "one stat x1.28, as a mean over six"
  end

  def test_coach_food_is_fixed_at_retirement_and_paid_weekly
    c = club
    m = retired("ONIX")
    c.retire(m)
    fixed = m.food_fixed
    assert fixed.positive?
    c.fame = 200
    assert_equal 0, FM::Coach.weekly_food(c), "not coaching"
    m.coach = true
    assert_equal fixed, FM::Coach.weekly_food(c)
  end

  def test_ai_picks_the_best_and_lets_them_go_when_short
    c = club(training: 4)
    [1, 300, 600].each { |ko| c.retire(retired("ONIX", ko: ko)) }
    FM::Coach.ai_pick(c)
    assert_equal [300, 600], c.coaches.map(&:ko).sort
    FM::Coach.dismiss(c, keep: 1)
    assert_equal 1, c.coaches.size
  end

  def test_decline_in_the_last_two_seasons
    m = FM::Mon.new(species: "ONIX", bst: 385, level: 30, stars: 3, age: 7)
    assert_equal 1.0, m.decline_mul
    m.age = 8
    assert_equal 0.96, m.decline_mul
    m.age = 9
    assert_equal 0.92, m.decline_mul
  end
end
