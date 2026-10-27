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

  def test_save_hash_is_plain_data
    h = FM::State.new_game.to_h
    assert_kind_of Hash, h
    refute_includes Marshal.dump(h), "FM::", "save data must not depend on FM class names"
  end

  def test_rejects_future_schema
    assert_raises(ArgumentError) { FM::State.from_h(schema_version: 99) }
  end
end
