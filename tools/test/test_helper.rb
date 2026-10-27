# Loads every FM Core plugin file with system Ruby (no engine).
# If a Core file references an engine symbol, it fails here — that is the point.
require "minitest/autorun"

ROOT = File.expand_path("../..", __dir__)
# base: keeps "[010]" out of the glob pattern, where it would be a character class.
core_dir = File.join(ROOT, "Plugins", "[010] FM Core")
Dir.glob("*.rb", base: core_dir).sort.each { |f| require File.join(core_dir, f) }
