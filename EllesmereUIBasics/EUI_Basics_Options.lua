-------------------------------------------------------------------------------
--  EUI_Basics_Options.lua
--  Registers the Basics module with EllesmereUI.
--  All get/set calls go through the global bridge to the addon's DB profile.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_CHAT          = "Chat"
local PAGE_MINIMAP       = "Minimap"
local PAGE_FRIENDS       = "Friends"
local PAGE_QUEST_TRACKER = "Quest Tracker"
local PAGE_CURSOR        = "Cursor"
local PAGE_DMG_METERS    = "Damage Meters"

local SECTION_CHAT    = "CHAT"
local SECTION_MINIMAP = "DISPLAY"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    ---------------------------------------------------------------------------
    --  DB helpers
    ---------------------------------------------------------------------------
    local db

    C_Timer.After(0, function()
        db = _G._EBS_AceDB
    end)

    local function DB()
        if not db then db = _G._EBS_AceDB end
        return db and db.profile
    end

    local function ChatDB()
        local p = DB()
        return p and p.chat
    end

    local function MinimapDB()
        local p = DB()
        return p and p.minimap
    end

    local function FriendsDB()
        local p = DB()
        return p and p.friends
    end

    ---------------------------------------------------------------------------
    --  Refresh helpers
    ---------------------------------------------------------------------------
    local function RefreshChat()
        if _G._EBS_ApplyChat then _G._EBS_ApplyChat() end
    end

    local function RefreshMinimap()
        if _G._EBS_ApplyMinimap then _G._EBS_ApplyMinimap() end
    end

    local function RefreshFriends()
        if _G._EBS_ApplyFriends then _G._EBS_ApplyFriends() end
    end

    local function RefreshAll()
        if _G._EBS_ApplyAll then _G._EBS_ApplyAll() end
    end

    ---------------------------------------------------------------------------
    --  Visibility row builder (reused across all pages)
    ---------------------------------------------------------------------------
    local PP = EllesmereUI.PP
    local function BuildVisibilityRow(W, parent, y, getCfg, refreshFn)
        local visRow, visH = W:DualRow(parent, y,
            { type="dropdown", text="Visibility",
              values = EllesmereUI.VIS_VALUES,
              order  = EllesmereUI.VIS_ORDER,
              getValue=function()
                  local c = getCfg(); if not c then return "always" end
                  return c.visibility or "always"
              end,
              setValue=function(v)
                  local c = getCfg(); if not c then return end
                  c.visibility = v
                  if refreshFn then refreshFn() end
                  if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                  EllesmereUI:RefreshPage()
              end },
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
                function(k) local c = getCfg(); return c and c[k] or false end,
                function(k, v)
                    local c = getCfg(); if not c then return end
                    c[k] = v
                    if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        return visH
    end

    ---------------------------------------------------------------------------
    --  Border color multiSwatch builder
    ---------------------------------------------------------------------------
    local function MakeBorderSwatch(getCfg, refreshFn)
        return {
            { tooltip = "Custom Color",
              hasAlpha = false,
              getValue = function()
                  local c = getCfg()
                  if not c then return 0.05, 0.05, 0.05 end
                  return c.borderR, c.borderG, c.borderB
              end,
              setValue = function(r, g, b)
                  local c = getCfg(); if not c then return end
                  c.borderR, c.borderG, c.borderB = r, g, b
                  refreshFn()
              end,
              onClick = function(self)
                  local c = getCfg(); if not c then return end
                  if c.useClassColor then
                      c.useClassColor = false
                      refreshFn(); EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  local c = getCfg()
                  if not c or not c.enabled then return 0.15 end
                  return c.useClassColor and 0.3 or 1
              end },
            { tooltip = "Class Colored",
              hasAlpha = false,
              getValue = function()
                  local _, classFile = UnitClass("player")
                  local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                  if cc then return cc.r, cc.g, cc.b end
                  return 0.05, 0.05, 0.05
              end,
              setValue = function() end,
              onClick = function()
                  local c = getCfg(); if not c then return end
                  c.useClassColor = true
                  refreshFn(); EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  local c = getCfg()
                  if not c or not c.enabled then return 0.15 end
                  return c.useClassColor and 1 or 0.3
              end },
        }
    end

    ---------------------------------------------------------------------------
    --  Chat Page
    ---------------------------------------------------------------------------
    local function BuildChatPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, SECTION_CHAT, y);  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Minimap Page
    ---------------------------------------------------------------------------
    local function BuildMinimapPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, SECTION_MINIMAP, y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Module",
              getValue=function() local m = MinimapDB(); return not (m and m.enabled == false) end,
              setValue=function(v)
                  local m = MinimapDB(); if not m then return end
                  m.enabled = v
                  if not v and EllesmereUI.ShowConfirmPopup then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "This module requires a UI reload to fully disable.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end
                  RefreshMinimap()
                  if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Size", min=100, max=600, step=5,
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return m and m.mapSize or 140 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.mapSize = v
                -- Cover the map render during drag to mask the zoom-nudge blink.
                -- Borders, buttons, etc. remain visible above the overlay.
                local minimap = _G.Minimap
                if minimap then
                    if not minimap._dragOverlay then
                        local ov = minimap:CreateTexture(nil, "BACKGROUND", nil, 7)
                        ov:SetAllPoints(minimap)
                        minimap._dragOverlay = ov
                    end
                    local shape = m.shape or "square"
                    if shape == "circle" or shape == "textured_circle" then
                        minimap._dragOverlay:SetTexture("Interface\\Common\\CommonMaskCircle")
                        minimap._dragOverlay:SetVertexColor(0, 0, 0, 1)
                    else
                        minimap._dragOverlay:SetColorTexture(0, 0, 0, 1)
                    end
                    minimap._dragOverlay:Show()
                end
                RefreshMinimap()
                if not _G._EBS_SizeDragTimer then
                    _G._EBS_SizeDragTimer = C_Timer.NewTimer(0, function() end)
                end
                _G._EBS_SizeDragTimer:Cancel()
                _G._EBS_SizeDragTimer = C_Timer.NewTimer(0.15, function()
                    if minimap and minimap._dragOverlay then
                        minimap._dragOverlay:Hide()
                    end
                end)
              end })
        y = y - h

        h = BuildVisibilityRow(W, parent, y, MinimapDB, RefreshMinimap);  y = y - h

        -- Shape | Border Thickness
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Shape",
              values = { square = "Square", circle = "Circle", textured_circle = "Textured Circle" },
              order  = { "square", "circle", "textured_circle" },
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return m and m.shape or "square" end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.shape = v
                RefreshMinimap()
              end },
            { type="slider", text="Border Thickness", min=0, max=5, step=1,
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return m and m.borderSize or 1 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.borderSize = v
                RefreshMinimap()
              end }
        );  y = y - h

        -- Accent Color | Interactable Button Size
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Accent Color",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              swatches = MakeBorderSwatch(MinimapDB, RefreshMinimap) },
            { type="slider", text="Interactable Button Size", min=16, max=40, step=1,
              tooltip="Size of mail, calendar, tracking, and minimap button group toggle",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return m and m.interactableBtnSize or 21 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.interactableBtnSize = v
                RefreshMinimap()
              end }
        );  y = y - h

        -- Minimap Button Size | Ungroup Minimap Button
        local ungroupRow
        ungroupRow, h = W:DualRow(parent, y,
            { type="slider", text="Minimap Button Size", min=14, max=40, step=1,
              tooltip="Size of addon minimap buttons in the flyout grid",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return m and m.addonBtnSize or 24 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.addonBtnSize = v
                RefreshMinimap()
              end },
            { type="dropdown", text="Ungroup Minimap Button",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue = function() return "__placeholder" end,
              setValue = function() end }
        );  y = y - h

        -- Replace placeholder dropdown with checkbox dropdown
        do
            local rightRgn = ungroupRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end

            -- Build items from currently collected minimap buttons
            local function GetUngroupItems()
                local items = {}
                local btns = _G._EBS_CachedAddonButtons or {}
                local vis = _G._EBS_AddonVisible or {}
                for _, btn in ipairs(btns) do
                    local name = btn:GetName()
                    if name and vis[btn] ~= false then
                        local label = name:gsub("^LibDBIcon10_", ""):gsub("^Lib_GPI_Minimap_", "")
                        items[#items + 1] = { key = name, label = label }
                    end
                end
                table.sort(items, function(a, b) return a.label < b.label end)
                return items
            end

            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                GetUngroupItems(),
                function(k)
                    local m = MinimapDB(); if not m then return false end
                    return m.ungroupedButtons and m.ungroupedButtons[k] and true or false
                end,
                function(k, v)
                    local m = MinimapDB(); if not m then return end
                    if not m.ungroupedButtons then m.ungroupedButtons = {} end
                    if v then
                        -- Assign next order index
                        local maxOrder = 0
                        for _, ord in pairs(m.ungroupedButtons) do
                            if type(ord) == "number" and ord > maxOrder then maxOrder = ord end
                        end
                        m.ungroupedButtons[k] = maxOrder + 1
                    else
                        m.ungroupedButtons[k] = nil
                    end
                    RefreshMinimap()
                end)
            local PP = EllesmereUI.PP
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        y = y - 10

        -- EXTRAS section header
        _, h = W:SectionHeader(parent, "EXTRAS", y);  y = y - h

        -- Show Zone | Show Clock
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Zone",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return not (m and m.hideZoneText) end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.hideZoneText = not v
                RefreshMinimap()
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Show Clock",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return m and m.showClock end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.showClock = v
                RefreshMinimap()
                EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Zone Inside | Clock Inside
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Zone Inside",
              tooltip="Display the zone text inside the minimap instead of below it",
              disabled=function() local m = MinimapDB(); return m and (not m.enabled or m.hideZoneText) end,
              disabledTooltip="Enable Show Zone first",
              getValue=function() local m = MinimapDB(); return m and m.zoneInside end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.zoneInside = v
                RefreshMinimap()
              end },
            { type="toggle", text="Clock Inside",
              tooltip="Display the clock inside the minimap instead of above it",
              disabled=function() local m = MinimapDB(); return m and (not m.enabled or not m.showClock) end,
              disabledTooltip="Enable Show Clock first",
              getValue=function() local m = MinimapDB(); return m and m.clockInside end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.clockInside = v
                RefreshMinimap()
              end }
        );  y = y - h

        -- Scroll to Zoom | Clock Scale (with cog: X/Y offset)
        local clockScaleRow
        clockScaleRow, h = W:DualRow(parent, y,
            { type="toggle", text="Scroll to Zoom",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return m and m.scrollZoom end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.scrollZoom = v
                RefreshMinimap()
              end },
            { type="slider", text="Clock Scale", min=0.5, max=2.0, step=0.01,
              disabled=function() local m = MinimapDB(); return m and (not m.enabled or not m.showClock) end,
              disabledTooltip="Enable Show Clock first",
              getValue=function() local m = MinimapDB(); return m and m.clockScale or 1.15 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.clockScale = v
                local bg = _G._EBS_ClockBg
                if bg then bg:SetScale(v) end
              end }
        );  y = y - h

        -- Inline cog on Clock Scale for X/Y offset
        do
            local rgn = clockScaleRow._rightRegion
            local function clockOff()
                local m = MinimapDB(); return m and (not m.enabled or not m.showClock)
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Clock Position",
                rows = {
                    { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                      get = function() local m = MinimapDB(); return m and m.clockOffsetX or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.clockOffsetX = v
                          local bg = _G._EBS_ClockBg
                          if bg then
                              bg:ClearAllPoints()
                              local cy = m.clockOffsetY or 0
                              local baseY = m.clockInside and -4 or (m.shape == "circle" or m.shape == "textured_circle") and -3 or 7
                              bg:SetPoint("TOP", _G.Minimap, "TOP", v, baseY + cy)
                          end
                      end },
                    { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                      get = function() local m = MinimapDB(); return m and m.clockOffsetY or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.clockOffsetY = v
                          local bg = _G._EBS_ClockBg
                          if bg then
                              bg:ClearAllPoints()
                              local cx = m.clockOffsetX or 0
                              local baseY = m.clockInside and -4 or (m.shape == "circle" or m.shape == "textured_circle") and -3 or 7
                              bg:SetPoint("TOP", _G.Minimap, "TOP", cx, baseY + v)
                          end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(clockOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(clockOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Show Clock")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = clockOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if clockOff() then cogBlock:Show() else cogBlock:Hide() end
        end

        -- Location Scale (with cog: X/Y offset) | (spacer)
        local locScaleRow
        locScaleRow, h = W:DualRow(parent, y,
            { type="slider", text="Location Scale", min=0.5, max=2.0, step=0.01,
              disabled=function() local m = MinimapDB(); return m and (not m.enabled or m.hideZoneText) end,
              disabledTooltip="Enable Show Zone first",
              getValue=function() local m = MinimapDB(); return m and m.locationScale or 1.15 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.locationScale = v
                local bg = _G._EBS_LocationBg
                if bg then bg:SetScale(v) end
              end },
            { type="label", text="" }
        );  y = y - h

        -- Inline cog on Location Scale for X/Y offset
        do
            local rgn = locScaleRow._leftRegion
            local function locOff()
                local m = MinimapDB(); return m and (not m.enabled or m.hideZoneText)
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Location Position",
                rows = {
                    { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                      get = function() local m = MinimapDB(); return m and m.locationOffsetX or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.locationOffsetX = v
                          local bg = _G._EBS_LocationBg
                          if bg then
                              bg:ClearAllPoints()
                              local ly = m.locationOffsetY or 0
                              local baseY = m.zoneInside and 4 or (m.shape == "circle" or m.shape == "textured_circle") and 3 or -7
                              bg:SetPoint("BOTTOM", _G.Minimap, "BOTTOM", v, baseY + ly)
                          end
                      end },
                    { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                      get = function() local m = MinimapDB(); return m and m.locationOffsetY or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.locationOffsetY = v
                          local bg = _G._EBS_LocationBg
                          if bg then
                              bg:ClearAllPoints()
                              local lx = m.locationOffsetX or 0
                              local baseY = m.zoneInside and 4 or (m.shape == "circle" or m.shape == "textured_circle") and 3 or -7
                              bg:SetPoint("BOTTOM", _G.Minimap, "BOTTOM", lx, baseY + v)
                          end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(locOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(locOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Show Zone")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = locOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if locOff() then cogBlock:Show() else cogBlock:Hide() end
        end


        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Friends List Page
    ---------------------------------------------------------------------------

    local ICON_STYLE_VALUES = {
        blizzard = "Blizzard",
        modern   = "Modern",
        pixel    = "Pixel",
        glyph    = "Glyph",
        arcade   = "Arcade",
        legend   = "Legend",
        midnight = "Midnight",
        runic    = "Runic",
    }
    local ICON_STYLE_ORDER = {
        "blizzard", "modern", "pixel", "glyph",
        "arcade", "legend", "midnight", "runic",
    }

    local function BuildFriendsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()

        -- Drag instructions (centered, above settings)
        do
            local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
            local infoLabel = parent:CreateFontString(nil, "OVERLAY")
            infoLabel:SetFont(fontPath, 15, "")
            infoLabel:SetTextColor(1, 1, 1, 0.75)
            infoLabel:SetPoint("TOP", parent, "TOP", 0, y - 20)
            infoLabel:SetJustifyH("CENTER")
            infoLabel:SetText("Shift+Drag to reposition  |  Ctrl+Drag to temporarily move (resets on close)")
            y = y - 40
        end

        -- DISPLAY
        _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

        -- Enable Friends List | Icon Style
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Friends List",
              getValue=function() local f = FriendsDB(); return f and f.enabled end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.enabled = v
                if not v and EllesmereUI.ShowConfirmPopup then
                    EllesmereUI:ShowConfirmPopup({
                        title       = "Reload Required",
                        message     = "This module requires a UI reload to fully disable.",
                        confirmText = "Reload Now",
                        cancelText  = "Later",
                        onConfirm   = function() ReloadUI() end,
                    })
                end
                RefreshFriends()
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Class Icon Theme",
              disabled=function() local f = FriendsDB(); return not f or not f.enabled end,
              disabledTooltip="Module is disabled",
              values = ICON_STYLE_VALUES,
              order  = ICON_STYLE_ORDER,
              getValue=function()
                local f = FriendsDB(); return f and f.iconStyle or "modern"
              end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.iconStyle = v
                if _G._EBS_ProcessFriendButtons then _G._EBS_ProcessFriendButtons() end
              end }
        );  y = y - h

        -- Border Size | Border Color
        _, h = W:DualRow(parent, y,
            { type="slider", text="Border Size", min=0, max=4, step=1,
              disabled=function() local f = FriendsDB(); return not f or not f.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local f = FriendsDB(); return f and f.borderSize or 0 end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.borderSize = v
                RefreshFriends()
                EllesmereUI:RefreshPage()
              end },
            { type="multiSwatch", text="Border Color",
              disabled=function()
                local f = FriendsDB()
                return not f or not f.enabled or (f.borderSize or 0) == 0
              end,
              disabledTooltip="Set Border Size above 0",
              swatches = {
                { tooltip = "Custom Color",
                  hasAlpha = false,
                  getValue = function()
                      local c = FriendsDB()
                      if not c then return 0.05, 0.05, 0.05 end
                      return c.borderR, c.borderG, c.borderB
                  end,
                  setValue = function(r, g, b)
                      local c = FriendsDB(); if not c then return end
                      c.borderR, c.borderG, c.borderB = r, g, b
                      RefreshFriends()
                  end,
                  onClick = function(self)
                      local c = FriendsDB(); if not c then return end
                      if c.useClassColor then
                          c.useClassColor = false
                          RefreshFriends(); EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local c = FriendsDB()
                      if not c or not c.enabled then return 0.15 end
                      return c.useClassColor and 0.3 or 1
                  end },
                { tooltip = "Accent Colored",
                  hasAlpha = false,
                  getValue = function()
                      local ar, ag, ab = EllesmereUI.GetAccentColor()
                      return ar, ag, ab
                  end,
                  setValue = function() end,
                  onClick = function()
                      local c = FriendsDB(); if not c then return end
                      c.useClassColor = true
                      RefreshFriends(); EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local c = FriendsDB()
                      if not c or not c.enabled then return 0.15 end
                      return c.useClassColor and 1 or 0.3
                  end },
              } }
        );  y = y - h

        -- Class Color Names (with inline swatch) | Window Scale
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Class Color Names",
              disabled=function() local f = FriendsDB(); return not f or not f.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local f = FriendsDB(); return f and f.classColorNames end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.classColorNames = v
                if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
              end },
            { type="slider", text="Window Scale", min=0.5, max=1.5, step=0.05,
              disabled=function() local f = FriendsDB(); return not f or not f.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local f = FriendsDB(); return f and f.scale or 1 end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.scale = v
                if FriendsFrame and FriendsFrame._ebsApplyScaleAndPosition then
                    FriendsFrame._ebsApplyScaleAndPosition()
                end
              end }
        );  y = y - h
        -- Enable Accent Colors | Enable Faction Banners
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Accent Colors",
              disabled=function() local f = FriendsDB(); return not f or not f.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local f = FriendsDB(); return f and (f.accentColors ~= false) end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.accentColors = v
                RefreshFriends()
              end },
            { type="toggle", text="Enable Faction Banners",
              disabled=function() local f = FriendsDB(); return not f or not f.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local f = FriendsDB(); return f and (f.factionBanners ~= false) end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.factionBanners = v
                if _G._EBS_ProcessFriendButtons then _G._EBS_ProcessFriendButtons() end
              end }
        );  y = y - h

        -- Show Region Icons | Auto-Accept Friend Invites
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Region Icons",
              disabled=function() local f = FriendsDB(); return not f or not f.enabled end,
              disabledTooltip="Module is disabled",
              tooltip="Shows a map icon of the friend's region if they are not playing within your region",
              getValue=function() local f = FriendsDB(); return f and (f.showRegionIcons ~= false) end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.showRegionIcons = v
                if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
              end },
            { type="toggle", text="Auto-Accept Friend Invites",
              disabled=function() local f = FriendsDB(); return not f or not f.enabled end,
              disabledTooltip="Module is disabled",
              tooltip="Auto-accepts all group invites from people on your friends list",
              getValue=function() local f = FriendsDB(); return f and f.autoAcceptFriendInvites end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.autoAcceptFriendInvites = v
              end }
        );  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIBasics", {
        title       = "Basics",
        description = "Lightweight skins for all major Blizzard UI objects.",
        pages       = { PAGE_CURSOR, PAGE_DMG_METERS, PAGE_QUEST_TRACKER, PAGE_FRIENDS, PAGE_CHAT, PAGE_MINIMAP },
        disabledPages = { PAGE_DMG_METERS, PAGE_CHAT },
        disabledPageTooltips = { [PAGE_DMG_METERS] = "Coming Soon", [PAGE_CHAT] = "Coming Soon" },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_CHAT    then return BuildChatPage(pageName, parent, yOffset) end
            if pageName == PAGE_MINIMAP then return BuildMinimapPage(pageName, parent, yOffset) end
            if pageName == PAGE_FRIENDS then return BuildFriendsPage(pageName, parent, yOffset) end
            if pageName == PAGE_QUEST_TRACKER and _G._EBS_BuildQuestTrackerPage then
                return _G._EBS_BuildQuestTrackerPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_CURSOR and _G._EBS_BuildCursorPage then
                return _G._EBS_BuildCursorPage(pageName, parent, yOffset)
            end
        end,
        onReset = function()
            if _G._EBS_AceDB then
                _G._EBS_AceDB:ResetProfile()
            end
            if _G._EBS_ResetCursor then _G._EBS_ResetCursor() end
            if _G._EBS_ResetQuestTracker then _G._EBS_ResetQuestTracker() end
            EllesmereUI:InvalidatePageCache()
            RefreshAll()
            if _G._EBS_ProcessFriendButtons then _G._EBS_ProcessFriendButtons() end
        end,
    })

    ---------------------------------------------------------------------------
    --  Slash command  /ebs
    ---------------------------------------------------------------------------
    SLASH_EBS1 = "/ebs"
    SlashCmdList.EBS = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIBasics")
    end
end)
