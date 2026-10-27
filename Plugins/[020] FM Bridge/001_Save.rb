#===============================================================================
# FM Bridge: the only place FM touches the engine. This file stores FM::State
# in the save file as plain data (FM::State#to_h), and exposes the calls that
# map events use, e.g. a Script command `FM.advance_days(7)`.
# SaveData API: Data/Scripts/002_Save data/002_SaveData_Value.rb
#===============================================================================
module FM
  module Bridge
    module_function

    def state
      @state ||= FM::State.new_game
    end

    def state=(value)
      @state = value
    end
  end

  module_function

  # Event-facing API. Keep these thin: logic lives in FM Core.
  def state
    Bridge.state
  end

  def advance_days(days)
    events = Bridge.state.advance_days(days)
    FM::Log.info("advance_days(#{days}) -> #{Bridge.state.calendar} " \
                 "balance=#{Bridge.state.finance.balance} events=#{events.map(&:first).inspect}")
    events
  end

  def balance
    Bridge.state.finance.balance
  end

  def date_text
    Bridge.state.calendar.to_s
  end
end

SaveData.register(:fm_state) do
  ensure_class :Hash
  save_value { FM::Bridge.state.to_h }
  load_value { |value| FM::Bridge.state = FM::State.from_h(value) }
  new_game_value { FM::State.new_game.to_h }
end
