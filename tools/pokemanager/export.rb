# Exports Poké Manager's static data tables from the bundled index.html as JSON
# and reports how much of it Essentials' PBS already covers.
#   ruby tools/pokemanager/asar.rb extract <PokeManager>/resources.neu import/pokemanager
#   ruby tools/pokemanager/export.rb
# Output: import/pokemanager/data/{dex,trainers,regions}.json (gitignored).
#
# Field meanings come from the comments next to each table in index.html:
#   DEX      [이름, 타입, HP, 공격, 방어, 특공, 특방, 스피드, 진화[[도감번호, 레벨]], 등급, 이전 진화 도감번호]
#            등급 0 일반 / 1 준전설 / 2 전설 / 3 환상 / 4 울트라비스트 / 5 패러독스
#   TRAINERS 지방별 20명 [역할, 이름, 레벨, 스카우팅 시설, 훈련 시설, 잠재력, 로스터 도감번호]
#            역할 C 챔피언 / E1-4 사천왕 / G1-8 관장 / T 트레이너("T:라벨" 가능)
#            로스터가 비면 buildWorld()가 새 게임마다 무작위로 채운다.
require "json"
require "fileutils"

ROOT = File.expand_path("../..", __dir__)
SRC  = File.join(ROOT, "import", "pokemanager", "resources", "index.html")
OUT  = File.join(ROOT, "import", "pokemanager", "data")
REGION_NAMES = %w[관동 성도 호연 신오 하나 칼로스 알로라 가라르 팔데아].freeze

# Returns the JS array/object literal that starts right after `marker`.
# Scans bytes: indexing a big UTF-8 string by character is O(n) per access.
def literal_after(text, marker)
  bytes = text.b
  start = bytes.index(marker.b) or raise "marker not found: #{marker}"
  i = bytes.index(/[\[{]/n, start + marker.bytesize)
  depth = 0
  quote = nil
  j = i
  while j < bytes.bytesize
    c = bytes.getbyte(j)
    if quote
      if c == 92 then j += 1            # backslash
      elsif c == quote then quote = nil
      end
    elsif c == 34 || c == 39 then quote = c   # " '
    elsif c == 91 || c == 123 then depth += 1  # [ {
    elsif c == 93 || c == 125                  # ] }
      depth -= 1
      return bytes[i..j].force_encoding("UTF-8") if depth.zero?
    end
    j += 1
  end
  raise "unterminated literal after #{marker}"
end

text = File.read(SRC, encoding: "utf-8")

dex = JSON.parse(literal_after(text, "const DEX=")).each_with_index.map do |d, i|
  { num: i + 1, name: d[0], types: d[1].split("/"), base: d[2, 6],
    evo: d[8].map { |n, lv| { num: n, level: lv } }, tier: d[9], prev: d[10].zero? ? nil : d[10] }
end

trainers = JSON.parse(literal_after(text, "const TRAINERS=")).each_with_index.flat_map do |list, r|
  list.map do |role, name, lv, scout, train, potential, roster|
    code, label = role.split(":", 2)
    { region: r, region_name: REGION_NAMES[r], role: code, label: label, name: name, level: lv,
      fac: { scout: scout, train: train }, potential: potential, roster: roster, canon: !roster.empty? }
  end
end

# SPONSORS [id, 이름, 지방, 등급 big/local/shop, 종류, 최소 명성] — single-quoted JS.
sponsors = JSON.parse(literal_after(text, "const SPONSORS=").tr("'", '"')).map do |id, name, region, tier, kind, fame|
  { id: id, name: name, region: region, tier: tier, kind: kind, min_fame: fame }
end

FileUtils.mkdir_p(OUT)
File.write(File.join(OUT, "sponsors.json"), JSON.pretty_generate(sponsors), mode: "w:UTF-8")
File.write(File.join(OUT, "dex.json"), JSON.pretty_generate(dex), mode: "w:UTF-8")
File.write(File.join(OUT, "trainers.json"), JSON.pretty_generate(trainers), mode: "w:UTF-8")

# Coverage against Essentials: species in PBS/pokemon.txt, in file order.
pbs = File.read(File.join(ROOT, "PBS", "pokemon.txt"), encoding: "bom|utf-8")
pbs_ids = pbs.scan(/^\[([A-Za-z0-9_]+)\]/).flatten   # NIDORANfE has lowercase
roster_nums = trainers.flat_map { |t| t[:roster] }.uniq.sort
beyond = roster_nums.select { |n| n > pbs_ids.size }
by_tier = dex.group_by { |d| d[:tier] }.transform_values(&:size)

puts "dex species: #{dex.size}  (tiers #{by_tier.sort.to_h})"
puts "trainers: #{trainers.size}  canon rosters: #{trainers.count { |t| t[:canon] }}  " \
     "random rosters: #{trainers.count { |t| !t[:canon] }}"
puts "per region: #{trainers.group_by { |t| t[:region_name] }.transform_values(&:size)}"
puts "Essentials PBS species: #{pbs_ids.size} (last: #{pbs_ids.last})"
puts "distinct roster species: #{roster_nums.size}, beyond PBS: #{beyond.size}"
unless beyond.empty?
  owners = trainers.select { |t| (t[:roster] & beyond).any? }.map { |t| "#{t[:region_name]}:#{t[:name]}" }
  puts "  e.g. #{beyond.first(8).map { |n| "#{n} #{dex[n - 1][:name]}" }.join(', ')}"
  puts "  trainers affected: #{owners.size} (#{owners.first(6).join(', ')}…)"
end
puts "wrote #{OUT}"
