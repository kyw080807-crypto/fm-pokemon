require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager 무리 출전 and injuries that get worse when they play.
class TestPtp < Minitest::Test
  def mon
    FM::Mon.new(species: "PIDGEY", bst: 251, level: 30, stars: 3)
  end

  def test_playing_through_keeps_it_in_the_entry_with_extra_drops
    w = TestPlayer.new("x").world
    c = w.clubs["P"]
    m = c.squad.max_by(&:rating)
    FM::Injury.injure(m, :battle, Random.new(1), :fracture)
    refute_includes c.entry, m
    m.ptp = true
    assert m.red?
    refute m.out?
    assert_includes c.entry, m
    assert_equal %i[spe main], m.debuffs - FM::Rating.debuff(m.cond)
    FM::Growth.condition_week(m)
    assert m.resting, "it still heals resting"
  end

  def test_played_through_injury_may_worsen
    m = mon
    FM::Injury.injure(m, :battle, Random.new(1), :sprain)
    m.ptp = true
    weeks = m.inj
    rng = Random.new(1)
    worse = nil
    50.times { (worse = FM::Injury.after_match([m], [m], nil, rng)).empty? or break }
    refute_empty worse
    assert_operator m.inj, :>, weeks
    assert worse.first.last[:worse]
  end

  def test_light_injury_that_plays_may_turn_red
    m = mon
    FM::Injury.injure(m, :battle, Random.new(1), :bruise)
    assert m.yellow?
    50.times do
      FM::Injury.after_match([m], [m], nil, Random.new(rand(1000)))
      break if m.red?
    end
    assert m.red?
    assert m.out?
  end

  def test_recovery_clears_the_choice
    m = mon
    FM::Injury.injure(m, :battle, Random.new(1), :sprain)
    m.ptp = true
    rng = Random.new(2)
    nil until FM::Injury.heal_week(m, 1, rng) == :recovered
    assert_nil m.ptp
  end
end
