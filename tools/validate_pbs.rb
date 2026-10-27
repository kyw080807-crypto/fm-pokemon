# Usage: ruby tools/validate_pbs.rb
# Checks custom PBS/fm_*.txt files outside the engine: section syntax, duplicate
# IDs, unknown/missing keys, value shapes and cross-file references.
# Keep SCHEMAS in sync with the SCHEMA in Plugins/[030] FM Data/ (once it exists)
# and with tools/pokemanager/build_pbs.rb, which writes these files.

ROOT = File.expand_path("..", __dir__)

REGIONS  = %w[KANTO JOHTO HOENN SINNOH UNOVA KALOS ALOLA GALAR PALDEA].freeze
TYPES    = %w[NORMAL FIRE WATER GRASS ELECTRIC ICE FIGHTING POISON GROUND FLYING PSYCHIC BUG
              ROCK GHOST DRAGON DARK STEEL FAIRY].freeze
INT      = /\A-?\d+\z/

# key => { check: Regexp | Array | Proc(value, data) -> error|nil, required:, repeat:, ref: }
SCHEMAS = {
  "fm_cities" => {
    "Name"      => { required: true },
    "Region"    => { required: true, check: REGIONS },
    "Form"      => { required: true, check: %w[LEAGUE MILAN LONDON SOLO] },
    "Size"      => { required: true, check: /\A[1-5]\z/ },
    "FreePlots" => { required: true, check: INT },
    "Stadium"   => { required: true },
    "Building"  => { repeat: true, check: /\A[A-Z_]+,[0-5](,[A-Z_]+)?\z/ }
  },
  "fm_clubs" => {
    "Name"      => { required: true },
    "Region"    => { required: true, check: REGIONS },
    "City"      => { required: true, ref: "fm_cities" },
    "Role"      => { required: true, check: /\A(C|E[1-4]|G[1-8]|T)\z/ },
    "Label"     => {},
    "Level"     => { required: true, check: INT },
    "Potential" => { required: true, check: /\A[1-5]\z/ },
    "Type"      => { required: true, check: TYPES },
    "Canon"     => { required: true, check: %w[true false] },
    "Clubhouse" => { required: true, check: /\A[1-5]\z/ },
    "Stadium"   => { required: true, check: /\A[0-6]\z/ },
    "Facility"  => { repeat: true, check: /\A(TRAINING|MEDICAL|SCOUTING|DAYCARE|SHOP),[1-5]\z/ },
    "Pokemon"   => { repeat: true, required: true, check: :species }
  },
  "fm_sponsors" => {
    "Name"    => { required: true },
    "Region"  => { required: true, check: REGIONS },
    "Tier"    => { required: true, check: %w[BIG LOCAL SHOP] },
    "Kind"    => { required: true, check: %w[STABLE PERF STRICT FAME BUZZ SHOP RISKY] },
    "MinFame" => { required: true, check: INT }
  },
  "fm_species" => {
    "Dex"       => { required: true, check: INT },
    "BST"       => { required: true, check: INT },
    "FinalBST"  => { required: true, check: INT },
    "Tier"      => { required: true, check: /\A[0-5]\z/ },
    "Region"    => { required: true, check: REGIONS },
    "Basic"     => { required: true, check: %w[true false] },
    "Evolution" => { repeat: true, check: :evolution }
  }
}.freeze

def parse(path, errors)
  sections = {}
  current = nil
  File.read(path, encoding: "bom|utf-8").each_line.with_index(1) do |raw, n|
    line = raw.sub(/#.*/, "").strip
    next if line.empty?
    if line =~ /\A\[\s*(.+?)\s*\]\z/
      id = Regexp.last_match(1)
      errors << "#{path}:#{n}: duplicate section [#{id}]" if sections.key?(id)
      current = sections[id] = { line: n, keys: Hash.new { |h, k| h[k] = [] } }
    elsif line =~ /\A([^=]+?)\s*=\s*(.*)\z/ && current
      current[:keys][Regexp.last_match(1)] << [Regexp.last_match(2), n]
    else
      errors << "#{path}:#{n}: unparseable line: #{line}"
    end
  end
  sections
end

def species_ids
  %w[pokemon.txt pokemon_base_Gen_9_Pack.txt].flat_map do |f|
    path = File.join(ROOT, "PBS", f)
    File.exist?(path) ? File.read(path, encoding: "bom|utf-8").scan(/^\[([A-Za-z0-9_]+)\]/).flatten : []
  end.to_h { |id| [id, true] }
end

errors = []
data = Hash.new { |h, k| h[k] = {} }
SPECIES = species_ids

SCHEMAS.each_key do |type|
  Dir[File.join(ROOT, "PBS", "#{type}{,_*}.txt")].sort.each do |path|
    parse(path, errors).each do |id, sec|
      errors << "#{path}:#{sec[:line]}: [#{id}] already defined in #{data[type][id][:path]}" if data[type].key?(id)
      data[type][id] = sec.merge(path: path)
    end
  end
end

def bad_value(rule, value)
  case rule[:check]
  when nil    then nil
  when Regexp then "#{value.inspect} doesn't match #{rule[:check].source}" unless value.match?(rule[:check])
  when Array  then "#{value.inspect} not one of #{rule[:check].first(4).join('/')}…" unless rule[:check].include?(value)
  when :evolution
    sp, lv = value.split(",")
    return "#{value.inspect} must be SPECIES,LEVEL" unless lv&.match?(INT)
    "unknown species #{sp}" unless SPECIES.key?(sp)
  when :species
    sp, lv, stars = value.split(",")
    return "#{value.inspect} must be SPECIES,LEVEL,STARS" unless lv&.match?(INT) && stars&.match?(/\A[1-5]\z/)
    "unknown species #{sp}" unless SPECIES.key?(sp)
  end
end

SCHEMAS.each do |type, schema|
  data[type].each do |id, sec|
    where = "#{sec[:path]}:#{sec[:line]} [#{id}]"
    schema.each do |key, rule|
      errors << "#{where}: missing #{key}" if rule[:required] && sec[:keys][key].empty?
    end
    sec[:keys].each do |key, values|
      rule = schema[key]
      next errors << "#{sec[:path]}:#{values.first[1]}: unknown key #{key} in [#{id}]" unless rule
      errors << "#{sec[:path]}:#{values[1][1]}: #{key} repeated in [#{id}]" if values.size > 1 && !rule[:repeat]
      values.each do |value, n|
        if (msg = bad_value(rule, value))
          errors << "#{sec[:path]}:#{n}: #{key} #{msg}"
        end
        errors << "#{sec[:path]}:#{n}: #{key} -> unknown #{rule[:ref]} [#{value}]" if rule[:ref] && !data[rule[:ref]].key?(value)
      end
    end
  end
end

counts = SCHEMAS.keys.map { |t| "#{t}: #{data[t].size}" }.join(", ")
if errors.empty?
  puts "PBS OK (#{counts})"
else
  puts errors.first(50)
  puts "#{errors.size} error(s) (#{counts})"
  exit 1
end
