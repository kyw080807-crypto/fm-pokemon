#===============================================================================
# FM::Recruit — an AI club's weekly scouting and signing (Poké Manager
# aiScoutWeek). Pure Ruby. Clubs short of players scout more often; a scout
# trip costs FM::Scout::FEE and brings 3-5 candidates (more with better
# scouting), 75% from the club's own region. A short squad signs the best
# affordable one; a full squad only swaps out its weakest non-canon mon for a
# candidate worth 5% more. Squad size comes from the clubhouse (design 01).
#===============================================================================
module FM
  module Recruit
    module_function

    # aiEmergency: below 3 mons a club gets free youth players, at least ★3
    # and 60% of the region's average level.
    def emergency(club, pool:, avg_level:, rng:)
      added = []
      while club.squad.size < 3
        c = Scout.candidate(pool, region: club.region, scout_level: club.facilities.fetch(:SCOUTING, 0),
                                  avg_level: avg_level, rng: rng)
        m = c[:mon]
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
        out = (club.squad - top).min_by do |m|
          Scout.value(m, pool) / Economy.food(ovr: Economy.ovr(m.rating), fame: club.fame)
        end
        break unless out
        club.squad.delete(out)
        club.retired << out
        released << out.species
      end
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
      Array.new(n) do
        region = yield
        c = Scout.candidate(pool, region: region, scout_level: club.facilities.fetch(:SCOUTING, 0),
                                  avg_level: avg_level, rng: rng, bonus: bonus)
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
      ok = cands.select { |c| club.wallet.balance - c[:cost] >= floor }
      ok.sort_by! { |c| urgent ? [c[:cost], -Scout.value(c[:mon], pool)] : [-Scout.value(c[:mon], pool)] }
      pick = ok.first or return

      out = nil
      unless short || size < cap
        weakest = club.squad.reject(&:canon).min_by { |m| Scout.value(m, pool) }
        return if weakest.nil? || Scout.value(pick[:mon], pool) <= Scout.value(weakest, pool) * 1.05
        club.squad.delete(weakest)
        club.retired << weakest
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
      candidates(club, n, pool: pool, avg_level: avg_level, rng: rng, year: date[0]) { region }
    end

    # Signs a candidate; with a full squad, `release` (a Mon in the squad)
    # makes room.
    class LimitReached < StandardError; end

    def sign(club, cand, date:, release: nil)
      raise LimitReached, "signing limit for #{date[0]}" if signs_left(club, date[0]) <= 0
      raise Finance::InsufficientFunds, "need #{cand[:cost]}" if club.wallet.balance < cand[:cost]
      if club.squad.size >= Build.squad_size(club.clubhouse)
        raise ArgumentError, "squad full: choose a mon to release" unless release && club.squad.include?(release)
        club.squad.delete(release)
        club.retired << release
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
