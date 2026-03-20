-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker.lua
-------------------------------------------------------------------------------
local addonName, ns = ...

local DEFAULTS = {
    enabled              = true,
    locked               = false,
    xPos                 = nil,
    yPos                 = nil,
    width                = 220,
    bgAlpha              = 0.35,
    fixedHeight          = false,
    fixedHeightValue     = 300,
    maxHeight            = 600,
    titleFontSize        = 11,
    titleFont            = nil,
    titleColor           = { r=1.0,  g=0.85, b=0.1  },
    objFontSize          = 10,
    objFont              = nil,
    objColor             = { r=0.72, g=0.72, b=0.72 },
    secFontSize          = 8,
    secFont              = nil,
    showZoneQuests       = true,
    showWorldQuests      = true,
    zoneCollapsed        = false,
    worldCollapsed       = false,
    showQuestItems       = true,
    questItemSize        = 22,
    secColor             = { r=0.047, g=0.824, b=0.624 },
    hdrFont              = nil,
    hdrFontSize          = 11,
    hdrColor             = { r=1.0,   g=1.0,   b=1.0  },
    hdrShadow            = "OUTLINE",
    titleShadow          = "NONE",
    objShadow            = "NONE",
    secShadow            = "OUTLINE",
    -- Shadow color/alpha/offset per font type (r,g,b default black, a=1, ox=1,oy=-1)
    hdrShadowColor       = { r=0, g=0, b=0, a=0.8 },
    titleShadowColor     = { r=0, g=0, b=0, a=0.8 },
    objShadowColor       = { r=0, g=0, b=0, a=0.8 },
    secShadowColor       = { r=0, g=0, b=0, a=0.8 },
    hdrShadowOffset      = { x=1, y=-1 },
    titleShadowOffset    = { x=1, y=-1 },
    objShadowOffset      = { x=1, y=-1 },
    secShadowOffset      = { x=1, y=-1 },
    delveCollapsed       = false,
    questsCollapsed      = false,
    questItemHotkey      = nil,
    autoAccept           = false,
    autoTurnIn           = false,
    autoTurnInShiftSkip  = true,
    showTopLine          = true,
    hideBlizzardTracker  = true,
}

local C = {
    accent    = { r=0.047, g=0.824, b=0.624 },
    complete  = { r=0.25,  g=1.0,   b=0.35  },
    failed    = { r=1.0,   g=0.3,   b=0.3   },
    header    = { r=1.0,   g=1.0,   b=1.0   },
    section   = { r=0.047, g=0.824, b=0.624 },
    timer     = { r=1.0,   g=0.82,  b=0.2   },
    timerLow  = { r=1.0,   g=0.3,   b=0.3   },
    barBg     = { r=0.15,  g=0.15,  b=0.15  },
    barFill   = { r=0.047, g=0.824, b=0.624 },
}

local EQT      = {}
ns.EQT         = EQT
EQT.rows       = {}
EQT.sections   = {}
EQT.itemBtns   = {}
EQT.timerRows  = {}   -- rows with active timers (need OnUpdate)
EQT.dirty      = false

-------------------------------------------------------------------------------
-- DB
-------------------------------------------------------------------------------
local function DB()
    EllesmereUIQuestTrackerDB = EllesmereUIQuestTrackerDB or {}
    for k, v in pairs(DEFAULTS) do
        if type(v) ~= "table" and EllesmereUIQuestTrackerDB[k] == nil then
            EllesmereUIQuestTrackerDB[k] = v
        end
    end
    for _, key in ipairs({"titleColor","objColor","secColor","hdrColor"}) do
        if not EllesmereUIQuestTrackerDB[key] then
            local d = DEFAULTS[key]
            EllesmereUIQuestTrackerDB[key] = {r=d.r, g=d.g, b=d.b}
        end
    end
    return EllesmereUIQuestTrackerDB
end
local function Cfg(k) return DB()[k] end

-------------------------------------------------------------------------------
-- Fonts
-------------------------------------------------------------------------------
local FALLBACK_FONT = "Fonts/FRIZQT__.TTF"
local function SafeFont(p)
    if not p or p == "" then return FALLBACK_FONT end
    -- WoW only supports TTF/TGA, not OTF
    local ext = p:match("%.(%a+)$")
    if ext and ext:lower() == "otf" then return FALLBACK_FONT end
    return p
end
-- Apply shadow color/offset to a FontString from DB settings
local function ApplyShadow(fs, shadowColorKey, shadowOffsetKey)
    if not fs then return end
    local sc = Cfg(shadowColorKey) or {}
    local so = Cfg(shadowOffsetKey) or {}
    fs:SetShadowColor(sc.r or 0, sc.g or 0, sc.b or 0, sc.a or 0.8)
    fs:SetShadowOffset(so.x or 1, so.y or -1)
end
local function SetFontSafe(fs, path, size, flags)
    if not fs then return end
    local safePath = SafeFont(path)
    fs:SetFont(safePath, size or 11, flags or "NONE")
    -- Verify font was set; if not try forward-slash fallback, then Blizzard default
    if not fs:GetFont() then
        fs:SetFont("Fonts/FRIZQT__.TTF", size or 11, flags or "NONE")
    end
    if not fs:GetFont() then
        fs:SetFont("Fonts\\FRIZQT__.TTF", size or 11, flags or "NONE")
    end
    if not fs:GetFont() then
        -- Last resort: copy font from GameFontNormal which always exists
        local gf = GameFontNormal and GameFontNormal:GetFont()
        if gf then fs:SetFont(gf, size or 11, flags or "NONE") end
    end
end
local function GlobalFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return SafeFont(EllesmereUI.GetFontPath("unitFrames"))
    end
    return FALLBACK_FONT
end
local function ResolveName(name)
    if not name or name == "" then return nil end
    if EllesmereUI and EllesmereUI.ResolveFontName then
        local p = EllesmereUI.ResolveFontName(name); if p then return p end
    end
    if EllesmereUI and EllesmereUI.FONT_BLIZZARD and EllesmereUI.FONT_BLIZZARD[name] then
        return EllesmereUI.FONT_BLIZZARD[name]
    end
    if EllesmereUI and EllesmereUI.FONT_FILES and EllesmereUI.FONT_FILES[name] and EllesmereUI.MEDIA_PATH then
        return SafeFont(EllesmereUI.MEDIA_PATH.."fonts\\"..EllesmereUI.FONT_FILES[name])
    end
    return nil
end
local function TitleFont() return ResolveName(Cfg("titleFont")) or GlobalFont(), Cfg("titleFontSize") or 11, Cfg("titleShadow") or "NONE" end
local function ObjFont()   return ResolveName(Cfg("objFont"))   or GlobalFont(), Cfg("objFontSize")   or 10, Cfg("objShadow") or "NONE" end
local function SecFont()
    return SafeFont(ResolveName(Cfg("secFont")) or GlobalFont()), Cfg("secFontSize") or 8, Cfg("secShadow") or "OUTLINE"
end
local function HdrFont()
    return SafeFont(ResolveName(Cfg("hdrFont")) or GlobalFont()), Cfg("hdrFontSize") or 11, Cfg("hdrShadow") or "OUTLINE"
end

-------------------------------------------------------------------------------
-- Timer helpers
-------------------------------------------------------------------------------
local function FormatTimeLeft(seconds)
    if seconds <= 0 then return "0:00" end
    if seconds < 60 then
        return string.format("0:%02d", math.floor(seconds))
    elseif seconds < 3600 then
        return string.format("%d:%02d", math.floor(seconds/60), math.floor(seconds%60))
    else
        return string.format("%dh %dm", math.floor(seconds/3600), math.floor((seconds%3600)/60))
    end
end

-- Scan a widget set for a ScenarioHeaderTimer widget (type 20).
-- Returns duration, startTime or nil, nil.
local function GetWidgetSetTimer(setID)
    if not setID or setID == 0 then return nil, nil end
    if not C_UIWidgetManager or not C_UIWidgetManager.GetAllWidgetsBySetID then return nil, nil end
    local ok, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
    if not ok or not widgets then return nil, nil end
    for _, w in ipairs(widgets) do
        if w.widgetType == 20 and C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo then
            local ti = C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo(w.widgetID)
            if ti and ti.shownState == 1 then
                local tMin     = ti.timerMin   or 0
                local tMax     = ti.timerMax   or 0
                local tVal     = ti.timerValue or 0
                local duration  = tMax - tMin
                local remaining = tVal - tMin
                if remaining > 0 and duration > 0 then
                    local startTime = GetTime() - (duration - remaining)
                    return duration, startTime
                end
            end
        end
    end
    return nil, nil
end

-- Returns duration, startTime (both needed for live countdown), or nil, nil.
-- Priority: GetQuestTimeLeftData -> ScenarioHeaderTimer widget (type 20) from step widgetSetID
local function GetQuestTimer(questID)
    -- 1. Standard quest timer
    if GetQuestTimeLeftData then
        local startTime, duration = GetQuestTimeLeftData(questID)
        if startTime and startTime > 0 and duration and duration > 0 then
            local remaining = duration - (GetTime() - startTime)
            if remaining > 0 then return duration, startTime end
        end
    end
    -- 2. ScenarioHeaderTimer widget from step widgetSetID (covers Assault/Event quests)
    if C_Scenario and C_Scenario.GetStepInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, widgetSetID = pcall(C_Scenario.GetStepInfo)
        if ok and widgetSetID and widgetSetID ~= 0 then
            local dur, start = GetWidgetSetTimer(widgetSetID)
            if dur and start then return dur, start end
        end
    end
    -- 3. ObjectiveTracker widget set fallback
    if C_UIWidgetManager and C_UIWidgetManager.GetObjectiveTrackerWidgetSetID then
        local otSet = C_UIWidgetManager.GetObjectiveTrackerWidgetSetID()
        if otSet and otSet ~= 0 then
            local dur, start = GetWidgetSetTimer(otSet)
            if dur and start then return dur, start end
        end
    end
    return nil, nil
end

-- Returns numFulfilled, numRequired for progressbar objectives
local function GetProgressBar(questID)
    if not C_QuestLog.GetQuestObjectives then return nil end
    local objs = C_QuestLog.GetQuestObjectives(questID)
    if not objs then return nil end
    for _, obj in ipairs(objs) do
        if obj.type == "progressbar" then
            -- numFulfilled/numRequired are on the obj table
            local cur = obj.numFulfilled or 0
            local max = obj.numRequired  or 100
            if max > 0 then return cur, max end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Row pool
-------------------------------------------------------------------------------
local rowPool = {}
local function AcquireRow(parent)
    local r = table.remove(rowPool)
    if not r then
        r = {}
        r.frame = CreateFrame("Button", nil, parent)
        r.text  = r.frame:CreateFontString(nil, "OVERLAY")
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(true)
        r.text:SetNonSpaceWrap(false)
        r.frame:SetScript("OnEnter", function(self)
            if self._questID then r.text:SetAlpha(0.55) end
        end)
        r.frame:SetScript("OnLeave", function() r.text:SetAlpha(1) end)
    end
    r.frame:SetParent(parent); r.frame._questID = nil
    r.frame:EnableMouse(false); r.frame:Show(); r.text:Show()
    return r
end
local function ReleaseRow(r)
    r.frame:Hide(); r.frame:ClearAllPoints(); r.frame:SetScript("OnClick", nil)
    -- Clean up timer/progressbar sub-widgets
    if r.timerFS     then r.timerFS:Hide()     end
    if r.barBg       then r.barBg:Hide()       end
    if r.barFill     then r.barFill:Hide()     end
    if r.pctFS       then r.pctFS:Hide()       end
    -- Clean up banner sub-widgets
    if r.bannerBg    then r.bannerBg:Hide()    end
    if r.bannerAccent then r.bannerAccent:Hide() end
    if r.bannerIcon  then r.bannerIcon:Hide()  end
    if r.tierFS      then r.tierFS:Hide()      end
    table.insert(rowPool, r)
end
local function ReleaseAll()
    EQT.timerRows = {}
    for i = #EQT.rows, 1, -1 do ReleaseRow(EQT.rows[i]); EQT.rows[i] = nil end
end

-- Section pool
local secPool = {}
local function AcquireSection(parent)
    local s = table.remove(secPool)
    if not s then
        s = {}
        s.frame = CreateFrame("Button", nil, parent)
        s.label = s.frame:CreateFontString(nil, "OVERLAY")
        s.label:SetJustifyH("LEFT")
        s.arrow = s.frame:CreateFontString(nil, "OVERLAY")
        s.arrow:SetJustifyH("CENTER")
    end
    s.frame:SetParent(parent); s.frame:EnableMouse(true)
    s.frame:Show(); s.label:Show(); s.arrow:Show()
    return s
end
local function ReleaseSection(s)
    s.frame:Hide(); s.frame:ClearAllPoints(); s.frame:SetScript("OnClick", nil)
    table.insert(secPool, s)
end

-- Item button pool
local itemPool = {}
-- Item buttons are SecureActionButtonTemplate parented to UIParent.
-- Never reparented or pooled - reparenting secure frames causes taint.
-- Created fresh each Refresh, hidden when not needed.
local allItemBtns = {}  -- all ever-created item buttons

local function AcquireItemBtn()
    -- Find a hidden button or create new one
    for _, b in ipairs(allItemBtns) do
        if not b:IsShown() then
            b._itemID = nil; b._logIdx = nil
            return b
        end
    end
    -- Create new secure button at UIParent level
    local b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "item")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93); b._icon = icon
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(); b._cd = cd
    b:SetScript("OnEnter", function(self)
        if self._itemID then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetItemByID(self._itemID); GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(allItemBtns, b)
    return b
end
local function ReleaseItemBtn(b)
    b:Hide(); b:ClearAllPoints()
    b._icon:SetTexture(nil)
    b:SetAttribute("item", nil)
end
local function ReleaseAllItems()
    for i = #EQT.itemBtns, 1, -1 do ReleaseItemBtn(EQT.itemBtns[i]); EQT.itemBtns[i] = nil end
end

-------------------------------------------------------------------------------
-- Misc helpers
-------------------------------------------------------------------------------
local function RemoveWatch(qID)
    if C_QuestLog and C_QuestLog.RemoveQuestWatch then C_QuestLog.RemoveQuestWatch(qID) end
end

local function GetQuestItem(qID)
    if not GetQuestLogSpecialItemInfo then return nil end
    local idx = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(qID)
    if not idx or idx == 0 then return nil end
    local name, tex, charges, _, t0, dur, _, _, _, itemID = GetQuestLogSpecialItemInfo(idx)
    if not name then return nil end
    return {itemID=itemID, logIdx=idx, name=name, texture=tex, charges=charges, startTime=t0, duration=dur}
end

local INTERNAL_TITLES = { ["Tracking Quest"]=true, [""]=true }
local function IsInternalTitle(t)
    if not t then return true end
    if INTERNAL_TITLES[t] then return true end
    if t:match("^Level %d+$") then return true end
    return false
end

local function BuildEntry(info, qID, list)
    local objs = {}
    local ot = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(qID)
    if ot then
        for _, o in ipairs(ot) do
            table.insert(objs, {
                text         = o.text or "",
                finished     = o.finished,
                objType      = o.type,
                numFulfilled = o.numFulfilled,
                numRequired  = o.numRequired,
            })
        end
    end
    table.insert(list, {
        index      = #list + 1,
        title      = (info and info.title) or ("Quest #"..qID),
        questID    = qID,
        objectives = objs,
        isComplete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(qID) or false,
        isFailed   = info and info.isFailed or false,
        isTask     = info and info.isTask or false,
    })
end

-------------------------------------------------------------------------------
-- GetScenarioSection
-- Returns a scenario entry when in a Delve/Scenario, with banner info and objectives.
local WIDGET_TYPE_DELVE_HEADER   = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.ScenarioHeaderDelves) or 29
local WIDGET_TYPE_SCENARIO_TIMER = 20
local WIDGET_TYPE_STATUSBAR      = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.StatusBar) or 2

local function GetScenarioSection()
    if not C_Scenario or not C_Scenario.IsInScenario then return nil end
    if not C_Scenario.IsInScenario() then return nil end

    -- Step info: stageName, numCriteria, widgetSetID (index 12)
    local ok, stageName, _, numCriteria, _, _, _, _, _, _, _, widgetSetID = pcall(C_Scenario.GetStepInfo)
    if not ok then return nil end

    -- Prefer C_ScenarioInfo widgetSetID (more reliable)
    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
        local si = C_ScenarioInfo.GetScenarioStepInfo()
        if si and si.widgetSetID and si.widgetSetID > 0 then
            widgetSetID = si.widgetSetID
        end
    end

    -- Scenario name
    local scenarioName
    local iOk, name = pcall(C_Scenario.GetInfo)
    if iOk and name and name ~= "" then scenarioName = name end

    -- Scan widget sets for Delve header (type 29) → banner info
    local bannerTitle, bannerIcon, bannerTier = nil, nil, nil
    local isDelve = C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress()

    local setsToScan = {}
    if widgetSetID and widgetSetID ~= 0 then setsToScan[#setsToScan+1] = widgetSetID end
    if C_UIWidgetManager and C_UIWidgetManager.GetObjectiveTrackerWidgetSetID then
        local otSet = C_UIWidgetManager.GetObjectiveTrackerWidgetSetID()
        if otSet and otSet ~= 0 and otSet ~= widgetSetID then setsToScan[#setsToScan+1] = otSet end
    end

    for _, setID in ipairs(setsToScan) do
        if C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID then
            local wOk, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
            if wOk and widgets then
                for _, w in ipairs(widgets) do
                    local wType = w.widgetType
                    local wID   = w.widgetID
                    -- Delve header widget
                    if wType == WIDGET_TYPE_DELVE_HEADER and
                       C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo then
                        local dOk, wi = pcall(C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo, wID)
                        if dOk and wi then
                            bannerTitle = (wi.headerText and wi.headerText ~= "") and wi.headerText or bannerTitle
                            bannerTier  = (wi.tierText   and wi.tierText   ~= "") and wi.tierText  or bannerTier
                            bannerIcon  = wi.atlasIcon or wi.icon or bannerIcon
                            isDelve = true
                        end
                    end
                end
            end
        end
        if bannerTitle then break end
    end

    -- Build display title
    local title
    if isDelve then
        title = bannerTitle or scenarioName or "Delve"
    elseif scenarioName and stageName and stageName ~= "" then
        title = scenarioName .. " — " .. stageName
    elseif stageName and stageName ~= "" then
        title = stageName
    else
        title = scenarioName or "Scenario"
    end

    -- Objectives from criteria
    local objectives = {}
    local seenText = {}
    local timerDuration, timerStartTime = nil, nil

    if C_ScenarioInfo then
        for i = 1, (numCriteria or 0) + 3 do
            local cOk, crit
            if C_ScenarioInfo.GetCriteriaInfoByStep then
                cOk, crit = pcall(C_ScenarioInfo.GetCriteriaInfoByStep, 1, i)
            end
            if (not cOk or not crit) and C_ScenarioInfo.GetCriteriaInfo then
                cOk, crit = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
            end
            if cOk and crit then
                -- Extract timer from criteria (duration/elapsed fields)
                if not timerDuration and crit.duration and crit.duration > 0 then
                    local elapsed = math.max(0, math.min(crit.elapsed or 0, crit.duration))
                    if elapsed < crit.duration then
                        timerDuration  = crit.duration
                        timerStartTime = GetTime() - elapsed
                    end
                end

                local desc = (crit.description and crit.description ~= "") and crit.description
                          or (crit.criteriaString and crit.criteriaString ~= "") and crit.criteriaString
                          or nil
                if desc then
                local numFulfilled = crit.quantity      or 0
                local numRequired  = crit.totalQuantity or 0

                local displayText
                if crit.isWeightedProgress then
                    -- quantity is 0-100 percentage
                    local pct = math.min(100, math.max(0, math.floor(numFulfilled)))
                    displayText = desc
                    if not seenText[displayText] then
                        seenText[displayText] = true
                        table.insert(objectives, {
                            text         = displayText,
                            finished     = crit.completed or false,
                            numFulfilled = pct,
                            numRequired  = 100,
                            objType      = "progressbar",
                        })
                    end
                elseif numRequired > 0 then
                    -- Only use quantityString prefix when it adds meaningful info (not just "0" or "1")
                    local qs = crit.quantityString
                    local useQS = qs and qs ~= "" and qs ~= "0" and qs ~= "1"
                    if useQS then
                        displayText = qs .. " " .. desc
                    else
                        displayText = string.format("%d/%d %s", numFulfilled, numRequired, desc)
                    end
                    if not seenText[displayText] then
                        seenText[displayText] = true
                        local isBar = numRequired > 1
                        table.insert(objectives, {
                            text         = displayText,
                            finished     = crit.completed or false,
                            numFulfilled = isBar and numFulfilled or nil,
                            numRequired  = isBar and numRequired  or nil,
                            objType      = isBar and "progressbar" or nil,
                        })
                    end
                else
                    displayText = desc
                    if not seenText[displayText] then
                        seenText[displayText] = true
                        table.insert(objectives, {
                            text     = displayText,
                            finished = crit.completed or false,
                        })
                    end
                end
                end -- if desc
            end
        end
    end

    -- Criteria timer fallback: widget timer
    if not timerDuration then
        local dur, start = GetQuestTimer(0) -- 0 = use scenario widget timer path
        -- Actually call widget timer directly
        for _, setID in ipairs(setsToScan) do
            if C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID then
                local wOk, wids = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
                if wOk and wids then
                    for _, w in ipairs(wids) do
                        if w.widgetType == WIDGET_TYPE_SCENARIO_TIMER and
                           C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo then
                            local ti = C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo(w.widgetID)
                            if ti and ti.shownState == 1 then
                                local tMin = ti.timerMin or 0
                                local duration = (ti.timerMax or 0) - tMin
                                local remaining = (ti.timerValue or 0) - tMin
                                if remaining > 0 and duration > 0 then
                                    timerDuration  = duration
                                    timerStartTime = GetTime() - (duration - remaining)
                                end
                            end
                        end
                    end
                end
            end
            if timerDuration then break end
        end
    end

    -- StatusBar widgets as progress objectives
    for _, setID in ipairs(setsToScan) do
        if C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID then
            local wOk, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
            if wOk and widgets then
                for _, w in ipairs(widgets) do
                    if w.widgetType == WIDGET_TYPE_STATUSBAR and
                       C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo then
                        local si = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(w.widgetID)
                        if si and si.barMax and si.barMax > 0 then
                            local text = (si.overrideBarText ~= "" and si.overrideBarText) or si.text or ""
                            if not seenText[text] then
                                seenText[text] = true
                                table.insert(objectives, {
                                    text         = text,
                                    finished     = false,
                                    numFulfilled = si.barValue,
                                    numRequired  = si.barMax,
                                    objType      = "progressbar",
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    if #objectives == 0 and title == "Scenario" then return nil end

    return {
        title          = title,
        objectives     = objectives,
        isDelve        = isDelve,
        bannerIcon     = bannerIcon,
        bannerTier     = bannerTier,
        timerDuration  = timerDuration,
        timerStartTime = timerStartTime,
    }
end

-- GetQuestLists
-------------------------------------------------------------------------------
local function GetQuestLists()
    local watched = {}
    local zone    = {}
    local world   = {}
    local seen    = {}

    if not C_QuestLog then return watched, zone, world end
    local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0

    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isInternalOnly then
            local qID = info.questID
            if qID and not seen[qID] then
                -- isTask quests may have isHidden=true in TWW – allow them through
                local skipHidden = info.isHidden and not info.isTask
                if not skipHidden then
                    local tracked = false
                    if C_QuestLog.GetQuestWatchType then
                        local wt = C_QuestLog.GetQuestWatchType(qID)
                        tracked = (wt ~= nil and wt ~= 0)
                    end
                    if not tracked and C_QuestLog.IsQuestWatched then
                        tracked = C_QuestLog.IsQuestWatched(qID) == true
                    end

                    if tracked then
                        -- If showZoneQuests is on, isOnMap quests go to zone (not watched)
                        -- so they appear in their own collapsible section
                        if Cfg("showZoneQuests") and info.isOnMap and not info.isTask then
                            seen[qID] = true
                            BuildEntry(info, qID, zone)
                        else
                            seen[qID] = true
                            BuildEntry(info, qID, watched)
                        end
                    elseif info.isTask then
                        if Cfg("showWorldQuests") and not IsInternalTitle(info.title) then
                            seen[qID] = true
                            BuildEntry(info, qID, world)
                        end
                    elseif info.isOnMap then
                        if Cfg("showZoneQuests") then
                            seen[qID] = true
                            BuildEntry(info, qID, zone)
                        end
                    end
                end
            end
        end
    end

    return watched, zone, world
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------
local PAD_H    = 8
local PAD_V    = 6
local HEADER_H = 20
local ROW_GAP  = 1
local SEC_GAP  = 4
local ITEM_PAD = 3
local BAR_H    = 9   -- progress bar height (doubled)
local BAR_PAD  = 2   -- gap between text and bar

function EQT:Refresh()
    local f = self.frame
    if not f then return end
    local content = f.content
    local width   = Cfg("width") or 220
    local tc      = Cfg("titleColor")
    local oc      = Cfg("objColor")
    local iqSize  = Cfg("questItemSize") or 22

    ReleaseAll(); ReleaseAllItems()
    for i = #self.sections, 1, -1 do ReleaseSection(self.sections[i]); self.sections[i] = nil end

    if f.bg then f.bg:SetColorTexture(0, 0, 0, Cfg("bgAlpha") or 0.35) end
    f:SetWidth(width)

    -- Update header "OBJECTIVES" text font/color
    if f.hdrTitle then
        local hfp, hfs, hff = HdrFont()
        SetFontSafe(f.hdrTitle, hfp, hfs, hff)
        local hc = Cfg("hdrColor") or C.header
        f.hdrTitle:SetTextColor(hc.r, hc.g, hc.b)
        ApplyShadow(f.hdrTitle, "hdrShadowColor", "hdrShadowOffset")
    end

    if f.collapsed then
        f:SetHeight(PAD_V + HEADER_H + PAD_V); content:SetHeight(1); return
    end

    local yOff = 0
    local sfp, sfs, sff = SecFont()
    local arrowSize = math.max(sfs + 4, 13)
    local arrowFont = SafeFont(GlobalFont())

    local function AddCollapsibleSection(label, isCollapsed, onToggle)
        local s = AcquireSection(content)
        SetFontSafe(s.label, sfp, sfs, sff)
        local sc = Cfg("secColor") or C.section
        s.label:SetTextColor(sc.r, sc.g, sc.b)
        ApplyShadow(s.label, "secShadowColor", "secShadowOffset")
        s.label:SetText(label)
        s.label:ClearAllPoints()
        s.label:SetPoint("LEFT",  s.frame, "LEFT",  0, 0)
        s.label:SetPoint("RIGHT", s.frame, "RIGHT", -(arrowSize + 4), 0)
        SetFontSafe(s.arrow, arrowFont, arrowSize, "OUTLINE")
        s.arrow:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
        s.arrow:SetText(isCollapsed and "+" or "-")
        s.arrow:ClearAllPoints()
        s.arrow:SetPoint("RIGHT", s.frame, "RIGHT", 0, 0)
        s.arrow:SetWidth(arrowSize + 4)
        local h = math.max(sfs + 6, arrowSize + 2)
        s.frame:SetHeight(h)
        s.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -yOff)
        s.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
        s.frame:SetScript("OnClick", onToggle)
        yOff = yOff + h + SEC_GAP
        table.insert(self.sections, s)
    end

    local function AddPlainSection(label)
        local s = AcquireSection(content)
        SetFontSafe(s.label, sfp, sfs, sff)
        local sc2 = Cfg("secColor") or C.section
        s.label:SetTextColor(sc2.r, sc2.g, sc2.b)
        s.label:SetText(label)
        s.label:ClearAllPoints()
        s.label:SetPoint("LEFT",  s.frame, "LEFT",  0, 0)
        s.label:SetPoint("RIGHT", s.frame, "RIGHT", 0, 0)
        SetFontSafe(s.arrow, sfp, sfs, sff); s.arrow:SetText("")
        s.frame:EnableMouse(false)
        local h = math.max(sfs + 6, 12)
        s.frame:SetHeight(h)
        s.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -yOff)
        s.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
        yOff = yOff + h + SEC_GAP
        table.insert(self.sections, s)
    end

    local tfp, tfs, tff = TitleFont()
    local ofp, ofs, off = ObjFont()

    -- Timer row: countdown text + shrinking bar
    local function AddTimerRow(questID, isAutoComplete, presetDuration, presetStartTime)
        local duration = presetDuration
        local startTime = presetStartTime
        if not duration or not startTime then
            duration, startTime = GetQuestTimer(questID)
        end
        if not duration or not startTime then return end

        local TIMER_BAR_H = BAR_H + 2
        local TEXT_H      = math.max(ofs, 10)
        local TOTAL_H     = TEXT_H + 4 + TIMER_BAR_H + 4

        local r = AcquireRow(content)
        r.frame:SetHeight(TOTAL_H)
        r.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -yOff)
        r.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)

        -- Countdown text
        SetFontSafe(r.text, ofp, TEXT_H, "OUTLINE")
        r.text:ClearAllPoints()
        r.text:SetPoint("TOPLEFT",  r.frame, "TOPLEFT",  14, 0)
        r.text:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT", -4, 0)
        r.text:SetHeight(TEXT_H + 2)
        r.text:Show()

        -- Timer bar background
        if r.barBg then r.barBg:Hide(); r.barBg = nil end
        r.barBg = r.frame:CreateTexture(nil, "BACKGROUND")
        r.barBg:SetColorTexture(C.barBg.r, C.barBg.g, C.barBg.b, 0.8)
        r.barBg:SetPoint("TOPLEFT",  r.frame, "TOPLEFT",  14, -(TEXT_H + 4))
        r.barBg:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT", -4, -(TEXT_H + 4))
        r.barBg:SetHeight(TIMER_BAR_H)
        r.barBg:Show()

        -- Timer bar fill
        if r.barFill then r.barFill:Hide(); r.barFill = nil end
        r.barFill = r.frame:CreateTexture(nil, "ARTWORK")
        r.barFill:SetColorTexture(C.timer.r, C.timer.g, C.timer.b, 0.85)
        r.barFill:SetPoint("TOPLEFT",    r.barBg, "TOPLEFT",    0, 0)
        r.barFill:SetPoint("BOTTOMLEFT", r.barBg, "BOTTOMLEFT", 0, 0)
        r.barFill:Show()

        local function UpdateTimer()
            if not r.text or not r.frame:IsShown() then return end
            local remaining = duration - (GetTime() - startTime)
            if remaining < 0 then remaining = 0 end
            -- Text
            r.text:SetText(FormatTimeLeft(remaining))
            if remaining < 30 then
                r.text:SetTextColor(C.timerLow.r, C.timerLow.g, C.timerLow.b)
                r.barFill:SetColorTexture(C.timerLow.r, C.timerLow.g, C.timerLow.b, 0.9)
            elseif remaining < 120 then
                r.text:SetTextColor(1, 0.9, 0.3)
                r.barFill:SetColorTexture(1, 0.9, 0.3, 0.85)
            else
                r.text:SetTextColor(C.timer.r, C.timer.g, C.timer.b)
                r.barFill:SetColorTexture(C.timer.r, C.timer.g, C.timer.b, 0.85)
            end
            -- Shrink bar proportionally
            local barW = r.barBg:GetWidth()
            if barW and barW > 0 then
                local pct = math.max(0, math.min(1, remaining / duration))
                r.barFill:SetWidth(math.max(1, barW * pct))
            end
        end
        UpdateTimer()

        yOff = yOff + TOTAL_H + ROW_GAP + 2
        table.insert(self.rows, r)
        r._updateTimer = UpdateTimer
        table.insert(self.timerRows, r)
    end

    -- Progress bar row
    local function AddProgressRow(cur, max)
        local r = AcquireRow(content)
        r.text:Hide()

        local pct = math.max(0, math.min(1, cur / max))
        local barW = (content:GetWidth() or width - PAD_H*2) - 14 - 30

        -- Background
        if not r.barBg then
            r.barBg = r.frame:CreateTexture(nil, "BACKGROUND")
        end
        r.barBg:SetColorTexture(C.barBg.r, C.barBg.g, C.barBg.b, 0.8)
        r.barBg:ClearAllPoints()
        r.barBg:SetPoint("TOPLEFT",  r.frame, "TOPLEFT",  14, -2)
        r.barBg:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT", -30, -2)
        r.barBg:SetHeight(BAR_H)
        r.barBg:Show()

        -- Fill
        if not r.barFill then
            r.barFill = r.frame:CreateTexture(nil, "ARTWORK")
        end
        r.barFill:SetColorTexture(C.barFill.r, C.barFill.g, C.barFill.b, 0.9)
        r.barFill:ClearAllPoints()
        r.barFill:SetPoint("TOPLEFT", r.barBg, "TOPLEFT", 0, 0)
        r.barFill:SetHeight(BAR_H)
        r.barFill:SetWidth(math.max(1, barW * pct))
        r.barFill:Show()

        -- Percentage text (always recreate - reparenting loses font state)
        if r.pctFS then r.pctFS:Hide(); r.pctFS = nil end
        r.pctFS = r.frame:CreateFontString(nil, "OVERLAY")
        SetFontSafe(r.pctFS, GlobalFont(), BAR_H + 2, "OUTLINE")
        r.pctFS:SetJustifyH("RIGHT")
        r.pctFS:SetJustifyV("MIDDLE")
        r.pctFS:SetTextColor(1, 1, 1)
        r.pctFS:SetText(math.floor(pct * 100 + 0.5).."%")
        r.pctFS:ClearAllPoints()
        r.pctFS:SetPoint("RIGHT",  r.frame,  "RIGHT",  0, 0)
        r.pctFS:SetPoint("TOP",    r.barBg,  "TOP",    0, 0)
        r.pctFS:SetPoint("BOTTOM", r.barBg,  "BOTTOM", 0, 0)
        r.pctFS:SetWidth(30)
        r.pctFS:Show()

        local rh = BAR_H + BAR_PAD * 2 + 2
        r.frame:SetHeight(rh)
        r.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -yOff)
        r.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
        yOff = yOff + rh + ROW_GAP
        table.insert(self.rows, r)
    end

    local function AddTitleRow(text, cr, cg, cb, qID)
        local r = AcquireRow(content)
        SetFontSafe(r.text, tfp, tfs, tff)
        r.text:SetTextColor(cr, cg, cb)
        ApplyShadow(r.text, "titleShadowColor", "titleShadowOffset")
        r.text:SetText(text)
        r.text:Show()
        local item = Cfg("showQuestItems") and qID and GetQuestItem(qID)
        local rightPad = item and (iqSize + ITEM_PAD * 2) or 0
        r.text:ClearAllPoints()
        r.text:SetPoint("TOPLEFT",  r.frame, "TOPLEFT",  4, 0)
        r.text:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT", -rightPad, 0)
        r.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -yOff)
        r.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
        local th = r.text:GetStringHeight()
        if th < tfs then th = tfs end
        local rh = math.max(th + 2, item and iqSize or 0)
        r.frame:SetHeight(rh); r.text:SetHeight(rh)
        if item then
            local btn = AcquireItemBtn()
            btn:SetSize(iqSize, iqSize)
            -- Anchor to r.frame but parented to UIParent - use SetPoint with explicit frame ref
            btn:SetPoint("RIGHT", r.frame, "RIGHT", -ITEM_PAD, 0)
            btn:SetFrameLevel(r.frame:GetFrameLevel() + 2)
            btn._icon:SetTexture(item.texture); btn._itemID = item.itemID; btn._logIdx = item.logIdx
            -- Set item attribute directly (we are outside combat at Refresh time)
            if not InCombatLockdown() then btn:SetAttribute("item", item.name) end
            if item.startTime and item.startTime > 0 and item.duration and item.duration > 0 then
                btn._cd:SetCooldown(item.startTime, item.duration); btn._cd:Show()
            else btn._cd:Hide() end
            if item.charges and item.charges > 0 then
                if not btn._chargeFS then
                    btn._chargeFS = btn:CreateFontString(nil, "OVERLAY")
                    SetFontSafe(btn._chargeFS, GlobalFont(), 9, "OUTLINE")
                    btn._chargeFS:SetTextColor(1,1,1)
                    btn._chargeFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 2)
                end
                btn._chargeFS:SetText(item.charges); btn._chargeFS:Show()
            elseif btn._chargeFS then btn._chargeFS:Hide() end
            table.insert(self.itemBtns, btn)
        end
        if qID then
            r.frame._questID = qID; r.frame:EnableMouse(true)
            r.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            r.frame:SetScript("OnClick", function(self, btn)
                if btn == "RightButton" then
                    RemoveWatch(qID); EQT.dirty = true
                else
                    -- TWW: open world map to quest details
                    if C_QuestLog.SetSelectedQuest then
                        C_QuestLog.SetSelectedQuest(qID)
                    end
                    if QuestMapFrame_OpenToQuestDetails then
                        QuestMapFrame_OpenToQuestDetails(qID)
                    elseif OpenQuestLog then
                        OpenQuestLog(qID)
                    elseif WorldMapFrame then
                        ShowUIPanel(WorldMapFrame)
                    end
                end
            end)
        end
        yOff = yOff + rh + ROW_GAP
        table.insert(self.rows, r)
    end

    local function AddObjRow(text, cr, cg, cb)
        local r = AcquireRow(content)
        SetFontSafe(r.text, ofp, ofs, off)
        r.text:SetTextColor(cr, cg, cb)
        ApplyShadow(r.text, "objShadowColor", "objShadowOffset")
        r.text:SetText(text)
        r.text:Show()
        r.text:ClearAllPoints()
        r.text:SetPoint("TOPLEFT",  r.frame, "TOPLEFT",  14, 0)
        r.text:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT",  0, 0)
        r.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -yOff)
        r.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
        local th = r.text:GetStringHeight()
        if th < ofs then th = ofs end
        local rh = th + 2; r.frame:SetHeight(rh); r.text:SetHeight(rh)
        yOff = yOff + rh + ROW_GAP
        table.insert(self.rows, r)
    end

    local function RenderList(list, startIdx)
        for i, q in ipairs(list) do
            local tr, tg, tb
            if q.isFailed then tr, tg, tb = C.failed.r, C.failed.g, C.failed.b
            elseif q.isComplete then tr, tg, tb = C.complete.r, C.complete.g, C.complete.b
            else tr, tg, tb = tc.r, tc.g, tc.b end
            AddTitleRow(((startIdx or 0)+i).."  "..q.title, tr, tg, tb, q.questID)

            -- Timer (for world/task quests)
            if q.isTask then
                AddTimerRow(q.questID)
            end

            -- Objectives
            for _, obj in ipairs(q.objectives) do
                if obj.objType == "progressbar" and obj.numRequired and obj.numRequired > 0 then
                    -- Show progress bar instead of text
                    AddProgressRow(obj.numFulfilled or 0, obj.numRequired)
                else
                    local cr = obj.finished and C.complete.r or oc.r
                    local cg = obj.finished and C.complete.g or oc.g
                    local cb = obj.finished and C.complete.b or oc.b
                    if obj.text and obj.text ~= "" then
                        AddObjRow(obj.text, cr, cg, cb)
                    end
                end
            end
            yOff = yOff + 3
        end
    end

    local watched, zone, world = GetQuestLists()
    local scenario = GetScenarioSection()

    -- Scenario / Delve section
    if scenario then
        if #watched > 0 or #zone > 0 or #world > 0 then yOff = yOff + 4 end

        -- Collapsible "DELVES" section header (only for delves, plain for other scenarios)
        local dc = false
        if scenario.isDelve then
            dc = Cfg("delveCollapsed") or false
            AddCollapsibleSection("DELVES", dc, function()
                DB().delveCollapsed = not Cfg("delveCollapsed"); EQT:Refresh()
            end)
        end

        if not dc then
        -- Delve banner: icon + title + tier badge
        if scenario.isDelve then
            local BANNER_H = 42
            local ICON_SIZE = 36
            local r = AcquireRow(content)
            r.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -yOff)
            r.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
            r.frame:SetHeight(BANNER_H)

            -- Dark background with subtle border
            if not r.bannerBg then
                r.bannerBg = r.frame:CreateTexture(nil, "BACKGROUND")
            end
            r.bannerBg:SetAllPoints()
            r.bannerBg:SetColorTexture(0.05, 0.04, 0.08, 0.8)
            r.bannerBg:Show()

            -- Accent border on left
            if not r.bannerAccent then
                r.bannerAccent = r.frame:CreateTexture(nil, "BORDER")
            end
            r.bannerAccent:SetWidth(2)
            r.bannerAccent:SetPoint("TOPLEFT",    r.frame, "TOPLEFT",  0, 0)
            r.bannerAccent:SetPoint("BOTTOMLEFT", r.frame, "BOTTOMLEFT", 0, 0)
            r.bannerAccent:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 0.9)
            r.bannerAccent:Show()

            -- Icon (large, right-aligned, slightly faded)
            if scenario.bannerIcon then
                if not r.bannerIcon then
                    r.bannerIcon = r.frame:CreateTexture(nil, "ARTWORK")
                    r.bannerIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                end
                r.bannerIcon:SetSize(ICON_SIZE, ICON_SIZE)
                r.bannerIcon:SetTexture(scenario.bannerIcon)
                r.bannerIcon:SetPoint("RIGHT", r.frame, "RIGHT", -6, 0)
                r.bannerIcon:SetAlpha(0.55)
                r.bannerIcon:Show()
            end

            -- Tier badge circle (top-right)
            if scenario.bannerTier then
                if not r.tierFS then
                    r.tierFS = r.frame:CreateFontString(nil, "OVERLAY")
                    r.tierFS:SetJustifyH("CENTER")
                end
                SetFontSafe(r.tierFS, GlobalFont(), tfs + 4, "OUTLINE")
                r.tierFS:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
                r.tierFS:SetText(scenario.bannerTier)
                r.tierFS:ClearAllPoints()
                r.tierFS:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT", -8, -6)
                r.tierFS:Show()
            end

            -- Title text (vertically centered in banner)
            local bc = Cfg("titleColor") or {r=1.0,g=0.82,b=0.0}
            local leftPad = 10
            SetFontSafe(r.text, tfp, tfs + 2, tff)
            r.text:SetTextColor(bc.r, bc.g, bc.b)
            r.text:SetText(scenario.title)
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT",  r.frame, "LEFT",  leftPad, 0)
            r.text:SetPoint("RIGHT", r.frame, "RIGHT", -(ICON_SIZE + 10), 0)
            r.text:SetJustifyV("MIDDLE")
            r.text:SetHeight(BANNER_H)
            r.text:Show()
            ApplyShadow(r.text, "titleShadowColor", "titleShadowOffset")

            yOff = yOff + BANNER_H + 6  -- extra gap below banner
            table.insert(self.rows, r)
        else
            AddPlainSection(scenario.title)
        end

        -- Timer row (if scenario has a countdown)
        if scenario.timerDuration and scenario.timerStartTime then
            AddTimerRow(nil, false, scenario.timerDuration, scenario.timerStartTime)
        end

        -- Objectives
        for _, obj in ipairs(scenario.objectives) do
            local cr = obj.finished and C.complete.r or oc.r
            local cg = obj.finished and C.complete.g or oc.g
            local cb = obj.finished and C.complete.b or oc.b
            if obj.objType == "progressbar" and obj.numRequired and obj.numRequired > 0 then
                AddProgressRow(obj.numFulfilled or 0, obj.numRequired)
                if obj.text and obj.text ~= "" then
                    AddObjRow(obj.text, cr, cg, cb)
                end
            else
                if obj.text and obj.text ~= "" then
                    AddObjRow(obj.text, cr, cg, cb)
                end
            end
        end
        end -- if not dc
    end

    -- Order: Delves (above) → Zone Quests → World Quests → Quests (bottom)
    local anyAbove = scenario ~= nil

    if Cfg("showZoneQuests") and #zone > 0 then
        if anyAbove then yOff = yOff + 4 end; anyAbove = true
        local zc = Cfg("zoneCollapsed") or false
        AddCollapsibleSection("ZONE QUESTS", zc, function()
            DB().zoneCollapsed = not Cfg("zoneCollapsed"); EQT:Refresh()
        end)
        if not zc then RenderList(zone, 0) end
    end
    if Cfg("showWorldQuests") and #world > 0 then
        if anyAbove then yOff = yOff + 4 end; anyAbove = true
        local wc = Cfg("worldCollapsed") or false
        AddCollapsibleSection("WORLD QUESTS", wc, function()
            DB().worldCollapsed = not Cfg("worldCollapsed"); EQT:Refresh()
        end)
        if not wc then RenderList(world, 0) end
    end
    if #watched > 0 then
        if anyAbove then yOff = yOff + 4 end
        local qc = Cfg("questsCollapsed") or false
        AddCollapsibleSection("QUESTS", qc, function()
            DB().questsCollapsed = not Cfg("questsCollapsed"); EQT:Refresh()
        end)
        if not qc then RenderList(watched, 0) end
    end
    if not scenario and #watched == 0 and #zone == 0 and #world == 0 then
        AddObjRow("No tracked quests.", oc.r, oc.g, oc.b)
    end

    content:SetHeight(math.max(yOff, 1))
    local totalH = PAD_V + HEADER_H + 4 + yOff + PAD_V
    if Cfg("fixedHeight") then
        f:SetHeight(Cfg("fixedHeightValue") or 300)
    else
        f:SetHeight(math.min(totalH, Cfg("maxHeight") or 600))
    end
    if f.sf then f.sf:SetVerticalScroll(0) end
end

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------
local function BuildFrame()
    local f = CreateFrame("Frame", "EUI_QuestTrackerFrame", UIParent)
    f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(false); f:SetMovable(true)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, Cfg("bgAlpha") or 0.35); f.bg = bg

    local topLine = f:CreateTexture(nil, "ARTWORK")
    topLine:SetHeight(1)
    topLine:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    topLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    topLine:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 0.7)
    if not Cfg("showTopLine") then topLine:Hide() end
    f.topLine = topLine

    local drag = CreateFrame("Frame", nil, f)
    drag:SetHeight(PAD_V + HEADER_H + PAD_V)
    drag:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    drag:SetFrameLevel(f:GetFrameLevel() + 20)
    drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        if not Cfg("locked") then f:StartMoving() end
    end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local uiH = UIParent:GetHeight()
        DB().xPos = f:GetLeft(); DB().yPos = f:GetTop() - uiH
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", DB().xPos, DB().yPos + uiH)
    end)

    local hdrTitle = drag:CreateFontString(nil, "OVERLAY")
    local hfp, hfs, hff = HdrFont()
    SetFontSafe(hdrTitle, hfp, hfs, hff)
    local hc = Cfg("hdrColor") or C.header
    hdrTitle:SetTextColor(hc.r, hc.g, hc.b)
    ApplyShadow(hdrTitle, "hdrShadowColor", "hdrShadowOffset")
    f.hdrTitle = hdrTitle
    hdrTitle:SetJustifyH("LEFT")
    hdrTitle:SetPoint("LEFT",  drag, "LEFT",  PAD_H, 0)
    hdrTitle:SetPoint("RIGHT", drag, "RIGHT", -28, 0)
    hdrTitle:SetHeight(HEADER_H)
    hdrTitle:SetText("OBJECTIVES")

    local colBtn = CreateFrame("Button", nil, f)
    colBtn:SetSize(22, 22)
    colBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD_H + 2, -PAD_V + 1)
    colBtn:SetFrameLevel(drag:GetFrameLevel() + 5)
    local colFS = colBtn:CreateFontString(nil, "OVERLAY")
    SetFontSafe(colFS, GlobalFont(), 16, "OUTLINE")
    colFS:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
    colFS:SetAllPoints(); colFS:SetText("-")
    f.collapsed = false
    colBtn:SetScript("OnClick", function()
        f.collapsed = not f.collapsed
        colFS:SetText(f.collapsed and "+" or "-")
        EQT:Refresh()
    end)

    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD_H, -(PAD_V + HEADER_H + 1))
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD_H, -(PAD_V + HEADER_H + 1))
    sep:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 0.25)

    local sf = CreateFrame("ScrollFrame", "EUI_QuestTrackerScroll", f)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     PAD_H, -(PAD_V + HEADER_H + 4))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD_H, PAD_V)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local new = math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta*28))
        self:SetVerticalScroll(new)
    end)
    f.sf = sf

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(math.max(10, (Cfg("width") or 220) - PAD_H*2))
    content:SetHeight(1)
    sf:SetScrollChild(content); f.content = content

    f:HookScript("OnSizeChanged", function(self, w)
        local cw = math.max(10, w - PAD_H*2)
        content:SetWidth(cw); sf:SetWidth(cw)
    end)
    return f
end

-------------------------------------------------------------------------------
-- Position / Slash / Init / Load
-------------------------------------------------------------------------------
function EQT:ApplyPosition()
    local f = self.frame; if not f then return end
    f:ClearAllPoints()
    local x, y = DB().xPos, DB().yPos
    if x and y then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y + UIParent:GetHeight())
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -200)
    end
end

local function RegisterSlash()
    SLASH_EUIQUEST1 = "/euiqt"
    SlashCmdList["EUIQUEST"] = function(msg)
        msg = strtrim(msg or ""):lower()
        if msg == "" or msg == "toggle" then
            local f = EQT.frame
            if f then if f:IsShown() then f:Hide() else f:Show(); EQT:Refresh() end end
        elseif msg == "lock" then
            DB().locked = not DB().locked
            print("|cff0cd29fEUI Quest Tracker:|r "..(Cfg("locked") and "Locked." or "Unlocked."))
        elseif msg == "reset" then
            DB().xPos = nil; DB().yPos = nil; EQT:ApplyPosition()
        end
    end
end

function EQT:Init()
    DB()
    EQT.sections  = EQT.sections  or {}
    EQT.itemBtns  = EQT.itemBtns  or {}
    EQT.timerRows = EQT.timerRows or {}
    if not Cfg("enabled") then return end
    self.frame = BuildFrame()
    self.frame:SetWidth(Cfg("width") or 220)
    self.frame:SetHeight(60)
    self:ApplyPosition()

    -- Hide/show Blizzard ObjectiveTrackerFrame based on setting
    local function ApplyBlizzardTrackerVisibility()
        local ot = _G.ObjectiveTrackerFrame
        if not ot then return end
        if Cfg("hideBlizzardTracker") and Cfg("enabled") ~= false then
            ot:SetAlpha(0)
            ot:EnableMouse(false)
        else
            ot:SetAlpha(1)
            ot:EnableMouse(true)
        end
    end
    EQT.ApplyBlizzardTrackerVisibility = ApplyBlizzardTrackerVisibility
    -- Also hook Show so Blizzard can't restore it while we want it hidden
    local ot = _G.ObjectiveTrackerFrame
    if ot then
        hooksecurefunc(ot, "Show", function()
            if Cfg("hideBlizzardTracker") and Cfg("enabled") ~= false then
                ot:SetAlpha(0)
                ot:EnableMouse(false)
            end
        end)
    end
    C_Timer.After(1, ApplyBlizzardTrackerVisibility)

    local w = CreateFrame("Frame")
    for _, ev in ipairs({
        "QUEST_LOG_UPDATE","QUEST_ACCEPTED","QUEST_REMOVED","QUEST_TURNED_IN",
        "PLAYER_ENTERING_WORLD","UNIT_QUEST_LOG_CHANGED",
    }) do w:RegisterEvent(ev) end
    pcall(function() w:RegisterEvent("QUEST_WATCH_LIST_CHANGED") end)
    pcall(function() w:RegisterEvent("QUEST_WATCH_UPDATE") end)
    pcall(function() w:RegisterEvent("QUEST_TASK_PROGRESS_UPDATE") end)
    pcall(function() w:RegisterEvent("TASK_IS_TOO_DIFFERENT") end)
    pcall(function() w:RegisterEvent("SCENARIO_CRITERIA_UPDATE") end)
    pcall(function() w:RegisterEvent("SCENARIO_UPDATE") end)
    pcall(function() w:RegisterEvent("UI_WIDGET_UNIT_CHANGED") end)

    local zoneFrame = CreateFrame("Frame")
    for _, ev in ipairs({"ZONE_CHANGED_NEW_AREA","ZONE_CHANGED"}) do
        zoneFrame:RegisterEvent(ev)
    end
    zoneFrame:SetScript("OnEvent", function()
        C_Timer.After(0.5,  function() EQT.dirty = true end)
        C_Timer.After(1.5,  function() EQT.dirty = true end)
        C_Timer.After(3.0,  function() EQT.dirty = true end)
        C_Timer.After(5.0,  function() EQT.dirty = true end)
    end)

    w:SetScript("OnEvent", function()
        EQT.dirty = true
        if EQT.UpdateQuestItemAttribute then EQT.UpdateQuestItemAttribute() end
    end)

    -------------------------------------------------------------------------------
    -- Auto Accept / Auto Turn-in
    -------------------------------------------------------------------------------
    local autoFrame = CreateFrame("Frame")
    -- QUEST_DETAIL: fires when a quest offer is shown to the player (NPC or item)
    -- QUEST_COMPLETE: fires when the turn-in dialog opens
    -- QUEST_ACCEPTED: fires after quest is accepted (used to confirm, not trigger)
    autoFrame:RegisterEvent("QUEST_DETAIL")
    autoFrame:RegisterEvent("QUEST_COMPLETE")
    autoFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "QUEST_DETAIL" then
            if not Cfg("autoAccept") then return end
            -- AcceptQuest() works immediately on QUEST_DETAIL in TWW
            -- No delay needed – the event fires exactly when the offer is ready
            AcceptQuest()
        elseif event == "QUEST_COMPLETE" then
            if not Cfg("autoTurnIn") then return end
            -- Skip auto turn-in if Shift is held (allows reading rewards)
            if Cfg("autoTurnInShiftSkip") and IsShiftKeyDown() then return end
            -- CompleteQuest() submits the turn-in
            CompleteQuest()
        end
    end)

    local elapsed = 0
    local timerElapsed = 0
    self.frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.3 and EQT.dirty then
            elapsed = 0; EQT.dirty = false; EQT:Refresh()
        end
        -- Update active timers every second
        timerElapsed = timerElapsed + dt
        if timerElapsed >= 1.0 then
            timerElapsed = 0
            for _, r in ipairs(EQT.timerRows) do
                if r._updateTimer then r._updateTimer() end
            end
        end
    end)
    RegisterSlash()
    C_Timer.After(1.5, function() EQT.dirty = true end)

    -------------------------------------------------------------------------------
    -- Quest item hotkey using SecureHandlerAttributeTemplate pattern (no taint)
    -- _onattributechanged runs in the secure environment and calls SetBindingClick
    -- The binding name 'EUI_QUESTITEM' is set via SetBinding/SaveBinding in options
    -------------------------------------------------------------------------------
    local qItemBtn = CreateFrame("Button", "EUI_QuestItemHotkeyBtn", UIParent,
        "SecureActionButtonTemplate, SecureHandlerAttributeTemplate")
    qItemBtn:SetSize(32, 32)
    qItemBtn:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    qItemBtn:SetAlpha(0)
    qItemBtn:EnableMouse(false)
    qItemBtn:RegisterForClicks("LeftButtonUp")
    qItemBtn:SetAttribute("type", "item")

    -- This runs entirely in the secure environment - no taint possible
    -- When item attribute changes, it updates the key binding internally
    qItemBtn:SetAttribute("_onattributechanged", [[
        if name == 'item' then
            self:ClearBindings()
            if value then
                local key1, key2 = GetBindingKey('EUI_QUESTITEM')
                if key1 then self:SetBindingClick(false, key1, self, 'LeftButton') end
                if key2 then self:SetBindingClick(false, key2, self, 'LeftButton') end
            end
        end
    ]])

    EQT.qItemBtn = qItemBtn

    -- Set the WoW binding so GetBindingKey('EUI_QUESTITEM') works
    -- This uses SaveBindings which is the standard API
    local function ApplyQuestItemHotkey()
        if InCombatLockdown() then return end
        local key = Cfg("questItemHotkey")
        -- Clear old binding
        local old1, old2 = GetBindingKey("EUI_QUESTITEM")
        if old1 then SetBinding(old1) end
        if old2 then SetBinding(old2) end
        -- Apply new binding
        if key and key ~= "" then
            SetBinding(key, "EUI_QUESTITEM")
        end
        SaveBindings(GetCurrentBindingSet())
        -- Trigger attribute handler to re-register click binding
        if not InCombatLockdown() then
            local cur = qItemBtn:GetAttribute("item")
            qItemBtn:SetAttribute("item", nil)
            qItemBtn:SetAttribute("item", cur)
        end
    end
    EQT.ApplyQuestItemHotkey = ApplyQuestItemHotkey

    -- Register the binding name globally so WoW knows about it
    _G["BINDING_NAME_EUI_QUESTITEM"] = "Use Quest Item"

    local function UpdateQuestItemAttribute()
        if InCombatLockdown() then return end
        local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
        for pass = 1, 3 do
            for i = 1, n do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and not info.isInternalOnly then
                    local qID = info.questID
                    local wt = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(qID)
                    local isRelevant = (pass == 1 and wt ~= nil and wt ~= 0)
                        or (pass == 2 and info.isOnMap and not info.isTask)
                        or (pass == 3 and info.isTask)
                    if isRelevant and not (info.isHidden and not info.isTask) then
                        local item = GetQuestItem(qID)
                        if item and item.name then
                            qItemBtn:SetAttribute("item", item.name)
                            return
                        end
                    end
                end
            end
        end
        qItemBtn:SetAttribute("item", nil)
    end
    EQT.UpdateQuestItemAttribute = UpdateQuestItemAttribute

    local qItemFrame = CreateFrame("Frame")
    qItemFrame:RegisterEvent("QUEST_LOG_UPDATE")
    qItemFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    qItemFrame:RegisterEvent("ZONE_CHANGED")
    qItemFrame:RegisterEvent("UPDATE_BINDINGS")
    qItemFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    qItemFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" or event == "UPDATE_BINDINGS" then
            ApplyQuestItemHotkey()
        end
        UpdateQuestItemAttribute()
    end)

    C_Timer.After(1.5, function()
        ApplyQuestItemHotkey()
        UpdateQuestItemAttribute()
    end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loaded)
    if loaded ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    C_Timer.After(0.1, function() EQT:Init() end)
end)
