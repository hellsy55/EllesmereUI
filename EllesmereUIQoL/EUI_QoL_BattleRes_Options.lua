-------------------------------------------------------------------------------
--  EUI_QoL_BattleRes_Options.lua
--  Options page for the BattleRes icon (registered under EllesmereUIQoL).
-------------------------------------------------------------------------------

local function DB()
    local fn = _G._EUI_BattleRes_DB
    return fn and fn() or nil
end

local function P()
    local d = DB()
    return d and d.profile and d.profile.battleRes
end

local function Cfg(key, fallback)
    local p = P()
    if not p then return fallback end
    if p[key] == nil then return fallback end
    return p[key]
end

local function Set(key, v)
    local p = P()
    if p then p[key] = v end
end

local function Refresh()
    if _G._EUI_BattleRes_Apply then _G._EUI_BattleRes_Apply() end
end

local SHAPE_VALUES = {
    none     = "None",
    cropped  = "Cropped",
    square   = "Square",
    circle   = "Circle",
    csquare  = "Curved Square",
    diamond  = "Diamond",
    hexagon  = "Hexagon",
    portrait = "Portrait",
    shield   = "Shield",
}
local SHAPE_ORDER = { "none", "cropped", "---", "square", "circle", "csquare", "diamond", "hexagon", "portrait", "shield" }

local BORDER_VALUES = { none = "None", thin = "Thin", normal = "Normal", heavy = "Heavy", strong = "Strong" }
local BORDER_ORDER  = { "none", "thin", "normal", "heavy", "strong" }

local VIS_VALUES = {
    MPLUS_AND_RAID = "M+ and Raid",
    MPLUS          = "M+",
    RAID           = "Raid",
    NEVER          = "Never",
}
local VIS_ORDER = { "MPLUS_AND_RAID", "MPLUS", "RAID", "NEVER" }

local function MakeBorderColorSwatches()
    return {
        { tooltip = "Custom Color",
          hasAlpha = false,
          getValue = function()
              local c = Cfg("borderColor")
              if c then return c.r or 0, c.g or 0, c.b or 0 end
              return 0, 0, 0
          end,
          setValue = function(r, g, b)
              Set("borderColor", { r = r, g = g, b = b, a = 1 })
              Refresh()
          end,
          onClick = function(self)
              if Cfg("borderUseClass") then
                  Set("borderUseClass", false)
                  Refresh(); EllesmereUI:RefreshPage()
                  return
              end
              if self._eabOrigClick then self._eabOrigClick(self) end
          end,
          refreshAlpha = function()
              if Cfg("enabled") == false or Cfg("visibility") == "NEVER" then return 0.15 end
              return Cfg("borderUseClass") and 0.3 or 1
          end },
        { tooltip = "Class Colored",
          hasAlpha = false,
          getValue = function()
              local _, ct = UnitClass("player")
              local cc = ct and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ct]
              if cc then return cc.r, cc.g, cc.b end
              return 1, 1, 1
          end,
          setValue = function() end,
          onClick = function()
              Set("borderUseClass", true)
              Refresh(); EllesmereUI:RefreshPage()
          end,
          refreshAlpha = function()
              if Cfg("enabled") == false or Cfg("visibility") == "NEVER" then return 0.15 end
              return Cfg("borderUseClass") and 1 or 0.3
          end },
    }
end

local function BuildBattleResPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PP
    local y = yOffset
    local _, h, row

    if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
    parent._showRowDivider = true

    -- ── BATTLE RES ────────────────────────────────────────────────────
    _, h = W:SectionHeader(parent, "BATTLE RES", y); y = y - h

    -- Enable + Icon Size
    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Enable BattleRes Icon",
          values=VIS_VALUES,
          order=VIS_ORDER,
          getValue=function() return Cfg("visibility") or "MPLUS_AND_RAID" end,
          setValue=function(v) Set("visibility", v); Refresh(); EllesmereUI:RefreshPage() end },
        { type="slider", text="Icon Size",
          disabled=function() return Cfg("visibility") == "NEVER" end,
          disabledTooltip="Enable BattleRes Icon",
          min=16, max=120, step=1, isPercent=false,
          getValue=function() return Cfg("iconSize") or 40 end,
          setValue=function(v) Set("iconSize", v); Refresh() end })
    y = y - h

    -- Shape | Border Color
    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Icon Shape",
          disabled=function() return Cfg("visibility") == "NEVER" end,
          disabledTooltip="Enable BattleRes Icon",
          values=SHAPE_VALUES,
          order=SHAPE_ORDER,
          getValue=function() return Cfg("shape") or "none" end,
          setValue=function(v) Set("shape", v); Refresh() end },
        { type="multiSwatch", text="Border Color",
          disabled=function() return Cfg("visibility") == "NEVER" end,
          disabledTooltip="Enable BattleRes Icon",
          swatches = MakeBorderColorSwatches() })
    y = y - h

    -- Border Size | Icon Zoom
    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Border Size",
          disabled=function() return Cfg("visibility") == "NEVER" end,
          disabledTooltip="Enable BattleRes Icon",
          values=BORDER_VALUES,
          order=BORDER_ORDER,
          getValue=function() return Cfg("borderSize") or "thin" end,
          setValue=function(v) Set("borderSize", v); Refresh() end },
        { type="slider", text="Icon Zoom",
          disabled=function()
              if Cfg("visibility") == "NEVER" then return true end
              local s = Cfg("shape") or "none"
              return s ~= "none" and s ~= "cropped"
          end,
          disabledTooltip=function()
              if Cfg("visibility") == "NEVER" then return "Enable BattleRes Icon" end
              return "Icon Shape: None or Cropped"
          end,
          min=0, max=20, step=0.5, isPercent=false,
          getValue=function() return Cfg("iconZoom") or 11 end,
          setValue=function(v) Set("iconZoom", v); Refresh() end })
    y = y - h

    -- Duration Size | Count Size, each with inline cog (X/Y offsets)
    row, h = W:DualRow(parent, y,
        { type="slider", text="Duration Size",
          disabled=function() return Cfg("visibility") == "NEVER" end,
          disabledTooltip="Enable BattleRes Icon",
          min=8, max=24, step=1, isPercent=false,
          getValue=function() return Cfg("durationSize") or 12 end,
          setValue=function(v) Set("durationSize", v); Refresh() end },
        { type="slider", text="Count Size",
          disabled=function() return Cfg("visibility") == "NEVER" end,
          disabledTooltip="Enable BattleRes Icon",
          min=8, max=20, step=1, isPercent=false,
          getValue=function() return Cfg("countSize") or 11 end,
          setValue=function(v) Set("countSize", v); Refresh() end })
    y = y - h

    -- Inline RESIZE cogs on Duration Size (left) and Count Size (right): X/Y offsets
    do
        local function _attachOffsetCog(rgn, popupTitle, xKey, yKey)
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = popupTitle,
                rows = {
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return Cfg(xKey) or 0 end,
                      set=function(v) Set(xKey, v); Refresh() end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return Cfg(yKey) or 0 end,
                      set=function(v) Set(yKey, v); Refresh() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            PP.Point(cogBtn, "RIGHT", rgn._control or rgn, "LEFT", -6, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            local function isDisabled() return Cfg("visibility") == "NEVER" end
            local function UpdateAlpha() cogBtn:SetAlpha(isDisabled() and 0.15 or 0.4) end
            EllesmereUI.RegisterWidgetRefresh(UpdateAlpha)
            UpdateAlpha()
            cogBtn:SetScript("OnClick", function(self)
                if not isDisabled() then cogShow(self) end
            end)
            cogBtn:SetScript("OnEnter", function(self)
                if not isDisabled() then self:SetAlpha(0.75) end
            end)
            cogBtn:SetScript("OnLeave", function(self) UpdateAlpha() end)
        end
        _attachOffsetCog(row._leftRegion,  "Duration Position", "durationOffsetX", "durationOffsetY")
        _attachOffsetCog(row._rightRegion, "Count Position",    "countOffsetX",    "countOffsetY")
    end

    _, h = W:Spacer(parent, y, 20); y = y - h

    parent:SetHeight(math.abs(y - yOffset))
end

_G._EUI_BuildBattleResPage = BuildBattleResPage
