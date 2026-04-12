-------------------------------------------------------------------------------
--  EllesmereUIMythicTimer.lua  —  M+ Timer overlay for EllesmereUI
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EMT = EllesmereUI.Lite.NewAddon(ADDON_NAME)

-- Upvalues
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local format = string.format
local GetWorldElapsedTime = GetWorldElapsedTime
local GetTimePreciseSec = GetTimePreciseSec
local wipe = wipe

-- Constants
local PLUS_TWO_RATIO   = 0.8
local PLUS_THREE_RATIO = 0.6
local CHALLENGERS_PERIL_AFFIX_ID = 152

local COMPARE_NONE = "NONE"
local COMPARE_DUNGEON = "DUNGEON"
local COMPARE_LEVEL = "LEVEL"
local COMPARE_LEVEL_AFFIX = "LEVEL_AFFIX"
local COMPARE_RUN = "RUN"

local function CopyTable(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for key, value in pairs(src) do
        out[key] = type(value) == "table" and CopyTable(value) or value
    end
    return out
end

local PRESET_ORDER = {
    "CUSTOM",
    "ELLESMERE",
    "WARP_DEPLETE",
    "MYTHIC_PLUS_TIMER",
}

local PRESET_LABELS = {
    CUSTOM = "Custom",
    ELLESMERE = "EllesmereUI",
    WARP_DEPLETE = "Warp Deplete",
    MYTHIC_PLUS_TIMER = "MythicPlusTimer",
}

local PRESET_VALUES = {
    ELLESMERE = {
        showAffixes = true,
        showPlusTwoTimer = true,
        showPlusThreeTimer = true,
        showPlusTwoBar = true,
        showPlusThreeBar = true,
        showDeaths = true,
        showObjectives = true,
        showObjectiveTimes = true,
        showEnemyBar = true,
        showEnemyText = true,
        objectiveAlign = "LEFT",
        timerAlign = "CENTER",
        titleAlign = "CENTER",
        standaloneAlpha = 0.85,
        showAccent = false,
        enemyForcesPos = "BOTTOM",
        enemyForcesPctPos = "LABEL",
        deathsInTitle = false,
        deathTimeInTitle = false,
        deathAlign = "LEFT",
        timerInBar = false,
        showTimerBar = true,
        showTimerBreakdown = false,
        affixDisplayMode = "TEXT",
        enemyForcesTextFormat = "PERCENT",
        objectiveTimePosition = "END",
        showCompletedMilliseconds = true,
        objectiveCompareMode = COMPARE_NONE,
        objectiveCompareDeltaOnly = false,
        showUpcomingSplitTargets = false,
        enemyBarColorMode = "PROGRESS",
        enemyBarSolidColor = { r = 0.35, g = 0.55, b = 0.8 },
        frameWidth = 260,
        barWidth = 220,
        timerBarHeight = 10,
        enemyBarHeight = 6,
        rowGap = 6,
        objectiveGap = 3,
        timerRunningColor = { r = 1, g = 1, b = 1 },
        timerWarningColor = { r = 0.9, g = 0.7, b = 0.2 },
        timerExpiredColor = { r = 0.9, g = 0.2, b = 0.2 },
        timerPlusTwoColor = { r = 0.4, g = 1, b = 0.4 },
        timerPlusThreeColor = { r = 0.3, g = 0.8, b = 1 },
        timerBarPastPlusThreeColor = { r = 0.3, g = 0.8, b = 1 },
        timerBarPastPlusTwoColor = { r = 0.4, g = 1, b = 0.4 },
        objectiveTextColor = { r = 0.9, g = 0.9, b = 0.9 },
        objectiveCompletedColor = { r = 0.3, g = 0.8, b = 0.3 },
        splitFasterColor = { r = 0.4, g = 1, b = 0.4 },
        splitSlowerColor = { r = 1, g = 0.45, b = 0.45 },
        deathTextColor = { r = 0.93, g = 0.33, b = 0.33 },
        enemy0to25Color = { r = 0.9, g = 0.25, b = 0.25 },
        enemy25to50Color = { r = 0.95, g = 0.6, b = 0.2 },
        enemy50to75Color = { r = 0.95, g = 0.85, b = 0.2 },
        enemy75to100Color = { r = 0.3, g = 0.8, b = 0.3 },
    },
    WARP_DEPLETE = {
        showAffixes = true,
        showPlusTwoTimer = true,
        showPlusThreeTimer = true,
        showPlusTwoBar = true,
        showPlusThreeBar = true,
        showDeaths = true,
        showObjectives = true,
        showObjectiveTimes = true,
        showEnemyBar = true,
        showEnemyText = true,
        objectiveAlign = "RIGHT",
        timerAlign = "RIGHT",
        titleAlign = "RIGHT",
        standaloneAlpha = 0.9,
        showAccent = false,
        enemyForcesPos = "UNDER_BAR",
        enemyForcesPctPos = "BAR",
        deathsInTitle = false,
        deathTimeInTitle = false,
        deathAlign = "RIGHT",
        timerInBar = false,
        showTimerBar = true,
        showTimerBreakdown = false,
        affixDisplayMode = "TEXT",
        enemyForcesTextFormat = "PERCENT",
        objectiveTimePosition = "START",
        showCompletedMilliseconds = true,
        objectiveCompareMode = COMPARE_DUNGEON,
        objectiveCompareDeltaOnly = false,
        showUpcomingSplitTargets = true,
        enemyBarColorMode = "SOLID",
        enemyBarSolidColor = { r = 0.73, g = 0.62, b = 0.13 },
        timerBarPastPlusThreeColor = { r = 0.3, g = 0.8, b = 1 },
        timerBarPastPlusTwoColor = { r = 0.4, g = 1, b = 0.4 },
        enemy0to25Color = { r = 0.9, g = 0.25, b = 0.25 },
        enemy25to50Color = { r = 0.95, g = 0.6, b = 0.2 },
        enemy50to75Color = { r = 0.95, g = 0.85, b = 0.2 },
        enemy75to100Color = { r = 0.3, g = 0.8, b = 0.3 },
    },
    MYTHIC_PLUS_TIMER = {
        showAffixes = true,
        showPlusTwoTimer = true,
        showPlusThreeTimer = true,
        showPlusTwoBar = false,
        showPlusThreeBar = false,
        showDeaths = true,
        showObjectives = true,
        showObjectiveTimes = true,
        showEnemyBar = true,
        showEnemyText = false,
        objectiveAlign = "LEFT",
        timerAlign = "LEFT",
        titleAlign = "LEFT",
        standaloneAlpha = 0.85,
        showAccent = false,
        enemyForcesPos = "BOTTOM",
        enemyForcesPctPos = "BAR",
        deathsInTitle = false,
        deathTimeInTitle = false,
        deathAlign = "LEFT",
        timerInBar = false,
        showTimerBar = false,
        showTimerBreakdown = true,
        affixDisplayMode = "TEXT",
        enemyForcesTextFormat = "PERCENT",
        objectiveTimePosition = "END",
        showCompletedMilliseconds = false,
        objectiveCompareMode = COMPARE_LEVEL_AFFIX,
        objectiveCompareDeltaOnly = false,
        showUpcomingSplitTargets = false,
        enemyBarColorMode = "PROGRESS",
        enemyBarSolidColor = { r = 0.35, g = 0.55, b = 0.8 },
        timerBarPastPlusThreeColor = { r = 0.3, g = 0.8, b = 1 },
        timerBarPastPlusTwoColor = { r = 0.4, g = 1, b = 0.4 },
        enemy0to25Color = { r = 0.8, g = 0.4, b = 0.4 },
        enemy25to50Color = { r = 0.8, g = 0.6, b = 0.3 },
        enemy50to75Color = { r = 0.7, g = 0.75, b = 0.3 },
        enemy75to100Color = { r = 0.4, g = 0.8, b = 0.4 },
    },
}

local function ApplyPresetToProfile(profile, presetID)
    local preset = PRESET_VALUES[presetID]
    if not profile or not preset then return false end

    for key, value in pairs(preset) do
        profile[key] = type(value) == "table" and CopyTable(value) or value
    end

    profile.selectedPreset = presetID
    return true
end

local function GetPresetValues()
    local values = {}
    for _, presetID in ipairs(PRESET_ORDER) do
        values[presetID] = PRESET_LABELS[presetID] or presetID
    end
    return values, PRESET_ORDER
end

local function CalculateBonusTimers(maxTime, affixes)
    local plusTwoT = (maxTime or 0) * PLUS_TWO_RATIO
    local plusThreeT = (maxTime or 0) * PLUS_THREE_RATIO

    if not maxTime or maxTime <= 0 then
        return plusTwoT, plusThreeT
    end

    if affixes then
        for _, affixID in ipairs(affixes) do
            if affixID == CHALLENGERS_PERIL_AFFIX_ID then
                local oldTimer = maxTime - 90
                if oldTimer > 0 then
                    plusTwoT = oldTimer * PLUS_TWO_RATIO + 90
                    plusThreeT = oldTimer * PLUS_THREE_RATIO + 90
                end
                break
            end
        end
    end

    return plusTwoT, plusThreeT
end

-- Database defaults
local DB_DEFAULTS = {
    profile = {
        enabled           = true,
        showAffixes       = true,
        showPlusTwoTimer  = true,
        showPlusThreeTimer = true,
        showPlusTwoBar    = true,
        showPlusThreeBar  = true,
        showDeaths        = true,
        showObjectives    = true,
        showObjectiveTimes = true,
        showEnemyBar      = true,
        showEnemyText     = true,
        objectiveAlign    = "LEFT",
        timerAlign        = "CENTER",
        titleAlign        = "CENTER",
        scale             = 1.0,
        standaloneAlpha   = 0.85,
        showAccent        = false,
        showPreview       = false,
        enemyForcesPos    = "BOTTOM",
        enemyForcesPctPos = "LABEL",
        deathsInTitle     = false,
        deathTimeInTitle  = false,
        deathAlign        = "LEFT",
        timerInBar        = false,
        showTimerBar      = true,
        showTimerBreakdown = false,
        affixDisplayMode  = "TEXT",
        enemyForcesTextFormat = "PERCENT",
        objectiveTimePosition = "END",
        showCompletedMilliseconds = true,
        objectiveCompareMode = "NONE",
        objectiveCompareDeltaOnly = false,
        showUpcomingSplitTargets = false,
        frameWidth        = 260,
        barWidth          = 220,
        timerBarHeight    = 10,
        enemyBarHeight    = 6,
        rowGap            = 6,
        objectiveGap      = 3,
        timerRunningColor = { r = 1, g = 1, b = 1 },
        timerWarningColor = { r = 0.9, g = 0.7, b = 0.2 },
        timerExpiredColor = { r = 0.9, g = 0.2, b = 0.2 },
        timerPlusTwoColor = { r = 0.4, g = 1, b = 0.4 },
        timerPlusThreeColor = { r = 0.3, g = 0.8, b = 1 },
        timerBarPastPlusThreeColor = { r = 0.3, g = 0.8, b = 1 },
        timerBarPastPlusTwoColor = { r = 0.4, g = 1, b = 0.4 },
        objectiveTextColor = { r = 0.9, g = 0.9, b = 0.9 },
        objectiveCompletedColor = { r = 0.3, g = 0.8, b = 0.3 },
        splitFasterColor  = { r = 0.4, g = 1, b = 0.4 },
        splitSlowerColor  = { r = 1, g = 0.45, b = 0.45 },
        deathTextColor    = { r = 0.93, g = 0.33, b = 0.33 },
        enemy0to25Color   = { r = 0.9, g = 0.25, b = 0.25 },
        enemy25to50Color  = { r = 0.95, g = 0.6, b = 0.2 },
        enemy50to75Color  = { r = 0.95, g = 0.85, b = 0.2 },
        enemy75to100Color = { r = 0.3, g = 0.8, b = 0.3 },
        enemyBarColorMode = "PROGRESS",
        enemyBarSolidColor = { r = 0.35, g = 0.55, b = 0.8 },
        fontPath          = nil,
        advancedMode      = false,
        selectedPreset    = "ELLESMERE",
    },
}

-- State
local db
local updateTicker
local currentRun = {
    active        = false,
    mapID         = nil,
    mapName       = "",
    level         = 0,
    affixes       = {},
    maxTime       = 0,
    elapsed       = 0,
    completed     = false,
    deaths        = 0,
    deathTimeLost = 0,
    objectives    = {},
}

-- Helpers
local function FormatTime(seconds, withMilliseconds)
    if not seconds or seconds < 0 then seconds = 0 end
    local whole = floor(seconds)
    local m = floor(whole / 60)
    local s = floor(whole % 60)
    if withMilliseconds then
        local ms = floor(((seconds - whole) * 1000) + 0.5)
        if ms >= 1000 then
            whole = whole + 1
            m = floor(whole / 60)
            s = floor(whole % 60)
            ms = 0
        end
        return format("%d:%02d.%03d", m, s, ms)
    end
    return format("%d:%02d", m, s)
end

local function RoundToInt(value)
    if not value then return 0 end
    return floor(value + 0.5)
end

local function GetColor(tbl, fallbackR, fallbackG, fallbackB)
    if tbl then
        return tbl.r or fallbackR, tbl.g or fallbackG, tbl.b or fallbackB
    end
    return fallbackR, fallbackG, fallbackB
end

local function GetEnemyForcesColor(profile, percent)
    local pct = min(100, max(0, percent or 0))

    if pct >= 75 then
        return GetColor(profile and profile.enemy75to100Color, 0.3, 0.8, 0.3)
    elseif pct >= 50 then
        return GetColor(profile and profile.enemy50to75Color, 0.95, 0.85, 0.2)
    elseif pct >= 25 then
        return GetColor(profile and profile.enemy25to50Color, 0.95, 0.6, 0.2)
    end

    return GetColor(profile and profile.enemy0to25Color, 0.9, 0.25, 0.25)
end

local function GetTimerBarFillColor(profile, elapsed, plusThreeTime, plusTwoTime, maxTime)
    if maxTime and maxTime > 0 then
        if elapsed > maxTime then
            return GetColor(profile and profile.timerExpiredColor, 0.9, 0.2, 0.2)
        elseif elapsed > plusTwoTime then
            return GetColor(profile and profile.timerBarPastPlusTwoColor, 0.4, 1, 0.4)
        elseif elapsed > plusThreeTime then
            return GetColor(profile and profile.timerBarPastPlusThreeColor, 0.3, 0.8, 1)
        end
    end

    return GetColor(profile and profile.timerRunningColor, 1, 1, 1)
end

local function NormalizeAffixKey(affixes)
    local ids = {}
    for _, affixID in ipairs(affixes or {}) do
        ids[#ids + 1] = affixID
    end
    table.sort(ids)
    return table.concat(ids, "-")
end

local function GetScopeKey(run, mode)
    if not run or not run.mapID then return nil end

    if mode == COMPARE_DUNGEON then
        return tostring(run.mapID)
    elseif mode == COMPARE_LEVEL then
        return format("%s:%d", run.mapID, run.level or 0)
    elseif mode == COMPARE_LEVEL_AFFIX or mode == COMPARE_RUN then
        return format("%s:%d:%s", run.mapID, run.level or 0, NormalizeAffixKey(run.affixes))
    end

    return nil
end

local function EnsureProfileStore(key)
    if not db or not db.profile then return nil end
    if not db.profile[key] then db.profile[key] = {} end
    return db.profile[key]
end

local function GetReferenceObjectiveTime(run, objectiveIndex, mode)
    if mode == COMPARE_NONE then return nil end
    if mode == COMPARE_RUN then
        local bestRuns = EnsureProfileStore("bestRuns")
        local scopeKey = GetScopeKey(run, COMPARE_RUN)
        local bestRun = bestRuns and bestRuns[scopeKey]
        return bestRun and bestRun.objectiveTimes and bestRun.objectiveTimes[objectiveIndex] or nil
    end

    local store = EnsureProfileStore("bestObjectiveSplits")
    local scopeKey = GetScopeKey(run, mode)
    local scope = store and scopeKey and store[scopeKey]
    return scope and scope[objectiveIndex] or nil
end

local function UpdateBestObjectiveSplits(run, objectiveIndex, elapsed)
    local store = EnsureProfileStore("bestObjectiveSplits")
    if not store then return end

    for _, mode in ipairs({ COMPARE_DUNGEON, COMPARE_LEVEL, COMPARE_LEVEL_AFFIX }) do
        local scopeKey = GetScopeKey(run, mode)
        if scopeKey then
            if not store[scopeKey] then store[scopeKey] = {} end
            local previous = store[scopeKey][objectiveIndex]
            if not previous or elapsed < previous then
                store[scopeKey][objectiveIndex] = elapsed
            end
        end
    end
end

local function UpdateObjectiveCompletion(obj, objectiveIndex)
    if not db or not db.profile or not obj or not obj.elapsed or obj.elapsed <= 0 then return end

    local compareMode = db.profile.objectiveCompareMode or COMPARE_NONE
    local reference = GetReferenceObjectiveTime(currentRun, objectiveIndex, compareMode)
    obj.referenceElapsed = reference
    obj.compareDelta = reference and (obj.elapsed - reference) or nil
    obj.isNewBest = reference == nil or obj.elapsed < reference

    UpdateBestObjectiveSplits(currentRun, objectiveIndex, obj.elapsed)
end

local function UpdateBestRun(run)
    local bestRuns = EnsureProfileStore("bestRuns")
    if not bestRuns then return end

    local scopeKey = GetScopeKey(run, COMPARE_RUN)
    if not scopeKey then return end

    local existing = bestRuns[scopeKey]
    local objectiveTimes = {}
    local objectiveNames = {}
    local enemyForcesTime = nil
    for index, objective in ipairs(run.objectives) do
        if objective.elapsed and objective.elapsed > 0 then
            if objective.isWeighted then
                enemyForcesTime = objective.elapsed
            else
                objectiveTimes[index] = objective.elapsed
            end
            objectiveNames[index] = objective.name
        end
    end

    if not existing or not existing.elapsed or run.elapsed < existing.elapsed then
        bestRuns[scopeKey] = {
            elapsed = run.elapsed,
            objectiveTimes = objectiveTimes,
            objectiveNames = objectiveNames,
            enemyForcesTime = enemyForcesTime,
            mapID = run.mapID,
            mapName = run.mapName,
            level = run.level,
            affixes = run.affixes,
            deaths = run.deaths,
            deathTimeLost = run.deathTimeLost,
            date = time(),
        }
    end
end

local function BuildSplitCompareText(referenceTime, currentTime, deltaOnly, fasterColor, slowerColor)
    if not referenceTime or not currentTime then return "" end

    local diff = currentTime - referenceTime
    local color = diff <= 0 and fasterColor or slowerColor
    local cR, cG, cB = GetColor(color, 0.4, 1, 0.4)
    local diffPrefix = diff < 0 and "-" or "+"
    local diffText = diff == 0 and "0:00" or FormatTime(abs(diff))
    local colorHex = format("|cff%02x%02x%02x", floor(cR * 255), floor(cG * 255), floor(cB * 255))

    if deltaOnly then
        return format("  %s(%s%s)|r", colorHex, diffPrefix, diffText)
    end

    return format("  |cff888888(%s, %s%s%s)|r", FormatTime(referenceTime), colorHex, diffPrefix, diffText)
end

local function FormatEnemyForcesText(enemyObj, formatId, compact)
    local rawCurrent = enemyObj.rawQuantity or enemyObj.quantity or 0
    local rawTotal = enemyObj.rawTotalQuantity or enemyObj.totalQuantity or 100
    local percent = enemyObj.percent or enemyObj.quantity or 0
    local remaining = max(0, rawTotal - rawCurrent)
    local prefix = compact and "" or "Enemy Forces "

    if formatId == "COUNT" then
        return format("%s%d/%d", prefix, RoundToInt(rawCurrent), RoundToInt(rawTotal))
    elseif formatId == "COUNT_PERCENT" then
        return format("%s%d/%d - %.2f%%", prefix, RoundToInt(rawCurrent), RoundToInt(rawTotal), percent)
    elseif formatId == "REMAINING" then
        if compact then
            return format("%d left", RoundToInt(remaining))
        end
        return format("%s%d remaining", prefix, RoundToInt(remaining))
    end

    return format("%s%.2f%%", prefix, percent)
end

-- Objective tracking
local function UpdateObjectives()
    local numCriteria = select(3, C_Scenario.GetStepInfo()) or 0
    local elapsed = currentRun.elapsed

    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info then
            local obj = currentRun.objectives[i]
            if not obj then
                obj = {
                    name          = "",
                    completed     = false,
                    elapsed       = 0,
                    quantity      = 0,
                    totalQuantity = 0,
                    rawQuantity   = 0,
                    rawTotalQuantity = 0,
                    percent       = 0,
                    isWeighted    = false,
                }
                currentRun.objectives[i] = obj
            end

            obj.name = info.description or ("Objective " .. i)
            local wasCompleted = obj.completed
            obj.completed = info.completed

            if obj.completed and not wasCompleted then
                -- On reload, already-completed objectives would get current elapsed.
                -- Use persisted split time if available (saved on first completion).
                local saved = db and db.profile._activeRunSplits and db.profile._activeRunSplits[i]
                if saved and saved > 0 then
                    obj.elapsed = saved
                else
                    obj.elapsed = elapsed
                    -- Persist for reload survival
                    if db and db.profile then
                        if not db.profile._activeRunSplits then db.profile._activeRunSplits = {} end
                        db.profile._activeRunSplits[i] = elapsed
                    end
                end
                UpdateObjectiveCompletion(obj, i)
            end

            obj.quantity = info.quantity or 0
            obj.totalQuantity = info.totalQuantity or 0
            obj.rawQuantity = info.quantity or 0
            obj.rawTotalQuantity = info.totalQuantity or 0
            if info.isWeightedProgress then
                obj.isWeighted = true
                -- Normalize weighted progress to a 0-100 percent value.
                local rawQuantity = info.quantity or 0
                local quantityString = info.quantityString
                if quantityString and quantityString ~= "" then
                    local normalized = quantityString:gsub("%%", "")
                    if normalized:find(",") and not normalized:find("%.") then
                        normalized = normalized:gsub(",", ".")
                    end
                    local parsed = tonumber(normalized)
                    if parsed then
                        rawQuantity = parsed
                    end
                end

                if obj.totalQuantity and obj.totalQuantity > 0 then
                    local percent = (rawQuantity / obj.totalQuantity) * 100
                    obj.quantity = floor(percent * 100 + 0.5) / 100
                else
                    obj.quantity = rawQuantity
                end
                obj.percent = obj.quantity

                if obj.completed then
                    obj.quantity = 100
                    obj.percent = 100
                    if obj.rawTotalQuantity and obj.rawTotalQuantity > 0 then
                        obj.rawQuantity = obj.rawTotalQuantity
                    end
                end
            else
                obj.isWeighted = false
                obj.percent = 0
                if obj.totalQuantity == 0 then
                    obj.quantity = obj.completed and 1 or 0
                    obj.totalQuantity = 1
                end
            end
        end
    end

    for i = numCriteria + 1, #currentRun.objectives do
        currentRun.objectives[i] = nil
    end
end

-- Coalesced refresh
local _refreshTimer
local function NotifyRefresh()
    if _refreshTimer then return end
    _refreshTimer = C_Timer.After(0.05, function()
        _refreshTimer = nil
        if _G._EMT_StandaloneRefresh then _G._EMT_StandaloneRefresh() end
    end)
end

-- Timer tick (1 Hz)
local function OnTimerTick()
    if not currentRun.active then return end

    local _, elapsedTime = GetWorldElapsedTime(1)
    currentRun.elapsed = elapsedTime or 0

    local deathCount, timeLost = C_ChallengeMode.GetDeathCount()
    currentRun.deaths = deathCount or 0
    currentRun.deathTimeLost = timeLost or 0

    UpdateObjectives()
    NotifyRefresh()
end

-- Suppress / restore Blizzard M+ frames
local _blizzHiddenParent
local _blizzOrigScenarioParent
local _blizzOrigObjectiveTrackerParent

local function SuppressBlizzardMPlus()
    if not db or not db.profile.enabled then return end

    if not _blizzHiddenParent then
        _blizzHiddenParent = CreateFrame("Frame")
        _blizzHiddenParent:Hide()
    end

    local sbf = _G.ScenarioBlocksFrame
    if sbf and sbf:GetParent() ~= _blizzHiddenParent then
        _blizzOrigScenarioParent = sbf:GetParent()
        sbf:SetParent(_blizzHiddenParent)
    end

    local otf = _G.ObjectiveTrackerFrame
    if otf and otf:GetParent() ~= _blizzHiddenParent then
        _blizzOrigObjectiveTrackerParent = otf:GetParent()
        otf:SetParent(_blizzHiddenParent)
    end
end

local function UnsuppressBlizzardMPlus()
    local sbf = _G.ScenarioBlocksFrame
    if sbf and _blizzOrigScenarioParent and sbf:GetParent() == _blizzHiddenParent then
        sbf:SetParent(_blizzOrigScenarioParent)
    end

    local otf = _G.ObjectiveTrackerFrame
    if otf and _blizzOrigObjectiveTrackerParent and otf:GetParent() == _blizzHiddenParent then
        otf:SetParent(_blizzOrigObjectiveTrackerParent)
    end
end

-- Run lifecycle
local function StartRun()
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if not mapID then return end

    local mapName, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    local level, affixes = C_ChallengeMode.GetActiveKeystoneInfo()

    currentRun.active        = true
    currentRun.completed     = false
    currentRun.mapID         = mapID
    currentRun.mapName       = mapName or "Unknown"
    currentRun.level         = level or 0
    currentRun.maxTime       = timeLimit or 0
    currentRun.elapsed       = 0
    currentRun.deaths        = 0
    currentRun.deathTimeLost = 0
    currentRun.affixes       = affixes or {}
    currentRun.preciseStart = GetTimePreciseSec and GetTimePreciseSec() or nil
    currentRun.preciseCompletedElapsed = nil
    wipe(currentRun.objectives)

    if updateTicker then updateTicker:Cancel() end
    updateTicker = C_Timer.NewTicker(1, OnTimerTick)
    OnTimerTick()

    SuppressBlizzardMPlus()
    NotifyRefresh()
end

local function CompleteRun()
    currentRun.completed = true
    currentRun.active = false

    if updateTicker then updateTicker:Cancel(); updateTicker = nil end

    local _, elapsedTime = GetWorldElapsedTime(1)
    currentRun.elapsed = elapsedTime or currentRun.elapsed
    if currentRun.preciseStart and GetTimePreciseSec then
        currentRun.preciseCompletedElapsed = max(0, GetTimePreciseSec() - currentRun.preciseStart)
    end
    UpdateBestRun(currentRun)
    UpdateObjectives()
    if db and db.profile then db.profile._activeRunSplits = nil end
    NotifyRefresh()
end

local function ResetRun()
    currentRun.active    = false
    currentRun.completed = false
    currentRun.mapID     = nil
    currentRun.mapName   = ""
    currentRun.level     = 0
    currentRun.maxTime   = 0
    currentRun.elapsed   = 0
    currentRun.deaths    = 0
    currentRun.deathTimeLost = 0
    currentRun.preciseStart = nil
    currentRun.preciseCompletedElapsed = nil
    wipe(currentRun.affixes)
    wipe(currentRun.objectives)
    if db and db.profile then db.profile._activeRunSplits = nil end

    if updateTicker then updateTicker:Cancel(); updateTicker = nil end

    UnsuppressBlizzardMPlus()
    NotifyRefresh()
end

local function CheckForActiveRun()
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if mapID then StartRun() end
end

-- Preview data
local PREVIEW_RUN = {
    active        = true,
    completed     = false,
    mapID         = 2648,
    mapName       = "The Rookery",
    level         = 12,
    maxTime       = 1920,
    elapsed       = 1380,
    deaths        = 2,
    deathTimeLost = 10,
    affixes       = {},
    preciseCompletedElapsed = nil,
    _previewAffixNames = { "Tyrannical", "Xal'atath's Bargain: Ascendant" },
    _previewAffixIDs = { 9, 152 },
    objectives    = {
        { name = "Kyrioss",                 completed = true,  elapsed = 510,  quantity = 1,     totalQuantity = 1,   rawQuantity = 1, rawTotalQuantity = 1, percent = 0, isWeighted = false },
        { name = "Stormguard Gorren",       completed = true,  elapsed = 1005, quantity = 1,     totalQuantity = 1,   rawQuantity = 1, rawTotalQuantity = 1, percent = 0, isWeighted = false },
        { name = "Code Taint Monstrosity",   completed = false, elapsed = 0,    quantity = 0,     totalQuantity = 1,   rawQuantity = 0, rawTotalQuantity = 1, percent = 0, isWeighted = false },
        { name = "|cffff3333Ellesmere|r",    completed = false, elapsed = 0,    quantity = 0,     totalQuantity = 1,   rawQuantity = 0, rawTotalQuantity = 1, percent = 0, isWeighted = false },
        { name = "Enemy Forces",            completed = false, elapsed = 0,    quantity = 78.42, totalQuantity = 100, rawQuantity = 188, rawTotalQuantity = 240, percent = 78.42, isWeighted = true },
    },
}

_G._EMT_Apply = function()
    if _G._EMT_StandaloneRefresh then _G._EMT_StandaloneRefresh() end
end

_G._EMT_GetPresets = GetPresetValues
_G._EMT_ApplyPreset = function(presetID)
    if not db or not db.profile then return false end
    local applied = ApplyPresetToProfile(db.profile, presetID)
    if applied and _G._EMT_StandaloneRefresh then
        _G._EMT_StandaloneRefresh()
    end
    return applied
end

-- Reset the current profile back to defaults and apply the EllesmereUI preset.
-- Used by the module's "Reset" button in the EllesmereUI options panel.
_G._EMT_ResetProfile = function()
    if not db or not db.profile then return false end

    -- Clear every key in the current profile
    for key in pairs(db.profile) do
        db.profile[key] = nil
    end

    -- Repopulate with DB defaults
    for key, value in pairs(DB_DEFAULTS.profile) do
        db.profile[key] = type(value) == "table" and CopyTable(value) or value
    end

    -- Apply the EllesmereUI preset on top (sets selectedPreset = "ELLESMERE")
    ApplyPresetToProfile(db.profile, "ELLESMERE")

    if _G._EMT_StandaloneRefresh then
        _G._EMT_StandaloneRefresh()
    end
    return true
end

-- Standalone frame
local standaloneFrame
local standaloneCreated = false

-- Font helpers
local FALLBACK_FONT = "Fonts/FRIZQT__.TTF"
local FONT_OPTIONS = {
    { key = nil,                          label = "EllesmereUI Default" },
    { key = "Fonts/FRIZQT__.TTF",         label = "Fritz Quadrata" },
    { key = "Fonts/ARIALN.TTF",           label = "Arial Narrow" },
    { key = "Fonts/MORPHEUS.TTF",         label = "Morpheus" },
    { key = "Fonts/SKURRI.TTF",           label = "Skurri" },
    { key = "Fonts/FRIZQT___CYR.TTF",     label = "Fritz Quadrata (Cyrillic)" },
    { key = "Fonts/ARHei.TTF",            label = "AR Hei (CJK)" },
}
local function SFont()
    if db and db.profile and db.profile.fontPath then
        return db.profile.fontPath
    end
    if EllesmereUI and EllesmereUI.GetFontPath then
        local p = EllesmereUI.GetFontPath("unitFrames")
        if p and p ~= "" then return p end
    end
    return FALLBACK_FONT
end
_G._EMT_GetFontOptions = function()
    local values, order = {}, {}
    for _, entry in ipairs(FONT_OPTIONS) do
        local k = entry.key or "DEFAULT"
        values[k] = entry.label
        order[#order + 1] = k
    end
    return values, order
end
local function SOutline()
    if EllesmereUI.GetFontOutlineFlag then return EllesmereUI.GetFontOutlineFlag() end
    return ""
end
local function SetFS(fs, size, flags)
    if not fs then return end
    local p = SFont()
    flags = flags or SOutline()
    fs:SetFont(p, size, flags)
    if not fs:GetFont() then fs:SetFont(FALLBACK_FONT, size, flags) end
end
local function ApplyShadow(fs)
    if not fs then return end
    if EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow() then
        fs:SetShadowColor(0, 0, 0, 0.8); fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function SetFittedText(fs, text, maxWidth, preferredSize, minSize)
    if not fs then return end
    text = text or ""
    preferredSize = preferredSize or 10
    minSize = minSize or 8
    local outline = SOutline()
    SetFS(fs, preferredSize, outline)
    ApplyShadow(fs)
    fs:SetText(text)

    for size = preferredSize, minSize, -1 do
        SetFS(fs, size, outline)
        ApplyShadow(fs)
        fs:SetText(text)
        if not maxWidth or fs:GetStringWidth() <= maxWidth then
            return
        end
    end
end

local function GetAccentColor()
    if EllesmereUI.ResolveThemeColor then
        local theme = EllesmereUIDB and EllesmereUIDB.accentTheme or "Class Colored"
        return EllesmereUI.ResolveThemeColor(theme)
    end
    return 0.05, 0.83, 0.62
end

local objRows = {}
local function GetObjRow(parent, idx)
    if objRows[idx] then return objRows[idx] end
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetWordWrap(false)
    objRows[idx] = fs
    return fs
end

local affixIcons = {}
local function GetAffixIcon(parent, idx)
    if affixIcons[idx] then return affixIcons[idx] end

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(16, 16)

    local border = frame:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetAtlas("ChallengeMode-AffixRing-Sm")
    frame.Border = border

    local portrait = frame:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(16, 16)
    portrait:SetPoint("CENTER", border)
    frame.Portrait = portrait

    frame.SetUp = ScenarioChallengeModeAffixMixin.SetUp
    frame:SetScript("OnEnter", ScenarioChallengeModeAffixMixin.OnEnter)
    frame:SetScript("OnLeave", GameTooltip_Hide)

    affixIcons[idx] = frame
    return frame
end

local function CreateStandaloneFrame()
    if standaloneCreated then return standaloneFrame end
    standaloneCreated = true

    local f = CreateFrame("Frame", "EllesmereUIMythicTimerStandalone", UIParent, "BackdropTemplate")
    f:SetSize(260, 200)
    f:SetPoint("TOPLEFT", UIParent, "CENTER", -130, 100)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(10)
    f:SetClampedToScreen(true)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.05, 0.04, 0.08, 0.85)
    f:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.6)

    f._accent = f:CreateTexture(nil, "BORDER")
    f._accent:SetWidth(2)
    f._accent:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    f._accent:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)

    f._titleFS = f:CreateFontString(nil, "OVERLAY")
    f._titleFS:SetWordWrap(false)
    f._titleFS:SetJustifyV("MIDDLE")

    f._affixFS = f:CreateFontString(nil, "OVERLAY")
    f._affixFS:SetWordWrap(true)
    f._affixIconsAnchor = CreateFrame("Frame", nil, f)
    f._affixIconsAnchor:SetSize(1, 16)

    f._timerFS = f:CreateFontString(nil, "OVERLAY")
    f._timerFS:SetJustifyH("CENTER")
    f._timerDetailFS = f:CreateFontString(nil, "OVERLAY")
    f._timerDetailFS:SetWordWrap(false)
    f._barBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f._barFill = f:CreateTexture(nil, "ARTWORK")
    f._seg3 = f:CreateTexture(nil, "OVERLAY")
    f._seg2 = f:CreateTexture(nil, "OVERLAY")
    f._threshFS = f:CreateFontString(nil, "OVERLAY")
    f._threshFS:SetWordWrap(false)
    f._deathFS = f:CreateFontString(nil, "OVERLAY")
    f._deathFS:SetWordWrap(false)
    f._enemyFS = f:CreateFontString(nil, "OVERLAY")
    f._enemyFS:SetWordWrap(false)
    f._enemyBarBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f._enemyBarFill = f:CreateTexture(nil, "ARTWORK")
    f._previewFS = f:CreateFontString(nil, "OVERLAY")
    f._previewFS:SetWordWrap(false)

    -- Hidden until RenderStandalone() shows it
    f:Hide()

    -- Apply saved scale and position immediately so the frame never flashes at default
    if db and db.profile then
        f:SetScale(db.profile.scale or 1.0)
        if db.profile.standalonePos then
            local pos = db.profile.standalonePos
            f:ClearAllPoints()
            f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        end
    end

    standaloneFrame = f
    return f
end

local function RenderStandalone()
    if not db or not db.profile.enabled then
        if standaloneFrame then standaloneFrame:Hide() end
        return
    end

    local p = db.profile
    local isPreview = false
    local run = currentRun
    if not run.active and not run.completed then
        if p.showPreview then
            run = PREVIEW_RUN
            isPreview = true
        else
            if standaloneFrame then standaloneFrame:Hide() end
            return
        end
    end

    local f = CreateStandaloneFrame()
    local PAD = 10
    local ALIGN_PAD = 6
    local TBAR_PAD = 10
    local configuredTimerBarH = p.timerBarHeight or 10
    local TBAR_H = p.timerInBar and max(configuredTimerBarH, 22) or configuredTimerBarH
    local ENEMY_BAR_H = p.enemyBarHeight or 6
    local ROW_GAP = p.rowGap or 6
    local OBJ_GAP = p.objectiveGap or 3

    f:SetWidth(p.frameWidth or 260)

    local scale = p.scale or 1.0
    f:SetScale(scale)
    local alpha = p.standaloneAlpha or 0.85
    f:SetBackdropColor(0.05, 0.04, 0.08, alpha)
    f:SetBackdropBorderColor(0.15, 0.15, 0.15, min(alpha, 0.6))

    local aR, aG, aB = GetAccentColor()
    if p.showAccent then
        f._accent:SetColorTexture(aR, aG, aB, 0.9)
        f._accent:Show()
    else
        f._accent:Hide()
    end

    local frameW = f:GetWidth()
    local innerW = frameW - PAD * 2
    local y = -PAD

    local function ContentPad(align)
        if align == "LEFT" or align == "RIGHT" then return PAD + ALIGN_PAD end
        return PAD
    end

    -- Title
    local titleAlign = p.titleAlign or "CENTER"
    local titleText = format("+%d  %s", run.level, run.mapName or "Mythic+")
    if p.showDeaths and p.deathsInTitle and run.deaths > 0 then
        local deathPart = format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t %d", run.deaths)
        if p.deathTimeInTitle and run.deathTimeLost > 0 then
            deathPart = deathPart .. format("  (-%s)", FormatTime(run.deathTimeLost))
        end
        titleText = titleText .. format("  |cffee5555%s|r", deathPart)
    end
    f._titleFS:SetJustifyH(titleAlign)
    f._titleFS:SetTextColor(1, 1, 1)
    SetFittedText(f._titleFS, titleText, innerW, 13, 10)
    f._titleFS:ClearAllPoints()
    f._titleFS:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    f._titleFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    f._titleFS:SetHeight(20)
    f._titleFS:Show()
    y = y - 22 - ROW_GAP

    -- Affixes
    if p.showAffixes then
        local names = {}
        local affixIDs = {}
        if run._previewAffixNames then
            for _, name in ipairs(run._previewAffixNames) do
                names[#names + 1] = name
            end
            if run._previewAffixIDs then
                for _, affixID in ipairs(run._previewAffixIDs) do
                    affixIDs[#affixIDs + 1] = affixID
                end
            end
        else
            for _, id in ipairs(run.affixes) do
                local name = C_ChallengeMode.GetAffixInfo(id)
                if name then
                    names[#names + 1] = name
                    affixIDs[#affixIDs + 1] = id
                end
            end
        end
        local affixMode = p.affixDisplayMode or "TEXT"
        local showAffixText = (affixMode == "TEXT" or affixMode == "BOTH") and #names > 0
        local showAffixIcons = (affixMode == "ICONS" or affixMode == "BOTH") and #affixIDs > 0

        if showAffixText then
            f._affixFS:SetTextColor(0.55, 0.55, 0.55)
            f._affixFS:SetJustifyH(titleAlign)
            SetFittedText(f._affixFS, table.concat(names, "  \194\183  "), innerW, 10, 8)
            f._affixFS:ClearAllPoints()
            f._affixFS:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
            f._affixFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
            f._affixFS:Show()
            y = y - (f._affixFS:GetStringHeight() or 12) - ROW_GAP
        else
            f._affixFS:Hide()
        end

        if showAffixIcons then
            local iconSpacing = 4
            local iconSize = 16
            local totalIconW = (#affixIDs * iconSize) + ((#affixIDs - 1) * iconSpacing)
            f._affixIconsAnchor:ClearAllPoints()
            if titleAlign == "RIGHT" then
                f._affixIconsAnchor:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
            elseif titleAlign == "LEFT" then
                f._affixIconsAnchor:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
            else
                f._affixIconsAnchor:SetPoint("TOP", f, "TOP", 0, y)
            end
            f._affixIconsAnchor:SetSize(totalIconW, iconSize)
            f._affixIconsAnchor:Show()

            for index, affixID in ipairs(affixIDs) do
                local icon = GetAffixIcon(f._affixIconsAnchor, index)
                icon:ClearAllPoints()
                if titleAlign == "RIGHT" then
                    if index == 1 then
                        icon:SetPoint("TOPRIGHT", f._affixIconsAnchor, "TOPRIGHT", 0, 0)
                    else
                        icon:SetPoint("RIGHT", affixIcons[index - 1], "LEFT", -iconSpacing, 0)
                    end
                else
                    if index == 1 then
                        icon:SetPoint("TOPLEFT", f._affixIconsAnchor, "TOPLEFT", 0, 0)
                    else
                        icon:SetPoint("LEFT", affixIcons[index - 1], "RIGHT", iconSpacing, 0)
                    end
                end
                icon:SetUp(affixID)
                icon.affixID = affixID
                icon:Show()
            end
            for index = #affixIDs + 1, #affixIcons do
                affixIcons[index]:Hide()
            end

            y = y - iconSize - ROW_GAP
        else
            f._affixIconsAnchor:Hide()
            for index = 1, #affixIcons do
                affixIcons[index]:Hide()
            end
        end
    else
        f._affixFS:Hide()
        f._affixIconsAnchor:Hide()
        for index = 1, #affixIcons do
            affixIcons[index]:Hide()
        end
    end

    -- Deaths
    if p.showDeaths and run.deaths > 0 and not p.deathsInTitle then
        local deathAlign = p.deathAlign or "LEFT"
        local dPad = ContentPad(deathAlign)
        SetFS(f._deathFS, 10)
        ApplyShadow(f._deathFS)
        local dR, dG, dB = GetColor(p.deathTextColor, 0.93, 0.33, 0.33)
        f._deathFS:SetTextColor(dR, dG, dB)
        f._deathFS:SetText(format("%d Death%s  -%s",
            run.deaths, run.deaths ~= 1 and "s" or "", FormatTime(run.deathTimeLost)))
        f._deathFS:ClearAllPoints()
        f._deathFS:SetPoint("TOPLEFT", f, "TOPLEFT", dPad, y)
        f._deathFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -dPad, y)
        f._deathFS:SetJustifyH(deathAlign)
        f._deathFS:Show()
        y = y - (f._deathFS:GetStringHeight() or 12) - ROW_GAP
    else
        f._deathFS:Hide()
    end

    -- Timer colours
    local elapsed = run.elapsed or 0
    local maxTime = run.maxTime or 0
    local timeLeft = max(0, maxTime - elapsed)
    local plusTwoT, plusThreeT = CalculateBonusTimers(maxTime, run.affixes)
    local completedElapsed = run.preciseCompletedElapsed or elapsed
    local timerBarR, timerBarG, timerBarB = GetTimerBarFillColor(p, run.completed and completedElapsed or elapsed, plusThreeT, plusTwoT, maxTime)

    local timerText
    if run.completed then
        timerText = FormatTime(completedElapsed, p.showCompletedMilliseconds ~= false)
    elseif elapsed > maxTime and maxTime > 0 then
        timerText = "+" .. FormatTime(elapsed - maxTime)
    else
        timerText = FormatTime(timeLeft)
    end

    local tR, tG, tB
    if run.completed then
        if completedElapsed <= plusThreeT then      tR, tG, tB = GetColor(p.timerPlusThreeColor, 0.3, 0.8, 1)
        elseif completedElapsed <= plusTwoT then    tR, tG, tB = GetColor(p.timerPlusTwoColor, 0.4, 1, 0.4)
        elseif completedElapsed <= maxTime then     tR, tG, tB = GetColor(p.timerWarningColor, 0.9, 0.7, 0.2)
        else                               tR, tG, tB = GetColor(p.timerExpiredColor, 0.9, 0.2, 0.2) end
    elseif timeLeft <= 0 then              tR, tG, tB = GetColor(p.timerExpiredColor, 0.9, 0.2, 0.2)
    elseif timeLeft < maxTime * 0.2 then   tR, tG, tB = GetColor(p.timerWarningColor, 0.9, 0.7, 0.2)
    else                                   tR, tG, tB = GetColor(p.timerRunningColor, 1, 1, 1) end

    local underBarMode = (p.enemyForcesPos == "UNDER_BAR")

    -- Threshold text
    local function RenderThresholdText()
        if (p.showPlusTwoTimer or p.showPlusThreeTimer) and maxTime > 0 then
            local parts = {}
            if p.showPlusThreeTimer then
                local diff = plusThreeT - elapsed
                if diff >= 0 then
                    local cR, cG, cB = GetColor(p.timerPlusThreeColor, 0.3, 0.8, 1)
                    parts[#parts + 1] = format("|cff%02x%02x%02x+3  %s|r", floor(cR * 255), floor(cG * 255), floor(cB * 255), FormatTime(diff))
                else
                    parts[#parts + 1] = format("|cff666666+3  -%s|r", FormatTime(abs(diff)))
                end
            end
            if p.showPlusTwoTimer then
                local diff = plusTwoT - elapsed
                if diff >= 0 then
                    local cR, cG, cB = GetColor(p.timerPlusTwoColor, 0.4, 1, 0.4)
                    parts[#parts + 1] = format("|cff%02x%02x%02x+2  %s|r", floor(cR * 255), floor(cG * 255), floor(cB * 255), FormatTime(diff))
                else
                    parts[#parts + 1] = format("|cff666666+2  -%s|r", FormatTime(abs(diff)))
                end
            end
            if #parts > 0 then
                SetFS(f._threshFS, 10)
                ApplyShadow(f._threshFS)
                f._threshFS:SetTextColor(1, 1, 1)
                f._threshFS:SetText(table.concat(parts, "      "))
                f._threshFS:SetJustifyH(p.timerAlign or "CENTER")
                f._threshFS:ClearAllPoints()
                f._threshFS:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
                f._threshFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
                f._threshFS:Show()
                y = y - (f._threshFS:GetStringHeight() or 12) - ROW_GAP
            else
                f._threshFS:Hide()
            end
        else
            f._threshFS:Hide()
        end
    end

    -- Enemy forces
    local function RenderEnemyForces()
        if not p.showEnemyBar then
            f._enemyFS:Hide(); f._enemyBarBg:Hide(); f._enemyBarFill:Hide()
            if f._enemyBarText then f._enemyBarText:Hide() end
            return
        end
        local enemyObj = nil
        for _, obj in ipairs(run.objectives) do
            if obj.isWeighted then enemyObj = obj; break end
        end
        if not enemyObj then
            f._enemyFS:Hide(); f._enemyBarBg:Hide(); f._enemyBarFill:Hide()
            if f._enemyBarText then f._enemyBarText:Hide() end
            return
        end

        local objAlign = p.objectiveAlign or "LEFT"
        local ePad = ContentPad(objAlign)
        local pctRaw = min(100, max(0, enemyObj.quantity))
        local pctPos = p.enemyForcesPctPos or "LABEL"
        local showEnemyText = p.showEnemyText ~= false

        local enemyTextFormat = p.enemyForcesTextFormat or "PERCENT"
        local label = pctPos == "LABEL"
            and FormatEnemyForcesText(enemyObj, enemyTextFormat, false)
            or "Enemy Forces"

        SetFS(f._enemyFS, 10)
        ApplyShadow(f._enemyFS)
        if enemyObj.completed then
            f._enemyFS:SetTextColor(GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3))
        else
            f._enemyFS:SetTextColor(GetColor(p.objectiveTextColor, 0.9, 0.9, 0.9))
        end
        f._enemyFS:SetText(label)

        local function RenderEnemyBar()
            local besideRoom = (not enemyObj.completed and pctPos == "BESIDE") and 62 or 0
            local barW = min(p.barWidth or (innerW - TBAR_PAD * 2), innerW - TBAR_PAD * 2) - besideRoom
            if barW < 60 then barW = 60 end
            f._enemyBarBg:ClearAllPoints()
            if objAlign == "RIGHT" then
                f._enemyBarBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + TBAR_PAD), y)
            elseif objAlign == "CENTER" then
                f._enemyBarBg:SetPoint("TOP", f, "TOP", 0, y)
            else
                f._enemyBarBg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + TBAR_PAD, y)
            end
            f._enemyBarBg:SetSize(barW, ENEMY_BAR_H)
            f._enemyBarBg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
            f._enemyBarBg:Show()

            local eR, eG, eB
            if enemyObj.completed then
                eR, eG, eB = GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3)
            elseif (p.enemyBarColorMode or "PROGRESS") == "SOLID" then
                eR, eG, eB = GetColor(p.enemyBarSolidColor, 0.35, 0.55, 0.8)
            else
                eR, eG, eB = GetEnemyForcesColor(p, pctRaw)
            end

            local epct = enemyObj.completed and 1 or min(1, max(0, pctRaw / 100))
            local eFillW = max(1, barW * epct)
            f._enemyBarFill:ClearAllPoints()
            f._enemyBarFill:SetPoint("TOPLEFT", f._enemyBarBg, "TOPLEFT", 0, 0)
            f._enemyBarFill:SetSize(eFillW, ENEMY_BAR_H)
            f._enemyBarFill:SetColorTexture(eR, eG, eB, 0.8)
            f._enemyBarFill:Show()

            if not f._enemyBarText then
                f._enemyBarText = f:CreateFontString(nil, "OVERLAY")
                f._enemyBarText:SetWordWrap(false)
            end
            if pctPos == "BAR" then
                SetFS(f._enemyBarText, 8)
                ApplyShadow(f._enemyBarText)
                if enemyObj.completed then
                    f._enemyBarText:SetTextColor(GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3))
                else
                    f._enemyBarText:SetTextColor(GetColor(p.objectiveTextColor, 0.9, 0.9, 0.9))
                end
                f._enemyBarText:SetText(FormatEnemyForcesText(enemyObj, enemyTextFormat, true))
                f._enemyBarText:ClearAllPoints()
                f._enemyBarText:SetPoint("CENTER", f._enemyBarBg, "CENTER", 0, 0)
                f._enemyBarText:Show()
            elseif pctPos == "BESIDE" then
                SetFS(f._enemyBarText, 8)
                ApplyShadow(f._enemyBarText)
                if enemyObj.completed then
                    f._enemyBarText:SetTextColor(GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3))
                else
                    f._enemyBarText:SetTextColor(GetColor(p.objectiveTextColor, 0.9, 0.9, 0.9))
                end
                f._enemyBarText:SetText(FormatEnemyForcesText(enemyObj, enemyTextFormat, true))
                f._enemyBarText:ClearAllPoints()
                if objAlign == "RIGHT" then
                    f._enemyBarText:SetPoint("RIGHT", f._enemyBarBg, "LEFT", -4, 0)
                else
                    f._enemyBarText:SetPoint("LEFT", f._enemyBarBg, "RIGHT", 4, 0)
                end
                f._enemyBarText:Show()
            else
                f._enemyBarText:Hide()
            end

            y = y - ENEMY_BAR_H - ROW_GAP
        end

        local function RenderEnemyLabel()
            if not showEnemyText then
                f._enemyFS:Hide()
                return
            end
            f._enemyFS:ClearAllPoints()
            f._enemyFS:SetPoint("TOPLEFT", f, "TOPLEFT", ePad, y)
            f._enemyFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -ePad, y)
            f._enemyFS:SetJustifyH(objAlign)
            f._enemyFS:Show()
            y = y - (f._enemyFS:GetStringHeight() or 12) - 4
        end

        if underBarMode then
            RenderEnemyBar()
            RenderEnemyLabel()
        else
            RenderEnemyLabel()
            RenderEnemyBar()
        end
    end

    -- Timer text
    if not p.timerInBar then
        local timerAlign = p.timerAlign or "CENTER"
        SetFS(f._timerFS, 20)
        ApplyShadow(f._timerFS)
        f._timerFS:SetTextColor(tR, tG, tB)
        f._timerFS:SetText(timerText)
        f._timerFS:SetJustifyH(timerAlign)
        f._timerFS:ClearAllPoints()
        local timerBlockW = min(innerW, max(140, floor(innerW * 0.72)))
        if timerAlign == "RIGHT" then
            f._timerFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + ALIGN_PAD), y)
        elseif timerAlign == "LEFT" then
            f._timerFS:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + ALIGN_PAD, y)
        else
            f._timerFS:SetPoint("TOP", f, "TOP", 0, y)
        end
        f._timerFS:SetWidth(timerBlockW)
        f._timerFS:Show()
        local timerH = f._timerFS:GetStringHeight() or 20
        if timerH < 20 then timerH = 20 end
        y = y - timerH - ROW_GAP
    else
        f._timerFS:Hide()
    end

    if p.showTimerBreakdown and maxTime > 0 then
        local timerAlign = p.timerAlign or "CENTER"
        SetFS(f._timerDetailFS, 10)
        ApplyShadow(f._timerDetailFS)
        f._timerDetailFS:SetTextColor(0.65, 0.65, 0.65)
        f._timerDetailFS:SetText(format("%s / %s", FormatTime(elapsed), FormatTime(maxTime)))
        f._timerDetailFS:SetJustifyH(timerAlign)
        f._timerDetailFS:ClearAllPoints()
        local detailBlockW = min(innerW, max(140, floor(innerW * 0.72)))
        if timerAlign == "RIGHT" then
            f._timerDetailFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + ALIGN_PAD), y)
        elseif timerAlign == "LEFT" then
            f._timerDetailFS:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + ALIGN_PAD, y)
        else
            f._timerDetailFS:SetPoint("TOP", f, "TOP", 0, y)
        end
        f._timerDetailFS:SetWidth(detailBlockW)
        f._timerDetailFS:Show()
        y = y - (f._timerDetailFS:GetStringHeight() or 10) - ROW_GAP
    else
        f._timerDetailFS:Hide()
    end

    if underBarMode then
        RenderThresholdText()
    end

    -- Timer bar
    if maxTime > 0 and p.showTimerBar ~= false then
        local barW = min(p.barWidth or (innerW - TBAR_PAD * 2), innerW - TBAR_PAD * 2)
        if barW < 60 then barW = 60 end

        f._barBg:ClearAllPoints()
        if (p.timerAlign or "CENTER") == "RIGHT" then
            f._barBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + TBAR_PAD), y)
        elseif (p.timerAlign or "CENTER") == "LEFT" then
            f._barBg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + TBAR_PAD, y)
        else
            f._barBg:SetPoint("TOP", f, "TOP", 0, y)
        end
        f._barBg:SetSize(barW, TBAR_H)
        f._barBg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
        f._barBg:Show()

        local fillPct = min(1, elapsed / maxTime)
        local fillW = max(1, barW * fillPct)
        f._barFill:ClearAllPoints()
        f._barFill:SetPoint("TOPLEFT", f._barBg, "TOPLEFT", 0, 0)
        f._barFill:SetSize(fillW, TBAR_H)
        f._barFill:SetColorTexture(timerBarR, timerBarG, timerBarB, 0.85)
        f._barFill:Show()

        -- +3 marker
        f._seg3:ClearAllPoints()
        f._seg3:SetSize(1, TBAR_H + 4)
        f._seg3:SetPoint("TOP", f._barBg, "TOPLEFT", floor(barW * (plusThreeT / maxTime)), 2)
        f._seg3:SetColorTexture(0.3, 0.8, 1, 0.9)
        if p.showPlusThreeBar then f._seg3:Show() else f._seg3:Hide() end

        -- +2 marker
        f._seg2:ClearAllPoints()
        f._seg2:SetSize(1, TBAR_H + 4)
        f._seg2:SetPoint("TOP", f._barBg, "TOPLEFT", floor(barW * (plusTwoT / maxTime)), 2)
        f._seg2:SetColorTexture(0.4, 1, 0.4, 0.9)
        if p.showPlusTwoBar then f._seg2:Show() else f._seg2:Hide() end

        if p.timerInBar then
            if not f._barTimerFS then
                f._barTimerFS = f:CreateFontString(nil, "OVERLAY")
                f._barTimerFS:SetWordWrap(false)
            end
            SetFS(f._barTimerFS, 12)
            ApplyShadow(f._barTimerFS)
            local btc = p.timerBarTextColor
            if btc then
                f._barTimerFS:SetTextColor(btc.r or 1, btc.g or 1, btc.b or 1)
            else
                f._barTimerFS:SetTextColor(tR, tG, tB)
            end
            f._barTimerFS:SetText(timerText)
            f._barTimerFS:ClearAllPoints()
            f._barTimerFS:SetPoint("CENTER", f._barBg, "CENTER", 0, 0)
            f._barTimerFS:Show()
        elseif f._barTimerFS then
            f._barTimerFS:Hide()
        end

        y = y - TBAR_H - ROW_GAP - 2
    else
        f._barBg:Hide(); f._barFill:Hide()
        f._seg3:Hide(); f._seg2:Hide()
        if f._barTimerFS then f._barTimerFS:Hide() end
    end

    if underBarMode then
        RenderEnemyForces()
    end

    if not underBarMode then
        RenderThresholdText()
    end

    -- Objectives
    local objIdx = 0
    if p.showObjectives then
        local objAlign = p.objectiveAlign or "LEFT"
        local oPad = ContentPad(objAlign)
        for i, obj in ipairs(run.objectives) do
            if not obj.isWeighted then
                objIdx = objIdx + 1
                local row = GetObjRow(f, objIdx)
                SetFS(row, 10)
                ApplyShadow(row)

                local displayName = obj.name or ("Objective " .. i)
                if obj.totalQuantity and obj.totalQuantity > 1 then
                    displayName = format("%d/%d %s", obj.quantity or 0, obj.totalQuantity, displayName)
                end
                if obj.completed then
                    displayName = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:0|t " .. displayName
                    row:SetTextColor(GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3))
                else
                    row:SetTextColor(GetColor(p.objectiveTextColor, 0.9, 0.9, 0.9))
                end
                local timeStr = ""
                if p.showObjectiveTimes ~= false and obj.completed and obj.elapsed and obj.elapsed > 0 then
                    timeStr = "|cff888888" .. FormatTime(obj.elapsed) .. "|r"
                end
                local compareSuffix = ""
                if obj.completed and obj.referenceElapsed then
                    compareSuffix = BuildSplitCompareText(obj.referenceElapsed, obj.elapsed, p.objectiveCompareDeltaOnly, p.splitFasterColor, p.splitSlowerColor)
                elseif (not obj.completed) and p.showUpcomingSplitTargets and (p.objectiveCompareMode or COMPARE_NONE) ~= COMPARE_NONE then
                    local target = GetReferenceObjectiveTime(run, i, p.objectiveCompareMode or COMPARE_NONE)
                    if target then
                        compareSuffix = "  |cff888888PB " .. FormatTime(target) .. "|r"
                    end
                end
                if timeStr ~= "" and (p.objectiveTimePosition or "END") == "START" then
                    row:SetText(timeStr .. "  " .. displayName .. compareSuffix)
                else
                    row:SetText(displayName .. (timeStr ~= "" and ("  " .. timeStr) or "") .. compareSuffix)
                end
                row:SetJustifyH(objAlign)
                row:ClearAllPoints()
                local oInnerW = frameW - oPad * 2
                local objBlockW = min(oInnerW, max(160, floor(oInnerW * 0.8)))
                if objAlign == "RIGHT" then
                    row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -oPad, y)
                elseif objAlign == "CENTER" then
                    row:SetPoint("TOP", f, "TOP", 0, y)
                else
                    row:SetPoint("TOPLEFT", f, "TOPLEFT", oPad, y)
                end
                row:SetWidth(objBlockW)
                row:Show()
                y = y - (row:GetStringHeight() or 12) - OBJ_GAP
            end
        end
    end

    for i = objIdx + 1, #objRows do
        objRows[i]:Hide()
    end

    if not underBarMode then
        RenderEnemyForces()
    end

    local totalH = abs(y) + PAD
    f:SetHeight(totalH)

    if isPreview then
        SetFS(f._previewFS, 8)
        f._previewFS:SetTextColor(0.5, 0.5, 0.5, 0.6)
        f._previewFS:SetText("PREVIEW")
        f._previewFS:ClearAllPoints()
        f._previewFS:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 4)
        f._previewFS:Show()
    elseif f._previewFS then
        f._previewFS:Hide()
    end

    f:Show()
end

_G._EMT_StandaloneRefresh = RenderStandalone
_G._EMT_GetStandaloneFrame = function()
    return CreateStandaloneFrame()
end

local function ApplyStandalonePosition()
    if not db then return end
    if not standaloneFrame then return end
    standaloneFrame:SetScale(db.profile.scale or 1.0)
    local pos = db.profile.standalonePos
    if pos then
        standaloneFrame:ClearAllPoints()
        standaloneFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end
end

local function ArePrimaryObjectivesComplete()
    local numCriteria = select(3, C_Scenario.GetStepInfo()) or 0
    if numCriteria == 0 then return false end

    local seenPrimary = false
    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info and not info.isWeightedProgress then
            seenPrimary = true
            if not info.completed then
                return false
            end
        end
    end

    return seenPrimary
end

local runtimeFrame = CreateFrame("Frame")
local runtimePollElapsed = 0
local runtimeInitElapsed = 0
local runtimeInitialized = false

local function RuntimeOnUpdate(_, elapsed)
    if not db then return end

    if not runtimeInitialized then
        runtimeInitElapsed = runtimeInitElapsed + elapsed
        if runtimeInitElapsed >= 1 then
            runtimeInitialized = true
            CheckForActiveRun()
            ApplyStandalonePosition()
        end
    end

    runtimePollElapsed = runtimePollElapsed + elapsed
    if runtimePollElapsed < 0.25 then return end
    runtimePollElapsed = 0

    if not db.profile.enabled then
        if currentRun.active or currentRun.completed then
            ResetRun()
        end
        return
    end

    local activeMapID = C_ChallengeMode.GetActiveChallengeMapID()
    if activeMapID then
        if not currentRun.active and not currentRun.completed then
            StartRun()
        elseif currentRun.active and ArePrimaryObjectivesComplete() then
            CompleteRun()
        end
    elseif currentRun.active or currentRun.completed then
        ResetRun()
    end
end

function EMT:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIMythicTimerDB", DB_DEFAULTS)
    _G._EMT_AceDB = db

    if db and db.profile then
        local pp = db.profile
        for key, value in pairs(DB_DEFAULTS.profile) do
            if pp[key] == nil then
                pp[key] = type(value) == "table" and CopyTable(value) or value
            end
        end
    end

    -- Season-based data purge: clear best runs/splits from previous seasons
    C_Timer.After(2, function()
        if not db or not db.profile then return end
        local currentMaps = C_ChallengeMode.GetMapTable()
        if not currentMaps or #currentMaps == 0 then return end

        local validMapIDs = {}
        for _, mapID in ipairs(currentMaps) do
            validMapIDs[mapID] = true
        end

        local purged = false

        if db.profile.bestRuns then
            for scopeKey in pairs(db.profile.bestRuns) do
                local mapIDStr = scopeKey:match("^(%d+):")
                local mapID = tonumber(mapIDStr)
                if mapID and not validMapIDs[mapID] then
                    db.profile.bestRuns[scopeKey] = nil
                    purged = true
                end
            end
        end

        if db.profile.bestObjectiveSplits then
            for scopeKey in pairs(db.profile.bestObjectiveSplits) do
                local mapIDStr = scopeKey:match("^(%d+)")
                local mapID = tonumber(mapIDStr)
                if mapID and not validMapIDs[mapID] then
                    db.profile.bestObjectiveSplits[scopeKey] = nil
                    purged = true
                end
            end
        end
    end)

    runtimeFrame:SetScript("OnUpdate", RuntimeOnUpdate)
end

function EMT:OnEnable()
    if not db or not db.profile.enabled then return end

    if EllesmereUI and EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement then
        local MK = EllesmereUI.MakeUnlockElement
        EllesmereUI:RegisterUnlockElements({
            MK({
                key   = "EMT_MythicTimer",
                label = "Mythic+ Timer",
                group = "Mythic+",
                order = 520,
                noResize = true,
                getFrame = function()
                    return _G._EMT_GetStandaloneFrame and _G._EMT_GetStandaloneFrame()
                end,
                getSize  = function()
                    local f = standaloneFrame
                    if f then return f:GetWidth(), f:GetHeight() end
                    return 260, 200
                end,
                isHidden = function()
                    return false
                end,
                savePos = function(_, point, relPoint, x, y)
                    -- Save in frame's own coordinate space (TOPLEFT so height grows downward)
                    local f = standaloneFrame
                    if f and f:GetLeft() and f:GetTop() then
                        db.profile.standalonePos = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = f:GetLeft(), y = f:GetTop() }
                    else
                        db.profile.standalonePos = { point = point, relPoint = relPoint, x = x, y = y }
                    end
                    if f and not EllesmereUI._unlockActive then
                        local pos = db.profile.standalonePos
                        f:ClearAllPoints()
                        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
                    end
                end,
                loadPos = function()
                    return db.profile.standalonePos
                end,
                clearPos = function()
                    db.profile.standalonePos = nil
                end,
                applyPos = function()
                    local pos = db.profile.standalonePos
                    if pos and standaloneFrame then
                        standaloneFrame:SetScale(db.profile.scale or 1.0)
                        standaloneFrame:ClearAllPoints()
                        standaloneFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
                    end
                end,
            }),
        })
    end
end

