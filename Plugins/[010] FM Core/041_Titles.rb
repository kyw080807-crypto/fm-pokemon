#===============================================================================
# FM::Titles — 칭호, a title that follows a career (Poké Manager: TITLE_DEF,
# titleCtx, titlesOf, mainTitle, TITLE_NEWS, updateTitles). Pure Ruby;
# names are the UI's (some carry a number or a type).
# - In order (the first that holds is the main one): living legend (3 PWT
#   titles), world champion (this season's PWT), an N-season dynasty (3+
#   league titles in a row), league conqueror (this season), the king
#   reborn (a title after 3+ seasons), former world champion, the fallen
#   king (a title once, 11th or lower now), legend's owner, riser (8+
#   places up), the uncrowned king (4+ top-4 finishes, no title), N league
#   titles, a league title, a type master (5 of 5+ in the entry share a
#   type; not gym leaders), mentor (5+ in its hall of fame), veteran (15
#   seasons), PWT challenger, prospect (a young ordinary T in the top 10).
# - When the leagues end and when the PWT ends, new titles are logged (a
#   season's form titles every season, the others when first earned or
#   renamed) and some make the news.
#===============================================================================
module FM
  module Titles
    DEFS = [
      [:legend, 3, ->(c) { c[:pwt] >= 3 }],
      [:worldnow, 3, ->(c) { c[:h0] && c[:h0][:pwt] == :champion }],
      [:dynasty, 3, ->(c) { c[:streak] >= 3 }],
      [:leaguenow, 2, ->(c) { c[:h0] && c[:h0][:pos] == 1 }],
      [:reborn, 2, ->(c) { c[:h0] && c[:h0][:pos] == 1 && c[:gap_title] >= 3 }],
      [:exworld, 2, ->(c) { c[:pwt] >= 1 }],
      [:fallen, 1, ->(c) { c[:lt] >= 1 && c[:h0] && c[:h0][:pos].to_i >= 11 }],
      [:legowner, 2, ->(c) { c[:leg] }],
      [:surge, 1, ->(c) { c[:h0] && c[:h1] && c[:h1][:pos].to_i - c[:h0][:pos].to_i >= 8 }],
      [:crownless, 1, ->(c) { c[:top4] >= 4 && c[:lt].zero? }],
      [:multi, 2, ->(c) { c[:lt] >= 2 }],
      [:champ1, 1, ->(c) { c[:lt] == 1 }],
      [:mono, 1, ->(c) { c[:mono] && c[:role] != "G" }],
      [:mentor, 1, ->(c) { c[:hof] >= 5 }],
      [:veteran, 0, ->(c) { c[:seasons] >= 15 }],
      [:challenger, 1, ->(c) { c[:pwt_in] >= 1 }],
      [:rising, 0, ->(c) { c[:role] == "T" && !c[:canon] && c[:seasons] <= 4 && c[:h0] && c[:h0][:pos].to_i.between?(1, 10) }]
    ].freeze
    SEASONAL = %i[worldnow leaguenow dynasty reborn fallen surge legowner].freeze
    NEWS = %i[legend worldnow dynasty reborn fallen surge crownless mono mentor multi].freeze
    LOG_SIZE = 40

    module_function

    # titleCtx
    def ctx(world, club)
      h = club.history.select { |_, x| x[:pos] }.sort_by { |y, _| -y }.map { |y, x| x.merge(year: y) }
      streak = 0
      h.each { |x| x[:pos] == 1 ? streak += 1 : break }
      hof = Hof.of(world)
      lw = hof[:league].select { |x| x[:club] == club.id }.map { |x| x[:year] }.sort.reverse
      prev_title = h[0] && lw.find { |y| y < h[0][:year] }
      types = Hash.new(0)
      party = club.entry
      pool = world.species
      party.each { |m| (pool&.dig(m.species, :types) || []).each { |t| types[t.to_s] += 1 } }
      mono = party.size >= 5 ? types.find { |_, n| n >= 5 }&.first : nil
      { h0: h[0], h1: h[1], streak: streak, lt: lw.size, gap_title: prev_title ? h[0][:year] - prev_title : 0,
        pwt: hof[:world].count { |x| x[:club] == club.id }, pwt_in: club.history.values.count { |x| x[:pwt] },
        role: club.role[0], canon: club.canon, top4: h.count { |x| x[:pos] <= 4 },
        leg: !!(pool && Legend.held(club, pool)), mono: mono, hof: (club.hof || []).size, seasons: h.size }
    end

    # titlesOf -> [{ k:, tier:, n: (a number or type for the name) }]
    def of(world, club)
      c = ctx(world, club)
      DEFS.filter_map do |k, tier, cond|
        next unless cond.call(c)
        n = { dynasty: c[:streak], multi: c[:lt], mono: c[:mono] }[k]
        { k: k, tier: tier, n: n }
      end
    end

    # mainTitle: the player's pick if it still holds, else the first.
    def main(world, club)
      ts = of(world, club)
      if club.id == world.player_club && world.my_title && (t = ts.find { |x| x[:k] == world.my_title })
        return t
      end
      ts.first
    end

    # updateTitles -> events
    def update(world)
      year = world.calendar.year
      region = world.player_club && world.clubs[world.player_club]&.region
      world.clubs.values.flat_map do |club|
        log = club.tlog ||= []
        have = log.select { |x| x[:year] == year }.map { |x| x[:k] }
        of(world, club).filter_map do |t|
          next if have.include?(t[:k])
          last = log.find { |x| x[:k] == t[:k] }
          next if !SEASONAL.include?(t[:k]) && last && last[:n] == t[:n]
          log.unshift({ k: t[:k], n: t[:n], year: year })
          log.pop while log.size > LOG_SIZE
          me = club.id == world.player_club
          next unless NEWS.include?(t[:k]) && (me || (t[:k] != :multi && t[:tier] >= 2) || club.region == region)
          { kind: :title_gained, club: club.id, title: t, date: world.calendar.date }
        end
      end
    end
  end
end
