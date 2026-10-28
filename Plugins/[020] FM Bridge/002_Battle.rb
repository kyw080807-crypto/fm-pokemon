#===============================================================================
# FM Bridge: the player's matches as real Essentials battles (roadmap stage
# 3; design 06 직접 전투). Poké Manager format: every battle at Lv50, each
# side brings its best three (FM::Club#lineup), single battle. IVs come from
# stars (Rating::IV_MID), EVs from the mon's trained total in pretrain order.
# The player's party is swapped out for the battle and restored after.
# Battle rules: can lose, no EXP, no prize money.
# Engine API: TrainerBattle.start_core(NPCTrainer)
#   (Data/Scripts/012_Overworld/002_Battle triggering/001_Overworld_BattleStarting.rb:492)
# 자동 진행 (design 06): the same battle with Battle#controlPlayer on, so the
# battle AI plays the player's side too (as the Battle Frontier sim does);
# its skill is the player's trainer type's. 빠른 진행: animations off.
#===============================================================================
module FM
  module Battle
    LEVEL = 50
    ROLE_TRAINER_TYPE = { "C" => :CHAMPION, "E" => :ELITEFOUR_Lorelei, "G" => :LEADER_Brock }.freeze
    FALLBACK_TYPE = :COOLTRAINER_M

    class << self
      attr_accessor :auto, :fast   # read by prepare_battle below during fight
    end

    module_function

    # EVs into stats in pretrain order: main attack, speed, HP, the matching
    # defence, special defence, defence; 252 each at most.
    def to_pokemon(mon, owner)
      pkmn = Pokemon.new(mon.species.to_sym, LEVEL, owner)
      iv = Rating::IV_MID.fetch(mon.stars - 1).round
      GameData::Stat.each_main { |s| pkmn.iv[s.id] = iv }
      base = GameData::Species.get(pkmn.species).base_stats
      main = base[:ATTACK] >= base[:SPECIAL_ATTACK] ? :ATTACK : :SPECIAL_ATTACK
      order = [main, :SPEED, :HP, main == :ATTACK ? :DEFENSE : :SPECIAL_DEFENSE, :SPECIAL_DEFENSE, :DEFENSE].uniq
      left = mon.ev.round
      order.each do |s|
        give = [left, 252].min
        pkmn.ev[s] = give
        left -= give
      end
      pkmn.calc_stats
      pkmn.heal
      pkmn
    end

    def trainer_for(club)
      type = ROLE_TRAINER_TYPE.fetch(club.role[0], FALLBACK_TYPE)
      type = FALLBACK_TYPE unless GameData::TrainerType.exists?(type)
      t = NPCTrainer.new(club.name, type)
      t.party = club.lineup.map { |m| to_pokemon(m, t) }
      t.lose_text = _INTL("...졌다.")
      t
    end

    # Fights with the player's chosen three (`picks`, FM::Mon; default the
    # best three) against the opponent's best three. Returns
    # { res:, ko_a:, ko_b: } from the player's side (a = player).
    # The match prompt and the pick screen are in FM UI.
    def fight(me, opp, picks: nil, auto: false, fast: false)
      picks ||= me.lineup
      Battle.auto = auto
      Battle.fast = fast
      saved = $player.party
      $player.party = picks.map { |m| to_pokemon(m, $player) }
      foe = trainer_for(opp)
      setBattleRule("canLose")
      setBattleRule("noExp")
      setBattleRule("noMoney")
      outcome = TrainerBattle.start_core(foe)
      foe_down = foe.party.count(&:fainted?)
      mine_down = $player.party.count(&:fainted?)   # healed after a loss, see below
      case outcome
      when 1 then { res: 1, ko_a: foe_down, ko_b: mine_down }
      when 2 then { res: -1, ko_a: foe_down, ko_b: picks.size }   # after_battle heals a losing party
      else { res: 0, ko_a: foe_down, ko_b: mine_down }
      end
    ensure
      Battle.auto = Battle.fast = false
      $player.party = saved if saved
    end
  end
end

module BattleCreationHelperMethods
  class << self
    alias __fm_prepare_battle prepare_battle
    def prepare_battle(battle)
      __fm_prepare_battle(battle)
      battle.controlPlayer = true if FM::Battle.auto
      battle.showAnims = false if FM::Battle.fast
    end
  end
end
