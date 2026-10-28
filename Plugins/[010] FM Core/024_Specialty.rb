#===============================================================================
# FM::Specialty — 전문 타입 규정 (design 00: 관장·사천왕의 전문 타입 규칙을
# 포켓 매니저에서 그대로 이식, player included). Pure Ruby, from Poké
# Manager's SIG_BY / sigOf / sigMon / sigBlock / sigParty / genCand hook:
# - The type belongs to the post (region + role), not the trainer: Kanto's
#   G1 is rock whoever holds it. Champions, rival Elite Four (no entry in
#   the table) and ordinary trainers are free.
# - A mon counts if it has the type now or gains it by evolving.
# - Squad: at most squad size - SQUAD_SHARE mons of other types may be
#   signed (those already there stay). Entry: at most ENTRY_SIZE -
#   ENTRY_SHARE of other types (the strongest of them), the rest filled
#   with the strongest specialty mons.
# - Scouting brings a specialty-type candidate SCOUT_SHARE of the time; the
#   AI scores specialty candidates x1.35, others x0.75 (on top of the
#   club-type x1.25 / x0.6).
# Mons don't carry types, so this reads the species pool the world
# registers in Scout.pool.
#===============================================================================
module FM
  module Specialty
    SQUAD_SHARE = 6
    ENTRY_SHARE = 4
    SCOUT_SHARE = 0.55
    SCORE_SIG = 1.35
    SCORE_OTHER = 0.75

    # SIG_BY, by region.
    TYPES = {
      "KANTO"  => { "E1" => "ICE", "E2" => "FIGHTING", "E3" => "GHOST", "E4" => "POISON", "G1" => "ROCK", "G2" => "WATER",
                    "G3" => "ELECTRIC", "G4" => "GRASS", "G5" => "POISON", "G6" => "PSYCHIC", "G7" => "FIRE", "G8" => "GROUND" },
      "JOHTO"  => { "E1" => "PSYCHIC", "E2" => "DARK", "G1" => "FLYING", "G2" => "BUG", "G3" => "NORMAL", "G4" => "GHOST",
                    "G5" => "FIGHTING", "G6" => "STEEL", "G7" => "ICE", "G8" => "DRAGON" },
      "HOENN"  => { "E1" => "DARK", "E2" => "GHOST", "E3" => "ICE", "E4" => "DRAGON", "G1" => "ROCK", "G2" => "FIGHTING",
                    "G3" => "ELECTRIC", "G4" => "FIRE", "G5" => "NORMAL", "G6" => "FLYING", "G7" => "PSYCHIC", "G8" => "WATER" },
      "SINNOH" => { "E1" => "BUG", "E2" => "GROUND", "E3" => "FIRE", "E4" => "PSYCHIC", "G1" => "ROCK", "G2" => "GRASS",
                    "G3" => "FIGHTING", "G4" => "WATER", "G5" => "GHOST", "G6" => "STEEL", "G7" => "ICE", "G8" => "ELECTRIC" },
      "UNOVA"  => { "E1" => "GHOST", "E2" => "DARK", "E3" => "PSYCHIC", "E4" => "FIGHTING", "G1" => "GRASS", "G2" => "NORMAL",
                    "G3" => "BUG", "G4" => "ELECTRIC", "G5" => "GROUND", "G6" => "FLYING", "G7" => "ICE", "G8" => "DRAGON" },
      "KALOS"  => { "E1" => "FIRE", "E2" => "WATER", "E3" => "STEEL", "E4" => "DRAGON", "G1" => "BUG", "G2" => "ROCK",
                    "G3" => "FIGHTING", "G4" => "GRASS", "G5" => "ELECTRIC", "G6" => "FAIRY", "G7" => "PSYCHIC", "G8" => "ICE" },
      "ALOLA"  => { "E1" => "FIGHTING", "E2" => "ROCK", "E3" => "GHOST", "E4" => "FLYING", "G1" => "NORMAL", "G2" => "WATER",
                    "G3" => "FIRE", "G4" => "GRASS", "G5" => "ELECTRIC", "G6" => "FAIRY", "G7" => "GROUND", "G8" => "STEEL" },
      "GALAR"  => { "E1" => "DRAGON", "G1" => "GRASS", "G2" => "WATER", "G3" => "FIRE", "G4" => "FIGHTING", "G5" => "GHOST",
                    "G6" => "FAIRY", "G7" => "ROCK", "G8" => "DARK" },
      "PALDEA" => { "E1" => "GROUND", "E2" => "STEEL", "E3" => "DRAGON", "G1" => "BUG", "G2" => "GRASS", "G3" => "ELECTRIC",
                    "G4" => "WATER", "G5" => "NORMAL", "G6" => "GHOST", "G7" => "PSYCHIC", "G8" => "ICE" }
    }.freeze

    module_function

    # sigOf
    def of(club)
      return nil unless club.role.start_with?("G", "E")
      TYPES.dig(club.region, club.role)
    end

    # sigMon
    def mon?(pool, species, type)
      return false unless pool && type
      Scout.final_types(pool, species).include?(type)
    end

    def other_cap(club) = [Build.squad_size(club.clubhouse) - SQUAD_SHARE, 0].max
    def entry_other_cap = [Club::ENTRY_SIZE - ENTRY_SHARE, 0].max

    def others(club, pool, list = club.squad)
      t = of(club)
      list.count { |m| !mon?(pool, m.species, t) }
    end

    # sigBlock: signing `mon` would break the squad rule.
    def block?(club, mon, pool, replacing: nil)
      t = of(club) or return false
      return false if mon?(pool, mon.species, t)
      others(club, pool, club.squad.reject { |m| m.equal?(replacing) }) >= other_cap(club)
    end

    # sigParty: the entry with at most entry_other_cap of other types.
    def party(club, entry, candidates, pool, strength: nil)
      given = strength
      t = of(club)
      return entry unless t && pool
      strength = given ? ->(m) { given[m] } : ->(m) { m.rating * m.strength_mul }
      non = entry.reject { |m| mon?(pool, m.species, t) }
      return entry if non.size <= entry_other_cap
      keep = non.max_by(entry_other_cap, &strength)
      out = entry.select { |m| mon?(pool, m.species, t) || keep.include?(m) }
      extra = candidates.select { |m| mon?(pool, m.species, t) && !out.include?(m) }.sort_by { |m| -strength.(m) }
      extra.each { |m| out << m if out.size < Club::ENTRY_SIZE }
      out.sort_by { |m| -strength.(m) }
    end
  end
end
