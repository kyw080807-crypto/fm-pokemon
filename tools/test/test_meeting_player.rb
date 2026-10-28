require_relative "test_helper"
require_relative "test_city_world"   # TestCityWorld#world: SHARED city with L1 and L2

# Design 02: the player at the city meeting (vote, take on shares, pay it
# all) and petitions.
class TestMeetingPlayer < Minitest::Test
  def setup
    @w = TestCityWorld.new("x").world
    @w.player_club = "L1"
    @w.clubs.each_value { |c| c.wallet.record(30_000_000, category: :grant, date: [1, 1, 1]) }
    @city = @w.cities["SHARED"]
  end

  def teardown
    FM::Meeting.player_hook = nil
  end

  def meetings(events) = events.select { |e| e[:kind] == :meeting && e[:city] == "SHARED" }

  def test_hook_is_asked_and_its_vote_counts
    seen = []
    FM::Meeting.player_hook = lambda do |p|
      seen << p
      { vote: false, extra: 0 }
    end
    ms = meetings(@w.advance_days(60))
    refute_empty seen
    assert_equal @w.clubs["L1"], seen.first.player
    refute ms.first[:votes]["L1"][:yes]
    refute ms.first[:passed], "1 of 2 is not a majority"
  end

  def test_taking_on_shares_moves_money_from_the_others
    p = nil
    FM::Meeting.player_hook = lambda do |prop|
      p = prop
      { vote: true, extra: 10_000_000 }   # more than the others' part: capped
    end
    @w.advance_days(60)
    base, = p.evaluate.call(0)
    shifted, votes = p.evaluate.call(10_000_000)
    assert_equal base.values.sum, shifted.values.sum
    assert_equal 0, shifted["L2"]
    assert_equal p.full_cost, shifted["L1"]
    assert_equal 0, votes["L2"][:share]
  end

  def test_full_payment_passes_without_a_vote_and_is_rewarded
    l1, l2 = @w.clubs["L1"], @w.clubs["L2"]
    l2.wallet.record(-l2.wallet.balance - 1_000_000, category: :drain, date: [1, 1, 1])   # would vote no
    fame = l1.fame
    rel = @w.relations.get("L1", "L2")
    FM::Meeting.player_hook = ->(_) { { full: true } }
    m = meetings(@w.advance_days(60)).first
    assert m[:passed]
    assert_equal "L1", m[:full]
    assert_equal ["L1"], m[:votes].keys
    assert_operator l1.fame, :>, fame
    assert_operator @w.relations.get("L1", "L2"), :>, rel
  end

  def test_petition_sets_the_next_agenda
    opts = FM::Meeting.petition_options(@w, @city)
    hotel = opts.find { |o| o[:agenda] == :infrastructure && o[:target] == :HOTEL }
    assert hotel
    assert(opts.any? { |o| o[:agenda] == :expansion })
    FM::Meeting.petition(@city, hotel, by: "L1")
    m = meetings(@w.advance_days(40)).first
    assert_equal :HOTEL, m[:target]
    assert_equal "L1", m[:petition]
    assert_nil @city.petition
  end

  def test_without_a_hook_the_ai_votes_for_the_player
    ms = meetings(@w.advance_days(60))
    refute_empty ms
    assert ms.first[:votes].key?("L1")
  end
end
