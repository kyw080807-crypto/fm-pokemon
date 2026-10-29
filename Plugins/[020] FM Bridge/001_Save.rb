#===============================================================================
# FM Bridge: the only place FM touches the engine. This file builds the FM
# world from compiled GameData (FM Data plugin), stores FM::State in the save
# file, and exposes the calls that map events use, e.g. a Script command
# `FM.advance_days(7)`.
# SaveData API: Data/Scripts/002_Save data/002_SaveData_Value.rb
#===============================================================================
module FM
  module Bridge
    module_function

    def state
      @state ||= new_state
    end

    def state=(value)
      @state = value
    end

    def new_state
      FM::State.new_game(world: world_available? ? build_world(seed: rand(2**31)) : nil)
    end

    def world_available?
      defined?(GameData::FmClub) && GameData::FmClub.count.positive?
    end

    # GameData -> the plain hashes FM::World.new_game takes (the same shape
    # tools/sim/season.rb reads from the PBS text).
    def world_data
      species = {}
      GameData::FmSpecies.each do |s|
        species[s.id] = { bst: s.bst, fb: s.final_bst, tier: s.tier, region: s.region.to_s,
                          basic: s.basic, evo: s.evolutions.map { |to, lv, item| [to, lv, item&.to_sym].compact },
                          types: s.types.map(&:to_s), prev: s.prev&.to_s, base: s.base_stats.dup,
                          eggs: s.egg_groups.dup, gender: s.gender_ratio }
      end
      cities = []
      forms = {}
      GameData::FmCity.each do |c|
        forms[c.id] = c.form
        cities << { id: c.id, name: c.real_name, region: c.region.to_s, form: c.form, size: c.size,
                    free_plots: c.free_plots, buildings: c.buildings.map { |b| b.compact } }
      end
      clubs = []
      GameData::FmClub.each do |c|
        city = GameData::FmCity.get(c.city)
        clubs << { id: c.id, name: c.real_name, region: c.region.to_s, city: c.city, role: c.role,
                   canon: c.canon, level: c.level, potential: c.potential, type: c.type.to_s,
                   stadium: c.stadium, clubhouse: c.clubhouse, city_size: city.size,
                   stadium_shared: %w[MILAN LEAGUE].include?(forms[c.city]),
                   facilities: c.facilities.to_h { |k, lv| [k, lv] },
                   pokemon: c.pokemon.map do |sp, lv, stars|
                     { species: sp, bst: species.fetch(sp)[:bst], level: lv, stars: stars }
                   end }
      end
      sponsors = []
      GameData::FmSponsor.each do |s|
        sponsors << { id: s.id, name: s.real_name, region: s.region.to_s, tier: s.tier, kind: s.kind,
                      min_fame: s.min_fame }
      end
      { clubs: clubs, cities: cities, species: species, sponsors: sponsors }
    end

    def refresh_static(world)
      return unless world && world_available?
      d = world_data
      world.refresh_static(species: d[:species], club_types: d[:clubs].to_h { |c| [c[:id], c[:type]] })
    end

    def build_world(seed:)
      d = world_data
      FM::World.new_game(d[:clubs], seed: seed, cities: d[:cities], species: d[:species], sponsors: d[:sponsors])
    end
  end

  module_function

  # Event-facing API. Keep these thin: logic lives in FM Core.
  def state
    Bridge.state
  end

  def world
    Bridge.state.world
  end

  def advance_days(days)
    events = Bridge.state.advance_days(days)
    if world
      FM::Log.info("advance_days(#{days}) -> #{world.calendar} events=#{events.size}")
    else
      FM::Log.info("advance_days(#{days}) -> #{Bridge.state.calendar} " \
                   "balance=#{Bridge.state.finance.balance} events=#{events.map(&:first).inspect}")
    end
    events
  end

  def balance
    Bridge.state.finance.balance
  end

  def date_text
    (world ? world.calendar : Bridge.state.calendar).to_s
  end
end

SaveData.register(:fm_state) do
  ensure_class :Hash
  save_value { FM::Bridge.state.to_h }
  load_value do |value|
    FM::Bridge.state = FM::State.from_h(value)
    FM::Bridge.refresh_static(FM::Bridge.state.world)
  end
  new_game_value { FM::Bridge.new_state.to_h }
end
