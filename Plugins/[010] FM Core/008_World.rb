#===============================================================================
# FM::World — every club and regional league, advanced one day at a time.
# Pure Ruby. On a league date each region plays its next round: results from
# FM::MatchSim, gate money to the home club, win/draw bonuses, fame changes
# (Poké Manager playRound). When a league ends: prize money, rebuild aid and
# fame by position (finalizeLeague). January 1 starts new leagues.
#
# Club data comes in as plain hashes (tools/sim reads PBS/fm_clubs.txt; the
# game will read compiled GameData), each with :pokemon as
# [{bst:, level:, stars:}].
#===============================================================================
module FM
  class Club
    attr_reader :id, :name, :region, :city, :role, :canon, :level, :potential,
                :facilities, :rating, :wallet, :form, :stadium_shared,
                :home_fill, :traits, :squad, :retired, :sponsor_bans, :history, :type
    attr_accessor :fame, :stadium, :clubhouse, :project, :city_size, :sponsor
    # FM::Fans / FM::Goals (the player's club only).
    attr_accessor :fsat, :fs_log, :fs_riot, :fs_love, :goal
    attr_accessor :hof   # FM::Hof: its own hall of fame
    attr_accessor :move_to, :moved_year   # FM::Transfer
    attr_accessor :bag   # FM::Items: the player's items, { id => count }
    attr_accessor :att   # this season's home crowds { year:, sum:, n: } (FM::Contract)
    attr_accessor :tlog  # FM::Titles: titles earned, newest first
    attr_accessor :gbag  # FM::Gimmick: an AI's gimmick items not in use
    attr_writer :stadium_shared

    # FM::Transfer: a new region, home city and role.
    def relocate(region:, city:, role:, city_size:)
      @region, @city, @role, @city_size = region, city, role, city_size
    end

    def initialize(data)
      @id, @name, @region, @city = data.values_at(:id, :name, :region, :city)
      @role, @canon, @level, @potential = data.values_at(:role, :canon, :level, :potential)
      @stadium = data[:stadium]
      @stadium_shared = data.fetch(:stadium_shared, false)
      @clubhouse = data.fetch(:clubhouse, 1)
      @city_size = data.fetch(:city_size, 1)
      @facilities  = (data[:facilities] || {}).dup
      @project   = nil   # { kind:, target:, to:, done: [y, m, d] }
      @home_fill = []    # attendance / capacity, last 5 home games
      @type      = data.fetch(:type, "NORMAL")
      @traits    = Traits.generate(name: @name, role: @role, type: @type)
      @squad = data[:pokemon].map do |m|
        Mon.new(species: m[:species], bst: m[:bst], level: m[:level], stars: m[:stars], ev: m[:ev],
                age: m.fetch(:age, 0), canon: @canon)
      end
      @retired = []
      @sponsor = nil          # FM::Sponsor.deal hash for this season
      @sponsor_bans = {}      # sponsor id => last banned year
      @history = {}           # year => { pos:, pwt: (result symbol), pwt_wins:, cup: }
      @fame    = Economy.initial_fame(level: @level, role: @role, canon: @canon)
      refresh_rating
      @wallet  = Finance.new(balance: Economy.start_funds(@fame))
      @form    = []
    end

    # FM::Aging: { building => { w: weeks at the top, n: renovations } }.
    attr_accessor :fac_age

    # FM::Daycare: { pairs: [[mon, mon], ...], eggs: [{ mon:, hatch: }] }.
    attr_accessor :daycare

    # FM::Credit state. Older saves: no loan, never in the red.
    attr_accessor :loan, :crisis, :bailed
    attr_writer :red_weeks
    def red_weeks = @red_weeks || 0

    # Signings this season (Recruit.sign_limit). Older saves: none yet.
    def signs_used(year) = @signs && @signs[:year] == year ? @signs[:n] : 0

    def sign_use(year)
      @signs = { year: year, n: signs_used(year) + 1 }
    end

    def push_form(result)
      @form << result
      @form.shift while @form.size > 5
    end

    def recent_wins
      @form.empty? ? 2 : @form.count(:w)   # demand() assumes 2 without a table
    end

    def push_fill(ratio)
      @home_fill << ratio
      @home_fill.shift while @home_fill.size > 5
    end

    # The three who play (topMons: best after condition).
    def lineup
      entry(3)
    end

    # The entry both sides reveal before a match (Poké Manager PARTY = 6);
    # each then picks 3 (PICK) of it.
    ENTRY_SIZE = 6
    # Mons out injured (FM::Injury, severity 2-3) are not in it. Gyms and
    # typed Elite Four keep it to their specialty (FM::Specialty.party).
    def entry(n = ENTRY_SIZE)
      avail = @squad.reject(&:out?)
      str = avail.to_h { |m| [m, m.rating * m.strength_mul] }.compare_by_identity
      six = avail.max_by(ENTRY_SIZE) { |m| str[m] }
      six = Specialty.party(self, six, avail, Scout.pool, strength: str) if Specialty.of(self)
      six.max_by(n) { |m| str[m] }
    end

    # Travel (match: false) or a match played (Growth.match_drain: fatigue).
    # A trip (FM::Travel) for the travelling party, the entry of six:
    # condition and hidden fatigue, days without training this week, and
    # the fare.
    # One night at `city`'s hotel before a match (design 05 호텔 숙박):
    # the fee and a day's rest x the hotel's multiplier, for the party.
    def stay_night(city, date:)
      lv = city.hotel
      entry.each do |m|
        m.cond = [m.cond + (Growth.rest_gain(m) / 7.0 * Travel.hotel_rest(lv)).round, 100].min
      end
      @wallet.record(-Travel.hotel_fee(lv), category: :travel, date: date)
      refresh_rating
    end

    def travel(trip, date:)
      return if trip[:days].zero? && trip[:cond].zero?
      entry.each do |m|
        Growth.drain(m, trip[:cond])
        m.fat = [m.fat + trip[:fat], 100].min
        m.away_days = m.away_days.to_i + trip[:days]
      end
      @wallet.record(-trip[:cost], category: :travel, date: date) if trip[:cost].positive?
      refresh_rating
    end

    def drain_lineup(amount, mons: lineup, match: false)
      mons.each do |m|
        match ? Growth.match_drain(m, amount) : Growth.drain(m, amount)
        m.played = true
      end
      refresh_rating
    end

    # The best three of the entry (topMons).
    def refresh_rating
      mons = Specialty.of(self) ? entry : @squad.reject(&:out?)
      @rating = Rating.team(mons.map do |m|
        h = m.to_rating
        d = Morale.disobey_p(m, self)
        h[:mul] *= 1 - d * Morale::FORMULA_DISOBEY if d.positive?
        h
      end)
    end

    def mon_ratings = @squad.map(&:rating)

    def food
      @squad.sum { |m| Economy.food(ovr: Economy.ovr(m.rating), fame: @fame) }
    end

    def weekly_cost
      food + Coach.weekly_food(self) + Nurse.weekly_food(self) + @facilities.values.sum { |lv| Economy.facility_keep(lv) } +
        Economy.stadium_keep(@stadium)
    end

    def coaches = @retired.select(&:coach)

    # Into the retired list (coach candidates), its food fixed as it was.
    def retire(mon)
      Items.give_back(self, mon)
      mon.coach = false
      mon.food_fixed = Economy.food(ovr: Economy.ovr(mon.rating), fame: @fame)
      @retired << mon
    end

    # Money beyond Invest's running-cost reserve.
    def spare
      @wallet.balance - weekly_cost * Invest::RESERVE_WEEKS
    end
  end

  class World
    attr_reader :calendar, :clubs, :leagues, :cities, :species, :cups
    # The club the player manages: the AI doesn't build, scout, sign or
    # release for it (emergency youth still applies). nil in older saves.
    attr_accessor :player_club

    def ai?(club) = club.id != @player_club

    # Static data a save keeps its own copy of (species pool, club types),
    # brought up to date from the game's compiled data on load: saves
    # made before a field existed (e.g. species :types / :prev) get it.
    def refresh_static(species:, club_types:)
      @species = species if species && !species.empty?
      Scout.pool = @species
      Morale.week = @week_key
      Morale.calendar = @calendar
      @clubs.each do |id, c|
        t = club_types[id]
        c.instance_variable_set(:@type, t) if t && c.type.nil?
      end
      ten_levels unless @fac_scale == 10
      @clubs.each_value { |c| Contract.fix(self, c) } if @sponsors
    end

    # Saves from before facilities had 10 levels: every level x2 (Lv5 -> Lv10),
    # projects too; the old top-level ages carry over.
    def ten_levels
      dbl = ->(p) { p && (p[:to] *= 2) && p[:from] && (p[:from] *= 2) }
      @clubs.each_value do |c|
        c.facilities.transform_values! { |lv| lv * 2 }
        dbl.(c.project) if c.project && c.project[:kind] == :building
        c.fac_age&.each_value { |a| a[:top] = 10 }
      end
      @cities.each_value do |c|
        c.buildings.each { |b| b[1] *= 2 }
        dbl.(c.project) if c.project && c.project[:kind] == :building
      end
      committees.each_value do |cm|
        cm.facilities.transform_values! { |lv| lv * 2 }
        dbl.(cm.project)
        cm.fac_age = nil
      end
      @fac_scale = 10
    end

    # Before a match (morPreMatch): each side's entry gets a talk unless it
    # had one this week. -> { club id => expected win, :big_after => bool }
    def pre_match(home, away, cup:)
      week = @week_key || date
      out = { big_after: cup }
      [[home, away], [away, home]].each do |c, o|
        pe = Morale.win_p(c, o)
        out[c.id] = pe
        mons = c.entry
        next if mons.empty? || mons.any? { |m| m.mood(week) }
        ctx = { f: pe - 0.5, big: big_match?(c, o, cup) }
        hook = Morale.player_talk
        pick = !ai?(c) && hook && hook.call(c, o, ctx, mons)
        tid, ind = pick.is_a?(Array) ? pick : [pick, {}]
        tid ||= Morale.coach_pick(mons, ctx, @rng)
        rep = 1
        if !ai?(c)
          (@talk_hist ||= []).reverse_each { |t| t == tid ? rep += 1 : break }
          @talk_hist = (@talk_hist + [tid]).last(3)
        end
        moods = Morale.apply(mons, tid, ctx, week, @rng, rep: rep, ind: ind || {})
        (@match_events ||= []) << { kind: :talk, club: c.id, talk: tid, moods: moods.values.tally, date: date } unless ai?(c)
      end
      out
    end

    # morBig: the PWT, or a late-season meeting near the top of the table.
    def big_match?(club, other, cup)
      return cup == :pwt if cup
      league = @leagues[club.region] or return false
      return false unless league.next_round >= league.rounds - 6
      a, b = league.position(club.id), league.position(other.id)
      (a <= 4 && b <= 6) || (b <= 4 && a <= 6)
    rescue StandardError
      false
    end

    # morWeek: morale toward the team's mood, bond with time; new mons get
    # their starting bond (bondInit).
    def morale_week
      year = @calendar.year
      @clubs.each_value do |c|
        c.squad.select(&:opened).each do |m|
          m.opened = nil
          (@match_events ||= []) << { kind: :bond_opened, club: c.id, species: m.species, date: date }
        end
        c.squad.each do |m|
          m.bond_year ||= year
          m.bond = Morale.bond_init(m, year, ai: ai?(c)) unless m.bond?
        end
        Morale.weekly(c, c.form)
      end
    end

    # The player's friendly tour (FM::Tour): next week only, or every
    # week it can.
    attr_accessor :tour_next, :tour_auto

    # FM::Legend: the registry, the PWT champion's right ({ club:, year:,
    # used: }) and the player's free gift candidate (with :until).
    attr_accessor :legends, :leg_right, :legend_gift

    # hasMatchT: a league round, or a cup game while still in it, this week.
    def official_match_week?(club, week = this_week)
      return true if week.any? { |d| league_date_set.key?(d) }
      cups = @cups or return false
      dates = cups[:dates]
      alive = lambda do |ko, id|
        ko.nil? || (!ko.done? && ko.bracket.last.include?(id))
      end
      %i[pet pent].each do |cup|
        next unless cups[cup][:players].include?(club.id) && week.any? { |d| dates[:pet].include?(d) }
        return true if alive.(cups[cup][:ko], club.id)
      end
      pwt = cups[:pwt]
      if pwt[:players].include?(club.id)
        sw = pwt[:swiss]
        return true if week.any? { |d| dates[:pwt_swiss].include?(d) } &&
                       (sw.nil? || (!sw.done? && sw.losses[club.id] < Tournament::SWISS_GOAL))
        return true if week.any? { |d| dates[:pwt_knockout].include?(d) } && pwt[:ko] && alive.(pwt[:ko], club.id)
      end
      false
    end

    def this_week = Array.new(7) { |i| @calendar.date_after(date, i) }

    def league_date_set
      @league_date_set = nil unless @league_date_set_year == @calendar.year
      @league_date_set_year = @calendar.year
      @league_date_set ||= league_dates.to_h { |d| [d, true] }   # (no Set: mkxp-z may lack the library)
    end

    # Daycare (FM::Daycare): the AI pairs every 13 weeks; eggs come and hatch.
    def daycare_week
      week_no = @calendar.days_between([@calendar.year, 1, 1], date) / 7 + 1
      @clubs.each_value.flat_map do |c|
        Daycare.ai_pick(self, c, week_no) if ai?(c)
        Daycare.week(self, c, @rng)
      end
    end

    # tourWeek
    def tour_week
      week = this_week
      @clubs.each_value.filter_map do |c|
        next if official_match_week?(c, week) || c.entry.size < 3
        if ai?(c)
          next if c.wallet.balance >= 0 && c.entry.any? { |m| m.cond < Tour::TIRED }
          next unless @rng.rand < Tour.ai_chance(c)
        else
          next unless tour_next || tour_auto
          self.tour_next = false
        end
        { kind: :tour, club: c.id, pay: Tour.go(c, date: date), date: date }
      end
    end

    # { region => its capital City }, for tournament trips.
    def capitals
      @cities.values.select(&:capital?).to_h { |c| [c.region, c] }
    end

    # The transport hub level of `city`'s region (its league committee).
    def hub(city)
      city && committees[city.region]&.facilities&.fetch(:HUB, 0).to_i
    end

    # Optional hook for the player's own matches: called as
    # hook.(home_club, away_club, world, neutral:) and returns a result hash
    # ({ res:, ko_a:, ko_b: }, home's view) or nil for the formula. Set by
    # the engine side (a real battle); kept on the class, not in saves.
    class << self
      attr_accessor :player_match
    end

    # `important`: cup finals (design 06: always asked, whatever the
    # player's default match mode).
    def play_match(home, away, rng:, neutral: false, important: false)
      gims = Gimmick.for_match(self, home, cup: neutral)
      hook = World.player_match
      if hook && @player_club && [home.id, away.id].include?(@player_club)
        r = hook.call(home, away, self, neutral: neutral, important: important, gimmicks: gims)
        return r if r
      end
      MatchSim.play(home.rating * Gimmick.side_mul(@species, home.lineup, gims),
                    away.rating * Gimmick.side_mul(@species, away.lineup, gims), rng: rng)
    end

    # A scout trip in `region` for the player's club (FM::Recruit.scout).
    # The player's scouting office (FM::Scouting): assignments, the
    # candidate list and the next regular report.
    attr_accessor :scouting
    attr_accessor :hof   # FM::Hof.of
    # FM::Events: the pending event, the last one's [year, week], the press
    # week, the player's last official result and the two boasts.
    attr_accessor :event, :ev_last, :press_week, :last_official, :boast, :fs_boast
    attr_accessor :h2h, :rival, :taunt   # FM::Rival
    attr_accessor :sponsor_offers   # FM::Contract: the player's offers to pick from
    attr_accessor :my_title         # FM::Titles: the title the player shows (nil = the first)
    attr_accessor :pwt_hosts        # FM::Gimmick.pwt_host: year => region
    attr_reader :rng
    def sponsor_table = @sponsors

    def send_scout(region, type: nil, spec: nil)
      Scouting.send(self, @clubs.fetch(@player_club), region, type: type, spec: spec, date: date)
    end

    # The PWT title's gift (free, outside the signing limit); `release`
    # makes room in a full squad.
    def claim_legend_gift(release: nil)
      g = @legend_gift or return nil
      c = @clubs.fetch(@player_club)
      return nil if Legend.block?(self, c, g[:mon].species)
      if c.squad.size >= Build.squad_size(c.clubhouse)
        return nil unless release && c.squad.include?(release)
        Items.give_back(c, release)
        c.squad.delete(release)
        c.retire(release)
      end
      c.squad << g[:mon]
      c.refresh_rating
      @legend_gift = nil
      Legend.acquire(self, c, g[:mon])
    end

    # species: FM::Scout pool (PBS/fm_species.txt). Without it squads stay
    # fixed (no growth, aging or scouting) — enough for league/economy tests.
    def self.new_game(club_data, seed:, cities: [], species: nil, sponsors: nil)
      new(club_data.map { |d| Club.new(d) }, seed: seed, cities: cities.map { |d| City.new(d) },
          species: species, sponsors: sponsors)
    end

    def initialize(clubs, seed:, cities: [], species: nil, sponsors: nil)
      @calendar = Calendar.new
      @clubs    = clubs.to_h { |c| [c.id, c] }
      @cities   = cities.to_h { |c| [c.id, c] }
      @species  = species
      @fac_scale = 10   # facilities on 10 levels (older saves: 5, see refresh_static)
      Scout.pool = species if species
      @sponsors = sponsors
      @clubs.each_value do |c|
        city = @cities[c.city] or next
        city.club_ids << c.id
        c.city_size = city.size
      end
      @rng      = Random.new(seed)
      @league_dates = {}
      seed_squads if @species
      Legend.registry(self) if @species   # initLegends: holders registered, legends made symbols
      @clubs.each_value(&:refresh_rating) if @species
      sign_sponsors
      start_leagues
    end

    # Every club takes its best offer for the season (aiPickSponsor).
    def sign_sponsors
      return unless @sponsors
      return Contract.new_year(self)
      @clubs.each_value do |c|
        offers = Sponsor.offers(@sponsors, region: c.region, fame: c.fame, clubhouse: c.clubhouse,
                                           bans: c.sponsor_bans, year: @calendar.year, rng: @rng)
        c.sponsor = Sponsor.ai_pick(offers)
      end
    end

    # buildWorld: starting mons get an age of 0-4 and the EVs that age would
    # have built up, if more than their level implies.
    def seed_squads
      @clubs.each_value do |c|
        t = Growth.original_level(c.facilities.fetch(:TRAINING, 0))
        c.squad.each do |m|
          m.age = @rng.rand(5)
          by_level = Growth::EV_MAX * ((m.level - 8) / 62.0).clamp(0.0, 1.0)
          by_age = Growth::EV_MAX * [1.0, m.age / Growth.grow_seasons(t)].min
          m.ev = [by_level, by_age].max
        end
        c.refresh_rating
      end
    end

    def avg_level(region)
      ms = @clubs.values.select { |c| c.region == region }.flat_map(&:squad)
      ms.empty? ? 30 : ms.sum(&:level).fdiv(ms.size)
    end

    def regions
      @clubs.values.map(&:region).uniq
    end

    def advance_days(days)
      Array.new(days) { advance_day }.flatten
    end

    # Moves to the next day and plays whatever happens on it.
    def advance_day
      events = []
      @calendar.advance(1).each do |kind, _|
        case kind
        when :new_year
          events.concat(Legend.season_end(self)) if @species
          events.concat(season_rollover)
          events.concat(Transfer.run(self, @calendar.year))
          sign_sponsors
          start_leagues
          reset_cups
          (e = @species && Legend.ai_claim(self, @rng)) && events << e
          @legend_gift = nil if @legend_gift && (@legend_gift[:until] <=> date) .negative?
          events << { kind: :new_year, year: @calendar.year }
        when :new_week
          @week_key = date
          Morale.week = date
          Morale.calendar = @calendar
          weekly_economy
          if (pc = @player_club && @clubs[@player_club])
            events.concat(Fans.week(pc, self, date: date))
            if (s = pc.sponsor) && Contract.v2?(s) && !s[:human]   # the player took over the club
              s[:human] = true
              Contract.season(self, pc, fresh: true)
            end
            events.concat(Contract.week(self, pc))
            (e = Rival.current(self).nil? && Rival.pick(self, pc, @rng)) && events << e
            events.concat(Events.week(self, pc, @rng))
            lg = @leagues && @leagues[pc.region]
            if (pc.goal.nil? || pc.goal[:year] != @calendar.year) && lg && lg.next_round.zero?
              events << Goals.set(self, pc)
            end
          end
          @clubs.each_value { |c| events.concat(Credit.week(c, date: date, calendar: @calendar)) }
          city_economy
          events.concat(finish_projects)
          events.concat(finish_city_projects)
          @clubs.each_value { |c| events.concat(Aging.club_week(self, c)) }
          @cities.each_value { |c| events.concat(Aging.city_week(self, c)) }
          committees.each_value { |cm| events.concat(Aging.committee_week(self, cm)) }
          committees.each_value do |cm|
            cm.weekly(self, date)
            (e = cm.finish(self, date)) && events << e
          end
          undo_loans if @loans
          if @player_club && @species
            events.concat(Scouting.week(self, @clubs.fetch(@player_club), date: date, rng: @rng))
          end
          events.concat(tour_week)
          nurse_week
          item_week if @species
          events.concat(daycare_week) if @species
          events.concat(condition_week)
          morale_week
          events.concat(squad_week) if @species
          @clubs.each_value { |c| Invest.decide(c, date: date, calendar: @calendar) if ai?(c) && !Credit.austerity?(c) }
        when :new_month
          events.concat(Meeting.monthly(self, date: date))
          if Committee::QUARTER_MONTHS.include?(@calendar.month)
            committees.each_value { |cm| (e = cm.quarterly(self, date)) && events << e }
          end
        end
      end
      round = league_dates.index(@calendar.date)
      if round
        @leagues.each do |region, league|
          next if league.done? || league.next_round != round
          events << play_league_round(region, league)
          events << finish_league(region, league) if league.done?
        end
      end
      if @cups.nil? && @leagues.values.all?(&:done?)
        events.concat(Titles.update(self))
        events.concat(Cups.setup(self, rng: @rng))
      end
      events.concat(Cups.play_day(self, rng: @rng)) if @cups
      events.concat(@match_events) if @match_events
      @match_events = nil
      events.each { |e| (c = @clubs[e[:club]]) && Contract.buzz(self, c) if Contract::BUZZ_KINDS.include?(e[:kind]) }
      events
    end

    # After any match (league or cup): both sides that played lose
    # condition and gain fatigue, and those knocked out may be hurt
    # (FM::Injury). `lineups` are the mons that played, taken before the
    # match; a real battle's result may name them (:lineup_a/:lineup_b)
    # and who fainted (:fainted_a/:fainted_b). Injury events are added to
    # the day's events.
    # fans: false for the games inside a best-of-3 (its result counts once).
    def after_match(home, away, r, lineups, league: false, talk: nil, fans: true)
      fan_result(home, away, r[:res], league: league) if fans
      la = r[:lineup_a] || lineups[0]
      lb = r[:lineup_b] || lineups[1]
      [[home, la, r[:fainted_a], r[:ko_b], r[:ko_a]], [away, lb, r[:fainted_b], r[:ko_a], r[:ko_b]]].each do |club, mons, fainted, ko, scored|
        fainted ||= mons.sample([ko.to_i, mons.size].min, random: @rng)
        mons.each do |m|
          m.gp += 1
          m.sgp += 1 if league
        end
        kos = {}.compare_by_identity
        scored.to_i.times do   # who scored isn't known: a random mon that played
          next if mons.empty?
          m = mons[@rng.rand(mons.size)]
          m.ko += 1
          m.sko += 1 if league
          kos[m] = (kos[m] || 0) + 1
        end
        disob = club.equal?(home) ? r[:disobeyed_a] : r[:disobeyed_b]
        (disob || {}).each do |m, n|
          m.disob += 1
          (@match_events ||= []) << { kind: :disobeyed, club: club.id, species: m.species, times: n, bond: m.bond.floor, date: date }
        end
        if talk
          won = club.equal?(home) ? r[:res].positive? : r[:res].negative?
          Morale.after_match(club, mons, fainted, kos, won: won, pe: talk[club.id], big: talk[:big_after])
        end
        used = club.equal?(home) ? r[:consumed_a] : r[:consumed_b]
        Items.consumed(club, used) if used
        club.drain_lineup(Growth::MATCH_COND, mons: mons, match: true)
        Injury.after_match(mons, fainted, club.facilities[:MEDICAL], @rng, nurse: Nurse.pow(club)).each do |m, info|
          (@match_events ||= []) << injury_event(club, m, info)
        end
        club.refresh_rating
      end
    end

    # fsResult for the player's side of a game or series (res: home view).
    def fan_result(home, away, res, series: false, league: false)
      [[home, away, res], [away, home, -res]].each do |c, o, my|
        next if ai?(c)
        Rival.count(self, o.id, my)
        Contract.match(c, my <=> 0, date: date) if league
        Contract.buzz(self, c) if my.positive? && Fans.team_ovr(o) - Fans.team_ovr(c) >= 10   # an upset win
        Fans.result(c, o, my <=> 0, series: series, date: date, rival: Rival.rival?(self, o.id))
        (e = league && Rival.result(self, c, o.id, my)) && (@match_events ||= []) << e
        Events.result(self, c, my <=> 0, league: league)
      end
    end

    # The player's ticket price (the reference until set; FM::Fans.set_price).
    attr_writer :ticket_price
    def ticket_price
      @ticket_price ||= (c = @clubs[@player_club]) ? Economy.price(c.fame) : 1
    end

    # Player promises from meetings (FM::Meeting.settle_promises).
    def promises = @promises ||= []

    # A brief build had meeting loans, which Poké Manager has no such thing
    # as; saves from it send every lent mon home at the next Monday.
    def undo_loans
      @loans.each do |l|
        mon = l[:mon]
        mon.remove_instance_variable(:@loan_from) if mon.instance_variable_defined?(:@loan_from)
        next unless @clubs[l[:to]].squad.delete(mon)
        @clubs[l[:from]].squad << mon
      end
      @clubs.each_value(&:refresh_rating)
      remove_instance_variable(:@loans)
    end

    def injury_event(club, mon, info)
      { kind: :injured, club: club.id, species: mon.species, date: date }.merge(info)
    end

    # Region strength for PWT places: mean PWT points of its clubs over the
    # last three seasons, weighted 1 / 0.6 / 0.3 (leagueCoef). Before any
    # PWT, the mean rating of its best four clubs.
    def league_coefficients
      year = @calendar.year
      by_region = @clubs.values.group_by(&:region)
      by_region.to_h do |region, cs|
        score = 0.0
        has = false
        [1.0, 0.6, 0.3].each_with_index do |weight, i|
          entries = cs.filter_map { |c| c.history[year - i] }.select { |h| h[:pwt] }
          next if entries.empty?
          has = true
          score += entries.sum { |h| Tournament.pwt_points(h[:pwt], wins: h[:pwt_wins] || 0) } / entries.size.to_f * weight
        end
        score = cs.map(&:rating).max(4).sum / 4.0 unless has
        [region, score]
      end
    end

    def reset_cups
      @cups = nil
    end

    def set_cups(cups)
      @cups = cups
    end

    private

    def league_dates
      @league_dates[@calendar.year] ||= Season.league_dates(@calendar, @calendar.year)
    end

    # A transfer before the first round: the leagues are drawn again.
    def redraw_leagues
      start_leagues
      pc = @player_club && @clubs[@player_club]
      (@match_events ||= []) << Goals.set(self, pc) if pc
    end
    public :redraw_leagues

    def start_leagues
      @leagues = regions.to_h do |region|
        ids = @clubs.values.select { |c| c.region == region }.map(&:id)
        [region, League.new(ids, rng: @rng)]
      end
    end

    def date
      @calendar.date
    end

    def play_league_round(region, league)
      round = league.next_round
      pc = @player_club && @clubs[@player_club]
      if round.zero? && pc && pc.region == region && @sponsor_offers   # sp2AutoPick at the first round
        Contract.sign(self, pc, Contract.auto_pick(@sponsor_offers))
        @sponsor_offers = nil
      end
      before = league.standings
      # Early on the table means little; rank by strength instead (original).
      ranking = round < 3 ? before.sort_by { |id| -@clubs[id].rating } : before
      results = league.play_round do |home_id, away_id|
        home, away = @clubs[home_id], @clubs[away_id]
        hc, ac = @cities[home.city], @cities[away.city]
        fans = hc && ac && Civic.away_fans(away_fame: away.fame, from: ac, to: hc,
                                           capacity: Economy.capacity(home.stadium))
        mine = !ai?(home)
        gate = Economy.gate(home_fame: home.fame, away_fame: away.fame, wins: home.recent_wins,
                            stadium: home.stadium, rng: @rng, away: fans && fans[:fans],
                            mood: hc ? hc.crowd_mood : 1.0, price: mine ? ticket_price : nil,
                            fans: mine ? Fans.att_mul(home) : 1.0)
        Fans.home_game(home, ticket_price, date: date) if mine
        tourism = fans ? (fans[:lodging] * Civic::LODGE_SPEND).round : 0
        hc.budget.record(tourism, category: :tourism, date: date) if tourism.positive?
        home.wallet.record(gate[:revenue], category: :gate, date: date) if gate[:revenue].positive?
        home.push_fill(gate[:attendance].fdiv(Economy.capacity(home.stadium)))
        a = home.att = home.att && home.att[:year] == @calendar.year ? home.att : { year: @calendar.year, sum: 0, n: 0 }
        a[:sum] += gate[:attendance]
        a[:n] += 1
        contribute(home, gate[:revenue])
        go = Travel.land(ac, hc, hub: hub(hc))
        away.travel(go, date: date)
        away.stay_night(hc, date: date) if go[:days].positive?   # arrived the day before
        lineups = [home.lineup, away.lineup]
        talk = pre_match(home, away, cup: false)
        r = play_match(home, away, rng: @rng)
        after_match(home, away, r, lineups, league: true, talk: talk)
        away.travel(Travel.land(hc, ac, arrive_before: false, hub: hub(ac)), date: date)   # home again (귀환)
        settle(r, home, away, ranking)
        r.slice(:res, :ko_a, :ko_b).merge(attendance: gate[:attendance])
      end
      { kind: :league_round, region: region, round: round + 1, date: date, results: results }
    end

    def settle(r, home, away, ranking)
      if r[:res].zero?
        relations.derby(home.id, away.id, draw: true) if home.city == away.city
        [home, away].each do |c|
          c.wallet.record(Economy::DRAW_BONUS, category: :bonus, date: date)
          c.push_form(:d)
        end
        return
      end
      winner, loser = r[:res].positive? ? [home, away] : [away, home]
      relations.derby(winner.id, loser.id) if home.city == away.city
      gap = [ranking.index(winner.id) - ranking.index(loser.id), 0].max
      winner.wallet.record(Economy::WIN_BONUS + gap * Economy::UPSET_PER_RANK, category: :bonus, date: date)
      upset = loser.fame > winner.fame + 15 ? 0.25 : 0
      winner.fame = Economy.add_fame(winner.fame, 0.4 + upset)
      loser.fame  = Economy.add_fame(loser.fame, -0.15)
      winner.push_form(:w)
      loser.push_form(:l)
    end

    # Poké Manager econWeek, every Monday: interest, food, building and
    # stadium upkeep out; merchandise in. Sponsors wait for the design's
    # contract system.
    def weekly_economy
      @clubs.each_value do |c|
        w = c.wallet
        interest = Economy.debt_interest(w.balance)
        w.record(-interest, category: :interest, date: date) if interest.positive?
        food = c.food
        w.record(-food, category: :food, date: date) if food.positive?
        keep = c.facilities.values.sum { |lv| Economy.facility_keep(lv) }
        w.record(-keep, category: :fac, date: date) if keep.positive?
        cp = Coach.weekly_food(c)
        w.record(-cp, category: :coach, date: date) if cp.positive?
        w.record(-Economy.stadium_keep(c.stadium), category: :std, date: date)
        legend = @species && Legend.held(c, @species)
        merch = (Economy.merch(c.fame) * (legend ? Legend::MERCH_MUL : 1) * (ai?(c) ? 1 : Fans.merch_mul(c))).round
        c.fame = Economy.add_fame(c.fame, Legend::FAME_WEEK) if legend
        w.record(merch, category: :merch, date: date) if merch.positive?
        pay_sponsor(c)
      end
    end

    def pay_sponsor(c)
      s = c.sponsor or return
      if s[:kind] == "RISKY" && @rng.rand < Sponsor::BUST_CHANCE
        c.sponsor = nil
        return
      end
      c.wallet.record((s[:base] / 52.0).round, category: :spon, date: date)
    end

    # sponSeasonEnd, plus the bonus for a top-4 finish.
    def sponsor_season_end(c, pos)
      s = c.sponsor or return
      return (@match_events ||= []).concat(Contract.evaluate(self, c, pos)) if Contract.v2?(s)
      if %w[PERF STRICT].include?(s[:kind]) && pos <= Sponsor::BONUS_POSITION && s[:bonus].positive?
        c.wallet.record(s[:bonus], category: :spon, date: date)
      end
      c.fame = Economy.add_fame(c.fame, Sponsor::FAME_BONUS) if s[:kind] == "FAME"
      c.sponsor_bans[s[:id]] = @calendar.year + Sponsor::STRICT_BAN_SEASONS if s[:kind] == "STRICT" && pos > Sponsor::BONUS_POSITION
    end

    def season_rollover
      events = []
      relations.season_decay
      @clubs.each_value do |c|
        c.fame = Growth.fame_drift(c.fame)
        next unless @species
        gone = Growth.rollover(c.squad)
        gone.each do |m|
          c.retire(m)
          (e = Hof.retired(self, c, m)) && events << e
        end
        c.squad.each { |m| m.sko = m.sgp = 0 }   # a new season's record
        Coach.ai_pick(c) if ai?(c)
        c.refresh_rating
        events << { kind: :retired, club: c.id, mons: gone.map(&:species), date: date } unless gone.empty?
      end
      events
    end

    # Design 05: the condition an away side loses getting to `home`
    # (FM::Travel.land; same city: none).
    def travel_fatigue(away, home)
      Travel.land(@cities[away.city], @cities[home.city])[:cond]
    end


    # aiShopAll (week % 4 == 1): AI clubs buy held items.
    def item_week
      return unless ((@calendar.day_of_year - 1) / 7) % Items::AI_EVERY == 0
      @clubs.each_value do |c|
        next unless ai?(c) && !Credit.austerity?(c)
        c.refresh_rating if Items.ai_shop(c, @species, date: date, world: self).positive?
      end
    end

    # nurseWeek for every club with nurses; aiNurses every 13 weeks.
    def nurse_week
      ai_turn = ((@calendar.day_of_year - 1) / 7) % Nurse::AI_EVERY == 0
      @clubs.each_value do |c|
        Nurse.ai_pick(c) if ai_turn && ai?(c)
        Nurse.week(c, date: date) if c.squad.any?(&:nurse) || c.retired.any?(&:nurse)
      end
    end

    # Monday: injuries heal (medical center), condition and fatigue move,
    # then a training week may hurt. -> :injured / :recovered events.
    def condition_week
      events = []
      staying = Cups.staying(self)
      @clubs.each_value do |c|
        med = c.facilities[:MEDICAL]
        nurse = Nurse.pow(c)
        rest = staying[c.id] ? Travel.hotel_rest(staying[c.id].hotel) : 1.0
        c.squad.each do |m|
          if Injury.heal_week(m, med, @rng, nurse: nurse)
            events << { kind: :recovered, club: c.id, species: m.species, rehab: m.rehab, date: date }
          end
          Growth.condition_week(m, rest_mul: rest)
          (info = Injury.train_week(m, @rng)) && events << injury_event(c, m, info)
        end
        c.refresh_rating
      end
      events
    end

    def squad_week
      events = []
      window = recruit_window?
      regs = regions
      avgs = regs.to_h { |r| [r, avg_level(r)] }
      @clubs.each_value do |c|
        train = c.facilities.fetch(:TRAINING, 0)
        st = Coach.staff(c, @species)
        mine = !ai?(c)
        pay = mine ? nil : ->(item) { c.wallet.record(-Items.price(c, item), category: :shop, date: date) }
        c.squad.each do |m|
          Growth.week(m, train_level: train, species: @species, fx: Coach.fx(c, m, @species, st), hold: mine, pay: pay)
        end
        avg = avgs[c.region]
        released = ai?(c) ? Recruit.budget(c, pool: @species) : []
        events << { kind: :released, club: c.id, mons: released, date: date } unless released.empty?
        youth = Recruit.emergency(c, pool: @species, avg_level: avg, rng: @rng)
        events << { kind: :youth, club: c.id, mons: youth, date: date } unless youth.empty?
        e = ai?(c) && Recruit.weekly(c, pool: @species, regions: regs, avg_level: avg,
                                      window: window, date: date, rng: @rng)
        events << e if e
        c.refresh_rating
      end
      events
    end

    # aiScoutWeek's transfer windows: the first weeks of the league and the
    # weeks after it ends.
    def recruit_window?
      dates = league_dates
      d = @calendar.days_until(dates.first)
      e = @calendar.days_until(dates.last)
      d.between?(-21, 0) || e.between?(-28, 0)
    end

    # Design 04: clubs pay into their city's public budget (공공예산 기여금).
    def contribute(club, gate_revenue)
      city = @cities[club.city] or return
      amount = (gate_revenue * Civic::CONTRIBUTION_RATE).round
      return unless amount.positive?
      club.wallet.record(-amount, category: :city, date: date)
      city.budget.record(amount, category: :contribution, date: date)
    end

    def city_economy
      @cities.each_value do |c|
        c.budget.record((Civic.weekly_tax(c.size) * c.tax_rate).round, category: :tax, date: date)
        c.drift_satisfaction
        keep = c.weekly_upkeep
        c.budget.record(-keep, category: :upkeep, date: date) if keep.positive?
      end
    end

    def finish_city_projects
      @cities.each_value.filter_map do |c|
        p = c.project
        next unless p && @calendar.days_until(p[:done]) <= 0
        c.project = nil
        if p[:kind] == :building
          b = c.buildings.find { |x, *| x == p[:target] }
          b ? b[1] = p[:to] : c.buildings << [p[:target], p[:to]]
          Aging.built(c, p[:target], p[:to])
          next { kind: :city_built, city: c.id, what: p[:target], level: p[:to], date: date }
        end
        c.free_plots += Civic.public_plots(p[:to]) - Civic.public_plots(c.size)
        c.size = p[:to]
        c.club_ids.each { |id| @clubs[id].city_size = c.size }
        { kind: :city_grown, city: c.id, size: c.size, date: date }
      end
    end

    def finish_projects
      @clubs.each_value.filter_map do |c|
        p = c.project
        next unless p && @calendar.days_until(p[:done]) <= 0
        case p[:kind]
        when :building
          c.facilities[p[:target]] = p[:to]
          Aging.built(c, p[:target], p[:to])
        when :clubhouse then c.clubhouse = p[:to]
        when :stadium   then c.stadium = p[:to]
        end
        c.project = nil
        { kind: :built, club: c.id, what: p[:target], level: p[:to], date: date }
      end
    end

    def finish_league(region, league)
      standings = league.standings
      standings.each_with_index do |id, i|
        pos = i + 1
        c = @clubs[id]
        c.wallet.record(Economy.league_prize(pos), category: :prize, date: date)
        aid = Economy.rebuild_aid(pos)
        c.wallet.record(aid, category: :aid, date: date) if aid.positive?
        c.fame = Economy.add_fame(c.fame, (11 - pos) * 0.6 + (pos == 1 ? 5 : 0))
        sponsor_season_end(c, pos)
        (c.history[@calendar.year] ||= {})[:pos] = pos
        (e = !ai?(c) && Goals.check(self, c, pos)) && (@match_events ||= []) << e
      end
      # Titles (league won, 8+ games) and the region's KO king.
      year = @calendar.year
      @clubs[standings.first].squad.each { |m| m.titles << [year, :league] if m.sgp >= Coach::TITLE_GAMES }
      king = standings.flat_map { |id| @clubs[id].squad }.max_by(&:sko)
      king.awards << [year, :ko_king] if king && king.sko.positive?
      (@match_events ||= []).concat(Hof.season_awards(self, region, league, standings))
      if (cm = committees[region])
        cm.seat_gym_reps(self, standings)
        cm.distribute(self, standings, date)
      end
      { kind: :league_end, region: region, date: date, standings: standings }
    end

    public

    # One per region with a capital (form LEAGUE). Built on first use, so
    # worlds saved before committees existed get them on load.
    def relations
      @relations ||= Relations.new   # older saves get an empty one
    end

    def committees
      @committees ||= @cities.values.select(&:capital?).to_h do |c|
        [c.region, Committee.new(region: c.region, city_id: c.id)]
      end
    end
  end
end
