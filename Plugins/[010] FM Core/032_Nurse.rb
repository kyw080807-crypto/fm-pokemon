#===============================================================================
# FM::Nurse — nurse Pokémon at the medical center (Poké Manager: NURSE_SP,
# canNurse, nurseQ, nurseGrade, nurseSlots, nursesOf, nurseFood, nursePow,
# nurseWeek, aiNurses, toggleNurse and its injHeal / injRecovered / injRisk
# wrappers). Pure Ruby.
# - The Happiny, Chansey, Audino and Igglybuff lines can nurse: in the
#   squad (still battling, 70% effect, no extra food) or retired (full
#   effect, eating what it ate when it retired, as a coach does).
# - Quality: the species' base (Blissey 3 ... Igglybuff 1) + 0.2 at 100
#   career KOs + (stars - 3) x 0.1, at most 3.5. Slots: 1, +1 at medical
#   Lv4, +1 at Lv8. Nurse power = the sum of qualities (x0.7 for active
#   ones), at most 5.
# - Power n: each healing week ends a week sooner with chance min(0.6,
#   0.12n) and the hurt mon's bond grows 0.5; at n >= 2.5 a 2+ week rehab
#   is cut to 1; a mon in rehab gets hurt 1 - min(0.25, 0.06n) as often.
# - Nurses beyond the slots (the center lost a level) step down from the
#   last. The AI fills its slots every 13 weeks with its best retired
#   nurses when it has 30 weeks of their food.
# - Nurses and the daycare's mons don't coach; nurses don't breed.
#===============================================================================
module FM
  module Nurse
    SPECIES = { "HAPPINY" => 1.5, "CHANSEY" => 2.5, "BLISSEY" => 3, "AUDINO" => 2.5,
                "IGGLYBUFF" => 1, "JIGGLYPUFF" => 1.3, "WIGGLYTUFF" => 2 }.freeze
    Q_MAX = 3.5
    POW_MAX = 5
    ACTIVE = 0.7
    AI_EVERY = 13          # weeks (S.week % 13 === 1)
    AI_FOOD_WEEKS = 30

    module_function

    # nurseId: the species without its form.
    def base(species) = species.to_s.sub(/_\d+\z/, "")
    def can?(mon) = !mon.nil? && SPECIES.key?(base(mon.species))

    def quality(mon)
      q = SPECIES.fetch(base(mon.species), 0) + (mon.ko >= 100 ? 0.2 : 0) + (mon.stars - 3) * 0.1
      ([q, Q_MAX].min * 10).round / 10.0
    end

    def grade(q) = q >= 3 ? "S" : q >= 2.4 ? "A" : q >= 1.6 ? "B" : "C"

    def slots(club)
      l = Injury.med_original(club.facilities[:MEDICAL])
      1 + (l >= 4 ? 1 : 0) + (l >= 8 ? 1 : 0)
    end

    def of(club) = (club.squad + club.retired).select(&:nurse)
    def retired?(club, mon) = club.retired.any? { |m| m.equal?(mon) }

    # nurseFood: only retired nurses eat (fixed when they retired).
    def food(club, mon)
      return 0 unless retired?(club, mon)
      mon.food_fixed ||= Economy.food(ovr: Economy.ovr(mon.rating), fame: club.fame)
    end

    def weekly_food(club) = of(club).sum { |m| food(club, m) }

    def pow(club)
      n = of(club).sum { |m| quality(m) * (retired?(club, m) ? 1 : ACTIVE) }
      [n, POW_MAX].min
    end

    # Retired mons free to take a nurse's job.
    def free?(club, mon) = can?(mon) && !mon.nurse && !mon.coach && !Daycare.paired?(club, mon)

    # nurseWeek -> the food paid
    def week(club, date:)
      ns = of(club)
      ns.drop(slots(club)).each { |m| m.nurse = false }
      pay = weekly_food(club)
      club.wallet.record(-pay, category: :nurse, date: date) if pay.positive?
      pay
    end

    # aiNurses (week of the year % 13 == 1)
    def ai_pick(club)
      free = slots(club) - of(club).size
      return if free <= 0
      club.retired.select { |m| free?(club, m) }.sort_by { |m| -quality(m) }.first(free).each do |m|
        m.food_fixed ||= Economy.food(ovr: Economy.ovr(m.rating), fame: club.fame)
        m.nurse = true if club.wallet.balance > m.food_fixed * AI_FOOD_WEEKS
      end
    end

    # toggleNurse -> :off, :on, or why not (:cannot, :busy, :full)
    def toggle(club, mon)
      return :cannot unless can?(mon) && (club.squad + club.retired).any? { |m| m.equal?(mon) }
      if mon.nurse
        mon.nurse = false
        return :off
      end
      return :busy if mon.coach || Daycare.paired?(club, mon)
      return :full if of(club).size >= slots(club)
      mon.nurse = true
      :on
    end

    # injHeal: an extra week of healing.
    def heal_bonus(n, rng) = n.positive? && rng.rand < [0.6, 0.12 * n].min ? 1 : 0
    # injRisk while in rehab.
    def rehab_risk_mul(n) = 1 - [0.25, 0.06 * n].min
    # injRecovered: a rehab cut to a week.
    def short_rehab?(n) = n >= 2.5
  end
end
