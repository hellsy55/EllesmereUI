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
local SECTION_FRIENDS = "FRIENDS LIST"

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

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Module",
              getValue=function() local c = ChatDB(); return not (c and c.enabled == false) end,
              setValue=function(v)
                  local c = ChatDB(); if not c then return end
                  c.enabled = v
                  RefreshChat()
                  if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Font Size", min=8, max=24, step=1,
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.fontSize or 14 end,
              setValue=function(v)
                local c = ChatDB(); if not c then return end
                c.fontSize = v
                RefreshChat()
              end })
        y = y - h

        h = BuildVisibilityRow(W, parent, y, ChatDB, RefreshChat);  y = y - h

        -- Background Opacity | Border Color
        _, h = W:DualRow(parent, y,
            { type="slider", text="Background Opacity", min=0, max=1, step=0.05,
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.bgAlpha or 0.6 end,
              setValue=function(v)
                local c = ChatDB(); if not c then return end
                c.bgAlpha = v
                RefreshChat()
              end },
            { type="multiSwatch", text="Border Color",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              swatches = MakeBorderSwatch(ChatDB, RefreshChat) }
        );  y = y - h

        -- Hide Chat Buttons | Hide Tab Flash
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Chat Buttons",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.hideButtons end,
              setValue=function(v)
                local c = ChatDB(); if not c then return end
                c.hideButtons = v
                RefreshChat()
              end },
            { type="toggle", text="Hide Tab Flash",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local c = ChatDB(); return c and c.hideTabFlash end,
              setValue=function(v)
                local c = ChatDB(); if not c then return end
                c.hideTabFlash = v
                RefreshChat()
              end }
        );  y = y - h

        -- Extended chat options (font, enhancements, copy, search)
        if EllesmereUI._BuildExtendedChatOptions then
            local extH = EllesmereUI._BuildExtendedChatOptions(parent, y)
            y = y - extH
        end

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
            { type="slider", text="Size", min=100, max=350, step=5,
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

        -- Accent Color | (spacer)
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Accent Color",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              swatches = MakeBorderSwatch(MinimapDB, RefreshMinimap) },
            { type="label", text="" }
        );  y = y - h
            
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
              end },
            { type="toggle", text="Show Clock",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return m and m.showClock end,
              setValue=function(v) local m = MinimapDB(); if not m then return end; m.showClock = v; RefreshMinimap() end }
        );  y = y - h

        -- Scroll to Zoom | Auto Zoom Out
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Scroll to Zoom",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return m and m.scrollZoom end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.scrollZoom = v
                RefreshMinimap()
              end },
            { type="toggle", text="Auto Zoom Out",
              disabled=function() local m = MinimapDB(); return m and (not m.enabled or not m.scrollZoom) end,
              disabledTooltip="Module is disabled",
              getValue=function() local m = MinimapDB(); return m and m.autoZoomOut end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.autoZoomOut = v
                RefreshMinimap()
              end }
        );  y = y - h


        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Friends List Page
    ---------------------------------------------------------------------------
    local function BuildFriendsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, SECTION_FRIENDS, y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Module",
              getValue=function() local f = FriendsDB(); return not (f and f.enabled == false) end,
              setValue=function(v)
                  local f = FriendsDB(); if not f then return end
                  f.enabled = v
                  RefreshFriends()
                  if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Background Opacity", min=0, max=1, step=0.05,
              disabled=function() local f = FriendsDB(); return f and not f.enabled end,
              disabledTooltip="Module is disabled",
              getValue=function() local f = FriendsDB(); return f and f.bgAlpha or 0.8 end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.bgAlpha = v
                RefreshFriends()
              end })
        y = y - h

        h = BuildVisibilityRow(W, parent, y, FriendsDB, RefreshFriends);  y = y - h

        -- Border Color | (spacer)
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Border Color",
              disabled=function() local f = FriendsDB(); return f and not f.enabled end,
              disabledTooltip="Module is disabled",
              swatches = MakeBorderSwatch(FriendsDB, RefreshFriends) },
            { type="label", text="" }
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
        disabledPages = { PAGE_DMG_METERS, PAGE_CHAT, PAGE_FRIENDS },
        disabledPageTooltips = { [PAGE_DMG_METERS] = "Coming Soon", [PAGE_CHAT] = "Coming Soon", [PAGE_FRIENDS] = "Coming Soon" },
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
