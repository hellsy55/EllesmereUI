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
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_S3xwZXTX1c)xXp(99GyH1bl(jsrjlvwuIxj6e7uPkwGZasIRabMaGr00UY)97zPxbAmluuYoXkvLYuZGPr3N(SV(7)yFu(DLdfWFKMxUP6dllQlB8oAr03)J9j59l7klBEvJFuKNXh83BcIx499)B8xp8W6s4)C9M6A8x8PYU(Q2MMq4XJYxvqlTFq(MM62LF8nfp0Uza(KK8IML3221d)Dw(lE)jxEE79LDW)Ar(qr3nLd9(j0N)86I((3x23UPBzj(dBV(6(YHFb3KW)lnXZ3pXpnjMEH9vRkHL4K3DXfV7m9t)ZnpZ7Oi458JcIts9dIXnVVF(FR82QL1LV4xRWDL6DNKFwrvZjfDtFHXlIYI8J8weOFHH5x8UZnFB(jlWDxSxyg8GYx21Tl30ZNoZxwCo9fMVkF6xNfhfNMLgH3fIJ2K3uu2rXPHbPbrjEjEH4XkmFT9lyr(66IhkToma8inmmmkm2lonolmDhGVfX4ZlF8i89eeL)8tp7s8m1E3L(ExgeNL6ffDzMV19yi)yTT1RAVVX6CU4iFVWy)yagv(mpJRWjNZNLedxGAycD)fkWvEEr)WvfwypYRstOkCMrugx3GUqzqmg7RWrNKdbBDlW7jNvVJ8888dcWlujQAG4Oof9X1jLWF0h0TG)W3R(zEz(jzlYqWQeDzNeepJUsw47L4NKKeAGMgL)Mx8YlSO)spkj2liIjDikc5g)Z49eN)(x)dVY6fLCKxAyu2cVSqGNatLJ4FBgQQRgE4PhZKrmL8HsPxzats7aV0bXoHNT)yLtj9sbkVf(zHXxM5zr65IWp7i)44a42cap7GMlHGLakywAAqQ)3)VXJMx(9vRgU9SIHL3IS2hrtmdB7rqKEfyaUDiU8afmWUDUF9icDfQJLWdN)ygb42YQBUDG3ZmJJ13w0aSToPDtZQ(FhpzlYlwTQTbLifaBQ66Y(7k7k)PxF8YbqIgU7WZBs(6n93wU65eBVN3w3I8D8b5z(azMF(vOGjpKwWp)g4VtdZO)Ud(7SeIbTFMyn(P(ss8gTkVeEVX5s2KVy1nLJ)AF4(KE3N02TQS7dv)wzd9IcYbUFN32xHBuCxgLdB3qAF9qZZaP3hbyylaY04GmuYCAExz95TvndWX(5V4Tx8I3)JWDY6rFIF(V24hsIYu)ysOpS6leREs0rjgSRoWf3lY)Oma5NWijPkWT1)ZMYnLFyOyydbXXJqCkXu0lioW3l(apcpBrO3rjzza)T44yVfSIlWzi4jbc9mhGOjQwWxelspce6ggM4LfNIICpKlcGCmgHbHzlsIiej6qKkpeHzaVC8QineGrOW0dy1FMF2rrWVnArukYAqT8XQRGfic(bSKKcIOwC)6qxHGiAZWqBJAdNGYEcI9ZIj5Ch0QheZAKyWPxP1M8fe4ftyn(XbXPjiD4HS9jfKWlRqVfzjewdqP9IMLapJHYoa0lEpr(bhfbuiaIzqqqYb(Auq6efCj2)OaaDnojijMyFCaB7NffhCKhawv6oa62uCJE3(mq)NJIGLhuwllyXbc2xedOWlwKffgsAncaL08ZQw21A(gauv8fKTWp9Gjwt9ci0yqBYWSmINqwoWnOzzPXRWpjeuO4abnHzeJWSqFaJa0xH46FEjk5rHYKgsW(0KKSGSd8U8zrj(eNwHkMQR2ifruGLYDh2(hiOqCWfwcjiPabhrcFYYVfKZvJY6glIaK411U8hQBVNnXdFEqm3TG9sOS3QMBoUP6UcsacOpfSuB6lpPU63(TIUvNcMXHY)qru(QfAI4j)8()1MIUYxVKxKap9(5IYFDytx5fG1InOLtaLKCdrFgT)tSozpozRWMOSUC5aiLe2XgyogYUhVzsZRGT8)OT9UM4JqKkubbb4sVlqj7HaFaPK9eXF3bBE0CiJt7NHYbrOSCBz4bayby58oHHVpJGFX5xrAbCbya7hBk77rBXVTQb(QO8pv1)k4M9TTVOP8UhGRnqEeB5WFhvERbnMh1AGyh)ks5OgIXvsEZM7EF7998fse)MFzBZGjCG105gHgpIZV(1(Q2n9acf(AHTEnS)U42U2n3Cl(jr5FS8HRQAwXhNFM3lGEt0EH3E0wbWgkQVV4H(pCB79NqFlIach8vv9fxvxEbyr5q1A6ddeplCQxv2GiWP5TBaq27lAUPK27IDuiHZFwbWXcrdWhDbcVExt9dVUbmph4ZiwsgIjap02CHCZVFqenLk(8eLQpD5bhx6YZjkUebtQ2OqLrPMH4U(NzGhd7Yuun4x9lgFvw(v38IgewTcbsP53Y3miUHXNhN3(PYUoeHX8YxtnIR7UV)Jnbo8HLquyUm)iFRJ7Jqnwf9yOIqASNZiXR0dkXk(WTfKtMAABkr5naokXJranJ147xqxzmgXD4DSfwwi)zJUmSEYFHGPjaGZ8UXJ5kGk3782XtCFYNAgtPh30mB49)Aom)MU27pTQd4GHSIdY3SMjJ0Ca(z(nKA(ge3Mi2mETD3vfdtVKTPhirsipnj1S8VqlvyZydfhlJvFr(DaoujIWyGbbgfvCdkdPd299Vh5NW06k49UrFgXyGViaQDd4ibEjEdWkl3ghxJ2Yja6giYmgcrUHxgT3FUXwKrdzEoNd29b7D(rLqpKPJXbCHKG10Cna)eyRu2awQG3vGPX3c)7Fdi1lQT3JFyDz5keuJOrj5LmnjEBbBIIU)wvF1vK7jaJWAkbyRLvwU5p9KlaiI3CpEbasFuzYXCFfamcdNU7DWQEpy(ZC6CZ83914i5RI3T99YcHaMNwHagY8iO)iE5wS5pu2XUr6pqzakvjmKP)O5ZZY(ulPbJENKZt4ZpdNT)RIt)8cZNLHpi((PGZUBHTaVZ)mWWFKMmlm1yrOkGqCHs1xTQaouKuW6DV5)BZPpfdZ1qfyi1wyZF4k5Pfm40py264IS5M7UHvayKiSzOECljDo2egpTLmTjYXm4xoseGLFR(pfrB22NW8Q3FrBSDmABtClgYLSnlDfMxQMlsuxs1CjH(PYMMz0K5Bc1aEfADu)lPqnxk3nN5lFzLMTfXRFTTH5pxI02xJxoCPAtuJheaeN)ZNlC66xePAXCqkBI8iTcClJBmdRzfzbklSqecXg)XMFAlgCIfHV6DV)1)J392lo(nZ5ag3Hv4ZeSmN87DReG95XLmUjwEpYn6FLKPhYoQ5XBUQTmDA5(MmDB)u(nz6Ox0(MHQ72LKe1Z3KPB7W9)Gnt9RRmDDgv8vsaWNDaRCf0P93OoRyYrO)FfdyLigA7xyOCz13wueE2Ow9OKg4WdI)hsyPM3DLFlUuUJl1wfc8T4sXby9)mIl1bgHAPt9OSfZLNNEYJwviMigFoQ)hLFzFXNO0ez7HqK5dSVcggZKmt7)CYJTIa)BfhXpZOAntmlDe(SVK()BlsuS)kROA5katpjrU6qdx2xJOAH8h)MdafP8ZFmglmnKjCot81n)fgPb0iprqPyMZKAzMiz5wHBN53WJlLfoCV(zfllReZ1ff)4TQi5ZEmPXwe(B)CKlmkup0w5ZjZgCWg(afUsyd7mP32EEpCqgm4ke9BXBPUr)M1mIdLZ8wKE4wsXw014Gt)bxPzKdrfIS6Bhj6gRjXC5seNns256MZ0yB357Mi5PCNVBZlO(pBP92mMm8LvYXeb0UIE1FWcmC4yjQkJMr(GdfYns55fCYnoJwKpsbgotnblHcK)IOeJ)B2lyKaGFZEHTMfCFZEH)kKfC)5jHb(M9cpMuC(Z0Ebs0avoCFLcLWNDQp)T8dtwfqpTrp4qTv4jX1rFlPNfL5sh8F5A(N9A5xPYB5BXsgtYODNFyhSFIoKkE5rQ3)H7AJX(hzlfn()HLuu2fg9N5MF3zULrum(YM(2Jkh79Z7JFgU0laDBYNJl9ChQNrH))jmkpFjkCPXP4nx4QhKB9MXlMM1wSOkxL1A6xYYwDEV0TN5hWHQBWJwSoxSiQkH2OoED5O0VLCaIKd4ruktFzZrG)m4iVP5ISGKBsLRIn5MzQC1zCZ3xHAx13DTIB5ypZ(nY)9i0Br(7lx)TCwNBMayFijiq3DpM0kqIv9pdzruZ)cJ2Q1zpmCB1YlQUJA7Jsm96n9xCFl9PIU4Wv)VyTW)PYXnHaVJ4gRf2KTmAXwKblGzGRRRg(qn2ujT7GhCTBr)kXFkSCfK6u0jkDzrhjaRA83jF)uBrrSWVSOFyYclwxUC6XION7NviTb2eoA7ww2F(YHZB77JZFZXN8cSKac5VfqSS3M0oG2LuNCIxWqUH2fqLZo1ApGFhdMS2Qi4t0fxgqi55iu92UsUryOk8FztkB8o2Nlx(UYpvvEpgwXKC9YCFRRs5h7yaQDP4kyvzXWT4w51nxunuxASsV4xxx1vUYE7qkGrhz(VOoMMOpeqRvVXcHmwQUP546AeVaaOIgbiWFTvDJziPMHqeE1jDLfFeBfLCBIq94)qXAUDQ5LFDxXDLIErYcL5OamrciLiOX59Q2PdaMuyqWbSOzv5Qgs3v4wgBSiRkQBBkH7F4ga4vxIDrQFUjnHBbJYUSN(7(LMaVKJc0DxnUxivC91v)QXrZJoAhVexq4izvYGrWnha6b6t(7rKfypR2mSnd4jmJFsEDrlldc1GMN3E366YHX3yKikUl3zF7her7PFA9Y27QAU5diXixpUuRvjYIKaOh0TFteujrUf9NLap7nsrx5zTRW(bYBF3BFbTCmQ2OUucqVO3GI)KWPOENwaijtIOGhpyvpTSEOa7dmCR4d3hQd(zv11v9LlBBwrT2iFZJa(Mb677kgaO)5V49yh1JHOl)OHvz8f1PeQmRt5aqucFw9k915I8U27rurY6EMuNrBzsDpMw81ydjK7rk0TpItW08c(nWxBDRJ)o4(DN9HJuejwG67tU)XUBi(wGYyDDXqj1OeJasLQYMv1pGvB8PLxxSPEaFe6EgoGaKb4cpqTee84CBzr9WTVDZDxH9JwSTe1UgFaUnwrN5erZZe5vP78iGWJvv9RlRXEyfCYWUgLSVjkeE8sXw5TN)CQvvb67XTvYFQPcP162SEOcKFPza6qwajwa5YgNxxEnT5hLWARkVAZ1xJPXPXMgSpGFxcjiCDIbhpba4I21acbXRhbpu7IQytxXPW)h7EiikKUN5aB9Q7w32b0Pdy75I6BxupeHWOb(XTa9iV7(baFbqOIOTl2taVUTbyigN)A8mFDXYY)5XRw9UM()PHW3)5DLRQk(N0J(pbMvaAy)9fpC0fxGaUq1TkUxrkczxf6zbI21e3BKe9smUk7WAKdVCrevUBFPAzpajAxr1QZk6(OWlIbeNw)8g4fy2YIarzw4m7eFfwJLl3VguetmHWt8YJPIxIjIj17Ph3ZUO29LMbhlSu6LBqSX1xFrrZhp(MB6AviuPCgEqSetO(LilgZpLBOoa7ygD36iJjtaiS4UkU)Sr3ZY(6PfMg9Hr5kK53xwSc7OTCF8r)Qb9eucqdekHybvzmn8wdqd)xBk7hoR9kcuR75nblMIdQA2ymE4ct07DEt5cP(nvnL98ors3)Upv2vx8GqYeOefXg82QHRA)vcF7NHNx0JwqAoI5O1bsFN(I7wp8G7(iNlTniyvAoiYQ6kqQKcYMLQ7NRbrmsbETg7ZxRGGF4EI2iQUWQIgf((uIu)ddfl)4(HPkApUiQQKFcFKH3u7Wq7DtylfAqGHAycKrTR7qUUeFyIXZRBaXzxvGnFCrNFkK4srOR(I)w39NOCotWW9ddpulACFGXNMhgJg9Lc72IHjGKi2jA(8e40C93jYdLcEnF8vf92uCuByxOdIwTrpIfoqElX6FoPSLjvhG4BrsyrrgBYGL5YlWdL)M3amB1S3yjniZsnIiqOQVRMiPGeFOvDe0vqiOG3P7gEG(YhW52RoZMNXnj3c9awMZHTcagPm9Zr58wagwmhEq39oeuXvXC1cJio)Jypbe()wnwmwKc1cX0qgyry5QAIr1fUKLmWR10slC3zlo1r4OrgMEl0O)Y)gr)X)MjR1hGtS6hC6w9SxQgbu(30AaFoBjQeyoXeVipTrEg6p7ZMncOGa((BAX(1NnkVV2U3enkp2FUrMxiwbsOPuia13VAv5XarR8wa)v2Y(uLJaPcPmioevpQ2ISzydFhGPAqhA0I0cSKIX2wjrrnSwb0Vf5k5GbMgyJQ)kSBsIPSB0naPwHUzqzbQnUU)TLfD7pqeOaible(OUbDZTfvtgaMKgcw2k005ymrxtOwogmffQWfZGg(RTyhyWvr)vGkLw0MWUEPwRuI4WwZIrTY0anEKe9J3CAX6ixoJ39catcne0O5YswkoIv6i2)scaPUKmCevftQWoWN5HYoHnrwQJOvvNA2Vcg9gUeXpMPvjaQtf2ZSuvZGJtKwFv2EhHfxYvXGVpBo7X11Ns6(lmUrHiB8KjKgTKbsSImR)Bn(hrJ2cypsyOSvlcBvydYnq3m8qJZ2Skq3o2UHDtByyu95cBW1M3msxunvK8le9wytmFRRyluYr9SoTiqlHV(wml0Qvk6SLg3LJ2DtmlcbGwQh(lc1dDAdfPgd9sa(RAtZmWXb92eFoI8VBqlFD8H1flv9qYm2awHISsBHal37h6QwxU6zFkGuk72I(BrfG39lrysSyf39ZViNnsLeYV7hpbuESR8f1vduVBMrNfDofBgrAvEIvB)Zl7qxl1WDqd9NB1HzvMgAzFmOoHINnQ1kMA8O6Tw2G(kPvLw)0mZJOtTUXwECZhFB7ig)Az(SV5u20H8p16ni6gOMwMXgRG8kZik2rw)Qi8hPXK0OtLtTJy6997Ur8WS52kZ2ar0GyTXAdR4qkT)tkSbFFcKh9Tss(TT9dvg(dXtlrGBDVSxNjNW6ICsJzr(vlldNgmPPX(zgEzpnnijoWpmmnjiLTDcv(kYlWFruCyuqwe8X8BqkQqDLZmM9Jf(GLWwQUUAj5Zesnht7Sm0TW6oGZkmwEo3IAr1taz5gYGT4Bbkmt0p0BieFocZUhTGdiZ1crWzyZAGKwjNslLsBdUBJrgPsmR9l5aasRl4gwP21MkSdeTCjTD0AjyFagH1Xha5hkk8eKvfII7KEzKBiuSkbrALBg6kQ12nUfnqH9jfCeT(60igqeldnwvqiJCMWqvbduMKIVUHvIUUxQ8Zc77yIEsX24LS0FdFBXIwzNSZiuKL8Uc)VRoLUXlq2i7bzfazYpWzfh1IM3SUxJeGgLJPh3XKKLmQzYZxIy2ddFrJTx5rhdxxkDWb7Sg2DZVV8gaVw(ALRR4f7HT5AzFc2Qzvvq(2NOgrLOatdV59OniIvwR1b5zwwI5gvibkUIgGsxDJ2v1wH1ys2)j3xW7a264B7e6TrVo2j3SgIW6YGo47XVJ9v97U(6AGtkR5Z021j)l41gwnKRkDYW3rmJlfLFDHyO800akoY(SSyZqlgLJ1dmgWRB(eiqtORgfoIg6MJB8YUZAjhj0bE(GBagAkp6IdKX2db4Pli(BHiW1AW(yEoW1cnoe54fAI3khYDIjnKPLVz5a(oiXy5hf)A6keptVr85Sz930vScBi1gA5gKFZYv0yoQO7H3tyO24RuLTlvlL676JAq1OpGOOSPD1tM6nH7Nfj(EHElwe6fXt(iD3sJfwk38hJsjqWO(3Z0mYXbixAWGPuv1149DyqCuMNF2cVKu2VBwhhfWitmFb5yRXZANeEc3fM4h7ttQHdyiQqX9G3g09QF8I0fbjrXEz4jAeHP1EsDgf4nmwmgji0739YBaE8h(lnplgbyckwg5bVw)GeMZKMe1eJZPbDmakkljmn03pkHMStSHvkvnmEZNi4oXlpSx4qqXpUy3rD6ok(sIki06OXBaBQFXJlQPBwq7ZVTailRXvLy2ySj(bw5BhSuq9mndzacsqyjPUgZD8hE(PsezeDh40iHs8RxdAexAW9FscOus4cY0oJ9HCL14M8fdYAw5oz8dKDsWaF5m0c0zHwo0lbiFPYvV4U1yae(WqXnm7gJDgdhf8iv42mwpWpusWEAvh(Zm7wGCeRrzbWsQ3N8LaJBI4)rzPEHzbcmueVnj)MsGRilVE7nKq4EqhSM08IHU2LvdpmMGusEcOROR3P3X6UQ7aokhIKv2DSJ9NOEoQjy(ykmvoUpvJjekZeydoOqScC1(4f3wEhMDbc7qvkjBXhJ9rHikTYrjbIsidblJay(j8TKKBKW00skY(V(632k5xZ34Q1bjl5ewLpiS0BflrM)HCiMYK)umx1sFvYVX5UM6)jA8KcbM6Es3irsolo49ve(KxOIkK5AZtXvMl70XfNdgSC1dOGniclPk6C6YSv0vLK4jBZ5PsrNzjVHTCwP6tpFP00vNQeWx)MOccvtySztT4r)GjFxNx0nuvulYMan5kOKeatKHk9Rk1Z8elSiyXuPqGo)5rSa8TjX17pDbLZjgeg0ei(RlHXuPBkDB3oHHtu8adKbdumhyJgyVSuHrLCNPuH5PbCRrRt03JYi5HtXGNJUCm(lOLbLkmcbaUPXMzmunseWcK33jKOEtfSL6fYmkfS)T1uDR8)TqPfkHSVC6bnANWTJ1PmmdhVBjEbbjEX4R4a0PC8SoMIwdP9fpgQMyThQZ4FROEtzFVx(eAHXKwPG2PbGsY(EWUe3)Sue7YUyoPgg0D0KGgw81vRLo1KpOlVf9qXku1kAIulU4yXBmAP4Lb)03zpxCS6cYtRMSrsiwOv5NJkntgIRU4Lkm)Ah2WPNzjz4XroNZK7xeLtiY3PH1QJmJlQ(N8or9przAj8GcSTDPwk(8sdW0arIl(CS6l4SPWLKBX5Lf5yR59mu2KbYtPStriGmTUWRpnjDgpwbJmTf9)P9nGSPf5l301ZzmAqELy6OjKPnZGCzAp7XTr(g5n5Ckd4WJnJuPdD10ZR6ws(W0scgyDmAJJ2qyLlnOePa11DOy5TKVaIZlO0GmLvudTHEtp7o7KCCUXbuOWN3Gz4xnInEl9VdF5XjVKtZnl79z)RybTiRjh6kQQHNpeTiF0(v9wdyvofqNDSx17U4CAQpQ3CVK(FUDgX0nN8i598tdYoDwVJm9GYrlbTBdW5qq1LmuIsu1RayCDjOM8Cn5dxfKrq(krkXzvNnSU0Y8mN92H8bLdgr2WiAEHzgNc7htAQivopApAy0puKtTUdCe9XRaTIrmQJXy(YcfhOCo7838tF4YJF7Px((JFncWnzkkMKJKhISMe1)ut1WlXutw4qte9hKE(om4tdpiyqo0oCon))HxJACGUpXaItizoJsG)QXk)w443izHkNrMOzVkFjRmQkihtDraBFGYt3G8GvejH8t)qfL9UC(kkYZYrVwkfjbnAOqS6ClnvkY0spDUX1NrMkkHDzmxbkAx650i7JTZfNgMCAjzWQz(GSp5sIvoLdYO5u5ETXm7gZwwoJd4B1dXelFoIJ8Vx6bSGyFC6hZd)4u2L9)AtugnAEdtZWj9mljy8C)Egd5K1pO9RbwFXCPoYlL0AhFnHPH0OUoYheMJOl77BbZAkrQ39qtqkPW1IKq)qp2D2WAVWZNgj5PE((rKUo77IBMKgG(CbPh4eeM89bgZhl4SppBY9IwaGvo8Iaaq6WOWfPPu(dUVBsGxGoQOQltkEShG6MIT6Ak1kuRIZT6Zc955KTxIhNus77wnmFTb(gvPehWw8zWDkR7bs623l13uihwV1DOiqaNjAybxaCt(73w286gmMaFcJRaW1CvjlExs7YTvnqlibT8wyizYOcyMlIdoVBe0MSx9Yiwy08yvgAORgUIC8p62oXhALxsuuHumkXELbMqMVUzfgst0FWIOEqU(R59fvuSk4qbq(ewNJHcLThNx1K67(IQlXyV5iYgbym0TbtCCBucu4Ko1LcCG2TMN130YHKvZwpuecvZbWkqBpC1yyN4mdQpOYqCLZNTK6ergTMkYAhRWyAgtuRlkZrrjQKdke70QE8zGT6vTd3YYEHRnodrPlG087k(1tWe9HZdBNYHe)ym3jKz2U1adTUSaaLJUArNgRcD5Jj7KrlZqPUgZXzqrl523kOtP4NJjXIarmYaPWqghhuUx3GES6boMaZn6ldMGWonP5DM0sWAYXJ2uvn76SYpvgza4Xu10agtp6s3kprQiunzC5XcUEYkpTHLOYaflr(Kx8TOb5i3kOArU9e8wad90AKOOvv6OiEgSUNTxrkFAeHGxW16Lv1125J3cAs)pjvMXykIkcIP0JlAv9mXvStXcXr7HCm5YqeoYh5Jdkng8DRGPlQPOOClIi(CreVkEAWFt10ZyvfrDAyD)u8ej4NyhPi2hRC9CQQ9eKdUG0a0R16ug4IwsjAuqraWc3Im1k)ansOu5CQgL7yF7Q0)ntWFbOEu8SLL3ZU1)gN1YyQpH81exdGPqerZyQbo19MrJztOnvAKgsBgDw5Bi4en6ZDMDiGOElT9JZVQSU9Esyd9ncwTet6j8jSeqsCAnQBGaeZ6KBmnJbN88k(Ka4qJ3mCLA7zKTyOmBnwgxppyW5yp)HaXJPaUAMUqoiPSt2xIbkHLRxqUl7AjoE33TgCOTxj6KRuyWycNdFSbhEzXI60qi9U0n3FPinkUVambajISexXwI2F0bLVNgBh0UQtQP8T4C7HoE06ACB7Hcxf5rROYFc1CvTYuCtGd)fI6ZvjWtGcly9jz7rz4KefaUXeF9V08m83BjdE8nUIYYSb9RHpmWeRfrNmJ5KNxBiTaT1KjMvMIcIUyr0wudY9GbSavihoqaLWiDZYmmr2AMcmIaslBI1AwFUPOUIWeT5)wleC4nzmjtctjDoSCsMCwLc0b46bjRfoSUQuj4tv9ORgFTWTJuK1n1sujswKREgOZukijtu7akhImCtHWXd2in0MNKal1W0eeHxSPSyeg(PLHik(Eoh2nkUqqYlDNzuCWWNu2TgZLWe5f)y(bM(BqOmMbhcb(KRiROwr7epcS4X0WfdMka3tLAJJ83ZuLI4Cld9hm68dYMaTAVhJvIVrEjkAcF0794R6B7UcXWsMHMXslijNe6)kA)CAvkuKteuY8CXzgOGyYH7RC5qksT)X(Xz2YceTrvPMPkEumQNq2Iss7J1jrObLwAJWuulenbbL)Zinu1UWg96RWo8V5YprRl8MrTWW)K4Ypmz7emGTAfhXSKnQsmxywElC1GPDkMdZnf5Xfvzoc5QOQTZ6GeU0SSCgR2(5PMxA75sUByyZX(GvQ3H90eRXBrwJtLLRvHvFMkrTke6dmLY0wGVqdWrQrpXzVtzPP8rDsElijI54ObXgqrthDZERz)18NZy6Pcrb9thRmVT0IzvkWP12BtC0CwAmVJN2InitR1Fr705aujWH3G2QsWZBDIkv(Nt9ah6J6WIghozys7eqKFZsneiCz3EDyesUw3dxbCWejqOV7JXChBhzi7ehc15cj2pU8z3yBfqB7yoyhQlmoC7MC7rJX(XtZ6ysmHg7iphQpoN2ECj(mvt5hDeGK0ycLfOi(Hg8JAJYglXAQXLPc6XEhCDOSCKQmfTpLg5Tg1S)q6F8dIv5E7OUTXMEELo3k1iBSUH1HYMnYe)l4GA0fU7SQY7ud1rs12dsTrerKdQhJY5uujOsRP2RMEP2TJp2pkbLhTpe)6n2vlcDB5LyIs2BtkYmguTD5yCbhpPZXyMmYgrTZDg)mJ4zhMjTxrgAIpmNX2kxbkY1198gx7icsJOAffuIJ4knldkhYoJvoIzITrZ6aHdvngUWF0bTkuBFPHJbCMEYo895CkfbSjD7u0Nsvv2VWNTdnvNZDPklaezJfhJnJyqjy8SRaS5qjLT4NrZoFeNhdMbKrzp7ehXAeYo0cyNEFLtJrHVfdEm6M4UbD4YzaQwiMPIlpwp5U1GiF4QRmRrvBvJLTh6XP2JnVBo2oV5jPsJsVjlndj3jB4MOzJA4eVHmJJOX4jo1fwt16ExoL2FFJZPtVopNZ(omxppXMXXbpDKHNZQ)FQoeopAhn7onR2IB9yc4rUB(a9c2HzZ52IVbUpeUtFpZdHT5j6dYXxCeHg5pGNqhu(y8sTJWg4YZl7vWUzSsd7qNZiNdWn0tTcvjkEQ7pNlbcWmzz(SmCFcUU75)1J0I0VmbvhJPmhEwJa4mtAISf3OVl3)ygp(hPdN1QFIeIJsTnxqA3wK(eKlw7Vg27xsxnRYXZQU7m3A)PlXR2AKxSDj1C659vinS(ZqUw94tvQDkMFl5i1yUIw(5zII3QKiYOJtV1mH6XX)Fo9qo8KBAgV)H9)Lf2vISmCgCGnWCK2QSE(YLvtpHjQ0wcl(KqrqnvVTLprhQb1)NBgbn2exU5B7WGv3(iWv(anNTNpkZnFS2lE4MeoRf5ZBf3bQq(8P)JLxIhNIpUZnNdZAOrg78uytJlluM1KdhrKFhve4BBPPMa39NMpTwM1M3jz2ZSM8Fq2J8ySxyMSAXYxmhGBv2IVdE8ggTf)VBAoXCH)IdS9udpMKqiocAGBJJh7JYjEDZPZk2zUUpJzUIqL5i9O2Mr6UTjtLm3ctM3rSHh7fNDe80hxnnTT0vXUzdqDGAE0XilFnoLgOgoJiUxunPILXe3fAOWGXjuNrXnXjVa)LQhHs)LlebrBCPNHjpTv)bd7eUyYH9(Y7QAwv2rfthy(DBt)M7Wnj36WeByCkhKlBAwfBU5oW(1l72q9VQK8bSLo(r(V5k(e3YGwa4Hio)ESVlXH1QQ5JpC5v1ylahFG7XhGdYXACm4igWDxHvBkTDkl6gUTU6t8haqM6IE8NI5bEXQAmt9tZVhoaxVPd)hyF)Vv8UkUBDD11pW)008UQHYllw9)kaM1f3vo02CZgCBJ2dbFBFrdUh8JYVVSyDBZLLnlVLpmGPuDvRHfewnUoHXJYj4j5F02ikoDXa)4dRlxwvu3)22gzA7HBjuiDx51LDDLR(706)cE5f91Ml30xUYOSxfPyI8N8s4Gz)KOrqWvGOsoOKVyr(D0afI2HQ32lrOM5Vv2ALRHRrncaxPLdyVNt9PQrEa1n6sOwODDb2WByZdWzJhEXQNEceQjxX0htvxmb9VPU9ECyviAMm66EgmM2OWnr0CK24ddDfdfWX5SxC6R)PZW38dCvt0eqHkiJwXr9YxQbxjM7aI)woQc856sv0GsP8mYQVdikwC9XLoT)Q4DsbNWv5KBxPKCFrEhzcnvYJMTqgSPkeqG3dQQXoYl2pjoj1piU8zCREhqJlQwrP8jsnZX31el0STMrK0fvWTtyE)hrIhGFm8d2GO7X53Eh3CSIYVRD4E(B7AB(nKCbPY6iwnJM8puJTB4wGBYzv9yp7MFgSHlYnlhJ6DF6UJi)1mCGTv7DeP3QYp1Ej11gP8b4QY(H27V8(Yh6aMna1hDgUQ9AX)TM510FBXQ27HDkUii7YQ7kb2A9i1ktLFfSrl7(4LihRLuR4dw86kSXnIfXnTzXhnlV)H7UQQDGyrbl9QYRL)O)90wy3)dokjUOdynW1CyapCjm(ehEvAbZFN6zxj29RcT(AyBpE5TvLFQezaJ9q56I1axdDlHezgrVFXuWPVCjHpAnfCcHvbvI7vuEwk6ozyrgDXMoGLfEgZOgji)V)WTvxp8HpwTg)Iq(W86HY70zFHvvEZ(D9I21yNIL3z332vJZ5k9UnKhepJgTMH5xUSynwj9REN4gbhqmQoAOSfBq0J0G(Jhit6Lra5uFZioeYMWPrh4KOCaEbcafvKOixdjNKmpdl6n6CRjEXPPbHXbzr(uxUhBcCWrc78vr0n4cgurTgdQWNuT)QiUdogZpG994m9bcufqzB9ZxuvTC)4H76gDL1N3wbiflYXbV0lEVR6xflj3KuHtoP3nIVXBUz6Kfu(p0v(GcPs3JmPrXgDmM2)krvwHFL1Do3)6(7iUGA1aHI67xCyRbOLNTPEa5lj6YP0ZI4BSkr02gbYITTtJDeutuN2IArn04XQ(tyt0uJecyQLl14o4LBkopSSrAeJxaAA2ON0aWFIsrZYVTAv5j1v)2Vv0TsqIZQyalKnEPv)n83acvRndvcEm6m1tdJW0WxGtj6GnGSs5W6sVYJ7SE3tnlySOIXFoXuH7vlyI59XQgnrpqJJ5SoXkrwgHg7ce1qa8m(uU)2i2xi8nt2W4gpyTqYanvKKIt2C9XTY5DT3GZCjSxFEbvc0wQOEwvt1DfRj9qXPrd)3U7WtOpQ4wsWa19jmkcvx1jaARsJQyi(Do9B2i7mQNSzaeRigTxMdRrEtWFndtZYFt1vNEcwPZ(ExEYMB(aW2VroUHqCJN3vC9aio5DynftcGnBTFu(63Cc8JWUYkpw1q1WXISauEe(9S8hQafHpZugj(OXy5yqfDSSOsFg30NG9POdMt1QJhHNE8QvT44VznOwnETJCNbMsYVrCU5smH2cIofyyUFawJWz8uxQy5aAHGauZf1jwu59ujPkkZ(O4fu)j4rXKkB0pMuUPV4tLR(hTT3jA(JCpob0J4FTPOd7ugHkGHOPKFe10fCXzBslSTFzhWAaxDgS6GLg24TayIzTCJn6Da6H)mbWJvqaPUvxF2DSOrD4khI8WMP)qlUMVJugZUrHsIGIaMfTDRagMlR6byUS(8f7ADpFA2EmioTawv(dyfGc6frzuj(bNXDNhQD4QoR)cJRZpbXJdWN5ZlRsGfPNykbngZuLDnx3vwEw7Nq0hrFcLEv2xzSpkEoEiXhkIQ6iEJvGiXkCpYX68odBuaNwD91vlbbiK7TC0dI5ZnQMevssK2BlmB6tW7SgNlMNv0uCdPahOOXQ7e9JyqdSU2bIG7vL1Rlnhvy(SSau97rTIbGWbmUtkLaFcC5W6bkC0YPA95niMlWCaEUF3vdsKLpYnq3jv1fSlNDRacr2m8URFFrZnIHZbcQgny5bW)9vRvDNBKpUPoEPYrUo1NFf3aTBqn(XgrHv5dtzff2CZPM8fZBHA250)MfNO61NICK)X0Epv7j9ssnKBCjn6krCZRd0Akokq2JJeTR3UBKZoYzMeDuJI9eJoeoCdiM98kUVoMycUQTlBXH(YLXAeC4EQlaSCybiQ5fIOtjXSfO(t3i9Hnb4SUa2cHcXxp6IdbQFpr6W4ww9QG5BkcuXoZeoJ0PpY422ifirlzWgvYXGivQdwlAzB6pLv6jIQBryZjPlHnN6QwRyJcHsOQe3sNrTgLOD4OMu9gTlpq7ZQQ0lfvNVvDGcgZslcGrpq7Dmt0fA)rUYIaAx0QQwhAC4IE(Wg(oskWCtDarB03QzEzloXw4a3t(e4KcqX0rs1mQmti3IMkiQUCFbyjgocFAE(Pa7gGPIjgPEC1GO8YwKl5bMS8pv2bglxuB0bezM307WQdHi4ZtOoIMaPfhcv1EArP9Z8OXsARzlyXWAM3I(swDuM0n(SAOGgn9mb7cv7ff5Dy1HhT2zwTJ5FS8HRQA4ghFVWntGQy)7VX7EpAnZ7jVB2ovrEDrm6eE54VK8RtY3muvtnQ8VGCRfDsPdIzDs(pj3zhoRAKtZF0SQnaTFJrn7ErXqnqiJ)BmQNQfYEPy9ifgzXy)xIQ18Gl)VISN3A77M1Ug0Ahnm8PHxnzY1efR3cRAhQZjuSooNmyLmjqOOQERAA4GBfRFQ4w7qZzWqNTPRnwQOgdmCdpRjMuuhIo1w6nQMbgJAFAJvS2HJfhPB(Uv0(pwLQDyM)(Os9wCVWtLM1gA6TnnRN3wy7EK(EXBEHXulLI1SCS1WwhtUshNeVKh5M4FeN6GzfymX8RugWD29SeptmGQyW)e5IHWS25T2EKsjhQT3IncwAeFaD6maH1DxI5zvKL)sCx(JmiyQTCUiiDz7lp84U)0QUsA(Lb8gF)R)HxXE0YLdmSDpe2WZq)Fyzd)eJm2kRJzDCMl7TbvF0tZwJbXaoPgnV1mdXko(Wn)UrD8Xrmwg7GyP9JuY0oALmSDEIKwEO9z7SnN6TTxwR7(mOAJMwNp1upW6tvImmDLKS5QP6t4bOCl1mgHeILPH4Cz1iAw2V5fVKZeb0lc84a4qSE32RxUe5aG0nRxJXK6hE(PxqgV7ozk3Qt4M29)DZ)XYBcshZ1S5U33EF)SUPdaoS72Vm6YGKW000lJIXrP7JIN0mEmmn)wNUZDloa0HUchkFPPEQAEMratKZBrUhF3XKd5Mm6qMLgxROdgLlguI6M50Z0JgE4uVd1HlRFc4j5kKtozhno5r4qWmLeZwc4(o8Rg7UCHBzh5ICNCvEc0LXr)zEgYuLdFvTdntTb3Tl3hPD46YYvuBo2Y7DaK1(50d)4hntixUq0fJ7rYxrErJgjL21xyCEt5Nk7ghkh95HBFTK30bH3VQA1QYMVtO8)8IKncDIiWbJTsGTVbwHlV8gCwktetOHoE5v9)a(jNa)Kh7(F(DM496PEVlxzE9PfoWrDGJ6Hl9rKafpjq55N6C7pz45YrkElrJ5lQGavkpCz6LbXl8ZcJVmZZ)XkjyQ(CZiBylYaMjqk7BKHmC3(8HHqfqOZl76BBkQX7Q5KxThcbSd710ytoReGPgGU7enWTzUtZ1alUlUvbXwPyhsFFKC8dOK2zV9IZtatFNcp3L1)Mh4hPiaNcX2x()UenFi6IosmGih1MO)UPLEBrD0zXZ1OKgv9ZbeM4DPnQMjKVhWfkl1lk6YShltOjoB3vQk4i)b2wLO6qLIdoy1Uu5AlQM6N)MQRl)UpuG1TGltLNIOiY1rBB3gfeBktWiZMShUtUcW7onrEF5e5u1YDqCABmN7ihSdUtJidn0cXDqa3kBOXSWvk7Tx2bVfr82Qy)5ZsYINUwBfZi9Tx6JUvRwOX4((gz7X5vHtbTysuzPBkNKvQSILl3eojQ0jDj3VTz7VS0GroNE8t8pkiklBrwuAqeNKH7DAo)SGqAwvNgMfdlbL2PZWSs((sIXzLEa8Us8s84SbE)FFWVoYFrKFqyCym3TInuT4aMJvc3VRMwrzhfdBl)GS00aA8GCi7QqhLjIBpiiEF(l4XkvIxqQ3bcZfdfBryPFsaReunXlomiiyrmav56BB4k9aqGYExAWcU8JLu1ViYvpuqrzD5smJQl4u6xNqDP8Ct)1N2)7nWvE833eg4Ng89nPEWf433eSictT(MWmVW0fW)n1p0Z)7BIII8wapg8FdItOCa3JZWPED2nb2IbMzjAHzc2cx4yamhRg95gU1lMxo1ZtLec6jqraFuFXzf)Q(NXVs5yfsor1LJAA9u8pJgI)PEjOVJKtivretg)MXFnB3KXq8B8UGsurQltSEtDrh6l5S8RQBBxvd020T1O40mRn16rxVy0WpEdHj0hpAiXXrnxeazr((jPEPHehIysaPemqQtjMY)c7gsYFvzxBvp2(2fhLEJzPbxBZgLQrGWPa0nSY5N4lHNsu0LoxBCcekgDsLuJWFX5VnMNT4O4aZDE4VgFvHNgY5NyPXaFVAtPAl1JkvUzQ9zXYRg1b2itxubhdAs6oRqrGwY(3Wxg6P3VPWyUq6qupn2pajiOfFc1dhtzNHxk1LsD35YvSmgkOxvnYbvycibX2siTrhpTdH012dNdM4m3HQsn8oLHAQrrDIySNXsPKLWmpzl5YheNezCHJzLdsk3eAoFAb(rs6YtR6qAgRjcSaSzsElMmiCXlQNyxnTnLMZU24iQPIegLeeUa5rICLWI8IYuX1LlrIs)Cp6t7kXsVGrEX0NcicGNGQgWfXuDDExX61GIRuEhpACYIljG5Rlack3O)qD7aHJKrVt4beSBhxLMM1vfWRva(bsAQ7UtUMk0Jci93Ha2V7)x5n5F3Py5)w(DNVPBDBF5)FUKePAD94NFXR)BVqwmOAFZcaAu)Jx21E3Zp9mkhVrKAHSGZ4JhSHrvcYt8(l3HompiEXx4tn2QB0frN4YwunU)XCvhM77f9xWtDqCWFbp1(EFPzM9Nrm8G40)YDxdYT(RgZmwcp2Mfq9s4XsKOigjLqpUVxwyNCbOJI4pVRf0AM6RhcPEGCYlVRc0jHYcd4ZddrX5uaCUSGwJYv0c2FjO2qz5Ql)KpwK9r0J1vEx7NGpt8edTI4)SC1LyCwGNZ345UCvvpOfZqvZg43GXyVKks9asfIlXwiY6lb76USUQbSJ7sQpqm5bQlVPy5d8R8smUt6TdVcYQqe2c9WQGDjc5ZjEtCqQ4n5LlRllA2S(YpfsT1JKC(makW8C8BkxfcVGumUryLzz1tu4k10YctWar6dzyhvyT)oEvHtb(oAY1sLWTziR46dqcSfpdOHzsuQhA9jWhl67BIddtbtud89aj3W)1lYZp97b1dddW)PF4Ii4Pcj3x89nlatHGNjibSx1pnkob(PrGzSjS9ZBXTlt3jplicm8fw8Nfh7tlBCweTmgzeL7dr2IGqyhKcMtt4RotCb3)uFurwF4OH)rg8cBct89bZQ4EVcD9lvhhaPYVfoTF)pA8Ba90P)fTuH8ywEItG()QURLECAyGW)v4paOm(z8EMlCypTsCnQWwGvQeKk9WYb(VZ8ntstCJttc7db9sL2nX1pMy)9WEIQyD56rWArVSHB4Hed7xB3NpNuLVP3s8nzj8(UU16SEtK728(KfYje9EmmiqXLMXD7pHJhS(8lGNlpu1fi0ft(ZF1(zCeJ7Vwjw9cdxlxx4bDIzXG69iDLMmmRk4ns4MPbceXXrCijdIIBxuQkYTpDIOsIVm6OlwsFKbw6mlUC6MzsH0tyAf6JmH3AVAbxx4KjIouuGJXsGCfXugkSELx6olrc5O(gZzQ(Zs5BSAoxtSJbzMungUqSd)n8ezVbUXSgPoOkO)j)HhODr9mFQm5pF2DNSJB718OpleOBkRCbp4h8NteIXSUFQcFGCY0uzzYuBjxBK)x05yELAYvDyrnoUQGjxi6XC(m8Sl7XCIoYlJUrvpMUEC3Yfn3)JJFFx7PB3F8R7LSdwbfK5L(1xNtN2Fe5sRdFmGPz7uf5LgQ0IOG2owQxwOs5qAgwun2Wiwmwd14m1YAARaTtIbT4T(a0Dp6Jr8DLdFDEDMncBrHP0Eb6L1aBrWiCEJbsvnmacgcrDJXeL2ZgHXiOxgaHSnym9axYb1KJMQw7XJ2gMO)Mb4aunDiCCP6OIuBvqlmgBnLKbogrtRZswErJw5pRLZfiLkb4zkoJoesTe5OaSLPdifvByWKc2kmQAQ5ygh3BMuqH0n7F80XDJWnTbSuprOraHlxFhHpAUAuoIpEufGPaYTZN1fK2fKu5NQw(VX1WWpx6Au4ylCvOEUubPTIfUkbl8vVMRaCDyUIeIC9HQqtvLtikTAMwGNfsAxQ9Ed8D7Z0rJzGbVlOgssJgv6BuDzPsndHOkwlXnF49TepjKSddgzNJgqpRUZLw2LrsDH82Qu4Qg1mFO)Y6cb2yEyt0mIGV9kJYje9qr0dvkXkoNoUt79si4jxqE4J(Kk7LJdd92Eh5sNRsUvnO1TMX4bnDsPNXUjLdl6MmRQov7nVgXrkbSYYwSDtXFoTYw3CSLTYEwQAClj)oUD3JDMGnhoXb2yXGSrjSjJNs9jLIoRTxKuhhldpLLNF6sLQ9VMVZj1X)gHa5IjEEIrwo37C4y7N757PgOwMtNPIlOyYrruMyATj(LxKAhxF7mg7UV9W(d3VsoEg37Q4pjY7nr59D6fC8MNR2WZOqFPf93w7qYj9AIXkBIX35RK9EWtMY3C7I)mwF5PifXs3Yu)kZG8Fb7U5Xlqn3z8PqnIsgCJFwJUHX2WHv40j(UZ8Tvrc0whK4eRKKzLTLWRfHWRRwZewH4Tm0yVWnKHigwLN7QyKHL2VqOZq07djE3ErpQ5BPER75lNrLmXXplLc8YwOqTDfTx6cPAlKWL)NBAJBj7jb6g4CNunnrSz2Ibtaei2CzPYMoLhCrsVQyHFbz2z(NpaGlFA3Hjz5zcjsSdp0QWvXU8e5BxUh)pp" },
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
