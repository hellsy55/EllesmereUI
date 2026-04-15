-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_Skin.lua
--
-- Restyles Blizzard's ObjectiveTrackerFrame sub-trackers (headers, blocks,
-- progress bars, timer bars) via hooks only. Never SetScript on any tracker
-- frame; HookScript only. No frame-tree recursion.
--
-- Styling targets (match the legacy custom tracker exactly):
--   title color      = { r=1.00, g=0.91, b=0.47 }  gold
--   objective color  = { r=0.72, g=0.72, b=0.72 }  gray
--   completed color  = { r=0.25, g=1.00, b=0.35 }  green
--   section accent   = live EllesmereUI.ELLESMERE_GREEN
--   bar bg           = { r=0.15, g=0.15, b=0.15 } at 0.8 alpha
--   bar fill         = accent tint on Blizzard's default statusbar texture
--   timer fill       = { r=1.00, g=0.82, b=0.20 }
--   timer low fill   = { r=1.00, g=0.30, b=0.30 }
--   font             = EllesmereUI.GetFontPath("unitFrames")
--   shadow / outline = EllesmereUI.GetFontUseShadow / GetFontOutlineFlag
--   border           = PanelPP.CreateBorder 1px black, physical pixel perfect
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT

-- Color helpers. All four user-facing text colors come from DB so they
-- follow the Colors section in the options page.
local function GetTitleRGB()
    local c = EQT.DB()
    return c.titleR or 1.0, c.titleG or 0.910, c.titleB or 0.471
end
local function GetQuestRGB()
    local c = EQT.DB()
    return c.questR or 0.722, c.questG or 0.722, c.questB or 0.722
end
local function GetCompletedRGB()
    local c = EQT.DB()
    return c.completedR or 0.251, c.completedG or 1.0, c.completedB or 0.349
end
local function GetFocusRGB()
    local c = EQT.DB()
    return c.focusR or 0.871, c.focusG or 0.251, c.focusB or 1.0
end
local C_TIMER     = { r = 1.00, g = 0.82, b = 0.20 }
local C_TIMER_LOW = { r = 1.00, g = 0.30, b = 0.30 }
local C_BAR_BG    = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 }

local SUB_TRACKERS = {
    "ScenarioObjectiveTracker",
    "UIWidgetObjectiveTracker",
    "CampaignQuestObjectiveTracker",
    "QuestObjectiveTracker",
    "AdventureObjectiveTracker",
    "AchievementObjectiveTracker",
    "MonthlyActivitiesObjectiveTracker",
    "ProfessionsRecipeTracker",
    "BonusObjectiveTracker",
    "WorldQuestObjectiveTracker",
    "InitiativeTasksObjectiveTracker",
}

-- Shared font sizes -- read from DB so the options panel can tweak them.
-- Defaults are seeded in the loader's QT_DEFAULTS table.
local function GetTitleSize() return EQT.Cfg("titleFontSize")     or 13 end
local function GetObjSize()   return EQT.Cfg("objectiveFontSize") or 11 end

-------------------------------------------------------------------------------
-- External weak-keyed flag tables. Never write custom fields onto Blizzard-
-- owned tables: the tracker iterates its own data tables (e.g. tracker.blocks
-- keyed by blockID) with pairs(), and any stray key becomes a "fake entry"
-- that breaks their MarkBlocksUnused logic. All idempotency flags live here.
-------------------------------------------------------------------------------
local _hookedTrackers    = setmetatable({}, { __mode = "k" })
local _hookedBlocks      = setmetatable({}, { __mode = "k" })
local _skinnedBars       = setmetatable({}, { __mode = "k" })
local _skinnedTimerBars  = setmetatable({}, { __mode = "k" })
local _blockIcons        = setmetatable({}, { __mode = "k" })  -- block -> our icon texture
local _hookedPOIButtons  = setmetatable({}, { __mode = "k" })  -- poiButton -> true

-- External weak-keyed flag tables. Every "am I in a state?" bool / number
-- we used to write directly onto Blizzard-owned frames (block, tracker,
-- line, FontString, StatusBar, bar, etc.) lives here instead so Blizzard's
-- iteration of its own tables never sees our additions. This is the
-- canonical taint-avoidance pattern per CLAUDE.md.
local function _wk() return setmetatable({}, { __mode = "k" }) end
local F = {
    heightHooked         = _wk(),
    dungeonHeightHooked  = _wk(),
    ignoreHeight         = _wk(),
    ignoreDungeonHeight  = _wk(),
    ignoreColor          = _wk(),
    colorHooked          = _wk(),
    lastX                = _wk(),
    ignorePoint          = _wk(),
    shiftPending         = _wk(),
    shiftHooked          = _wk(),
    dungeonShifted       = _wk(),
    shiftApplied         = _wk(),
    fillHooked           = _wk(),
    underScenarioTracker = _wk(),
    ownerBlockResolved   = _wk(),
    blockShrunk          = _wk(),
    skinPending          = _wk(),
    ghost                = _wk(),  -- bar -> our standalone ghost Frame
}
local _delveTitleFS      = setmetatable({}, { __mode = "k" })  -- block -> innerTitleFS
EQT._getInnerTitleFS = function(block) return _delveTitleFS[block] end
local _delveFlagFrame    = setmetatable({}, { __mode = "k" })  -- block -> flag frame
local _delveLevelNumFS   = setmetatable({}, { __mode = "k" })  -- block -> level number FontString
EQT._getDelveLevelNumFS  = function(block) return _delveLevelNumFS[block] end
-- Hide any cached delve-flag regions (level number + flag frame) so they
-- don't linger on screen after leaving a delve. Blizzard's pool can keep
-- StageBlock children visible after the scenario ends because our re-
-- anchored FontString points at the block itself rather than the flag.
EQT._hideDelveLeftovers = function()
    for _, fs in pairs(_delveLevelNumFS) do
        if fs and fs.Hide then fs:Hide() end
    end
    for _, f in pairs(_delveFlagFrame) do
        if f and f.Hide then f:Hide() end
    end
end
local _delveInnerFrame   = setmetatable({}, { __mode = "k" })  -- block -> inner frame
local _poiHiddenParent  -- shared hidden container POI buttons get reparented to
local _blockFocus        = setmetatable({}, { __mode = "k" })  -- block -> focus texture
local _headerClickOverlays = setmetatable({}, { __mode = "k" })  -- header -> click overlay

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function GetAccent()
    local eg = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    if eg then return eg.r, eg.g, eg.b end
    return 0.047, 0.824, 0.624
end

local function GetFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("unitFrames") or "Fonts/FRIZQT__.TTF"
    end
    return "Fonts/FRIZQT__.TTF"
end

local function GetOutline()
    if EllesmereUI and EllesmereUI.GetFontOutlineFlag then
        return EllesmereUI.GetFontOutlineFlag() or ""
    end
    return ""
end

local function ApplyShadow(fs)
    if not fs then return end
    if EllesmereUI and EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow() then
        fs:SetShadowColor(0, 0, 0, 0.8)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- Registry of every FontString we've styled. Lets us re-template in bulk
-- when the user changes font path / outline / shadow settings.
local _eqtFontRegistry = setmetatable({}, { __mode = "k" })

-- Reapplies EUI font path with explicit size + outline + shadow.
-- If `size` is nil, preserves Blizzard's current size.
local function StyleFontStringSized(fs, size)
    if not fs or not fs.GetFont then return end
    if not size then
        local _, cur = fs:GetFont()
        size = cur or 12
    end
    local ok = pcall(fs.SetFont, fs, GetFont(), size, GetOutline())
    if not ok then fs:SetFont("Fonts/FRIZQT__.TTF", size, GetOutline()) end
    ApplyShadow(fs)
    _eqtFontRegistry[fs] = true
end

-- Convenience wrappers so every title / objective uses the shared sizes.
-- Scenario titles (delve / event banner titles) render 2px larger to
-- match their prominent visual role in the tracker.
local function StyleFontString(fs)     StyleFontStringSized(fs, nil)                end
local function StyleTitleFS(fs)        StyleFontStringSized(fs, GetTitleSize())     end
local function StyleScenarioTitleFS(fs) StyleFontStringSized(fs, GetTitleSize() + 1) end
local function StyleObjectiveFS(fs)    StyleFontStringSized(fs, GetObjSize())       end

-- Walk every FontString region on a frame (top-level only) and restyle it.
-- No recursion: child frames each go through their own skin call.
local function StyleAllFontStrings(frame)
    if not frame or not frame.GetRegions then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region and region:GetObjectType() == "FontString" then
            StyleFontString(region)
        end
    end
end

-- Bulk re-template everything we've touched. Called when user changes font
-- settings in options.
function EQT.RefreshFonts()
    for fs in pairs(_eqtFontRegistry) do
        if fs and fs.GetFont then
            local _, size = fs:GetFont()
            pcall(fs.SetFont, fs, GetFont(), size or 12, GetOutline())
            ApplyShadow(fs)
        end
    end
end

local function GetPP()
    return EllesmereUI and EllesmereUI.PanelPP
end

-- Physical-pixel-perfect 1px accent divider under each section header.
-- Parented to ObjectiveTrackerFrame (NOT the header) so collapse/expand
-- animations on the header don't drag our divider with them. Keyed by
-- header so we only create one per section (Quests, Professions, etc).
-- Follows the canonical border pattern: DisablePixelSnap + SetHeight via
-- PP.perfect / effectiveScale.
local _headerDividers = setmetatable({}, { __mode = "k" })
local function EnsureAccentDivider(header)
    if not header or not header.CreateTexture then return nil end
    local otf = _G.ObjectiveTrackerFrame
    if not otf or not otf.CreateTexture then return nil end

    -- Never draw a divider for the master "All Objectives" header or its
    -- menu bar -- those are hidden sections at the top of the tracker.
    if header == otf.HeaderMenu or header == otf.Header then return nil end

    -- Divider is visible only when the tracker itself is currently being
    -- rendered (Blizzard hides the tracker frame when it has no content).
    -- Signals, ORed:
    --   tracker has any block, OR
    --   tracker is flagged as having contents (hasContents), OR
    --   tracker was displayed on the last layout pass (wasDisplayedLastLayout).
    -- Any of those == the section is still active. All false == fully hidden.
    -- Collapse keeps hasContents/wasDisplayedLastLayout true, so collapsed
    -- trackers still show their divider.
    local owner = header:GetParent()
    local hasAnyBlock = false
    if owner and owner.usedBlocks then
        for _, byTemplate in pairs(owner.usedBlocks) do
            if type(byTemplate) == "table" then
                for _ in pairs(byTemplate) do
                    hasAnyBlock = true
                    break
                end
                if hasAnyBlock then break end
            end
        end
    end
    -- The divider belongs to a section that is actually rendered. Require
    -- the header itself to be shown right now AND the tracker to have some
    -- current content signal. `wasDisplayedLastLayout` alone isn't enough
    -- because Blizzard doesn't always clear it when a section empties.
    local headerShown = header.IsShown and header:IsShown()
    local trackerShown = owner and owner.IsShown and owner:IsShown()
    local hasContentSignal = hasAnyBlock or (owner and owner.hasContents)
    local active = headerShown and trackerShown and hasContentSignal
    if not active then
        local tex = _headerDividers[header]
        if tex then tex:Hide() end
        return nil
    end
    local tex = _headerDividers[header]
    if not tex then
        tex = otf:CreateTexture(nil, "OVERLAY")
        _headerDividers[header] = tex
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT",  header, "BOTTOMLEFT",  7, 0)
    tex:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -1, 0)
    local PP_CORE = EllesmereUI and EllesmereUI.PP
    local PP_SEC  = EllesmereUI and EllesmereUI.PanelPP
    if PP_SEC and PP_SEC.DisablePixelSnap then PP_SEC.DisablePixelSnap(tex) end
    local perfect = (PP_CORE and PP_CORE.perfect) or (PP_SEC and PP_SEC.mult) or 1
    local es = header.GetEffectiveScale and header:GetEffectiveScale() or 1
    local onePixel = (es and es > 0) and (perfect / es) or (PP_SEC and PP_SEC.mult) or 1
    tex:SetHeight(onePixel)
    local r, g, b = GetAccent()
    tex:SetColorTexture(r, g, b, 1)
    tex:Show()
    return tex
end

-------------------------------------------------------------------------------
-- Strip every Texture region on a frame except ones explicitly preserved.
-- Top-level only, never recurses. Leaves FontStrings alone.
-------------------------------------------------------------------------------
local function StripTextures(frame, keep)
    if not frame or not frame.GetRegions then return end
    keep = keep or {}
    -- IMPORTANT: hide via SetTexture("") only. SetTexture(nil) and
    -- SetAlpha(0) both taint Blizzard-owned textures. Tainted widget-pool
    -- textures cause arithmetic errors when the pool reuses them for
    -- tooltip/POI widgets later (Blizzard_UIWidgetTemplateTextWithState
    -- textHeight crashes).
    for _, region in ipairs({ frame:GetRegions() }) do
        if region and region:GetObjectType() == "Texture" and not keep[region]
           and region.SetTexture then
            region:SetTexture("")
        end
    end
end

-------------------------------------------------------------------------------
-- Header skin: accent color + EUI font. Strips every decorative texture
-- region from the header; keeps the minimize button (+/-) and Text intact.
-------------------------------------------------------------------------------
local function SkinHeader(header)
    if not header then return end
    if not EQT.Cfg("skinHeaders") then return end

    -- Named decorative regions we always want gone.
    -- Hide via SetTexture("") only (anti-taint pattern -- see StripTextures).
    for _, k in ipairs({
        "Background", "Line", "LineSheen", "LineGlow", "Divider",
        "Sheen", "Glow", "Stripe",
    }) do
        local r = header[k]
        if r and r.SetTexture then r:SetTexture("") end
    end

    -- Sweep anonymous Texture regions too. Preserve the minimize button's
    -- textures by skipping anything owned by header.MinimizeButton.
    local minBtn = header.MinimizeButton
    local keep = {}
    if minBtn and minBtn.GetRegions then
        for _, region in ipairs({ minBtn:GetRegions() }) do
            keep[region] = true
        end
        if minBtn.GetNormalTexture and minBtn:GetNormalTexture() then
            keep[minBtn:GetNormalTexture()] = true
        end
        if minBtn.GetPushedTexture and minBtn:GetPushedTexture() then
            keep[minBtn:GetPushedTexture()] = true
        end
        if minBtn.GetHighlightTexture and minBtn:GetHighlightTexture() then
            keep[minBtn:GetHighlightTexture()] = true
        end
    end
    StripTextures(header, keep)

    -- Accent-tint the +/- minimize button. Desaturate first so the base
    -- atlas's built-in tint doesn't multiply with our accent.
    if minBtn and EQT.Cfg("accentHeaders") then
        local r, g, b = GetAccent()
        local function tint(tex)
            if not tex then return end
            if tex.SetDesaturated then tex:SetDesaturated(true) end
            if tex.SetVertexColor then tex:SetVertexColor(r, g, b) end
        end
        tint(minBtn.GetNormalTexture    and minBtn:GetNormalTexture())
        tint(minBtn.GetPushedTexture    and minBtn:GetPushedTexture())
        tint(minBtn.GetHighlightTexture and minBtn:GetHighlightTexture())
        tint(minBtn.GetDisabledTexture  and minBtn:GetDisabledTexture())
        if minBtn.GetRegions then
            for _, rg in ipairs({ minBtn:GetRegions() }) do
                if rg:GetObjectType() == "Texture" then tint(rg) end
            end
        end
    end

    local text = header.Text
    if text then
        if EQT.Cfg("accentHeaders") then
            local r, g, b = GetAccent()
            text:SetTextColor(r, g, b)
        else
            text:SetTextColor(1, 1, 1)
        end
        StyleFontString(text)
    end

    -- Catch any other FontString regions on the header (subtitle, count text).
    StyleAllFontStrings(header)

    -- Accent-colored 1px divider beneath the header.
    EnsureAccentDivider(header)

    -- Click-anywhere-on-header overlay: forwards clicks to SetCollapsed so
    -- clicking the title text (not just the +/- button) toggles the
    -- section. The overlay is our own frame; we own its mouse state and
    -- never touch Blizzard's frames' mouse state. Stops short of the
    -- MinimizeButton so that button's native click still fires normally.
    if not _headerClickOverlays[header] then
        local overlay = CreateFrame("Button", nil, header)
        overlay:SetFrameLevel(header:GetFrameLevel() + 1)
        overlay:RegisterForClicks("LeftButtonUp")
        overlay:SetPoint("TOPLEFT",     header, "TOPLEFT",     0, 0)
        local minBtn = header.MinimizeButton
        if minBtn then
            overlay:SetPoint("BOTTOMRIGHT", minBtn, "BOTTOMLEFT", -2, 0)
        else
            overlay:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
        end
        overlay:SetScript("OnClick", function()
            -- Simulate a click on the MinimizeButton so Blizzard's full
            -- collapse cascade runs (header state + tracker layout pass).
            if header.MinimizeButton and header.MinimizeButton.Click then
                header.MinimizeButton:Click("LeftButton")
            elseif header.ToggleCollapsed then
                header:ToggleCollapsed()
            end
        end)
        _headerClickOverlays[header] = overlay
    end
end

-------------------------------------------------------------------------------
-- Block skin: color quest title gold, objectives gray, completed green.
-- Objective lines live on block.lines[*] keyed by text; tint each line's
-- FontString according to its completion state each refresh via a hook on
-- the block's GetLine / AddObjective path where available.
-------------------------------------------------------------------------------
local function StyleObjectiveLine(line)
    if not line or not line.Text then return end
    StyleObjectiveFS(line.Text)
    if line.Dash then StyleObjectiveFS(line.Dash) end
    if line.GetRegions then StyleAllFontStrings(line) end

    -- Blizzard sets line.Text color via line:SetState; our hook re-tints
    -- after their call. Completed lines expose a `state` field we read.
    local completed = line.state == "completed" or line.Dash and line.Dash:GetAlpha() == 0
    if completed then
        line.Text:SetTextColor(GetCompletedRGB())
    else
        line.Text:SetTextColor(GetQuestRGB())
    end
end

-------------------------------------------------------------------------------
-- Quest type icon system. Replaces Blizzard's per-block type icon with our
-- own atlas picks so the visuals match the rest of EUI.
-------------------------------------------------------------------------------
local QUEST_ICON_ATLAS = {
    normal    = nil,
    campaign  = "Crosshair_campaignquest_32",
    legendary = "Crosshair_legendaryquest_32",
    important = "Crosshair_important_48",
    recurring = "Crosshair_Recurring_48",
    daily     = "Crosshair_Recurring_48",
    weekly    = "Crosshair_Recurring_48",
    meta      = "Crosshair_Wrapper_48",
}
local QUEST_TURNIN_ATLAS = {
    campaign  = "Crosshair_campaignquestturnin_32",
    legendary = "Crosshair_legendaryquestturnin_32",
    important = "Crosshair_importantturnin_48",
    recurring = "Crosshair_Recurringturnin_48",
    daily     = "Crosshair_Recurringturnin_48",
    weekly    = "Crosshair_Recurringturnin_48",
    meta      = "Crosshair_Wrapperturnin_48",
}
local QUEST_ICON_SIZE_OVERRIDE = {
    recurring = 18, daily = 18, weekly = 18, important = 22,
}
local QUEST_ICON_SIZE = 16

-- Cache of questID -> { key = "...", done = bool }. Computed ONCE per quest
-- the first time we see it, then refreshed only when the quest log itself
-- signals change (via QUEST_LOG_UPDATE / QUEST_REMOVED handled below).
-- Never called inline on the live skin path so secure quest-log APIs
-- can't leak taint into MoneyFrame / reward rendering on quest turn-in.
local _classifyCache = {}

local function _computeClassification(questID)
    if not questID or not C_QuestLog then return nil end
    local logIdx = C_QuestLog.GetLogIndexForQuestID
        and C_QuestLog.GetLogIndexForQuestID(questID)
    local info = logIdx and C_QuestLog.GetInfo and C_QuestLog.GetInfo(logIdx)
    local cls  = info and info.questClassification
    local freq = (info and info.frequency) or 0
    local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) or false

    local key = "normal"
    if C_CampaignInfo and C_CampaignInfo.IsCampaignQuest
       and C_CampaignInfo.IsCampaignQuest(questID) then
        key = "campaign"
    elseif cls and Enum and Enum.QuestClassification then
        local QC = Enum.QuestClassification
        if     cls == QC.Important then key = "important"
        elseif cls == QC.Legendary then key = "legendary"
        elseif cls == QC.Campaign  then key = "campaign"
        elseif cls == QC.Recurring then key = "recurring"
        end
    end
    if key == "normal" then
        if     freq == 1 then key = "daily"
        elseif freq == 2 then key = "weekly"
        end
    end
    return { key = key, done = done }
end

local function ClassifyQuest(questID)
    if not questID then return nil, false end
    local entry = _classifyCache[questID]
    if not entry then return nil, false end
    local key = entry.key
    if entry.done and QUEST_TURNIN_ATLAS[key] then
        return QUEST_TURNIN_ATLAS[key], key
    end
    return QUEST_ICON_ATLAS[key], key
end

-- Refresh the classify cache outside any skin / tracker-Update chain.
-- Only driven by quest-log events so secure-API reads never happen inside
-- the debounced tracker Update or block hover paths that surround
-- MoneyFrame / reward rendering.
local function _refreshClassifyCache()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
    local seen = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
        local qID = info and info.questID
        if qID then
            seen[qID] = true
            _classifyCache[qID] = _computeClassification(qID)
        end
    end
    -- Drop stale entries for quests no longer in the log (turned in, etc.)
    for qID in pairs(_classifyCache) do
        if not seen[qID] then _classifyCache[qID] = nil end
    end
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("QUEST_LOG_UPDATE")
    f:RegisterEvent("QUEST_ACCEPTED")
    f:RegisterEvent("QUEST_REMOVED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    local _pending = false
    f:SetScript("OnEvent", function()
        -- Debounced: quest events can burst-fire. Refresh once per 250ms.
        if _pending then return end
        _pending = true
        C_Timer.After(0.25, function()
            _pending = false
            _refreshClassifyCache()
        end)
    end)
end

-- Hides Blizzard's built-in quest type icon(s) on a block (without
-- recursing into the block's children) and stamps ours on top.

local function ApplyQuestTypeIcon(block)
    if not block then return end

    -- Blizzard's POI button (block.poiButton) is the left-side circular
    -- icon. The drain-textures approach loses every time Blizzard
    -- re-applies textures via SetNormalAtlas. Reparent to a hidden
    -- container is the only bulletproof path. Non-secure frame, we
    -- explicitly own its suppression -- standard CLAUDE.md pattern.
    if block.poiButton then
        local pb = block.poiButton
        if not _poiHiddenParent then
            _poiHiddenParent = CreateFrame("Frame", nil, UIParent)
            _poiHiddenParent:Hide()
        end
        -- Reparent every single skin pass (not just once). Blizzard's
        -- block pool re-parents poiButton back onto the block during
        -- acquisition / animation entry, so a one-time reparent gets
        -- silently undone on world quest entry / block recycle.
        if pb:GetParent() ~= _poiHiddenParent then
            pb:SetParent(_poiHiddenParent)
        end
        -- Hook SetParent so if Blizzard re-parents to block mid-frame,
        -- we snap it back immediately.
        if not _hookedPOIButtons[pb] then
            _hookedPOIButtons[pb] = true
            hooksecurefunc(pb, "SetParent", function(self, newParent)
                if newParent ~= _poiHiddenParent then
                    self:SetParent(_poiHiddenParent)
                end
            end)
        end
    end

    -- Hide Blizzard's quest-type icon by scanning for atlas-backed textures
    -- whose atlas name matches a known quest-icon prefix. Top-level region
    -- sweep + a one-level pass into child Button frames (the POI button).
    local function looksLikeQuestIconAtlas(a)
        if type(a) ~= "string" then return false end
        local l = a:lower()
        return l:find("quest", 1, true)
            or l:find("poi-", 1, true)
            or l:find("crosshair_", 1, true)
            or l:find("campaign", 1, true)
            or l:find("legendary", 1, true)
            or l:find("portrait", 1, true)
    end

    local function killAtlasTex(tex)
        if not tex then return end
        local atlas = tex.GetAtlas and tex:GetAtlas()
        if looksLikeQuestIconAtlas(atlas) then
            -- SetTexture("") only -- anti-taint pattern.
            if tex.SetTexture then tex:SetTexture("") end
        end
    end

    if block.GetRegions then
        for _, rg in ipairs({ block:GetRegions() }) do
            if rg.GetObjectType and rg:GetObjectType() == "Texture" then
                killAtlasTex(rg)
            end
        end
    end
    if block.GetChildren then
        for _, child in ipairs({ block:GetChildren() }) do
            if child.GetNormalTexture    then killAtlasTex(child:GetNormalTexture())    end
            if child.GetPushedTexture    then killAtlasTex(child:GetPushedTexture())    end
            if child.GetHighlightTexture then killAtlasTex(child:GetHighlightTexture()) end
            if child.GetRegions then
                for _, rg in ipairs({ child:GetRegions() }) do
                    if rg.GetObjectType and rg:GetObjectType() == "Texture" then
                        killAtlasTex(rg)
                    end
                end
            end
        end
    end

    -- Hide Blizzard's POI / portrait / legend ring textures. Top-level only.
    for _, k in ipairs({
        "QuestPortrait", "QuestTypeIcon", "poiIcon", "questIcon",
        "IconRing", "Icon", "poiTexture", "TagTexture",
    }) do
        local r = block[k]
        -- SetTexture("") only -- anti-taint pattern.
        if r and r.SetTexture then r:SetTexture("") end
    end

    local qID = block.id
    if type(qID) ~= "number" then
        if _blockIcons[block] then _blockIcons[block]:Hide() end
        return
    end

    -- Suppress our custom icon when Blizzard's ItemButton or
    -- groupFinderButton is already visible on this block. Probe the block
    -- fields directly (the icon you SEE is Blizzard's, and our overlay
    -- texture is mouse-pass-through, so it eats the visual click target).
    local hasItem = (block.ItemButton and block.ItemButton.IsShown
                     and block.ItemButton:IsShown())
                 or (block.itemButton and block.itemButton.IsShown
                     and block.itemButton:IsShown())
    local hasLFG  = (block.groupFinderButton and block.groupFinderButton.IsShown
                     and block.groupFinderButton:IsShown())
                 or (block.GroupFinderButton and block.GroupFinderButton.IsShown
                     and block.GroupFinderButton:IsShown())
    if hasItem or hasLFG then
        if _blockIcons[block] then _blockIcons[block]:Hide() end
        return
    end

    local atlas, key = ClassifyQuest(qID)
    if not atlas then
        if _blockIcons[block] then _blockIcons[block]:Hide() end
        return
    end

    local ico = _blockIcons[block]
    if not ico then
        ico = block:CreateTexture(nil, "OVERLAY")
        _blockIcons[block] = ico
    end
    local size = QUEST_ICON_SIZE_OVERRIDE[key] or QUEST_ICON_SIZE
    ico:SetSize(size, size)
    ico:SetAtlas(atlas)
    ico:ClearAllPoints()
    ico:SetPoint("TOPRIGHT", block, "TOPRIGHT", -2, 3)
    ico:SetAlpha(1)
    ico:Show()
end

-------------------------------------------------------------------------------
-- Focus highlight: color the super-tracked quest's block with the user's
-- focus color (default purple). One texture per block, cached in _blockFocus.
-------------------------------------------------------------------------------
-- Find the quest title FontString on a block. It's the first FontString
-- region in Blizzard's layout (confirmed via dump). Cached per-block so
-- hot paths (hover reassert) don't re-walk regions on every mouse event.
local _blockTitleFSCache = setmetatable({}, { __mode = "k" })
local function GetBlockTitleFS(block)
    if not block then return nil end
    local cached = _blockTitleFSCache[block]
    if cached then return cached end
    if not block.GetRegions then return nil end
    for _, rg in ipairs({ block:GetRegions() }) do
        if rg.GetObjectType and rg:GetObjectType() == "FontString" then
            _blockTitleFSCache[block] = rg
            return rg
        end
    end
    return nil
end

-- Super-tracked quest ID cache. Updated only on SUPER_TRACKING_CHANGED so
-- hover handlers don't hit C_SuperTrack.GetSuperTrackedQuestID on every
-- mouse enter/leave.
local _superTrackedID = nil
local function GetSuperTrackedIDCached() return _superTrackedID end
do
    local sf = CreateFrame("Frame")
    sf:RegisterEvent("SUPER_TRACKING_CHANGED")
    sf:RegisterEvent("PLAYER_ENTERING_WORLD")
    sf:SetScript("OnEvent", function()
        if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
            local id = C_SuperTrack.GetSuperTrackedQuestID()
            _superTrackedID = (id and id ~= 0) and id or nil
        end
    end)
end

function ApplyFocusHighlight(block)  -- global to file (called from SkinBlock)
    if not block then return end
    local fs = GetBlockTitleFS(block)
    if not fs then return end
    -- Force the shared title size + EUI font/outline/shadow.
    StyleTitleFS(fs)
    -- Constrain quest title to a fixed pixel width with no word wrap.
    -- Blizzard anchors the title FS with TOPLEFT + TOPRIGHT (full block
    -- width); SetWidth alone is a no-op while both anchors are present.
    -- Strip the right anchor and re-apply just the left so SetWidth wins.
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
    if fs.GetNumPoints and fs:GetNumPoints() > 0 then
        local point, relTo, relPoint, x, y = fs:GetPoint(1)
        if point then
            fs:ClearAllPoints()
            fs:SetPoint(point, relTo, relPoint, x or 0, y or 0)
        end
    end
    if fs.SetWidth then fs:SetWidth(220) end
    local qID     = (type(block.id) == "number") and block.id or nil
    local isFocus = qID and (qID == GetSuperTrackedIDCached())
    local isDone  = qID and C_QuestLog and C_QuestLog.IsComplete
                    and C_QuestLog.IsComplete(qID)
    local r, g, b
    if isFocus then
        r, g, b = GetFocusRGB()
    elseif isDone then
        r, g, b = GetCompletedRGB()
    else
        r, g, b = GetTitleRGB()
    end
    fs:SetTextColor(r, g, b)
end

-- Hook block line-add APIs once per block instance. Catches every line
-- Blizzard creates or recycles without walking children.
local function HookBlockLineMethods(block)
    if _hookedBlocks[block] then return end
    _hookedBlocks[block] = true

    -- Blizzard changes the title text color on mouse enter (darkens it
    -- as hover feedback). Reassert our color from a post-hook so whatever
    -- gold/focus color we chose is what the player sees.
    local function reassertTitle()
        ApplyFocusHighlight(block)
    end
    if block.HookScript then
        block:HookScript("OnEnter", reassertTitle)
        block:HookScript("OnLeave", reassertTitle)
    end
    -- The HeaderButton (if present) often owns the hover script directly.
    if block.HeaderButton and block.HeaderButton.HookScript then
        block.HeaderButton:HookScript("OnEnter", reassertTitle)
        block.HeaderButton:HookScript("OnLeave", reassertTitle)
    end

    -- Left-click on a quest block also super-tracks it (in addition to
    -- Blizzard's default click behavior). HookScript preserves the
    -- default handler and just adds our side-effect.
    local function superTrackOnClick(self, button)
        if button ~= "LeftButton" then return end
        local qID = self.id
        if type(qID) ~= "number" then return end
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            C_SuperTrack.SetSuperTrackedQuestID(qID)
        end
    end
    -- Only hook the HeaderButton (title-text area), NOT the whole block.
    -- Hooking block:OnMouseUp eats clicks meant for the quest item button
    -- and LFG eyeball that sit inside the block's hit region, breaking
    -- the user's ability to actually use quest items.
    if block.HeaderButton and block.HeaderButton.HookScript then
        block.HeaderButton:HookScript("OnClick", function(self, button)
            superTrackOnClick(block, button)
        end)
    end

    -- AddObjective(block, objectiveKey, ...) pools a line and assigns it.
    -- After Blizzard runs, retrieve the line via GetExistingLine and style.
    if block.AddObjective and block.GetExistingLine then
        hooksecurefunc(block, "AddObjective", function(self, objectiveKey)
            local line = self:GetExistingLine(objectiveKey)
            if line then StyleObjectiveLine(line) end
        end)
    end

    -- SetStringText(block, fontString, text, ...) is Blizzard's wrapper
    -- for writing text into an arbitrary FontString owned by the block.
    if block.SetStringText then
        hooksecurefunc(block, "SetStringText", function(_, fontString)
            if fontString and fontString.GetObjectType
               and fontString:GetObjectType() == "FontString" then
                StyleFontString(fontString)
            end
        end)
    end
end

local _dumpedTemplates = {}
local function SkinBlock(block)
    if not block then return end

    -- Bail out completely for ANY ScenarioObjectiveTracker block when the
    -- player isn't in a delve or a dungeon (Prey / Abundance / Assault /
    -- outdoor scenario events). Their child frames include Blizzard widget
    -- visualizers (TextWithState etc.) pooled and reused for AreaPOI
    -- tooltip widgets -- ANY method call on those FontStrings / Textures
    -- / Frames taints the pool, then later when GameTooltip processes a
    -- POI widget set, arithmetic on textHeight fails. Leaving these
    -- blocks completely unstyled (Blizzard default) is the only safe
    -- option. The section HEADER ("Stormarion Assault" etc.) is skinned
    -- via SkinHeader on a separate path, so it still gets our accent.
    local sot = _G.ScenarioObjectiveTracker
    local underScenarioTracker = false
    if sot and block.parentModule == sot then
        underScenarioTracker = true
    elseif sot then
        local f, depth = block:GetParent(), 0
        while f and depth < 6 do
            if f == sot then underScenarioTracker = true; break end
            f = f.GetParent and f:GetParent()
            depth = depth + 1
        end
    end
    -- Bail for ALL ScenarioObjectiveTracker blocks (delves / dungeons /
    -- scenarios / outdoor events). Blizzard renders the entire scenario
    -- section using its own widget visualizers; those frames are pooled
    -- and reused for AreaPOI tooltip widgets and any mutation we apply
    -- taints them. Only the section header is skinned via SkinHeader.
    if underScenarioTracker then return end

    HookBlockLineMethods(block)

    -- Raise ItemButton / GroupFinderButton frame levels above the block on
    -- EVERY skin pass. Blizzard pools the block + Init/Reset paths can
    -- lower the level back to the block's, after which clicks fall through
    -- to the block instead of the icon button. Re-applying every pass is
    -- cheap and guarantees correct hit-testing.
    local bl = block.GetFrameLevel and block:GetFrameLevel() or 0
    if block.ItemButton and block.ItemButton.SetFrameLevel then
        block.ItemButton:SetFrameLevel(bl + 5)
    end
    if block.GroupFinderButton and block.GroupFinderButton.SetFrameLevel then
        block.GroupFinderButton:SetFrameLevel(bl + 5)
    end

    -- Strip decorative block textures (dashed backgrounds, hover glow,
    -- scenario banners, etc). FontStrings are untouched by StripTextures.
    for _, k in ipairs({
        "Background", "HeaderBackground", "Stripe", "Sheen", "Glow",
        "Highlight", "ShineTop", "ShineBottom",
    }) do
        local r = block[k]
        -- SetTexture("") only -- anti-taint pattern.
        if r and r.SetTexture then r:SetTexture("") end
    end
    -- Preserve our own icon (if already stamped on a prior refresh).
    local _keep = {}
    if _blockIcons[block] then _keep[_blockIcons[block]] = true end
    StripTextures(block, _keep)

    -- Style every FontString region on the block (quest title, count).
    -- Tint the first region -- that's the title in Blizzard's layout.
    -- Final color is set by ApplyFocusHighlight below (title or focus).
    StyleAllFontStrings(block)

    -- Item button (quest item) count FontString if present.
    if block.itemButton and block.itemButton.Count then
        StyleFontString(block.itemButton.Count)
    end

    -- Replace Blizzard's quest-type icon with ours, based on the quest's
    -- classification / frequency / turn-in state.
    ApplyQuestTypeIcon(block)

    -- Focus highlight for super-tracked quest.
    ApplyFocusHighlight(block)

    -- Strip + style direct children. Scenario StageBlock holds all its
    -- visual content on a single child Frame (Act title / objectives /
    -- timer bar), and we'd otherwise leave all its textures and
    -- FontStrings untouched. Read-only walk on child types; texture
    -- ops only, no mouse state changes.
    -- Atlas patterns we consider "ornamental" and safe to strip.
    local function isOrnamentalAtlas(atlas)
        if type(atlas) ~= "string" then return false end
        local l = atlas:lower()
        return l:find("scenario", 1, true)
            or l:find("evergreen", 1, true)
            or l:find("toast", 1, true)
            or l:find("filigree", 1, true)
            or l:find("parchment", 1, true)
            or l:find("delves-", 1, true)
            or l:find("bountiful", 1, true)
            or l:find("shimmer", 1, true)
            or l:find("sparkle", 1, true)
            or l:find("trackerheader", 1, true)
            or l:find("jailerstower", 1, true)
    end

    -- Track:
    --   levelFlagFrame  - the "flag" frame that holds the delve level number
    --   innerTitleFS    - the visible delve title FontString
    --   delveInnerFrame - the frame hosting delves-scenario-frame texture
    --                     (we shrink its height to close the dead space)
    -- Prime from cache so subsequent skin passes (after we've stripped the
    -- identifying atlases) still find these references.
    local levelFlagFrame  = _delveFlagFrame[block]
    local innerTitleFS    = _delveTitleFS[block]
    local delveInnerFrame = _delveInnerFrame[block]
    local function processFrame(frame, depth)
        if not frame or depth > 3 or not frame.GetChildren then return end
        for _, child in ipairs({ frame:GetChildren() }) do
            if child.GetObjectType then
                local ok, otype = pcall(child.GetObjectType, child)
                if ok then
                    if otype == "StatusBar" and EQT._SkinWidgetBar then
                        EQT._SkinWidgetBar(child)
                    elseif otype == "Frame" or otype == "Button" then
                        local isLevelFlag = false
                        local hasDelvesFrame = false
                        if child.GetRegions then
                            for _, rg in ipairs({ child:GetRegions() }) do
                                local ot = rg.GetObjectType and rg:GetObjectType()
                                if ot == "Texture" then
                                    local atlas = rg.GetAtlas and rg:GetAtlas()
                                    if type(atlas) == "string" then
                                        local la = atlas:lower()
                                        if la:find("flag", 1, true) then
                                            isLevelFlag = true
                                        end
                                        if la:find("delves-scenario-frame", 1, true) then
                                            hasDelvesFrame = true
                                        end
                                    end
                                    if isOrnamentalAtlas(atlas) and not rg._eqtKeep then
                                        -- SetTexture("") only -- anti-taint
                                        -- pattern. Leaving the atlas in place
                                        -- is fine; "" texture renders nothing.
                                        rg:SetTexture("")
                                    end
                                elseif ot == "FontString" then
                                    StyleObjectiveFS(rg)
                                end
                            end
                            if hasDelvesFrame then
                                delveInnerFrame = child
                                _delveInnerFrame[block] = child
                                for _, rg in ipairs({ child:GetRegions() }) do
                                    if rg.GetObjectType
                                       and rg:GetObjectType() == "FontString" then
                                        innerTitleFS = rg
                                        _delveTitleFS[block] = rg
                                        break
                                    end
                                end
                            end
                        end
                        if isLevelFlag then
                            levelFlagFrame = child
                            _delveFlagFrame[block] = child
                        end
                        processFrame(child, depth + 1)
                    end
                end
            end
        end
    end
    processFrame(block, 0)

    -- Force title to scenario-title size + color, and nudge 4px to the left.
    -- Blizzard re-anchors this FontString on objective updates / stage
    -- transitions. Hook SetPoint and only shift if the current X doesn't
    -- already match the value we last applied -- that way Blizzard
    -- re-applying our already-shifted X doesn't re-shift again.
    if innerTitleFS then
        StyleScenarioTitleFS(innerTitleFS)
        local function applyColor()
            if F.ignoreColor[innerTitleFS] then return end
            local r, g, b = GetTitleRGB()
            local cr, cg, cb = innerTitleFS:GetTextColor()
            if cr == r and cg == g and cb == b then return end
            F.ignoreColor[innerTitleFS] = true
            innerTitleFS:SetTextColor(r, g, b)
            F.ignoreColor[innerTitleFS] = nil
        end
        applyColor()
        if not F.colorHooked[innerTitleFS] then
            F.colorHooked[innerTitleFS] = true
            hooksecurefunc(innerTitleFS, "SetTextColor", applyColor)
        end
        local function applyShift()
            if F.ignorePoint[innerTitleFS] then return end
            local point, relTo, relPoint, x, y = innerTitleFS:GetPoint(1)
            if not point then return end
            if F.lastX[innerTitleFS] and x == F.lastX[innerTitleFS] then return end
            local shiftedX = (x or 0) - 16
            F.lastX[innerTitleFS] = shiftedX
            F.ignorePoint[innerTitleFS] = true
            innerTitleFS:ClearAllPoints()
            innerTitleFS:SetPoint(point, relTo, relPoint, shiftedX, y or 0)
            F.ignorePoint[innerTitleFS] = nil
        end
        local function queueShift()
            if F.shiftPending[innerTitleFS] then return end
            F.shiftPending[innerTitleFS] = true
            C_Timer.After(0, function()
                F.shiftPending[innerTitleFS] = nil
                applyShift()
            end)
        end
        applyShift()
        if not F.shiftHooked[innerTitleFS] then
            F.shiftHooked[innerTitleFS] = true
            hooksecurefunc(innerTitleFS, "SetPoint", queueShift)
        end
    end

    -- Pull the level number FontString out of the flag frame and anchor
    -- it directly so its baseline lines up with the title's baseline.
    if levelFlagFrame then
        local numFS = _delveLevelNumFS[block]
        if not numFS and levelFlagFrame.GetRegions then
            for _, rg in ipairs({ levelFlagFrame:GetRegions() }) do
                if rg.GetObjectType and rg:GetObjectType() == "FontString" then
                    numFS = rg
                    _delveLevelNumFS[block] = rg
                    break
                end
            end
        end
        if numFS and innerTitleFS then
            local font, _, flags = numFS:GetFont()
            numFS:SetFont(font, 17, flags or "")
            numFS:SetTextColor(GetAccent())
            numFS:ClearAllPoints()
            numFS:SetPoint("BOTTOMRIGHT", block, "RIGHT", -4, 0)
            numFS:SetPoint("BOTTOM",      innerTitleFS, "BOTTOM", 0, 3)
            numFS:Show()
            if levelFlagFrame.Show then levelFlagFrame:Show() end
        end
    end

    -- Close the dead space: shrink the delve inner frame AND force the
    -- owning StageBlock itself to a compact height. Blizzard's layout
    -- stacks ObjectivesBlock based on StageBlock's height -- if we only
    -- shrink the inner frame, the block still reserves the full banner
    -- space. hooksecurefunc on SetHeight catches Blizzard's layout pass
    -- and immediately overrides with our value. Reentry-guarded to
    -- prevent recursion on our own SetHeight calls.
    if delveInnerFrame then
        if delveInnerFrame.SetHeight then delveInnerFrame:SetHeight(22) end
        if block.SetHeight and not F.heightHooked[block] then
            F.heightHooked[block] = true
            hooksecurefunc(block, "SetHeight", function(self)
                if F.ignoreHeight[self] then return end
                F.ignoreHeight[self] = true
                self:SetHeight(26)
                F.ignoreHeight[self] = nil
            end)
            block:SetHeight(26)
        end
    else
        -- Non-delve StageBlock. Covers 5-player dungeons AND outdoor /
        -- scenario-style events (Abundance, public events, etc.) -- every
        -- context EXCEPT delves (handled above) reserves the same ~80px
        -- banner that we want to reclaim. The hook is installed once per
        -- block and gated only on "not a delve right now" at fire time so
        -- zoning in/out after login still behaves correctly without a
        -- reload. Isolated from the delve branch via its own flag.
        local bp = block:GetParent()
        if bp and bp.StageBlock == block then
            if block.SetHeight and not F.dungeonHeightHooked[block] then
                F.dungeonHeightHooked[block] = true
                local function inDelve()
                    return C_PartyInfo and C_PartyInfo.IsDelveInProgress
                        and C_PartyInfo.IsDelveInProgress()
                end
                hooksecurefunc(block, "SetHeight", function(self)
                    if F.ignoreDungeonHeight[self] then return end
                    if inDelve() then return end
                    F.ignoreDungeonHeight[self] = true
                    self:SetHeight(16)
                    F.ignoreDungeonHeight[self] = nil
                end)
                if not inDelve() then block:SetHeight(16) end
            end
            -- Shift the dungeon stage title up 20px. Find the first
            -- FontString region on the block (or within its child frames)
            -- and nudge its Y offset. Reentry-guarded so Blizzard's own
            -- SetPoint calls re-apply our offset, not double-nudge.
            local titleFS
            if block.GetRegions then
                for _, rg in ipairs({ block:GetRegions() }) do
                    if rg.GetObjectType and rg:GetObjectType() == "FontString" then
                        titleFS = rg
                        break
                    end
                end
            end
            if not titleFS and block.GetChildren then
                for _, c in ipairs({ block:GetChildren() }) do
                    if c.GetRegions then
                        for _, rg in ipairs({ c:GetRegions() }) do
                            if rg.GetObjectType and rg:GetObjectType() == "FontString" then
                                titleFS = rg
                                break
                            end
                        end
                    end
                    if titleFS then break end
                end
            end
            if titleFS and not F.dungeonShifted[titleFS] then
                F.dungeonShifted[titleFS] = true
                local function applyShift()
                    if F.ignorePoint[titleFS] then return end
                    if C_PartyInfo and C_PartyInfo.IsDelveInProgress
                       and C_PartyInfo.IsDelveInProgress() then
                        return
                    end
                    local n = titleFS:GetNumPoints() or 0
                    if n == 0 then return end
                    if F.shiftApplied[titleFS] then return end
                    local points = {}
                    for i = 1, n do
                        local point, relTo, relPoint, x, y = titleFS:GetPoint(i)
                        points[i] = { point, relTo, relPoint, x or 0, (y or 0) + 20 }
                    end
                    F.shiftApplied[titleFS] = true
                    F.ignorePoint[titleFS] = true
                    titleFS:ClearAllPoints()
                    for _, pt in ipairs(points) do
                        titleFS:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
                    end
                    F.ignorePoint[titleFS] = nil
                end
                applyShift()
                hooksecurefunc(titleFS, "SetPoint", function()
                    if F.ignorePoint[titleFS] then return end
                    F.shiftApplied[titleFS] = nil
                    if F.shiftPending[titleFS] then return end
                    F.shiftPending[titleFS] = true
                    C_Timer.After(0, function()
                        F.shiftPending[titleFS] = nil
                        applyShift()
                    end)
                end)
            end
        end
    end

    -- Render our own affix icons inline after the title, hiding Blizzard's.
    if innerTitleFS and EQT.UpdateDelveAffixIcons then
        EQT.UpdateDelveAffixIcons(block, innerTitleFS)
    end
end

-------------------------------------------------------------------------------
-- Progress bar ghost: instead of fighting Blizzard's textures / animations /
-- Icon / Label on every repaint, we hide the native bar outright and render
-- our own standalone frame next to it. The native bar stays in Blizzard's
-- layout (so line height / anchor math still works), but its alpha is 0 so
-- nothing it owns is ever visible. Our ghost is parented to the native
-- bar's parent and pinned to the bar's rect, with a live value hook.
-------------------------------------------------------------------------------
local _skinnedWidgetBars = setmetatable({}, { __mode = "k" })
local function CreateGhostBar(bar)
    if not bar then return end
    if not EQT.Cfg("skinProgressBars") then return end

    -- Bail if this bar belongs to ScenarioObjectiveTracker. Same widget-
    -- pool taint rationale as SkinBlock -- delves / dungeons / scenarios
    -- all use Blizzard's defaults now.
    do
        local sot = _G.ScenarioObjectiveTracker
        if sot then
            local f, depth = bar:GetParent(), 0
            while f and depth < 8 do
                if f == sot then return end
                f = f.GetParent and f:GetParent()
                depth = depth + 1
            end
        end
    end

    local valueBar = bar
    if bar.Bar and bar.Bar.GetValue then valueBar = bar.Bar end

    -- Hide the native bar subtree. SetAlpha(0) inherits to every
    -- descendant (Icon, Label, BarGlow, animations, everything), so we
    -- never have to strip textures or block anim groups again.
    bar:SetAlpha(0)
    if bar.EnableMouse then bar:EnableMouse(false) end

    -- Create the ghost once. Parented to the native bar's parent so our
    -- alpha stays at 1 regardless of what Blizzard does to the native bar.
    if not F.ghost[bar] then
        local ghost = CreateFrame("Frame", nil, bar:GetParent() or bar)
        ghost:SetFrameLevel((bar:GetFrameLevel() or 0) + 1)
        -- Explicitly disable mouse so the ghost (which extends past the
        -- bar's natural rect to give us the wider visual) doesn't eat
        -- clicks intended for the quest item button or LFG eyeball that
        -- sit in the same horizontal band.
        ghost:EnableMouse(false)
        -- SetPropagateMouseMotion/Clicks are protected (combat-locked).
        -- EnableMouse(false) already makes the frame transparent to mouse
        -- hit testing, so the propagate calls are belt-and-suspenders.
        -- Skip them in combat to avoid the ADDON_ACTION_BLOCKED warning
        -- when a new ghost bar is created mid-fight (rare but possible).
        if not InCombatLockdown() then
            if ghost.SetPropagateMouseMotion then ghost:SetPropagateMouseMotion(true) end
            if ghost.SetPropagateMouseClicks then ghost:SetPropagateMouseClicks(true) end
        end
        local bg = ghost:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C_BAR_BG.r, C_BAR_BG.g, C_BAR_BG.b, C_BAR_BG.a)
        ghost._bg = bg
        local fill = ghost:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT",    ghost, "TOPLEFT",    0, 0)
        fill:SetPoint("BOTTOMLEFT", ghost, "BOTTOMLEFT", 0, 0)
        ghost._fill = fill
        local PP = GetPP()
        if PP and PP.CreateBorder then
            PP.CreateBorder(ghost, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end
        F.ghost[bar] = ghost
    end
    local ghost = F.ghost[bar]

    -- Re-parent the ghost if Blizzard moved the native bar to a new parent
    -- (pool re-use on zone / track change).
    local desiredParent = bar:GetParent()
    if desiredParent and ghost:GetParent() ~= desiredParent then
        ghost:SetParent(desiredParent)
    end

    do
        local r, g, b = GetAccent()
        ghost._fill:SetColorTexture(r, g, b, 0.9)
    end

    -- Pin the ghost to the native bar's rect (the native bar is alpha 0
    -- but still in Blizzard's layout under the last objective line). Inset
    -- 20px from the left to clear the objective bullet / indent. Deferred
    -- one frame so Blizzard's post-Show re-parent lands before we anchor.
    -- Cache whether this bar lives under ScenarioObjectiveTracker so the
    -- reanchor fast-path doesn't walk parents on every call.
    local function isUnderScenarioTracker()
        local f = bar
        for _ = 1, 10 do
            if not f then return false end
            if f == _G.ScenarioObjectiveTracker then return true end
            f = f.GetParent and f:GetParent()
        end
        return false
    end
    F.underScenarioTracker[bar] = isUnderScenarioTracker()

    local function reanchor()
        local p = bar:GetParent()
        if not p then return end
        if ghost:GetParent() ~= p then ghost:SetParent(p) end
        -- Delve progress bars need a +6 / -5 nudge so they sit clear of the
        -- delve scenario title/flag. Detect via C_PartyInfo.IsDelveInProgress.
        local dx, dy = 0, 0
        local rightPad = 48
        local isDelve = C_PartyInfo and C_PartyInfo.IsDelveInProgress
                        and C_PartyInfo.IsDelveInProgress()
        if isDelve then
            dx, dy = 6, -5
        elseif F.underScenarioTracker[bar] then
            -- Non-delve scenario bars (Abundance / outdoor events / dungeon
            -- scenario steps): shrink the ghost width by 30px so it fits
            -- the narrower banner these contexts use. 48 - 30 = 18.
            rightPad = 18
        end
        ghost:ClearAllPoints()
        ghost:SetPoint("TOPLEFT",  bar, "TOPLEFT",   dx,              dy)
        ghost:SetPoint("TOPRIGHT", bar, "TOPRIGHT",  rightPad + dx,   dy)
        ghost:SetHeight(8)
    end
    reanchor()
    C_Timer.After(0, reanchor)

    local function updateFill()
        local minV, maxV = 0, 1
        if valueBar.GetMinMaxValues then minV, maxV = valueBar:GetMinMaxValues() end
        local v = valueBar.GetValue and valueBar:GetValue() or 0
        local range = (maxV or 1) - (minV or 0)
        local ratio = 0
        if range > 0 then ratio = math.max(0, math.min(1, (v - minV) / range)) end
        local w = ghost:GetWidth() or 0
        ghost._fill:SetWidth(math.max(0.001, w * ratio))
        ghost._fill:Show()
    end
    updateFill()
    if not F.fillHooked[bar] then
        F.fillHooked[bar] = true
        if valueBar ~= bar and valueBar.HookScript then
            valueBar:HookScript("OnValueChanged", updateFill)
            valueBar:HookScript("OnMinMaxChanged", updateFill)
        elseif bar.GetObjectType and bar:GetObjectType() == "StatusBar" then
            bar:HookScript("OnValueChanged", updateFill)
            bar:HookScript("OnMinMaxChanged", updateFill)
        end
        if ghost.HookScript then
            ghost:HookScript("OnSizeChanged", updateFill)
        end
        -- Mirror native show/hide so the ghost appears/vanishes with the bar.
        if bar.HookScript then
            bar:HookScript("OnShow", function()
                ghost:Show(); reanchor(); updateFill()
            end)
            bar:HookScript("OnHide", function() ghost:Hide() end)
        end
    end

    -- Lock outer bar + inner StatusBar to 8px. Debug confirmed the world-
    -- quest outer bar ships at 38px with a single TOPLEFT anchor (no
    -- BOTTOM anchor), and the inner .Bar is 17px with only a LEFT anchor.
    -- Both are freely SetHeight-able; the reserved 30px of dead space IS
    -- the outer bar's 38 vs our 8px ghost. Reentry-guarded hook.
    local function lockHeight(f)
        if not f or not f.SetHeight or F.heightHooked[f] then return end
        F.heightHooked[f] = true
        hooksecurefunc(f, "SetHeight", function(self)
            if F.ignoreHeight[self] then return end
            F.ignoreHeight[self] = true
            self:SetHeight(8)
            F.ignoreHeight[self] = nil
        end)
        f:SetHeight(8)
    end
    lockHeight(bar)
    if bar.Bar and bar.Bar ~= bar then lockHeight(bar.Bar) end

    -- Blizzard's tracker layout reads `bar.height` (Lua field, not
    -- :GetHeight()) to compute the owning block's .height, then anchors
    -- the next block below that. bar.height ships at 38; shrinking the
    -- frame with SetHeight(8) doesn't touch this field, so the block
    -- keeps reserving ~30 extra px of dead space. Overwrite it.
    if bar.height ~= nil then bar.height = 8 end
    -- Find & shrink the owning block once per bar. Cached on bar so
    -- subsequent CreateGhostBar calls skip the full sibling walk. Even
    -- after the cached block is no longer the current owner (pool reuse),
    -- the .height/SetHeight adjustment has already been applied and
    -- gated by F.blockShrunk[c], so re-walking is wasted work.
    if not F.ownerBlockResolved[bar] then
        F.ownerBlockResolved[bar] = true
        local bp = bar:GetParent()
        if bp and bp.GetNumChildren then
            local bTop = bar.GetTop and bar:GetTop()
            local bBot = bar.GetBottom and bar:GetBottom()
            if bTop and bBot then
                for i = 1, bp:GetNumChildren() do
                    local c = select(i, bp:GetChildren())
                    if c and type(c.usedLines) == "table" and c ~= bar
                       and c.height and not F.blockShrunk[c] then
                        local cTop = c.GetTop and c:GetTop()
                        local cBot = c.GetBottom and c:GetBottom()
                        if cTop and cBot and cTop >= bTop and cBot <= bBot then
                            F.blockShrunk[c] = true
                            c.height = (c.height or c:GetHeight() or 0) - 30
                            if c.SetHeight then c:SetHeight(c.height) end
                            break
                        end
                    end
                end
            end
        end
    end

    if bar:IsShown() then ghost:Show() else ghost:Hide() end
    _skinnedWidgetBars[bar] = true
end

local function SkinProgressBar(bar)
    if not bar then return end
    if _skinnedBars[bar] then return end
    _skinnedBars[bar] = true
    CreateGhostBar(bar)
end

local function SkinWidgetBar(bar)
    CreateGhostBar(bar)
end
EQT._SkinWidgetBar = SkinWidgetBar

-- Recursively (2 levels) find StatusBar frames under a block and skin them.
-- Read-only walk -- we never touch mouse state on children.
local function ScanBlockForWidgetBars() end  -- no-op kept for back-compat
EQT._ScanBlockForWidgetBars = ScanBlockForWidgetBars

-- Iterate every tracker's usedProgressBars pool and skin each. World-quest
-- / bonus-objective / scenario widget progress bars live on the tracker
-- itself, not on line.ProgressBar, so they miss our GetProgressBar hook.
local function SkinTrackerProgressBars(tracker)
    if not tracker or not tracker.usedProgressBars then return end
    -- Skip bars on the ScenarioObjectiveTracker when not in delve/dungeon.
    -- Same rationale as the SkinBlock bail: scenario widget visualizers
    -- are pooled into AreaPOI tooltip widgets and any ghost-bar mutation
    -- taints them.
    if tracker == _G.ScenarioObjectiveTracker then return end
    for _, bySomething in pairs(tracker.usedProgressBars) do
        if type(bySomething) == "table" then
            if bySomething.GetObjectType then
                -- Flat: usedProgressBars[key] = bar
                SkinWidgetBar(bySomething)
            else
                -- Nested: usedProgressBars[key1][key2] = bar
                for _, bar in pairs(bySomething) do
                    if type(bar) == "table" and bar.GetObjectType then
                        SkinWidgetBar(bar)
                    end
                end
            end
        end
    end
end
EQT._SkinTrackerProgressBars = SkinTrackerProgressBars

-------------------------------------------------------------------------------
-- Timer bar skin: same flat texture, yellow tint swapping to red when low.
-------------------------------------------------------------------------------
local function SkinTimerBar(bar)
    if not bar then return end
    if _skinnedTimerBars[bar] then return end
    _skinnedTimerBars[bar] = true

    if not EQT.Cfg("skinProgressBars") then return end

    -- Bail if this bar belongs to ScenarioObjectiveTracker.
    do
        local sot = _G.ScenarioObjectiveTracker
        if sot then
            local f, depth = bar:GetParent(), 0
            while f and depth < 8 do
                if f == sot then return end
                f = f.GetParent and f:GetParent()
                depth = depth + 1
            end
        end
    end

    local sb = bar.Bar or bar
    local tex = sb and sb.GetStatusBarTexture and sb:GetStatusBarTexture()
    if tex then tex:SetVertexColor(C_TIMER.r, C_TIMER.g, C_TIMER.b, 0.9) end

    if bar.BarBG then bar.BarBG:SetColorTexture(C_BAR_BG.r, C_BAR_BG.g, C_BAR_BG.b, C_BAR_BG.a) end
    if bar.Label then StyleFontString(bar.Label) end
    StyleAllFontStrings(bar)

    local PP = GetPP()
    if PP and PP.CreateBorder then
        PP.CreateBorder(sb or bar, 0, 0, 0, 1, 1, "OVERLAY", 7)
    end
end

-------------------------------------------------------------------------------
-- Re-skin every block a tracker has already populated. Safe to call any time
-- (idempotent via the _eqtBlockSkinned / _eqtBarSkinned flags on each frame).
-------------------------------------------------------------------------------
local function SkinExistingBlocks(tracker)
    if not tracker then return end

    -- Refresh the accent divider under this tracker's header on every pass
    -- so collapsed/re-expanded states always keep a visible divider.
    if tracker.Header then EnsureAccentDivider(tracker.Header) end

    -- ScenarioObjectiveTracker is left at Blizzard's native height/layout
    -- in ALL contexts (delves / dungeons / scenarios). Any height
    -- compaction from us pushes widget-visualizer-positioned elements
    -- (timers, progress bars, lives indicators) outside our bounds.

    -- Walk the tracker's usedProgressBars pool -- catches world-quest and
    -- bonus-objective widget bars that don't live on line.ProgressBar.
    if EQT.Cfg("skinProgressBars") and EQT._SkinTrackerProgressBars then
        EQT._SkinTrackerProgressBars(tracker)
    end

    -- Skin scenario / fixed named blocks that live as permanent fields on
    -- the tracker, NOT in usedBlocks (StageBlock = "Act I..." / "Stage
    -- Complete", ObjectivesBlock, widget container blocks, etc).
    -- Skin named tracker fields. ScenarioObjectiveTracker children are
    -- handled by Blizzard natively now (SkinBlock bails for them); only
    -- non-scenario blocks pass through. We intentionally do NOT hook
    -- ObjectivesBlock SetHeight — Blizzard's layout stays untouched.
    for _, fieldName in ipairs({
        "StageBlock", "ObjectivesBlock",
        "TopWidgetContainerBlock", "BottomWidgetContainerBlock",
        "ProvingGroundsBlock", "MawBuffsBlock", "ChallengeModeBlock",
    }) do
        local fb = tracker[fieldName]
        if fb then SkinBlock(fb) end
    end

    -- Collect blocks into an ordered list sorted top-to-bottom by Y. We use
    -- this to apply sequential per-section numbering (1, 2, 3...) that
    -- matches the visual order.
    -- Blizzard's usedBlocks is keyed by template string, and each entry is
    -- a sub-table keyed by blockID -> block. Iterate two levels.
    local ordered = {}
    if tracker.usedBlocks then
        for _, byTemplate in pairs(tracker.usedBlocks) do
            if type(byTemplate) == "table" then
                for _, block in pairs(byTemplate) do
                    if type(block) == "table" and block.GetTop then
                        ordered[#ordered + 1] = block
                    end
                end
            end
        end
        table.sort(ordered, function(a, b)
            local ay = a.GetTop and a:GetTop() or 0
            local by = b.GetTop and b:GetTop() or 0
            return ay > by
        end)

        for _, block in ipairs(ordered) do
            SkinBlock(block)
        end

        -- Style objective lines and their progress/timer bars.
        for _, block in ipairs(ordered) do
            if block.lines then
                for _, line in pairs(block.lines) do
                    StyleObjectiveLine(line)
                    if line.ProgressBar then
                        _skinnedBars[line.ProgressBar] = nil
                        SkinProgressBar(line.ProgressBar)
                    end
                    if line.TimerBar then
                        _skinnedTimerBars[line.TimerBar] = nil
                        SkinTimerBar(line.TimerBar)
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Hook a single sub-tracker.
-------------------------------------------------------------------------------
local function HookTracker(tracker)
    if not tracker then return end
    if _hookedTrackers[tracker] then return end
    _hookedTrackers[tracker] = true

    if tracker.Header then
        SkinHeader(tracker.Header)
        if tracker.Header.SetCollapsed then
            hooksecurefunc(tracker.Header, "SetCollapsed", function(self)
                SkinHeader(self)
            end)
        end
    end

    if tracker.AddBlock then
        hooksecurefunc(tracker, "AddBlock", function(_, block)
            SkinBlock(block)
        end)
    end

    if tracker.GetProgressBar then
        hooksecurefunc(tracker, "GetProgressBar", function(_, line)
            local bar = line and type(line) == "table" and line.ProgressBar
            if bar then
                SkinProgressBar(bar)
                -- Widget-bar skin owns the hide-all-FontStrings + ornament
                -- drain path. Run it on live bar acquisition so new world-
                -- quest / bonus-objective bars hide instantly instead of
                -- waiting for the next event tick.
                SkinWidgetBar(bar)
            end
        end)
    end

    if tracker.GetTimerBar then
        hooksecurefunc(tracker, "GetTimerBar", function(_, line)
            local bar = line and type(line) == "table" and line.TimerBar
            if bar then SkinTimerBar(bar) end
        end)
    end

    -- Re-evaluate the divider AND queue a BG resize after every layout
    -- pass. Update fires on content changes, collapse, and expand; the
    -- debounce in QueueResize coalesces bursts into a single measurement.
    if tracker.Update then
        hooksecurefunc(tracker, "Update", function(self)
            if self.Header then EnsureAccentDivider(self.Header) end
            if EQT.QueueResize then EQT.QueueResize() end
            -- Re-skin blocks on this tracker so late-added blocks (world
            -- quest tracked from map with another active, pool reuse,
            -- etc.) pick up POI reparent / icon hide. Debounced one frame
            -- so burst Update calls coalesce into a single skin pass.
            -- 100ms debounce so a burst of Update calls (Blizzard can
            -- fire many in one layout pass) coalesces into a single
            -- SkinExistingBlocks pass instead of one per Update.
            if not F.skinPending[self] then
                F.skinPending[self] = true
                C_Timer.After(0.1, function()
                    F.skinPending[self] = nil
                    SkinExistingBlocks(self)
                end)
            end
        end)
    end

    -- OnSizeChanged fires when frames settle into their final positions
    -- after Blizzard's layout pass. Belt-and-suspenders alongside the
    -- Update hook so we catch cases where Update fires mid-transition.
    if tracker.ContentsFrame and tracker.ContentsFrame.HookScript then
        tracker.ContentsFrame:HookScript("OnSizeChanged", function()
            if EQT.QueueResize then EQT.QueueResize() end
        end)
    end

    SkinExistingBlocks(tracker)
end

-------------------------------------------------------------------------------
-- Collect every tracker Blizzard exposes. Prefer the authoritative MODULES
-- table on ObjectiveTrackerFrame; fall back to named globals so late-loaded
-- sub-trackers are still caught.
-------------------------------------------------------------------------------
local function EachTracker(fn)
    local seen = {}

    local otf = _G.ObjectiveTrackerFrame
    local modules = otf and (otf.modules or otf.MODULES)
    if modules then
        for _, t in ipairs(modules) do
            if t and not seen[t] then
                seen[t] = true
                fn(t)
            end
        end
    end

    for _, name in ipairs(SUB_TRACKERS) do
        local t = _G[name]
        if t and not seen[t] then
            seen[t] = true
            fn(t)
        end
    end
end

-------------------------------------------------------------------------------
-- Entry point called from the loader after Blizzard_ObjectiveTracker loads.
-------------------------------------------------------------------------------
function EQT.InitSkin()
    -- Nuke the master "All Objectives" header / menu at the top of the
    -- tracker. We use per-section headers (Quests / Achievements / etc)
    -- instead, so the master bar is redundant.
    local otf = _G.ObjectiveTrackerFrame
    if otf then
        local headerMenu = otf.HeaderMenu
        if headerMenu then
            headerMenu:Hide()
            headerMenu:SetAlpha(0)
            if headerMenu.SetHeight then headerMenu:SetHeight(0.001) end
            headerMenu:HookScript("OnShow", function(self) self:Hide() end)
        end
        if otf.Header and otf.Header ~= headerMenu then
            otf.Header:Hide()
            otf.Header:HookScript("OnShow", function(self) self:Hide() end)
        end
        -- Strip the parchment / nine-slice background behind the whole tracker.
        if otf.NineSlice then otf.NineSlice:Hide() end
        StripTextures(otf)
    end

    EachTracker(HookTracker)

    -- Re-skin on tracker refresh events. Each of these fires when Blizzard
    -- re-populates blocks; we piggy-back to catch newly-pooled-but-not-yet-
    -- hooked children and to reapply fonts/colors Blizzard just reset.
    local evt = CreateFrame("Frame")
    evt:RegisterEvent("QUEST_LOG_UPDATE")
    evt:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    evt:RegisterEvent("SCENARIO_UPDATE")
    evt:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
    evt:RegisterEvent("TRACKED_ACHIEVEMENT_LIST_CHANGED")
    evt:RegisterEvent("TRACKED_RECIPE_UPDATE")
    evt:RegisterEvent("SUPER_TRACKING_CHANGED")
    -- Debounce the event burst (QUEST_LOG_UPDATE alone can fire many
    -- times per second on quest accept / objective progress). Coalesce
    -- all refreshes into a single SkinExistingBlocks pass per 100ms.
    local _evtSkinPending = false
    evt:SetScript("OnEvent", function()
        if EQT.QueueResize then EQT.QueueResize() end
        if _evtSkinPending then return end
        _evtSkinPending = true
        C_Timer.After(0.1, function()
            _evtSkinPending = false
            EachTracker(SkinExistingBlocks)
        end)
    end)

    -- Top-level ObjectiveTrackerFrame:Update fires whenever any section
    -- changes (added, removed, resized). Hook it so the BG always follows.
    local otf = _G.ObjectiveTrackerFrame
    if otf and otf.Update then
        hooksecurefunc(otf, "Update", function()
            if EQT.QueueResize then EQT.QueueResize() else if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end end
        end)
    end
    -- Same story for the global container that orchestrates the modules.
    if _G.ObjectiveTracker_Update then
        hooksecurefunc("ObjectiveTracker_Update", function()
            if EQT.QueueResize then EQT.QueueResize() else if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end end
        end)
    end

    EQT.RestyleAll = function()
        EachTracker(function(t)
            if t.Header then SkinHeader(t.Header) end
            SkinExistingBlocks(t)
        end)
    end
end
