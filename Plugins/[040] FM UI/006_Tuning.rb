#===============================================================================
# FM UI: 기술변경권 · 민트 · 특성캡슐 (FM::Tuning), from the shop menu.
# Move, nature and ability names are Essentials' (GameData).
#===============================================================================
module FM
  module UI
    module_function

    def move_name(m) = GameData::Move.try_get(m)&.name || m.to_s
    def nature_name(n) = GameData::Nature.try_get(n)&.name || n.to_s
    def ability_name(a) = GameData::Ability.try_get(a)&.name || a.to_s

    def battle_pokemon(c, m) = FM::Battle.to_pokemon(m, $player, club: c)

    def tuning_menu(c)
      loop do
        mons = c.squad
        rows = mons.map { |m| _INTL("{1} 숙련 {2}", species_name(m.species), m.level) }
        i = pbMessage(_INTL("누구를 바꿀까요?"), rows + [_INTL("닫기")], rows.size + 1)
        break if i >= mons.size
        m = mons[i]
        pk = battle_pokemon(c, m)
        head = _INTL("{1}: {2} · 성격 {3} · 특성 {4}", species_name(m.species), pk.moves.map { |x| move_name(x.id) }.join("/"),
                     nature_name(pk.nature_id), ability_name(pk.ability_id))
        cmds = [_INTL("기술 바꾸기 (기술변경권 {1})", money(Tuning.price(c, :moves))), _INTL("성격 바꾸기 (민트 {1})", money(Tuning.price(c, :mint))),
                _INTL("특성 바꾸기 (특성캡슐 {1})", money(Tuning.price(c, :ability))), _INTL("돌아가기")]
        case pbMessage(head, cmds, cmds.size)
        when 0 then pick_moves(c, m, pk)
        when 1 then pick_nature(c, m)
        when 2 then pick_ability(c, m, pk)
        end
      end
    end

    TUNING_FAIL = { money: "돈이 모자랍니다.", same: "지금과 같습니다.", not_learnable: "배울 수 없는 기술이 있습니다.",
                    count: "기술은 1~4개를 고르세요.", unknown: "고를 수 없습니다." }.freeze

    def tuning_result(r, ok_text)
      pbMessage(r == :ok ? ok_text : _INTL(TUNING_FAIL.fetch(r, r.to_s)))
    end

    # Pick up to four, then confirm.
    def pick_moves(c, m, pk)
      pool = FM::Battle.learnable(m.species, m.level)
      chosen = pk.moves.map(&:id)
      src = { level: "숙련", evo: "진화", tm: "기술머신", egg: "알기술" }
      loop do
        rows = pool.map { |mv, s| _INTL("{1}{2} ({3})", chosen.include?(mv) ? "▶" : "", move_name(mv), _INTL(src[s])) }
        i = pbMessage(_INTL("기술 {1}/4: {2}", chosen.size, chosen.map { |x| move_name(x) }.join("/")),
                      [_INTL("이대로 정하기")] + rows + [_INTL("취소")], rows.size + 2)
        return if i > rows.size
        if i.zero?
          return unless pbConfirmMessage(_INTL("기술변경권 {1}으로 {2}의 기술을 바꿀까요?", money(Tuning.price(c, :moves)), species_name(m.species)))
          return tuning_result(Tuning.set_moves(c, m, chosen, pool: pool.map(&:first), date: world.calendar.date),
                               _INTL("{1}의 기술을 바꿨습니다.", species_name(m.species)))
        end
        mv = pool[i - 1][0]
        if chosen.include?(mv)
          chosen.delete(mv)
        elsif chosen.size < 4
          chosen << mv
        else
          pbMessage(_INTL("기술은 4개까지입니다. 먼저 하나를 빼세요."))
        end
      end
    end

    def pick_nature(c, m)
      ns = Morale::NATURES
      i = pbMessage(_INTL("어떤 성격으로? (지금 {1})", nature_name(Morale.nature(m))), ns.map { |n| nature_name(n) } + [_INTL("취소")], ns.size + 1)
      return if i >= ns.size
      tuning_result(Tuning.mint(c, m, ns[i], date: world.calendar.date), _INTL("{1}의 성격이 {2}(으)로 바뀌었습니다.", species_name(m.species), nature_name(ns[i])))
    end

    def pick_ability(c, m, pk)
      abs = FM::Battle.abilities_of(m.species)
      if abs.uniq.size < 2
        pbMessage(_INTL("{1}은(는) 다른 특성이 없습니다.", species_name(m.species)))
        return
      end
      i = pbMessage(_INTL("어떤 특성으로? (지금 {1})", ability_name(pk.ability_id)), abs.map { |a| ability_name(a) } + [_INTL("취소")], abs.size + 1)
      return if i >= abs.size
      tuning_result(Tuning.capsule(c, m, i, count: abs.size, current: pk.ability_index, date: world.calendar.date),
                    _INTL("{1}의 특성이 {2}(으)로 바뀌었습니다.", species_name(m.species), ability_name(abs[i])))
    end
  end
end
