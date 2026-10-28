#===============================================================================
# FM::Morale — morale, bond and the locker-room talk (Poké Manager: MOR_T,
# BOND_*, TEMPER / NAT_TEMPER, MOOD, TALKS, TALK_E, talkScore, talkReact,
# talkCoachPick, talkApply, morPreMatch, morWinP, morBig, morAfterBattle,
# morWeek, bondInit). Pure Ruby.
# - Morale 0-100 in five tiers (x0.96-1.03 on stats); each week it moves
#   15% toward the team's mood (55 +- 2 per recent league W/L, 45-65).
#   After a match: +-0.5, 12 x (result - expected) (x1.4 in big games),
#   -1 if it fainted, +2 a KO; the entry's bench moves 4 x the surprise.
# - Bond 0-255 (start 70, more for time together and canon mons): +0.5 a
#   week (+0.5 in the entry), +1-1.5 a match (+0.5 a KO). Below 120 a
#   proud mon may disobey (in battle; FM Bridge).
# - Temperament comes from the nature. Before a match each side gets a
#   talk (the player's choice, else the coach / AI: the best 60%, second
#   28%, third 12%); each mon of the entry reacts with a mood for the week
#   (x0.97-1.04, morale and bond changes). The same talk again loses
#   force. Individual talks are not carried over yet.
# - In battle (FM Bridge): a proud mon (stronger than its team's average,
#   newly evolved, a proud species, a legend) with bond under 120 may
#   disobey (disobey_p, at most 30% an action): another move, a nap, or
#   nothing. High bond may survive a lethal hit with 1 HP once a battle,
#   or shake off a status at the end of a turn (bond_fx). The formula
#   counts disobedience as half its chance off the mon's strength (an
#   estimate: the original plays every match as a battle).
#===============================================================================
module FM
  module Morale
    BOND_MAX = 255
    BOND_START = 70
    BOND_OBEY = 120
    TIERS = [[85, :best, 1.03], [65, :good, 1.015], [40, :ok, 1.0], [20, :bad, 0.98], [0, :worst, 0.96]].freeze
    MOOD = { fire: [1.04, 8, 2], mot: [1.02, 4, 1], calm: [1.0, 0, 0], nerv: [0.97, -3, 0], comp: [0.98, -1, 0],
             off: [0.98, -4, -2] }.freeze   # mul, morale, bond

    # Essentials' nature order (FM::Battle uses the same list).
    NATURES = %i[HARDY LONELY BRAVE ADAMANT NAUGHTY BOLD DOCILE RELAXED IMPISH LAX TIMID HASTY SERIOUS JOLLY NAIVE
                 MODEST MILD QUIET BASHFUL RASH CALM GENTLE SASSY CAREFUL QUIRKY].freeze
    TEMPER = {
      fiery: %i[HARDY LONELY ADAMANT NAUGHTY BRAVE], easy: %i[BOLD DOCILE IMPISH LAX RELAXED],
      cool: %i[MODEST MILD SERIOUS RASH QUIET], sens: %i[CALM GENTLE CAREFUL BASHFUL SASSY],
      free: %i[TIMID HASTY JOLLY NAIVE QUIRKY]
    }.freeze

    TALKS = %i[win easy fire focus fun trust demand].freeze
    TALK_E = {
      win: { fiery: 1, easy: 0.4, cool: 0.4, sens: 0.6, free: 0.8 },
      easy: { fiery: -0.4, easy: 0.8, cool: 0.2, sens: 1, free: 0.6 },
      fire: { fiery: 1.6, easy: -0.2, cool: -0.6, sens: 0.2, free: 0.6 },
      focus: { fiery: -0.4, easy: 0.4, cool: 1.4, sens: 0.6, free: -0.6 },
      fun: { fiery: -0.2, easy: 1, cool: -0.2, sens: 0.4, free: 1.4 },
      trust: { fiery: 0.6, easy: 0.6, cool: 0.4, sens: 1.4, free: 0.6 },
      demand: { fiery: 1, easy: -0.8, cool: 0.2, sens: -1.6, free: -0.8 }
    }.freeze

    class << self
      # The Monday of the current week (World sets it): moods last a week.
      attr_accessor :week
      # hook.(club, opponent, ctx, mons) -> a talk from TALKS, or nil for
      # the coach; set by FM UI while the player advances time.
      attr_accessor :player_talk
      # The world's calendar, for weeks since an evolution.
      attr_accessor :calendar
    end

    PRIDE_SPECIES = {
      CHARMANDER: 1.3, CHARMELEON: 1.7, CHARIZARD: 1.7, GYARADOS: 1.3, DRAGONITE: 1.3, TYRANITAR: 1.3, SALAMENCE: 1.3,
      GARCHOMP: 1.3, METAGROSS: 1.2, HYDREIGON: 1.3, GOODRA: 1.2, KOMMOO: 1.2, DRAGAPULT: 1.2, BAXCALIBUR: 1.2,
      PRIMEAPE: 1.3, ANNIHILAPE: 1.3, LUCARIO: 1.2, ZOROARK: 1.2, MEWTWO: 1.4, GRENINJA: 1.2
    }.freeze
    LAZY_SPECIES = %i[SNORLAX MUNCHLAX SLAKING SLAKOTH SLOWPOKE SLOWBRO SLOWKING KOMALA SWAMPERT PSYDUCK DROWZEE
                      HYPNO].freeze
    FORMULA_DISOBEY = 0.5

    module_function

    def nature(mon) = NATURES[mon.nature_index % NATURES.size]
    TEMPER_OF = TEMPER.flat_map { |t, list| list.map { |n| [n, t] } }.to_h.freeze
    def temper(mon) = TEMPER_OF.fetch(nature(mon), :easy)

    def tier(mor) = TIERS.find { |th, _, _| mor >= th }
    def mor_mul(mon) = tier(mon.mor)[2]
    def mood_mul(mon, week) = (k = mon.mood(week)) ? MOOD[k][0] : 1.0

    def add_mor(mon, d) = mon.mor = (mon.mor + d).clamp(0, 100).round(1)
    def add_bond(mon, d) = mon.bond = (mon.bond + d).clamp(0, BOND_MAX).round(1)

    # bondInit: time together (5 seasons at most), canon mons, AI clubs.
    def bond_init(mon, year, ai:)
      years = [0, year - (mon.bond_year || year)].max
      [BOND_START + 28 * [years, 5].min + (mon.canon ? 40 : 0) + (ai ? 15 : 0), 230].min
    end

    # morWinP (AI's estimate from strength).
    def win_p(club, other)
      a = [club.rating, 1].max
      b = [other.rating, 1].max
      1 / (1 + Math.exp(-4.494 * Math.log(a / b.to_f)))
    end

    # talkScore -> { s:, np:, cp:, om: }
    def score(mon, tid, ctx, rep)
      tp = temper(mon)
      f = ctx[:f]
      mv = mon.mor
      s = TALK_E[tid][tp]
      np = cp = 0.0
      om = [0, -s].max
      add = lambda do |d, k = :o|
        s += d
        next unless d.negative?
        case k
        when :n then np -= d
        when :c then cp -= d
        else om -= d
        end
      end
      case tid
      when :win
        add.(-1.4 * -f * (tp == :sens ? 1.6 : 1), :n) if f < -0.12
        add.(-0.5, :c) if f > 0.2 && mv >= 65
      when :easy
        add.(-1.4 * f, :c) if f > 0.12
        add.(1.2 * -f) if f < -0.12
        add.(-0.3, :c) if ctx[:big]
      when :fire then add.(0.4) if ctx[:big]
      when :focus then add.(0.3) if ctx[:big] && %i[cool sens].include?(tp)
      when :fun
        add.(-0.4, :c) if ctx[:big] && tp != :free
        add.(0.3) if f < -0.12
      when :trust then add.((mon.bond - BOND_OBEY) / 200.0)
      when :demand
        add.(tp == :sens ? -0.8 : tp == :fiery ? 0 : -0.3, :n) if f < -0.12
        add.(0.3) if f > 0.15
        add.(-0.4, :n) if tp == :sens && ctx[:big]
      end
      s *= 0.7 if mv < 40 && s.positive?
      add.(-0.4, :c) if mv >= 85 && tid == :win
      add.(-0.4) if mv < 25 && tid == :demand
      s *= rep >= 3 ? 0.3 : 0.6 if rep >= 2 && s.positive?
      { s: s, np: np, cp: cp, om: om }
    end

    # talkReact
    def react(sc, noise)
      s = sc[:s] + noise
      return :fire if s >= 1.5
      return :mot if s >= 0.6
      return :calm if s > -0.6
      mx = [sc[:np], sc[:cp], sc[:om]].max
      sc[:np].positive? && mx == sc[:np] ? :nerv : sc[:cp].positive? && mx == sc[:cp] ? :comp : :off
    end

    # talkCoachPick
    def coach_pick(mons, ctx, rng)
      ranked = TALKS.sort_by { |t| -mons.sum { |m| score(m, t, ctx, 1)[:s] } }
      r = rng.rand
      r < 0.6 ? ranked[0] : r < 0.88 ? ranked[1] : ranked[2]
    end

    # talkApply -> { mon => mood }
    def apply(mons, tid, ctx, week, rng, rep: 1)
      mons.to_h do |m|
        k = react(score(m, tid, ctx, rep), (rng.rand - 0.5) * 0.7)
        m.set_mood(k, week)
        add_mor(m, MOOD[k][1])
        add_bond(m, MOOD[k][2])
        [m, k]
      end
    end

    # prideOf: above the team's average overall, a recent evolution (20
    # weeks), a proud species, a legend; at most 2.5.
    def pride(mon, club)
      ovr = ->(m) { Economy.ovr(m.rating) }
      sq = club.squad.empty? ? [mon] : club.squad
      p = [0, (ovr.(mon) - sq.sum(&ovr) / sq.size.to_f) / 12.0].max
      if mon.evo_week && calendar && week
        d = calendar.days_between(mon.evo_week, week) / 7
        p += 0.9 * (1 - d / 20.0) if d >= 0 && d < 20
      end
      k = mon.species && PRIDE_SPECIES[mon.species.to_sym]
      p = (p + 0.25) * k if k
      p *= 1.3 if Scout.pool && mon.species && Scout.legend?(Scout.pool, mon.species)
      [p, 2.5].min
    end

    def lazy?(mon) = !mon.species.nil? && LAZY_SPECIES.include?(mon.species.to_sym)

    # disobeyP: a chance an action, 0 at bond 120 or with no pride.
    def disobey_p(mon, club)
      return 0.0 if mon.bond >= BOND_OBEY
      pr = pride(mon, club)
      return 0.0 if pr <= 0
      p = (BOND_OBEY - mon.bond) / BOND_OBEY.to_f * pr * 0.2
      p *= { comp: 1.6, off: 1.4, fire: 0.7, mot: 0.85 }.fetch(mon.mood(week), 1)
      p *= { worst: 1.5, bad: 1.2 }.fetch(tier(mon.mor)[1], 1)
      [p, 0.3].min
    end

    # bondFx -> [survive a lethal hit, shake off a status a turn]
    def bond_fx(mon)
      b = mon.bond
      b >= 220 ? [0.008, 0.03] : b >= 180 ? [0.004, 0.02] : b >= 150 ? [0.002, 0.01] : [0.0, 0.0]
    end

    # morWeek for one club: `form` is its last league results (:w/:d/:l).
    def weekly(club, form)
      f = form.last(5)
      base = (55 + 2 * (f.count(:w) - f.count(:l))).clamp(45, 65)
      entry = club.entry
      club.squad.each do |m|
        m.mor = (m.mor + (base - m.mor) * 0.15).round(1)
        add_bond(m, 0.5 + (entry.any? { |e| e.equal?(m) } ? 0.5 : 0))
      end
    end

    # morAfterBattle for one side: `played` mons, `fainted` of them, KOs
    # each scored this match, `won`, the pre-match expectation `pe`.
    def after_match(club, played, fainted, kos, won:, pe:, big:)
      dr = (won ? 1 : 0) - pe
      played.each do |m|
        k = kos[m] || 0
        down = fainted.any? { |x| x.equal?(m) }
        add_mor(m, (won ? 0.5 : -0.5) + 12 * dr * (big ? 1.4 : 1) + (down ? -1 : 0) + 2 * k)
        add_bond(m, (won ? 1.5 : 1) + 0.5 * k)
        m.form_ko = (0.6 * m.form_ko + 0.4 * [2, k].min).round(1)
      end
      club.entry.each { |m| add_mor(m, 4 * dr) unless played.any? { |p| p.equal?(m) } }
    end
  end
end
