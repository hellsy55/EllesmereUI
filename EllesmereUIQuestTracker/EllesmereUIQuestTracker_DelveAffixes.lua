-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_DelveAffixes.lua
--
-- Renders our own delve affix icons inline next to the StageBlock title.
-- Hides Blizzard's WidgetContainer SpellContainer (top-level only) so we
-- can lay out the affixes ourselves with full control over position +
-- styling. Tooltips are built from C_TooltipInfo.GetSpellByID and rendered
-- via EllesmereUI.ShowWidgetTooltip per CLAUDE.md (never GameTooltip).
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT

local DELVE_HEADER_TYPE =
    (Enum and Enum.UIWidgetVisualizationType
     and Enum.UIWidgetVisualizationType.ScenarioHeaderDelves) or 29

local ICON_SIZE   = 18
local ICON_SPACING = 4

-- Pool of our affix icon buttons (keyed by index). Recycled across refreshes.
local _iconPool = {}
local _spellContainerHidden = setmetatable({}, { __mode = "k" })

local function GetAccent()
    local eg = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    if eg then return eg.r, eg.g, eg.b end
    return 0.047, 0.824, 0.624
end

-- One-shot search for any SpellContainer named frame inside the scenario
-- tracker, then hide it so it stops rendering Blizzard's icons.
-- Containers are referenced via parentKey ("SpellContainer", "WidgetContainer")
-- on their parent's Lua table, NOT via :GetName(). Walk via field-lookups.
local function HideBlizzardSpellContainers()
    local sot = _G.ScenarioObjectiveTracker
    local cf  = sot and sot.ContentsFrame
    if not cf then return end
    -- Recursively walk every Frame, look for a SpellContainer field on it.
    local function walk(f, depth)
        if not f or depth > 7 then return end
        if type(f) == "table" then
            for k, v in pairs(f) do
                if type(k) == "string"
                   and (k == "SpellContainer" or k:find("SpellContainer", 1, true))
                   and type(v) == "table" and v.SetAlpha
                   and not _spellContainerHidden[v] then
                    _spellContainerHidden[v] = true
                    -- Hide() (not just SetAlpha(0)) so hit-testing + child
                    -- mouseover tooltips are cut off too. Alpha-zero leaves
                    -- the container clickable; Blizzard's shimmer / glow
                    -- animations also keep playing on alpha-0 textures.
                    v:SetAlpha(0)
                    if v.Hide then v:Hide() end
                    if v.EnableMouse then v:EnableMouse(false) end
                    if v.EnableMouseMotion then v:EnableMouseMotion(false) end
                    if v.HookScript then
                        v:HookScript("OnShow", function(self)
                            self:SetAlpha(0)
                            if self.Hide then self:Hide() end
                            if self.EnableMouse then self:EnableMouse(false) end
                        end)
                    end
                end
            end
        end
        if f.GetChildren then
            for _, c in ipairs({ f:GetChildren() }) do
                walk(c, depth + 1)
            end
        end
    end
    walk(cf, 0)
end

-- Build the spell tooltip text from C_TooltipInfo.GetSpellByID and show
-- it via EllesmereUI's widget tooltip system.
local function ShowAffixTooltip(iconBtn, spellID)
    if not spellID or not EllesmereUI or not EllesmereUI.ShowWidgetTooltip then return end
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
        local data = C_TooltipInfo.GetSpellByID(spellID)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                if line.leftText and line.leftText ~= "" then
                    lines[#lines + 1] = line.leftText
                end
            end
        end
    end
    if #lines == 0 and C_Spell and C_Spell.GetSpellName then
        lines[#lines + 1] = C_Spell.GetSpellName(spellID) or ""
    end
    EllesmereUI.ShowWidgetTooltip(iconBtn, table.concat(lines, "\n"))
end

local function HideAffixTooltip()
    if EllesmereUI and EllesmereUI.HideWidgetTooltip then
        EllesmereUI.HideWidgetTooltip()
    end
end

-- Acquire (or create) an icon at index i, parented to host frame.
local function AcquireIcon(host, i)
    local btn = _iconPool[i]
    if not btn or btn:GetParent() ~= host then
        btn = CreateFrame("Button", nil, host)
        btn:SetSize(ICON_SIZE, ICON_SIZE)
        btn:EnableMouse(true)
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn._icon = icon
        local PP = EllesmereUI and EllesmereUI.PanelPP
        if PP and PP.CreateBorder then
            PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end
        btn:SetScript("OnEnter", function(self) ShowAffixTooltip(self, self._spellID) end)
        btn:SetScript("OnLeave", HideAffixTooltip)
        _iconPool[i] = btn
    end
    btn:Show()
    return btn
end

local function ReleaseUnused(fromIndex)
    for i = fromIndex, #_iconPool do
        if _iconPool[i] then _iconPool[i]:Hide() end
    end
end

-- Get the active scenario step's widget set ID. Prefer C_ScenarioInfo
-- (more reliable on Midnight); fall back to C_Scenario.GetStepInfo's
-- 12th return value.
local function GetWidgetSetIDs()
    local sets = {}
    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
        local si = C_ScenarioInfo.GetScenarioStepInfo()
        if si and si.widgetSetID and si.widgetSetID > 0 then
            sets[#sets + 1] = si.widgetSetID
        end
    end
    if C_Scenario and C_Scenario.GetStepInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, widgetSetID =
            pcall(C_Scenario.GetStepInfo)
        if ok and widgetSetID and widgetSetID ~= 0 then
            local seen = false
            for _, s in ipairs(sets) do if s == widgetSetID then seen = true end end
            if not seen then sets[#sets + 1] = widgetSetID end
        end
    end
    return sets
end

-- Parse delve lives from the widget's `currencies` array. One of the
-- currencies has a tooltip starting with "Total deaths:" -- its `text`
-- field is remaining lives, and the deaths count parses out of the
-- tooltip. Returns remaining, max, deaths (all nil if not found).
local function GetDelveLivesFromHeaderInfo(hi)
    if not hi or not hi.currencies then return nil, nil, nil end
    for _, c in ipairs(hi.currencies) do
        local tooltip = tostring(c.tooltip or "")
        if tooltip:find("Total deaths") then
            local remaining = tonumber(c.text)
            if remaining then
                local deaths = tonumber(tooltip:match("[Tt]otal deaths:%s*(%d+)")) or 0
                return remaining, remaining + deaths, deaths
            end
        end
    end
    return nil, nil, nil
end

-- Returns remaining, max lives for the active delve (both nil if not in
-- a delve or the widget isn't found yet).
local function GetDelveLives()
    if not C_UIWidgetManager
       or not C_UIWidgetManager.GetAllWidgetsBySetID
       or not C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo then
        return nil
    end
    for _, setID in ipairs(GetWidgetSetIDs()) do
        local ok, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
        if ok and widgets then
            for _, w in ipairs(widgets) do
                if w.widgetType == DELVE_HEADER_TYPE then
                    local dOk, wi = pcall(
                        C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo,
                        w.widgetID)
                    if dOk and wi then
                        local rem, max = GetDelveLivesFromHeaderInfo(wi)
                        if rem then return rem, max end
                    end
                end
            end
        end
    end
    return nil
end

-- Affixes live on the ScenarioHeaderDelves widget (type 29). Its
-- visualization info has a `spells` array. Walk every active widget set,
-- find delve-header widgets, collect their spells.
local function GetActiveAffixes()
    local out = {}
    if not C_UIWidgetManager
       or not C_UIWidgetManager.GetAllWidgetsBySetID
       or not C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo then
        return out
    end
    local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
    for _, setID in ipairs(GetWidgetSetIDs()) do
        local ok, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
        if ok and widgets then
            for _, w in ipairs(widgets) do
                if w.widgetType == DELVE_HEADER_TYPE then
                    local dOk, wi = pcall(
                        C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo,
                        w.widgetID)
                    if dOk and wi and wi.spells then
                        for _, sp in ipairs(wi.spells) do
                            if sp.spellID and sp.spellID > 0 then
                                out[#out + 1] = {
                                    spellID = sp.spellID,
                                    icon    = GetSpellTexture and GetSpellTexture(sp.spellID),
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

-- Hide Blizzard's delve-lives display. It lives under a CurrencyContainer
-- parentKey on an anonymous Frame under the scenario tracker's widget
-- container. Walk frames' Lua tables (parentKey=CurrencyContainer) and
-- suppress matches top-level.
local _hiddenLiveContainers = setmetatable({}, { __mode = "k" })
local function HideBlizzardLives()
    local sot = _G.ScenarioObjectiveTracker
    local cf  = sot and sot.ContentsFrame
    if not cf then return end
    local function walk(f, depth)
        if not f or depth > 7 then return end
        if type(f) == "table" then
            for k, v in pairs(f) do
                if type(k) == "string"
                   and k:find("CurrencyContainer", 1, true)
                   and type(v) == "table" and v.SetAlpha
                   and not _hiddenLiveContainers[v] then
                    _hiddenLiveContainers[v] = true
                    v:SetAlpha(0)
                    if v.Hide then v:Hide() end
                    if v.EnableMouse then v:EnableMouse(false) end
                    if v.HookScript then
                        v:HookScript("OnShow", function(self)
                            self:SetAlpha(0)
                            if self.Hide then self:Hide() end
                        end)
                    end
                end
            end
        end
        if f.GetChildren then
            for _, c in ipairs({ f:GetChildren() }) do
                walk(c, depth + 1)
            end
        end
    end
    walk(cf, 0)
end

-- Lives indicator (our own). Single heart texture + count FontString.
local HEART_SIZE = 12
local _livesFrame
local function EnsureLivesFrame(stageBlock)
    if _livesFrame and _livesFrame:GetParent() == stageBlock then return _livesFrame end
    _livesFrame = CreateFrame("Frame", nil, stageBlock)
    _livesFrame:SetSize(40, 14)
    local heart = _livesFrame:CreateTexture(nil, "ARTWORK")
    heart._eqtKeep = true   -- exempt from skin's "delves-" atlas strip
    heart:SetAtlas("delves-scenario-heart-icon")
    heart:SetSize(HEART_SIZE, HEART_SIZE)
    heart:SetPoint("LEFT", _livesFrame, "LEFT", 0, 0)
    _livesFrame._heart = heart
    local count = _livesFrame:CreateFontString(nil, "OVERLAY")
    count:SetFont(EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames") or "Fonts/FRIZQT__.TTF",
        11, EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag() or "")
    count:SetPoint("LEFT", heart, "RIGHT", 3, 0)
    count:SetTextColor(1, 1, 1)
    _livesFrame._count = count
    return _livesFrame
end

-- Parse every active delve-affix spell's tooltip for a "remaining: X / Y"
-- pattern. Returns a list of { killed, total, name, finished } rows so we
-- can render them as extra objective lines. Nemesis Strongbox ("Enemy
-- groups remaining: 3 / 4") is the canonical case; other affix spells
-- that expose similar trackable counts surface automatically.
local function GetAffixProgressLines()
    local out = {}
    if not C_UIWidgetManager or not C_TooltipInfo then return out end
    local affixes = GetActiveAffixes()
    -- GetActiveAffixes pulls from the same widget set; we want ALL the
    -- spellIDs here, not just the first one (UpdateDelveAffixIcons slices
    -- to 1 for the inline icon row, but progress lines should cover all).
    -- Re-query directly to avoid that slicing.
    local allIDs = {}
    for _, setID in ipairs(GetWidgetSetIDs()) do
        local ok, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
        if ok and widgets then
            for _, w in ipairs(widgets) do
                if w.widgetType == DELVE_HEADER_TYPE then
                    local dOk, wi = pcall(
                        C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo,
                        w.widgetID)
                    if dOk and wi and wi.spells then
                        for _, sp in ipairs(wi.spells) do
                            if sp.spellID and sp.spellID > 0 then
                                allIDs[#allIDs + 1] = sp.spellID
                            end
                        end
                    end
                end
            end
        end
    end
    local GetName = C_Spell and C_Spell.GetSpellName
    for _, sid in ipairs(allIDs) do
        local data = C_TooltipInfo.GetSpellByID and C_TooltipInfo.GetSpellByID(sid)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local txt = line.leftText
                if txt then
                    local clean = txt:gsub("|cn[^:]*:", "")
                                     :gsub("|c%x%x%x%x%x%x%x%x", "")
                                     :gsub("|r", "")
                    local rem, tot = clean:lower():match("remaining:%s*(%d+)%s*/%s*(%d+)")
                    if rem and tot then
                        local r = tonumber(rem) or 0
                        local t = tonumber(tot) or 0
                        out[#out + 1] = {
                            killed   = t - r,
                            total    = t,
                            name     = (GetName and GetName(sid)) or "Objective",
                            finished = r == 0,
                        }
                    end
                end
            end
        end
    end
    return out
end

-- Render the affix-progress lines as a small stack of FontStrings below
-- the last visible Blizzard objective on the StageBlock. Pool reused
-- across updates.
local _affixLineFS = {}
local function GetAffixLineFS(i, parent)
    local fs = _affixLineFS[i]
    if not fs then
        fs = parent:CreateFontString(nil, "OVERLAY")
        local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames"))
                     or "Fonts/FRIZQT__.TTF"
        local outline = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or ""
        fs:SetFont(font, 10, outline)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        _affixLineFS[i] = fs
    end
    if fs:GetParent() ~= parent then fs:SetParent(parent) end
    return fs
end
local function HideAffixLines(fromIndex)
    for i = fromIndex, #_affixLineFS do
        if _affixLineFS[i] then _affixLineFS[i]:Hide() end
    end
end

local function RenderAffixProgressLines(stageBlock)
    local lines = GetAffixProgressLines()
    if #lines == 0 then HideAffixLines(1); return end
    local sot = _G.ScenarioObjectiveTracker
    local ob  = sot and sot.ObjectivesBlock
    local parent = ob or stageBlock
    -- Anchor the first extra line below the lowest visible FontString in
    -- ObjectivesBlock (the last Blizzard objective). If that block has
    -- nothing yet, fall back to StageBlock's bottom.
    local anchorFrame = parent
    local anchorPoint = "BOTTOMLEFT"
    local xOff, yOff = 20, -4
    local ourFS = {}
    for _, fs in pairs(_affixLineFS) do ourFS[fs] = true end
    if ob and ob.GetRegions then
        local lowest, lowestY
        for _, rg in ipairs({ ob:GetRegions() }) do
            if rg.GetObjectType and rg:GetObjectType() == "FontString"
               and not ourFS[rg]
               and rg:IsShown() and rg:GetText() and rg:GetText() ~= "" then
                local b = rg:GetBottom()
                if b and (not lowestY or b < lowestY) then
                    lowestY, lowest = b, rg
                end
            end
        end
        if lowest then
            anchorFrame = lowest
            anchorPoint = "BOTTOMLEFT"
            xOff, yOff = 0, -2
        end
    end
    local function cfg(k)
        local db = EQT.DB and EQT.DB() or {}
        return db[k]
    end
    local qR = cfg("questR") or 0.722
    local qG = cfg("questG") or 0.722
    local qB = cfg("questB") or 0.722
    local cR = cfg("completedR") or 0.251
    local cG = cfg("completedG") or 1.000
    local cB = cfg("completedB") or 0.349
    local prev = anchorFrame
    local prevPoint = anchorPoint
    xOff = xOff - 11
    yOff = yOff
    for i, row in ipairs(lines) do
        local fs = GetAffixLineFS(i, parent)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", prev, prevPoint, xOff, yOff)
        fs:SetText(string.format("%d/%d %s", row.killed, row.total, row.name))
        if row.finished then
            fs:SetTextColor(cR, cG, cB)
        else
            fs:SetTextColor(qR, qG, qB)
        end
        fs:Show()
        prev = fs
        prevPoint = "BOTTOMLEFT"
        xOff, yOff = -10, -1
    end
    HideAffixLines(#lines + 1)
end

-- Public entry: called from SkinBlock when we've identified the StageBlock
-- and have the inner title FontString to anchor against.
function EQT.UpdateDelveAffixIcons(stageBlock, innerTitleFS)
    -- Delve / scenario / dungeon sections all use Blizzard's native UI now.
    -- This module is a no-op; we keep the function defined so calls from
    -- the skin module don't error.
    do return end

    local isDelve = C_PartyInfo and C_PartyInfo.IsDelveInProgress
                    and C_PartyInfo.IsDelveInProgress()
    if not isDelve then
        ReleaseUnused(1)
        HideAffixLines(1)
        if _livesFrame then _livesFrame:Hide() end
        if EQT._hideDelveLeftovers then EQT._hideDelveLeftovers() end
        return
    end

    -- Lives display: always anchored 4px to the LEFT of the delve level
    -- number FontString, regardless of whether affixes are present.
    local lives = EnsureLivesFrame(stageBlock)
    local remaining, maxLives = GetDelveLives()
    if remaining then
        lives._count:SetText(maxLives
            and (remaining .. "/" .. maxLives)
            or tostring(remaining))
        local numFS = EQT._getDelveLevelNumFS and EQT._getDelveLevelNumFS(stageBlock)
        if numFS then
            lives:ClearAllPoints()
            lives:SetPoint("RIGHT", numFS, "LEFT", -4, 0)
        end
        lives:Show()
    else
        lives:Hide()
    end

    local affixes = GetActiveAffixes()
    -- Only show the first affix (others are redundant for delve display).
    if #affixes > 1 then
        for i = #affixes, 2, -1 do table.remove(affixes, i) end
    end
    if #affixes == 0 then
        ReleaseUnused(1)
        return
    end

    -- Anchor the first icon to the title text's left + its rendered string
    -- width. The title's RIGHT point is near the frame's right edge (auto-
    -- width FontString), so anchoring to "RIGHT" puts the icon far away.
    -- StringWidth gives us the actual text edge.
    local titleW = innerTitleFS:GetStringWidth() or 0
    local prevAnchor = innerTitleFS
    local xPad = 6 + titleW
    local relPoint = "LEFT"
    for i, aff in ipairs(affixes) do
        local btn = AcquireIcon(stageBlock, i)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", prevAnchor, relPoint, xPad, 0)
        if aff.icon then btn._icon:SetTexture(aff.icon) end
        btn._spellID = aff.spellID
        prevAnchor = btn
        relPoint = "RIGHT"
        xPad = ICON_SPACING
    end
    ReleaseUnused(#affixes + 1)

    -- Render nemesis-style progress lines (affix spells whose tooltips
    -- expose "remaining: X / Y") as extra objective rows below Blizzard's
    -- criteria. Shows the user's Nemesis Strongbox count etc.
    RenderAffixProgressLines(stageBlock)

    -- On zone-in, the title FontString can be styled before its text is
    -- populated (GetStringWidth returns 0 momentarily), making the affix
    -- land where the title WILL be. Re-run shortly to pick up the real
    -- text width. Debounced so bursts coalesce.
    if (titleW or 0) == 0 and not EQT._affixRetryPending then
        EQT._affixRetryPending = true
        C_Timer.After(0.2, function()
            EQT._affixRetryPending = false
            if EQT.UpdateDelveAffixIcons then
                -- Grab latest cached stage block + title FS from the skin
                -- module's caches if available.
                local sot = _G.ScenarioObjectiveTracker
                local sb = sot and sot.StageBlock
                if sb and EQT._getInnerTitleFS then
                    local fs = EQT._getInnerTitleFS(sb)
                    if fs then EQT.UpdateDelveAffixIcons(sb, fs) end
                end
            end
        end)
    end
end

-- Refresh on widget / scenario events.
local evt = CreateFrame("Frame")
evt:RegisterEvent("UPDATE_UI_WIDGET")
evt:RegisterEvent("SCENARIO_UPDATE")
evt:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:RegisterEvent("ZONE_CHANGED_NEW_AREA")
evt:SetScript("OnEvent", function()
    -- Re-skin path picks up our affix update via SkinBlock's call into here.
    if EQT.QueueResize then EQT.QueueResize() end
    local isDelve = C_PartyInfo and C_PartyInfo.IsDelveInProgress
                    and C_PartyInfo.IsDelveInProgress()
    if not isDelve then
        ReleaseUnused(1)
        HideAffixLines(1)
        if _livesFrame then _livesFrame:Hide() end
        if EQT._hideDelveLeftovers then EQT._hideDelveLeftovers() end
    end
end)
