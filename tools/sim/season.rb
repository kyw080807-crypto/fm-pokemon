# Headless world run (roadmap stage 1): 180 clubs in 9 regional leagues,
# advanced day by day through FM::World — no engine, no graphics.
#   ruby tools/sim/season.rb [years=1] [seed=1]
# Reads PBS/fm_clubs.txt and species base stats from PBS; loads FM Core
# straight from Plugins/[010] FM Core.
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

def club_data
  bst = {}
  %w[pokemon.txt pokemon_base_Gen_9_Pack.txt].each do |f|
    pbs_sections(f).each { |id, s| bst[id] = s["BaseStats"].first.split(",").sum(&:to_i) if s["BaseStats"].any? }
  end
  cities = pbs_sections("fm_cities.txt")
  pbs_sections("fm_clubs.txt").map do |id, s|
    one = ->(k) { s[k].first }
    city = cities.fetch(one.("City"))
    { id: id, name: one.("Name"), region: one.("Region"), city: one.("City"), role: one.("Role"),
      canon: one.("Canon") == "true", level: one.("Level").to_i, potential: one.("Potential").to_i,
      stadium: one.("Stadium").to_i, clubhouse: one.("Clubhouse").to_i,
      city_size: city["Size"].first.to_i,
      # Milan cities share one stadium; capitals use the committee's (design 09).
      stadium_shared: %w[MILAN LEAGUE].include?(city["Form"].first),
      facilities: s["Facility"].to_h { |f| k, lv = f.split(","); [k.to_sym, lv.to_i] },
      pokemon: s["Pokemon"].map do |p|
        sp, lv, stars = p.split(",")
        { bst: bst.fetch(sp), level: lv.to_i, stars: stars.to_i }
      end }
  end
end

years = (ARGV[0] || 1).to_i
seed = (ARGV[1] || 1).to_i
data = club_data
world = FM::World.new_game(data, seed: seed)
start_funds = world.clubs.values.sum { |c| c.wallet.balance }
growth = lambda do
  cs = world.clubs.values
  avg = ->(b) { cs.sum { |c| c.facilities.fetch(b, 0) }.fdiv(cs.size).round(2) }
  "clubhouse #{cs.map(&:clubhouse).tally.sort.to_h}, stadium #{cs.map(&:stadium).tally.sort.to_h}, " \
    "mean TRAINING #{avg.(:TRAINING)} SCOUTING #{avg.(:SCOUTING)} MEDICAL #{avg.(:MEDICAL)}"
end
start_growth = growth.call
ends = []
results = []

time = Benchmark.realtime do
  years.times do
    world.advance_days(365).each do |e|
      ends << e if e[:kind] == :league_end
      results.concat(e[:results]) if e[:kind] == :league_round
    end
  end
end

puts format("%d year(s): %d league matches in %.3fs (%.1f ms per year of 180 clubs)",
            years, results.size, time, 1000 * time / years)
n = results.size.to_f
fav = results.count do |h, a, r|
  hr, ar = world.clubs[h].rating, world.clubs[a].rating
  (r[:res] == 1 && hr >= ar) || (r[:res] == -1 && ar > hr)
end
puts format("favourite wins %.1f%%, home wins %.1f%%, draws %.1f%%, mean crowd %d",
            100 * fav / n, 100 * results.count { |*, r| r[:res] == 1 } / n,
            100 * results.count { |*, r| r[:res].zero? } / n, results.sum { |*, r| r[:attendance] } / n)

# Where clubs of each role finish, averaged over all simulated seasons.
pos = Hash.new { |h, k| h[k] = [] }
ends.each { |e| e[:standings].each_with_index { |id, i| pos[world.clubs[id].role[0]] << i + 1 } }
puts "mean finishing position by role: " +
     %w[C E G T].map { |r| format("%s %.1f", r, pos[r].sum.fdiv(pos[r].size)) }.join(", ")

won = ->(v) { (v.negative? ? "-₽" : "₽") + v.abs.round.to_s.reverse.scan(/\d{1,3}/).join(",").reverse }
money = Hash.new(0)
world.clubs.each_value { |c| c.wallet.totals.each { |k, v| money[k] += v } }
puts "money per club per year: " +
     money.sort_by { |_, v| -v }.map { |k, v| "#{k} #{won.(v / 180.0 / years)}" }.join(", ")
balances = world.clubs.values.map { |c| c.wallet.balance }.sort
puts "funds: start total #{won.(start_funds)} -> end total #{won.(balances.sum)}; " \
     "end median #{won.(balances[90])}, in debt #{balances.count(&:negative?)} of 180"
puts "start: #{start_growth}"
puts "end:   #{growth.call}"
by_role = world.clubs.values.group_by { |c| c.role[0] }
puts "mean end funds by role: " + %w[C E G T].map { |r| "#{r} #{won.(by_role[r].sum { |c| c.wallet.balance } / by_role[r].size)}" }.join(", ")

puts "last season, per region: champion (rating) / runner-up / bottom"
ends.last(world.leagues.size).each do |e|
  s = e[:standings]
  fmt = ->(id) { c = world.clubs[id]; "#{c.name} (#{c.rating.round})" }
  puts "  #{e[:region].ljust(7)} #{fmt.(s[0])} / #{fmt.(s[1])} / #{fmt.(s[-1])}"
end
