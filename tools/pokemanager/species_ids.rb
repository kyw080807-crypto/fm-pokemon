# Maps Poké Manager national dex numbers to Essentials species IDs and checks
# every roster species (TRAINERS + locked rosters) resolves.
#   ruby tools/pokemanager/species_ids.rb [--gen9-ids]
# PBS order is national dex order: PBS/pokemon.txt holds #1-898 and the Gen 9
# Pack's PBS/pokemon_base_Gen_9_Pack.txt holds #899-1025.
require "json"

ROOT = File.expand_path("../..", __dir__)

def species_ids
  %w[pokemon.txt pokemon_base_Gen_9_Pack.txt].flat_map do |f|
    path = File.join(ROOT, "PBS", f)
    File.exist?(path) ? File.read(path, encoding: "bom|utf-8").scan(/^\[([A-Za-z0-9_]+)\]/).flatten : []
  end
end

ids = species_ids
trainers = JSON.parse(File.read(File.join(ROOT, "import", "pokemanager", "data", "trainers.json"), encoding: "utf-8"))
locked = JSON.parse(File.read(File.join(__dir__, "data", "rosters.json"), encoding: "utf-8"))["trainers"]

nums = (trainers.flat_map { |t| t["roster"] } + locked.flat_map { |t| t["mons"].map { |m| m["num"] } }).uniq.sort
missing = nums.reject { |n| ids[n - 1] }
gen9 = nums.select { |n| n > 898 }.map { |n| ids[n - 1] }.compact

if ARGV.include?("--gen9-ids")
  puts gen9.join(" ")
else
  puts "PBS species: #{ids.size}; roster species: #{nums.size}; missing: #{missing.size}"
  puts "missing dex numbers: #{missing.inspect}" unless missing.empty?
  puts "Gen 9+ roster species (#{gen9.size}): #{gen9.join(', ')}"
  exit(missing.empty? ? 0 : 1)
end
