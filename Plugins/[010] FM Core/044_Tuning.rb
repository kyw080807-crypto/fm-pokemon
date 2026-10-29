#===============================================================================
# FM::Tuning — 기술변경권 · 민트 · 특성캡슐 (Poké Manager TICKETS: tmticket,
# mint, abilcap; movesetOf / natureOf / abilityOf). Pure Ruby; the move
# pool and the abilities come from the caller (Essentials data, FM Bridge).
# - A TM ticket (₽20,000) sets a mon's four moves from what it can learn
#   (level-up moves to its level, all of them once evolved, TMs, egg and
#   tutor moves); a mint (₽15,000) sets its nature (the stats and its
#   temperament, FM::Morale); an ability capsule (₽25,000) switches it to
#   another ability its species can have.
# - Without a ticket a mon fights with its auto moves (autoMoves, FM
#   Bridge); after evolving, set moves the new form can't learn give way
#   to auto ones.
# The original's AI changes these to Showdown meta sets; we have none, so
# AI mons keep their auto moves, nature and ability.
#===============================================================================
module FM
  module Tuning
    PRICES = { moves: 20_000, mint: 15_000, ability: 25_000 }.freeze
    MAX_MOVES = 4

    module_function

    def price(club, kind) = (PRICES.fetch(kind) * Items.shop_mul(club) / 10.0).round * 10

    def pay(club, kind, date)
      cost = price(club, kind)
      return false if club.wallet.balance < cost
      club.wallet.record(-cost, category: :shop, date: date)
      true
    end

    # pool: the moves it can learn now (FM::Battle.learnable). -> :ok or why not
    def set_moves(club, mon, moves, pool:, date:)
      moves = moves.uniq
      return :count unless moves.size.between?(1, MAX_MOVES)
      return :not_learnable unless moves.all? { |m| pool.include?(m) }
      return :same if mon.moves == moves
      return :money unless pay(club, :moves, date)
      mon.moves = moves
      :ok
    end

    def mint(club, mon, nature, date:)
      return :unknown unless Morale::NATURES.include?(nature)
      return :same if Morale.nature(mon) == nature
      return :money unless pay(club, :mint, date)
      mon.nat = nature
      :ok
    end

    # count: how many abilities the species has (normal + hidden); index
    # is the one to take.
    def capsule(club, mon, index, count:, current:, date:)
      return :unknown unless index.between?(0, count - 1)
      return :same if index == current
      return :money unless pay(club, :ability, date)
      mon.ab = index
      :ok
    end
  end
end
