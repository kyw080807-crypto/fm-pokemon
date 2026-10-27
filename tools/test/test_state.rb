require_relative "test_helper"

class TestState < Minitest::Test
  def test_new_game_defaults
    state = FM::State.new_game
    assert_equal [1, 1, 1], state.date
    assert_equal FM::State::START_BALANCE, state.finance.balance
  end

  def test_advance_days_applies_recurring_items
    state = FM::State.new_game(balance: 0)
    state.finance.add_recurring(:sponsor, amount: 100, category: :sponsor, every: :week)
    events = state.advance_days(14)
    assert_equal [1, 1, 15], state.date
    assert_equal 200, state.finance.balance
    assert_equal 2, events.count { |kind, _| kind == :new_week }
    # Recurring entries are dated on the day the week started.
    assert_equal [[1, 1, 8], [1, 1, 15]], state.finance.entries.map(&:date)
  end

  def test_save_hash_survives_marshal
    state = FM::State.new_game
    state.finance.add_recurring(:rent, amount: -50, category: :rent, every: :month)
    state.advance_days(40)
    h = Marshal.load(Marshal.dump(state.to_h))
    copy = FM::State.from_h(h)
    assert_equal state.to_h, copy.to_h
  end

  # Calendar and finance are plain data; the world (when present) is kept as
  # objects under a schema version — see FM::State.
  def test_save_hash_without_world_is_plain_data
    h = FM::State.new_game.to_h
    assert_kind_of Hash, h
    refute_includes Marshal.dump(h), "FM::", "save data must not depend on FM class names"
  end

  def small_world(seed)
    clubs = (0...4).map do |i|
      { id: "K#{i}", name: "K#{i}", region: "KANTO", city: "C", role: "T", canon: true, level: 20 + i,
        potential: 3, stadium: 1, pokemon: [{ species: "PIDGEY", bst: 251 + 40 * i, level: 20, stars: 3 }] * 3 }
    end
    FM::World.new_game(clubs, seed: seed, species: { "PIDGEY" => { bst: 251, fb: 479, tier: 0, region: "KANTO",
                                                                   basic: true, evo: [] } })
  end

  # A world saved mid-season and loaded must continue exactly as if it had
  # never stopped (Random state included).
  def test_world_survives_save_and_continues_identically
    a = small_world(9)
    a.advance_days(100)
    state = FM::State.new_game(world: a)
    copy = FM::State.from_h(Marshal.load(Marshal.dump(state.to_h)))
    b = copy.world
    a.advance_days(200)
    b.advance_days(200)
    fingerprint = ->(w) { w.clubs.values.map { |c| [c.wallet.balance, c.fame.round(4), c.squad.size, c.rating.round(4)] } }
    assert_equal fingerprint.(a), fingerprint.(b)
    assert_equal a.calendar.date, b.calendar.date
  end

  def test_state_v1_saves_still_load
    v1 = { schema_version: 1, calendar: FM::Calendar.new.to_h, finance: FM::Finance.new(balance: 5).to_h }
    s = FM::State.from_h(v1)
    assert_nil s.world
    assert_equal 5, s.finance.balance
  end

  def test_rejects_future_schema
    assert_raises(ArgumentError) { FM::State.from_h(schema_version: 99) }
  end
end
