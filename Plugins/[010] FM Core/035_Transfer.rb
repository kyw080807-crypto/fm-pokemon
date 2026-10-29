#===============================================================================
# FM::Transfer — 지방 이적 (Poké Manager: MOVE_FAME, movePartner, moveWhy,
# moveNow, moveHomeCount, moveDo, moveRunAll). Pure Ruby; the player only.
# - The club keeps its Pokémon, money and history. Fame -30%, the training
#   ground and scouting office back to Lv1 (their aging too; the medical
#   center and the rest stay), a rented stadium, any project dropped with
#   no refund, extra coaches step down. Fans start at 50 (+0.5 for the
#   first meeting), the ticket price back to the reference, a new season
#   goal if the league hasn't started.
# - The weakest ordinary trainer of the new region (non-canon T first,
#   then any T, then anyone) takes the old place, so every league keeps
#   its size; if their roles differ they swap roles.
# - Before any league round of the season it happens at once (leagues
#   drawn again); during the season it waits for the new year. Once a
#   season.
# Our clubs belong to a home city, which the original doesn't have: the
# two clubs swap cities as well. A club moving into a capital plays at
# the committee's side stadium, into a MILAN city its partner's; one
# leaving a shared stadium goes back to renting.
#===============================================================================
module FM
  module Transfer
    FAME_CUT = 0.3
    FANS_START = 50

    module_function

    # moveWhy -> nil or the reason it can't
    def why_not(world, club)
      year = world.calendar.year
      return :moved if club.moved_year == year && now?(world)
      return :pending if club.move_to
      return :moved if club.moved_year == year + 1
      nil
    end

    # moveNow: no league round played yet this season.
    def now?(world) = world.leagues.values.all? { |l| l.next_round.zero? }

    def home_count(world, club, region) = club.squad.count { |m| Scout.home?(world.species, m.species, region) }

    # movePartner
    def partner(world, club, to)
      pool = world.clubs.values.select { |c| c.region == to && !c.equal?(club) && c.move_to.nil? }
      pick = ->(a) { a.min_by { |c| [Fans.team_ovr(c), c.id.to_s] } }
      pick.(pool.select { |c| c.role == "T" && !c.canon }) || pick.(pool.select { |c| c.role == "T" }) || pick.(pool)
    end

    # -> :moved (done now), :requested, or why not
    def request(world, club, to)
      return :same if to == club.region || !world.regions.include?(to)
      w = why_not(world, club)
      return w if w
      club.move_to = to
      return :requested unless now?(world)
      run(world, world.calendar.year)
      world.redraw_leagues
      :moved
    end

    def cancel(club) = club.move_to = nil

    # moveRunAll -> events
    def run(world, year)
      world.clubs.values.select(&:move_to).filter_map { |c| apply(world, c, year) }
    end

    # moveDo -> the event or nil
    def apply(world, club, year)
      to = club.move_to
      club.move_to = nil
      return if to.nil? || to == club.region
      from = club.region
      o = partner(world, club, to)
      date = world.calendar.date
      if o
        my_city, o_city = club.city, o.city
        my_role, o_role = club.role, o.role
        swap_city(world, club, from: my_city, to: o_city, region: to, role: o_role == my_role ? my_role : o_role)
        swap_city(world, o, from: o_city, to: my_city, region: from, role: o_role == my_role ? o_role : my_role)
        world.committees.each_value { |cm| cm.gym_reps.reject! { |id| id == club.id || id == o.id } }
      else
        club.relocate(region: to, city: club.city, role: club.role, city_size: club.city_size)
      end
      fame0 = club.fame
      club.fame = Economy.add_fame(club.fame, -club.fame * FAME_CUT)
      %i[TRAINING SCOUTING].each do |b|
        club.facilities[b] = 1
        club.fac_age&.delete(b)
      end
      club.project = nil
      fix_stadium(world, club, reset: true)
      club.coaches.drop(Coach.slots(club)).each { |m| m.coach = false }
      club.home_fill.clear
      club.moved_year = year
      club.fsat = FANS_START
      club.fs_log = []
      Fans.add(club, 0.5, :new_region, date: date)
      world.ticket_price = nil
      world.boast = world.fs_boast = nil
      world.rival = world.taunt = nil
      club.goal = nil
      [club, o].compact.each(&:refresh_rating)
      { kind: :region_moved, club: club.id, from: from, to: to, partner: o&.id, fame0: fame0, fame: club.fame,
        city: club.city, date: date }
    end

    def swap_city(world, c, from:, to:, region:, role:)
      world.cities[from]&.club_ids&.delete(c.id)
      city = world.cities[to]
      city.club_ids << c.id if city && !city.club_ids.include?(c.id)
      c.relocate(region: region, city: to, role: role, city_size: city ? city.size : c.city_size)
      fix_stadium(world, c)
    end

    # A capital's clubs play at the side stadium, a MILAN city's pair share
    # one; leaving them, rent.
    # reset: the mover's own stadium is gone either way (the original).
    def fix_stadium(world, c, reset: false)
      city = world.cities[c.city]
      if city&.capital?
        cm = world.committees[city.region]
        c.stadium_shared = true
        c.stadium = Committee.stadium_of(cm ? cm.facilities[:SIDE_STADIUM] : 0)
      elsif city&.form == "MILAN"
        mate = city.club_ids.map { |id| world.clubs[id] }.find { |x| x && !x.equal?(c) }
        c.stadium_shared = true
        c.stadium = mate ? mate.stadium : 0
      elsif c.stadium_shared || reset
        c.stadium_shared = false
        c.stadium = 0
      end
    end
  end
end
