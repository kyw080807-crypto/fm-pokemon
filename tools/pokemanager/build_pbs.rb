# Builds PBS/fm_cities.txt and PBS/fm_clubs.txt (the new game's starting
# world) from:
#   docs/design/08_placement.md      which trainers live in which city
#   docs/design/09_initial_state.md  year-1 city size, stadium, public
#                                    buildings, clubhouse/building levels, type
#   import/pokemanager/data/trainers.json  Poké Manager TRAINERS (export.rb)
#   tools/pokemanager/data/rosters.json    locked random rosters (lock_rosters.js)
#   PBS/pokemon.txt + PBS/pokemon_base_Gen_9_Pack.txt  dex number -> species ID
#
#   ruby tools/pokemanager/build_pbs.rb
# Every trainer must land in exactly one city and every name must resolve, or
# it stops. Canon roster mons get the club's level and stars = potential, as
# Poké Manager's buildWorld() does (minus its ±1 level noise).
require "json"

ROOT = File.expand_path("../..", __dir__)
REGIONS = %w[KANTO JOHTO HOENN SINNOH UNOVA KALOS ALOLA GALAR PALDEA].freeze
REGION_KO = %w[관동 성도 호연 신오 하나 칼로스 알로라 가라르 팔데아].freeze
TYPES = { "노말" => "NORMAL", "불꽃" => "FIRE", "물" => "WATER", "풀" => "GRASS", "전기" => "ELECTRIC",
          "얼음" => "ICE", "격투" => "FIGHTING", "독" => "POISON", "땅" => "GROUND", "비행" => "FLYING",
          "에스퍼" => "PSYCHIC", "벌레" => "BUG", "바위" => "ROCK", "고스트" => "GHOST", "드래곤" => "DRAGON",
          "악" => "DARK", "강철" => "STEEL", "페어리" => "FAIRY" }.freeze
BUILDINGS = { "주거지구" => "RESIDENTIAL", "상점가" => "SHOPPING", "교통" => "TRANSPORT",
              "호텔·관광" => "HOTEL", "방송국" => "BROADCAST", "치안·방재" => "SAFETY", "연구소" => "LAB",
              "보호구역" => "SANCTUARY", "박물관" => "MUSEUM", "온천·요양원" => "SPA",
              "키우미 목장" => "DAYCARE_RANCH" }.freeze
CLUB_BUILDINGS = { "훈" => "TRAINING", "메" => "MEDICAL", "스" => "SCOUTING", "키" => "DAYCARE",
                   "숍" => "SHOP" }.freeze
FORMS = { "리그" => "LEAGUE", "밀란형" => "MILAN", "런던형" => "LONDON", "단독" => "SOLO" }.freeze

def die(msg) = abort("build_pbs: #{msg}")

def md_rows(path)
  region = nil
  rows = []
  File.read(path, encoding: "utf-8").each_line do |line|
    if (m = line.match(/^###\s+\*\*([^\s*]+)/))   # "### **관동 (11개 도시)**" or "### **관동**"
      region = REGION_KO.index(m[1])
    elsif region && line.start_with?("| ") && !line.start_with?("| :") && !line.start_with?("| 도시 ")
      cells = line.strip.sub(/\A\|/, "").sub(/\|\z/, "").split(" | ").map { |c| c.strip.gsub("\\", "") }
      rows << [region, cells]
    end
  end
  rows
end

def species_ids
  %w[pokemon.txt pokemon_base_Gen_9_Pack.txt].flat_map do |f|
    File.read(File.join(ROOT, "PBS", f), encoding: "bom|utf-8").scan(/^\[([A-Za-z0-9_]+)\]/).flatten
  end
end

trainers_path = File.join(ROOT, "import", "pokemanager", "data", "trainers.json")
die "#{trainers_path} missing: run tools/pokemanager/export.rb" unless File.exist?(trainers_path)
trainers = JSON.parse(File.read(trainers_path, encoding: "utf-8"))
locked = JSON.parse(File.read(File.join(__dir__, "data", "rosters.json"), encoding: "utf-8"))["trainers"]
ids = species_ids

# Breeding data from Essentials' own species PBS (FM::Daycare): egg groups and
# gender ratio, keyed by species ID.
def breeding
  %w[pokemon.txt pokemon_base_Gen_9_Pack.txt].each_with_object({}) do |f, h|
    File.read(File.join(ROOT, "PBS", f), encoding: "bom|utf-8").split(/^\[/).drop(1).each do |sec|
      id = sec[/\A([A-Za-z0-9_]+)\]/, 1] or next
      h[id] = { eggs: sec[/^EggGroups = (.+)$/, 1]&.strip || "Undiscovered",
                gender: sec[/^GenderRatio = (.+)$/, 1]&.strip || "Female50Percent" }
    end
  end
end
breed = breeding
die "expected 1025 species, got #{ids.size}" unless ids.size == 1025

# Resolve a short design-doc name ("하준★", "자매") to one Poké Manager trainer.
def find_trainer(trainers, region, short)
  name = short.delete("★").strip
  hits = trainers.select { |t| t["region"] == region && (t["name"] == name || t["name"].end_with?(" #{name}")) }
  die "#{REGION_KO[region]} '#{short}': #{hits.size} matches" unless hits.size == 1
  hits.first
end

# --- 08: city list and residents ------------------------------------------
cities = []
club_city = {}
md_rows(File.join(ROOT, "docs", "design", "08_placement.md")).each do |region, (city, names, form, _why)|
  n = cities.count { |c| c[:region] == region } + 1
  id = format("CITY_%s_%02d", REGIONS[region], n)
  cities << { id: id, region: region, name: city, form: FORMS.fetch(form) { die "form #{form}" }, clubs: [] }
  names.split(",").each do |short|
    t = find_trainer(trainers, region, short)
    key = [t["region"], t["name"]]
    die "#{t['name']} placed twice" if club_city.key?(key)
    club_city[key] = id
    cities.last[:clubs] << t
  end
end
die "placed #{club_city.size} of 180 trainers" unless club_city.size == 180

# --- 09: year-1 state -------------------------------------------------------
club_state = {}
md_rows(File.join(ROOT, "docs", "design", "09_initial_state.md")).each do |region, cells|
  next unless cells.size == 5
  city_name, size, stadium, publics, clubs = cells
  city = cities.find { |c| c[:region] == region && c[:name] == city_name } or die "09: unknown city #{city_name}"
  city[:size] = size[/\A\d/].to_i
  city[:stadium] = stadium
  m = publics.match(/\A(.*)\(빈 (\d+)\)\z/) or die "09: publics '#{publics}'"
  city[:free] = m[2].to_i
  city[:buildings] = m[1].split(",").map(&:strip).map do |b|
    landmark = b.include?("★")
    b = b.delete("★")
    if (t = b.match(/\A타입 지구\((\S+)\) (\d)\z/))
      ["TYPE_DISTRICT", t[2].to_i, TYPES.fetch(t[1])]
    else
      bm = b.match(/\A(.+) (\d)\z/) or die "09: building '#{b}'"
      [BUILDINGS.fetch(bm[1]) { die "09: building name #{bm[1]}" }, bm[2].to_i, landmark ? "LANDMARK" : nil].compact
    end
  end
  # Stadium a club plays home league games in (0 = city-owned rental).
  # "메인 Lv5 + 사이드 Lv3 (위원회 소유)" capitals: league games use the side
  # stadium. "공동 LvN" Milan: shared. "단독 LvN" / "시 소유 임대": the one club.
  # "초련 Lv2 · 하준 임대": per club.
  stadium_of = lambda do |short|
    case stadium
    when /사이드 Lv(\d)/ then Regexp.last_match(1).to_i
    when /\A(공동|단독) Lv(\d)\z/ then Regexp.last_match(2).to_i
    when "시 소유 임대" then 0
    else
      part = stadium.split(" · ").find { |p| p.start_with?("#{short} ") } or die "09: no stadium for #{short} in '#{stadium}'"
      part.end_with?("임대") ? 0 : part[/Lv(\d)/, 1].to_i
    end
  end
  clubs.split(" / ").each do |entry|
    name, levels, type = entry.split(" · ").map(&:strip)
    nm = name.match(/\A(.+) H(\d)\z/) or die "09: club '#{entry}'"
    t = find_trainer(trainers, region, nm[1])
    facs = levels.split.map { |x| xm = x.match(/\A(\D+)(\d)\z/); [CLUB_BUILDINGS.fetch(xm[1]), xm[2].to_i] }
    club_state[[t["region"], t["name"]]] = { clubhouse: nm[2].to_i, facilities: facs, type: TYPES.fetch(type),
                                             stadium: stadium_of.(nm[1]) }
  end
end
missing = cities.reject { |c| c[:size] }.map { |c| c[:name] }
die "09 has no row for #{missing.inspect}" unless missing.empty?
die "09 has state for #{club_state.size} of 180 clubs" unless club_state.size == 180

# --- write -----------------------------------------------------------------
header = ->(what) { "# FM #{what} — generated by tools/pokemanager/build_pbs.rb; edit the sources, not this file.\n" \
                    "# Sources: docs/design/08_placement.md, 09_initial_state.md, Poké Manager TRAINERS, " \
                    "tools/pokemanager/data/rosters.json\n" }

city_txt = +header.call("cities (year-1 state)")
cities.each do |c|
  city_txt << "#-------------------------------\n[#{c[:id]}]\nName = #{c[:name]}\nRegion = #{REGIONS[c[:region]]}\n"
  city_txt << "Form = #{c[:form]}\nSize = #{c[:size]}\nFreePlots = #{c[:free]}\nStadium = #{c[:stadium]}\n"
  c[:buildings].each { |b| city_txt << "Building = #{b.join(',')}\n" }
end

club_txt = +header.call("clubs (year-1 state)")
locked_by = locked.to_h { |t| [[t["region"], t["name"]], t["mons"]] }
trainers.each_with_index do |t, i|
  key = [t["region"], t["name"]]
  st = club_state.fetch(key)
  n = trainers[0..i].count { |x| x["region"] == t["region"] }
  club_txt << "#-------------------------------\n" << format("[CLUB_%s_%02d]\n", REGIONS[t["region"]], n)
  club_txt << "Name = #{t['name']}\nRegion = #{REGIONS[t['region']]}\nCity = #{club_city.fetch(key)}\n"
  club_txt << "Role = #{t['role']}\n"
  club_txt << "Label = #{t['label']}\n" if t["label"]
  club_txt << "Level = #{t['level']}\nPotential = #{t['potential']}\nType = #{st[:type]}\n"
  club_txt << "Canon = #{t['canon'] ? 'true' : 'false'}\n"
  club_txt << "Clubhouse = #{st[:clubhouse]}\nStadium = #{st[:stadium]}\n"
  st[:facilities].each { |f, lv| club_txt << "Facility = #{f},#{lv}\n" }
  t["roster"].each { |num| club_txt << "Pokemon = #{ids[num - 1]},#{t['level']},#{t['potential']}\n" }
  (locked_by[key] || []).each do |m|
    sp = ids[m["num"] - 1] or die "no species ##{m['num']}"
    club_txt << "Pokemon = #{sp},#{m['level']},#{m['stars']}\n"
  end
end

# --- species: Poké Manager's growth data (DEX) keyed by Essentials ID -------
# Evolution levels are Poké Manager's (it turns every evolution into a level);
# FinalBST is the best base stat total reachable by evolving, which scouting
# aims at (SP[].fb). Region is the dex range of the species' generation.
# Types and Prev (what it evolves from) are for the original's roster rules:
# type preference (aiCandScore), one per evolution family (famOf/famDup)
# and homegrown (isHome).
dex_path = File.join(ROOT, "import", "pokemanager", "data", "dex.json")
die "#{dex_path} missing: run tools/pokemanager/export.rb" unless File.exist?(dex_path)
dex = JSON.parse(File.read(dex_path, encoding: "utf-8"))
ranges = [151, 251, 386, 493, 649, 721, 809, 905, 1025]
bst_of = ->(d) { d["base"].sum }
final_bst = lambda do |num, seen = []|
  d = dex[num - 1]
  kids = d["evo"].map { |e| e["num"] }.reject { |n| seen.include?(n) }
  ([bst_of.(d)] + kids.map { |n| final_bst.(n, seen + [num]) }).max
end
species_txt = +header.call("species growth data")
dex.each do |d|
  species_txt << "#-------------------------------\n[#{ids[d['num'] - 1]}]\n"
  species_txt << "Name = #{d['name']}\n"   # Korean name from Poké Manager (Essentials' are English)
  species_txt << "Dex = #{d['num']}\nBST = #{bst_of.(d)}\nFinalBST = #{final_bst.(d['num'])}\n"
  species_txt << "Tier = #{d['tier']}\nRegion = #{REGIONS[ranges.index { |r| d['num'] <= r }]}\n"
  species_txt << "Basic = #{d['prev'] ? 'false' : 'true'}\n"
  species_txt << "Types = #{d['types'].map(&:upcase).join(',')}\n"
  species_txt << "BaseStats = #{d['base'].join(',')}\n"   # HP, Atk, Def, SpA, SpD, Spe (coachSpec)
  br = breed.fetch(ids[d['num'] - 1])
  species_txt << "EggGroups = #{br[:eggs]}\nGenderRatio = #{br[:gender]}\n"
  species_txt << "Prev = #{ids[d['prev'] - 1]}\n" if d["prev"]
  d["evo"].each { |e| species_txt << "Evolution = #{ids[e['num'] - 1]},#{e['level']}\n" }
end

# --- sponsors: Poké Manager SPONSORS --------------------------------------
sponsors = JSON.parse(File.read(File.join(ROOT, "import", "pokemanager", "data", "sponsors.json"), encoding: "utf-8"))
sponsor_txt = +header.call("sponsors")
sponsors.each do |s|
  sponsor_txt << "#-------------------------------\n[#{s['id'].upcase}]\nName = #{s['name']}\n"
  sponsor_txt << "Region = #{REGIONS[s['region']]}\nTier = #{s['tier'].upcase}\nKind = #{s['kind'].upcase}\n"
  sponsor_txt << "MinFame = #{s['min_fame']}\n"
end

# PBS files in this project are UTF-8 with BOM and CRLF, like the shipped ones.
{ "fm_cities.txt" => city_txt, "fm_clubs.txt" => club_txt, "fm_species.txt" => species_txt,
  "fm_sponsors.txt" => sponsor_txt }.each do |file, txt|
  File.binwrite(File.join(ROOT, "PBS", file), "﻿".encode("UTF-8") + txt.gsub("\n", "\r\n"))
end
puts "cities: #{cities.size}  clubs: #{trainers.size}  " \
     "pokemon: #{club_txt.scan(/^Pokemon = /).size}  forms: #{cities.group_by { |c| c[:form] }.transform_values(&:size)}"
