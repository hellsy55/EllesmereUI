-------------------------------------------------------------------------------
--  EUI_BlizzardSkin_Options.lua
--  Sidebar module for Blizzard UI skin. Two tabs:
--    * Character Sheet        -- themed character panel options
--    * Tooltips, Menus & Popups -- reskin toggles for Blizzard tooltips/menus
-------------------------------------------------------------------------------
local PAGE_CHARSHEET = "Character Sheet"
local PAGE_TOOLTIPS  = "Tooltips, Menus & Popups"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local function BuildTooltipsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        _, h = W:Spacer(parent, y, 20);  y = y - h

        _, h = W:SectionHeader(parent, "BLIZZARD UI ELEMENTS", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Reskin Blizzard Elements",
              tooltip="Reskins Blizzard tooltips, right-click context menus, and popups with a dark, minimal style matching the EUI aesthetic. Requires reload to apply.",
              getValue=function()
                  return not EllesmereUIDB or EllesmereUIDB.customTooltips ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.customTooltips = v
                  if EllesmereUI.ShowConfirmPopup then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Reskin setting requires a UI reload to fully apply.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end
              end },
            { type="toggle", text="Accent Colored Elements",
              tooltip="Recolors headers, arrows, and spell titles in Blizzard tooltips and context menus to match your UI Accent Color.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.accentReskinElements or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.accentReskinElements = v
              end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Player Titles in Tooltips",
              tooltip="Shows a player's RP title on their unit tooltip.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.tooltipPlayerTitles or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.tooltipPlayerTitles = v
              end },
            { type="slider", text="Font Size Scale",
              tooltip="Scales the font size of reskinned Blizzard tooltips, menus, and popups.",
              min=0.7, max=1.5, step=0.05, format="%.0f%%",
              displayMul=100,
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.tooltipFontScale or 1.0
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.tooltipFontScale = v
              end }
        );  y = y - h

        return math.abs(y)
    end

    EllesmereUI:RegisterModule("EllesmereUIBlizzardSkin", {
        title       = "Blizz UI Enhanced",
        description = "Themed Blizzard frames: Character Sheet, tooltips, menus, popups.",
        pages       = { PAGE_CHARSHEET, PAGE_TOOLTIPS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_CHARSHEET and _G._EUI_BuildCharacterSheetPage then
                return _G._EUI_BuildCharacterSheetPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_TOOLTIPS then
                return BuildTooltipsPage(pageName, parent, yOffset)
            end
        end,
    })

    SLASH_EBSK1 = "/ebsk"
    SlashCmdList.EBSK = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIBlizzardSkin")
    end
end)
