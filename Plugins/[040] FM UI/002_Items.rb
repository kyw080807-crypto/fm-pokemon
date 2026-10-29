#===============================================================================
# FM UI: the shop and held items (Poké Manager viewShop / heldShopSection /
# equipItem). Names and texts are the original's (ITEM_KO, HELD).
#===============================================================================
module FM
  module UI
    module_function

    ITEM_TEXT = {
      LEFTOVERS: ["먹다남은음식", "매 턴 끝에 최대 HP의 1/16을 회복한다"],
      LIFEORB: ["생명의구슬", "공격 기술 위력이 1.3배가 되지만 공격할 때마다 HP가 조금 줄어든다"],
      CHOICEBAND: ["구애머리띠", "공격이 1.5배가 되지만 처음 고른 기술만 쓸 수 있다"],
      CHOICESPECS: ["구애안경", "특수공격이 1.5배가 되지만 처음 고른 기술만 쓸 수 있다"],
      CHOICESCARF: ["구애스카프", "스피드가 1.5배가 되지만 처음 고른 기술만 쓸 수 있다"],
      ASSAULTVEST: ["돌격조끼", "특수방어가 1.5배가 되지만 변화 기술을 쓸 수 없다"],
      EVIOLITE: ["진화의휘석", "아직 진화할 수 있는 포켓몬의 방어와 특수방어가 1.5배가 된다"],
      EXPERTBELT: ["달인의띠", "효과가 굉장한 기술의 위력이 1.2배가 된다"],
      ROCKYHELMET: ["울퉁불퉁멧", "접촉 공격을 한 상대에게 데미지를 준다"],
      HEAVYDUTYBOOTS: ["통굽부츠", "스텔스록, 압정뿌리기 같은 설치 기술의 피해를 받지 않는다"],
      BLACKSLUDGE: ["검은오물", "독 타입은 매 턴 회복하고, 다른 타입은 피해를 입는다"],
      FOCUSSASH: ["기합의띠", "HP가 가득할 때 한 방에 쓰러지지 않고 HP 1로 버틴다 (배틀당 1회)"],
      WEAKNESSPOLICY: ["약점보험", "효과가 굉장한 공격을 받으면 공격과 특수공격이 2랭크 오른다 (배틀당 1회)"],
      SITRUSBERRY: ["자뭉열매", "HP가 절반 이하가 되면 HP를 회복한다 (1회용)"],
      LUMBERRY: ["리샘열매", "상태이상이나 혼란을 한 번 회복한다 (1회용)"],
      LIGHTCLAY: ["빛의점토", "리플렉터·빛의장막 같은 벽 기술이 8턴 동안 이어진다"],
      FLAMEORB: ["화염구슬", "턴이 끝나면 지닌 포켓몬이 화상을 입는다 (근성·매직가드 등과 함께)"],
      TOXICORB: ["맹독구슬", "턴이 끝나면 지닌 포켓몬이 맹독에 걸린다 (포이즌힐 등과 함께)"],
      POWERHERB: ["파워풀허브", "모으는 기술을 한 번 바로 쓸 수 있다 (배틀당 1회)"],
      WHITEHERB: ["하양허브", "떨어진 능력치를 한 번 원래대로 되돌린다 (배틀당 1회)"],
      MENTALHERB: ["멘탈허브", "도발·앵콜 같은 행동 제한을 한 번 풀어준다 (배틀당 1회)"],
      AIRBALLOON: ["풍선", "공격을 받기 전까지 땅 타입 기술에 맞지 않는다 (배틀당 1회)"],
      BOOSTERENERGY: ["부스트에너지", "고대활성·쿼크차지를 날씨·필드 없이 발동시킨다 (배틀당 1회)"],
      LOADEDDICE: ["속임수주사위", "연속 공격 기술이 4~5번 맞는다"],
      SCOPELENS: ["초점렌즈", "급소에 맞을 확률이 오른다"],
      WIDELENS: ["광각렌즈", "기술의 명중률이 1.1배가 된다"],
      THROATSPRAY: ["목스프레이", "소리 기술을 쓰면 특수공격이 1랭크 오른다 (배틀당 1회)"],
      EJECTBUTTON: ["탈출버튼", "공격을 받으면 대기 포켓몬과 교체된다 (배틀당 1회)"],
      EJECTPACK: ["탈출팩", "능력치가 떨어지면 대기 포켓몬과 교체된다 (배틀당 1회)"],
      REDCARD: ["레드카드", "공격한 상대를 강제로 교체시킨다 (배틀당 1회)"],
      DAMPROCK: ["축축한바위", "비바라기·잔비의 비가 8턴 동안 이어진다"],
      HEATROCK: ["뜨거운바위", "쾌청·가뭄의 햇살이 8턴 동안 이어진다"],
      SMOOTHROCK: ["보송보송바위", "모래바람이 8턴 동안 이어진다"],
      ICYROCK: ["차가운바위", "설경이 8턴 동안 이어진다"],
      TERRAINEXTENDER: ["그라운드코트", "필드가 8턴 동안 이어진다"],
      PROTECTIVEPADS: ["방호패드", "접촉 기술을 써도 상대의 접촉 효과를 받지 않는다"],
      SHEDSHELL: ["아름다운허물", "잡아두는 특성·기술에 걸려도 교체할 수 있다"],
      COVERTCLOAK: ["은밀망토", "상대 기술의 추가 효과를 받지 않는다"],
      CLEARAMULET: ["클리어참", "상대가 능력치를 떨어뜨리지 못한다"]
    }.freeze

    def item_name(id) = id && ITEM_TEXT[id] ? _INTL(ITEM_TEXT[id][0]) : id.to_s
    def item_desc(id) = ITEM_TEXT[id] ? _INTL(ITEM_TEXT[id][1]) : ""

    def items_menu
      c = player_club or return
      loop do
        bag = Items.bag(c)
        head = _INTL("잔고 {1} · 가방 {2}개{3}", money(c.wallet.balance), bag.values.sum,
                     Items.shop_mul(c) < 1 ? _INTL(" · 숍 스폰서 할인 20%") : "")
        cmds = [_INTL("상점에서 사기"), _INTL("지닌 물건 주기·빼기"), _INTL("닫기")]
        case pbMessage(head, cmds, cmds.size)
        when 0 then item_shop(c)
        when 1 then item_equip(c)
        else break
        end
      end
    end

    def item_shop(c)
      ids = Items::HELD.keys
      loop do
        rows = ids.map { |id| _INTL("{1} {2} (가방 {3})", item_name(id), money(Items.price(c, id)), Items.count(c, id)) }
        i = pbMessage(_INTL("무엇을 살까요? (잔고 {1})", money(c.wallet.balance)), rows + [_INTL("닫기")], rows.size + 1)
        break if i >= ids.size
        id = ids[i]
        next unless pbConfirmMessage(_INTL("{1}: {2}\n{3}에 살까요?", item_name(id), item_desc(id), money(Items.price(c, id))))
        if Items.buy(c, id, date: world.calendar.date)
          pbMessage(_INTL("{1}을(를) 샀습니다.", item_name(id)))
        else
          pbMessage(_INTL("돈이 모자랍니다."))
        end
      end
    end

    def item_equip(c)
      loop do
        mons = c.squad
        rows = mons.map { |m| _INTL("{1} · {2}", species_name(m.species), m.item ? item_name(m.item) : _INTL("(없음)")) }
        i = pbMessage(_INTL("누구에게 줄까요? 같은 물건은 팀에 하나만."), rows + [_INTL("닫기")], rows.size + 1)
        break if i >= mons.size
        m = mons[i]
        have = Items.bag(c).keys
        opts = have.map { |id| _INTL("{1} ({2}개)", item_name(id), Items.count(c, id)) }
        opts << _INTL("빼기") if m.item
        j = pbMessage(_INTL("{1}에게 무엇을? (가방에 있는 것)", species_name(m.species)), opts + [_INTL("취소")], opts.size + 1)
        next if j >= opts.size
        id = j < have.size ? have[j] : nil
        case Items.equip(c, m, id)
        when :ok
          pbMessage(id ? _INTL("{1}에게 {2}을(를) 쥐여 주었습니다.", species_name(m.species), item_name(id)) :
                         _INTL("{1}의 물건을 가방에 넣었습니다.", species_name(m.species)))
        when :taken then pbMessage(_INTL("팀의 다른 포켓몬이 이미 {1}을(를) 지니고 있습니다.", item_name(id)))
        else pbMessage(_INTL("줄 수 없습니다."))
        end
      end
    end
  end
end
