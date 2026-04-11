-------------------------------------------------------------------------------
--  EUI_MythicTimer_Options.lua
--  Registers the Mythic+ Timer module with EllesmereUI sidebar options.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_DISPLAY = "Mythic+ Timer"

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
        if p then p[key] = val end
    end

    local function Refresh()
        if _G._EMT_Apply then _G._EMT_Apply() end
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
    end

    ---------------------------------------------------------------------------
    --  Build Page
    ---------------------------------------------------------------------------
    local function BuildPage(_, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        local alignValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
        local alignOrder  = { "LEFT", "CENTER", "RIGHT" }

        -- ── DISPLAY ────────────────────────────────────────────────────────
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
            { type="toggle", text="Show Accent Stripe",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("showAccent") == true end,
              setValue=function(v) Set("showAccent", v); Refresh() end },
            { type="dropdown", text="Title / Affix Align",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              values=alignValues,
              order=alignOrder,
              getValue=function() return Cfg("titleAlign") or "CENTER" end,
              setValue=function(v) Set("titleAlign", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Objective Align",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              values=alignValues,
              order=alignOrder,
              getValue=function() return Cfg("objectiveAlign") or "LEFT" end,
              setValue=function(v) Set("objectiveAlign", v); Refresh() end },
            { type="dropdown", text="Timer Align",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              values=alignValues,
              order=alignOrder,
              getValue=function() return Cfg("timerAlign") or "CENTER" end,
              setValue=function(v) Set("timerAlign", v); Refresh() end })
        y = y - h

        -- ── TIMER ──────────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "TIMER", y); y = y - h

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
              end },
            { type="label", text="" })
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

        -- ── OBJECTIVES ─────────────────────────────────────────────────────
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
            { type="toggle", text="Show Deaths",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("showDeaths") ~= false end,
              setValue=function(v) Set("showDeaths", v); Refresh() end },
            { type="toggle", text="Deaths in Title",
              disabled=function() return Cfg("enabled") == false or Cfg("showDeaths") == false end,
              disabledTooltip=function()
                  if Cfg("enabled") == false then return "the module" end
                  return "Show Deaths"
              end,
              getValue=function() return Cfg("deathsInTitle") == true end,
              setValue=function(v) Set("deathsInTitle", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Time Lost in Title",
              disabled=function() return Cfg("enabled") == false or Cfg("showDeaths") == false or Cfg("deathsInTitle") ~= true end,
              disabledTooltip=function()
                  if Cfg("enabled") == false then return "the module" end
                  if Cfg("showDeaths") == false then return "Show Deaths" end
                  return "Deaths in Title"
              end,
              getValue=function() return Cfg("deathTimeInTitle") == true end,
              setValue=function(v) Set("deathTimeInTitle", v); Refresh() end },
            { type="toggle", text="Show Enemy Forces",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("showEnemyBar") ~= false end,
              setValue=function(v) Set("showEnemyBar", v); Refresh() end })
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
            { type="dropdown", text="Enemy Forces %",
              disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
              disabledTooltip="Requires Show Enemy Forces",
              values={ LABEL = "In Label Text", BAR = "In Bar", BESIDE = "Beside Bar" },
              order={ "LABEL", "BAR", "BESIDE" },
              getValue=function() return Cfg("enemyForcesPctPos") or "LABEL" end,
              setValue=function(v) Set("enemyForcesPctPos", v); Refresh() end },
            { type="label", text="" })
        y = y - h

        parent:SetHeight(math.abs(y - yOffset))
    end

    ---------------------------------------------------------------------------
    --  RegisterModule
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIMythicTimer", {
        title    = "Mythic+ Timer",
        icon_on  = "Interface\\AddOns\\EllesmereUI\\media\\icons\\sidebar\\consumables-ig.tga",
        icon_off = "Interface\\AddOns\\EllesmereUI\\media\\icons\\sidebar\\consumables-g.tga",
        pages    = { PAGE_DISPLAY },
        buildPage = BuildPage,
    })
end)
