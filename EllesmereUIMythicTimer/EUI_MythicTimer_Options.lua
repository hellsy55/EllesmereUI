-------------------------------------------------------------------------------
--  EUI_MythicTimer_Options.lua  —  Settings page for M+ Timer
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_DISPLAY = "Mythic+ Timer"
local PAGE_BEST_RUNS = "Best Runs"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local db
    C_Timer.After(0, function() db = _G._EMT_AceDB end)

    local function DB()
        if not db then db = _G._EMT_AceDB end
        return db and db.profile
    end

    local function Cfg(key)
        local p = DB()
        return p and p[key]
    end

    local function Set(key, val)
        local p = DB()
        if p then
            p[key] = val
            if key ~= "selectedPreset" and key ~= "advancedMode" and key ~= "fontPath" then
                p.selectedPreset = "CUSTOM"
            end
        end
    end

    local function SetPreset(presetID)
        local p = DB()
        if not p then return end

        if presetID == "CUSTOM" then
            p.selectedPreset = "CUSTOM"
            return
        end

        if _G._EMT_ApplyPreset and _G._EMT_ApplyPreset(presetID) then
            return
        end

        p.selectedPreset = presetID
    end

    local function IsAdvanced()
        return Cfg("advancedMode") == true
    end

    local function Refresh()
        if _G._EMT_Apply then _G._EMT_Apply() end
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
    end

    local function RebuildPage()
        if _G._EMT_Apply then _G._EMT_Apply() end
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
    end

    -- Build Page
    local function BuildPage(pageName, parent, yOffset)
        if pageName == PAGE_BEST_RUNS then
            if _G._EMT_BuildBestRunsPage then
                _G._EMT_BuildBestRunsPage(parent, yOffset)
            end
            return
        end

        local W = EllesmereUI.Widgets
        local y = yOffset
        local row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        local presetValues = {
          CUSTOM = "Custom",
          ELLESMERE = "EllesmereUI",
          WARP_DEPLETE = "Warp Deplete",
          MYTHIC_PLUS_TIMER = "MythicPlusTimer",
        }
        local presetOrder = { "CUSTOM", "ELLESMERE", "WARP_DEPLETE", "MYTHIC_PLUS_TIMER" }
        if _G._EMT_GetPresets then
          local values, order = _G._EMT_GetPresets()
          if values then presetValues = values end
          if order then presetOrder = order end
        end

        local alignValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
        local alignOrder  = { "LEFT", "CENTER", "RIGHT" }
        local affixDisplayValues = { TEXT = "Text", ICONS = "Icons", BOTH = "Text + Icons" }
        local affixDisplayOrder = { "TEXT", "ICONS", "BOTH" }
        local compareModeValues = {
          NONE = "None",
          DUNGEON = "Per Dungeon",
          LEVEL = "Per Dungeon + Level",
          LEVEL_AFFIX = "Per Dungeon + Level + Affixes",
          RUN = "Best Full Run",
        }
        local compareModeOrder = { "NONE", "DUNGEON", "LEVEL", "LEVEL_AFFIX", "RUN" }
        local forcesTextValues = {
          PERCENT = "Percent",
          COUNT = "Count / Total",
          COUNT_PERCENT = "Count / Total + %",
          REMAINING = "Remaining Count",
        }
        local forcesTextOrder = { "PERCENT", "COUNT", "COUNT_PERCENT", "REMAINING" }
        local objectiveTimePositionValues = { END = "After Boss Name", START = "Before Boss Name" }
        local objectiveTimePositionOrder = { "END", "START" }

        -- ── DISPLAY ──────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Module",
              getValue=function() return Cfg("enabled") ~= false end,
              setValue=function(v) Set("enabled", v); Refresh() end },
            { type="toggle", text="Show Preview",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("showPreview") == true end,
              setValue=function(v) Set("showPreview", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Preset",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              values=presetValues,
              order=presetOrder,
              getValue=function() return Cfg("selectedPreset") or "ELLESMERE" end,
              setValue=function(v) SetPreset(v); Refresh() end },
            { type="toggle", text="Advanced Mode",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("advancedMode") == true end,
              setValue=function(v)
                  local p = DB()
                  if p then p.advancedMode = v end
                  RebuildPage()
              end })
        y = y - h

        local fontValues, fontOrder = {}, {}
        if _G._EMT_GetFontOptions then
            fontValues, fontOrder = _G._EMT_GetFontOptions()
        end

        row, h = W:DualRow(parent, y,
            { type="slider", text="Scale",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              min=0.5, max=2.0, step=0.05, isPercent=false,
              getValue=function() return Cfg("scale") or 1.0 end,
              setValue=function(v) Set("scale", v); Refresh() end },
            { type="slider", text="Opacity",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              min=0.1, max=1.0, step=0.05, isPercent=false,
              getValue=function() return Cfg("standaloneAlpha") or 0.85 end,
              setValue=function(v) Set("standaloneAlpha", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Font",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              values=fontValues,
              order=fontOrder,
              getValue=function() return Cfg("fontPath") or "DEFAULT" end,
              setValue=function(v)
                  Set("fontPath", v ~= "DEFAULT" and v or nil)
                  Refresh()
              end },
            { type="label", text="" })
        y = y - h

        if IsAdvanced() then
            row, h = W:DualRow(parent, y,
                { type="toggle", text="Show Accent Stripe",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function() return Cfg("showAccent") == true end,
                  setValue=function(v) Set("showAccent", v); Refresh() end },
                { type="toggle", text="Show MS On Completion",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function() return Cfg("showCompletedMilliseconds") ~= false end,
                  setValue=function(v) Set("showCompletedMilliseconds", v); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Title / Affix Align",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  values=alignValues,
                  order=alignOrder,
                  getValue=function() return Cfg("titleAlign") or "CENTER" end,
                  setValue=function(v) Set("titleAlign", v); Refresh() end },
                { type="dropdown", text="Timer Align",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  values=alignValues,
                  order=alignOrder,
                  getValue=function() return Cfg("timerAlign") or "CENTER" end,
                  setValue=function(v) Set("timerAlign", v); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Objective Align",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  values=alignValues,
                  order=alignOrder,
                  getValue=function() return Cfg("objectiveAlign") or "LEFT" end,
                  setValue=function(v) Set("objectiveAlign", v); Refresh() end },
                { type="dropdown", text="Affix Display",
                  disabled=function() return Cfg("enabled") == false or Cfg("showAffixes") == false end,
                  disabledTooltip=function()
                    if Cfg("enabled") == false then return "the module" end
                    return "Show Affixes"
                  end,
                  values=affixDisplayValues,
                  order=affixDisplayOrder,
                  getValue=function() return Cfg("affixDisplayMode") or "TEXT" end,
                  setValue=function(v) Set("affixDisplayMode", v); Refresh() end })
            y = y - h
        end

        -- ── TIMER ────────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "TIMER", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Timer Bar",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("showTimerBar") ~= false end,
              setValue=function(v) Set("showTimerBar", v); Refresh() end },
            { type="toggle", text="Show Timer Details",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("showTimerBreakdown") == true end,
              setValue=function(v) Set("showTimerBreakdown", v); Refresh() end })
        y = y - h

        if IsAdvanced() then
            row, h = W:DualRow(parent, y,
                { type="toggle", text="Timer Inside Bar",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function() return Cfg("timerInBar") == true end,
                  setValue=function(v) Set("timerInBar", v); Refresh() end },
                { type="colorpicker", text="In-Bar Text Color",
                  disabled=function() return Cfg("enabled") == false or Cfg("timerInBar") ~= true end,
                  disabledTooltip="Requires Timer Inside Bar",
                  getValue=function()
                      local c = Cfg("timerBarTextColor")
                      if c then return c.r or 1, c.g or 1, c.b or 1 end
                      return 1, 1, 1
                  end,
                  setValue=function(r, g, b)
                      Set("timerBarTextColor", { r = r, g = g, b = b })
                      Refresh()
                  end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="toggle", text="+3 Threshold Text",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function() return Cfg("showPlusThreeTimer") ~= false end,
                  setValue=function(v) Set("showPlusThreeTimer", v); Refresh() end },
                { type="toggle", text="+3 Bar Marker",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function() return Cfg("showPlusThreeBar") ~= false end,
                  setValue=function(v) Set("showPlusThreeBar", v); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="toggle", text="+2 Threshold Text",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function() return Cfg("showPlusTwoTimer") ~= false end,
                  setValue=function(v) Set("showPlusTwoTimer", v); Refresh() end },
                { type="toggle", text="+2 Bar Marker",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function() return Cfg("showPlusTwoBar") ~= false end,
                  setValue=function(v) Set("showPlusTwoBar", v); Refresh() end })
            y = y - h
        end

        -- ── OBJECTIVES ───────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "OBJECTIVES", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Affixes",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("showAffixes") ~= false end,
              setValue=function(v) Set("showAffixes", v); Refresh() end },
            { type="toggle", text="Show Boss Objectives",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("showObjectives") ~= false end,
              setValue=function(v) Set("showObjectives", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Objective Times",
              disabled=function() return Cfg("enabled") == false or Cfg("showObjectives") == false end,
              disabledTooltip=function()
                  if Cfg("enabled") == false then return "the module" end
                  return "Show Boss Objectives"
              end,
              getValue=function() return Cfg("showObjectiveTimes") ~= false end,
              setValue=function(v) Set("showObjectiveTimes", v); Refresh() end },
            { type="toggle", text="Show Enemy Forces",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("showEnemyBar") ~= false end,
              setValue=function(v) Set("showEnemyBar", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Deaths",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("showDeaths") ~= false end,
              setValue=function(v) Set("showDeaths", v); Refresh() end },
            { type="dropdown", text="Death Align",
              disabled=function() return Cfg("enabled") == false or Cfg("showDeaths") == false end,
              disabledTooltip=function()
                  if Cfg("enabled") == false then return "the module" end
                  return "Show Deaths"
              end,
              values=alignValues,
              order=alignOrder,
              getValue=function() return Cfg("deathAlign") or "LEFT" end,
              setValue=function(v) Set("deathAlign", v); Refresh() end })
        y = y - h

        if IsAdvanced() then
            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Boss Time Position",
                  disabled=function() return Cfg("enabled") == false or Cfg("showObjectives") == false or Cfg("showObjectiveTimes") == false end,
                  disabledTooltip=function()
                      if Cfg("enabled") == false then return "the module" end
                      if Cfg("showObjectives") == false then return "Show Boss Objectives" end
                      return "Show Objective Times"
                  end,
                  values=objectiveTimePositionValues,
                  order=objectiveTimePositionOrder,
                  getValue=function() return Cfg("objectiveTimePosition") or "END" end,
                  setValue=function(v) Set("objectiveTimePosition", v); Refresh() end },
                { type="dropdown", text="Enemy Text Format",
                  disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
                  disabledTooltip="Requires Show Enemy Forces",
                  values=forcesTextValues,
                  order=forcesTextOrder,
                  getValue=function() return Cfg("enemyForcesTextFormat") or "PERCENT" end,
                  setValue=function(v) Set("enemyForcesTextFormat", v); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Split Compare",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  values=compareModeValues,
                  order=compareModeOrder,
                  getValue=function() return Cfg("objectiveCompareMode") or "NONE" end,
                  setValue=function(v) Set("objectiveCompareMode", v); Refresh() end },
                { type="toggle", text="Delta Only",
                  disabled=function() return Cfg("enabled") == false or (Cfg("objectiveCompareMode") or "NONE") == "NONE" end,
                  disabledTooltip="Requires Split Compare",
                  getValue=function() return Cfg("objectiveCompareDeltaOnly") == true end,
                  setValue=function(v) Set("objectiveCompareDeltaOnly", v); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="toggle", text="Show Upcoming Split Targets",
                  disabled=function() return Cfg("enabled") == false or (Cfg("objectiveCompareMode") or "NONE") == "NONE" end,
                  disabledTooltip="Requires Split Compare",
                  getValue=function() return Cfg("showUpcomingSplitTargets") == true end,
                  setValue=function(v) Set("showUpcomingSplitTargets", v); Refresh() end },
                { type="button", text="Clear Best Times",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  onClick=function()
                      local p = DB()
                      if p then
                          p.bestObjectiveSplits = {}
                          p.bestRuns = {}
                      end
                      Refresh()
                  end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="toggle", text="Deaths in Title",
                  disabled=function() return Cfg("enabled") == false or Cfg("showDeaths") == false end,
                  disabledTooltip=function()
                      if Cfg("enabled") == false then return "the module" end
                      return "Show Deaths"
                  end,
                  getValue=function() return Cfg("deathsInTitle") == true end,
                  setValue=function(v) Set("deathsInTitle", v); Refresh() end },
                { type="toggle", text="Time Lost in Title",
                  disabled=function() return Cfg("enabled") == false or Cfg("showDeaths") == false or Cfg("deathsInTitle") ~= true end,
                  disabledTooltip=function()
                      if Cfg("enabled") == false then return "the module" end
                      if Cfg("showDeaths") == false then return "Show Deaths" end
                      return "Deaths in Title"
                  end,
                  getValue=function() return Cfg("deathTimeInTitle") == true end,
                  setValue=function(v) Set("deathTimeInTitle", v); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="toggle", text="Show Enemy Forces Text",
                  disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
                  disabledTooltip="Requires Show Enemy Forces",
                  getValue=function() return Cfg("showEnemyText") ~= false end,
                  setValue=function(v) Set("showEnemyText", v); Refresh() end },
                { type="dropdown", text="Enemy Forces Position",
                  disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
                  disabledTooltip="Requires Show Enemy Forces",
                  values={ BOTTOM = "Bottom (default)", UNDER_BAR = "Under Timer Bar" },
                  order={ "BOTTOM", "UNDER_BAR" },
                  getValue=function() return Cfg("enemyForcesPos") or "BOTTOM" end,
                  setValue=function(v) Set("enemyForcesPos", v); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Enemy Bar Color",
                  disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
                  disabledTooltip="Requires Show Enemy Forces",
                  values={ PROGRESS = "Progress (% Breakpoints)", SOLID = "Solid" },
                  order={ "PROGRESS", "SOLID" },
                  getValue=function() return Cfg("enemyBarColorMode") or "PROGRESS" end,
                  setValue=function(v) Set("enemyBarColorMode", v); Refresh() end },
                { type="dropdown", text="Enemy Forces %",
                  disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
                  disabledTooltip="Requires Show Enemy Forces",
                  values={ LABEL = "In Label Text", BAR = "In Bar", BESIDE = "Beside Bar" },
                  order={ "LABEL", "BAR", "BESIDE" },
                  getValue=function() return Cfg("enemyForcesPctPos") or "LABEL" end,
                  setValue=function(v) Set("enemyForcesPctPos", v); Refresh() end })
            y = y - h

        end

        if IsAdvanced() then
            -- ── LAYOUT ────────────────────────────────────────────────────
            _, h = W:SectionHeader(parent, "LAYOUT", y); y = y - h

            row, h = W:DualRow(parent, y,
                { type="slider", text="Frame Width",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  min=220, max=420, step=10, isPercent=false,
                  getValue=function() return Cfg("frameWidth") or 260 end,
                  setValue=function(v) Set("frameWidth", v); Refresh() end },
                { type="slider", text="Bar Width",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  min=120, max=360, step=10, isPercent=false,
                  getValue=function() return Cfg("barWidth") or 220 end,
                  setValue=function(v) Set("barWidth", v); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="slider", text="Timer Bar Height",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  min=6, max=30, step=1, isPercent=false,
                  getValue=function() return Cfg("timerBarHeight") or 10 end,
                  setValue=function(v) Set("timerBarHeight", v); Refresh() end },
                { type="slider", text="Enemy Bar Height",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  min=4, max=20, step=1, isPercent=false,
                  getValue=function() return Cfg("enemyBarHeight") or 6 end,
                  setValue=function(v) Set("enemyBarHeight", v); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="slider", text="Element Spacing",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  min=0, max=16, step=1, isPercent=false,
                  getValue=function() return Cfg("rowGap") or 6 end,
                  setValue=function(v) Set("rowGap", v); Refresh() end },
                { type="slider", text="Objective Spacing",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  min=0, max=12, step=1, isPercent=false,
                  getValue=function() return Cfg("objectiveGap") or 3 end,
                  setValue=function(v) Set("objectiveGap", v); Refresh() end })
            y = y - h

            -- ── COLORS ────────────────────────────────────────────────────
            _, h = W:SectionHeader(parent, "COLORS", y); y = y - h

            row, h = W:DualRow(parent, y,
                { type="colorpicker", text="Timer Running",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function()
                      local c = Cfg("timerRunningColor")
                      if c then return c.r or 1, c.g or 1, c.b or 1 end
                      return 1, 1, 1
                  end,
                  setValue=function(r, g, b) Set("timerRunningColor", { r = r, g = g, b = b }); Refresh() end },
                { type="colorpicker", text="Timer Warning",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function()
                      local c = Cfg("timerWarningColor")
                      if c then return c.r or 0.9, c.g or 0.7, c.b or 0.2 end
                      return 0.9, 0.7, 0.2
                  end,
                  setValue=function(r, g, b) Set("timerWarningColor", { r = r, g = g, b = b }); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="colorpicker", text="Timer Expired",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function()
                      local c = Cfg("timerExpiredColor")
                      if c then return c.r or 0.9, c.g or 0.2, c.b or 0.2 end
                      return 0.9, 0.2, 0.2
                  end,
                  setValue=function(r, g, b) Set("timerExpiredColor", { r = r, g = g, b = b }); Refresh() end },
                { type="colorpicker", text="+3 Text",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function()
                      local c = Cfg("timerPlusThreeColor")
                      if c then return c.r or 0.3, c.g or 0.8, c.b or 1 end
                      return 0.3, 0.8, 1
                  end,
                  setValue=function(r, g, b) Set("timerPlusThreeColor", { r = r, g = g, b = b }); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="colorpicker", text="+2 Text",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function()
                      local c = Cfg("timerPlusTwoColor")
                      if c then return c.r or 0.4, c.g or 1, c.b or 0.4 end
                      return 0.4, 1, 0.4
                  end,
                  setValue=function(r, g, b) Set("timerPlusTwoColor", { r = r, g = g, b = b }); Refresh() end },
                { type="colorpicker", text="Bar Past +3",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function()
                      local c = Cfg("timerBarPastPlusThreeColor")
                      if c then return c.r or 0.3, c.g or 0.8, c.b or 1 end
                      return 0.3, 0.8, 1
                  end,
                  setValue=function(r, g, b) Set("timerBarPastPlusThreeColor", { r = r, g = g, b = b }); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="colorpicker", text="Bar Past +2",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function()
                      local c = Cfg("timerBarPastPlusTwoColor")
                      if c then return c.r or 0.4, c.g or 1, c.b or 0.4 end
                      return 0.4, 1, 0.4
                  end,
                  setValue=function(r, g, b) Set("timerBarPastPlusTwoColor", { r = r, g = g, b = b }); Refresh() end },
                { type="colorpicker", text="Objective Active",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function()
                      local c = Cfg("objectiveTextColor")
                      if c then return c.r or 0.9, c.g or 0.9, c.b or 0.9 end
                      return 0.9, 0.9, 0.9
                  end,
                  setValue=function(r, g, b) Set("objectiveTextColor", { r = r, g = g, b = b }); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="colorpicker", text="Objective Complete",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function()
                      local c = Cfg("objectiveCompletedColor")
                      if c then return c.r or 0.3, c.g or 0.8, c.b or 0.3 end
                      return 0.3, 0.8, 0.3
                  end,
                  setValue=function(r, g, b) Set("objectiveCompletedColor", { r = r, g = g, b = b }); Refresh() end },
                { type="colorpicker", text="Deaths",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function()
                      local c = Cfg("deathTextColor")
                      if c then return c.r or 0.93, c.g or 0.33, c.b or 0.33 end
                      return 0.93, 0.33, 0.33
                  end,
                  setValue=function(r, g, b) Set("deathTextColor", { r = r, g = g, b = b }); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="colorpicker", text="Split Faster",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function()
                      local c = Cfg("splitFasterColor")
                      if c then return c.r or 0.4, c.g or 1, c.b or 0.4 end
                      return 0.4, 1, 0.4
                  end,
                  setValue=function(r, g, b) Set("splitFasterColor", { r = r, g = g, b = b }); Refresh() end },
                { type="colorpicker", text="Split Slower",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function()
                      local c = Cfg("splitSlowerColor")
                      if c then return c.r or 1, c.g or 0.45, c.b or 0.45 end
                      return 1, 0.45, 0.45
                  end,
                  setValue=function(r, g, b) Set("splitSlowerColor", { r = r, g = g, b = b }); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="colorpicker", text="Enemy Bar Solid",
                  disabled=function() return Cfg("enabled") == false or (Cfg("enemyBarColorMode") or "PROGRESS") ~= "SOLID" end,
                  disabledTooltip="Requires Enemy Bar Color: Solid",
                  getValue=function()
                      local c = Cfg("enemyBarSolidColor")
                      if c then return c.r or 0.35, c.g or 0.55, c.b or 0.8 end
                      return 0.35, 0.55, 0.8
                  end,
                  setValue=function(r, g, b) Set("enemyBarSolidColor", { r = r, g = g, b = b }); Refresh() end },
                { type="colorpicker", text="Enemy 0-25%",
                  disabled=function() return Cfg("enabled") == false or (Cfg("enemyBarColorMode") or "PROGRESS") ~= "PROGRESS" end,
                  disabledTooltip="Requires Enemy Bar Color: Progress",
                  getValue=function()
                      local c = Cfg("enemy0to25Color")
                      if c then return c.r or 0.9, c.g or 0.25, c.b or 0.25 end
                      return 0.9, 0.25, 0.25
                  end,
                  setValue=function(r, g, b) Set("enemy0to25Color", { r = r, g = g, b = b }); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="colorpicker", text="Enemy 25-50%",
                  disabled=function() return Cfg("enabled") == false or (Cfg("enemyBarColorMode") or "PROGRESS") ~= "PROGRESS" end,
                  disabledTooltip="Requires Enemy Bar Color: Progress",
                  getValue=function()
                      local c = Cfg("enemy25to50Color")
                      if c then return c.r or 0.95, c.g or 0.6, c.b or 0.2 end
                      return 0.95, 0.6, 0.2
                  end,
                  setValue=function(r, g, b) Set("enemy25to50Color", { r = r, g = g, b = b }); Refresh() end },
                { type="colorpicker", text="Enemy 50-75%",
                  disabled=function() return Cfg("enabled") == false or (Cfg("enemyBarColorMode") or "PROGRESS") ~= "PROGRESS" end,
                  disabledTooltip="Requires Enemy Bar Color: Progress",
                  getValue=function()
                      local c = Cfg("enemy50to75Color")
                      if c then return c.r or 0.95, c.g or 0.85, c.b or 0.2 end
                      return 0.95, 0.85, 0.2
                  end,
                  setValue=function(r, g, b) Set("enemy50to75Color", { r = r, g = g, b = b }); Refresh() end })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="colorpicker", text="Enemy 75-100%",
                  disabled=function() return Cfg("enabled") == false or (Cfg("enemyBarColorMode") or "PROGRESS") ~= "PROGRESS" end,
                  disabledTooltip="Requires Enemy Bar Color: Progress",
                  getValue=function()
                      local c = Cfg("enemy75to100Color")
                      if c then return c.r or 0.3, c.g or 0.8, c.b or 0.3 end
                      return 0.3, 0.8, 0.3
                  end,
                  setValue=function(r, g, b) Set("enemy75to100Color", { r = r, g = g, b = b }); Refresh() end },
                { type="label", text="" })
            y = y - h
        end

        parent:SetHeight(math.abs(y - yOffset))
    end

    -- RegisterModule
    EllesmereUI:RegisterModule("EllesmereUIMythicTimer", {
        title    = "Mythic+ Timer",
        icon_on  = "Interface\\AddOns\\EllesmereUI\\media\\icons\\sidebar\\consumables-ig.tga",
        icon_off = "Interface\\AddOns\\EllesmereUI\\media\\icons\\sidebar\\consumables-g.tga",
        pages    = { PAGE_DISPLAY, PAGE_BEST_RUNS },
        buildPage = BuildPage,
        onReset  = function()
            if EllesmereUIMythicTimerDB then
                EllesmereUIMythicTimerDB.profiles = nil
                EllesmereUIMythicTimerDB.profileKeys = nil
            end
        end,
    })
end)
