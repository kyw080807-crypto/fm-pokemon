# Headless season run (roadmap stage 1): all 9 regional leagues, 180 clubs,
# 38 rounds each, results from FM::MatchSim — no engine, no graphics.
#   ruby tools/sim/season.rb [seasons=1] [seed=1]
# Club strength = mean base stat total of its best 3 roster species (matches
# are 3-of-6 at Lv50, as in Poké Manager). Reads PBS/fm_clubs.txt and species
# base stats from PBS; loads FM Core straight from Plugins/[010] FM Core.
require "benchmark"

ROOT = File.expand_path("../..", __dir__)
core = File.join(ROOT, "Plugins", "[010] FM Core")
Dir.glob("*.rb", base: core).sort.each { |f| require File.join(core, f) }

def pbs_sections(file)
  sections = {}
  cur = nil
  File.read(File.join(ROOT, "PBS", file), encoding: "bom|utf-8").each_line do |raw|
    line = raw.sub(/#.*/, "").strip
    next if line.empty?
    if line =~ /\A\[(.+)\]\z/
      cur = sections[Regexp.last_match(1)] = Hash.new { |h, k| h[k] = [] }
    elsif cur && line =~ /\A(\w+)\s*=\s*(.*)\z/
      cur[Regexp.last_match(1)] << Regexp.last_match(2)
    end
  end
  sections
end

bst = {}
%w[pokemon.txt pokemon_base_Gen_9_Pack.txt].each do |f|
  pbs_sections(f).each { |id, s| bst[id] = s["BaseStats"].first.split(",").sum(&:to_i) if s["BaseStats"].any? }
end

clubs = pbs_sections("fm_clubs.txt").map do |id, s|
  totals = s["Pokemon"].map { |p| bst.fetch(p.split(",").first) }.sort.reverse
  { id: id, name: s["Name"].first, region: s["Region"].first, rating: totals.first(3).sum / 3.0 }
end
by_id = clubs.to_h { |c| [c[:id], c] }
regions = clubs.group_by { |c| c[:region] }

seasons = (ARGV[0] || 1).to_i
seed = (ARGV[1] || 1).to_i
rng = Random.new(seed)
stats = Hash.new(0)
last = nil

time = Benchmark.realtime do
  seasons.times do
    last = regions.to_h do |region, list|
      league = FM::League.new(list.map { |c| c[:id] }, rng: rng)
      league.rounds.times do
        league.play_round do |home, away|
          ra, rb = by_id[home][:rating], by_id[away][:rating]
          r = FM::MatchSim.play(ra, rb, rng: rng)
          stats[:matches] += 1
          stats[:draws] += 1 if r[:res].zero?
          fav_home = ra >= rb
          stats[:fav_wins] += 1 if (r[:res] == 1 && fav_home) || (r[:res] == -1 && !fav_home)
          stats[:home_wins] += 1 if r[:res] == 1
          r
        end
      end
      [region, league]
    end
  end
end

pct = ->(k) { format("%.1f%%", 100.0 * stats[k] / stats[:matches]) }
puts format("%d season(s), %d matches in %.3fs (%.2f ms per season of 180 clubs)",
            seasons, stats[:matches], time, 1000 * time / seasons)
puts "favourite wins #{pct.(:fav_wins)}, home wins #{pct.(:home_wins)}, draws #{pct.(:draws)}"
puts "last season, per region: champion (rating) / runner-up / bottom"
last.each do |region, league|
  s = league.standings
  fmt = ->(id) { c = by_id[id]; t = league.table[id]; "#{c[:name]} #{t[:pts]}pts (#{c[:rating].round})" }
  puts "  #{region.ljust(7)} #{fmt.(s[0])} / #{fmt.(s[1])} / #{fmt.(s[-1])}"
end
