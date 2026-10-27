#===============================================================================
# FM Font: switches MessageConfig to the Galmuri pixel fonts in Fonts/ so Korean
# text renders. MessageConfig reads these constants at call time, so replacing
# them here changes every window without touching Data/Scripts.
#
# mkxp-z registers a font under its typographic family (name ID 16) when it has
# one, else its family (ID 1): "Galmuri11", not "Galmuri11 Regular". Check with
#   ruby tools/font_names.rb Fonts/Galmuri11.ttf
# Galmuri11-Condensed is not shipped: it shares the "Galmuri11" family and
# would shadow the regular face, so the narrow font is Galmuri11 too.
# Sizes are multiples of each font's pixel grid (Galmuri11 = 12px, Galmuri9 =
# 10px) so glyphs stay sharp. Y offset 0 puts Galmuri11 where Power Green sits
# with its offset of 8 in a 32px line (checked by rendering both side by side).
#===============================================================================
module MessageConfig
  FM_FONT_SETTINGS = {
    FONT_NAME:            "Galmuri11",
    FONT_SIZE:            24,
    FONT_Y_OFFSET:        0,
    SMALL_FONT_NAME:      "Galmuri9",
    SMALL_FONT_SIZE:      20,
    SMALL_FONT_Y_OFFSET:  0,
    NARROW_FONT_NAME:     "Galmuri11",
    NARROW_FONT_SIZE:     24,
    NARROW_FONT_Y_OFFSET: 0
  }.freeze

  FM_FONT_SETTINGS.each do |const, value|
    remove_const(const) if const_defined?(const, false)
    const_set(const, value)
  end
end
