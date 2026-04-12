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
    { folder = "EllesmereUINameplates",        display = "Nameplates",         svName = "EllesmereUINameplatesDB"        },
    { folder = "EllesmereUIActionBars",        display = "Action Bars",        svName = "EllesmereUIActionBarsDB"        },
    { folder = "EllesmereUIUnitFrames",        display = "Unit Frames",        svName = "EllesmereUIUnitFramesDB"        },
    { folder = "EllesmereUICooldownManager",   display = "Cooldown Manager",   svName = "EllesmereUICooldownManagerDB"   },
    { folder = "EllesmereUIResourceBars",      display = "Resource Bars",      svName = "EllesmereUIResourceBarsDB"      },
    { folder = "EllesmereUIAuraBuffReminders", display = "AuraBuff Reminders", svName = "EllesmereUIAuraBuffRemindersDB" },
    { folder = "EllesmereUIBasics",            display = "Basics",             svName = "EllesmereUIBasicsDB"            },
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
    -- Seed castbar anchor defaults if the profile predates them.
    -- These follow the same per-profile unlockLayout system as all
    -- other elements — this just ensures old profiles get the defaults.
    do
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
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_S3xwZXTnwJ(xjpEVpivCFZpPnhRA82iRKzYutvDr1nLeVQfz)rY2YkPY)97zbaeGeSxKLDs(IYlrMnjWbaN9n8B)J2GS7l6YH)ijRyD5NMNVSOY5WOGx9pAJZAN3uuu9Mk3GahTh8VQ8cJCE1VJFD3JRkG)31RxUe)Ipx00wwxv5dVEq2ICAOD9YwxTSE(DVn)X61DWtIZYRMFBDtl(R(zD5n3u0DsEB3v5nWJIepr9h4xuF91TfD)s1ba4b)xyuqAGBGtKhnvTLlkGx)4pC5LF4D9V()gwmbUrHo(PWBgIWSxq2jN(UzZx32vF)mxNzEHPjobbZsD1NAaSOxRUE5I6hQA1bHOdDD8dDdHrS4aNWEaWp7Yp8r9z)GOGddt8dCccdCDCJqaW1n7NlUTC(YIZ(sjUBOwUXzVlVS648g9jB6L7OzZnoc3B0xTWKD2)8Yzx2Kp)UcJ92GmyIImMP(fsq2Bp71xAUsWHooa2QIsIPDs)SvfgWFu2QL5pwya(WXvIVVFGFOtysyQFYMpUoikeFFJnS0SZU44zFS(bZfGBm98twM32ErrB96M5fJ34sIDCDJDrqEJ4jaCg4g7K4hh44bGBcDu5jWezm0THA6AIzUb8cEv6M6K6gNgLsZ1aeodKXTSu3WM8yusIIii23pjjc2y4fQlHTVURCzz3Jp)0bW6fM0uhNi)G4iImqISSvcGdOVnY1j2noo2hznjO3TGLMCyCOJBIVRtiGNsRnj51xXefMDX5)4BmOhIpeWvcsJCs9zQbyl86AKRYiuLq(h0XnjmLW0WGWK0KaTL0OJRGuKbINNlqbfgelWkPb0cdtlt1EYUCmlYeGdzKBQF4SuhdwK2i39p0j0nomoXDR8gJ5TqbJHGx974MOt2dLl6U9D5DZVLfoyWfU1orpYLdzfasqaMAt9sE85GyBRvTxnucKMyhnwpwhv(C)2IYBUTtbZgSCbCvKpltGV628kqQZX1RRw0(B4coklFXI6kuqOxu2zlxw0EFrtXpD(jcbpVlVk)gIXxC28f3Jlp8DDZAQ7Y7azTVPy5QIMZQYVAzXIxt)0TGWWJxdYl)x3wuDEv(8UYpxayVUPzRBloEz5V(R5nlW3aho8B8hmC)4Y6h(u3JGYamBtqUC7VHNhbzFUS9nW4)M61TLv3GJAGqA(hRBlricE)Lfx3Hlo47o(MJRqThGtoq4)hU(I8QBk(aOOaiQaM64SQ13Fr9dTvU4l5K1(q5QIJwIBvohgtQDuWloyUsYUR4XRkRwCe8JP4hKKDldjiqj2fyGQ9wCnaY9ob2U7GPcoPaQtX)(hP5Zp7QBUagkhuSu)I7D4xq7MXzxv3SOOrSgcLl)3xFjrNdVIcM6hs4T5HmjRCED1Nk)1Ik)0dbUyGi0WapxATcGdaINCloqTimhNTkVArX9LZP9)vfflQqEdWUcTrY7k03gi3i(GuTiupObJWj1lRrmhazH)QSBe))RGJeg3vSFsGOR4CshkEBzvrBfT9ek2lUeuE5o4PTO(F3wwrGZCAz866QoEOKRq1g(X0ul3ppsS9dtFBAMMwwavcRBOCHrWeCoL38ZLTLxrcOqYMLpK)iWt1ns919toTxayaQj3aMy6HJQkV)hHZPeedhEzq)X8U1n5DfFO6KtHJJGSQ87laOtskcZM6SMxngyuxWpYNovpVR4EjENNtw)usQRqhmigP5If0wfhbGSHW5mF1qXGaO0DeWdaZvcszeW4DTlRr4UUI0ec2ZUe1p3ydwEcaR9XymmnpUoszm3BZj97vJibyafJaRK(N8MlHTlWMeBfEg4Z46ncPF(q1YhpVcoCQMxqCF2ahlxTToEuH3wh)uHmwHh6i9mYAicHVu0CKUsWMMp0uwuXSlrOWJjN65zcWfrkk45EzXx6q6rD(f)cVMhq39VPzvqjFj85DLRyon9N4cwhkoNVV(SQI7rEFc(J82jZQ4)uxFVK5bUyqmuItI4DfNA6qMaRH5M8py2JeNR2v5ZbgJvh4(QF)fE3a7lHOR9N3TN2P8l8RJZe2jmIbMGi5zHBnjYrNoAxywhN9tSjmpfw1aj)F4SQ12BFHr9lmQ)2OKTvHy)Ve1S9ir))Du1AHgcO6pOkT200g0Ghnl85HVnz(1iLS3aB7X6YjuXomJSw9psE2w0FguyGvIZUg3aZjD9qzBffkC3VppWKUnQETnJqqt)2Ss2w0RuE0l0tFFv6(pwnST4bGDr)AtPLpxAwRP33M0SEdwgh370PpHU9bggL9uty28axIer2HUAjAzQWyF0EbF0ylWmnYNw3bwKt(jyK3tSApToVExbeErX9GHdcR5yUOb8Gl)fHnVplA3r(hyGgoBYg8xtEqLxLJnFBspqnHnW7IJPaZhv77hr2w)jmgtsFoB3kDt3fzHPIPdN8ZUPP(HtlBkagn1vTk)mBG)IFJYJsGgQghkAgXoIvHjFGEdcrSAnpt5j4zpWBut4BclgkVtwDpeWzCzHXRdW0ypPne)t4vblE2Z(yZwJ4jC7Rel(NAloA(8IkYc)r0wm8yZ5h7L95Bw0HPO5HcsiB1TYZEApT276YEVlmHdxn8QH0PC6(G1MIdaXGiGPbZ8I9tssMfe69u54mH3chtxVbwn28V7E6kWHo)DkpacSq)ynsF(dhr6dal7P868geeO7YgbM8y)rpgjBSAg7cNNTP7InFHyWZXMJ(n5dTj3WnwRLPyfDa73WEVKtEJD3vF3QJ72j(r282VnTaT4eqtL62Qx2nL2yLTQ5i27ZDBmIggMaLoL7L)c7Lmc72cAB04atPYiVidLfgsrgMvv8zoI)68q0orXdyHE(aU8BkxSOO6he673lss4q5Y2F82AkiEuWwhPpnR0dqqoB2n4loR3EgRssFMGFX06OM25liBOMq6nG(pXcXWt8YDfh5UYjNsbjw63wNVrUT9jjbaeXkWsmIh8ZSiGnW)CAzbtOK3EezisbOXrRytkK(XIM26Q8LOX0thdsLhNLU8FhJlPf5aw5BOm(BQiwA3U2Xoc3kJgRkH89qkGhg33XsbShLMPIA6Ujf4PeSnBbgApLjyjYHMQJmLebtP0t5EHDwuaPN9ifV0nm7pJQJ2ZmYi)9EMzgzpxhgNwbBql1bbdMn5qgT7DlE1wiX3q0Qb8Q3wEDXp8P8pxwDZitSNcFXwGShRDQjU3Uh76TAvS1yZTjhSPfMedYMn66QNUwP7B8)E6ALAQR4oAoHiSB7jlidg5BZGH9rb19YszlrYEkXPdytHPpLHUPECIpjYjIlX8BjuKZuQutcZDk7AYq5jZJvh4g7EOxqAAuAqIxa7QKMILFSUSQRnk7KZE)LNDX)OnmB1GN4M9LQd88dW08jXpnegcxmjBu4QYziMs(tpy0JDIDWuLEpMHi)d999tCC9Isd9PjqtPsykgdywgD4Re(Owcubj44676LMK4LWwLTZlBNdDCC8c48XMZgsRomqmzUrCMYg74L4SN7WuElnb))NLnymLTHtqFpNehNyyNGYlrVSURUQhlIXT6OSQwLiDu60lZuUeqn(ILlp)02FRcoQdFvLVNBI3RQsC8d9FvLxuaSbapn1Xpjc()jU(oUVQkiGYPD8)7fYP7PdNitT9jXuizWSW)wckOlVTPaKnTCHMhbdbluYxG5(IXdPHt9(y(VjYVlZFa95iIia24LFFHIjJ5l9U8ViYBmx1KDAzdc1V5dxC()5dV)YJElogxxUCjN1xYGgPGakjdniLd5LS6nWy)ZzLKCbHprMXpI4CeiSq5umlUWQqGQAH(pHNDpriRuJnSc63Dy4ex5XEPbUUXjyoQIteVlW(hK3)5)wyfxC2BkAQlBVVF91QWxaz(WzaAMCKizrR8eLybDYYJuuwx59fn8)andKWFyShB2NKsz8ZL43qwl3v8LU1asGmDT6x546HoI95PqbyHznyQRsPMmMTqDpYNqE0IDucDkezGVbm5gNqxwcRJwNSTKGwavJ53PqjWD0J7d1vFkrrO9021Kz0fSzr7Jwfe2NhLslcWXkHwH9KuP8oJ(dKOAibcIbioF2I0wm1krrjYuTet9sIjnP44Q8M7GdRqonNR8I3ykxcmrGp69aGAj9qh63hcVeXEr4nnmkjc4UgJERLcMJdiWA16L5nyeOsZUAzD9ILRBHZEq5pCZ)0YwS8nuOp8GH0zHbPoUPyQ775JjVpN5OTfllM3bS)YflrmutCatxvmhNf3mhcNdWjVRuC4Ij6kqbcVbkkolkKQ9O7ZxTc0xLYXyfJaov9WHeWmw31bu0CuJMV4(pTSUtKNIIxGGcICFjMjFYmFfooioh4bcqeqb0JshwQ8LOm803HI)8pG7Z)W)NIBY(HtlbTNl(HpUUzvDBX)xQmPQPcm6OtU88F(m500NUKywGdkF86M67p5039AAlcq1fBrVJxE8S6N5fg9nEv3NVVQ1mVr8h4Q21j4VHRAVqV)wUQt(B4Q215Bn3S)8rxdSW)7gZmI5ESEX6CCEB5CQyw9Y(Fwx021xVLJcKgkvZso7aYNZx3vJHMEfvSkCao)p1vf)tCeffisBXCs2MruStPp9Y1nvNx9PBlVU7t3vUIujSVYzu5qZkm6s8e8qDZYfWWTmFvlvTlGS6FfMqJhbIBRVF1YcSEymRUdqFB5VykV1N0xvtdiq)jYQqqFgb8pOQuafwCsblJs9CrfxqBIDZqjwGjYHGbP(HO24EC58XLBvvqenn8(gV4rTKCW08ECDI4dQ)qNqGn(UUbh6hh6K4fd2GVNgGdweCOxKJFKFsOxsalrNQIi20gHV1nCiVOYDCoK3zSf9vuBb48(FHhj9h4msa9VXkkbrc61bpjR(Q)FM78XS(nOQoI)SH)t2KCd)JWLemULfYiTyzPOJkqpeNwwdCrUqbZ5a8a)SzZZxHMES4dvZjvvNkLZYNFBzXNlUhSgYy2K6d77ik3NvnfpAao8oXhHhR2Da0(LL3urdgyyt9kEZruIeyWBw(ztCzuP159qpHM5ak(3TeFprTsXODQ9Xuw7XEDCPxx33TKpEUVSQe0IDYC3q5YIJ7O6btZGCBCd8YUQRY0FdrzRRUPPE9k0JdO2WuHagOZh6DmqOPSmCO)2YRo94Zbf8DDMD86B(eCSxXieXecXjn5x3bAN(bSwE0k5nLLzaKCm8r4CxTG4d5MnhRN)ZRWYUhEaBCZj4ZgY2jmdEkzoUQs1yL4b4KXROJCy7bHLJWIH8eGRsEthEUY1mK6xeRBUcBiq411n3NJh)UE3sO4LOD2Gjbyfdk2Qzu3eKbavFIcUabH4H8E4LlWMQHLxpSWZ)CXcUQDidWAPkMkkR9)zDEdMQi(QnaU7k4EOROIZSXPqVydDWgWaqsIJotMooUDGahAFWiBQcPDm8ZeBymFrK1U6iByczWzzQG2XcfTlXMfhZpSMsDkJSnJOKq5bWOa0OZboWG1AMCefvmkE4nbpAyXGa(pI27cgJt1wj(G3LxUKnguBT(lSNk43GK3c4W86fbpFHZGu4aKdegInks)mVSRBkkEx9NrugSK0aiKMkZJm4aHRsSMf4lfGNS3jSsfrCnNlgYUiVCXPLxFD581l7WI(cGS1TfM12hVUrz9yPN9AIHY1ynRTGeznvYGnv0LPbhP4rI1qG)2Yc1blXbPTVqznZ2lryGrxla4WOnVnvM6rG(jzPQ(CLYZW9LlkUbo0Lt7GC7C6t8Ckz8i2VsXBuf5kKuoxvVKO55e3hpCduKdF5xXjkIwTXc0GmHgZDFq6tBI3RIbsOqxcCHWEHsT1jQFpoNKa6SLG(ttroYB2Q6JeDVaTYqhWfs6R45RRNhDgFE1Nl7OkHeax1NqL7ejZLdI4pjz(Zv3SzzyBOuzVQhQWaRxqaI1J2urEaMv6YcYzq21sxSuvv00IONra1vtljW0h0h7lWdCo5uV0tTRcKnfEnoMSYABkCgllEdnDbA382UtkBMVSqda9F9rXVMQ6s0N4RBR8fCSzSfsmuswExhOKcvS5HG(fybxNq8X8W8YP5oDkNgSa4PfFfkgAj9wLIkBfRYvlK76YhXDskkce7n)SBMVqdEFn9FAWRh7mEb29wG34mj0b88yF8UDGJK(lSzabUj48SBlsP7Obr1iOmJ3Jihqn)2CSzQmXWhc8ELfjTKOxleYmRHEAEr1(obk086vpYsfgPAJgRab7gSfEu1bc4qACYz2crsxMF1Rby62ni8cJc3Qh5u3J1PXWrMYACMuCJjxb2zT53u8jrz6syzjYN(6C92zqcbySZPjbz2Ykautwym7YVFfwA(CnBlkT5pvK3m)wdXJllNFhQL0pDXBj2Q2udLmkPPRO6eGoOQyzlGLwpijbf7DyEPdG4T5lQFykwuw4UeQVGrP(vUEoKlM9C1vTfreOAGqO1llEC5JFcynEAX15G0vcxHj5qCp0fXxGy(0Hyr(YUBF)67VcJcdGscMlGVaRck5GCzLAG8R7PY98YwuIHIbBjdGv3yb1RkFFoo)VwakV)JNqLZoOMc3is(PksB0M1R6kHnAsVtY6cP9XQ)eTsdEk71yS5zGW2)MvQtQg1Icmzhr5RAanOMdpxVHnk2vK5uYnGlRxbANxGfCoU9Wv466MCzmYq9n6J5ba6L3VcoWZbjYW423gkiHdX4UMe6(XM6h6Uv1RpWm4hSdlmm7CCndImk(VG28FOQ9)Q1vt(V3xSOm))sV6)9SVaw512(q(JhE5L4gNVqPNLeSImq)fXwWbaobFSrDDdHAzSXIOdbWdxmPrhebmaNgyUU4DaFBzHTqupUCen13FtmXz0nh0S1zineemazooFB)nbjhOAJW(jE4HvzmA8cWHJAPvNqnISboqrz9zcbVkRp9qQVlZRU7OBaf5uiujUA29hjny15qz3DkqIUBSKNSDJagFAGPj44OqMVOiFb2KOyS5(Pw43hezovAHPbLyFxgbqdj3l8U6ROLUw)RjAmoyFtEGWdJuNva69w3)THuZSPL97eQGAeTKgzNNHwZOE5Dxv)fcF7Fl0ranTaolP4UASG6ptp7(vDO7leEuq0ZwgSBjdffUds(gdDHWv1TSxQWD2uXPp6ohVa2Py4MBOl30UabyW5ebikxfOOrjHjiPo1dC2nmvrlrcrvL8tyAmuuji5Ic7MbBjFncmagGvbWIqetzyJIy8CoAr)vSeFAD5637Ef5FJRlEvfQXWLdWMO12ySy06OlkSBdidqseqspFEHnG9m03kYd1b4QU7n5TMuCuBhCqmfjJwybxsS(tOW(Rt1bi(gKeguKGYG9my1I7naecbAVfKn0lBNL0Gml16FpbANvJKuqIp6npcSMtmWmKU99dWKceNBNy85ODsIYLbf7Mpj2kwdxcbPFeLZBSXWKC4cD7qySgZvdmIWmSmjXevqRprj7oCh1aYZ63zGbHLR2tmQoWLSKX2tftgQKVAkofKZi6Kpgox0jQh9x(3i6p(3841Zj54BSZgXrejBK1G8VPXaEoR4UCZewdd8Tj3SR44HR4P4d6vkYQjaF)T1yl1YeL3Lk47H(wgtqkK5fIvGeAkfcqhAJE0d4ajpfqAgtzFk98fUvuySo5)bqTfz7qdMxatvJouZ7PJtBFw8v)rbrQcw9HkizHbw)M9pMVI514RWu2o6MWAfswUgLfO24Q23dADV7BIOlIrblC3qvT1Gkt3tNIma0jneSSvOPtXyIoMajc6mffQWPsci8NnyhOXvP)NazUg0MaupVxRuI4yQmrfz(771Jhjr)yGRxSoUi1MBqnBqT0LfAPheQX(qwPdy)ljaK6sY7J6kSd8zESG86eCIBOosVQ6uFdvqSWojIeb7kYnpAd1Qc7PgQQz0z6u6R(VOKaIS(WtP2VgFFoOhhTC5PKU)cJBuiYAVzSwrIt9wVv)CLRWYSen7PL2QWoWsdDtJdLv9Db62H2nSDAd2ZvuTV8XIoc87nVzGUO9KHYFGGdtmFJJydusJFrxDfdHVtv0IcxjRDwoa6gzwe7isn1d)fH6HwTHsLRwywJkiXa6iJUUNUi(TV1YhhsFhqCTe9caHISsBHO0hTPCvXId(mwXU(z3M3ElQa82NeHjXIrC7VFugBKkjKF7VEmO8ytXzll7k6zGicAGjJOEvEcvG)hlAqphZUXd2xLllJuDvrQzyFmOoHY(luRvSiGq1BnSb9nsRkn(0u9LOvTUrJuRU791dy83lZNJKQYMoK)5aHvtNT9if7aRFvDPGbAmjn6uMGOy8zK2TS9ZgXlZMB33CiDrXAd1gwXHuYFukSbNpbYt)PsCgw5MLA(dXPxIa33ijwS(uBr2g50q9z8CJcc9d8sdsyJKivBs8Id9C99tI9epMmmnnfBMWjjHUPShxWgeGqXt1roZy2nu4tocBP86soqMKAo62zPPBHXza7EiwEoPFjXbe4OPzyIbFlqHzI(HMbriTLzmlOpwVqeuR1vajTsovVuQEzu2ngzGkXSdvu97v03ik1UwxsE6Fobo9AjyUagG1Xla5dfQEHSQquCR0ltvtsGiTI1Dn5l7TBCdAGcWjGSrnkxHXZC6Hq4cH9yvECntaQOqPmSGbktsXh3Wirh3Zv(zPpDCiTYiv9q3J7LO7HsutxmpsLnAcYoE3mmmCRVhD0k(aLpHPSFvgpR813Gr7EwZAk0saUfYY(o(V5akGXCf0rGJO3dyK45GWwwD3JZUAjAIp(cpGVagfJM6v3clbrHzFLOv9chU5nD3UeZVvS39cApcRi8trw35lw(i95puwT461n4)a9RxTyUYbLWkV(r(ttafQ7kMLV4)hciU4aDFrxD1nR5mcG(128kegWCnQiFvD1SIQ5ypqMEJ5GujyaHrdpqcOLYX4kbdeQixYfT5HvfZlZx2((6kzJdfbjGYDvtX1fnnfl(x04Fgp8WGdlRUzRBlwOfYew1E1N8AyHz(MaTgEeiYe63XP879p2b7Kee2)P4UM(3knDcWI66raeodaXTupv5stcBlMmrg0dLsxsuOhMzj4bBV3rjnn44TDefDkA3htZz0z0uCo1dM2Gu5hozAqheausD5WY5DND65)eDfj8OW)NC0kSL40(XKUPSnFI)U3)NutBqe8ckQeC6Q339uXLt)YLwTFr3NRSFs0zijuPJK3G8oyT)2I0kyxovCdtamyez3HhT9Uhz3XbJAD504I(pM6wbC8QO8XxdlupIzejDEjC6a69Ehs8a6vaFaLVeG(j3Z5(pMl5DyisGFTPU6xrYfKkRPdPdmclkWKcJ5C3TGvkVRe4jX0kHKUFiez82JHoI8xeppkYITuMKG6W856zexzIv4vfTD1pm7HIhBaMnyAiqPsv91I))sMxtlfChasP0rXJc3eWwRfPwzQ8RaaTO5UzCZ9vm4llrgZyiaPqxIVkyh2J3FvzDhXIcg6ffxl)OFFCWF(PQYUxJyX0PaRAYv5nFqRKvsvP3ZexQi7ADXHSYm6J)uvb6fcwt544g6fMeNWYH(svqkQprQFsAua3g)35zz0nlbx8HHEhgcZJJFGtcDlSGtJFcv0F(bUPaeShZI2DSaVkCPk1ZXjicaAwJ0VuDGVBi)4yhyA3JXx35d4Wt9s79GMJkMpT7NHnaK(Uuz5ff7hLKq(fFN3QXC5rk2wWD4apkGs7lOIUwv4F(hR8s4o6ESVRVdNUkWMzKdxBJjoUUbPi7ZDfoLxNk8Mq0EcFhGPojLzYOx35ldajfdd2ehh(cAHL8Jy50dzDafIX7X95mBI)r1RqqjjWgDUzBRuaaLKe97pOPDYaVP57dq2u1Yhz)Ui8PbkhNDVlqrJnXF9lTakfWinI7tbvSqMafWyv0LPlk(eHbHI6ZYQVxLsZKgzi87enGIphfFPh9CYBlS)UR6WunfoplAUDfTtlbBrWxfbxebyJeYd01HxF9E1JZ3AhAXPcLkMIDWtzFKOpNCLkjvrGThJ0TEu(nbNySk4CpRJFd02w(kzaDUmakYW)UD7az9QLVVwuxCYUp)lIZqrK0qmDyJ8ynoZY85LHj9(xOhGmoyBNJhQS34lxid3D4vWNWQJSpYhKc(7xKGfx5d3cNVucYS99cWUufsTQka5k7CWHfN6fyoNJiwY7fJqq(iO1MqGNjAn7zsstd2nz9t1rywo37xDxEufELq0UBhU7IPRKzqNLTtfgrej2teboxhPeFU5bdDKtc84H8JGIkaSrPMRCbYEIHtMsuPCTZ1(ZuwqVgQPMj0IPuLoMSBBelr6k)bMlDCi1vLGYbpsLbsLgXXl0xxUCPP)cI81CaDFqyXeGJDrUb612XkeWoMikswie4YqMSQk75AiOsOm9KZEz63wbCuWcH8leoaFVFOJWjRryAZ9xQoqCXGqk3lCxbjZOpZx1cDe649Tf2j8CJpAjdF8Y8wWItKpMcgRwkY1FdGbQKThKrab800mYu1rC2ZL(8qcjvYnzbMje4rmTvFXxfVvngmMOB7JWMPZwLXeyymr7pFDexWiCJ4sp0GB98fpj5OfJsHmchziNrzKrEr6H4GJiOU6z2tezlc15S5zcH6OeFxGAMt0sj)e(QgbZsFgjensq(3cQDWqLURWydnm7PvyOiVQjvjaJVwpINX9WYu8LsvsIfGWir(I4fcaMkRRfV6Kc9bXaDxrzMMuLcj25w4DQjWLZhQjfoJUFrQ2IXcDFf)ZHLAuSuNwHjBzMmAkjQccomGYbS8nR1YaZIF3L4pn1SLu)s0MB7XbunF2rvIbzSB9dNxHPVpk4AAr5kQkMjSNp6cAV4r43CWlni9SQn6yj)9EEDSOF2LlFciOztY1f6ZsOTi1elUORo(gDZNbn37UQxZ5U(EDsFSrSLHO9eiQpEKosBqGNkZmfS7dO46I(I0K5Gz0WLkUy4sz1UuQI8sC(UVs0nvgzOGCk9AWAnc4zae9Cc(iUbFmKE7HUzXCzW4aQ9Dw5yARN4QjmWWI0nQ1t3JhyvaNaSaInnErk1uhzogIDW10W5vFmVPd9x1KQ(bgHjzzzWozsbI9FGHs9JmMdWUKBIJw(0bPiVK0NvASXnmL6IsGtZ8KPBkB9IveBommiRzgJKSUNxHMnxGW(bg4jWy61kBOfQj9w0PVs6rvv9QA7OmmX9gnSZUQqaSY7vABne5FFncPPA0Ey(gWzrD6yyvO6PIth7M4cRCDrcYqSk6uj6k9q9Ikmokkr3IJnn0dtdh3lLrhRIn5nYnAC2eDhhq)c9n23kQ7rDl3gzM2y73f9(4TBMMsBOHMnRBLMUSlDR0g6ODSlTi1yqdvFJQQ70)jIJeTNOUvYSKbCt4fgH6IJTyJ6(moXjb(U(u5AZkR2NhErA1oUhLeDwKHOL9qKNpTB3MiDUU82cmMjM1bhZYFOE39zc6Gm61M)i4qZHnAjcg3Ohqu854DxsorVAO7VnaKV06Us64ms3E2FGSx1hvszF9QWJ9WrH(8IBpbHBO0FUuN9ab0iUGw5vTfnWTORTrs4rNAA1)YCk7JpVAbg)(AHW6rA4TxUvs)y8RttZDvlbBkmVngoBRoduusMTfjryUyV0E0vT1nxbklSlA6nW4DsBoLBMSRTMlioMMiXPUqsGWiotFOSZQEz3dacfKS4AA0Cv9Oe8uYFFQbBz6x6DvbManHBg6zmq7Sn0OzhOCGc73u)FfB6XcyTlMwK6GKegLBmLjMIUEqQrEq52QZd0WLj4(TjDjZTvqjt8MWzvPfHs80KYAWkWZGsxlObSLYpb)b(Trqchy3(Sjryv8aoGYgmypF)PDDWiNLy6BwH(Lt7bKNHKohy3GfeF)Q6YAkeuCOH7JbhDSGgJJYxmpXu4yPc3NcNyWxVVETWIdhMkAcBWdcJfp3lvzA)byX98ylF2aXujf3Mk0wSo3y7dWv2IH6pjxWVdwDlnZYuHZ918AGJVAzpu1v7gMSNQDnHXQWcCWXW4sVZAQppqpSH2Wo0FdJ5SXn3aSM5r)2kZtMEN2m281Du98PSC1qyMPVtS5qitZx)k8D1ZHzUwIROoVjJmE2M1TAULrqMnzyj1zkbuvk3jyXLNt6q1n4c2PTWnXuNhTqzB1o3jcESTOVzjKrpz7zD3KJ7ShkGPcDOTAlFQWpUh21A1txwJra7NuwLwTkX1EfAz1(ua3gfUjSlxjzZWKkYQYPDO1MCT7(40cDN1YAs0VWqvC2UPLJ8b2U4esvybj)XmkjhuDCN9mUJt7JboOvIuwHsdf0qv7HBAKNfTAn5oNYgd8O3oRg9M0zyAQ(n6XjoU5JI9ZULgaw9))0b(Vhxsz33(hKFBwbomY220oDtMcoGvTYZTKncBj07kZg3hTUhQYLkeK2i32cNsDV8OsNIn79hklpPm0A6(KI9KPYwuAEAHBDGVB6d)GnN3SFMBS94Qk6gr7tCvTKEotBV0uET5zlYPdJGO1iEUJrlDsLm2)CK6jAVJUEjBmSPdD))Uh4uoAyBqg52C3fiuAyMrT9WJUJwGTtXhDNZcKNKbAyEABp9hgNTupzJ5MqEXENsutQe02C69wdRQf)SnPYlM(qYsut7ZkRPmkDO(D29tM1GUovqt3GB8Mq)5TzYPUj1g5gZofQ0jdIR9ycnLrNJSzDRXj1EilFomICk3HAX4YVDriD)CBXaVmaO5JtTVnf109XaclHt9PB1)iBjEcHuDxJcYKEk)pnbwDCovSjRO)AJV6gJqNi9W(tJtVNoLyTMLz2JtZ2cQ6ZqusnJ0fNcK1DFKT(CViZEjtxNOVS9TntxtZwGLAhgcFmlN2uzbypPNnB9G4T(DD1X5nKTyXzRw3EBXIHopwVjFf50NsTjI0nNk(8yohZbwM0y8tdAeWEHQlhYZwCtXWFgtzb670sLbrFkdiY1VJ7cYaW1xwStUbIANYno0lDp739U(uxVokw8Xa8tJoERpGLQuCWHXyLX55HxMD75fhNRtG7HPrrHHEX(bChiYn7FUUyDXN6Y7yRFX6HkmHRCnVqpxNW9CjCqKVZHXP4D6xyyOteFl4aRb8QzHR7UVMDOdSSfbRIFU42Y5llo7lLCNpdNMi(w2Zp2jnmbdb2EubAUXXIAdmnkoGqKOfbEtRqJUFA4Hj4rrIpShTNLI3bUPhgaFBawjJ(XuVdGgE8knHpcOgl4EaWu19HxugFPRjxqerDIvfahtxeIHU4nziLP)7XO7fsxJIbProPc4no7D5LiHQQk)C4cBKlBtSSp2JjWbhE6WY3jknMWAC9YoRAE9AmPp7NNaxVdXBZpaX0ZJU7I3NPrTthR2xcDp0dqxdJ9Idj2h7X4DqqO3HoW2kqmY36grWX4nA7kHrbhgG1TAItQh1Le2JHpkeqHJIsd89dt9Po2xs27kN3uRpdaQkobPrUj7nXAIJhHg7bJFAkXtind4gunVqBkCJ9pK6nt7bSduieJWuFxaJWxuEdGGDDuMeFAVpjoo1lDpplpii2LQjuylonGRFcIicV5RyIipIp2tJBPOap7VbHrHeCsoW3Xz4n8HOA2gkIa77b1ZP(8HQ9)bI5OlaI8w8(F4i8UJaL0r1YDk2K1L3LQNM3LJY)Wil4QgOrINCf36bYEapDPoiGhr7iI6ybuEYH9UbgGuDXamo)11lxu)qfUYS3572MSvJlMoDmhnz3dbgTBS2WdLvCKa6g0zwNUJiOVA)kuoqCfIkqCiz428s4gUAGTfSnzNZvluJyBYd5glR0kexpoRA99xu)qR8I6K41HTKITxhCEWHh8YQR5dXP8CSptF5Tn1RVHAF2bz3v84vLvlmQqw0xbiWikIckbnJZYx(q(JTO791U5pO(dkwGZxc4kDLRO6L0t8UVPCXIc6cGijREnamxKxjWKauCUIi4RucGJLStvypwMYsFwpJ0IKa)UTLm5D99ypfQP(O1Wp2Fj)IqTrt8X8N07hpPzxjBAq4s32fRmxmo1FUOPb2wEV(PFp14U1Upd13C0YjCMlZ)Gp15JafALkxGS2rZLyfCTHjtQTeejL4Xikc6jkMO7XZydSm)m6zdU4194NQxCYy3LxN9JdZva7ETwpDgNg3yZ4aa6Hv9Z2oM9ZUPP(HtlBkiJoA9YwJvAUbT1)wEZNOndg1ypNMlyT0B0l0gqp03wLu5bAFBsIBfVyEuHvSIr)s9(AqYaIWOn4ypC6gugc1LROABt0J7L73BN)XagdIq8jUrDgM82yturagChBwua4AiYmgIOdurrTtdez0qMNZhZxSaVDofTzyE3dz6OTaXQGIQFlJYFXnRg7CyGLk4zLliUd(3)kWTKUli0Gr(oOfBBKetwTRLTHodomRQa2BnSYYo)PNDjauBP)Rtca3Mi05yI3zp7IaGby4Y8)DiR6DG5pZPZoZF7hJdKCjMBWK6F22njhyfUqc2xPqGiD2Uc(z0CVbE97lpzUNaneZFpfeyx)dTnH9Hzp33kSD)vyLMEeZE6(iCm7ndM4Q8R8VOS7NwIoGzBNRpid3uDNNg7D7sCbu()mW1FG6mM6mYxQgwvfWIIKCDrT78)n50NKbSO7kbdP2aBEl5w2wK(3lyWQFWm1XL9SP9JfRIWMGWXUK0P4qmLmnCZCk(Ldeby43Q)QiAZgU2UkABcr805NnTk2bzCBYah7if2KX9xglCErQ3FhK6ztfW)ye3Tb5VFVT0zGmVj1z87JGVD1ehlEzXq4wy2)(JcNU(nrQM8(eoq2IfSzT4olYIAsEIBDA(c2AsXGJSi8nF4IZ)pF49xE0BNYbm2dRWx52YuYV3UsagMQsx5QdnFB0EjfJHE3O)DsMo133)Amx1uMo3g5FrMo1vHeEHFGJYEw9A5lY0FrMUPRf)2Ac7lY05MclWK7P52YTjtVpJk(ojaGI0(ZNaaA42zba2SN67yaR2lpqoTbOBGOysPa2SACdES0IZd)lsyPM2tLVexk7XLsCDP8sCPWWq9x74sTN66zKTy24n(ShTkFS5Y81W9piBwB(Nlwa2HU5JkMpWt1YG0EF0(14XVnfvlPIKdIzPLmD4BPh)2GSK9t8GS)dniCT7zqR2x7lEYzVWEeqlUN(pi7fEXmGVNMbm2748TuY338xyJrYI4STxrYYUc3wJV1tu3)9uCGEsoaIgmsm3jQ5vJuXGYMJNwESfGF7xJCHbH6HafB8n3DbcJs4S9E3KVuS3CsVT58EyVmyWw053yvl(5Yw866xE5CrPK3KgqSVCM3G0d7P3Wg01ypfIyp4OwevqQiS1eDJfvmvUeXrJ2mx3amVXPX22Z3nrYtzpF3Mwq9F2s7Tjen(TnOqJeqBlUu)blWWsyGOl1IjY0blkKRLYZrCYnoHwKprbgwJcTrmGIYUOy1lbbI9kN0(jQgq(o5)SV6897LKIWA)I7LaOW3IV7O4WxsfqrUwVlz(9g9W2lbq59YcdyVnH6PNmGpx5eXuvk5FXYeaZQb8Re43E6kO56UVT5S4GAqC3m5(RWow6wI)RXow7(3CqHw9m6AtlUB8R2Q1HP3kFhLSx2YoHP76LQM8Uu67qwpmTPP7yqX2xJNFY5UpNH0MfQ1lreZnRPIRR9jQuRNqQ7pbtUNjP5)zW6v98LJzyli5gvUwuB)ZUxDMW22jmB95SGTMOajhynBFr2))Ee61x86VetpTIb7Ly6TXIuZMmNNLcrBFf(9sm9wu0WfNNKV63SAs(pqltFjMEpLYq(RQ(0WRylV(U7XOwbsOQ7EilIA8l8ZoB5YI27lAk(PZVOOTEDd1uxW28eFhFW(donBj83xwo)UFSY5q(2jIBzyVv8CUTfCtt(cS(R1QpDVSBMV4yq7(f5npEbH3hlQYQJyQamUD5TTubPt5d5G6XUfVzX7VXtXVjvnti8ef7647ef57eWnJK(IdaBPt9a)ryl)c9TE)3ZWaOkdD7SZ1PAy21LlxEm8Y(EHb9x2zmWQTCuBgPzRRWUr)hRvnil3yr)kk2n0LAsj7rJXH0OLbJlWnC3WOKiV4GqNuCfj3aH5FemPwJ(zxDJ4fCY6GJU3L3CxR8eGxV)s1bH4gg(UWeHdMpFbMk3ZbRoKZgSHyS1XBqbPX(j(UUbXuJmJV20VSeqP4(KUAMpM2P5F)tRW(bNA2qelc6Oc7Od)yraZm2Uzaqcom8kED11poDn(a6ZwvSehvQ15Obe)iJYnQ9qeN1v8LU1n9n1cClb3lPKqfB6b1p8JNCQergr3DYuyM803Jvjo0s89JJtDJ8Je3JIQnd5i3JBYhmP8QVV(TLfoJNRSLXfeYdhDTMqKmNDp3117YVPGI0RgKX7J4IH39yKkbLNRIm60Yg8Z0logUvnJLbpFzJji01hge)py0v9xC2nfvfn5lXqNS56VbohYPRQFCNx)oCZKGu(Va0vxhI2igyNvEpWrzQ2XZe5Qamv69Jf1DZUoZhUeqLmgQV(62c5nBkFxq2FRYB2yd1B4UmMQwFLaqc7VG5vxhyWtVfw63wVCbJaGiRYNWGGKBe9RjzfFzvE1IZV(91s(18jU6RqYs2vv8cH5bOyjY8p4vLK8pbpg6DCNGBWHalvT)tuNvJUAMnzpypnzSqVXahtelqpTmHkQqMRToxwSnUww1bRSto79xE2fwzWIogqBVbryjHxo4LRy5vLll7EegbUVgTn0vbhvlGzpvQp3pbtCDCJf64Poz0AFjE9NxFCExfxRtwDHPobRsIa(2UecLEJhc4iOMl8geUmFjMeia(b)H4Qpu0b64wu(3vQNPjwyrWcIfb68xhXcW3M8CXUtx4YPVQIWicLl(9LWyS0TDKWWkk(eOywWg1KXWiwd0EvxQW00a7b67HPK8WXyWtrxoe)f0IOaemHQuYXN3gn2Ujcic59DmjQNB3oBG9VPMQGQf7ikTqjKDLtpOr7iUDC7k1pf7MHXoEEXoH7z3)m6qql5qqtsVWIdCi2aSiErxxBGsLSst)C(Y1fTTozJOfgsALaAN6H3iWoauIWplfXmGlVJ6uNSo(8(SuNofDNpkGcVtbkxjVAX4f68BXEzeiMe05GvYNo4yXBmAPyYGp9dMTbkJI(DCVbBGeIiJ73yL8jC0ftkd1tKxiwlWgaMK91pj8IOCcr(wfgPwYSEaQ)jRiT6FIC1J5(IzD98EP4tlnWnONE5e8ePI4vAll2eRxwmTPM3wfmXMxzHYobpqfntqHQSYEYPU4P0x97)ox)18DZhFt99B4JIy1TpQTT8MQ7bJmjtTaRqxvm)Jn1GaUc8jEzruhY1nB29LG9OuNadEGVF28f3pd7l9ZaRnHXOybnGTZafWkkwm7ZUaDQFa9Anf3x)z4zI3ORE2n3w32nB(IzOgRW75Q9EZwu2cSJ6kRwdFZkC86qlp8aBOHbRTRPC1SURUA2YYQ7G3GUibg9cllUjF(J8uo7UIhXxqao8iSQUTexoai0cJYnlRFq(EIzshiNnFzrE16vZ(S)LCF)LxdGf9NG)sXcFycijCyt)Kn5xtHvJ(2PQd3vSSyoqb3FkW)IBgVNkpx8ZCN5(B45G4A8Loi5M8wo1j9ilmp)0kGHKVi0Q0khEKNhO)eIrJz75IcGO7OtU88F(mYclau7BDDn8St3(4I7m5RiQkQh1IVlDj2c43)(tewC9cC9drEspBateGJJCSCNfJ7qdxt8cyWQcxOCqUgS7Lghkm9uBXAbyhEoeZutWUDyGBas2XGuWoDO5fhgtkyPnm(HKxoE22MGZmbm5TtWusO33d8iI)uks1qyWelhahN4wnlEMRtONVhSp6LqCTCYMPyDWABlz(i(8kWa6xvf6dKbVQsSVw55eGDME0fDQXozMxyKBQF4mq8K9HYZjmn4vvhG4So4Feg66rdtkF3LDhis36NstfWsJxgUoZCHvHFemNEX06iv(BbZ8I9tssMbI7TdfWNgH9j6k8pIa9QR8JDfT(Ay9t4DNUwXzw(RvUavM23aO10)IgkWajsUGcms4D6y)zayySpbaVxyAItqWS0j2NI8H96O0ahagbDPEfEgeZtGV68cLuqIygFKrmOsPtnaNVcu6XhKal5BX73Yw2ane(8Q(tfDyJDMLNnEy9JdPXZ1nWnkew0Ujj4A3nXZfomDbGgpA9s4MbQBgyJutUapIbEHClTNbS9BFSAo6hh50JIdcP7ls7RpCbeNTUJSo2(oa2fXb4me5(a7HGczvUPoXa4ofKzUbahT4hHdEiXs7ZfF6HYvf0vAj7DKFhFh4WzBVdpTB5Tq4DBdeVA2YBrynB8DeYATTP3tmNIOVHrorZCCc(ncZlmdomNdQhCmCWiVClglew0oQzXzTDWx0Q7TWkqZc2BKa5m9Zxkn7WO3ZAXt9HdEFYjM4ab0Sgd07Y)IXyz(RO)Nq5x9(uU3r2XrHj(a1skEhdGoIrZj1dNLQrTM1HaiQ574ObaZaW1bDhTNxaohHzLaYV01(4FZofDyqacZWnp(36dbGNdmqXPbUX4yIYL9jNPqkHqOR93J0Mo3gqJr18G3)0Ypxwv8dF62YILlisF(GtDdHadbOq7))k7kyNgggg6xeslPPPR9mWjaXHjUIkSkXK6ArRdTT)EE(5M2KoHe78wswStT97Lv)AoeXtN1rLsO0OsXHMRLJAKRBSyjEfs3nrQnNu2tdG0A3R722SFhBV7Ko3ew6D0cf1sFVMOFBrXQSsK0pF1AcEptzQEAlmPgLfv9Fx)jICeUDhXkm91CvIyoZYrJ)nPn5ifwxm))jy1iMRLhcuWrZeCRVhfAt4xPWrw)5hrcwr1p)38(tDCPCQVsgbOK2Vf00Ns9pCAIuv4qEi)A5mt6TuKU1t6N9J19P1)nw0N0H)JCFB(co6oakN9h5a3nzR988s2QCtbRxDHf(jCcCGQ8VI6)fyvcVPLZNn0YLNPD()CrbyHUk(acDRWceNX97gendgX1vF)mBowJ1yqMGCyPYNG(bKsXANJPIPXRU0znJ3PgYUdlm3lhAAFDbpWxZmSP6C3DoRoAhEEQ0JsELjnOjp508Pk1IdF4nn16FaTQG61GAMinnERxk85MNlT6G332FyFD3XNBeApuxLa(8XDTisHe5P9n)gwoQOmTkEyVa65J6wj5WdNfKOdNQVqpr)phb8tndlBg6B7pHr)7" },
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
