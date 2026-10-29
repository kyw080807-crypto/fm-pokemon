require_relative "test_helper"
require_relative "test_squad"   # TestSquad::SPECIES

# Poké Manager youthMon (the emergency call-up's youth players).
class TestYouth < Minitest::Test
  def test_youth_players_are_new_and_young
    rng = Random.new(5)
    50.times do
      m = FM::Scout.youth(TestSquad::SPECIES, region: "KANTO", scout_level: 10, rng: rng)
      assert_equal 0, m.age
      assert m.level.between?(10, 15), "5-10 + 10 / 2"
      assert m.stars.between?(1, 5)
    end
    low = FM::Scout.youth(TestSquad::SPECIES, region: "KANTO", scout_level: 0, rng: Random.new(1))
    assert low.level.between?(5, 10), "no scouting office = original level 1"
  end
end
