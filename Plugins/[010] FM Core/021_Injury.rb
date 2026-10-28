#===============================================================================
# FM::Injury — injuries and the medical center, carried over from Poké
# Manager (부상 2.0: INJ_TYPES, injRisk, pickInjury, injure, injHeal, injWeek,
# injRecovered, medRiskCut). Pure Ruby; names and texts are in FM UI, keyed
# by the type symbol.
#
# - A mon knocked out in a match is hurt with chance RATE (x2 under
#   condition 50, more with hidden fatigue, x1.6 in rehab, x its hidden
#   proneness 0.7-1.5), less with a better medical center.
# - Training weeks carry a small risk too (TRAIN_RATE).
# - Severity 1 (가벼운 부상): can still play, one stat stage down (injDbStat).
#   Severity 2-3: out of the entry and resting until healed.
# - Healing is a week per week; the medical center gives an extra week
#   with chance 3% per original level. After a 2-3 injury: 2 weeks of
#   rehab (condition at most 70), 1 week with a Lv5 center (design 01:
#   "Lv5 장기 결장 위험 감소"; original Lv10 perk).
# Not carried over: type-specific injuries (Core species data has no
# types), playing through an injury (무리 출전), news.
#===============================================================================
module FM
  module Injury
    RATE = 0.05
    TRAIN_RATE = 0.004
    REHAB_WEEKS = 2
    REHAB_COND = 70

    # k => [severity, weeks range, caused by fatigue, stat a light one drops]
    TYPES = {
      bruise:     [1, 1..2, false, :def],
      cramp:      [1, 1..1, true, :main],
      sprain:     [2, 2..3, false, :spe],
      muscle:     [2, 3..4, true, :main],
      concussion: [2, 2..3, false, :spe],
      burnout:    [2, 2..4, true, :main],
      ligament:   [3, 5..7, false, :spe],
      fracture:   [3, 6..8, false, :def]
    }.freeze

    module_function

    def stat(kind) = TYPES.fetch(kind)[3]

    def med_original(med_level) = Growth.original_level(med_level.to_i)   # none = original level 1

    # medRiskCut: -2% risk per original medical level above 1, at most 18%.
    def risk_cut(med_level) = [0.18, 0.02 * (med_original(med_level) - 1)].min

    # injRisk: chance a mon knocked out in a match gets hurt.
    def match_risk(mon, med_level)
      r = RATE * (mon.cond < 50 ? 2 : 1) * (1 + mon.fat / 150.0) * mon.prone / 1.1
      r *= 1.6 if mon.rehab.to_i.positive?
      r * (1 - risk_cut(med_level))
    end

    def train_risk(mon)
      TRAIN_RATE * (1 + mon.fat / 50.0) * (mon.cond < 40 ? 2 : 1) * mon.prone * (mon.rehab.to_i.positive? ? 2 : 1)
    end

    # pickInjury weights, without the type-specific ones.
    def pick(mon, cause, rng)
      weights = TYPES.map do |k, (sev, _, fat, _)|
        v = 1.0
        v *= mon.fat >= 40 ? 2.5 : 0.5 if fat
        v *= 0.3 if cause == :train && sev == 3
        v *= (mon.cond < 40 || mon.fat >= 60) ? 1 : 0.3 if sev == 3
        v *= 0.8 if sev == 2
        [k, v]
      end
      x = rng.rand * weights.sum(&:last)
      weights.each { |k, v| return k if (x -= v) <= 0 }
      weights.last.first
    end

    def injure(mon, cause, rng, kind = nil)
      kind ||= pick(mon, cause, rng)
      sev, weeks, = TYPES.fetch(kind)
      w = rng.rand(weeks)
      mon.inj = w
      mon.injd = { k: kind, sev: sev, w0: w, cause: cause }
      mon.rehab = nil
      mon.resting = true if sev >= 2
      { injury: kind, sev: sev, weeks: w, cause: cause }
    end

    # After a match: `fainted` of the mons that played are hurt with
    # match_risk. Returns the injuries as [mon, info].
    def after_match(fainted, med_level, rng)
      fainted.filter_map do |m|
        next if m.hurt?
        [m, injure(m, :battle, rng)] if rng.rand < match_risk(m, med_level)
      end
    end

    # Start of the week, before Growth.condition_week: rehab counts down,
    # injuries heal (injHeal) and may end (injRecovered). -> :recovered/nil
    def heal_week(mon, med_level, rng)
      mon.rehab = mon.rehab > 1 ? mon.rehab - 1 : nil if mon.rehab.to_i.positive?
      return unless mon.hurt?
      orig = med_original(med_level)
      mon.inj -= 1 + (rng.rand < orig * 0.03 ? 1 : 0)
      return if mon.inj.positive?
      sev = mon.injd && mon.injd[:sev]
      mon.inj = nil
      mon.injd = nil
      if sev && sev >= 2
        mon.rehab = orig >= 10 ? 1 : REHAB_WEEKS
        mon.cond = [mon.cond, REHAB_COND].min
      end
      :recovered
    end

    # After Growth.condition_week: a training week may hurt (injWeek).
    def train_week(mon, rng)
      return if mon.hurt? || mon.resting
      injure(mon, :train, rng) if rng.rand < train_risk(mon)
    end
  end
end
