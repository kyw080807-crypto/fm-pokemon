#===============================================================================
# FM Data: GameData classes for the PBS/fm_*.txt files that tools/pokemanager/
# build_pbs.rb writes (cities, clubs, species growth data, sponsors). Defining
# DATA_FILENAME and PBS_BASE_FILENAME is enough for GameData.load_all and the
# compiler's file discovery (Data/Scripts/010_Data/001_GameData.rb:248-282);
# 002_Compiler.rb adds them to the compile list.
# Schema letters (Compiler.get_csv_record): s string, u unsigned, b boolean,
# m symbol, e enum, q raw text; ^ = repeatable line; upper case = optional.
#===============================================================================
module GameData
  class FmCity
    attr_reader :id, :real_name, :region, :form, :size, :free_plots, :stadium, :buildings, :pbs_file_suffix

    DATA = {}
    DATA_FILENAME = "fm_cities.dat"
    PBS_BASE_FILENAME = "fm_cities"
    SCHEMA = {
      "SectionName" => [:id,         "m"],
      "Name"        => [:real_name,  "s"],
      "Region"      => [:region,     "m"],
      "Form"        => [:form,       "s"],
      "Size"        => [:size,       "u"],
      "FreePlots"   => [:free_plots, "u"],
      "Stadium"     => [:stadium,    "q"],
      "Building"    => [:buildings,  "^muM"]
    }

    extend ClassMethodsSymbols
    include InstanceMethods

    def initialize(hash)
      @id         = hash[:id]
      @real_name  = hash[:real_name] || ""
      @region     = hash[:region]
      @form       = hash[:form]
      @size       = hash[:size] || 1
      @free_plots = hash[:free_plots] || 0
      @stadium    = hash[:stadium] || ""
      @buildings  = hash[:buildings] || []
      @pbs_file_suffix = hash[:pbs_file_suffix] || ""
    end
  end

  class FmClub
    attr_reader :id, :real_name, :region, :city, :role, :label, :level, :potential, :type, :canon,
                :clubhouse, :stadium, :facilities, :pokemon, :pbs_file_suffix

    DATA = {}
    DATA_FILENAME = "fm_clubs.dat"
    PBS_BASE_FILENAME = "fm_clubs"
    SCHEMA = {
      "SectionName" => [:id,         "m"],
      "Name"        => [:real_name,  "s"],
      "Region"      => [:region,     "m"],
      "City"        => [:city,       "m"],
      "Role"        => [:role,       "s"],
      "Label"       => [:label,      "s"],
      "Level"       => [:level,      "u"],
      "Potential"   => [:potential,  "u"],
      "Type"        => [:type,       "m"],
      "Canon"       => [:canon,      "b"],
      "Clubhouse"   => [:clubhouse,  "u"],
      "Stadium"     => [:stadium,    "u"],
      "Facility"    => [:facilities, "^mu"],
      "Pokemon"     => [:pokemon,    "^euu", :Species]
    }

    extend ClassMethodsSymbols
    include InstanceMethods

    def initialize(hash)
      @id         = hash[:id]
      @real_name  = hash[:real_name] || ""
      @region     = hash[:region]
      @city       = hash[:city]
      @role       = hash[:role] || "T"
      @label      = hash[:label]
      @level      = hash[:level] || 1
      @potential  = hash[:potential] || 1
      @type       = hash[:type] || :NORMAL
      @canon      = hash[:canon] || false
      @clubhouse  = hash[:clubhouse] || 1
      @stadium    = hash[:stadium] || 0
      @facilities = hash[:facilities] || []
      @pokemon    = hash[:pokemon] || []
      @pbs_file_suffix = hash[:pbs_file_suffix] || ""
    end
  end

  class FmSpecies
    attr_reader :id, :real_name, :dex, :bst, :final_bst, :tier, :region, :basic, :evolutions, :types, :prev, :base_stats, :egg_groups, :gender_ratio,
                :pbs_file_suffix

    DATA = {}
    DATA_FILENAME = "fm_species.dat"
    PBS_BASE_FILENAME = "fm_species"
    SCHEMA = {
      "SectionName" => [:id,         "m"],
      "Name"        => [:real_name,  "s"],   # Korean (Poké Manager)
      "Dex"         => [:dex,        "u"],
      "BST"         => [:bst,        "u"],
      "FinalBST"    => [:final_bst,  "u"],
      "Tier"        => [:tier,       "u"],
      "Region"      => [:region,     "m"],
      "Basic"       => [:basic,      "b"],
      "Evolution"   => [:evolutions, "^muM"],   # species, level, item (optional)
      "Types"       => [:types,      "*m"],   # Poké Manager's (lower-case there)
      "Prev"        => [:prev,       "m"],
      "BaseStats"   => [:base_stats, "*u"],   # HP, Atk, Def, SpA, SpD, Spe
      "EggGroups"   => [:egg_groups, "*s"],   # Essentials' (FM::Daycare)
      "GenderRatio" => [:gender_ratio, "s"]
    }

    extend ClassMethodsSymbols
    include InstanceMethods

    def initialize(hash)
      @id         = hash[:id]
      @real_name  = hash[:real_name] || ""
      @dex        = hash[:dex]
      @bst        = hash[:bst]
      @final_bst  = hash[:final_bst]
      @tier       = hash[:tier] || 0
      @region     = hash[:region]
      @basic      = hash[:basic] || false
      @evolutions = hash[:evolutions] || []
      @types      = hash[:types] || []
      @prev       = hash[:prev]
      @base_stats = hash[:base_stats] || []
      @egg_groups = hash[:egg_groups] || []
      @gender_ratio = hash[:gender_ratio] || "Female50Percent"
      @pbs_file_suffix = hash[:pbs_file_suffix] || ""
    end
  end

  class FmSponsor
    attr_reader :id, :real_name, :region, :tier, :kind, :min_fame, :pbs_file_suffix

    DATA = {}
    DATA_FILENAME = "fm_sponsors.dat"
    PBS_BASE_FILENAME = "fm_sponsors"
    SCHEMA = {
      "SectionName" => [:id,        "m"],
      "Name"        => [:real_name, "s"],
      "Region"      => [:region,    "m"],
      "Tier"        => [:tier,      "s"],
      "Kind"        => [:kind,      "s"],
      "MinFame"     => [:min_fame,  "u"]
    }

    extend ClassMethodsSymbols
    include InstanceMethods

    def initialize(hash)
      @id        = hash[:id]
      @real_name = hash[:real_name] || ""
      @region    = hash[:region]
      @tier      = hash[:tier]
      @kind      = hash[:kind]
      @min_fame  = hash[:min_fame] || 0
      @pbs_file_suffix = hash[:pbs_file_suffix] || ""
    end
  end
end
