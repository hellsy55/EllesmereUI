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
    { folder = "EllesmereUIDamageMeters",     display = "Damage Meters",       svName = "EllesmereUIDamageMetersDB"     },
    { folder = "EllesmereUIChat",             display = "Chat",                svName = "EllesmereUIChatDB"             },
    { folder = "EllesmereUIBags",             display = "Bags",                svName = "EllesmereUIBagsDB"             },
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
    -- Suppress stale anchor moves on AB bars during the rebuild phase.
    -- LayoutBar positions them from the new profile's barPositions; resize
    -- hooks would reposition them with old-profile offsets (1-frame blink).
    -- Separate flag from _applyingSavedPositions so CDM's early-return in
    -- ApplyAnchorPosition (which checks _applyingSavedPositions) isn't
    -- triggered prematurely by the wider window.
    EllesmereUI._abAnchorSuppressed = true
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
    -- Quest Tracker
    if _G._EQT_RefreshAll then _G._EQT_RefreshAll() end
    -- Chat (sidebar icons, borders, fonts, visibility)
    if _G._ECHAT_RefreshAll then _G._ECHAT_RefreshAll() end
    -- Friends List
    if _G._EFR_ApplyFriends then _G._EFR_ApplyFriends() end
    -- Mythic Timer
    if _G._EMT_Apply then _G._EMT_Apply() end
    -- Damage Meters
    if _G._EDM_Apply then _G._EDM_Apply() end
    -- Dragon Riding HUD
    if _G._EDR_Rebuild then _G._EDR_Rebuild() end
    -- Minimap (flyout button state)
    if _G._EMIN_RefreshFlyout then _G._EMIN_RefreshFlyout() end
    -- Global class/power colors (updates oUF, nameplates, raid frames)
    if EllesmereUI.ApplyColorsToOUF then EllesmereUI.ApplyColorsToOUF() end
    -- Re-register unlock elements for all modules whose bar sets can
    -- differ between profiles. Without this, _applySavedPositions uses
    -- stale registrations from the outgoing profile and anchors fail
    -- for elements that only exist in the incoming profile (they land
    -- at CENTER/CENTER = screen center).
    if _G._ECME_RegisterUnlock then _G._ECME_RegisterUnlock() end
    if _G._ECME_RegisterTBBUnlock then _G._ECME_RegisterTBBUnlock() end
    if _G._ERB_RegisterUnlock then _G._ERB_RegisterUnlock() end
    if _G._EABR_RegisterUnlock then _G._EABR_RegisterUnlock() end
    if _G._ECL_RegisterUnlock then _G._ECL_RegisterUnlock() end
    if _G._EUI_BattleRes_RegisterUnlock then _G._EUI_BattleRes_RegisterUnlock() end
    -- After all addons have rebuilt and positioned their frames from
    -- db.profile.positions, re-apply centralized grow-direction positioning
    -- (handles lazy migration of imported TOPLEFT positions to CENTER format)
    -- and resync anchor offsets so the anchor relationships stay correct for
    -- future drags. Triple-deferred so it runs AFTER debounced rebuilds have
    -- completed and frames are at final positions.
    -- Position re-application and anchor resync are deferred to
    -- OnSpecSwitchComplete (if spec switching) or run inline here
    -- for non-spec profile switches (manual switch from options).
    if not EllesmereUI._specProfileSwitching then
        C_Timer.After(0, function()
            C_Timer.After(0, function()
                if EllesmereUI._applySavedPositions then
                    EllesmereUI._applySavedPositions()
                end
                if EllesmereUI.ResyncAnchorOffsets then
                    EllesmereUI.ResyncAnchorOffsets()
                end
            end)
        end)
    end
    -- If CDM is loaded, it calls OnSpecSwitchComplete from ProcessSpecChange
    -- after its SPELLS_CHANGED rebuild finishes. If CDM is NOT loaded,
    -- complete immediately since there's nothing to wait for.
    local cdmLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("EllesmereUICooldownManager")
    if not cdmLoaded then
        EllesmereUI.OnSpecSwitchComplete()
    end
end

--- Called by CDM (or RefreshAllAddons if CDM not loaded) when the spec
--- switch rebuild is fully settled. Clears the suppression flag and
--- re-applies width/height matches so all matched frames pick up
--- the new profile dimensions.
function EllesmereUI.OnSpecSwitchComplete()
    EllesmereUI._specProfileSwitching = false
    if EllesmereUI.ApplyAllWidthHeightMatches then
        EllesmereUI.ApplyAllWidthHeightMatches()
    end
    if EllesmereUI._applySavedPositions then
        EllesmereUI._applySavedPositions()
    end
    if EllesmereUI.ResyncAnchorOffsets then
        EllesmereUI.ResyncAnchorOffsets()
    end
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
    -- Exclude spec-specific data from export
    exportData.trackedBuffBars = nil
    exportData.tbbPositions = nil
    -- CDM spell assignments are NOT exported -- users share spell layouts
    -- via Blizzard's built-in CDM sharing system instead.
    exportData.spellAssignments = nil
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

        -- Pre-check specs that have data; all specs remain selectable
        local preCheckedSpecs = {}
        for _, sp in ipairs(specs) do
            local numID = tonumber(sp.key)
            if numID and sp.checked then
                preCheckedSpecs[numID] = true
            end
        end

        EllesmereUI:ShowSpecAssignPopup({
            db              = dummyDB,
            dbKey           = "_cdmPick",
            presetKey       = "_cdm",
            title           = opts.title,
            subtitle        = opts.subtitle,
            buttonText      = opts.confirmText or "Confirm",
            disabledSpecs   = {},
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

function EllesmereUI.ExportCurrentProfile()
    local profileData = EllesmereUI.SnapshotAllAddons()
    -- CDM spell assignments are NOT exported -- users share spell layouts
    -- via Blizzard's built-in CDM sharing system instead.
    profileData.spellAssignments = nil
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
        -- Disable all reskin module syncs so the pre-logout sync
        -- doesn't overwrite other profiles with the imported data.
        if EllesmereUI._reskinModules and EllesmereUIDB then
            if not EllesmereUIDB.syncedModules then EllesmereUIDB.syncedModules = {} end
            for folder in pairs(EllesmereUI._reskinModules) do
                EllesmereUIDB.syncedModules[folder] = false
            end
        end

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
                        -- _specProfileSwitching disabled (see doSwitch comment)
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
                                -- _specProfileSwitching disabled (see doSwitch comment)
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
                    -- _specProfileSwitching disabled: was causing width/height
                    -- matches to never re-apply because SPELLS_CHANGED fires
                    -- before PLAYER_SPECIALIZATION_CHANGED (CDM completes
                    -- before the flag is set, flag stuck true forever).
                    -- EllesmereUI._specProfileSwitching = true
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
        elseif charChanged then
            -- No spec assignment for this character and character changed
            -- (alt swap). If the current activeProfile is spec-assigned
            -- (left over from the previous character), switch to the last
            -- non-spec profile so this character doesn't inherit another
            -- character's spec layout. Skip on plain /reload (same char)
            -- to respect the user's intentional profile choice.
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
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_S3xwZTTrwB)xj38EPuH9TCLSKDS(ILLgj5mjtnvPcIeseJib4aaAzfxZ)9VZsVIfsrVmXjJDntSmfrJUp9zVpNN(J)CBq2QIUC4hsYk2uE1S8Lfvohgf8J)CBCw7SMIIQxx5ge4y8b)9kVWiNF8)GpD3tRlG)6UnlxIpX7lAAlRRQ8HVEq28CAOD9Y2uTSE2dVj)P6nDWNeNLxnBrDtl(BDZE5LV4MJZB7ErEd8brzD5n3x016gZ)ML5TTxw0wVPzwb(S13DxBr3VvDGR7HrWF8JCdsDssP3zB58cyiEX5xF95NP)2)A1bohg4gfMggeMKMe4NGlaVGSJp5SBMTPTRE1nUo34fMM4eeCtQR1mXN)A11lNx)yvR1Si6qxh)q3WiVWIdCc1Zc)SRp)cRPquWHPP(HojrHrjE4eaw94iVPRCzz3tFfENXH4YgEFbPbUbU070tqHz6S5lvs7nxGohM4dRViGKL445KSLfyueUHehaKWOK4q6L5lEz4g8T2BWt(281)z7BQexiqdVRg3chSCc5FXGvJFAGFusqsA42wnHoh6444g6fMeNKYKUEmc7f7krihDPnGtHwxrzRxM)uHLmrC2z5LvGGIflO1EStKMMfK9Mx(QRT4bJpK3x8yAZiBlJr1EgBdYDttAYEoDdZU80F61wZ3KdbkMxOBAOVRhnZtZUQduFu0tBHKAnyZoijm1Z1ZZp1GWmu2mXhFtWljnjXlH2Ttj9pxu)O9EWU0ln9(8y6LOTA)S19fe59ERT50dDdd9I9d8J7PQzSbMfgnK8XDDNShlN3T4S8UzlgO8DcnU9z6N6RzZr1QyJmiJJ(OSi8IIY7x0XtmwsB9I8kqT8lQ3unV9J)hsIiF(86k0SHhy2y5YI2vfnfV70JM1bMDaocYIsC28Y28Bxw8Q6MvxKFFz19VI(41BAxum)ysB)X1lRrrlxWwKlWE7MDlA5Zbn95MDp8Zj(Ojf3Sg4NtJ9jPMWS2f1p(ILL)(VF6m4nsdCQyGFxBbzSIgA4x45jNix9WtnLZH5HA2aZ)fGPku8d(4JQkxLJlHwG5hx6n1Z(PL1pQNKYjr)jNCsJgZ8GH8(flr64GPItgyxmVBttExX5vhlSKHtYWmPDTxo)(I(pOlixruTxu3mVO5QYFVOIirrz3QPchTe3SiYOxgOL)I62sA5qUya7l(eL(jWMDiQac93OPy5f1LvDWU6XV8Tx)Yl)zGLzT4tK2VDZ(qLRpPeay7dDctIyhpGXmsmMXSvhFVyWaf8735GlFD0Gdw7pemqYgTsf2t(BBk2uaQz62qmu4e33be)qbk6pX73B5apx6TOEA5AW7ZGUCWiegqq6xkwuoBzXl)qjAANj6XO)B7GKBrvITuIPi5jYrmW1EpzNJU5gkmFomemT64M6aAZiIoTJgkh(WyA45D8qumCp4xegpVSynBIajbHU7jfGgKWSF9c9yaozAAbF3tktkk7PIx2lRMb6Z6kAmgx3WpZXLiEXILkjHbexFNq3yYbN9yJ)aFHWwCGJNFqaoRvgXL7oEo0e2lk2Z1fCmAVEdKB4sRsorSxWGN(FORjxOgFtxxDL8Lb(mRfC2x5oWqozeuk0oW9bH4bB7xQGzhRhPtvO6Jdc8fbH4h5ecEyqwPUOqeldn8s(MN5WRTLJVarCwW(BGs4WFVvHcJcsMt1gi6RoxBZHdcK0LhBzA4tZIzA2M2cYGzEZ8tGicrR0OvZiRbNmS4Di9ADZA)3BYBkqlSKbXOSv1WOudHxEfy(9OLlXbWtzM8AikuGsrFtJ32vDpb(aWdyXYIzDGvm4LB4aPHxbxx8bW6ybnuEelDj86)h11RQcjlwGfBPz5rSUQS8(z4DraA602KPhqKa1fNlc5LwJ(z3ssixaodb(oqZw3GS3x2(AWJI3w)YQIvpXlBoKO)o6YhtFaRZ0Z(AYBRkp2hrdJAXzvBwDz9JTmha4vez3F09EPNssVKir5GShkE62YQ58C(x53BO0tORbpp6kxJCaXzfvOxAZXT4KS6nWY8Y8Q7lOxMWPTi5W9Q6Qo9S4wHpB3l(7g4VX3Es2cGtbEwKu8sE4zF)Ko5G7Z7ECIZYx(y(tTi72likgXZQOYNrkXPHout5VMi34h6NTkFwtnoPjoBxAtkcC6btrcXzFosx5V79n1pEszdWHI(mbcgfOfcKhe2miPaXaKATm(nMeZuyW7wYt3JAGbR9sC7LNXQjYUx1927(n5Ex7I81fgAmqVFGfd6km7ql)szQbZWCn4eYdvfTTysIwuwj2dwDBEhstn2AawmIaFf(sGVDvDvbnXjo)N32oiMSeEFxVOPEZ9lyLd8giWhmVOc5WKz9qW6lyl7X1r6yrFQ5qcWWa4Fc9)Mszemo46gyuFa3zy))nzU(vZDLqt2xdob27)FMLuyMa1Y1IHri(zgwbXmJesBE84SBV3um1H0ArRMrfuDe7u8RtUJQ2OF(s8G(iElN1GcEn1wVSCoXIGQSHiFkERKpMKdsasO6fjyfWTOqZVVsjukSWS4xaLdGachVeer7c4F)7GGw(s6vQmvy8mESuGLAuT9NEsP(0EZz4dGljoImqZ8Vu2wElLNoyjwHcYe3GHcAHYojhnR3DOow4HmMoIhkcvJCE1YNoTQLYVbkonWiKwd0Rz9CWxcIqJecPWMb5DLPY1ffZrgyIpqUlzqUn(UYa4SIT6RSXNaCE1ZEZi0()YAqbzS(Ubfs9ZF6mOWMyy3R(Ubfo42)lyqXwZkPa5lPXKe8aS6kHaG(Yyjz)9EUVHMiHBmtyPzedSuIo(sAHbut9f2cdevrVeSz7TghD4y2XLE(0ZfYXDiY0wOvck77R4wi6BXC6uoTpEmisdRug0(UH1VQrQ9DdRQu1)NodRFpsnkQtRuQ8FbdRtAi5B7q1(8nWUprYX(B8nDWBgNyXxfBQH85hxf4itfPvCXgURmsWLSLpJe1Wj(B8m25M1lm)xF(LN(po)TxF0B2syUrIZrUYDqMnNmpBJFWmFMKVTLiYH5Uz6W2hMzRXJA38qhubvQZrWxYKg7ZfdMvEI)EC7FprW)zirWFpU9)qCVy8e7ozO7tLA2VszcElX)T)oymwSDJLK4j94YohhKY2X85yyQHhndYFHdDNQ0aQOv(khd73pzYjoHZVFYKuXFlo(UVFYKF)KjN(io)(jtklDK)6CYKunc(f24JTFf)fTeyMWhSrSN898N(TB(tdYUPn)9uHST1Z0yy6l((Xv(F9SQ2ZvERY8fBrUjdaAKI1yFRGTb5pBhLjdN49HLjt)GJs1hmhvvjdQvMjRRMNBuqujc9zKL1E14O)aY(ZlMOXYI2GCVjQ18xKFVOEU)mtB4FIojtQEK)UHy07tzXcklvWTxlQF3qmvpLmr6pTLC63neZvv9Fkke1VBi2Sm0)lRHyDFq91ZUe1DY)58SV(g0WJx27U4795W37ZbzBg9NZ(CW28sifN5ufoZ(ghxVOz4b3o4UV9kB1TxvnJC0xF7xznt1JQFMb89F76ejj7SYzn1)Vu0Q2agYZkKvkqUpXwQ0SJJP(v(pRUlSVAQ(JmtYkKJ57Tm5xOwM8B7kLHBkV)c2YK)VALYioGYXs7BV2PCG(1XAZuk76FZ0sLwiOXx4qt73s)b2Wp1NU9NOSBV)I85FonWpJDdc8a451j3t5p03GXU(DBoKtsFbBt)VK2CgIeii34)TBv)b4fgojM4qE61CJdKJNcYT23g)F8kZhHZHVWn))in0(KHfV9JR0gZfaAyVkb9531)BPwpN8Gl)mlcuvd(pamei8LBmtE9p7ryfpSEp3t)ZFEN65WEnQ)zrtiCKgCT(mJ)DCzH)s2Mjie95OrGP(aoKBOcFHKixbdQFg4C4zp1TOC21LRiePucbll30E9J10NIAqtYQV9FHyjZ7l6d2nohYqAiIRjgGBiDsCGcG1ll7UAjI3LMyfJZHCJprpL4hfhFhigM3i6)DePXaZbi4OCU89lqVjAGFvEB3GbwmUAmwHqCmqdzbbIr1nZkAVyw3f1TTHzV5Ox8sS5F85F7lY7nnPzanld5jmcAl(s4ofNye0ibph34rwtvK8HtxlujYLX4MMI3xw8iJJqDiz(cMKpgI6GWeJ6DliSZlY7wGVGtRUUSJXKkXi9YpSUSPyUn9MQacAHW)eb(Jc8NLgRwJbcfalVV6OLlXDBGmjWqvyVqXh0AGPm86M4wErtr(diIgZgEvF9FkFndYJoz31KVQqcKjyUh9Cn3BWxjIYM5De24E(7E713CXlVer(oIBOdxUVRT4OziMgPj7ebCrtrHIRfSIjzLaAsE18I5vE4lemHQrKSeM(FkI1NVP4UonaTGGMY88L1vfaZcHX0mkk9RvjjKPujiYsEeZ)UFdEdXh6HirOh8toegFMMLF3DLFWGI5qumEjGiMjkeJOlLId9n53wSexCm)Yr4Zt43cqbmzKbU40S392tE5L38IJUuZNdlglAuqgZX0dQQaMzkUgIZq8JeRbnV9yzV3TEw9QYQ7VcL5yaPsamtAkex5yIo4tjxiOLWYtXiCC9Q15nfNvphrMP3E(BFjsF6kN9GU4Z8yFCWV6YIUI5NvUCzzBXS6Q5K4p(9LIm4oEpvlJRbaFiGZH3eqi9eEl9NvNuSSlhrmhKqZ7rNqch8B92I2oLIiIAqy5zywyysgSitpW15a3G4pwf6lWTpp)0m30pw5NK(JvUorbW)noauovfc)uqOedyDJCZa9h6rWpj6hRId8XNYbEkph3y8juOgl9oDnFNP4Gd)HrmWahVmxVpcpoO6QkYbE)EHE4qeKa)xVOygMGHzim9cHFDAmoarE4VojfNF(WNqdwyymSaH1vQl(oOVsuGd8FtHvk8fzCkKifXWc2yAf5HFbxqWRYnmgxdXWxgEeGDtm2ajcPzWSJhdIOzrm260ZhP)mnxT(Xpl6Jvjo4RfO4WQdSZaVBxKe4htaVfUUIOTNP(EWUMCzfzVdN4IBnE(W4NMIJzmTcngzC7bPyg7kWAJ2wKSkrajnXdiPbPiHjbNHoj0ug2TPTNWqy6PjnW)eiwM76kQgVwm(vBFr5JtLD86zceUXVRLlVLTBgjMphLh2j7nYXzXEVvwpKsHmrcg0j52y6)ox30xdMNGwCyZngfH8arpypcKVaEF4demqOKVsG3pdwGpJvhRwWsCFl6hy5pKpDhcts(ltzNTVcKpHNXCzBAmOfDt9JO9CujQa76yB)Sxq(zDGszq35Y5AlEE(2kBj9626T1gI67UJJHjA8nG)Bqv(orFWe0baHNgUuDvAJX3VfCez9Y8Ucc(VdaptklQMV8jelyoP4U8nl7WVczSdwvGTtWv2ocieXf(II8LDlE7Mv3s42MBwx9A8lWapkrDIfqIpc)KAysJrX71flra5gmtJieQeHVfEG)kXu5TxCm(6HNygFDw8UQs0pJMnR7kVDzHcDbhZHAY3Aw)1sWZgCUzbLGGjX61n4YzWVYx((eUIdQJ4LOGiCD9AWSn5jcsIixyY30KFcch4L1vOLFE3hDehM(LRwx3aou1H4toUUVIWsoAtpfCo52n3DhXfPa6BWD2AW()DDiuoFxDf4iAy2P4I)U8zf)ZJMp)8Q2)PrOm)ZvfZlZ)N0x9FcE8bmHTpM)0HxFnsb9vBV4egnYlb7YdiNcvyBQaTAz4ia7(FCxg5TfGrObEs2Kxo)S8MheOyUh5HRlt6Ux4sehvKBwf8wTGxtWXttoQDYnd8U9PW78zaROg7yMB(WOndlnc6UiOpcZIWvPH4idG9Ia0gDVeHfxUMvbh0zPGbqjk4)9Qscd65TEAuXAr4U7qyVKLAOpmitXJFzr(C8smHHqtDumqmyQWyi3gW1dq2fUN(B1BmqLqGtYKsZ8LuKhoz)7nGtDNvFlrk147Ox0qowfaKYCTaPL5p7l8mgf6nLvfT8lvQu483x0Sm)jjBIGCSOS726pq8G)k66h(aSWijDyn31BGVC16UNghnLhlYpIILKbo1xElebHI(MMOVRc8aFpLK4qxgOsHiQ2Mykqsqo0R6YN9WZduCf3OdOobPIgEjdVP6UU6vJOysl0HXWt7cKomIqrAKoTccD42CgS6jOx1NuFXGVQ4N1WVkHKWcTXeapZ4FCS9IrRntZJBPnnYsBQMDgyYSy)SEiSfAQE415ThD)9n1QjCKExlrhWUdPnh40LJ3XCmNgWdB)xMLuyOjhRH8gmjeYhyaWAaZLn6GQl1SDWIxVZyyPJ5rjbzDS1GbgXaZZ0DRVku9khaq1G9HNfql7ySDY4h8mo)wJzzbOxsR(xGEcyrV41eU(39ep2qDAF86fXry4)BOrsEZ2qOCSMGbdI6sRI5C1jxtQe25qkYazcTWzNTX2rqyBCKCOkhHLbK)mkdG)mpEA1jVWc2F13LjocMrAmmzmfx9urkI5GmPfqxZtIRbfLIfFxo7Ca9WGd0GBdyzb5J3uJatRTiIRM0eRfr4RzhWdXzZ6zujLcNx6xfSz)urdgxp4KiOtd1Zam(S7g4DYs58IJaDzYTsbyBJQ3qQ9ySsOAALfvu1uKqsHiUu(NK2)uMlTTcRkvrkFd2pdBaHOHHzlYBxGFGfCKpWdloFzu6JwU8eYdlYvwqQ0qNJEmIiUpopWmZxKolTH6eQ65l7gfdFlSeC8SwUCo6yKnvy0B3Yt85ZGggW9r(yFh1v14SQInDn5l1A73gNHF2dcXXDphanhQnudTAG37RBFBrEZZNHeuZO9orFJ(WlR8BBRBU94Lf5vSZamcDOvEIALnPVcRM70AHABYWl)Fcu40TOnKjM07x5CHf(6B)6TuPPDQKvRBiV6KTk)dcETkI7jI88LcZYYqLRnpIeC3jVir1JRxxmxTcn4d1oLisFTIRWWIMTStV4m908hYinLAnORIjg6XjHhoUeTMemOU4Sf1TDLgXE5OhqkChXXeiZDK0isVRVawGG8hg1hGXiuiV)P2usEZy5CQouVyn5iX4CjCdLAYnCmvSFRuT5RuESB()aDWpCu0IyABYBkE5YYo6shGP6cN20m59agDPrwzSxScofNbRwy9Vu5YGJFcl5XbflcfEe1iw(op4Cgh4Oup7YsF37fPIwMx(lOPukElrEnO4KK6TW8C9Q2qsW0d2EEHzOkqDLHnDl)zSzAnoUOAO(EoQSXkJpsE)mAexXVjJRyGOVceumuSBTKmTsVB(hoG1RwNptDPIK2lkTExhzbUUXrbXoHjjCOGSl7Gp7EHbPoUPrc3iiV6T)yU3)ukZ290tKCMNTjPiZ0uS7HhIe2Y5xLF1JfFyp6qAQBuKBssOlM2ALFtjEXHEU((jXEjC0ziDiWXZnki0pWlna(yKoabdp755TCkNHkbrqMJd8Wp6AkbvWh8Ep2LdzAqSsie7Wkh0TP6nJST86rFqFY8oDGxxiooj8ULP6H3w3ZQQ2RvpPBEAF80E(kUfiWPJyTODSHz6SYRJqbt5DLZO8vr()zKXjq5R0)dk2boXMS5aPui(kXkLXmrp2vodXLQdLt8JOx3WpY7tSXF2ca4kQ4wnYWJPEjMWW7VlkAWZpKDxayQK6yvuCwPTl1Ghg3LMmxdDpEj8hxFW9bHSvldNTSu6Wxrl8gU(kAHZItVnd8(bu5ATpg6j7znMDaqFGHguthNXellAxFt9TkJFjg0Z4iT1wqyHM4EQuDQDha0ZnJ2G1E9yN6tRLi7Ym5KgLCmg7Wn0iUBrFM55TxCmD28K38YScA7lYy3jme3nghVPdZds(ymtifkxT4TnZNXUNRaXbxQLZu22Efshtmlse2emFg4mxgLZOrRg2rBYbdAQ8k4cISd8H6NOZmgTvIoDDe59xkDpzXIeyzyb)Ik7QOapl3Lfs5ooxG8zgFzX9G0S8Dihx(Tak1EV(cxXch8ZPtINiw4ULpivFjgJRyK1oJqNhavth8m(fY5Vqlao)TkVGbELiFsy8HVl(MGXaEt0RIpZzLhOmnIFhIkba0YUeI8dzPg9AIYHCQIwjWQ(qkiDqBC(MUASCdw3X7LNw9EW)nkCqJNaNjHCqFJJvfIBemJ7Qkp86rtulg53kOD4BMOD8cGxQMViK4MerMW8XbW6sofE33LlU(vRQGO0FfEvZblcJC9lV9UfxqRMjojnd4N7WeUOiaItP6nIpNUgCWasQM9e(D4ac8YUF2C6QHnVH(yobhHz33KphVEGSYOmPgSUlFP6ep6pexsmZ2S2Wst8E1wNGO5kxUKOiUHrjrEXbHoPK2zeQELUbtxnyi7IGz2A6kzd5lbDU8aTk7iqJ0Ai6c7mfLQwA4Ynk21X3jkY3jqCN1YQXUs(GuYsetFPKQK2W)BXHxDmedBvXsClaLv4fiYB5R8IloHsVSEV6imFdiltQ4QDNR5g86oexm7XfoPaavOsersjyH1XOCQ3RWIpoPXJ0HuAJh0O4Fk3nzk8VvDqi6FQqrbnTv1a1a1dA6mtecsJ9t8DDdItjrGqjvfp4rQ(NSF3VqOwK3nGjh7nYe3rwGTkCPl8L)5P)rO7rUtlQVuqBK8tuJMIG8tc2B0WiEhDjpwmKKGevYVnwP8pD8js5kyLjQEhD(01KhHqqIVFCm4bSFefWPXUGCG18n8(cxbAIBpnzPE2)gYLSQod1mwm)LRwJ22VQl)EslOEazrjfJoUJr6hyUybFo43KqPWjLn4m0ekX1igoFJ2k)J5WsRuYWfpUOayqAIJFQNqjaxFbSB37NXw(8b6NjB9vunPjzGEj9H2VUywlEZFLMbAcF46ffRWYluK0h1z6QuViyw1LTN6asHnozLaWBt4wP8teusWPA(M1EoONHFVs9f9FcARWqLkloRP2dqLPymKDcBppicLwP6bqxMzkR8gxyL89W8yxIw2w8NY4lltQUa8MWy)GxOsOHVaZ4PTqkCAiNCeB0sJjiTtyS4qqNEVRKZPLqm3HitJSzi1U2fZeXBGUel3k7BltjKSn82N5sTsjZe(NjLqihJJZUVa8jGt372r0Fq1N(u7tYY7AQNv29eog22jv60XZBLEhRBkxbEbWYD9xNCQbh9YrDFL76TvlkoyoUoQNeMscCGbE(qgffo7NLe4pJLm4pE9px5fL(Jx3xEmjRGQL2tV7T1sNWi9NBQwwp7HppR22(RRKSTvJIMmnKSj7WF7kzpvqhws8MsDsTCJhD1Zt(EANdWZUwvDwAfU8vWXqdMJPoadnvoexK30vMVuwYSJPOONDZ9uLWKQ4q3pOIyORURyfd(a2(GnWpJbrdUvL1ttd5(MH0XlU4kAnsXPTHvtRgKjvUmMf6w2Aqw2x7Y91SySjGCmjqqdEGp1UouT4IMfbLFVG8etepxV99P1T5qhrafcP0FRy0tWzNEs7hRGWd5tyTVLCJhtzThhOFjF5MI2wNmC5JFGiTu98hy0vrF(ViohWy0dI64yOpggC4hJ33VC16ym7ypx3cBSX3fD9gJ(mjB2cmFmZrh3cqvo27Zjz11Z0UwiO(QaomdJBR6112T5Gh13N1IHuKmGN)YU)204jTzuRC6a3i)WJGzdez3ScmbR3TS(rEBEOQ)dCdSVK83V43WwRW0TzI8trxX3DUpVS6yyIWhdMUNjcGHyD5A5ztij7cg3rUdv75(3aAHuTDizhwnock2RkFFbOJICJgETYAsn4qxRRkDq7m8Bp3(Yi2m0cfBOWfRH9wNbJbfuFFbgoHtMzMGZoJAKXNkgDcMxjSWskoVK3W7ISr1SPQO9QsShnezMa1wWJ8ZZbw(nWZMPfhvZm(loUN3GMLY5fu(Ap9od)sesnQmqHHVAOqY04KopmuEief7AVs8QNearITcIlLuxatsJKvD8cQw0cqDi4p4fLTUOPTSTd)nVg(76MNol)dYIeuKTSYQ1B6oV6661Ciw4tRo9LiskjmjokGsyxizusUZACn47LH(LHVi0If5Qgkl9l1LZW)LO0AtYU5M7xwFlDpLoDEsPmqu01vwDpNzh8Lkdbhl8wDfFZIShxV(jwKvDmjC(fzy(9k4)t2P0nCZvZAQxsT(KhTILLAJizqhe4d8NGytyAiEyf7LQLdIdIo0jXpWjimW1HlC0GSBkMx2HDK0BRb(JItkBxv22wmNZBFx(T6RZBjqCXZB68Vf2(5A70pRCoipKpV4KIL5pvr3u26K8sIs4QI1ae6rBJb(HoHj0IbRZ8682bRAVek6wVOypx3uoLhnflVOUSQdS1JDh3lVe3qw37tCZ(q1bP((yMicCs9H)N8eEKZ0R6AkQUNUc24zWDnffNv)E649XKJOcuMSKcbDTPdZbn1dxMmom7aRXaPeW)qvOu9p7GSNQsIpm0b7uU0WWysLdoz9comf)dS5M47rZverawZvbmqrJyTMbbPobXKHj4PctLQstJJ5wGcyafCQg5re)UkBtaxqCc5odeXhwD6lLPC0ZHI5Wd2vCJfh5m8GohIZxNyWbehSVB4dCcRvmGzG6laUBzrw7RRRx2bkZREn2K2mRe16N8lIl9hXJIe6ZXehaZuTCdth5cHsk0XvnT1iXhxgFYbSWdv4ngI5Ghq8r6muRdNjrCNs1UG4sGFbIJ9XmP(8PrBnXnQmkmD)RkA7YxTwejAu2)3Pz)FN9dWdb(qYekJB9EJdHXLOA8rFWz8hSgAOe9Vv)gUz72SgZ9wXX5lND(AUd88YURSPT7YnvNuZNnIB2SgyI8QYLCbTfK96IMAkVx)sb8r5ydQMKbQfxTUSM6wvNSJM)EiU7nn0z(fKHTgnnrWEsURBzbyxHFBgxq)IeJogaO6Lnx0negD(zO6dTQqgSQAXvoSlqNfcmbWCNMVwNyvR853Fy4CfHyrb4XRo1QgT4pxzs7nWdygSZG0zADbDduSUfLv9TFa7INDXBE3v3C0Bp5Mlp60tq9jR71qThasYhcc1GKvAQhDwy6oQ9apqWdT254he6cX7J7jrzZ200wJ7TweMXU(7hjznwNr3OhK2WZLcmzv8b4f7C8jEPWYyYZ)uDIyumu8bjGvGWXLnZ4YgZlRScBEwWxAr3McI5yM91NXKAgsfepM(QU8zliJsYjI)Rok(vaNsugMm6nTYWrBaZZGVYWNxHnsnys3kzT9wzKD8CQWdtO0F5Jhe2OZs1lYZ6CoNEg(k6p47xoNcZwYfE42Mse3V5ucuS0KxUefths6glk6jCHH7ee84kajbCkDdtHOSCHr4rc4PA9o)Wb)Wrnf5)qiDdL5AQ8b(aSA1H9e6NAXcmatFTxwxlinYbjplFz5Tn5Duo3Xsrh1kDwE1M8LhnFUiD3)7nfBk(4)b)t)Z58K8v53xCgQYIAsTS5R4jYI5udjbkru4Cfm0fDNK3L)ZfpbBIVY1H)MGAvUj14d64266hwHNW1hHzjy8a7ezQ5d)XkU(b9PsO4zv(qXW8HDLjGQfdSJXvDnpv4mwMvOQ)q0t9QYQbm4z)H6CicEPHNssAAsOFi102K97y)yqzrqyiyhMlKMENMHpxDRA32O5gyuZ(fDeDwEML9JhBT9OLlvazaD8NIs44XYQ5OpTQSkWAhjXCRfkxfk2VFEtR3N5GFMSxXe1zyVzjxhlyiSqms9(D7S8ogUHCecTdeqhqmOtKIC43mFvpxV9D9pmg8ungCmZNpGAC3imfCI1lnmjnjaI0gzH9y6pYcjnOP6Vrp8vc2LxACzZmEojOjNze69c8hyLLOnHr75fMTkVB2c2lfyVKD)IDgJxYJweiJx0j6Z3nHAbrTL1Pkaei4eHlscjulyyWdX5BqsK9oI9CZO2yu2l8KY37Cdw84xuwvvm)QIL3j2w1NdLzb2WXbdblpxIXkur1bIgsr(b7xy5oRPGwfAe8RM3CwnyUd)gYOfmrWfUK9c0Sd7C9Ka8DYGCPACKYBJDvtTnuzHa9JbcKIiW44sM4CZz5tDjntegGhuYJXAl4iUafm1ps)AvSJxvLVg436av9SdOAn0kFePJtxeVp54YQ8pGvWcxP88jSoyUZCMSsh2XEnc546tkfjiO61GE(tRUmVKm1Wo1FuvjWNbo4QoE((hJl5QpmhSsUdL1eE8ozt19fSdYUCEVnY1DV9gSWg9SpeBuhbbFoYQ61p0lLRSxQ0vtnR4x25dQ0RGVbnj02cscPWftJJcJ84AIfu(GH9fhK4eeLaYDO1RyAw2FYteT3up7b2qmn2skT0HBntIPtVeBa6DMERBmTniNctZoFdyv(uH7DuugQUq3pKIGECEub99CK(2bX5Yso6fJCNLErwFlg9yUUEn3b(MjBHPu8oNr9lrJH(yB1LveOjq(g7VoycREdbSlJXCh46blliAyEhjHs9BCQdegEqc3DxGdLG4YjLniesr8IV5LVIsdUIHNcrh7WyMHH)BSM4rxI0tV4m2eC7hXhaCVAtZvfTTWGkstj8bNCg2p9GlnuYwRBlX3Pm5bcSS0lXlaI1q7qbhAtCGJNVaYtwuGMWQCjxDJOKOrs2YZo3h5325SG9DV3SaKrOxhN3hd3Agol4xllqJBYMcK6kFia1iU7j2iJH5dPxMCEQTjDbEC6AICDS9fBAsNloTGysv7jitcNPwdqAc)N28ACm3kpRO9UP6pcGRP4oeUjUeRNpXHDj8QQxT2sDvaP)XLMzIMly4htfOT9hZUM7AMqI3vv29kelROygWyABWGu6K1YTmGnmvcYUSooRgI3JB(qrxsbSuECJMk0F83xuuDAfwaKVNsLbePl1LvkhYf5b3t)gbkOrTnJtLhlAeLhUW4ZWa)b9VsIa93WQgLwtvUcOQ)e5KtirqQV5AQh1IAxHIyfoAg9G4KqsnCbO)nYamoYIOCNUhiAxn533O5ugqMuhZhwe6hdoaIWsMUaiPfpepfvJ6QUKcRtwLRJy3hAwENmmAW7dWoc4hqavTT02psoKFzvF0GF4LfGZrTfOlVGCLheUdDMj82pwXFMZnwsN3)eYFWo7Tflr3nafEgDxhNWzx(llmFBajlYwNKhrEzA1Igi)JMnHXbcz(kaUbf0wO8EHRfnXBY38SR4IMsuD9k(urIG5EYHcJcREAE4WJaX4TZ9uRCgGKj5oZieOeYTjSBw5SHk6vbZ9LqmvNlWgoq4DTQlvyYH5MLIn3CFru(NirByuIIwgMIltK8vAXWrctBlaTqraPiU0nxCGgWg3j7UP3AcxPTKUeQcCnurO49uHGrVfHCy)9i1a0N9qS)8BvhG0ySWj1kHSeGt0cfwFU5CsHxPkobUdsuPUqQ7KosbVmV5gYMc6pLRresie9ODSbf2WZgrV(q1Tk9omWTb80rGTjWljL7tsa2Wu(qqbnG(f5xpLyDTLGhQzrGHjwBuczbl0p0ns21Kg63v6vQRq9kWIEO6jTkAHWeNErUqTPf9ozSW0FPyqvL7ROHDum28ziqIAC6Ri6NbcnsYzRr5mUxcnMcA7okfptvsYIJBa1yHPJagTerHVAACHTfAQ1G2Ar)8qNV3HYuUM6umCYtIbnyVJQPMEJksKsQsTyuFI47arftkkT17liqICFy7zsKVrhjBGLbrmkmkvfoHnmbnbvukm5pQxdQssOpOfjqzvlL0QLI1NAiknu9Tg2qW0tJeGtkBxdE6GhkPqzmO4Lkdzt8L45Gnfj2Mq2b3nxYIyxnIoMnw2H)eCdd89BEbNbE8e8ih9OJNbDuM)3KolLxG2(Kz(laMwolmsne6c9T7wIJhtcH4dN0pRj9OIZ9yVMXJZfwFhAcmucOtZiE4zknsIPXihRIhcBx2ue(076PCfKnHLLa5ujfO8NixOqu5YuuiuTpjKiydket5zd4UD3TS4zFnLwQ9E2o2mQhmyWutWMBSI53XE5XYig24uwqkI6PvXH)udpps1KBRUQcCAP7wmVVQDu9MSX5tIqgVTJIdvTR0IY2legOvfDST3Mk9Kg4(RWY3Og3eqLXEzm7lRXNPm8l2b2dtb886trNp2R5JjBr7uK32JR2xazjutB0Vdkj5c1LVb8Zuflyekd5YrQsfMIrzb89OtTZiL9JfK5w8suhHRiisQGumBng1rtB8s42675hCiMBx0fru5hxUDtgH3wILBB22y8PQNq40bSXiOLgfkz3nhjMnyMlvsAyL1d)0xCVvY(ab0UBvXgQXyiL8T2lRrdEbI8QpRLnG0qdeXAyfrgIjhMXXTBxmn0ezpseJiQkQpV3GO1apzOPJH(n90ZUPr3wcy6hWgnZOLOsvM8dmO(ItrCGLutJx8xN84F6dwqB83i(g7aSgVQgNi2k90x4)p6H4yAleE2ovj3mACWe)fU5ywfjuTfbHrId4KrrXfn0PvytbGf9NLFecUY9j4x1LraMTSJiCsapXDeNKOeqzjRlpZiczVJNGEy529yj)YDcN3hl9odIn)tjKQNFl0psUFIvYrwrEZwDgjfztfvLACSftzVTKE7k4LmCCtRObvszhsZKOo5ivG0ejIuLhmRq3MicWTgBkxBC8zJHlJTKJaT1pXQJnbPYELv2e6NIhn8s0ZJrwldei30zCJu1R8jwJvm7ipz4jzjnCmqB6NA4wYsVQxMob3dOcVIbMcU)rg7c5zKORWm6TTKC)8IUAc(9)GJTsK8HjJoFSaVgnDX)rh21Zl6QTQv(tiERGbTTRk7pwiT4Kcxcb1(HJr4u6Ip7mjlhgWYGwC3a3fhpSSiig8Ciu4tRMJamecyaII6)BMW16Np1NruBj97QNXtp5)JebNvN1OrlBnoTgnOF(hX3BoLjFthw3EzYU)zfA0Ht0Pebgb7jAybRk)ziEpWswVLWeWb7uhJx)Oc5UZWaMi(6eH4w9)GZfZive53WHl2pK3(N13irpsPM757S6wUB)Mio0pJyp(CIGL7AeziAdIeJ8UKc4v7aRrAsbxTvNIHrUazFlL5PvhQ7GiFSInHWc0Er3orIM)seF70oOVxXAosyVJf)6Kb)ozqxBREdfOEgv79IMGCQJzDlH7oEGstej7WG6MkIQ9nCwUL9W6HqPouH6Stf55yhoZOzlzua3yBNh54X0U1dk0KzxD2atCEodCWtNvDZWfTkHgze5A0vYmQ0brEULOu31rcoAdTmSKe0Uupr0NO)DYOl1Xdp5PvVRI64RsWQyihwUAZ6PO7JmB8tbPWC1akBAm8mcfN6SrpcUhDwj3MhU8PnQJl(te0YadaCC1INhRNsuz6WU6CKPifAoEERcaCNXnT9DiW(pLRGaoV1FgKftuk)PQd8s8iKOyFPUwax6N4IYXai3L9rShzNAFNn6s5d2J8sOMwt8hz1KgMgtl0N7UgcVsejFa)Z(T5XDmPW)7(hzqDBRSWTtev(2i1CJIb8zwZHk97FYvx4UkWjrvlmUnHjk5pqRL5zn6yDTxJYe7LJb9pChJR)PXkfRTCUsdbRHrQCn1WpLjZrQ1lBB6CliRMBMPgEK0Zm4K(No5FK9DRIaKRUChTZJtE2OJxBGB5adNOq16)X7Q8sN27RbmpIHAQt)DlhnWNunT0Rozf4ze2CXI6Q1aA4DomKpJjQxkWlFq8NPYuMVavm18)mbvONxkx7vqlkb(rY5kcEjK5hHPJ(vGXNuvUekQyiS6z7vo3dbfEK4eBaHQo6CX4syQQaEfLaGWm6wIAyo6SoTGTNE3Tf9XOfA1x5K8osHNAEvFmXvnYy1h8F855f8xZKFsEcFIYRCKIkEqj58fohW2bzVxz(f10Pqu8pLBRneVI(ZyL(8vmNXiODGLJ6tRjePQPCEXhr8kuE7HqNMPkwujc0)zvRqtwtWiWYAPmHl(gr54OYhYEu7qiwoypI66n)BR6kcr2dleZxu6n9ShWR9)ilcPVaxXzyNYIWPKsw(6AQhGWU4zBz2gCmxFvsHBKu)C73FpwXTMkC0ccbdyO)6vhueIiBXMXGGpcVgyL6oOMRXZKtxQVtKgKp7mKVnNq7N13rQMky2BVO2wEyE(LEL5MiWJRRW9rlilrvTRRhMpP8VZ927OqMJrcC)KlQRrQQK9ToVG3DFwinwtV1E3B0tbFYQgBRDF1u909yLAg3XwJwM0twu1JC0cCYXE2NLWiLlu)0)cgUuvLPvf9S3bSovNiURcHB7DIODnFULsNB60SoilNtDgdt1Qht1Ai96xPDC7gRILsDjwkVR8MiUz5(YUl4olp9SRSst7pw3kwJD4dwx(GKZeQudm5HqmvACtS9KwaaRjuxwNWg0e9EJYA2yni02odIrR4PPIzEKCym55N0tP7ZTxLM6KigVriyp75(Y1(oNCYQR6Z4G(2)ZTqGcC7Sw8MeivgKfFzf42RN9yvs7Uojh9ad3zJD8L(inyhp1BByL2tvO6i9D7UkKUXtX44v9t)As(tTq722zxGxN0DxiRZUNvlG)hC6yNOXJ6n1hTtiL1f)GSroz2x3I3a9YSMOfx3wUwhMz2r0qnvczNQbyhMv2js54yTZ5enB7xIKZUxotmrpDBKY3j63yfy9oABiVf4ay0MN8RyAa3wgIvx6Hwnam2)4Fzt5lNNlU1DrpMhVcAhVfWg0m6JMgwrpVBGCqcGeD799DpKdq1UXBbsfSp8f2hJT1rntuNcBZLf1nl4ynQmJ)vg4KaF30ozpfA2WBQo)E0UmEuyuyhnfT2(KObgKoXTNTS8wJDCua)yC)M6Daobu7sShyTWwYj7UkkHXByTPkB39kPs7SWdgjhbtxskg3d(QG8hZtdgAJeqTTcjy4tig4cLNjdHzqubcqFiFkVC7Xyu2aCVQzEqWeqFUg(Q47XiXJYRcsZB0gSGbjDi4DwpFpnkNx9VRcbg2QAUQt1iqJfqUACJAnkI73hDS6FtiqxvMg3tuSpLiOErGOJ1nljoFr8f4YIvLviY)YOBjc80BwHxluwlgcbm57ttVS8n3VcmtEdId9eQx1HxzTpW)mdVQizg8kHHQ8hXR2pw7qz1dpDZTlZNH3KAEzpIFbMCUEr5mAaqC6dHrvA6uK30Tyz575pa2nbVMXhfRnY85lXMDkHqMQ720G)deu1RfVR8vRxwE3t8JMK1u2vCt(8)LGbyz(QIU6Q73GtB0Qi8BBZRW5GBq2Jf5RRRUPOA2cEXaoq3uUggqy04Z7hxkVaxj)J6kXTSbI5J8923SY8LTVTUsIgz4uc1K0uCxrttX8)on(VKhEXDG2nBAlM37sSe4dLpYRGfM93epYjylq0T)uhUfLT6PoGssZq9JIunZNfxbHap)syBuZaqCVeCRD6jvbriAnrDYn9r09Vji1D0p8)dmb)dxw8yEdcwiIBC16U3wumNamlr8ZWyDXrV5Oto9T4y87arIgIpIpY1lk(HFPUCE76YgS1wsYUblFTRyJW9(9xlHak75R8Aw7a6w2ngVnZqjrKtLRcZ3HS1Ys)c7ajePvX319lRFKqQm(kt4dm48iU6gRnqbU4SNe)opYpzX(R1alGPVkbI4RfbXgXIt9eI8OiZ)l)aSJ02(y(teVTjM(XhYmOxctP9vDn5D5WE5zV8KtF3zi5dNY2NcRVab2PJEv8ZimUryWq7mCRvF)8j0MGNXnHDZhrqAmYQdoNlvayuo4JCfHzF32DaJhI2Oi3Oifgvmy9VIQ8c)CUMs4cmdpKxcGu4(Hc3Xnf4iSpwOkM0ELxs61BFa1teLDl8aBqj7WSfiO8skpwv39i)BBQR(DuZaQqPHSeybC1SvPZ7wakopRSTvOwiKU31XzK13E4SJ00PNDW0QEfPLzEX7RVbheCZb0Vx02v)4npw8udOxLHyD0VzeSrX)MUUgWUSlFE9JWmfhe0Aw5QcqdElQyIvOHGqCrZd3WyFTyWxw22vqGXmXWGFvqA)jq)lEDmWd98I7Kp0iOK8FBdmbVUb0cYf)Mx2)U3NmAIrIydW0DXySaVfhCTUbIXatAzX7lqRnTa7)Y81GksbsD1u8K1hbBjfZSXWtCf4ddcgC7RPAvKOgP0LY71BAa1ZxTO8UUREGrOw)SBMLVgrP65NlOsSQKRRxJxri4BgSnu3SCEVzdQEZ8JuieiFhHG3Ms4fsTwewJ4Iohs3Qecy5KbcAiAZAeQYq0R2c8BX6mt(BmhmNdfiZPgbhDo0NWLt82yGPlIJeW5qX98pJiF6ggnvxOgIRiycyizZDZlw(ERLiEklfZ0tpbaBwF7)cbBY3x07Q7WXGOZCwJIgWseQNUWjC7Fn9ShfnySes1LOA6yxTKM4Bz)7jLXkLx8gEf2gXRCOaMVLVNv)7ilbjlie3OOpao0(Fg9VpTRyLX3d9Fq99mHuFnSOkEVkOeJeYSKisYacVnhrSENv8JiI)a)iUHYGb5le369cjys1hjzs3aLHIlUayKhaO2TpuwzisrhMjZWs30Ube4qHUkkV9RbQbEhpC2MLDOIyy)34MXw9E5KxOWgtjiHruD9CqaiBcngVUEdQ)LGy9CeX3i1fIQoqq5W1dlMzmtvjetn3rfsILTpRjd3Rya6HEPGMCyHFrt99OLCebHbVtGp3Y16ZkrW)DnJZWQFE8E2fp0coLgD0fBNrdoo2nDjEodgxTlCakBQUVPEZAG0VPdSrqWvV1n4HycX)AHene9pWaCCt(D4DkeDhOqMmnVp4r7gDvVa0UJVGQ5Y7tF8ClapBr0eL0AIJ0l)a41cSieyYP4YQ)8k8(Qb1B6KbKS8UFjhyaymnMM08CIEZIlcg8sWNH)SJX3JPLs8TfINAcbBrYRXJdy34akoVrXUQXqZ7rZNJi48Q1qCeiBbJNpQFJGGXZNz4RtC7P4N56HizEk4MpEPLmRddjsShX8cdXP1W(fL8EOUkT3dZYOAsgrEpT6oeiiaQt(7lM)pQRxjQsD((kbyo)3BYByuXusLe4g(H09H0Z461fCMGUkBWrNP3kdZCAY44LjILjQwcFrKSIpMGQYs5gx1J89hQoO0bxOCJA)fvtGJ65K3AWiI2A1CFObrimxq9YSscoIPKoTh3mfyP1ct8FcRLeWTjcbEXp4m11EHXA93yaswCrdH(9acpkEyD(jzH5kpYT((SSQZVvEDpHInSmc9QS3Yymu4yCrIFPa6ud5nHCK7wXusVlEMHr7Cs5D3vodK2EIDyAWL9pVUrRpeUcsPiiY62ttaDRNLxLFp5Fh4xYC8k)0k3ayOTI7qi0D8EOORhwIJT5Gtv5DW2gJUUsGne(Ln1DK08RlwUUO5NG4COc4IbMDiYHwLrk8HW3ncPbY(StpCsqWhuzHZVPaGUaXnq8GoLAllbmRWi0IFzE19ubVbHzsASQ2S6Y6hBLig(dfpDBz1CPubFJzRVq4sYeFb6MVhxE0nYWlU3iWlrceGOZEGWDEwZe40U4FZMSuxlyceeuiHEg(ew3X4I7SYXKHbfKmXdrQEla9bZbq(mGVUI0S2pPtsmJKUvojlcGQ7Ciw7vLZOTV1ffZz8HLa7CR7yJajnqP8MmRApc2UX46MMMg5f45b)fdz3go5kAdibL1avIThs(c(Jixa5CZAkq8F64tynCIAyzr5ShWiM03Ns0fhiSmh6(JAhH9yP)L(kIouKjvmE(3aE(Wxny(4YNUSOyqrULKm5BbBRBLQ(a3U(IMdLWzhEqiVxY68)V8UY6TTncc)xXp2(qd49LFYWUj2ij1gXQ9H(IGIntcHPffSKrlq(Z3Do2L7UCxk6d5ka1xCJpO4E9nFZ3m7m4Mj9vb6mV3E(LlUfq2erVwdyA1VbuRmSaUNj3ab8Rkylm9h3VCjodt1QzXWwwPoedBSs8dIWynByTxcHcWfD9tbmpys6jGHgEwHCCh2WXnDsZzwvPWLJ0Uv837hlkw2036Ab(eEibkiwmFzCV96)PzvnvZ0e0Q53r0zrSLNGgsOL2zDQuir1rcPoJkVVvXe1QXiR(fuJyFPBfXy6QfRxdfVCHp93vVbqknBET(AbTSfgvH6Muxa7HX4KFzLa1BtZnlA1ArQeoS(MUzYtqy)vX0uVXcifUhlYMMQFLxn7Yl)0SlUcx77xDiinZgsd3czmAABAnGTG3Hnsqvx5h(hM9jy9nx8(eYcZhjiDCTKxRWgtSlZlKql0k(aZlMRdtYGIJDyJBoXhYWBNrf7n0(6)eA2ui)QOz7tFlSP0x0RizxKsCekxGNIrKxdBgMB)jtd5vpUPPTzdOqShdd(W0TmBdfp0jcNZMfDHMRFYJWGyW88Q)u9IMYhp9GuAYYXMrJxSCREo1tamheRsY4Knb5aj2M2cAQrZwUS7mRDSx3SL2kLfq3GCAzYO4ggh8OxWimThdmEsW5Sm66fulautQbQ0SMdOCbWNd2Vo4Kmek3vbg4Taq3hb4No2UHPbKn7BH7cKy0y8g3I7cowg2EFw)z7ZGXL(noM6KyySUqpIhw0XEdX(1vDpPiiiioQiPmkoNQIuGPbq4LHn6PxlJdcSqORcidajRvXZZjdx2pe2LaFWF6wpewBmBvuAEC4Wsc6(k2YjzhtXf3rmK4atMTKKwHQby5vBV)b9dPj5cGx)JMUbellpBX8MlpwqhNnCgXIz0yQnm0MRRKeHHB3MJbM2MmyHABT556eGtxHC7PH(kiNsBJz0YLLhBpbEdmFOXqv3FalF7y7gVE8)Zq3Mx1kC)uxBaPgcyCAUR5M784mQl6JgnS5CoiSC8)j4z0DpiO3q4z5FsFBVstMNXfyW6i005IsnlBx218JGuw9E419J0CXq6MJFa2NseE0(HN1G7QW1qmrGw(Rwb4xxlNXuCWSlM6GEQlkqJivL9HzRToQ6GRXcRrhsDaTvBP6LQcQN6gzuPfmWCdJrMKy6yN9VQrie4RiIwhdBYcry9gy1I3ng1QUJLX3Las1zQmSPRBBJmT6lx8HZ53ri2HOodclq4tg2pkMHvrnXYEaqjIcHZwLNOShjGQtGxd94ezZCCGmk66BIOsUbJ97dRPyftweutbXDrpbka0y0oNNmpkpUOOyEsA0taaZHmGwyAUOE7bpXm(XuOm9QyQh6dt1hBcxZfxbgWZNQPI3PR6GaKC0jOCK4(lNka7cXOhCdcWjn1dmeTeuLpsmqczZanif12kAbKKKQqnmQQPoJMOdNrC5VU)7lGl1S3cCMLoSk)tI522QfQ1OSuE(Ww(1l0FqvgYHYB4t8j1LfoggllvmFC4)M1hqFWuE(qAdvC1IYGLzCahZ4KU9r10QLq7E0oSC9dmWxlI7KGW685F)hDR3m)gkfwnD9rbRRznWXSIhIdSBnIpKZBU926LhD6zG)ybvnR)a8zcTk4rqLFrkiBaps022oOSkfuMhgmpkTSiijzEzOBu5rvLtDJK8fqnJvWP5oNRZ2Jat7fH9jsb1j9l)uqft8FQ5B1hD9civ1DYc1oLeOWfmj9BCaqAPo8lIQP7C8yCwZMwg8EccYxrxrqDlOZ(BPl6e0miIQfaUjegHrdC1lqR0TGJ(YXUn55pmMV(c79RjsTpci9aIkXX5M3SzsEOLJBuoOOsdr6Ejq5yIkeAiYphweznKSGKrK6J3CQ3)qD7vDnl3SUx6kzLGuHOJTU(G83Lucjvqyrk2Oh1ci)lQSBIAVjFfX2XEwAzAsArzbKpepH0bl8DrjLf55LrLY(RVhy6P(cl9waMb(TKiHphXrjbPbLbX4CGBQ58tpm7LLV(WZpQAZx7BFw)KVckyQJJ5XpNwryAf3wFdKjPli9A7tPNc51tz9pxgveLE8Y4OWIOJxweaD4)LrzjGhPlJfJQImXxlcJdcpEzsssqM4xt81OukfRdiXlx3NqdcgelUVM9uMpPo7hqhoVR9wT9SPc6clUTPE5gJVj(4u)(yQTdUgZIKQ(bFEX)oYFgK8SSNcMppXFgD9vsR(wtBl84lXcUxrqo4jfOBtF2mdPLSXRdKFgeBG(8rsQFR6vdtrfiPdPrhMdWGxlthLP)p(eorEHPuIwa9IddWCSrWNxi2cMaFaPy4bKvTq6gujVrgyMJKxDE9dDnRHIIepFUwRrSr3DDqW1Fq94omT7eqX4cSQ(qdFiAn9bkncKx3jC3KsdACEat8)M7RH(IlKgXI)p5ibEuQkBe(t06z449UgE26xLiFfOB(bR65OMlBZAedG1bvdDDSpjRSxQPz((Chx3IjHcHx1kTRjinpjZjd4o98OyxVuulP1qU5Z7orqkP5N(NA)obmNQHtcJ6dL)maJIsVvkF1)4HnuWbnzoJhLldQc6TR8(FTmHU7x41eIkByE9gN2PsZJyEktNhoR5ba248l)Yf)9L)XSt(eIISQB1JTlEaKbSS6RTDD32k(GX)qyxISv8kNnPNnC0knb7JjXj5rXzzhJxUg82QGjD0Q6BGhzyva(DfRh31W7EHCUtCkq8BG3RP8aXxG(C6QvcQNyMpQFhuH0ev8ifB9Lz)nNgNx32TbhILYFbgU1(2MPh0mUQ9axKa8IHWo7ehGbX5iyM9OFP(7vhDgCNnRp6QhFyv366FLUCv4fu8KtNDXF97Yl1gLSN8mnWf49p0D)PN9zmDubym2wWNPHhL86XvrPz74rnnePTEIDyYMd9)VJ6SD9OE)CTo6GBToPkmPyxFWEFClEyq8b3IDu1o)C9(3snSdpFxVwVxcNLTRh17Fl2XvP55hCNRf0uYsoah1HbPhGJ6O0YdXr9HP7hzhICZIYo8iIl4MTRbZ2)iPig07A7w7FdAquHdVLAyuxCaA3kmyxVdF)JfEu1o3HR9Vbn4Nz2UEh(EjAw2UMp6(4OomyxZrzFButboaQSBq8oOMiceDvO0xUCdxwh7ECduiw4AeivUWGOA992UVUO1rXP7(UBFKk5oIhM4)(V)" },
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

-------------------------------------------------------------------------------
--  Wago UI Packs API
--  ExportProfile and ImportProfile already exist above with the right
--  signatures. The functions below fill in the rest of the spec:
--  https://github.com/methodgg/Wago-Creator-UI/blob/main/
--  WagoUI_Libraries/LibAddonProfiles/ImplementationGuide.lua
-------------------------------------------------------------------------------
function EllesmereUI.DecodeProfileString(profileString)
    local payload = EllesmereUI.DecodeImportString(profileString)
    return payload and payload.data or nil
end

function EllesmereUI.SetProfile(profileKey)
    EllesmereUI.SwitchProfile(profileKey)
end

function EllesmereUI.GetProfileKeys()
    local _, profiles = EllesmereUI.GetProfileList()
    local keys = {}
    if profiles then
        for k in pairs(profiles) do keys[k] = true end
    end
    return keys
end

function EllesmereUI.GetProfileAssignments()
    return nil
end

function EllesmereUI.GetCurrentProfileKey()
    return EllesmereUI.GetActiveProfileName()
end

function EllesmereUI.OpenConfig()
    if not InCombatLockdown() then EllesmereUI:Show() end
end

function EllesmereUI.CloseConfig()
    EllesmereUI:Hide()
end
