# Usage: ruby tools/font_names.rb Fonts/*.ttf
# Prints a TrueType font's name-table entries (family, subfamily, full name,
# typographic family). mkxp-z registers a font under typo_family (ID 16) when
# present, else family (ID 1); that is the name MessageConfig must use.

WANTED = { 1 => "family", 2 => "subfamily", 4 => "full", 16 => "typo_family" }.freeze

def names(path)
  data = File.binread(path)
  num_tables = data[4, 2].unpack1("n")
  name_off = nil
  num_tables.times do |i|
    tag, _sum, off, _len = data[12 + 16 * i, 16].unpack("a4NNN")
    name_off = off if tag == "name"
  end
  return {} unless name_off
  _fmt, count, str_off = data[name_off, 6].unpack("nnn")
  out = {}
  count.times do |i|
    pid, eid, lid, nid, len, off = data[name_off + 6 + 12 * i, 12].unpack("n6")
    next unless WANTED.key?(nid)
    raw = data[name_off + str_off + off, len]
    if pid == 3 && eid == 1 && lid == 0x409
      out[WANTED[nid]] = raw.force_encoding("UTF-16BE").encode("UTF-8")
    elsif pid == 1 && !out.key?(WANTED[nid])
      out[WANTED[nid]] = raw.force_encoding("ASCII-8BIT").encode("UTF-8", invalid: :replace, undef: :replace)
    end
  end
  out
end

ARGV.each { |path| puts "#{File.basename(path)}: #{names(path).inspect}" }
