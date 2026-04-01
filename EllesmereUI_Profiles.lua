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
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_T31wZTnUs6)kZJ7(qCrW7u(jBh7Kuoj2hhnZKCQPkvus0wCJmPwsQK4jL)VVO7gGaGeuxCSZoZzCEi2wIeOrF5RVGBF)8A)r3M1KY)L4rzRZ)WS0Lzfohe6F451rJQNvLLv86cMVVJ2h87fUbHohEp82n3TkJ)JRxVCj8aFjRQoVSOW7q4lNNInnZD06ILLZ(8BtVRCDZ3HhmTy2IYQAKcooTYJ)lHJAsRUjRPMfn60RoEYjltRRVkRUCD1Sm4DkV(66SMpv8cVdC4)Zpikk0lmYf7R685z1bJU6nV61Jvp8hlyheggg5h74hghfaenZt0rNKw3mnTsVRL)IE3XoWJ)pFVaNG4GeFvVfo64lgp(I3P3Dc2cFi5(4mK8h92tpZye9cCiXhnomweloghtSr)w2I8zlZo9B5n69C0O3LMxWPh9UZ5Gavp4nA8fxAWYIcHEiWZ331l2tWZwTm9USkR8m6R6XxUhf90tr))2y1o4iZnijkmG)JnqJHH6mHKdP(66YzRRTqIb03y2vGuL5Meh7gZ07RbfRCMWjV8DtMvwUCE5xlQneWm87w3KVmV5oJoAlYswh1tj7CRcXx4JSGGq)eFMVt4g7NOd0FuxOJ4I0UsePGuRtqrsqsGFqCsSVx8M5tVim4GyUXcxt2N5WcH(jbv9VS8RMJPTzs4Cqc)FoX((rUG2WoiGKT92zDbh4ZB8y)iFMlZjzJiir9qqsg9Hgoaw2XdziSlQz9uPFrSJWu(0)14jJRsN9ztogcReA26m72lw0ac7deYiZI(mnl2lSHu26no8tqjxyIFSRVlxvd6kNrFnFEZI3L2mBX3Pbji85MQ8X0a6cDbD0yWDXW1qt6adihl04Drw(nlA0PcfRUL)21oVJXTaoCrArt5ThxUUyE93Vh1(sNpVeHfCdhD6YLz13MvL9RV5erd9U0I0BqrA0OzZVfg4WZYgvv2K2WDB(6SLRYQoTiD6YS5NHF1col(41Co7VViR4nfPZAY)sgxWYsgTUo74L5)5FMwnhEcO5G3XRtZ9QLLF9dn3X9Rt6hap57WG3F0xYRFnV9FD5668IBgJFg5y(YY6COj4p)YSRBGbh)9o(MJr4mU4I7h)IRVkT4MSl4(85sLZGrvX6BVQ8R1fSdrrE9xZxLD0sGv5Cqegbrgn4gdbC85S7MMxm)iWuh)YPLvZ5em1hC1RfaLZLnNWzYnNHYR62)(vyV4nA6nxXBaN4d1hsVdEcKhkBvbLhiFI3xogvy0EKRWhbAXJLTy8O8zLfFi)pZk8XbfdPQtwaVB9yKvSkTyE2T5Zqg9QSS5f(0Wh5y0WNruNyeFHegY9WETWjLllbveUwb9wJUr8ZPfs8brZGKfZPFB828IS6IyA8sJTX8Gd(m)tRHy2wKxGKZmCyCwzrd1uYrylp(ySRL8NJeCCE3ZHaBnpqZbsT5cnFE8pKZa(T868POzdyFS8RP3bpFy7BR6CxHqVTZnOjsX)OI8B5Qhheh09tVcPn)rfP3MXjUt0io9be9yTQE04Rd5)rI8dfJAeucLkOQs9Q0zCJLcxI7suaxlTbjdEtpvytYnfD0iqJMHfpAbz0bQIN2AtWXUqLgfeqx9l0qgi6esZCrkg)DrzrgPZH0mX60hP0aNpO4Q)xuS8U3uuJUWQ3cmdpi(S60M1v8b4ffN8YX6wzVV80ISBVJAcDYSvBdztGffyKdon44wC8IMCEIgxuLNvqivNHKgAzjeCJZ(wdcsqsMXLQbPU88tsScdlRpsshYwDmVfBYxDwhfgbEGRbDFwlqhHfqM))7YYBLacWy5vY)q8ScalD66JTFeNcoNOTZ0eha419pXGWip4VnGWgSMHrHD14RpJchnQnHJNqm44dpFVHGJg9RTu2tdamJySDbG5sCam7i8JFgd(zm4UyW6r79udb)3R4G3vi4qfB9ziyE7c2SN)uca)Gccoy0Xcc7Nk(7Zba)m47pi47WMQMOV7HDRoGSnRyUubkew5Tt8N4g5fhhpXpW9CRG3wn01r0hWTGDDVnGqebFZyycw4Jjb5bGnNV)yhwnWTOA3g92LLOBVnyPoOlsl4nwCy1xZQVQ4qqqD8KTjiiRo6SbDy4a1W13g9SzI2ywjjZIfO5b1ZUhuRaapcalwGRSfHGnCL91LSLGvSHGnKxAdSNbr(3liOort1X)Y9FVJPBxRXGrfzFHkPVogIWoH3CCE48SIFr4RvGM4nAYKBwuw3mrfCWnvLF9L5vzZqJL25zGReLx)k4zpMBSRB03gzHMMdZqTYbRTUb97sEYe6)JVhTaOIn3AO(9Z1lFh)VcgTQmVaMaJto99Jp9kOlRYwEPXhE)5skc1aUR4fHoWC9455hM45GtzSLxZwRZg9nsFPn)vztMeGZdQJlZ1ZNfUFnzO7bbWlZ8sctI9rfsR46IEJfstQrKJBSJ7(1xeRhMEZPtvmwID3GZNqBr5)UEv3J5cVSLlFZlR)EHBSBWHfEUSy3dlID8c8oKhCTpNG4FAIJxCi)NXmph2Hf((402b)0ni6qAkvqD9AfmFaQvs69UctHXlQY42KlNRfsvaxzmDoGry8HMppagg32OFsc2A(qaijfmMSfpsc4l)aUopqRV(IREZ)(I3p(O3cn515lxEKmesZM8vIM0qT2VZdHZLbVvxvUA9Y0QZXkspDzz58LCXDlA(H4RsAaVe8ZbRnbFb4Izl(U0VrPq42TV4FJInrKomSJCt8zSOyNypFxKpbwPeFI(Dsq06s91zvL513Qgn1TkoC35CofaZekMIQcxXsWaFqQLeELeqaOwePdDUfFNjuSF53MvTnVikH3Xczom9AWB2sGbJQaQc65sa8P5orm4iC)Q0QptsjyyFSYNOdcqJnLmmPgUBT1vAHS3v(tQfI36JArHsjFIoEhYvNKFz17LYXT0TjbzbIhLnuc1X6FGK7aweUu3BsYJ5CZ6ANr96sLdZPef16WeCGsaiq33lgQaA6slCJ2ywTXi))98wWsg4D9xEOu7fghjbHXHCyViavm0yy(k5WKHS9xMxdZ6ARaJAd4Hc8tCyjHE(rUEHHeGih1jBj3hhh(lvog9KrOTkBgyPYg5GFkN795CH6sng8jxREgmLOJcdqSYBtxTI7OdroBXdodzBPOF0Jx30WnPj8cUBUpSSSrOzkEG0kXFFtx5XbYqy468U6cfHfRNdMb9VaS3F5)k7Mr)YlZ)cN1)lxUUAvzD2)nU6PkXfKWrNm(n)2PYUrX6zuMLNvvE7jV8DNDp5GqYIEhn8OE1BKBq4t8Owf2w7yMye))4OM54)pWrTlgfY)8g1X)dCuZCEQrZ(R3OMdH)pnWm8BI0x4phNwNpdtxYD0)76S6g1I6AGIbzlvDNrPRBkpA2SSvnubJwvLDhNpSmDvnXltWhz86QI3u8Hf5x38HpNVACNyOLvdCfe)afU2xlRwo3OL8g9NCV8gFexQuE7QLzqvcmR0MV6Bm9S6fiKmKeQcIOqUKZQZMPAgyDc3gYRFOOs9iVQ2GiCagt)sKX5fLY8rzm)d8IcCIDJC9JGwEpYNJhh)bUHoEHEXbUuUJg5qyB(uUXOQG2k0eOOW55)oWM)x4GsKmd)dX)(nnz3cFMk0(4rLt)Fm5MrUT65rUTm0ixrcUgj8tkyuLmMmlDfeR98l4QxKgaVT7id9iUnqiua2YYiYjXl56zDj7)nx9O9ZKHP65yYMefZL0ONNT8lgAuCT1L53uClpwt(aVPCLEiQXGcI54pKc6xyO73YbC8LjcR0(jDLM8MLzMnIFuBBKi1kLHNIpUEHuVhKV3MxKZrV((GdS(MQrOW4KQ0RB4p1fqGTAfSKYSHhIF5Sp3MH2jWF1Xuncqnfl3bmLuXCAdlVWt4wCPvnaZd6Xq13qaP1uL8MHDsz1TPapM5Ua4SRePzimy8dI2pJeEsd4Qb2XlXjuyqpGH5omfKoW2jGRwa1aMk7Vvdiy8bpIy4rLmBJ1DfXL4)nx9DwoUDeeL(dAQxbjlXZW7myKdFW7sZxc9e9xObex2r9g1zIQYwnVM44waU7vLrIQ54S80DjCvlwJGAlm0UynuPxbfCvA(8xMF915ZwVS5o6DxxNzucCawbkED4O6)31PvzO(61qQWZR)EVsN0VsVw0D1XZIhcpttcEGtWHDvT1edMF9RKFGLXYaEc3QEL0u8EWdYS1v1OXUh3zY34FGZjV0n5L7(WNZrX9(cBqO8DMG6W)DgnlTU5K8QzlZ0iqVZok6SZaAhs7EDnhd9qnYWHWctBAsNTaBOaExcINyHgwnu1Lt1WmQGPpdB7cWUFj(u5cEkWFTOlPd8aCsS4LO9G3OBMnxJEpd)Ng96Y2d6vrDbJwsvsA7e3zDiUb0u2A7GdszDN4MDaPmH4ryOIZwK2mCizbCSuzlbXrwp2UDqR1t4guHMvU6ocAPNFHEgpmy55x0Wbhwcf8blVebSmoD6zCAAXgultWUIQue5eXi4B5eE36Xa2hy11P3K9H25warKeF6zP6Z9xmsye6R)HdyK5GfsJZiVDvTQAF0CC9HS0QzluySECEC(SpdT)VE1BRhB3gLIMQQjR4eoJUiBznx7SeMp0(4moejUiDopKx7wP2WIc0hWGBcE0auP(Dz6r2dkcRwM2KHRGFFb27Y7(aFW9YSRt5q3OUc1nGUhKwZvGMp8blYsx2S4YSkOSVO4Ghfe8eAlWMiX2yainTPDLyGNj6V3F5j4cyWfbz4zk9Rf5qHKRwVQjFkc4ic)jOn8hXVwr)kLodu1rO))inbXs3OZZGj85nMR8hpzF9AkSDwePSkhL8mm4QFzGqd4b0YazDvQSa8GlrvaOCsp)2vCPAAbUzouvQ1J4cCoJK6Evv5xBw0wKuFugxhem6nWy(60zz)bpsOlkQ)dnr1FCB2880)aF0)40VXZDQUMBJCW4XNH7wcPOdOvW4)tcwWlKl1uAJL8bnCoiQlucctzx36z7ZbiZ55fw9zrakueRmAAu05VXMkg6XRkZS1msvEyDZG(B7pzSU0qxO6Yi4mC7yDcoXiDsDRvpj2xVjTkNujj7l1GngHdoZ5UJmvSeOiT6UxLLo)UwAsL)JNs3nHY)jYKjQwkyCTomZM3vov3g6mC350BOOMrepHOrP2zyu4rZeIYy1xZyvSypKEced1f5ntl)gQa9rPgezenwnvdcswjCo92vn3PKnILoxh(HkDqKBeJjTmTSUUL3LeRsEY13R95dyXc(hijgBmBpTgDiNaSDXz0F3u9cuB)kjaHJqzyAjhW)wBS0wlgonuJmFX8nX)sej5nqIptj)0uzE8uj0j)9km2vAuzq1g1SqOOAqcCu1COsgAZDvijqm0UmEhyRTw85xNwF0n3uvQLTQYcsjECqKwxfk5j4e(9jtIaL(5ZgZBxSrjxsAQIAQCUTn1B5FPc)HCf8(2j1saLR499GYrZqv0VjDOXTlY9iDODu9GJHnK2gNFlHJVe8U(jt1e5aB79sKMHKHqly0N5g6We2z4tLW4pQI7GrXjIKo6ugtTIwvviIeDyRdVokCm5AyYaM1juP(k)9kXV3DaC8n2HbCIvQAo66AXe0yylZKpg6uneALnrAPTVOhZxiJan73wcbkzQCZuCaTsrfZiWhqla0BulfSaCpIEe3wukfG3Y0juBay1J1yxOVfiocPN8ZrntnlUt1RLC3voMBRkP2IJluHD3basroVkDfT4j9A1u2U6wIrqzxIBsvC04oA(Q63ZJ2D3zJUucJuwdgjXOzzcM86ghcq3Tcc1gDGaGvlQQ2P4xl4bcaqdhXiUIn4QVtmfUj902yIQhnBwNOacngKA9DGMusdUk0yWO1qEM()1QeOkw44avafmAD1ylqhkpkMqzHIk(tAk0C812ac)DSIOIvKhp7KwWCnaNaDr8w1UChzb(pcJNeZbHI6y1VvWej)eRLYQuPuvb3JwU8L4iqK9mwElHBGXOXz3O13ojQYGOJsHsKj)cczTiBDtv6YDYIGZh1JUsgXnUaOQYxLn)fFX9CZ4lmOctZMp2jeCLZ1oKE)yepVt0CFseAZGRUgr1K0Sz00NJmiRTZJj5Yhm3)PlsRxaANICjPQibb5yybRVYl1zLBVtdfA7Ol7T)4cnV8RZNHApO3aDh8wmUuTkgwFsclmKfhhWs0sAno2nkWL55fh5gtrXs(XCzH(bE(Uj(0jvs3q26ecHKFT9HsGYK2irxfpxlJcvAKV26ln42sHHU0EFzh)dQGdCnwAkiGzhVAj6IiBrvLGOngjWQ7Xdc5ouy7GFLeqqU4X4k964yTuzmtBIPczTwTYZKgFvooBND7RbjAyKuLwLD6Y8MS3yShqJgbRz2CTsC4OGqykIXlry8WDe3nw92NpqNu46O9eMeOolqINO5XPtEeTFENq7X5EvfLz9z0XTXko8v7iiOhbb)gj2jzmApjMZmMyLZXrduUw6LHrhYR1PXNmJkMcaUnPEGH1g516CSe7ZWoxfMGjBOJDgmCX62DzwJyAt0qb3U6WqRLnE7aOGGjGnv9qulktlI9qnMQsRW1t2niluaQsMibciuA25Kwj0yOBXIGfyTBSELbHyDH1CWvCAVawyBFh1(46U1RVfKsgtqZ3HvkrMiuX013atR3KQ148ZZhwG)Tpt)ovJBChbmAPyUxlxxiMIH8IpF3KPltXPs0D0xRhtvJVQCf3ze2afRVDAoTbB4Y20QMflH1cXnytDnFCcVka3Nsrlep6R8bW1RRG)ak1wPOVs5jkNF9D0RgZvhAYMKo))HAyEdDBwtzXnRbYoH(260Izu8hFnlDvzXKSIzlObdhBI7cN3G8wJGbGHYXWibM(mAvv6k2wbRYMLNUS(9LfYk0JQ8UWcI46SQQS5)o2(NsnpVX5dRMjRRZM3zgE8uVYz8bM5tYnharGyHp(oA5HC7DnCojsHQxf4A6VRm5PLWQfTvb4EYS04tBRYyabMnN6SVdCuWqbMnAGzRkyjQIqZZ1r4SSGCFyTQa7waCyPpenxOUGKPckjapORMu(W5DN(Y38R4jO0DY4yrpd2wNKErHkCEXVRckbxAUY9eiTIArSUmC7RiQlSA4IK230blONqhNsKLrRlokaUTaACp8C05m3LTRje3aQ925P4goi2cyrbrWH1u2lCeN3tqbQowU3hiWCDTWZ6AsNMpgM6S6pFhAunL)c4C8YdE4wAXsdR7OMVsFBvzXFMjSYQAa7adL1iS)UOzbxz6D511cBLaejK2)g165d1L6gBsDCYcNWDiUHVuobHtXvGr51IFUKm0RXzpHts3sgVt59Fw1NNqn7yKYMUmhWBHzudPHASHRVJJ1u2GipOVRRLV099NlLFTiV5mq5ezUuCattRUWyDMVsBZRW6Fa(TR7Gfw3J8kCxN4gWGTDclWniokMcJ4BYZXkV4Kq)yF)d39ErEYQrnE4ERc6iofbBlKlxroobpRVI8y8VoqqIHoIZcqhgZpjCpir9cgaejUzI3dIS75Tg1kmhA77a7iO4ibr6XIO9LtKtsyy8EqKm96H32jU7j)uqQTNQETKkU5LID8dejuaSEMVGnhghhVpYCwVt6qSF46uhSNSw8ix8(ZPsFtzyiToivIXQHZ4wj5yL4yCx98Z6rEJfkPJjBcOvLy4481R09I0koVwfm4UxkKv6sunHXyEqcRxyQw13k1N1wFq1Imd2(oCblfBTiUr8tejZ(jP)blfqv6qsG)7iswv)1bpq6t8mgQkvodEGXWehY5avlwDUS0YtvjTjMYoGGj)sFuwkbXdQkmNC2UHNTDckHv2Z5YYIO3N0ctTVlU(RPjO2HiJ9i6OsfFcihnrPvPQtlltZ2JOo0451kqTZOBt)Mqg2wQnKrESgkSmVrIMiMcjGC7Z2Pc7ILFsBG0L7qJGpa7Kj10vi8HTpZVQ4iVybx0TCxNivvB0UxHOTGvhHf1Ns9s12HAAgpmPZ1smRvTMQf8XY6RfO1vhbl7XAT9jn2QcDUWUQCFsontDkqhJ1(jtXTmkSWXq2LUs54Z7ApGKyIQjVKhRbN2KRPyTNuSdcDn(qLmLCQRPAAKag(oFus7eHjgIE(91HApSjAL4svUeXxiS4olF5sZ4sd90kRSwrdd9K1Isx9A7AfcAhwdhsD5ZvRwd5(GsHAiSsWL4hTslXVB1kADV)nuhOqaLO0cOrSOZGJXvYieJpxuNHqHXgTZf1N)NDzUJa5gjAXCxCh5o)EHmM(ykfF1Q1slIL9YmAJ2mDK9UIL)NPHK2t3JMp3kOT2(g8haBDq1T9XzZWyu9nWmLVoShS8LeWsVqgVxatnv)H6tSbnTE6rRzFPUzXPoT2W6TuS4rWppJuEKJs64uiUvosrTt)(hLyStBMIf72yrxPK9Oa6Xisall3RKw9Lpk7cBo99aAePV30UfEh2TFa80IvVth9tl(ygW1LHdyxrhQu8n4v7RxF32rTX8GoqOaTkwKEQRNNGLGbEaTcxBhe)r9e)hVJsM9pyGHn03yaFmnWP2d8KEltrQyfFGt2JpFt(5TTEoHzQvH)1zDe21RVQUPwC7VbpjD8)toRT4a1f0ep(g9SM9Hpsz60mvB)M3wU)naJ9Gcaig6iTq674gWhxwnH9uFmNOBzangL5TLdM0A0jg77RNEZGu66GhxRmlOHihkGwNo4J2XRUBYawbDcA2Vf2RVpsfYhE4Jl1rS64tqwMiuTHV2lnTZoxgQ4BkUmTQ5UnfsySciBP5IZFahLQxWiy)Ej5fQyI9g(jAFNEVglzy662AlVpH3ZHo3Ku(D(Km4sDog1gIvCOYawdFSFIF9IwRBMRXkqk9rIsv9tYyQTRYm(8TMWN9qKysELbmU(4vpKP9iToHEwMAfGGTDIPZaPVZWdnnyesoZWEILTG8PmZtuhX(tY33MVI9ki1(HEV5K2ijH1tLbxhdg7BlPj5wpJUECX(XEUZPV1gUu30P1dUu3TLE2B9cc2tbPO9PBmeEh1R0oAA)ersIdwXhcTzWK3WJocNOyFpMxKArhRwxDHjXoEjUm8GQGwzo9DBOTEnJilDBPWjw5qJxKbZacK7tiURFRkoNQZnarc77QXsL4UHKp4kUDBf)OfktErGW)tv8N7F4)6XX(P2qQefdSn8E7bY3dB238(v4tBkU4TIjAfdXM9)McAl2KI0ay3QnRLOO3TcSynCQHlPcA8He5rtRlRM(GkFITOI6wZaRPaLyYGeVVimdTLmAR0C3kQrBWfrDM2BkE)UAkF0Ap2MLNIfjEEkK4HJXDGOs2SXvNQ6BjLVncoTtPW2ncTwKEB5SA1CYsANwsW0yTnIiuAfUEgUY3FtXCyrvvw1AAzIB9Own1Dl5PDna4bsEAJ(s32gvbHfnQ8NSiEwmqnXmp3AY52mj3sIiBYA8bNvXgJ93Ey()W7Belb0URXMpyi0Ds8ydheYDI7vRQ77Ohf7rjgBUg3izNCTtTtrQnuYpa)20MKSzfwXDtWChcJcQWuNwupfQhyjWFAcyAFCrOhVZW1kRxHcT56BdvB5ryZsWHBGvoIAunUeN11XNB6Md5Caej4BXuI1QJLiuBMcx6y7Df76xTTbRz2dSYydxLllbm1Z9JHBSUzhAPkudexYqfK6bv0PDOGswRwXEx5OHtEDOCU3V0jgQomU9ed9DjALG7K)r3ua6wkT(iBypuhkYvPBbtTvzMDmZZHkkJHZmtPOTi1nZc5hOW0pgvWXYuPRJnzS29Tv4M(fqzWs2yp2BRL7FWjtyW5bytf5z4u0Su)MbN4eBzmT3LQHS7SwQMTKUHTz)AOsJA7Ki4rOKntTve3P2MFS4ojuPwha760Hfto3eLCQ1Zw3A1VPA1UPz0yFQhN(KsyptXTvsLEL3DxQVENsM2nD)hyTy2q5ZU3yn2TZZ364hJSw7fp1GZZWUo1Rdh81tY0QoKF(nnFRdmdipAZKA38TTEcVmiIQLO66d2)Oo3O)qz2)aJFS78hlp9Y2yM(75KL2naK(Zo6ogy6on9O7mg7gJBTF5g6nhM2wQup4WAT7YApd11wb122s9BRf3OFHgge92mj6nU(nTwaGUE3gOsfw9ep00HouPkgi2HFEZg6GZt7(f8DVy37whNEteAVaEFmIJEOvd2W1X8PBAq3Ve46KVfZ266BtrxVpHszjG7hE(p9IQ6bem(UwpylbGTt1J7NZmNUPsvUPSk(rNk1Hc))VyL)BdvaXsUNdV6zTLm)tX0JcNpenx(8QBvyLTBObBeR9PD1TYXqGDihO7D2wjeBl0zZDx2rYZqCXUzz16AU9q3QNPxP4qh1YOnwyGHNmbrEIsasTXV25Wd0nO9sv6053K19RbBn890SbfhKttnVCM8hXjxpKUGDqKVyljXIcCt2ZJ1AMxiDfhjE57fTEOO1J8pic25BUUoroES9SXD8zhKegge4g557lCj9VwNTgVm2u7USGyAFH5g4YCc2ZHWlc9CoikjjjmjiiWjSDm4(OWHEHfweFu8BzlYNTm70VLR2kxHXha7ymViNKG449RByrInbNxsyKVsqelBDVKGdIbrrShNhTNBzSxWsoWN)U(Wov0lkOT5dAfbH7PW1rGbE634gyhPDs93sWrWgOZnGLe4XC3tc2niaEB)KqNeb9gn6DP5GHQSdCDOldmABzMSFDGy39XfwEoHjrOwd3s70IzyoUvQ(XN5EaCNBXvmDDD3ZteBNwoDulFjGDGlxDniYnkWBpj7x4h4EGdNT6G8u091XP3OXvcc9pWh2xQXojUH7jBpmGRchgM475fK4ftbS(U8zvL69axvf6GKqw8EBSg74IQXU82pjXN8i)bSKxADblIzyZTF9bAQa37CEbobXHexI7Hxx3j2dfcXrrjUj7Pq9f(CYdau486eFAZtGYy)wwKlcO9WGnfxDCHgElOqQpqu992Ou66Rao3ckPJeJ2D8T42RfclgoV2GdTE0tYySPwx3E5a8Y0MuWr4z47iBOE(PyIdvCmPPXNtN(8c6r4cgpXbCjNxY2P9uiacCsBK9WCYACpsPRcDUYjExIr7kfn4Gat2LzmiB4enqF0(deLG4g)t3zUTJG4nERu3VgoYdJwJ1x)uewwgikD9IBCbKdhh(WDXjpqYTh1Rl9WYmXEHmkEO8GPCGcm1hSr7CJdlQsJ9JqB19HRPGG1YdzTCq6WdkaosmGQ4kU(Ift2dLj2RXlDtQQwDAAlNa7Ql7smTaZdQMbt1lCu5xYQQabW6BrBHcrPted8DJFgz05B)5nj2oh4O4PK94fvLRVzbXyTudABxyVcPGAaP0oi0d1v0m)50gGALtjsWB(aMXF7jhUNs7cF4HUa6zWjEbhncic1DbppBsZl7BA6N7q6UJUf096mLn4N15(p24jPmTHZMDDBy5PR0qP(ylFk86wOBLu0GdS2qDVZxDhTM2qpAwyFSG8Eui1XAlkj2zNQF99qg6DUXZJ1PnJZ00wUDNlt9BaVe4zqfwooHOrYl3UgAVBVFCuhOth6fyaZvuRtptBSiMMaXTQn9zxMoFE7KKl1haDoTHH17fAlz3UnjeBuP6(JeK8l4)9FY5c4TNGMclD0vdNrKKsgbdRVE)SFJCBKVvhOvbB7r2bGpDc78i5aqvDU9KZoK7HEyQmYent)WX8hb5FaDJnU8dTjnFS8J9KI)Bbswuw09XdG9atS7eON3IUW)YRH(NX)hc)F4Wr(NTBa60(0Ain7JVblXQAcZh3E5bF(gW4TJNF((f)h5JPtfX6dLnKqY64BateRwxdIem4WEJ4KgWpgvW6VhU2gY9Z(KFZUl8p)H430MZpdVJ7NBpBoZ7kIdgvK9f4Uh)zVEp717zVE)90RNTGyFWz3O7FIyNdKBtWOpEPOQRpjE1K3VO(Y18SnFC7SlRXA31SS4d3epOhR71xC1B(3x8(Xh92ZhaPHYDQ7em8dYwgctB7bb0vM2fe1cV8EZ6O)tXNUhHv9Sp9N9P)Sp9N9PF()r4t3t0a)T0NUATv8tXbWJ7ew1ArTZy)2NKNhc(4pwDlnCim0fDBF9H9fuEpD21hOEdO62rF)R3mu9mW(Za7pmG9)2ntvBC(T3KdGGFAoa8cp8hZbG)Oj1PFbxOiAzfAlVG9DTm0vVC8ds09J5xyanO9ehVREqIASDUDhldw)BBO8BWPW(6G6XjraBlvIN(0aGb8)a9wyjcSNa3eByv88xsFfEIt2vR7suBH3TpUvEGUdEaH1QIl9EZfJ6pyLT2EfS(PnnwHJUkB1t5O6VzLXuTEM)PeaWtX06jUDR3zp97LZ0hNqaEUcGpxbW)276)5ef)pWz1JnWU(5h034p75YYCNT8ds8BNi)PfUsN9tZUfmPj44E5FgVVXFK9plUxj2r)Z2ndEmCcVh5HpybE2Ryh2GKEF9U(q8GVHG32Zc7(44U(bMN(4ZhYzT9aME2D9)p4U2wuQ)L0zncWnuM628rylTiBrj(WCv3zMGgWjTX2L9NYwlZND4pMFaBSTFeFapM7AG93DY(cxV7(4p)HHTBXnlUTe3aW(qheI2u63tK9bGt3j4DkaMFOCXgWW3Qr(pviEl4QpUy87s1y3pK8ook)RuHyhikKojJXij6UN3L9OiSDGe9qa4hEUv2NGjVxFtP)tPqDpptDpptD1pptDpHohEQJ)Fx8n8Jh4)FLCqSlX))FEZu3945Ry75yrVJ4JG2ZfdjLEpEUdRDUzDvwD56kSktWUwlcpe6O0nsgXBSMXCR2xvip35OZeS3k(CQpUPkDom0nYj8MzZpMRdopT6URqbBKqF7ifEGXHbSru(EJQHdWuqVsHmK02ta9egXC8Ccd9C8PZOdoofEAD(rHvV8HB7qnsQDafm668LlpM)NEUb(QlRSEVXr8hjjaB41fWPS9LLTN7vSiXXquelGfrhET7ZXeJoRUTFK8RxHdhZzcKO6RGbH4EtZpWjrCjZ2WBf44CSwY3j2YNkEraWM4k13CLGfbYYX53IhgNY(74oSpI34Ne5f7Xy(r4X4d0ieHP3HhxWAB2pScoD3irj2lINbNvZgOp)Km4dnU8Xs4uKuUsm0XhxkwLmQJLDFhO0e6XvQnr4bPN(bkhq9aFo6qbGs5xF1jVusduiGT6FDvNeCDU8okkHf6fg2HliBzfPscc9gLg7Y5l2L53PnELYRq5xpH7iRiBj0sa7dO(JfVpOgCKmgvjfYDh0DoGPdtz1rNmjHeeZyzlbwf(9Uo(IgDtwrwv6YVBdMZyMMDGGAg3HBBAxQPocNsOy7VQk)woJFOkCmquSD95ipic1Hu0HCIgvQ7CNoKrvNgMMNhH6N(IezRHo5GFP4Gbv7O)SzbFyVG7sSvG3(jejirBWVnEu23wLwm)nx)(sjk8z2XxcWd(UagxFlWHo)E3z8LxKWD1GNCFErbzVWrCiSzfCjwJnjXlIbzQkmEb8XboH6)dTKSerMjOIDFV9SGnn)fQ7w6WwZ4GomB4XD78zVs9zFXAXz2OMTaVZcr0Xgou1JMZVN8tVCMyZqzpMdDt6wu(dBv41dK3vB0bhBZ5PlHw7mDR5aXzlhD2A(t1aBy7jMU90zpg2tCDaVb0bgYnAOPQE4pFv9(E6EaQ6TQ1dOIzrBSJg7duVFpuFpij0Ug8q2ID1F5ruKXDDnx4JO)OA8oRehcI4JrEPEqww9qygI6gDryOspEFvEdTO7gZdPZfU1CDyEjQ7dbH)AtTArKd)w6Y1z11oJ6PjBZNIpD2hYCIyrr75jNi63Mmpy7K5GMLMNim1v5RK3tsmS3NTaStMdkm((kr1RAnnELSZ4V6fBokKozx3XGj04sjU1WJP6uHrS90cTaHMa0KCE0D0myzBqnVDiFKjh4yZ)eOyHaQSCMsOom(pZx9nNaseCE47gvnoqVAy0QbSLfl4WU2YXah431awugXjhE)9I5fs5)O(70CzGHeFuDD(nf3ch)1uvo5F6SlRk5Tqg8jUJcXnQqWOMQ0zFMZIwF91hlp4fXtGXVJ8zUuIhKSYMmapQiPOTDz0xp2IdARjXg055Xi)XgfoHUfnQFNh6DPFt1UQCT2C45gbY3TBFLqnYaFPB3wqPMQNGmpffU5nKWMRRV7HDZPZnkIhOFuKxGtCy7OQD(B7nQeB36Uu3XcQtHM56W7XOeFwe05W74HFhk2XdWB1TmhC(KYdbo72C6SfvwcBSul0jHo86Vm)l5fz)YhwKNTCUA0xRDtUqNH7AE4D9Xtv4erWVidKERpkma0YcnI0dFZllc9fUt1PRZ6MSSroPKswBndXVP)Lilhcu7sPXmj5(POYs6WNXS)qS9(rr0tOCKePeiSJnFy60tf)tAcXtApNK0avptXU(KuLqNJqvXswpbaPJcGQW4ElQxU4MPrNGPr757gKegNCOEQTD6ovPXQOHwB1cNsoJydC)Wjd2XlbpjF9CcyrbrX97H3YvWQlOt7Bq08EXLcANHnClj0gC4ReIFj2yuimE4(RHtlBtlU2K0bMV6UcwsKsOsxMlJXC4U(d4aTIZvkTti3cgfpehYdtFhHlteMttcN45h576nXl0NI1pfbwZMlEyUVPa4WAgA3y5BfmXnHZv8Me7oWl56fZOdT)o9vcVVcDs2uFv4Ne35v9NWniJJJNWhM2FvMRxiCQsJ)sipw9cViM4GYgm(HhtE5BXzbYVfloM274i(lSP4)LLrGVN3KGi224wrJw3GUVT)GW5NnxbpikWH)ZeiYc(pDCDH)NhmtryIVC)9Lbl5sXlAHG454pHpw2gbPERi(BfgegojoW(BzkTXoHZt4c9DVpiwvu4KKqVT(wMDvCaNYI3nnKy9XualKnjzafKaVGqol3LBlhb)0XxCEs7XdI92YV0(KNl6KX9hqX8ezM4enatBtT15ijBPjJc4geSb0QFynzaZ3BIVxKD(a8ssEV1M)fmpOXFrqaZ1kf74MmXnEGM3MUa36niXj2zssKDqgB4emF4h7pBPFxhh7fpjm2UfRLU2lGRfnqxRp(8gnzYnlkRBMGxYv7AZ746pjmyxPMyhxNjbdIZ2snbJgMi4iA(mVaUCNBeeXH5eWZyKl0fRICA5gOb8IcWx0Jfd4u8F4Yoe1uG0cTbtzver2GJ1uHjZqL625sd0XulmhQWtrtBlW4jHgcW2wGBIdJd5aHH7VotRP09I8Gbh3iRGjAhzIgEJytcfzomRZXiBkoHQyBZJkKLaq7Od92Oa8WquVLcO9Otg)MF7u5dm0m51E3nXOIWkd6KKKabdKeB3ijo3xC3C9KqtsV(pyAj8XJwKQ8soK)oXHekFpzCitPM7ortXbU)meAwJC8CCQ8fFKkL7cZKlH30DuZ0P6xvrSrie3iEYljjIlHhglEFV2tOyGgjVZJccpO9MWXp8H1wYBhix3iGUIcDbsZDVBR7VNaEVUKWgcb()00LGi90VTINyv9xtVd5QLRBwYZwqKkB9Iuowl)T))o" },
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
