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
--  Addon registry: maps addon folder names to their DB accessor info.
--  Each entry: { svName, globalName, isFlat }
--    svName    = SavedVariables name (e.g. "EllesmereUINameplatesDB")
--    globalName = global variable holding the AceDB object (e.g. "_ECME_AceDB")
--    isFlat    = true if the DB is a flat table (Nameplates), false if AceDB
--
--  Order matters for UI display.
-------------------------------------------------------------------------------
local ADDON_DB_MAP = {
    { folder = "EllesmereUINameplates",        display = "Nameplates",         svName = "EllesmereUINameplatesDB",        globalName = nil,            isFlat = true  },
    { folder = "EllesmereUIActionBars",        display = "Action Bars",        svName = "EllesmereUIActionBarsDB",        globalName = nil,            isFlat = false },
    { folder = "EllesmereUIUnitFrames",        display = "Unit Frames",        svName = "EllesmereUIUnitFramesDB",        globalName = nil,            isFlat = false },
    { folder = "EllesmereUICooldownManager",   display = "Cooldown Manager",   svName = "EllesmereUICooldownManagerDB",   globalName = "_ECME_AceDB",  isFlat = false },
    { folder = "EllesmereUIResourceBars",      display = "Resource Bars",      svName = "EllesmereUIResourceBarsDB",      globalName = "_ERB_AceDB",   isFlat = false },
    { folder = "EllesmereUIAuraBuffReminders", display = "AuraBuff Reminders", svName = "EllesmereUIAuraBuffRemindersDB", globalName = "_EABR_AceDB",  isFlat = false },
    { folder = "EllesmereUICursor",            display = "Cursor",             svName = "EllesmereUICursorDB",            globalName = "_ECL_AceDB",   isFlat = false },
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
local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = DeepCopy(v)
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
--  CDM spell-layout fields: excluded from main profile snapshots/applies.
--  These are managed exclusively by the CDM Spell Profile export/import.
-------------------------------------------------------------------------------
local CDM_SPELL_KEYS = {
    trackedSpells = true,
    extraSpells   = true,
    removedSpells = true,
    dormantSpells = true,
    customSpells  = true,
}

--- Deep-copy a CDM profile, stripping only spell-layout data.
--- Removes per-bar spell lists and specProfiles (CDM spell profiles).
--- Positions (cdmBarPositions, tbbPositions) ARE included in the copy
--- because they belong to the visual/layout profile, not spell assignments.
local function DeepCopyCDMStyleOnly(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    -- Keys managed by CDM's internal spec profile system -- never include
    -- in layout snapshots so they are not overwritten on profile switch.
    local CDM_INTERNAL = {
        specProfiles = true,
        activeSpecKey = true,
        barGlows = true,
        trackedBuffBars = true,
        spec = true,
    }
    for k, v in pairs(src) do
        if CDM_INTERNAL[k] then
            -- Omit -- managed by CDM's own spec system
        elseif k == "cdmBars" and type(v) == "table" then
            -- Deep-copy cdmBars but strip spell fields from each bar entry
            local barsCopy = {}
            for bk, bv in pairs(v) do
                if bk == "bars" and type(bv) == "table" then
                    local barList = {}
                    for i, bar in ipairs(bv) do
                        local barCopy = {}
                        for fk, fv in pairs(bar) do
                            if not CDM_SPELL_KEYS[fk] then
                                barCopy[fk] = DeepCopy(fv)
                            end
                        end
                        barList[i] = barCopy
                    end
                    barsCopy[bk] = barList
                else
                    barsCopy[bk] = DeepCopy(bv)
                end
            end
            copy[k] = barsCopy
        else
            copy[k] = DeepCopy(v)
        end
    end
    return copy
end

--- Merge a CDM style-only snapshot back into the live profile,
--- preserving all existing spell-layout fields.
--- Positions (cdmBarPositions, tbbPositions) ARE applied from the snapshot
--- because they belong to the visual/layout profile.
local function ApplyCDMStyleOnly(profile, snap)
    -- Keys managed by CDM's internal spec profile system -- never overwrite
    -- from a layout snapshot so spell assignments survive profile switches.
    local CDM_INTERNAL = {
        specProfiles = true,
        _capturedOnce = true,
        activeSpecKey = true,
        barGlows = true,
        trackedBuffBars = true,
        spec = true,
    }
    -- Apply top-level non-spell keys
    for k, v in pairs(snap) do
        if CDM_INTERNAL[k] then
            -- Skip -- managed by CDM's own spec system
        elseif k == "cdmBars" and type(v) == "table" then
            if not profile.cdmBars then profile.cdmBars = {} end
            for bk, bv in pairs(v) do
                if bk == "bars" and type(bv) == "table" then
                    if not profile.cdmBars.bars then profile.cdmBars.bars = {} end
                    for i, barSnap in ipairs(bv) do
                        if not profile.cdmBars.bars[i] then
                            profile.cdmBars.bars[i] = {}
                        end
                        local liveBar = profile.cdmBars.bars[i]
                        for fk, fv in pairs(barSnap) do
                            if not CDM_SPELL_KEYS[fk] then
                                liveBar[fk] = DeepCopy(fv)
                            end
                        end
                    end
                else
                    profile.cdmBars[bk] = DeepCopy(bv)
                end
            end
        else
            profile[k] = DeepCopy(v)
        end
    end
end

-------------------------------------------------------------------------------
--  Profile DB helpers
--  Profiles are stored in EllesmereUIDB.profiles = { [name] = profileData }
--  profileData = {
--      addons = { [folderName] = <snapshot of that addon's profile table> },
--      fonts  = <snapshot of EllesmereUIDB.fonts>,
--      customColors = <snapshot of EllesmereUIDB.customColors>,
--  }
--  EllesmereUIDB.activeProfile = "Custom"  (name of active profile)
--  EllesmereUIDB.profileOrder  = { "Custom", ... }
--  EllesmereUIDB.specProfiles  = { [specID] = "profileName" }
-------------------------------------------------------------------------------
local function GetProfilesDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.profiles then EllesmereUIDB.profiles = {} end
    if not EllesmereUIDB.profileOrder then EllesmereUIDB.profileOrder = {} end
    if not EllesmereUIDB.specProfiles then EllesmereUIDB.specProfiles = {} end
    return EllesmereUIDB
end

--- Check if an addon is loaded
local function IsAddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
    return false
end

--- Get the live profile table for an addon
local function GetAddonProfile(entry)
    if entry.isFlat then
        -- Flat DB (Nameplates): the global IS the profile
        return _G[entry.svName]
    else
        -- AceDB-style: profile lives under .profile
        local aceDB = entry.globalName and _G[entry.globalName]
        if aceDB and aceDB.profile then return aceDB.profile end
        -- Fallback for Lite.NewDB addons: look up the current character's profile
        local raw = _G[entry.svName]
        if raw and raw.profiles then
            -- Determine the profile name for this character
            local profileName = "Default"
            if raw.profileKeys then
                local charKey = UnitName("player") .. " - " .. GetRealmName()
                profileName = raw.profileKeys[charKey] or "Default"
            end
            if raw.profiles[profileName] then
                return raw.profiles[profileName]
            end
        end
        return nil
    end
end

--- Snapshot the current state of all loaded addons into a profile data table
function EllesmereUI.SnapshotAllAddons()
    local data = { addons = {} }
    for _, entry in ipairs(ADDON_DB_MAP) do
        if IsAddonLoaded(entry.folder) then
            local profile = GetAddonProfile(entry)
            if profile then
                if entry.folder == "EllesmereUICooldownManager" then
                    data.addons[entry.folder] = DeepCopyCDMStyleOnly(profile)
                else
                    data.addons[entry.folder] = DeepCopy(profile)
                end
            end
        end
    end
    -- Include global font and color settings
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    local cc = EllesmereUI.GetCustomColorsDB()
    data.customColors = DeepCopy(cc)
    return data
end

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
                    if folderName == "EllesmereUICooldownManager" then
                        data.addons[folderName] = DeepCopyCDMStyleOnly(profile)
                    else
                        data.addons[folderName] = DeepCopy(profile)
                    end
                end
                break
            end
        end
    end
    -- Always include fonts and colors
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    data.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
    return data
end

--- Apply a profile data table to all loaded addons
function EllesmereUI.ApplyProfileData(profileData)
    if not profileData or not profileData.addons then return end
    for _, entry in ipairs(ADDON_DB_MAP) do
        local snap = profileData.addons[entry.folder]
        if snap and IsAddonLoaded(entry.folder) then
            local profile = GetAddonProfile(entry)
            if profile then
                if entry.folder == "EllesmereUICooldownManager" then
                    -- Style-only: preserve all spell-layout fields
                    ApplyCDMStyleOnly(profile, snap)
                elseif entry.isFlat then
                    -- Flat DB: wipe and copy
                    local db = _G[entry.svName]
                    if db then
                        for k in pairs(db) do
                            if not k:match("^_") then
                                db[k] = nil
                            end
                        end
                        for k, v in pairs(snap) do
                            if not k:match("^_") then
                                db[k] = DeepCopy(v)
                            end
                        end
                    end
                else
                    -- AceDB: wipe profile and copy
                    for k in pairs(profile) do profile[k] = nil end
                    for k, v in pairs(snap) do
                        profile[k] = DeepCopy(v)
                    end
                    -- Ensure per-unit bg colors are never nil after a profile load
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
    end
    -- Apply fonts and colors
    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for k in pairs(fontsDB) do fontsDB[k] = nil end
        for k, v in pairs(profileData.fonts) do
            fontsDB[k] = DeepCopy(v)
        end
    end
    if profileData.customColors then
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k in pairs(colorsDB) do colorsDB[k] = nil end
        for k, v in pairs(profileData.customColors) do
            colorsDB[k] = DeepCopy(v)
        end
    end
end

--- Trigger live refresh on all loaded addons after a profile apply
function EllesmereUI.RefreshAllAddons()
    -- ResourceBars
    if _G._ERB_Apply then _G._ERB_Apply() end
    -- CDM
    if _G._ECME_Apply then _G._ECME_Apply() end
    -- Cursor (main dot + trail + GCD/cast circles)
    if _G._ECL_Apply then _G._ECL_Apply() end
    if _G._ECL_ApplyTrail then _G._ECL_ApplyTrail() end
    if _G._ECL_ApplyGCDCircle then _G._ECL_ApplyGCDCircle() end
    if _G._ECL_ApplyCastCircle then _G._ECL_ApplyCastCircle() end
    -- AuraBuffReminders
    if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
    -- ActionBars: use the full apply which includes bar positions
    if _G._EAB_Apply then _G._EAB_Apply() end
    -- UnitFrames
    if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
    -- Nameplates
    if _G._ENP_RefreshAllSettings then _G._ENP_RefreshAllSettings() end
    -- Global class/power colors (updates oUF, nameplates, raid frames)
    if EllesmereUI.ApplyColorsToOUF then EllesmereUI.ApplyColorsToOUF() end
end

--- Snapshot current font settings; returns a function that checks if they
--- changed and shows a reload popup if so.
function EllesmereUI.CaptureFontState()
    local fontsDB = EllesmereUI.GetFontsDB()
    local prevFont = fontsDB.global
    local prevOutline = fontsDB.outlineMode
    return function()
        local cur = EllesmereUI.GetFontsDB()
        if cur.global ~= prevFont or cur.outlineMode ~= prevOutline then
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

--- Apply a partial profile (specific addons only) by merging into active
function EllesmereUI.ApplyPartialProfile(profileData)
    if not profileData or not profileData.addons then return end
    for folderName, snap in pairs(profileData.addons) do
        for _, entry in ipairs(ADDON_DB_MAP) do
            if entry.folder == folderName and IsAddonLoaded(folderName) then
                local profile = GetAddonProfile(entry)
                if profile then
                    if folderName == "EllesmereUICooldownManager" then
                        ApplyCDMStyleOnly(profile, snap)
                    elseif entry.isFlat then
                        local db = _G[entry.svName]
                        if db then
                            for k, v in pairs(snap) do
                                if not k:match("^_") then
                                    db[k] = DeepCopy(v)
                                end
                            end
                        end
                    else
                        for k, v in pairs(snap) do
                            profile[k] = DeepCopy(v)
                        end
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

-------------------------------------------------------------------------------
--  Export / Import
--  Format: !EUI_<base64 encoded compressed serialized data>
--  The data table contains:
--    { version = 1, type = "full"|"partial", data = profileData }
-------------------------------------------------------------------------------
local EXPORT_PREFIX = "!EUI_"
local CDM_LAYOUT_PREFIX = "!EUICDM_"

function EllesmereUI.ExportProfile(profileName)
    local db = GetProfilesDB()
    local profileData = db.profiles[profileName]
    if not profileData then return nil end
    local payload = { version = 1, type = "full", data = profileData }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

function EllesmereUI.ExportAddons(folderList)
    local profileData = EllesmereUI.SnapshotAddons(folderList)
    local sw, sh = GetPhysicalScreenSize()
    local euiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
    local meta = {
        euiScale = euiScale,
        screenW  = sw and math.floor(sw) or 0,
        screenH  = sh and math.floor(sh) or 0,
    }
    local payload = { version = 1, type = "partial", data = profileData, meta = meta }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

--- Export CDM spell profiles for selected spec keys.
--- specKeys = { "250", "251", ... } (specID strings)
function EllesmereUI.ExportCDMSpellLayouts(specKeys)
    local cdmEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUICooldownManager" then cdmEntry = e; break end
    end
    if not cdmEntry then return nil end
    local profile = GetAddonProfile(cdmEntry)
    if not profile or not profile.specProfiles then return nil end
    local exported = {}
    for _, key in ipairs(specKeys) do
        if profile.specProfiles[key] then
            exported[key] = DeepCopy(profile.specProfiles[key])
        end
    end
    if not next(exported) then return nil end
    local payload = { version = 1, type = "cdm_spells", data = exported }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return CDM_LAYOUT_PREFIX .. encoded
end

--- Import CDM spell profiles from a string. Overwrites matching spec profiles.
function EllesmereUI.ImportCDMSpellLayouts(importStr)
    -- Detect profile strings pasted into the wrong import
    if importStr and importStr:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX then
        return false, "This is a UI Profile string, not a CDM Spell Profile. Use the Profile import instead."
    end
    if not importStr or #importStr < 5 then
        return false, "Invalid string"
    end
    if importStr:sub(1, #CDM_LAYOUT_PREFIX) ~= CDM_LAYOUT_PREFIX then
        return false, "Not a valid CDM Spell Profile string. Make sure you copied the entire string."
    end
    if not LibDeflate then return false, "LibDeflate not available" end

    local encoded = importStr:sub(#CDM_LAYOUT_PREFIX + 1)
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return false, "Failed to decode string" end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return false, "Failed to decompress data" end
    local payload = Serializer.Deserialize(decompressed)
    if not payload or type(payload) ~= "table" then
        return false, "Failed to deserialize data"
    end
    if payload.version ~= 1 then
        return false, "Unsupported CDM spell profile version"
    end
    if payload.type ~= "cdm_spells" or not payload.data then
        return false, "Invalid CDM spell profile data"
    end

    local cdmEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUICooldownManager" then cdmEntry = e; break end
    end
    if not cdmEntry then return false, "Cooldown Manager not found" end
    local profile = GetAddonProfile(cdmEntry)
    if not profile then return false, "Cooldown Manager profile not available" end

    if not profile.specProfiles then profile.specProfiles = {} end

    -- Build a set of spellIDs the importing user actually has in their CDM
    -- viewer. Spells not in this set are "not displayed" and should be
    -- filtered out so the user is not given spells they cannot track.
    local userCDMSpells
    if _G._ECME_GetCDMSpellSet then
        userCDMSpells = _G._ECME_GetCDMSpellSet()
    end

    -- Helper: filter an array of spellIDs, keeping only those in the user's CDM
    local function FilterSpellList(list)
        if not list or not userCDMSpells then return list end
        local filtered = {}
        for _, sid in ipairs(list) do
            if userCDMSpells[sid] then
                filtered[#filtered + 1] = sid
            end
        end
        return filtered
    end

    -- Helper: filter a removedSpells table (spellID keys, boolean values)
    local function FilterSpellMap(map)
        if not map or not userCDMSpells then return map end
        local filtered = {}
        for sid, v in pairs(map) do
            if userCDMSpells[sid] then
                filtered[sid] = v
            end
        end
        return filtered
    end

    -- Overwrite matching spec profiles from the imported data, filtering spells
    local count = 0
    for specKey, specData in pairs(payload.data) do
        local data = DeepCopy(specData)

        -- Filter barSpells
        if data.barSpells then
            for barKey, barSpells in pairs(data.barSpells) do
                if barSpells.trackedSpells then
                    barSpells.trackedSpells = FilterSpellList(barSpells.trackedSpells)
                end
                if barSpells.extraSpells then
                    barSpells.extraSpells = FilterSpellList(barSpells.extraSpells)
                end
                if barSpells.removedSpells then
                    barSpells.removedSpells = FilterSpellMap(barSpells.removedSpells)
                end
                if barSpells.dormantSpells then
                    barSpells.dormantSpells = FilterSpellMap(barSpells.dormantSpells)
                end
                if barSpells.customSpells then
                    barSpells.customSpells = FilterSpellList(barSpells.customSpells)
                end
            end
        end

        -- Filter tracked buff bars
        if data.trackedBuffBars and data.trackedBuffBars.bars then
            local kept = {}
            for _, tbb in ipairs(data.trackedBuffBars.bars) do
                if not tbb.spellID or tbb.spellID <= 0
                   or not userCDMSpells
                   or userCDMSpells[tbb.spellID] then
                    kept[#kept + 1] = tbb
                end
            end
            data.trackedBuffBars.bars = kept
        end

        profile.specProfiles[specKey] = data
        count = count + 1
    end

    -- If the user's current spec matches one of the imported specs, apply it
    -- to the live bars immediately so it takes effect without a /reload.
    if _G._ECME_GetCurrentSpecKey and _G._ECME_LoadSpecProfile then
        local currentKey = _G._ECME_GetCurrentSpecKey()
        if currentKey and payload.data[currentKey] then
            _G._ECME_LoadSpecProfile(currentKey)
            -- Rebuild visual CDM bar frames with the newly loaded data
            if _G._ECME_Apply then _G._ECME_Apply() end
        end
    end

    return true, nil, count
end

--- Get a list of saved CDM spec profile keys with display info.
--- Returns: { { key="250", name="Blood", icon=... }, ... }
function EllesmereUI.GetCDMSpecProfiles()
    local cdmEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUICooldownManager" then cdmEntry = e; break end
    end
    if not cdmEntry then return {} end
    local profile = GetAddonProfile(cdmEntry)
    if not profile or not profile.specProfiles then return {} end
    local result = {}
    for specKey in pairs(profile.specProfiles) do
        local specID = tonumber(specKey)
        local name, icon
        if specID and specID > 0 and GetSpecializationInfoByID then
            local _, sName, _, sIcon = GetSpecializationInfoByID(specID)
            name = sName
            icon = sIcon
        end
        result[#result + 1] = {
            key  = specKey,
            name = name or ("Spec " .. specKey),
            icon = icon,
        }
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

function EllesmereUI.ExportCurrentProfile()
    local profileData = EllesmereUI.SnapshotAllAddons()
    local sw, sh = GetPhysicalScreenSize()
    -- Use EllesmereUI's own stored scale (UIParent scale), not Blizzard's CVar
    local euiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
    local meta = {
        euiScale = euiScale,
        screenW  = sw and math.floor(sw) or 0,
        screenH  = sh and math.floor(sh) or 0,
    }
    local payload = { version = 1, type = "full", data = profileData, meta = meta }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

function EllesmereUI.DecodeImportString(importStr)
    if not importStr or #importStr < 5 then return nil, "Invalid string" end
    -- Detect CDM layout strings pasted into the wrong import
    if importStr:sub(1, #CDM_LAYOUT_PREFIX) == CDM_LAYOUT_PREFIX then
        return nil, "This is a CDM Spell Profile string. Use the CDM Spell Profile import instead."
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
    if payload.version ~= 1 then
        return nil, "Unsupported profile version"
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
        return false, "This is a CDM Spell Profile string. Use the CDM Spell Profile import instead."
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
        db.profiles[profileName] = DeepCopy(payload.data)
        -- Add to order if not present
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        if specLocked then
            -- Save the profile but do not activate or apply it
            return true, nil, "spec_locked"
        end
        -- Make it the active profile
        db.activeProfile = profileName
        EllesmereUI.ApplyProfileData(payload.data)
        FixupImportedClassColors()
        -- Re-snapshot after fixup so the stored profile has correct colors
        db.profiles[profileName] = EllesmereUI.SnapshotAllAddons()
        return true, nil
    elseif payload.type == "partial" then
        -- Partial: copy current profile, overwrite the imported addons
        local currentSnap = EllesmereUI.SnapshotAllAddons()
        -- Merge imported addon data over current
        if payload.data and payload.data.addons then
            for folder, snap in pairs(payload.data.addons) do
                currentSnap.addons[folder] = DeepCopy(snap)
            end
        end
        -- Merge fonts/colors if present
        if payload.data.fonts then
            currentSnap.fonts = DeepCopy(payload.data.fonts)
        end
        if payload.data.customColors then
            currentSnap.customColors = DeepCopy(payload.data.customColors)
        end
        -- Store as new profile
        db.profiles[profileName] = currentSnap
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        if specLocked then
            return true, nil, "spec_locked"
        end
        db.activeProfile = profileName
        EllesmereUI.ApplyProfileData(currentSnap)
        FixupImportedClassColors()
        -- Re-snapshot after fixup
        db.profiles[profileName] = EllesmereUI.SnapshotAllAddons()
        return true, nil
    end

    return false, "Unknown profile type"
end

-------------------------------------------------------------------------------
--  Profile management
-------------------------------------------------------------------------------
function EllesmereUI.SaveCurrentAsProfile(name)
    local db = GetProfilesDB()
    db.profiles[name] = EllesmereUI.SnapshotAllAddons()
    local found = false
    for _, n in ipairs(db.profileOrder) do
        if n == name then found = true; break end
    end
    if not found then
        table.insert(db.profileOrder, 1, name)
    end
    db.activeProfile = name
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
    -- If deleted profile was active, fall back to Custom
    if db.activeProfile == name then
        db.activeProfile = "Custom"
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
    end
end

function EllesmereUI.SwitchProfile(name)
    local db = GetProfilesDB()
    local profileData = db.profiles[name]
    if not profileData then return end
    db.activeProfile = name
    EllesmereUI.ApplyProfileData(profileData)
end

function EllesmereUI.GetActiveProfileName()
    local db = GetProfilesDB()
    return db.activeProfile or "Custom"
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
--  Auto-save active profile on setting changes
--  Called by addons after any setting change to keep the active profile
--  in sync with live settings.
-------------------------------------------------------------------------------
function EllesmereUI.AutoSaveActiveProfile()
    if EllesmereUI._profileSaveLocked then return end
    local db = GetProfilesDB()
    local name = db.activeProfile or "Custom"
    db.profiles[name] = EllesmereUI.SnapshotAllAddons()
end

-------------------------------------------------------------------------------
--  Spec auto-switch handler
-------------------------------------------------------------------------------
do
    local specFrame = CreateFrame("Frame")
    local lastKnownSpecID = nil
    local pendingReload = false
    specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    specFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    specFrame:SetScript("OnEvent", function(_, event, unit)
        -- Deferred reload: fire once combat ends
        if event == "PLAYER_REGEN_ENABLED" then
            if pendingReload then
                pendingReload = false
                StaticPopup_Show("EUI_PROFILE_RELOAD")
            end
            return
        end

        -- PLAYER_ENTERING_WORLD has no unit arg; PLAYER_SPECIALIZATION_CHANGED
        -- fires with "player" as unit. For PEW, always check current spec.
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then
            return
        end
        local specIdx = GetSpecialization and GetSpecialization() or 0
        local specID = specIdx and specIdx > 0
            and GetSpecializationInfo(specIdx) or nil
        if not specID then return end

        local isFirstLogin = (lastKnownSpecID == nil)

        -- On PLAYER_ENTERING_WORLD (reload/zone-in), only switch if the spec
        -- actually changed. A plain /reload should not override the user's
        -- active profile selection.
        if event == "PLAYER_ENTERING_WORLD" then
            if not isFirstLogin and specID == lastKnownSpecID then
                return -- spec unchanged on reload/zone-in, skip
            end
        end
        lastKnownSpecID = specID

        local db = GetProfilesDB()
        local targetProfile = db.specProfiles[specID]
        if targetProfile and db.profiles[targetProfile] then
            local current = db.activeProfile or "Custom"
            if current ~= targetProfile then
                -- Auto-save current before switching (skip on first login,
                -- SavedVariables already has the previous character's save)
                if not isFirstLogin then
                    db.profiles[current] = EllesmereUI.SnapshotAllAddons()
                end
                if isFirstLogin then
                    -- On first login, addons already loaded correct state from
                    -- SavedVariables. Just update the active profile name so the
                    -- UI shows the right profile -- don't apply snapshot data on
                    -- top, which would overwrite positions with stale values.
                    db.activeProfile = targetProfile
                else
                    EllesmereUI.SwitchProfile(targetProfile)
                    if InCombatLockdown() then
                        pendingReload = true
                    else
                        StaticPopup_Show("EUI_PROFILE_RELOAD")
                    end
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
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_T31AZTjsw7)k7FGOcAUt(KTJDskpj2LJMDs2AQYfscBXBKaTaAC8KY)3FpN(cD3qds4BJNDCQAR1dc6lNlpNNZPBA(5PvUXRtRtG)imoDB2xMNSkn3AIVte(Vqp)i3WO3EAvqC18Y008pKB76APCHFlN45B927WwQ(2nPW)3vBxTcVH)iTSkRip3(T4pUiH2nEXxvKxxb)LF81RkMLSQY2k(4FSPmTQ6MKBpTY2oUyB9QS80pvSaBV8I8uO9TjXZ3wvxS(OIvfLv02A(QKQQFE3DyRLSyrroEzIF8XRwLwToTm9x)4rffRwuCt(NsYtUoT8N0gA22RU6WKs20fhFHIlHnquC1YIBMMbnWuCImROCrA5H5S59SRpy1MLjGuYLoXMLu(E4)iKa)xWuHDZFj7pznS4PVG)0vBsMNLFDoE3(XRkM)90fNqFWRYwvNwsNZoXjOimmoBEroRPcXw3jEBv6r4CMkdor28hq7SMw5xYQQRSIXFV4QRQsR)AUJfBaKMNmBfTp9IVjBr9YCc9xOtKdrDpBODDzXn)6gAxSo5hOKjpuz(8E68XpEzA21lRzJprN9T83O0MWmFILhvgJI1pctPPGcJ4fF56SRltQtxCgyQuMTi9lBsxT6JVRAkDUcweFpl)qA3HxI4kFIZbzq2FO9aG1WI1W488IQS6mUPGf3M5s)lTDDISScU01YfncIVn32YAsKTFGDGhjYHocltxDErgyG6hF0XFE6XxGIPnTUID8pYFJDO)Ka3Oq3axBITn6bi7TaO3C988dV03Hi6n7jbEwwr2EEKah3r2DKi)jOlj6qsCjy3ffpNBBxX7I3efmjm0X2bMoUEbJSlCjtc89dd8jeRalhSl8OUfnnVx0KaBFxhlFFxlQDYiAFkiHDKqe5XviKld8esipMikG4ger8gxZ)ghs4exBFFpF3ixBxS3cI3wNTkR(wf5taaRzzfgqcTgPk33BIlObS9TaXK)BruhWk9Y5jBQ3wcgX5ZtNsrx4DQeDjGBAIcYgpWPC)JQF(tQ1lZVA6YS5FphWcr80Lz5Opg6yEnd(X2nE(YKYRtpbqrziduhF74Q6K5F)OIT51hY7Z8TRVO4Mko(23tVDww(IdaVXiwdXVYzCacYBBdN4G3IQzMs78EbGt1nzBsfiIbSwg9Z)sZ45eQCkjF(YIYZ4aew0MFgoRMyf(wDXIDagb4SRUij)6ueByvYTtBeexieeAJFeZHbrc30)oRkBgvhGXfwbHvQOYi(tWKB0wXVzYjfOm76zQHhGNnzEna4CqE2AkAVhBmaG1jG2hGKol)O3rvP5jRtbH2rsHMoMjOQzTfiHQPni2BRY(Z)mPCrlv5f5D0UCbpHjmoUbnhLMxiKMW8I1LgdwWmLc5QKPfs)eM2RPVKgye74Laa9HiAWVTmn)J5S5WuQnaDOWSb0m24dFhAWK3LvMoNcm7g)lhFc)j1JwciOs5S2yhLbyqzqQwNHHLucosjKWVHJOEhvtBhRfKi0FMRvMM(J6PmHg6r4J3reYyPodu6NvMLMdAhyW2149RcEakX110qmRB7W4LfBRG()dGG7yPXTlV1AIt5gVk9Q6wgzcDexsY8PJyZ5LjBe8IeYH)trXAHYhNuVx8FWDAEF3H5xZveBNY6MtAnkqf4Dddp1AiAY39KthgGI822OCThdMrM0nBnaNzcEsAwWTn7cm1cKtdAQTzOoOKbF3xiasbX)Qqw1coQhGutO4pj4q7cp8zaqYl(Ip((pmsejTWxkOreBPBLenYiiYdauQf(tFGngWL6f)rjGGaCXaKupmqEoGMArIzKat3tMtAatDOrzcwItA(utWy3teP(yRjbM0Sg)7cOKx8Hmj19dsQTb()qGKAZbFaMroe5n8)IyrMjB8CGf1xCHDakPtZXCEo7esYeOJS2dUyI1KqB7ldI8p1CkAMWy0O5maarFGb94vmG7pHeFeDm)VAsw6Fbzj)VSBdieGJMPy1f1sg1GZ)tHR(G0GeStvZ1qdlUV4o7OsH9diO6E7)C4E3oV7(tFPT)TjV4oiH9HxmaC6tGdE7qzTcImk367jtdtU1MRx2ZOxDB5s)EZGEK7ntvzM9K3P)07nrcQXe(b7o3HBqFOw96(P7CpQ69Vtp32Ox3xp2r66ykYCFbXnqKPRpEVyeAqjpqpwJWWI4eCo4JYT9Eu5IDhnwBDhEg9BhF0yt(VKxy(VDuWgDP3tF37xG5)ICPn53ouchgCPFyUU9Hi8y6s3nFsDp8r5o)igfUNf27z0DEeHH9I)uw180vRsYtbfMHyWgkiWZNlSreKXgeUvT97b5EhEY9vaVNwhzD20pv5k3XxFKucEGoYDbLLi3HX1Lz5FpTUIUcQ24p8U0Rs2UIUTqE6RONUhU5sRT3o2d5mpqkC6f)XqDcnBs3P(J6wtJLmWExVoJ6tDiLUvnCVGzgWU8rpx((xrotLBCOW(gYI9ryLdEEsNN3bQ1lSt9eFqypDRtNwG5Nc4M2vNRBqg2giJAQXniMYUu9SzYDm0DAork7qS7OUKQBRSTLvf4UjZjEz6pGrO1rVJe9oCVJu1eM2dG6sYwrv5xpFHYDFc9F4mRmzr22k2Qg18Swm2qj1Weyj1ifmTP2AHmJrab9AqPdxEfU)ROZKSCqUKph8zxDlJgC3DlMy3FDNXNaO5KuvFuw58vPkdwNtoiqBW6ynIbl0pGRt53LoCYHVpO)lxNSAFg)tBn(BrPQ79wdofBltrRdS)UK1v3rXCu0KFgynTzfayqJ(aZ5KQL)swEkTHOBCOzm)Iy(c0exYniCODXxwvuFbQeOpCAYQ6LNNwoh84OgM1fBW7G6GtOoMbXxva0jPTVckeZJ(e0xDXQB)85hvHzYtOQeWs8xZZYRtll3UPoBgv9GdmRjUE8XwZFwY(tCe6rDtX()Rm0dM7seoQkXXCNFYr0FFGVX(cy(xIz60InGhCAE66BrbhdMdcv8omCb4dHirkryIGyjyIA0ntzJFwa2)maex2(b1Zl(J407QK5P)(blwCwE1VROJ(91PlYs(D6T(7Ynl6KPtrzKt8vcPgmKqZNVXNsVHWblz6fyAnLBuOKWd4IU4tGbkh7M4YMXiB6VPkAGivB(821ZOtev4U5ZXwD32legMniFPBcsQHiDhSEEXnqGn5MBTr560OBdD1AkxHDL2imiEts(I01zZF)ka9BtA6ICxMliQe(yZsu7Ya1BSOUinzXTn9kPPxDKwureoiOMnVmCpyh8F3Mwv)PIzQw2Nqf)kwp7wm5e3yAQmA5EnCUqQBbx4NktktpgOFLkNI8XKu(E86n13QlELtusZ8KondJxNLNnduZn3BexdqVBxNM73ZoKlyg0ohiFGUj0is7N1IhhMamxe(IwCT8SIAWuXGVR0ugnrdBCZP)i1P9J5hvSEwsDZ8Y2jOzEj(BCEfYheC)xyi)Blbb8j0bG2urR6sCZsTXLVgCJuNcQhnJjThcImNK)9pKuDW1al6MHRVuNfkvAwm4oqDpx3iVDxO5U4jupTm1inpZVa)O0tNHfJymkSCDv0gkG8mCu6GrDrfAaor9Jd2)0XOM9BlDQq8VpwmasuFgGqViqjphJ29TUO(44A39sGIp1x1fNFhYyBk8)0IQvJezRpOesfsBhXYcZi9VA0RUnQ1aEh2i1AzUzlYjqZR2YxArl(7s(F3EcC41TE2qP9LLQbwiHlIrRYFPaZIq3W0wobcKpxOndobvIOfISCAa9jGm6bGJKqiIpLEeHg(mvtvMTFP(2v4kHMkIpEknIUI3Ic2lrlKa7kclkLee9J7LoqZW59jByj)40OO3T1It8LSSbohc6c58dZIMX92m6WzXMQpNMuU)ItWNRXIy3JGinVznZEwwch1mdrXtOgy17bR26LaHwbmAytRDukg9ubjiunm3305BPsTdC)UL9gnOm2yT2UNnSH8uQpfQrzSi0BL2U2nZpe0XNJxrf9ga)cz3F2vqMJigc1QvpqMcQzlJfngaskQbsoQHEskf2EbnovI5dZ4UJvIxdTCTLURHw3VrFtw8Lk1dwT6D0ixv0exq0MufWgF5iYZUzarCyczFk5VnDGjdKxNXdzZ)o3M9YTiKBSuT4A6PAJCEwbSSNuSwObM2TMx3oUfYRqF0A4kv9IFGhhA5g(ObnjASUbljv0IMkWXEkvEhT6hvQz7EMOzb1YHKr3qgeNxkd1oqqHhRrxDz2M0fV5piuZpuXFmImCoG0CcZYs6sQ4QgOjl39i2MX4rTcqcJpjqkFgGMAm)tLlZsU7d0NGLdbJySs2r7CuawFPBRltwTVGK6OcsEmbk8e)MsWheSMTohmW6NN8HhdvG7xaFhUywDU(YpX69N0WUZYEaAf8eWdcgmbCzrs270YVF8vgkvDJmxmKO(OiZ4PCrnQ6JMwcXsX3xRwupUz(RZzHvaBtvd4Erv5EvuG9ia(qSgmLUV5y7dueG7hZ8EJrowkd9G73tK5EifCVRxXqS82vHjgmRXhVYwWV(otKFxue6P6PJjp5bRtINQt8E0u3NQQyGoXOPdoYIQnwoA7hLRXwjiBevTDnDKUvTNGgRAe68iGgAhlfqa(CrlVFPIGqu7GbR(0aKTVhfMAWm0gQevruJXVOSolDAQbg2A(nw8YuRe68HuiKERd84QEMwGOw50yM6UXcRPeXVftaz2Y0kqjYkWyD)S40OOCU4fN7EKI((VGa9srF81FgIxnNoULLQqNmAltUbwZMDwbGrM9eXUtVTZNXCc)JPmLglUHV2ixyvXuA7nYeXTPsQFbSU47DfCuXTUKjgU7HP(s2GZx25SXyrZm7FR22T4xsKSIcvBidqoTQpDlMmJiCz)mKvwdVpyeCVpq)iiLvSngUkJbXllQQZuYUZso9TLS5CIeGBsacEjaf5Gbjo2zKYyOA7HseSG3BGaKn9KxhRi8Vyr4gbQ1Wa)gHU8yBucGJH2BvX4Dg7fLEuK6gfef0NYvEYiZuZ(YDm7P5JWMpMQda0mO8O3EjGjd5C1yUfECTu7vDMvUVUPtIw(HQB5ambEChpDbmiHrk9CbbdBa9921OMs7Gcb(BsmBRarGb71Rb1)LLBZtz7YbKq23z)nBhuG7eia9RIUrmUPyBoFJ7NL)9BVC2kKRgEd3G3aUTnkl2SmB(u(2KBgU1mOdhi536LRY(d2favnmXWhfRAvcR6MHX3atGR2wElVscf8(kz9MvzxDl7rdb9DD6Ljl()ynm0qRtRlYVElB7hs)1QK85SCzVjnztr(LP5ZxYMmaKeW5eAqO1yHnXPYH4m5)uG1NepPJi8T8ZM05zjRQ(Cr(h57NeQzpjEtz6vqITPl(nA7FmR5HghMw1xUTkDH(M3bmxAEKtGjM(DckAuf8USQna)y6P2KF86BRbjjDekFuuQP(SSOB1y3ulna4Se1UAZUyGAWfeVG1z)eLOOTpUj)qHT2PNfEkzHBnPdOBhh6276ASwU3UjL7YwPSkCfODD9TSjmOzkr6z1a2qcmD(0XV7J)6NWB7wHhJfJv61DJNe4346hW)BjHi6o(s8soZo6JOqCP)G)s8Ith50Lo0(HEId4DOc9WXKAI2X4PTdSmA8TT54XUf4TtVVBZFJJt0Kqh4F45oeTPBotGcINE25StReXHcKYLWtfiBl)a6t7tIIWJfiQfnKFjDln(ZtfW5QgKN027ojBkUDRQ(o)CUbEGT1uxQ1f13WUwzr(FMYDZkRrhbnR1aAVCw9sWA6tzvvCNfpk8g70sRsLWC7X0u9XeKpDXk2GQynZNUAzYIIBGoF9u2VFfZFDg0JPLF)swdr9xxK(hfxsXvPNMA3cOkf1umgAKQRe37D3XS7vWg)18S6tqZq(2XAdmzbXznRUsYTzg90tItqMexLUkDEn6OAWLWcAeaoMfLMNeb9k8IV8nHnMHIllmQfbZevBb8MNjPIGM0(S28B5VHVjceJCk4ajMWqnO3eWz4mHNNfpaoZ3tH3fV4rSq0qe)8A(E8NQ)uNa4TOUJMwcJQv7xzeescrSppqDco3uXb9x4trF2GS1ECf3sTusqsYCIY4Qo(O3FetQG2DNZLmN0rvW2pNiATYfzfjvulviRvk)NwYfrsMSXdFu7Wz9tPyO(aGEiTC5gPGNtHZNhAN29i7EHe(u5QzWX8vAJHkATYVju5r05yxvOCEEsJ50xnc2HwG0IgRM2oBjpu)N6YI096ZmC97K2OtPrykxNWLwB2CNgHpi4rUyXS5l16ukrEHVr2I0w7OBWtFrkZ9vycW2hWHnoliEH4V)QOIFZQNrZ0CLYEzvXbJkxEe8RJA83(QO5m4NJLASEgDSq3ToIkVWV12EcECn1jzRwjhbyzRJA0cHmPVJlXougg11jIy7fyh5hff6RbafPyrRjuylMMGD)UD)jntznJlwXJXldMTmHnJ6CtYqjBRlA6p6XWOSYo2paWlBfV7VQRu7crzr1eSSHef2qv38lfSkyuP8oQ3buRZAZWvWkRzIn7(GRE41NPWyYfVK0kRwUtYL1FxAuXVrtque)oog6lGui260kTPbsG1Qrv(Vtf(UqDufPn79FH7xBW2bXvd529DQUyIAMWAUHZyw3mUHFbEaMYOlsh9nYPtBmXkmi01bFFBDII4l1dROji5ohxF4xdiC7(bzmif3AUxdgxYxZ1tA4Gf9qgWsZBTlXKiP4x7wdfkb57xfFak7i69OrYPr9O4C7R5HW(b(kUjhMARVkQn(y(5q2Gm2PQ0C6eyku62Ro(JAgVFteHVTbp7GED6P9rDAOGS2cXJI)A)HR3fjmnUaJInLfdJqp1O(x1otK(I0bFfrEqOksqpcTDgztdwLPbKAeMjLgFdzm4gqlzW2fPkvWrpyO4y)GRn(wRa46qnD5zO(6l2IOPDdkn(EeEQzMNm3W9H5jdzPlZtvhq9rRVINzBGWbPKAjDdBErSBUcpSvupk2w2N(csg6KjOvEZrPEUkRYTVdh23ChqLpbV90(48YlN10LPyDbWmW8HusHhm)0(P22Ww4a67ggtDI208GWw4jknNYiVMDwCuMlGeNNYdSY1iEsS4US9vn(4x)ownyXIN2dn1tgIM6j)frtT)We)dKwAlZH)gZi9bWd6LazvRyf)y16I3IfRln(0UzXkxAmfHNCRx0BaHXYZ9PH244zphsp88PaDeUavb7JWzy0hb7(y9BG4n91qz5dHJGoT7(yZEpzo3d7Ywmf6q74XLG8qSygdv5oKEhMJS5KSFCikpuC29LvX(qEwyE1p35XWtwJRzp09hj3yosv7ObD59AKXQzMeN2pBY(O(WEtpoKxmmOzZzVRxTolDUxSmFaKI7Hb((XjExfvPDMepy6WTYdlKVIfVO4(oUm9ANA(ExsYHY6D)ij3FnlOv8Crs53PZWtyWVYVDkOTaL1m3(IomVn)ne2YFt)IE09tLXD4sdTHr9gV7qh7jEHoowHe7OiB(tg47IFRoI89CdDPBAGoRU2DQlWdBv68MqCJcj(qWAsaVLSdSCMy7hyf4BBtpSim1s2eEgbY8cWMmW1dI(7yhzfzhe10KanGjWfCdTGy)91KQB9bCEgeGZixpIRvaFRA9J8i)aSdCjbUKO(MMQzRqhvb24enIe4rS48vGrfXpCci7H5EOLxFTLT6oiUrJr2HgZNRPhEe4ZuLErEW17vUGRImky0NtHEeu845BbSQSCeZjlFF8l(cKEreXY8CcBsxHV)z6lxnAEiwwzA1AAm9gt0ODrPPnB)bbK3x)6olewhsfJzDUOFSC6jq6aP98uUks9wCGHQJNPG(6bdS4bdmqaMN8VnPjNxnWzpB5gO0x9TqK9Tcc3UX1N)Q1Z)0TE6JGlXo(sgkjBJ59j(xISPAWNp8L)Cm1rYvpcTijQoLl6LBHHmMAu)LWz41aOtDAc1LpkeWg9khURxyRgPqO22YvPOl7AHaPLqzxLijsFgXFuUAUNu2gQOe9T)iepSwrbg61tIFkOTJf8yO0B2Zm73zY3e8a8cFzC(y(cChSxyqD1xvh3f(blveZPAgQ)kyX0CITIBxW(E3xiwTh(SCp4zJ0o559jDQOoTioki8AC8IkTQGwVDJ8I92cOJnV2V8F6uN(Xv89EFjzun43XlldGDG74q5SAAbDhUnLoZu2VWOKd5vJrr01yngurCZgqkC64RR((xh9UMH0wh3e3uVPthUO5JABL1XHvlWv6UlTTMu8qrGqnv3x0o0M1Q6yVf5EpQN9ShLDLr)1dQ3Ad3UIc3VYY2P0nglB64QoARIF(0xNtJfWCC1N5XPSM9uKBTWM6gq9wL9HQ0zFlEJPID2)QHRvj8Mct2YrQbDTVKauQ3jdmXy9ohrLO3ZeG0EnlObruw0ekylVOOsK2hHAJoRBHJzeKoVj6Kyz56GP1G1OVYM9x4zz7EWSQIYzN8qwChZB2H7)AtUJDORUmzwYo2VhTx3NDUoB9TKbTxTONKvbCGCRzsAXHuQyxSZQJPsIItBkF4uz5)qjNwTZytu16woLxHlEjnvth9NN23wDO)SGATyfgwAsdbR7BhFBCR327wj(0HwAfdw(MxyIbmcBffYyMYMZaZmeOzggdKoMrkR9qjU3u3mthUZIkB2HBNErM3hjMx8LEO6nyTAAbHYycR(AWrpw0pK9DXgFT92wbiBTZwtLOTVLSgEH80tWG4rboCEuS24xBDWht8AouNpEX1PT)zBFTFMLE0eSB5hp5OqfpxrYZwZkladIN1zkP94YSkBOm0PJONJ6NRSklUXW83ruMCBITh9LjIyf57JdGX9UiffaeAcc8dTC9CJyfGaAFFE7h4ojWYYYM9bEVvZVRp)52wU2tGrf7ZxVlhj84FakxUIClWdjxmv8cczZKqIBGvWONkKqatggR(aSmROG0Pcrru5mbrMdSJS8DhD77gzpjiii0jiG4g20(HI23jc0e4ai0X2YBSFm6TJM4cpRRVlg2WRP5fFQ7FJVhD6z5ec3uuW4AEAi4G4pLKHEpIMm0dxmLiBF)il3GrB8a(qt8TTjwoUEOThlgZX5ZXZpDk0tZyNRADI8JSPCshvhzdYBSeIHo(E4lCNq2e0OATdMyhff5b)HDy44KnVXL4XQN)HjxRmOHbQl973FuOvez32JTm(diEtSCCGjSRLpFnD)u28YcTUiiyc2dr(2HEoJSli(oOujGqST8JO4zrXFH(EYPQKHXHpi1SaVqBI3o7JwY(al7jUH2bUUGkwSWhNNwR0dKqNjeu6hqc8CIgR0pWEcyb6t8Ic898BuUUIMhaGOg(UakLtazCnp8O0vr0nYLQh8OVsNaSFdIBlWyB8iTlzdwP4fNXE7eH0XAUBErKPVCSewa9TvnFHaExsDcgD6KhLJPCSqL)3TjL0Zqb(h2HnLfMoBgg4DPL08m0bTnl8plqu7zdECoYV5obIc0I4DVI2Q8rBWJLTGCcjpBwuf3pGq7UyGt9aMKyk0e7DcwU5EOrHopzXcLppqSCXqwxYtteifBTVNjQFIyq6E0pBeGMC3P93nTvLjMysjMq8cf06BodNVe7thZhYwSinNrDx(vGH268xoFFXZVxdqLpEu8VniM(sOWsrtPD1wrg2i7l08fqbCfNaPqkPxyiM4OJbhQe07ri5BJPD2NGZuD0RW1qRDEW7sd0(BZdjE7gusbwbu)trLjxdYP0I)iv98SNXjK)1gzARVefD(yYWteszukRqUMjCtMgn9P2hjvLgq7dffZGV1x0X()ikb)ulBQgCh7ghq7g3pXbwwH8BidQfwc)3)jO2PF6ougXSV5a4r7l3BS94fMXRWdp6LLfBVE5jAmuF1HE8o023h352gW)pTJS4a41GNSMJRzFXr4mB2X1a050tFz5ph28LI60hQZCFze21tWm0Qzp7EnWnBl2)CO1a2SstlvZxXKgpM09KKX)SqLEBl4hZ(dMaL6d64raSYpgVqjid)SyGYvn9GknEONEWdhaG7jN8H7JGJEpIOxaE8Awzpb(6HV6RBYxVx3093rVlu9yCXvbBi96YRhG6E5rpGRBpo7p5E0HVm9Onr)4z3J1(v)1DfBU)mg2d)0rhk((GZ))EEYgHlVtDztE55pFF0Cp7(7VgH(1i0)f6x3ncT2cx(Qt990Po6vN6DegNVBIEE8LhiR8)j4t7f)1ZB8OFqL6ZSvMx8n09JKRyx5AQ6f6dRP4sBVKVZMcF7qtXosMpC2fF8)C2NNEWVCApozm68T3DepW5(FjL5m45agMhEBeWWViYvIdM9km7aWSHpey2xtw6Eba3xYsQB6P)MHfPVDQ(B2GV1g16Pgn9vsT)ZcT91mvp9zauTlRw1Tg5lpF6xemKSF1J91Qj)YZxUFcsxKU5XHJXFxsuLf(x82bJ7Nz2UBHQHe7x3M7M(YNRSLMViTQyBjLzd7Jsf(kdXfGEGPFYcC8O5hsL5hqNPAypoXv4BeT8LJLzNjAJ3NZETCLxr0gj0x7xM7Hx8vzRwDiCVbo0BUZxZNq7qCt4hA7gfgy36Thy37q(ix)j4HBIVJJLh775Jyo9E6iOrxrSugDFl)nE4gygSfV(c69XE76OFzDNkBJd5)MyoEyoR(8QFDEyp5x2GhnB03pqSnKVR664wIg(cXV3iK)gh(VU1jLcoepafG0UI24M0hxW1hQnjthGnWHCTbZANDcJXhPQkkSrI85pZ7v(bMUfmmfDhGG2XG2Hli49(uuvsF9zzVKTSwcTB88y6PRtZtzFG8d5ggIGVd53yHHZAFEYOB2POMX3vzANTPmBDsj9lKnmZxcp7YIvl0c5R(zTIZyyUCpWB0HPqnwa7Snr(McQFE9PEuO0jsVf)tewR36sl5i9cMkq5kSXGWfR9VEi3GOh3b6BpOy8lChOmfKiFCVddhfu6(hAFRQ2Hjp3A0qB2yO71AMiGAAmFT5NtRn3X5Z5FsU52TMo8Qg0Os1kVXv4TngfT(4n(hzvzZYwLvFlipzrL6AElEplFcn463(sdn)K22xkhbx7T5fhbFmwy(6wy(pjwyw)D2cJb2(amYGypPa66IHa28rr(H8qagm64)(bCs4dIWryVx1CZZbH46qOqZydF1WcS8cdjoEKixBYom(8ny75B75h6tcC9SIyehOHWzHE0nkvmdDc7Zm0EyZo34nzBoRFnCi(7)MQ9tllmXC1oWN9cFYSu7IrcP9vmxo6cJNVep1aOInxSLJWU6dk8Aew22s957ZLMRATcouccuVctytugU4PZvwYk8ZKklt1MF5imdOCNbSrHRdJUMVFKYrKyYX71dvuXD8l48Nn4x0k6I0Ji6T3H)7))p" },
    { name = "Spin the Wheel", description = "Randomize all settings", exportString = nil },
}

EllesmereUI.WEEKLY_SPOTLIGHT = nil  -- { name = "...", description = "...", exportString = "!EUI_..." }
-- To set a weekly spotlight, uncomment and fill in:
-- EllesmereUI.WEEKLY_SPOTLIGHT = {
--     name = "Week 1 Spotlight",
--     description = "A clean minimal setup",
--     exportString = "!EUI_...",
-- }

-------------------------------------------------------------------------------
--  Spin the Wheel: global randomizer
--  Randomizes all addon settings except X/Y offsets, scale, and enable flags.
--  Does not touch Party Mode.
-------------------------------------------------------------------------------
function EllesmereUI.SpinTheWheel()
    local function rColor()
        return { r = math.random(), g = math.random(), b = math.random() }
    end
    local function rBool() return math.random() > 0.5 end
    local function pick(t) return t[math.random(#t)] end
    local function rRange(lo, hi) return lo + math.random() * (hi - lo) end
    local floor = math.floor

    -- Randomize each loaded addon (except Nameplates which has its own randomizer)
    for _, entry in ipairs(ADDON_DB_MAP) do
        if IsAddonLoaded(entry.folder) and entry.folder ~= "EllesmereUINameplates" then
            local profile = GetAddonProfile(entry)
            if profile then
                EllesmereUI._RandomizeProfile(profile, entry.folder)
            end
        end
    end

    -- Nameplates: use the existing randomizer keys from the preset system
    if IsAddonLoaded("EllesmereUINameplates") then
        local db = _G.EllesmereUINameplatesDB
        if db then
            EllesmereUI._RandomizeNameplates(db)
        end
    end

    -- Randomize global fonts
    local fontsDB = EllesmereUI.GetFontsDB()
    local validFonts = {}
    for _, name in ipairs(EllesmereUI.FONT_ORDER) do
        if name ~= "---" then validFonts[#validFonts + 1] = name end
    end
    fontsDB.global = pick(validFonts)
    local outlineModes = { "none", "outline", "shadow" }
    fontsDB.outlineMode = pick(outlineModes)

    -- Randomize class colors
    local colorsDB = EllesmereUI.GetCustomColorsDB()
    colorsDB.class = {}
    for token in pairs(EllesmereUI.CLASS_COLOR_MAP) do
        colorsDB.class[token] = rColor()
    end
end

--- Generic profile randomizer for AceDB-style addons.
--- Skips keys containing "offset", "Offset", "scale", "Scale", "X", "Y",
--- "pos", "Pos", "position", "Position", "anchor", "Anchor" (position-related),
--- and boolean keys that look like enable/disable toggles.
function EllesmereUI._RandomizeProfile(profile, folderName)
    local function rColor()
        return { r = math.random(), g = math.random(), b = math.random() }
    end
    local function rBool() return math.random() > 0.5 end

    local function IsPositionKey(k)
        local kl = k:lower()
        if kl:find("offset") then return true end
        if kl:find("scale") then return true end
        if kl:find("position") then return true end
        if kl:find("anchor") then return true end
        if kl == "x" or kl == "y" then return true end
        if kl == "offsetx" or kl == "offsety" then return true end
        if kl:find("unlockpos") then return true end
        return false
    end

    -- Boolean keys that control whether a feature/element is enabled.
    -- These should never be randomized — users want their frames to stay visible.
    local function IsEnableKey(k)
        local kl = k:lower()
        if kl == "enabled" then return true end
        if kl:sub(1, 6) == "enable" then return true end
        if kl:sub(1, 4) == "show" then return true end
        if kl:sub(1, 4) == "hide" then return true end
        if kl:find("enabled$") then return true end
        if kl:find("visible") then return true end
        return false
    end

    local function RandomizeTable(tbl, depth)
        if depth > 5 then return end  -- safety limit
        for k, v in pairs(tbl) do
            if type(k) == "string" and IsPositionKey(k) then
                -- Skip position/scale keys
            elseif type(k) == "string" and type(v) == "boolean" and IsEnableKey(k) then
                -- Skip enable/show/hide toggle keys
            elseif type(v) == "table" then
                -- Check if it's a color table
                if v.r and v.g and v.b then
                    tbl[k] = rColor()
                    if v.a then tbl[k].a = v.a end  -- preserve alpha
                else
                    RandomizeTable(v, depth + 1)
                end
            elseif type(v) == "boolean" then
                tbl[k] = rBool()
            elseif type(v) == "number" then
                -- Randomize numbers within a reasonable range of their current value
                if v == 0 then
                    -- Leave zero values alone (often flags)
                elseif v >= 0 and v <= 1 then
                    tbl[k] = math.random() -- 0-1 range (likely alpha/ratio)
                elseif v > 1 and v <= 50 then
                    tbl[k] = math.random(1, math.floor(v * 2))
                end
            end
        end
    end

    -- Snapshot visibility settings that must survive randomization
    local savedVis = {}

    if folderName == "EllesmereUIUnitFrames" and profile.enabledFrames then
        savedVis.enabledFrames = {}
        for k, v in pairs(profile.enabledFrames) do
            savedVis.enabledFrames[k] = v
        end
    elseif folderName == "EllesmereUICooldownManager" and profile.cdmBars then
        savedVis.cdmBars = {}
        if profile.cdmBars.bars then
            for i, bar in ipairs(profile.cdmBars.bars) do
                savedVis.cdmBars[i] = bar.barVisibility
            end
        end
    elseif folderName == "EllesmereUIResourceBars" then
        savedVis.secondary = profile.secondary and profile.secondary.visibility
        savedVis.health    = profile.health    and profile.health.visibility
        savedVis.primary   = profile.primary   and profile.primary.visibility
    elseif folderName == "EllesmereUIActionBars" and profile.bars then
        savedVis.bars = {}
        for key, bar in pairs(profile.bars) do
            savedVis.bars[key] = {
                alwaysHidden      = bar.alwaysHidden,
                mouseoverEnabled  = bar.mouseoverEnabled,
                mouseoverAlpha    = bar.mouseoverAlpha,
                combatHideEnabled = bar.combatHideEnabled,
                combatShowEnabled = bar.combatShowEnabled,
            }
        end
    end

    RandomizeTable(profile, 0)

    -- Restore visibility settings
    if folderName == "EllesmereUIUnitFrames" and savedVis.enabledFrames then
        if not profile.enabledFrames then profile.enabledFrames = {} end
        for k, v in pairs(savedVis.enabledFrames) do
            profile.enabledFrames[k] = v
        end
    elseif folderName == "EllesmereUICooldownManager" and savedVis.cdmBars then
        if profile.cdmBars and profile.cdmBars.bars then
            for i, vis in pairs(savedVis.cdmBars) do
                if profile.cdmBars.bars[i] then
                    profile.cdmBars.bars[i].barVisibility = vis
                end
            end
        end
    elseif folderName == "EllesmereUIResourceBars" then
        if profile.secondary then profile.secondary.visibility = savedVis.secondary end
        if profile.health    then profile.health.visibility    = savedVis.health    end
        if profile.primary   then profile.primary.visibility   = savedVis.primary   end
    elseif folderName == "EllesmereUIActionBars" and savedVis.bars then
        if profile.bars then
            for key, vis in pairs(savedVis.bars) do
                if profile.bars[key] then
                    profile.bars[key].alwaysHidden      = vis.alwaysHidden
                    profile.bars[key].mouseoverEnabled   = vis.mouseoverEnabled
                    profile.bars[key].mouseoverAlpha     = vis.mouseoverAlpha
                    profile.bars[key].combatHideEnabled  = vis.combatHideEnabled
                    profile.bars[key].combatShowEnabled  = vis.combatShowEnabled
                end
            end
        end
    end
end

--- Nameplate-specific randomizer (reuses the existing logic from the
--- commented-out preset system in the nameplates options file)
function EllesmereUI._RandomizeNameplates(db)
    local function rColor()
        return { r = math.random(), g = math.random(), b = math.random() }
    end
    local function rBool() return math.random() > 0.5 end
    local function pick(t) return t[math.random(#t)] end

    local borderOptions = { "ellesmere", "simple" }
    local glowOptions = { "ellesmereui", "vibrant", "none" }
    local cpPosOptions = { "bottom", "top" }
    local timerOptions = { "topleft", "center", "topright", "none" }

    -- Aura slots: exclusive pick
    local auraSlots = { "top", "left", "right", "topleft", "topright", "bottom" }
    local function pickAuraSlot()
        if #auraSlots == 0 then return "none" end
        local i = math.random(#auraSlots)
        local s = auraSlots[i]
        table.remove(auraSlots, i)
        return s
    end

    db.borderStyle = pick(borderOptions)
    db.borderColor = rColor()
    db.targetGlowStyle = pick(glowOptions)
    db.showTargetArrows = rBool()
    db.showClassPower = rBool()
    db.classPowerPos = pick(cpPosOptions)
    db.classPowerClassColors = rBool()
    db.classPowerGap = math.random(0, 6)
    db.classPowerCustomColor = rColor()
    db.classPowerBgColor = rColor()
    db.classPowerEmptyColor = rColor()

    -- Text slots
    local textPool = { "enemyName", "healthPercent", "healthNumber",
        "healthPctNum", "healthNumPct" }
    local function pickText()
        if #textPool == 0 then return "none" end
        local i = math.random(#textPool)
        local e = textPool[i]
        table.remove(textPool, i)
        return e
    end
    db.textSlotTop = pickText()
    db.textSlotRight = pickText()
    db.textSlotLeft = pickText()
    db.textSlotCenter = pickText()
    db.textSlotTopColor = rColor()
    db.textSlotRightColor = rColor()
    db.textSlotLeftColor = rColor()
    db.textSlotCenterColor = rColor()

    db.healthBarHeight = math.random(10, 24)
    db.healthBarWidth = math.random(2, 10)
    db.castBarHeight = math.random(10, 24)
    db.castNameSize = math.random(8, 14)
    db.castNameColor = rColor()
    db.castTargetSize = math.random(8, 14)
    db.castTargetClassColor = rBool()
    db.castTargetColor = rColor()
    db.castScale = math.random(10, 40) * 5
    db.showCastIcon = math.random() > 0.3
    db.castIconScale = math.floor((0.5 + math.random() * 1.5) * 10 + 0.5) / 10

    db.debuffSlot = pickAuraSlot()
    db.buffSlot = pickAuraSlot()
    db.ccSlot = pickAuraSlot()
    db.debuffYOffset = math.random(0, 8)
    db.sideAuraXOffset = math.random(0, 8)
    db.auraSpacing = math.random(0, 6)

    db.topSlotSize = math.random(18, 34)
    db.rightSlotSize = math.random(18, 34)
    db.leftSlotSize = math.random(18, 34)
    db.toprightSlotSize = math.random(18, 34)
    db.topleftSlotSize = math.random(18, 34)

    local timerPos = pick(timerOptions)
    db.debuffTimerPosition = timerPos
    db.buffTimerPosition = timerPos
    db.ccTimerPosition = timerPos

    db.auraDurationTextSize = math.random(8, 14)
    db.auraDurationTextColor = rColor()
    db.auraStackTextSize = math.random(8, 14)
    db.auraStackTextColor = rColor()
    db.buffTextSize = math.random(8, 14)
    db.buffTextColor = rColor()
    db.ccTextSize = math.random(8, 14)
    db.ccTextColor = rColor()

    db.raidMarkerPos = pickAuraSlot()
    db.classificationSlot = pickAuraSlot()

    db.textSlotTopSize = math.random(8, 14)
    db.textSlotRightSize = math.random(8, 14)
    db.textSlotLeftSize = math.random(8, 14)
    db.textSlotCenterSize = math.random(8, 14)

    db.hashLineEnabled = math.random() > 0.7
    db.hashLinePercent = math.random(10, 50)
    db.hashLineColor = rColor()
    db.focusCastHeight = 100 + math.random(0, 4) * 25

    -- Font
    local validFonts = {}
    for _, f in ipairs(EllesmereUI.FONT_ORDER) do
        if f ~= "---" then validFonts[#validFonts + 1] = f end
    end
    db.font = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\"
        .. (EllesmereUI.FONT_FILES[pick(validFonts)] or "Expressway.TTF")

    -- Colors
    db.focusColorEnabled = true
    db.tankHasAggroEnabled = true
    db.focus = rColor()
    db.caster = rColor()
    db.miniboss = rColor()
    db.enemyInCombat = rColor()
    db.castBar = rColor()
    db.interruptReady = rColor()
    db.castBarUninterruptible = rColor()
    db.tankHasAggro = rColor()
    db.tankLosingAggro = rColor()
    db.tankNoAggro = rColor()
    db.dpsHasAggro = rColor()
    db.dpsNearAggro = rColor()

    -- Bar texture (skip texture key randomization — texture list is addon-local)
    db.healthBarTextureClassColor = math.random() > 0.5
    if not db.healthBarTextureClassColor then
        db.healthBarTextureColor = rColor()
    end
    db.healthBarTextureScale = math.random(5, 20) / 10
    db.healthBarTextureFit = math.random() > 0.3
end

-------------------------------------------------------------------------------
--  Initialize profile system on first login
--  Creates the "Custom" profile from current settings if none exists.
--  Also saves the active profile on logout (via Lite pre-logout callback)
--  so SavedVariables are current before StripDefaults runs.
-------------------------------------------------------------------------------
do
    -- Register pre-logout save via Lite so it runs BEFORE StripDefaults
    EllesmereUI.Lite.RegisterPreLogout(function()
        if not EllesmereUI._profileSaveLocked then
            local db = GetProfilesDB()
            local name = db.activeProfile or "Custom"
            db.profiles[name] = EllesmereUI.SnapshotAllAddons()
        end
    end)

    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")

        local db = GetProfilesDB()
        -- On first install, create "Custom" from current (default) settings
        if not db.activeProfile then
            db.activeProfile = "Custom"
        end
        -- Ensure Custom profile exists with current settings
        if not db.profiles["Custom"] then
            -- Delay slightly to let all addons initialize their DBs
            EllesmereUI._profileSaveLocked = true
            C_Timer.After(0.5, function()
                db.profiles["Custom"] = EllesmereUI.SnapshotAllAddons()
                EllesmereUI._profileSaveLocked = false
            end)
        end
        -- Ensure Custom is in the order list
        local hasCustom = false
        for _, n in ipairs(db.profileOrder) do
            if n == "Custom" then hasCustom = true; break end
        end
        if not hasCustom then
            table.insert(db.profileOrder, "Custom")
        end

        ---------------------------------------------------------------
        --  Migration: clean up duplicate spec assignments
        --  An older version allowed multiple specs to be assigned to
        --  the same profile. The guardrails now prevent this in the UI,
        --  but existing corrupted data needs to be fixed. For each
        --  profile name, only the FIRST specID found is kept; the rest
        --  are unassigned so the user can reassign them properly.
        ---------------------------------------------------------------
        if db.specProfiles and next(db.specProfiles) then
            local profileToSpec = {}  -- profileName -> first specID seen
            local toRemove = {}
            for specID, pName in pairs(db.specProfiles) do
                if not profileToSpec[pName] then
                    profileToSpec[pName] = specID
                else
                    -- Duplicate: this spec also points to the same profile
                    toRemove[#toRemove + 1] = specID
                end
            end
            for _, specID in ipairs(toRemove) do
                db.specProfiles[specID] = nil
            end
        end

        -- Auto-save active profile when the settings panel closes
        C_Timer.After(1, function()
            if EllesmereUI._mainFrame and not EllesmereUI._profileAutoSaveHooked then
                EllesmereUI._profileAutoSaveHooked = true
                EllesmereUI._mainFrame:HookScript("OnHide", function()
                    EllesmereUI.AutoSaveActiveProfile()
                end)
            end

            -- Debounced auto-save on every settings change (RefreshPage call).
            -- Uses a 2-second timer so rapid slider drags collapse into one save.
            if not EllesmereUI._profileRefreshHooked then
                EllesmereUI._profileRefreshHooked = true
                local _saveTimer = nil
                local _origRefresh = EllesmereUI.RefreshPage
                EllesmereUI.RefreshPage = function(self, ...)
                    _origRefresh(self, ...)
                    if _saveTimer then _saveTimer:Cancel() end
                    _saveTimer = C_Timer.NewTimer(2, function()
                        _saveTimer = nil
                        EllesmereUI.AutoSaveActiveProfile()
                    end)
                end
            end
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
        local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
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
        local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
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
        local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
        scrollTarget = math.max(0, math.min(maxScroll, target))
        if not isSmoothing then isSmoothing = true; smoothFrame:Show() end
    end

    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = tonumber(self:GetVerticalScrollRange()) or 0
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
            local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
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
--  CDM Spell Profiles
--  Separate import/export system for CDM ability assignments only.
--  Captures which spells are assigned to which bars and tracked buff bars,
--  but NOT bar glows, visual styling, or positions.
--
--  Export format: !EUICDM_<base64 encoded compressed serialized data>
--  Payload: { version = 1, bars = { ... }, buffBars = { ... } }
--
--  On import, the system:
--    1. Decodes and validates the string
--    2. Analyzes which spells need to be tracked/enabled in CDM
--    3. Prints required spells to chat
--    4. Blocks import until all spells are verified as tracked
--    5. Applies the layout once verified
-------------------------------------------------------------------------------

--- Snapshot the current CDM spell profile (spell assignments only, no styling/glows)
function EllesmereUI.ExportCDMLayout()
    local aceDB = _G._ECME_AceDB
    if not aceDB or not aceDB.profile then return nil, "CDM not loaded" end
    local p = aceDB.profile
    if not p.cdmBars or not p.cdmBars.bars then return nil, "No CDM bars found" end

    local layoutData = { bars = {}, buffBars = {} }

    -- Capture bar definitions and spell assignments
    for _, barData in ipairs(p.cdmBars.bars) do
        local entry = {
            key      = barData.key,
            name     = barData.name,
            barType  = barData.barType,
            enabled  = barData.enabled,
        }
        -- Spell assignments depend on bar type
        if barData.trackedSpells then
            entry.trackedSpells = DeepCopy(barData.trackedSpells)
        end
        if barData.extraSpells then
            entry.extraSpells = DeepCopy(barData.extraSpells)
        end
        if barData.removedSpells then
            entry.removedSpells = DeepCopy(barData.removedSpells)
        end
        if barData.dormantSpells then
            entry.dormantSpells = DeepCopy(barData.dormantSpells)
        end
        if barData.customSpells then
            entry.customSpells = DeepCopy(barData.customSpells)
        end
        layoutData.bars[#layoutData.bars + 1] = entry
    end

    -- Capture tracked buff bars (spellID assignments only, not visual settings)
    if p.trackedBuffBars and p.trackedBuffBars.bars then
        for i, tbb in ipairs(p.trackedBuffBars.bars) do
            layoutData.buffBars[#layoutData.buffBars + 1] = {
                spellID = tbb.spellID,
                name    = tbb.name,
                enabled = tbb.enabled,
            }
        end
    end

    local payload = { version = 1, data = layoutData }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil, "LibDeflate not available" end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return CDM_LAYOUT_PREFIX .. encoded
end

--- Decode a CDM spell profile import string without applying it
function EllesmereUI.DecodeCDMLayoutString(importStr)
    if not importStr or #importStr < 5 then
        return nil, "Invalid string"
    end
    -- Detect profile strings pasted into the wrong import
    if importStr:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX then
        return nil, "This is a UI Profile string, not a CDM bar layout string."
    end
    if importStr:sub(1, #CDM_LAYOUT_PREFIX) ~= CDM_LAYOUT_PREFIX then
        return nil, "Not a valid CDM spell profile string. Make sure you copied the entire string."
    end
    if not LibDeflate then return nil, "LibDeflate not available" end
    local encoded = importStr:sub(#CDM_LAYOUT_PREFIX + 1)
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return nil, "Failed to decode string" end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return nil, "Failed to decompress data" end
    local payload = Serializer.Deserialize(decompressed)
    if not payload or type(payload) ~= "table" then
        return nil, "Failed to deserialize data"
    end
    if payload.version ~= 1 then
        return nil, "Unsupported CDM spell profile version"
    end
    if not payload.data or not payload.data.bars then
        return nil, "Invalid CDM spell profile data"
    end
    return payload.data, nil
end

--- Collect all unique spellIDs from a decoded CDM spell profile
local function CollectLayoutSpellIDs(layoutData)
    local spells = {}  -- { [spellID] = barName }
    for _, bar in ipairs(layoutData.bars) do
        local barName = bar.name or bar.key or "Unknown"
        if bar.trackedSpells then
            for _, sid in ipairs(bar.trackedSpells) do
                if sid and sid > 0 then spells[sid] = barName end
            end
        end
        if bar.extraSpells then
            for _, sid in ipairs(bar.extraSpells) do
                if sid and sid > 0 then spells[sid] = barName end
            end
        end
        if bar.customSpells then
            for _, sid in ipairs(bar.customSpells) do
                if sid and sid > 0 then spells[sid] = barName end
            end
        end
        -- dormantSpells are talent-dependent, include them too
        if bar.dormantSpells then
            for _, sid in ipairs(bar.dormantSpells) do
                if sid and sid > 0 then spells[sid] = barName end
            end
        end
        -- removedSpells are intentionally excluded from bars, don't require them
    end
    -- Buff bar spells
    if layoutData.buffBars then
        for _, tbb in ipairs(layoutData.buffBars) do
            if tbb.spellID and tbb.spellID > 0 then
                spells[tbb.spellID] = "Buff Bar: " .. (tbb.name or "Unknown")
            end
        end
    end
    return spells
end

--- Check which spells from a layout are currently tracked in CDM
--- Returns: missingSpells (table of {spellID, name, barName}), allPresent (bool)
function EllesmereUI.AnalyzeCDMLayoutSpells(layoutData)
    local aceDB = _G._ECME_AceDB
    if not aceDB or not aceDB.profile then
        return {}, false
    end
    local p = aceDB.profile

    -- Build set of all currently tracked spellIDs across all bars
    local currentlyTracked = {}
    if p.cdmBars and p.cdmBars.bars then
        for _, barData in ipairs(p.cdmBars.bars) do
            if barData.trackedSpells then
                for _, sid in ipairs(barData.trackedSpells) do
                    currentlyTracked[sid] = true
                end
            end
            if barData.extraSpells then
                for _, sid in ipairs(barData.extraSpells) do
                    currentlyTracked[sid] = true
                end
            end
            if barData.removedSpells then
                for _, sid in ipairs(barData.removedSpells) do
                    currentlyTracked[sid] = true
                end
            end
            if barData.customSpells then
                for _, sid in ipairs(barData.customSpells) do
                    currentlyTracked[sid] = true
                end
            end
            if barData.dormantSpells then
                for _, sid in ipairs(barData.dormantSpells) do
                    currentlyTracked[sid] = true
                end
            end
        end
    end
    -- Also check buff bars
    if p.trackedBuffBars and p.trackedBuffBars.bars then
        for _, tbb in ipairs(p.trackedBuffBars.bars) do
            if tbb.spellID and tbb.spellID > 0 then
                currentlyTracked[tbb.spellID] = true
            end
        end
    end

    -- Compare against layout requirements
    local requiredSpells = CollectLayoutSpellIDs(layoutData)
    local missing = {}
    for sid, barName in pairs(requiredSpells) do
        if not currentlyTracked[sid] then
            local spellName
            if C_Spell and C_Spell.GetSpellName then
                spellName = C_Spell.GetSpellName(sid)
            end
            missing[#missing + 1] = {
                spellID = sid,
                name    = spellName or ("Spell #" .. sid),
                barName = barName,
            }
        end
    end

    -- Sort by bar name then spell name for readability
    table.sort(missing, function(a, b)
        if a.barName == b.barName then return a.name < b.name end
        return a.barName < b.barName
    end)

    return missing, #missing == 0
end

--- Print missing spells to chat
function EllesmereUI.PrintCDMLayoutMissingSpells(missing)
    local EG = "|cff0cd29f"
    local WHITE = "|cffffffff"
    local YELLOW = "|cffffff00"
    local GRAY = "|cff888888"
    local R = "|r"

    print(EG .. "EllesmereUI|r: CDM Spell Profile Import - Spell Check")
    print(EG .. "----------------------------------------------|r")

    if #missing == 0 then
        print(EG .. "All spells are already tracked. Ready to import.|r")
        return
    end

    print(YELLOW .. #missing .. " spell(s) need to be enabled in CDM before importing:|r")
    print(" ")

    local lastBar = nil
    for _, entry in ipairs(missing) do
        if entry.barName ~= lastBar then
            lastBar = entry.barName
            print(EG .. "  [" .. entry.barName .. "]|r")
        end
        print(WHITE .. "    - " .. entry.name .. GRAY .. " (ID: " .. entry.spellID .. ")" .. R)
    end

    print(" ")
    print(YELLOW .. "Enable these spells in CDM, then click Import again.|r")
end

--- Apply a decoded CDM spell profile to the current profile
function EllesmereUI.ApplyCDMLayout(layoutData)
    local aceDB = _G._ECME_AceDB
    if not aceDB or not aceDB.profile then return false, "CDM not loaded" end
    local p = aceDB.profile
    if not p.cdmBars or not p.cdmBars.bars then return false, "No CDM bars found" end

    -- Build a lookup of existing bars by key
    local existingByKey = {}
    for i, barData in ipairs(p.cdmBars.bars) do
        existingByKey[barData.key] = barData
    end

    -- Apply spell assignments from the layout
    for _, importBar in ipairs(layoutData.bars) do
        local target = existingByKey[importBar.key]
        if target then
            -- Bar exists: update spell assignments only
            if importBar.trackedSpells then
                target.trackedSpells = DeepCopy(importBar.trackedSpells)
            end
            if importBar.extraSpells then
                target.extraSpells = DeepCopy(importBar.extraSpells)
            end
            if importBar.removedSpells then
                target.removedSpells = DeepCopy(importBar.removedSpells)
            end
            if importBar.dormantSpells then
                target.dormantSpells = DeepCopy(importBar.dormantSpells)
            end
            if importBar.customSpells then
                target.customSpells = DeepCopy(importBar.customSpells)
            end
            target.enabled = importBar.enabled
        end
        -- If bar doesn't exist (custom bar from another user), skip it.
        -- We only apply to matching bar keys.
    end

    -- Apply tracked buff bars
    if layoutData.buffBars and #layoutData.buffBars > 0 then
        if not p.trackedBuffBars then
            p.trackedBuffBars = { selectedBar = 1, bars = {} }
        end
        -- Merge: update existing buff bars by index, add new ones
        for i, importTBB in ipairs(layoutData.buffBars) do
            if p.trackedBuffBars.bars[i] then
                -- Update existing buff bar's spell assignment
                p.trackedBuffBars.bars[i].spellID = importTBB.spellID
                p.trackedBuffBars.bars[i].name = importTBB.name
                p.trackedBuffBars.bars[i].enabled = importTBB.enabled
            else
                -- Add new buff bar with default visual settings + imported spell
                local newBar = {}
                -- Use TBB defaults if available
                local defaults = {
                    spellID = importTBB.spellID,
                    name = importTBB.name or ("Bar " .. i),
                    enabled = importTBB.enabled ~= false,
                    height = 24, width = 270,
                    verticalOrientation = false,
                    texture = "none",
                    fillR = 0.05, fillG = 0.82, fillB = 0.62, fillA = 1,
                    bgR = 0, bgG = 0, bgB = 0, bgA = 0.4,
                    gradientEnabled = false,
                    gradientR = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
                    gradientDir = "HORIZONTAL",
                    opacity = 1.0,
                    showTimer = true, timerSize = 11, timerX = 0, timerY = 0,
                    showName = true, nameSize = 11, nameX = 0, nameY = 0,
                    showSpark = true,
                    iconDisplay = "none", iconSize = 24, iconX = 0, iconY = 0,
                    iconBorderSize = 0,
                }
                for k, v in pairs(defaults) do newBar[k] = v end
                p.trackedBuffBars.bars[#p.trackedBuffBars.bars + 1] = newBar
            end
        end
    end

    -- Save to current spec profile
    local specKey = p.activeSpecKey
    if specKey and specKey ~= "0" and p.specProfiles then
        -- Update the spec profile's barSpells to match
        if not p.specProfiles[specKey] then p.specProfiles[specKey] = {} end
        local prof = p.specProfiles[specKey]
        prof.barSpells = {}
        for _, barData in ipairs(p.cdmBars.bars) do
            local key = barData.key
            if key then
                local entry = {}
                if barData.trackedSpells then
                    entry.trackedSpells = DeepCopy(barData.trackedSpells)
                end
                if barData.extraSpells then
                    entry.extraSpells = DeepCopy(barData.extraSpells)
                end
                if barData.removedSpells then
                    entry.removedSpells = DeepCopy(barData.removedSpells)
                end
                if barData.dormantSpells then
                    entry.dormantSpells = DeepCopy(barData.dormantSpells)
                end
                if barData.customSpells then
                    entry.customSpells = DeepCopy(barData.customSpells)
                end
                prof.barSpells[key] = entry
            end
        end
        -- Update buff bars in spec profile
        if p.trackedBuffBars then
            prof.trackedBuffBars = DeepCopy(p.trackedBuffBars)
        end
    end

    return true, nil
end
