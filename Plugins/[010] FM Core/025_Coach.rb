#===============================================================================
# FM::Coach — retired mons as coaches (Poké Manager: coachesOf, coachSlots,
# coachSpec, coachQ, coachFx, coachFood, aiCoaches). Pure Ruby.
# - A club's retired mons can coach; slots: 1 + original training level / 4,
#   +1 at level 10.
# - Quality 1-3: 1 + career KOs / 150 + titles x 0.3 + awards x 0.2 +
#   (stars - 3) x 0.2 (titles: league or PWT won with 8+ games that season;
#   awards: the league's KO king).
# - Each coach: level progress x (1 + 0.025q), x (1 + 0.04q) more for mons
#   sharing a type with it, at most x1.25 in all; its best base stat
#   trains x (1 + 0.2q), at most x1.6 per stat.
# - A coach eats what it ate when it retired (coachFood), each week.
# - The AI fills its slots with its best coaches at season end (aiCoaches)
#   and lets them go when money runs short (aiBudget, urgent scouting).
# Differs from the original where our data does: EVs here are one total,
# so a coach's stat boost counts as the mean over the six stats; and
# formula matches don't say who scored, so KOs go to a random mon of the
# side that played (World#after_match).
#===============================================================================
module FM
  module Coach
    LV_PER_Q = 0.025
    TYPE_LV_PER_Q = 0.04
    LV_CAP = 1.25
    EV_PER_Q = 0.2
    EV_CAP = 1.6
    TITLE_GAMES = 8   # a title counts for mons with 8+ games that season

    module_function

    def slots(club)
      t = Growth.original_level(club.facilities.fetch(:TRAINING, 0))
      1 + t / 4 + (t >= 10 ? 1 : 0)
    end

    def quality(m)
      q = 1 + m.ko / 150.0 + m.titles.size * 0.3 + m.awards.size * 0.2 + (m.stars - 3) * 0.2
      (q.clamp(1.0, 3.0) * 10).round / 10.0
    end

    def grade(q) = q >= 2.5 ? "S" : q >= 2 ? "A" : q >= 1.5 ? "B" : "C"

    # coachSpec: index of its best base stat (HP, Atk, Def, SpA, SpD, Spe).
    def spec(pool, m)
      b = pool.dig(m.species, :base)
      return 0 if b.nil? || b.empty?
      b.each_index.max_by { |i| [b[i], -i] }
    end

    # A club's coaching staff this week: [[quality, types], ...], and the
    # parts of coachFx that don't depend on the mon.
    def staff(club, pool)
      lv = 1.0
      ev = Hash.new(1.0)
      list = club.coaches.map do |c|
        q = quality(c)
        s = spec(pool, c)
        ev[s] = [ev[s] + EV_PER_Q * q, EV_CAP].min
        lv *= 1 + LV_PER_Q * q
        [q, pool.dig(c.species, :types) || []]
      end
      { list: list, lv: lv, ev: (6 + ev.values.sum { |v| v - 1 }) / 6.0 }
    end

    # coachFx -> { lv:, ev: } multipliers for `mon`'s week.
    def fx(club, mon, pool, staff = staff(club, pool))
      return { lv: 1.0, ev: 1.0 } if staff[:list].empty?
      mt = pool.dig(mon.species, :types) || []
      lv = staff[:list].reduce(staff[:lv]) { |a, (q, ct)| (ct & mt).any? ? a * (1 + TYPE_LV_PER_Q * q) : a }
      { lv: [lv, LV_CAP].min, ev: staff[:ev] }
    end

    # (Older saves: fixed the first time it is needed, as coachFood does.)
    def weekly_food(club)
      club.coaches.sum { |m| m.food_fixed ||= Economy.food(ovr: Economy.ovr(m.rating), fame: club.fame) }
    end

    # aiCoaches
    # (Mons at the daycare and nurses don't coach.)
    def ai_pick(club)
      n = slots(club)
      club.retired.each { |m| m.coach = false }
      club.retired.reject { |m| m.nurse || Daycare.paired?(club, m) }.sort_by { |m| -quality(m) }.first(n).each { |m| m.coach = true }
    end

    def dismiss(club, keep: 0)
      club.coaches.drop(keep).each { |m| m.coach = false }
    end
  end
end
