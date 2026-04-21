-------------------------------------------------------------------------------
--  EllesmereUI_Profiles.lua
--
--  Global profile system: import/export, presets, spec assignment.
--  Handles serialization (LibDeflate + custom serializer) and profile
--  management across all EllesmereUI addons.
--
--  Load order (via TOC):
--    1. Libs/LibDeflate.lua
--    2. EllesmereUI_Lite.lua
--    3. EllesmereUI.lua
--    4. EllesmereUI_Widgets.lua
--    5. EllesmereUI_Presets.lua
--    6. EllesmereUI_Profiles.lua  -- THIS FILE
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI

-------------------------------------------------------------------------------
--  LibDeflate reference (loaded before us via TOC)
--  LibDeflate registers via LibStub, not as a global, so use LibStub to get it.
-------------------------------------------------------------------------------
local LibDeflate = LibStub and LibStub("LibDeflate", true) or _G.LibDeflate

-------------------------------------------------------------------------------
--  Reload popup: uses Blizzard StaticPopup so the button click is a hardware
--  event and ReloadUI() is not blocked as a protected function call.
-------------------------------------------------------------------------------
StaticPopupDialogs["EUI_PROFILE_RELOAD"] = {
    text = "EllesmereUI Profile switched. Reload UI to apply?",
    button1 = "Reload Now",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-------------------------------------------------------------------------------
--  Addon registry: display-order list of all managed addons.
--  Each entry: { folder, display, svName }
--    folder  = addon folder name (matches _dbRegistry key)
--    display = human-readable name for the Profiles UI
--    svName  = SavedVariables name (e.g. "EllesmereUINameplatesDB")
--
--  All addons use _dbRegistry for profile access. Order matters for UI display.
-------------------------------------------------------------------------------
local ADDON_DB_MAP = {
    { folder = "EllesmereUIActionBars",        display = "Action Bars",         svName = "EllesmereUIActionBarsDB"        },
    { folder = "EllesmereUINameplates",        display = "Nameplates",          svName = "EllesmereUINameplatesDB"        },
    { folder = "EllesmereUIUnitFrames",        display = "Unit Frames",         svName = "EllesmereUIUnitFramesDB"        },
    { folder = "EllesmereUICooldownManager",   display = "Cooldown Manager",    svName = "EllesmereUICooldownManagerDB"   },
    { folder = "EllesmereUIResourceBars",      display = "Resource Bars",       svName = "EllesmereUIResourceBarsDB"      },
    { folder = "EllesmereUIAuraBuffReminders", display = "AuraBuff Reminders",  svName = "EllesmereUIAuraBuffRemindersDB" },
    -- v6.6 split-out addons (were previously bundled under EllesmereUIBasics).
    -- The old Basics entry is intentionally removed -- it's a shim with no
    -- user-visible profile data and listing it produced a misleading
    -- "Not included: Basics" warning on every imported v6.6+ profile.
    { folder = "EllesmereUIQoL",               display = "Quality of Life",     svName = "EllesmereUIQoLDB"               },
    { folder = "EllesmereUIBlizzardSkin",      display = "Blizz UI Enhanced",   svName = "EllesmereUIBlizzardSkinDB"      },
    { folder = "EllesmereUIFriends",           display = "Friends List",        svName = "EllesmereUIFriendsDB"           },
    { folder = "EllesmereUIMythicTimer",       display = "Mythic+ Timer",       svName = "EllesmereUIMythicTimerDB"       },
    { folder = "EllesmereUIQuestTracker",      display = "Quest Tracker",       svName = "EllesmereUIQuestTrackerDB"      },
    { folder = "EllesmereUIMinimap",           display = "Minimap",             svName = "EllesmereUIMinimapDB"           },
}
EllesmereUI._ADDON_DB_MAP = ADDON_DB_MAP

-------------------------------------------------------------------------------
--  Serializer: Lua table <-> string (no AceSerializer dependency)
--  Handles: string, number, boolean, nil, table (nested), color tables
-------------------------------------------------------------------------------
local Serializer = {}

local function SerializeValue(v, parts)
    local t = type(v)
    if t == "string" then
        parts[#parts + 1] = "s"
        -- Length-prefixed to avoid delimiter issues
        parts[#parts + 1] = #v
        parts[#parts + 1] = ":"
        parts[#parts + 1] = v
    elseif t == "number" then
        parts[#parts + 1] = "n"
        parts[#parts + 1] = tostring(v)
        parts[#parts + 1] = ";"
    elseif t == "boolean" then
        parts[#parts + 1] = v and "T" or "F"
    elseif t == "nil" then
        parts[#parts + 1] = "N"
    elseif t == "table" then
        parts[#parts + 1] = "{"
        -- Serialize array part first (integer keys 1..n)
        local n = #v
        for i = 1, n do
            SerializeValue(v[i], parts)
        end
        -- Then hash part (non-integer keys, or integer keys > n)
        for k, val in pairs(v) do
            local kt = type(k)
            if kt == "number" and k >= 1 and k <= n and k == math.floor(k) then
                -- Already serialized in array part
            else
                parts[#parts + 1] = "K"
                SerializeValue(k, parts)
                SerializeValue(val, parts)
            end
        end
        parts[#parts + 1] = "}"
    end
end

function Serializer.Serialize(tbl)
    local parts = {}
    SerializeValue(tbl, parts)
    return table.concat(parts)
end

-- Deserializer
local function DeserializeValue(str, pos)
    local tag = str:sub(pos, pos)
    if tag == "s" then
        -- Find the colon after the length
        local colonPos = str:find(":", pos + 1, true)
        if not colonPos then return nil, pos end
        local len = tonumber(str:sub(pos + 1, colonPos - 1))
        if not len then return nil, pos end
        local val = str:sub(colonPos + 1, colonPos + len)
        return val, colonPos + len + 1
    elseif tag == "n" then
        local semi = str:find(";", pos + 1, true)
        if not semi then return nil, pos end
        return tonumber(str:sub(pos + 1, semi - 1)), semi + 1
    elseif tag == "T" then
        return true, pos + 1
    elseif tag == "F" then
        return false, pos + 1
    elseif tag == "N" then
        return nil, pos + 1
    elseif tag == "{" then
        local tbl = {}
        local idx = 1
        local p = pos + 1
        while p <= #str do
            local c = str:sub(p, p)
            if c == "}" then
                return tbl, p + 1
            elseif c == "K" then
                -- Key-value pair
                local key, val
                key, p = DeserializeValue(str, p + 1)
                val, p = DeserializeValue(str, p)
                if key ~= nil then
                    tbl[key] = val
                end
            else
                -- Array element
                local val
                val, p = DeserializeValue(str, p)
                tbl[idx] = val
                idx = idx + 1
            end
        end
        return tbl, p
    end
    return nil, pos + 1
end

function Serializer.Deserialize(str)
    if not str or #str == 0 then return nil end
    local val, _ = DeserializeValue(str, 1)
    return val
end

EllesmereUI._Serializer = Serializer

-------------------------------------------------------------------------------
--  Deep copy utility
-------------------------------------------------------------------------------
local function DeepCopy(src, seen)
    if type(src) ~= "table" then return src end
    if seen and seen[src] then return seen[src] end
    if not seen then seen = {} end
    local copy = {}
    seen[src] = copy
    for k, v in pairs(src) do
        -- Skip frame references and other userdata that can't be serialized
        if type(v) ~= "userdata" and type(v) ~= "function" then
            copy[k] = DeepCopy(v, seen)
        end
    end
    return copy
end

local function DeepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            DeepMerge(dst[k], v)
        else
            dst[k] = DeepCopy(v)
        end
    end
end

EllesmereUI._DeepCopy = DeepCopy




-------------------------------------------------------------------------------
--  Profile DB helpers
--  Profiles are stored in EllesmereUIDB.profiles = { [name] = profileData }
--  profileData = {
--      addons = { [folderName] = <snapshot of that addon's profile table> },
--      fonts  = <snapshot of EllesmereUIDB.fonts>,
--      customColors = <snapshot of EllesmereUIDB.customColors>,
--  }
--  EllesmereUIDB.activeProfile = "Default"  (name of active profile)
--  EllesmereUIDB.profileOrder  = { "Default", ... }
--  EllesmereUIDB.specProfiles  = { [specID] = "profileName" }
-------------------------------------------------------------------------------
local function GetProfilesDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.profiles then EllesmereUIDB.profiles = {} end
    if not EllesmereUIDB.profileOrder then EllesmereUIDB.profileOrder = {} end
    if not EllesmereUIDB.specProfiles then EllesmereUIDB.specProfiles = {} end
    return EllesmereUIDB
end
EllesmereUI.GetProfilesDB = GetProfilesDB

-------------------------------------------------------------------------------
--  Anchor offset format conversion
--
--  Anchor offsets were originally stored relative to the target's center
--  (format version 0/nil). The current system stores them relative to
--  stable edges (format version 1):
--    TOP/BOTTOM: offsetX relative to target LEFT edge
--    LEFT/RIGHT: offsetY relative to target TOP edge
--
--- Check if an addon is loaded
local function IsAddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
    return false
end

--- Re-point all db.profile references to the given profile name.
--- Called when switching profiles so addons see the new data immediately.
local function RepointAllDBs(profileName)
    if not EllesmereUIDB.profiles then EllesmereUIDB.profiles = {} end
    if type(EllesmereUIDB.profiles[profileName]) ~= "table" then
        EllesmereUIDB.profiles[profileName] = {}
    end
    local profileData = EllesmereUIDB.profiles[profileName]
    if not profileData.addons then profileData.addons = {} end

    -- Sync: copy synced module data from outgoing profile to incoming.
    -- activeProfile is already set to the new name by callers, so read
    -- the outgoing profile from the db registry (not yet re-pointed).
    local sm = EllesmereUIDB.syncedModules
    if sm then
        local reg = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
        local outName = reg and reg[1] and reg[1]._profileName or "Default"
        local outProf = EllesmereUIDB.profiles[outName]
        if outProf and outProf.addons and outName ~= profileName then
            for folder, synced in pairs(sm) do
                if synced and outProf.addons[folder] then
                    profileData.addons[folder] = DeepCopy(outProf.addons[folder])
                end
            end
        end
    end

    local registry = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
    if not registry then return end
    for _, db in ipairs(registry) do
        local folder = db.folder
        if folder then
            if type(profileData.addons[folder]) ~= "table" then
                profileData.addons[folder] = {}
            end
            db.profile = profileData.addons[folder]
            db._profileName = profileName
            -- Re-merge defaults so new profile has all keys
            if db._profileDefaults then
                EllesmereUI.Lite.DeepMergeDefaults(db.profile, db._profileDefaults)
            end
        end
    end
    -- Restore unlock layout from the profile.
    -- If the profile has no unlockLayout yet (e.g. created before this key
    -- existed), leave the live unlock data untouched so the current
    -- positions are preserved. Only restore when the profile explicitly
    -- contains layout data from a previous save.
    local ul = profileData.unlockLayout
    if ul then
        EllesmereUIDB.unlockAnchors     = DeepCopy(ul.anchors      or {})
        EllesmereUIDB.unlockWidthMatch  = DeepCopy(ul.widthMatch   or {})
        EllesmereUIDB.unlockHeightMatch = DeepCopy(ul.heightMatch  or {})
        EllesmereUIDB.phantomBounds     = DeepCopy(ul.phantomBounds or {})
    end
    -- Seed castbar anchor defaults ONLY on brand-new profiles (no unlockLayout
    -- yet). Re-seeding every load would clobber a user's deliberate un-anchor
    -- or manual position with the default "target BOTTOM" anchor the next
    -- time the profile is applied (e.g. via spec profile assignment).
    if not ul then
        local anchors = EllesmereUIDB.unlockAnchors
        local wMatch  = EllesmereUIDB.unlockWidthMatch
        if anchors and wMatch then
            local CB_DEFAULTS = {
                { cb = "playerCastbar", parent = "player" },
                { cb = "targetCastbar", parent = "target" },
                { cb = "focusCastbar",  parent = "focus" },
            }
            for _, def in ipairs(CB_DEFAULTS) do
                if not anchors[def.cb] then
                    anchors[def.cb] = { target = def.parent, side = "BOTTOM" }
                end
                if not wMatch[def.cb] then
                    wMatch[def.cb] = def.parent
                end
            end
        end
    end
    -- Restore fonts and custom colors from the profile
    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for k in pairs(fontsDB) do fontsDB[k] = nil end
        for k, v in pairs(profileData.fonts) do fontsDB[k] = DeepCopy(v) end
        if fontsDB.global      == nil then fontsDB.global      = "Expressway" end
        if fontsDB.outlineMode == nil then fontsDB.outlineMode = "shadow"     end
    end
    if profileData.customColors then
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k in pairs(colorsDB) do colorsDB[k] = nil end
        for k, v in pairs(profileData.customColors) do colorsDB[k] = DeepCopy(v) end
    end
end

-------------------------------------------------------------------------------
--  ResolveSpecProfile
--
--  Single authoritative function that resolves the current spec's target
--  profile name. Used by both PreSeedSpecProfile (before OnEnable) and the
--  runtime spec event handler.
--
--  Resolution order:
--    1. Cached spec from lastSpecByChar (reliable across sessions)
--    2. Live GetSpecialization() API (available after ADDON_LOADED for
--       returning characters, may be nil for brand-new characters)
--
--  Returns: targetProfileName, resolvedSpecID, charKey  -- or nil if no
--           spec assignment exists or spec cannot be resolved yet.
-------------------------------------------------------------------------------
local function ResolveSpecProfile()
    if not EllesmereUIDB then return nil end
    local specProfiles = EllesmereUIDB.specProfiles
    if not specProfiles or not next(specProfiles) then return nil end

    local charKey = UnitName("player") .. " - " .. GetRealmName()
    if not EllesmereUIDB.lastSpecByChar then
        EllesmereUIDB.lastSpecByChar = {}
    end

    -- Prefer cached spec from last session (always reliable)
    local resolvedSpecID = EllesmereUIDB.lastSpecByChar[charKey]

    -- Fall back to live API if no cached value
    if not resolvedSpecID then
        local specIdx = GetSpecialization and GetSpecialization()
        if specIdx and specIdx > 0 then
            local liveSpecID = GetSpecializationInfo(specIdx)
            if liveSpecID then
                resolvedSpecID = liveSpecID
                EllesmereUIDB.lastSpecByChar[charKey] = resolvedSpecID
            end
        end
    end

    if not resolvedSpecID then return nil end

    local targetProfile = specProfiles[resolvedSpecID]
    if not targetProfile then return nil end

    local profiles = EllesmereUIDB.profiles
    if not profiles or not profiles[targetProfile] then return nil end

    return targetProfile, resolvedSpecID, charKey
end

-------------------------------------------------------------------------------
--  Spec profile pre-seed
--
--  Runs once just before child addon OnEnable calls, after all OnInitialize
--  calls have completed (so all NewDB calls have run).
--  At this point the spec API is available, so we can resolve the current
--  spec and re-point all db.profile references to the correct profile table
--  in the central store before any addon builds its UI.
--
--  This is the sole pre-OnEnable resolution point. NewDB reads activeProfile
--  as-is (defaults to "Default" or whatever was saved from last session).
-------------------------------------------------------------------------------

--- Called by EllesmereUI_Lite just before child addon OnEnable calls fire.
--- Uses ResolveSpecProfile() to determine the correct profile, then
--- re-points all db.profile references via RepointAllDBs.
function EllesmereUI.PreSeedSpecProfile()
    local targetProfile, resolvedSpecID = ResolveSpecProfile()
    if not targetProfile then
        -- No spec assignment resolved; lock auto-save if spec profiles exist
        if EllesmereUIDB and EllesmereUIDB.specProfiles and next(EllesmereUIDB.specProfiles) then
            EllesmereUI._profileSaveLocked = true
        end
        return
    end

    EllesmereUIDB.activeProfile = targetProfile
    RepointAllDBs(targetProfile)
    EllesmereUI._preSeedComplete = true
end

--- Get the live profile table for an addon.
--- All addons use _dbRegistry (which points into
--- EllesmereUIDB.profiles[active].addons[folder]).
local function GetAddonProfile(entry)
    if EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry then
        for _, db in ipairs(EllesmereUI.Lite._dbRegistry) do
            if db.folder == entry.folder then
                return db.profile
            end
        end
    end
    return nil
end

--- Snapshot the current state of all loaded addons into a profile data table
function EllesmereUI.SnapshotAllAddons()
    local data = { addons = {} }
    for _, entry in ipairs(ADDON_DB_MAP) do
        if IsAddonLoaded(entry.folder) then
            local profile = GetAddonProfile(entry)
            if profile then
                data.addons[entry.folder] = DeepCopy(profile)
            end
        end
    end
    -- Include global font and color settings
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    local cc = EllesmereUI.GetCustomColorsDB()
    data.customColors = DeepCopy(cc)
    -- Include unlock mode layout data (anchors, size matches)
    if EllesmereUIDB then
        data.unlockLayout = {
            anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
            phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
        }
    end
    return data
end

--[[ ADDON-SPECIFIC EXPORT DISABLED
--- Snapshot a single addon's profile
function EllesmereUI.SnapshotAddon(folderName)
    for _, entry in ipairs(ADDON_DB_MAP) do
        if entry.folder == folderName and IsAddonLoaded(folderName) then
            local profile = GetAddonProfile(entry)
            if profile then return DeepCopy(profile) end
        end
    end
    return nil
end

--- Snapshot multiple addons (for multi-addon export)
function EllesmereUI.SnapshotAddons(folderList)
    local data = { addons = {} }
    for _, folderName in ipairs(folderList) do
        for _, entry in ipairs(ADDON_DB_MAP) do
            if entry.folder == folderName and IsAddonLoaded(folderName) then
                local profile = GetAddonProfile(entry)
                if profile then
                    data.addons[folderName] = DeepCopy(profile)
                end
                break
            end
        end
    end
    -- Always include fonts and colors
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    data.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
    -- Include unlock mode layout data
    if EllesmereUIDB then
        data.unlockLayout = {
            anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
            phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
        }
    end
    return data
end
--]] -- END ADDON-SPECIFIC EXPORT DISABLED

--- Apply imported profile data into the live db.profile tables.
--- Used by import to write external data into the active profile.
--- For normal profile switching, use SwitchProfile (which calls RepointAllDBs).
function EllesmereUI.ApplyProfileData(profileData)
    if not profileData or not profileData.addons then return end

    -- Build a folder -> db lookup from the Lite registry
    local dbByFolder = {}
    if EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry then
        for _, db in ipairs(EllesmereUI.Lite._dbRegistry) do
            if db.folder then dbByFolder[db.folder] = db end
        end
    end

    for _, entry in ipairs(ADDON_DB_MAP) do
        local snap = profileData.addons[entry.folder]
        if snap and IsAddonLoaded(entry.folder) then
            local db = dbByFolder[entry.folder]
            if db then
                local profile = db.profile
                -- TBB and barGlows are spec-specific (in spellAssignments),
                -- not in profile. No save/restore needed on profile switch.
                for k in pairs(profile) do profile[k] = nil end
                for k, v in pairs(snap) do profile[k] = DeepCopy(v) end
                if db._profileDefaults then
                    EllesmereUI.Lite.DeepMergeDefaults(profile, db._profileDefaults)
                end
                -- Ensure per-unit bg colors are never nil after import
                if entry.folder == "EllesmereUIUnitFrames" then
                    local UF_UNITS = { "player", "target", "focus", "boss", "pet", "totPet" }
                    local DEF_BG = 17/255
                    for _, uKey in ipairs(UF_UNITS) do
                        local s = profile[uKey]
                        if s and s.customBgColor == nil then
                            s.customBgColor = { r = DEF_BG, g = DEF_BG, b = DEF_BG }
                        end
                    end
                end
            end
        end
    end
    -- Apply fonts and colors
    do
        local fontsDB = EllesmereUI.GetFontsDB()
        for k in pairs(fontsDB) do fontsDB[k] = nil end
        if profileData.fonts then
            for k, v in pairs(profileData.fonts) do fontsDB[k] = DeepCopy(v) end
        end
        if fontsDB.global      == nil then fontsDB.global      = "Expressway" end
        if fontsDB.outlineMode == nil then fontsDB.outlineMode = "shadow"     end
    end
    do
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k in pairs(colorsDB) do colorsDB[k] = nil end
        if profileData.customColors then
            for k, v in pairs(profileData.customColors) do colorsDB[k] = DeepCopy(v) end
        end
    end
    -- Restore unlock mode layout data
    if EllesmereUIDB then
        local ul = profileData.unlockLayout
        if ul then
            EllesmereUIDB.unlockAnchors     = DeepCopy(ul.anchors      or {})
            EllesmereUIDB.unlockWidthMatch  = DeepCopy(ul.widthMatch   or {})
            EllesmereUIDB.unlockHeightMatch = DeepCopy(ul.heightMatch  or {})
            EllesmereUIDB.phantomBounds     = DeepCopy(ul.phantomBounds or {})
        end
        -- If profile predates unlockLayout, leave live data untouched
    end
end

--- Trigger live refresh on all loaded addons after a profile apply.
function EllesmereUI.RefreshAllAddons()
    -- ResourceBars (full rebuild)
    if _G._ERB_Apply then _G._ERB_Apply() end
    -- CDM: skip during spec-profile switch. CDM's SPELLS_CHANGED handler
    -- will detect the spec key mismatch and rebuild with the correct spec.
    -- Running it here would race with that rebuild.
    if not EllesmereUI._specProfileSwitching then
        if _G._ECME_LoadSpecProfile and _G._ECME_GetCurrentSpecKey then
            local curKey = _G._ECME_GetCurrentSpecKey()
            if curKey then _G._ECME_LoadSpecProfile(curKey) end
        end
        if _G._ECME_Apply then _G._ECME_Apply() end
    end
    -- Cursor (style + position)
    if _G._ECL_Apply then _G._ECL_Apply() end
    if _G._ECL_ApplyTrail then _G._ECL_ApplyTrail() end
    if _G._ECL_ApplyGCDCircle then _G._ECL_ApplyGCDCircle() end
    if _G._ECL_ApplyCastCircle then _G._ECL_ApplyCastCircle() end
    -- AuraBuffReminders (refresh + position)
    if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
    if _G._EABR_ApplyUnlockPos then _G._EABR_ApplyUnlockPos() end
    -- ActionBars (style + layout + position)
    if _G._EAB_Apply then _G._EAB_Apply() end
    -- UnitFrames (style + layout + position)
    if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
    -- Nameplates
    if _G._ENP_RefreshAllSettings then _G._ENP_RefreshAllSettings() end
    -- Global class/power colors (updates oUF, nameplates, raid frames)
    if EllesmereUI.ApplyColorsToOUF then EllesmereUI.ApplyColorsToOUF() end
    -- After all addons have rebuilt and positioned their frames from
    -- db.profile.positions, re-apply centralized grow-direction positioning
    -- (handles lazy migration of imported TOPLEFT positions to CENTER format)
    -- and resync anchor offsets so the anchor relationships stay correct for
    -- future drags. Triple-deferred so it runs AFTER debounced rebuilds have
    -- completed and frames are at final positions.
    C_Timer.After(0, function()
        C_Timer.After(0, function()
            C_Timer.After(0, function()
                -- Skip during spec-driven profile switch. _applySavedPositions
                -- iterates registered elements and calls each one's
                -- applyPosition callback, which for CDM bars is BuildAllCDMBars.
                -- That triggers a rebuild + ApplyAllWidthHeightMatches before
                -- CDMFinishSetup has had a chance to run, propagating
                -- transient mid-rebuild sizes through width-match and
                -- corrupting iconSize in saved variables. CDM's SPELLS_CHANGED
                -- handler handles the rebuild; other addons' positions don't
                -- change on spec swap so skipping is safe.
                if EllesmereUI._specProfileSwitching then return end
                -- Re-apply centralized positions (migrates legacy formats)
                if EllesmereUI._applySavedPositions then
                    EllesmereUI._applySavedPositions()
                end
                -- Resync anchor offsets (does NOT move frames)
                if EllesmereUI.ResyncAnchorOffsets then
                    EllesmereUI.ResyncAnchorOffsets()
                end
            end)
        end)
    end)
    -- Note: _specProfileSwitching is cleared by CDM's ProcessSpecChange
    -- after its rebuild settles -- not here. The rebuild runs from
    -- SPELLS_CHANGED which is well after this triple-deferred chain
    -- (~3 frames = ~50ms), so clearing the flag here would let width-match
    -- propagation run against transient mid-rebuild bar sizes once CDM
    -- starts rebuilding and corrupt iconSize in saved variables.
end

-------------------------------------------------------------------------------
--  Profile Keybinds
--  Each profile can have a key bound to switch to it instantly.
--  Stored in EllesmereUIDB.profileKeybinds = { ["Name"] = "CTRL-1", ... }
--  Uses hidden buttons + SetOverrideBindingClick, same pattern as Party Mode.
-------------------------------------------------------------------------------
local _profileBindBtns = {} -- [profileName] = hidden Button

local function GetProfileKeybinds()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.profileKeybinds then EllesmereUIDB.profileKeybinds = {} end
    return EllesmereUIDB.profileKeybinds
end

local function EnsureProfileBindBtn(profileName)
    if _profileBindBtns[profileName] then return _profileBindBtns[profileName] end
    local safeName = profileName:gsub("[^%w]", "")
    local btn = CreateFrame("Button", "EllesmereUIProfileBind_" .. safeName, UIParent)
    btn:Hide()
    btn:SetScript("OnClick", function()
        local active = EllesmereUI.GetActiveProfileName()
        if active == profileName then return end
        local _, profiles = EllesmereUI.GetProfileList()
        local fontWillChange = EllesmereUI.ProfileChangesFont(profiles and profiles[profileName])
        EllesmereUI.SwitchProfile(profileName)
        EllesmereUI.RefreshAllAddons()
        if fontWillChange then
            EllesmereUI:ShowConfirmPopup({
                title       = "Reload Required",
                message     = "Font changed. A UI reload is needed to apply the new font.",
                confirmText = "Reload Now",
                cancelText  = "Later",
                onConfirm   = function() ReloadUI() end,
            })
        else
            EllesmereUI:RefreshPage()
        end
    end)
    _profileBindBtns[profileName] = btn
    return btn
end

function EllesmereUI.SetProfileKeybind(profileName, key)
    local kb = GetProfileKeybinds()
    -- Clear old binding for this profile
    local oldKey = kb[profileName]
    local btn = EnsureProfileBindBtn(profileName)
    if oldKey then
        ClearOverrideBindings(btn)
    end
    if key then
        kb[profileName] = key
        SetOverrideBindingClick(btn, true, key, btn:GetName())
    else
        kb[profileName] = nil
    end
end

function EllesmereUI.GetProfileKeybind(profileName)
    local kb = GetProfileKeybinds()
    return kb[profileName]
end

--- Called on login to restore all saved profile keybinds
function EllesmereUI.RestoreProfileKeybinds()
    local kb = GetProfileKeybinds()
    for profileName, key in pairs(kb) do
        if key then
            local btn = EnsureProfileBindBtn(profileName)
            SetOverrideBindingClick(btn, true, key, btn:GetName())
        end
    end
end

--- Update keybind references when a profile is renamed
function EllesmereUI.OnProfileRenamed(oldName, newName)
    local kb = GetProfileKeybinds()
    local key = kb[oldName]
    if key then
        local oldBtn = _profileBindBtns[oldName]
        if oldBtn then ClearOverrideBindings(oldBtn) end
        _profileBindBtns[oldName] = nil
        kb[oldName] = nil
        kb[newName] = key
        local newBtn = EnsureProfileBindBtn(newName)
        SetOverrideBindingClick(newBtn, true, key, newBtn:GetName())
    end
end

--- Clean up keybind when a profile is deleted
function EllesmereUI.OnProfileDeleted(profileName)
    local kb = GetProfileKeybinds()
    if kb[profileName] then
        local btn = _profileBindBtns[profileName]
        if btn then ClearOverrideBindings(btn) end
        _profileBindBtns[profileName] = nil
        kb[profileName] = nil
    end
end

--- Returns true if applying profileData would change the global font or outline mode.
--- Used to decide whether to show a reload popup after a profile switch.
function EllesmereUI.ProfileChangesFont(profileData)
    if not profileData or not profileData.fonts then return false end
    local cur = EllesmereUI.GetFontsDB()
    local curFont    = cur.global      or "Expressway"
    local curOutline = cur.outlineMode or "shadow"
    local newFont    = profileData.fonts.global      or "Expressway"
    local newOutline = profileData.fonts.outlineMode or "shadow"
    -- "none" and "shadow" are both drop-shadow (no outline) -- treat as identical
    if curOutline == "none" then curOutline = "shadow" end
    if newOutline == "none" then newOutline = "shadow" end
    return curFont ~= newFont or curOutline ~= newOutline
end

--[[ ADDON-SPECIFIC EXPORT DISABLED
--- Apply a partial profile (specific addons only) by merging into active
function EllesmereUI.ApplyPartialProfile(profileData)
    if not profileData or not profileData.addons then return end
    for folderName, snap in pairs(profileData.addons) do
        for _, entry in ipairs(ADDON_DB_MAP) do
            if entry.folder == folderName and IsAddonLoaded(folderName) then
                local profile = GetAddonProfile(entry)
                if profile then
                    for k, v in pairs(snap) do
                        profile[k] = DeepCopy(v)
                    end
                end
                break
            end
        end
    end
    -- Always apply fonts and colors if present
    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for k, v in pairs(profileData.fonts) do
            fontsDB[k] = DeepCopy(v)
        end
    end
    if profileData.customColors then
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k, v in pairs(profileData.customColors) do
            colorsDB[k] = DeepCopy(v)
        end
    end
end
--]] -- END ADDON-SPECIFIC EXPORT DISABLED

-------------------------------------------------------------------------------
--  Export / Import
--  Format: !EUI_<base64 encoded compressed serialized data>
--  The data table contains:
--    { version = 3, type = "full"|"partial", data = profileData }
-------------------------------------------------------------------------------
local EXPORT_PREFIX = "!EUI_"

function EllesmereUI.ExportProfile(profileName)
    local db = GetProfilesDB()
    local profileData = db.profiles[profileName]
    if not profileData then return nil end
    -- If exporting the active profile, ensure fonts/colors/layout are current
    if profileName == (db.activeProfile or "Default") then
        profileData.fonts = DeepCopy(EllesmereUI.GetFontsDB())
        profileData.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
        profileData.unlockLayout = {
            anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
            phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
        }
    end
    local exportData = DeepCopy(profileData)
    -- Exclude spec-specific data from export (bar glows, tracking bars)
    exportData.trackedBuffBars = nil
    exportData.tbbPositions = nil
    -- Include spell assignments from the dedicated store on the export copy
    -- (barGlows and trackedBuffBars excluded from export -- spec-specific)
    local sa = EllesmereUIDB and EllesmereUIDB.spellAssignments
    if sa then
        local spCopy = DeepCopy(sa.specProfiles or {})
        -- Strip spec-specific non-exportable data from each spec profile
        for _, prof in pairs(spCopy) do
            prof.barGlows = nil
            prof.trackedBuffBars = nil
            prof.tbbPositions = nil
        end
        exportData.spellAssignments = {
            specProfiles = spCopy,
        }
    end
    local payload = { version = 3, type = "full", data = exportData }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

--[[ ADDON-SPECIFIC EXPORT DISABLED
function EllesmereUI.ExportAddons(folderList)
    local profileData = EllesmereUI.SnapshotAddons(folderList)
    local sw, sh = GetPhysicalScreenSize()
    local euiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
    local meta = {
        euiScale = euiScale,
        screenW  = sw and math.floor(sw) or 0,
        screenH  = sh and math.floor(sh) or 0,
    }
    local payload = { version = 3, type = "partial", data = profileData, meta = meta }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end
--]] -- END ADDON-SPECIFIC EXPORT DISABLED

-------------------------------------------------------------------------------
--  CDM spec profile helpers for export/import spec picker
-------------------------------------------------------------------------------

--- Get info about which specs have data in the CDM specProfiles table.
--- Returns: { { key="250", name="Blood", icon=..., hasData=true }, ... }
--- Includes ALL specs for the player's class, with hasData indicating
--- whether specProfiles contains data for that spec.
function EllesmereUI.GetCDMSpecInfo()
    local sa = EllesmereUIDB and EllesmereUIDB.spellAssignments
    local specProfiles = sa and sa.specProfiles or {}
    local result = {}
    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specID, sName, _, sIcon = GetSpecializationInfo(i)
        if specID then
            local key = tostring(specID)
            result[#result + 1] = {
                key     = key,
                name    = sName or ("Spec " .. key),
                icon    = sIcon,
                hasData = specProfiles[key] ~= nil,
            }
        end
    end
    return result
end

--- Filter specProfiles in an export snapshot to only include selected specs.
--- Reads from snapshot.spellAssignments (the dedicated store copy on the payload).
--- Modifies the snapshot in-place. selectedSpecs = { ["250"] = true, ... }
function EllesmereUI.FilterExportSpecProfiles(snapshot, selectedSpecs)
    if not snapshot or not snapshot.spellAssignments then return end
    local sp = snapshot.spellAssignments.specProfiles
    if not sp then return end
    for key in pairs(sp) do
        if not selectedSpecs[key] then
            sp[key] = nil
        end
    end
end

--- After a profile import, apply only selected specs' specProfiles from the
--- imported data into the dedicated spell assignment store.
--- importedSpellAssignments = the spellAssignments object from the import payload.
--- selectedSpecs = { ["250"] = true, ... }
function EllesmereUI.ApplyImportedSpecProfiles(importedSpellAssignments, selectedSpecs)
    if not importedSpellAssignments or not importedSpellAssignments.specProfiles then return end
    if not EllesmereUIDB.spellAssignments then
        EllesmereUIDB.spellAssignments = { specProfiles = {} }
    end
    local sa = EllesmereUIDB.spellAssignments
    if not sa.specProfiles then sa.specProfiles = {} end
    for key, data in pairs(importedSpellAssignments.specProfiles) do
        if selectedSpecs[key] then
            sa.specProfiles[key] = DeepCopy(data)
        end
    end
    -- If the current spec was imported, reload it live
    if _G._ECME_GetCurrentSpecKey and _G._ECME_LoadSpecProfile then
        local currentKey = _G._ECME_GetCurrentSpecKey()
        if currentKey and selectedSpecs[currentKey] then
            _G._ECME_LoadSpecProfile(currentKey)
        end
    end
end

--- Get the list of spec keys that have data in imported spell assignments.
--- Returns same format as GetCDMSpecInfo but based on imported data.
--- Accepts either the new spellAssignments format or legacy CDM snapshot.
function EllesmereUI.GetImportedCDMSpecInfo(importedSpellAssignments)
    if not importedSpellAssignments then return {} end
    -- Support both new format (spellAssignments.specProfiles) and legacy (cdmSnap.specProfiles)
    local specProfiles = importedSpellAssignments.specProfiles
    if not specProfiles then return {} end
    local result = {}
    for specKey in pairs(specProfiles) do
        local specID = tonumber(specKey)
        local name, icon
        if specID and specID > 0 and GetSpecializationInfoByID then
            local _, sName, _, sIcon = GetSpecializationInfoByID(specID)
            name = sName
            icon = sIcon
        end
        result[#result + 1] = {
            key     = specKey,
            name    = name or ("Spec " .. specKey),
            icon    = icon,
            hasData = true,
        }
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

-------------------------------------------------------------------------------
--  CDM Spec Picker Popup
--  Thin wrapper around ShowSpecAssignPopup for CDM export/import.
--
--  opts = {
--      title    = string,
--      subtitle = string,
--      confirmText = string (button label),
--      specs    = { { key, name, icon, hasData, checked }, ... },
--      onConfirm = function(selectedSpecs)  -- { ["250"]=true, ... }
--      onCancel  = function() (optional)
--  }
--  specs[i].hasData = false grays out the row and shows disabled tooltip.
--  specs[i].checked = initial checked state (only for hasData=true rows).
-------------------------------------------------------------------------------
do
    -- Dummy db/dbKey/presetKey for the assignments table
    local dummyDB = { _cdmPick = { _cdm = {} } }

    function EllesmereUI:ShowCDMSpecPickerPopup(opts)
        local specs = opts.specs or {}

        -- Reset assignments
        dummyDB._cdmPick._cdm = {}

        -- Build a set of specIDs that are in the caller's list
        local knownSpecs = {}
        for _, sp in ipairs(specs) do
            local numID = tonumber(sp.key)
            if numID then knownSpecs[numID] = sp end
        end

        -- Build disabledSpecs map (specID -> tooltip string)
        -- Any spec NOT in the caller's list gets disabled too
        local disabledSpecs = {}
        -- Build preCheckedSpecs set
        local preCheckedSpecs = {}

        for _, sp in ipairs(specs) do
            local numID = tonumber(sp.key)
            if numID then
                if not sp.hasData then
                    disabledSpecs[numID] = "Create a CDM spell layout for this spec first"
                end
                if sp.checked then
                    preCheckedSpecs[numID] = true
                end
            end
        end

        -- Disable all specs not in the caller's list (other classes, etc.)
        local SPEC_DATA = EllesmereUI._SPEC_DATA
        if SPEC_DATA then
            for _, cls in ipairs(SPEC_DATA) do
                for _, spec in ipairs(cls.specs) do
                    if not knownSpecs[spec.id] then
                        disabledSpecs[spec.id] = "Not available for this operation"
                    end
                end
            end
        end

        EllesmereUI:ShowSpecAssignPopup({
            db              = dummyDB,
            dbKey           = "_cdmPick",
            presetKey       = "_cdm",
            title           = opts.title,
            subtitle        = opts.subtitle,
            buttonText      = opts.confirmText or "Confirm",
            disabledSpecs   = disabledSpecs,
            preCheckedSpecs = preCheckedSpecs,
            onConfirm       = opts.onConfirm and function(assignments)
                -- Convert numeric specID assignments back to string keys
                local selected = {}
                for specID in pairs(assignments) do
                    selected[tostring(specID)] = true
                end
                opts.onConfirm(selected)
            end,
            onCancel        = opts.onCancel,
        })
    end
end

function EllesmereUI.ExportCurrentProfile(selectedSpecs)
    local profileData = EllesmereUI.SnapshotAllAddons()
    -- Include spell assignments from the dedicated store
    local sa = EllesmereUIDB and EllesmereUIDB.spellAssignments
    if sa then
        profileData.spellAssignments = {
            specProfiles = DeepCopy(sa.specProfiles or {}),
            -- barGlows excluded from export (spec-specific, stored in specProfiles)
        }
        -- Filter by selected specs if provided
        if selectedSpecs and profileData.spellAssignments.specProfiles then
            for key in pairs(profileData.spellAssignments.specProfiles) do
                if not selectedSpecs[key] then
                    profileData.spellAssignments.specProfiles[key] = nil
                end
            end
        end
    end
    local sw, sh = GetPhysicalScreenSize()
    -- Use EllesmereUI's own stored scale (UIParent scale), not Blizzard's CVar
    local euiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
    local meta = {
        euiScale = euiScale,
        screenW  = sw and math.floor(sw) or 0,
        screenH  = sh and math.floor(sh) or 0,
    }
    local payload = { version = 3, type = "full", data = profileData, meta = meta }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

function EllesmereUI.DecodeImportString(importStr)
    if not importStr or #importStr < 5 then return nil, "Invalid string" end
    -- Detect old CDM bar layout strings (format removed in 5.1.2)
    if importStr:sub(1, 9) == "!EUICDM_" then
        return nil, "This is an old CDM Bar Layout string. This format is no longer supported. Use the standard profile import instead."
    end
    if importStr:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return nil, "Not a valid EllesmereUI string. Make sure you copied the entire string."
    end
    if not LibDeflate then return nil, "LibDeflate not available" end
    local encoded = importStr:sub(#EXPORT_PREFIX + 1)
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return nil, "Failed to decode string" end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return nil, "Failed to decompress data" end
    local payload = Serializer.Deserialize(decompressed)
    if not payload or type(payload) ~= "table" then
        return nil, "Failed to deserialize data"
    end
    if not payload.version or payload.version < 3 then
        return nil, "This profile was created before the beta wipe and is no longer compatible. Please create a new export."
    end
    if payload.version > 3 then
        return nil, "This profile was created with a newer version of EllesmereUI. Please update your addon."
    end
    return payload, nil
end

--- Reset class-dependent fill colors in Resource Bars after a profile import.
--- The exporter's class color may be baked into fillR/fillG/fillB; this
--- resets them to the importer's own class/power colors and clears
--- customColored so the bars use runtime class color lookup.
local function FixupImportedClassColors()
    local rbEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUIResourceBars" then rbEntry = e; break end
    end
    if not rbEntry or not IsAddonLoaded(rbEntry.folder) then return end
    local profile = GetAddonProfile(rbEntry)
    if not profile then return end

    local _, classFile = UnitClass("player")
    -- CLASS_COLORS and POWER_COLORS are local to ResourceBars, so we
    -- use the same lookup the addon uses at init time.
    local classColors = EllesmereUI.CLASS_COLOR_MAP
    local cc = classColors and classColors[classFile]

    -- Health bar: reset to importer's class color
    if profile.health and not profile.health.darkTheme then
        profile.health.customColored = false
        if cc then
            profile.health.fillR = cc.r
            profile.health.fillG = cc.g
            profile.health.fillB = cc.b
        end
    end
end

--- Import a profile string. Returns: success, errorMsg
--- The caller must provide a name for the new profile.
function EllesmereUI.ImportProfile(importStr, profileName)
    local payload, err = EllesmereUI.DecodeImportString(importStr)
    if not payload then return false, err end

    local db = GetProfilesDB()

    if payload.type == "cdm_spells" then
        return false, "This is a CDM Bar Layout string, not a profile string."
    end

    -- Check if current spec has an assigned profile (blocks auto-apply)
    local specLocked = false
    do
        local si = GetSpecialization and GetSpecialization() or 0
        local sid = si and si > 0 and GetSpecializationInfo(si) or nil
        if sid then
            local assigned = db.specProfiles and db.specProfiles[sid]
            if assigned then specLocked = true end
        end
    end

    if payload.type == "full" then
        -- Full profile: store as a new named profile
        local stored = DeepCopy(payload.data)
        -- Strip spell assignment data from stored profile (lives in dedicated store)
        if stored.addons and stored.addons["EllesmereUICooldownManager"] then
            stored.addons["EllesmereUICooldownManager"].specProfiles = nil
            stored.addons["EllesmereUICooldownManager"].barGlows = nil
        end
        stored.spellAssignments = nil
        -- Snap all positions to the physical pixel grid (imported profiles
        -- may come from a different version without pixel snapping)
        if EllesmereUI.SnapProfilePositions then
            EllesmereUI.SnapProfilePositions(stored)
        end
        db.profiles[profileName] = stored
        -- Add to order if not present
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        -- CDM spell assignments are NOT written here. The caller shows
        -- a spec picker popup that lets the user choose which specs to
        -- import, then calls ApplyImportedSpecProfiles() with only the
        -- selected specs. Writing here would bypass that selection.
        if specLocked then
            return true, nil, "spec_locked"
        end
        -- Make it the active profile and re-point db references
        db.activeProfile = profileName
        RepointAllDBs(profileName)
        -- Apply imported data into the live db.profile tables
        EllesmereUI.ApplyProfileData(payload.data)
        FixupImportedClassColors()
        -- Don't ReloadUI() here: the caller (options panel import flow)
        -- may need to show the CDM spec picker popup before reloading.
        -- The caller handles the reload/refresh after the popup completes.
        return true, nil
    --[[ ADDON-SPECIFIC EXPORT DISABLED
    elseif payload.type == "partial" then
        -- Partial: deep-copy current profile, overwrite the imported addons
        local current = db.activeProfile or "Default"
        local currentData = db.profiles[current]
        local merged = currentData and DeepCopy(currentData) or {}
        if not merged.addons then merged.addons = {} end
        if payload.data and payload.data.addons then
            for folder, snap in pairs(payload.data.addons) do
                local copy = DeepCopy(snap)
                -- Strip spell assignment data from CDM profile (lives in dedicated store)
                if folder == "EllesmereUICooldownManager" and type(copy) == "table" then
                    copy.specProfiles = nil
                    copy.barGlows = nil
                end
                merged.addons[folder] = copy
            end
        end
        if payload.data.fonts then
            merged.fonts = DeepCopy(payload.data.fonts)
        end
        if payload.data.customColors then
            merged.customColors = DeepCopy(payload.data.customColors)
        end
        -- Store as new profile
        merged.spellAssignments = nil
        db.profiles[profileName] = merged
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        -- Write spell assignments to dedicated store
        if payload.data and payload.data.spellAssignments then
            if not EllesmereUIDB.spellAssignments then
                EllesmereUIDB.spellAssignments = { specProfiles = {} }
            end
            local sa = EllesmereUIDB.spellAssignments
            local imported = payload.data.spellAssignments
            if imported.specProfiles then
                for key, data in pairs(imported.specProfiles) do
                    sa.specProfiles[key] = DeepCopy(data)
                end
            end
            if imported.barGlows and next(imported.barGlows) then
                -- barGlows is now per-spec in specProfiles, not global. Skip import.
            end
        end
        -- Backward compat: extract specProfiles from CDM addon data (pre-migration format)
        if payload.data and payload.data.addons and payload.data.addons["EllesmereUICooldownManager"] then
            local cdm = payload.data.addons["EllesmereUICooldownManager"]
            if cdm.specProfiles then
                if not EllesmereUIDB.spellAssignments then
                    EllesmereUIDB.spellAssignments = { specProfiles = {} }
                end
                for key, data in pairs(cdm.specProfiles) do
                    if not EllesmereUIDB.spellAssignments.specProfiles[key] then
                        EllesmereUIDB.spellAssignments.specProfiles[key] = DeepCopy(data)
                    end
                end
            end
            if cdm.barGlows then
                if not EllesmereUIDB.spellAssignments then
                    EllesmereUIDB.spellAssignments = { specProfiles = {} }
                end
                if not next(EllesmereUIDB.spellAssignments.barGlows or {}) then
                    -- barGlows is now per-spec in specProfiles, not global. Skip import.
                end
            end
        end
        if specLocked then
            return true, nil, "spec_locked"
        end
        db.activeProfile = profileName
        RepointAllDBs(profileName)
        EllesmereUI.ApplyProfileData(merged)
        FixupImportedClassColors()
        -- Reload UI so every addon rebuilds from scratch with correct data
        ReloadUI()
        return true, nil
    --]] -- END ADDON-SPECIFIC EXPORT DISABLED
    end

    return false, "Unknown profile type"
end

-------------------------------------------------------------------------------
--  Profile management
-------------------------------------------------------------------------------
function EllesmereUI.SaveCurrentAsProfile(name)
    local db = GetProfilesDB()
    local current = db.activeProfile or "Default"
    local src = db.profiles[current]
    -- Deep-copy the current profile into the new name
    local copy = src and DeepCopy(src) or {}
    -- Ensure fonts/colors/unlock layout are current
    copy.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    copy.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
    copy.unlockLayout = {
        anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
        widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
        heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
        phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
    }
    db.profiles[name] = copy
    local found = false
    for _, n in ipairs(db.profileOrder) do
        if n == name then found = true; break end
    end
    if not found then
        table.insert(db.profileOrder, 1, name)
    end
    -- Switch to the new profile using the standard path so the outgoing
    -- profile's state is properly saved before repointing.
    EllesmereUI.SwitchProfile(name)
end

function EllesmereUI.DeleteProfile(name)
    local db = GetProfilesDB()
    db.profiles[name] = nil
    for i, n in ipairs(db.profileOrder) do
        if n == name then table.remove(db.profileOrder, i); break end
    end
    -- Clean up spec assignments
    for specID, pName in pairs(db.specProfiles) do
        if pName == name then db.specProfiles[specID] = nil end
    end
    -- Clean up keybind
    EllesmereUI.OnProfileDeleted(name)
    -- If deleted profile was active, fall back to Default
    if db.activeProfile == name then
        db.activeProfile = "Default"
        RepointAllDBs("Default")
    end
end

function EllesmereUI.RenameProfile(oldName, newName)
    local db = GetProfilesDB()
    if not db.profiles[oldName] then return end
    db.profiles[newName] = db.profiles[oldName]
    db.profiles[oldName] = nil
    for i, n in ipairs(db.profileOrder) do
        if n == oldName then db.profileOrder[i] = newName; break end
    end
    for specID, pName in pairs(db.specProfiles) do
        if pName == oldName then db.specProfiles[specID] = newName end
    end
    if db.activeProfile == oldName then
        db.activeProfile = newName
        RepointAllDBs(newName)
    end
    -- Update keybind reference
    EllesmereUI.OnProfileRenamed(oldName, newName)
end

function EllesmereUI.SwitchProfile(name)
    local db = GetProfilesDB()
    if not db.profiles[name] then return end
    -- Save current fonts/colors into the outgoing profile before switching
    local outgoing = db.profiles[db.activeProfile or "Default"]
    if outgoing then
        outgoing.fonts = DeepCopy(EllesmereUI.GetFontsDB())
        outgoing.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
        -- Save unlock layout into outgoing profile
        outgoing.unlockLayout = {
            anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
            phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
        }
    end
    db.activeProfile = name
    RepointAllDBs(name)
end

function EllesmereUI.GetActiveProfileName()
    local db = GetProfilesDB()
    return db.activeProfile or "Default"
end

function EllesmereUI.GetProfileList()
    local db = GetProfilesDB()
    return db.profileOrder, db.profiles
end

function EllesmereUI.AssignProfileToSpec(profileName, specID)
    local db = GetProfilesDB()
    db.specProfiles[specID] = profileName
end

function EllesmereUI.UnassignSpec(specID)
    local db = GetProfilesDB()
    db.specProfiles[specID] = nil
end

function EllesmereUI.GetSpecProfile(specID)
    local db = GetProfilesDB()
    return db.specProfiles[specID]
end

-------------------------------------------------------------------------------
--  AutoSaveActiveProfile: no-op in single-storage mode.
--  Addons write directly to EllesmereUIDB.profiles[active].addons[folder],
--  so there is nothing to snapshot. Kept as a stub so existing call sites
--  (keybind buttons, options panel hooks) do not error.
-------------------------------------------------------------------------------
function EllesmereUI.AutoSaveActiveProfile()
    -- Intentionally empty: single-storage means data is always in sync.
end

-------------------------------------------------------------------------------
--  Spec auto-switch handler
--
--  Single authoritative runtime handler for spec-based profile switching.
--  Uses ResolveSpecProfile() for all resolution. Defers the entire switch
--  during combat via pendingSpecSwitch / PLAYER_REGEN_ENABLED.
-------------------------------------------------------------------------------
do
    local specFrame = CreateFrame("Frame")
    local lastKnownSpecID = nil
    local lastKnownCharKey = nil
    local pendingSpecSwitch = false   -- true when a switch was deferred by combat
    local specRetryTimer = nil        -- retry handle for new characters

    specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    specFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    specFrame:SetScript("OnEvent", function(_, event, unit)
        ---------------------------------------------------------------
        --  PLAYER_REGEN_ENABLED: handle deferred spec switch
        ---------------------------------------------------------------
        if event == "PLAYER_REGEN_ENABLED" then
            if pendingSpecSwitch then
                pendingSpecSwitch = false
                -- Re-resolve after combat ends (spec may have changed again)
                local targetProfile = ResolveSpecProfile()
                if targetProfile then
                    local current = EllesmereUIDB and EllesmereUIDB.activeProfile or "Default"
                    if current ~= targetProfile then
                        local fontWillChange = EllesmereUI.ProfileChangesFont(
                            EllesmereUIDB.profiles[targetProfile])
                        EllesmereUI._specProfileSwitching = true
                        EllesmereUI.SwitchProfile(targetProfile)
                        EllesmereUI.RefreshAllAddons()
                        if fontWillChange then
                            EllesmereUI:ShowConfirmPopup({
                                title       = "Reload Required",
                                message     = "Font changed. A UI reload is needed to apply the new font.",
                                confirmText = "Reload Now",
                                cancelText  = "Later",
                                onConfirm   = function() ReloadUI() end,
                            })
                        end
                    end
                end
            end
            return
        end

        ---------------------------------------------------------------
        --  Filter: only handle "player" for PLAYER_SPECIALIZATION_CHANGED
        ---------------------------------------------------------------
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then
            return
        end

        ---------------------------------------------------------------
        --  Resolve the current spec via live API
        ---------------------------------------------------------------
        local specIdx = GetSpecialization and GetSpecialization() or 0
        local specID = specIdx and specIdx > 0
            and GetSpecializationInfo(specIdx) or nil

        if not specID then
            -- Spec info not available yet (common on brand new characters).
            -- Start a short polling retry so we can assign the correct
            -- profile once the server sends spec data.
            if not specRetryTimer and (lastKnownSpecID == nil) then
                local attempts = 0
                specRetryTimer = C_Timer.NewTicker(1, function(ticker)
                    attempts = attempts + 1
                    local idx = GetSpecialization and GetSpecialization() or 0
                    local sid = idx and idx > 0
                        and GetSpecializationInfo(idx) or nil
                    if sid then
                        ticker:Cancel()
                        specRetryTimer = nil
                        -- Record the spec so future events use the fast path
                        lastKnownSpecID = sid
                        local ck = UnitName("player") .. " - " .. GetRealmName()
                        lastKnownCharKey = ck
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        if not EllesmereUIDB.lastSpecByChar then
                            EllesmereUIDB.lastSpecByChar = {}
                        end
                        EllesmereUIDB.lastSpecByChar[ck] = sid
                        EllesmereUI._profileSaveLocked = false
                        -- Resolve via the unified function
                        local target = ResolveSpecProfile()
                        if target then
                            local cur = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
                            if cur ~= target then
                                local fontChange = EllesmereUI.ProfileChangesFont(
                                    EllesmereUIDB.profiles[target])
                                EllesmereUI._specProfileSwitching = true
                                EllesmereUI.SwitchProfile(target)
                                EllesmereUI.RefreshAllAddons()
                                if fontChange then
                                    EllesmereUI:ShowConfirmPopup({
                                        title       = "Reload Required",
                                        message     = "Font changed. A UI reload is needed to apply the new font.",
                                        confirmText = "Reload Now",
                                        cancelText  = "Later",
                                        onConfirm   = function() ReloadUI() end,
                                    })
                                end
                            end
                        end
                    elseif attempts >= 10 then
                        ticker:Cancel()
                        specRetryTimer = nil
                    end
                end)
            end
            return
        end

        -- Spec resolved -- cancel any pending retry
        if specRetryTimer then
            specRetryTimer:Cancel()
            specRetryTimer = nil
        end

        local charKey = UnitName("player") .. " - " .. GetRealmName()
        local isFirstLogin = (lastKnownSpecID == nil)
        -- charChanged is true when the active character is different from the
        -- last session (alt-swap). On a plain /reload the charKey stays the same.
        local charChanged = (lastKnownCharKey ~= nil) and (lastKnownCharKey ~= charKey)

        -- On PLAYER_ENTERING_WORLD (reload/zone-in), skip if same character
        -- and same spec -- a plain /reload should not override the user's
        -- active profile selection.
        if event == "PLAYER_ENTERING_WORLD" then
            if not isFirstLogin and not charChanged and specID == lastKnownSpecID then
                return -- same char, same spec, nothing to do
            end
        end
        lastKnownSpecID = specID
        lastKnownCharKey = charKey

        -- Persist the current spec so PreSeedSpecProfile can guarantee the
        -- correct profile is loaded on next login via ResolveSpecProfile().
        if not EllesmereUIDB then EllesmereUIDB = {} end
        if not EllesmereUIDB.lastSpecByChar then EllesmereUIDB.lastSpecByChar = {} end
        EllesmereUIDB.lastSpecByChar[charKey] = specID

        -- Spec resolved successfully -- unlock auto-save if it was locked
        -- during PreSeedSpecProfile when spec was unavailable.
        EllesmereUI._profileSaveLocked = false

        ---------------------------------------------------------------
        --  Defer entire switch during combat
        ---------------------------------------------------------------
        if InCombatLockdown() then
            pendingSpecSwitch = true
            return
        end

        ---------------------------------------------------------------
        --  Resolve target profile via the unified function
        ---------------------------------------------------------------
        local db = GetProfilesDB()
        local targetProfile = ResolveSpecProfile()
        if targetProfile then
            local current = db.activeProfile or "Default"
            if current ~= targetProfile then
                local function doSwitch()
                    EllesmereUI._specProfileSwitching = true
                    local fontWillChange = EllesmereUI.ProfileChangesFont(db.profiles[targetProfile])
                    EllesmereUI.SwitchProfile(targetProfile)
                    EllesmereUI.RefreshAllAddons()
                    if not isFirstLogin and fontWillChange then
                        EllesmereUI:ShowConfirmPopup({
                            title       = "Reload Required",
                            message     = "Font changed. A UI reload is needed to apply the new font.",
                            confirmText = "Reload Now",
                            cancelText  = "Later",
                            onConfirm   = function() ReloadUI() end,
                        })
                    end
                end
                if isFirstLogin then
                    -- Defer two frames: one frame lets child addon OnEnable
                    -- callbacks run, a second frame lets any deferred
                    -- registrations inside OnEnable (e.g. SetupOptionsPanel)
                    -- complete before SwitchProfile tries to rebuild frames.
                    C_Timer.After(0, function()
                        C_Timer.After(0, doSwitch)
                    end)
                else
                    doSwitch()
                end
            elseif isFirstLogin or charChanged then
                -- activeProfile already matches the target. If the pre-seed
                -- already injected the correct data into each child SV, the
                -- addons built with the right values and no further action is
                -- needed. Only call SwitchProfile if the pre-seed did not run
                -- (e.g. first session after update, no lastSpecByChar entry).
                if not EllesmereUI._preSeedComplete then
                    C_Timer.After(0, function()
                        C_Timer.After(0, function()
                            EllesmereUI.SwitchProfile(targetProfile)
                        end)
                    end)
                end
            end
        elseif isFirstLogin or charChanged then
            -- No spec assignment for this character. If the current
            -- activeProfile is spec-assigned (left over from a previous
            -- character), switch to the last non-spec profile so this
            -- character doesn't inherit another spec's layout.
            local current = db.activeProfile or "Default"
            local currentIsSpecAssigned = false
            if db.specProfiles then
                for _, pName in pairs(db.specProfiles) do
                    if pName == current then currentIsSpecAssigned = true; break end
                end
            end
            if currentIsSpecAssigned then
                -- Find the best fallback: lastNonSpecProfile, or any profile
                -- that isn't spec-assigned, or Default as last resort.
                local fallback = db.lastNonSpecProfile
                if not fallback or not db.profiles[fallback] then
                    -- Walk profileOrder to find first non-spec-assigned profile
                    local specAssignedSet = {}
                    if db.specProfiles then
                        for _, pName in pairs(db.specProfiles) do
                            specAssignedSet[pName] = true
                        end
                    end
                    for _, pName in ipairs(db.profileOrder or {}) do
                        if not specAssignedSet[pName] and db.profiles[pName] then
                            fallback = pName
                            break
                        end
                    end
                end
                fallback = fallback or "Default"
                if fallback ~= current and db.profiles[fallback] then
                    C_Timer.After(0, function()
                        C_Timer.After(0, function()
                            EllesmereUI.SwitchProfile(fallback)
                        end)
                    end)
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Popular Presets & Weekly Spotlight
--  Hardcoded profile strings that ship with the addon.
--  To add a new preset: add an entry to POPULAR_PRESETS with name + string.
--  To update the weekly spotlight: change WEEKLY_SPOTLIGHT.
-------------------------------------------------------------------------------
EllesmereUI.POPULAR_PRESETS = {
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_S3xwZTTr2c)xjp(99GuH9T8KKL3QyzRRLsMKPMQubrcjHRjb4aaAzLPM)73ZsVc2GlYljZepvnvKjbr39Pp7R)RFQpQyz1qj8hzfvRRVCw5IQgVJtI(XFQpTOFwxvvZRA8JI8m(G)wtqCI3p(VXF9WJRQG)ZTRxSa)fFSQRVUTPjeE8OI5L0R2pOyDZI2zF4nLp2UEa(K0IYMz3321ZF7TTZw3)SY(HBk7GpjPyOS7UQH(y(BWNV92B7Rg(nCVb)V4KO8i)iVKaAD6RNxb)QtF3vx9UZ1p9V2qBYGOIND25xdVOH2Lx77DDqCEMxu015(MlMFi)yTTlM3(qZOv1ZZZpl03lokjlnwVQHfx9UlmxYJsJpolmm0piplliZh3b((8bHpw74e6JNW484O4S8Si8IqCa3yPIYpoolmilik1l1lexPWIv2lqsXQfLpw1zcdpYJ2HrHXEXzX5HzBhiEucDIIsIJtt8tdeNOFP6(6zlQE(NQTorPfNxw3CAP1k6DCW2Gz(Pj0HMVvjqwEXZF)PxFr7dvwye(P0N)SfL99VVQVDD3SQnrpYs989t9TUOCHEaaIi458JcItZ8HTiExncnWcfzxR(2WlYp2pooifa7PXvh5XlMpHZTEOEr9WJFfWgbKraZnkonnjmHV6KyeMRMZlTJIbOtsIVxQFAkSV1hUOI388xCLfwF2XPXEbrmrjD2KuXFgRtCX7F9lFL1cLESxwyuEIxoagjqyGGBXMexYDGjccrDP5FSLlmgR3p3l3pnpjxGBWRIdEvUwma)caGXHrrbHiVGDXTcH3XEH5sqOnNRmGXvIFEy815EwCUCrJVb220SrsjyQbdleQ6v8q98H7pVCy29it6ruf9UjenOAN4jgXTxZIhwblyRc)HOsiIEqabWxX5lMPLUVQ(U7h49mtkV6(YgGR)PTRBM3)V(3eAz585TnOKNa49Uyrv)YQUQF(1NmBaKCHlaEEtlwTU)(Q5pJKA8S2fTiFiFqULpGZ4xCdkjYdPj8lUd(7SWC6V7G)opL4f7NlEh)CFfXWIElVaw34cPuMNp)UQXFTpCFsR9PTDZR6US(3RAOfkOaKpErBFnUrXDzubSDdP91JnhbsPr0TeGCnoihLaNv0vT4I26Mb4y)SN)2RE(7)jaIVA0N4x8Pg)qIfS6htc3H3EI4TNgDCkkdmiaf1GWGd5L7f5FCoqjq8)IiGdWk9tdDLcO(6HH2g5bjmfP8cI9ZJbSsuWXbSwbXS0kdwe0bj4lcy6ihWjaXZwwiFBKKDmiKnmm1lpodfXEahcGH7XXa4g4fKKgryt0HitbIYHtPsNKdeeDKF(XrWDzusugkns96JLVEGpZHTHjfTaaX)Z6Q1vxouoSMOIqabi754OC4)L5LhKCOB1e)4JtHFCCAqAmqJblJsyLCfc8iPCE(XbXzPiD4baQzDHW7PqVK80eHmLN3md4zmu1bqDX6e5hCCeqH4fhgeeKEGlJciNQUdJ9poW4ODqB7JIIdo2dOsaIrP82tlVtVBpc0M6Pd3tIbS3KK8OWqsbraSNvCE9SUwZvaUzXl28e)S4dKFZrzEbegmOmEyEoXtiVaWCAMvzSe(PHGIfhgO(OWCIryEOpGra6TqC9VOcfEOqzYcjyFwAAEq(bExEuuQpXPvOWQ6QnsHZh4HyKpnULaTesmLyjKGKceCmj8jV4Eqo3cuw3yreGeVU2zVCr7dSPC4ZdI5UhmqcfFw3C3jn1lljbiGEvWRADF1PlQ)9FVSB(zG5AO8pueLV6fTH4j)I()56YUQxpJFjbE69ZvvFAyDx1vGvHnO2oGml5gI(mA)NADYEAYwHnr1IQzdGusyhBG5yi7E8MjROg2Y)922LnXhJivOcccWLExGs2db(asj7GQZcj7KHjMN2pdLdIqz52YWJk(yD)RGBQx1UUhUPGRb)4IBiLaUcS16dnv99Oj33x3aFL6XFB7ZBQw(i(4(cDO(BOUBG1VSsdKW1xr6g1q8TslAwV89Tp0Z3hrW9bWR7fTndMGbwrN7ek80b)xwDB6HFNWE8Je3YZwaBWRUVRD9D3J7KOIpu94n1nZ5henfNWPB)yvxhCgF76Le(dJLKwuU4HYh7V8(2hoL2UisiC6Nx3xEZIQRaJYhQxrFyG4zbi18QgejoRODnSHEFzZDv0bqa8cj8(ZlbUwiQa(Ojim(DnlE81nG14aVgXRKv9uaJeBvXby)alAQv85jQvsDF4kHVbDIMlrYKQokuBuQDiUR)vgaYWVCfLd(v)MXxLxCZDpVbHvZrGuwX9mseIpz85XMxaAmanfj(E3nsqS82vFyjSfMtZpX384(iuJArWeupinM75Kiw6bbWeDVF59LKdLAABad7ZqevgpHHMXsAK32EfDLXyelX7ylmTq(ZgDzy9K)gbttbaN5DJhZzavW35TJN4(KVIzK6ECtZSI3)R5WI76AF4S6oGlgYooOy9QX0x)kVczMRG42eXMXRTL3uoS5LSn9ajwc5RjjPL)fATcjChUOy0uJ3EsXsahQcPynWGadJkVdLJ0b7((3Jmvy6Df8E3OpJyoWxeWDRbCKaViVk8nl3gNSaTNtGPX4lmNoIRgDr0(WfgBpgfKFYla7(G9TKHdd5qgoghUejXQP5AaUjWsPQb0QfVNatJVh(3)oqMxUWE)D5QQQ5iygrHslQy6r8Mc2eLD)sDF9nKNEaJWAQa4QLvwU5n9fxcqeV5(CKaSj3sqQWEjaWs6HqOGd207bJFMlNBg)UVghj5IW5gFVKieUqytFzea4qMNVdM5w85pu(XUX8pqHaU1)WaiWS82pg9m7A1R0GtVt65ny0pbRT)RIv)0sZNKJpi)(lbRD3sBbu()mWXFKQmY9kZPN4E5wnahkrky9U38)T50NHHZAOgmKAlS5pCf80cgC6ZeB9Br2CtDT4ue2eeoULIofhcJN2sM224xoseGLlR(pfrBtYREFLVnHCE6suyhGLQf7HGUTzHJBmdxc6Krj5p9M48DrF)vq0Nl9aNYkNVUY82Iq4V1M68NgbF7RjoG4GXEyXs4wCXVEHWPRFvKQfZbPSjYJuO2TmUTOIVnxDGrBIieIn(Jn90wm4gwe(Q39(x)3F3BV6K3mLZxyFNnoScFMGLPKFVBLaSppUeVTHv3JCJ(3iz6HStAE6MR(Dz6KZFC7n3VnUT87Y0)UmDBFl(Dz6OClI323iJz)sjtxNmfFJea8zhXQPc60(AtNlZP(ggWQdYlKtB)5w0ZDsHaUmA0(9y51shoq8)qcl10ER87XLYDCPioxFpUuC4X(p34sDGrNw6upkrXCXx8lE0QcXKV4Zr9)OIR7l)iLMigxtUmk4GYKHXmAZ1Uo)ZXzFBlQwsDihfZshHp7RPZ(2ICKdt0WeHR9adA1HAAXtoZfoGaAH8g)lzaT(ZJx920X4C(s8Tn3f2Qd9ioBhKY)Uv42z(n80szHpZyzzLyUUIM84TQi7ZeP92bLhBr4V9ZrUWOWksBfx8n3xReCWg(afUsyd7mH32EEpCqgl4k68BnHiCL7CtA8WHYzElspCNEdBrxJduiIBhh7quHiJ(2rsUXIkMkxICLNBotHTDNRBIeNYDUUnTG6)SLYBt4CSVUXdAdb0UeE9hSadhAPsvz0ez6GdfYns55eoXgNqlYNOadNbG2kgqjfVVA13dceNzUs7NOAa5BK)Z(SZ3phyHKQl7VKrN5(4NJzsFpNieP07ur1XvIWEWcfDvocFpDa5cY8RFMFVvpS994N8Toza)sf)KPk81)dltaSRgWpZn)Utxbdx391nNfhvdI7Nj3Fg2XgG2k85yhRB)BABDlTipz512U28Rr26poRJ5k16GSLDct3nlvnrzDjlUQVM1P10MMUNbe7qnE(jN7(CgsRQ)pJcxZL3b(E0Werd7jK6(FDlwR)my96MjG3uf9jwS4t4))jSTDcZw)swWw(UloYrwZQlY()7rOhLthuXR)9y6zuKEFpMEJR44DLUhFpME)3E9i)hOvPFpMEpLYq(ZkMEy)Uiq3Dp2OvGeR6FgYIOM)fgTvRZFC4(6zxvVKAKFsgelw3F1dT0NkcO1n)VyDW)XQXnGaVJ5gRf2KTmAXwurRNu0VAr9WLlW2eODh8GRtq6xj(trdSauaVStufuIUra6SS3jxFQTOiEXVOSFyJxS49YEEdlGEz)SQI6chTDZQ6Vy2WfT99XfV5KtFowsaHf03cIzT3M0oG2LX8ggFHHYgBhUXOE7b87yxEATvrWhUDTQ0CFUi47Q(yD1diSnTyabZxWGCxfNp2dauRTaWoVQC4ECbEDZv1dlQmEtp)tRQ7QMBFqilmPdc)xuFqt0zbO3vVXlc1CQ(UMtwSaVTbWKOn)bkq2QUhmmfHp3e2YPDvLFa7pNmJw1J)YYvCtsZR42UYLvI(cqcXVkvFNdB(YM5vZBcuCYaOfcBUVRQsHqIGugUd48NmBwvd2(qIl6vDvh4YGGRVgBzCVP62bzlgjSa7SiZlx02ubibu3of)9vD)gSOPhhOBmqKP)839RnzCJd1SVHMxuE7T1FYas4rqcEdHTPhS17Gn4dfM3BkVPAbSvZHDhCTX)urMgO3xS7uqiqqOgg(S2LRwunm(QLuwNBYDJqtIyOKaNhq4Zl(53E2ZF)1NEY7P(UkUz)5vZAxw3C3LiPk30oOMUsubJJnQHJaO)6fu8NeYe3t9aORKOqaWbyGclapbLDvN3oh7HiV9DV95egH(IcBxryFMO9b1H986flQ7RM12mNO9dlgaub4rwmxd4rW5SpO9cvGV5rh3jaqyz5a1OeF3p)2RU(IN)ESJ7rRpUENreb86pE)Ew1IHsSR0aWLKIU2hqSzrmw0y(mpGi(I1eTeyXtyfiUc3qBWTRKMhXRhXBCcwyiGcE17S)DKHKtccmFUf7A1jfFlq)TAr5qf1KfJacY6QM5lEetCTZQUTC9Ib8rODkaTbGhWbFGALiin99vLlgU)TRxEd22AXEAu7k8b4wGfbwsfTmySz)O7yjGGN519RQwG9)kaaHDCkzpxui45fITYBV4zuBUcS3H7QK)Ctnsg2TE1q9nlQuDmfxYrirkiYyCXcGWh3BJumEE1nRV9wSX1ySPdLRLq6dxJzWXtaaUQDfqaruui4HOUlx3vEg8)XopcILPBbdWwVE5Q2oGxd1osPE(f1)riYhGRFlqmZ7UxcOuaYxeTDXwj4TTnaB34IxJN5BlNv9poz(8310)pmeC)pwwnVU8Fqp6)ayBc0e9pu(4XxDfc4cv3Q4EfXDLDJOJyoRYwrLOpKXvOhwFD4LlkpJ7uyQw9dGy3vwp)8YUpi65Lbe)C)IgybmB1riNxtCMDIVcVJzZ2VgBuaZBaGN4LhsTc)wSITPor84(9f1QW0Ch5UbQUrz1E7Txv28HtU7UUwfcf3fyz(PPuBwKfw6NXnIhG(Mr3ToYyIiaITwwZ92n6Ew2tqTW0OpmQqHm)(QY5yJfM7)p6Lg0XqjMM7OZagJjuLX0ireEf)Z1v9dN3EdbQ19lNGKnXbvDQmgpmXe9EN3uUqQFtDtvpVtK09V7JvDlkFuifduaJ0f4(6HBA)eHV9RWZl6Vli9njw36aPVtF(Yvdp6Uh05sNgcwLvac0QVbe4PGS5z6EbBqeJuGxRX(81kOccCprBevhCvrJcFFgrQF5q5SpSFyQIEJoIQk5NWhzyLAhgAxUbBPqdcmu7uGmQDvhY1L4dtmEEDdix8MsSJEl6yuHexkcD1x836UgfLVAcgUxo84crt)l1(Wy03yuy3wmmbKeXorZNNaNMV)DI8qPVxZhEvzVnfh1K4fkWOvoLBa3a5TeR)zSoAg9unaX3IKWIIm2KblZLxGhk)nOsHA2BSKgKzPgreiu13vBiPGeFO13eKPlOp5D6UHhy6wc4C7vhDZZ4MKB9EalZPWwbaJuM(fOCEladlMdpO7EhcA)QyUAHrex8bSFcc)FRgsg34POwpMgYaVewgUMyuDHlzjd8AfKHk5R2ItDyMmYW0lrJ(l)Be9h)BMSwFao1QpYPBt0EzAeq5FtVd4ZzRyLaZnmpmYtBGOHY3(SjNakiGV)MwSp)zJY7RTzovJYZdJaq7naRaj0ukeGTEnWmItaoqYBb8xzl7t13siTKL52kr1JQTiBK2W3byQg0HgTxTalPySfCsuudJCavGrUsoyGPb2OgY0jluHPSB0naPwHUzqzbQnUQ)TvLD7pqeOaiblC3GxbA4wQQjdatsdblBfA6umM4gTPM9SHkCXmOH)Al2bgCv0FfOsPfTjSRNP1kLioS1SyuBqnqJhjr)4nNwSoYLZyTtamj0ksJgtlQX(ywPJy)ljaK6sYWruvmPc7aFMhR6egOzPoIwvDQrbly0B4of)yMwLaOovyphhVikv1m44eP1xLT3ryuM8TyW3Nn29KfloJ09xyCJcr24jtjnAjdKyfzw9ln(hdYJO9iHHYwTiSvbbgaMRgDt1m6NOQ(b62X2nSBAdddRVqyHU28Mr6IQPIKFHOVeBI5BDfBHsoQv3PfbAj813IzHwTsrhX04UC0UBdZIqaOL6H)Mq9qN2qrQXqlcWFvBAMboUwtze5F3Gw(64YvLZu9FYC2awHISsBHqxfm0vVQA(rFmG4TDFz)9OcW7EreMelEJ7(5tkyJujH87(XtbLh7QE(I6bQVpZOZIUUInJiTkpXQT)fvDOhRuf8U8yz1zAvMgAzFmOoHINnQ1kgXxu9wlBqFL0QsRFAU5r0Pw3OrQnF4TTJy8RL5ZzoJYMoK)PwVbrRl20Ym2yfKxzorXoY6xfH)inMKgDsxgSxEu2TS77gXdtYImqt9rXAJ1gwXHuA)NuydUEcKh9TsAX9T9d1g(dXtlrG7eKShRjx96ICAKNN8c8tIIdJcYJYmSColinoWpmmlnq8XKl)YZX5ptwwSFo7XfyfKIkux5mJz)yH)CjSL6BRNr(mHuZX0oldDlSUd4smHLNZT2wHF0mmmXIVfOWmr)qRqikAH4y0JwWbK5AHi4GHzfqsRKtPLsPTb3TXiJujM1(LCaaP1fOeMsTR11ORdNnJ2oATeaLrmoaJW64dG8dffTcYQcrXDsVmYnekwLGiTQ1dDLl02nUfnqH9jfyfT(60yHqehenwvqiJCMYqvbduMKIVUH3eDDptj8M9SmrpPyBGPDpiz1W3wSOv238mcfzjV7S9ZvJw3yjKTbFqAbqO8sUxgtn351R61ObOz5ydw(es2so1k65RrmUMWx0yhih0fUlQKU4GDxd7563xDhGzlxw57vSWEydYw2LHn6MTbfLuqdi6runkW4W7EpAfI4nR17G8nllZCTk4hL3qbA6M70(a3kAiB0wSL7lynGToUANsRgTCSlXzDeP4QGNv47XVJDMnyg(cGxkR7JQabv98B(xWVB4TH8vPtgUgXe2uqii1DOfdvYQb(((1nFeeFre2g)eaWDmBHgRc0p3qxDCFB2vE15iX4WJh(EiGP8KlopglfcVZsi(EHiS1AQabR1TLIzqutdOR7lWXabCmmWBLJ8mXukY0Y38caFFaTywFGyVz(gXNZM1Fxx5CSzwBOLBqXDZMtJiPYUhFpHFAJTsPoQuTuQFTpQ5wJ(aIILN2vp5Qvc3pjP(EHEjjHEr8utsobaf9aARTWjiVFesQFhmvdSpm2PQZjyxv9If4vFyqCuUNFEIxAg5eonuX4LYdJqo2C8S6jvmfys9J9PX9WHmazqEu8wGUF9JtYscsJI9Yr9aSPp1nyo87eOnmomgGj0739YBaEej(BnhfJamb9Qgp9sjmNjmjAjgLtd2yysuEAywOVFuknvOydRuQAySYNk4nHFpWTT7dC8W4hxS7OUKhfDjr1hADNWBaBAFXJRgbeeZ57lbC8f4BLy1ySjEjFv7GHcQNPzidqqcETsQRX8gF5ZotIiZK5kmtE51GgXDvwyyAkOMryczANX(q(M1Oq8fJi2AAmDzximWxo)TanCOxh6LaKRu18NVCfgaHlhkVtYasTZy4OGdj8xmUKaJhekkiypRUd3FMDAqoU4OKa4WQ3N8La)AqIKO8mVW8abIjpoCyLTrcGTYIZUMShnZjWehwpE0e8fmLYjhBNsypWF5dxDF1smBceweQAP4kok89gExlcPQCyqGFQmYS8vH5NWWlnRGuInRXpbPf4KTN3ISatnbj3OrKZz0JOrGkfPtTepLmtCsPP(FIwfPqiLUtNpsoGZY51clFtshLyZnwqfUVqEQcYGx4I09x9zxmtA6fqlkbHAT8nqGry2wBULkjDBccCQ9KjYSMjzorSX(EFKw1ovFrJld6pa4VGEOD1lbPvFtrGfQMimMLsYIPWO5RsJbaXNngTWThvu(R86BFBRuxab9I8ADhO58qPliioGgxN248KGMVT48MkBmsvXTJZNlMPWSy8nhQHoKGJMbyWqqrPmLoZprcHPLhGUnDtYpmUvYp1Ks1r3wWj1KBsj0JRQ3Az3qD5crgMSjX0DvG(MSXBBVZ2cSR0rUpROCORDw9WJJvNtQChO7cghwaUd6CqzyJGK1nCyIjA1iPoj4E4usWVP22m)FBjoJ0BDRuS8V2MID)L2ivEWKkmd0bmaud13ZpKy4jsJnEuuTHDBO(F)s5I1v99EfBqgAJUZATgMJtHUuVGGuVyC)FaATMCmOqEmOsqGAyeZs3SRLTPKMziOKgF0aD1Q6vsxCY7Lz3J(RyoQOfXOrCXXYDz5iIfd(PVZEc7y1pL3CKlnIkorRZphJAwUj(2flQWwSDyGVEWRLJhh5ittUFruoHAhoLsPoYmUO6FY7e1)e57KYJCW22zg5u2KuSysHiXSEgwsBCUv4sJcX5LzLARh(eIIjfi2uuCgcbKj5fRyRCChAQBzopScJmTs9)P9naRKeq5WUEAS5Arx5EMWSrpaYY7co1DAKj0KpnUV6tWc79SZcYpBcDB5i39S6UzKBnL)MWxCs6l48VdmqEDp7RA1UGYTcKJ3q5S7jFdyPWkyPnAVKP7EWPqhysm8cBWudeNHibf1IXoNGv8y3aq(cPKsoZmIVziAWRXU8f0)ZyxgWA9kYl1TVltlK7P4cA6rUpBjyXS3sXfdDL1l4btI7PP34t5ecy54OGw0b4F4w7AgsrYlUba1lQaLCgJ)4Qs3ckMlssoJWi7QwMWeUav(xMj70PJg7yMHTq(YKd5qYltXQ1WCqZHfciqqQTg0OJRihvsh4aaKFd0Bms4Fl(nGFKE(pAbubcWZV4n)8LxFYBp763FYRbK)WIvwzF8V2CuumnwsdI8cXXUkXHqMAYhf4JtdFGi33pij1hOR3iXo)5M6HxGzxn55eoSdGW43Hr2A4rzpryJu8ZurbGXQXaSE8q)(q0KZNdHMASVtYedI9PbVknjGZyFq)PMOCAo1gMLJt8yuw0ERV4gtxEw0BCGy(mh5LrwkIltywiPDDKpipczRUVRcIvkYLShBcYiX6jPH(HES3zH3DIhp56Z889JiTj23xUzwhGqOSdCC6s8HmgM)mCgqwWrUSxucaw54LbaaPhqctYYOeIBF3KG(d6W8jDlxafGXdqPgXwDfLRaQ3IZT6rH(8qJ2l1JZYM9DRc0vvC(XHWbQadoGT4rWDklYeZGM(EPkta7EmXCL4by4wLjdRHNAdfzxHihdW8tLt3kSMwQNx93UVQ51nOxK)ivXgba1whYUgyqnVYiUqG6AO)OmMtSw1nHpx3eile4Peg8k833MD1UPgvMIyTXjGwZqfMZXaWR7EmuzjwVBQoquo6rFM4HwRVitGXWvzY8v8oaZmeL(b(aQKDgD)VTFMeJqunO9eSmu0PbfOvBZIh5unrdInGIuHfeuemhoaSZ3LjN9UJslh1l5ZBKi3Bcj4KnMYbesWdDlCQbJwzYTYrWBKyk6PnkjbcMVINTO8pyeisCuihkRtqrrkqGP6I5niCjrjNUJ81wuovQHt9UHjGyFfAUa9skrA0AsJdwfcPuesCXnvlAFGS)qeowkXeWlA2n3NkZfhVILLFsCPkYMyFgWkuZx4sQnaOBKs4c3aHzElAnmHlRK5jLfMlIpPjbeDNtYK435fcAtUoimFs2HPbi5RM(tJvWEmh3PNqXiWmc3cSjvCv4DM4mgs0jHcyLjPKiRavqpm0Q8b8f1lwyhf)KqJ0cZi9ct4s0bm0bZ8bj20UXceBzS8q0(wdt(fARFwDpYq3G1Xg2dMH3T0nnNu8MOvcarM4TPd5ghGponnGJP5xWxiSVTnZQZ9jJqL0yIBgkogy(QG0rCbmPyjtr)vBtbPYglAjsxZL7g8Tvkgz50iTLvo2Zj8kjzKIXRwEHjNUrsrKLrIO8xCYCWbRFd34RvNvnmFhn8KNwKIBknZOji8(9MuypTluBbJEQPGUaTXiz8WS9xxfajMPGiNXUMAr5kSloK)W1AZeI456tzEfBtQKDcpcTb73fSxizv3mCdLSAwtFqZlwG1ehGmjdF105f(P0pdJZK4dNKQjNZpvcNy0sjFVgwOXIqDj3zZIbIeU4lmxHgm6CW)D4oHamXVSHjCQgOmuHLF60RcXgIKy1d0ztJTOaMlHPiyElbAXnCdlntdnvkpTHaVruOrKCij7kRmXrVrgZBKQJG7zPcWTLOAtzvtTzn6KWu8JDO0jBL)IQsa696M5ywvHHKwyw6yDibR2LRU1TpiCHr)ya0geRCkF86Mlk7gEKJ5SDlJ0krwyiUl(RBCHO2Pg1eSFMm(Yo0ecBWrJuOAtVpYB39q(VTSypnTHAFPOwurhFsPUw(4uN7C6kCizJW8gGj5PlcbIgumZ05atBl7vKO8uSAhNKse6Ty7c6FnCdv4Msf8LC5r78zlpu8r20wcm(4eU6M8l2WeaQGecgJkApm8pi9XXjEpkygxBq3A2Cj36hZjc9ec6mpw2MXSbHJqTUWXNcN5ANuJWn11LlLiDn4YvjTdTzHJOKE0OgScWp907S8AdG3pCJAByKJTpfvqDG2zxIee)acTX2sNdwZrdgo2VjcjLZoB2WttTpWt)U7EbCX5O3QJ5OH5(PHXgYtKsXB5hya5d1CaSk3ftjS8xWXlHqTKw3MPrcnLSsGacwYmvWIG2jnVOQDyWIXMAsZln5fQyp5YHVUIBhSTmPUK5LnjClYGQ3aoykCxLBrt4)IdsbzhMdStZfdiZCn0qMlDAoeExck9zweuwitKVWUJfrIjhTOuTM0Q8G0jUW29BDkJAS9OWuMDYcA30StnRBLykdtN5K(3THcCAD(6M3dg1lSrvY)XP2KcmwwPfPkMVPLtDBTBzigwQVxtkpLhvWwVVspKX0)kvHTyyO0qrSL2HpzOh3W5z7WPfpndpqLhT07IPvsylj0o50HLeFbmzykJ(CyZaqqZ7gHkrJ19DBwsyvsEKbXko14KLaRf5n170gl7pHwrak2SDu6)GSBaiTnVOmhg8)zWKcuFqvw7)ukmFmneg5x790MKPfkT3MMaQ9mcHDZ(fbxCd3jMgVYwfHn2WbB0IOObjgAkjwYsszVSOzkhysjWQfniBnGGQvPJIGcFFSWbdyQ9B8lGph)QyOdw3jw1rIWkHrC7mm6)lJvrUlfDNQv8fO8Zd8lWSHxxTmx1sH4f9T02m3cuItxl14vi6GguUJ9TRcFmx4awWSfYHuhwWt(pxJ1Cyw2g8jSeqsgeVdZ1mb(awPoYC)xLrCtO33bP8102VXgcXGol16hhkeTfwUDF1UArqskxrvgz0GGCyIOJWuDywnA6cqH)g2HYS22zAjdESz7k3G8zybQ2Jp6i(P5KywK0KtjgzTkYsIDfJHLJtAc7KUJEeb0oCR9w8t12SZDs7toiRxDzI2ezE1xqdDhfFETnKtzZzglgreuuLmerpRKJPUrF1sgvBNXP2TnAJIAQWpXgwgkWNC5oIjcasMT(Wgw0Tfti3uPiUOkXeEeJyifzHX5yG239IHzhbqo5M(2UBWy88KDcWgwRZATOb4yiCjNUmLhXMYwEYlH7RFYC4SOrrc1m7oEsrwDB2dJoKGGOCfIIXq1DW02io3oTDfJ(RiRAoOmqzVvKFBz)Y0iLB1RvSdx2Wtn7xso4YEuvqOghZCNyWhEgm4kWxJdxLZmqAlwX6wXO9lbdubr7q07hTBuj9cuftijzcIqHGkNm9MWPDGPnJJWGHNR4spfZdYPRF9jYQjhSj3RGjVrKD2)Gl7mHYMw4QJyrpIQuuk1hseQDKYrthfl)jvG4qnGzSRrDhAMjYZ9ncu1KAw8TidV2VGWVJe8JXP3DST4i1BewBHoT7YbBoy7nzWI2VW6J9QSXXnZiu)Ov7oT(YY2INukDDaoeyepvkFVEQHJBRor(WZYRjZf1TMOxBpBg20DFtRMZ259QtBLXzQQvq8hB75KHYACQQovGeXuDytvy30kWDzukWPAVY9cglMIxOHpgMkGrhMPN7mVogfrZjtBYVeH60TwTBlYqUm3KyZS)AbFyPQ728VH23e7B2mT9iUEajLlNzPJYr4VGgO8uSs1rSHDLW67LZU3i9DMYK2dWm0nJIQkzsejQKH5ptMBtBnmI7JZ1DLuHp5e59RJt1D6aNjY8STyg92vlwKeEk)Q(KcaRDY7XPVz7WfFpdDL9TlNHKykM6FJZqx7wZa1ER5rWTS814ATH6MncphOmLIBXnKJe4S8WOqZ40eJ)s1Jq5T9vy6c5qQdwfDwnFmSn7IjR(7Rww3mVQJmDdyW120VEjUjTk5r4ldkK9JRY13TSQz46U1uRXkTya7xKFG)BUQlXTmqJHNS4IhWM6e7yG6Mp8413Sa7V44d8a(aCH5TcNppIHq6nyrRsBNQYUH7xu)r(daJmbRCXFkMsHLZxGPPzwXdWb421D4)ahQaTI1QC5Qf13(i)tZk6QhQUUC()RayUOCz1qBZDRXTnAGf8T9Ln4EaSM(HQYvTnxx1m7E(WKxmRREf8cH3gxQX4r5u8K83BBevlVywJC5QQz1Ll6FBBZRfvAlULqTU7QUTQRRA(FJE)pNF9IMMZ1R7RMpA8Ua3PYFYlGdM9tIo4dUceLMaLR8jflPjDeTd1)ueQz(BL9T5fW1OgbGR0YbSX2P(u18uGA1DPu)5Erj2XtysjC(LIxS6rZaH)XfD9juDktq)7w0(aojme9hh9eSjTO1SWnb0CK24YHUYHs44C(Zp71)854k)OONOhqgJLtVXrnkyQPzjgQbI)wgCBFUCwfo2NYSnRgHGO2Z1hx60(jJ(WUZQtNA6OucXWf7d(V3rTsq1v84M)vabEpOk47yVy)040mFDVtaqJlRNtLGc7ig0hSMyHM9mnIKUSgUDcl6)as8aQLc)G18mg6(LCN3kQyz7Wd8321287i5csL1rSASQpE2DtVB4EGBY519ydbNFgSBoY9hfJjx0M7oI8xWHKQ28(2LeP38Qp2En1sijpQEtv)q7dx)q1JDa5fq9rNHBAVv8FXjpe1C)kN3(aStXxcYUSEzfWwRhPwzQ8BGnAv3hUg5ynJ6YFWlFrn2viX6aN2S4JMx0)4YBQBhiwuuvEDR8hXfOSv)X7)bNtfx1bSg46)mGNCfgFIZswpH5WtTeS0PgMZyxvE291vFSczbJTO5fLRa(g6oojYoI2b0HeUtQMryKwZQNqrJy8vuUDj6L6WtQhhXKtTYPUx4vR7agzxEF9Tdx(H6vmiy0q6bPZK0E56UoFe30RdlUEw5kSi7N)obKM1)9Q2vyZQL39p02TahOx6tuyXVdNgZpkdhBrAkmSbTk6T80OmHRdmScPG)KvwchMqy7ikIGPgn7oAyUYJAk9Xwa3vFJ9sfi7qO6tipM0aEjcWSQDIgL6fNLfeghKhzmTvY9msqE5e6GlNhaK8H6g9vscJ3qDQdQycvTjSiUvLItMh51dFR4SJGiRbFSwH9ffhn3wJ4()rx1IlARbSPKcCyr9837QmKXkRoLBheI9fIOY7lxL)ciCI29wOO6w3P3X8rycFncIUWXHIgtGBSE)nedrHCliy4gBIOFRsF5RhQwYkvrBb82N3O62xO43sDFjQR1iaMIo15gDlK5vl(OfIiqBGd9Stxu)7)Ez3CbXnRCbGIocJkKXdTN23cKtvxKtH0rnmXiQ8gbXJYzrN(hlYWADNffh0Ea7GZxVyGzOt95u43l7cuy9ERGrWt)OMdHdR1aYESMJiomYm4IYblMAbV4van1NY9rhXzcHRmBGq(oaVs0jQokAcq1VOR9oCGoHns0ROYr3sf1ZRBQxwUIA9g4OUH)B3rDg9FphpVbQPvy0tVDfjw0Phnkh)(VWLobekl65QNUEaeRiMByMtrsEtWFnJ1Lx8M6Bo7uSQ089U(013DjW2VrolJqmKN1vE7aio5DyTFrcGnBoHuerBof(r4Alg(B40EQD2haLhHFpl)Hsbm4ZmLrIiBXyaVPmvww)1hX9qkyFkAp6e2cpI(oz(8wC26ScuRgVD5cRs9nIZn(PITGO5hgw4hGf2vopsNkNnGwiia1CHoJv6xFnUreDLGO4eQxr8K40Kp6hZnVRYpwn)V32UuGAZDmfav6FUUSJlmBjWq0XZpMAagUypTr7XTFwhWVbF7myDZU97OELf2nAHleZYxg(ziSeFjcqjZvgfIPUmPHaa(qGElOc0UfpAvVxIkRbP3X397iv0MOLzoRTTBoqHpRUhUlK1iN72XmhoONH)cQFepgzsMPr4(9Cr32X6y)BmrqgDIiwGaIoF0zDUWp)LyE8b6EXgTwIOGkmhrLGBr6kgHryw4cWx7BsSZRxvDE7hrKpCphrj8bR)aTyDvLd)coC)WpJ3yyHaCw9T3wpd(yC6g6OVhB2KQin6sm7LuaiAboUppVSP8owPU4IzZxcmU0mr4oTkXe66SRdIt8ZdJVo3Zx3GF9poikppjpkliIjA2BzVhfes9)QSW8y4vqAmKwSEOEr9aAo2(24qWmFLpmhshlmM8gRQvfhKFCS5uc9WojHomDblbEg0fDDqAyww21rXbciNFc32zs9cY8oq4gpzivxmat6GyqdSOORZXlM9dSrWA((MKk4x01oqCDFv1IvvMdJoFwTaeAz2huqYbWSVELcd4tGVoU0QTFDQMRFdY(cKqGllxr(c2sIEehZgGBrZBuLq2nDoqrI1dV723x2CNyGVGucPfnRx((2h6LDY2(hQxP637O6HMDnTSIpu94n1nZP2yTGYVDnAOh23xSgznufkHnmFQvXXIuOgOp9VzLfuDYwrp74P08Av7j9RKAX74R0OhwXDPqafkokq2rSeTa6U7yhBn50nK63KNA0Z5byUaqOe66ykCyA6GDg3J9vawHFXRXASU4EsEamCy9guZGgDt4ks0LdhP0PjaNvs2w3JqC5rpBjziqCgzSjRU5YwkeAmlIz2j262IQJRUTnIXhA(k2xGob0KIAD6Ig)N(tz1H5g8cS5KSE7XRtb4sOXV55tOen3MWrLnLOD44lvTI2Dda7ZQQ4cfnknRghqS4Lay0d0EhBqTcv)jpysaTRAv1nenSNrhEzdFhPdXutYcXGzWQJWz3gf3SZKRGocqXMJ5mNEDa4LnjdlC4i3xcMTJdjQMNDgqLapUj(PEGijnVcznqUHlV4JvDd1Zkxy0vnzDaiYjdn0zxbjVPLJWAZRxvsvAr39R8Wxt6kHwW6NvmNg9vUONB6WiaRMuPrdZtW8q1JProjwDnulozc0gEp8tm7rIXAVWxJG(4)7VZ72Pg17jVB2hdIaMsTZ1)kZVwP03xvU1IgDYbXSoT4Nz1rFkSQrEl)rZQ2a0(Dg1FNr9xjLShP8ile7)suZMhm()vKv9wBi8SM2cJO)YW3Mm)AdLS3cBBhkZjuYoUGmx9psU2o0Gg0yGL(4wNBmjhmgg9SJvfQCRb0hIc2wQnQCk)OUe3yTSDOx5if1puTU)JvdBVIn8aW(OF94XzdPHp3(3)m0S2qVVTRz9eEaroP(Xk(6s076WBr3zh2lpIKymMCbAKkrPAknDMIyloKWj)8UjOZL50w9HEXatvMegSl7f9NgoCWI8ZryZ70MI7Ie6aToFKsptZXiV4f4E7N4d(Mg0XdMql3)mHbX2oPAAFCy7QiS1qH(cXYE(nM0rBL9rU(ILZnsQ3ehv8MN)cozh0yWBYQrnrKOYn3te4EXnLHHT7yEeQnsKDQPQJRhi4JpYdvt4WchgplhmtB1s8XBCRqzG54Hb6NAkzy9Pmxs3VhvJGY6xyLfcBqCPsvY76AF4S6UkAseccoF)RF5ROaHrGil)ICq8xC7PSrHKduFz9QvyGjF5Zo7QVogVB5dbPZ5m9fRlx152j5pvwpBhwOgHOtLNWAcAmyHSV7XGeaBNdKTZy3aVHtNe6P4hwCrlIq8dNqkg4K1ZwCtQd)fUPpP3eDAKprNUJFAZaYTknBgwrBwno1wWYzse81L)Y23HF6ypJl8aRnVMTQfYKUkFVy7GngRn5EVl19C4nqBL72T72DNiaJ0IC0zZCuAVjVNXac1Oi(WCEOdXLyOl3mYkiVOrd9uBYZ4IMQpw1noWogIwmCUoix7v1ZNx18dc9)5bgSlgVyQ72)sCmCFk1SXDORnRseMQxxFh(GeZaWOcnYRh5i0Va7FXs5PwQzZTxhIL4eByR4Di5S4jHep7mylpfCGefm10BAkDqDp4M5Xs1EeWMDjtyIyo)ufk4wP4Tf8PTeCix417VSbshiNQ8SnftVOQRVTPCbEn6sX0ndG6tuSWxCnsDLZjUu4XLLVgbByhrYundFSci4OHE4irebut6DSxD2UicNYO2p5doAM2UeM(5lrWY4Jjmqzs5b2YTNYrd7TGaZWZk09AsraFr4bnbLURGgV)8GSsVINipOTJxThX6wfl4jlXTrHjgJ()(ZxItFGndV60CLasN3uFB1pCzjwilWp25nRlxLiYQ1DLifw4IhywvSV6P6m5tCQkNL1X7sVU92ezkVgnTr2DubDRB8u52X(XqAABkSDFXNphjNY70CMmJ9N9r6BIEQBip10HrywZzPBhN9FQeKMlmTHB0n4BkTBPb53SpurLTIi)Q0z8ugp60F9z9)RMGSG4FSjmWpl4hBY8cJd)XMGKiml2BcZ9cZsG)BMFON)p2eff5Lapg8FdI5AqWJtiLEZrMoQrVWpfI7URCmzCJvt)Cdx7eZVo1ZtLTbGHcAGxUSsKVcJFimZKiUhGsXw)6Zl)KACaTLrTU1qzx48F1oGswmRBGXlpMWnICDFv7Q1lk7qhIMxCZI225lat4TgW)aNwYQE5WIINdG6zxppFrXAEB8rXCOEJJ)Dob8ZJ89tZ8YcPuFKHtYzYU8mJpjcff6LNw8QQU26ESBwjwNEJ(dp3e3mQlIaEusZx087wNl8OHieUeJj5IhoNO1yYQYg5mEw)ht(Fs5LkSIImBFiu7Ba)DwL02enXBSecHxgptqiKskf9HTGf48QA4OqZI3TlxC8DnF7GPJpShLjYR2bJuI3ovk6iHGQwJNPnYxUQQAonHJKmp5IPdVo10w58cB(bY7yQ8b07nNlIRUooNdDIc6JVPUeh3PWnLAyxNsWWPynYv8hoCXCKVFJTDNWrrSxC)MhNKLeK5LI5Mk6uvnzGAaEZLyOCqrjR0EJ5CDen8mcJsdctsKJFV(QfvZga2FL6(WRWX1RQMH0N(fEKHqDvyntW4lycWaeeWtqLXxQhvqMllxTcuWGYv0rdgw8vciB6kxGYN1lx0oq4j5uS2GhG2fUlVsDbEbmGnUke0QHEuye)be8(d))QUR4hodRB3QF4I1DRA7R()Z1sivKQN8SRE9V8C5YqDZx5mycLz8IU2Lp7SZFbvsiaITaeDoF8GNe(8WIG4KVYNAZIAtCMXslJw))4o1ywr)18U(pFN6GIK)AEvN9xUR6WcFVO)sEQJ)l3PgiR)AFOz21OWkS8G)ZHCR400)IDvt1ip1viq7j4(uROMljvYpPVxwUPC9YJk2CrxlO9f1gsek447xC9YAqnskOWyhcievIHc0W1L07OAo9c7Vguwcut96p6JLdlyjd8yDvlB)i8zINyOveNIzZVMNGQH(gp31ZR7b15gQBwd)gmAWvuf1hqkoDn2XtwDnyn71lQBaRxVMABf4diwn(bK1ejSc9WdH9SIRXWKm(fTO6UYzpYBTrpahmfEtE9SfvLnRxD9hdXoRaoF67ObxivzwMXdHZ4Cjqr8mGfCPrzEO5Y(EXr)ytCyygytDGVhOmf8F9I88Z(rWs0Wa8F6hMebpvywyya8XjGHBWZeKcgy7NffNc)0iWU7uwz2Tu9BBUtokicSuhE5h9)1CNl7y50aHHFv4fyg5Yooo(WkeSaexgjAelMnh1qFaAPMG0HEbJq8Ut9xLD74CpJ6U1SAUKCsSR4KQ((D5YEpjxwFSrUmrnXdqs1mFNi2ADClOZ70yOxCLJn9UsiYBI7A4Ve5ByVlqeddQL0fX8NXDztA(OCV9Z)2b)ggYq(xYLYP7K2dxlEZy5jInxSLN9UX3vkAcD5U7W1J3m)Y3qo(MqyNmV31482aBT8(OdYEe8Ey9f(aP1FZLhXInwF9cmdYy(0ZF8)foD(V)q)VIfSC(CLcAZO5TBEtp)SMyel0FhSIaNyNRhnmEj3ntFS1X9rEqipqOn2GBGutf4r3yPWvvjI0vyFf1Kr(cpLgTlRA9)vgzW9v5ThMQ5lXloxUZPlU3Pson(AkAq806U7vs7OT0sPOS0yvyaLuLSbzPEQ0dI9cE927UNnqF19xX3l(639JFZ7F3p8tFX3nhr7q1Mk3WSenROH1sYEPxWTudI)()S76zLSv92RFgTtfHi2RVZ1q8x(cbpsA2A5HMFY0uzIYYhPto2lH2q1QyujwZZSqqZR20q50)eqrOIwDJKWzt5GsMovlPbQb9wJXqwRjyyxgVokdLfQSwxw(7lhuDOz0lhXXMxn5wd9wR3yCszGsNW2DVyYndTlW9N6)78D)11)82(h)(lx)DDJjN)cQU5R)4LROaJ9Wp3cVfPi3FPdiB7yT2teBVIbKTGhND7jddrrPesLeSewCwCmnEo1dhKaJotY6cpTJLjVMO13avopXVp)LmY36KvrNw20ub3qvLybf5QRRAlbqnqqDRRJc66C8JQTajvFMAleISKFHaJPHfkal04Yf3AACn16frOBAggP2tp7qb(sM0Kh37RT35MuZUEOzdmPiEi9c9qZ7KyhtMj7UAtDE7RX4ij(VA6McDr4mdVyDw6CJTtIZDhGprMFH7WTyodv7kODWFmiw8drWOel9Jaz2dbJeE8t5mlhEmZsW0eDNT2G0FoirJaYu4rogrtMHPMVPgSQtT4b3zVfnWIDkIJ4BnTNnMgCOnWGa0wFfle6V0Pl)dhs(akLX0mCRdGtAHxjn9iOsvif9sDQw(pCo8GZTohf9AJZsOq26kPiDBCwOhV6PScuwDTAzweVPmUjMquP3OwmH5j0rQZYuZcnjgZA743iA4XkrL(DUNbpZ0Jw4LikVhYF4PVXrUaGztopE2HkXZWevztSJDpLMpP1s4GzttGYmvZV2wZzvLraz6QbfcLLstG1r9wMTQk9cwLN7y5kqPY4vpZM(oiZrtiYXpiZBFniOnWrwh5pN6nY0IQtqEER3nBp05IEcJAoBikyHwdFFcXgkGB5Str)QZcEzHcKM7XB(J7V8WD7Kv02GWInrY7TbztROMvScYOemaKftI5cWTsKtPsXBEJ4QMCCEsSpMmlOMECA2kScczD5drM085tGGcs2NqSI8tigQ31y9X2ommPMC(ORlGf0B4PANyxRmUOqA9cKGbHwPGA5IwpfLXtlM8oJjj19e(sEgyjlrS7spBEsODJemlj35uCVr5NvfVPQKIZ1Xx5oew6b4nFtJv)1n8lwX2O0ao5GFXtFO3l2xQZbrP5dEOlTwjLoLlvyCiuOqpfATTioOdFTsEJNc9QAE(BOCxZn7wWr9l3(WKsFnHYS1d33RrMGKrefHy2ZZ)d" },
}

EllesmereUI.WEEKLY_SPOTLIGHT = nil  -- { name = "...", description = "...", exportString = "!EUI_..." }
-- To set a weekly spotlight, uncomment and fill in:
-- EllesmereUI.WEEKLY_SPOTLIGHT = {
--     name = "Week 1 Spotlight",
--     description = "A clean minimal setup",
--     exportString = "!EUI_...",
-- }


-------------------------------------------------------------------------------
--  Initialize profile system on first login
--  Creates the "Default" profile from current settings if none exists.
--  Also saves the active profile on logout (via Lite pre-logout callback)
--  so SavedVariables are current before StripDefaults runs.
-------------------------------------------------------------------------------
do
    -- Register pre-logout callback to persist fonts, colors, and unlock layout
    -- into the active profile, and track the last non-spec profile.
    -- All addons use _dbRegistry (NewDB), so no manual snapshot is needed --
    -- they write directly to the central store.
    EllesmereUI.Lite.RegisterPreLogout(function()
        if not EllesmereUI._profileSaveLocked then
            local db = GetProfilesDB()
            local name = db.activeProfile or "Default"
            local profileData = db.profiles[name]
            if profileData then
                profileData.fonts = DeepCopy(EllesmereUI.GetFontsDB())
                profileData.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
                profileData.unlockLayout = {
                    anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
                    widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
                    heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
                    phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
                }
            end
            -- Track the last active profile that was NOT spec-assigned so
            -- characters without a spec assignment can fall back to it.
            local isSpecAssigned = false
            if db.specProfiles then
                for _, pName in pairs(db.specProfiles) do
                    if pName == name then isSpecAssigned = true; break end
                end
            end
            if not isSpecAssigned then
                db.lastNonSpecProfile = name
            end
        end
    end)

    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")

        local db = GetProfilesDB()

        -- On first install, create "Default" from current (default) settings
        if not db.activeProfile then
            db.activeProfile = "Default"
        end
        -- Ensure Default profile exists (empty table -- NewDB fills defaults)
        if not db.profiles["Default"] then
            db.profiles["Default"] = {}
        end
        -- Ensure Default is in the order list
        local hasDefault = false
        for _, n in ipairs(db.profileOrder) do
            if n == "Default" then hasDefault = true; break end
        end
        if not hasDefault then
            table.insert(db.profileOrder, "Default")
        end

        ---------------------------------------------------------------
        --  Note: multiple specs may intentionally point to the same
        --  profile. No deduplication is performed here.
        ---------------------------------------------------------------

        -- Restore saved profile keybinds
        C_Timer.After(1, function()
            EllesmereUI.RestoreProfileKeybinds()
        end)
    end)
end

-------------------------------------------------------------------------------
--  Shared popup builder for Export and Import
--  Matches the info popup look: dark bg, thin scrollbar, smooth scroll.
-------------------------------------------------------------------------------
local SCROLL_STEP  = 45
local SMOOTH_SPEED = 12

local function BuildStringPopup(title, subtitle, readOnly, onConfirm, confirmLabel)
    local POPUP_W, POPUP_H = 520, 310
    local FONT = EllesmereUI.EXPRESSWAY

    -- Dimmer
    local dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.25)

    -- Popup
    local popup = CreateFrame("Frame", nil, dimmer)
    popup:SetSize(POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    popup:EnableMouse(true)
    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.08, 0.10, 1)
    EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PanelPP)

    -- Title
    local titleFS = EllesmereUI.MakeFont(popup, 15, "", 1, 1, 1)
    titleFS:SetPoint("TOP", popup, "TOP", 0, -20)
    titleFS:SetText(title)

    -- Subtitle
    local subFS = EllesmereUI.MakeFont(popup, 11, "", 1, 1, 1)
    subFS:SetAlpha(0.45)
    subFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -4)
    subFS:SetText(subtitle)

    -- ScrollFrame containing the EditBox
    local sf = CreateFrame("ScrollFrame", nil, popup)
    sf:SetPoint("TOPLEFT",     popup, "TOPLEFT",     20, -58)
    sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -20, 52)
    sf:SetFrameLevel(popup:GetFrameLevel() + 1)
    sf:EnableMouseWheel(true)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth() or (POPUP_W - 40))
    sc:SetHeight(1)
    sf:SetScrollChild(sc)

    local editBox = CreateFrame("EditBox", nil, sc)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(FONT, 11, "")
    editBox:SetTextColor(1, 1, 1, 0.75)
    editBox:SetPoint("TOPLEFT",     sc, "TOPLEFT",     0, 0)
    editBox:SetPoint("TOPRIGHT",    sc, "TOPRIGHT",   -14, 0)
    editBox:SetHeight(1)  -- grows with content

    -- Scrollbar track
    local scrollTrack = CreateFrame("Frame", nil, sf)
    scrollTrack:SetWidth(4)
    scrollTrack:SetPoint("TOPRIGHT",    sf, "TOPRIGHT",    -2, -4)
    scrollTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -2,  4)
    scrollTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
    scrollTrack:Hide()
    local trackBg = scrollTrack:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(1, 1, 1, 0.02)

    local scrollThumb = CreateFrame("Button", nil, scrollTrack)
    scrollThumb:SetWidth(4)
    scrollThumb:SetHeight(60)
    scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
    scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 1)
    scrollThumb:EnableMouse(true)
    scrollThumb:RegisterForDrag("LeftButton")
    scrollThumb:SetScript("OnDragStart", function() end)
    scrollThumb:SetScript("OnDragStop",  function() end)
    local thumbTex = scrollThumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(1, 1, 1, 0.27)

    local scrollTarget = 0
    local isSmoothing  = false
    local smoothFrame  = CreateFrame("Frame")
    smoothFrame:Hide()

    local function UpdateThumb()
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        if maxScroll <= 0 then scrollTrack:Hide(); return end
        scrollTrack:Show()
        local trackH = scrollTrack:GetHeight()
        local visH   = sf:GetHeight()
        local ratio  = visH / (visH + maxScroll)
        local thumbH = math.max(30, trackH * ratio)
        scrollThumb:SetHeight(thumbH)
        local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
        scrollThumb:ClearAllPoints()
        scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -(scrollRatio * (trackH - thumbH)))
    end

    smoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = sf:GetVerticalScroll()
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
        local diff = scrollTarget - cur
        if math.abs(diff) < 0.3 then
            sf:SetVerticalScroll(scrollTarget)
            UpdateThumb()
            isSmoothing = false
            smoothFrame:Hide()
            return
        end
        sf:SetVerticalScroll(cur + diff * math.min(1, SMOOTH_SPEED * elapsed))
        UpdateThumb()
    end)

    local function SmoothScrollTo(target)
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        scrollTarget = math.max(0, math.min(maxScroll, target))
        if not isSmoothing then isSmoothing = true; smoothFrame:Show() end
    end

    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = EllesmereUI.SafeScrollRange(self)
        if maxScroll <= 0 then return end
        SmoothScrollTo((isSmoothing and scrollTarget or self:GetVerticalScroll()) - delta * SCROLL_STEP)
    end)
    sf:SetScript("OnScrollRangeChanged", function() UpdateThumb() end)

    -- Thumb drag
    local isDragging, dragStartY, dragStartScroll
    local function StopDrag()
        if not isDragging then return end
        isDragging = false
        scrollThumb:SetScript("OnUpdate", nil)
    end
    scrollThumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        isSmoothing = false; smoothFrame:Hide()
        isDragging = true
        local _, cy = GetCursorPosition()
        dragStartY      = cy / self:GetEffectiveScale()
        dragStartScroll = sf:GetVerticalScroll()
        self:SetScript("OnUpdate", function(self2)
            if not IsMouseButtonDown("LeftButton") then StopDrag(); return end
            isSmoothing = false; smoothFrame:Hide()
            local _, cy2 = GetCursorPosition()
            cy2 = cy2 / self2:GetEffectiveScale()
            local trackH   = scrollTrack:GetHeight()
            local maxTravel = trackH - self2:GetHeight()
            if maxTravel <= 0 then return end
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
            local newScroll = math.max(0, math.min(maxScroll,
                dragStartScroll + ((dragStartY - cy2) / maxTravel) * maxScroll))
            scrollTarget = newScroll
            sf:SetVerticalScroll(newScroll)
            UpdateThumb()
        end)
    end)
    scrollThumb:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then StopDrag() end
    end)

    -- Reset on hide
    dimmer:HookScript("OnHide", function()
        isSmoothing = false; smoothFrame:Hide()
        scrollTarget = 0
        sf:SetVerticalScroll(0)
        editBox:ClearFocus()
    end)

    -- Auto-select for export (read-only): click selects all for easy copy.
    -- For import (editable): just re-focus so the user can paste immediately.
    if readOnly then
        editBox:SetScript("OnMouseUp", function(self)
            C_Timer.After(0, function() self:SetFocus(); self:HighlightText() end)
        end)
        editBox:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)
    else
        editBox:SetScript("OnMouseUp", function(self)
            self:SetFocus()
        end)
        -- Click anywhere in the scroll area should also focus the editbox
        sf:SetScript("OnMouseDown", function()
            editBox:SetFocus()
        end)
    end

    if readOnly then
        editBox:SetScript("OnChar", function(self)
            self:SetText(self._readOnly or ""); self:HighlightText()
        end)
    end

    -- Resize scroll child to fit editbox content
    local function RefreshHeight()
        C_Timer.After(0.01, function()
            local lineH = (editBox.GetLineHeight and editBox:GetLineHeight()) or 14
            local h = editBox:GetNumLines() * lineH
            local sfH = sf:GetHeight() or 100
            -- Only grow scroll child beyond the visible area when content is taller
            if h <= sfH then
                sc:SetHeight(sfH)
                editBox:SetHeight(sfH)
            else
                sc:SetHeight(h + 4)
                editBox:SetHeight(h + 4)
            end
            UpdateThumb()
        end)
    end
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if readOnly and userInput then
            self:SetText(self._readOnly or ""); self:HighlightText()
        end
        RefreshHeight()
    end)

    -- Buttons
    if onConfirm then
        local confirmBtn = CreateFrame("Button", nil, popup)
        confirmBtn:SetSize(120, 26)
        confirmBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 14)
        confirmBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(confirmBtn, confirmLabel or "Import", 11,
            EllesmereUI.WB_COLOURS, function()
                local str = editBox:GetText()
                if str and #str > 0 then
                    dimmer:Hide()
                    onConfirm(str)
                end
            end)

        local cancelBtn = CreateFrame("Button", nil, popup)
        cancelBtn:SetSize(120, 26)
        cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 14)
        cancelBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(cancelBtn, "Cancel", 11,
            EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)
    else
        local closeBtn = CreateFrame("Button", nil, popup)
        closeBtn:SetSize(120, 26)
        closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
        closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(closeBtn, "Close", 11,
            EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)
    end

    -- Dimmer click to close
    dimmer:SetScript("OnMouseDown", function()
        if not popup:IsMouseOver() then dimmer:Hide() end
    end)

    -- Escape to close
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            dimmer:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    return dimmer, editBox, RefreshHeight
end

-------------------------------------------------------------------------------
--  Export Popup
-------------------------------------------------------------------------------
function EllesmereUI:ShowExportPopup(exportStr)
    local dimmer, editBox, RefreshHeight = BuildStringPopup(
        "Export Profile",
        "Copy the string below and share it",
        true, nil, nil)

    editBox._readOnly = exportStr
    editBox:SetText(exportStr)
    RefreshHeight()

    dimmer:Show()
    C_Timer.After(0.05, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
--  Import Popup
-------------------------------------------------------------------------------
function EllesmereUI:ShowImportPopup(onImport)
    local dimmer, editBox = BuildStringPopup(
        "Import Profile",
        "Paste an EllesmereUI profile string below",
        false,
        function(str) if onImport then onImport(str) end end,
        "Import")

    dimmer:Show()
    C_Timer.After(0.05, function() editBox:SetFocus() end)
end
