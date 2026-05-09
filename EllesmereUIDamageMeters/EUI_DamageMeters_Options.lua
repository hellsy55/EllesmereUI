-------------------------------------------------------------------------------
--  EUI_DamageMeters_Options.lua
--  Options page for EllesmereUI Damage Meters.
--  All settings are live (no Edit Mode, no reload required).
-------------------------------------------------------------------------------
local _, ns = ...
local EDM = ns.EDM

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    if not EDM then return end
    -- Do nothing if the module is disabled / coming soon
    if not _G._EDM_DB then return end

    local function DB()
        local d = _G._EDM_DB
        if d and d.profile and d.profile.dm then return d.profile.dm end
        return {}
    end
    local function Cfg(k)    return DB()[k]  end
    local function Set(k, v) DB()[k] = v     end

    -- All settings are picked up on the next refresh cycle (0.3s combat,
    -- 2s idle). Just Set() and go.

    -- Bar texture dropdown values (same pattern as Resource Bars / Nameplates)
    local dmTexValues = {}
    local dmTexOrder = {}
    do
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(
                _G._EDM_BarTextureNames or {},
                _G._EDM_BarTextureOrder or {},
                nil,
                _G._EDM_BarTextures
            )
        end
        local texNames = _G._EDM_BarTextureNames or {}
        local texOrder2 = _G._EDM_BarTextureOrder or {}
        local texLookup = _G._EDM_BarTextures or {}
        for _, key in ipairs(texOrder2) do
            if key ~= "---" then
                dmTexValues[key] = texNames[key] or key
            end
            dmTexOrder[#dmTexOrder + 1] = key
        end
        dmTexValues._menuOpts = {
            itemHeight = 28,
            background = function(key) return texLookup[key] end,
        }
    end

    local function BuildPage(_, parent, yOffset)
        local W  = EllesmereUI.Widgets
        local PP = EllesmereUI.PP
        local y  = yOffset
        local h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        local function Refresh() if ns.RefreshMeter then ns.RefreshMeter() end end
        local function ApplyHdr() if ns.ApplyHeader then ns.ApplyHeader() end end

        -- ── DISPLAY ─────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

        -- Visibility | Visibility Options
        local dmVisValues = {}
        local dmVisOrder = {}
        for _, key in ipairs(EllesmereUI.VIS_ORDER) do
            dmVisValues[key] = EllesmereUI.VIS_VALUES[key]
            dmVisOrder[#dmVisOrder + 1] = key
        end
        local visRow
        visRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Visibility",
              values = dmVisValues,
              order  = dmVisOrder,
              getValue=function() return Cfg("visibility") or "always" end,
              setValue=function(v) Set("visibility", v); if EllesmereUI.RequestVisibilityUpdate then EllesmereUI.RequestVisibilityUpdate() end end },
            { type="dropdown", text="Visibility Options",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end })
        do
            local rightRgn = visRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                EllesmereUI.VIS_OPT_ITEMS,
                function(k) return Cfg(k) or false end,
                function(k, v) Set(k, v); if EllesmereUI.RequestVisibilityUpdate then EllesmereUI.RequestVisibilityUpdate() end end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        y = y - h

        -- Background Opacity (+ inline color swatch) | Header Opacity (+ inline color swatch)
        local bgRow
        bgRow, h = W:DualRow(parent, y,
            { type="slider", text="Background Opacity",
              min = 0, max = 1, step = 0.05,
              getValue = function() return Cfg("bgAlpha") or 0.75 end,
              setValue = function(v) Set("bgAlpha", v); if ns.ApplyBackground then ns.ApplyBackground() end end },
            { type="slider", text="Header Opacity",
              min = 0, max = 1, step = 0.05,
              getValue = function() return Cfg("hdrBgAlpha") or 1 end,
              setValue = function(v) Set("hdrBgAlpha", v); ApplyHdr() end })
        -- Inline color swatch on Background Opacity
        do
            local rgn = bgRow._leftRegion
            local ctrl = rgn._control
            local bgSwatch, bgSwatchRefresh = EllesmereUI.BuildColorSwatch(
                rgn, bgRow:GetFrameLevel() + 3,
                function()
                    return (Cfg("bgR") or 0), (Cfg("bgG") or 0), (Cfg("bgB") or 0)
                end,
                function(r, g, b)
                    Set("bgR", r); Set("bgG", g); Set("bgB", b)
                    if ns.ApplyBackground then ns.ApplyBackground() end
                end,
                false, 20)
            PP.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(function() bgSwatchRefresh() end)
        end
        -- Inline color swatch on Header Opacity
        do
            local rgn = bgRow._rightRegion
            local ctrl = rgn._control
            local hdrSwatch, hdrSwatchRefresh = EllesmereUI.BuildColorSwatch(
                rgn, bgRow:GetFrameLevel() + 3,
                function()
                    local c = Cfg("hdrBgColor")
                    if c then return c.r or 0x1B/255, c.g or 0x1B/255, c.b or 0x1B/255 end
                    return 0x1B/255, 0x1B/255, 0x1B/255
                end,
                function(r, g, b)
                    Set("hdrBgColor", { r = r, g = g, b = b })
                    ApplyHdr()
                end,
                false, 20)
            PP.Point(hdrSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(function() hdrSwatchRefresh() end)
        end
        y = y - h

        -- Header Text Color | Header Icon Color
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Header Text Color",
              swatches = {
                  { tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local c = Cfg("hdrTextColor")
                        if c then return c.r or 1, c.g or 1, c.b or 1 end
                        return 1, 1, 1
                    end,
                    setValue = function(r, g, b)
                        Set("hdrTextColor", { r = r, g = g, b = b })
                        ApplyHdr()
                    end,
                    onClick = function(self)
                        if Cfg("hdrTextUseAccent") ~= false then
                            Set("hdrTextUseAccent", false)
                            ApplyHdr(); EllesmereUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        return Cfg("hdrTextUseAccent") ~= false and 0.3 or 1
                    end },
                  { tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        return EllesmereUI.ResolveThemeColor(EllesmereUI.GetActiveTheme())
                    end,
                    setValue = function() end,
                    onClick = function()
                        Set("hdrTextUseAccent", true)
                        ApplyHdr(); EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return Cfg("hdrTextUseAccent") ~= false and 1 or 0.3
                    end },
              } },
            { type="multiSwatch", text="Header Icon Color",
              swatches = {
                  { tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local c = Cfg("iconColor")
                        if c then return c.r or 1, c.g or 1, c.b or 1 end
                        return 1, 1, 1
                    end,
                    setValue = function(r, g, b)
                        Set("iconColor", { r = r, g = g, b = b })
                        if ns.ApplyIconColor then ns.ApplyIconColor() end
                    end,
                    onClick = function(self)
                        if Cfg("iconColorUseAccent") then
                            Set("iconColorUseAccent", false)
                            if ns.ApplyIconColor then ns.ApplyIconColor() end
                            EllesmereUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        return Cfg("iconColorUseAccent") and 0.3 or 1
                    end },
                  { tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        return EllesmereUI.ResolveThemeColor(EllesmereUI.GetActiveTheme())
                    end,
                    setValue = function() end,
                    onClick = function()
                        Set("iconColorUseAccent", true)
                        if ns.ApplyIconColor then ns.ApplyIconColor() end
                        EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return Cfg("iconColorUseAccent") and 1 or 0.3
                    end },
              } })
        y = y - h

        -- ── BAR DESIGN ──────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "BAR DESIGN", y); y = y - h

        -- Bar Texture | Bar Height
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Bar Texture",
              values = dmTexValues, order = dmTexOrder,
              getValue = function() return Cfg("barTexture") or "none" end,
              setValue = function(v) Set("barTexture", v); Refresh() end },
            { type="slider", text="Bar Height", min = 8, max = 40, step = 1,
              getValue = function() return Cfg("barHeight") or 18 end,
              setValue = function(v) Set("barHeight", v); Refresh() end })
        y = y - h

        -- Bar Spacing | Bar Color
        _, h = W:DualRow(parent, y,
            { type="slider", text="Bar Spacing", min = 0, max = 10, step = 1,
              getValue = function() return Cfg("barSpacing") or 2 end,
              setValue = function(v) Set("barSpacing", v); Refresh() end },
            { type="multiSwatch", text="Bar Color",
              swatches = {
                  { tooltip = "Class Color",
                    hasAlpha = false,
                    getValue = function()
                        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS["PALADIN"]
                        if cc then return cc.r, cc.g, cc.b end
                        return 0.96, 0.55, 0.73
                    end,
                    setValue = function() end,
                    onClick = function()
                        Set("showClassColor", true)
                        Refresh(); EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return Cfg("showClassColor") ~= false and 1 or 0.3
                    end },
                  { tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local c = Cfg("barColor")
                        if c then return c.r or 0.35, c.g or 0.55, c.b or 0.8 end
                        return 0.35, 0.55, 0.8
                    end,
                    setValue = function(r, g, b)
                        Set("barColor", { r = r, g = g, b = b })
                        Set("showClassColor", false); Set("barColorUseAccent", false)
                        Refresh(); EllesmereUI:RefreshPage()
                    end,
                    onClick = function(self)
                        if Cfg("showClassColor") ~= false or Cfg("barColorUseAccent") ~= false then
                            Set("showClassColor", false); Set("barColorUseAccent", false)
                            Refresh(); EllesmereUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        if Cfg("showClassColor") ~= false then return 0.15 end
                        return Cfg("barColorUseAccent") ~= false and 0.3 or 1
                    end },
                  { tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        return EllesmereUI.ResolveThemeColor(EllesmereUI.GetActiveTheme())
                    end,
                    setValue = function() end,
                    onClick = function()
                        Set("showClassColor", false); Set("barColorUseAccent", true)
                        Refresh(); EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        if Cfg("showClassColor") ~= false then return 0.15 end
                        return Cfg("barColorUseAccent") ~= false and 1 or 0.3
                    end },
              } })
        y = y - h

        -- Font Size | Number Format
        _, h = W:DualRow(parent, y,
            { type="slider", text="Font Size", min = 8, max = 18, step = 1,
              getValue = function() return Cfg("fontSize") or 11 end,
              setValue = function(v) Set("fontSize", v); Refresh() end },
            { type="dropdown", text="Number Format",
              values = { [0] = "DPS", [1] = "Damage", [2] = "Damage (DPS)" },
              order = { 0, 1, 2 },
              getValue = function() return Cfg("numberFormat") or 2 end,
              setValue = function(v) Set("numberFormat", v); Refresh() end })
        y = y - h

        -- Icon Style | Show Breakdown on Hover (with inline cog for scale)
        local hoverRow
        hoverRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Icon Style",
              values = _G._EDM_IconStyleValues or {},
              order  = _G._EDM_IconStyleOrder or {},
              getValue = function() return Cfg("iconStyle") or "spec" end,
              setValue = function(v) Set("iconStyle", v); Refresh() end },
            { type="toggle", text="Show Breakdown on Hover",
              getValue = function() return Cfg("showHoverTooltip") ~= false end,
              setValue = function(v) Set("showHoverTooltip", v) end })
        do
            local rgn = hoverRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Hover Tooltip Scale",
                rows = {
                    { type = "slider", label = "Scale", min = 80, max = 150, step = 1,
                      get = function() return (Cfg("hoverTooltipScale") or 100) end,
                      set = function(v) Set("hoverTooltipScale", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end
        y = y - h

        -- Always Show Player | (empty)
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Always Show Player",
              tooltip = "This will pin your bar to the window when it is not within the visible area",
              getValue = function() return Cfg("showPinnedSelf") ~= false end,
              setValue = function(v) Set("showPinnedSelf", v); Refresh() end },
            { type="label", text="" })
        y = y - h

        -- ── EXTRAS ──────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

        local function ApplySAT() if ns.ApplySATimer then ns.ApplySATimer() end end

        -- Refresh Rate | Standalone Combat Timer (with inline cog for font size)
        local rrRow
        rrRow, h = W:DualRow(parent, y,
            { type="slider", text="Refresh Rate",
              tooltip = "Increase to improve performance, Decrease to update meters faster",
              min = 0.1, max = 1, step = 0.05,
              getValue = function() return Cfg("refreshRate") or 0.5 end,
              setValue = function(v) Set("refreshRate", v) end,
              fmt = function(v) return format("%.2fs", v) end },
            { type="toggle", text="Standalone Combat Timer",
              getValue = function() return Cfg("standaloneTimer") or false end,
              setValue = function(v)
                  Set("standaloneTimer", v); ApplySAT(); EllesmereUI:RefreshPage()
                  if v and ns.ShowSATimerPreview then ns.ShowSATimerPreview()
                  elseif not v and ns.HideSATimerPreview then ns.HideSATimerPreview() end
              end })
        -- Add "(seconds)" suffix to Refresh Rate label
        do
            local rgn = rrRow._leftRegion
            local suffix = rgn:CreateFontString(nil, "OVERLAY")
            suffix:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
            suffix:SetTextColor(1, 1, 1, 0.35)
            local rrLabel
            for i = 1, rgn:GetNumRegions() do
                local reg = select(i, rgn:GetRegions())
                if reg and reg.GetText and reg:GetText() == "Refresh Rate" then
                    rrLabel = reg
                    break
                end
            end
            if rrLabel then
                suffix:SetPoint("LEFT", rrLabel, "RIGHT", 5, 0)
            else
                suffix:SetPoint("LEFT", rgn, "LEFT", 150, 0)
            end
            suffix:SetText("(seconds)")
        end
        -- Inline cog (RESIZE) on Standalone Combat Timer for font size
        do
            local rgn = rrRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Standalone Timer Settings",
                rows = {
                    { type = "slider", label = "Font Size", min = 10, max = 40, step = 1,
                      get = function() return Cfg("standaloneTimerSize") or 26 end,
                      set = function(v) Set("standaloneTimerSize", v); ApplySAT() end },
                    { type = "toggle", label = "Align Text Left",
                      get = function() return Cfg("standaloneTimerAlignLeft") or false end,
                      set = function(v) Set("standaloneTimerAlignLeft", v); ApplySAT() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end
        y = y - h

        -- "Hold Shift+Click..." label | Timer Text Color
        _, h = W:DualRow(parent, y,
            { type="label", text="Hold Shift+Click to Freely Move Standalone Timer" },
            { type="multiSwatch", text="Timer Text Color",
              disabled = function() return not Cfg("standaloneTimer") end,
              disabledTooltip = "Standalone Combat Timer to be enabled",
              swatches = {
                  { tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local c = Cfg("standaloneTimerColor")
                        if c then return c.r or 1, c.g or 1, c.b or 1 end
                        return 1, 1, 1
                    end,
                    setValue = function(r, g, b)
                        Set("standaloneTimerColor", { r = r, g = g, b = b })
                        ApplySAT()
                    end,
                    onClick = function(self)
                        if Cfg("standaloneTimerUseAccent") then
                            Set("standaloneTimerUseAccent", false)
                            ApplySAT(); EllesmereUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        if not Cfg("standaloneTimer") then return 0.15 end
                        return Cfg("standaloneTimerUseAccent") and 0.3 or 1
                    end },
                  { tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        return EllesmereUI.ResolveThemeColor(EllesmereUI.GetActiveTheme())
                    end,
                    setValue = function() end,
                    onClick = function()
                        Set("standaloneTimerUseAccent", true)
                        ApplySAT(); EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        if not Cfg("standaloneTimer") then return 0.15 end
                        return Cfg("standaloneTimerUseAccent") and 1 or 0.3
                    end },
              } })
        y = y - h

        return math.abs(y)
    end

    EllesmereUI:RegisterModule("EllesmereUIDamageMeters", {
        title       = "Damage Meters",
        description = "Custom damage meter using Blizzard's built-in combat data.",
        searchTerms = "damage meters dps hps healing interrupts dispels",
        pages       = { "Damage Meters" },
        buildPage   = function(pageName, p, yOffset)
            if ns.ShowSATimerPreview then ns.ShowSATimerPreview() end
            return BuildPage(pageName, p, yOffset)
        end,
        onPageCacheRestore = function()
            if ns.ShowSATimerPreview then ns.ShowSATimerPreview() end
        end,
        onReset = function()
            local d = _G._EDM_DB
            if d and d.ResetProfile then d:ResetProfile() end
        end,
    })

    -- Show preview when panel opens on DM page, hide when panel closes
    if EllesmereUI.RegisterOnShow then
        EllesmereUI:RegisterOnShow(function()
            if EllesmereUI:GetActiveModule() == "EllesmereUIDamageMeters" then
                if ns.ShowSATimerPreview then ns.ShowSATimerPreview() end
            end
        end)
    end
    if EllesmereUI.RegisterOnHide then
        EllesmereUI:RegisterOnHide(function()
            if ns.HideSATimerPreview then ns.HideSATimerPreview() end
        end)
    end
end)
