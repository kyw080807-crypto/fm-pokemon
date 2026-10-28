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
  raise "new game has no world" unless FM.world
  FM.advance_days(14)
  fingerprint = -> { [FM.world.calendar.date, FM.world.clubs.values.map { |c| [c.wallet.balance, c.fame] }] }
  before = fingerprint.call
  saved = Marshal.load(Marshal.dump(value.save))
  value.load_new_game_value
  raise "new game did not reset state" if fingerprint.call == before
  value.load(saved)
  raise "world changed across save/load" unless fingerprint.call == before
  FM::Log.info("smoke: after load #{FM.date_text}, #{FM.world.clubs.size} clubs")
end

# Stage-0 gate: the FM data compiles and a full world runs in the engine.
FM::Smoke.register("world_from_gamedata") do
  counts = [GameData::FmClub.count, GameData::FmCity.count, GameData::FmSpecies.count, GameData::FmSponsor.count]
  raise "FM data counts #{counts.inspect}" unless counts == [180, 100, 1025, 33]
  t = Time.now
  w = FM::Bridge.build_world(seed: 1)
  built = Time.now - t
  t = Time.now
  events = w.advance_days(60)
  ran = Time.now - t
  rounds = events.count { |e| e[:kind] == :league_round }
  raise "no league rounds by March 1" if rounds.zero?
  FM::Log.info(format("smoke: world built in %.2fs; 60 days in %.2fs (%d league rounds, %d events)",
                      built, ran, rounds, events.size))
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

# The FM pause-menu entry exists, and the text its screens would show (for
# a chosen club, 60 days in) renders: written to logs/fm_menu.png to look at.
FM::Smoke.register("fm_menu_render") do
  keys = []
  MenuHandlers.each(:pause_menu) { |key, *_| keys << key }
  raise "pause menu has no :fm entry (#{keys.inspect})" unless keys.include?(:fm)
  saved = FM::Bridge.state
  FM::Bridge.state = FM::State.new_game(world: FM::Bridge.build_world(seed: 7))
  begin
    club = FM.world.clubs.values.find { |c| c.region == "KANTO" && c.role == "G3" } || FM.world.clubs.values.first
    FM.state.player_club = club.id
    FM.advance_days(60)
    FM.advance_days(100)   # past a few city meetings and a committee meeting
    rows = FM::UI.my_club_rows(club.id).first(4) + FM::UI.city_rows(club.city, club.id).first(9) +
           FM::UI.committee_rows("KANTO").first(4)
    bitmap = Bitmap.new(Graphics.width, 32 * rows.size)
    bitmap.fill_rect(bitmap.rect, Color.new(248, 248, 248))
    pbSetSystemFont(bitmap)
    bitmap.font.color = Color.new(80, 80, 88)
    rows.each_with_index { |t, i| bitmap.draw_text(8, 32 * i, Graphics.width - 16, 32, t) }
    bitmap.to_file("logs/fm_menu.png")
    bitmap.dispose
    FM::Log.info("smoke: menu rows for #{club.name}: #{rows.size}")
    # Player actions the new menu items call.
    opts = FM::Invest.options(club)
    raise "no build options" if opts.empty?
    cands = FM.world.player_scout(club.region)
    raise "scout returned nothing" if cands.nil? || cands.empty?
    names = cands.map { |cd| FM::UI.species_name(cd[:mon].species) }
    FM::Log.info("smoke: #{opts.size} build options; scouted #{names.join(', ')}")
    # Battle parties can be built for real species (no battle is started:
    # that needs the map scene).
    foe = FM::Battle.trainer_for(FM.world.clubs.values.find { |c| c.role == "C" })
    mine = club.lineup.map { |m| FM::Battle.to_pokemon(m, foe) }
    raise "battle party not built" unless foe.party.size == 3 && mine.all? { |p| p.level == FM::Battle::LEVEL }
    entry_rows = club.entry.map { |m| FM::UI.mon_line(m) }
    raise "entry rows" if entry_rows.empty?
    FM::Log.info("smoke: pick screen row: #{entry_rows.first}")
    # 자동 진행 hooks battle setup; every saved match mode has a label.
    raise "prepare_battle not wrapped" unless BattleCreationHelperMethods.respond_to?(:__fm_prepare_battle)
    raise "match mode labels" unless FM::State::MATCH_MODES.all? { |m| FM::UI.mode_names[m] }
    FM::Log.info("smoke: battle #{foe.name} (#{foe.trainer_type}) " +
                 foe.party.map { |p| "#{p.speciesName} #{p.totalhp}HP" }.join(", "))
  ensure
    FM::Bridge.state = saved
  end
end

# Stage 3 (직접 전투와 자동 진행이 시즌에 맞는다): real AI-vs-AI battles
# between clubs against MatchSim's neutral win odds. Slow, so only with
# logs/calibrate.flag (delete it after). Pairs are clubs of one region on
# day 60 of a seeded world; the result table and the best-fitting SCALE
# go to the log.
FM::Smoke.register("battle_calibration") do
  next FM::Log.info("smoke: battle_calibration skipped (no logs/calibrate.flag)") unless File.exist?("logs/calibrate.flag")
  n = File.read("logs/calibrate.flag").to_i
  n = 300 unless n.positive?
  # Battles read game globals that only exist once a game is loaded.
  $game_switches  ||= Game_Switches.new
  $game_variables ||= Game_Variables.new
  $PokemonGlobal  ||= PokemonGlobalMetadata.new
  $bag            ||= PokemonBag.new
  $player         ||= Player.new("FM", :POKEMONTRAINER_Red)
  w = FM::Bridge.build_world(seed: 11)
  w.advance_days(60)
  rng = Random.new(5)
  by_region = w.clubs.values.group_by(&:region).values
  games = []
  t = Time.now
  n.times do
    a, b = by_region.sample(random: rng).sample(2, random: rng)
    r = FM::Battle.simulate(a, b)
    games << [a.rating - b.rating, r]
  end
  secs = Time.now - t
  bins = [-Float::INFINITY, -100, -50, -20, 20, 50, 100, Float::INFINITY]
  bins.each_cons(2) do |lo, hi|
    g = games.select { |d, _| d >= lo && d < hi }
    next if g.empty?
    real = g.sum { |_, r| r[:res].positive? ? 1.0 : (r[:res].zero? ? 0.5 : 0.0) } / g.size
    sim = g.sum { |d, _| FM::MatchSim.win_probability(d, 0) } / g.size
    FM::Log.info(format("smoke: calib gap %5s..%-5s n=%3d real %.2f sim %.2f", lo, hi, g.size, real, sim))
  end
  decided = games.reject { |_, r| r[:res].zero? }
  ll = lambda do |scale|
    decided.sum do |d, r|
      p = 1.0 / (1.0 + Math.exp(-d / scale))
      Math.log(r[:res].positive? ? p : 1 - p)
    end
  end
  best = (20..400).step(5).max_by { |sc| ll.call(sc.to_f) }
  draws = games.size - decided.size
  turns = games.sum { |_, r| r[:turns] }.fdiv(games.size)
  FM::Log.info(format("smoke: calib %d battles in %.1fs, draws %d, avg %.1f turns, best SCALE %d (now %.0f)",
                      games.size, secs, draws, turns, best, FM::MatchSim::SCALE))
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
