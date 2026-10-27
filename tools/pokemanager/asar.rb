# Read-only reader for Poké Manager's resources.neu (Neutralino, asar format).
#   ruby tools/pokemanager/asar.rb list    <resources.neu>
#   ruby tools/pokemanager/asar.rb extract <resources.neu> <out_dir>
# asar layout: uint32 4 | uint32 header_size | uint32 pickle_len | uint32 json_len
# | JSON index | file bytes (offsets relative to 8 + header_size).
require "json"
require "fileutils"

def read_index(path)
  File.open(path, "rb") do |f|
    _, header_size, _, json_len = f.read(16).unpack("V4")
    index = JSON.parse(f.read(json_len))
    [index, 8 + header_size]
  end
end

def each_file(node, prefix = "", &block)
  node.fetch("files", {}).each do |name, entry|
    path = prefix.empty? ? name : "#{prefix}/#{name}"
    if entry.key?("files")
      each_file(entry, path, &block)
    else
      yield path, entry
    end
  end
end

cmd, src, out = ARGV
abort "usage: asar.rb list|extract <resources.neu> [out_dir]" unless %w[list extract].include?(cmd) && src
index, base = read_index(src)

if cmd == "list"
  each_file(index) { |p, e| puts format("%10d  %s", e["size"].to_i, p) }
else
  abort "extract needs <out_dir>" unless out
  File.open(src, "rb") do |f|
    each_file(index) do |p, e|
      next if e["unpacked"]
      dest = File.join(out, p)
      raise "unsafe path #{p}" unless File.expand_path(dest).start_with?(File.expand_path(out))
      FileUtils.mkdir_p(File.dirname(dest))
      f.seek(base + e["offset"].to_i)
      File.binwrite(dest, f.read(e["size"].to_i))
    end
  end
  puts "extracted to #{out}"
end
