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
    -- CDM: skip during spec-profile switch. CDM's own PLAYER_SPECIALIZATION_CHANGED
    -- handler will update the active spec key and rebuild with the correct spec
    -- spells via OnSpecChanged's deferred FullCDMRebuild. Running it here
    -- would use a stale active spec key (not yet updated by CDM) and show the
    -- wrong spec's spells until the deferred rebuild overwrites them.
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
                -- corrupting iconSize in saved variables. CDM's OnSpecChanged
                -- handles the rebuild at spec_change + 0.5s; other addons'
                -- positions don't change on spec swap so skipping is safe.
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
    -- Note: _specProfileSwitching is cleared by CDM's OnSpecChanged after
    -- its deferred rebuild settles -- not here. CDMFinishSetup runs at
    -- spec_change + 0.5s, which is well after this triple-deferred chain
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
        -- Write spell assignments to dedicated store
        if payload.data.spellAssignments then
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
        if payload.data.addons and payload.data.addons["EllesmereUICooldownManager"] then
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
        -- Make it the active profile and re-point db references
        db.activeProfile = profileName
        RepointAllDBs(profileName)
        -- Apply imported data into the live db.profile tables
        EllesmereUI.ApplyProfileData(payload.data)
        FixupImportedClassColors()
        -- Reload UI so every addon rebuilds from scratch with correct data
        ReloadUI()
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
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_S3xwZXTX1c)xXp(99azH9n)ePO2klkXRiDIDQuflWzajXvyaMaGru0PY)97zPB0Dd0ywOwSJTsvPm1myA09Pp7R)7FQliBvrFo8hjzfBkVCrEvrTZXrb)4p1fN1TOTOO(v1UbboAFWFV2lmY5h)p4VU)X1fW)52nvv4V4JfTDLn11(WJhKTmNwAxVSn1vnl(WBYFSztp8jXz51lUVPTd)w)S(827k6FwEx)n5TWhfj(KH)a)fn3EBxr)VwFeS9G)xyuqAGBGtKh9Q6kxwap(PV7QRE35Qh)xGdtGBuOJFk8KH4E2li7zND(1l2013S6AxNR9cttCccUo1v)vdBl6XAAQw28qDN(wW5yhhh3eFxNWGOK4q1oWp7Q3DH(R)O4WJt89DJCcCGnHlUdCDZUTbF)0Xw)LgYFH(7YfpTHPHbHjPjb49I4Wo5vfKECyIVxIxqStSJp(M8ZwB(cIYwxL)yr7iakSd9d8dDctct9t2oa9Oi6efefggh5g7jor)TI7lxuv88pvACIIZopVS(0CJ3OZXWvX8he34i6qZ3Weiln75V)0RVO5Hcd8d3y6ZFwvEx37l6A20UOW8IcrvsIDCDJDnUOSHQaywbWZ5g4fgN4YylJrdmqr21BFlNrI8bimyCGPycssGjOcke)TS68vKBQtQBCAuk(UK386haRxohfIumrUoXUXXX(AyCbzV55V4kdS7KJJdD8cycrcGj34FgVNWS3)6x(kJxu8Xoj(bProP(a5gtdHKNB6lRk7F8RaHlq3ce5bEXEbWBnqCDrKNwyuzHWfWMG9SISsNnHvgvtzoLa8MICt9dVo1XG5KnY40JDdd9GlmacvCKZ2iWIjWPVRxAsIxcqGHauNShkx2F)559lUNzlBW)RZoTgCpquGaVBGiFUhYJ5RjaCDdqRX8(1y4RrXBDvzCG7lkV7(EEpZuRRVpVgySFAZM6LD)B8KfLLVCztnkRXd2TvvfDRkAl(5xFYIEqwfUTXZBC26nD3xS8zKGHN1u1GSACbjvUaLMB2nOCrhKCWn7o4Vt8tP)Uf(70yIDRBQyn(5UcINeTkVaEVHzsbjpF5DfJ)Ax4(KE3N20USO9YYFROMErEzGaXlA6kXnkUldYGTRpTVES(iqU8XaPAeqPg6LIYCtYAlQUOPSUho2p75V9QN)(Fca3Rh9jUzFQ21N4Yo8JjX5WQhjw94GJJrXCEEO0eegCilUtG7XPapCcJKPECZ(F2uSP4Y(8(neehpcHaUyqk8)sCs9IqK2d4TCuKB4XXWpom2loeUpKNbVViqOJSaIGtHPKo(Iik5yqeQVFStAycka9aofaB2JdbinOEquCaHirxejYdHFkWoFqJJdfg5MEmO6HBquqcYAyy5dhUcIoWlxw2fi87t9T5cIOn99n1dB4yu8JxOBAiWK5a3WEHS(fAm7hKtjFbEoe3zh3qVWKyKo8aG3iPlFz57eLghjyT)86fapJ(Iwa0lEpbUEhhauioH(EEEXh4RzashpaxcDp2tdD9G22hfe6DSdawbIrPO2tZVtTBpcuy6PtlffcOWrrPb((KoGWvCs25LlAB0FdaQksSMg5MeEG8BokXXJqJb9T9tzjQPza3G6ffAVc3yFqNIdduFKFkXim13fWiavwiU(xuGIKgqzs8jyFsCCQx6bExEuqSlXPvOt6WvBWarKhBuWtIBjqqHuurgcjiPaEhtcFsZUhKZvHY6glIaK412S4LvnpWgVHppiM7EWEiuCBz9DNuxUkNeGaQubl1MUItRk)TFlVD5zGbAO8pueL7Wcnr8KBw3)AtEBXRxWlINJA)CvXN630wCfyhynAkgiZsUHOpJ2)XgNSNMSvytuuvSOhKsc7ynmhnz3J3mjzLWw(F00SQo8yePcvqqaUu7cuYUpWhqkzpw83TWMhnyu70(zOCqakl3ugEq2hl7EfCt9QMnDWnfCn4gMDdPeWvG5uFOUORdnY((YA4RgE832886IvpIpURWcI)oQ7wnALoQ0aXn(vKUr1eFR4S6nREFZdD89raCFa86ErtDVoyGv05oHcpIJpSE0d)oP93IB5fvWg8Q7BB2C394oji7dfpEtz9s(bblVXvd0BI2m8(J2la2qE1d5p2D59npCk9TiciCYxw2LFtvXvGn39LRPp0t8SauAzrnIaNK1Sb2mVpV(UcAZlaC(eo)55ahlenaF0ie((U6QhFDnySnWNrSKS5wc4dTnJKB(9dKOOuXNNOuDjWcCCPBpRO4semPAJcvgLAgI76FHbEmSlDGQb)QFv7RsZU5UNxJWQLiqkj7EgbcXL0(8WSMpw02cF4B1V9vuJ46UBeGqDGdFyjmfMlZpX364(WxHwrpgQiKcR9Cs8k9GsSIlVpNCFuDtny3EcIKs8yeqZqj9XBBUIUYymIv4DSbwMp)zJUmmEYFLGPXaGt)UXH5kGk3B92XrCFYNAgtPd30mB49)A2p7U2MhoRSf4GHSI9Y2SMomA0w)c)gs0FdIBteBgV2wDtE)0lzt6bsKeYttsol)l0sfsWoCrXOPAREu2kahQary0WGaJIYVdLH0c7(U3JmuyA9b49UrFgXyGViaQDn4ibEjEdWkl3gNuH2Yja6AiYmgcrUHxgnpCH2wKrdzEoxa29b7D(rLqpKPJ2bmssWQBUgGFcSvkQblvW7kW047H)9VbK65vM7XlxxuSeb1iAuCwbttI3wWMiV9Vv2vEd5HcWiS6ca2AyLLD(tFXLaeWBUphjat5ycyU7LaGry40DVfw17bZFMtNDM)2Vghj5s8UnVxIecy(ckeisNTRGFMfg6g86puEY2X8pqbb21)qigxXmD)y2ZcahwsnU9wPPNWSFg2B)PID)8s0NLRpid)lb7D7sCbgO)rGR)i1zm1zK4EbIleQkRRkGffjfSE3B()MC6tWay1xcgsTf28hUsEkbdw9dMPoUiBU5UwyfagjcBgch7ssNJdH2tBitBICmn(LJeby43Q)Br0MnCT9v02mI4P7pHzagAvShY42Mbo2rkSjJtgwP)WBHZ3L69xbPE2ubCoJC(6kUBlYF)wBPZizEZQZ43gbF7RjowuD3q4wy2VCHWPRFvKQfYbPSoWHuO2UmUX8LNvKfWTnsecXA3XMFAkgCIfHV6DV)1)J392Ro5nZ5agoa)JdRWNjyzo537wjaZZJnzCtS8EKB0)gjt3NDuZt3Cvtz60YHoAzVmx97Y0hh07d1RLFxM(3LPB6AXVlt)Td(1w47ZVfgZ(LsMoLmcugv8nsaWNDeRSf0P9vaGn7P(ggWknNVTBpRpVWQTOO7SXUYMvJMRJHhlT48W)ljSuZ7PYVhxk7XLI4A994sXHh7)UJl1bgHAPt9OSfZgVXV4rRYhteJph1)dYUUl)JuAIS9RkMpW(kyymZ2uLRZ)C8432IQ1mXS0s4Z(A6XVTil5Wepmt4ApWGwDO2x8KZEHdiGwi)X)sgqR)44AVPEhNZzIVT5VWwJKfXz7GIKLDfUTMFdpTuw4ZmwwgjMRTOjpERkY(SbZFoG8yla)TFoYfgfQhARyJV5(lqyscNDGcxjSHDM0BBpVhoidgSfD(T4Tu7OFZAaXHYzElspSNEdBrxJduiIDhhBruHiR(2rIUXIkMlxI4SrYmx3SMgB7oF3ejpL98DBEb1)rlT3MXdzFDdk0eb02eE97SadlHbIQYOzY0blkKRLYZrCYnoJwKprbgwJcTrmGIYEFX6Vheio7CL2pr1aY3i)N9zNVFFpPiSNj8FBs77dvm63tfW)eK53B1dBFpakdbq5GnH6qsg8NOiXP(JXmH)MPsj)VSmbWSAa)m387oDf0CD3x3CwCuniUFMC)zyhRhARWNJDS29V5OyE9f01MFnYw)XzDmxTwhKTSZy6UEPQjkTlzbw91SwTM3009mOyhQu)NCU7Zzi9q9)Pv8A28oW3JiMiIypHu3)RBbB9hbRxNMaEcsUjLRfwS4Z4))zST9BqbB5AVajhznRQi7)ZJqpkNoOIx)7X0tRi9(Em9gx1X7kLp(Em9(ZEnj)7OLPFpMEpLYq(ZkMEy)UWt1DpM0kqch6FgYIOM)fATvRZFS)(YfxvUI6vFsgevB6U6Hg6tff50n)VyTW)XIXnHaNJ5gRf2KT0AXwuHRhL1TUQS)YkStaA2bp46eK(vI)u0alafWZBfLcLOJeGvn(7KVFQTOiw4xK31pzHfRl7tqSi65(zfQMa2foAAxu0DXI(lA66cZEZjN(CSKa85VfeZAUnPDaTld5nmUG(CpTZJkNDkMOWVJbtgBve8HBxJkn3Llc(2Ipww8aYnkoRhbZxWGCBPri2hagE3ca7YI8(7XxWRRVQSVQqBLE(Nwx2wS08Gqwyshe(VO(GMO7cqRvN2cHAovEx9jvv4TnaMeD4pqbYMH7bntr4ZnHTCABr(hWwWjZOD4XFz(AUjP5KDBB(QcrhgjAGFfatqiW9Tffs0UWSUHMKdaMgWlGdyE9YIL1KX5WDh2UqwMx1uxa3QawmOmAb2BO(1ApN4J9uD6hYwE(7(L6erZ(COV6HD4O8BVT8tAhnh6ODYc8hHhPuTBlCVocREgKVa4xbxsa9jVsiYcC6g22S7tqybU(WtY7a09zE(kG4ZAwTUQOF8DlPTo3L7mXt8cOD)pVErZQY67Uejg5wZb1Avcmija6bvJoebQsKBr)zXZXCJK3wCEZsSFG82392NtlhJuoQlLa0lQnO4pjSpQ3P5bk1lrPWJhSQNvu1NJ9bgUv8H7JHd(5LvvLDflAQxsT2ix9Ja(Mb67v59WT8fp)9yh1JHOl(GMdQ4R0ZiKE286E4Me(SQLQl(OS2MhqKwYfMmPoJGZK6omEWRXgsi3Jui8ee7HO5L8BGV24wh)DW97oZw4eeDxqK4sTWnZUH4BbAO1v59fuJsmaiQklQxw9iwTXNvCB(MQE8rO7z4acqgGlCp1sqWJZ9f5v93)2nRUb7USyFjQzn(aCBSIoZXIUaj20EuDEeq4XYYU1fvypScozyxJs23efcpEHyR82lEg1QQaBw4(n5pxxIuETBw3xEtvXqNpXMSasSaYLnmRQ4wAZps52Lf3S52BXg2G2M2x(Uesq46edoEcaWvnRbecIxpcEO2fv(M28ZG)p29qquivpZb26LRw30c0Pu)oM6BxupeHWObo3na9iV7EjGVaiub02f7jG32udSodZEnEMVnFrX)8KLlFxD3)ut47)CvXYY8)j9O)tGTgGg29q(JhF1viGZF4wf3RifHSRcDKNODnXD6drVeJRYoSg5WlxerL72xdTShGeTnVC555TFq03k9iEYUz1WlqVLfbIYmWz2j(kSglwSFnOiMycHN4LhtfVal9AQHbpUNDrT7lfdoUJEQA2vn3E7v51F4K7URTzaHkHZWdILym1VezbEUjCd1byhZO7ghzmzcaXkRk5(ZgDpl7RNgyA0hgKnGm)(I8LytTL7JpQxnONWGOwUXldym6uImMgERbOH)RnfD9N3CdbQv98gVOP4GdDBmgpmsh9EN3u2qQFtzDrhVtK09V7JfTv5pkKmbkrrSbVVS)MMpr4B)c88IE0csFtmhnoqQ70NVAD)J27JC20lHGvjzGiRYBaPsdq20ev)C1lGrkWR1qx(AfuraUNOnYqxyDGgf((eIu)Y(8fFy)WufD(wevvYpHpYWBQPVVz1e2s(AeyOgMazuZ6wKRlXhMy886AqC2n5yJ3w05N8jUue6QR4VvD)jkNZemCVS)XkrJ7l28WO1OVgWUnyycijIDIIppbo1x)DI8qPGx9hEvENjfh1x3f6GOuW0HBH7k2VpJvltR3Obi(gKeguKH6myzU8c8q5V5naZwf7nwsdYSuHiceQQ7QjskiXhkLmbDfe0N8oD3WdmGLao3E1z2C0Uj5wOhWYCoSvaWiLPFbkN3aWWI5Wd6U3HGcVdmxnWicZ(a2taH)VrJfJfPqTqmfKbwewgUIyC4cxYsg41QBPfU7mfNAXuxKHPtKc9x(3i6p(3mzT6aCQr)Gt1QNDsuiGY)Mwd4ZzlrLaZjM4f4OmYtt)zx2SrafeW3Ftd2V(mr5Dv29gRq5X(ZnY8cXkqcTbfcq99lxwCcWbsElG)ktzFdnGesfsz(Psu9OAlYMHn8DaMQgDOwlsZZqkgBfMefvZUgq)wKRKfgykGnQ(RWcljMYUr3aK6b0nnklqTX1DVTiVD)bIafajyHh3edGgUTOQZaqN0qWYEanDogt8ODqXEwtfUqg0WFTb7anUkQVcuP0G2e21luALsehMAwmQvM6PWJKOF8Mtjwh5YP9UJamj0qqTMllzP4iwPJy)ljaK6sYWruvmPc7aFMhlAf2ezOoIsvDQz)ky0R5se3qMwLaOwvypfhjidQQPXXjqPVkBVJWIl5QOX3NnN9KQQZiD)fg3mGiR9KXKgTKbsSImR)B1UhtTzFypsyOSvlcBvydY1q3gAO83i6VQJ6ZQaD7y7g2nTHMr1xiSbxzEZiDrvurYVq0BH1X8nUInqjh1U6uIane(6AWSqPwPOZwQDxoA3nXSieaAOE4Vkup0QnuKAm0lb4VQmntdhxPPmI8VBqlFDC568fd9qYu2awHISsBHal376BlxxS8Op6rkLDFE39OcW7(LimjwSI7(5JYyJujH87(XJbLhBlEEvzp17Mz0zrNtXKrKsLNWHT)ffTORLQ5oOH6Zn6WSdMgAyFmOoXapBuRvm14r1BnSb9vsRkn(PP6hrRADJ9846p82Mrm(vY8zV4nythY)uP3GOBGQBzgBScYRmLOyhz97aH)inMKgDo4u7aMEF)UBepmBU9GzBGiAqS2yTHh4qkT)tkSbFFcKh1TsC29nD9LA(dXrjrGBDVSxNj31AJCAKpiD8CJcc9d8sds0SCoXlo0Z13pj2t8XKx4stXXhtssOBk7Xf4nifvmCLZmMDdfERLWwkVTCb5ZesnhD7S00TW4oGt9vwEo3IAfEuvZWed(wGcZe9d9g8rrleMDhAbhqMReIGJXM1aj9GCkLukLn42ngzKkXS2VKdaiTUGB4b1U2uIDGOflOTJslbqzeTdWiSo(ai)qrHNGSQquCR0lJCdXaRsqKwXM(28kLDJBrduyFsbhrPVonUoeXYqHv55ZiNXmuvWaLjP4RByLOR7fdcVzFht0tdSnWuNhKSQ5Blw0k7oEgHISK3Eg7zRzPR9kKTYEqAbqO8sUNetnP5nR7uObOz5yJs(es2sk1o55Rrm2KWxuBgmg01WvfsxCWURHD487lUdWSLVw56kEXoy3Tu2PGnAxv5K39j6runkW4W7EpAfIyLv6Dq(MLLzUziOa53qbl6M7uoR2ieitAV1Y9f8oGTo(2oLEB0RJDZnRJiSUmOd(E87yVvdMHxb8szDFM2Jt4FbV2WQH8vPtg(ocjSjpFqQBFdgtJ19899RR)ii(IiS1(jaG7y2cnwfOFUMU64EVSTCJZsYTHhpCDiGP8KlopAVkeENer898ryRXK9bEx3MlMJq11GUUVahLdWXqdVvozYetAiDlFtZa8DqIXIpOoqS3mFJ4ZzZ6VRnFj2qQ10Y1l7UflPXCuE7JVNWpnXwPkBxQwk131h1GQrFarXJt5QN0H3eUFIIDD8DII8Dc4jFKQBPXclLB(tq((iuu97zkg5G(JNgaGPuLvv4TTVxyqQJBAKtCc73nJJZaWivm5a5OWXZANyXaCj2n0LMudhYSFbznXBd6A1nmkjYloi0jfprJiln2tdNrbAdJdJrcc9(DN8gGhSH)A9rHiatqVQWtVucZzctIwIr5uGogafKg7N476gett2j2WQbvn0EZNk4nHFpWTT9dCiO4hxS7OoDhfFjrfeAC04nGjTV4XfJXbwq7ZUphWXRWvLy1OTjEjR8TfgkOEM6HmabjiSKuxJ5n(YNDMerMjZhWm5xVc0iU0s89JJb1m8Jit702hYvwHBYxmIOSQW0LDsqpx5m0c0WHwo0lbixPILpF1Amacx2NFNKb0WoJHJcoKd42mwpWnusWEwzlU)07wGCSTrjbWHvTp5lbg3eX)dstC8t9eyOiEBC2DfalgwE92BiHW9Gkynjz59Tnlk7FCmbPK8eqxrxVtVJ1TLRaok47yR8rnhcjJgqfyggRMJAcMp6IsLZZZHXecLddSbhuiwbUAF4Q7lwH5HGWo0bLKn4JX(OqeLw5OKarjKHGLra0)e(wsYnsyAAbLdaV(232i5xZ4IdRdswY5UpFqyz3dSez(hdtPuI8NI5Qs27G0BCURn8)enEsH4svFtFKejRfh8(kaFYlCGkK5AZZNvMl70XfNfgSOYzAWgeHLKgpNMmBfDDqq8KT58uPOZSK3WgoRC4tVyH00vRAiYx)6Occft4GlORfp6hm576I82(Y8kr2eOixbvKO2LjBp83uQN5jwyrWIPsHaD(ZJyb4BtIR3F6ckNt0imOzl83wcJPs3g0SD7egwrX90qg0qXSGnQH9YsfgLoF6sfMNgWUbowrFpoLKhofdEo6YX4VGwguQWieayNgBM5q1irariVVtjr966xl1lKzuky)BQP6w5)BGsluczF50dA0Ab3nbu)Zd0c11X1NGFIKpJhIutSud147VLxTPORZjBcMSnfw9tXzhxSJNxStiU)pafwJogubpeucWJhQRapgwkIzfOnNudn6oAUod4bRlxlDQjVxwCp6HILOQv08LwCXXI3y0sXld(PVZCU4y0fKNoSKgjHisPYphvAMmexDXlvy91omPxnU0sXJJCqNj3VikNqKVvZQhoYmU4W)K3jd)tuMwmpOaBAwOKIpV0amnqK4IpdlenkBkgRxnrwiK1y3kzlcMyZRSqzNGqazADHxFks6uEScgOBl6)tZBaztrG2zTD0aU1qxk7tVLPDRh7BBTCRCKHYKNlUV4tWl25zN5LE2mkxYXN7zLTlyNx6LvkMCBc5TyEZHM4OSdEWFguEueMLtj(ycZYxj5lkdTGEth7m74mCQXbM(cBOAm)(QuBq)xCs8l4KCZWyF4mGks3NV4(ILxr0HGb4w3LdVmpwptbGz77q1EkmJM0JQT0lO)Nv)pyULcZ6BZlR4riI9zF3ya6mkSXrlbTBdW5qG11mCco3y(u33xvaQjpxbezR208YwksjoJsoK1LwMN5S3oKpOCKdY3S08ctpofMpM0urQYgv25P1puKtTUdCe9XRaTIbgOvS0hnwmaP25x8MF(YRp5TND97p51iAUotrXOCK8qKXKO(NRl7FbMeZeeLJmaWM4DyWN6Fuod0MKfE6g2bCc1Mt0JhS2hIA9UCuUgMj9Kxx8cDP5BknWDty3e)P6GuACW6NKItxyM7Z4zn9mgpmz03Zo3j0tmlKdCsinfXxJFIpnELdCbbiiFW99TOn075tHlnLwDCcIGnnhWOpvFKVlpoHDID4C3yFxF9Cdax(KdCW1sMCRnX83YM0x6Nc)OKekT123njGcQcgN0lAEuyapafrOTkM5tI0N7XAVesVMOyFxFh2H0aWmYXLgR4joUUbK6u77(0pBDbNcBiOKYJ)dy)DeShy5DysU01j1XHKeO23yerL5RQMZu9fjaHinaWuiLZikSebkxw83VVO(11OJE)ivyeEaAElYRf40SSql0nG(vOlJ0ghRgLNGlxEcWrfFkH)oeUKBAZJBUPsPiCyCoIv3xGPfma8AVhJMfGZRT2u5wm4ve1zINnSUIK1fJOK(a1uSg)A9rIkSaFGH8rg9qVPtzit)d1aTNGv7HktLa1qRREKZgefiwdks59VxM3syDy)JlZF6DhKBoWuYNxlxRNcj48bwmu(HnmbPovJrRm)t5GSPl)r(0ALeabZxZJXt(hmcejokKpFv5qOilfWSrr)geUKO8h3skvlQAPHza9UHjGm7b0Cb6LSmvg9oPjV6acPuesy2nfvnpqYVermLYDa8IM9e9PY0LXjBv(NexQIe(1LbSc9YfMKobGojRTfbrctow07LeU8GmpPSWurie1rYP7CsMeVMxiOnzvM0FswjbpK8vr)PWkyj64o9eYn(6bHwGnnyXkVZeNrFIoXxaR0jLejU3a0dJ(jFaFrzvLzG2J81YClTmamIkSfmnJWKtqInTBSaXwgRGdLRvX8tH26Nv2TgOi1yDmXaUe8ULUP58wxhTsaiseRMkQyCm44mPaoM6FbFHWEgwpXl3NK2usJjUzifRWukbPJqOdErlyjtbOvPzmQiTq0sGQ0g3n4BRumYkErA8PC6It4vsYObgVk5f6C6gjfrwPhIkuXkZblS(185nRzRAyfFiIuStPP76DrpLzkf2t7c1uWOdN1aCcxJOnA5lhMq(Qe1psplb5KQvxfkBbTWI8hUCyMrepxcjllyJ9KSt4o4jyWTapJKvDt)nu(KzmP)0VybwtCmSKm8feo(4pL(zyOGeF4SunPCkKs4eJEvY1vZSkweQn5otRxhs4IROggPzqohFEl(cWdZnltycNnadgQWYpTgQIPQhOs4ftrbmxcDrW8wc0IR)gwAMcAoO80ebEJOqdi5qs2vgjlJAJmM3iLQ)3ZsfGBlrnGYQMAYA0kHP4hBrPt2e9QICa6966LyIpHrnwKzeJ1Hem5w(2nU9bHlm6hdGMqSYzLXRRXGw8ihw4zN(XBJ)6KlKHDQwP36MidbSfnHW(i0ifQM6UqE7UhY)nLf7OOng2xduldbWEwPUgoLuLEBQIqiAsKy9W8W0gHGAqMBx2Rix2PaBoopIi0BX2f0)Q)gQ2kLk4l5YJ25ZI5g4Jm1wcme2eU6u(ftmbGQzaVXOIMZD(dsFCC4YJcMX3TOwwNt)yoxLNrq38MXmHWrOwN)4tH10HtQr4uDDhe(i8NkxBXw0ML5DtqyTYKYd)0tVZWRnaEF)ndBdT0G9POcQf0oZQyG4hqOnMw6CWAoQXWXCLiKuobQzdp11(ap97UjbW1pJARoMJgMEMAgBiprdkEl)aniVVIdGrfPOlHL)coaheQL062efsOUKvceqWsMPcwNYwP5ffwddw02uZAEPoVWb2t28wRTaTbBlDQlzQttc3c0O61Gd6c3hs)Nz8FXbPGSfZb2P5IEKzUAAiZv3mhZTlbL(0RtjdKjYbt3XIiX8xwunv0DPnRY9IN5cB3R6Cg1y6rH5m7Kf0o1StfR7bXuAMoZ5LVDdf4mV811VhmQxyJQK)JvTjfySSslsvmFtdND1k3YqmSg(EfP8CEub7W9d6HmM(FqvydggdAOi2s7WNm0JR58SD40INMHhOYJg6DX0krSLeOnXCwoBXsIVaMmmNrFwSza2b8UrOs0yDF3MLegvnhzq8aNASnwJLl8u9onXY(dOveGInBhL(3j7gasB9lk9bV(FemPa1hCiX6Fk1opM3aJ8R9EAtY8cL2Btta1EgHWoTLoyVHTBInCWgTiQRpIH2GelzvJSxw0mNdmPCm1GgKTgqq1oOJIGcFFSWbBqPMR4xaFo(vXqhS0qmk1dHvcJ42Pz0)xgRISxT4wvR4lqfI75MH5uPQGwUQHcXl6BPTzUfOeNQCNXRq0bnOChZB3b8XuHdybd7jhsDybp5)EnwZIzzt4tyiGCFmxth4dyLQiZ9NkJ4MrVVds5R5TFJneIbDgQ1pouiklSS7(QD1fFKuUIcbsRh(yXerlHP6WSAu3fGc)nSdLznTZ0qg8yZ2hCdYNHfOkp(OI4NItIEDmtoLyK1Qilj2vmAwooRjSZ6o6req7WT2BXpvBZo3zTp5GSE1MjAZK2uFbn0Du85v2qoNnNjSyerqrhKHiAnKCm11A9vBno12TrBuutf(jwZYqb(Kn3rmtaqsm1hwZIUTyc5uLI46EeZwrmIHuKfuU5NZXaLV7fZbhcGCYnDnT3GX45j7eGjwRZATOa4yiCjReNZJyZzlp5LW91pzwCw0ip1RNDhpPiRUn7HrhsqquUiRrZIThmTjX52QTRy0FfzvZbLbk7TI8Bl7xMhPCRETID4Yep1SFj5Gn7rhcc14yMBfd(WZGbBb(AC4QSMbsBXkw7kgTFjyWqq0oe9(r7ghKEbQIjKKmdrOqqL1KZzgN2bM2mocdAEUIltumpiNVeZNjRMSWMCVcM8Ki7S)bx2AcLnVWvlXIEevPOANpKiuBjLJMpkwUZQaXHAaZyxJAp0mwJiTfBFMvZIVfz41(fe(DKGFmo9UJTfhPETWAl0PDxoyZcBVzdw0(fwFSDInoUzAH6hTA3Q1xg2w8KsPRdWHaJ4Ps571tnCCB1jYhEwEnBUOU1e9A7zZWu39nVAoBN3RkTvgNPQgbXFSTNZgkRXPQ6Cbset1HPQWo1kWDzukWPAVY9cglMIxOwmaNlGrhMPN7mVogfrZztBYVeH60UwTBlYq2m3KyZS)AbFyPQ728VHY3e7B2mT9iUEajLlNzPJYr4VGgO8uSs1sSHTLW67LZUNK(oZzs7byg60OOoKS1IebvZ8NzZTPTggX9X562sQWNCI8(1XP6wDGZmzE2wmJE7QflscVb)Q(KcaRzY7XPVzt)fS1LhKlC(Eg6AjP)SLd8pP7jZjRHlNHUMnBaQduZt6Az5RX1Ad1WzeEoyWukUl0qosGZYdTcnJRQg(lhEekVTXAT0wErGvrNr)bd7eUyYQ)(IvL1llAjt3agCn1DBwHBsU1Hj2WWF7LjBzw5BUBvrD)1TBOUxvCwp2sh)a)3CjtIBzGgdpzHzpG9Dj2XaL1F4XRVPcBb44d8a(aCH5TghdoIz95ny9MsBNI82(7Rk)i)bGrMGvU4pftPW8LvyAAMK9aCaUDtl(pW((FJ4DLVADv5TpY)0KS2Y(IRZx()kaMv5Rk6BQVBdUTrdSGVTlVg3daz1df5RBQVUOEX98HjnBrB5AybHvJRty8OCkEs(hn1IYBxmWpUCDXIY8QU32u)Arf5IBjuR72IBlABlw(3P1)58Yl6RnxVPRyPwfWkQ9j5p5fWbZ8jrh8bxbIstGYv(OSv0afI2HdVTxGqn9FlEcWwRCfCnQqa4kT08thg5bu3OlMAH2v5ydVH1ZchtO4fRA6jq4FCftFcvaWe0)UQMhWHvHOzYOQ(54Sg9c3eqZrAJl7BZ7ZHJZ5p)Sx)ZNJV5hfTTCpYySuAfh1lFPgCLyUdi(B5OkWLRlvHJ9PmBZOZfikwC1XLoTFsRvPBTCYP(ckLqmCX(G)7DuReeBb9widwcFEe49GQGVJDcDJdJtCvn7aanoVCjvckSJyqFWQJfQ3wZis68s42XpR7diXdOwk8d2GO7Hz3VIBowbzRA6FG)22M6FdjxqQSwIvZOzee1w76Vh4MCEzh2ZU5NbB4ICZYrRQ3NU7iYFfdhyB1SIi9ww8XMRPU2i5r1Bk66BE46hkESfiVaQp6mCtZTI)BfZRP7(8Lnpa7uCrq2LLRka2ADi1ktLFdSrlA)W1ihRfuJ4dw8QsSXnIfXnTzXhnnR7Xv3u20tSOOQ86w5p6)mTf29)GJsIRAbwdCQr5XdxcTpXA9MhXC4PU2v8CZmzSXhV4(YIpwGSGXUOCv(AGVHO6TAlWb9G6JIXwucHqAmgC8HfbJa2ROu7s0EYWkv8QnTapl8qMs9wq(FF59L32F5hkxZN(rJqhKets2LQ6j8bClP2p76f5RXIJF57eazw13RAwJTswoQap00wHJml9dZVb3SgFeoHJQ(OXNHnETEQVkECabZ063C0mrLhytQHzSaUo8nkIvSDS6jBsNQJHyAJb75IfQLrKRZDFOSwbdJ47zQvyqf)3q7UkG7(NH8dyERntpfa95SSn(5kkNzU)7WDzJ2IQlAkbuGOmCql983BR2HXAmooru4007gXU4nNTAwbyjkqx0A54oHjjE(HEPbAZ1LuhT88xolqiDEuDqtNJLh7PD3srhmfLDsKleoi3G7(7iUWWhkOk42nI4xrF5R7lwXAorhmefGpyQ2iO43s9BlQxYaiVADmtZ(5rcojSmrhedwaAo2Wvyiw7DWFIi2Pz3xUS40QYF73YBxkiUzLlGfAegNpJNAouTfiVdTCTbKsQNggqL3iiEuoFUu)yrgwRok48SdiNpFtvpZqNAfPWVx2uLW69Ea8bp9JkGUfR1aAFmCHehgzgCr5GftnH4qdWZHpLB8nIZecYzEb(81dEBPsuDu0eq6CrBZD4mxc71NxrLJUHkQNxwxUkFnPhkonA4)2EuNr)3ZXZRN6(eAD5mBrIfD6r9GJF)34RoceklAlQNUPheRigTx6dRrEtWFnJqMM9MYBo7uSQ0CDU(0n3DjW2VwoUHqmKN1MFBpio5DyTFrcG1BTFuerRpf(r47MhRAOA4yySbLhHFpl)Hsbm4Z0LrYKmWNszQSS(RpIB6tW(u0bZjSfhcB9KLlBWXFZAqTA82LlSQHVrCUXpvSfeDkq)mxpSWUs5PUu(IE0cbbOMl0zSs)6kXnIOReeegr92GNetR0r)ysPPU8pwS8F00SsGAZ94eav6FTjVLlmBjWq0uYpMAag240nPd22TOfe)GRodwTWYcB8wWvGEblJn6DaUI)mbWJfrIYUgU(m7PrJ6rwwLpIu24A(oszmZgfkXSnaOgBAxcuYlk7ay(OQqu1ZNMThdItlGLfVeZXoqViQVrIFW5IoIJXz9xzCD(jioDa(mFEXT3qrkZKEIPe0ymZHss522IIZB(iI(iAuXey18kJJu1ZWdj(qbuEDWM9MJiXd4EuLNX7mmH)pR82Blxa8bXXxOTwqmFUr5ou8pjT3I0B6tW7ScNGMNNxNFhPahOiXYvI(rmO)vBtprW9QIQ1f6JkmxwIaQ(TElWG1McmUtkRaFcC54QQ1C5gA951iMlWCaEU)TT8RN1GLBGUtkqeZgegidzt)7U99513jghhiWjoREZQ338qNSJF29q56HUXnQKHE3Ukj7dfpc2LVK6SVcyEZguhFSLFymqrOItbBN5uB9I5MqT3C6FZYjg6UNI21WtPHEoSNulj1aUXLuRpeXDuoqVPWapzxns0GEBVtoTiNz2ZrTg2t16i4amxaig43AzgjORgHzYwJDPeUVRiwgJHUH95SaWKHfzmmHqe9gjMra1r6gPVHoaNvDYuSJp(6rNAiq27iIfgBYOrESLAGftGuMuXuTgujTHBBTW7GwUGTeMtaHOupRwWBEzrxoyFaoRyQF2zK5Lyvpb7ojPiS7gURfkcQFafkqXDXzurdjEhoDjhELMvcU5HDOWYeD7kJIghSFLweaLUN28yd5uO2h59kcQDvZqnJqZkx0zhMa4rm(NBqdi6B(g9VltjiMYd42WNaBsakMofQSAXjWmBwow63w8QcpTo(PAC1iv6gznqEGjn7JfTGXY5vADarM5nroPPCMOxzlqKeZ6wd(fd5tNbD3VWJglPPKnGIVRzonQBCr)r0I(Fc(JCFfuRPNjyEm0ErrojgD4rJDMr7y(Ny2JeJ1oHBMavX(pFN3TvLP2tE3SLQIyLrm6et33)sYVooBtFzf1AY)kYTw0JlomM1Xz)SCRD4SQbE()UZQwd2(Dg1FNrnRA7xALShP8ile7pjQzZJT8)kYQERnVBwtBqdE0SWVm8TjZVMOK9wyBpvxoHk2HzK1Qpf1R)sXZ2I(ZGcdBtJBm82AtkC2LAcfUvW5dr9AayoXiKDRKTf9khPN(HQ09VVAy7KnXda7J(1JNWhADS7pdnR107BBAwpVLXMUaXUzYMUaXUfYum5W5Vl5hUPqiBwnB0MWftTszy2zpKj6ajCa)ezGHWY2TyX9oOloudYNAnMf6GbJXFbUx)jcqyELpJ5UIy1y6iibWalbRlr3Dd3TQwTWSUZcmOCySsYjYg1izdYEZZFbkIg7uqO)rmmX30dVwyZy4ckdlcNYHHN2DpCwzBbn)Yag6V)1V8vWlxZrtEIHgWOglOjtHHHPbvPYoIy(kqb0mmEIG0z8yHAq7QnJiWHiPoQLrWFNZ68XBgd)aHH8xdxDykhy8Pc)em6qP7VC5K0HW)TA7VY6zoJkO02WWzihexf7((eE1JGBdfVC3M1RXys9YND2vKX7ZnEfMX1RQGnOnZNMzxyZlD6oL1ghjSxHsb666GR9I9tssUoieNKUpjMtZXxuFOnTT(GNf3WDGCHg7i458giSlUObj9(HtiVXz1BsZloqXKcdTfdarvYS6C6Pyyw4iShmD2LIm2IYKjJOXbNLc)NM7LGT)ifDwxuSK7)S774UAS7YfZodtxKVvvtStjBqRpRlbT05mTPsOoI2qfBRRg4oD5UPcbw5MAck1h0Xt5cngUpmOypmNhYtzvtHKjz3pnYkiVOrJKsZm4omRU4JfTwcStz3lXzC8PuBIwiphqOFv5YLf1)GWcG9scNiqcJv2MTXbt1NRVdFteLfyvHcv1HCe6xI9V4D5m8UwS08fzis2CdBeVdjGWrciE2zS9zwf0)uefSpQGA4qzzKA2LmGHKD46KR9cJCt9dVo1X9PkeygPt2YBI5voDoTa3FXbK2ttJCX20j9II2UM68k8IZkvd85Bn4z7tOkTinWk3dlCY2PoOw9nUnLEM0F1SijWESuEIIb8Ob(XyTq3UyG5efTFscSkqDxIq)8LlyqbYAWAQtYCsfmLupN)g2BXbuCINysMUPwhESK(ARmQIrKRdWjknXji460NmJOzcMTDnWTgb4zlQPrbhMTA8WIFTD8Z5zpbiwVP82IF4YCS8fSQV6CinwTDEAsuyIb(1LP0286MwStmjD(YYrYASa)kYrYu(9wKJ85ZeASs97WtphIIQhK5Y6Ne1mRWwE(yWyIs7xrM7ZjBVrUXYLBcNevQKUKhE0SPyg6XihRrUXUh7fKMgLgK4fWjz4EN2Zh55tZQ6e)0qyjePMSi(PhWe(stNXd4xj8d9WaAk94WeFFxV0KepQZVFiNeFlL6HD3aiEFUr8yLk2XlX5aHBu6jndF99gaWfHw)nQM5nLIT0e3BXhkOsurKqDQuClHNK5V(SU)DTxIx4pw775M49J1jo(H()yTxuaM871(Po(jrW)nX13X9hRdccCIGhd(VEHCrh4WzGuN(emhD4JOTniWYVYYiroCyyKR5lUqE5gEEQenGlrWKlyrfMJo(HWurdVPvZJ9H5(8wN456ZQwmJ4nEZ4sW20OrTjcf0W2JsDqQjKUEtvEl6J10SBQAAwwbuBgZzFqIlrakhiu8q7d75KgV2ZZ)epTIWkCB83OauYHeoMJ8PbUUXjoj(eHBi5hpgsX)TSHvsP6vC2RkABk7WUwL4n0P1h45M1Mw9u4Ho4qSj7ggbh4YYJyd6ENlynbofJrzZado5QXKGfnpERItuxL4LlzVcMy)WVuRhIq9Wb8nRxxB8l5sCACsLSa9J4nU4FWWg1KKCOsThJcWZHvvk(R7aAYVpZ5Qfj8YQ7tUCWVrsL15sKdVEuurP8gx)dKZUFQOa4xVjgYvLaHin9Fh5YeBDwCozjLfT3mT)8HjfDSaz1EAtY13hokX4k7YiLHg7UgcVehLS45inmkjcyDgJoyfDvT6INH(GQDiYMCOqjVR0gq0b0GYWpi2ZpksoQ96kQkw0dS)YLNqSqSOClCDXcKo1nZHqQAlW6JGrMXmEcikGNa4)6N5f6rvF5Q81Rb9kPSd2ySL7rRjqkOktbkdMVSQPN29PYhG2gtRLs9c6c4)I3iyDVqIqfEnX3HIC8pGq3F4)xXDz)Wzyr6w8dxSPDDtxX)FUWbPks9KND1R)Bpx(AOw3ReiIAj8I2Mvp7SZPmXg53jGrNZhp4jr5rzXoFLp08jepRy5(io2IRPFFo04vD0x5t9F8UQ9ZCDc(l3P2llk8R8H(pMi4jFLp1)Xeb)R9D9F8o1ac(F14Lrvgo1leqnS5UZQOsdjLspPRtwKLCvIJI4VOTb0cHA(gcHEGUgxVQeuZIY7aufaFuAofJLRZP1OyjTGDxdQnuuS86p6IfbkOBp8yTfRA(i8zINOVreIMflVMNBOEKYbxJTWJ1xdMSDDvznyI21uFya19W3vBHUEzzhO5tFz9g4zWiLxq1URXQuvCx(Ih5x51yOHuBh(1ilvqyl0bld2khKpNyH44iXBYRxuvKxVz91F0h7Na4ivVLgxFu9rRhjioz7LafXZa20ehK4Ggo66eg8J1H((jG1LEUoGaw4)6e44M8JGbo(E4)01pkaEkFWGDp4JJadyGNXlgm10njimg(PbGfOXSADBXhgt3jh5fa2Scl(rHHU0YgMgqltkNFfyIgz)qKg55d7GeWsycVYAAay)N6I6G6chn8psHxyTFSRlyoe3itORjPbGaiv(TWP9h)jTFdOSn9VOLYNNF0Z7Oal3dr(Gv8aqho4rPGHM85EOeKSV5pYf(r(U4u8U2pWp0lgaBHHP(ONaIddXRbsLz6yCzrpwRTmDgQgnH8lqeWplo76UhRxG1RR8zP(5YOyxoDV8)vCNn7g1WaXXFv4jaLXF7EfUWboHexJwuxGkTeKw1diH4DN5JK44K4eNLL2EPsDt96yp2E(9FShJgBOjHhqMdQEprGNfDZ0NpkjAHUeaTJqts0xh89cInE89JNWiqw30Paml)7iNk4m(HMEqeXANpR2)MTmWxrE0dsz8oAGZ5h1YrADlXxEvKm5gLzyqIGCbpMkjsvOCdYXKszetvMybYxj9DQt0JCbasB)2txFdfUKAe9aqSe6I9xJMogVCanfzUeHes59GKQhdxtw57x2Cjp2Gy)2f8axoB1RUmkXjTuMMmnqYuhzHcy7j)XCjlYv9yP(ktL7OO0j1O7rX9Ht(hS7(uztfOURsFKP04MAswuhY7MqiMhAF8Nx)XPUN)45RFtUvSxrbzCUn5Ya)5ZxPeE1Lp7OPV7XN(F7Q0X9eAn)PEbDvQWAbvVgdPhcLtyezRsoSoOFZ01EOjGGwGpS693GwSTUCo8fjP4fI)W77aRtZhTVj6ZQ0bGMuRGUrRnUzuNMr5PK0cMOXe6O0nwxaYnnlPV7DRYiolsTqEQfAT0xwj1Nw26fjFhYfuJYkelQSZ7hsT2wdyIJvjtvDAkV17PVNjfdUwePp6DRzsCULAMuvvNcw1lHDe7zwo3rYZxFlIvO0kO1OcSJNvGKerYcRghgGEZkTRehc9RrNbpiBHWs0ndXOg2c2r(XDfl00IE5J(5hAvkp)(CqwdgXirkCmwJb6ICYJCKNG0I71TwfvbpgfcHE0JHyIbVGtvL))kAoQi3XHM9DgnOr)W64)SuoZWzwJkzjvypgthagWrH9SN2bckK4JbGOEvvaTzmyRzui3Gho)l0L(jWnha45FKFHWqX67eiMs1OCSmSxLiEO5Lh3IduAhHtELsyu(d9m4G69EgHzANNIQN7vqYBXopfdSU5ZSbDzY(mswUwxJRTPXi4ARXLnN1JNIDmvWChJUTagUE0T3owVl(3gI3nouIIJgVEDFojD4gjkHL5D8(HqhvwioK)iqGmYHJBpM35HAh)gCoW4JORgtccTalnnG0Ld390a8N48unyr6JgWtLEg51QyEylsF0X(03F68LhRK3tzEBd(teSwLNVdfMfX7YrAnTcnPEf7k9SJmzocygYvo0NY7B0rCbkBdhk0AJ4DraWsCszmG5hEHvnl6Je7Q8KZJj(Rbui2Vr46gLn6cdwj9PKKsiHu2bscbzwGWRcjuhCS9IMZlS8MtO02eRUiJxpE4UHhxU2YtHhxbkaWvcSyJdUywVq5z7xiQza63ptQbPpc4)sGCb9iBFkJseoXGJIIo0RxQO19fTLB0GGMKgg)Wdv0sQC6bkE8Cs8v5PDCM3PCKpphUSe5yxYbVk0Ric5xP0Vm(17iUNVC6YIuXmq5(Rlp1jRWs7htkP4IT4)9" },
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
