#===============================================================================
# FM Logger: writes to logs/fm_runtime.log (relative to the game folder) so
# Claude Code can read runtime output without seeing the mkxp-z console.
#===============================================================================
module FM
  module Log
    DIR  = "logs"
    FILE = File.join(DIR, "fm_runtime.log")

    module_function

    def write(level, msg)
      line = "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} [#{level}] #{msg}"
      Dir.mkdir(DIR) unless File.directory?(DIR)
      File.open(FILE, "a:UTF-8") { |f| f.puts(line) }
      # The engine's echo is printf: a bare % would raise and lose the line.
      echoln(line.gsub("%", "%%")) if respond_to?(:echoln, true)
    rescue StandardError
      # Logging must never crash the game.
    end

    def info(msg);  write("INFO", msg);  end
    def warn(msg);  write("WARN", msg);  end
    def error(msg); write("ERROR", msg); end

    def exception(e)
      error("#{e.class}: #{e.message}")
      (e.backtrace || []).first(30).each { |l| write("TRACE", "  #{l}") }
    end
  end
end

# Mirror Essentials' error reporting into our log.
# TODO(verify): confirm pbPrintException is the v21.1 entry point
#   (grep "def pbPrintException" Data/Scripts/) and record it in docs/essentials-notes.md.
if defined?(pbPrintException)
  alias __fm_pbPrintException pbPrintException
  def pbPrintException(e)
    FM::Log.exception(e)
    __fm_pbPrintException(e)
  end
end

FM::Log.info("=== session start (debug=#{$DEBUG.inspect}) ===")
