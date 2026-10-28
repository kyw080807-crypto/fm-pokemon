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
# its skill is the opponent's (Player#skill_level below), so auto is no
# weaker or stronger than the other side. Battle style is Set, so the
# "switch your Pokémon?" prompt never comes up. 빠른 진행: animations off.
# Condition, as in Poké Manager (pmApplyCm, condDebuff): every stat but
# HP is multiplied by Rating.cond_mul, and low condition (or a light
# injury) means stat stages down for the whole battle: put back on at
# every switch-in and after Haze-style resets (Battler patches below).
#===============================================================================
module FM
  module Battle
    LEVEL = 50
    ROLE_TRAINER_TYPE = { "C" => :CHAMPION, "E" => :ELITEFOUR_Lorelei, "G" => :LEADER_Brock }.freeze
    FALLBACK_TYPE = :COOLTRAINER_M

    class << self
      attr_accessor :auto, :fast   # read by prepare_battle below during fight
      attr_accessor :auto_skill    # the player's AI skill while auto is on
    end

    module_function

    # EVs into stats in pretrain order: main attack, speed, HP, the matching
    # defence, special defence, defence; 252 each at most.
    # club: the mon's club, for disobedience (FM::Morale.disobey_p).
    def to_pokemon(mon, owner, club: nil)
      pkmn = Pokemon.new(mon.species.to_sym, LEVEL, owner)
      pkmn.nature = Morale.nature(mon)   # the same list the temperament comes from
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
      # setOf: condMul x declineMul x morMul x moodMul; friendship = bond.
      pkmn.fm_cond_mul = Rating.cond_mul(mon.cond) * mon.decline_mul * Morale.mor_mul(mon) *
                         Morale.mood_mul(mon, Morale.week)
      pkmn.happiness = mon.bond.round.clamp(0, 255)
      pkmn.fm_disobey = club ? Morale.disobey_p(mon, club) : 0.0
      pkmn.fm_lazy = Morale.lazy?(mon)
      pkmn.fm_end, pkmn.fm_shake = Morale.bond_fx(mon)
      pkmn.fm_mood = mon.mood(Morale.week)
      pkmn.fm_debuffs = mon.debuffs.map { |s| STAGE_STAT.fetch(s) { main } }
      pkmn.calc_stats
      pkmn.heal
      pkmn
    end

    STAGE_STAT = { spe: :SPEED, def: :DEFENSE, spd: :SPECIAL_DEFENSE }.freeze   # :main = the better attack

    # Lowers the battler's stages by its Pokémon's FM debuffs (no ability
    # or Mist interaction: it is the mon's state, not a move).
    def apply_debuffs(battler)
      list = battler.pokemon&.fm_debuffs
      return if list.nil? || list.empty?
      list.each { |s| battler.stages[s] = [battler.stages[s] - 1, -6].max }
    end

    MOOD_LINES = { fire: "{1}은(는) 투지가 활활 불타오르고 있다!", nerv: "{1}은(는) 긴장한 것 같다…",
                   comp: "{1}은(는) 여유를 부리고 있다…", off: "{1}은(는) 어딘가 시큰둥하다…" }.freeze

    # The week's mood, once, the first time it comes out.
    def mood_line(battle, battler)
      pk = battler&.pokemon
      return if pk.nil? || battler.fainted? || pk.fm_mood_shown || !MOOD_LINES[pk.fm_mood]
      pk.fm_mood_shown = true
      battle.pbDisplay(_INTL(MOOD_LINES[pk.fm_mood], battler.pbThis))
    end

    def debuff_text(list)
      names = { SPEED: _INTL("스피드"), ATTACK: _INTL("공격"), SPECIAL_ATTACK: _INTL("특수공격"), DEFENSE: _INTL("방어"),
                SPECIAL_DEFENSE: _INTL("특수방어") }
      list.tally.map { |s, n| _INTL("{1} -{2}", names.fetch(s, s.to_s), n) }.join(" · ")
    end

    def trainer_for(club)
      type = ROLE_TRAINER_TYPE.fetch(club.role[0], FALLBACK_TYPE)
      type = FALLBACK_TYPE unless GameData::TrainerType.exists?(type)
      t = NPCTrainer.new(club.name, type)
      t.party = club.lineup.map { |m| to_pokemon(m, t, club: club) }
      t.lose_text = _INTL("...졌다.")
      t
    end

    # Fights with the player's chosen three (`picks`, FM::Mon; default the
    # best three) against the opponent's best three. Returns
    # { res:, ko_a:, ko_b: } from the player's side (a = player), plus who
    # played and who fainted (FM::Mon) for fatigue and injuries
    # (World#after_match). The match prompt and the pick screen are in FM UI.
    def fight(me, opp, picks: nil, auto: false, fast: false)
      picks ||= me.lineup
      Battle.auto = auto
      Battle.fast = fast
      saved = $player.party
      $player.party = picks.map { |m| to_pokemon(m, $player, club: me) }
      foe = trainer_for(opp)
      Battle.auto_skill = auto ? foe.skill_level : nil
      theirs = opp.lineup   # trainer_for builds the party from this, in order
      setBattleRule("canLose")
      setBattleRule("noExp")
      setBattleRule("noMoney")
      outcome = TrainerBattle.start_core(foe)
      fainted_b = theirs.select.with_index { |_, i| foe.party[i]&.fainted? }
      # after_battle heals a losing party, so on a loss all three fainted.
      fainted_a = outcome == 2 ? picks : picks.select.with_index { |_, i| $player.party[i]&.fainted? }
      res = { 1 => 1, 2 => -1 }.fetch(outcome, 0)
      disob = lambda do |mons, party|
        mons.each_with_index.filter_map { |m, i| (n = party[i]&.fm_disob_n.to_i).positive? ? [m, n] : nil }.to_h
      end
      { res: res, ko_a: fainted_b.size, ko_b: fainted_a.size,
        lineup_a: picks, lineup_b: theirs, fainted_a: fainted_a, fainted_b: fainted_b,
        disobeyed_a: disob.(picks, $player.party), disobeyed_b: disob.(theirs, foe.party) }
    ensure
      Battle.auto = Battle.fast = false
      Battle.auto_skill = nil
      $player.party = saved if saved
    end

    # The same battle with no scene and the AI on both sides (as the Battle
    # Frontier generator does: DebugSceneNoVisuals, controlPlayer). Debug
    # mode caps it at 100 rounds (then the engine judges on remaining HP).
    # Used to calibrate MatchSim against real results. a = first club.
    def simulate(a, b)
      ta = trainer_for(a)
      tb = trainer_for(b)
      battle = ::Battle.new(::Battle::DebugSceneNoVisuals.new, ta.party, tb.party, [ta], [tb])
      battle.debug = true
      battle.controlPlayer = true
      battle.internalBattle = false
      decision = battle.pbStartBattle
      ko_a = tb.party.count(&:fainted?)
      ko_b = ta.party.count(&:fainted?)
      { res: { 1 => 1, 2 => -1 }.fetch(decision, 0), ko_a: ko_a, ko_b: ko_b, turns: battle.turnCount }
    end
  end
end

class Pokemon
  attr_accessor :fm_cond_mul, :fm_debuffs   # FM battles only (FM::Battle.to_pokemon)
  # FM::Morale in battle: disobedience chance, lazy species, bond effects,
  # this week's mood; fm_end_used once the 1-HP survival happened.
  attr_accessor :fm_disobey, :fm_lazy, :fm_end, :fm_shake, :fm_mood, :fm_end_used, :fm_mood_shown
  attr_accessor :fm_disob_n   # times it disobeyed this battle

  alias __fm_calc_stats calc_stats
  def calc_stats
    __fm_calc_stats
    mul = @fm_cond_mul
    return if mul.nil? || mul == 1
    @attack  = [(@attack * mul).floor, 1].max
    @defense = [(@defense * mul).floor, 1].max
    @spatk   = [(@spatk * mul).floor, 1].max
    @spdef   = [(@spdef * mul).floor, 1].max
    @speed   = [(@speed * mul).floor, 1].max
  end
end

class Battle
  alias __fm_pbOnBattlerEnteringBattle pbOnBattlerEnteringBattle
  def pbOnBattlerEnteringBattle(battler_index, skip_event_reset = false)
    Array(battler_index).flatten.each do |i|
      b = @battlers[i]
      FM::Battle.mood_line(self, b)
      next if !b || b.fainted? || b.pokemon&.fm_debuffs.nil? || b.pokemon.fm_debuffs.empty?
      FM::Battle.apply_debuffs(b)
      pbDisplay(_INTL("{1}은(는) 컨디션이 나빠 {2} 상태로 싸운다!", b.pbThis,
                      FM::Battle.debuff_text(b.pokemon.fm_debuffs)))
    end
    __fm_pbOnBattlerEnteringBattle(battler_index, skip_event_reset)
  end
end

# Poké Manager morale in battle (FM::Morale): bond-based survival at 1 HP
# (once a battle) and shaking off a status at the end of a turn.
class Battle::Move
  alias __fm_pbReduceDamage pbReduceDamage
  def pbReduceDamage(user, target)
    st = target.damageState
    pk = target.pokemon
    if pk && pk.fm_end.to_f.positive? && !pk.fm_end_used && !st.substitute && st.calcDamage >= target.hp &&
       target.hp > 1 && user.opposes?(target) && @battle.pbRandom(1000) < pk.fm_end * 1000
      st.calcDamage = target.hp - 1
      pk.fm_end_used = true
      @battle.pbDisplay(_INTL("{1}은(는) 트레이너를 슬프게 하지 않으려고 버텼다!", target.pbThis))
    end
    __fm_pbReduceDamage(user, target)
  end
end

class Battle
  alias __fm_pbEndOfRoundPhase pbEndOfRoundPhase
  def pbEndOfRoundPhase
    __fm_pbEndOfRoundPhase
    return if @decision.positive?
    allBattlers.each do |b|
      next if b.fainted? || b.status == :NONE
      s = b.pokemon&.fm_shake.to_f
      next unless s.positive? && pbRandom(1000) < s * 1000
      pbDisplay(_INTL("{1}은(는) 트레이너의 기대에 부응하려고 상태 이상을 이겨냈다!", b.pbThis))
      b.pbCureStatus(false)
    end
  end
end

class Battle::Battler
  # Disobedience (Poké Manager morPatch runMove): not while asleep or
  # frozen or in a move that locks it in. 30%: another damaging move;
  # then a nap (45% for lazy species, else 20%); else it does nothing.
  alias __fm_pbObedienceCheck? pbObedienceCheck?
  def pbObedienceCheck?(choice)
    d = @pokemon&.fm_disobey.to_f
    if d.positive? && choice[0] == :UseMove && !usingMultiTurnAttack? && !%i[SLEEP FROZEN].include?(@status) &&
       @battle.pbRandom(1000) < d * 1000
      return fm_disobey(choice)
    end
    __fm_pbObedienceCheck?(choice)
  end

  def fm_disobey(choice)
    @pokemon.fm_disob_n = @pokemon.fm_disob_n.to_i + 1
    r = @battle.pbRandom(100)
    if r < 30
      others = []
      eachMoveWithIndex do |m, i|
        others << i if i != choice[1] && m.damagingMove? && @battle.pbCanChooseMove?(@index, i, false)
      end
      unless others.empty?
        i = others[@battle.pbRandom(others.length)]
        @battle.pbDisplay(_INTL("{1}은(는) 명령을 무시하고 제멋대로 움직였다!", pbThis))
        choice[1] = i
        choice[2] = @moves[i]
        choice[3] = -1
        return true
      end
    end
    if r < 30 + (@pokemon.fm_lazy ? 45 : 20) && pbCanSleep?(self, false)
      pbSleepSelf(_INTL("{1}은(는) 낮잠을 자기 시작했다!", pbThis))
      return false
    end
    q = @battle.pbRandom(100)
    msg = if pbHasType?(:FIRE) && q < 25 then _INTL("{1}은(는) 트레이너에게 불꽃을 내뿜었다!", pbThis)
          elsif q < 50 then _INTL("{1}은(는) 말을 듣지 않는다!", pbThis)
          elsif q < 75 then _INTL("{1}은(는) 고개를 홱 돌려 버렸다!", pbThis)
          else _INTL("{1}은(는) 못 들은 척하고 있다…", pbThis)
          end
    @battle.pbDisplay(msg)
    false
  end
end

class Battle::Battler
  alias __fm_pbResetStatStages pbResetStatStages
  def pbResetStatStages
    __fm_pbResetStatStages
    FM::Battle.apply_debuffs(self)
  end
end

class Player
  alias __fm_skill_level skill_level
  def skill_level
    FM::Battle.auto_skill || __fm_skill_level
  end
end

module BattleCreationHelperMethods
  class << self
    alias __fm_prepare_battle prepare_battle
    def prepare_battle(battle)
      __fm_prepare_battle(battle)
      if FM::Battle.auto
        battle.controlPlayer = true
        battle.switchStyle = false   # no "Will you switch?" when the foe sends out a new one
      end
      battle.showAnims = false if FM::Battle.fast
    end
  end
end
