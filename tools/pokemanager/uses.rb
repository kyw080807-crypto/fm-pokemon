# Shows where an identifier is used in the bundled index.html.
#   ruby tools/pokemanager/uses.rb <file> <identifier> [context=200] [max=10]
file, ident, ctx, max = ARGV
ctx = (ctx || 200).to_i
max = (max || 10).to_i
text = File.read(file, encoding: "utf-8")
re = /(?<![\w$])#{Regexp.escape(ident)}(?![\w$])/
hits = 0
text.to_enum(:scan, re).each do
  pos = Regexp.last_match.begin(0)
  puts "=== @#{pos}"
  puts text[[pos - ctx / 2, 0].max, ctx + ident.size]
  hits += 1
  break if hits >= max
end
puts "total matches: #{text.scan(re).size}"
