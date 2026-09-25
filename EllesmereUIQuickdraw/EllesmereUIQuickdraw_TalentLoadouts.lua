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

-- The single canonical "active loadout name" for the pip (IsMacrotextSlotActive
-- below): the LAST matching entry in the spec's own list order (rather than
-- the first match, or treating every match as simultaneously "active") gives
-- a single, deterministic answer that matches how TalentLoadoutsEx's own
-- list reads top to bottom -- whatever is listed lowest is treated as the
-- "current" name for a build shared across more than one saved entry.
local function ResolveActiveLoadoutName()
    local entries = ResolveActiveLoadoutEntries()
    if not entries then return nil end
    return entries[#entries].name
end
ns.GetActiveTalentLoadoutName = ResolveActiveLoadoutName

function ns.IsMacrotextSlotActive(slot)
    local name = slot and slot.talentLoadoutName
    if not name then return false end
    return ResolveActiveLoadoutName() == name
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
--  which saved TalentLoadoutsEx loadout is active. Shown when a ready check
--  fires (so the reminder lands right when it matters, before a pull), the
--  same way the mirrored palette's pip already answers "which loadout am I
--  on" on demand -- this just pushes that same, now-correctly-resolved
--  answer (see ResolveActiveLoadoutName above) to the player without them
--  having to open Quickdraw to look.
--
--  "Repeat Every" is a COOLDOWN on that trigger, not a standalone timer: a
--  ready check fires the announcement, but if another one lands before the
--  configured number of minutes has passed since the last time the text was
--  actually shown, it is silently skipped. Someone spamming ready checks in
--  a short window (a re-check right after a wipe, a leader double-clicking
--  it) then pops the text once, not once per ready check.
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
    row.text:SetTextColor(1, 1, 1, 1) -- always white, independent of the pip's color

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

        row:ClearAllPoints()
        if i == 1 then
            row:SetPoint("TOP", f, "TOP", 0, 0)
        else
            row:SetPoint("TOP", f.rows[i - 1], "BOTTOM", 0, -rowGap)
        end

        local w = size + 8 + row.text:GetStringWidth()
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

-- GetTime() of the last pop that actually made it to the screen -- nil means
-- "never yet this session", which always passes the cooldown check below.
local lastShownAt
local lastEntries
local announceHideTimer
local function ShowLoadoutAnnouncement()
    if not AnnounceEnabled() then return end -- master switch, off by default

    local now = GetTime()
    local cooldown = AnnounceCooldownSeconds()
    if cooldown > 0 and lastShownAt and (now - lastShownAt) < cooldown then
        -- Too soon since the last pop: this ready check (or whatever else
        -- calls this) is within the configured window of an earlier one, so
        -- it is silently skipped rather than re-popping the same text. A
        -- cooldown of 0 (the slider's minimum) disables this check entirely
        -- -- every ready check pops the text, no matter how close together.
        return
    end

    -- Every saved entry the CURRENT talents match, not just one: a build
    -- shared across two differently-named/iconed loadouts announces all of
    -- them, one paragraph each, rather than picking a single "winner" the
    -- way the pip has to.
    local entries = ResolveActiveLoadoutEntries()
    if not entries then return end -- nothing saved/resolvable to announce

    lastShownAt = now
    lastEntries = entries

    local f = EnsureAnnounceFrame()
    ApplyAnnounceStyle(f, entries)
    f:Show()

    if announceHideTimer then announceHideTimer:Cancel() end
    announceHideTimer = C_Timer.NewTimer(AnnounceDuration(), function()
        announceHideTimer = nil
        f:Hide()
    end)
end
ns.ShowLoadoutAnnouncement = ShowLoadoutAnnouncement

-- Called by the options page whenever the font size changes, so a slider
-- takes effect immediately instead of waiting for the next ready check --
-- re-lays-out the CURRENTLY visible text (if any) with the new size right
-- away. Duration and the cooldown are both read fresh at the moment they
-- matter (AnnounceDuration inside the hide timer, AnnounceCooldownSeconds
-- inside the ready-check check above), so neither needs anything here.
function ns.RefreshLoadoutTextSettings()
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

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")
watcher:RegisterEvent("PLAYER_TALENT_UPDATE")
watcher:RegisterEvent("PLAYER_PVP_TALENT_UPDATE")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("READY_CHECK")
local refreshGeneration = 0
watcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= "TalentLoadoutsEx" then return end
    if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 ~= "player" then return end
    InvalidateActiveLoadout()

    if event == "READY_CHECK" then
        EnsureTalentSupport()
        ShowLoadoutAnnouncement()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
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
    end)
end)

-- Manual refresh / sanity check without a UI reload, e.g. right after saving
-- a new loadout in TalentLoadoutsEx.
SLASH_EUIQUICKDRAWTALENTLOADOUTS1 = "/eui-tlx"
SlashCmdList["EUIQUICKDRAWTALENTLOADOUTS"] = function()
    EnsureTalentSupport()
    RefreshTalentLoadoutPalette(true)
end
