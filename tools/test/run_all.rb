# Usage: ruby tools/test/run_all.rb
$LOAD_PATH.unshift(__dir__)
Dir[File.join(__dir__, "test_*.rb")].sort.each { |f| require f unless f.end_with?("test_helper.rb") }
