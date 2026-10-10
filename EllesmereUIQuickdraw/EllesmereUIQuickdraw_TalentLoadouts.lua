if EUI_CLIENT_BLOCKED then return end -- same pre-client-gate failsafe as the main file
-------------------------------------------------------------------------------
--  EllesmereUIQuickdraw_TalentLoadouts.lua
--
--  Mirrors TalentLoadoutsEx's own saved loadout list for the character's
--  CURRENT class/spec into one Quickdraw palette, one macrotext slot per
--  loadout, icon only (Quickdraw's per-slot labels are already fixed off in
--  the main file, so nothing else is needed to hide the name on the icon
--  itself). That palette can then be nested -- exactly like any other menu --
--  inside a slot of another palette (kind = "palette") using the normal
--  "Action Menu" entry in the slot-assignment picker. Point it at your
--  existing "Specializations" menu and you get a talent-loadout switcher
--  living one level down from your specs, no separate addon involved.
--
--  This file is NOT a separate addon: it must ship inside the
--  EllesmereUIQuickdraw folder and be listed in EllesmereUIQuickdraw.toc
--  (after the main Lua file), so it shares that addon's `ns` table,
--  its SavedVariables (EllesmereUIQuickdrawDB) and its load order.
--
--  What it depends on from TalentLoadoutsEx: the raw SavedVariables global
--  `TalentLoadoutEx[classFilename][specIndex]`, which is a dense array of
--  either a Config ({name, icon, text, ...}) or a Group ({name, icon,
--  isExpanded}). Groups are skipped: there is nothing for /tlx to load from
--  one. Applying a loadout goes through TalentLoadoutsEx's own `/tlx <name>`
--  slash command (see its modules/command.lua), the same path its own UI and
--  its macro-conditional users go through -- nothing here touches talents
--  directly.
--
--  Two ways to reach the mirrored palette, and they are not exclusive:
--    - manually, nesting it under any menu the normal way, through that
--      menu's "Nest Another Action Menu" entry in the slot-assignment
--      picker (its name is "Talent Loadouts", see TALENT_LOADOUT_PALETTE_NAME
--      below);
--    - automatically, through ns.ActiveSpecNestPalette (an extension point
--      on the patched ChildIndex, in the main file): every "spec"/
--      "dynamicspec" slot ANYWHERE in the profile nests into this palette
--      the moment it names the spec the character is CURRENTLY on, no
--      manual nesting slot required for it. A different spec's own icon is
--      untouched by this and still just switches to it on release; only the
--      icon for the spec you are already on stops firing a no-op switch and
--      opens the list instead. Since it is always the SAME mirrored
--      palette, and that palette always reflects whichever spec is
--      currently active, this falls out correctly on its own: Affliction's
--      icon only ever offers Affliction's loadouts, because it can only
--      ever be a door while Affliction is the one active spec there is
--      loadouts for.
--
--  The little corner pip (the same one world-marker slots use, "is this
--  marker on the ground right now") also lights up here for two things, once
--  the matching MarkerPip patch is applied to the main file:
--    - a "spec"/"dynamicspec" slot, when it names the spec this character is
--      currently on;
--    - one of this file's loadout slots, when the active talent configuration
--      matches the saved TLEx build. Reads do not depend on the Talents UI
--      or TLEx's UI-driven GetLoadedData cache.
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

-- The palette this file owns. Change this (and rename the palette to match,
-- or just let it recreate one under the new name) to point it elsewhere.
local TALENT_LOADOUT_PALETTE_NAME = "Talent Loadouts"

-- The current class/spec's loadout array from TalentLoadoutsEx's own
-- SavedVariables, or nil if it isn't loaded yet / has nothing saved.
local function GetTalentLoadoutSpecTable()
    local TLX = _G.TalentLoadoutEx
    if type(TLX) ~= "table" then return nil end

    local _, classFilename = UnitClass("player")
    local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    if not classFilename or not specIndex then return nil end

    local classTable = TLX[classFilename]
    local specTable = classTable and classTable[specIndex]
    return type(specTable) == "table" and specTable or nil
end

-- One macrotext slot per saved Config in the current spec's list (Groups --
-- entries with no .text -- are skipped, see the header above).
local function BuildTalentLoadoutSlots()
    local specTable = GetTalentLoadoutSpecTable()
    if not specTable then return {} end

    local slots = {}
    for _, data in ipairs(specTable) do
        if data.text and data.name and #data.name > 0 and #slots < ns.MAX_SLOTS then
            local icon = data.icon
            -- TalentLoadoutsEx stores a hero-talent icon as an ATLAS NAME
            -- (a string) and every other icon as a numeric fileID.
            -- Quickdraw's SetIconTexture/ApplyIconCrop only recognise the
            -- atlas form wrapped as { atlas = ... } (see the "macrotext"
            -- branch of SlotDisplay in the main file) -- a bare string would
            -- be handed to SetTexture and fail to resolve as a file path.
            if type(icon) == "string" then
                icon = { atlas = icon }
            end

            slots[#slots + 1] = {
                kind = "macrotext",
                macrotext = "/tlx " .. data.name,
                icon = icon,
                -- Never drawn on the icon itself -- Quickdraw's per-slot
                -- labels are fixed off -- kept only so the slot picker/editor
                -- can still identify the entry by name if you go looking.
                name = data.name,
                -- Read by ns.IsMacrotextSlotActive below, and by nothing
                -- else -- this is what lets the patched MarkerPip (in the
                -- main file) tell one of OUR slots apart from a plain custom
                -- macro, without the main file knowing TalentLoadoutsEx
                -- exists.
                talentLoadoutName = data.name,
            }
        end
    end
    return slots
end

-- Finds the palette by name, or creates one at the first free index so the
-- very first login already has something for a "palette" slot to point at.
-- Returns the palette table and its index.
--
-- p.paletteCount (bumped below) is a SEPARATE counter from the palettes
-- table itself -- it is what "Add Action Menu" increments, and it is what
-- the options page's nesting picker (PaletteEntries) and the runtime's own
-- palette push (PushAllPalettes) loop over (1..paletteCount), NOT 1..MAX_
-- PALETTES. A palette written straight into p.palettes past that count
-- exists and can be READ (EnsurePalette does not care), but is invisible to
-- both of those loops -- which is exactly the "only shows TMARK/WMARK in the
-- Nest Another Action Menu list" symptom this fixes.
local function FindOrCreateTalentLoadoutPalette()
    local p = ns.Profile()
    if not p then return nil end

    local function ClaimCount(index)
        if not p.paletteCount or p.paletteCount < index then
            p.paletteCount = index
        end
    end

    if type(p.palettes) == "table" then
        for index, palette in pairs(p.palettes) do
            if type(palette) == "table" and palette.name == TALENT_LOADOUT_PALETTE_NAME then
                ClaimCount(index)
                return ns.EnsurePalette(index), index
            end
        end
    end

    for index = 1, ns.MAX_PALETTES do
        if not (p.palettes and p.palettes[index]) then
            local palette = ns.EnsurePalette(index)
            if palette then
                palette.name = TALENT_LOADOUT_PALETTE_NAME
                ClaimCount(index)
                return palette, index
            end
        end
    end

    return nil -- every palette slot (MAX_PALETTES) is already taken
end

local lastIndex, lastCount
local function RefreshTalentLoadoutPalette(announce)
    local palette, index = FindOrCreateTalentLoadoutPalette()
    if not palette then
        if announce then
            print("|cff0cd29fEllesmereUI Quickdraw|r: no free Action Menu slot to hold \"" ..
                  TALENT_LOADOUT_PALETTE_NAME .. "\" (all " .. ns.MAX_PALETTES .. " are in use).")
        end
        return
    end

    palette.slots = BuildTalentLoadoutSlots()

    -- Read by the patched ChildIndex in the main file: a spec/dynamicspec
    -- slot nests into THIS palette while it names the character's current
    -- spec, so releasing on the active spec's own icon opens the loadout
    -- list instead of firing a no-op switch-to-the-spec-you-are-already-on.
    -- A different spec's slot is untouched -- it still just switches.
    local changed = ns.ActiveSpecNestPalette ~= index
    ns.ActiveSpecNestPalette = index
    if changed and ns.RequestPush then
        -- Only on the index actually changing (first run, or a fresh
        -- palette claimed after the old one vanished): the spec slots'
        -- pushed attributes need to be told the door exists. Every other
        -- refresh -- a spec swap, a saved loadout added -- lands where the
        -- existing SPELLS_CHANGED-driven push already reaches on its own.
        ns.RequestPush()
    end

    lastIndex, lastCount = index, #palette.slots

    if announce then
        print("|cff0cd29fEllesmereUI Quickdraw|r: \"" .. TALENT_LOADOUT_PALETTE_NAME ..
              "\" (Action Menu " .. index .. ") now has " .. lastCount ..
              " talent loadout" .. (lastCount == 1 and "" or "s") ..
              " for your current spec. Nest it under another menu with an Action Menu slot pointed at Action Menu " .. index .. ", or let your spec slots open it directly (see the header of this file).")
    end
end
ns.RefreshTalentLoadoutPalette = RefreshTalentLoadoutPalette

-------------------------------------------------------------------------------
--  "Is this one currently applied?" -- read by the patched MarkerPip in the
--  main file (PaletteView:SlotIsPipped's macrotext branch) for any slot that
--  carries a .talentLoadoutName, i.e. one of the slots this file builds.
--  Left generic on the main-file side on purpose: it has no idea
--  TalentLoadoutsEx exists, it just asks ns for an opinion on a macrotext
--  slot when one is offered.
-------------------------------------------------------------------------------
-- Decode with Blizzard's stateless import/export mixin, passing the active
-- config/tree explicitly. Never use the panel's potentially stale config,
-- and never invoke TLEx's import helpers (which can change starter builds).
local function ReadLoadoutEntries(text, configID, specID, treeID)
    local parser = ClassTalentImportExportMixin
    if not parser or not ExportUtil or type(text) ~= "string" or text == "" then return nil end
    local ok, entries = pcall(function()
        local stream = ExportUtil.MakeImportDataStream(text)
        local valid, version, savedSpec, hash = parser:ReadLoadoutHeader(stream)
        if not valid or savedSpec ~= specID
           or version ~= C_Traits.GetLoadoutSerializationVersion() then return nil end
        if not parser:IsHashEmpty(hash)
           and not parser:HashEquals(hash, C_Traits.GetTreeHash(treeID)) then return nil end
        local content = parser:ReadLoadoutContent(stream, treeID)
        return parser:ConvertToImportLoadoutEntryInfo(configID, treeID, content)
    end)
    return ok and entries or nil
end

local activeSnapshot
local function InvalidateActiveLoadout()
    activeSnapshot = nil
end

-- Shared by the pip and ready-check text. A short snapshot avoids decoding
-- every saved build for every slot on every render tick. Failed reads are
-- retried on the next query; spec/config changes bypass the snapshot.
local function ResolveActiveLoadoutEntries()
    local specTable = GetTalentLoadoutSpecTable()
    if not specTable or not C_ClassTalents or not C_Traits then return nil end
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specID = specIndex and C_SpecializationInfo.GetSpecializationInfo(specIndex)
    local configID = C_ClassTalents.GetActiveConfigID()
    local treeID = specID and C_ClassTalents.GetTraitTreeForSpec(specID)
    if not configID or not treeID or not C_Traits.GenerateImportString then return nil end

    local now = GetTime()
    if activeSnapshot and activeSnapshot.specID == specID
       and activeSnapshot.configID == configID and activeSnapshot.specTable == specTable
       and now - activeSnapshot.time < 0.2 then
        return activeSnapshot.entries
    end

    local ok, currentText = pcall(C_Traits.GenerateImportString, configID)
    if not ok or type(currentText) ~= "string" or currentText == "" then return nil end
    local current = ReadLoadoutEntries(currentText, configID, specID, treeID)
    if not current or #current == 0 then return nil end
    local byEntry = {}
    for _, entry in ipairs(current) do byEntry[entry.selectionEntryID] = entry end

    local options = TalentLoadoutEx.Option
    local pvp = options and options.IsEnabledPvp
        and C_SpecializationInfo.GetAllSelectedPvpTalentIDs() or {}
    local entries = {}
    for _, data in ipairs(specTable) do
        if data.text and data.name and not data.isLegacy then
            local matches = data.text == currentText
            if not matches then
                local saved = ReadLoadoutEntries(data.text, configID, specID, treeID)
                matches = saved ~= nil and #saved > 0
                -- Match TLEx's entry/rank comparison, including partial builds
                -- and equivalent exports with different header hashes.
                for _, entry in ipairs(saved or {}) do
                    local applied = byEntry[entry.selectionEntryID]
                    if not applied or applied.ranksGranted ~= entry.ranksGranted
                       or applied.ranksPurchased ~= entry.ranksPurchased then
                        matches = false
                        break
                    end
                end
            end
            for index, talentID in ipairs(pvp) do
                local savedID = tonumber(data["pvp" .. index])
                if savedID and savedID ~= talentID then matches = false end
            end
            if matches then entries[#entries + 1] = { name = data.name, icon = data.icon } end
        end
    end
    activeSnapshot = { specID = specID, configID = configID, specTable = specTable,
        time = now, entries = #entries > 0 and entries or nil }
    return activeSnapshot.entries
end

-- Keep the historical single-name resolver for callers that explicitly want
-- one canonical name.  The pip must NOT use it, though: TalentLoadoutsEx can
-- have several differently named saved loadouts whose talent data is identical,
-- and every one of those slots represents the currently applied build.
local function ResolveActiveLoadoutName()
    local entries = ResolveActiveLoadoutEntries()
    if not entries then return nil end
    return entries[#entries].name
end
ns.GetActiveTalentLoadoutName = ResolveActiveLoadoutName

-------------------------------------------------------------------------------
-- Optional NSRT shared-note check. Only compare plain SavedVariables names:
-- no encounter/unit tokens, protected combat data or talent changes involved.
-- Normalize punctuation so Nek'zali/Nekzali and Kith'ix/Kithix agree.
-------------------------------------------------------------------------------
local NSRT_BOSSES = {
    { name = "Nek'zali",          aliases = { "nekzali" } },
    { name = "Lost Explorers",    aliases = { "lostexplorers", "explorers" } },
    { name = "Sszorak",           aliases = { "sszorak" } },
    { name = "Entombed Sentinels",aliases = { "entombedsentinels", "sentinels" } },
    { name = "Vashnik",           aliases = { "vashnik" } },
    { name = "Twin Fangs",        aliases = { "twinfangs" } },
    { name = "Coiled Altar",      aliases = { "coiledaltar" } },
    { name = "Ula'tek",           aliases = { "ulatek" } },
    { name = "Nymrissa",          aliases = { "nymrissa" } },
    { name = "Kith'ix",           aliases = { "kithix" } },
}

local function BossesInName(value)
    local result, seen = {}, {}
    if type(value) ~= "string" or value == "" then return result end
    local folded = value:lower():gsub("[^%w]", "")
    for _, boss in ipairs(NSRT_BOSSES) do
        for _, alias in ipairs(boss.aliases) do
            if folded:find(alias, 1, true) then
                if not seen[boss.name] then
                    seen[boss.name] = true
                    result[#result + 1] = boss.name
                end
                break
            end
        end
    end
    return result
end

local function NSRTCheckEnabled()
    local p = ns.Profile and ns.Profile()
    return p and p.nsrtLoadoutCheckEnabled == true
end

local function NSRTSoundEnabled()
    local p = ns.Profile and ns.Profile()
    return p and p.nsrtLoadoutMismatchSoundEnabled == true
end

-- Use the same curated sound list and LibSharedMedia entries as other EUI
-- sound selectors. Preview and runtime playback share this resolver.
local function PlayNSRTCheckSound(key)
    if not key or key == "none" then return end
    if not (EllesmereUI and EllesmereUI.BuildAlertSoundTables) then return end
    local paths, names, order = EllesmereUI.BuildAlertSoundTables()
    if EllesmereUI.AppendSharedMediaSounds then
        EllesmereUI.AppendSharedMediaSounds(paths, names, order)
    end
    local value = paths[key]
    if not value or value == 1 then return end
    if EllesmereUI._PlayLSMSound then
        EllesmereUI._PlayLSMSound(value)
    elseif type(value) == "number" then
        PlaySound(value, "Master")
    elseif type(value) == "string" then
        PlaySoundFile(value, "Master")
    end
end
ns.PlayNSRTCheckSound = PlayNSRTCheckSound

-- Third return value: individual status for each active TLEx entry, so the
-- ready-check atlas is displayed immediately after THAT entry's name.
-- No icon/sound is emitted for unknown notes, absent TLEx data, or names
-- without any of the known bosses. An exact boss overlap is required.
local function GetNSRTLoadoutCheck(active)
    local nsrt = _G.NSRT
    if type(nsrt) ~= "table" then
        return "unknown", "NSRT: addon not loaded"
    end
    local note = nsrt.ActiveReminder
    if type(note) ~= "string" or note == "" then
        return "unknown", "NSRT: no shared note loaded"
    end
    local noteBosses = BossesInName(note)
    if #noteBosses == 0 then
        return "unknown", "NSRT: boss not recognized in shared note (" .. note .. ")"
    end

    -- Multiple TLEx names can resolve to identical active talents. The global
    -- outcome is MATCH if ANY matching build name mentions the same boss as
    -- the NSRT note; other named builds retain their individual X icons.
    if active == nil then active = ResolveActiveLoadoutEntries() end
    if not active or #active == 0 then
        return "unknown", "NSRT: no matching active TLEx loadout"
    end
    local notes = {}
    for _, boss in ipairs(noteBosses) do notes[boss] = true end
    local perEntry, anyMatch, recognized, loadoutSeen, loadoutBosses = {}, false, false, {}, {}
    for i, entry in ipairs(active) do
        local entryBosses = BossesInName(entry.name)
        if #entryBosses > 0 then
            recognized = true
            local matchedBoss
            for _, boss in ipairs(entryBosses) do
                if not loadoutSeen[boss] then
                    loadoutSeen[boss] = true
                    loadoutBosses[#loadoutBosses + 1] = boss
                end
                if notes[boss] then matchedBoss = boss end
            end
            perEntry[i] = matchedBoss and "match" or "mismatch"
            if matchedBoss then anyMatch = matchedBoss end
        end
    end
    if not recognized then
        return "unknown", "NSRT: boss not recognized in active TLEx loadout"
    end
    if anyMatch then
        return "match", "NSRT: MATCH - " .. anyMatch, perEntry
    end
    return "mismatch", "NSRT: MISMATCH - note: " .. table.concat(noteBosses, ", ")
        .. " / loadout: " .. table.concat(loadoutBosses, ", "), perEntry
end
ns.GetNSRTLoadoutCheck = GetNSRTLoadoutCheck

-- Dungeons use the saved TLEx loadout NAME, without consulting NSRT or
-- encounter data.  IsInInstance() reports "party" for dungeon instances of
-- every difficulty (including normal, heroic, M0 and Mythic+).
local function InDungeonInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "party"
end

local function HasDungeonLoadoutMarker(value)
    if type(value) ~= "string" then return false end
    local upper = value:upper()
    -- Plain string searches: '+' is NOT a Lua-pattern quantifier here.
    return upper:find("M+", 1, true) ~= nil
        or upper:find("M0", 1, true) ~= nil
end

local function GetDungeonLoadoutCheck(active)
    if active == nil then active = ResolveActiveLoadoutEntries() end
    if not active or #active == 0 then
        return "unknown", "Dungeon: no matching active TLEx loadout"
    end

    -- An applied talent build can match multiple saved names. Keep each
    -- name's own status, but regard the active build as compatible if ANY
    -- matching saved name contains M+ or M0.
    local statuses, names, hasMatch = {}, {}, false
    for i, entry in ipairs(active) do
        local name = entry.name
        if type(name) == "string" and name ~= "" then
            local matched = HasDungeonLoadoutMarker(name)
            statuses[i] = matched and "match" or "mismatch"
            names[#names + 1] = name
            if matched then hasMatch = true end
        end
    end
    if #names == 0 then
        return "unknown", "Dungeon: active TLEx loadout has no name"
    end
    if hasMatch then
        return "match", "Dungeon: MATCH - active loadout contains M+ or M0", statuses
    end
    return "mismatch", "Dungeon: MISMATCH - active loadout missing M+ or M0 ("
        .. table.concat(names, ", ") .. ")", statuses
end
ns.GetDungeonLoadoutCheck = GetDungeonLoadoutCheck

-- The raid/other-instance behavior remains NSRT-based. Dungeon validation
-- never reads the NSRT note (it also works without that addon installed).
local function GetContextLoadoutCheck(active)
    if InDungeonInstance() then return GetDungeonLoadoutCheck(active) end
    return GetNSRTLoadoutCheck(active)
end
ns.GetContextLoadoutCheck = GetContextLoadoutCheck


function ns.IsMacrotextSlotActive(slot)
    local name = slot and slot.talentLoadoutName
    if not name then return false end

    local entries = ResolveActiveLoadoutEntries()
    if not entries then return false end
    for _, entry in ipairs(entries) do
        if entry.name == name then return true end
    end
    return false
end

-- Load the parser and TLEx's slash-command dependencies without showing any
-- frames. Loading is deferred in combat; direct reads keep working once loaded.
local pendingTalentSupport = false
local function EnsureTalentSupport()
    if InCombatLockdown() then
        pendingTalentSupport = true
        return
    end
    pendingTalentSupport = false
    if type(_G.TalentLoadoutEx) == "table" and C_AddOns
       and not C_AddOns.IsAddOnLoaded("Blizzard_PlayerSpells") then
        C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
    end
    InvalidateActiveLoadout()
end

-------------------------------------------------------------------------------
--  On-screen loadout announcement -- a plain, oversized text reminder of
--  which saved TalentLoadoutsEx loadout is active. Shown on ready checks,
--  when the player's applied talent/loadout state changes, and for the first
--  five seconds of a player pull countdown on a context-specific mismatch.
--  The display is always hidden on entering combat and can never reopen
--  until combat ends. The mirrored palette's pips answer "which loadouts match what I
--  have applied" on demand; this pushes the full resolved set to the player
--  without them having to open Quickdraw to look.
--
--  "Repeat Every" is a COOLDOWN on READY-CHECK triggers only, not a standalone
--  timer and not a throttle on talent swaps: a ready check fires the
--  announcement, but if another one lands before the configured number of
--  minutes has passed since the last ready-check pop, it is silently skipped.
--  An actual talent/loadout change gets its own pop using the same Text
--  Duration as ready checks. Pull-specific mismatch pops bypass Repeat Every
--  and use a fixed 5-second duration, subject to the combat hide rule.
--
--  Font size, on-screen duration, the cooldown length and the master on/off
--  all live in the profile (read through ns.Profile(), the same accessor
--  the options page uses) so they are editable from the Specialization
--  action menu's Appearance section -- see EUI_Quickdraw_Options.lua, which
--  is also what greys this whole feature out on every OTHER action menu,
--  since it has nothing to do with one that carries no spec/loadout
--  entries. Position is NOT a profile-appearance setting: it is a normal
--  Unlock Mode element (see RegisterLoadoutTextUnlock below), draggable and
--  resettable the same way every other movable piece of the suite is.
-------------------------------------------------------------------------------
local ANNOUNCE_DURATION_DEFAULT  = 10   -- seconds the text stays on screen
local ANNOUNCE_COOLDOWN_DEFAULT  = 10   -- minutes between two ready-check pops
local ANNOUNCE_FONT_SIZE_DEFAULT = 30
local ANNOUNCE_ROW_GAP_DEFAULT   = 6    -- pixels between two stacked loadout lines
local ANNOUNCE_DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 300 }

local function AnnounceEnabled()
    local p = ns.Profile and ns.Profile()
    return p and p.loadoutTextEnabled == true
end

local function AnnounceFontSize()
    local p = ns.Profile and ns.Profile()
    return (p and p.loadoutTextFontSize) or ANNOUNCE_FONT_SIZE_DEFAULT
end

local function AnnounceDuration()
    local p = ns.Profile and ns.Profile()
    return (p and p.loadoutTextDuration) or ANNOUNCE_DURATION_DEFAULT
end

-- Pixels between two stacked loadout lines when more than one entry matches
-- -- "Line Spacing" on the Appearance page.
local function AnnounceRowGap()
    local p = ns.Profile and ns.Profile()
    local gap = p and p.loadoutTextRowGap
    if gap == nil then return ANNOUNCE_ROW_GAP_DEFAULT end
    return gap
end

-- Stored in MINUTES (what the slider shows); the cooldown check below wants
-- seconds, read fresh on every ready check so a slider change applies to the
-- very next one with nothing else to refresh.
local function AnnounceCooldownSeconds()
    local p = ns.Profile and ns.Profile()
    local minutes = (p and p.loadoutTextIntervalMin) or ANNOUNCE_COOLDOWN_DEFAULT
    return minutes * 60
end

local function AnnouncePos()
    local p = ns.Profile and ns.Profile()
    local pos = p and p.loadoutTextPos
    if pos and pos.point then return pos end
    return ANNOUNCE_DEFAULT_POS
end

local function ApplyAnnouncePosition(f)
    local pos = AnnouncePos()
    f:ClearAllPoints()
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

-- TalentLoadoutsEx stores a hero-talent icon as an ATLAS NAME (a string) and
-- every other icon as a numeric fileID -- same distinction BuildTalentLoadout
-- Slots above already has to make for Quickdraw's own icon widgets.
local function ApplyAnnounceIcon(tex, icon)
    if type(icon) == "string" then
        tex:SetAtlas(icon)
    elseif type(icon) == "number" then
        tex:SetTexture(icon)
    else
        tex:SetTexture(134400) -- INV_Misc_QuestionMark: no icon on record
    end
end

local announceFrame
local function EnsureAnnounceFrame()
    if announceFrame then return announceFrame end

    local f = CreateFrame("Frame", "EllesmereUIQuickdrawLoadoutAnnounce", UIParent)
    f:SetSize(640, 60)
    f:SetFrameStrata("HIGH")
    f:Hide()
    ApplyAnnouncePosition(f)
    f.rows = {} -- pooled { icon = Texture, text = FontString } rows, one per entry

    announceFrame = f
    return f
end

local function EnsureAnnounceRow(f, i)
    local row = f.rows[i]
    if row then return row end

    row = CreateFrame("Frame", nil, f)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- crop the default Blizzard icon border

    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.text:SetTextColor(1, 1, 1, 1)

    -- Same native green check/red X atlases used by EUI Raid Frames' ready check.
    row.status = row:CreateTexture(nil, "OVERLAY")
    row.status:SetPoint("LEFT", row.text, "RIGHT", 5, 0)
    row.status:Hide()

    f.rows[i] = row
    return row
end

-- Lays out one icon+name row per resolved entry, stacked top to bottom
-- ("separated into paragraphs" per request), each centered as its own
-- icon+text block under the frame's anchor point, and sizes the frame to
-- fit however many entries there are this time. Re-run on every show (not
-- just once at creation) so a live font-size change takes effect immediately
-- and the row count can grow or shrink between one ready check and the next.
local function ApplyAnnounceStyle(f, entries)
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("quickdraw")) or STANDARD_TEXT_FONT
    local size = AnnounceFontSize()
    local rowH = math.ceil(size * 1.3)
    local rowGap = AnnounceRowGap()

    local maxWidth = 0
    for i, entry in ipairs(entries) do
        local row = EnsureAnnounceRow(f, i)
        row:SetSize(1, rowH) -- width corrected below once the text is measured
        row.icon:SetSize(size, size)
        ApplyAnnounceIcon(row.icon, entry.icon)
        row.text:SetFont(fontPath, size, "OUTLINE")
        row.text:SetText(entry.name)
        row.text:SetTextColor(1, 1, 1, 1)
        local status = entry.nsrtStatus
        local statusWidth = 0
        if status == "match" or status == "mismatch" then
            row.status:SetSize(size, size)
            row.status:SetAtlas(status == "match" and "UI-LFG-ReadyMark-Raid"
                or "UI-LFG-DeclineMark-Raid")
            row.status:Show()
            statusWidth = size + 5
        else
            row.status:Hide()
        end

        row:ClearAllPoints()
        if i == 1 then
            row:SetPoint("TOP", f, "TOP", 0, 0)
        else
            row:SetPoint("TOP", f.rows[i - 1], "BOTTOM", 0, -rowGap)
        end

        local w = size + 8 + row.text:GetStringWidth() + statusWidth
        row:SetWidth(w)
        if w > maxWidth then maxWidth = w end
        row:Show()
    end

    -- A previous, longer list can leave stale rows behind in the pool.
    for i = #entries + 1, #f.rows do
        f.rows[i]:Hide()
    end

    local totalH = #entries * rowH + math.max(0, #entries - 1) * rowGap
    f:SetSize(math.max(maxWidth, 10), math.max(totalH, 10))
end

-- GetTime() of the last READY-CHECK pop that actually made it to the screen --
-- nil means "never yet this session", which always passes the ready-check
-- cooldown below. Talent/loadout-change pops intentionally do not touch it.
local lastReadyCheckShownAt
local lastEntries
local announceHideTimer

-- An ordinary, non-secure display. Combat always takes precedence over
-- ready checks, pull countdowns, talent changes, callbacks and diagnostics.
local announcementCombat = InCombatLockdown and InCombatLockdown() or false
local function AnnouncementInCombat()
    return announcementCombat or (InCombatLockdown and InCombatLockdown())
end
local function HideLoadoutAnnouncement()
    if announceHideTimer then
        announceHideTimer:Cancel()
        announceHideTimer = nil
    end
    if announceFrame then announceFrame:Hide() end
end

-- Audio is evaluated ONLY when a ready check or player pull countdown starts.
-- Refreshes from the CURRENT TLEx talents and NSRT note at trigger time;
-- talent swaps, note changes, manual diagnostics and text redraws stay silent.
local function WarnNSRTMismatchOnRaidPrompt()
    if not NSRTCheckEnabled() or not NSRTSoundEnabled() then return end
    -- Only sound inside an actual raid instance. A raid group in the open
    -- world, a dungeon or a PvP instance must never trigger this alert.
    -- Keep the manual options sound preview independent of this restriction.
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "raid" then return end
    InvalidateActiveLoadout()
    if GetNSRTLoadoutCheck() ~= "mismatch" then return end
    local p = ns.Profile and ns.Profile()
    PlayNSRTCheckSound((p and p.nsrtLoadoutMismatchSoundKey) or "robotblip")
end

local function ShowLoadoutAnnouncement(fromTalentChange, forPullCountdown)
    -- Never expose loadout text in combat, even if a previously scheduled
    -- callback or option toggle attempts to display it after combat starts.
    if AnnouncementInCombat() then
        HideLoadoutAnnouncement()
        return
    end
    if not AnnounceEnabled() then return end

    -- The pull reminder is distinct from the existing ready-check/talent
    -- reminder: it ignores Repeat Every, requires a mismatch for the current
    -- instance type (NSRT in raids; M+/M0 in dungeons), and
    -- lasts exactly five seconds rather than using Text Duration.
    local now = GetTime()
    if not fromTalentChange and not forPullCountdown then
        local cooldown = AnnounceCooldownSeconds()
        if cooldown > 0 and lastReadyCheckShownAt ~= nil
            and (now - lastReadyCheckShownAt) < cooldown then
            return
        end
    end

    local active = ResolveActiveLoadoutEntries()
    local status, perEntry
    if NSRTCheckEnabled() then
        local _, _, statuses
        status, _, statuses = GetContextLoadoutCheck(active)
        perEntry = statuses
    end
    if forPullCountdown and status ~= "mismatch" then
        -- A preceding ready-check message must not linger into a pull whose
        -- current loadout is correct or whose note cannot be verified.
        HideLoadoutAnnouncement()
        return
    end
    if not active then return end

    -- Preserve multiple active TLEx entries, with an individual check/X next
    -- to each name rather than a separate NSRT status line.
    local entries = {}
    for i, entry in ipairs(active) do
        entries[#entries + 1] = {
            name = entry.name,
            icon = entry.icon,
            nsrtStatus = perEntry and perEntry[i] or nil,
        }
    end
    if #entries == 0 then return end

    if not fromTalentChange and not forPullCountdown then
        lastReadyCheckShownAt = now
    end
    lastEntries = entries

    local f = EnsureAnnounceFrame()
    ApplyAnnounceStyle(f, entries)
    -- The combat state may have changed while checking the TLEx names.
    if AnnouncementInCombat() then HideLoadoutAnnouncement(); return end
    f:Show()

    local duration = forPullCountdown and 5 or AnnounceDuration()
    if announceHideTimer then announceHideTimer:Cancel() end
    announceHideTimer = C_Timer.NewTimer(duration, function()
        announceHideTimer = nil
        f:Hide()
    end)
end
ns.ShowLoadoutAnnouncement = ShowLoadoutAnnouncement

-- A manual diagnostic also works while the on-screen text is disabled.
-- This is intentionally read-only and safe to invoke in combat.
SLASH_EUIQUICKDRAWNSRTCHECK1 = "/eui-nsrt-check"
SlashCmdList["EUIQUICKDRAWNSRTCHECK"] = function()
    local status, message = GetContextLoadoutCheck()
    local color = status == "match" and "|cff40ff6b"
        or status == "mismatch" and "|cffff4d4d" or "|cffffc74d"
    print("|cff0cd29fEllesmereUI Quickdraw|r: " .. color .. message .. "|r")
    if NSRTCheckEnabled() and AnnounceEnabled() then
        ShowLoadoutAnnouncement(true)
    end
end

-- Register through NSRT's public CallbackHandler API (dot-call; the first
-- argument is our unique callback owner). The callback is fired by SetReminder,
-- including playlist changes and unloading notes.
local nsrtCallbackRegistered = false
local function RegisterNSRTNoteCallback()
    if nsrtCallbackRegistered then return end
    local api = _G.NSAPI
    if not api or type(api.RegisterCallback) ~= "function" then return end
    api.RegisterCallback("EllesmereUIQuickdraw", "NSRT_REMINDER_CHANGED", function()
        C_Timer.After(0, function()
            if NSRTCheckEnabled() and AnnounceEnabled() and not InDungeonInstance() then
                ShowLoadoutAnnouncement(true)
            end
        end)
    end)
    nsrtCallbackRegistered = true
end

-- Called by the options page whenever the font size changes, so a slider
-- takes effect immediately instead of waiting for the next ready check --
-- re-lays-out the CURRENTLY visible text (if any) with the new size right
-- away. Duration and the cooldown are both read fresh at the moment they
-- matter (AnnounceDuration inside the hide timer, AnnounceCooldownSeconds
-- inside the ready-check check above), so neither needs anything here.
function ns.RefreshLoadoutTextSettings()
    if AnnouncementInCombat() or not AnnounceEnabled() then
        HideLoadoutAnnouncement()
        return
    end
    if announceFrame and announceFrame:IsShown() and lastEntries then
        ApplyAnnounceStyle(announceFrame, lastEntries)
    end
end

-------------------------------------------------------------------------------
--  Unlock Mode: lets the announcement text be dragged anywhere on screen,
--  the same way every other movable piece of the suite is repositioned.
--  Follows the same shape as EllesmereUIQoL_FlightTimer.lua's mover (a
--  fixed-size, non-resizable, sometimes-hidden HUD element).
-------------------------------------------------------------------------------
local function RegisterLoadoutTextUnlock()
    local MK = EllesmereUI.MakeUnlockElement
    if not MK then return end
    EllesmereUI:RegisterUnlockElements({
        MK({
            key      = "EUI_QuickdrawLoadoutText",
            label    = "Quickdraw: Loadout Text",
            group    = "Quickdraw",
            order    = 100,
            -- Off the mover list entirely while the feature itself is off
            -- (mirrors the Flight Timer bar / FPS Counter pattern) -- there
            -- is nothing meaningful to drag if it never shows.
            isHidden = function() return not AnnounceEnabled() end,
            getFrame = function() return EnsureAnnounceFrame() end,
            getSize  = function()
                if announceFrame then return announceFrame:GetWidth(), announceFrame:GetHeight() end
                return 640, 60
            end,
            noResize = true,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                local p = ns.Profile and ns.Profile()
                if not p then return end
                p.loadoutTextPos = { point = point, relPoint = relPoint, x = x, y = y }
                if announceFrame and not EllesmereUI._unlockActive then
                    ApplyAnnouncePosition(announceFrame)
                end
            end,
            loadPos = function() return AnnouncePos() end,
            clearPos = function()
                local p = ns.Profile and ns.Profile()
                if p then p.loadoutTextPos = nil end
                if announceFrame then ApplyAnnouncePosition(announceFrame) end
            end,
            applyPos = function()
                local f = EnsureAnnounceFrame()
                ApplyAnnouncePosition(f)
            end,
        }),
    })
end
ns.RegisterLoadoutTextUnlock = RegisterLoadoutTextUnlock

-- Compact fingerprint of the applied talent state. Comparing this after the
-- existing event debounce keeps one loadout swap (which can fire a burst of
-- TRAIT_CONFIG_UPDATED / PLAYER_TALENT_UPDATE events) to one announcement,
-- while ignoring noisy talent events that did not actually change the build.
-- The active config id distinguishes two native loadouts with identical talent
-- contents; PvP talents are appended because they live outside the PvE export.
local function CurrentTalentStateKey()
    if not C_ClassTalents or not C_Traits or not C_Traits.GenerateImportString then return nil end
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return nil end

    local ok, text = pcall(C_Traits.GenerateImportString, configID)
    if not ok or type(text) ~= "string" or text == "" then return nil end

    local pvpKey = ""
    if C_SpecializationInfo and C_SpecializationInfo.GetAllSelectedPvpTalentIDs then
        local pvp = C_SpecializationInfo.GetAllSelectedPvpTalentIDs() or {}
        local ids = {}
        for i = 1, #pvp do ids[i] = tostring(pvp[i] or 0) end
        pvpKey = table.concat(ids, ",")
    end
    return tostring(configID) .. "\031" .. text .. "\031" .. pvpKey
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")
watcher:RegisterEvent("PLAYER_TALENT_UPDATE")
watcher:RegisterEvent("PLAYER_PVP_TALENT_UPDATE")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("READY_CHECK")
-- Blizzard pull countdowns (including /pull from DBM and BigWigs).
-- START_PLAYER_COUNTDOWN and START_TIMER can both fire for one countdown.
watcher:RegisterEvent("START_PLAYER_COUNTDOWN")
watcher:RegisterEvent("START_TIMER")
local lastPullWarningAt
local refreshGeneration = 0
local lastTalentStateKey
local talentAnnouncementPending = false
watcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_REGEN_DISABLED" then
        announcementCombat = true
        HideLoadoutAnnouncement()
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        announcementCombat = false
        -- Do not reshow a dismissed reminder just because combat ended.
    end
    if event == "ADDON_LOADED" then
        if arg1 == "NorthernSkyRaidTools" then
            -- The NSAPI table may be published after ADDON_LOADED settles.
            C_Timer.After(0, RegisterNSRTNoteCallback)
            return
        end
        if arg1 ~= "TalentLoadoutsEx" then return end
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        RegisterNSRTNoteCallback()
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 ~= "player" then return end

    if event == "START_PLAYER_COUNTDOWN" or event == "START_TIMER" then
        -- START_TIMER also covers PvP and challenge mode countdowns: ignore
        -- those. START_PLAYER_COUNTDOWN has secret-capable arguments in
        -- Midnight, so deliberately never inspect its event payload.
        if event == "START_TIMER" then
            local playerCountdown = Enum and Enum.StartTimerType
                and Enum.StartTimerType.PlayerCountdown or 2
            if arg1 ~= playerCountdown then return end
        end
        local now = GetTime()
        -- The same Blizzard countdown can generate BOTH native events.
        if not lastPullWarningAt or now - lastPullWarningAt >= 1 then
            lastPullWarningAt = now
            WarnNSRTMismatchOnRaidPrompt()
            -- Show a CURRENT raid/NSRT or dungeon/M+/M0 mismatch for five seconds.
            -- This is not gated by the ready-check Repeat Every cooldown.
            if NSRTCheckEnabled() then
                InvalidateActiveLoadout()
                ShowLoadoutAnnouncement(true, true)
            end
        end
        return
    end

    if event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE"
       or event == "PLAYER_PVP_TALENT_UPDATE" then
        talentAnnouncementPending = true
    end

    InvalidateActiveLoadout()

    if event == "READY_CHECK" then
        EnsureTalentSupport()
        WarnNSRTMismatchOnRaidPrompt()
        ShowLoadoutAnnouncement(false)
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Remove a reminder from the previous zone: the check can change
        -- when crossing the raid/dungeon boundary even without a talent swap.
        HideLoadoutAnnouncement()
        RegisterLoadoutTextUnlock()
    end
    if event ~= "PLAYER_REGEN_ENABLED" or pendingTalentSupport then
        EnsureTalentSupport()
    end

    -- Let spec/config events settle, canceling callbacks from earlier swaps.
    -- Further reads always query the active config, even if it arrives later.
    refreshGeneration = refreshGeneration + 1
    local generation = refreshGeneration
    C_Timer.After(0.2, function()
        if generation ~= refreshGeneration then return end
        InvalidateActiveLoadout()
        RefreshTalentLoadoutPalette(false)
        if ns.RequestPush then ns.RequestPush() end

        local stateKey = CurrentTalentStateKey()
        if stateKey then
            local changed = lastTalentStateKey ~= nil and stateKey ~= lastTalentStateKey
            lastTalentStateKey = stateKey
            if changed and talentAnnouncementPending then
                -- Uses the exact same frame/style/Text Duration as ready checks,
                -- but intentionally bypasses their Repeat Every cooldown.
                InvalidateActiveLoadout()
                ShowLoadoutAnnouncement(true)
            end
            talentAnnouncementPending = false
        end
    end)
end)

-- Manual refresh / sanity check without a UI reload, e.g. right after saving
-- a new loadout in TalentLoadoutsEx.
SLASH_EUIQUICKDRAWTALENTLOADOUTS1 = "/eui-tlx"
SlashCmdList["EUIQUICKDRAWTALENTLOADOUTS"] = function()
    EnsureTalentSupport()
    RefreshTalentLoadoutPalette(true)
end
