-------------------------------------------------------------------------------
--  EUI_Chat_Options.lua
--
--  Options page for EllesmereUI Chat: visibility, background opacity/color,
--  top accent line.
-------------------------------------------------------------------------------
local _, ns = ...
local ECHAT = ns.ECHAT

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    if not ECHAT then return end

    local function DB()
        local d = _G._ECHAT_DB
        if d and d.profile and d.profile.chat then
            return d.profile.chat
        end
        return {}
    end
    local function Cfg(k)    return DB()[k]  end
    local function Set(k, v) DB()[k] = v     end

    local function RefreshAll()
        if ECHAT.ApplyBackground  then ECHAT.ApplyBackground()  end
        if ECHAT.ApplyFonts       then ECHAT.ApplyFonts()       end
        if ECHAT.RefreshVisibility then ECHAT.RefreshVisibility() end
    end

    local function BuildPage(_, parent, yOffset)
        local W  = EllesmereUI.Widgets
        local PP = EllesmereUI.PP
        local y  = yOffset
        local h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        -- Top instruction label
        do
            local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
            local infoLabel = parent:CreateFontString(nil, "OVERLAY")
            infoLabel:SetFont(fontPath, 15, "")
            infoLabel:SetTextColor(1, 1, 1, 0.75)
            infoLabel:SetPoint("TOP", parent, "TOP", 0, y - 20)
            infoLabel:SetJustifyH("CENTER")
            infoLabel:SetText("Reposition the chat frame using Blizzard Edit Mode")
            y = y - 40
        end

        -- -- DISPLAY ---------------------------------------------------------
        -- -- DISPLAY -----------------------------------------------------------
        _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

        -- Row 1: Visibility | Visibility Options
        local chatVisValues = {}
        local chatVisOrder = {}
        for _, key in ipairs(EllesmereUI.VIS_ORDER) do
            if key ~= "mouseover" then
                chatVisValues[key] = EllesmereUI.VIS_VALUES[key]
                chatVisOrder[#chatVisOrder + 1] = key
            end
        end
        local visRow
        visRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Visibility",
              values = chatVisValues,
              order  = chatVisOrder,
              getValue=function() return Cfg("visibility") or "always" end,
              setValue=function(v) Set("visibility", v); RefreshAll() end },
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
                function(k, v) Set(k, v); RefreshAll() end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        y = y - h

        -- Row 2: Background Opacity (+ inline color swatch) | Idle Fade Delay
        local bgRow
        bgRow, h = W:DualRow(parent, y,
            { type="slider", text="Background Opacity",
              min = 0, max = 1, step = 0.05,
              getValue=function() return Cfg("bgAlpha") or 0.70 end,
              setValue=function(v) Set("bgAlpha", v); RefreshAll() end },
            { type="slider", text="Idle Fade Delay",
              min = 5, max = 30, step = 1,
              getValue=function() return Cfg("idleFadeDelay") or 15 end,
              setValue=function(v)
                  Set("idleFadeDelay", v)
                  if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
              end })
        do
            local rgn = bgRow._leftRegion
            local ctrl = rgn._control
            local bgSwatch, bgSwatchRefresh = EllesmereUI.BuildColorSwatch(
                rgn, bgRow:GetFrameLevel() + 3,
                function()
                    return (Cfg("bgR") or 0.03), (Cfg("bgG") or 0.045), (Cfg("bgB") or 0.05)
                end,
                function(r, g, b)
                    Set("bgR", r); Set("bgG", g); Set("bgB", b)
                    RefreshAll()
                end,
                false, 20)
            PP.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(function() bgSwatchRefresh() end)
        end
        y = y - h

        -- -- SIDEBAR -----------------------------------------------------------
        _, h = W:SectionHeader(parent, "SIDEBAR", y); y = y - h

        -- Row 1: Sidebar Visibility (+ cog) | Sidebar Icons
        local sidebarVisValues = {
            always    = { text = "Always" },
            mouseover = { text = "Mouseover" },
            never     = { text = "Never" },
        }
        local sidebarVisOrder = { "always", "mouseover", "never" }
        local sidebarIconItems = {
            { key = "showFriends",  label = "Friends" },
            { key = "showCopy",     label = "Copy Chat" },
            { key = "showVoice",    label = "Voice/Channels" },
            { key = "showSettings", label = "Settings" },
            { key = "showScroll",   label = "Scroll to Bottom" },
        }
        local sidebarRow
        sidebarRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Sidebar Visibility",
              values=sidebarVisValues, order=sidebarVisOrder,
              getValue=function() return Cfg("sidebarVisibility") or "always" end,
              setValue=function(v)
                  Set("sidebarVisibility", v)
                  if ECHAT.ApplySidebarVisibility then ECHAT.ApplySidebarVisibility() end
              end },
            { type="dropdown", text="Sidebar Icons",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end })
        -- Cog for Sidebar Visibility
        do
            local lrgn = sidebarRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Sidebar Settings",
                rows = {
                    { type="toggle", label="Show Sidebar on Right",
                      get=function() return Cfg("sidebarRight") or false end,
                      set=function(v)
                          Set("sidebarRight", v)
                          if ECHAT.ApplySidebarPosition then ECHAT.ApplySidebarPosition() end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, lrgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", lrgn._lastInline or lrgn._control, "LEFT", -8, 0)
            lrgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(lrgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        end
        -- Sidebar Icons checkbox dropdown
        do
            local rightRgn = sidebarRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                sidebarIconItems,
                function(k) return Cfg(k) ~= false end,
                function(k, v)
                    Set(k, v)
                    if ECHAT.ApplySidebarIcons then ECHAT.ApplySidebarIcons() end
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        y = y - h

        -- Row 2: Sidebar Icons Color | (empty)
        local function MakeIconColorSwatches()
            return {
                { tooltip = "Custom Color",
                  hasAlpha = false,
                  getValue = function()
                      return (Cfg("iconR") or 1), (Cfg("iconG") or 1), (Cfg("iconB") or 1)
                  end,
                  setValue = function(r, g, b)
                      Set("iconR", r); Set("iconG", g); Set("iconB", b)
                      if ECHAT.ApplyIconColor then ECHAT.ApplyIconColor() end
                  end,
                  onClick = function(self)
                      if Cfg("iconUseAccent") then
                          Set("iconUseAccent", false)
                          if ECHAT.ApplyIconColor then ECHAT.ApplyIconColor() end
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      return Cfg("iconUseAccent") and 0.3 or 1
                  end },
                { tooltip = "Accent Color",
                  hasAlpha = false,
                  getValue = function()
                      local ar, ag, ab = EllesmereUI.GetAccentColor()
                      return ar, ag, ab
                  end,
                  setValue = function() end,
                  onClick = function()
                      Set("iconUseAccent", true)
                      if ECHAT.ApplyIconColor then ECHAT.ApplyIconColor() end
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return Cfg("iconUseAccent") and 1 or 0.3
                  end },
            }
        end
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Sidebar Icons Color",
              swatches = MakeIconColorSwatches() },
            { type="label", text="" })
        y = y - h

        -- -- EXTRAS ------------------------------------------------------------
        _, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

        -- Row 1: Hide Tooltip on Hover | Hide Combat Log Tab
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Tooltip on Hover",
              getValue=function() return Cfg("hideTooltipOnHover") or false end,
              setValue=function(v) Set("hideTooltipOnHover", v) end },
            { type="toggle", text="Hide Combat Log Tab",
              getValue=function() return Cfg("hideCombatLogTab") or false end,
              setValue=function(v)
                  Set("hideCombatLogTab", v)
                  if ECHAT.ApplyHideCombatLogTab then ECHAT.ApplyHideCombatLogTab() end
              end })
        y = y - h

        -- Row 2: Hide Borders | (empty)
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Borders",
              getValue=function() return Cfg("hideBorders") or false end,
              setValue=function(v)
                  Set("hideBorders", v)
                  if ECHAT.ApplyBorders then ECHAT.ApplyBorders() end
              end },
            { type="label", text="" })
        y = y - h

        -- -- TEXT --------------------------------------------------------------
        _, h = W:SectionHeader(parent, "TEXT", y); y = y - h

        -- Row 1: Font | Timestamps
        do
            local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
            local tsValues = {
                ["__blizzard"]  = { text = "Use Blizzard Setting" },
                ["none"]        = { text = "None" },
                ["%I:%M "]      = { text = "03:27" },
                ["%I:%M:%S "]   = { text = "03:27:32" },
                ["%I:%M %p "]   = { text = "03:27 PM" },
                ["%I:%M:%S %p "] = { text = "03:27:32 PM" },
                ["%H:%M "]      = { text = "15:27" },
                ["%H:%M:%S "]   = { text = "15:27:32" },
            }
            local tsOrder = {
                "__blizzard", "none", "---",
                "%I:%M ", "%I:%M:%S ", "%I:%M %p ", "%I:%M:%S %p ", "---",
                "%H:%M ", "%H:%M:%S ",
            }
            _, h = W:DualRow(parent, y,
                { type="dropdown", text="Font",
                  values=fontValues, order=fontOrder,
                  getValue=function() return Cfg("font") or "__global" end,
                  setValue=function(v)
                      Set("font", v)
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Font changed. A UI reload is needed to apply the new font.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end },
                { type="dropdown", text="Timestamps",
                  values=tsValues, order=tsOrder,
                  getValue=function() return Cfg("timestampFormat") or "%I:%M " end,
                  setValue=function(v)
                      Set("timestampFormat", v)
                      if ECHAT.ApplyTimestampCVar then ECHAT.ApplyTimestampCVar() end
                  end })
        end
        y = y - h

        -- Row 2: Text Size | Tab Text Size
        _, h = W:DualRow(parent, y,
            { type="slider", text="Text Size",
              min = 8, max = 24, step = 1,
              getValue=function() return Cfg("fontSize") or 12 end,
              setValue=function(v) Set("fontSize", v); RefreshAll() end },
            { type="slider", text="Tab Text Size",
              min = 8, max = 16, step = 1,
              getValue=function() return Cfg("tabFontSize") or 10 end,
              setValue=function(v) Set("tabFontSize", v); RefreshAll() end })
        y = y - h

        return math.abs(y)
    end

    _G._EBS_BuildChatPage = BuildPage

    EllesmereUI:RegisterModule("EllesmereUIChat", {
        title       = "Chat",
        description = "Chat frame reskin, clickable URLs, copy chat, sidebar icons.",
        pages       = { "Chat" },
        buildPage   = function(pageName, p, yOffset) return BuildPage(pageName, p, yOffset) end,
        searchTerms = "chat url copy whisper sidebar friends voice",
        onReset = function()
            local d = _G._ECHAT_DB
            if d and d.ResetProfile then d:ResetProfile() end
            RefreshAll()
            EllesmereUI:InvalidatePageCache()
        end,
    })
end)
