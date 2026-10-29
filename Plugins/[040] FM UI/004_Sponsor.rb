#===============================================================================
# FM UI: sponsor contracts 2.0 (Poké Manager sponPanel / sp2 negotiation;
# the kind texts are the original's SPON_KIND).
#===============================================================================
module FM
  module UI
    module_function

    SPONSOR_KIND_TEXT = {
      "STABLE" => ["안정형", "기본금이 크고 기대치가 무난하다. 보너스는 작다"],
      "PERF" => ["성과형", "기본금은 적지만 기대치를 채우면 보너스가 크다"],
      "STRICT" => ["엄격 성과형", "보너스가 크다. 핵심 기대치를 놓치면 바로 해지되고 다음 두 시즌 동안 제안하지 않는다"],
      "FAME" => ["명성형", "기본금은 적지만 시즌 말 명성 +4"],
      "BUZZ" => ["화제형", "이변·우승 같은 화제가 날 때마다 ₽8,000 보너스"],
      "SHOP" => ["할인형", "기본금은 적지만 상점 물건 20% 할인"],
      "RISKY" => ["고위험", "기본금이 크지만 19라운드에 13위 이하면 해지"]
    }.freeze
    AMB_NAMES = { -1 => "낮게", 0 => "기본", 1 => "높게" }.freeze
    IMP_NAMES = { k: "핵심", n: "중요", b: "보너스" }.freeze
    SAT_WHY = { league_win: "리그 승리", league_loss: "리그 패배", buzz: "화제 기사", review: "중간 평가", season: "시즌 평가",
                debt: "적자", debt4: "4주 연속 적자" }.freeze

    def sponsor_name(s) = s[:bridge] ? _INTL("지역 상공회") : s[:name].to_s
    def kind_name(s) = s[:bridge] ? _INTL("임시 후원") : _INTL(SPONSOR_KIND_TEXT.fetch(s[:kind], [s[:kind].to_s])[0])

    def sponsor_mood(v)
      v >= 80 ? _INTL("매우 만족") : v >= 60 ? _INTL("만족") : v >= 40 ? _INTL("보통") : v >= 20 ? _INTL("불만") : _INTL("매우 불만")
    end

    # sp2Label
    def exp_label(e)
      case e[:k]
      when :pos, :pwt then e[:t] == 1 ? _INTL("리그 1위") : goal_text(world, e[:t], e[:region] || player_club.region)
      when :fame then _INTL("리그 종료 때 명성 {1} 이상", e[:t])
      when :fans then _INTL("팬 만족도 {1} 이상", e[:t])
      when :att then _INTL("홈 평균 관중 {1}명 이상", e[:t])
      when :buzz then _INTL("화제 기사 {1}건 이상", e[:t])
      when :debt then e[:t].zero? ? _INTL("리그 기간 적자 없음") : _INTL("리그 기간 적자 {1}주 이하", e[:t])
      end
    end

    def exp_line(c, e)
      st, cur = Contract.now(world, c, e, false)
      mark = { ok: "○", near: "△", bad: "×", wait: "·" }.fetch(st)
      _INTL("{1} [{2}] {3} · 보너스 {4}{5}", mark, _INTL(IMP_NAMES[e[:imp]]), exp_label(e), money(e[:bonus].to_i),
            cur.nil? ? "" : _INTL(" (지금 {1})", cur))
    end

    def contract_rows(c)
      s = c.sponsor
      return [_INTL("스폰서 없음")] unless s
      rows = [_INTL("{1} · {2}", sponsor_name(s), kind_name(s))]
      if Contract.v2?(s)
        span = s[:len] > 1 ? _INTL("{1}시즌 계약 ({2}~{3}년차)", s[:len], s[:since], s[:until]) : _INTL("1시즌 계약 ({1}년차)", s[:since])
        rows << _INTL("{1} · 시즌 기본금 {2} · 목표 수준 {3}", span, money(s[:base]), _INTL(AMB_NAMES[s[:amb]]))
        rows << _INTL("만족도 {1}/100 ({2})", s[:sat].round, sponsor_mood(s[:sat])) if s[:sat]
        (s[:exp] || []).each { |e| rows << exp_line(c, e) }
        (s[:sat_log] || []).first(4).each do |x|
          rows << _INTL("  {1} {2}", _INTL(SAT_WHY[x[:why]] || x[:why].to_s), format("%+.1f", x[:d]))
        end
        (s[:evals] || []).each do |v|
          rows << _INTL("{1}년차 평가: {2}위 · 기대치 {3}/{4} · 보너스 {5} · 만족도 {6}", v[:year], v[:pos], v[:ok], v[:n], money(v[:pay]), v[:sat])
        end
      else
        rows << _INTL("시즌 기본금 {1}", money(s[:base]))
      end
      rows
    end

    def sponsor_menu
      c = player_club or return
      loop do
        offs = world.sponsor_offers
        cmds = [[_INTL("계약 보기"), :view]]
        cmds << [_INTL("후원 제안 고르기 ({1})", offs.size), :pick] if offs
        cmds << [_INTL("계약 조기 해지 (위약금 {1})", money(Contract.penalty(world, c.sponsor))), :quit] if Contract.can_quit?(world, c)
        cmds << [_INTL("닫기"), :close]
        head = c.sponsor ? _INTL("스폰서: {1}", sponsor_name(c.sponsor)) : _INTL("스폰서 없음{1}", offs ? _INTL(" · 리그 개막 전에 고르지 않으면 자동으로 정해집니다") : "")
        i = pbMessage(head, cmds.map(&:first), cmds.size)
        case cmds[i]&.last
        when :view then show_list(_INTL("스폰서 계약"), contract_rows(c))
        when :pick then pick_sponsor(c, offs)
        when :quit
          next unless pbConfirmMessage(_INTL("위약금 {1}을 내고 {2}와의 계약을 깰까요?", money(Contract.penalty(world, c.sponsor)),
                                             sponsor_name(c.sponsor)))
          pen = Contract.player_quit(world, c)
          pbMessage(_INTL("계약을 해지했습니다 (위약금 {1}). 새 후원 제안을 고르세요.", money(pen))) if pen
        else break
        end
      end
    end

    # The negotiation: an offer, its length, its target level.
    def pick_sponsor(c, offs)
      rows = offs.map do |o|
        tag = o[:renew] ? _INTL("[재계약] ") : ""
        _INTL("{1}{2} · {3} · 기본금 {4}", tag, sponsor_name(o), kind_name(o), money(o[:base0] || o[:base]))
      end
      i = pbMessage(_INTL("어느 회사와 계약할까요?"), rows + [_INTL("취소")], rows.size + 1)
      return if i >= offs.size
      o = offs[i]
      lens = (o[:lens][0]..o[:lens][1]).to_a
      j = lens.size > 1 ? pbMessage(_INTL("계약 기간은? 길수록 기본금과 계약금이 붙지만 금액은 계약이 끝날 때까지 그대로입니다."),
                                    lens.map { |l| _INTL("{1}시즌", l) }, lens.size) : 0
      len = lens[j] || lens.first
      ambs = o[:bridge] ? [0] : [-1, 0, 1]
      k = ambs.size > 1 ? pbMessage(_INTL("목표 수준은? 높이면 기본금(+15%)·보너스(+45%)가 커지지만 기대치가 빡빡해집니다."),
                                    ambs.map { |a| _INTL(AMB_NAMES[a]) }, ambs.size) : 0
      a = ambs[k] || 0
      tm = Contract.terms(o, len, a)
      exps = Contract.exps(world, c, o, a, tm[:pool], human: true)
      lines = [_INTL("{1} · {2}시즌 · 목표 {3}", sponsor_name(o), len, _INTL(AMB_NAMES[a])),
               _INTL("시즌 기본금 {1} · 계약금 {2} · 보너스 총액 {3}", money(tm[:base]), money(tm[:sign]), money(tm[:pool]))]
      exps.each { |e| lines << _INTL("[{1}] {2} · 보너스 {3}", _INTL(IMP_NAMES[e[:imp]]), exp_label(e), money(e[:bonus])) }
      lines << _INTL(SPONSOR_KIND_TEXT.fetch(o[:kind], ["", ""])[1]) unless o[:bridge]
      show_list(_INTL("계약 조건"), lines)
      return unless pbConfirmMessage(_INTL("이 조건으로 {1}와 계약할까요?", sponsor_name(o)))
      Contract.take(world, c, i, len: len, amb: a)
      c.sponsor[:human] = true
      Contract.season(world, c, fresh: true)
      pbMessage(_INTL("{1} 후원 계약 ({2}시즌){3}", sponsor_name(c.sponsor), len,
                      tm[:sign].positive? ? _INTL(" · 계약금 {1} 입금", money(tm[:sign])) : ""))
    end

    SPONSOR_QUIT_WHY = { low_sat: "만족도가 너무 낮아졌다", debt4: "4주 연속 적자가 이어졌다",
                         risky: "19라운드에 13위 이하 (고위험 계약 조건)", strict_fail: "핵심 기대치를 지키지 못했다" }.freeze

    def sponsor_news(e, id)
      return unless e[:club] == id
      n = e[:name] || _INTL("지역 상공회")
      case e[:kind]
      when :sponsor_quit then _INTL("{1}, 후원 중단: {2}", n, _INTL(SPONSOR_QUIT_WHY.fetch(e[:why], e[:why].to_s)))
      when :sponsor_warn then _INTL("{1}의 공식 경고: 만족도 {2}. 15 아래로 떨어지면 계약 해지", n, e[:sat])
      when :sponsor_review then _INTL("{1} 중간 평가: 순조 {2} · 부진 {3} · 만족도 {4}", n, e[:ok], e[:bad], e[:sat])
      when :sponsor_eval
        _INTL("{1} 시즌 평가: 기대치 {2}/{3} 달성{4} · 만족도 {5}", n, e[:ok], e[:n],
              e[:pay].positive? ? _INTL(" · 보너스 {1}", money(e[:pay])) : "", e[:sat])
      when :sponsor_renewal
        e[:yes] ? _INTL("{1}, 재계약 희망 (만족도 {2}): 새 시즌 제안에 포함", n, e[:sat]) : _INTL("{1}, 이번 시즌으로 후원 마무리 (만족도 {2})", n, e[:sat])
      end
    end
  end
end
