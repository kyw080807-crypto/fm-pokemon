#===============================================================================
# FM UI: the opponent analysis report (FM::Analysis), with Essentials' type
# chart (GameData::Type#effectiveness: 0 / 1 / 2 / 4 = x0 / x0.5 / x1 / x2).
#===============================================================================
module FM
  module UI
    module_function

    TYPE_CHART = lambda do |atk, df|
      d = GameData::Type.try_get(df.to_sym)
      d && GameData::Type.exists?(atk.to_sym) ? d.effectiveness(atk.to_sym) / 2.0 : 1.0
    end

    def edge_mark(x) = x >= 0.5 ? "◎" : x >= 0.15 ? "○" : x > -0.15 ? "·" : x > -0.5 ? "△" : "×"

    def analysis
      c = player_club or return
      nm = Analysis.next_match(world, c)
      unless nm
        pbMessage(_INTL("다가오는 리그 경기가 없습니다."))
        return
      end
      opp = world.clubs[nm[:opp]]
      r = Analysis.report(world, c, opp, chart: TYPE_CHART)
      mon = ->(m) { _INTL("{1} 전력 {2} · 컨디션 {3}{4}", species_name(m.species), m.rating.round, m.cond, m.hurt? ? _INTL(" · 부상") : "") }
      rows = [_INTL("{1}라운드 {2} {3} · 예상 승률 {4}%", nm[:round], nm[:home] ? _INTL("홈") : _INTL("원정"), opp.name, (r[:win] * 100).round),
              _INTL("팀 전력 {1} 대 {2}", r[:rating][0].round, r[:rating][1].round),
              _INTL("상대 성향: {1}", r[:style].map { |t, n| _INTL("{1} {2}마리", type_name(t), n) }.join(" · "))]
      rows << _INTL("— 예상 선출 —")
      r[:expect].each { |m| rows << "  " + mon.(m) }
      rows << _INTL("— 위협 순위 —")
      r[:threats].first(3).each_with_index { |(m, _), i| rows << _INTL("  {1}. {2}", i + 1, mon.(m)) }
      rows << _INTL("— 추천 선출 —")
      r[:best].each { |m| rows << "  " + mon.(m) }
      rows << _INTL("— 맞대결 (◎ 유리 ~ × 불리) —")
      rows << "  " + r[:foes].map { |m| species_name(m.species)[0, 3] }.join(" ")
      r[:mine].each_with_index do |m, i|
        rows << _INTL("  {1}: {2}", species_name(m.species), r[:grid][i].map { |x| edge_mark(x) }.join(" "))
      end
      show_list(_INTL("상대 분석: {1}", opp.name), rows)
    end
  end
end
