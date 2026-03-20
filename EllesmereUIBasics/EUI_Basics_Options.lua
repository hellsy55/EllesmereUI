-------------------------------------------------------------------------------
--  EUI_Basics_Options.lua
--  Registers the Basics module with EllesmereUI.
--  All get/set calls go through the global bridge to the addon's DB profile.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_CHAT          = "Chat"
local PAGE_MINIMAP       = "Minimap"
local PAGE_FRIENDS       = "Friends List"
local PAGE_QUEST_TRACKER = "Quest Tracker"
local PAGE_CURSOR        = "Cursor Circle"

local SECTION_CHAT    = "CHAT"
local SECTION_MINIMAP = "MINIMAP"
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

        -- Enable Chat Skin | Font Size
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Chat Skin",
              getValue=function() local c = ChatDB(); return c and c.enabled end,
              setValue=function(v)
                local c = ChatDB(); if not c then return end
                c.enabled = v
                RefreshChat()
                EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Font Size", min=8, max=24, step=1,
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Enable Chat Skin",
              getValue=function() local c = ChatDB(); return c and c.fontSize or 14 end,
              setValue=function(v)
                local c = ChatDB(); if not c then return end
                c.fontSize = v
                RefreshChat()
              end }
        );  y = y - h

        -- Background Opacity | Border Color
        _, h = W:DualRow(parent, y,
            { type="slider", text="Background Opacity", min=0, max=1, step=0.05,
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Enable Chat Skin",
              getValue=function() local c = ChatDB(); return c and c.bgAlpha or 0.6 end,
              setValue=function(v)
                local c = ChatDB(); if not c then return end
                c.bgAlpha = v
                RefreshChat()
              end },
            { type="multiSwatch", text="Border Color",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Enable Chat Skin",
              swatches = MakeBorderSwatch(ChatDB, RefreshChat) }
        );  y = y - h

        -- Hide Chat Buttons | Hide Tab Flash
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Chat Buttons",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Enable Chat Skin",
              getValue=function() local c = ChatDB(); return c and c.hideButtons end,
              setValue=function(v)
                local c = ChatDB(); if not c then return end
                c.hideButtons = v
                RefreshChat()
              end },
            { type="toggle", text="Hide Tab Flash",
              disabled=function() local c = ChatDB(); return c and not c.enabled end,
              disabledTooltip="Enable Chat Skin",
              getValue=function() local c = ChatDB(); return c and c.hideTabFlash end,
              setValue=function(v)
                local c = ChatDB(); if not c then return end
                c.hideTabFlash = v
                RefreshChat()
              end }
        );  y = y - h

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

        -- Enable Minimap Skin | Scale
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Minimap Skin",
              getValue=function() local m = MinimapDB(); return m and m.enabled end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.enabled = v
                RefreshMinimap()
                EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Scale", min=0.5, max=2.0, step=0.1,
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Enable Minimap Skin",
              getValue=function() local m = MinimapDB(); return m and m.scale or 1.0 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.scale = v
                RefreshMinimap()
              end }
        );  y = y - h

        -- Border Color | Hide Zone Text
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Border Color",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Enable Minimap Skin",
              swatches = MakeBorderSwatch(MinimapDB, RefreshMinimap) },
            { type="toggle", text="Hide Zone Text",
              disabled=function() local m = MinimapDB(); return m and not m.enabled end,
              disabledTooltip="Enable Minimap Skin",
              getValue=function() local m = MinimapDB(); return m and m.hideZoneText end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.hideZoneText = v
                RefreshMinimap()
              end }
        );  y = y - h

        -- Hide Minimap Buttons
        _, h = W:Toggle(parent, "Hide Minimap Buttons", y,
            function() local m = MinimapDB(); return m and m.hideButtons end,
            function(v)
                local m = MinimapDB(); if not m then return end
                m.hideButtons = v
                RefreshMinimap()
            end
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

        -- Enable Friends Skin | Background Opacity
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Friends Skin",
              getValue=function() local f = FriendsDB(); return f and f.enabled end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.enabled = v
                RefreshFriends()
                EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Background Opacity", min=0, max=1, step=0.05,
              disabled=function() local f = FriendsDB(); return f and not f.enabled end,
              disabledTooltip="Enable Friends Skin",
              getValue=function() local f = FriendsDB(); return f and f.bgAlpha or 0.8 end,
              setValue=function(v)
                local f = FriendsDB(); if not f then return end
                f.bgAlpha = v
                RefreshFriends()
              end }
        );  y = y - h

        -- Border Color | (spacer)
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Border Color",
              disabled=function() local f = FriendsDB(); return f and not f.enabled end,
              disabledTooltip="Enable Friends Skin",
              swatches = MakeBorderSwatch(FriendsDB, RefreshFriends) },
            nil
        );  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIBasics", {
        title       = "Basics",
        description = "Chat, Minimap, Friends List, Quest Tracker, and Cursor.",
        pages       = { PAGE_CHAT, PAGE_MINIMAP, PAGE_FRIENDS, PAGE_QUEST_TRACKER, PAGE_CURSOR },
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
