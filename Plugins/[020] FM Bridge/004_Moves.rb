#===============================================================================
# FM Bridge: a battle Pokémon's moves, nature and ability (Poké Manager:
# learnPool, autoMoves, STATUS_GOOD, BAD_MOVES, recoilOf; FM::Tuning).
# - learnable: level-up moves to its level (all of them once evolved), TMs
#   and tutor moves, egg moves, along its prevolutions.
# - auto_moves: damaging moves scored power x accuracy x STAB 1.5 x 0.65
#   off its better attack x the bad-move penalty x recoil x 0.85 for
#   priority x 0.5 for two-turn moves, ability boosts (Strong Jaw, Iron
#   Fist, Tough Claws, Technician, Mega Launcher, Sharpness); the best of
#   each of its types, one coverage type, one good status move, then the
#   best left. Signature-move rules and Showdown's sets are left out.
# Engine API (checked): GameData::Species#moves / tutor_moves /
# get_egg_moves / get_previous_species, GameData::Move#power / accuracy /
# type / category / priority / function_code / flags, Pokemon#learn_move /
# forget_all_moves / nature= / ability_index=.
#===============================================================================
module FM
  module Battle
    STATUS_GOOD = { SWORDSDANCE: 1, NASTYPLOT: 1, CALMMIND: 1, DRAGONDANCE: 1, BULKUP: 1, QUIVERDANCE: 1,
                    SHELLSMASH: 1, SHIFTGEAR: 1, COIL: 1, IRONDEFENSE: 0.5, AGILITY: 0.6, CURSE: 0.6, RECOVER: 2,
                    ROOST: 2, SOFTBOILED: 2, SLACKOFF: 2, MOONLIGHT: 2, MORNINGSUN: 2, SYNTHESIS: 2, MILKDRINK: 2,
                    SHOREUP: 2, TOXIC: 3, WILLOWISP: 3, THUNDERWAVE: 3, SPORE: 3, SLEEPPOWDER: 3, HYPNOSIS: 3, YAWN: 3,
                    GLARE: 3, STUNSPORE: 3, POISONPOWDER: 3, LEECHSEED: 4, STEALTHROCK: 4, SPIKES: 4, TOXICSPIKES: 4,
                    SUBSTITUTE: 5, PROTECT: 5, LIGHTSCREEN: 4, REFLECT: 4, TAUNT: 4 }.freeze
    BAD_MOVES = %i[SELFDESTRUCT EXPLOSION MEMENTO FINALGAMBIT MISTYEXPLOSION FOCUSPUNCH LASTRESORT HEALINGWISH
                   LUNARDANCE DREAMEATER BELCH STEELBEAM MINDBLOWN SYNCHRONOISE SNORE SLEEPTALK NATURALGIFT FLING
                   HYPERBEAM GIGAIMPACT BLASTBURN FRENZYPLANT HYDROCANNON ROCKWRECKER ROAROFTIME PRISMATICLASER
                   ETERNABEAM METEORASSAULT SKYATTACK RAZORWIND SKULLBASH SOLARBLADE SOLARBEAM FUTURESIGHT DOOMDESIRE
                   UPROAR BIDE COUNTER MIRRORCOAT METALBURST ENDEAVOR PRESENT SPLASH CELEBRATE HOLDHANDS].freeze
    SOFT_BAD = { OUTRAGE: 0.7, THRASH: 0.7, PETALDANCE: 0.7, MAGNITUDE: 0.6 }.freeze

    module_function

    # learnPool -> [[move, :level / :evo / :tm / :egg], ...]
    def learnable(species, level)
      sp = GameData::Species.get(species)
      evolved = sp.get_previous_species != sp.species
      out = {}
      add = ->(m, src) { out[m] ||= src }
      cur = sp
      4.times do
        cur.moves.each { |lv, m| add.(m, lv <= level ? :level : :evo) if evolved || lv <= level }
        cur.tutor_moves.each { |m| add.(m, :tm) }
        cur.get_egg_moves.each { |m| add.(m, :egg) }
        prev = cur.get_previous_species
        break if prev == cur.species
        cur = GameData::Species.get(prev)
      end
      out.to_a
    end

    def recoil(md, ability)
      return 0 if ability == :MAGICGUARD
      code = md.function_code.to_s
      return 0 unless code.include?("Recoil")
      return 0 if ability == :ROCKHEAD
      code.include?("Half") ? 0.5 : code.include?("Third") ? 1 / 3.0 : 0.25
    end

    # autoMoves
    def auto_moves(species, level, ability, branch)
      sd = GameData::Species.get(species)
      types = sd.types
      phys = sd.base_stats[:ATTACK] >= sd.base_stats[:SPECIAL_ATTACK]
      dmg = []
      stat = []
      learnable(species, level).each do |m, _|
        md = GameData::Move.try_get(m) or next
        if md.status?
          (g = STATUS_GOOD[md.id]) && stat << [md.id, g]
          next
        end
        bp = md.power
        bp = 70 if bp == 1   # variable power (Low Kick, Grass Knot, ...)
        next if bp.to_i <= 0
        bp *= 1.5 if (ability == :STRONGJAW && md.has_flag?("Biting")) || (ability == :MEGALAUNCHER && md.has_flag?("Pulse")) ||
                     (ability == :SHARPNESS && md.has_flag?("Slicing"))
        bp *= 1.2 if ability == :IRONFIST && md.has_flag?("Punching")
        bp *= 1.3 if ability == :TOUGHCLAWS && md.has_flag?("Contact")
        bp *= 1.5 if ability == :TECHNICIAN && bp <= 60
        acc = md.accuracy.to_i.zero? ? 1.0 : md.accuracy / 100.0
        stab = types.include?(md.type) ? 1.5 : 1.0
        fit = md.physical? == phys ? 1.0 : 0.65
        pen = BAD_MOVES.include?(md.id) ? 0.3 : SOFT_BAD.fetch(md.id, 1.0)
        rc = recoil(md, ability)
        rp = rc.positive? ? (ability == :RECKLESS ? 1.0 : 1 - rc * 0.75) : 1.0
        two = md.function_code.to_s.start_with?("TwoTurnAttack") ? 0.5 : 1.0
        score = bp * acc * stab * fit * pen * rp * (md.priority.positive? ? 0.85 : 1) * two
        dmg << { id: md.id, type: md.type, rc: rc.positive?, score: score }
      end
      dmg.sort_by! { |d| -d[:score] }
      pick = []
      used = []
      types.each do |t|
        x = dmg.find { |d| d[:type] == t && !pick.include?(d[:id]) }
        next unless x
        pick << x[:id]
        used << x[:type]
      end
      rec_n = -> { pick.count { |id| dmg.any? { |d| d[:id] == id && d[:rc] } } }
      cov = dmg.find { |d| !used.include?(d[:type]) && !pick.include?(d[:id]) && !(d[:rc] && rec_n.call >= 1) }
      if cov && pick.size < 3
        pick << cov[:id]
        used << cov[:type]
      end
      pick << stat.min_by { |id, g| [((g * 7 + branch) % 5), id.to_s] }[0] if stat.any? && pick.size < 4
      dmg.each { |d| pick << d[:id] if pick.size < 4 && !pick.include?(d[:id]) && !(d[:rc] && rec_n.call >= 1) }
      stat.each { |id, _| pick << id if pick.size < 4 && !pick.include?(id) }
      pick << :TACKLE if pick.empty?
      pick.first(4)
    end

    # A mon's moves for battle: its set moves it can still learn, topped up
    # with auto ones; then its mint and capsule.
    def apply_moves(pkmn, mon)
      pkmn.ability_index = mon.ab if mon.ab
      pool = learnable(pkmn.species, mon.level).map(&:first)
      set = (mon.moves || []).map(&:to_sym).select { |m| pool.include?(m) }
      auto = auto_moves(pkmn.species, mon.level, pkmn.ability_id, mon.branch)
      moves = (set + auto).uniq.first(4)
      moves = set if set.size == 4
      pkmn.forget_all_moves
      moves.each { |m| pkmn.learn_move(m) }
      pkmn
    end

    # The abilities a species can have (normal, then hidden).
    def abilities_of(species)
      sd = GameData::Species.get(species)
      sd.abilities + sd.hidden_abilities
    end
  end
end
