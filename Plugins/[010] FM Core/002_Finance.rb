#===============================================================================
# FM::Finance — club money: balance, an entry log, and recurring weekly/monthly
# items applied from FM::Calendar boundary events. Pure Ruby (no engine
# symbols). Amounts are integers; positive = income, negative = expense.
# Dates are [year, month, day] arrays, as taken from a Calendar snapshot.
#===============================================================================
module FM
  class Finance
    SCHEMA_VERSION = 1
    PERIODS        = { week: :new_week, month: :new_month }.freeze

    class InsufficientFunds < StandardError; end

    Entry     = Struct.new(:amount, :category, :date, :memo)
    Recurring = Struct.new(:id, :amount, :category, :every)

    attr_reader :balance, :entries

    def initialize(balance: 0)
      @balance   = balance
      @entries   = []
      @recurring = {}
    end

    def can_afford?(cost)
      @balance >= cost
    end

    # Books any non-zero amount, even if it takes the balance below zero
    # (fines, wages that are owed regardless).
    def record(amount, category:, date:, memo: nil)
      raise ArgumentError, "amount must be a non-zero Integer: #{amount.inspect}" unless amount.is_a?(Integer) && amount != 0
      entry = Entry.new(amount, category, date.dup.freeze, memo)
      @entries << entry
      @balance += amount
      entry
    end

    # Player-chosen purchases: refuses rather than going into debt.
    def spend(cost, category:, date:, memo: nil)
      raise ArgumentError, "cost must be a positive Integer: #{cost.inspect}" unless cost.is_a?(Integer) && cost.positive?
      raise InsufficientFunds, "need #{cost}, have #{@balance}" unless can_afford?(cost)
      record(-cost, category: category, date: date, memo: memo)
    end

    def add_recurring(id, amount:, category:, every:)
      raise ArgumentError, "every must be one of #{PERIODS.keys.inspect}" unless PERIODS.key?(every)
      raise ArgumentError, "amount must be a non-zero Integer" unless amount.is_a?(Integer) && amount != 0
      @recurring[id] = Recurring.new(id, amount, category, every)
    end

    def remove_recurring(id)
      @recurring.delete(id)
    end

    def recurring
      @recurring.values
    end

    # Feed every [kind, snapshot] pair from Calendar#advance through here.
    def on_calendar_event(kind, date)
      @recurring.each_value do |item|
        next unless PERIODS[item.every] == kind
        record(item.amount, category: item.category, date: date, memo: item.id.to_s)
      end
    end

    # Sum of amounts per category, optionally limited to an inclusive date range.
    def totals(from: nil, to: nil)
      @entries.each_with_object(Hash.new(0)) do |e, sums|
        next if from && (e.date <=> from).negative?
        next if to && (e.date <=> to).positive?
        sums[e.category] += e.amount
      end.to_h
    end

    def to_h
      { schema_version: SCHEMA_VERSION,
        balance:        @balance,
        entries:        @entries.map(&:to_h),
        recurring:      @recurring.values.map(&:to_h) }
    end

    def self.from_h(h)
      version = h[:schema_version] || 0
      raise ArgumentError, "unknown finance schema #{version}" if version > SCHEMA_VERSION
      ledger = new(balance: h[:balance] || 0)
      (h[:entries] || []).each do |e|
        ledger.entries << Entry.new(e[:amount], e[:category], e[:date].dup.freeze, e[:memo])
      end
      (h[:recurring] || []).each do |r|
        ledger.add_recurring(r[:id], amount: r[:amount], category: r[:category], every: r[:every])
      end
      ledger
    end
  end
end
