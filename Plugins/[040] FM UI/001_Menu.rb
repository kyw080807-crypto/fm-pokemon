#===============================================================================
# FM UI: first in-game screens, reached from the pause menu ("FM"). Built on
# Essentials' own message and command windows; all text goes through _INTL.
# Data comes from FM::View (FM Core). Map events can open it with
# `FM::UI.main`.
#===============================================================================
module FM
  module UI
    module_function

    REGION_NAMES = {
      "KANTO" => "관동", "JOHTO" => "성도", "HOENN" => "호연", "SINNOH" => "신오", "UNOVA" => "하나",
      "KALOS" => "칼로스", "ALOLA" => "알로라", "GALAR" => "가라르", "PALDEA" => "팔데아"
    }.freeze
    REGIONS = REGION_NAMES.keys.freeze
    WEEKDAYS = { mon: "월", tue: "화", wed: "수", thu: "목", fri: "금", sat: "토", sun: "일" }.freeze

    def region_name(r) = _INTL(REGION_NAMES.fetch(r.to_s, r.to_s))

    def date_text(date)
      _INTL("{1}년 {2}월 {3}일", date[0], date[1], date[2])
    end

    def money(n)
      s = n.abs.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
      n.negative? ? "-₽#{s}" : "₽#{s}"
    end

    # Korean name from FM species data, else Essentials' (English) name.
    def species_name(id)
      ko = GameData::FmSpecies.try_get(id)&.real_name
      return _INTL(ko) unless ko.nil? || ko.empty?
      GameData::Species.try_get(id)&.name || id.to_s
    end

    def phase_text(phase)
      { preseason: _INTL("프리시즌"), league: _INTL("리그 진행 중"), cups: _INTL("대회 기간"),
        offseason: _INTL("비시즌") }.fetch(phase)
    end

    def event_text(kind)
      { league: _INTL("리그 경기"), pet: _INTL("PET·PENT"), pwt_swiss: _INTL("PWT 스위스 스테이지"),
        pwt_knockout: _INTL("PWT 토너먼트") }.fetch(kind)
    end

    # A full-screen, scrollable list with a title; Use or Back closes it.
    def show_list(title, rows)
      rows = [_INTL("(없음)")] if rows.empty?
      viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      viewport.z = 99_999
      head = Window_UnformattedTextPokemon.newWithSize(title, 0, 0, Graphics.width, 64, viewport)
      list = Window_CommandPokemonEx.newWithSize(rows, 0, 64, Graphics.width, Graphics.height - 64, viewport)
      loop do
        Graphics.update
        Input.update
        list.update
        break if Input.trigger?(Input::BACK) || Input.trigger?(Input::USE)
      end
      list.dispose
      head.dispose
      viewport.dispose
      Input.update
    end

    def world
      FM.world
    end

    def main
      unless world
        pbMessage(_INTL("FM 세계가 없습니다. 새 게임을 시작해 주세요."))
        return
      end
      loop do
        s = View.season(world)
        nxt = s[:next] ? _INTL("다음: {1} ({2}, {3}일 뒤)", event_text(s[:next][:kind]),
                               date_text(s[:next][:date]), s[:next][:in_days]) : ""
        header = _INTL("{1} ({2}) · {3}\n{4}", date_text(s[:date]), _INTL(WEEKDAYS[s[:weekday]]),
                       phase_text(s[:phase]), nxt)
        commands = [_INTL("내 클럽"), _INTL("시설 투자"), _INTL("스카우트"), _INTL("내 도시"), _INTL("리그 관리위원회"),
                    _INTL("리그 순위"), _INTL("대회"), _INTL("1주 진행"), _INTL("클럽 선택"), _INTL("경기 설정"),
                    _INTL("닫기")]
        case pbMessage(header, commands, commands.size)
        when 0 then my_club
        when 1 then invest
        when 2 then scout
        when 3 then my_city
        when 4 then committee
        when 5 then standings
        when 6 then cups
        when 7 then advance_week
        when 8 then choose_club
        when 9 then match_settings
        else break
        end
      end
    end

    def choose_region(prompt)
      names = REGIONS.map { |r| region_name(r) }
      i = pbMessage(prompt, names + [_INTL("취소")], names.size + 1)
      i < REGIONS.size ? REGIONS[i] : nil
    end

    def choose_club
      region = choose_region(_INTL("어느 지방의 클럽을 맡을까요?")) or return
      rows = View.standings(world, region)
      names = rows.map { |r| r[:name] }
      i = pbMessage(_INTL("맡을 클럽을 고르세요."), names + [_INTL("취소")], names.size + 1)
      return if i >= rows.size
      FM.state.player_club = rows[i][:id]
      pbMessage(_INTL("{1}의 감독이 되었습니다.", rows[i][:name]))
    end

    def my_club
      id = FM.state.player_club
      unless id
        pbMessage(_INTL("아직 맡은 클럽이 없습니다. 먼저 클럽을 고르세요."))
        return choose_club
      end
      show_list(_INTL("내 클럽"), my_club_rows(id))
    end

    def my_club_rows(id)
      c = View.club(world, id)
      rows = []
      rows << _INTL("{1} · {2} · 순위 {3}위", c[:name], region_name(c[:region]), c[:position] || "-")
      rows << _INTL("잔고 {1} · 명성 {2} · 전력 {3}", money(c[:balance]), c[:fame], c[:rating])
      fac = c[:facilities].map { |k, lv| "#{facility_name(k)} Lv#{lv}" }.join(" · ")
      rows << _INTL("클럽하우스 Lv{1} · 경기장 Lv{2}", c[:clubhouse], c[:stadium])
      rows << fac unless fac.empty?
      if c[:project]
        rows << _INTL("공사 중: {1} Lv{2} ({3} 완공)", facility_name(c[:project][:target]), c[:project][:to],
                      date_text(c[:project][:done]))
      end
      if c[:sponsor]
        rows << _INTL("스폰서: {1} (연 {2})", c[:sponsor][:name], money(c[:sponsor][:base]))
      end
      rows << _INTL("— 스쿼드 {1}마리 —", c[:squad].size)
      c[:squad].each do |m|
        rest = m[:resting] ? _INTL(" · 휴식") : ""
        rows << _INTL("{1} Lv{2} ★{3} · {4}년차 · 전력 {5} · 컨디션 {6}{7}", species_name(m[:species]), m[:level], m[:stars],
                      m[:age] + 1, m[:rating], m[:cond], rest)
      end
      rows
    end

    # The player's club, or nil (after telling them to pick one).
    def player_club
      id = FM.state.player_club
      return world.clubs[id] if id
      pbMessage(_INTL("아직 맡은 클럽이 없습니다. 먼저 클럽을 고르세요."))
      choose_club
      FM.state.player_club && world.clubs[FM.state.player_club]
    end

    def invest
      c = player_club or return
      if c.project
        pbMessage(_INTL("{1} Lv{2} 공사 중입니다 ({3} 완공). 한 번에 하나만 지을 수 있습니다.",
                        facility_name(c.project[:target]), c.project[:to], date_text(c.project[:done])))
        return
      end
      opts = Invest.options(c)
      if opts.empty?
        pbMessage(_INTL("지금 올릴 수 있는 시설이 없습니다. 클럽하우스나 도시 크기가 상한을 정합니다."))
        return
      end
      labels = opts.map do |kind, target, from, cost|
        _INTL("{1} Lv{2}→{3} · {4} · {5}주", facility_name(target), from, from + 1, money(cost),
              Build.build_weeks(kind, from))
      end
      i = pbMessage(_INTL("잔고 {1}. 무엇을 지을까요?", money(c.wallet.balance)), labels + [_INTL("취소")], labels.size + 1)
      return if i >= opts.size
      choice = opts[i]
      if c.wallet.balance < choice.last
        pbMessage(_INTL("돈이 모자랍니다 ({1} 필요).", money(choice.last)))
        return
      end
      return unless pbConfirmMessage(_INTL("{1}에 {2}을 쓸까요?", facility_name(choice[1]), money(choice.last)))
      Invest.start(c, choice, date: world.calendar.date, calendar: world.calendar)
      pbMessage(_INTL("공사를 시작했습니다. {1} 완공 예정.", date_text(c.project[:done])))
    end

    # Scouting stays in the home region for now (design 05: travel level sets
    # the range; travel isn't built yet).
    def scout
      c = player_club or return
      unless pbConfirmMessage(_INTL("{1}에 스카우트를 보낼까요? (비용 {2})", region_name(c.region), money(Scout::FEE)))
        return
      end
      cands = world.player_scout(c.region)
      unless cands
        pbMessage(_INTL("스카우트 비용이 모자랍니다."))
        return
      end
      labels = cands.map do |cand|
        m = cand[:mon]
        _INTL("{1} Lv{2} ★{3} · {4}년차 · 전력 {5} · {6}", species_name(m.species), m.level, m.stars,
              m.age + 1, m.rating.round, money(cand[:cost]))
      end
      i = pbMessage(_INTL("스카우트 보고서입니다. 영입할 포켓몬을 고르세요."), labels + [_INTL("영입 안 함")],
                    labels.size + 1)
      return if i >= cands.size
      cand = cands[i]
      if c.wallet.balance < cand[:cost]
        pbMessage(_INTL("돈이 모자랍니다 ({1} 필요).", money(cand[:cost])))
        return
      end
      release = nil
      if c.squad.size >= Build.squad_size(c.clubhouse)
        names = c.squad.map { |m| _INTL("{1} Lv{2} ★{3} · 전력 {4}", species_name(m.species), m.level, m.stars, m.rating.round) }
        j = pbMessage(_INTL("스쿼드가 가득 찼습니다. 누구를 내보낼까요?"), names + [_INTL("취소")], names.size + 1)
        return if j >= c.squad.size
        release = c.squad[j]
      end
      e = Recruit.sign(c, cand, date: world.calendar.date, release: release)
      msg = _INTL("{1}을 영입했습니다 ({2}).", species_name(e[:species]), money(e[:cost]))
      msg += " " + _INTL("{1}은 팀을 떠났습니다.", species_name(e[:released])) if e[:released]
      pbMessage(msg)
    end

    SIZE_NAMES = { 1 => "마을", 2 => "소도시", 3 => "중도시", 4 => "대도시", 5 => "거대도시" }.freeze
    FORM_NAMES = { "SOLO" => "단독", "LONDON" => "런던형", "MILAN" => "밀란형", "LEAGUE" => "리그 도시" }.freeze

    def agenda_text(agenda, target)
      case agenda
      when :expansion then _INTL("도시 확장")
      when :infrastructure then _INTL("{1} 건설", facility_name(target))
      when :tax then target == :raise ? _INTL("세율 인상") : _INTL("세율 인하")
      else facility_name(target)
      end
    end

    def relation_text(r)
      return _INTL("우호") if r >= 0.2
      return _INTL("냉랭") if r <= -0.2
      _INTL("보통")
    end

    def my_city
      c = player_club or return
      show_list(_INTL("내 도시"), city_rows(c.city, c.id))
    end

    def city_rows(city_id, viewer)
      v = View.city(world, city_id, viewer: viewer)
      rows = []
      rows << _INTL("{1} · {2} · {3}", v[:name], _INTL(SIZE_NAMES[v[:size]]), _INTL(FORM_NAMES.fetch(v[:form], v[:form])))
      rows << _INTL("예산 {1} · 세율 ×{2} · 시민 만족도 {3}", money(v[:budget]), format("%.1f", v[:tax_rate]), v[:satisfaction])
      rows << _INTL("교통 Lv{1} · 호텔 Lv{2} · 빈 부지 {3}칸", v[:transport], v[:hotel], v[:free_plots])
      if v[:project]
        what = v[:project][:kind] == :expansion ? _INTL("도시 확장") : facility_name(v[:project][:target])
        rows << _INTL("공사 중: {1} → {2} ({3} 완공)", what, v[:project][:to], date_text(v[:project][:done]))
      end
      rows << _INTL("— 연고 클럽 —")
      v[:clubs].each do |cl|
        rel = cl[:relation].nil? ? _INTL("(나)") : _INTL("관계 {1} ({2})", relation_text(cl[:relation]), format("%+.2f", cl[:relation]))
        rows << _INTL("{1} · 명성 {2} · {3}", cl[:name], cl[:fame], rel)
      end
      rows << _INTL("— 최근 도시 회의 —")
      rows << _INTL("(아직 없음)") if v[:log].empty?
      v[:log].each do |e|
        result = e[:passed] ? _INTL("통과") : _INTL("부결")
        rows << _INTL("{1} {2}: {3} ({4}/{5})", date_text(e[:date]), agenda_text(e[:agenda], e[:target]), result, e[:yes], e[:members])
      end
      rows
    end

    def committee
      c = player_club or return
      v = View.committee(world, c.region)
      unless v
        pbMessage(_INTL("이 지방에는 리그 관리위원회가 없습니다."))
        return
      end
      show_list(_INTL("{1} 리그 관리위원회", region_name(c.region)), committee_rows(c.region))
    end

    def committee_rows(region)
      v = View.committee(world, region)
      rows = []
      rows << _INTL("수도 {1} · 예산 {2}", v[:city], money(v[:budget]))
      v[:facilities].each { |k, lv| rows << _INTL("{1} Lv{2}", facility_name(k), lv) }
      if v[:project]
        rows << _INTL("공사 중: {1} Lv{2} ({3} 완공)", facility_name(v[:project][:target]), v[:project][:to], date_text(v[:project][:done]))
      end
      rows << _INTL("— 위원 —")
      v[:members].each { |m| rows << (m[:gym_rep] ? _INTL("{1} (관장 대표)", m[:name]) : m[:name]) }
      rows << _INTL("— 최근 총회 —")
      rows << _INTL("(아직 없음)") if v[:log].empty?
      v[:log].each do |e|
        result = e[:passed] ? _INTL("통과") : _INTL("부결")
        rows << _INTL("{1} {2}: {3} ({4}/{5})", date_text(e[:date]), facility_name(e[:target]), result, e[:yes], e[:members])
      end
      rows
    end

    def facility_name(key)
      { TRAINING: _INTL("훈련장"), MEDICAL: _INTL("메디컬센터"), SCOUTING: _INTL("스카우팅"),
        DAYCARE: _INTL("키우미집"), SHOP: _INTL("프렌들리숍"), CLUBHOUSE: _INTL("클럽하우스"),
        STADIUM: _INTL("경기장"), TRANSPORT: _INTL("교통"), HOTEL: _INTL("호텔"),
        SIDE_STADIUM: _INTL("사이드 스타디움"), LEAGUE_HQ: _INTL("리그 본부"), HUB: _INTL("지방 교통 허브"),
        BROADCAST: _INTL("방송 센터"), HALL_OF_FAME: _INTL("명예의 전당") }.fetch(key.to_sym, key.to_s)
    end

    def standings
      mine = FM.state.player_club && world.clubs[FM.state.player_club]
      region = (mine && pbConfirmMessage(_INTL("내 지방 순위를 볼까요?"))) ? mine.region : choose_region(_INTL("어느 지방?"))
      return unless region
      show_list(_INTL("{1} 리그", region_name(region)), standings_rows(region))
    end

    def standings_rows(region)
      View.standings(world, region).map do |r|
        mark = r[:id] == FM.state.player_club ? "▶" : " "
        _INTL("{1}{2}. {3}  {4}승 {5}무 {6}패  승점 {7}", mark, r[:pos], r[:name], r[:w], r[:d], r[:l], r[:pts])
      end
    end

    def cups
      c = View.cups(world)
      unless c
        pbMessage(_INTL("대회 대진은 리그가 모두 끝난 뒤에 정해집니다."))
        return
      end
      rows = []
      { pet: "PET", pent: "PENT" }.each do |k, label|
        ko = c[k][:ko]
        champ = ko && ko[:champion] ? world.clubs[ko[:champion]].name : _INTL("진행 중")
        rows << _INTL("{1} (개최: {2}) — 우승: {3}", label, region_name(c[k][:host]), champ)
      end
      pwt = c[:pwt]
      champ = pwt[:ko] && pwt[:ko][:champion] ? world.clubs[pwt[:ko][:champion]].name : _INTL("진행 중")
      rows << _INTL("PWT (개최: {1}) — 우승: {2}", region_name(pwt[:host]), champ)
      (pwt[:swiss] || []).each do |r|
        rows << _INTL("  {1} {2}-{3}", world.clubs[r[:id]].name, r[:wins], r[:losses])
      end
      show_list(_INTL("대회"), rows)
    end

    def mon_line(m)
      rest = m.resting ? _INTL(" · 휴식") : ""
      _INTL("{1} Lv{2} ★{3} · 전력 {4} · 컨디션 {5}{6}", species_name(m.species), m.level, m.stars, m.rating.round,
            m.cond, rest)
    end

    def mode_names
      { ask: _INTL("매번 묻기"), direct: _INTL("직접 전투"), auto: _INTL("자동 진행"), skip: _INTL("결과만 보기") }
    end

    # Design 06 기본값 설정 and 속도 옵션.
    def match_settings
      loop do
        st = FM.state
        rows = [_INTL("기본 방식: {1}", mode_names[st.match_mode]),
                _INTL("빠른 진행(연출 생략): {1}", st.match_fast ? _INTL("켜짐") : _INTL("꺼짐")), _INTL("닫기")]
        case pbMessage(_INTL("관장전과 결승은 기본 방식과 상관없이 항상 묻습니다."), rows, rows.size)
        when 0
          names = State::MATCH_MODES.map { |m| mode_names[m] }
          i = pbMessage(_INTL("경기를 어떻게 진행할까요?"), names + [_INTL("취소")], names.size + 1)
          st.match_mode = State::MATCH_MODES[i] if i < names.size
        when 1 then st.match_fast = !st.match_fast
        else break
        end
      end
    end

    # World.player_match hook: decide how to play (the default mode, or ask
    # when it is :ask or the match is important), then for a direct battle
    # show the opponent's entry of six and let the player pick three; auto
    # fights the best three with the AI on both sides. nil = the formula.
    def player_match(home, away, world, neutral: false, important: false)
      mine = world.player_club
      me, opp = home.id == mine ? [home, away] : [away, home]
      mode = FM.state.match_mode
      if important || mode == :ask
        tag = important ? (neutral ? _INTL("결승") : _INTL("관장전")) : (neutral ? _INTL("대회") : _INTL("리그"))
        modes = %i[direct auto skip]
        i = pbMessage(_INTL("{1}: {2} (전력 {3}) vs {4} (전력 {5})", tag, me.name, me.rating.round, opp.name,
                            opp.rating.round), modes.map { |m| mode_names[m] }, modes.size)
        mode = modes[i] || :skip
      end
      fast = FM.state.match_fast
      r = case mode
          when :direct
            picks = choose_three(me, opp) or return nil
            FM::Battle.fight(me, opp, picks: picks, fast: fast)
          when :auto then FM::Battle.fight(me, opp, auto: true, fast: fast)
          else return nil
          end
      home.id == mine ? r : { res: -r[:res], ko_a: r[:ko_b], ko_b: r[:ko_a] }
    end

    # Poké Manager: both entries of six are shown, then each side picks
    # three. Returns the three Mons in the order picked (first one leads),
    # or nil if the player backs out (the match then goes by the formula).
    def choose_three(me, opp)
      show_list(_INTL("상대 엔트리: {1}", opp.name), opp.entry.map { |m| mon_line(m) })
      entry = me.entry
      picked = []
      loop do
        rows = entry.map do |m|
          i = picked.index(m)
          (i ? "#{i + 1}▶ " : "   ") + mon_line(m)
        end
        done = picked.size == 3 || picked.size == entry.size
        rows << (done ? _INTL("이 3마리로 출전") : _INTL("({1}/3 선택)", picked.size))
        i = pbMessage(_INTL("출전할 3마리를 고르세요 (먼저 고른 포켓몬이 선봉, 다시 고르면 취소)."), rows + [_INTL("결과만 보기")],
                      rows.size + 1)
        return nil if i == rows.size
        if i == entry.size
          return picked if done
          next
        end
        m = entry[i]
        if picked.include?(m) then picked.delete(m)
        elsif picked.size < 3 then picked << m
        end
      end
    end

    # The player's matches this week can be fought for real (FM::Battle);
    # the hook is only on while the player advances time from this menu.
    def advance_week
      FM::World.player_match = method(:player_match) if FM.state.player_club
      events = begin
        FM.advance_days(7)
      ensure
        FM::World.player_match = nil
      end
      id = FM.state.player_club
      lines = events.filter_map do |e|
        case e[:kind]
        when :league_round
          r = e[:results].find { |h, a, _| h == id || a == id } if id
          next unless r
          h, a, res = r
          me_home = h == id
          won = me_home ? res[:res].positive? : res[:res].negative?
          opp = world.clubs[me_home ? a : h].name
          score = me_home ? "#{res[:ko_a]}:#{res[:ko_b]}" : "#{res[:ko_b]}:#{res[:ko_a]}"
          outcome = res[:res].zero? ? _INTL("무") : (won ? _INTL("승") : _INTL("패"))
          _INTL("{1} vs {2}: {3} ({4})", date_text(e[:date]), opp, outcome, score)
        when :built
          _INTL("{1} 완공", facility_name(e[:what])) if e[:club] == id
        when :signed
          _INTL("영입: {1} ({2})", species_name(e[:species]), money(e[:cost])) if e[:club] == id
        when :cup_champion
          _INTL("{1} 우승: {2}", e[:cup].to_s.upcase, world.clubs[e[:club]].name)
        when :city_grown
          _INTL("{1}가 {2}단계로 커졌다", e[:city], e[:size]) if id && world.clubs[id].city == e[:city]
        end
      end
      lines.unshift(_INTL("오늘: {1}", date_text(world.calendar.date)))
      show_list(_INTL("1주 진행"), lines)
    end
  end
end

MenuHandlers.add(:pause_menu, :fm, {
  "name"      => _INTL("FM"),
  "order"     => 5,
  "condition" => proc { next !FM.world.nil? },
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    menu.pbHideMenu
    FM::UI.main
    menu.pbShowMenu
    next false
  }
})
