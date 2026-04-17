-------------------------------------------------------------------------------
--  EUI_QoL_Options.lua
--  Registers the Quality of Life sidebar addon with its two tabs:
--    * Quality of Life -- general QoL features (built by parent general options)
--    * Cursor          -- cursor skin (built by EUI_QoL_Cursor_Options.lua)
-------------------------------------------------------------------------------
local PAGE_QOL    = "Quality of Life"
local PAGE_CURSOR = "Cursor"
local PAGE_BREZ   = "BattleRes"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    EllesmereUI:RegisterModule("EllesmereUIQoL", {
        title       = "Quality of Life",
        description = "Quality of life features and custom cursor.",
        pages       = { PAGE_QOL, PAGE_CURSOR, PAGE_BREZ },
        searchTerms = { "brez", "bres", "battle res", "combat res", "cursor", "macro", "fps" },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_QOL and _G._EUI_BuildQoLPage then
                return _G._EUI_BuildQoLPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_CURSOR and _G._EBS_BuildCursorPage then
                return _G._EBS_BuildCursorPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_BREZ and _G._EUI_BuildBattleResPage then
                return _G._EUI_BuildBattleResPage(pageName, parent, yOffset)
            end
        end,
        onReset = function()
            if _G._EBS_ResetCursor then _G._EBS_ResetCursor() end
            EllesmereUI:InvalidatePageCache()
        end,
    })

    SLASH_EQOL1 = "/eqol"
    SlashCmdList.EQOL = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIQoL")
    end
end)
