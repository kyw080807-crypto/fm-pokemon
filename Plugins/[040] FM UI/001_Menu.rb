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
                    _INTL("재정·대출"), _INTL("코치"), _INTL("친선 투어"), _INTL("키우미집"), _INTL("간호사"), _INTL("기록·명예의 전당"), _INTL("상점·지닌 물건"), _INTL("닫기")]
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
        when 10 then finance
        when 11 then coaches
        when 12 then tour
        when 13 then daycare
        when 14 then nurses
        when 15 then records
        when 16 then items_menu
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
      loop do
        cmds = [_INTL("클럽 정보"), _INTL("부상 관리 (무리 출전)"), _INTL("지방 이적"), _INTL("칭호"), _INTL("다음 상대 분석"), _INTL("닫기")]
        case pbMessage(_INTL("내 클럽"), cmds, cmds.size)
        when 0 then show_list(_INTL("내 클럽"), my_club_rows(id))
        when 1 then injury_room(world.clubs[id])
        when 2 then region_move(world.clubs[id])
        when 3 then title_menu(world.clubs[id])
        when 4 then analysis
        else break
        end
      end
    end

    TITLE_NAMES = { legend: "살아있는 전설", worldnow: "세계 챔피언", dynasty: "{1}연패 왕조", leaguenow: "리그 제패자",
                    reborn: "부활한 왕", exworld: "전 세계 챔피언", fallen: "몰락한 왕", legowner: "전설의 주인", surge: "돌풍",
                    crownless: "무관의 제왕", multi: "리그 {1}회 우승", champ1: "리그 우승 경험", mono: "{1} 마스터", mentor: "명장",
                    veteran: "노장", challenger: "PWT 도전자", rising: "유망주" }.freeze

    def title_name(t)
      n = t[:k] == :mono ? type_name(t[:n]) : t[:n]
      _INTL(TITLE_NAMES.fetch(t[:k], t[:k].to_s), n)
    end

    # The profile's title chips: the player picks the one shown.
    def title_menu(c)
      ts = Titles.of(world, c)
      if ts.empty?
        pbMessage(_INTL("아직 칭호가 없습니다. 리그 성적과 PWT, 명예의 전당으로 칭호가 붙습니다."))
        return
      end
      rows = ts.map { |t| (Titles.main(world, c)[:k] == t[:k] ? "▶" : "") + title_name(t) } + [_INTL("자동 (첫 번째)")]
      i = pbMessage(_INTL("이름 옆에 보일 칭호를 고르세요."), rows + [_INTL("닫기")], rows.size + 1)
      return if i > ts.size
      world.my_title = i < ts.size ? ts[i][:k] : nil
    end

    # Poké Manager 지방 이적 (movePanel).
    def region_move(c)
      if c.move_to
        return unless pbConfirmMessage(_INTL("{1} 지방으로 이적 예정입니다 (새 시즌이 시작될 때). 신청을 취소할까요?", region_name(c.move_to)))
        Transfer.cancel(c)
        pbMessage(_INTL("지방 이적 신청을 취소했습니다."))
        return
      end
      if Transfer.why_not(world, c) == :moved
        pbMessage(_INTL("이번 시즌에 이미 지방을 옮겼습니다."))
        return
      end
      now = Transfer.now?(world)
      rs = world.regions - [c.region]
      rows = rs.map { |r| _INTL("{1} (본거지 포켓몬 {2}마리)", region_name(r), Transfer.home_count(world, c, r)) }
      head = _INTL("지금 {1} 지방. 포켓몬·자금·우승 기록은 그대로, 명성 −30%, 훈련장·스카우팅 Lv1, 경기장은 임대로 돌아갑니다.\n" \
                   "새 지방에서 가장 약한 일반 트레이너와 연고 도시를 맞바꿉니다. 한 시즌에 한 번만.", region_name(c.region))
      i = pbMessage(head, rows + [_INTL("취소")], rows.size + 1)
      return if i >= rs.size
      to = rs[i]
      o = Transfer.partner(world, c, to)
      fame = (c.fame * (1 - Transfer::FAME_CUT)).round
      msg = _INTL("{1} → {2}: 명성 {3} → {4}, 새 연고 도시 {5}. {6}", region_name(c.region), region_name(to), c.fame.round, fame,
                  o ? world.cities[o.city]&.name || o.city : "-",
                  now ? _INTL("리그 개막 전이라 바로 옮깁니다. 이적할까요?") : _INTL("시즌 중이라 새 시즌부터 옮깁니다. 신청할까요?"))
      return unless pbConfirmMessage(msg)
      case Transfer.request(world, c, to)
      when :moved then pbMessage(_INTL("{1} 지방으로 옮겼습니다. 새 리그가 다시 편성되었습니다.", region_name(to)))
      when :requested then pbMessage(_INTL("{1} 지방 이적을 신청했습니다. 새 시즌이 시작될 때 옮깁니다.", region_name(to)))
      end
    end

    # Poké Manager 무리 출전: a red-injured mon kept in the entry, at speed
    # and main attack -1 more, and it may get worse if it plays.
    def injury_room(c)
      loop do
        reds = c.squad.select(&:red?)
        if reds.empty?
          pbMessage(_INTL("출전할 수 없는 부상 포켓몬이 없습니다."))
          return
        end
        rows = reds.map do |m|
          _INTL("{1}{2} · {3} {4}주", m.ptp ? _INTL("[무리 출전] ") : "", species_name(m.species), injury_name(m.injd[:k]), m.inj)
        end
        i = pbMessage(_INTL("무리 출전시키면 엔트리에 남지만 스피드·주 공격이 한 단계씩 더 떨어지고, 뛰면 부상이 악화될 수 있습니다 " \
                            "(쓰러지면 45%, 아니면 25%)."), rows + [_INTL("닫기")], rows.size + 1)
        return if i >= reds.size
        m = reds[i]
        m.ptp = !m.ptp
        c.refresh_rating
      end
    end

    def my_club_rows(id)
      c = View.club(world, id)
      rows = []
      rows << _INTL("{1} · {2} · 순위 {3}위", c[:name], region_name(c[:region]), c[:position] || "-")
      rows << _INTL("잔고 {1} · 명성 {2} · 전력 {3}", money(c[:balance]), c[:fame], c[:rating])
      rows << _INTL("대출 잔액 {1} (매주 {2} 상환)", money(c[:loan][:owed]), money(c[:loan][:part])) if c[:loan]
      rows << _INTL("재정 위기: {1}", crisis_name(c[:crisis])) if c[:crisis]
      club = world.clubs[id]
      if id == world.player_club
        rows << goal_row(club) if club.goal && club.goal[:year] == world.calendar.year
        t = Titles.main(world, club)
        rows << _INTL("칭호: {1}", t ? title_name(t) : _INTL("(아직 없음)"))
        if (rv = Rival.current(world))
          rows << _INTL("라이벌 {1} · 올 시즌 {2}승 {3}패", world.clubs[rv[:club]].name, rv[:w], rv[:l])
        end
        v = Fans.of(club)
        rows << _INTL("팬 만족도 {1}/100 ({2}) · 입장료 {3} (적정가 {4})", v.round, fan_mood_name(Fans.mood(v)),
                      money(world.ticket_price), money(Economy.price(club.fame)))
      end
      fac = c[:facilities].map { |k, lv| "#{facility_name(k)} Lv#{lv}" }.join(" · ")
      rows << _INTL("클럽하우스 Lv{1} · 경기장 Lv{2} · 이번 시즌 영입 {3}/{4}", c[:clubhouse], c[:stadium], c[:signs][:used],
                    c[:signs][:limit])
      rows << fac unless fac.empty?
      if c[:project]
        rows << _INTL("공사 중: {1} Lv{2} ({3} 완공)", facility_name(c[:project][:target]), c[:project][:to],
                      date_text(c[:project][:done]))
      end
      if c[:sponsor]
        rows << _INTL("스폰서: {1} (연 {2})", c[:sponsor][:name] || _INTL("지역 상공회"), money(c[:sponsor][:base]))
      end
      if (sp = c[:specialty])
        rows << _INTL("{1} 전문 · 다른 타입 스쿼드 {2}/{3} · 엔트리 {4}/{5}", type_name(sp[:type]), sp[:others], sp[:cap],
                      sp[:entry_others], sp[:entry_cap])
      end
      rows << _INTL("— 스쿼드 {1}마리 · 홈그로운 {2} (최소 {3}) · 외부 {4}/{5} —", c[:squad].size, c[:homegrown],
                    Recruit::HG_MIN, c[:squad].size - c[:homegrown], c[:foreign_cap])
      c[:squad].each do |m|
        rest = injury_tag(m[:injury], m[:rehab]) || (m[:resting] ? _INTL(" · 휴식") : "")
        rest += debuff_tag(m[:species], m[:debuffs])
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

    CRISIS_NAMES = { warning: "경고 (잔고 마이너스)", austerity: "긴축 (새 공사·스카우트·영입 금지)",
                     pressure: "해고 압박 (구제금융 뒤 다시 적자)" }.freeze

    def crisis_name(stage) = _INTL(CRISIS_NAMES.fetch(stage, stage.to_s))

    # 긴축 or worse: nothing new is started (design 04 재정 위기 단계).
    def austerity_blocked?(club)
      return false unless Credit.austerity?(club)
      pbMessage(_INTL("재정 위기({1})라 새로 시작할 수 없습니다. 잔고를 회복하거나 대출을 검토하세요.", crisis_name(club.crisis)))
      true
    end

    # Design 04 대출: one loan at a time, up to fame x ₽5,000, repaid weekly.
    # viewRecords: PWT champions, the region's champions and KO kings,
    # records, and the club's own hall of fame.
    def records
      h = Hof.of(world)
      c = player_club
      region = c ? c.region : world.regions.first
      name = ->(id) { world.clubs[id]&.name || id.to_s }
      loop do
        rec = h[:records]
        best = rec[:"pts_#{region}"]
        head = _INTL("{1} 리그 최다 승점: {2}", region_name(region), best ? _INTL("{1} {2} · {3}년차", best[:pts], name.(best[:club]), best[:year]) : "-")
        k = rec[:ko]
        head += "\n" + _INTL("한 시즌 최다 KO: {1}", k ? _INTL("{1} {2}의 {3} · {4}년차", k[:ko], name.(k[:club]), species_name(k[:species]), k[:year]) : "-")
        cmds = [_INTL("PWT 역대 우승"), _INTL("{1} 리그 역대 우승", region_name(region)), _INTL("{1} 시즌 KO왕", region_name(region)),
                _INTL("내 클럽 명예의 전당"), _INTL("지방 바꾸기"), _INTL("닫기")]
        rows = case pbMessage(head, cmds, cmds.size)
               when 0 then h[:world].map { |x| _INTL("{1}년차 {2} (준우승 {3})", x[:year], name.(x[:club]), x[:runner_up] ? name.(x[:runner_up]) : "-") }
               when 1 then h[:league].select { |x| x[:region] == region }.map { |x| _INTL("{1}년차 {2} · 승점 {3} ({4}-{5})", x[:year], name.(x[:club]), x[:pts], x[:w], x[:l]) }
               when 2 then h[:ko].select { |x| x[:region] == region }.map { |x| _INTL("{1}년차 {2}의 {3} {4}KO", x[:year], name.(x[:club]), species_name(x[:species]), x[:ko]) }
               when 3
                 ((c && c.hof) || []).map do |x|
                   _INTL("{1} ★{2} · {3}~{4}년차 · {5}KO · 우승 {6} · 수상 {7}{8}", species_name(x[:species]), x[:stars], x[:y0], x[:y1], x[:ko],
                         x[:titles].size, x[:awards].size, x[:kind] == :legend ? _INTL(" · 전설") : "")
                 end
               when 4
                 rs = world.regions
                 j = pbMessage(_INTL("어느 지방?"), rs.map { |r| region_name(r) } + [_INTL("취소")], rs.size + 1)
                 region = rs[j] if j < rs.size
                 next
               else break
               end
        if rows.empty?
          pbMessage(_INTL("아직 기록이 없습니다."))
        else
          rows.each_slice(8) { |part| pbMessage(part.join("\n")) }
        end
      end
    end

    def goal_text(world, t, region)
      kind, = Goals.label(world, t, region)
      case kind
      when :title then _INTL("리그 우승")
      when :pwt then _INTL("PWT 진출권 ({1}위 이내)", t)
      when :top then _INTL("상위권 ({1}위 이내)", t)
      when :upper_half then _INTL("상위 절반 ({1}위 이내)", t)
      when :mid then _INTL("중위권 ({1}위 이내)", t)
      else _INTL("{1}위 이내", t)
      end
    end

    # goalBar
    def goal_row(club)
      g = club.goal
      label = goal_text(world, g[:t], g[:region])
      if g[:done]
        return g[:ok] ? _INTL("시즌 목표 {1}: 달성 ({2}위, 보너스 {3})", label, g[:pos], money(g[:paid])) :
                        _INTL("시즌 목표 {1}: 실패 ({2}위)", label, g[:pos])
      end
      _INTL("시즌 목표 {1} · 달성 보너스 {2}+", label, money(g[:bonus]))
    end

    FAN_MOODS = { ecstatic: "열광", happy: "만족", normal: "보통", unhappy: "불만", angry: "분노" }.freeze
    FAN_WHY = { win: "경기 승리", loss: "경기 패배", draw: "무승부", upset_win: "이변의 승리", upset_loss: "약체에게 패배",
                series_win: "시리즈 승리", series_loss: "시리즈 패배", dear_tickets: "비싼 입장료", cheap_tickets: "저렴한 입장료",
                price_up: "입장료 인상", price_down: "입장료 인하", goal_met: "시즌 목표 달성", goal_missed: "시즌 목표 실패",
                rival_win: "라이벌전 승리", rival_loss: "라이벌전 패배", new_region: "새 지방 팬들과 첫 만남", tv: "방송 출연",
                signing: "팬 사인회", no_signing: "사인회 거절", interview: "인터뷰", press: "기자회견", press_sorry: "기자회견 사과",
                press_excuse: "기자회견 변명", press_skip: "기자회견 불참", boast_loss: "기자회견 큰소리 후 패배" }.freeze

    def fan_mood_name(k) = _INTL(FAN_MOODS[k])

    # fanPanel and the price picker (fsSetPrice).
    def fans_and_price(c)
      loop do
        v = Fans.of(c)
        ref = Economy.price(c.fame)
        head = _INTL("팬 만족도 {1}/100 ({2}) · 관중 ×{3} · 굿즈 ×{4}\n입장료 {5} · 적정가 {6} · 상한 {7}", v.round,
                     fan_mood_name(Fans.mood(v)), format("%.2f", Fans.att_mul(c)), format("%.2f", Fans.merch_mul(c)),
                     money(world.ticket_price), money(ref), money(Fans.cap(c)))
        log = (c.fs_log || []).first(4).map { |x| _INTL("{1} {2}", _INTL(FAN_WHY[x[:why]] || x[:why].to_s), format("%+.1f", x[:d])) }
        head += "\n" + log.join(" · ") unless log.empty?
        prices = Fans::PRICES
        rows = prices.map { |p| p == world.ticket_price ? _INTL("[{1}]", money(p)) : money(p) }
        i = pbMessage(head, rows + [_INTL("닫기")], rows.size + 1)
        break if i >= prices.size
        r = Fans.set_price(c, world, prices[i], date: world.calendar.date)
        if r == :capped
          pbMessage(_INTL("팬들의 반발이 커서 입장료를 {1}보다 올릴 수 없습니다 (팬 만족도 {2}).", money(Fans.cap(c)), v.round))
        end
      end
    end

    def finance
      c = player_club or return
      loop do
        limit = Credit.limit(c)
        head = if c.loan
                 _INTL("대출 잔액 {1} · 매주 {2} 상환 (이자 주 {3}%)", money(c.loan[:owed]), money(c.loan[:part]),
                       format("%.2f", Credit::LOAN_RATE * 100))
               else
                 _INTL("대출 한도 {1} (명성 × {2}) · {3}주 분할 상환, 이자 주 {4}%", money(limit), money(Credit::LIMIT_PER_FAME),
                       Credit::TERM_WEEKS, format("%.2f", Credit::LOAN_RATE * 100))
               end
        head += "\n" + _INTL("재정 위기: {1}", crisis_name(c.crisis)) if c.crisis
        cmds = [_INTL("스폰서 계약"), _INTL("팬 만족도·입장료")]
        cmds << _INTL("대출 받기") unless c.loan
        cmds << _INTL("전액 상환 ({1})", money(c.loan[:owed])) if c.loan
        cmds << _INTL("닫기")
        i = pbMessage(head, cmds, cmds.size)
        case cmds[i]
        when _INTL("스폰서 계약") then sponsor_menu
        when _INTL("팬 만족도·입장료") then fans_and_price(c)
        when _INTL("대출 받기")
          unless Credit.can_borrow?(c, [limit, 1].max)
            pbMessage(_INTL("지금은 대출을 받을 수 없습니다."))
            next
          end
          amounts = [0.25, 0.5, 1.0].map { |f| (limit * f / 10_000).floor * 10_000 }.select(&:positive?).uniq
          j = pbMessage(_INTL("얼마나 빌릴까요?"), amounts.map { |a| money(a) } + [_INTL("취소")], amounts.size + 1)
          next if j >= amounts.size
          Credit.borrow(c, amounts[j], date: world.calendar.date)
          pbMessage(_INTL("{1}을 빌렸습니다. 매주 {2}씩 갚습니다.", money(amounts[j]), money(c.loan[:part])))
        when nil, _INTL("닫기") then break
        else
          if c.wallet.balance < c.loan[:owed]
            pbMessage(_INTL("잔고가 모자랍니다."))
          elsif pbConfirmMessage(_INTL("{1}를 지금 갚을까요?", money(c.loan[:owed])))
            Credit.repay_all(c, date: world.calendar.date)
          end
        end
      end
    end

    STAT_NAMES = %w[체력 공격 방어 특공 특방 스피드].freeze

    EGG_NAMES = { "Monster" => "괴수", "Water1" => "수중1", "Water2" => "수중2", "Water3" => "수중3", "Bug" => "벌레",
                  "Flying" => "비행", "Field" => "육상", "Fairy" => "요정", "Grass" => "식물", "Humanlike" => "인간형",
                  "Mineral" => "광물", "Amorphous" => "부정형", "Ditto" => "메타몽", "Dragon" => "드래곤",
                  "Undiscovered" => "미발견" }.freeze
    COMPAT_WHY = { pick_two: "두 마리를 골라야 합니다.", legend: "전설·준전설은 알을 낳지 않습니다.",
                   undiscovered: "알을 낳을 수 없는 포켓몬입니다 (미발견 그룹).", two_dittos: "메타몽끼리는 알을 낳지 않습니다.",
                   genderless: "성별이 없는 포켓몬은 메타몽하고만 알을 낳습니다.", same_gender: "수컷과 암컷이어야 합니다.",
                   egg_group: "알 그룹이 다릅니다." }.freeze

    def gender_mark(mon) = { M: "♂", F: "♀", N: "" }[Daycare.gender(world.species, mon)]

    def dc_line(mon)
      groups = Daycare.eggs(world.species, mon).map { |g| _INTL(EGG_NAMES.fetch(g, g)) }.join("·")
      _INTL("{1}{2} ★{3} · {4}", species_name(mon.species), gender_mark(mon), mon.stars, groups)
    end

    # Poké Manager 키우미집: retired mons (not coaching) and Ditto breed.
    def daycare
      c = player_club or return
      unless Daycare.built?(c)
        pbMessage(_INTL("키우미집이 없습니다. 시설 투자에서 키우미집을 지으면 은퇴한 포켓몬끼리 알을 낳게 할 수 있습니다."))
        return
      end
      loop do
        st = Daycare.state(c)
        head = _INTL("키우미집 · 짝 {1}/{2} · 알 {3}/{4} · 짝마다 주 {5}", st[:pairs].size, Daycare.slots(c), st[:eggs].size,
                     Daycare.egg_max(c), money(Daycare::FEE))
        cmds = [_INTL("짝 짓기"), _INTL("짝 풀기 ({1})", st[:pairs].size), _INTL("알 ({1})", st[:eggs].size), _INTL("닫기")]
        case pbMessage(head, cmds, cmds.size)
        when 0 then daycare_pair(c)
        when 1
          next if st[:pairs].empty?
          rows = st[:pairs].map { |x, y| _INTL("{1} × {2}", dc_line(x), dc_line(y)) }
          i = pbMessage(_INTL("어느 짝을 풀까요?"), rows + [_INTL("취소")], rows.size + 1)
          st[:pairs].delete_at(i) if i < rows.size
        when 2
          rows = st[:eggs].map do |e|
            wait = e[:waiting] ? _INTL(" · 자리가 없어 기다리는 중") : ""
            _INTL("{1}의 알 · {2} 부화{3}", species_name(e[:mon].species), date_text(e[:hatch]), wait)
          end
          show_list(_INTL("키우미집 알"), rows)
        else break
        end
      end
    end

    def daycare_pair(c)
      st = Daycare.state(c)
      if st[:pairs].size >= Daycare.slots(c)
        pbMessage(_INTL("짝 자리가 없습니다 (키우미집 단계를 올리면 늘어납니다)."))
        return
      end
      pool = Daycare.candidates(world.species, c).reject { |m| Daycare.paired?(c, m) }
      if pool.size < 2
        pbMessage(_INTL("맡길 포켓몬이 모자랍니다. 은퇴한 포켓몬(코치 제외)이나 메타몽이 필요합니다."))
        return
      end
      i = pbMessage(_INTL("첫 번째 포켓몬"), pool.map { |m| dc_line(m) } + [_INTL("취소")], pool.size + 1)
      return if i >= pool.size
      rest = pool - [pool[i]]
      j = pbMessage(_INTL("짝지을 포켓몬"), rest.map { |m| dc_line(m) } + [_INTL("취소")], rest.size + 1)
      return if j >= rest.size
      a, b = pool[i], rest[j]
      cp = Daycare.compat(world.species, a, b)
      unless cp[:ok]
        pbMessage(_INTL(COMPAT_WHY.fetch(cp[:why], "알을 낳을 수 없습니다.")))
        return
      end
      baby = Daycare.baby_species(world.species, Daycare.mother(world.species, a, b))
      return unless pbConfirmMessage(_INTL("궁합 {1} (주에 {2}%). {3}의 알을 기다릴까요? (짝마다 주 {4})",
                                           cp[:rate] >= 0.1 ? _INTL("아주 좋음") : cp[:rate] >= 0.06 ? _INTL("좋음") : _INTL("그럭저럭"),
                                           (cp[:rate] * Daycare.rate_mul(c) * 100).round, species_name(baby), money(Daycare::FEE)))
      a.coach = b.coach = false
      st[:pairs] << [a, b]
    end

    # Poké Manager 원정 친선 투어: a week without official matches, for fees.
    def tour
      c = player_club or return
      loop do
        busy = world.official_match_week?(c)
        head = _INTL("공식 경기가 없는 주에 엔트리가 다른 지방을 돌며 출전료를 법니다. 예상 출전료 {1}.\n" \
                     "엔트리 컨디션 −{2}, 그 주는 훈련·휴식 없음.", money(Tour.pay(c)), Tour::COND)
        head += "\n" + _INTL("이번 주는 공식 경기가 있어 갈 수 없습니다.") if busy
        cmds = [world.tour_next ? _INTL("다음 주 투어 취소") : _INTL("다음 주 투어 신청"),
                world.tour_auto ? _INTL("매주 자동 투어: 켜짐") : _INTL("매주 자동 투어: 꺼짐"), _INTL("닫기")]
        case pbMessage(head, cmds, cmds.size)
        when 0 then world.tour_next = !world.tour_next
        when 1 then world.tour_auto = !world.tour_auto
        else break
        end
      end
    end

    # Poké Manager coaches: retired mons take a slot (training level) and
    # speed up growth; a coach eats what it ate when it retired.
    def coaches
      c = player_club or return
      loop do
        pool = world.species
        slots = Coach.slots(c)
        staff = c.coaches
        head = _INTL("코치 {1}/{2}자리 (훈련장 단계) · 주 식비 {3}", staff.size, slots, money(Coach.weekly_food(c)))
        if staff.any?
          fx = Coach.staff(c, pool)
          head += "\n" + _INTL("숙련 성장 +{1}% · 노력치 +{2}% (같은 타입 포켓몬은 더)", ((fx[:lv] - 1) * 100).round,
                               ((fx[:ev] - 1) * 100).round)
        end
        list = c.retired.sort_by { |m| [m.coach ? 0 : 1, -Coach.quality(m)] }
        if list.empty?
          pbMessage(_INTL("은퇴한 포켓몬이 없습니다. 은퇴하거나 교체된 포켓몬이 코치 후보가 됩니다."))
          return
        end
        rows = list.map do |m|
          q = Coach.quality(m)
          mark = m.coach ? _INTL("[코치] ") : m.nurse ? _INTL("[간호] ") : ""
          food = m.food_fixed || Economy.food(ovr: Economy.ovr(m.rating), fame: c.fame)
          _INTL("{1}{2} {3}등급({4}) · {5} 전문 · KO {6} · 식비 {7}", mark, species_name(m.species), Coach.grade(q),
                format("%.1f", q), STAT_NAMES[Coach.spec(pool, m)], m.ko, money(food))
        end
        i = pbMessage(head, rows + [_INTL("닫기")], rows.size + 1)
        break if i >= list.size
        m = list[i]
        if m.coach
          m.coach = false
          pbMessage(_INTL("{1}이 코치에서 물러났습니다.", species_name(m.species)))
        elsif Daycare.paired?(c, m)
          pbMessage(_INTL("{1}은(는) 키우미집에 맡겨져 있습니다. 먼저 짝을 풀어 주세요.", species_name(m.species)))
        elsif m.nurse
          pbMessage(_INTL("{1}은(는) 간호사로 일하고 있습니다. 먼저 간호사에서 내려 주세요.", species_name(m.species)))
        elsif staff.size >= slots
          pbMessage(_INTL("코치 자리가 없습니다. 훈련장 단계를 올리면 자리가 늘어납니다."))
        else
          m.coach = true
          m.food_fixed ||= Economy.food(ovr: Economy.ovr(m.rating), fame: c.fame)
          pbMessage(_INTL("{1}이 코치로 합류했습니다 ({2}등급 · {3} 전문).", species_name(m.species),
                          Coach.grade(Coach.quality(m)), STAT_NAMES[Coach.spec(pool, m)]))
        end
      end
    end

    # Poké Manager nurses (nursePanel): the Happiny / Chansey / Audino /
    # Igglybuff lines, active (70%) or retired, at the medical center.
    def nurses
      c = player_club or return
      loop do
        ns = Nurse.of(c)
        n = Nurse.pow(c)
        head = _INTL("간호사 {1}/{2}자리 (메디컬 센터 Lv4·Lv8에 한 자리씩) · 간호 {3}/{4} · 주 식비 {5}", ns.size, Nurse.slots(c),
                     format("%.1f", n), Nurse::POW_MAX, money(Nurse.weekly_food(c)))
        if n.positive?
          head += "\n" + _INTL("부상 회복 한 주 더 {1}% · 재활 중 부상 위험 −{2}%{3}", ([0.6, 0.12 * n].min * 100).round,
                               ([0.25, 0.06 * n].min * 100).round, Nurse.short_rehab?(n) ? _INTL(" · 재활 1주") : "")
        end
        list = (c.squad + c.retired).select { |m| Nurse.can?(m) }.sort_by { |m| [m.nurse ? 0 : 1, -Nurse.quality(m)] }
        if list.empty?
          pbMessage(_INTL("간호사가 될 포켓몬(핑복·럭키·해피너스·다부니·푸린 계열)이 없습니다. 스카우트의 특별 스카우팅으로 찾을 수 있습니다."))
          return
        end
        rows = list.map do |m|
          q = Nurse.quality(m)
          ret = Nurse.retired?(c, m)
          mark = m.nurse ? _INTL("[간호] ") : ""
          _INTL("{1}{2} {3}등급({4}) · {5}", mark, species_name(m.species), Nurse.grade(q), format("%.1f", q),
                ret ? _INTL("은퇴 · 식비 {1}", money(Nurse.food(c, m))) : _INTL("현역 겸임 (효과 70%)"))
        end
        i = pbMessage(head, rows + [_INTL("닫기")], rows.size + 1)
        break if i >= list.size
        m = list[i]
        case Nurse.toggle(c, m)
        when :off then pbMessage(_INTL("{1}, 간호사 일을 내려놓았습니다.", species_name(m.species)))
        when :on
          pbMessage(_INTL("{1}, 메디컬 센터 간호사로 임명 ({2}등급).", species_name(m.species), Nurse.grade(Nurse.quality(m))))
        when :busy then pbMessage(_INTL("{1}은(는) 코치이거나 키우미집에 있습니다.", species_name(m.species)))
        when :full then pbMessage(_INTL("간호사 자리가 없습니다. 메디컬 센터를 Lv4·Lv8로 올리면 자리가 늘어납니다."))
        end
      end
    end

    def invest
      c = player_club or return
      return if austerity_blocked?(c)
      if c.project
        pbMessage(_INTL("{1} Lv{2} 공사 중입니다 ({3} 완공). 한 번에 하나만 지을 수 있습니다.",
                        facility_name(c.project[:target]), c.project[:to], date_text(c.project[:done])))
        return
      end
      opts = Invest.options(c)
      renov = Aging::CLUB.select { |b| c.facilities[b].to_i >= 1 && !(c.project && c.project[:target] == b) }
      if opts.empty? && renov.empty?
        pbMessage(_INTL("지금 올릴 수 있는 시설이 없습니다. 클럽하우스나 도시 크기가 상한을 정합니다."))
        return
      end
      labels = opts.map do |kind, target, from, cost|
        _INTL("{1} Lv{2}→{3} · {4} · {5}주", facility_name(target), from, from + 1, money(cost),
              Build.build_weeks(kind, from))
      end
      labels += renov.map do |b|
        a = Aging.age(c, b)
        lv = c.facilities[b]
        _INTL("{1} Lv{2} 보수 · {3} (노후 {4}/{5}주)", facility_name(b), lv, money(Aging.renov_cost(a, lv)), a[:w], Aging.life(lv))
      end
      i = pbMessage(_INTL("잔고 {1}. 무엇을 지을까요? (시설은 Lv1 {2}주 ~ Lv10 {3}주가 지나면 낡아 한 단계 떨어집니다)",
                          money(c.wallet.balance), Aging.life(1), Aging.life(10)), labels + [_INTL("취소")], labels.size + 1)
      return if i >= labels.size
      if i >= opts.size
        b = renov[i - opts.size]
        cost = Aging.renov_cost(Aging.age(c, b), c.facilities[b])
        return unless pbConfirmMessage(_INTL("{1}을 {2}에 보수할까요? 노후도가 0이 되고, 다음 보수·재건 비용은 25% 오릅니다.",
                                             facility_name(b), money(cost)))
        if Aging.renovate(c, b, date: world.calendar.date)
          pbMessage(_INTL("{1}을 보수했습니다.", facility_name(b)))
        else
          pbMessage(_INTL("돈이 모자랍니다 ({1} 필요).", money(cost)))
        end
        return
      end
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
    TYPE_NAMES = {
      "NORMAL" => "노말", "FIRE" => "불꽃", "WATER" => "물", "ELECTRIC" => "전기", "GRASS" => "풀", "ICE" => "얼음",
      "FIGHTING" => "격투", "POISON" => "독", "GROUND" => "땅", "FLYING" => "비행", "PSYCHIC" => "에스퍼", "BUG" => "벌레",
      "ROCK" => "바위", "GHOST" => "고스트", "DRAGON" => "드래곤", "DARK" => "악", "STEEL" => "강철", "FAIRY" => "페어리"
    }.freeze

    def type_name(t) = _INTL(TYPE_NAMES.fetch(t.to_s, t.to_s))

    # signBlock texts (Poké Manager).
    def sign_block_text(why, club)
      case why
      when :homegrown
        _INTL("홈그로운 규정: 다른 지방 출신은 {1}마리까지입니다 (스쿼드의 {2}마리 이상이 {3} 출신). 다른 지방 출신을 내보내면 영입할 수 있습니다.",
              Recruit.foreign_cap(club), Recruit::HG_MIN, region_name(club.region))
      when :family then _INTL("같은 진화 계열의 포켓몬이 이미 스쿼드에 있습니다.")
      when :sub_legend then _INTL("준전설은 1마리만 둘 수 있습니다.")
      when :legend then _INTL("전설은 클럽마다 1마리, 세계에 한 마리뿐입니다 (이미 주인이 있거나 전설이 있음).")
      when :specialty
        _INTL("전문 타입 규정: {1} 타입이 아닌 포켓몬은 스쿼드에 {2}마리까지입니다.", type_name(Specialty.of(club)),
              Specialty.other_cap(club))
      end
    end

    # PWT champion's gift: a free legend, outside the signing limit.
    def legend_gift(c)
      g = world.legend_gift or return
      m = g[:mon]
      return unless pbConfirmMessage(_INTL("PWT 우승 선물: 전설 {1} Lv{2}이(가) 함께하려 합니다 (무료, {3}까지). 데려올까요?\n" \
                                           "전설은 상징이라 훈련할 수 없고 개체값·노력치가 0이지만, 굿즈 수입 ×{4}·명성이 오르고 {5}시즌 함께합니다.",
                                           species_name(m.species), m.level, date_text(g[:until]), Legend::MERCH_MUL, Legend::LEG_YEARS))
      if Legend.block?(world, c, m.species)
        pbMessage(sign_block_text(:legend, c))
        return
      end
      release = nil
      if c.squad.size >= Build.squad_size(c.clubhouse)
        names = c.squad.map { |x| _INTL("{1} Lv{2} ★{3} · 전력 {4}", species_name(x.species), x.level, x.stars, x.rating.round) }
        j = pbMessage(_INTL("스쿼드가 가득 찼습니다. 누구를 내보낼까요?"), names + [_INTL("취소")], names.size + 1)
        return if j >= c.squad.size
        release = c.squad[j]
      end
      pbMessage(_INTL("전설 {1}이(가) 합류했습니다!", species_name(m.species))) if world.claim_legend_gift(release: release)
    end

    # Poké Manager's scouting office (FM::Scouting): scouts report the
    # next week and candidates wait in a list for a few weeks.
    def scout
      c = player_club or return
      legend_gift(c) if world.legend_gift
      loop do
        st = Scouting.state(world)
        year = world.calendar.year
        limit = Recruit.sign_limit(c, year)
        used = limit - Recruit.signs_left(c, year)
        extra = []
        mul = Recruit.recovery_mul(c, year)
        extra << _INTL("하위권 영입 할인 {1}%", ((1 - mul) * 100).round) if mul < 1
        extra << _INTL("하위권 스카우트 보너스") if Recruit.scout_bonus(c, year).positive?
        nxt = st[:next_passive] ? date_text(st[:next_passive]) : _INTL("곧")
        head = _INTL("스카우트 {1}/{2}명 파견 중 · 후보 {3}마리 · 이번 시즌 영입 {4}/{5}\n정기 보고: {6}",
                     st[:assign].size, Scouting.max_scouts(c), st[:cands].size, used, limit, nxt)
        head += "\n" + extra.join(" · ") unless extra.empty?
        cmds = [_INTL("지방에 파견 ({1})", money(Scouting::FEE)), _INTL("타입별 스카우팅 ({1})", money(Scouting::TYPE_FEE)),
                _INTL("특별 스카우팅 ({1})", money(Scouting::SPEC_FEE)), _INTL("후보 명단 ({1})", st[:cands].size), _INTL("닫기")]
        case pbMessage(head, cmds, cmds.size)
        when 0 then dispatch_scout(c)
        when 1 then dispatch_scout(c, typed: true)
        when 2 then special_scout(c)
        when 3 then candidate_list(c)
        else break
        end
      end
    end

    def dispatch_scout(c, typed: false)
      return if austerity_blocked?(c)
      regions = Scouting.regions(world, c)
      type = nil
      if typed
        types = TYPE_NAMES.keys
        i = pbMessage(_INTL("어떤 타입을 찾을까요? (진화하면 그 타입이 되는 포켓몬 포함)"), types.map { |t| type_name(t) } + [_INTL("취소")],
                      types.size + 1)
        return if i >= types.size
        type = types[i]
      end
      if typed
        where = regions.size == 1 ? region_name(c.region) : _INTL("전체 지방")
        where_note = regions.size == 1 ? _INTL(" (교통 Lv5부터 전체 지방)") : ""
        return unless pbConfirmMessage(_INTL("{1} 타입 스카우트를 {2}{3}에 보낼까요? ({4})", type_name(type), where, where_note,
                                             money(Scouting::TYPE_FEE)))
        target = [nil, where]
      else
        opts = regions.map { |r| [r, region_name(r)] }
        j = pbMessage(regions.size == 1 ? _INTL("교통 Lv5부터 다른 지방에도 보낼 수 있습니다. 어디로 보낼까요?") : _INTL("어디로 보낼까요?"),
                      opts.map(&:last) + [_INTL("취소")], opts.size + 1)
        return if j >= opts.size
        target = opts[j]
      end
      case world.send_scout(target[0], type: type)
      when :busy then pbMessage(_INTL("파견할 스카우트가 없습니다 (스카우팅 시설을 올리면 늘어납니다)."))
      when :money then pbMessage(_INTL("파견 비용이 모자랍니다."))
      when :region then pbMessage(_INTL("교통이 Lv5 이상이어야 다른 지방으로 보낼 수 있습니다."))
      else pbMessage(_INTL("{1}에 스카우트를 보냈습니다. 다음 주에 보고서가 옵니다.", target[1]))
      end
    end

    # sendSpecScout: nurse Pokémon or Ditto only, from anywhere.
    def special_scout(c)
      return if austerity_blocked?(c)
      kinds = Scouting::SPEC_POOL.keys
      i = pbMessage(_INTL("무엇을 찾을까요? 간호사 포켓몬(핑복·럭키·다부니·푸린 계열)은 배틀에 쓰다가 간호사로, 메타몽은 키우미집에서 누구와도 알을 낳습니다."),
                    kinds.map { |k| spec_name(k) } + [_INTL("취소")], kinds.size + 1)
      return if i >= kinds.size
      k = kinds[i]
      return unless pbConfirmMessage(_INTL("{1} 특별 스카우팅을 보낼까요? ({2})", spec_name(k), money(Scouting::SPEC_FEE)))
      case world.send_scout(nil, spec: k)
      when :busy then pbMessage(_INTL("파견할 스카우트가 없습니다 (스카우팅 시설을 올리면 늘어납니다)."))
      when :money then pbMessage(_INTL("파견 비용이 모자랍니다."))
      when :blocked then pbMessage(_INTL("스쿼드에 이미 메타몽이 있습니다."))
      else pbMessage(_INTL("{1} 특별 스카우팅을 보냈습니다. 다음 주에 보고서가 옵니다.", spec_name(k)))
      end
    end

    def spec_name(k) = k == :ditto ? _INTL("메타몽") : _INTL("간호사 포켓몬")

    def age_text(c)
      lo, hi = c[:age_lo], c[:age_hi]
      lo == hi ? _INTL("{1}시즌째", lo + 1) : _INTL("{1}~{2}시즌째(추정)", lo + 1, hi + 1)
    end

    def candidate_list(c)
      loop do
        cands = Scouting.state(world)[:cands]
        if cands.empty?
          pbMessage(_INTL("후보가 없습니다. 스카우트를 보내거나 정기 보고를 기다리세요."))
          return
        end
        labels = cands.map do |cand|
          m = cand[:mon]
          price = cand[:full] ? _INTL("{1}(정가 {2})", money(cand[:cost]), money(cand[:full])) : money(cand[:cost])
          tag = cand[:legend] ? _INTL("[전설] ") : ""
          tag + _INTL("{1} Lv{2} ★{3} · {4} · {5} · {6} · {7}까지", species_name(m.species), m.level, cand[:shown], age_text(cand),
                      region_name(cand[:region]), price, date_text(cand[:until]))
        end
        i = pbMessage(_INTL("후보 명단 (★와 나이는 스카우트의 추정입니다)"), labels + [_INTL("닫기")], labels.size + 1)
        return if i >= cands.size
        sign_candidate(c, cands[i])
      end
    end

    def sign_candidate(c, cand)
      return if austerity_blocked?(c)
      if Recruit.signs_left(c, world.calendar.year) <= 0
        pbMessage(_INTL("이번 시즌 영입 한도({1}마리)를 다 썼습니다. 지난 시즌 순위가 낮을수록 한도가 큽니다.",
                        Recruit.sign_limit(c, world.calendar.year)))
        return
      end
      if c.wallet.balance < cand[:cost]
        pbMessage(_INTL("돈이 모자랍니다 ({1} 필요).", money(cand[:cost])))
        return
      end
      return unless pbConfirmMessage(_INTL("{1}을 {2}에 영입할까요?", species_name(cand[:mon].species), money(cand[:cost])))
      release = nil
      if c.squad.size >= Build.squad_size(c.clubhouse)
        names = c.squad.map { |m| _INTL("{1} Lv{2} ★{3} · 전력 {4}", species_name(m.species), m.level, m.stars, m.rating.round) }
        j = pbMessage(_INTL("스쿼드가 가득 찼습니다. 누구를 내보낼까요?"), names + [_INTL("취소")], names.size + 1)
        return if j >= c.squad.size
        release = c.squad[j]
      end
      if (why = Recruit.sign_block(c, cand, world.species, release: release, world: world))
        pbMessage(sign_block_text(why, c))
        return
      end
      e = Recruit.sign(c, cand, date: world.calendar.date, release: release, pool: world.species)
      Scouting.take(world, cand)
      Legend.acquire(world, c, cand[:mon]) if cand[:legend]
      msg = _INTL("{1}을 영입했습니다 ({2}). 실제 ★{3}.", species_name(e[:species]), money(e[:cost]), cand[:mon].stars)
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
      loop do
        city = world.cities[c.city]
        pending = city.petition && _INTL("청원 중: {1}", agenda_text(city.petition[:agenda], city.petition[:target]))
        cmds = [_INTL("도시 정보"), _INTL("다음 회의 안건 청원"), _INTL("닫기")]
        case pbMessage(pending || _INTL("{1}", city.name), cmds, cmds.size)
        when 0 then show_list(_INTL("내 도시"), city_rows(c.city, c.id))
        when 1 then petition(c, city)
        else break
        end
      end
    end

    # Design 02: any club may put an agenda to its city's next monthly
    # meeting; it still needs a majority (or the player's full payment).
    def petition(club, city)
      if city.capital?
        pbMessage(_INTL("수도의 안건은 리그 관리위원회 총회가 정합니다."))
        return
      end
      opts = Meeting.petition_options(world, city)
      if opts.empty?
        pbMessage(_INTL("지금은 올릴 수 있는 안건이 없습니다 (공사 중이거나 세율 변경 뒤 반년이 안 됨)."))
        return
      end
      names = opts.map do |o|
        cost = o[:cost].positive? ? _INTL(" · 비용 {1}", money(o[:cost])) : ""
        lv = o[:from] ? _INTL(" Lv{1}→{2}", o[:from], o[:from] + 1) : ""
        agenda_text(o[:agenda], o[:target]) + lv + cost
      end
      i = pbMessage(_INTL("다음 달 1일 회의에 올릴 안건을 고르세요."), names + [_INTL("취소")], names.size + 1)
      return if i >= opts.size
      Meeting.petition(city, opts[i], by: club.id)
      pbMessage(_INTL("{1} 안건을 청원했습니다.", agenda_text(opts[i][:agenda], opts[i][:target])))
    end

    REASON_LINES = {
      no_money: "이번 시즌은 돈이 없다.", prefers_team: "그 돈이면 우리 팀에 투자하겠다.",
      too_expensive: "분담금이 너무 크다.", no_need: "지금은 필요 없다."
    }.freeze

    def reason_line(reason) = _INTL(REASON_LINES.fetch(reason, "반대한다."))

    # Meeting.player_hook: the meeting scene for the player's city. Shows
    # the agenda, each club's share and leaning (with its reason), and lets
    # the player take on more of the others' shares, pay it all, or vote.
    # 대가 제안: pick a club voting no and what to offer it.
    def make_offer(me, against, offers)
      names = against.map(&:name)
      i = pbMessage(_INTL("누구에게 제안할까요?"), names + [_INTL("취소")], names.size + 1)
      return if i >= against.size
      club = against[i]
      rel = world.relations.get(me.id, club.id)
      kinds = [[:support, _INTL("다음 회의 지지 약속")]]
      kinds << [:favor, _INTL("관계로 부탁 (관계 {1})", relation_text(rel))] if rel >= Meeting::FAVOR_MIN
      kinds.reject! { |k, _| offers.any? { |o| o[:club].equal?(club) && o[:kind] == k } }
      if kinds.empty?
        pbMessage(_INTL("{1}에게 더 제안할 것이 없습니다.", club.name))
        return
      end
      j = pbMessage(_INTL("무엇을 제안할까요?"), kinds.map(&:last) + [_INTL("취소")], kinds.size + 1)
      return if j >= kinds.size
      { club: club, kind: kinds[j].first }
    end

    def offer_text(o)
      case o[:kind]
      when :support then _INTL("{1}에 다음 회의 지지 약속", o[:club].name)
      else _INTL("{1}에 부탁", o[:club].name)
      end
    end

    def player_meeting(p)
      me = p.player
      extra = 0
      offers = []
      loop do
        shares, votes = p.evaluate.call(extra, offers)
        rows = [_INTL("{1} 회의: {2}", p.city.name, agenda_text(p.agenda, p.target))]
        if p.cost.positive?
          rows << _INTL("비용 {1} · 도시 예산 {2} · 클럽 분담 {3}", money(p.cost), money(p.city_part), money(p.full_cost))
        end
        p.members.each do |c|
          next if c.equal?(me)
          v = votes[c.id]
          lean = v[:yes] ? _INTL("찬성 쪽") : _INTL("반대 쪽")
          why = v[:yes] ? "" : _INTL(" — \"{1}\"", reason_line(v[:reason]))
          rows << _INTL("{1}: 분담 {2} · {3}{4}", c.name, money(shares[c.id]), lean, why)
        end
        rows << _INTL("나({1}): 분담 {2}", me.name, money(shares[me.id]))
        offers.each { |o| rows << _INTL("제안: {1}", offer_text(o)) }
        show_list(_INTL("도시 회의"), rows)
        cmds = [_INTL("찬성"), _INTL("반대")]
        others = shares.reject { |id, _| id == me.id }.values.sum
        can_shift = p.cost.positive? && p.members.size > 1 && others.positive?
        can_full = p.cost.positive? && p.full_cost.positive? && me.wallet.balance >= p.full_cost
        cmds << _INTL("분담 더 맡기") if can_shift
        cmds << _INTL("전액 부담 ({1})", money(p.full_cost)) if can_full
        against = p.members.reject { |c| c.equal?(me) || votes[c.id][:yes] }
        cmds << _INTL("대가 제안") unless against.empty?
        yes_now = votes.count { |id, v| id != me.id && v[:yes] }
        i = pbMessage(_INTL("찬성 쪽 {1}/{2}곳. 어떻게 할까요?", yes_now, p.members.size - 1), cmds, 2)   # cancel = 반대
        case cmds[i]
        when _INTL("찬성") then return { vote: true, extra: extra, offers: offers }
        when _INTL("반대"), nil then return { vote: false, extra: extra, offers: offers }
        when _INTL("대가 제안")
          o = make_offer(me, against, offers) or next
          _, after = p.evaluate.call(extra, offers + [o])
          if after[o[:club].id][:yes]
            offers << o
            pbMessage(_INTL("{1}: \"좋다, 그렇다면 찬성하겠다.\"", o[:club].name))
          else
            pbMessage(_INTL("{1}: \"그것만으로는 안 된다. {2}\"", o[:club].name, reason_line(after[o[:club].id][:reason])))
          end
        when _INTL("분담 더 맡기")
          steps = [25, 50, 100].map { |pct| (others * pct / 100.0).round }
          labels = [25, 50, 100].zip(steps).map { |pct, amt| _INTL("다른 클럽 몫의 {1}% ({2})", pct, money(amt)) }
          j = pbMessage(_INTL("얼마나 더 맡을까요?"), labels + [_INTL("취소")], labels.size + 1)
          extra += steps[j] if j < steps.size
        else
          return { full: true } if pbConfirmMessage(_INTL("{1}를 혼자 내고 투표 없이 통과시킬까요?", money(p.full_cost)))
        end
      end
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
      v[:promises].each { |pr| rows << _INTL("약속: 다음 회의에서 찬성 ({1}에게, {2})", pr[:to], date_text(pr[:made])) }
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
      loop do
        cmds = [_INTL("대회 진행"), _INTL("글로벌 파워랭킹"), _INTL("리그 계수"), _INTL("닫기")]
        case pbMessage(_INTL("대회"), cmds, cmds.size)
        when 0 then cup_progress
        when 1 then power_ranking
        when 2 then coefficients
        else break
        end
      end
    end

    # powerPanels: the top 30 and the player's place.
    def power_ranking
      list = Power.ranking(world)
      me = list.find { |x| x[:club] == world.player_club }
      rows = list.first(30)
      rows += [me] if me && me[:rank] > 30
      lines = rows.map do |x|
        c = world.clubs[x[:club]]
        _INTL("{1}{2}. {3} ({4}) {5}점 · 전력 {6}", x[:club] == world.player_club ? "▶" : "", x[:rank], c.name, region_name(c.region),
              format("%.1f", x[:score]), x[:ovr])
      end
      head = _INTL("최근 3시즌 (PWT + PET·PENT + 리그 순위 점수) × 1.0 · 0.6 · 0.3")
      head += "\n" + _INTL("나 {1}위 · {2}점", me[:rank], format("%.1f", me[:score])) if me
      show_list(head, lines)
    end

    def coefficients
      rows = Power.coefficients(world).map do |x|
        _INTL("{1}. {2} 계수 {3} · PWT 진출권 {4}장", x[:rank], region_name(x[:region]), format("%.1f", x[:score]), x[:slots])
      end
      show_list(_INTL("리그 계수 (최근 3번의 PWT, 기록이 없으면 지방 상위 4명 전력)"), rows)
    end

    def cup_progress
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

    INJURY_NAMES = { bruise: "타박상", cramp: "근육 경련", sprain: "다리 염좌", muscle: "근육 파열", concussion: "뇌진탕",
                     burnout: "번아웃", ligament: "인대 손상", fracture: "골절" }.freeze

    def injury_name(kind) = _INTL(INJURY_NAMES.fetch(kind, "부상"))

    # " · 🟡 타박상 1주" (can play) / " · 부상 골절 6주" (out) / " · 재활 2주", or nil.
    def injury_tag(injury, rehab)
      if injury
        if injury[:sev] == 1
          _INTL(" · 가벼운 부상({1}) {2}주", injury_name(injury[:kind]), injury[:weeks])
        else
          injury[:ptp] ? _INTL(" · 부상({1}) {2}주 · 무리 출전", injury_name(injury[:kind]), injury[:weeks]) :
            _INTL(" · 부상({1}) {2}주 결장", injury_name(injury[:kind]), injury[:weeks])
        end
      elsif rehab
        _INTL(" · 재활 {1}주", rehab)
      end
    end

    # " · ⬇스피드 -1 · 공격 -1" (condDebuffTxt): the stages it will fight at.
    def debuff_tag(species, list)
      return "" if list.nil? || list.empty?
      base = GameData::Species.try_get(species)&.base_stats
      main = base && base[:SPECIAL_ATTACK] > base[:ATTACK] ? _INTL("특공") : _INTL("공격")
      names = { spe: _INTL("스피드"), main: main, def: _INTL("방어"), spd: _INTL("특방") }
      _INTL(" · ⬇{1}", list.tally.map { |s, n| "#{names.fetch(s, s.to_s)} -#{n}" }.join(" "))
    end

    def mon_line(m)
      inj = m.hurt? ? { kind: m.injd && m.injd[:k], sev: m.injd && m.injd[:sev], weeks: m.inj, ptp: m.ptp } : nil
      rest = (injury_tag(inj, m.rehab) || (m.resting ? _INTL(" · 휴식") : "")) + debuff_tag(m.species, m.debuffs) +
             _INTL(" · 사기 {1}", morale_name(m))
      _INTL("{1} Lv{2} ★{3} · 전력 {4} · 컨디션 {5}{6}", species_name(m.species), m.level, m.stars, m.rating.round,
            m.cond, rest)
    end

    def mode_names
      { ask: _INTL("매번 묻기"), direct: _INTL("직접 전투"), auto: _INTL("자동 진행"), skip: _INTL("결과만 보기") }
    end

    # Design 06 기본값 설정 and 속도 옵션.
    TALK_TEXT = {
      win: ["우리가 이긴다!", "오늘은 우리가 이긴다! 자신 있게 가자!"],
      easy: ["부담 갖지 마", "결과는 신경 쓰지 마. 우리 배틀만 하면 돼."],
      fire: ["열정을 보여 줘!", "가진 힘을 전부 쏟아붓자! 열정을 보여 줘!"],
      focus: ["작전대로 침착하게", "준비한 대로만 하면 된다. 침착하게 가자."],
      fun: ["즐기고 오자!", "긴장 풀고, 신나게 즐기고 오자!"],
      trust: ["너희를 믿는다", "나는 너희를 믿는다. 너희라면 할 수 있어."],
      demand: ["실망시키지 마라", "오늘 지면 용납 못 한다. 실망시키지 마라."]
    }.freeze
    MOOD_NAMES = { fire: "투지 폭발", mot: "의욕적", calm: "평온", nerv: "긴장", comp: "자만", off: "시큰둥" }.freeze
    TEMPER_NAMES = { fiery: "열혈", easy: "느긋", cool: "냉철", sens: "섬세", free: "자유분방" }.freeze
    MORALE_NAMES = { best: "최상", good: "좋음", ok: "양호", bad: "나쁨", worst: "최악" }.freeze

    def morale_name(mon) = _INTL(MORALE_NAMES[Morale.tier(mon.mor)[1]])

    # Morale.player_talk: the locker room before the player's match. The
    # entry and each one's temperament are shown; the reactions come in the
    # week's summary. nil (cancel) leaves it to the coach.
    def locker_room(club, opp, ctx, mons)
      return nil if FM.state.match_mode == :skip   # matches it only hears about: the coach talks
      rows = mons.map do |m|
        _INTL("{1} · {2} · 사기 {3} · 유대 {4}", species_name(m.species), _INTL(TEMPER_NAMES[Morale.temper(m)]), morale_name(m),
              m.bond.round)
      end
      show_list(_INTL("라커룸: {1}전 (승리 기대 {2}%)", opp.name, ((ctx[:f] + 0.5) * 100).round), rows)
      talks = Morale::TALKS
      i = pbMessage(_INTL("경기 전 한마디: 무슨 말을 할까요? (같은 말을 연달아 하면 효과가 떨어집니다)"),
                    talks.map { |t| _INTL(TALK_TEXT[t][0]) } + [_INTL("코치에게 맡기기")], talks.size + 1)
      return nil if i >= talks.size
      pbMessage(_INTL("\"{1}\"", _INTL(TALK_TEXT[talks[i]][1])))
      [talks[i], individual_words(mons)]
    end

    ITALK_NAMES = { praise: "칭찬", cheer: "격려", push: "분발 촉구", calm: "진정시키기" }.freeze

    # Poké Manager's individual words (ITALKS) after the team talk.
    def individual_words(mons)
      ind = {}
      loop do
        rows = mons.map do |m|
          w = ind[m] ? _INTL(" → {1}", _INTL(ITALK_NAMES[ind[m]])) : ""
          _INTL("{1} ({2}){3}", species_name(m.species), _INTL(TEMPER_NAMES[Morale.temper(m)]), w)
        end
        i = pbMessage(_INTL("따로 한마디 할 포켓몬이 있나요? (기질에 맞으면 힘이 나고 유대감이 오릅니다)"), rows + [_INTL("이대로 경기에")],
                      rows.size + 1)
        return ind if i >= mons.size
        words = Morale::ITALKS
        j = pbMessage(_INTL("{1}에게 뭐라고 할까요?", species_name(mons[i].species)),
                      words.map { |k| _INTL(ITALK_NAMES[k]) } + [_INTL("아무 말 안 하기")], words.size + 1)
        j < words.size ? ind[mons[i]] = words[j] : ind.delete(mons[i])
      end
    end

    def match_settings
      loop do
        st = FM.state
        rows = [_INTL("기본 방식: {1}", mode_names[st.match_mode]),
                _INTL("빠른 진행(연출 생략): {1}", st.match_fast ? _INTL("켜짐") : _INTL("꺼짐")),
                _INTL("라커룸 토크: {1}", st.talk_auto ? _INTL("코치에게 맡기기") : _INTL("직접")), _INTL("닫기")]
        case pbMessage(_INTL("대회 결승은 기본 방식과 상관없이 항상 묻습니다."), rows, rows.size)
        when 0
          names = State::MATCH_MODES.map { |m| mode_names[m] }
          i = pbMessage(_INTL("경기를 어떻게 진행할까요?"), names + [_INTL("취소")], names.size + 1)
          st.match_mode = State::MATCH_MODES[i] if i < names.size
        when 1 then st.match_fast = !st.match_fast
        when 2 then st.talk_auto = !st.talk_auto
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
        tag = important ? _INTL("결승") : (neutral ? _INTL("대회") : _INTL("리그"))
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
      home.id == mine ? r : flip(r)
    end

    # A result from the player's side as the home side's view.
    def flip(r)
      { res: -r[:res], ko_a: r[:ko_b], ko_b: r[:ko_a], lineup_a: r[:lineup_b], lineup_b: r[:lineup_a],
        fainted_a: r[:fainted_b], fainted_b: r[:fainted_a], disobeyed_a: r[:disobeyed_b], disobeyed_b: r[:disobeyed_a] }
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
      id = FM.state.player_club   # taken before: a dismissal clears it
      if id
        FM::World.player_match = method(:player_match)
        Meeting.player_hook = method(:player_meeting)
        Morale.player_talk = method(:locker_room) unless FM.state.talk_auto
      end
      events = begin
        FM.advance_days(7)
      ensure
        FM::World.player_match = nil
        Meeting.player_hook = nil
        Morale.player_talk = nil
      end
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
        when :legend_joined
          _INTL("전설 {1}이(가) {2}의 새 주인 곁으로 ({3}시즌 함께)", species_name(e[:species]), world.clubs[e[:club]].name,
                Legend::LEG_YEARS)
        when :legend_left
          _INTL("전설 {1}이(가) {2}의 곁을 떠났다 ({3}시즌 동행을 마침)", species_name(e[:species]), world.clubs[e[:club]].name,
                Legend::LEG_YEARS)
        when :scout_report
          next unless e[:club] == id
          names = e[:species].map { |sp| species_name(sp) }.join(", ")
          if e[:passive] then _INTL("정기 스카우트 보고: {1}", names)
          elsif e[:spec] then _INTL("{1} 특별 스카우트 보고: {2}", spec_name(e[:spec]), names)
          elsif e[:type] then _INTL("{1} 타입 스카우트 보고({2}): {3}", type_name(e[:type]), e[:region] ? region_name(e[:region]) : _INTL("전체 지방"), names)
          else _INTL("스카우트 보고({1}): {2}", region_name(e[:region]), names)
          end
        when :disobeyed
          next unless e[:club] == id
          _INTL("{1}이(가) 경기 중 {2}번 말을 듣지 않았다 (유대감 {3})", species_name(e[:species]), e[:times], e[:bond])
        when :bond_opened
          next unless e[:club] == id
          _INTL("{1}이(가) 이제 말을 따르기 시작했다. 함께 쌓은 시간이 결실을 맺었다.", species_name(e[:species]))
        when :talk
          next unless e[:club] == id
          moods = e[:moods].map { |k, n| _INTL("{1} {2}", _INTL(MOOD_NAMES[k]), n) }.join(" · ")
          _INTL("라커룸 토크 \"{1}\": {2}", _INTL(TALK_TEXT[e[:talk]][0]), moods)
        when :egg
          _INTL("키우미집에 {1}의 알이 생겼다", species_name(e[:species])) if e[:club] == id
        when :hatched
          next unless e[:club] == id
          _INTL("키우미집에서 {1}이(가) 태어났다 ({2} × {3} · ★{4})", species_name(e[:species]), species_name(e[:parents][0]),
                species_name(e[:parents][1]), e[:stars])
        when :egg_waiting
          _INTL("{1}의 알이 부화했지만 스쿼드에 자리가 없다 (키우미집에서 기다림)", species_name(e[:species])) if e[:club] == id
        when :fans_price_cut
          _INTL("팬들의 항의로 입장료를 {1} → {2}로 내렸다", money(e[:from]), money(e[:to])) if e[:club] == id
        when :fans_riot
          _INTL("팬들이 경기장 앞에서 항의 시위를 벌였다. 관중이 줄고 굿즈도 안 팔린다") if e[:club] == id
        when :fans_love
          _INTL("팬들이 열광하고 있다. 홈 경기장은 연일 응원 열기로 뜨겁다") if e[:club] == id
        when :goal_set
          next unless e[:club] == id
          g = e[:goal]
          _INTL("{1}년차 시즌 목표: {2} · 달성 보너스 {3} ({4}전력 순위 {5}위 기준)", g[:year], goal_text(world, g[:t], g[:region]),
                money(g[:bonus]), g[:prev] ? _INTL("지난 시즌 {1}위 · ", g[:prev]) : "", g[:ovr])
        when :goal_result
          next unless e[:club] == id
          g = e[:goal]
          if g[:ok]
            _INTL("시즌 목표 달성! 목표 {1}위 이내 → {2}위. 보너스 {3}", g[:t], g[:pos], money(g[:paid]))
          else
            _INTL("시즌 목표 실패: 목표 {1}위 이내, 실제 {2}위. 팬들이 실망했다", g[:t], g[:pos])
          end
        when :aging_warning
          next unless e[:club] == id
          _INTL("{1} Lv{2}가 낡아 가고 있다: {3}주 뒤 Lv{4}로 떨어진다 (시설 투자에서 {5}으로 보수)", facility_name(e[:what]),
                e[:level], e[:weeks], e[:level] - 1, money(e[:cost]))
        when :aged
          _INTL("{1}이 낡아 Lv{2}로 떨어졌다. 다시 올리려면 {3}", facility_name(e[:what]), e[:level], money(e[:cost])) if e[:club] == id
        when :tour
          _INTL("원정 친선 투어: 출전료 {1} · 엔트리 컨디션 −{2}, 이번 주 훈련 쉼", money(e[:pay]), Tour::COND) if e[:club] == id
        when :crisis
          _INTL("재정 위기: {1}", crisis_name(e[:stage])) if e[:club] == id
        when :bailout
          _INTL("리그 구제금융: 빚 {1}을 대신 갚았다 (명성 −{2}, 다음 시즌 영입 한도 −1)", money(e[:amount]),
                Credit::BAILOUT_FAME) if e[:club] == id
        when :dismissed
          _INTL("구단주가 감독을 해고했다. 새 클럽을 골라야 한다.") if e[:club] == id
        when :meeting
          next unless id && e[:votes].key?(id)
          result = e[:passed] ? _INTL("통과") : _INTL("부결")
          how = e[:full] ? _INTL(" (전액 부담)") : _INTL(" ({1}/{2})", e[:votes].count { |_, v| v[:yes] }, e[:votes].size)
          line = _INTL("도시 회의 {1}: {2}{3}", agenda_text(e[:agenda], e[:target]), result, how)
          (e[:promises] || []).each do |pr|
            name = world.clubs[pr[:to]].name
            line += pr[:kept] ? _INTL(" · {1}와의 약속을 지켰다", name) : _INTL(" · {1}와의 약속을 어겼다 (평판 하락)", name)
          end
          line
        when :signed
          _INTL("영입: {1} ({2})", species_name(e[:species]), money(e[:cost])) if e[:club] == id
        when :injured
          next unless e[:club] == id
          cause = e[:cause] == :train ? _INTL("훈련 중") : _INTL("경기 중")
          if e[:worse]
            _INTL("부상 악화: {1} {2}, +{3}주{4}", species_name(e[:species]), injury_name(e[:injury]), e[:weeks],
                  e[:sev] >= 2 ? _INTL(" · 출전 불가") : "")
          elsif e[:sev] == 1
            _INTL("가벼운 부상: {1} {2}({3}), {4}주 · 출전은 가능", species_name(e[:species]), injury_name(e[:injury]), cause,
                  e[:weeks])
          else
            _INTL("부상: {1} {2}({3}), {4}주 결장", species_name(e[:species]), injury_name(e[:injury]), cause, e[:weeks])
          end
        when :recovered
          next unless e[:club] == id
          if e[:rehab]
            _INTL("복귀: {1} (재활 {2}주, 재부상 주의)", species_name(e[:species]), e[:rehab])
          else
            _INTL("회복: {1}", species_name(e[:species]))
          end
        when :league_champion
          n = world.clubs[e[:club]].name
          base = e[:streak] >= 2 ? _INTL("{1}, {2} 리그 {3}연패", n, region_name(e[:region]), e[:streak]) :
                                   _INTL("{1}, {2} 리그 우승", n, region_name(e[:region]))
          base += _INTL(" ({1}승 {2}패, 승점 {3})", e[:w], e[:l], e[:pts])
          base += _INTL(" · 역대 최다 승점") if e[:record]
          base
        when :ko_king
          next unless id && world.clubs[id].region == e[:region]
          _INTL("시즌 KO왕: {1}의 {2} ({3}KO, {4}경기)", world.clubs[e[:club]].name, species_name(e[:species]), e[:ko], e[:gp])
        when :first_top4
          _INTL("{1}, 처음으로 리그 {2}위 — 상위 4위 진입", world.clubs[e[:club]].name, e[:pos])
        when :riser
          _INTL("올해의 돌풍: {1} ({2}위 → {3}위, {4}계단)", world.clubs[e[:club]].name, e[:from], e[:to], e[:d])
        when :pwt_hof
          n = world.clubs[e[:club]].name
          e[:titles] >= 2 ? _INTL("{1}, PWT 통산 {2}번째 우승", n, e[:titles]) : _INTL("{1}, PWT 챔피언 등극", n)
        when :sponsor_quit, :sponsor_warn, :sponsor_review, :sponsor_eval, :sponsor_renewal
          sponsor_news(e, id)
        when :title_gained
          _INTL("{1}, '{2}' 칭호", world.clubs[e[:club]].name, title_name(e[:title]))
        when :rival_set
          next unless e[:club] == id
          n = world.clubs[e[:rival]].name
          w, l = e[:h2h]
          (e[:again] ? _INTL("{1}, 올해도 라이벌", n) : _INTL("올 시즌 라이벌: {1}", n)) +
            (w + l > 0 ? _INTL(" (지금까지 {1}승 {2}패)", w, l) : "")
        when :rival_result
          next unless e[:club] == id
          n = world.clubs[e[:rival]].name
          (e[:won] ? _INTL("라이벌 {1}을(를) 꺾었다", n) : _INTL("라이벌 {1}에게 무릎", n)) +
            _INTL(" (올 시즌 {1}승 {2}패, 명성 {3})", e[:w], e[:l], format("%+d", e[:fame]))
        when :event_done
          next unless e[:club] == id
          _INTL("선택 이벤트에 답하지 않아 마지막 선택지로 넘어갔다") if e[:auto]
        when :youth
          next unless e[:club] == id
          _INTL("출전할 포켓몬이 모자라 유소년 {1}을(를) 급히 불러올렸다 (긴급 유소년 콜업)", e[:mons].map { |sp| species_name(sp) }.join(", "))
        when :region_moved
          n = world.clubs[e[:club]].name
          if e[:club] == id
            _INTL("{1} → {2} 지방 이적 완료. 명성 {3} → {4}, 시설 Lv1, 임대 경기장에서 다시 시작", region_name(e[:from]), region_name(e[:to]),
                  e[:fame0].round, e[:fame].round)
          else
            _INTL("{1}, {2}을 떠나 {3} 리그로", n, region_name(e[:from]), region_name(e[:to]))
          end
        when :hof_inducted
          _INTL("{1}이(가) 은퇴하며 명예의 전당에 올랐다 ({2}KO)", species_name(e[:species]), e[:ko]) if e[:club] == id
        when :cup_champion
          _INTL("{1} 우승: {2}", e[:cup].to_s.upcase, world.clubs[e[:club]].name)
        when :city_grown
          _INTL("{1}가 {2}단계로 커졌다", e[:city], e[:size]) if id && world.clubs[id].city == e[:city]
        end
      end
      lines.unshift(_INTL("오늘: {1}", date_text(world.calendar.date)))
      show_list(_INTL("1주 진행"), lines)
      ask_event if id && FM.state.player_club == id
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
