require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager 명예의 전당 (addHof / seasonAwards / hofAdd / hofWorthy).
class TestHof < Minitest::Test
  H = FM::Hof

  def setup
    @w = TestPlayer.new("x").world
    @p = @w.clubs["P"]
  end

  def mon(ko: 0, titles: [], awards: [])
    m = FM::Mon.new(species: "PIDGEY", bst: 251, level: 40, stars: 3, age: 6)
    m.ko = ko
    titles.each { |t| m.titles << t }
    awards.each { |a| m.awards << a }
    m
  end

  def test_worthy
    refute H.worthy?(mon(ko: 399))
    assert H.worthy?(mon(ko: 400))
    assert H.worthy?(mon(titles: [[1, :pwt]]))
    assert H.worthy?(mon(titles: [[1, :league], [2, :league], [3, :league]]))
    assert H.worthy?(mon(awards: [[1, :ko_king], [2, :ko_king]]))
    assert H.worthy?(mon(ko: 250, awards: [[1, :ko_king]]))
    refute H.worthy?(mon(ko: 249, awards: [[1, :ko_king]]))
  end

  def test_club_hall_keeps_thirty_newest
    31.times { H.induct(@w, @p, mon(ko: 500), :retired) }
    assert_equal 30, @p.hof.size
    assert_equal :retired, @p.hof.first[:kind]
    assert_equal @w.calendar.year - 6, @p.hof.first[:y0]
    assert_nil H.retired(@w, @p, mon(ko: 10)), "not worthy"
  end

  def test_a_season_fills_the_records
    events = @w.advance_days(365)
    h = H.of(@w)
    champ = h[:league].first
    refute_nil champ
    assert_equal "KANTO", champ[:region]
    assert_equal champ[:pts], h[:records][:pts_KANTO][:pts]
    assert(events.any? { |e| e[:kind] == :league_champion && e[:club] == champ[:club] })
    if (k = h[:ko].first)
      assert(events.any? { |e| e[:kind] == :ko_king && e[:ko] == k[:ko] })
      assert_equal k[:ko], h[:records][:ko][:ko]
    end
  end

  def test_streaks_count_back_to_back_titles
    league = FM::League.new(%w[P A B C], rng: Random.new(1))
    standings = %w[P A B C]
    first = H.season_awards(@w, "KANTO", league, standings).first
    assert_equal 1, first[:streak]
    assert_equal 2, H.season_awards(@w, "KANTO", league, standings).first[:streak]
    assert_equal 1, H.season_awards(@w, "KANTO", league, %w[A P B C]).first[:streak]
  end
end
