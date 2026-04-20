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

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Detailed Tooltips",
              tooltip="Shows full spell and ability descriptions in tooltips instead of just the name. Only enforced on login after you toggle this setting.",
              getValue=function()
                  return GetCVar("UberTooltips") == "1"
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.uberTooltipsManual = true
                  EllesmereUIDB.uberTooltips = v
                  SetCVar("UberTooltips", v and "1" or "0")
              end },
            { type="toggle", text="Show M+ Score",
              tooltip="Displays a player's Mythic+ score on their unit tooltip, colored by rarity.",
              getValue=function()
                  return not EllesmereUIDB or EllesmereUIDB.tooltipMythicScore ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.tooltipMythicScore = v
              end }
        );  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Character Sheet options page
    ---------------------------------------------------------------------------
    local function BuildCharacterSheetPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h
        local PP = EllesmereUI.PanelPP

        parent._showRowDivider = true

        local function themedOff()
            return not (EllesmereUIDB and EllesmereUIDB.themedCharacterSheet)
        end

        local function AttachDisabledOverlay(target)
            local block = CreateFrame("Frame", nil, target)
            block:SetAllPoints(target)
            block:SetFrameLevel(target:GetFrameLevel() + 10)
            block:EnableMouse(true)
            local bg = EllesmereUI.SolidTex(block, "BACKGROUND", 0, 0, 0, 0)
            bg:SetAllPoints()
            block:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(block, EllesmereUI.DisabledTooltip("Enable Character Sheet"))
            end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function refresh()
                if themedOff() then block:Show(); target:SetAlpha(0.3)
                else block:Hide(); target:SetAlpha(1) end
            end
            EllesmereUI.RegisterWidgetRefresh(refresh); refresh()
        end

        local function AttachStatSwatch(rgn, dbColorKey, defaultColor, parentEnabledFn, cogOpts)
            local swGet = function()
                local c = EllesmereUIDB and EllesmereUIDB.statCategoryColors and EllesmereUIDB.statCategoryColors[dbColorKey]
                if c then return c.r, c.g, c.b, 1 end
                return defaultColor.r, defaultColor.g, defaultColor.b, 1
            end
            local swSet = function(r, g, b)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                if not EllesmereUIDB.statCategoryColors then EllesmereUIDB.statCategoryColors = {} end
                if not EllesmereUIDB.statCategoryUseColor then EllesmereUIDB.statCategoryUseColor = {} end
                EllesmereUIDB.statCategoryColors[dbColorKey] = { r = r, g = g, b = b }
                EllesmereUIDB.statCategoryUseColor[dbColorKey] = true
                if EllesmereUI._refreshCharacterSheetColors then EllesmereUI._refreshCharacterSheetColors() end
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, swGet, swSet, false, 20)
            PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
            rgn._lastInline = swatch
            local function refresh()
                local parentEnabled = parentEnabledFn()
                if themedOff() then
                    swatch:SetAlpha(0.15); swatch:EnableMouse(false)
                else
                    swatch:SetAlpha(parentEnabled and 1 or 0.3)
                    swatch:EnableMouse(parentEnabled)
                end
                updateSwatch()
            end
            EllesmereUI.RegisterWidgetRefresh(refresh); refresh()

            if cogOpts then
                local _, cogShow = EllesmereUI.BuildCogPopup(cogOpts)
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(EllesmereUI.COGS_ICON)
                cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                cogBtn:SetScript("OnLeave", function(self)
                    local parentEnabled = parentEnabledFn()
                    self:SetAlpha(themedOff() and 0.15 or (parentEnabled and 0.4 or 0.15))
                end)
                cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
                local function cogRefresh()
                    local parentEnabled = parentEnabledFn()
                    if themedOff() then
                        cogBtn:SetAlpha(0.15); cogBtn:EnableMouse(false)
                    else
                        cogBtn:SetAlpha(parentEnabled and 0.4 or 0.15)
                        cogBtn:EnableMouse(parentEnabled)
                    end
                end
                EllesmereUI.RegisterWidgetRefresh(cogRefresh); cogRefresh()
            end
        end

        local function StatCategoryToggle(text, key, tooltipText)
            return { type="toggle", text=text, tooltip=tooltipText,
                     getValue=function()
                         return EllesmereUIDB and EllesmereUIDB["showStatCategory_"..key] ~= false
                     end,
                     setValue=function(v)
                         if not EllesmereUIDB then EllesmereUIDB = {} end
                         EllesmereUIDB["showStatCategory_"..key] = v
                         if EllesmereUI._updateStatCategoryVisibility then
                             EllesmereUI._updateStatCategoryVisibility()
                         end
                         EllesmereUI:RefreshPage()
                     end }
        end
        local function StatCategoryEnabled(key)
            return function()
                return EllesmereUIDB and EllesmereUIDB["showStatCategory_"..key] ~= false
            end
        end

        ---------------------------------------------------------------------------
        --  CORE OPTIONS
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CORE OPTIONS", y);  y = y - h

        local enableRow
        enableRow, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Character Sheet",
              tooltip="Applies EllesmereUI theme styling to the character sheet window.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.themedCharacterSheet or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.themedCharacterSheet = v
                  if not v then
                      EllesmereUIDB.showMythicRating = false
                      EllesmereUIDB.showItemLevel = false
                      EllesmereUIDB.showUpgradeTrack = false
                      EllesmereUIDB.showEnchants = false
                      EllesmereUIDB.showGems = false
                      EllesmereUIDB.showStatCategory_Attributes = false
                      EllesmereUIDB.showStatCategory_Attack = false
                      EllesmereUIDB.showStatCategory_Crests = false
                      EllesmereUIDB.showStatCategory_SecondaryStats = false
                      EllesmereUIDB.showStatCategory_Tertiary = false
                      EllesmereUIDB.showStatCategory_Defense = false
                      EllesmereUIDB.showStatCategory_PvP = false
                  end
                  if EllesmereUI.ShowConfirmPopup then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Character Sheet theme setting requires a UI reload to fully apply.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Show Mythic+ Rating",
              tooltip="Display your Mythic+ rating above the item level on the character sheet.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showMythicRating or false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showMythicRating = v
                  if EllesmereUI._updateMythicRatingDisplay then EllesmereUI._updateMythicRatingDisplay() end
              end }
        );  y = y - h

        do
            local leftRgn = enableRow._leftRegion
            local _, scaleCogShow = EllesmereUI.BuildCogPopup({
                title = "Character Sheet Settings",
                rows = {
                    { type="slider", label="Scale", min=0.5, max=1.5, step=0.05,
                      get=function()
                          return EllesmereUIDB and EllesmereUIDB.themedCharacterSheetScale or 1
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.themedCharacterSheetScale = v
                          if CharacterFrame then CharacterFrame:SetScale(v) end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, leftRgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) scaleCogShow(self) end)
        end

        AttachDisabledOverlay(enableRow._rightRegion)

        local ilvlRow
        ilvlRow, h = W:DualRow(parent, y,
            { type="toggle", text="Item Level",
              tooltip="Toggle visibility of item level text on the character sheet.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showItemLevel ~= false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showItemLevel = v
                  if EllesmereUI._refreshItemLevelVisibility then EllesmereUI._refreshItemLevelVisibility() end
              end },
            { type="toggle", text="Upgrade Track",
              tooltip="Toggle visibility of upgrade track text on the character sheet.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showUpgradeTrack ~= false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showUpgradeTrack = v
                  if EllesmereUI._refreshUpgradeTrackVisibility then EllesmereUI._refreshUpgradeTrackVisibility() end
              end }
        );  y = y - h
        AttachDisabledOverlay(ilvlRow)

        local enchGemRow
        enchGemRow, h = W:DualRow(parent, y,
            { type="toggle", text="Enchants",
              tooltip="Toggle visibility of enchant text on the character sheet.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showEnchants ~= false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showEnchants = v
                  if EllesmereUI._refreshEnchantsVisibility then EllesmereUI._refreshEnchantsVisibility() end
              end },
            { type="toggle", text="Show Gems",
              tooltip="Toggle visibility of gem icons inside equipment slots.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showGems ~= false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showGems = v
                  if EllesmereUI._refreshGemsVisibility then EllesmereUI._refreshGemsVisibility() end
              end }
        );  y = y - h
        AttachDisabledOverlay(enchGemRow)

        _, h = W:Spacer(parent, y, 10);  y = y - h

        ---------------------------------------------------------------------------
        --  STAT DISPLAY
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "STAT DISPLAY", y);  y = y - h

        local secondaryCogOpts = {
            title = "Secondary Stats Settings",
            rows = {
                { type="toggle", label="Show Raw Rating",
                  get=function() return EllesmereUIDB and EllesmereUIDB.showSecondaryRaw or false end,
                  set=function(v)
                      if not EllesmereUIDB then EllesmereUIDB = {} end
                      EllesmereUIDB.showSecondaryRaw = v
                      if v then EllesmereUIDB.showSecondaryBoth = false end
                      if EllesmereUI._refreshStatFormats then EllesmereUI._refreshStatFormats() end
                  end },
                { type="toggle", label="Show % and Raw",
                  get=function() return EllesmereUIDB and EllesmereUIDB.showSecondaryBoth or false end,
                  set=function(v)
                      if not EllesmereUIDB then EllesmereUIDB = {} end
                      EllesmereUIDB.showSecondaryBoth = v
                      if v then EllesmereUIDB.showSecondaryRaw = false end
                      if EllesmereUI._refreshStatFormats then EllesmereUI._refreshStatFormats() end
                  end },
            },
        }
        local tertiaryCogOpts = {
            title = "Tertiary Stats Settings",
            rows = {
                { type="toggle", label="Show Raw Rating",
                  get=function() return EllesmereUIDB and EllesmereUIDB.showTertiaryRaw or false end,
                  set=function(v)
                      if not EllesmereUIDB then EllesmereUIDB = {} end
                      EllesmereUIDB.showTertiaryRaw = v
                      if v then EllesmereUIDB.showTertiaryBoth = false end
                      if EllesmereUI._refreshStatFormats then EllesmereUI._refreshStatFormats() end
                  end },
                { type="toggle", label="Show % and Raw",
                  get=function() return EllesmereUIDB and EllesmereUIDB.showTertiaryBoth or false end,
                  set=function(v)
                      if not EllesmereUIDB then EllesmereUIDB = {} end
                      EllesmereUIDB.showTertiaryBoth = v
                      if v then EllesmereUIDB.showTertiaryRaw = false end
                      if EllesmereUI._refreshStatFormats then EllesmereUI._refreshStatFormats() end
                  end },
            },
        }
        local function crestRow(label, key)
            return { type="toggle", label=label,
                     get=function()
                         return not (EllesmereUIDB and EllesmereUIDB["showCrest_"..key] == false)
                     end,
                     set=function(v)
                         if not EllesmereUIDB then EllesmereUIDB = {} end
                         EllesmereUIDB["showCrest_"..key] = v
                         if EllesmereUI._refreshStatsVisibility then EllesmereUI._refreshStatsVisibility() end
                     end }
        end
        local crestsCogOpts = {
            title = "Crests",
            rows = {
                crestRow("Show Myth",       "Myth"),
                crestRow("Show Hero",       "Hero"),
                crestRow("Show Champion",   "Champion"),
                crestRow("Show Veteran",    "Veteran"),
                crestRow("Show Adventurer", "Adventurer"),
            },
        }

        local statRow1
        statRow1, h = W:DualRow(parent, y,
            StatCategoryToggle("Show Attributes", "Attributes",
                "Toggle visibility of the Attributes stat category."),
            StatCategoryToggle("Show Secondary", "SecondaryStats",
                "Toggle visibility of the Secondary Stats category.")
        );  y = y - h
        AttachDisabledOverlay(statRow1)
        AttachStatSwatch(statRow1._leftRegion, "Attributes",
            { r = 0.047, g = 0.824, b = 0.616 }, StatCategoryEnabled("Attributes"))
        AttachStatSwatch(statRow1._rightRegion, "Secondary Stats",
            { r = 0.471, g = 0.255, b = 0.784 }, StatCategoryEnabled("SecondaryStats"),
            secondaryCogOpts)

        local statRow2
        statRow2, h = W:DualRow(parent, y,
            StatCategoryToggle("Show Tertiary", "Tertiary",
                "Toggle visibility of the Tertiary stat category (Leech, Avoidance, Speed)."),
            StatCategoryToggle("Show Attack", "Attack",
                "Toggle visibility of the Attack stat category.")
        );  y = y - h
        AttachDisabledOverlay(statRow2)
        AttachStatSwatch(statRow2._leftRegion, "Tertiary Stats",
            { r = 0.859, g = 0.325, b = 0.855 }, StatCategoryEnabled("Tertiary"),
            tertiaryCogOpts)
        AttachStatSwatch(statRow2._rightRegion, "Attack",
            { r = 1, g = 0.353, b = 0.122 }, StatCategoryEnabled("Attack"))

        local statRow3
        statRow3, h = W:DualRow(parent, y,
            StatCategoryToggle("Show Defense", "Defense",
                "Toggle visibility of the Defense stat category."),
            StatCategoryToggle("Show Crests", "Crests",
                "Toggle visibility of the Crests stat category.")
        );  y = y - h
        AttachDisabledOverlay(statRow3)
        AttachStatSwatch(statRow3._leftRegion, "Defense",
            { r = 0.247, g = 0.655, b = 1 }, StatCategoryEnabled("Defense"))
        AttachStatSwatch(statRow3._rightRegion, "Crests",
            { r = 1, g = 0.784, b = 0.341 }, StatCategoryEnabled("Crests"),
            crestsCogOpts)

        local statRow4
        statRow4, h = W:DualRow(parent, y,
            StatCategoryToggle("Show PvP", "PvP",
                "Toggle visibility of the PvP stat category (Honor Level, Honor, Conquest)."),
            { type="label", text="" }
        );  y = y - h
        AttachDisabledOverlay(statRow4)
        AttachStatSwatch(statRow4._leftRegion, "PvP",
            { r = 0.671, g = 0.431, b = 0.349 }, StatCategoryEnabled("PvP"))

        ---------------------------------------------------------------------------
        --  INSPECT SHEET
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "INSPECT SHEET", y);  y = y - h

        local themedInspectSheetRow
        themedInspectSheetRow, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Inspect Sheet",
              tooltip="Applies EllesmereUI theme styling to the inspect sheet window.",
              getValue=function()
                  return not EllesmereUIDB or EllesmereUIDB.themedInspectSheet ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.themedInspectSheet = v
                  if EllesmereUI.ShowConfirmPopup then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Inspect Sheet theme setting requires a UI reload to fully apply.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Show Enchants",
              tooltip="Toggle visibility of enchant icons on the inspect sheet.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.inspectShowEnchants ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.inspectShowEnchants = v
                  if EllesmereUI._refreshInspectEnchantsVisibility then
                      EllesmereUI._refreshInspectEnchantsVisibility()
                  end
              end }
        );  y = y - h

        do
            local function themedOff()
                return not (EllesmereUIDB and EllesmereUIDB.themedInspectSheet)
            end

            local leftRgn = themedInspectSheetRow._leftRegion
            local _, themedInspectCogShow = EllesmereUI.BuildCogPopup({
                title = "Inspect Sheet Settings",
                rows = {
                    { type="slider", label="Scale",
                      min=0.5, max=1.5, step=0.05,
                      get=function()
                          return EllesmereUIDB and EllesmereUIDB.themedInspectSheetScale or 1
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.themedInspectSheetScale = v
                          if InspectFrame then
                              InspectFrame:SetScale(v)
                          end
                      end },
                },
            })

            local themedInspectCogBtn = CreateFrame("Button", nil, leftRgn)
            themedInspectCogBtn:SetSize(26, 26)
            themedInspectCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = themedInspectCogBtn
            themedInspectCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            themedInspectCogBtn:SetAlpha(themedOff() and 0.15 or 0.4)
            local themedInspectCogTex = themedInspectCogBtn:CreateTexture(nil, "OVERLAY")
            themedInspectCogTex:SetAllPoints()
            themedInspectCogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            themedInspectCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            themedInspectCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(themedOff() and 0.15 or 0.4) end)
            themedInspectCogBtn:SetScript("OnClick", function(self) themedInspectCogShow(self) end)

            local themedInspectCogBlock = CreateFrame("Frame", nil, themedInspectCogBtn)
            themedInspectCogBlock:SetAllPoints()
            themedInspectCogBlock:SetFrameLevel(themedInspectCogBtn:GetFrameLevel() + 10)
            themedInspectCogBlock:EnableMouse(true)
            themedInspectCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(themedInspectCogBtn, EllesmereUI.DisabledTooltip("Enable Inspect Sheet"))
            end)
            themedInspectCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                if themedOff() then
                    themedInspectCogBtn:SetAlpha(0.15)
                    themedInspectCogBlock:Show()
                else
                    themedInspectCogBtn:SetAlpha(0.4)
                    themedInspectCogBlock:Hide()
                end
            end)
            if themedOff() then themedInspectCogBtn:SetAlpha(0.15) themedInspectCogBlock:Show() else themedInspectCogBtn:SetAlpha(0.4) themedInspectCogBlock:Hide() end
        end

        local itemLevelInspectRow
        itemLevelInspectRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Item Level",
              tooltip="Toggle visibility of item level text on the inspect sheet.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.inspectShowItemLevel ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.inspectShowItemLevel = v
                  if EllesmereUI._refreshInspectItemLevelVisibility then
                      EllesmereUI._refreshInspectItemLevelVisibility()
                  end
              end },
            { type="toggle", text="Show Upgrade Track",
              tooltip="Toggle visibility of upgrade track text on the inspect sheet.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.inspectShowUpgradeTrack ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.inspectShowUpgradeTrack = v
                  if EllesmereUI._refreshInspectUpgradeTrackVisibility then
                      EllesmereUI._refreshInspectUpgradeTrackVisibility()
                  end
              end }
        );  y = y - h

        do
            local function themedOff()
                return not (EllesmereUIDB and EllesmereUIDB.themedInspectSheet)
            end

            local itemLevelInspectBlock = CreateFrame("Frame", nil, itemLevelInspectRow)
            itemLevelInspectBlock:SetAllPoints(itemLevelInspectRow)
            itemLevelInspectBlock:SetFrameLevel(itemLevelInspectRow:GetFrameLevel() + 10)
            itemLevelInspectBlock:EnableMouse(true)
            local itemLevelInspectBg = EllesmereUI.SolidTex(itemLevelInspectBlock, "BACKGROUND", 0, 0, 0, 0)
            itemLevelInspectBg:SetAllPoints()
            itemLevelInspectBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(itemLevelInspectBlock, EllesmereUI.DisabledTooltip("Enable Inspect Sheet"))
            end)
            itemLevelInspectBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                if themedOff() then
                    itemLevelInspectBlock:Show()
                    itemLevelInspectRow:SetAlpha(0.3)
                else
                    itemLevelInspectBlock:Hide()
                    itemLevelInspectRow:SetAlpha(1)
                end
            end)
            if themedOff() then itemLevelInspectBlock:Show() itemLevelInspectRow:SetAlpha(0.3) else itemLevelInspectBlock:Hide() itemLevelInspectRow:SetAlpha(1) end
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h
        return math.abs(y)
    end

    EllesmereUI:RegisterModule("EllesmereUIBlizzardSkin", {
        title       = "Blizz UI Enhanced",
        description = "Themed Blizzard frames: Character Sheet, tooltips, menus, popups.",
        pages       = { PAGE_CHARSHEET, PAGE_TOOLTIPS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_CHARSHEET then
                return BuildCharacterSheetPage(pageName, parent, yOffset)
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
