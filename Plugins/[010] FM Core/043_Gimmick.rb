#===============================================================================
# FM::Gimmick — battle gimmicks by region (Poké Manager: GIM_REG, pwtHost,
# gimOfRegion, gimPWT, gimNow, GIM_HELD, MEGA_STONES, ZCRYS, gimItemKind,
# gimUnique, gimItemOK, megaStoneFor, gmaxOK, gimLive, gimPickHolders,
# aiGimmick, gimPickBonus). Pure Ruby; the battles are the Deluxe Battle Kit
# add-ons' (FM Bridge), the item catalog comes from the game data
# (Gimmick.catalog: mega stones, Z crystals, G-Max species).
# - League games use their region's gimmick: Hoenn and Kalos Mega Evolution,
#   Alola Mega + Z-Moves, Galar Dynamax, Paldea Terastallization; the rest
#   none. Cups use the PWT host's: odd seasons a gimmick region, even ones
#   a plain region, at random, each once before any repeats (pwtHost).
# - A mon uses a gimmick only holding its item, in the held-item slot:
#   its own Mega Stone (40,000; a Primal orb 100,000), a Z-Crystal
#   (20,000), a Max Mushroom (25,000; any number in a team) or G-Max
#   Mushroom (40,000, G-Max species only), a Tera Crystal of one type
#   (20,000, the Tera type). Trainers own every key item (Mega Ring etc.).
#   The item does nothing in other games.
# - The AI, when it shops and when it makes the PWT, sets its best two up
#   for its next gimmick (two of one type avoided), keeping the others in
#   its gimmick bag and its old items back; Z and Tera take the mon's
#   first type (the original picks its strongest move's type).
# Our formula matches have no battle engine: a side with one live gimmick
# holder in its three counts x1.04, with two or more x1.05 (draft, after
# gimPickBonus 4 / 4.8).
#===============================================================================
module FM
  module Gimmick
    REGION = { "HOENN" => %i[mega], "KALOS" => %i[mega], "ALOLA" => %i[mega z], "GALAR" => %i[dmax],
               "PALDEA" => %i[tera] }.freeze
    HOST_GIM = %w[HOENN KALOS ALOLA GALAR PALDEA].freeze
    HOST_PLAIN = %w[KANTO JOHTO SINNOH UNOVA].freeze
    TYPES = %w[NORMAL FIRE WATER ELECTRIC GRASS ICE FIGHTING POISON GROUND FLYING PSYCHIC BUG ROCK GHOST DRAGON DARK
               STEEL FAIRY].freeze
    MUSHROOM = :MAXMUSHROOM
    GMAX_MUSHROOM = :GMAXMUSHROOM
    PRICES = { mega: 40_000, primal: 100_000, z: 20_000, MAXMUSHROOM: 25_000, GMAXMUSHROOM: 40_000, tera: 20_000 }.freeze
    HOLDERS = 2
    MUL_ONE = 1.04
    MUL_TWO = 1.05
    AI_RESERVE_WEEKS = 4

    class << self
      # { mega: { ITEM => [species] }, primal: { ITEM => species }, z: { ITEM => TYPE }, gmax: [species] }
      attr_writer :catalog
      def catalog = @catalog ||= { mega: {}, primal: {}, z: {}, gmax: [] }
    end

    module_function

    def of_region(region) = REGION.fetch(region.to_s, [])

    # pwtHost: kept on the world once drawn.
    def pwt_host(world, year)
      hosts = world.pwt_hosts ||= {}
      return hosts[year] if hosts[year]
      ([1, year - 12].max..year).each do |k|
        next if hosts[k]
        grp = k.odd? ? HOST_GIM : HOST_PLAIN
        recent = []
        j = k - 2
        while j.positive? && recent.size < grp.size - 1 && hosts[j]
          recent << hosts[j]
          j -= 2
        end
        pool = grp - recent
        hosts[k] = pool[world.rng.rand(pool.size)]
      end
      hosts[year]
    end

    def pwt(world) = of_region(pwt_host(world, world.calendar.year))

    # gimNow for a game: a league game its region's, a cup game the PWT's.
    def for_match(world, home, cup:) = cup ? pwt(world) : of_region(home.region)

    def tera_item(type) = :"#{type}TERACRYSTAL"
    def tera_type(id) = id.to_s.end_with?("TERACRYSTAL") ? id.to_s.delete_suffix("TERACRYSTAL") : nil

    # gimItemKind
    def kind(id)
      return unless id
      c = catalog
      return :mega if c[:mega].key?(id) || c[:primal].key?(id)
      return :z if c[:z].key?(id)
      return :dmax if [MUSHROOM, GMAX_MUSHROOM].include?(id)
      return :tera if TYPES.include?(tera_type(id))
      nil
    end

    def item?(id) = !kind(id).nil?
    def unique?(id) = ![MUSHROOM, GMAX_MUSHROOM].include?(id)   # gimUnique

    def price(id)
      case kind(id)
      when :mega then catalog[:primal].key?(id) ? PRICES[:primal] : PRICES[:mega]
      when :z then PRICES[:z]
      when :dmax then PRICES.fetch(id)
      when :tera then PRICES[:tera]
      end
    end

    def base(pool, species)
      s = species
      4.times do
        prev = pool&.dig(s, :prev) or break
        s = prev
      end
      s
    end

    def same?(a, b) = a.to_s == b.to_s

    # gimItemOK
    def ok?(pool, mon, id)
      c = catalog
      case kind(id)
      when nil then false
      when :mega
        (c[:mega][id] || []).any? { |s| same?(s, mon.species) } || same?(c[:primal][id], mon.species)
      when :dmax then id != GMAX_MUSHROOM || gmax?(mon)
      else true
      end
    end

    def gmax?(mon) = catalog[:gmax].any? { |s| same?(s, mon.species) }

    # gimLive
    def live?(pool, mon, gims) = (k = kind(mon.item)) && gims.include?(k) && ok?(pool, mon, mon.item)

    # The formula match's side multiplier (gimPickBonus).
    def side_mul(pool, mons, gims)
      return 1.0 if gims.empty?
      n = mons.count { |m| live?(pool, m, gims) }
      n >= 2 ? MUL_TWO : n == 1 ? MUL_ONE : 1.0
    end

    def mega_stones(mon) = catalog[:mega].select { |_, ss| ss.any? { |s| same?(s, mon.species) } }.keys +
                           catalog[:primal].select { |_, s| same?(s, mon.species) }.keys

    # megaStoneFor: X for physical, Y for special when there are two.
    def mega_for(pool, mon)
      ids = mega_stones(mon)
      return ids.first if ids.size < 2
      b = pool&.dig(mon.species, :base) || []
      want = b.size == 6 && b[1] >= b[3] ? "X" : "Y"
      ids.find { |id| id.to_s.end_with?(want) } || ids[mon.branch % ids.size]
    end

    def z_for(type) = catalog[:z].find { |_, t| same?(t, type) }&.first

    def first_type(pool, mon) = (pool&.dig(mon.species, :types) || []).first.to_s

    # gimPickHolders: the first n that pass, avoiding two of one first type.
    def pick_holders(pool, party, n, &ok)
      out = []
      party.each do |m|
        break if out.size >= n
        next unless ok.call(m)
        if out.any? && first_type(pool, m) == first_type(pool, out[0]) &&
           party.any? { |x| !x.equal?(m) && !out.include?(x) && ok.call(x) && first_type(pool, x) != first_type(pool, out[0]) }
          next
        end
        out << m
      end
      out
    end

    # aiGimmick: `buy` pays for an item (true) or can't (false).
    def ai_prepare(club, pool, gims, &buy)
      bag = club.gbag ||= []
      party = club.entry.each_with_index.sort_by { |m, i| [-m.rating, i] }.map(&:first)
      club.squad.each do |m|
        next unless kind(m.item) && !live?(pool, m, gims)
        bag << m.item
        prev = m.prev_item
        m.item = prev && club.squad.none? { |x| !x.equal?(m) && x.item == prev } ? prev : nil
        m.prev_item = nil
      end
      return if gims.empty?
      get = ->(id) { (i = bag.index(id)) ? (bag.delete_at(i) && true) : buy.call(id) }
      put = lambda do |m, id|
        return true if m.item == id
        return false unless id && get.call(id)
        if m.item
          kind(m.item) ? bag << m.item : m.prev_item = m.item
        end
        m.item = id
        true
      end
      live = -> { party.select { |m| live?(pool, m, gims) } }
      if gims.include?(:mega)
        pick_holders(pool, party, HOLDERS) { |m| mega_for(pool, m) }.each { |m| put.(m, mega_for(pool, m)) unless live?(pool, m, gims) }
      end
      if gims.include?(:z) && live.call.size < HOLDERS
        zt = live.call.filter_map { |m| catalog[:z][m.item] }.map(&:to_s)
        pick_holders(pool, party.reject { |m| live?(pool, m, gims) }, HOLDERS - live.call.size) { true }.each do |m|
          t = first_type(pool, m)
          next if zt.include?(t)
          zt << t if (id = z_for(t)) && put.(m, id)
        end
      end
      if gims.include?(:dmax)
        pick_holders(pool, party, HOLDERS) { true }.each do |m|
          put.(m, gmax?(m) ? GMAX_MUSHROOM : MUSHROOM) unless live?(pool, m, gims)
        end
      end
      if gims.include?(:tera)
        pick_holders(pool, party, HOLDERS) { true }.each do |m|
          next if live?(pool, m, gims)
          types = (pool&.dig(m.species, :types) || []).map(&:to_s)
          t = types.find { |y| party.none? { |x| x.item == tera_item(y) } }
          put.(m, tera_item(t)) if t
        end
      end
    end

    # aiNextGim
    def next_for(world, club)
      cups = world.cups
      cups && cups[:pwt] && cups[:pwt][:players].include?(club.id) ? pwt(world) : of_region(club.region)
    end
  end
end
