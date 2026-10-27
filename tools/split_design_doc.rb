# Usage: ruby tools/split_design_doc.rb <drive-export.json> [--write]
# Splits the Google Docs Markdown export of "포켓 매니저 에센셜 설계 문서" into
# docs/design/NN_*.md by top-level (##) section, so agents can read one area
# at a time. Without --write it only prints the plan. Re-run after the Google
# Doc changes; the Google Doc stays the source of truth.
require "json"
require "base64"

ROOT = File.expand_path("..", __dir__)
OUT  = File.join(ROOT, "docs", "design")

# "## heading" text (bold markers stripped) => output file.
# Sections listed under one file are concatenated in document order.
FILES = {
  "00_overview.md"      => ["개요와 목표", "범위", "확정 사항 요약", "시작 방식",
                            "이전 방식과 새 방식의 비교"],
  "01_city_club.md"     => ["도시와 클럽 구조", "도시 크기와 건물", "클럽하우스"],
  "02_negotiation.md"   => ["협의 시스템"],
  "03_league_cities.md" => ["리그 중심도시와 대회"],
  "04_finance.md"       => ["재정 시스템"],
  "05_travel_season.md" => ["교통과 원정"],
  "06_match.md"         => ["경기와 전투"],
  "07_maps.md"          => ["월드맵과 맵 제작 방식"],
  "08_placement.md"     => ["연고지 배치표"],
  "09_initial_state.md" => ["게임 시작 시 도시 구성"],
  "10_tech_roadmap.md"  => ["기술 구조와 데이터", "제작 재료", "로드맵", "위험과 미결 사항"]
}.freeze

def heading_text(line)
  line.sub(/\A##\s+/, "").gsub(/\*\*/, "").strip
end

src = ARGV.fetch(0) { abort "usage: ruby tools/split_design_doc.rb <export.json> [--write]" }
json = JSON.parse(File.read(src, encoding: "utf-8"))
md = Base64.decode64(json["content"]).force_encoding("UTF-8")
md = md.delete_prefix("﻿").gsub("\r\n", "\n")

# Images arrive as reference-style base64 data URIs at the end; save them to
# docs/design/img/ and point the ![alt][imageN] references at the files.
images = {}
md = md.gsub(%r{^\[(image\d+)\]: <data:image/(\w+);base64,([^>]+)>\s*\n?}) do
  images[Regexp.last_match(1)] = [Regexp.last_match(2), Regexp.last_match(3)]
  ""
end
md = md.gsub(/!\[([^\]]*)\]\[(image\d+)\]/) do
  name, (ext, _) = Regexp.last_match(2), images[Regexp.last_match(2)]
  ext ? "![#{Regexp.last_match(1)}](img/#{name}.#{ext})" : Regexp.last_match(0)
end

title = nil
sections = []          # [[heading, text]]
current = nil
md.each_line do |line|
  if line.start_with?("# ") && title.nil?
    title = line.sub(/\A#\s+/, "").gsub(/\*\*/, "").strip
  elsif line.start_with?("## ")
    current = [heading_text(line), +""]
    sections << current
  end
  current[1] << line if current
end

known = FILES.values.flatten
unmapped = sections.map(&:first) - known
missing  = known - sections.map(&:first)
puts "title: #{title}"
puts "sections: #{sections.size}, images: #{images.keys.inspect}"
puts "unmapped sections: #{unmapped.inspect}" unless unmapped.empty?
puts "missing sections: #{missing.inspect}" unless missing.empty?
abort "fix FILES before writing" if ARGV.include?("--write") && (!unmapped.empty? || !missing.empty?)

if ARGV.include?("--write")
  Dir.mkdir(File.join(OUT, "img")) unless images.empty? || File.directory?(File.join(OUT, "img"))
  images.each do |name, (ext, data)|
    File.binwrite(File.join(OUT, "img", "#{name}.#{ext}"), Base64.decode64(data))
  end
end

FILES.each do |file, heads|
  body = sections.select { |h, _| heads.include?(h) }.map(&:last).join("\n").rstrip + "\n"
  header = "<!-- #{title} 에서 분리. 원본은 Google Docs이며 그쪽이 기준이다. " \
           "수정은 원본에서 하고 tools/split_design_doc.rb 로 다시 만든다. -->\n\n"
  puts format("%-22s %6d chars  %s", file, body.size, heads.join(" / "))
  File.write(File.join(OUT, file), header + body, mode: "w:UTF-8") if ARGV.include?("--write")
end
