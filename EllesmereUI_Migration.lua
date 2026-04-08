--------------------------------------------------------------------------------
--  EllesmereUI_Migration.lua
--  Loaded via TOC after EllesmereUI_Lite.lua, before EllesmereUI_Profiles.lua.
--  Runs at ADDON_LOADED time for "EllesmereUI" (before child addons init).
--
--  All legacy migrations have been removed. The beta-exit wipe (reset
--  version 5) guarantees every user starts from a clean slate.
--------------------------------------------------------------------------------

local floor = math.floor

--- Round all width/height values in a table to whole pixels.
--- Call from each child addon's OnInitialize after its DB is loaded.
--- keys: list of field names to round (e.g. {"width", "height"})
--- tables: list of profile sub-tables to scan
function EllesmereUI.RoundSizeFields(keys, tables)
    for _, tbl in ipairs(tables) do
        if type(tbl) == "table" then
            for _, key in ipairs(keys) do
                local v = tbl[key]
                if type(v) == "number" then
                    tbl[key] = floor(v + 0.5)
                end
            end
        end
    end
end

local migrationFrame = CreateFrame("Frame")
migrationFrame:RegisterEvent("ADDON_LOADED")
migrationFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "EllesmereUI" then return end
    self:UnregisterEvent("ADDON_LOADED")
    -- Perform the full wipe for users updating from beta builds.
    -- This runs before child addons init so they see a clean DB.
    EllesmereUI.PerformResetWipe()
    -- Stamp fresh installs early (before child addons can create DBs
    -- that would make StampResetVersion think it's an old install).
    EllesmereUI.StampResetVersion()

    ---------------------------------------------------------------------------
    --  Migration: wipe legacy friends list data across all profiles.
    --  The friends module was fully rebuilt (session 15-17). Old profile data
    --  contains stale keys (bgAlpha without bgR/G/B, no tile/icon/group
    --  settings) that conflict with the new defaults. One-time wipe replaces
    --  the friends subtable with { enabled = <previous> } so the module stays
    --  on/off as the user had it, and fresh defaults fill the rest.
    ---------------------------------------------------------------------------
    if EllesmereUIDB and EllesmereUIDB.profiles and not EllesmereUIDB._friendsWipeDone then
        for profName, profData in pairs(EllesmereUIDB.profiles) do
            if type(profData) == "table" and profData.addons then
                local basics = profData.addons.EllesmereUIBasics
                if basics and basics.friends then
                    local wasEnabled = basics.friends.enabled
                    basics.friends = { enabled = wasEnabled }
                end
            end
        end
        EllesmereUIDB._friendsWipeDone = true
    end

    ---------------------------------------------------------------------------
    --  Position snap helpers (reusable for migration + profile import)
    ---------------------------------------------------------------------------
    local function MakeSnappers()
        local physH = select(2, GetPhysicalScreenSize())
        local perfect = physH and physH > 0 and (768 / physH) or 1
        local uiScale = EllesmereUIDB.ppUIScale or perfect
        if uiScale <= 0 then uiScale = perfect end
        local onePixel = perfect / uiScale

        local function snap(v)
            if type(v) ~= "number" or v == 0 then return v end
            return floor(v / onePixel + 0.5) * onePixel
        end
        local function snapPos(tbl)
            if type(tbl) ~= "table" then return end
            if tbl.x then tbl.x = snap(tbl.x) end
            if tbl.y then tbl.y = snap(tbl.y) end
        end
        local function snapPosMap(map)
            if type(map) ~= "table" then return end
            for _, pos in pairs(map) do snapPos(pos) end
        end
        local function snapAnchors(anchors)
            if type(anchors) ~= "table" then return end
            for _, info in pairs(anchors) do
                if type(info) == "table" then
                    if info.offsetX then info.offsetX = snap(info.offsetX) end
                    if info.offsetY then info.offsetY = snap(info.offsetY) end
                end
            end
        end
        return snapPos, snapPosMap, snapAnchors
    end

    -- Snap all positions in a single profile data table.
    -- Called by migration (all profiles) and by profile import (one profile).
    local function SnapProfilePositions(profData)
        if type(profData) ~= "table" then return end
        local snapPos, snapPosMap, snapAnchors = MakeSnappers()

        local ul = profData.unlockLayout
        if ul then snapAnchors(ul.anchors) end

        local addons = profData.addons
        if type(addons) ~= "table" then return end

        local uf = addons.EllesmereUIUnitFrames
        if uf then snapPosMap(uf.positions) end

        local eab = addons.EllesmereUIActionBars
        if eab then snapPosMap(eab.barPositions) end

        local cdm = addons.EllesmereUICooldownManager
        if cdm then snapPosMap(cdm.cdmBarPositions) end

        local erb = addons.EllesmereUIResourceBars
        if type(erb) == "table" then
            for _, section in pairs(erb) do
                if type(section) == "table" and section.unlockPos then
                    snapPos(section.unlockPos)
                end
            end
        end

        local abr = addons.EllesmereUIAuraBuffReminders
        if type(abr) == "table" and abr.unlockPos then
            snapPos(abr.unlockPos)
        end

        local basics = addons.EllesmereUIBasics
        if type(basics) == "table" then
            if basics.questTracker then snapPos(basics.questTracker.pos) end
            if basics.minimap then snapPos(basics.minimap.position) end
            if basics.friends then snapPos(basics.friends.position) end
        end

        local cursor = addons.EllesmereUICursor
        if type(cursor) == "table" then
            if cursor.gcd then snapPos(cursor.gcd.pos) end
            if cursor.cast then snapPos(cursor.cast.pos) end
        end
    end

    -- Expose for profile import
    EllesmereUI.SnapProfilePositions = SnapProfilePositions

    ---------------------------------------------------------------------------
    --  One-time migration: re-snap all stored positions
    ---------------------------------------------------------------------------
    if not EllesmereUIDB._positionSnapV3Done then
        local _, _, snapAnchors = MakeSnappers()
        snapAnchors(EllesmereUIDB.unlockAnchors)

        if EllesmereUIDB.profiles then
            for _, profData in pairs(EllesmereUIDB.profiles) do
                SnapProfilePositions(profData)
            end
        end

        EllesmereUIDB._positionSnapV3Done = true
    end

    ---------------------------------------------------------------------------
    --  Migration: wipe friendAssignments and friendNotes.
    --  Friend group assignments are now stored in Blizzard's friend note
    --  field (server-side) instead of local DB keyed by bnetAccountID
    --  (which is not stable across sessions). Group definitions, colors,
    --  order, and collapsed states are preserved.
    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------
    --  Migration: clear quest tracker secColor when it matches the legacy
    --  hardcoded default. Previously the default was a fixed green table
    --  which DeepMergeDefaults baked into every user's DB, preventing the
    --  fallback to the live accent color from ever firing. Wiping the
    --  legacy default lets the quest tracker pick up the user's chosen
    --  accent color. Users who explicitly picked a different color keep it.
    ---------------------------------------------------------------------------
    if EllesmereUIDB.profiles and not EllesmereUIDB._questTrackerSecColorMigrated then
        for _, profData in pairs(EllesmereUIDB.profiles) do
            if type(profData) == "table" and profData.addons then
                local basics = profData.addons.EllesmereUIBasics
                if basics and basics.questTracker then
                    local sc = basics.questTracker.secColor
                    if type(sc) == "table"
                       and sc.r == 0.047 and sc.g == 0.824 and sc.b == 0.624 then
                        basics.questTracker.secColor = nil
                    end
                end
            end
        end
        EllesmereUIDB._questTrackerSecColorMigrated = true
    end

    if EllesmereUIDB.global and not EllesmereUIDB.global._friendNotesMigrated then
        -- Check if user had any group assignments before wiping
        local hadAssignments = false
        if EllesmereUIDB.global.friendAssignments then
            for _ in pairs(EllesmereUIDB.global.friendAssignments) do
                hadAssignments = true
                break
            end
        end
        if hadAssignments then
            EllesmereUIDB.global._friendGroupReassignPopup = true
        end
        EllesmereUIDB.global.friendAssignments = {}
        EllesmereUIDB.global.friendNotes = {}
        EllesmereUIDB.global._friendNotesMigrated = true
    end
end)
