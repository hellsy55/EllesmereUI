if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_RaidCheck.lua -- Consumable check on a ready check
--
--  Shows on ANY ready check in the group, whoever started it, and lists every
--  member against what a raid expects of them: flask, food, augment rune,
--  vantus rune, the group-wide buffs, weapon enchant and durability. The grid
--  is the whole report -- there is no summary line, because a raid leader
--  reading twelve columns does not also need them counted in prose.
--
--  WHAT ANSWERS A COLUMN. Every column declares how it is matched, and the
--  vectors are not interchangeable:
--
--    ids     exact spell ids. The only vector that survives restricted
--            content, and the only one that rots -- new consumables need new
--            ids every expansion.
--    icons   "Well Fed" reuses a handful of icons, so any recipe matches and
--            nothing needs updating.
--    prefix  every Vantus buff is "<prefix>: <boss>", so the prefix catches
--            every boss of every tier.
--    class   a group-wide buff. Not a matcher: it says whose absence makes
--            the column meaningless.
--    selfRead  read live off your own client. No API reports a weapon enchant
--            for anyone else, so YOUR row is answered locally and everyone
--            else's is volunteered over the comms layer. The local read is
--            applied last and wins: it is current, and it still works when
--            there is no group and so no transport at all.
--            (Durability reaches the same place by another road -- see the
--            column, LibDurability already reports your own value locally --
--            so it needs nothing from this mechanism.)
--
--  MIDNIGHT AURA RESTRICTIONS. The game offers two ways to read another
--  player's auras and each is blind where the other sees, so both ship:
--
--    * the index sweep answers with the FULL aura -- icon and name included --
--      which is what lets an unlisted consumable register. It is refused
--      outright in restricted content.
--    * GetUnitAuraBySpellID survives restriction, and combat, but only for
--      ids the client does not consider secret, and never exposes an icon.
--      So there the id tables are all we have.
--
--  A secret result reads as "unknown" rather than "missing". Claiming someone
--  has no flask because the client refused to answer is worse than saying
--  nothing, and that principle runs through the whole file: a column with no
--  answer is blank, never a cross.
--
--  The honest limit: inside a raid this window knows exactly what it has been
--  told to look for. A client reading its OWN auras and volunteering the
--  result is what would remove that, and is the road the enchant column is
--  already on -- read locally, reported outward.
-------------------------------------------------------------------------------
local _, ns = ...

local GetRaidRosterInfo   = GetRaidRosterInfo
local GetNumGroupMembers  = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local UnitIsGroupLeader, UnitIsGroupAssistant = UnitIsGroupLeader, UnitIsGroupAssistant
local UnitExists, UnitIsPlayer = UnitExists, UnitIsPlayer
local UnitIsUnit          = UnitIsUnit
local UnitIsDeadOrGhost   = UnitIsDeadOrGhost
local InCombatLockdown    = InCombatLockdown
local SendChatMessage     = SendChatMessage
local UnitName, UnitClass, UnitIsConnected = UnitName, UnitClass, UnitIsConnected
local UnitPhaseReason     = UnitPhaseReason
local UnitIsVisible       = UnitIsVisible
local Ambiguate           = Ambiguate
local issecretvalue       = issecretvalue
-- UseItemByName was namespaced to C_Item.UseItemByName; the old global may
-- no longer exist standalone on current clients (that's exactly why the
-- Auto-Repair click was silently doing nothing -- pcall was swallowing a
-- "call a nil value" error). Prefer the namespaced version, fall back to
-- the bare global for older clients that still have it.
local UseItemByName = (C_Item and C_Item.UseItemByName) or UseItemByName
local GetAuraDataByIndex  = C_UnitAuras.GetAuraDataByIndex
local GetUnitAuraBySpellID = C_UnitAuras.GetUnitAuraBySpellID
local GetReadyCheckStatus = GetReadyCheckStatus
local GetInstanceInfo     = GetInstanceInfo
local C_Timer             = C_Timer

-- Two member columns of twenty: a 40-man roster in one screenful, without a
-- scroll frame and without a window taller than the game. Sized to be legible
-- at a glance mid-raid rather than to save pixels -- the window fits the group
-- and the column set, so there is room, and the scale slider is there for
-- anyone who disagrees.
--
-- SINGLE_COL_THRESHOLD overrides that split as soon as the group would spill
-- into a second column at all (21+ members): a lone straggler in a second
-- column is exactly the "scan left, scan right, scan left again" problem a
-- single tall column avoids, so there is no reason to wait for a bigger
-- group first. Below the threshold -- 20 or fewer -- the two-column layout
-- above never actually needs the second column, so nothing changes there.
-- MAX_ROSTER is the row pool's real ceiling: kept separate from MEMBER_COLS
-- * COL_ROWS so single-column mode growing past what the two-column layout
-- ever needed doesn't silently run out of row frames -- the window grows
-- tall enough to hold every one of the 40 up front.
local MEMBER_COLS = 2
local COL_ROWS    = 20
local SINGLE_COL_THRESHOLD = COL_ROWS + 1
local MAX_ROSTER  = 40
local NAME_W      = 112
local CELL_W      = 30
local ROW_H       = 22
local COL_GAP     = 16
local PAD         = 14
local TITLE_H     = 26
local HEADER_H    = 20
local NAME_SIZE   = 12
local SMALL_SIZE  = 11
local ICON_SZ     = 18
local READY_ICON_W = 12   -- the ?/X/V glyph riding the name's left edge
local AURA_SCAN_LIMIT = 40
local SWEEP_PERIOD    = 2

-- Blizzard's own ready-check art: exactly these semantics, guaranteed present,
-- and no texture of ours to ship. Atlases (matching EllesmereUIRaidFrames'
-- UpdateReadyCheck) rather than the legacy Interface\RaidFrame textures.
local ATLAS_OK   = "UI-LFG-ReadyMark-Raid"
local ATLAS_MISS = "UI-LFG-DeclineMark-Raid"

-- QoL's key in EllesmereUI._addonKeyToFolder. On-screen text has to resolve
-- through GetFontPath: EllesmereUI.MakeFont hardcodes the options-panel font,
-- and using it here would make this the one QoL window ignoring the user's
-- Global Font setting.
local FONT_KEY = "extras"

local fonts = {}   -- every fontstring the window owns, with its size

local function FontPath()
    return (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath(FONT_KEY))
        or STANDARD_TEXT_FONT
end

local function MakeText(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FontPath(), size, "")
    fs:SetTextColor(1, 1, 1)
    fonts[#fonts + 1] = { fs = fs, size = size }
    return fs
end

-- Re-resolved every time the window opens rather than only at build: the
-- window is built once and lives for the session, so a Global Font change
-- between two ready checks would otherwise never reach it.
local function ApplyFonts()
    local path = FontPath()
    for _, e in ipairs(fonts) do e.fs:SetFont(path, e.size, "") end
end

-- "Well Fed" has reused the same handful of icons across expansions, so food
-- is identifiable without knowing its spell id at all. That is the one
-- consumable column that does not rot -- a new recipe keeps the icon and keeps
-- being detected.
local FOOD_ICONS = {
    [136000] = true,   -- the stat "Well Fed"
    [134062] = true,   -- plain "Well Fed", no stat line
    [132805] = true,
    [133950] = true,
}

-- The Vantus prefix is not hardcoded: it is read off a known Vantus rune and
-- cut at the first separator, so every client gets it correctly localized. The
-- seed spell is only a name source -- which rune it is does not matter, and an
-- old one is the safest choice because it will never be removed.
local VANTUS_SEED = 237825
local vantusPrefix, vantusTried
local function VantusPrefix()
    if vantusTried then return vantusPrefix end
    vantusTried = true
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(VANTUS_SEED)
    local name = info and info.name
    if name then vantusPrefix = name:match("^(.-)[:%-：]") end
    return vantusPrefix
end

-- Consumables, in display order. `seed` and `icon` are only the header art;
-- `seed` fetches it from the game so a header cannot drift from what it checks.
--
-- Only flask and rune carry ids, and they are the only entries here that will
-- ever need a patch-day edit. /euiraidcheck is the maintenance tool.
local CHECKS = {
    -- nameTooltip: which specific flask/food a player has up is worth
    -- surfacing on hover, the same way Vantus already names its rune.
    { key = "flask",  label = "Flask",  seed = 1235110, nameTooltip = true,
      ids = { [1236763] = true, [1239355] = true, [1235057] = true, [1239755] = true,
              [1236767] = true, [1235111] = true, [1235110] = true, [1235108] = true } },
    { key = "food",   label = "Food",   icon = 136000, icons = FOOD_ICONS, nameTooltip = true },
    { key = "rune",   label = "Rune",   seed = 1264426, nameTooltip = true,
      ids = { [1264426] = true } },
    -- Vantus runes apply to raid bosses, so in a Mythic+ key the column is not
    -- merely unlikely to be filled, it is meaningless.
    -- icon is fixed rather than derived from the seed spell: the seed exists
    -- only to read the localized "Vantus Rune:" prefix, and its own icon is
    -- an arbitrary old rune's art, not a good header glyph.
    { key = "vantus", label = "Vantus", seed = VANTUS_SEED, icon = 7549087,
      prefix = VantusPrefix, raidOnly = true },
}

-- Temporarily off: the column is only ever answered for players also
-- running EllesmereUIQoL (see selfRead/Comms note below), which reads as
-- broken to anyone who doesn't know that. Flip back to true to bring the
-- column back -- nothing else needs to change.
local SHOW_WENCHANT_COLUMN = false

local DURABILITY_KEY = "durability"
local WENCHANT_KEY   = "wenchant"
local VANTUS_KEY     = "vantus"
local MSG_REPORT     = "rc"    -- a client describing itself
local MSG_QUERY      = "rcq"   -- someone asking the group to describe itself

-- Auto-Repair: left-clicking a row's Durability cell uses the Auto-Hammer
-- when that row's own durability reading is at or below the threshold.
-- Raid only (see Refresh's autoRepairOn) -- a dungeon or M+ group repairs at
-- the vendor between pulls easily enough that this is raid-specific chrome,
-- not a general durability shortcut. 25 is its own threshold, deliberately
-- not EllesmereUI.DURABILITY_LOW (20): that constant colors the grid's
-- existing low-durability warning, a separate and already-shipped decision
-- this feature does not get to quietly change.
local AUTO_REPAIR_ITEM_ID  = 132414
local AUTO_REPAIR_THRESHOLD = 25

-- What each client volunteered about itself, from either wire. One store, so
-- a future field lands here rather than growing a third parallel map -- and
-- the paint path never has to care which transport a value arrived on.
local reported = {}   -- player name -> { dur = number, we = enchantID }

-- True for the life of one ready check: set on READY_CHECK, cleared on
-- READY_CHECK_FINISHED. GetReadyCheckStatus answers with stale data outside
-- that window -- the last check's verdicts, not "no check" -- so the ?/X/V
-- column has to gate on this rather than on the API alone.
local readyCheckActive = false

-- The library reports names Ambiguate'd to "none" while UnitName gives the
-- bare name, so normalisation happens once, here, at the store boundary.
local function Note(name, field, value)
    if type(name) ~= "string" then return end
    name = Ambiguate(name, "short")
    local e = reported[name]
    if not e then e = {}; reported[name] = e end
    e[field] = value
end

-- Your own main-hand enchant id, or 0 for none. Only your own client can
-- answer this, for you or for anyone -- which is why it also goes on the wire.
--
-- Through the parent, not GetWeaponEnchantInfo directly: that call is a
-- deprecation shim on 12.1, and the parent owns the one reader that knows it.
--
-- Main hand only: off-hand items that cannot take an enchant at all are
-- common, and reading those as missing would be a false accusation.
local function MyEnchantID()
    local has, _, _, enchantID = EllesmereUI.WeaponEnchants()
    return (has and enchantID) or 0
end

-- The single place an enchant id becomes a verdict, so your row and everyone
-- else's are judged by the same rule -- one arrives locally and one off the
-- wire, and that must not be a difference the user can see.
local function EnchantOK(id)
    return (id or 0) > 0
end

-- Best-effort name for a temporary weapon enchant id (GetWeaponEnchantInfo /
-- C_PaperDollInfo.GetTemporaryEnchantmentInfo's enchantID). UNVERIFIED: some
-- temp enchants apply via a spell whose id matches this one, in which case
-- GetSpellInfo resolves a real name; others don't, and this returns nil. A
-- permanent enchant's name IS reliably readable off the item link's own
-- enchant field (see EllesmereUIBlizzardSkin's EUI_GetEnchantText), but a
-- temporary one lives entirely outside the item string -- there is no
-- confirmed general API for it, so this is a plain attempt with a silent
-- nil on failure rather than any scanning-tooltip fallback.
local function EnchantName(id)
    if not id or id == 0 then return nil end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
    return info and info.name
end

-- Left-click on a low-durability row's Durability cell (see Refresh/MakeRow).
-- Re-checks both gates itself instead of trusting the hit frame's shown
-- state: that state is a Refresh()-cadence snapshot, up to SWEEP_PERIOD
-- stale, and leaving the raid or flipping the option off mid-window must not
-- leave a click still armed. UseItemByName resolves by id fine and needs no
-- bag slot from the caller; the pcall is what a plain button click needs
-- here, not a SecureActionButton -- using an item from a real mouse click is
-- unrestricted in combat the same as it is out of it, but the feature is
-- deliberately out-of-combat-only anyway (see InCombatLockdown check): a
-- pull is not when anyone should be looking at this column, let alone
-- clicking it.
local function UseAutoRepairItem()
    if not ns.RaidCheckAutoRepair() then return end
    if not IsInRaid() then return end
    if InCombatLockdown() then return end
    pcall(UseItemByName, AUTO_REPAIR_ITEM_ID)
end

-- "Name-Realm" when the unit is cross-realm, plain name otherwise -- what
-- SendChatMessage's target argument needs either way. UnitName's second
-- return is "" (not nil) same-realm, so that case falls through untouched.
local function FullName(unit)
    local name, realm = UnitName(unit)
    if not name then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

-- Raid buffs are checked for every online player -- being far away or in a
-- different phase doesn't stop UnitAura from answering, so there's no
-- reason to blank the column for someone just because they're across the
-- room. What phasing DOES break is a negative read: a MISSING verdict on
-- someone out of your broadcast range or in a different phase isn't
-- trustworthy (their aura state may simply not be syncing to you), so
-- Refresh applies this asymmetrically -- see the def.class block below --
-- rather than gating the whole column. A player who reads as HAVING the
-- buff is trusted regardless of phase; that positive information doesn't
-- depend on live sync the same way an absence does.
--
-- Ported directly from BuffReminders' Plain/IsUnitPhased (Core/Core.lua,
-- Core/State.lua) rather than re-derived: UnitIsVisible for out-of-
-- broadcast-range, UnitPhaseReason (guarded through Plain, which reads a
-- secret value as nil) for an actual phase/instance difference.
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Phased(unit)
    return not UnitIsVisible(unit)
        or Plain(UnitPhaseReason and UnitPhaseReason(unit)) ~= nil
end

-------------------------------------------------------------------------------
--  Columns
-------------------------------------------------------------------------------

local COLUMNS   = {}   -- display order
local SELF_COLS = {}   -- columns that read your own row locally
local ID_TO_KEY = {}   -- spell id -> column key, flattened from every id set
local ICON_COLS = {}   -- columns matched on aura icon
local NAME_COLS = {}   -- columns matched on an aura name prefix
local WANTS_NAME = {}  -- column key -> true, for id/icon columns that also want the matched aura's name (e.g. Flask, Food)
local columnsBuilt

local function LibDur()
    return LibStub and LibStub("LibDurability", true)
end

-- Built on first open rather than at load: nothing here needs to exist until
-- the window does, and by then every file has run.
local function EnsureColumns()
    if columnsBuilt then return end
    columnsBuilt = true

    for _, def in ipairs(CHECKS) do
        COLUMNS[#COLUMNS + 1] = def
    end

    -- Oils and sharpening stones are one thing to the game -- a temporary
    -- weapon enchant -- so this is one column rather than two. Which
    -- consumable a player used is their business; whether the weapon is
    -- enchanted is the raid's, and it means no id table to maintain.
    --
    -- The column exists whether or not the transport does: `selfRead` answers
    -- your own row from your own client, so it is filled solo, filled before
    -- any reply could arrive, and never wrong because a message was dropped.
    -- Comms only ever fills OTHER people's rows.
    if SHOW_WENCHANT_COLUMN then
        COLUMNS[#COLUMNS + 1] = { key = WENCHANT_KEY, label = "Weapon Enchant",
                                  selfRead = function() return EnchantOK(MyEnchantID()) end,
                                  note = "Oil or sharpening stone on the main hand. Other players' rows need them to be running EllesmereUI.",
                                  icon = "Interface\\Icons\\INV_Stone_SharpeningStone_05" }
    end

    -- Only offered when the library is embedded: a column nobody can ever
    -- answer is worse than none.
    --
    -- The note is not a detail. Every client on the shared channel reports an
    -- average across its equipped slots, so this number is not the one the
    -- DataBars durability block shows, which is the single worst piece. Both
    -- are right; only the average is comparable between people, which is why
    -- the column cannot use the other reading.
    if LibDur() then
        COLUMNS[#COLUMNS + 1] = { key = DURABILITY_KEY, label = "Durability",
                                  numeric = true,
                                  note = "Average across equipped items, as reported by each player.",
                                  icon = "Interface\\Icons\\Trade_BlackSmithing" }
    end

    -- Raid buff definitions are not ours and are not copied: they live in the
    -- parent, shared with Aura Buff Reminders. Every child addon has the
    -- parent, so these columns exist whatever else the user has switched off,
    -- and there is one list to maintain rather than two.
    for _, b in ipairs(EllesmereUI.RaidBuffs) do
        -- The table also carries entries checked per player rather than
        -- group-wide; only the group-wide ones belong in a raid check.
        if b.check == "raid" then
            local ids = {}
            for _, id in ipairs(b.buffIDs) do ids[id] = true end
            COLUMNS[#COLUMNS + 1] = { key = b.key, class = b.class, ids = ids,
                                      seed = b.castSpell, fallbackName = b.name }
        end
    end

    -- One flat lookup instead of walking every column's id set per aura.
    for _, def in ipairs(COLUMNS) do
        if def.selfRead then SELF_COLS[#SELF_COLS + 1] = def end
        if def.ids then
            for id in pairs(def.ids) do ID_TO_KEY[id] = def.key end
        end
        if def.icons  then ICON_COLS[#ICON_COLS + 1] = def end
        if def.prefix then NAME_COLS[#NAME_COLS + 1] = def end
        if def.nameTooltip then WANTS_NAME[def.key] = true end
    end
end

-- A buff column carries no label of ours: its name is the spell's, already
-- localized by the game. Resolved once and kept.
local columnName = {}
local function ColumnName(def)
    if def.label then return EllesmereUI.L(def.label) end
    local n = columnName[def.key]
    if not n then
        local info = def.seed and C_Spell and C_Spell.GetSpellInfo
            and C_Spell.GetSpellInfo(def.seed)
        n = (info and info.name) or def.fallbackName or def.key
        columnName[def.key] = n
    end
    return n
end

-- The clickable spell link, not just the name -- lets whoever gets whispered
-- shift-click it into chat, hover it for the tooltip, whatever they'd do
-- with any other spell link. Falls back to the plain name on the rare tick
-- the link isn't cached yet (GetSpellLink can return nil before the client
-- has seen the spell), same fallback shape as ColumnName above. Not cached
-- itself, unlike columnName: the link can legitimately go from nil to
-- non-nil across the session as data streams in, and re-asking costs one
-- table lookup either way.
local function BuffLink(def)
    local link = def.seed and C_Spell and C_Spell.GetSpellLink
        and C_Spell.GetSpellLink(def.seed)
    return link or ColumnName(def)
end

-- Left-click on a missing raid-buff icon: whisper the one class that can
-- cast it. providerName travels as a resolved string, not a unit token --
-- see Refresh, where it is (re)computed every sweep. Unit tokens like
-- "raidN" can point at a different person by the time a click lands; a name
-- captured a sweep ago cannot silently retarget that way.
local function WhisperBuffProvider(def, providerName)
    if not ns.RaidCheckBuffWhisper() then return end
    if not providerName then return end
    SendChatMessage(BuffLink(def) .. ", please", "WHISPER", nil, providerName)
end

-------------------------------------------------------------------------------
--  Reading
-------------------------------------------------------------------------------

-- AuraKit is 12.1-gated and does not exist at all on an older client (see the
-- LIVE GATE at the top of EllesmereUI_AuraKit.lua), so the nil check is load
-- bearing, not defensive noise -- do not remove it. False is the right answer
-- there: aura restriction arrived WITH 12.1, so a client without AuraKit is a
-- client where nothing is restricted and the index sweep always works.
local function Restricted()
    local AK = EllesmereUI.AuraKit
    if not AK then return false end
    return AK.AurasRestricted()
end

-- True during ANY combat -- trash or boss alike -- while inside a raid or
-- an active Mythic+ Keystone run. A normal/heroic dungeon or open-world
-- fight does not block this. C_ChallengeMode.IsChallengeModeActive() is
-- what distinguishes M+ from an ordinary dungeon, since GetInstanceInfo's
-- instanceType is "party" for both alike.
local function ConsumablesBlockedByCombat()
    if not InCombatLockdown() then return false end
    local _, instanceType = GetInstanceInfo()
    if instanceType == "raid" then return true end
    return C_ChallengeMode ~= nil and C_ChallengeMode.IsChallengeModeActive ~= nil
        and C_ChallengeMode.IsChallengeModeActive() == true
end

-- Can this column be answered at all right now? One predicate, so nothing
-- downstream branches on a column's name.
--
-- consumablesBlocked: true during any combat (trash or boss) inside a raid
-- or an active M+ (ConsumablesBlockedByCombat above). Personal consumables
-- (flask/food/rune/vantus -- the ids/icons/prefix columns below) go blank
-- for that window rather than checked: combat there is exactly when aura
-- restriction is most likely to be active AND when a stale/degraded read is
-- most likely to be trusted at a glance, so the column sits out the fight
-- rather than risk crossing someone who actually has their flask up. A
-- normal/heroic dungeon or open-world fight is unaffected -- consumable
-- checking keeps working there, same as out of combat. Raid-buff columns
-- (def.class) and the locally-read columns (durability, weapon enchant) do
-- not depend on another unit's aura secrecy the same way, so they are
-- untouched by this and keep reporting through combat regardless of
-- content type.
local function Answerable(def, restricted, classPresent, consumablesBlocked)
    if def.class    then return classPresent[def.class] or false end
    if def.raidOnly and not IsInRaid() then return false end
    if consumablesBlocked and (def.ids or def.icons or def.prefix) then return false end
    if def.ids      then return true end
    -- Icon and name prefix live on the full aura, which only the sweep hands
    -- back, so those columns cannot answer under restriction. A prefix that
    -- did not resolve is the same situation: better no column than one that
    -- crosses everybody.
    if def.prefix   then return not restricted and def.prefix() ~= nil end
    if def.icons    then return not restricted end
    return true   -- volunteered: askable always, blank until someone answers
end

-- Unrestricted path. One sweep answers every column at once AND hands back the
-- icon and name, which is what lets an unlisted consumable register.
--
-- A named function so the pcall wraps the whole unit in one call rather than
-- allocating a closure per unit -- restriction was already decided by the
-- caller, so a per-index catch buys nothing here.
local function SweepBody(unit, out)
    for i = 1, AURA_SCAN_LIMIT do
        local aura = GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then return end
        local id = aura.spellId
        if id and not (issecretvalue and issecretvalue(id)) then
            local key = ID_TO_KEY[id]
            if key then
                out[key] = true
                if aura.name and WANTS_NAME[key] then
                    out._names = out._names or {}
                    out._names[key] = out._names[key] or aura.name
                    -- expirationTime is an absolute GetTime() timestamp, 0 for
                    -- a buff with no expiry; the tooltip does the subtraction
                    -- at hover time so the number is never stale by the time
                    -- it is read.
                    if aura.expirationTime and aura.expirationTime > 0 then
                        out._expires = out._expires or {}
                        out._expires[key] = out._expires[key] or aura.expirationTime
                    end
                end
            end
            if aura.icon then
                for j = 1, #ICON_COLS do
                    local def = ICON_COLS[j]
                    if def.icons[aura.icon] then
                        out[def.key] = true
                        if aura.name and def.nameTooltip then
                            out._names = out._names or {}
                            out._names[def.key] = out._names[def.key] or aura.name
                            if aura.expirationTime and aura.expirationTime > 0 then
                                out._expires = out._expires or {}
                                out._expires[def.key] = out._expires[def.key] or aura.expirationTime
                            end
                        end
                    end
                end
            end
            if aura.name then
                for j = 1, #NAME_COLS do
                    local def = NAME_COLS[j]
                    -- Each column resolves its own prefix; the lookup is
                    -- memoised, so this is a table read per aura.
                    local p = def.prefix()
                    if p and aura.name:find(p, 1, true) == 1 then
                        out[def.key] = true
                        -- Kept alongside the boolean so the grid can show WHICH
                        -- Vantus rune (or future prefix column) is active, not just
                        -- that one is. First match wins; a second application would
                        -- be a bug elsewhere, not a reason to overwrite a good name.
                        out._names = out._names or {}
                        out._names[def.key] = out._names[def.key] or aura.name
                    end
                end
            end
        end
    end
end

-- Restricted path. Returns true, false, or nil when the client refused to
-- answer -- and nil matters: see the header.
-- wantName: also try to return the specific aura's name alongside the
-- verdict (used for Flask, the one id-based column still answerable under
-- restriction). A secret aura still counts toward "unknown" even when a
-- name was not asked for -- that behavior is unchanged.
local function UnitHasAny(unit, ids, wantName)
    local unknown = false
    for id in pairs(ids) do
        local ok, aura = pcall(GetUnitAuraBySpellID, unit, id)
        if not ok then
            unknown = true
        elseif aura ~= nil then
            if issecretvalue and issecretvalue(aura) then
                unknown = true
            else
                local expires
                if wantName and aura.expirationTime and aura.expirationTime > 0 then
                    expires = aura.expirationTime
                end
                return true, wantName and aura.name, expires
            end
        end
    end
    if unknown then return nil end
    return false
end

local function UnitChecks(unit, answerable, restricted)
    local out = {}
    if restricted then
        for _, def in ipairs(COLUMNS) do
            if answerable[def.key] and def.ids then
                local found, name, expires = UnitHasAny(unit, def.ids, def.nameTooltip)
                out[def.key] = found
                if name then
                    out._names = out._names or {}
                    out._names[def.key] = name
                end
                if expires then
                    out._expires = out._expires or {}
                    out._expires[def.key] = expires
                end
            end
        end
    else
        -- Seeded only on this path: the sweep reports what it FINDS, so a
        -- column it never touches has to already read as absent.
        for _, def in ipairs(COLUMNS) do
            if answerable[def.key] and (def.ids or def.icons or def.prefix) then
                out[def.key] = false
            end
        end
        pcall(SweepBody, unit, out)
    end
    return out
end

-- Enumerating a group is three different APIs, not one, and mixing them is how
-- a Delve companion lands in a raid check:
--
--   * In a raid, GetRaidRosterInfo(i) pairs with raid<i> and is the only
--     source of the subgroup number.
--   * In a party it pairs with nothing -- a party is the player plus
--     party1..party4, and there are no subgroups.
--   * Solo there is no group, and the window reports the player, since
--     checking your own consumables before you join something is the same
--     question this answers.
--
-- Cheap on purpose: no auras are read here. Which buff columns are worth
-- reading depends on which classes are present, so the roster has to exist
-- before a single aura call is made.
local function ReadMembers()
    local out = {}

    local function Add(unit, subgroup)
        -- UnitIsPlayer keeps followers out: a Delve companion is a group
        -- member as far as these APIs are concerned, and it does not eat.
        if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
        local _, class = UnitClass(unit)
        out[#out + 1] = {
            unit   = unit,
            name   = UnitName(unit) or "?",
            class  = class,
            online = UnitIsConnected(unit),
            group  = subgroup or 1,
            -- Not a cosmetic flag: your own row is the one that can be read
            -- locally instead of waited for.
            isSelf = UnitIsUnit(unit, "player"),
        }
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local _, _, subgroup = GetRaidRosterInfo(i)
            Add("raid" .. i, subgroup)
        end
    elseif IsInGroup() then
        Add("player")
        for i = 1, GetNumSubgroupMembers() do Add("party" .. i) end
    else
        Add("player")
    end

    -- Plain A-Z by name, subgroup ignored entirely: a raid leader hunting one
    -- name reads the grid top-to-bottom once instead of finding the right
    -- subgroup block first.
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-------------------------------------------------------------------------------
--  Volunteered reports
-------------------------------------------------------------------------------

-- The raw id travels, not a verdict: the receiver applies EnchantOK, so a
-- later refinement of what counts works against everyone immediately instead
-- of waiting for the whole raid to update.
local function MyReport()
    return "we=" .. MyEnchantID()
end

-- Bounded parse: this is another player's client talking, so a field that is
-- not exactly what is expected is dropped rather than coerced.
local function ReadReport(sender, payload)
    if type(payload) ~= "string" then return end
    local we = payload:match("we=(%d+)")
    if we then Note(sender, "we", tonumber(we)) end
end

local function NoteDurability(percent, _, name)
    if type(percent) == "number" then Note(name, "dur", percent) end
end

-------------------------------------------------------------------------------
--  On-demand reports -- driven by the Flask/Food/Repair/Rune/Vantus buttons
--  on the Raid Tools panel (EllesmereUIQoL_RaidTools.lua). Independent of the
--  grid window: none of this requires it to be open, or even enabled --
--  everything it reads (the roster, the aura checks, LibDurability) already
--  works standalone.
-------------------------------------------------------------------------------
local REPORT_TITLE = {
    flask = "Flask", food = "Food", rune = "Rune",
    vantus = "Vantus", durability = "Repair",
}
ns.REPORT_TITLE = REPORT_TITLE

-- A durability request is a broadcast; give it a moment for other clients'
-- LibDurability to answer before reading what came back. Flask/Food/Rune/
-- Vantus need nothing like this -- they read live off the aura APIs.
local DURABILITY_REPORT_DELAY = 1.5

local function ReportChannel()
    if IsInRaid() then return "GUILD" end
    if IsInGroup() then return "PARTY" end
    return nil   -- solo: nobody to report to
end

-- The client refuses (and taints) any single SendChatMessage over this many
-- characters -- a raid-wide Repair/Flask/etc. report blows past it easily
-- once the roster is more than a handful of names, so a long report has to
-- go out as more than one message rather than not go out at all.
local CHAT_MSG_LIMIT   = 255
-- Marks every message after the first as a continuation of the one before
-- it, since it carries no title of its own once the split happens mid-list.
local CHAT_CONT_PREFIX = "(cont.) "
-- Staggered rather than fired back to back: the server's own chat throttle
-- can silently eat messages sent in the same instant, which would look like
-- the addon dropped part of the report.
local CHAT_CHUNK_DELAY = 0.3

-- The rightmost ", " that still ends at or before `limit`, so a cut always
-- falls between two list entries and never through the middle of a name.
-- Nil means there is no such boundary at all (one entry alone is longer
-- than the whole limit) -- the caller hard-cuts rather than lose the rest
-- of the report.
local function LastBoundary(text, limit)
    local cut
    local from = 1
    while true do
        local s = text:find(", ", from, true)
        if not s or s + 1 > limit then break end
        cut = s + 1
        from = s + 1
    end
    return cut
end

-- Splits a report line into chat-safe pieces. The first piece is budgeted
-- the full limit, since it goes out as-is; every piece after that is
-- budgeted CHAT_CONT_PREFIX shorter, since SendChatChunks prepends that
-- prefix before sending it -- computed here, not tacked on after, so the
-- prefixed message itself never exceeds CHAT_MSG_LIMIT.
local function ChatChunks(text)
    local chunks = {}
    local limit = CHAT_MSG_LIMIT
    while #text > limit do
        local cut = LastBoundary(text, limit) or limit
        chunks[#chunks + 1] = text:sub(1, cut)
        text = text:sub(cut + 1)
        limit = CHAT_MSG_LIMIT - #CHAT_CONT_PREFIX
    end
    chunks[#chunks + 1] = text
    return chunks
end

-- Sends one report as one or more chat messages, continuation pieces
-- trailing the first by CHAT_CHUNK_DELAY apiece. A short report (the common
-- case) is a single immediate SendChatMessage, same as before this existed.
local function SendChatChunks(text, channel)
    local chunks = ChatChunks(text)
    SendChatMessage(chunks[1], channel)
    for i = 2, #chunks do
        local msg = CHAT_CONT_PREFIX .. chunks[i]
        local delay = (i - 1) * CHAT_CHUNK_DELAY
        C_Timer.After(delay, function() SendChatMessage(msg, channel) end)
    end
end

-- toChat = true posts to /guild (in a raid) or /party (see ReportChannel); false (or
-- solo, where there is no channel to post to) prints to the player's own
-- chat frame only.
local function SendOrPrint(text, toChat)
    if not text then return end
    if toChat then
        local channel = ReportChannel()
        if channel then
            SendChatChunks(text, channel)
            return
        end
    end
    EllesmereUI.Print("|cff0cd29fEllesmereUI:|r " .. text)
end

local function BooleanReportLine(key)
    EnsureColumns()
    local def
    for _, d in ipairs(COLUMNS) do
        if d.key == key then def = d; break end
    end
    local title = EllesmereUI.L(REPORT_TITLE[key] or key)
    if not def then
        return title .. ": " .. EllesmereUI.L("not available.")
    end

    local roster = ReadMembers()
    local classPresent = {}
    for _, e in ipairs(roster) do
        if e.class then classPresent[e.class] = true end
    end
    local restricted = Restricted()
    local consumablesBlocked = ConsumablesBlockedByCombat()
    if not Answerable(def, restricted, classPresent, consumablesBlocked) then
        return title .. ": " .. EllesmereUI.L("no data available right now.")
    end

    local answerable = { [key] = true }
    local missing = {}
    for _, e in ipairs(roster) do
        local checks = UnitChecks(e.unit, answerable, restricted)
        if checks[key] == false then
            missing[#missing + 1] = e.name
        end
    end

    if #missing == 0 then
        return title .. ": " .. EllesmereUI.L("everyone has it.")
    end
    table.sort(missing)
    return EllesmereUI.Lf("Missing %s: %s", title, table.concat(missing, ", "))
end

-- Repair report only calls out gear that actually needs attention -- anyone
-- already durability-healthy just adds noise to a raid-wide chat message.
local DURABILITY_REPORT_THRESHOLD = 90

local function DurabilityReportLine()
    local title = EllesmereUI.L(REPORT_TITLE.durability)
    if not LibDur() then
        return title .. ": " .. EllesmereUI.L("not available.")
    end

    local roster = ReadMembers()
    local rows, anyData = {}, false
    for _, e in ipairs(roster) do
        local r = reported[e.name]
        local pct = r and r.dur
        if pct then
            anyData = true
            if pct <= DURABILITY_REPORT_THRESHOLD then
                rows[#rows + 1] = { name = e.name, pct = pct }
            end
        end
    end
    if not anyData then
        return title .. ": " .. EllesmereUI.L("no data available right now.")
    end
    if #rows == 0 then
        return EllesmereUI.Lf("%s: everyone is above %d%%.", title, DURABILITY_REPORT_THRESHOLD)
    end
    -- Worst durability first -- that is the row a raid lead actually needs
    -- to act on, and the one that should not scroll off a long roster line.
    table.sort(rows, function(a, b) return a.pct < b.pct end)

    local parts = {}
    for _, r in ipairs(rows) do
        parts[#parts + 1] = r.name .. " " .. math.floor(r.pct + 0.5) .. "%"
    end
    return title .. ": " .. table.concat(parts, ", ")
end

-- key: "flask" | "food" | "rune" | "vantus" | "durability".
-- toChat: true = right-click (post to /guild in a raid, /party in a party); false = left-click
-- (this client's own chat frame only).
function ns.ReportConsumable(key, toChat)
    if key == DURABILITY_KEY then
        local LD = LibDur()
        if LD then LD:RequestDurability() end
        C_Timer.After(LD and DURABILITY_REPORT_DELAY or 0, function()
            SendOrPrint(DurabilityReportLine(), toChat)
        end)
        return
    end
    SendOrPrint(BooleanReportLine(key), toChat)
end

-------------------------------------------------------------------------------
--  Permission
-------------------------------------------------------------------------------

local db
local function P()
    return db and db.profile and db.profile.raidCheck
end

local function HasRank()
    return IsInGroup()
       and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
end

-- The option only widens who SEES it; it grants nothing, because there is
-- nothing to grant -- every column is either a local read or volunteered.
local function MayShow()
    local p = P()
    if not p or not p.enabled then return false end
    if p.showWithoutRank then return true end
    return HasRank()
end

local DB_DEFAULTS = {
  profile = {
    raidCheck = {
        -- Off by default: this opens a window on an event the user did not
        -- ask for, so it is opt-in like every other QoL feature.
        enabled          = false,
        showWithoutRank  = false,
        -- Drop columns nothing in this group can satisfy instead of dimming
        -- them. On by default -- a dimmed column still costs the width and the
        -- eye that a used one would.
        hideInapplicable = true,
        -- Show only the people something is wrong with. Off by default: the
        -- full roster is what most people expect to open.
        hideReady        = false,
        -- Off by default: using an item off a raid-check click is exactly
        -- the kind of thing that should be opted into, not discovered by
        -- surprise the first time someone's durability drops.
        autoRepair       = false,
        -- Same reasoning as autoRepair, and the same shape: off by default,
        -- since whispering someone on a raid leader's behalf is not
        -- something to switch on by surprise.
        buffWhisper      = false,
        scale            = 1,
        pos              = {},
    },
  },
}

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------

local win
local rows      = {}   -- flat, member-column major
local colHeader = {}   -- column key -> one frame per member column
local sweeper
local closeTimer   -- always armed while the window is shown, however it opened
local CLOSE_DELAY = 30   -- seconds the window stays open before auto-closing

-- Raid-buff blink: one shared clock instead of one AnimationGroup per icon.
-- An AnimationGroup's :Play() starts its own timeline from zero, so two
-- icons that started blinking on different sweeps end up pulsing out of
-- phase with each other -- correct individually, but reads as flicker when
-- several are missing at once. Every icon here instead just sets/clears its
-- own membership in buffBlinkTargets (see Refresh); a single OnUpdate
-- computes one alpha per frame off GetTime() and stamps it onto whatever is
-- currently in the set, so anything blinking is always in lockstep.
-- Durability and Vantus-mismatch blinks are unrelated to this and keep
-- their own AnimationGroups -- only raid-buff icons were asked to move.
local buffBlinkTargets = {}
local buffBlinkDriver

local function SetBuffBlink(icon, on, restoreAlpha)
    if on then
        if not buffBlinkTargets[icon] then
            buffBlinkTargets[icon] = true
            if not buffBlinkDriver then
                buffBlinkDriver = CreateFrame("Frame")
                buffBlinkDriver:Hide()
                buffBlinkDriver:SetScript("OnUpdate", function()
                    local alpha = 0.625 + 0.375 * math.sin(GetTime() * 5)
                    for tex in pairs(buffBlinkTargets) do
                        tex:SetAlpha(alpha)
                    end
                end)
            end
            buffBlinkDriver:Show()
        end
    elseif buffBlinkTargets[icon] then
        buffBlinkTargets[icon] = nil
        icon:SetAlpha(restoreAlpha or 1)
        if not next(buffBlinkTargets) and buffBlinkDriver then
            buffBlinkDriver:Hide()   -- nothing left to animate; stop the OnUpdate entirely
        end
    end
end

local combatCloseTimer   -- armed only while combat is waiting out the grace period below
local openedAt            -- GetTime() of the most recent Show
local openedManually      -- true when Show came from the slash command, not a ready check
local MIN_MANUAL_OPEN = 10   -- seconds a manually opened window is guaranteed to stay up, even into combat

local function MakeRow(parent, index)
    local r = CreateFrame("Frame", nil, parent)

    -- Hover highlight spans the whole row -- name through the last visible
    -- column -- because it is sized to the row's full width in Relayout and
    -- every cell/icon is a child with no mouse region of its own, so the
    -- frame beneath them is what the cursor actually enters.
    local hl = r:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(r)
    hl:SetColorTexture(1, 1, 1, 0.08)
    hl:Hide()
    r._highlight = hl

    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self) self._highlight:Show() end)
    r:SetScript("OnLeave", function(self) self._highlight:Hide() end)
    -- Re-armed here rather than relying on the window's own handler: a row
    -- has mouse enabled for the highlight above, which claims the click
    -- before it would otherwise reach the window frame underneath.
    r:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and win then win:Hide() end
    end)

    r._name = MakeText(r, NAME_SIZE)
    r._name:SetPoint("LEFT", r, "LEFT", 2 + READY_ICON_W, 0)
    r._name:SetWidth(NAME_W - 6 - READY_ICON_W)
    r._name:SetJustifyH("LEFT")

    -- Auto-Repair: pulses the name (not the durability number itself, which
    -- already carries its own color) while this row's durability sits at or
    -- below AUTO_REPAIR_THRESHOLD. Region alpha, not SetTextColor's alpha --
    -- the offline/elsewhere dim below writes the color channel, so the two
    -- multiply together instead of fighting over the same value.
    local blink = r._name:CreateAnimationGroup()
    local pulse = blink:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1)
    pulse:SetToAlpha(0.25)
    pulse:SetDuration(0.6)
    pulse:SetSmoothing("IN_OUT")
    blink:SetLooping("BOUNCE")
    r._lowDurBlink = blink

    -- Ready check status: blank outside an active ready check (see
    -- readyCheckActive), otherwise a yellow "?" while pending -- there is no
    -- ready/not-ready art for "pending" to reuse -- and, once the game has a
    -- verdict, the SAME ready-check art every other column in this grid uses
    -- (ATLAS_OK / ATLAS_MISS), so ready and not-ready read identically wherever
    -- they appear in the window.
    r._ready = MakeText(r, NAME_SIZE)
    r._ready:SetPoint("LEFT", r, "LEFT", 2, 0)
    r._ready:SetWidth(READY_ICON_W)
    r._ready:SetJustifyH("CENTER")

    r._readyTex = r:CreateTexture(nil, "ARTWORK")
    r._readyTex:SetSize(READY_ICON_W, READY_ICON_W)
    r._readyTex:SetPoint("LEFT", r, "LEFT", 2, 0)
    r._readyTex:Hide()

    -- Geometry belongs to Relayout, which runs before the window is ever
    -- shown: anything positioned here would only be overwritten.
    r._cells   = {}
    r._cellTex = {}
    for c, def in ipairs(COLUMNS) do
        if def.numeric then
            local fs = MakeText(r, SMALL_SIZE)
            fs:SetWidth(CELL_W)
            fs:SetJustifyH("CENTER")
            r._cells[c] = fs

            -- Same low-durability pulse as the name, on the number itself --
            -- the number is the thing to actually look at; the name blink is
            -- the thing that catches your eye across the room.
            if def.key == DURABILITY_KEY then
                local numBlink = fs:CreateAnimationGroup()
                local numPulse = numBlink:CreateAnimation("Alpha")
                numPulse:SetFromAlpha(1)
                numPulse:SetToAlpha(0.25)
                numPulse:SetDuration(0.6)
                numPulse:SetSmoothing("IN_OUT")
                numBlink:SetLooping("BOUNCE")
                r._durNumBlink = numBlink
            end
            -- Unused for durability now that the column always shows the
            -- number (even at 100%), but kept so the cell/tex pairing stays
            -- uniform across numeric columns.
            local tex = r:CreateTexture(nil, "ARTWORK")
            tex:SetSize(ICON_SZ, ICON_SZ)
            tex:SetAtlas(ATLAS_OK)
            tex:SetAlpha(0.9)
            tex:Hide()
            r._cellTex[c] = tex
        else
            local tex = r:CreateTexture(nil, "ARTWORK")
            tex:SetSize(ICON_SZ, ICON_SZ)
            tex:SetAlpha(0.9)
            r._cells[c] = tex

            -- A different Vantus than your own is worth a glance even though
            -- the buff itself is present -- boss-specific runes are easy to
            -- carry over from last week's kill. Its own blink, independent
            -- of the hit-frame/whisper machinery below: Vantus has no
            -- provider to whisper (nobody "casts" it onto someone else), so
            -- this is purely informational and driven straight off the
            -- check icon.
            if def.key == VANTUS_KEY then
                local mismatchBlink = tex:CreateAnimationGroup()
                local mismatchPulse = mismatchBlink:CreateAnimation("Alpha")
                mismatchPulse:SetFromAlpha(1)
                mismatchPulse:SetToAlpha(0.25)
                mismatchPulse:SetDuration(0.6)
                mismatchPulse:SetSmoothing("IN_OUT")
                mismatchBlink:SetLooping("BOUNCE")
                r._vantusMismatchBlink = mismatchBlink
            end

            -- Prefix columns (Vantus) and nameTooltip columns (Flask, Food)
            -- know not just THAT the buff is up but WHICH one -- the name
            -- comes off the aura itself, see SweepBody / UnitHasAny. Weapon
            -- Enchant gets the same hover-only treatment for the same
            -- reason (which oil/stone, not just whether one is up) even
            -- though its check itself arrives over comms rather than a live
            -- aura read -- see EnchantName; the name is best-effort and may
            -- legitimately be blank. Raid-buff (def.class) columns get the
            -- overlay for a different job: when the buff is MISSING and
            -- someone who can cast it is present and reachable, left-click
            -- whispers them -- see Refresh, which decides per sweep whether
            -- a provider exists and only then shows this frame and plays
            -- the blink below. A texture cannot take mouse input on its
            -- own, so a transparent frame sits over the icon just to catch
            -- the hover/click; Relayout keeps it pinned to the same spot as
            -- the icon.
            if def.prefix or def.nameTooltip or def.class or def.key == WENCHANT_KEY then
                local hit = CreateFrame("Frame", nil, r)
                hit:SetSize(ICON_SZ, ICON_SZ)
                hit:EnableMouse(true)
                hit:Hide()
                hit:SetScript("OnEnter", function(self)
                    if def.class then
                        local providers = r._buffProvider and r._buffProvider[def.key]
                        if not providers then return end
                        local near, far, single = providers.near, providers.far, providers.single
                        if not (near or far or single) then return end
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:AddLine(ColumnName(def), 1, 1, 1)
                        if single then
                            GameTooltip:AddLine(EllesmereUI.L("Left-click to whisper") .. " " .. single, 0.8, 0.8, 0.8, true)
                        else
                            -- Raid: up to two independent targets, one per
                            -- half of the roster -- see providerFor in
                            -- Refresh. Either line is omitted if that half
                            -- has nobody who can answer it.
                            if near then
                                GameTooltip:AddLine(EllesmereUI.L("Left-click to whisper") .. " " .. near, 0.8, 0.8, 0.8, true)
                            end
                            if far then
                                GameTooltip:AddLine(EllesmereUI.L("Right-click to whisper") .. " " .. far, 0.8, 0.8, 0.8, true)
                            end
                        end
                        GameTooltip:Show()
                        return
                    end
                    local name = r._auraNames and r._auraNames[def.key]
                    if not name then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(ColumnName(def) .. ": " .. name, 1, 1, 1)
                    -- Recomputed at hover time from the absolute expiration
                    -- timestamp, so the minutes are always accurate to the
                    -- moment the tooltip is actually read, not to whenever
                    -- the last Refresh happened to run.
                    local expires = r._auraExpires and r._auraExpires[def.key]
                    if expires then
                        local remain = expires - GetTime()
                        if remain > 0 then
                            local mins = math.ceil(remain / 60)
                            if mins <= 1 then
                                GameTooltip:AddLine("< 1 min remaining", 0.8, 0.8, 0.8)
                            else
                                GameTooltip:AddLine(mins .. " min remaining", 0.8, 0.8, 0.8)
                            end
                        end
                    end
                    GameTooltip:Show()
                end)
                hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
                if def.class then
                    -- Left whispers the near (groups 1-4) or, outside a
                    -- raid, the only target. Right whispers the far
                    -- (groups 5-8) target when a raid has one; when it
                    -- doesn't, right-click falls through to the row's usual
                    -- job of closing the window, same as everywhere else in
                    -- the grid -- this frame sits on top of the row and
                    -- would otherwise eat that click for nothing.
                    hit:SetScript("OnMouseUp", function(self, button)
                        local providers = r._buffProvider and r._buffProvider[def.key]
                        if button == "LeftButton" then
                            local target = providers and (providers.near or providers.single)
                            WhisperBuffProvider(def, target)
                        elseif button == "RightButton" then
                            local target = providers and providers.far
                            if target then
                                WhisperBuffProvider(def, target)
                            elseif win then
                                win:Hide()
                            end
                        end
                    end)

                    -- Referenced from Refresh via SetBuffBlink -- no
                    -- per-icon AnimationGroup anymore, see buffBlinkTargets
                    -- above for why.
                    r._buffIcon = r._buffIcon or {}
                    r._buffIcon[c] = tex
                end
                r._cellHit = r._cellHit or {}
                r._cellHit[c] = hit
            end
        end
    end

    rows[index] = r
    return r
end

local function Build()
    EnsureColumns()

    win = CreateFrame("Frame", "EllesmereUIRaidCheckWindow", UIParent)
    win:SetFrameStrata("DIALOG")
    win:SetFrameLevel(200)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:Hide()
    EllesmereUI.RegisterEscapeClose(win)

    EllesmereUI.SolidTex(win, "BACKGROUND", 0.06, 0.08, 0.10, 0.95):SetAllPoints()
    EllesmereUI.MakeBorder(win, 1, 1, 1, EllesmereUI.DD_BRD_A, EllesmereUI.PP)

    local title = MakeText(win, 13)
    title:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -PAD)
    title:SetText(EllesmereUI.L("Raid Check"))
    local function TintTitle() title:SetTextColor(EllesmereUI.GetAccentColor()) end
    TintTitle()
    -- Set once at build would go stale on a theme change.
    EllesmereUI.RegAccent({ type = "callback", fn = TintTitle })

    -- Headers, once per member column so both halves are labelled. Icons
    -- rather than captions: twelve columns leave no room for words, and the
    -- spell's own art needs no translating. Each is a frame so it can be
    -- hovered -- twelve icons and not a word says nothing on its own.
    for mc = 1, MEMBER_COLS do
        for _, def in ipairs(COLUMNS) do
            local h = CreateFrame("Frame", nil, win)
            h:SetSize(ICON_SZ, ICON_SZ)
            local tex = h:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            local icon = def.icon
            if not icon and def.seed and C_Spell and C_Spell.GetSpellInfo then
                local info = C_Spell.GetSpellInfo(def.seed)
                icon = info and info.iconID
            end
            if icon then
                tex:SetTexture(icon)
            else
                tex:SetAtlas(ATLAS_MISS)
            end

            -- Raid buff columns only: when hiding inapplicable columns and
            -- the providing class is not in the group, the column stays
            -- (see the visibility pass in Refresh) but reads as "nobody can
            -- give this" rather than quietly vanishing.
            if def.class then
                local xMark = h:CreateTexture(nil, "OVERLAY")
                xMark:SetAllPoints()
                xMark:SetAtlas(ATLAS_MISS)
                xMark:SetVertexColor(1, 0.15, 0.15, 1)
                xMark:Hide()
                h.xMark = xMark

                -- Raid Buff Whisper lives on this one icon rather than on
                -- every row's cell: "is anyone missing this, and who do I
                -- ask" is a question about the whole raid, not about any one
                -- player, so it belongs on the icon that represents the
                -- whole column. h._buffMissing/h._buffProviders are written
                -- by Refresh() every sweep and read here at hover/click time,
                -- same reasoning as everywhere else in this file that a
                -- click target travels as a resolved value rather than
                -- something recomputed live off a stale unit token.
                -- h._icon feeds the shared blink driver (SetBuffBlink) so
                -- this icon pulses in lockstep with every other blinking
                -- raid-buff icon instead of running its own phase.
                h._icon = tex
            end

            h:EnableMouse(true)
            h:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(ColumnName(def))
                if def.note then
                    GameTooltip:AddLine(EllesmereUI.L(def.note), 1, 1, 1, true)
                end
                if def.class then
                    if h._buffMissing == false then
                        GameTooltip:AddLine(EllesmereUI.L("Everyone already has this buff."), 0.6, 1, 0.6, true)
                    elseif h._buffMissing then
                        local providers = h._buffProviders or {}
                        local near, far, single = providers.near, providers.far, providers.single
                        if single then
                            GameTooltip:AddLine(EllesmereUI.L("Left-click to whisper") .. " " .. single, 0.8, 0.8, 0.8, true)
                        elseif near or far then
                            if near then
                                GameTooltip:AddLine(EllesmereUI.L("Left-click to whisper") .. " " .. near, 0.8, 0.8, 0.8, true)
                            end
                            if far then
                                GameTooltip:AddLine(EllesmereUI.L("Right-click to whisper") .. " " .. far, 0.8, 0.8, 0.8, true)
                            end
                        else
                            GameTooltip:AddLine(EllesmereUI.L("Someone is missing it, but nobody reachable can provide it right now."), 1, 0.7, 0.7, true)
                        end
                    end
                end
                if def.key == DURABILITY_KEY then
                    -- Auto-Repair status, same three-way shape as the raid-
                    -- buff headers: nothing to say when the option/raid/
                    -- combat gate is off (h._lowDurability stays nil, see
                    -- the tail loop in Refresh), a green line when nobody is
                    -- low, a click hint when someone is.
                    if h._lowDurability == false then
                        GameTooltip:AddLine(EllesmereUI.L("Nobody is below the Auto-Repair threshold."), 0.6, 1, 0.6, true)
                    elseif h._lowDurability then
                        GameTooltip:AddLine(EllesmereUI.L("Left-click to use the Auto-Hammer."), 0.8, 0.8, 0.8, true)
                    end
                end
                GameTooltip:Show()
            end)
            h:SetScript("OnLeave", function() GameTooltip:Hide() end)
            if def.key == DURABILITY_KEY then
                -- One action, not two, so there's no near/far split like the
                -- raid-buff headers -- Auto-Repair always targets yourself,
                -- so there is only one thing a click here could ever mean.
                h:SetScript("OnMouseUp", function(self, button)
                    if button == "LeftButton" then
                        UseAutoRepairItem()
                    end
                end)
            end
            if def.class then
                -- Left whispers the near (groups 1-4) or, outside a raid,
                -- the only target; right whispers the far (groups 5-8)
                -- target. Both are no-ops (WhisperBuffProvider itself checks)
                -- when that slot has nobody in it -- there is nothing else
                -- bound to a raid-buff header's right-click, so there is no
                -- fallback action to preserve the way there is on a row.
                h:SetScript("OnMouseUp", function(self, button)
                    local providers = h._buffProviders
                    if button == "LeftButton" then
                        WhisperBuffProvider(def, providers and (providers.near or providers.single))
                    elseif button == "RightButton" then
                        WhisperBuffProvider(def, providers and providers.far)
                    end
                end)
            end

            colHeader[def.key] = colHeader[def.key] or {}
            colHeader[def.key][mc] = h
        end
    end

    -- Dragging the window, and remembering where it was left.
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p = P()
        if not p then return end
        local point, _, relPoint, x, y = self:GetPoint()
        p.pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    -- Hooked on the frame rather than done in HideRaidCheck: Escape closes
    -- this through RegisterEscapeClose, which hides the frame directly. Arming
    -- and disarming anywhere else leaves the sweep running on a window nobody
    -- can see, for the rest of the session.
    win:HookScript("OnHide", function()
        if sweeper then sweeper.Stop() end
        -- Closed some other way (Escape, right-click, /euiraidcheck show
        -- toggling it off): whatever countdown was armed no longer applies.
        if closeTimer then closeTimer:Cancel(); closeTimer = nil end
        if combatCloseTimer then combatCloseTimer:Cancel(); combatCloseTimer = nil end
        -- The icons themselves are about to be hidden with the window, so
        -- there's nothing to visually reset -- just stop the OnUpdate and
        -- drop the references so a closed window isn't still driving one.
        if buffBlinkDriver then buffBlinkDriver:Hide() end
        wipe(buffBlinkTargets)
    end)

    -- Right-click anywhere on the window closes it, so no dedicated close
    -- button is needed. Rows re-arm the same handler (see MakeRow) since a
    -- row with mouse enabled for the hover highlight would otherwise eat the
    -- click before it reaches the window frame beneath it.
    win:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then self:Hide() end
    end)

    -- One row per possible roster slot (MAX_ROSTER, not MEMBER_COLS *
    -- COL_ROWS): single-column mode can stack all 40 in column one, past
    -- what the two-column layout alone would ever need.
    for i = 1, MAX_ROSTER do MakeRow(win, i) end
end

-- Puts every header and cell where the current column set says it belongs, and
-- hides the ones that are not in it.
--
-- Guarded by a signature because it is real work -- forty rows times twelve
-- cells -- and the column set changes when the group does, not every two
-- seconds.
--
-- rowsPerCol is normally COL_ROWS; Refresh passes something larger when the
-- big-raid single-column mode (see SINGLE_COL_THRESHOLD) is folding the
-- whole roster into column one instead of wrapping into column two.
local lastLayoutSig
local function Relayout(visible, slotOf, memberCols, bodyW, rowsPerCol)
    rowsPerCol = rowsPerCol or COL_ROWS
    local sig = memberCols .. "|" .. rowsPerCol .. "|" .. table.concat(visible, ",")
    if sig == lastLayoutSig then return end
    lastLayoutSig = sig

    local headerY = -(PAD + TITLE_H)
    for mc = 1, MEMBER_COLS do
        local baseX = PAD + (mc - 1) * (bodyW + COL_GAP)
        for _, def in ipairs(COLUMNS) do
            local h = colHeader[def.key][mc]
            local slot = slotOf[def.key]
            h:SetShown(slot ~= nil and mc <= memberCols)
            if slot then
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", win, "TOPLEFT",
                    baseX + NAME_W + (slot - 1) * CELL_W + (CELL_W - ICON_SZ) / 2,
                    headerY)
            end
        end
    end

    for i = 1, #rows do
        local r = rows[i]
        local mc   = math.floor((i - 1) / rowsPerCol)
        local line = (i - 1) % rowsPerCol
        r:SetSize(bodyW, ROW_H)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", win, "TOPLEFT",
            PAD + mc * (bodyW + COL_GAP),
            headerY - HEADER_H - line * ROW_H)
        for ci, def in ipairs(COLUMNS) do
            local slot = slotOf[def.key]
            if slot then
                local x = NAME_W + (slot - 1) * CELL_W
                local cell = r._cells[ci]
                cell:ClearAllPoints()
                if def.numeric then
                    cell:SetPoint("LEFT", r, "LEFT", x, 0)
                    -- The tick shares the slot with the number; only one of
                    -- the two is ever shown.
                    local tex = r._cellTex[ci]
                    tex:ClearAllPoints()
                    tex:SetPoint("LEFT", r, "LEFT", x + (CELL_W - ICON_SZ) / 2, 0)
                else
                    cell:SetPoint("LEFT", r, "LEFT", x + (CELL_W - ICON_SZ) / 2, 0)
                    local hit = r._cellHit and r._cellHit[ci]
                    if hit then
                        hit:ClearAllPoints()
                        hit:SetPoint("LEFT", r, "LEFT", x + (CELL_W - ICON_SZ) / 2, 0)
                    end
                end
            end
        end
    end
end

-- Repaints everything from a fresh roster read.
local function Refresh()
    if not win or not win:IsShown() then return end

    -- Roster first, auras second: a raid buff nobody present can cast is not a
    -- failing, and knowing that spares reading its ids on every member. With
    -- no Evoker, Blessing of the Bronze alone is thirteen ids across forty
    -- people that answer a column nobody will ever look at.
    local roster = ReadMembers()
    local classPresent = {}
    for _, e in ipairs(roster) do
        if e.class then classPresent[e.class] = true end
    end

    -- Roster-invariant, so decided once rather than per member per column.
    -- ConsumablesBlockedByCombat(): any combat (trash or boss) inside a raid
    -- or an active M+ pauses the personal-consumable columns (see
    -- Answerable); a normal/heroic dungeon or open-world fight does not.
    local restricted = Restricted()
    local consumablesBlocked = ConsumablesBlockedByCombat()
    local answerable = {}
    for _, def in ipairs(COLUMNS) do
        answerable[def.key] = Answerable(def, restricted, classPresent, consumablesBlocked)
    end

    -- Auto-Repair is raid-only regardless of the option -- a party or M+
    -- group is never far from a vendor between pulls, so the click target
    -- and the blink both sit out anywhere else. Combat is a hard no for both
    -- durability's click/blink AND the raid-buff whisper/blink below: a pull
    -- is not when anyone should be staring at this window, let alone
    -- clicking it.
    local outOfCombat  = not InCombatLockdown()
    local autoRepairOn = ns.RaidCheckAutoRepair() and IsInRaid() and outOfCombat

    -- Unlike Auto-Repair, this one is NOT out-of-combat-only: whispering a
    -- request for a buff doesn't touch anything protected, and a missing
    -- raid buff is just as worth catching mid-pull as between them.
    local buffWhisperOn = ns.RaidCheckBuffWhisper()

    -- One reachable provider per raid-buff column, decided once here rather
    -- than per row: every row missing the same buff would otherwise redo the
    -- exact same roster walk. "Reachable" means online, alive, and near you
    -- -- Phased() (see above), the same broadcast-range + phase check used
    -- for the recipient side, applied here to the provider instead. A
    -- provider who is technically online but out of your broadcast range,
    -- in a different phase, or dead/a ghost isn't someone who can
    -- realistically cast anything right now, so they don't count as a
    -- target and don't trigger the blink below. Self is excluded on
    -- purpose: whispering yourself to ask for your own missing buff is not
    -- a thing this feature needs to support.
    --
    -- In a raid, a column can carry up to two independent targets -- one
    -- from the front half of the roster (groups 1-4), one from the back half
    -- (groups 5-8) -- since a 20-40 man raid can easily have a provider
    -- covering each half rather than one for the whole raid. Left-click
    -- reaches the near one, right-click the far one (see the hit frame's
    -- OnMouseUp in MakeRow). Outside a raid there is only one subgroup, so
    -- there is only ever a `single` target, and only left-click is wired to
    -- it -- right-click keeps closing the window there, same as everywhere
    -- else in the grid.
    local inRaid = IsInRaid()
    local providerFor = {}
    -- Whether at least one roster member is missing each raid-buff column --
    -- raid/party-wide, filled in as rows are painted below. This is what the
    -- column HEADER's own blink/tooltip/click go by (see the tail loop
    -- further down): "everyone already has it" is a raid-wide claim, not a
    -- per-row one, so it belongs on the one icon that represents the whole
    -- column rather than on any single player's cell.
    local anyMissing = {}
    -- Whether anyone in the raid currently reads at or below
    -- AUTO_REPAIR_THRESHOLD -- filled in as rows are painted below, read by
    -- the Durability column HEADER's own click/tooltip (see the tail loop
    -- further down), the same way anyMissing feeds the raid-buff headers.
    local anyLowDurability = false
    for _, def in ipairs(COLUMNS) do
        if def.class then
            local entry = {}
            for _, e in ipairs(roster) do
                if e.class == def.class and not e.isSelf and e.online
                    and not Phased(e.unit) and not UnitIsDeadOrGhost(e.unit) then
                    if inRaid then
                        local grp = e.group or 1
                        if grp <= 4 then
                            entry.near = entry.near or FullName(e.unit)
                        else
                            entry.far = entry.far or FullName(e.unit)
                        end
                    else
                        entry.single = entry.single or FullName(e.unit)
                    end
                    if inRaid then
                        if entry.near and entry.far then break end
                    elseif entry.single then
                        break
                    end
                end
            end
            providerFor[def.key] = entry
        end
    end

    for _, e in ipairs(roster) do
        e.checks = UnitChecks(e.unit, answerable, restricted)
        e.phased = Phased(e.unit)
        -- A corpse/ghost can't receive a raid buff at all -- not a data
        -- reliability question like offline/phased, just a plain fact --
        -- so a MISSING verdict on a dead player gets the same treatment
        -- (see the def.class block below). UnitIsDeadOrGhost is ordinary,
        -- non-secret unit state (BuffReminders' own IsValidBuffTarget uses
        -- it unguarded the same way).
        e.dead = UnitIsDeadOrGhost(e.unit)
        local r = reported[e.name]
        if r then
            e.durability = r.dur
            if r.we then
                e.checks[WENCHANT_KEY] = EnchantOK(r.we)
                e.enchantID = r.we
            end
        end
        -- Last, so the local read beats anything that came off the wire: it is
        -- current, and your own row must not depend on a message that is not
        -- sent at all when you are alone.
        if e.isSelf then
            for _, def in ipairs(SELF_COLS) do e.checks[def.key] = def.selfRead() end
            e.enchantID = MyEnchantID()
        end
    end

    -- Your own Vantus, if any -- read off your own row rather than a
    -- second aura scan, since UnitChecks/SweepBody just filled it in above.
    -- nil when you have none up, or the column can't answer at all (Vantus
    -- is raid-only and unavailable under restriction); either way there is
    -- nothing to compare anyone else's rune against, so the mismatch blink
    -- below simply never fires.
    local myVantusName
    for _, e in ipairs(roster) do
        if e.isSelf then
            myVantusName = e.checks._names and e.checks._names[VANTUS_KEY]
            break
        end
    end

    -- Which columns are on screen. Dimming an inapplicable one still spends
    -- width on it, so it can be dropped outright instead -- and then the
    -- remaining columns close ranks.
    local hide = ns.RaidCheckHideInapplicable()
    local visible, slotOf = {}, {}
    for _, def in ipairs(COLUMNS) do
        -- Raid buff columns are an exception to hiding: a group-wide buff
        -- nobody can cast is not the same situation as Vantus outside a raid
        -- or an icon column under restriction, where there is genuinely
        -- nothing to say. Here there is something to say -- "nobody can give
        -- this" -- so the column stays and reads as a red X instead.
        if answerable[def.key] or not hide or def.class then
            visible[#visible + 1] = def.key
            slotOf[def.key] = #visible
        end
    end

    -- Only the people something is wrong with, and only when asked -- nobody
    -- reads a fault count that is not on screen, so the whole pass is skipped
    -- rather than computed and discarded.
    --
    -- A missing verdict is NOT a fault. Someone whose client has not reported,
    -- or whose aura the game refused to disclose, has not failed anything, so
    -- only an explicit failure keeps a row.
    if ns.RaidCheckHideReady() then
        local short = {}
        local low = EllesmereUI.DURABILITY_LOW
        for _, e in ipairs(roster) do
            for _, def in ipairs(COLUMNS) do
                if answerable[def.key] then
                    local bad
                    if def.numeric then
                        bad = e.durability ~= nil and e.durability <= low
                    else
                        bad = e.checks[def.key] == false
                    end
                    -- One fault is enough to keep the row; what it is shows in
                    -- the grid.
                    if bad then
                        short[#short + 1] = e
                        break
                    end
                end
            end
        end
        roster = short
    end

    -- The window fits the group rather than the largest group possible.
    -- Below the threshold this is the original two-column wrap; past 20
    -- members it switches to one tall column instead of spilling into a
    -- second, so the roster reads top-to-bottom in one pass instead of two.
    local n = #roster
    local memberCols, rowsPerCol
    if n >= SINGLE_COL_THRESHOLD then
        memberCols = 1
        rowsPerCol = math.min(math.max(n, 1), MAX_ROSTER)
    else
        memberCols = math.max(1, math.ceil(n / COL_ROWS))
        rowsPerCol = COL_ROWS
    end
    local rowsShown  = math.min(math.max(n, 1), rowsPerCol)
    local bodyW      = NAME_W + #visible * CELL_W
    win:SetSize(PAD * 2 + memberCols * bodyW + (memberCols - 1) * COL_GAP,
                PAD * 2 + TITLE_H + HEADER_H + rowsShown * ROW_H)
    Relayout(visible, slotOf, memberCols, bodyW, rowsPerCol)

    for i = 1, #rows do
        local r, e = rows[i], roster[i]
        if e then
            local c = EllesmereUI.GetClassColor(e.class)
            r._name:SetText(e.name)
            -- Same dim for both: offline and "elsewhere" (a different
            -- instance/phase -- UnitPhaseReason returns nil when the unit is
            -- right there with you) read the same way at a glance, and
            -- neither one is a fault the way a missing consumable is.
            -- UnitPhaseReason is guarded for older clients that predate it,
            -- same as EllesmereUIRaidFrames' own use of it.
            local elsewhere = UnitPhaseReason and UnitPhaseReason(e.unit)
            local dim = (not e.online) or elsewhere
            r._name:SetTextColor(c.r, c.g, c.b, dim and 0.2 or 1)

            if readyCheckActive then
                local status = GetReadyCheckStatus(e.unit)
                if status == "ready" then
                    r._ready:SetText("")
                    r._readyTex:SetAtlas(ATLAS_OK)
                    r._readyTex:Show()
                elseif status == "notready" then
                    r._ready:SetText("")
                    r._readyTex:SetAtlas(ATLAS_MISS)
                    r._readyTex:Show()
                elseif status == "waiting" then
                    r._readyTex:Hide()
                    r._ready:SetText("?")
                    r._ready:SetTextColor(1, 0.85, 0.1)
                else
                    r._readyTex:Hide()
                    r._ready:SetText("")
                end
            else
                r._readyTex:Hide()
                r._ready:SetText("")
            end
            for ci, def in ipairs(COLUMNS) do
                local cell = r._cells[ci]
                local tex  = r._cellTex[ci]
                if not slotOf[def.key] then
                    cell:Hide()
                    if tex then tex:Hide() end
                    if r._cellHit and r._cellHit[ci] then r._cellHit[ci]:Hide() end
                    if def.key == DURABILITY_KEY then
                        if r._lowDurBlink:IsPlaying() then
                            r._lowDurBlink:Stop()
                            r._name:SetAlpha(1)
                        end
                        if r._durNumBlink:IsPlaying() then
                            r._durNumBlink:Stop()
                            cell:SetAlpha(1)
                        end
                    end
                    if def.class then
                        SetBuffBlink(cell, false, 0.9)
                    end
                    if def.key == VANTUS_KEY and r._vantusMismatchBlink:IsPlaying() then
                        r._vantusMismatchBlink:Stop()
                        cell:SetAlpha(0.9)
                    end
                elseif def.numeric then
                    -- The number is shown at every reading, including 100 --
                    -- a plain number reads faster at a glance than a tick
                    -- that means "full" only for this one column.
                    local pct = e.durability
                    local shown = pct and math.floor(pct + 0.5)
                    cell:SetShown(shown ~= nil)
                    tex:Hide()
                    if shown then
                        cell:SetText(shown)
                        cell:SetTextColor(EllesmereUI.GetDurabilityColor(pct))
                    end

                    if def.key == DURABILITY_KEY then
                        local lowDur = autoRepairOn and pct ~= nil and pct <= AUTO_REPAIR_THRESHOLD
                        if lowDur then anyLowDurability = true end
                        if lowDur then
                            if not r._lowDurBlink:IsPlaying() then r._lowDurBlink:Play() end
                            if not r._durNumBlink:IsPlaying() then r._durNumBlink:Play() end
                        else
                            if r._lowDurBlink:IsPlaying() then
                                r._lowDurBlink:Stop()
                                r._name:SetAlpha(1)
                            end
                            if r._durNumBlink:IsPlaying() then
                                r._durNumBlink:Stop()
                                cell:SetAlpha(1)
                            end
                        end
                    end
                else
                    -- Deliberately not `answerable and checks or nil`: `and`
                    -- binds tighter, so a false verdict would fall through to
                    -- nil and a missing consumable would draw nothing at all.
                    local v
                    if answerable[def.key] then v = e.checks[def.key] end
                    -- A MISSING verdict is not trusted/flagged for someone
                    -- offline or phased away from you -- their aura state
                    -- (or, for weapon enchant, their last report) may simply
                    -- not be current -- for raid buffs (def.class) AND for
                    -- personal consumables (flask/food/rune/vantus, answered
                    -- via ids/icons/prefix) AND weapon enchant, requested to
                    -- follow the exact same rule as the consumables it's
                    -- grouped with here even though it technically arrives
                    -- over comms rather than a live aura read. Raid buffs get
                    -- one more case: dead/ghost, who plainly cannot receive a
                    -- buff at all right now -- that one does NOT extend to
                    -- consumables or weapon enchant, since a flask/food/rune/
                    -- oil generally survives death, so a dead player's
                    -- reading there is still meaningful. A present (v==true)
                    -- verdict is kept regardless of any of this: that
                    -- information doesn't depend on live sync or current
                    -- state the way an absence does. See Phased() above.
                    -- Durability is the one column still fully unaffected.
                    if v == false then
                        local unreliable = not e.online or e.phased
                        local personalAura = not def.class
                            and (def.ids or def.icons or def.prefix or def.key == WENCHANT_KEY)
                        if def.class and (unreliable or e.dead) then
                            v = nil
                        elseif personalAura and unreliable then
                            v = nil
                        end
                    end
                    if def.class and v == false then
                        anyMissing[def.key] = true
                    end
                    if def.prefix or def.nameTooltip then
                        r._auraNames = r._auraNames or {}
                        r._auraNames[def.key] = e.checks._names and e.checks._names[def.key]
                        r._auraExpires = r._auraExpires or {}
                        r._auraExpires[def.key] = e.checks._expires and e.checks._expires[def.key]
                    elseif def.key == WENCHANT_KEY then
                        -- Best-effort, see EnchantName -- nil just means no
                        -- tooltip line, same as any other unresolved name.
                        r._auraNames = r._auraNames or {}
                        r._auraNames[def.key] = EnchantName(e.enchantID)
                    end
                    local hit = r._cellHit and r._cellHit[ci]
                    if v == true then
                        cell:SetAtlas(ATLAS_OK)
                        cell:Show()
                        if def.class then
                            -- Present: nothing to whisper for, nothing to blink.
                            if hit then hit:Hide() end
                            SetBuffBlink(cell, false, 0.9)
                        else
                            -- Only the tick is hoverable: a MISS or a blank
                            -- cell has no buff name behind it to report.
                            if hit then hit:Show() end

                            if def.key == VANTUS_KEY then
                                local theirName = e.checks._names and e.checks._names[def.key]
                                local mismatch = outOfCombat and myVantusName
                                    and theirName and theirName ~= myVantusName
                                if mismatch then
                                    if not r._vantusMismatchBlink:IsPlaying() then
                                        r._vantusMismatchBlink:Play()
                                    end
                                elseif r._vantusMismatchBlink:IsPlaying() then
                                    r._vantusMismatchBlink:Stop()
                                    cell:SetAlpha(0.9)
                                end
                            end
                        end
                    elseif v == false then
                        cell:SetAtlas(ATLAS_MISS)
                        cell:Show()
                        if def.class then
                            -- Blinks and is clickable only when a nearby
                            -- provider exists (see providerFor above) -- a
                            -- missing buff nobody around can fix isn't worth
                            -- flashing about.
                            local providers = providerFor[def.key]
                            r._buffProvider = r._buffProvider or {}
                            r._buffProvider[def.key] = providers
                            local hasProvider = providers
                                and (providers.near or providers.far or providers.single)
                            local active = buffWhisperOn and hasProvider ~= nil
                            if hit then hit:SetShown(active) end
                            SetBuffBlink(cell, active, 0.9)
                        else
                            if hit then hit:Hide() end
                        end
                        if def.key == VANTUS_KEY and r._vantusMismatchBlink:IsPlaying() then
                            r._vantusMismatchBlink:Stop()
                            cell:SetAlpha(0.9)
                        end
                    else
                        -- Unanswerable, or the client would not say.
                        cell:Hide()
                        if hit then hit:Hide() end
                        if def.class then
                            SetBuffBlink(cell, false, 0.9)
                        end
                        if def.key == VANTUS_KEY and r._vantusMismatchBlink:IsPlaying() then
                            r._vantusMismatchBlink:Stop()
                            cell:SetAlpha(0.9)
                        end
                    end
                end
            end
            r:Show()
        else
            r:Hide()
            if r._lowDurBlink:IsPlaying() then
                r._lowDurBlink:Stop()
                r._name:SetAlpha(1)
            end
            if r._durNumBlink and r._durNumBlink:IsPlaying() then
                r._durNumBlink:Stop()
                r._durNumBlink:GetParent():SetAlpha(1)
            end
            if r._buffIcon then
                for _, icon in pairs(r._buffIcon) do
                    SetBuffBlink(icon, false, 0.9)
                end
            end
            if r._vantusMismatchBlink and r._vantusMismatchBlink:IsPlaying() then
                r._vantusMismatchBlink:Stop()
                r._vantusMismatchBlink:GetParent():SetAlpha(0.9)
            end
        end
    end

    -- An unanswerable column that stays on screen (hiding off, or restricted
    -- content) is dimmed, reading as "no data". A class-missing raid buff
    -- column is a different case -- there IS an answer, the class is simply
    -- not in the group -- so it stays at full alpha with a red X instead,
    -- whatever the hide setting.
    for _, def in ipairs(COLUMNS) do
        if slotOf[def.key] then
            local on = answerable[def.key]
            local classMissing = def.class and not on
            for mc = 1, MEMBER_COLS do
                local h = colHeader[def.key][mc]
                local baseAlpha = classMissing and 1 or (on and 0.8 or 0.2)
                h:SetAlpha(baseAlpha)
                if h.xMark then h.xMark:SetShown(classMissing) end
                if def.class and h._icon then
                    -- nil when the class isn't in the group at all (on is
                    -- false): distinct from "on, but nobody's missing it",
                    -- which is anyMissing[def.key] == false rather than nil.
                    -- The header's OnEnter treats those differently -- see
                    -- MakeRow -- so this is not the same as writing false.
                    h._buffMissing   = on and (anyMissing[def.key] or false) or nil
                    h._buffProviders = providerFor[def.key]
                    local providers = providerFor[def.key]
                    local hasProvider = providers
                        and (providers.near or providers.far or providers.single)
                    local blinking = buffWhisperOn and on and anyMissing[def.key]
                        and hasProvider ~= nil
                    SetBuffBlink(h._icon, blinking, baseAlpha)
                end
                if def.key == DURABILITY_KEY then
                    -- Same nil/false/true shape as h._buffMissing: nil when
                    -- Auto-Repair isn't active right now at all (option off,
                    -- not a raid, or in combat), so the header's OnEnter says
                    -- nothing rather than falsely claiming "nobody's low".
                    if autoRepairOn then
                        h._lowDurability = anyLowDurability
                    else
                        h._lowDurability = nil
                    end
                end
            end
        end
    end

    return true   -- the ticker keeps going while the window is up
end

-------------------------------------------------------------------------------
--  Options accessors
--
--  The page's entire view of this feature. Each reads with no argument and
--  writes with one, so the slice name and the profile walk never leave here.
-------------------------------------------------------------------------------

function ns.ApplyRaidCheckScale()
    if not win then return end
    local base = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1
    local p = P()
    win:SetScale(base * ((p and p.scale) or 1))
end

function ns.RaidCheckScale(v)
    local p = P()
    if v == nil then return (p and p.scale) or 1 end
    if not p then return end
    p.scale = v
    ns.ApplyRaidCheckScale()
end

function ns.RaidCheckHideReady(v)
    local p = P()
    if v == nil then return (p and p.hideReady) == true end
    if not p then return end
    p.hideReady = v
    lastLayoutSig = nil   -- the row count changed, so the grid is re-laid out
    Refresh()
end

function ns.RaidCheckHideInapplicable(v)
    local p = P()
    if v == nil then return not p or p.hideInapplicable ~= false end
    if not p then return end
    p.hideInapplicable = v
    lastLayoutSig = nil   -- the column set changed
    Refresh()
end

function ns.RaidCheckAutoRepair(v)
    local p = P()
    if v == nil then return (p and p.autoRepair) == true end
    if not p then return end
    p.autoRepair = v
    -- Not raid-gated here: the toggle can be flipped from anywhere, and
    -- Refresh() is what actually decides whether it applies right now.
    Refresh()
end

function ns.RaidCheckBuffWhisper(v)
    local p = P()
    if v == nil then return (p and p.buffWhisper) == true end
    if not p then return end
    p.buffWhisper = v
    Refresh()
end

function ns.RaidCheckEnabled(v)
    local p = P()
    if v == nil then return (p and p.enabled) == true end
    if not p then return end
    p.enabled = v
    if not v then ns.HideRaidCheck() end
end

function ns.RaidCheckShowWithoutRank(v)
    local p = P()
    if v == nil then return (p and p.showWithoutRank) == true end
    if not p then return end
    p.showWithoutRank = v
    if not MayShow() then ns.HideRaidCheck() end
end

-------------------------------------------------------------------------------
--  Show / hide
-------------------------------------------------------------------------------

function ns.HideRaidCheck()
    if win then win:Hide() end   -- OnHide stops the sweep and cancels closeTimer
end

-- `fromReadyCheck` suppresses the query: on that path every client has already
-- volunteered unprompted, and asking again would make each of them broadcast
-- once more for every leader whose window opened.
function ns.ShowRaidCheck(fromReadyCheck)
    if not MayShow() then return end
    if not win then Build() end

    ApplyFonts()
    ns.ApplyRaidCheckScale()
    win:ClearAllPoints()
    local p = P()
    local pos = p and p.pos
    if pos and pos.point then
        win:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        win:SetPoint("CENTER")
    end

    -- Ask before painting: answers land over the next few seconds and the
    -- sweep picks them up. Both transports throttle their own requests, so
    -- reopening the window repeatedly costs nothing.
    local LD = LibDur()
    if LD then LD:RequestDurability() end
    if not fromReadyCheck and EllesmereUI.Comms then
        EllesmereUI.Comms.Send(MSG_QUERY, "")
    end

    win:Show()
    Refresh()
    openedAt = GetTime()
    openedManually = not fromReadyCheck
    if combatCloseTimer then combatCloseTimer:Cancel(); combatCloseTimer = nil end
    -- Always closes itself CLOSE_DELAY seconds after opening, no matter how
    -- it was opened -- a ready check, or the player manually toggling it
    -- with /euiraidcheck. Re-showing (another ready check, or opening it
    -- again manually) restarts the countdown rather than stacking one.
    if closeTimer then closeTimer:Cancel() end
    closeTimer = C_Timer.NewTimer(CLOSE_DELAY, function()
        closeTimer = nil
        if win and win:IsShown() then ns.HideRaidCheck() end
    end)
    -- An interval driver, not a per-frame one: people drink their flask DURING
    -- the check so the grid has to follow, but not at frame rate. The frame is
    -- created here, in this addon's chunk, because the engine bills a
    -- handler's whole call tree to the addon that created the frame (see
    -- EllesmereUI_Ticker.lua) -- the shared driver would charge the parent.
    sweeper = sweeper or EllesmereUI.Tick.NewAnimTicker(CreateFrame("Frame"), Refresh, SWEEP_PERIOD)
    sweeper.Start()
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not (EllesmereUI and EllesmereUI.Lite and EllesmereUI.Lite.NewDB) then return end
    -- Merges DB_DEFAULTS into the shared QoL profile, the arrangement every
    -- QoL feature uses.
    db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", DB_DEFAULTS, true)
    if not EllesmereUI._onScaleChanged then EllesmereUI._onScaleChanged = {} end
    EllesmereUI._onScaleChanged[#EllesmereUI._onScaleChanged + 1] = ns.ApplyRaidCheckScale

    -- Listening and answering are unconditional and session-long: someone
    -- else's raid check should work whether or not you use your own, and a
    -- report that arrived before the window opened is already there when it
    -- does. Reports also answer other addons' requests, so the durability
    -- column is populated the moment the window opens.
    local LD = LibDur()
    if LD then LD:Register("EllesmereUIRaidCheck", NoteDurability) end

    local C = EllesmereUI.Comms
    if C then
        C.On(MSG_QUERY,  function() C.Send(MSG_REPORT, MyReport(), C.REPLY_SPREAD) end)
        C.On(MSG_REPORT, ReadReport)
    end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("READY_CHECK")
ev:RegisterEvent("READY_CHECK_CONFIRM")
ev:RegisterEvent("READY_CHECK_FINISHED")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat closes the window -- unless it was opened by hand
        -- less than MIN_MANUAL_OPEN seconds ago, in which case it is
        -- guaranteed to stay up until that grace period runs out. Right-click
        -- and Escape still close it immediately either way (see win's own
        -- OnMouseUp/RegisterEscapeClose), and the OnHide hook cancels this
        -- timer if the window goes away some other way first.
        if win and win:IsShown() then
            local minOpen = openedManually and MIN_MANUAL_OPEN or 0
            local remaining = minOpen - (GetTime() - (openedAt or 0))
            if remaining <= 0 then
                ns.HideRaidCheck()
            else
                if combatCloseTimer then combatCloseTimer:Cancel() end
                combatCloseTimer = C_Timer.NewTimer(remaining, function()
                    combatCloseTimer = nil
                    if win and win:IsShown() then ns.HideRaidCheck() end
                end)
            end
        end
        return
    end
    if event == "READY_CHECK" then
        readyCheckActive = true
        -- Volunteer on every ready check, feature enabled or not: a ready
        -- check is already the moment the group asks, so nobody needs to send
        -- a query and the answers are in flight before any window opens.
        local C = EllesmereUI.Comms
        if C then C.Send(MSG_REPORT, MyReport(), C.REPLY_SPREAD) end
        -- Any ready check, whoever started it: an assistant checking the raid
        -- and the leader should see the same thing. (Arms the close timer.)
        ns.ShowRaidCheck(true)
        return
    end
    if event == "READY_CHECK_CONFIRM" then
        -- One player's status just landed -- paint it immediately rather
        -- than waiting on the next sweep, which can be up to SWEEP_PERIOD
        -- seconds away and would read as the grid ignoring the click.
        Refresh()
        return
    end
    if event == "READY_CHECK_FINISHED" then
        readyCheckActive = false
        Refresh()
        return
    end
    -- Leaving the group, or losing rank without the option, closes it.
    if win and win:IsShown() and not MayShow() then ns.HideRaidCheck() end
end)

-------------------------------------------------------------------------------
--  Maintenance
--
--  Consumable ids change every patch, so this ships rather than living in a
--  branch: `ids` audits what is configured, `buffs` lists what the player is
--  carrying so a new id can be read off and pasted in. Inert until invoked,
--  the same arrangement as /euiloc.
-------------------------------------------------------------------------------
SLASH_EUIRAIDCHECK1 = "/euiraidcheck"
SlashCmdList["EUIRAIDCHECK"] = function(msg)
    local Print = EllesmereUI.Print
    local tag = "|cff0cd29fEllesmereUI:|r "
    EnsureColumns()

    if msg == "show" then
        -- Opening it without starting a ready check: looking at the raid
        -- should not require pinging everyone in it.
        if win and win:IsShown() then ns.HideRaidCheck() else ns.ShowRaidCheck() end
        return
    end

    if msg == "buffs" then
        -- The player's own auras, one line each: spell id, icon id, name, and
        -- the column it satisfies. When a consumable reads as missing, this
        -- says whether the id is simply unlisted or the sweep never saw the
        -- aura at all.
        --
        -- Matched through the same tables the grid uses, so it can never
        -- claim a hit the grid would not.
        for i = 1, AURA_SCAN_LIMIT do
            local ok, aura = pcall(GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not aura then break end
            local id = aura.spellId
            if id and not (issecretvalue and issecretvalue(id)) then
                local key
                for _, def in ipairs(ICON_COLS) do
                    if aura.icon and def.icons[aura.icon] then key = def.key end
                end
                for _, def in ipairs(NAME_COLS) do
                    local p = def.prefix()
                    if p and aura.name and aura.name:find(p, 1, true) == 1 then key = def.key end
                end
                key = ID_TO_KEY[id] or key
                Print(tag .. id .. "  icon " .. tostring(aura.icon) .. "  "
                    .. (aura.name or "?")
                    .. (key and ("  |cff0cd29f-> " .. key .. "|r") or ""))
            end
        end
        return
    end

    Print(tag .. "auras restricted: " .. tostring(Restricted())
        .. "   vantus prefix: " .. (VantusPrefix() or "|cffff5555unresolved|r"))
    for _, def in ipairs(COLUMNS) do
        if def.ids then
            for id in pairs(def.ids) do
                local secret = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
                    and C_Secrets.ShouldSpellAuraBeSecret(id)
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                Print(tag .. ColumnName(def) .. " " .. id .. "  "
                    .. ((info and info.name) or "|cffff5555?|r")
                    .. (secret and "  |cffff5555SECRET|r" or ""))
            end
        end
    end
end
