-------------------------------------------------------------------------------
--  EUI_DamageMeters_Options.lua
--  Options page for EllesmereUI Damage Meters: visibility settings.
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

    local function RefreshAll()
        -- Visibility refresh will go here once reskinning is implemented
    end

    local function BuildPage(_, parent, yOffset)
        local W  = EllesmereUI.Widgets
        local PP = EllesmereUI.PP
        local y  = yOffset
        local h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

        -- Row 1: Visibility | Visibility Options
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

        return math.abs(y)
    end

    EllesmereUI:RegisterModule("EllesmereUIDamageMeters", {
        title       = "Damage Meters",
        description = "Reskins supported damage meter addons to match EllesmereUI.",
        searchTerms = "damage meters details recount skada dps hps",
        pages       = { "Damage Meters" },
        buildPage   = function(pageName, p, yOffset) return BuildPage(pageName, p, yOffset) end,
        onReset = function()
            if EllesmereUIDamageMetersDB then
                EllesmereUIDamageMetersDB.profiles = nil
                EllesmereUIDamageMetersDB.profileKeys = nil
            end
        end,
    })
end)
