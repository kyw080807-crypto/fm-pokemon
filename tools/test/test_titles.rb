require_relative "test_helper"
require_relative "test_player"   # TestPlayer#world

# Poké Manager 칭호 (TITLE_DEF / titleCtx / titlesOf / mainTitle / updateTitles).
class TestTitles < Minitest::Test
  T = FM::Titles

  def setup
    @w = TestPlayer.new("x").world
    @p = @w.clubs["P"]
  end

  def champion(club, year) = FM::Hof.of(@w)[:league].unshift({ year: year, region: club.region, club: club.id, pts: 50 })
  def keys = T.of(@w, @p).map { |t| t[:k] }

  def test_a_dynasty_and_its_order
    (1..3).each do |y|
      @p.history[y] = { pos: 1 }
      champion(@p, y)
    end
    assert_equal %i[dynasty leaguenow multi], keys.first(3)
    assert_equal 3, T.main(@w, @p)[:n]
  end

  def test_the_fallen_and_the_uncrowned
    @p.history[1] = { pos: 1 }
    champion(@p, 1)
    @p.history[2] = { pos: 12 }
    assert_includes keys, :fallen
    a = @w.clubs["A"]
    (1..4).each { |y| a.history[y] = { pos: 3 } }
    assert_includes T.of(@w, a).map { |t| t[:k] }, :crownless
  end

  def test_the_player_may_pick_a_title_that_holds
    @p.history[1] = { pos: 1, pwt: :champion }
    champion(@p, 1)
    FM::Hof.of(@w)[:world].unshift({ year: 1, club: "P" })
    assert_equal :worldnow, T.main(@w, @p)[:k]
    @w.my_title = :champ1
    assert_equal :champ1, T.main(@w, @p)[:k]
    @w.my_title = :legend
    assert_equal :worldnow, T.main(@w, @p)[:k], "a title it doesn't hold falls back"
  end

  def test_update_logs_once_and_makes_news
    @p.history[1] = { pos: 1 }
    @p.history[2] = { pos: 1 }
    champion(@p, 1)
    champion(@p, 2)
    events = T.update(@w)
    assert(events.any? { |e| e[:club] == "P" && e[:title][:k] == :multi })
    assert_empty T.update(@w).select { |e| e[:club] == "P" }, "once a season"
  end

  def test_a_season_end_updates_titles
    events = @w.advance_days(365)
    assert(@w.clubs.values.any? { |c| c.tlog&.any? })
    assert events.any? { |e| e[:kind] == :title_gained } if @w.clubs.values.any? { |c| c.tlog&.any? { |x| T::NEWS.include?(x[:k]) } }
  end
end
