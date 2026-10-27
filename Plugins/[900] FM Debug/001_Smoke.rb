#===============================================================================
# FM Debug: smoke checks for Claude Code, which cannot see the game window.
# tools/run_debug.ps1 -Smoke writes logs/smoke.flag; when it exists in debug
# mode, every registered check runs once data is loaded (just before the
# title screen), results go to logs/fm_runtime.log, and the game exits.
#===============================================================================
module FM
  module Smoke
    FLAG   = "logs/smoke.flag"
    @checks = []

    module_function

    def register(name, &block)
      @checks << [name, block]
    end

    def requested?
      $DEBUG && File.exist?(FLAG)
    end

    def run_all
      FM::Log.info("smoke: #{@checks.size} check(s)")
      failures = 0
      @checks.each do |name, block|
        begin
          block.call
          FM::Log.info("smoke: PASS #{name}")
        rescue StandardError => e
          failures += 1
          FM::Log.error("smoke: FAIL #{name}")
          FM::Log.exception(e)
        end
      end
      FM::Log.info("smoke: done, #{failures} failure(s)")
    end
  end
end

# Renders sample text with each MessageConfig font to logs/font_test.png so the
# result can be inspected as an image.
FM::Smoke.register("font_render") do
  samples = [
    [:pbSetSystemFont, "시스템: 포켓몬 리그 매니저 0123 ABC !?…"],
    [:pbSetSmallFont,  "작은 글씨: 이번 주 수입 12,000원"],
    [:pbSetNarrowFont, "좁은 글씨: 관동 체육관 리그 1라운드"]
  ]
  [MessageConfig::FONT_NAME, MessageConfig::SMALL_FONT_NAME, MessageConfig::NARROW_FONT_NAME].uniq.each do |name|
    raise "font #{name.inspect} not found in Fonts/" unless Font.exist?(name)
  end
  # 32px rows = one message-window line; guide lines mark each row's edges.
  bitmap = Bitmap.new(512, 32 * samples.size)
  bitmap.fill_rect(bitmap.rect, Color.new(248, 248, 248))
  samples.each_with_index do |(setter, text), i|
    send(setter, bitmap)
    bitmap.font.color = Color.new(80, 80, 88)
    bitmap.fill_rect(0, 32 * i, 512, 1, Color.new(255, 0, 0))
    bitmap.fill_rect(0, 32 * i + 31, 512, 1, Color.new(0, 0, 255))
    bitmap.draw_text(8, 32 * i, 496, 32, text)
  end
  raise "Bitmap#to_file not available in this mkxp-z" unless bitmap.respond_to?(:to_file)
  bitmap.to_file("logs/font_test.png")
  bitmap.dispose
end

# Runs the registered :fm_state SaveData value through save -> Marshal ->
# load the way a real save file does, and checks a new game starts clean.
FM::Smoke.register("save_round_trip") do
  value = SaveData.instance_variable_get(:@values).find { |v| v.id == :fm_state }
  unless value
    ids = SaveData.instance_variable_get(:@values).map(&:id)
    raise "SaveData :fm_state is not registered (have #{ids.inspect}, FM::Bridge #{defined?(FM::Bridge) ? 'loaded' : 'missing'})"
  end
  value.load_new_game_value
  raise "new game balance wrong" unless FM.balance == FM::State::START_BALANCE
  FM.state.finance.add_recurring(:smoke_sponsor, amount: 500, category: :sponsor, every: :week)
  FM.advance_days(14)
  before = FM.state.to_h
  saved = Marshal.load(Marshal.dump(value.save))
  value.load_new_game_value
  raise "new game did not reset state" if FM.state.to_h == before
  value.load(saved)
  raise "state changed across save/load" unless FM.state.to_h == before
  FM::Log.info("smoke: after load #{FM.date_text}, balance #{FM.balance}")
end

# Gen 9+ species used by Poké Manager rosters must exist in compiled data
# (Generation 9 Pack) and have front sprites. List from:
#   ruby tools/pokemanager/species_ids.rb --gen9-ids
FM::Smoke.register("roster_gen9_species") do
  ids = %i[OVERQWIL FLORAGATO MEOWSCARADA QUAQUAVAL OINKOLOGNE NYMBLE PAWMOT FIDOUGH DACHSBUN
           SMOLIV SQUAWKABILLY GARGANACL TADBULB BELLIBOLT WATTREL MABOSSTIFF KLAWF SCOVILLAIN
           RELLOR FLITTLE ESPATHRA TINKATON WUGTRIO VAROOM ORTHWORM GLIMMORA GREAVARD HOUNDSTONE
           CETITAN VELUZA CLODSIRE FARIGIRAF DUDUNSPARCE KINGAMBIT BAXCALIBUR OGERPON]
  missing = ids.reject { |id| GameData::Species.exists?(id) }
  raise "species not compiled: #{missing.inspect}" unless missing.empty?
  no_sprite = ids.reject { |id| pbResolveBitmap("Graphics/Pokemon/Front/#{id}") }
  raise "no front sprite: #{no_sprite.inspect}" unless no_sprite.empty?
  count = 0
  GameData::Species.each_species { count += 1 }
  FM::Log.info("smoke: #{count} species compiled, #{ids.size} roster Gen 9+ species OK")
end

# Run just before the title screen: by then Compiler.main has compiled and
# Game.set_up_system has loaded GameData (Data/Scripts/999_Main/999_Main.rb).
# Running at plugin load would see empty GameData.
alias __fm_pbCallTitle pbCallTitle
def pbCallTitle
  if FM::Smoke.requested?
    FM::Smoke.run_all
    # Exit straight away: `exit` would be caught by the engine's error
    # handling and reported as a crash.
    exit!(0)
  end
  __fm_pbCallTitle
end
