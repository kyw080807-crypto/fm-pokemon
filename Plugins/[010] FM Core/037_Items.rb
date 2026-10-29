#===============================================================================
# FM::Items — held items and the shop (Poké Manager: HELD, CONSUMABLE,
# itemPrice, shopMul, invAdd, buyItem, teamHolds, equipItem, returnItem,
# consumeItems, pickItemFor, aiMetaTeam's item part). Pure Ruby.
# - HELD: the original's 39 battle items and prices (names and texts are
#   the UI's). Ids are Essentials item ids.
# - The player buys into the club's bag (x0.8 with a SHOP sponsor), and
#   gives a mon one item; no two of the team hold the same one. A mon that
#   leaves (retires, released) gives its item back to the bag.
# - Real battles use the item as Essentials does. A consumable used up in
#   a real battle is gone; the bag's next one goes straight back on.
# - The AI, every 4 weeks, keeps 20 weeks of running costs (+₽60,000 with
#   fewer than 6 mons) and spends at most half the rest: its best mons
#   first, an item each by pickItemFor (Eviolite if it can evolve, Black
#   Sludge for poison types, Leftovers for bulk, Choice Scarf for speed,
#   then the attack items and berries). Ours also keeps the money a club
#   saves for a sold-out stadium (FM::Invest).
# - Evolution items (EVO) are sold too: the player's mon uses one to take
#   that branch (useEvolve); an AI pays for it when it evolves (evolve).
# Not ported: form items, Mega stones and other gimmicks, TM tickets, mints
# and ability capsules (the original's are Showdown sets).
# Our formula matches have no battle engine: a held item counts x1.03 in
# the team rating there (draft).
#===============================================================================
module FM
  module Items
    HELD = {
      LEFTOVERS: 30_000, LIFEORB: 35_000, CHOICEBAND: 35_000, CHOICESPECS: 35_000, CHOICESCARF: 35_000,
      ASSAULTVEST: 30_000, EVIOLITE: 30_000, EXPERTBELT: 25_000, ROCKYHELMET: 25_000, HEAVYDUTYBOOTS: 20_000,
      BLACKSLUDGE: 25_000, FOCUSSASH: 20_000, WEAKNESSPOLICY: 20_000, SITRUSBERRY: 3000, LUMBERRY: 3000,
      LIGHTCLAY: 20_000, FLAMEORB: 15_000, TOXICORB: 15_000, POWERHERB: 15_000, WHITEHERB: 15_000,
      MENTALHERB: 15_000, AIRBALLOON: 15_000, BOOSTERENERGY: 25_000, LOADEDDICE: 20_000, SCOPELENS: 15_000,
      WIDELENS: 15_000, THROATSPRAY: 15_000, EJECTBUTTON: 15_000, EJECTPACK: 15_000, REDCARD: 15_000,
      DAMPROCK: 10_000, HEATROCK: 10_000, SMOOTHROCK: 10_000, ICYROCK: 10_000, TERRAINEXTENDER: 15_000,
      PROTECTIVEPADS: 15_000, SHEDSHELL: 10_000, COVERTCLOAK: 15_000, CLEARAMULET: 15_000
    }.freeze
    CONSUMABLE = %i[FOCUSSASH WEAKNESSPOLICY SITRUSBERRY LUMBERRY POWERHERB WHITEHERB MENTALHERB AIRBALLOON
                    BOOSTERENERGY THROATSPRAY EJECTBUTTON EJECTPACK REDCARD].freeze
    # Evolution items (LEARN.evoItems): itemPrice's stones 8,000, Linking
    # Cord 12,000, Soothe Bell 10,000, the rest 15,000.
    EVO = %i[THUNDERSTONE MOONSTONE FIRESTONE SOOTHEBELL LEAFSTONE SUNSTONE WATERSTONE KINGSROCK LINKINGCORD
             METALCOAT PROTECTOR DRAGONSCALE ELECTIRIZER MAGMARIZER ICESTONE UPGRADE SHINYSTONE DUSKSTONE RAZORFANG
             RAZORCLAW DUBIOUSDISC DAWNSTONE PRISMSCALE REAPERCLOTH DEEPSEATOOTH DEEPSEASCALE OVALSTONE SACHET
             WHIPPEDDREAM TARTAPPLE SWEETAPPLE SYRUPYAPPLE CRACKEDPOT METALALLOY AUSPICIOUSARMOR MALICIOUSARMOR
             UNREMARKABLETEACUP].freeze
    SHOP_MUL = 0.8
    AI_EVERY = 4
    AI_RESERVE_WEEKS = 20
    AI_SHORT_SQUAD = 60_000
    RATING_MUL = 1.03

    module_function

    def held?(id) = HELD.key?(id)
    def evo?(id) = EVO.include?(id)
    def shop_mul(club) = club.sponsor && club.sponsor[:kind] == "SHOP" ? SHOP_MUL : 1.0
    def base_price(id)
      return HELD[id] if HELD.key?(id)
      return 12_000 if id == :LINKINGCORD
      return 10_000 if id == :SOOTHEBELL
      id.to_s.end_with?("STONE") && id != :OVALSTONE ? 8000 : 15_000
    end
    def price(club, id) = (base_price(id) * shop_mul(club) / 10.0).round * 10

    def bag(club) = club.bag ||= {}
    def count(club, id) = bag(club)[id].to_i

    def add(club, id, n)
      b = bag(club)
      b[id] = b[id].to_i + n
      b.delete(id) if b[id] <= 0
    end

    # buyItem -> the cost, or nil if it can't
    def buy(club, id, n = 1, date:)
      return unless held?(id) || evo?(id)
      cost = price(club, id) * n
      return if club.wallet.balance < cost
      club.wallet.record(-cost, category: :shop, date: date)
      add(club, id, n)
      cost
    end

    def team_holds?(club, id, except = nil) = club.squad.any? { |m| !m.equal?(except) && m.item == id }

    # equipItem (id nil = take it off) -> :ok or why not
    def equip(club, mon, id)
      return :not_mine unless club.squad.any? { |m| m.equal?(mon) }
      if id
        return :unknown unless held?(id)
        return :none if count(club, id) < 1
        return :taken if team_holds?(club, id, mon)
      end
      add(club, mon.item, 1) if mon.item
      mon.item = nil
      if id
        add(club, id, -1)
        mon.item = id
      end
      :ok
    end

    # evoOptions: [[to, level, item], ...]
    def evo_options(pool, mon) = (pool.dig(mon.species, :evo) || [])

    # useEvolve: the player's choice k; an item evolution takes the item
    # from the bag (no level needed), else the level. -> :ok or why not
    def use_evolve(club, mon, k, pool)
      to, lv, item = evo_options(pool, mon)[k]
      return :none unless to
      if item
        return :no_item if count(club, item) < 1
        add(club, item, -1)
      elsif mon.level < lv
        return :level
      end
      Growth.become(mon, pool, to)
      club.refresh_rating
      :ok
    end

    # returnItem: the player's bag gets it back; an AI's item goes with it.
    def give_back(club, mon)
      add(club, mon.item, 1) if mon.item && club.bag
      mon.item = nil
    end

    # consumeItems after a real battle: `used` held a consumable that's gone.
    def consumed(club, used)
      used.each do |m|
        id = m.item
        next unless id && CONSUMABLE.include?(id)
        m.item = nil
        equip(club, m, id) if club.bag && count(club, id).positive?
      end
    end

    # pickItemFor
    def pick_for(pool, mon, used)
      s = pool[mon.species] || {}
      b = s[:base] || []
      prefs = []
      prefs << :EVIOLITE unless (s[:evo] || []).empty?
      prefs << :BLACKSLUDGE if (s[:types] || []).map(&:to_s).include?("POISON")
      if b.size == 6
        prefs << :LEFTOVERS if b[0] + b[2] + b[4] >= 300
        prefs << :CHOICESCARF if b[5] >= 100
        prefs << (b[1] >= b[3] ? :CHOICEBAND : :CHOICESPECS)
      end
      prefs.concat(%i[LIFEORB ASSAULTVEST EXPERTBELT SITRUSBERRY LUMBERRY])
      prefs.find { |x| !used.include?(x) }
    end

    # aiMetaTeam's item part -> what it spent
    def ai_shop(club, pool, date:)
      reserve = club.weekly_cost * AI_RESERVE_WEEKS + (club.squad.size < 6 ? AI_SHORT_SQUAD : 0)
      # (Ours: a club saving for a sold-out stadium keeps that too, as FM::Invest does.)
      reserve += Build.stadium_cost(club.stadium) * Invest::MARGIN if Invest.stadium_wanted?(club)
      budget = [0, club.wallet.balance - reserve].max * 0.5
      used = club.squad.filter_map(&:item)
      top = club.lineup
      party = club.entry.sort_by { |m| [top.any? { |t| t.equal?(m) } ? 0 : 1, -m.rating] }
      spent = 0
      party.each do |m|
        next if m.item
        id = pick_for(pool, m, used) or next
        cost = (HELD.fetch(id) * shop_mul(club)).round
        next if cost > budget
        budget -= cost
        spent += cost
        club.wallet.record(-cost, category: :shop, date: date)
        m.item = id
        used << id
      end
      spent
    end
  end
end
