#===============================================================================
# FM::Sponsor — season-long sponsor contracts (design 04: 계약형, pick among
# offers with conditions), with Poké Manager's sponsors and numbers
# (SPONSORS, sponDeal, sponOffers, aiPickSponsor, sponSeasonEnd, sponWeek).
# Pure Ruby. Sponsor table rows come from PBS/fm_sponsors.txt.
#
# Kinds: STABLE (big base), PERF (smaller base + bonus for a top-4 finish),
# STRICT (bonus for top 4; finishing lower bans the sponsor for 2 seasons),
# FAME (+4 fame at season end), BUZZ, SHOP, RISKY (big base, may go bust).
# Design 01 ties sponsor grade to the clubhouse: big companies need clubhouse
# 3 (스폰서 2등급). Not yet: BUZZ news bonus, shady sponsors (the SHOP discount is FM::Items.shop_mul).
#===============================================================================
module FM
  module Sponsor
    TIER_MUL = { "BIG" => 1.35, "LOCAL" => 1.0, "SHOP" => 0.7 }.freeze
    BIG_CLUBHOUSE = 3
    BONUS_POSITION = 4
    STRICT_BAN_SEASONS = 2
    FAME_BONUS = 4
    BUST_CHANCE = 0.006   # RISKY, per week (대보라홀딩스 부도)

    module_function

    def r(x) = (x / 1000.0).round * 1000

    def deal(row, fame:)
      f = [10, Economy.fame_eff(fame)].max
      m = TIER_MUL.fetch(row[:tier])
      base, bonus = case row[:kind]
                    when "STABLE" then [[30_000, f * 1500].max * m, 0]
                    when "PERF"   then [[18_000, f * 900].max * m, [50_000, f * 1500].max * m]
                    when "STRICT" then [[25_000, f * 1200].max * m, [80_000, f * 2400].max * m]
                    when "FAME"   then [[20_000, f * 800].max * m, 0]
                    when "BUZZ"   then [[20_000, f * 900].max * m, 0]
                    when "SHOP"   then [[20_000, f * 700].max, 0]
                    when "RISKY"  then [[45_000, f * 2200].max * m, 0]
                    end
      row.merge(base: r(base), bonus: r(bonus))
    end

    def eligible(table, region:, fame:, clubhouse:, bans:, year:)
      table.select do |row|
        next false if bans.fetch(row[:id], 0) >= year || fame < row[:min_fame]
        next false if row[:tier] == "BIG" && clubhouse < BIG_CLUBHOUSE
        row[:region] == region || (row[:tier] == "BIG" && fame >= row[:min_fame] + 10)
      end
    end

    # Up to 3 offers, one per kind: a big company, locals, a shop, then any.
    def offers(table, region:, fame:, clubhouse:, bans:, year:, rng:)
      pool = eligible(table, region: region, fame: fame, clubhouse: clubhouse, bans: bans, year: year)
      out = []
      add = lambda do |rows|
        row = rows.empty? ? nil : rows[rng.rand(rows.size)]
        out << deal(row, fame: fame) if row && out.none? { |o| o[:id] == row[:id] || o[:kind] == row[:kind] }
      end
      add.(pool.select { |x| x[:tier] == "BIG" })
      12.times { break if out.size >= 3; add.(pool.select { |x| x[:tier] == "LOCAL" }) }
      add.(pool.select { |x| x[:tier] == "SHOP" }) if out.size < 3
      12.times { break if out.size >= 3; add.(pool) }
      out
    end

    def ai_pick(offers)
      offers.max_by { |o| o[:base] + o[:bonus] * 0.4 }
    end
  end
end
