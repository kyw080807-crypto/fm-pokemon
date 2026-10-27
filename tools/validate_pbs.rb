# Usage: ruby tools/validate_pbs.rb
# Checks custom PBS/fm_*.txt files outside the engine: section syntax, duplicate
# IDs, unknown/missing keys, integer fields and cross-file references.
# Keep SCHEMAS in sync with the SCHEMA in Plugins/[030] FM Data/.

ROOT = File.expand_path("..", __dir__)

# key => [type, required?, reference_type_or_nil]
SCHEMAS = {
  "fm_cities" => {
    "Name"       => [:string, true,  nil],
    "Region"     => [:int,    true,  nil],
    "Population" => [:int,    false, nil]
  },
  "fm_routes" => {
    "From" => [:id,  true, "fm_cities"],
    "To"   => [:id,  true, "fm_cities"],
    "Cost" => [:int, true, nil],
    "Days" => [:int, true, nil]
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
      current = sections[id] = { line: n, keys: {} }
    elsif line =~ /\A([^=]+?)\s*=\s*(.*)\z/ && current
      current[:keys][Regexp.last_match(1)] = [Regexp.last_match(2), n]
    else
      errors << "#{path}:#{n}: unparseable line: #{line}"
    end
  end
  sections
end

errors = []
data = Hash.new { |h, k| h[k] = {} }

SCHEMAS.each_key do |type|
  Dir[File.join(ROOT, "PBS", "#{type}{,_*}.txt")].sort.each do |path|
    parse(path, errors).each do |id, sec|
      errors << "#{path}:#{sec[:line]}: [#{id}] already defined in #{data[type][id][:path]}" if data[type].key?(id)
      data[type][id] = sec.merge(path: path)
    end
  end
end

SCHEMAS.each do |type, schema|
  data[type].each do |id, sec|
    where = "#{sec[:path]}:#{sec[:line]} [#{id}]"
    schema.each do |key, (_, required, _)|
      errors << "#{where}: missing #{key}" if required && !sec[:keys].key?(key)
    end
    sec[:keys].each do |key, (value, n)|
      rule = schema[key]
      next errors << "#{sec[:path]}:#{n}: unknown key #{key} in [#{id}]" unless rule
      kind, _, ref = rule
      errors << "#{sec[:path]}:#{n}: #{key} must be an integer" if kind == :int && value !~ /\A-?\d+\z/
      errors << "#{sec[:path]}:#{n}: #{key} -> unknown #{ref} [#{value}]" if ref && !data[ref].key?(value)
    end
  end
end

counts = SCHEMAS.keys.map { |t| "#{t}: #{data[t].size}" }.join(", ")
if errors.empty?
  puts "PBS OK (#{counts})"
else
  puts errors
  puts "#{errors.size} error(s) (#{counts})"
  exit 1
end
