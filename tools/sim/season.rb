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

def city_data
  pbs_sections("fm_cities.txt").map do |id, s|
    { id: id, name: s["Name"].first, region: s["Region"].first, form: s["Form"].first,
      size: s["Size"].first.to_i, free_plots: s["FreePlots"].first.to_i,
      buildings: s["Building"].map { |b| k, lv = b.split(","); [k.to_sym, lv.to_i] } }
  end
end

def species_data
  pbs_sections("fm_species.txt").to_h do |id, s|
    [id, { bst: s["BST"].first.to_i, fb: s["FinalBST"].first.to_i, tier: s["Tier"].first.to_i,
           region: s["Region"].first, basic: s["Basic"].first == "true",
           evo: s["Evolution"].map { |e| to, lv = e.split(","); [to, lv.to_i] } }]
  end
end

def sponsor_data
  pbs_sections("fm_sponsors.txt").map do |id, s|
    { id: id, name: s["Name"].first, region: s["Region"].first, tier: s["Tier"].first,
      kind: s["Kind"].first, min_fame: s["MinFame"].first.to_i }
  end
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
      type: one.("Type"),
      stadium: one.("Stadium").to_i, clubhouse: one.("Clubhouse").to_i,
      city_size: city["Size"].first.to_i,
      # Milan cities share one stadium; capitals use the committee's (design 09).
      stadium_shared: %w[MILAN LEAGUE].include?(city["Form"].first),
      facilities: s["Facility"].to_h { |f| k, lv = f.split(","); [k.to_sym, lv.to_i] },
      pokemon: s["Pokemon"].map do |p|
        sp, lv, stars = p.split(",")
        { species: sp, bst: bst.fetch(sp), level: lv.to_i, stars: stars.to_i }
      end }
  end
end

years = (ARGV[0] || 1).to_i
seed = (ARGV[1] || 1).to_i
data = club_data
world = FM::World.new_game(data, seed: seed, cities: city_data, species: species_data, sponsors: sponsor_data)
puts "year-1 sponsors: " + world.clubs.values.map { |c| c.sponsor && c.sponsor[:kind] }.tally.sort_by { |_, n| -n }.to_h.to_s
start_rating = world.clubs.transform_values(&:rating)
city_sizes = -> { world.cities.values.map(&:size).tally.sort.to_h }
start_cities = city_sizes.call
meetings = []
squad_events = Hash.new(0)
cup_champs = []
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
      meetings << e if e[:kind] == :meeting
      squad_events[e[:kind]] += 1 if %i[signed released youth].include?(e[:kind])
      cup_champs << e.merge(year: e[:date][0]) if e[:kind] == :cup_champion
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
puts "city sizes: start #{start_cities} -> end #{city_sizes.call}"
meetings.group_by { |m| m[:agenda] }.each do |agenda, ms|
  reasons = ms.flat_map { |m| m[:votes].values.map { |v| v[:reason] } }.compact.tally
  puts "#{agenda} meetings: #{ms.size}, passed #{ms.count { |m| m[:passed] }}; no-vote reasons #{reasons}"
end
puts "total unrest #{world.cities.values.sum(&:unrest)}"
ordinary = world.cities.values.reject(&:capital?)
puts "ordinary cities transport #{ordinary.map(&:transport).tally.sort.to_h}, hotel #{ordinary.map(&:hotel).tally.sort.to_h}"
budgets = world.cities.values.map { |c| c.budget.balance }.sort
puts "city budgets: median #{won.(budgets[budgets.size / 2])}, negative #{budgets.count(&:negative?)} of #{budgets.size}"
cs = world.clubs.values
puts "squads: mean size #{(cs.sum { |c| c.squad.size }.fdiv(cs.size)).round(1)}, " \
     "signing events #{squad_events.sort.to_h}, retired or released mons #{cs.sum { |c| c.retired.size }}, " \
     "empty squads #{cs.count { |c| c.squad.empty? }}"
# Does investment show up in strength? Compare rating change by end training level.
by_train = cs.group_by { |c| c.facilities.fetch(:TRAINING, 0) }.sort.map do |lv, g|
  delta = g.sum { |c| c.rating - start_rating[c.id] }.fdiv(g.size)
  "T#{lv}: #{g.size} clubs #{delta >= 0 ? '+' : ''}#{delta.round}"
end
puts "rating change by end TRAINING level: #{by_train.join(', ')}"
ratings = cs.map(&:rating).sort
puts "ratings: start #{start_rating.values.min.round}-#{start_rating.values.max.round} " \
     "(median #{start_rating.values.sort[90].round}) -> end #{ratings.first.round}-#{ratings.last.round} (median #{ratings[90].round})"
pwt = cup_champs.select { |e| e[:cup] == :pwt }
puts "PWT champions: " + pwt.map { |e| c = world.clubs[e[:club]]; "Y#{e[:year]} #{c.name}(#{c.region})" }.join(", ")
puts "PWT titles by region: #{pwt.map { |e| world.clubs[e[:club]].region }.tally.sort_by { |_, n| -n }.to_h}; " \
     "by role: #{pwt.map { |e| world.clubs[e[:club]].role[0] }.tally}"
subs = cup_champs.reject { |e| e[:cup] == :pwt }
puts "PET/PENT champions by role: #{subs.map { |e| world.clubs[e[:club]].role[0] }.tally}"
by_role = world.clubs.values.group_by { |c| c.role[0] }
puts "mean end funds by role: " + %w[C E G T].map { |r| "#{r} #{won.(by_role[r].sum { |c| c.wallet.balance } / by_role[r].size)}" }.join(", ")

puts "last season, per region: champion (rating) / runner-up / bottom"
ends.last(world.leagues.size).each do |e|
  s = e[:standings]
  fmt = ->(id) { c = world.clubs[id]; "#{c.name} (#{c.rating.round})" }
  puts "  #{e[:region].ljust(7)} #{fmt.(s[0])} / #{fmt.(s[1])} / #{fmt.(s[-1])}"
end
