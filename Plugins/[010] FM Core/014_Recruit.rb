#===============================================================================
# FM::Recruit — an AI club's weekly scouting and signing (Poké Manager
# aiScoutWeek). Pure Ruby. Clubs short of players scout more often; a scout
# trip costs FM::Scout::FEE and brings 3-5 candidates (more with better
# scouting), 75% from the club's own region. A short squad signs the best
# affordable one; a full squad only swaps out its weakest non-canon mon for a
# candidate worth 5% more. Squad size comes from the clubhouse (design 01).
# Candidates are judged as the original does (aiCandOk / aiCandScore): never
# a second of one evolution family or a second 준전설; gym leaders and canon
# trainers want their type (x1.25, other types x0.6 for gyms, x0.95 for the
# rest), types the squad already has count x0.92, and seasons left count
# (remainF). Not carried over: finalVia (the original's usage-based battle
# viability, from data we don't have). 홈그로운 (HG_MIN): at least HG_MIN
# of a squad come from the club's own region, so outsiders fill at most
# squad size - HG_MIN places (player and AI; mons already there stay).
#===============================================================================
module FM
  module Recruit
    HG_MIN = 4

    module_function

    # (A mon hatched at the club's daycare counts as homegrown there.)
    def home?(club, mon, pool) = mon.hatched_by == club.id || Scout.home?(pool, mon.species, club.region)

    def foreign_cap(club) = [Build.squad_size(club.clubhouse) - HG_MIN, 0].max
    def foreign_count(club, pool, except: nil) = club.squad.count { |m| !m.equal?(except) && !home?(club, m, pool) }

    # hgBlock: signing `mon` would break the homegrown rule.
    def hg_block?(club, mon, pool, replacing: nil)
      !home?(club, mon, pool) && foreign_count(club, pool, except: replacing) >= foreign_cap(club)
    end

    # famDup
    def fam_dup?(club, species, pool)
      f = Scout.family(pool, species)
      club.squad.any? { |m| Scout.family(pool, m.species) == f }
    end

    def second_sub_legend?(club, species, pool)
      pool.dig(species, :tier) == 1 && club.squad.any? { |m| pool.dig(m.species, :tier) == 1 }
    end

    # aiCandOk
    def cand_ok?(club, cand, pool)
      !fam_dup?(club, cand[:mon].species, pool) && !second_sub_legend?(club, cand[:mon].species, pool) &&
        !Specialty.block?(club, cand[:mon], pool)
    end

    # aiCandScore (without finalVia).
    def cand_score(club, cand, pool)
      m = cand[:mon]
      types = pool.dig(m.species, :types) || []
      v = (pool.dig(m.species, :fb) || m.bst) * (0.75 + 0.1 * m.stars)
      if (ty = club_type(club))
        v *= types.include?(ty) ? 1.25 : (club.role.start_with?("G") ? 0.6 : 0.95)
      end
      have = club.squad.flat_map { |x| pool.dig(x.species, :types) || [] }
      v *= 0.92 if !types.empty? && types.all? { |t| have.include?(t) }
      if (sig = Specialty.of(club))
        v *= Specialty.mon?(pool, m.species, sig) ? Specialty::SCORE_SIG : Specialty::SCORE_OTHER
      end
      v * Scout.remain_f(m.age)
    end

    # The type a club builds around: its specialty (sigSync sets T.type to
    # it), else a gym leader's or canon trainer's PBS Type.
    def club_type(club)
      Specialty.of(club) || ((club.canon || club.role.start_with?("G")) ? club.type : nil)
    end

    # aiEmergency / emergencyCallup: below 3 mons a club gets free youth
    # players (youthMon), at least ★3 and 60% of the region's average level.
    def emergency(club, pool:, avg_level:, rng:)
      added = []
      tries = 0
      sig = Specialty.of(club)
      while club.squad.size < 3 && (tries += 1) <= 20
        type = sig && rng.rand < Specialty::SCOUT_SHARE ? sig : nil
        m = Scout.youth(pool, region: club.region, scout_level: club.facilities.fetch(:SCOUTING, 0), rng: rng, type: type)
        next if fam_dup?(club, m.species, pool)
        m.stars = [m.stars, 3].max
        m.level = [m.level, (avg_level * 0.6).round].max
        Growth.evolve(m, pool)
        club.squad << m
        added << m.species
      end
      added
    end

    # aiBudget: short of 20 weeks' running costs, release (up to 6 at a time)
    # the mon giving least value per unit of food, never the best three.
    def budget(club, pool:)
      released = []
      6.times do
        break if club.squad.size <= 4 || club.wallet.balance >= club.weekly_cost * Invest::RESERVE_WEEKS
        top = club.squad.max_by(3, &:rating)
        out = (club.squad - top).reject { |m| Scout.legend?(pool, m.species) }.min_by do |m|
          Scout.mon_value(m, pool) / Economy.food(ovr: Economy.ovr(m.rating), fame: club.fame)
        end
        break unless out
        Items.give_back(club, out)
        club.squad.delete(out)   # aiBudget: let go, not retired
        released << out.species
      end
      Coach.dismiss(club, keep: 1) if club.wallet.balance.negative?   # aiBudget
      released
    end

    # --- by last season's league position (Poké Manager, player and AI) ---
    # signLimit: signings a season, top 4 -> 2, 5-10 -> 3, 11 or lower -> 4,
    # no position yet -> 3 (free youth call-ups don't count).
    def prev_pos(club, year) = club.history.dig(year - 1, :pos)

    # (FM::Credit: one fewer the season after a bailout.)
    def sign_limit(club, year)
      p = prev_pos(club, year)
      n = p.nil? ? 3 : p <= 4 ? 2 : p <= 10 ? 3 : 4
      [n - Credit.sign_penalty(club, year), 1].max
    end

    def signs_left(club, year) = sign_limit(club, year) - club.signs_used(year)

    # scoutBonus: 11th or lower scouts at +2 quality.
    def scout_bonus(club, year)
      p = prev_pos(club, year)
      p && p >= 11 ? 2 : 0
    end

    # recoveryMul: 15th or lower signs at 40% off, 11-14th 20% off, and a
    # club in the red at least 20% off. discCost rounds to ₽500, min ₽500.
    def recovery_mul(club, year)
      p = prev_pos(club, year)
      m = p && p >= 15 ? 0.6 : p && p >= 11 ? 0.8 : 1.0
      club.wallet.balance.negative? ? [m, 0.8].min : m
    end

    def disc_cost(cost, mul) = [(cost * mul / 500.0).round * 500, 500].max

    # Candidates for `club` as genCand + recoveryMul make them.
    def candidates(club, n, pool:, avg_level:, rng:, year:)
      bonus = scout_bonus(club, year)
      mul = recovery_mul(club, year)
      sig = Specialty.of(club)
      Array.new(n) do
        region = yield
        type = sig && rng.rand < Specialty::SCOUT_SHARE ? sig : nil
        c = Scout.candidate(pool, region: region, scout_level: club.facilities.fetch(:SCOUTING, 0),
                                  avg_level: avg_level, rng: rng, bonus: bonus, type: type)
        mul < 1 ? c.merge(full: c[:cost], cost: disc_cost(c[:cost], mul)) : c
      end
    end

    def weekly(club, pool:, regions:, avg_level:, window:, date:, rng:)
      return if signs_left(club, date[0]) <= 0 || Credit.austerity?(club)
      cap = Build.squad_size(club.clubhouse)
      size = club.squad.size
      soon = club.squad.count { |m| m.age >= m.life - 1 }
      want = [cap, 8 + soon].min
      short = size < want
      p = if size < 4 then 0.45
          elsif short then soon.positive? ? 0.3 : 0.2
          elsif window then 0.12
          else 0
          end
      return if p.zero? || rng.rand > p
      urgent = size < 4
      # Urgent: let the coaches go to find the money (aiScoutWeek).
      Coach.dismiss(club) if urgent && club.wallet.balance < club.weekly_cost * 6 + 20_000
      weekly = club.weekly_cost
      reserve = urgent ? weekly * 2 : weekly * 6 + 20_000
      return if club.wallet.balance - Scout::FEE < reserve
      club.wallet.record(-Scout::FEE, category: :scout, date: date)

      q = Growth.original_level(club.facilities.fetch(:SCOUTING, 0))
      n = 3 + (q >= 7 ? 1 : 0) + (q >= 10 ? 1 : 0)
      cands = candidates(club, n, pool: pool, avg_level: avg_level, rng: rng, year: date[0]) do
        rng.rand < 0.75 ? club.region : regions[rng.rand(regions.size)]
      end
      floor = urgent ? 0 : reserve * 0.6
      ok = cands.select { |c| cand_ok?(club, c, pool) && club.wallet.balance - c[:cost] >= floor }
      ok.sort_by! { |c| urgent ? [c[:cost], -cand_score(club, c, pool)] : [-cand_score(club, c, pool)] }
      pick = ok.first or return
      need_home = hg_block?(club, pick[:mon], pool)
      return if short && need_home

      out = nil
      unless short || size < cap
        av = ->(m) { Scout.mon_value(m, pool) * Scout.remain_f(m.age) }
        weakest = club.squad.reject do |m|
          m.canon || Scout.legend?(pool, m.species) || (need_home && home?(club, m, pool))
        end.min_by(&av)
        return if weakest.nil? || av.(pick[:mon]) <= av.(weakest) * 1.05
        club.squad.delete(weakest)
        club.retire(weakest)
        out = weakest.species
      end
      club.wallet.record(-pick[:cost], category: :sign, date: date, memo: pick[:mon].species)
      club.sign_use(date[0])
      club.squad << pick[:mon]
      { kind: :signed, club: club.id, species: pick[:mon].species, cost: pick[:cost], released: out, date: date }
    end

    # --- player actions ---------------------------------------------------
    # One scout trip for the player: pays the fee and returns the candidates
    # (nil if the fee can't be paid).
    def scout(club, pool:, region:, avg_level:, rng:, date:)
      return nil if club.wallet.balance < Scout::FEE
      club.wallet.record(-Scout::FEE, category: :scout, date: date)
      q = Growth.original_level(club.facilities.fetch(:SCOUTING, 0))
      n = 3 + (q >= 7 ? 1 : 0) + (q >= 10 ? 1 : 0)
      out = []
      n.times do
        c = nil
        7.times do
          c = candidates(club, 1, pool: pool, avg_level: avg_level, rng: rng, year: date[0]) { region }.first
          f = Scout.family(pool, c[:mon].species)
          break unless fam_dup?(club, c[:mon].species, pool) || out.any? { |o| Scout.family(pool, o[:mon].species) == f }
        end
        out << c
      end
      out
    end

    # Signs a candidate; with a full squad, `release` (a Mon in the squad)
    # makes room.
    class LimitReached < StandardError; end
    class Blocked < StandardError; end   # signBlock: homegrown rule, family, 준전설

    # Why the player can't sign `cand` (signBlock), or nil.
    # world: for the legend rules (FM::Legend).
    def sign_block(club, cand, pool, release: nil, world: nil)
      sp = cand[:mon].species
      return :legend if world && Legend.block?(world, club, sp)
      others = release ? club.squad - [release] : club.squad
      return :homegrown if hg_block?(club, cand[:mon], pool, replacing: release)
      return :specialty if Specialty.block?(club, cand[:mon], pool, replacing: release)
      return :family if others.any? { |m| Scout.family(pool, m.species) == Scout.family(pool, sp) }
      return :sub_legend if pool.dig(sp, :tier) == 1 && others.any? { |m| pool.dig(m.species, :tier) == 1 }
      nil
    end

    def sign(club, cand, date:, release: nil, pool: nil)
      raise LimitReached, "signing limit for #{date[0]}" if signs_left(club, date[0]) <= 0
      if pool && (why = sign_block(club, cand, pool, release: release))
        raise Blocked, why.to_s
      end
      raise Finance::InsufficientFunds, "need #{cand[:cost]}" if club.wallet.balance < cand[:cost]
      if club.squad.size >= Build.squad_size(club.clubhouse)
        raise ArgumentError, "squad full: choose a mon to release" unless release && club.squad.include?(release)
        club.squad.delete(release)
        club.retire(release)
      end
      club.wallet.record(-cand[:cost], category: :sign, date: date, memo: cand[:mon].species)
      club.sign_use(date[0])
      club.squad << cand[:mon]
      club.refresh_rating
      { kind: :signed, club: club.id, species: cand[:mon].species, cost: cand[:cost],
        released: release&.species, date: date }
    end
  end
end
