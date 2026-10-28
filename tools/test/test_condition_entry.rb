require_relative "test_helper"

class TestEntry < Minitest::Test
  def test_entry_is_top_six_after_condition_and_lineup_is_its_top_three
    c = FM::Club.new(id: "X", name: "X", region: "KANTO", city: "C", role: "T", canon: false, level: 20,
                     potential: 3, stadium: 1,
                     pokemon: (0...8).map { |i| { species: "PIDGEY", bst: 300 + i * 20, level: 30, stars: 3 } })
    best = c.squad.max_by(&:bst)
    best.cond = 20
    assert_equal 6, c.entry.size
    assert_equal c.entry.first(3), c.lineup
    assert(c.entry.each_cons(2).all? { |a, b| a.rating * FM::Rating.cond_mul(a.cond) >= b.rating * FM::Rating.cond_mul(b.cond) })
    c.squad.pop(5)
    assert_equal 3, c.entry.size, "a short squad shows everyone"
  end
end
