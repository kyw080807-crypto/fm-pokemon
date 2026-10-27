# Prints text around matches in a large one-line JS/HTML file.
#   ruby tools/pokemanager/peek.rb <file> <regex> [chars_after=600] [max_hits=3] [chars_before=0]
file, pattern, after, max, before = ARGV
after  = (after || 600).to_i
max    = (max || 3).to_i
before = (before || 0).to_i
text = File.read(file, encoding: "utf-8")
hits = 0
text.scan(Regexp.new(pattern)) do
  m = Regexp.last_match
  from = [m.begin(0) - before, 0].max
  puts "=== @#{m.begin(0)}"
  puts text[from, before + after]
  hits += 1
  break if hits >= max
end
puts "(no match)" if hits.zero?
