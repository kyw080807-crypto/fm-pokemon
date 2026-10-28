require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager morale, bond and locker-room talk.
class TestMorale < Minitest::Test
  def mon(nature_index: 0)
    m = FM::Mon.new(species: "PIDGEY", bst: 251, level: 30, stars: 3)
    m.instance_variable_set(:@nature_index, nature_index)
    m
  end

  def test_temper_from_nature
    assert_equal :fiery, FM::Morale.temper(mon(nature_index: 0))   # HARDY
    assert_equal :cool, FM::Morale.temper(mon(nature_index: 15))   # MODEST
    assert_equal :free, FM::Morale.temper(mon(nature_index: 10))   # TIMID
  end

  def test_tiers_and_stat_effect
    m = mon
    m.mor = 90
    assert_equal 1.03, FM::Morale.mor_mul(m)
    m.mor = 10
    assert_equal 0.96, FM::Morale.mor_mul(m)
    m.set_mood(:fire, [1, 1, 1])
    assert_equal 1.04, FM::Morale.mood_mul(m, [1, 1, 1])
    assert_equal 1.0, FM::Morale.mood_mul(m, [1, 1, 8]), "a mood lasts the week"
  end

  def test_talk_scores_follow_temperament
    ctx = { f: 0.0, big: false }
    fiery = mon(nature_index: 0)
    sens = mon(nature_index: 20)   # CALM
    assert_operator FM::Morale.score(fiery, :fire, ctx, 1)[:s], :>, FM::Morale.score(sens, :fire, ctx, 1)[:s]
    assert_operator FM::Morale.score(sens, :demand, ctx, 1)[:s], :<, 0
    assert_equal :off, FM::Morale.react(FM::Morale.score(sens, :demand, ctx, 1), 0)
    assert_equal :fire, FM::Morale.react({ s: 1.6, np: 0, cp: 0, om: 0 }, 0)
    weak = FM::Morale.score(fiery, :fire, ctx, 3)[:s]
    assert_in_delta FM::Morale.score(fiery, :fire, ctx, 1)[:s] * 0.3, weak, 1e-9, "the same talk again loses force"
  end

  def test_weekly_drift_toward_team_mood
    w = TestPlayer.new("x").world
    c = w.clubs["A"]
    c.squad.each { |m| m.mor = 20 }
    FM::Morale.weekly(c, %i[w w w w w])
    assert_in_delta 20 + (65 - 20) * 0.15, c.squad.first.mor, 0.06   # morale is kept to 0.1
  end

  def test_after_match_beats_expectations
    w = TestPlayer.new("x").world
    c = w.clubs["A"]
    m = c.lineup.first
    m.mor = 50
    FM::Morale.after_match(c, [m], [], { m => 2 }, won: true, pe: 0.3, big: false)
    assert_in_delta 50 + 0.5 + 12 * 0.7 + 4, m.mor, 0.05
  end

  def test_one_talk_a_week_and_the_player_chooses
    w = TestPlayer.new("x").world
    asked = []
    FM::Morale.player_talk = lambda do |club, _opp, ctx, mons|
      asked << [club.id, ctx[:f].round(2), mons.size]
      :trust
    end
    events = w.advance_days(60)
    talks = events.select { |e| e[:kind] == :talk }
    refute_empty asked
    assert(talks.all? { |e| e[:club] == "P" && e[:talk] == :trust })
  ensure
    FM::Morale.player_talk = nil
  end
end
