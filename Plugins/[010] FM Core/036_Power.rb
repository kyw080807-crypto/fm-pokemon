#===============================================================================
# FM::Power — 글로벌 파워랭킹 (Poké Manager: PR_W, pwtPts, subPts, lgPts,
# powerScore, powerRanking, leagueCoef's display). Pure Ruby.
# - Score: the last three seasons of (PWT points + PET/PENT points + league
#   points) x 1.0 / 0.6 / 0.3, newest first. PWT: champion 100, final 70,
#   semi 50, quarter 35, last 16 22, out in the Swiss stage 4 + 3 a win.
#   PET/PENT: final 10, semi 6, quarter 3, last 16 1 (the champion counts
#   its PWT). League: (21 - place) x 2.
# - Ties go to team OVR. League coefficients are World#league_coefficients.
#===============================================================================
module FM
  module Power
    WEIGHTS = [1.0, 0.6, 0.3].freeze
    SUB_POINTS = { final: 10, sf: 6, qf: 3, r16: 1 }.freeze

    module_function

    def league_points(pos) = pos ? [0, 21 - pos].max * 2 : 0
    def sub_points(cup) = cup ? SUB_POINTS.fetch(cup[1], 0) : 0

    def pwt_points(h) = h[:pwt] ? Tournament.pwt_points(h[:pwt], wins: h[:pwt_wins] || 0) : 0

    # powerScore
    def score(club)
      seasons = club.history.sort_by { |y, _| -y }.first(3)
      s = seasons.each_with_index.sum do |(_, h), i|
        (pwt_points(h) + sub_points(h[:cup]) + league_points(h[:pos])) * WEIGHTS[i]
      end
      s.round(1)
    end

    # powerRanking -> [{ club:, score:, ovr:, rank: }], best first
    def ranking(world)
      list = world.clubs.values.map { |c| { club: c.id, score: score(c), ovr: Fans.team_ovr(c) } }
      list.sort_by! { |x| [-x[:score], -x[:ovr], x[:club].to_s] }
      list.each_with_index { |x, i| x[:rank] = i + 1 }
    end

    # leagueCoef for screens: [{ region:, score:, slots:, rank: }]
    def coefficients(world)
      coef = world.league_coefficients
      slots = Tournament.pwt_slots(coef)
      coef.sort_by { |r, s| [-slots.fetch(r, 3), -s, r.to_s] }.each_with_index.map do |(r, s), i|
        { region: r, score: s.round(1), slots: slots.fetch(r, 3), rank: i + 1 }
      end
    end
  end
end
