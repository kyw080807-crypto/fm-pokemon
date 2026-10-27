#===============================================================================
# Compile the FM PBS files after the engine's own (compile_pbs_files has a
# fixed order; Data/Scripts/021_Compiler/001_Compiler.rb:983). FmClub's
# Pokemon lines are checked against Species, so they must come after it.
#===============================================================================
module Compiler
  FM_DATA_CLASSES = %i[FmSpecies FmCity FmClub FmSponsor].freeze

  class << self
    alias __fm_compile_pbs_files compile_pbs_files unless method_defined?(:__fm_compile_pbs_files)

    def compile_pbs_files
      __fm_compile_pbs_files
      text_files = get_all_pbs_files_to_compile
      FM_DATA_CLASSES.each do |name|
        paths = text_files.dig(name, 1) || []
        compile_PBS_file_generic(GameData.const_get(name), *paths)
      end
    end
  end
end
