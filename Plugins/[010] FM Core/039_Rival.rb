#===============================================================================
# FM::Rival — the player's season rival (Poké Manager: S.h2h, pickRival,
# isRival, rivalResult, the taunt event). Pure Ruby; the player only.
# - Head to head: every official game (or best-of-3 series) against a club
#   counts W/D/L.
# - Each season, while its league is on, a rival from the league: (games
#   played x 1.5 + losses x 1.5) + (8 - the gap in last season's places,
#   or +4 for an ordinary trainer when either has none) + 3 if it was the
#   rival before + up to 2 at random; the best score.
# - A league game against it: a win fame +3, anything else -2 (+5 / -4
#   after answering its taunt). Fans count rival games x1.4 (FM::Fans).
# - The taunt event (FM::Events): answering it, fame +2 and the next rival
#   game weighs more.
#===============================================================================
module FM
  module Rival
    module_function

    def h2h(world) = world.h2h ||= {}

    def count(world, opp_id, my)
      h = (h2h(world)[opp_id] ||= { w: 0, d: 0, l: 0 })
      h[my.positive? ? :w : my.negative? ? :l : :d] += 1
    end

    def rival?(world, id)
      r = world.rival
      !r.nil? && r[:club] == id && r[:year] == world.calendar.year
    end

    def current(world) = (r = world.rival) && r[:year] == world.calendar.year ? r : nil

    # pickRival -> the event or nil
    def pick(world, club, rng)
      league = world.leagues[club.region] or return
      return if league.done?
      year = world.calendar.year
      me = club.history.dig(year - 1, :pos)
      prev = world.rival
      best = nil
      bs = -Float::INFINITY
      league.table.keys.each do |id|
        next if id == club.id
        o = world.clubs[id]
        hh = h2h(world)[id] || { w: 0, l: 0 }
        s = (hh[:w] + hh[:l]) * 1.5 + hh[:l] * 1.5
        p = o.history.dig(year - 1, :pos)
        s += me && p ? 8 - [8, (p - me).abs].min : (o.role.start_with?("T") ? 4 : 0)
        s += 3 if prev && prev[:club] == id
        s += rng.rand * 2
        if s > bs
          bs = s
          best = id
        end
      end
      return unless best
      cont = prev && prev[:club] == best
      world.rival = { club: best, year: year, w: 0, l: 0, since: cont ? prev[:since] : year }
      hh = h2h(world)[best] || { w: 0, l: 0 }
      { kind: :rival_set, club: club.id, rival: best, again: cont, h2h: [hh[:w], hh[:l]], date: world.calendar.date }
    end

    # rivalResult (league games) -> the event or nil
    def result(world, club, opp_id, my)
      return unless rival?(world, opp_id)
      r = world.rival
      won = my.positive?
      won ? r[:w] += 1 : r[:l] += 1
      t = world.taunt
      taunt = t && t[:year] == world.calendar.year && t[:club] == opp_id
      f = won ? (taunt ? 5 : 3) : (taunt ? -4 : -2)
      club.fame = Economy.add_fame(club.fame, f)
      world.taunt = nil if taunt
      { kind: :rival_result, club: club.id, rival: opp_id, won: won, w: r[:w], l: r[:l], fame: f, taunt: !!taunt,
        date: world.calendar.date }
    end
  end
end
