#===============================================================================
# FM::Credit — loans and the financial crisis ladder (design 04 재정 시스템:
# 대출, 재정 위기 단계 경고 → 긴축 → 구제금융 → 해고 압박). Pure Ruby. Poké
# Manager has neither (only 0.5% a week on a negative balance, kept as is);
# all numbers are drafts.
# - A loan: up to LIMIT_PER_FAME x fame, one at a time, LOAN_RATE a week
#   on what is owed, repaid in TERM_WEEKS equal parts each Monday; it can
#   be repaid early.
# - The ladder, by consecutive Mondays deep in the red (owing more than
#   DEEP_WEEKS of running costs; a dip before prize money is only a
#   warning):
#     :warning   (in the red at all)
#     :austerity (AUSTERITY_WEEKS): no new building, scouting or signing
#     :bailout   (BAILOUT_WEEKS): the league clears the debt; fame
#                -BAILOUT_FAME and one signing fewer next season
#     :pressure  (red again within PRESSURE_WEEKS of a bailout, for
#                AUSTERITY_WEEKS): the owner's warning; AUSTERITY_WEEKS
#                more and the manager is dismissed (:dismissed — the
#                player loses the club, FM::State) and the league clears
#                the debt again for whoever comes next.
#===============================================================================
module FM
  module Credit
    LIMIT_PER_FAME = 5_000
    LOAN_RATE = 0.0025
    TERM_WEEKS = 52
    AUSTERITY_WEEKS = 8
    BAILOUT_WEEKS = 16
    BAILOUT_FAME = 5
    PRESSURE_WEEKS = 52
    DEEP_WEEKS = 4

    module_function

    def limit(club) = (club.fame * LIMIT_PER_FAME / 10_000).floor * 10_000

    def can_borrow?(club, amount)
      club.loan.nil? && amount.positive? && amount <= limit(club) && club.crisis != :pressure
    end

    def borrow(club, amount, date:)
      raise ArgumentError, "can't borrow #{amount}" unless can_borrow?(club, amount)
      club.loan = { owed: amount, part: (amount / TERM_WEEKS.to_f).ceil, taken: date }
      club.wallet.record(amount, category: :loan, date: date)
    end

    def repay_all(club, date:)
      l = club.loan or return
      club.wallet.record(-l[:owed], category: :loan_repay, date: date)
      club.loan = nil
    end

    # Monday: interest and one part of the loan, then the ladder.
    # -> events
    def week(club, date:, calendar:)
      events = []
      if (l = club.loan)
        interest = (l[:owed] * LOAN_RATE).round
        part = [l[:part], l[:owed]].min
        club.wallet.record(-interest, category: :loan_interest, date: date) if interest.positive?
        club.wallet.record(-part, category: :loan_repay, date: date)
        l[:owed] -= part
        club.loan = nil if l[:owed] <= 0
      end
      red = club.wallet.balance.negative?
      deep = club.wallet.balance < -club.weekly_cost * DEEP_WEEKS
      club.red_weeks = deep ? club.red_weeks + 1 : 0
      before = club.crisis
      recent = club.bailed && calendar.days_between(club.bailed, date) <= PRESSURE_WEEKS * 7
      stage = if !red then nil
              elsif recent && club.red_weeks >= AUSTERITY_WEEKS then :pressure
              elsif club.red_weeks >= BAILOUT_WEEKS then :bailout
              elsif club.red_weeks >= AUSTERITY_WEEKS then :austerity
              else :warning
              end
      if stage == :pressure && club.red_weeks >= 2 * AUSTERITY_WEEKS
        events << { kind: :dismissed, club: club.id, date: date }
        stage = :bailout
      end
      if stage == :bailout
        debt = -club.wallet.balance
        club.wallet.record(debt, category: :bailout, date: date)
        club.fame = Economy.add_fame(club.fame, -BAILOUT_FAME)
        club.bailed = date
        club.red_weeks = 0
        events << { kind: :bailout, club: club.id, amount: debt, date: date }
        stage = nil
      end
      club.crisis = stage
      events << { kind: :crisis, club: club.id, stage: stage, date: date } if stage && stage != before
      events
    end

    # 긴축: nothing new is started.
    def austerity?(club) = %i[austerity pressure].include?(club.crisis)

    # A bailout last season costs a signing this season.
    def sign_penalty(club, year) = club.bailed && club.bailed[0] == year - 1 ? 1 : 0
  end
end
