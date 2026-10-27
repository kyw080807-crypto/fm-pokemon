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

    def weekly(club, pool:, regions:, avg_level:, window:, date:, rng:)
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
      cands = Array.new(n) do
        region = rng.rand < 0.75 ? club.region : regions[rng.rand(regions.size)]
        Scout.candidate(pool, region: region, scout_level: club.facilities.fetch(:SCOUTING, 0),
                              avg_level: avg_level, rng: rng)
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
      club.squad << pick[:mon]
      { kind: :signed, club: club.id, species: pick[:mon].species, cost: pick[:cost], released: out, date: date }
    end
  end
end
