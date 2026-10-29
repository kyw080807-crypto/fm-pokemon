#===============================================================================
# FM Bridge: battle gimmicks through the Deluxe Battle Kit add-ons (Z-Power,
# Dynamax, Terastallization) and Essentials' Mega Evolution, under FM's
# rules (FM::Gimmick): only the match's gimmick, only a mon holding its
# item, every trainer owning the key items. Outside FM battles
# (FM::Battle.gimmicks nil) the plugins behave as they ship.
# Engine API (checked): Battle#pbCanMegaEvolve? / pbCanZMove? /
# pbCanUltraBurst? / pbCanDynamax? / pbCanTerastallize?, pbHasMegaRing? /
# pbHasZRing? / pbHasDynamaxBand? / pbHasTeraOrb?, Battle::Battler#hasMega? /
# hasZMove? / hasUltra? / hasDynamax? / pbDynamaxAvailable? / hasTera?,
# Player#tera_charged?, Pokemon#tera_type= / gmax_factor= / dynamax_able=.
#===============================================================================
module FM
  module Battle
    class << self
      attr_accessor :gimmicks   # FM::Gimmick kinds for the battle on now; nil = not an FM battle
    end

    Z_TYPES = { NORMALIUMZ: "NORMAL", FIGHTINIUMZ: "FIGHTING", FLYINIUMZ: "FLYING", POISONIUMZ: "POISON",
                GROUNDIUMZ: "GROUND", ROCKIUMZ: "ROCK", BUGINIUMZ: "BUG", GHOSTIUMZ: "GHOST", STEELIUMZ: "STEEL",
                FIRIUMZ: "FIRE", WATERIUMZ: "WATER", GRASSIUMZ: "GRASS", ELECTRIUMZ: "ELECTRIC", PSYCHIUMZ: "PSYCHIC",
                ICIUMZ: "ICE", DRAGONIUMZ: "DRAGON", DARKINIUMZ: "DARK", FAIRIUMZ: "FAIRY" }.freeze
    PRIMAL = { REDORB: :GROUDON, BLUEORB: :KYOGRE }.freeze

    module_function

    # FM::Gimmick.catalog from the game data.
    def gimmick_catalog
      mega = {}
      GameData::Species.each do |s|
        next if s.mega_stone.nil?
        (mega[s.mega_stone] ||= []) << s.species unless (mega[s.mega_stone] || []).include?(s.species)
      end
      gmax = []
      GameData::Species.each { |s| gmax << s.species if s.respond_to?(:gmax_move) && s.gmax_move && !gmax.include?(s.species) }
      { mega: mega, primal: PRIMAL.select { |id, _| GameData::Item.exists?(id) },
        z: Z_TYPES.select { |id, _| GameData::Item.exists?(id) }, gmax: gmax }
    end

    def gim?(kind) = gimmicks&.include?(kind)

    # FM battles: the Tera Orb never needs recharging (every trainer holds its
    # key items, ready) and no gimmick is switched off. Set for the battle,
    # then put back.
    def with_gimmick_switches
      ids = []
      ids << [Settings::TERA_ORB_ALWAYS_CHARGED, true] if defined?(Settings::TERA_ORB_ALWAYS_CHARGED)
      %i[NO_ZMOVE NO_ULTRA_BURST NO_DYNAMAX NO_TERASTALLIZE NO_MEGA_EVOLUTION].each do |k|
        ids << [Settings.const_get(k), false] if Settings.const_defined?(k)
      end
      $game_switches ||= Game_Switches.new
      old = ids.map { |id, _| $game_switches[id] }
      ids.each { |id, v| $game_switches[id] = v }
      yield
    ensure
      ids&.each_with_index { |(id, _), i| $game_switches[id] = old[i] } if old
    end
    def fm_battle? = !gimmicks.nil?

    # The battle Pokémon's gimmick state: Max Mushrooms and Tera Crystals are
    # FM items with no battle effect, so it goes in empty-handed with the
    # right to Dynamax (G-Max) or its Tera type.
    def gimmick_pokemon(pkmn, mon)
      id = mon.item
      case FM::Gimmick.kind(id)
      when :dmax
        pkmn.item = nil
        pkmn.fm_dmax = true
        pkmn.gmax_factor = true if id == FM::Gimmick::GMAX_MUSHROOM && pkmn.respond_to?(:gmax_factor=)
      when :tera
        pkmn.item = nil
        type = FM::Gimmick.tera_type(id)&.to_sym
        pkmn.fm_tera = true
        pkmn.tera_type = type if type && GameData::Type.exists?(type) && pkmn.respond_to?(:tera_type=)
      end
      pkmn
    end
  end
end

class Pokemon
  attr_accessor :fm_dmax, :fm_tera   # holds a Max Mushroom / a Tera Crystal (FM::Gimmick)
end

class Battle
  # Key items: every trainer owns them in FM battles (hasKey).
  %i[pbHasMegaRing? pbHasZRing? pbHasDynamaxBand? pbHasTeraOrb?].each do |m|
    next unless method_defined?(m)
    alias_method :"__fm_#{m}", m
    define_method(m) { |*args| FM::Battle.fm_battle? ? true : send(:"__fm_#{m}", *args) }
  end

  { pbCanMegaEvolve?: :mega, pbCanZMove?: :z, pbCanUltraBurst?: :z, pbCanDynamax?: :dmax,
    pbCanTerastallize?: :tera }.each do |m, kind|
    next unless method_defined?(m)
    alias_method :"__fm_#{m}", m
    define_method(m) do |idx|
      next false if FM::Battle.fm_battle? && !FM::Battle.gim?(kind)
      send(:"__fm_#{m}", idx)
    end
  end
end

class Battle::Battler
  { hasMega?: :mega, hasZMove?: :z, hasUltra?: :z }.each do |m, kind|
    next unless method_defined?(m)
    alias_method :"__fm_#{m}", m
    define_method(m) do |*args|
      next false if FM::Battle.fm_battle? && !FM::Battle.gim?(kind)
      send(:"__fm_#{m}", *args)
    end
  end

  if method_defined?(:hasDynamax?)
    alias __fm_hasDynamax? hasDynamax?
    def hasDynamax?(*args)
      return false if FM::Battle.fm_battle? && !(FM::Battle.gim?(:dmax) && @pokemon&.fm_dmax)
      __fm_hasDynamax?(*args)
    end
  end

  # (No map check in FM battles: headless ones have no $game_map.)
  if method_defined?(:pbDynamaxAvailable?)
    alias __fm_pbDynamaxAvailable? pbDynamaxAvailable?
    def pbDynamaxAvailable?
      return __fm_pbDynamaxAvailable? unless FM::Battle.fm_battle?
      side = idxOwnSide
      owner = @battle.pbGetOwnerIndexFromBattlerIndex(@index)
      @battle.dynamax[side][owner] != -2
    end
  end

  if method_defined?(:hasTera?)
    alias __fm_hasTera? hasTera?
    def hasTera?(*args)
      return false if FM::Battle.fm_battle? && !(FM::Battle.gim?(:tera) && @pokemon&.fm_tera)
      __fm_hasTera?(*args)
    end
  end
end

class Player
  if method_defined?(:tera_charged?)
    alias __fm_tera_charged? tera_charged?
    def tera_charged? = FM::Battle.fm_battle? || __fm_tera_charged?
  end
end
