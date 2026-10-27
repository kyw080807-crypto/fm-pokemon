#===============================================================================
# FM::Rating and FM::Economy — numbers carried over from Poké Manager
# (index.html: makeMon/pretrain, initFame, demand/gate, STD, LEAGUE_PRIZE,
# REBUILD_AID, WIN_BONUS/UPSET_PER), plus the design's away-section cap.
# Pure Ruby.
#===============================================================================
module FM
  # Team strength for FM::MatchSim on a base-stat-total scale. Battles are at
  # Lv50, where a stat is about base + IV/2 + EV/8, so a mon rates
  # BST + (sum of IVs)/2 + (sum of EVs)/8. IVs: midpoint of the star range
  # (IVLO/IVHI). EVs: pre-training by level, 510 * clamp((level-8)/62).
  module Rating
    IV_MID = [10.0, 15.5, 21.0, 25.5, 28.5].freeze   # ★1..★5
    EV_MAX = 510

    module_function

    def mon(m)
      ev = EV_MAX * ((m[:level] - 8) / 62.0).clamp(0.0, 1.0)
      m[:bst] + IV_MID.fetch(m[:stars] - 1) * 6 / 2.0 + ev / 8.0
    end

    # Mean of the best three (each side picks 3 of its 6); missing slots are 0.
    def team(mons)
      best = mons.map { |m| mon(m) }.max(3)
      best.sum / 3.0
    end
  end

  module Economy
    FAME_MIN = 15
    FAME_MAX = 300
    FUNDS_PER_FAME = 3000
    # Seats by stadium level; 0 is the city-owned rental (design 09).
    CAPACITY = [1000, 2000, 4000, 7000, 12_000, 20_000, 30_000].freeze
    AWAY_SECTION = 0.3          # design 05: away fans fill at most 30% of seats
    WIN_BONUS = 1500
    UPSET_PER_RANK = 600
    DRAW_BONUS = 500

    module_function

    def initial_fame(level:, role:, canon:)
      bonus = case role[0]
              when "C" then 20
              when "E" then 12
              when "G" then 8
              else canon ? 10 : 0
              end
      (level * 1.6 + bonus).clamp(FAME_MIN, 95).round
    end

    def start_funds(fame)
      fame * FUNDS_PER_FAME
    end

    # Fame above 100 counts 40% toward crowds (famE).
    def fame_eff(fame)
      fame <= 100 ? fame : 100 + (fame - 100) * 0.4
    end

    def add_fame(fame, delta)
      (fame + delta).clamp(FAME_MIN, FAME_MAX)
    end

    def capacity(stadium)
      CAPACITY.fetch(stadium)
    end

    # Reference ticket price; AI clubs charge exactly this.
    def price(fame)
      [1, (3 + fame_eff(fame) * 0.03).round].max
    end

    # Expected crowd before the random spread. wins = wins in the last 5.
    # link = design 05 travel factor L (1.0 = same region at transport Lv3).
    def demand(home_fame:, away_fame:, wins:, capacity:, link: 1.0)
      away = [fame_eff(away_fame) * 25 * link, capacity * AWAY_SECTION].min
      (500 + fame_eff(home_fame) * 45 + away) * (0.8 + 0.1 * wins)
    end

    def gate(home_fame:, away_fame:, wins:, stadium:, rng:, link: 1.0)
      cap = capacity(stadium)
      d = demand(home_fame: home_fame, away_fame: away_fame, wins: wins, capacity: cap, link: link)
      att = [cap, (d * (0.92 + rng.rand * 0.16)).round].min
      p = price(home_fame)
      { attendance: att, price: p, revenue: att * p }
    end

    # --- weekly (econWeek) -------------------------------------------------
    STADIUM_KEEP = [800, 800, 1500, 2500, 4000, 6500, 10_000].freeze
    DEBT_RATE = 0.005

    # Lv50 overall (ovrOf: stat total / 6) from a FM::Rating.mon value:
    # each stat is ~base + IV/2 + EV/8 + 5, and HP adds another 55.
    def ovr(mon_rating)
      ((mon_rating + 6 * 5 + 55) / 6.0).round
    end

    # Food is effectively a wage: grows with the square of OVR, scaled by the
    # owner's fame (fameMul). Body-size and last-season multipliers are 1 here.
    def food(ovr:, fame:)
      o = ovr * 1.5
      f = (100 + o * o / 90 + [0, o - 200].max**2 / 8.0) * (0.55 + 0.009 * fame).clamp(0.6, 1.45)
      (f / 10).round * 10
    end

    # Club buildings use design levels 1-5 (old level = 2 x new); every
    # building pays upkeep (design 01), not just training and scouting.
    def facility_keep(level)
      (60 * (2 * level)**1.4).round
    end

    def stadium_keep(stadium)
      STADIUM_KEEP.fetch(stadium)
    end

    def merch(fame)
      (fame_eff(fame)**1.6 * 0.6).round
    end

    def debt_interest(balance)
      return 0 if balance >= 0
      [10, (-balance * DEBT_RATE / 10.0).round * 10].max
    end

    def league_prize(pos)
      ((150_000 - (pos - 1) * 3158) / 1000.0).round * 1000
    end

    def rebuild_aid(pos)
      pos >= 15 ? (pos - 14) * 25_000 : 0
    end
  end
end
