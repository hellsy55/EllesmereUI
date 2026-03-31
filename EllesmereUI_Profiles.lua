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
    -- spells via SwitchSpecProfile's deferred FullCDMRebuild. Running it here
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
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_T31wZXTTs6)k5XDFWQi4Ds9KKSKTlzB5J8Ke7tLQuXzgknC9iYzj5yBfx6)(IUBacasW5ISS3Kt05HtS4qc0Or3F9nC5BN34NEBEBg)FeNMVU49ZYwMx6CqO)HN3eL2mRopV8LLmFFhTh87LUbHohEp81T3TkN)FUE9YLWl8586MIQYsVdHFCEg20m301LlRM9PxNDx162VbVyw5Sfv1nifCCwTh)FeM2MvFtEBdlk90lp(QtwM10CzEt166z5W3uD91n5TFS8zEh4W)F(brrHEHrUyF1umpVji9Yx9Ixor9YFOKDqyyyKFSJFyCuaq0mprhDswt70SA9Uw(p07o2b(jjjEXjH(X(EXQElm94lMm5I3O3DohW49xCKdJfXeDiocDFCgH(PV(0ZmgGpdhHDDzmoezP)w(IIzlZp9RfT69Cu6BYkk50JE3HeDelkWnXnjmwBi6Lo5I3zWoJcHUlWZ331l2tWpxTm7U8AR8t6NgWZ4Fh)ZYBT)YACchS7sc8dIt2o7)zHbhe755ZzD(mhwOGzCD1S1nuVO3Hb0pyozdmZGq)eFMVt4g4e(jhWflsct8JD9DDfCItE(BUAwv1Y5vFPSXykNH)262ILfT3zW93YSlkdj5nBDU8z(6KflzJnE0b6dwCmKGsMVR6lM912KyDWE1j23pYL3IUBrlb5wUIgF4eJn1qhyI11L57fe4VzH0Wq4D9I8DC9arM7vn925FbGYGgpztGlr0Kts67B5aA5hpMWV(OGtyEm3K4y3yMBWggfplwYMqPulAxwKFhV9hFEGLE6)AYvtQZM9jZjDe4k0S5D5tZrUC9FwexiBJsxHhKW5KbUr8jbaje6lN0VumVDXBYANT4BdgCQruFqfnMzF8BnPfyOasP8FGt5wfAPb8I8IBw02rfgCGUHDF15E6WcOVfzLTv3EC16Y5nF7EuulB(8ku73nm90LlZBUnVo)xF1jIg6nzLz3GC6O0zZVfOu4DzP1vTzTCZNVmF5Q86tlZMUmF(z4pTGZJpEnNZ(7lYlFvz2S2IpNZz3SK01n5hVS4p)ZS65WBanh8nE9AUxSS6lVV9oU9DsOa4CFdg8(PFUO5L82)LvRBkkVzc(mYa97QAkGMG)(lZVUfgC8V74BogrT48xU98lU(YSYBYVGB7NpdDgmQkxF7LvFPPKDioL38LIv5hTeyvoheHEsKtdUjGJhFk)UPfLZpcarWFCAv9Cobt9bx(Abq585Mt4m52ZW5RMU)(fyV4Lo9Ml5nGt8H6dP3aVbYdLTQGYdKVXBRMGcpAVYL4RaT4XYwmoTywv57l(Z8sFCqXqQ6KfW32mbzfRYkNNFBXmKrVkpFEPpn8rogn8ze1jgXxiXCCpCqlCs1YkqeHlvqFv6nI)70o1wrZGKfZzyB86IY8MYyA8sJTjCVc(e)PnGVBlkkrYzgomoRQSLAk5iSJhFm21s(ZrcooV75qFDQhO6aj2CHMPn(d5mGFROPykQ2a6hl)s2DW7h291Qo3vmP315g0ej4FuzXTVaSie0)PxI0MFAz2T5CI7enItFarVwNOhn(6r(FGi)qXOgrrWzfuuPzv2mUYsPlXDjkGlL2IKbFAIX1bD0Om13dIlXPliTnqg80oLboEikTO097lyHAWa1MqIKlYqhWlRkZjHnKyjEM(qKgX8rdxU)IYL39QYg0MvZwWx4EXN3K1UUMpYUO8KNprx96TvNwMF7DutOtMDIzi)buLaTBWDkoGfhOOTGhPXf1f5Lee1ziPHQuIzSj5FTfrhOPKjvQbP(e5hLGegQuFGMwiL0j8wSTy1z9KueabUg09zDiCeiaP3)VRQUvIeaJLxi)dX7kqQ0PRp09iofCorBNPnDaOw3)dg9f5b)Tb91G1mo8RRgF9j43O0Uak(Rg4Bu6V2rA)yGEzeNDa0RdIMDe(4rbHbb5NaH)hjiSUFE)OXG)7LhW7kgCOIT(egmVDbD2Z)lhcCq6Xcc7Nk(BC6ur4Opb((e47dc8DCvvt039qVvhq2MwmFwbYrC1Tx5FLBKxCC8v(bUNBf82QIUoI(iMfSl7TbeIi4xMaLyHpMeKha2C((JDyvb3IOTa7GREEc2F)Yr8FT5xooR(xyBqRDuZLwWESy8AOu2qXYXGJ6zvBtWrwn6zdgXWyQHzWnALZe5XmFsMPmqZAQNDRPwbdEeazSaDzZBbBym7R5zloUydnBml2g4qJAfyVGJ65zvpBn3)TEQX91mdslZ)mLqFD8ePoJBkNhopV8xe2DfilEPxD1nlQAAVs5OWn1vF55f15ZqLLUslWfIkAEb8UCfUj6aaDEzOj5WmeRCWmSBq)UKvnH8)K7rnakLZDkQF7C9K4X)RG0vvfLq5lo503o50lHUSoF57mE49NlPiuc4UYNfIfOXZZpmXZblGSLpZwRZs)kjV0fmRSjtcWYG64YC98zH7xtg6Eqa8XmVKWKyFuG0kgVO3yHuT)ICCJDC3V(Iy9qbTMovXyj2DlwvHUuZ)n9CVhZN8YxU8vpV5BLUXUbhw65YIDpSm2XlW7qUJ2(CcI)0ehV4q()nM55WoS03hlnf8FDdIoKkSckR3OG8dqPssU3vOkmzrDoxNC5Cn3Rc4cJzZbmcJhA((ayyCxJ(rjyR5lbGKKJzYw8ijGV8bCzEGwF5fx(Q)9fVDYrVgAYRlwU8iP7KMn5lenPHyTFVxcRObVvxvTA9YS6ZX8spDzv18L8P7o08dXpLKaEoyZdwPc(cWfZw8nzFLcNWTFFX)ffBIiDyyh5M4ZyrXoXE(UiFc0sj(e9VPjIUKJ8Y86QIMBvJMMobhUPDoNcGzcffQQ0vSGmWxKAjHvjbeakfrYqNBX2zc5hyXT51BZkIAY7yXCouWn4l7iWG0AGQGEUcaFAVt4poc3VkR(t0SemSpwzt0bbOXMs6Yul3S26An337p)tIfIV6dAEKsbIIgEhZuNKFz16LYWT0SjbzbtpkDOeQJ1FGK7aAeUu3BsYt4CZMgN0bDPYG5uII6mycgqjaeO7h4dvav00s3OngHBmY)FlVfSenEF7LhkLEHXrsqyCih2lcqfdngMVqomziB)5fnqDy7MWO2aEPa)ehwsONFKRxyibiYrDYxYTXXH)YKJrpPhARYNbAQSuh8PCU3NkeIlnOJOCP6zqHrtddqSYBZwTIBOdro7WdodzBzOD0Jx32YvPj8cUzU3VSQvizkEHSAXFFt)5JdKUWWL5D1NueASEoy00)cWE)L)R8Bs)LNx8zoR)xE366vvn5)34APQcl0(rNm5v)2PYUrX6zuuMNvxD7jp)nNDpzGqYIEdn8OE1l1ni8h8Ow52w3yMye))4OM54)pWrTl6fY)8g1X)dCuZC(rJM9xVrnhc)FAGz4VePV8FooRPyggUKB6)768Mw1kUAKedzluDN0S1TvhnBw(Qwk5rRQZVJZhwMTQH4Lj4RmzDD5RkF)IIRBF)NkwnPNp0YmdUc8FGCx7lv1lNB0sEP)j3kVXJ4Zkv3UAzoKLaZSU5R(ftlREbIzgAgQg8Oi4qP)bZundSQH7C51puK1EKx1yqeoaJzy6Y48Ikz8OmM)bErboXUrU(rqlVhXZX9J)a3qhVqV4axk2rJyiSvBLBmYqOTenbckCE(VdS5)foOebZWFi(3VQn)w4zkx7JtRM()yYnJC7KZJC7yOrUIaCnc4NeWOmzC1SSvGV2ZVGlErsa82U3COhXTbcHCWwMsroj(oUCwFY(FZfp6EM0nvpht2KiXUKe988LF2qIIlTUS4MYB5(AYh4TvR0Drngeqmh)HKt)cfD)ooGJVmqyL0pjR0w0Um3Sr8J6AJePuP09u811tQ69W87TfLfC0RVn6aBOQAeozCsD21T836cWXwTewsr2WDXVA2N6Iq7e4V6PQgbOMI1(agsQO(2WIm8eUgxwDlW8GEmu9leqAdLjVzyNuvFBgWJzUlao7krygcfg)GO9tjHh0aU8HD8sCcfk0JOyUdLJ0b2CbCXcihWujaSQabJp4vedpkLzBmVRiUe)V5IVZkWnNGi1Fqt9ciyjEeENbJC4bVjRyj0t0FHkq85oQ3OotKv265neh3cW9GSmsunhNLhUlHRArBeeBHH2fRHm9kOGlZkM)8IRVUy26LT3rF76MCJuGdWkqYRdtB(FxNvNJYRxdHcpV5BdsDYWm9Ar2vhplEm8mTzWdCcoSVOT20G5p)c5dSmwgXs4wLRKQI3dwqMTUUbv294gt(k)boN8C3KNV7dFohf3jmSrHY3zcQh)3jDwwt7jf1ZwMRrGENDu0zNb0oe296gog6HAKHdHfM12MnBb2qb8UeMEIfsynqwxovdZOgkLg22LGE)s8Tke8uG)Arwsh4b4KyYlr9bV0BMnxJEpd)FA0RlBpOxf1fKUKYK02jUZ6rCJiPS12bhKY8oXv7as5kIhHUkoBrw74UKfWXsLTe4hzZe76bDApHBqeAw1Q7iOLb2fgO8WGDXszlhCyjKWhm9seWYKSPNXPPfBqSmb7kktrKredNVLf)UZIbSRWAAYUj)9D1warKep9Sm9A)fJegH(6F4ikzoyI04mYBx1OY2hvJR3NNvpBHcJ1JZJlM9jO9)1lFDZe76OK3u1T5LNWz0L5lB4sNvqTrhIZ4qK4IS5CxETRLAdlkqFadMj4EdqP63LP7zpiiSAzwBoUo(9fyVlV798b3ZZVoJdDJYku3aYEqynxcs(WdwKNTSDX7YRH0(IthCVGG3qBX2ej2NeaPPv2vIbEMO)E77obxmdUiidpsPFTSasKC96vTftrahH7pbDU)i(N10)KcNbY6i0)FGkwS0m68COGpVYCva5j7RxsUTZIiHv5OKhHbx8lhM0aEaTKqwxNjtapysu5akN0lUDfFwnRe3EhQm16rCboNrsDVOU6lTl6ssQpoh3eeK(kymFD2S8)G7j0fLn)H2u1FCB(8IS)aF1)40VYJDQPHRJCWKjNH7zc5uhqRGY)hfSGNjx3P0wn59A4CGxx4miuYU(5Z2NdqwWJlS(tchuipwzuzu05VXMcg6(RkJS10tvUBDZG(B7VzS(SH(KQlJGZWT7fvV)EHU1jNe7R3KwNNubj7lLGngHJw5C3utblbksNS7L5zZVRJMuX)4PKDtO4FImzIQLfgxQdJS5nvt11Hod3JodgkQkI4jMAuIDgkfEuLqukR(AkRIf(H0sGyOUOODA1xrbOpiLGiLOjQsniiz1KZP3UQ9o1CJyz01JFOche5gXyqltRAA64DjXQGNC996E)awSG)bZetmQ2tNshYjaDxSI(7MOxGA)DjbiCecdtR4a(3AJL2PXWPHgK5lQ3e)hrKKxbb(mLSttP5XtfqN8FxJ(UsJkdQ2iNfcbvdsGJQwazYqR2vH0eIH0LX3aBMXYp9YSMJU5M6kTOvvAqQPhheP1vHsEcwWVpAse4SFXSj82fBuYKKMOOMiNBxt9A(pQWFitbVTROwcOCfVFauoQgQ8(nPhnU9PCpsgAhfp4yyJjTX53s443bwx)OPyICGT9EjstrYysli9tCfDOGDg2ujm(JQ5gyuCIiPHoLYu3uRklerIoSZGxpboMCnmzaZ6eQeFL)7AX)U)a44BSdd4eRe1C0L1IjOXWoMjFm0lBi0kBIKs7(qpMVyocKSFDf4OKPWntXb0sfvmJaFaPaqUrTuWcWTkkSGYKZcWxzAeQZbSMjASl02c4hH0s(5OKPMg3P65sU)khZTtKuBHYfQWU7baPiNxKTIwiLEDskBxClXWPS3HBBvC04MoFvZB5E7U7SrxkGrkQbZTqwIHkVUYHa0DRGqDEhiay18QQRe)AopqaaA4ig(vSbt998PWnzG0gtK9OzZ65fqOXGuRVd0ML0GRcngmAnKNP9FTmbQ8fooq5qbJwxn2C0HIJIjewiVI)OManhFTZHWFhZiQyf5XJoPdmxdWjqFkERsxUPwG)Jq)jXyqiVow9BLmrWpXAHSkfkvzW9OLlFoocerpJP3sygycQC23B9TtIQii6juOMYK)aHSwMVUToB5oPrW5J6Exj94gxau1fRYN)Sp7EUP)fguHPAZh65cUY4ApsFOpIN3ZBUpkCTz0vxJiBsA6mAYZrgK125X08Y7n3fQlYAwasNIyjPSibo5yObRVYl1zLBVtdfs7Oj7T)6cjVIRlMHspO1aDd8wuUuTk6wFsclmKfhhWs0cAno2nkWL55fh5gtEXs2XCzH(bE(Uj(0ztsFx265cHKFT9HsGsL2iqxfpxlIcvyKV06hn6wuHHM0EBvp7dkNdCnwAkiGzpRAj6tr28QkbrBmcGv3Ih4YDOq3b)jjGGCXJXf61XX6OYyMwHPczDATYJKgFvmoBND7RbjAOKuNvNF6YI28xzSHqJsH1mBHwkoCuqimfX4LiuE4gI77RE37hOtkCz0btMeOolqINOzXPxCeDpVNR9yTxvEz2CgDQBSIdF1nccgqqohiRYcnhJ6tIAMXeRCooAGY0YGim6rEDgn(OPxXKdWDb1dmSopVwxGPyFg25k3emzd90ZGHlM3U3L3kkBIgk42fhgBTSXBhafeubSjQhIsr5AEShQXuvsfUEYUbzHcqvsfjqaHsvNtQLqJH(jlcwG1UX6zge81fwZbxYP9syHT9nu6Jl72S(wywYOanFdwPe5cxfZwFduwVRQxJ1NNpSa7BFI(3uoUXDeq6srTxRwxkkXqr5NU7QPlZWsj6M(LMju24RRwXngHnq56BNwqB2g(CBwD7ILWAH4gSPUMpoHpfG7ZiVfIt)cFaC96A4pGuTvj6RmEGYfxFh9PXCXH28RYM))qnmVHUnVTQ8M1azNq)Atw5mY)JVKNTQQ8Q8YzlObdhBIBcN3G8wJGbGHYXWibkFgTQkDfBRGv5ZkYw282Qszg6rrExybrCDEDD(8FhB)tPMN348Hv7vRBYN3RcpEQp5m(aZ8n5QdWuGyHp(gA5HC7DTCojsHQpf4A6FRm4PLWQfTta4EsT04PDzzmGaZMtD23aokOOavJgy2QewIIiuDUocRYcY9H1QcSBbWHL(q0CH6cZm1qkb4oD1MXhoV50N)QFfpzGUt6hlAzW26K0lkuHZl(3kNsWLMRC)bsROweRlh3(kI8cRgUiP9vDWc6n0XPerz0zIJCGBlGg3dVhDQZ9UU1eIBa1E7CjUHZHTawuqeCukL)mhXP9eKGQJL79bcmxxk8S(Q0zftGsN18P7qLQP8paRXl35HBPflnSUJA)c9R1vL)zUqlRUf0dmewJW(7I2fCHP3u00i0vcqKqA)B0OhpuFQBIj1XjlSG7GFdFU6keofxbgvxl(Vljf9gS6jCs6ws5DkV)ZR)0vuZobPSPlla8wOIAin0GnCZDCSMQwe5bTDDT8JUFyTu(1YI2ZaHtK5s(bmnR(cJ1z(kTnVcB4X53UUdwy9pz4WDDIBad22jSa3G4OyYnIVkpU3ehdG(hU79I8CUJA8W9we0rCul2LixUGCCcEodg5X4)CGGedDehfGomMFs4EqI6jmaisCJfVhejsHAhXAuRWCOTVdSJGIJeePhlI2xorojHHX7brY0ZhExN4UN8tbP2DA61rQ4Mxk2XpqeqbW6z(c2CyCC8(mNZgC22H9dxM6G9K1IhYI3FoL6BkcdP2bjsmrnCM0ntornDmPVC(zdiVjcH0jKob0QsmCSE9kzViTKZRLbdU5LszMUeztycghKq7fk1Q(2Q(SU8dQwKzW23HpXs(wl8BeFIiy2pkTpyjbQsdsc8FhrWQ6FoybsVWZORQu6m4ogdfoKZbQxS6CzQLNQcAtuYoGGj7sFqMkbXlQsmNSA3W72vGsyL9CUmTi69jTWuhAIB4AAcYDiYypIo4uX3aIrtKAvk70Y00SDpQdnEFTeu7KEB2xfZHDPAdzKhRHclJBKOjIPqtqUdz7uIDX0pPnq6ZDOrW7HDYKQCfcBy7t9vfh)fl4tDl31cPQAJU9keTfS6nzr9PuUuTDOMMZDt6CTaZ6eRPCbFSm)AbAD1rWYESrBFsJTQqMlSVi3hLLzQxc6ySUNmntE0IHSlDHYjN3xFajXevt(oUVgCAtUMI1EtXoi014HQ5uYOUMOPray438bjTteMyi65pugQ7GNOBgxkYLi(bHg3zflxA6xAONwAL1sAyONmxu6IxBxQqq7WA4qklFUA1Ai3hukudHwcUe)OvAj(BRwrR79VIYaLcOeLuanIfDgC8TskHO)5I8meku2ODUOE9F2LAhbZB0ulg7IBQ787fZX0JPq8vRwlnpw2l1OnQZ0BU3vS8)mvK0E7b085wbT123GFhyRJkUTpgBghJAOcM58Rd7bp)stWsRqgFxatvQ)q9cBqL1t3Bn7l1nlg1P1g2GLIf3d(55KWJCushNcXDZJKx70)(dsm2PTtXKDBSORuZ94e0JHNawwUxjDYlFq2f2m67b0isFVQBl8oUz)a4TfRENEYNwSXmIPlddWUIouj4BWR2xR(UDJAJ6GoIRaDcwKCQRNNGLGoEaTcxAhM(Jgm9F8ooZS)odmUI(gD4JPbo1D4NmyzksjR49CYEY5BYoVT1ZjuPwf(xV1ryFR(Q8MAXS)gSK0Z(pzS2Ibuxqs84B0JA2hEKs1PDQ2(nVlD)Bag7b5aqm0rAU03ZmGpUSAchi(m4Ssf)iJ082Xbt6u6eJ991sVPtk9nWJRvMf0qKdfqRth8v7zv3nzeTGEon73b7n0gPc5dpVXLYiwn8jilteQo3xheM2zNlDv8vLVlRU9Un5sySciBP5IZFedLQpWWz)bb5fQyIdg(jA)MEVglzy6Y2AlVpH1ZXodLu2D(O05sDog1gIvCOsbwdFCyGFd8wRFKRXkqk9rIsu9JsFQTlYm58TgWNDxKysELbmU(4v3LP9iSoHCwUAfGGTDIPXaPTZWdnvyeZCMU9elBb5BzgNOoI9hLFVnBf7LtQdD9EZbTrZewpvgCDmySVUIkYTEeDd4Id99CNdFRZDP(HtR7CPUzl9O3g4eSNcsr7PB0fEh1N0nA6EIiiXrZ4dH2mAWB4rhHtuSVhZlsTOJvRRUWKyhVexgEqvqRmNHMn0wVMrKMUTq4eRCOjlYHkGaX(eI7636YZP8CdqKW(UAIuiUVl5JUIB3wYp6GYigiAkq5)5(7(VUFSFSZLkrYa7CV3UJ8dWM9nVXf(4M8lERyIwXqSP)VjN2InPina2TQZAXl6DlblwDNA8uQGkFirE00MQ6PpO0NyZRO(5mWAiqjMmiX3lCZqBjJ2nBUBj1OZ5IOEL9M83VVKYhS2JDr5PyrI3NCjECFChXRKnRC1lR(wc5BJGt7uiS99qRdP3wmRwvNSe2PLamnwBJicLwIRNHR89xvohwuvv1DQwM4wpQztD3cEAxDaEKGN2OT0TTrvqyrJm)jtINffutmZZTgCUnvYTeiYM0gFWrvSrF)T7M)39(gXIdT7QV5J6cDVap2WHICp)E1Y6(oArXUxIXMRXnAUtU2P2jp1gl4hGFBQts6ScT4(byUdUrbzyQxlQhc1dmf4)yCyAFmrO7VZ45kBqIcTz6BdzB5ryZsWHBGvoIAunPcR66KZnnZHCoaIeSTyoJ1jJLieBMc3Zy7Dg7gMTTrZz2dmZyJNLllomnW8JHzS(rhAjluJ4xYyjK6bL0PDiHswZwXEN5OXdEDSyU3VWjglpmUdMggAs0kb3l(J(Ha0pvAdr2WEOjueRs)eMAlZm7yKNJLugdJzMZI28u3mkKVJet)yKbhlLsxhBYyT7BlXndtGYOPSXUV3wt3)Ofty06aSPK8mEiAwYFZOfoXwet7DQAi9oRPQzlHByR6xJLAuBNebpcPSzQTK4o1w9XI7fqLADaSRLdlMmUjs5uNLT(5QFt5QDtv0yFYhNErjShP42sPYG07Ul5xVxkt7hU)dmxmBi9z3BSg7256To5XiQ1b(tnADg21sVoUZx)qkR6y253u9whPcipAvsTF82wpHxgfr1IxDdb7FuRn63vK9pq)h7x)y5Px2gJ0FplwAFhqgwD0D0X0DQ8O7mg7g9BDy6ggudtBlvQhSBT2nzTNU6AlHABBP(T1KBmmrdJIEBge9gx)MwtaqFRBJKPcRwIhRCOJLQIr8D4Nx1qhToT7NZ3d8DVFECgui0bo8(y4h9yRgSXZJ5pUYGUFbW1lElMT113M8UEFCLYId3p84Fg4v1dWz8DnFWwCaBNYh3pNkNUPuvUPOk(ElL6yU))xS0)THmGyj2ZXx9S2cM)hr5rHZhI2390QBvOLTBObBeR9h7QBLJHa7qoq27STsi2wOZM7USJKNH4IDZYQ1nC9H(zptptXHoQLrBSqbdpzcI8ePaKAJFT3HhOBq3LQ0PZVjV)pd6A43PPdkoiNMAE5m5NYjxpKUGDqKVyljXIcCt2ZJ1AMxiDfhj(47fTEOO1J8pic25BUUoroES9SXD8zhKegge4g557lmj9VwNVgVm2u7USGyAFH5g4YCc2ZHWZc9CoikjjjmjiiWjSBm4(OWHEMfweFu8B5lkMTm)0VwO2kxHXha7ymViNKG449RByrInbNxsyKVAIiw26EjbhedtfXECE0EULXEgl5aF(36d7urVOGUMpOBkiCpNCDeyGN(vUc2rANu)DeCeSb6CdyjbEm39KGDdcGV2pj0jrqVrPVjRauuLDGRdDzGrBlZK9Rde7Up(KLNtysek1W10oTCggJBTQF8zUha35wCbtxx398eX2PJth1Xxcyh4YfxdICJc82tY(z(bUh4WzRoipfnFDC2nACLGq)d8H9LAStIB4EY2dd4IWHHj(EEbjEXKdRVPywDLEpWfvHoijKfV3kRXoUOySlV9ts8jlYVht5LwxWIyg6C7xFGQkW9oNxGtqCiXL4w41LDI9WjH4OOe3K9Cs9z(CYdau486eFAZtGZX(DSixeq7HbBkU64cnSwqUuFGi77DEP03wbCUfurhjgD74BXnzl4wmCETbhA9OLKjytTUP7Yb45zTzGHWZWVr2qdStXehQ4yqttoNo95f0JWemEId4sgVKTt3Pqa44K2i7HzK14EKsxe6CLr8(eJ2vkAWbbMSltFq2WjAG(O97WlbXn(NUXCBhbXB8gQEyoCKhgTgRV(PiSS0ru6Qg34Yihoo8H7ItUJKB3Rxx6LLrI9mPx8q6bZ4afyOpyJ272hwKLg7hH2Q7gxZjcwhpK1XbPdpOa4iXaYIR4QmwuShksSxIx6MuwT610wob2vx2LyybMhunJgQxyA1NZRRHjG13I6cLIuNig47g)mYOZ3(7BsS9oWrXtj7jlQRwFZcIXAjh02UWEfZcQbKs6GqpuxxZ83tBaQLoLibV59ye)DNC4EkPl8Lh7YONbN4fC0iGiu3l88OjnV4VPYp3J0DtVfK96vYg8z9UlKnEtksB4SzxxhwE6knwOp2INcVUf6Njfn4aRnu)78v3010g6rtd7dLK1JsPmwxsjXo7u9RVhsrV3TFESoTzCMM2XT7DXQFdyLapdQW0XjMAK8YTlHo4M8hh1b60HEcgWyf160Z0glIYeiUHTPN9US5Z7ksUuEaK50ggwVxOTeD72MHyPvQ7psyMFb)V)toxaV9e0eyPJUA4mIKeYiyy917N9BNBJ4T6bTkyBpYga8PtyNhjdaQSZTNC2XmpmatLrQO56hoMFpi)JiBSXLFOTzZhl7y)qX)Tajlsl6(ybWUJj2ncmWArF4F5vs)t4)JH)pU7i)Z2maDAFA1LM9X2GfFvnH5J7U8GpFdy82XZpF)8)JSX0lJydHYgBsY64BeveRAxJIem6WEJ4KgWpgzW6VhM2gZ8Z(eFZUp5F(dXUPnJFgwh3pZE2mM3FkoiTm)ZWDp(tw9EYQ3tw9(7PvpBoX(GJUr3(eXohj2MG0p8orwx)HyvtE)I6lxZZ2SXTZMSMODxZYIpCt8GbSUxEXLV6FFXBNC0RpFeKgk2P(fy47KTmgM22DcO)CAFqul8Y7nZJ(pfB6Eew1t20FYM(t20FYM(5)hHnDprd83sB6Q1wXpfdapUfSQtJANX(TxKNhc(43xElnmim2fD7q5H9fuEpn2neOEdO62rF)RxfQEcy)jG9hgW(F7Qu1gRV9Mmae8tZaGx4HFFga8tVQj7Z4cfrlQqBXfSVRLH(YLtEqtDFF2fgrcApXX7lhKOgBNB3WYO5)2gk)gmkSVgOECceW2sL4hFyaWa(FGwlS4b2paZeByv88xsBfEIt2vR7suBU3TpMvEGMdEaU1Q8l9EZfJ63zMT2EgS(PvgRW0lZx9JCu93S0yQwpZ)uCa4hrz9e3U17SL(9Yy6JJlapLbWNYa4F7n9)uGI)hyv9yJSRF(oTn(ZUwwM7SLVtIF7e5pn3v6TFA2nNjnbh3l7Z49n(JS9zX9kXoAF2UAWJHr49io8rtWZE57WgMP3xRRpel4BW5T9mXUpoMRFGXPp58XmwB3HPNmx))dMRT5L6FjnwJaCJfPUnBe2clYMxIpmt19Qe0igPn2US)u2Az(Sd)(SdyJT99yd4XCxdS)Mt2x46D3g)5pmSDlMzXTL4ga2h7Gq0Mq)EISpcC6obVtoW8Dfl2ik(wvY)PcXBbx9XfJFxYg7(HK3Zq5FLse7iEH0lymgnJU7XDz3lcBhirpea(XRTY(4m596Bk9FkjQ7Pk19uL6AEQsD)ano8J2))DX2W3VJ))vYaXU4)))5vPU7XZxXUZXIbhXhbDNlgsk9E8Chw7CZ6Y8MQ11ywMGDTweEi0rHBKKYBS2jCT2xukp35OZeSxlEo1h3uNnhg6gXeEZS5hZLbNNvF3L4eBKqE7ifEGXHbSHx(EPnWbykixPqgs66jGEcJyoEoHHEo(0z0bhNcpTo)GqRx(YDDOgj1nGcsVUy5YJ5)PNBGV6YkBWxCe)vscWgEDjCkB)UQUZ9kwK4yikIfWIOdV295yIrNv31ps(1lWHJzLajQ(syqiU308dCsexYST8wboohBK8DIT8XYNfaSjUq9nxkyrWC5KIBXdJtz)DCp2hXB8tI8I9ym)i8y8bAeIW07WJlzDn77xbNUB0uj2lI3bRQzl0NFu68Hgx(yjCkskxkg64RlNwLmQJLDFpO0e61vInr4bPN(bkhq9aFo6qbGs1xEXjpxsdKlGDYF9fNeCD(8Duucl0lmShxq2YksLMi0BuASlRxSlZVxB8cLvHQVCc3qwz(sOLa2hq9hl(Eqm4iPpQskKBoOFnGPdtz1rNmndjiMjYwc0k8hCD8fLEtEzED2YVzdMZOsZoGtnt6XTn1l1ehHtjuS9xvxClNXpwgogXl2(2CKheH6qk6qorPv6g3Pdzu1PHP55rO(PVir2AOto4pkoyq1o6pBxWh2l4Me7MW7Ecrcs0g8xJtZ)6QSY5V663wjrHpZo(saEW3fW4YBbo0537oJV8SeUPg8K7Zlki)zoIdHnRGlXASjjErmmNQCJxaFCGtO()d1KS4rMjOIDBVd0Gnv)fI7w6Wo14GEmB41D79SxOE2NTMCMnkzlW7Sqe90Hdv9Oz99Kp9DZeBgk7(CORs3HYFyNaVUJ8UAJo4yBUiBj0ANPRnhioB5OZwZFQkyJRpX01No7XqFIld4nImWyMrdnf1d)5lQp0s3dquVtSEermlsJ9KyFGY97H47bjH2LGhtxSV8l3JICUPR5cBedhvt2zH4qyk(yKxQ7KLvleMUOUrtegI0t2xH3qlYUXCx6CHBnxhMxI6(qqyV2uQw45WVLTCDEtJt6ajzB2u8PZ(qMtelkApp5er72K6bBNuh0008eUPUQyL8EsIH9(SfGEYCqGX3xnv9IovJxi7m(NEXM9cPx019uycnUuI7u8yQovOeBpSqlqOjanjRJUJMclBdI5Dd5Jm5ahB(NaflMGQQMPMuhh)N5R(LtGzeSo899QghOxooA1i6YIfCyFD5yGd87AalkL4KdV)ErDHu2pA(gvld0L4JAAkUP8w44VMYYj)PZExDfVfYHN4MgIBuHG026SzFIZIwF91hlp4fXtGXVH8z(Se3jzLozaEursEB7YOFEIfd0wdInO37JE(JnkCcDlAu)EV0BY(QQDvXATz3ZnCKVF3(cHyKb(s)UTKcnvpazEikC1BiGnxxF3d7htNBue3r)OiVaN4WUrvx9BhmQeB36(u3XcQtHM56W7XOeFwe05W34H)goTJhG3QBzo48jL7cC(Tf0zlQmf2yQwOtcD4ZFEXNlkZ)L3VOiF5C1OVr7MCHod31SW76JNQWjcNFrgi9vFqOaOffAejh(QNxg6lmNQtxN1pyzJysjHSUCgI)YWlrwoeO2LsJzqYddrLL0JpJr)Hy7d9IyWKYrsKsGWo28LPtpv8pPcIN0DojPbQEMID9rPiHohHYILmFcash5avPX9w0GyXndJobdJ2Z3nijmo5q9qB71DQuJvtdTUSfoLmgXg5(Ht6SJxcEs(65eWIcIIh2dVMlG1usN23WuZBfxkO9g2WTKqNZHVqm9lXgJcHXd3EnCAzBQX1fKoW8v3vWsIucv6YCzmMd30FahOvCUsPDc5wYi)H4qEy47iCzIqD6k)R4s6XXXxX)EYx)meynFU4LlzUEHWX1m(pc5obx6fXeNa1Gwf8AYB1kEBl)vmRtAFJJ4VWMI)xiHgljJGRCt4SzVRIhHkCD9Iz0TaGbXheh7fFvymZ6NDpLW7RU6MfvnTxH3fnJ(IQCtB)D4JSGGiySWIJ9X)JRCvFNdlkszBH9zD(TvFU7BpV0LldXJ4yY5LbEbH4)W1XhEc9(ZHqzkB7EFg3BRqGnIJ5G0XPDoB1N5feFi0Ya9j4viU0qgwItSZvjr(JYhIsx3I(DyV3Gd(Bo1fef4W)VjGlr8)RJRl8)Z9cRmmX3XgBbAB0jtqROHYmuMHvCVu2vHcZYZ6DgnMHvR49cixwc09O2sNkMhI)FlzT4OtM8QF7u5lmwAYnVGWvi6eJ8(7jsITBKeFwvCX38dHMKAapyAj8XJwKsCsoK)oXHeQa)W4qMZAU7enfh4(ZysZkS85yDYeps5pBPPNBKLQ2Pt1VhqyPmruzSKeXnCbJfVV3PaKEAQ8cfji8GURzc)WhwBjV6nCDJa6kk0fin39UTU)Ec376kcBie4)tZwctPN(1vCVwA4HeHC1Q1Tl5MIf(j2SiJJHZ)6)V" },
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
