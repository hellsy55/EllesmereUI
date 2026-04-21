-------------------------------------------------------------------------------
--  EUI_DragonRiding_Options.lua  —  Options page for Dragon Riding HUD
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local function DB()
        return _G._EDR_AceDB and _G._EDR_AceDB.profile
    end
    local function Cfg(k) local p = DB(); return p and p[k] end
    local function Set(k, v) local p = DB(); if p then p[k] = v end end
    -- SetField writes into a nested table (e.g. db.profile.speedText.size).
    -- Guards mirror the Cfg() "or {}" pattern on the getter side so a missing
    -- subtable never raises; DeepMergeDefaults normally keeps these present.
    local function SetField(k, field, v)
        local t = Cfg(k); if t then t[field] = v end
    end
    local function Rebuild() if _G._EDR_Rebuild then _G._EDR_Rebuild() end
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
    end
    local function Redraw() if _G._EDR_Redraw then _G._EDR_Redraw() end end

    local function MakeCogBtn(rgn, showFn, iconPath)
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints()
        cogTex:SetTexture(iconPath or EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
        cogBtn:SetScript("OnClick", function(s) showFn(s) end)
        return cogBtn
    end

    local function BuildPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        -- ── GENERAL ────────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "GENERAL", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enabled",
              getValue = function() return Cfg("enabled") == true end,
              setValue = function(v) Set("enabled", v); Rebuild() end },
            { type = "toggle", text = "Hide in Combat",
              getValue = function() return Cfg("hideInCombat") == true end,
              setValue = function(v) Set("hideInCombat", v); Rebuild() end }
        ); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Width", min = 80, max = 600, step = 1,
              getValue = function() return Cfg("width") end,
              setValue = function(v) Set("width", v); Rebuild() end },
            { type = "slider", text = "Inter-Element Gap", min = 0, max = 12, step = 1,
              getValue = function() return Cfg("gap") end,
              setValue = function(v) Set("gap", v); Rebuild() end }
        ); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Stack Spacing", min = 0, max = 10, step = 1,
              getValue = function() return Cfg("stackSpacing") end,
              setValue = function(v) Set("stackSpacing", v); Rebuild() end },
            { text = "" }  -- empty right half preserves dual-column layout
        ); y = y - h
        _, h = W:Spacer(parent, y, 20); y = y - h

        -- ── BORDERS ────────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "BORDERS", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Borders",
              getValue = function() return Cfg("borderEnabled") == true end,
              setValue = function(v) Set("borderEnabled", v); Redraw() end },
            { type = "slider", text = "Thickness", min = 1, max = 4, step = 1,
              getValue = function() return Cfg("borderThickness") end,
              setValue = function(v) Set("borderThickness", v); Redraw() end }
        ); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "colorpicker", text = "Border Color", hasAlpha = true,
              getValue = function() local t = Cfg("borderColor"); return t.r, t.g, t.b, t.a end,
              setValue = function(r, g, b, a)
                  local p = Cfg("borderColor")
                  p.r, p.g, p.b, p.a = r, g, b, a
                  Redraw()
              end },
            { text = "" }
        ); y = y - h
        _, h = W:Spacer(parent, y, 20); y = y - h

        local justifyValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
        local justifyOrder  = { "LEFT", "CENTER", "RIGHT" }

        -- ── SPEED BAR ──────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "SPEED BAR", y); y = y - h

        -- Height + Thrill Color toggle
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Height", min = 4, max = 40, step = 1,
              getValue = function() return Cfg("speedHeight") end,
              setValue = function(v) Set("speedHeight", v); Rebuild() end },
            { type = "toggle", text = "Thrill Color Change",
              getValue = function() return Cfg("thrillColorToggle") == true end,
              setValue = function(v) Set("thrillColorToggle", v); Redraw() end }
        ); y = y - h

        -- Colors: Speed (normal + background) | Thrill (thrill + tick)
        _, h = W:DualRow(parent, y,
            { type = "multiSwatch", text = "Color",
              swatches = {
                { text = "Normal",
                  getValue = function() local t = Cfg("normalColor"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = Cfg("normalColor"); p.r, p.g, p.b, p.a = r, g, b, a; Redraw() end,
                  hasAlpha = true,
                  tooltip = "Speed bar fill when below Thrill threshold." },
                { text = "Background",
                  getValue = function() local t = Cfg("speedBarBg"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = Cfg("speedBarBg"); p.r, p.g, p.b, p.a = r, g, b, a; Redraw() end,
                  hasAlpha = true,
                  tooltip = "Speed bar background." },
              } },
            { type = "multiSwatch", text = "Thrill Color",
              swatches = {
                { text = "Thrill",
                  getValue = function() local t = Cfg("thrillColor"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = Cfg("thrillColor"); p.r, p.g, p.b, p.a = r, g, b, a; Redraw() end,
                  hasAlpha = true,
                  tooltip = "Speed bar fill when above Thrill threshold." },
                { text = "Tick",
                  getValue = function() local t = Cfg("tickColor"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = Cfg("tickColor"); p.r, p.g, p.b, p.a = r, g, b, a; Redraw() end,
                  hasAlpha = true,
                  tooltip = "Thrill threshold tick mark." },
              } }
        ); y = y - h

        -- Speed text: enabled + justify (cog for size/offsetX/offsetY)
        local speedTextRow
        speedTextRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Speed Text",
              getValue = function() return Cfg("speedText") and Cfg("speedText").enabled ~= false end,
              setValue = function(v) SetField("speedText", "enabled", v); Redraw() end },
            { type = "dropdown", text = "Speed Text Justify",
              values = justifyValues, order = justifyOrder,
              getValue = function() return (Cfg("speedText") or {}).justify or "CENTER" end,
              setValue = function(v) SetField("speedText", "justify", v); Redraw() end }
        )
        do
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Speed Text Position",
                rows = {
                    { type = "slider", label = "Size",     min = 6,    max = 32,  step = 1,
                      get = function() return (Cfg("speedText") or {}).size    or 12 end,
                      set = function(v) SetField("speedText", "size",    v); Redraw() end },
                    { type = "slider", label = "Offset X", min = -200, max = 200, step = 1,
                      get = function() return (Cfg("speedText") or {}).offsetX or 0  end,
                      set = function(v) SetField("speedText", "offsetX", v); Redraw() end },
                    { type = "slider", label = "Offset Y", min = -200, max = 200, step = 1,
                      get = function() return (Cfg("speedText") or {}).offsetY or 0  end,
                      set = function(v) SetField("speedText", "offsetY", v); Redraw() end },
                },
            })
            MakeCogBtn(speedTextRow._rightRegion, cogShow, EllesmereUI.RESIZE_ICON)
        end
        y = y - h

        _, h = W:Spacer(parent, y, 20); y = y - h

        -- ── SKYRIDING STACKS ───────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "SKYRIDING STACKS", y); y = y - h

        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Height", min = 2, max = 24, step = 1,
              getValue = function() return Cfg("skyridingHeight") end,
              setValue = function(v) Set("skyridingHeight", v); Rebuild() end },
            { type = "multiSwatch", text = "Color",
              swatches = {
                { text = "Filled",
                  getValue = function() local t = Cfg("skyridingFilled"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = Cfg("skyridingFilled"); p.r, p.g, p.b, p.a = r, g, b, a; Redraw() end,
                  hasAlpha = true,
                  tooltip = "Active stack color." },
                { text = "Background",
                  getValue = function() local t = Cfg("skyridingBg"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = Cfg("skyridingBg"); p.r, p.g, p.b, p.a = r, g, b, a; Redraw() end,
                  hasAlpha = true,
                  tooltip = "Empty stack background." },
              } }
        ); y = y - h

        _, h = W:Spacer(parent, y, 20); y = y - h

        -- ── SECOND WIND ────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "SECOND WIND", y); y = y - h

        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Height", min = 2, max = 24, step = 1,
              getValue = function() return Cfg("secondWindHeight") end,
              setValue = function(v) Set("secondWindHeight", v); Rebuild() end },
            { type = "multiSwatch", text = "Color",
              swatches = {
                { text = "Filled",
                  getValue = function() local t = Cfg("secondWindFilled"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = Cfg("secondWindFilled"); p.r, p.g, p.b, p.a = r, g, b, a; Redraw() end,
                  hasAlpha = true,
                  tooltip = "Active Second Wind charge color." },
                { text = "Background",
                  getValue = function() local t = Cfg("secondWindBg"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = Cfg("secondWindBg"); p.r, p.g, p.b, p.a = r, g, b, a; Redraw() end,
                  hasAlpha = true,
                  tooltip = "Empty Second Wind charge background." },
              } }
        ); y = y - h

        _, h = W:Spacer(parent, y, 20); y = y - h

        -- ── WHIRLING SURGE ─────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "WHIRLING SURGE", y); y = y - h

        -- Cooldown Text: enabled (cog for size/offsetX/offsetY). Justify is
        -- always CENTER for the small square icon; x/y offsets cover the rest.
        local wsTextRow
        wsTextRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Cooldown Text",
              getValue = function() return Cfg("whirlingSurgeText") and Cfg("whirlingSurgeText").enabled ~= false end,
              setValue = function(v) SetField("whirlingSurgeText", "enabled", v); Redraw() end },
            { text = "" }
        )
        do
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Cooldown Text Position",
                rows = {
                    { type = "slider", label = "Size",     min = 6,    max = 32,  step = 1,
                      get = function() return (Cfg("whirlingSurgeText") or {}).size    or 12 end,
                      set = function(v) SetField("whirlingSurgeText", "size",    v); Redraw() end },
                    { type = "slider", label = "Offset X", min = -200, max = 200, step = 1,
                      get = function() return (Cfg("whirlingSurgeText") or {}).offsetX or 0  end,
                      set = function(v) SetField("whirlingSurgeText", "offsetX", v); Redraw() end },
                    { type = "slider", label = "Offset Y", min = -200, max = 200, step = 1,
                      get = function() return (Cfg("whirlingSurgeText") or {}).offsetY or 0  end,
                      set = function(v) SetField("whirlingSurgeText", "offsetY", v); Redraw() end },
                },
            })
            MakeCogBtn(wsTextRow._rightRegion, cogShow, EllesmereUI.RESIZE_ICON)
        end
        y = y - h

        _, h = W:Spacer(parent, y, 20); y = y - h

        parent:SetHeight(math.abs(y - yOffset))
    end

    EllesmereUI:RegisterModule("EllesmereUIDragonRiding", {
        title       = "Dragon Riding",
        description = "HUD for skyriding: speed, stacks, Second Wind, Whirling Surge.",
        pages       = { "General" },
        buildPage   = BuildPage,
        onReset = function()
            if EllesmereUIDragonRidingDB then
                EllesmereUIDragonRidingDB.profiles = nil
                EllesmereUIDragonRidingDB.profileKeys = nil
            end
        end,
    })
end)
