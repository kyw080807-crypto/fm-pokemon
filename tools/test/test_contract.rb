require_relative "test_helper"
require_relative "test_sponsor"   # TestSponsor::TABLE

# Poké Manager 스폰서 계약 2.0 (sp2Terms / sp2Exps / sp2Eval / sp2Review /
# sp2RenewOffer / sp2NewYear / sp2AutoPick / sp2PlayerQuit).
class TestContract < Minitest::Test
  C = FM::Contract
  TABLE = TestSponsor::TABLE

  def world
    clubs = (0...4).map do |i|
      { id: "K#{i}", name: "K#{i}", region: "KANTO", city: "C", role: i.zero? ? "C" : "T", canon: true,
        level: i.zero? ? 40 : 20, potential: 3, stadium: 1, clubhouse: 3,
        pokemon: Array.new(3) { { bst: i.zero? ? 650 : 380, level: 40, stars: 3 } } }
    end
    w = FM::World.new_game(clubs, seed: 1, sponsors: TABLE)
    w.player_club = "K1"
    w
  end

  def row(kind) = TABLE.find { |x| x[:kind] == kind } || TABLE.first

  def test_terms_by_length_and_target
    o = C.offer(FM::Sponsor.deal(row("STABLE"), fame: 50))
    b = o[:base0]
    t = C.terms(o, 3, 1)
    assert_equal C.r(b * 1.15 * 1.1), t[:base]
    assert_equal C.r(b * 0.15), t[:sign]
    assert_equal C.r(b * 0.12 * 1.45), t[:pool]
    assert_equal 0, C.terms(o, 1, 0)[:sign]
  end

  def test_ai_contracts_have_one_expectation_the_player_several
    w = world
    ai = w.clubs["K2"]
    assert C.v2?(ai.sponsor)
    assert_equal [:pos], ai.sponsor[:exp].map { |e| e[:k] }
    me = w.clubs["K1"]
    C.sign(w, me, FM::Sponsor.deal(row("STRICT"), fame: me.fame).merge(human: true), len: 2, amb: 1)
    me.sponsor[:human] = true
    C.season(w, me, fresh: true)
    assert_operator me.sponsor[:exp].size, :>=, 2
    assert_equal me.sponsor[:pool], me.sponsor[:exp].sum { |e| e[:bonus] }, 1000
    assert_equal w.calendar.year + 1, me.sponsor[:until]
  end

  def test_season_eval_pays_and_moves_satisfaction
    w = world
    c = w.clubs["K2"]
    s = c.sponsor
    s[:exp] = [{ k: :pos, imp: :k, t: 2, bonus: 10_000 }]
    s[:sat] = 60
    bal = c.wallet.balance
    C.evaluate(w, c, 1)
    assert_equal bal + 10_000, c.wallet.balance
    assert_equal 72, s[:sat]
    assert_empty C.evaluate(w, c, 1), "once a season"
  end

  def test_strict_key_miss_ends_it
    w = world
    c = w.clubs["K2"]
    C.sign(w, c, FM::Sponsor.deal(row("STRICT"), fame: c.fame), len: 2, amb: 0)
    c.sponsor[:exp] = [{ k: :pos, imp: :k, t: 1, bonus: 1 }]
    events = C.evaluate(w, c, 4)
    assert(events.any? { |e| e[:kind] == :sponsor_quit })
    assert_nil c.sponsor
    assert_equal w.calendar.year + 2, c.sponsor_bans[row("STRICT")[:id]]
  end

  def test_low_satisfaction_warns_then_leaves
    w = world
    me = w.clubs["K1"]
    C.sign(w, me, FM::Sponsor.deal(row("STABLE"), fame: me.fame), len: 3, amb: 0)
    s = me.sponsor
    s[:human] = true
    s[:exp] = [{ k: :pos, imp: :k, t: 1, bonus: 1 }]
    s[:since] = w.calendar.year - 1
    s[:sat] = 28
    w.advance_days(w.calendar.days_until(FM::Season.league_dates(w.calendar, 1).first) + 1)
    events = C.review(w, me, 8)
    assert_equal :sponsor_warn, events.first[:kind]
    me.sponsor[:sat] = 14
    events = C.review(w, me, 12)
    assert_equal :sponsor_quit, events.first[:kind]
    assert w.sponsor_offers&.first&.dig(:bridge), "a stopgap sponsor is offered"
  end

  def test_renewal_and_new_year
    w = world
    c = w.clubs["K2"]
    s = c.sponsor
    s[:until] = w.calendar.year
    s[:renew_ok] = true
    s[:sat] = 90
    o = C.renew_offer(w, c)
    assert o[:renew]
    assert_operator o[:base], :>, FM::Sponsor.deal(TABLE.find { |x| x[:id] == s[:id] }, fame: c.fame)[:base]
    w.clubs["K1"].sponsor[:until] = w.calendar.year
    w.advance_days(w.calendar.days_until([w.calendar.year + 1, 1, 1]))
    assert C.v2?(c.sponsor)
    assert_nil w.clubs["K1"].sponsor, "the player chooses"
    refute_empty w.sponsor_offers
  end

  def test_the_player_picks_or_gets_the_auto_pick
    w = world
    w.clubs["K1"].sponsor = nil
    w.sponsor_offers = C.offers_for(w, w.clubs["K1"])
    pick = C.auto_pick(w.sponsor_offers)
    w.advance_days(w.calendar.days_until(FM::Season.league_dates(w.calendar, 1).first) + 1)
    assert_equal pick[:id], w.clubs["K1"].sponsor[:id]
    assert_nil w.sponsor_offers
  end

  def test_early_quit_costs_a_quarter_of_the_base_left
    w = world
    me = w.clubs["K1"]
    C.sign(w, me, FM::Sponsor.deal(row("STABLE"), fame: me.fame), len: 3, amb: 0)
    refute C.can_quit?(w, me), "not in the first season"
    me.sponsor[:since] = w.calendar.year - 1
    pen = C.penalty(w, me.sponsor)
    assert_equal C.r(me.sponsor[:base] * 3 * 0.25), pen, "this season and the two left"
    assert_equal pen, C.player_quit(w, me)
    assert_nil me.sponsor
    refute_empty w.sponsor_offers
  end
end
