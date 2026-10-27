#===============================================================================
# FM Debug: smoke checks for Claude Code, which cannot see the game window.
# tools/run_debug.ps1 -Smoke writes logs/smoke.flag; when it exists in debug
# mode, every registered check runs at plugin load, results go to
# logs/fm_runtime.log, and the game exits.
#===============================================================================
module FM
  module Smoke
    FLAG   = "logs/smoke.flag"
    @checks = []

    module_function

    def register(name, &block)
      @checks << [name, block]
    end

    def requested?
      $DEBUG && File.exist?(FLAG)
    end

    def run_all
      FM::Log.info("smoke: #{@checks.size} check(s)")
      failures = 0
      @checks.each do |name, block|
        begin
          block.call
          FM::Log.info("smoke: PASS #{name}")
        rescue StandardError => e
          failures += 1
          FM::Log.error("smoke: FAIL #{name}")
          FM::Log.exception(e)
        end
      end
      FM::Log.info("smoke: done, #{failures} failure(s)")
    end
  end
end

# Renders sample text with each MessageConfig font to logs/font_test.png so the
# result can be inspected as an image.
FM::Smoke.register("font_render") do
  samples = [
    [:pbSetSystemFont, "시스템: 포켓몬 리그 매니저 0123 ABC !?…"],
    [:pbSetSmallFont,  "작은 글씨: 이번 주 수입 12,000원"],
    [:pbSetNarrowFont, "좁은 글씨: 관동 체육관 리그 1라운드"]
  ]
  [MessageConfig::FONT_NAME, MessageConfig::SMALL_FONT_NAME, MessageConfig::NARROW_FONT_NAME].uniq.each do |name|
    raise "font #{name.inspect} not found in Fonts/" unless Font.exist?(name)
  end
  # 32px rows = one message-window line; guide lines mark each row's edges.
  bitmap = Bitmap.new(512, 32 * samples.size)
  bitmap.fill_rect(bitmap.rect, Color.new(248, 248, 248))
  samples.each_with_index do |(setter, text), i|
    send(setter, bitmap)
    bitmap.font.color = Color.new(80, 80, 88)
    bitmap.fill_rect(0, 32 * i, 512, 1, Color.new(255, 0, 0))
    bitmap.fill_rect(0, 32 * i + 31, 512, 1, Color.new(0, 0, 255))
    bitmap.draw_text(8, 32 * i, 496, 32, text)
  end
  raise "Bitmap#to_file not available in this mkxp-z" unless bitmap.respond_to?(:to_file)
  bitmap.to_file("logs/font_test.png")
  bitmap.dispose
end

if FM::Smoke.requested?
  FM::Smoke.run_all
  # PluginManager rescues SystemExit from `exit` and reports it as a plugin
  # error, so leave immediately instead.
  exit!(0)
end
