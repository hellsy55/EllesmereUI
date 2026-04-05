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
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_T3vwZTno26)k9J37dXf338t2o2jPCw8yRU7KPMQurjrBXBKj1isLe3U8)97zbGeGeulootNEA3vntK5cWbN1VZbGa3FELxYTz1PWpIsYwNF100fzfwhe4D45vHjvtxLLv86cBpplLl87fo(bwh(a(213Tmd(NRxVyb(aFjBvvEzrH7H4nNLsnTTtY6IfLt)8BtVRCD994dMwmDE5Qk43XjNE5XJVO8RzRG)kiPoD1nz1v2H01pzrAv1LzvLRxnndFXYRVUkR(targd)NBuCGxKNBOp1Hv5ZYGM44pmA0hEx7t)XIxyDGLLLDKRTLVxqe84a1BBN8BzZZNUi70VLxR25HjVlnV440v69OsN4Mm6dxO2d2Hbheee476554g5sTVBYYfP3LT6K0Q6jPAdVaXT6r1pq8l(P4)F9xJ)HoDH9BSVNFumWkI2argq0yKvSvKJLR9HCNDD501vgOrF(o69LRRRxGVFyGDODu0M56KoICKUv(7l8pWZoWpWl2Z2ZkWPTT9sE7PNnstEgDqOVLvGTLRVTp8Sm7(Kx(UXtllxmR8RfvAAt209wxNViV(oTr0g7g7dSdcc9ISAuAazAxrIusQmuSu0fCISD2I2zG)brT8vhMT1x6VNSn)KlFZRET2ak8aRixhF7yFxBhFbxJBDJkP912SrnaxpxFl)i)yVDqba49N(pgnE0Q0PFwxnWlbglb66xa)oWZ2X1NeSBu4qkZXXo2T2ZKcBFgNbnzB8LBzBBWOXlMC1ee7f545achSRSs(A(S65VlTE6877ZfvyD4WhDKb3agTd4xRRRcfTkf)Jd9Y6MWYrlZrMNLFZ8Af6uZgPNHHUWsiHe(YMNwuxE7XLRlMvD)dKoA6SzLKLMtqYPlwKvDB2QSF9nNiA)3LwKEdjZbM7YSP3J2po(ou8MBtxUmV4MQ7PaczfPtwKn7mA4KoTgIIC866AiwInf6z6SBVArzn9xXYhiDL4VVzr5xpPCrj2v2jtq9OdXFDd8Rih6N4JsHSksVfKYwjhV(6R)L3d)XV8)KDtYV8Y8VKxK9lxSE1YYQS)xk0yjPxF0jJEZVDQSBUQ(oigj18a3f0yoBv5Tap8msVWpPkBr206SzVJhECVIJ6G)goQTT8(B3O2jjW)h8GMVQ2qM5d)PnOrr9p6r9pFIA0So6VDJAqb)VB(Y4BaJaGGVOSkhPDo5fv4M(jllZlqCtNC67hD6LipAv2Il0U4d4ZnbO8kAKEhGJXcr)H4)IDTOuVm8AMAD7KVjGyb0bG7P82XEJDcDJIIg7rrzX23oGX6eA5ez58iA9Web8ajbh7Jztzz5a40aSN7xtg4CGp(Y2UaKQipM36cVF1NbSTLRMbWogrS7AceYmukJiNUNKxsHJuZXlbH8CpPpcqmwS4nVS6(cNiaDBHlan05WIiijb3dlCc8aMaC1yl3Oa4FJSDTSpSWZJGnJ)RJF4Hm6oae50pxDv(Fakky34NKpTSGtxWXMV9O5arphe)N2Q57NCZQ0z5zf1Axu)5Ve1Pp0WnowO27415gVl9BkTNfWyxUEbKhq2DGk4KfLLZwaYFKmVoFXcS9J9dIcabEiQpGIi3Kj38kI(71TVs0Tn2Wi)Vlju4Z2PIHh(oKzPtYY0Izz3Mp9vGTfsEHAx5TGnzvbnCd7pQkSTiUlAsZCxEiGCIqhaBUDyeKYINtZt9r6PItGw4RxTmD1Nh14sim51zRkZRUTL8RASwdsMcKnIOoqakUWruMd6b52fEpuqZ6HK4xu5dw1IvSyM5LkeYOCa47ikJd8xYrc2uI21LVtd54NScPbkrJLPtbRl2JKdnuAEmVKfzxx30WIglUdJCuomaQSs6X8VAzw2Scptc9JO(dhihtnAerT0q2H9bHesRfGKp9jbhPo7B1RxHjMvuwKXT0rGuZJjWVKTQoFA6IpSc1wsXbZzi3IggTTARc1LcfkW6sDemAom2anOQcNd7n8mHiI)3jSRR2M)yHnNpN4wHtOqCZooF56venw4X8cuOIrwg1NL2e9G1upsgjr2tVmFfAI(6pC5B(NF49Jo6TQKrZtJm7xMxHz51Wc5geTS89ITSJdC9cDCdcaFKStsmO5xYaH6u0Y3oXIuyQNmPnM0dIqTcpMoGN1sM9)6SflZw1oe8zMngaeDXw97ZZkEtb3fJOgMU1I8)4psxHUeGhwVTADj16fg4OFjV61WB(6Y1vq4t2xcxVVEQ1rjFo7Uj5fGNpBw8wUU(dxFzAXnzFauHaUZz4aQy9Txw(1k(H8KV0hezO7COUVRMwf1hJzRkG(o(gfFOESdeuL(eiJ26ZiPsvZF)kP5yxVBnJV3Hpg1yHjti)fhlDVkEI3xoIkcGYJCzJ)eWMhWw4OB55XHQf)xiRQGe6jZXwQYG6yRfUfpipAbMPUjo1NkEXgnIMW0FJrKaWfqcIMHTBT63gko59fJ0gdxqyxppVGn2OHXzLf1TUa0y7hlalYTH0h1NP4CnqTyBbsJ6dkLXdUiWa(T8Q8jeCfS(el(kyFb3kO5TB7ChMf125A0eBiCur(TObzKp)WaCY0A0xr2hko5LTHEItorH6uhrxQ6N9aROd7r9cN6bIbnvDhsOa6nowkeI2DagTWDayss3guKMiSwXagKYaRskcxX9EKOZhv244H1a)NLL3kFiXRZQROMvBar7dvSW4rhq7Gk)hkwC3BkGrEX0SQZ2OZLn7Kpkzo77anIoTfssaBkiy0JGaqJAJ7GyCgmUdIO7R5lZyBdaArRL1iO5QZx21()ts4an2YNwKD7DkMYcWuQAkh3)sxkYVHmXNNUSnG5GXvei10eenDwlf(XMlbJIZzXXzkIg0d2d)W9ilmI(RNhzn(KQlzw)UfmKcx(zVWn5cE(psFWrDTI2fxWHj)QsvSF2b8ZoG)ZXbSkuVF8(F)llI4D2)RFlt(z)VIshE(psVVpoeW(u5yFg97ZoF)P357gno7nI3hdwvVYMmFnxO(bKqMSWvDQVpvktXb5g8r03YDFDBOzRTrWAxusX96PrnuapGOhHl2mGifSq0t45gJrnKULHGxg970l81M81ym6MUheJoi0DkoiGG(UF2XAj5AoW5aEFF0(wme93GpwtEx2ZaWA(0nIwzOOXM8)03P)(54ziV0DWv9W962S9S(8tkY(cV6X0G05MCZQYV(Y8vztfZxGyXCjCK4MmE8nZlRQhlae0QhicALx9k8(hNItmrR9tdccfvfShfgMWaagrZYk(fkY1JL(LTMLS1o5Lvn0UvdTpD2Ut4AfaSdXpe76Hh6q(XjRRAQPTCMf5j(nuDfmDCAv(0kAWFnQVpJM(rJ2XdeZGmOqNkVbiu0YZpbspn7sjqnGExVSQvZrpCHqLf9Cb6I40yVQqFOetnNmGbBS7t96Lz3aSaz3Q4E9alFMd)fJE)XzThNJmYsSAKIZCrJpTXhjo1iQn(XYNke9ziOjE6wQO1uS9HBXtg)6n(e9fukoE4jJRHdESAKFWl2cWoV5MSbRd4KBDD5rWWzz9zK87nfFjVMLxwKUjnoOzInWLDOCTCnjuuKTIEshuB5iIPmkDYifFecWW6ylgWDiiSrs9xliroRhQqde4ANd1ViYe8d8zvfGi6c(TBehADraWuQhwnDVLFbSuhEYQua9t6SmCAoHW)c70PLlVJxHhN1v9TNG1gxBMf1FyDnkU4PQ0uCttJwEIOabWzWLNFMIzadBLHzJ0HWCuqXxP6wjsDCCQ60C3xgAr0keVaC2WclCwlbw5TlRAJOXXmVklD105C3Z(hNUaWHHT)VE5BR06cf)dKL6Q6SciYmOUTOcuTkr4m9nxngG96gWyEBWKoMKrCGqhllX69(FVgglTlh39WRMLQz15sVC)tGF8pW2SI9WIpZO1RGmEUAE(11x958LmNz800L4Cgp7dqNm682Cqw(w2ggAWVwUAXmq0ViDzL06PoVErwh4NHWq72LlYqgIoUCV27Oo)WwhWvsqDkIr3MCQ9vztBBg0FqZIeWlq49JyBvAK2aSD3KLLYv3JTT3bUH(wroHoEHylVhRvMWiGQdSCdCJ8DW1kJ6kpyG6UCJwoegTX4We)oYPBLBSS8Ivz31Cn1fhq5K)pDUzOJGB28Zj8p51JK2ChZ6ASsWFaAlAmrBST7idTyzU5v8yCR8ZtUEDA15iZdqCQtTwEHnVFeT(g4giWH4QYvfGRL1Wo2NLT4lAKoOQVi)McWNynWRQlxQTkBaTaGzQnuzEmXFFtD2Tc84)B5FZ17sV2DeW3PRxvXdMDnKJbRxTqX7IVxsdyE23acW6Kx6e)YZrVh5cNeOdd2gyAAv9j5RMUiRZ6amibx1dRRa26Hk9Vf)xPKEAexHgUBCp7OWZyx(v4s7rfD0km5D6PkkxDB6cJet)raKlsnGDFoZkbyxtNnev6yVBu5z0)Pst(jl4fZZ2jPZ6ss06ClFb(OgDeRbFDahoTRghWAcjQXmpIq)EBoKXA6Y9ZtFizaFYQ0RRHM7dyePZ6gKhYqTC6NptUgOob)lZo6dXLkQy20i8zwuZFe(1dCc4SoDvnAeX8GM7OethY5N6lCuH2A2oZ1cvEirePFjBgNrhliPe(GW0)71PRYmBO0jtFl8tCdSyXwz0qMj(ejIpIGczjZgZshRkg4IcFjad0OZLOAEfUgJaWfSLKij8vZeOp5(bcncsx8krmsi0DkivAaDSlQi8R(oHMMzupORzqZaUScpV9cyGvG2GqetZPVYpzIWW9VmnF2lZV(68PRxupOE)srXneXg98d3V4HX(8hzNLBSva(9lHjU5yRM4gISD5IuaQ)906OKZEBXDxbS2xMDDkqEe4xMerZgCrjFjA(IxyEw6I65xKTcX8tmbWTo(eS2lbjou852GdRwpuoojZYXLjiw7HFTkdZzTbclJv8mbT8(loHQqSd56eYa9xlYXLM4Q1lRZNqUr5OwE(nbTe)Cc)tE9iJficPTpY1YHLhXiftRTWE3Yv2FVMH2ylkeSKlaaXaZOm0haYJ46VVEvQCXXHQHTbPbYp)2Lai20c6ZEQTmJUmxcOdjf(ki5865n10YJWVw57N8gCCdjEL9Vat(puu9VueL)RBZMLN(VOh9FD63GOPvvGY8bJgDgLINu0I0k6u7tIX6lKtzp)jyDLI)C09cjHXIl0zbmc63GJ4zVdI7imJzCc28ItvLrgPR4ycMIeJcVI5T7Xh367GXar3baNftLFe1kugC03c2junqndqkQfFJROPGClgLw85JUbYbTr9I)aofy4cArvHFWIpqmeHYV2GFWcl7qvw6nARIu4IsDaLlgQZ)ANqnqHJqd9UYjQMxNrFGz902AR4TllBvuK3k)1K6lNPKCQ9iRCrjOLGQfJP551tk)gPz9rPQfBDnQD9TkgqTYStVDz9DTewAt9nflLAsq0ILMecru87jLvvnInF7wXMJNBZZhZziauokhgPTCJBSgph1ErLrQ0P7MMOF73xO0ZHLGhnPeIbDRbpnTMsanaJcPtj6MKlM3GH(NWvSGgxTJkB3WMrf(BMiADVYv0xKhO2GrlpqH2RgLbEIZXSdvwH3bSCstLu7DWVh7Ip)60kDZhRwVZkFewIpgzqUpTJPqaRkKpTXsKrtO4NuZWrsqVfUzRxkoOX7BwB2IewAfekrQyvsImAH(h30WNqli(Tl)DzfQDsxXsrmXdVPthuve46sN4xGXS)u)OvVxwrSn2RHkwzAIo)Kpd(iW1hV2mPYrgoAfewQLZekdp2MJBJaU1JASOdBct2rTZwoHs65Fg02wYFpr87UdGJVXSpcROwVewkAC4VFGgwsMjmg07ExUmrSUAZl6zfjmTq973wIib1vXJAdQOKKVDm7zc1kq9O25QYN(gQpcSiLsbXs6xjWvdKWQrkSlUu3a6dz8)Zjnvf7oLLQs)PXZPrfvPgrbjgXb5y3XcOJRlPgZ2v78vgxkwyasWLvVplD1UZmD40O5Km0sGvXEfDeOAIi8lR4qsbdqppsrAadfiYA(muuW0WmffVlrQbw3awGbqJ0qiUoXcCfnWDVmlD2DndG4wfC3w8UocgKMd6pTjbQgnQmvmKGIXJRYlu866QJ)OfQKVs9J8vWIl26bcnGo5CUAWY(9vPlLRw2gmO)ov1jXeSQIrtZBvHmNg1Xfenzkz81kcdBFsg2YYFRWweMksP6)Y8qykCwgA68jf7vODYwxVkDXoP6svgth5NyMdKr16OY0YsK3q44KIKRmz2yWKSgNmIkSPb64t6(6z36nieW2SXFY68Zf2agjlodTrTXfAsbVbP3NeWEmM4t7AmWx1sERUqc1SU3(ZZZLevNMlYQRoRv0MdjFtPxqClvaFXAqzL59G1BOEv(YSzV4loN3fW72PKaHWHIUV9hhYToTAoIWE7pRxh7z1vn0Q0vzNUiVo7nDxH2Gt3oy0A1ABSyf(TBSa1sf2tr0PGHVnvZxVPxB34d2uqT3xAMoDuSUcBasQhxlG6UmLj2WvzGA30aXbKVPy6X1Ycw1TecppqysDUu)6e54HdaPiOnMrXgwgKsHU2NdR8II6SW1hombN1)CLYF4g3mSSBhwwXdL(wlZNr34yh45765e7f520srroH(o2UUrHoIltHEIJTdcGmI9TJ5cSa9qpXo7V22xgwS1zsNKmAIT0joL5fSL9H8MvZsWySnnV(kVhWbB0re0bVlTsvapOkrqSfQqBx5ulsFNgw5oAzEG6lhTyXljDeYHKEjO6aQ3uu3yTYJDbTZ3yAv(26KnGcwGdkJkKQjlU9rT4tBve6HTu8fcYUfzsK)Gc)xYmqvMi1srIWGXLyYLa9ddc5xWoUUmwFlkC41xIO2TWVDs4LOLdm4Ubli(4vRl46NxJUQ)m)BEggWIi7KSGxzjFTCDHO6V5fF(UXtwKs1I3j5RvIjbzv5sqFJAGI13orSuiHaKPRQNVa36eUHAQRbpd4RIU3tzqcrjFfgaxVEf(hyT7kf9vkKjD(13XVAeiARZgNo7)JByOHUnRUS4M1izhZ3TkTaPbCIEZsxwwmoRy6CEWa(PGOrqdcTghey5QSRbyIGxdKMGha(N6XRRYMrL2LM(9LztZtxu9(Yc5CAikgBZl)7uhDk3p6nI2uI5Q0FWiu)jbnkuwi(IDFhVTsC7D1al9Cgq7NV7yKPJLRh)uSL5vTa)0MBuaEGMsjqVqSCIWHqhsxLMuvoahZ0CsGEJ)s5ys9N0DNa4vl)64VMD3kOzkjfgiJ9YRf)7cwwvrlNHRlxDR41wKJbrWjlI6qXKapbiZSvFEmtqS2iU6hwG(PG)hrbv3bkqL1K6ebs7A5ZZl4QzmB6EuPanvWz3fFW2I4QpoJO9LdSI5SOWrmJNhrZtgPZQ9rYdkxRWcGayuRtbbX7o9LV5xPDES7KWyPaDBAFZjmmOXTQl8Bo2mTQRKFic8NbpHlmJwrKIAL3uOzEfZ8nvhC8tO66u4tTj8n79ElELO428UM4fnRLahFU9255l5fUyoHH(Hr2o(zVWsGhaRn3XYDGK(kHN11RuAoPkv957i)ctGxGMdliq(TYnGHBlR)kF3vLf)rMWrXQAEkovmZc51Tv9Cqr7D5vvcZDmhonJLwMm7AvBwE(1I86ZqvaAiW4VMKU6d67Kci8aySwtMRojoZoFZtaawlIQkP4psu7pEJyBKCtLdxGYfYGuTb9evdPzg8r3je8kgIZNuRP1Kw8JIzyaFxE8(rrYD0l)PIxiYkLrGXpYNKZvjzeiGKejclQ2P4auD6nukXuQCRKOjfRgkNdgt6hS59TPFtmoBGAt9Iyme0Di0mwvj6pkHrqVknHM8K5cxjB1YL9jWMMrDiXnd6Ex5ICDLK1lXriHFTC97GTsK4ITLwr9JQGfMhnbC5mHbWOTB8jAjQN7ZHB79ZALa40nkFMZBNyX2D8baW98gRHtuh3KYeWZjjqHxRnZfQ0eN4NgzYAccuzA35tsyPQ0ojXJn80Y9Tr3gdioB621TaTeNyRbpid5BMVyNMgmm3FkFogmk8RcTcBRj3C8vL(TRk(MN2K1TUnHLiUo)9cOww1DOKSDDB3Fg(3OVeL7j9kflmEmuFyjHijcIBXta4fIHjN5eIVTd3JMPwzkh95SCljC70POwkvfoqPOw(20ejHfjR(INfZ)vrm7LiNMWqLPFtjpqdrUgrL3qgukFwM6NQMPWAwSKsXxJXaD7(WpUr3uX18zpHc0TgD1reO6iEpPM0aWQH0Kl5GsJUQT(a8zaWj9sTsGJWfjy7CKywLMN8j5key72ybApVY8pTPiSI7POS2uqidam6g0IAN5lv4ynlRdCTn1miUc3RSANGYDWgAtGw2d)owjkIrLYbi6GMpzWwrZUacIxBukGGS3dqq99My3uGTj0h4YgGMyoADF)f7nejvwqZhJ1U7Z21aO0MpKSb8hginZplFXcDdAXhGrVPTYnwutknLQTRgyec2wbU1B520fegRD1vLxpuuGa9v3fsueZc657U1KYqMbui4MnpDBZFLXd68EeLZ0SmgXMuDH)i4IACbrs(j1tOjFOZxDrd6pCimmSY4g)JnB1Dqd28Pp1SL1nGB(yfUshcq2UkoZFCEygqGyROZ3S9)1FTupmmBlAKsTrJNKEokmzN4HVyx23N67FsCPnMsJwrqBNmWHZHz4SrugpCp31gWi8d(L5cLCfi9g9eSSNmGZiUL46SSsf6VchFwgxSbSBVE(Rg(JH2b)YNX1N0BkMHtSw5gwYD6(F25S1n7rjsFYzy5QCYp3Pqmd5egzn6djoXoXYyOBGsRwH9N6DLwZ6oTyluXhTlFNGE(TuwUwHCBBknBXaz08mS4G6F7KdKQTPKFf2NnLSa(TyDEQhxmUXfzJ203fu4NGfbe4YhRzy7OCujvNmU4UkRwfKtIobXai6sWgDUyHA0e8aNyVbO6kqrJklcw9qWg3y(odJnCy03gWM1ZAwlyvw7kEru7q4QhFJw9enxEkvzM6AxyJ4VgcOQbfFDpyrn6I6Gx2Bmskot1BjVg0aDu2PUwXDClPOh2MX3(MIlsxvFhxpod570nVY4Mw7Jn81HXJAXIhDFkdhlXPPXBfXnrnAs2PX1McCJanOm8n8AuqA)8ULuMJL21FBjVImQA3gFvZ8CRysJAnmu5XTmlXgsTZa(l1z)xLtNJkmL067Q1nfZqA5roHd0UB3v2GzAAUGRbkX27iSXGwTAcAQAX6UyKiNfOJi)GI0SuDcUhjuQcqS7wIJYxoJoG3MhCVl3o7J04()S(snKcTPSMyesUUwY9)SUgkxZnv0GDlpuUk39Zd1oQtTRfzx13HCdgd2)b(ff1nxvbcV4bul7OQnWhVv3cZ0azE3)(kC001jlhL9z8M1sZaLTFWs3yOSDNzOGwEkALkxUtzSuct(OQJwFWI0RJR(iQ5EqB9NAYSyFl34UMXApyx7rgSFFi0mKQBNS2D5RUpjaB(JY8rk12qr7gmr79fzNPeZ3Gx6obGAZq1acrt(S(pxXg3X6bymh)HGI2VebMClTnCdgq02fpME9RAdlTdqBvQgXWoZgYR1(wOXU(3nvBXhno4EfWy)rgVbS5BgS2qqQ7wdfJ1nDqy3Bgi8glPy)sOyoaZgJ(pqmDZy)3WwlNzqkBnnGDSOpgH4piAN9eR)aXB7MOtVzvY00880GO3CG(bYjXeY(9ndQ9BIJ6xNTDfY2(uJ9VlC8p(uBmK4uxaQBhL)gYCPBIP7uf)6nPsByEy2D089ZQPhw0nK42ExmrTki)Zw1d3qnQgy2f2qMg2nlidwNMxTI7ArhvNVGh4foUCTPTJWWhaQ1p5OVhgJ52XL7Cypn6THl)XIa3WcMBqiWgNJRNmG6pkiBBC5o0dWUXCS)zdX(Ug9zyu8DTxDDzpy6qz3KfVXLlqpWXMaXBaT4Jfd)aWM7gYzqiWBk1DJts5oaKFJtIP5CJ3Bm9Bed9JE2q7Mb2Gy47HQDdtJQza3daC3mq2bQh4qG2haLC3q99wjyBi0)3hS9(Wh7H56PfR(grBVJi23uUpBEbMTd5(3h)(qy93pG6MRqGPv1q)jVEtfF)7eC(aPbm4CwTViWzVvMRZU502ECGWFQQQEFC4gYTFie)7nm89n3WnaupioYYn2XMolsnUzAGNYHwHrEU2UHU)WqVV1A3ygc)JpjrTuzEK46bql4hxdoEoJDb2EUddkfmOFH229M(cGmF4dBBZvTVnPb8i91X3gptFT9D8JcJ4V72Vv4fJFxSXUrXbErEOyBx7LMVpaQXd4ON7X3TKLv3L)g1q2w8jpmEujhfEO8PTfhiXHwEwr7bvQUbAGnpDgNSh0zV8VgMiDT9oWgpthDdIII2hwPT6cAQPtC2twQCTMZ0Qofds9d2ZrUBezT2UKZXppTOyXq0gKF(IbEGfFMwgzzB7fhSZdCEYmKBtNYV1lPgXiHk2OgH4OwjXOUA5N1BOpss7J6VfcEK8OjxSw6xUUc8a0DcbvxuoXHkfKq8vRtvKWYtmPmlxvUHTifdFlIo(nB39No7MSFT7MIDGGSuCok3KPuEn2x2bsid6hE5EjWy0TrjWtOGAh67eVNBuX2Ub8zmU4LFq06bIwp07Gq09cO2gAr7wb7tJB5zFqCqGVVtORNNa0W)yD2A6e5O1(1pIT8C8bBq)9Ci8IaxqqaE7cI999TcAgdopjCOxyGfbJIFlBE(0fzN(T8wRXGOdWJdE3qRy)OO9RBSdd5JxD34GqVwbrKS1DJ9picffrU28US)E06VWo(ap4D9WWbU8wFd18(nIGG9u4kx5BN(ni(QWYJ2xtBi4q80XhIpf77A7SNeSJVp(2GFhRyb9gM8U0C06UXvQfh9GJ9fVFDG4O7hewUwbXIpJyNKtlMsvFyvB)4z7CaEa0dkMooo75gFQvdNoSHVarSDa1v)qNqF39KSFHh4Y3cyRwepLIIDC6nkCf)aVd8WG)rwXob7jBpWhuHdcI9CD9HyGmIO3LpDvPApaQQyhehyhT3gRrwoKASd0(XXEmEPROseO0f2HocRHiFad6E2hUXcBjmGnV8kdsUiRwv3jYLecrHHXoX7Pq9fEH2KdfGxh7Xl4Fsg71WICihApo3Mw0xroTvSlYfRBSI2WsABpGCGLErC0o6uEzADkgHKRASSz69o2InFz5HrcTXplOgrH(OV6FXcyr2oT7ea4oZ)ISP1qGU0vT2UN3gxUBZ4402fDPhLd9hFExvjulC5Jk6U6y67aKG4iuxnSStc5frM2jFSfUHdVSqXk2bZm6u1tidgZtBYIqM0kN8J9omjPEf3Zg2EY74wdj6T(I0zZA22UC4ZaJrZxvU(M5C(vDoGk1lvR2bJr5xYwTcVOkrrBOlibloW66TZOhPCSHrKD3nhFLzeXruAMxthnrCH0gS4nbssF3yidEEP53LaVxQyOSVN2OuixLUtvosU6UpMI5)MEdUNn2SFLzlehIYutjFy6KQsmBckn(UmYeZtJMfUVk7rRiE42cE7bZhoDks1k6XI00a0wEnDlSIoBOZE(MH5FWl52uiwZUjWCBFyTAOUuH1sjSFgF8AOACl3AMgAvWIBlgGttuJw58iffDPlZ6wkbfFfgBSUhXvojR5VftfNeFSGdsag0KlxXOjsTh12yOy1LohnJUcjG2MqyZirBF4K4DA1ft7Ang6DobwfYofQQT8osVyDuxduDmWdorzOnnfboIrM8Rmx0YSv9vuHaBoCbCfBn(avtLQJymLTNYDOk5C4V)dqfHo3jueR82FnU)qYJD2tR6hBv)P3CJcATmNm586z))7L)Fdc3hJN4ngGyap(7DKdtE03yiatoKnyNi3fxFAIdmWYQ2CyadMCCnT1dgixyZ7s0Goo8S2GpJ)wfiy4OK)1oEGzh86iD8eUF1C67jo456aezpDiFUj8I6XhIAoBupFpdo0bHVL5AB1V)nZ(hW))g8DzwV0K)7bguBYPsxdsTArTNH2mfQ4N24AdQXUN6DMc61rzydH(0cp(ueZR5OED)JSnyeYNd59CiVDWs4VzH86fw4CZb8gWH)Ufh8PlTNbWS3lG3dyPk)4fI6N(dlQM8WC0tEyoU9yCILIMjNfnheOY967byc94DV(dx(M)5hE)OJE75dgp0Wuf8DYw2NaYBA4SlCnCeOwr8NJPVDpzpht)5y6pht)5y6gIP7QPdS5y6UI3)NHy6TRsctJXF2daS)UWnhGWuGetHdF6QJzFKcMkXWtLF9ht0M)BE(R(E91)8mx9FRE6FsMaRDlmWgNxRNwp)dLV1dQlbS9mdG)eMWkVKX05eoqXkk2FxPgmqK990izhsmaVY)PsmiUv948NUGi)atoq4N4PjwXF2jh03B1OZ)ly6bnr6F6cAyiu6pGOfByfN8djKXUmhxUbA6pA7qo65gi(6s)zi3a1Lv63zLT(zBAS8EoG3Zb8EoG3Zb8EoG3Zb80lgw4Ji0WpffdBxJa88SH8NU)F5zaW)v4()5jd5VxLiB7tgYFvxGd2d8Pm(DM8Z(KGYMgj7uMsp09Z177K4)jkZToFKGdT37QhA0EdQI9dr3RgTO553tKAtgl7AG6)KwI9Md79dC6P0Xf9KeG1DBQx)vka7gW3)CC2bCN9dieRjCo)qcWAk5d9aSoIz1DWes0INkgM7j3EBlC(Doa8gIGS34(FOZEaGzFvpffXRhofKo(EIeymNnZjiVBHhmhAPVx6hDSbZby3ZPy88bDjUH8Um5LFdHf6G(ulKFhpJpvXe24N1AVidIfRYt4QsyV8WBmaMzh8denWOp2FcdgOdL4)2ccyaOtmB7zizP90FF)TxHNSaa7Tx(Z3pOLpGtv1Lzl)rNWZFzwB6pqBShOobUfZH24f53YVpxTn5E1HsYvoUQBJwxMvvUEfLQf(vSfsBtGm)nobClxpcgJVQqUfEZB8HVvCDokXnRsNH0TMXZntNDmy)mlD1DxwWruz90JA5EA7KZAbQCtQW9nwuhVfXDCtpH0tqOTLRvqGRLhU3COYMJouL4pMu)BF5JeKtkTpFYwS(jxNVyb8Kh46471UFhIuQvlT8jrtjB6JGxiwi7Knp4OQRSto0FL0JHcZPPjysqWDSsQHMh3PdRUuJC)uXl8XblO7EZLCZ5sIKRK04O2(R7iNhFEXHUrU22EHIDhlAtxvSrgR0XhxWmDU1Xn5qAVBl)w52uP4p(KHrf3Zs6GjuKK5RlaZDcyjvKTazKK2AVyFXChOKZLc59k6rWgfzHKLLp1SV6KxkjJZ0fFFSd)4suT22pY1nmm2oWniOtFiB5wjUuAG76UQ7)1spgoYnqqBpFU9OtOjsj)0B5DeZ60BKvWaP3rYEBKKBpch1J4b3Ru0pf0lTnD65Bfh1JV3yOgNSUapA1UOSzFxZouSnyfA7BhYhIb7Z2uKKkW(WtFldLaRFtwr2Q0f3VvpzwOF3rDyG62JkQ728MmjaIzf4AB1D3FU5qMdmZmDXSj3V4vD8O6ykmPunsoVBX2UbMQVDFQU7lZKTIpml6MITuwV2dfX65WWEoaP8YgBD5vysq6mIUBus23wMwm7nx)(sPV6Z0Fl0S25WUUzAChgPmQKUpIqrqBSmH3KdScu)pD0jTGu1DVygZzpBzJ(cm0Hng0(90I3TDKsYIRH3GBL05PlWCByY6lMJ3lmVou3p8Ww1dKYKJsppvU()dAVylOaHTTjw(MTEyDATSIugVVsOl0AQ6l24449D47hIE(Xy)mS5ITQ5YzpfMlGoJ7H7LLbTnyRyAe8FEtJbdtUntdtcDJ(fhuLVr1(q14lI9(vfSig10FkvFnz00v)fcmMbquMjca0xfMaNasUJLym6R7kUpYc9pCl(91HNUrh)AAYJ2xD2adQSrq0DhC322Y2nMdutWc0r39QgJFaaXVLUyDwvLvspfytib84D0qBRq7WW9C)qKIgZwf27KvquYY8L)UIYgqYWvKhdZ2hAuRqrJSh6yp89)WMry0PkkDSwc02sZBS6Oh1OrRrJaDd3yKQKZMK0sgv2e0CdbCcYOOjUy4ivrjLLtBfIrjtNJ0cr8cjM4khR)anjqy0Q3KhcHzHiBcdHbyBD7wlOxjKRIUefs02oUIRu3OdvnIJHC3ftswB0JQ758)j85hvvLFtXT4EToNApC1PxSQeAbAlL2jjWNYjfOakxh6XIfT34GXUEHEoUJDdeR4ZuQbZMjEyqK4J7aPyxgjFl)XoXawy3Xrod8soUrqw7ITOtL(kca(o22jW4RXvTAv2Tqo(nxtRjIg7bnqG1yRW471iPa4obwb(JJDUVxVggdJWaR4nnclaS5DgM0R64gaJ2TYB07pxF7XXEH75B556o2p0EBVvBLvfBw(KIWvz1yHmKCXziGGIAPiVWn03hsEPqUSz728qET2b(hw4AJ7F74)4WpQnaKUEv6MerNJvzzC1DftPZRebHmYGyW2d)N9t4RloI8dghfTBcs9o3o2g0883g3T9TcH3kWpa6pFZVv3obEAVixqWhCpL516AYpI5Ee3vGbUUFOVf8VXOpv4FTCCW)FWTqrqSN1GsaDr(58RGDKFcFMfD1xZxMrhYhmMWhoNB8T8muNUT2Hj2T9u8qBlpfYf24JyqqA54noW3SzIUgdkb9TdSrNcgfc(U(bGyWj0pme)xlp(C6ylUHeKr8yNO91g3h8ez7BMC2To232ZDSN7aDmQ8l79bAo)e60BZ87B74z76dTbWAq)fcp5fbEoDgoEJD8JTISghhAo0HjpCHbJJdC3DEw04aBash63ND4BLmE8nZlRQhpD2qndkefI2EKCOBue0AdibGHVBaUJBt)ias0bCCAl2eXHhNm7Kh5CSBv6UuTtvEhlXFrnf8xIZ7bjPpm)3ueZGqiC3aEG2QgdkLIICb(y0gSy07rlhRX(dgA3GuYhepE2oHGQGd1GewAS(5CTXZuNijLT8AzPAKxQfmJeEBQg8g3eWf(93tQbt1M7txY)be8bPY38YcBq4loyKUb3bWXJmhc6iolcZWtpNJoz0B(TtLpq7eOmrI8KM1fXbW5koUziRaaTVeGZJMwcE6OfPjlY4rouWUXHIr3Z)WyqS7djj5TtKKWn8)HOjNDIMI8D(pHEehNZpbIZp9ZGTb4G4y5gMoTZPZ0kKd10px1M)SpnNK8mj4yZ3EKHIuzCYM8788uzYXgYRZnEx630MvWE3LRIRpDOJ1SEx3We7OLvAxY4vcgxNj26A55V17y(o76P7SB5hHUGXPOXXXti3uMfhNWql3yqjZ3kkOHK7o)gdqyhliS2Iq4yb9tySNDi2L474KGfDo72CA2dpJp)auUsZcUHwDl8zpko6Ez(xYlY(LRMNNTaps2eIGkLZ5s(CKtPmCoE0j7rSnF0XqSm(TmmptTQCbeFPDIW0N7eTzQIvV(OScM0D6FowcPVQCuDQpXx9NXhiQHoBLMhlQcm9lXxpzqtLmqc7y9hMNGE6pDO6Le3SZLQu0JZAztcv1qnj0v0CllNRqSoeC1nl0otx7nfB6Zowmn7yUEacPa68gtzs807UnnZ9YLzMXZYpzHiDJ8PdAe7WaihUO(9WBbfRQc(4bbfn4Hk6O(dBYZM9HMN9SWaC8y7gJNunIsMQlyketNlkcApRrLKQSEgo2o22qUk(aJXNbr0fqapKRNmr9WCYoHaVGhdx2IzJlcALO99GvXZHFBpWGjoGoqTTtKhsu(bh0C0bbWn3VMMLvjYJtjhNqSuHHbobicX9UTEGeqmCXJXtV5SuadM7Ohya8xxYaIcWGotsxGMoN(TLGSO6RP3rC1Y11lajVWBz180zLFfE7))d" },
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
