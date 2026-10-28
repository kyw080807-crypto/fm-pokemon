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
  def test_disobedience_needs_low_bond_and_pride
    w = TestPlayer.new("x").world
    c = w.clubs["A"]
    star = c.squad.max_by(&:rating)
    star.level = 90   # far above the team average
    star.bond = 60
    star.mor = 60
    assert_operator FM::Morale.pride(star, c), :>, 0
    p = FM::Morale.disobey_p(star, c)
    assert_operator p, :>, 0
    assert_operator p, :<=, 0.3
    star.bond = FM::Morale::BOND_OBEY
    assert_equal 0.0, FM::Morale.disobey_p(star, c), "120 bond: it listens"
    weak = c.squad.min_by(&:rating)
    weak.bond = 0
    assert_equal 0.0, FM::Morale.disobey_p(weak, c), "no pride, no disobedience" if FM::Morale.pride(weak, c).zero?
  end

  def test_proud_species_and_formula_cost
    w = TestPlayer.new("x").world
    c = w.clubs["A"]
    m = c.squad.first
    m.species = "CHARMELEON"
    assert_operator FM::Morale.pride(m, c), :>=, 0.25 * 1.7
    before = c.rating
    c.squad.each { |x| x.bond = 0 }
    c.refresh_rating
    assert_operator c.rating, :<, before
  end

  def test_bond_effects
    m = mon
    m.bond = 230
    assert_equal [0.008, 0.03], FM::Morale.bond_fx(m)
    m.bond = 100
    assert_equal [0.0, 0.0], FM::Morale.bond_fx(m)
  end

  def test_individual_words_by_temperament
    ctx = { f: 0.0, big: false }
    sens = mon(nature_index: 20)    # CALM
    fiery = mon(nature_index: 0)    # HARDY
    base = FM::Morale.score(sens, :easy, ctx, 1)[:s]
    assert_operator FM::Morale.score(sens, :easy, ctx, 1, :cheer)[:s], :>, base
    assert_operator FM::Morale.score(sens, :easy, ctx, 1, :push)[:s], :<, base
    assert_operator FM::Morale.score(fiery, :easy, ctx, 1, :push)[:s], :>, FM::Morale.score(fiery, :easy, ctx, 1)[:s]
  end

  def test_good_word_adds_bond
    m = mon(nature_index: 20)
    b = m.bond
    rng = Random.new(1)
    moods = FM::Morale.apply([m], :trust, { f: 0.0, big: false }, [1, 1, 1], rng, ind: { m => :cheer })
    extra = %i[fire mot].include?(moods[m]) ? 1 : 0
    assert_in_delta b + FM::Morale::MOOD[moods[m]][2] + extra, m.bond, 1e-9
  end

  def test_bond_passing_120_after_disobeying_is_news
    m = mon
    m.bond = 119
    m.disob = 1
    FM::Morale.add_bond(m, 2)
    assert m.opened
    n = mon
    n.bond = 119
    FM::Morale.add_bond(n, 2)
    refute n.opened, "only after it has disobeyed"
  end

  def test_disobedience_from_a_battle_is_counted
    w = TestPlayer.new("x").world
    p = w.clubs["P"]
    star = p.lineup.first
    FM::World.player_match = lambda do |home, _away, _world, **|
      mine = home.id == "P"
      { res: 1, ko_a: 3, ko_b: 0, (mine ? :disobeyed_a : :disobeyed_b) => { star => 2 } }
    end
    events = w.advance_days(60)
    d = events.find { |e| e[:kind] == :disobeyed }
    assert d
    assert_equal 2, d[:times]
    assert_operator star.disob, :>=, 1
  ensure
    FM::World.player_match = nil
  end

end
