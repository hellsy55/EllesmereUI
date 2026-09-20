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
--    - one of THIS file's loadout slots, when TalentLoadoutsEx's own public
--      API (TLX.GetLoadedData) says that exact loadout is the one currently
--      applied.
--  The second one leans on TalentLoadoutsEx's own tracking, which only runs
--  once Blizzard_PlayerSpells (the Talents & Specializations panel) has
--  loaded -- normally the first time the player opens it. This file force-
--  loads it once at login instead, so the pip works without that step. If it
--  still reads as "nothing active" right after login, it catches up on the
--  next spec change, talent change, or /tlx use.
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
function ns.IsMacrotextSlotActive(slot)
    local name = slot and slot.talentLoadoutName
    if not name then return false end

    local TLX = _G.TLX
    if type(TLX) ~= "table" or type(TLX.GetLoadedData) ~= "function" then
        return false
    end

    -- GetLoadedData hands back TalentLoadoutsEx's own loadedDataList
    -- unpacked -- zero, one, or (identical loadouts saved twice) more than
    -- one Config table, each already vetted by ITS comparison logic, not a
    -- plain string == on the export text.
    local loaded = { TLX.GetLoadedData() }
    for _, data in ipairs(loaded) do
        if data and data.name == name then
            return true
        end
    end
    return false
end

-- TalentLoadoutsEx's own "currently applied" tracking hangs off
-- hooksecurefunc(PlayerSpellsFrame.TalentsFrame, "SetShown", ...) -- the
-- TALENTS TAB, a child frame, not the PlayerSpellsFrame window itself (see
-- its modules/frame.lua). EllesmereUIActionBars' "Show When Spellbook Is
-- Open" watches the PARENT window instead (HookScript on PlayerSpellsFrame's
-- own OnShow/OnHide). Those are two different frames: toggling the TALENTS
-- TAB directly satisfies TalentLoadoutsEx's hook without ever calling
-- Show()/Hide() on the parent PlayerSpellsFrame, so ActionBars' hook never
-- fires and there is nothing of its state to disturb -- no resync required
-- because nothing is ever touched. (An earlier version of this file toggled
-- the parent and then resynced ActionBars afterward; toggling the right
-- frame in the first place is simpler and does not depend on ActionBars'
-- resync path staying compatible with a same-tick Show/Hide.)
--
-- A child's own :IsShown() is independent of whether its ancestors are
-- shown -- only :IsVisible() cares about the whole chain -- so this never
-- renders anything on screen: the parent PlayerSpellsFrame is never shown,
-- so the tab has nothing to be visible IN, even while it reports itself as
-- shown to TalentLoadoutsEx's hook.
local TALENT_PANEL_WARMUP_DELAY = 5 -- seconds after PLAYER_ENTERING_WORLD

-- Runs more than once per session on purpose: TalentLoadoutsEx's own
-- "currently applied" tracking (see ns.IsMacrotextSlotActive above) only
-- seems to re-settle for the NEW spec once the Talents tab has actually
-- toggled again after the swap -- a plain PLAYER_SPECIALIZATION_CHANGED
-- reaching TalentLoadoutsEx's own event handlers is not, in practice,
-- enough on its own. So this flashes again on every spec change, not just
-- once at login; pendingFlash (rather than a permanent "already done" flag)
-- is what lets a spec change that lands mid-combat retry once combat ends,
-- same as the very first login attempt would.
local pendingFlash = false
local function FlashTalentPanel()
    if InCombatLockdown() then
        pendingFlash = true
        return
    end
    pendingFlash = false

    if C_AddOns and C_AddOns.LoadAddOn and C_AddOns.IsAddOnLoaded
       and not C_AddOns.IsAddOnLoaded("Blizzard_PlayerSpells") then
        C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
    end

    local frame = _G.PlayerSpellsFrame
    local talentsFrame = frame and frame.TalentsFrame
    -- Already shown (the player has the Talents tab open themselves) --
    -- never steal that away with a hide of our own.
    if talentsFrame and not talentsFrame:IsShown() then
        talentsFrame:SetShown(true)
        talentsFrame:SetShown(false)
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= "TalentLoadoutsEx" then return end

    if event == "PLAYER_ENTERING_WORLD" then
        -- First flash of the session: give the rest of the suite (ActionBars
        -- included) time to finish its own startup first.
        C_Timer.After(TALENT_PANEL_WARMUP_DELAY, FlashTalentPanel)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- A spec swap, not a talent edit within the current spec -- flash
        -- again right away so TalentLoadoutsEx's own tracking settles onto
        -- the NEW spec's loadouts before the player next checks the pip.
        -- Everything is long past "still loading" by this point in a
        -- session, so no delay here.
        FlashTalentPanel()
    elseif event == "PLAYER_REGEN_ENABLED" and pendingFlash then
        -- Picks up whichever flash (login or a spec change) landed mid-combat.
        FlashTalentPanel()
    end

    -- A tick late on purpose: TalentLoadoutsEx's own list can still be
    -- settling (it debounces its rebuild by 0.1s -- see its RequestUpdate),
    -- and this addon's own profile may not exist yet on the very first
    -- ADDON_LOADED pass either -- FindOrCreateTalentLoadoutPalette just
    -- no-ops in that case and PLAYER_ENTERING_WORLD covers it a moment later.
    C_Timer.After(0.2, function() RefreshTalentLoadoutPalette(false) end)
end)

-- Manual refresh / sanity check without a UI reload, e.g. right after saving
-- a new loadout in TalentLoadoutsEx.
SLASH_EUIQUICKDRAWTALENTLOADOUTS1 = "/eui-tlx"
SlashCmdList["EUIQUICKDRAWTALENTLOADOUTS"] = function()
    RefreshTalentLoadoutPalette(true)
end
