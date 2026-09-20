if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_RaidBuffCheck.lua -- Resolves who benefits from a raid buff
--
--  EllesmereUI_RaidBuffs.lua documents the "benefit" field: which stat a buff
--  grants, where that distinction matters. Battle Shout (attackPower) doesn't
--  help a Mage; Arcane Intellect (intellect) doesn't help a Warrior. Mark of
--  the Wild, Power Word: Fortitude, Blessing of the Bronze, and Skyfury have
--  no "benefit" because they're equally useful to everyone.
--
--  This file only exposes EllesmereUI.RaidBuff_UnitBenefits(name, benefit,
--  classToken) -- the resolver. Deciding "missing" and drawing the grid is
--  EllesmereUIQoL_RaidCheck.lua's job; this resolver lives here, in the
--  parent, for the same reason the RaidBuffs table does: any other module
--  that needs the same answer (Aura Buff Reminders, etc.) uses this one copy
--  instead of duplicating the logic.
--
--  Why SPEC and not just class: Druid, Shaman, Paladin, Monk, and Demon
--  Hunter are hybrids -- at least one spec of each uses attackPower, another
--  uses intellect (e.g. Feral vs. Balance Druid; Devourer is Demon Hunter's
--  intellect spec). Filtering only by the buff's own class (e.g.
--  "class=WARRIOR" on Battle Shout) says who CAN cast it, not who benefits
--  from it -- that needs each group member's actual spec.
--
--  DEPENDENCY: LibSpecialization (already embedded in the addon, under
--  Libs/LibSpecialization). It broadcasts each player's specID to the rest
--  of the group over addon comms -- only works for people who are also
--  running a compatible lib (BigWigs, DBM, VuhDo, and other major addons
--  already embed it, so real-world coverage in raid content tends to be high
--  without asking anyone to install anything extra). When someone's spec is
--  unknown, the resolver would rather show the warning than hide it (an
--  occasional false positive is annoying; a false negative is worse --
--  someone goes without a buff thinking it was already checked).
-------------------------------------------------------------------------------

local LS = LibStub and LibStub("LibSpecialization", true)

-- The stat each spec actually uses. This is what makes filtering work for
-- hybrid classes -- everything here is keyed by specID, never by class.
local SPEC_STAT = {
    -- Death Knight (all attackPower)
    [250] = "attackPower", [251] = "attackPower", [252] = "attackPower",
    -- Demon Hunter (Havoc/Vengeance attackPower, Devourer intellect)
    [577] = "attackPower", [581] = "attackPower", [1480] = "intellect", -- Havoc, Vengeance, Devourer
    -- Druid (half and half)
    [102] = "intellect",   -- Balance
    [103] = "attackPower", -- Feral
    [104] = "attackPower", -- Guardian
    [105] = "intellect",   -- Restoration
    -- Evoker (all intellect)
    [1467] = "intellect", [1468] = "intellect", [1473] = "intellect",
    -- Hunter (all attackPower, even though it's ranged)
    [253] = "attackPower", [254] = "attackPower", [255] = "attackPower",
    -- Mage (all intellect)
    [62] = "intellect", [63] = "intellect", [64] = "intellect",
    -- Monk (half and half)
    [268] = "attackPower", -- Brewmaster
    [269] = "attackPower", -- Windwalker
    [270] = "intellect",   -- Mistweaver
    -- Paladin (half and half)
    [65] = "intellect",    -- Holy
    [66] = "attackPower",  -- Protection
    [70] = "attackPower",  -- Retribution
    -- Priest (all intellect, Shadow included)
    [256] = "intellect", [257] = "intellect", [258] = "intellect",
    -- Rogue (all attackPower)
    [259] = "attackPower", [260] = "attackPower", [261] = "attackPower",
    -- Shaman (half and half)
    [262] = "intellect",   -- Elemental
    [263] = "attackPower", -- Enhancement
    [264] = "intellect",   -- Restoration
    -- Warlock (all intellect)
    [265] = "intellect", [266] = "intellect", [267] = "intellect",
    -- Warrior (all attackPower)
    [71] = "attackPower", [72] = "attackPower", [73] = "attackPower",
}

-- Classes that are NEVER ambiguous: whatever the spec, the stat is always
-- the same, so we don't even need to know the spec to decide. This covers
-- the vast majority of cases without depending on LibSpecialization having
-- received anything -- which is what was missing, since in a normal group
-- half the raid's specs never arrive (only people running a compatible lib
-- broadcast their own).
local CLASS_STAT = {
    WARRIOR     = "attackPower",
    ROGUE       = "attackPower",
    DEATHKNIGHT = "attackPower",
    HUNTER      = "attackPower",
    MAGE        = "intellect",
    PRIEST      = "intellect",
    WARLOCK     = "intellect",
    EVOKER      = "intellect",
    -- DRUID, SHAMAN, PALADIN, MONK, and DEMONHUNTER are deliberately left
    -- out: each has at least one spec on either side (DH: Havoc/Vengeance
    -- vs. Devourer, intellect), so only the real spec can tell (via
    -- SPEC_STAT + LibSpecialization).
}

-- Known specID per name, filled in as LibSpecialization packets arrive.
-- Populated gradually -- don't expect everyone to be known on the first
-- frame after joining a group. Only consulted for the 5 hybrid classes
-- above; everything else is already resolved by CLASS_STAT.
EllesmereUI.RaidSpecByName = EllesmereUI.RaidSpecByName or {}

if LS then
    LS.RegisterGroup(EllesmereUI, function(specId, role, position, name)
        EllesmereUI.RaidSpecByName[name] = specId
    end)
end

-- Does this unit benefit from the requested "benefit"?
--   benefit == nil                     -> the buff helps everyone, always true
--   unambiguous class                  -> decided instantly, no spec needed
--   hybrid class + known spec          -> checked against the spec's real stat
--   hybrid class + unknown spec        -> don't hide the warning (see note above)
function EllesmereUI.RaidBuff_UnitBenefits(unitName, benefit, classToken)
    if not benefit then return true end
    local classStat = CLASS_STAT[classToken]
    if classStat then return classStat == benefit end
    local specId = EllesmereUI.RaidSpecByName[unitName]
    if not specId then return true end
    return SPEC_STAT[specId] == benefit
end
