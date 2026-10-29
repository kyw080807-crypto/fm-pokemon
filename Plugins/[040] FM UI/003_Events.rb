#===============================================================================
# FM UI: the player's choice events (Poké Manager eventOverlay; texts are the
# original's EVENTS / PRESS_W / PRESS_L, with the fan-satisfaction notes).
# Asked after "1주 진행"; FM::Events takes the last option if it is skipped.
#===============================================================================
module FM
  module UI
    module_function

    def event_texts(ev, c)
      case ev[:key]
      when :tv
        [_INTL("지역 방송 출연 제의"),
         _INTL("{1} 지역 방송국이 다음 주 특집에 출연해 달라고 한다. 촬영 때문에 엔트리 포켓몬들이 조금 지칠 수 있다.", region_name(c.region)),
         [_INTL("출연한다 (명성 +3, 엔트리 컨디션 -8, 팬 만족도 +2)"), _INTL("거절한다 (변화 없음)")]]
      when :fans
        [_INTL("팬 사인회 요청"), _INTL("팬클럽이 홈 경기장에서 사인회를 열자고 한다."),
         [_INTL("연다 (굿즈 수입 +{1}, 엔트리 컨디션 -5, 팬 만족도 +5)", money(Events.fan_cash(c))),
          _INTL("훈련에 집중 (팬 만족도 -1)")]]
      when :taunt
        n = world.clubs[world.rival[:club]].name
        [_INTL("라이벌 {1}의 도발", n), _INTL("\"이번 시즌도 내가 위다.\" {1}의 인터뷰가 화제다.", n),
         [_INTL("맞받아친다 (명성 +2. 다음 라이벌전 승리 시 명성 +5, 패배 시 -4)"), _INTL("무시한다 (변화 없음)")]]
      when :rumor
        [_INTL("유망주 소문"), _INTL("{1}에 눈에 띄는 유망주가 있다는 소문이 돈다.", region_name(ev[:region])),
         [_INTL("스카우트를 급파한다 ({1} · 좋은 후보 2마리 보고서가 바로 도착)", money(Scouting::FEE)), _INTL("흘려듣는다 (변화 없음)")]]
      when :event
        [_INTL("지역 행사 초청"), _INTL("{1}의 상점가가 행사에 트레이너로 와 달라고 한다. 사례금이 있다.", region_name(c.region)),
         [_INTL("참석한다 ({1}, 이번 주 엔트리 컨디션 -6)", money(Events.event_cash(c))), _INTL("정중히 거절 (변화 없음)")]]
      when :camp
        [_INTL("합숙 훈련 제안"), _INTL("근처 훈련장이 주말 합숙 프로그램을 연다고 한다."),
         [_INTL("참가한다 ({1} · 엔트리 전원 노력치 +8, 컨디션 -10)", money(Events::CAMP_FEE)), _INTL("넘어간다 (변화 없음)")]]
      when :slump
        n = ev[:mon] ? species_name(ev[:mon].species) : "?"
        [_INTL("{1}의 슬럼프", n), _INTL("{1}이(가) 요즘 훈련에 집중하지 못한다.", n),
         [_INTL("푹 쉬게 한다 (컨디션 +25, 이번 주는 휴식)"), _INTL("다그친다 (반반: 노력치 +10 또는 컨디션 -15)")]]
      when :interview
        [_INTL("기자회견 (경기 전)"), _INTL("다음 리그 경기를 앞두고 기자가 각오를 묻는다."),
         [_INTL("우승하겠다고 큰소리 (명성 +3, 팬 만족도 +2. 다음 리그 경기에서 지면 명성 -4)"), _INTL("겸손하게 (명성 +1, 팬 만족도 +1)")]]
      when :press_win
        [_INTL("경기 후 기자회견"), _INTL("지난 경기 직후, 기자들이 마이크를 들이댄다."),
         [_INTL("팬들 덕분이라고 말한다 (팬 만족도 +4)"), _INTL("포켓몬들을 칭찬한다 (팬 만족도 +2, 명성 +1)"),
          _INTL("\"다음도 이긴다\" 큰소리 (명성 +2, 팬 만족도 +3. 다음 공식 경기에서 지면 팬 만족도 -5)")]]
      when :press_loss
        [_INTL("경기 후 기자회견"), _INTL("지난 경기에서 진 직후, 기자들이 마이크를 들이댄다."),
         [_INTL("팬들에게 사과한다 (팬 만족도 +3, 명성 -1)"), _INTL("문제점을 인정하고 개선을 약속 (팬 만족도 +2)"),
          _INTL("운이 없었을 뿐이라고 말한다 (팬 만족도 -4)"), _INTL("기자회견에 나가지 않는다 (팬 만족도 -2)")]]
      end
    end

    # eventOverlay
    def ask_event
      c = player_club
      ev = world.event
      return unless c && ev
      title, body, opts = event_texts(ev, c)
      i = pbMessage(_INTL("{1}\n{2}", title, body), opts, opts.size)
      out = Events.resolve(world, c, i)
      return unless out
      if out[:species]
        pbMessage(_INTL("유망주 소문 보고서 도착: {1}", out[:species].map { |sp| species_name(sp) }.join(", ")))
      elsif out[:pushed]
        pbMessage(out[:pushed] == :better ? _INTL("다그친 보람이 있었다 (노력치 +10).") : _INTL("더 지쳐 버렸다 (컨디션 -15)."))
      end
    end
  end
end
