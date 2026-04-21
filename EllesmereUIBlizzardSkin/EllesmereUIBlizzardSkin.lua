-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin.lua
--  Umbrella addon for themed Blizzard UI frames. Hosts the Character Sheet
--  rework (EllesmereUIBlizzardSkin_CharacterSheet.lua) and the tooltip, context
--  menu, and static popup reskinning below.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-------------------------------------------------------------------------------
--  Tooltip / Context Menu / Static Popup Skinning
--  Restyles Blizzard's GameTooltip and related frames with EUI's dark style.
--  Visual-only changes (alpha, backdrop color, font). No Hide/Show/SetParent
--  on Blizzard frames. All hooks are post-hooks via hooksecurefunc.
-------------------------------------------------------------------------------
;(function()
    local _ttSkinned = {}
    local _isSecret = issecretvalue
    local _PP  -- resolved lazily
    local _select = select
    local _GameTooltip = GameTooltip
    local _RAID_CC = RAID_CLASS_COLORS
    local _nameL1 = nil  -- cached ref to GameTooltipTextLeft1

    local function _enabled()
        return not EllesmereUIDB or EllesmereUIDB.customTooltips ~= false
    end

    local function _ttSkin(tt, _, isEmbedded)
        if not tt or tt:IsForbidden() or not _enabled() then return end
        -- Embedded tooltips (e.g. EmbeddedItemTooltip, the reward-item block
        -- inside a world-quest tooltip) render INSIDE a parent tooltip.
        -- Adding our bg + border to them makes the embedded block look like
        -- a standalone framed tooltip sitting inside the parent.
        if isEmbedded or tt.IsEmbedded then return end
        if _isSecret and _isSecret(tt:GetWidth()) then return end
        if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
        if tt.NineSlice then tt.NineSlice:SetAlpha(0) end
        if not tt._euiBg then
            tt._euiBg = tt:CreateTexture(nil, "BACKGROUND", nil, -8)
            tt._euiBg:SetAllPoints()
            local RS = EllesmereUI.RESKIN
            tt._euiBg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.TT_ALPHA)
            if _PP and _PP.CreateBorder then
                _PP.CreateBorder(tt, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
            end
        end
        tt._euiBg:Show()
    end

    local function _ttFonts(tt)
        if not tt or tt:IsForbidden() or not _enabled() then return end
        local fp = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
        local ol = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag() or ""
        local scale = EllesmereUIDB and EllesmereUIDB.tooltipFontScale or 1.0
        local titleSize = math.floor(13 * scale + 0.5)
        local bodySize  = math.floor(11 * scale + 0.5)
        local name = tt.GetName and tt:GetName()
        if not name then return end
        local nLines = tt.NumLines and tt:NumLines() or 30
        for i = 1, nLines do
            local left = _G[name .. "TextLeft" .. i]
            if not left then break end
            left:SetFont(fp, (i == 1) and titleSize or bodySize, ol)
            local right = _G[name .. "TextRight" .. i]
            if right then right:SetFont(fp, bodySize, ol) end
        end
    end

    local function _ttOnShow(self) _ttSkin(self); _ttFonts(self) end

    local function _ttHook(tt)
        if not tt or tt:IsForbidden() or _ttSkinned[tt] then return end
        _ttSkinned[tt] = true
        tt:HookScript("OnShow", _ttOnShow)
    end

    local function _accentEnabled()
        return EllesmereUIDB and EllesmereUIDB.accentReskinElements
    end

    local function _ttUnitColor(tt)
        if tt ~= _GameTooltip or tt:IsForbidden() then return end
        local ok, _, unit = pcall(tt.GetUnit, tt)
        if not ok then return end
        if not unit then
            if UnitExists("mouseover") then unit = "mouseover" end
        end
        if not unit or (_isSecret and _isSecret(unit)) then return end
        if not UnitIsPlayer(unit) then return end
        local _, classFile = UnitClass(unit)
        if not classFile or (_isSecret and _isSecret(classFile)) then return end
        if not _nameL1 then _nameL1 = _G.GameTooltipTextLeft1 end
        if not _nameL1 then return end
        -- Strip player titles (default on: tooltipPlayerTitles is opt-in)
        local db = EllesmereUIDB
        if not (db and db.tooltipPlayerTitles) then
            local name = UnitName(unit)
            if name and not (_isSecret and _isSecret(name)) then
                local realm = select(2, UnitName(unit))
                local display = (realm and realm ~= "") and (name .. "-" .. realm) or name
                _nameL1:SetText(display)
            end
        end
        -- Class color the name line and the status bar
        local cc = _RAID_CC and _RAID_CC[classFile]
        if cc then
            _nameL1:SetTextColor(cc.r, cc.g, cc.b)
            if GameTooltipStatusBar then
                GameTooltipStatusBar:SetStatusBarColor(cc.r, cc.g, cc.b)
            end
        end
        -- M+ Score
        if EllesmereUIDB and EllesmereUIDB.tooltipMythicScore ~= false
            and C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
            local info = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
            local score = info and info.currentSeasonScore
            if score and score > 0 then
                local sColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
                    and C_ChallengeMode.GetDungeonScoreRarityColor(score)
                local r, g, b = 1, 1, 1
                if sColor then r, g, b = sColor.r, sColor.g, sColor.b end
                tt:AddDoubleLine("M+ Score:", score, 1, 1, 1, r, g, b)
            end
        end
    end

    local function _ttInit()
        for _, tt in ipairs({
            _GameTooltip, ShoppingTooltip1, ShoppingTooltip2,
            ItemRefTooltip, ItemRefShoppingTooltip1, ItemRefShoppingTooltip2,
            FriendsTooltip, EmbeddedItemTooltip, GameSmallHeaderTooltip, QuickKeybindTooltip,
            _G.WarCampaignTooltip, _G.ReputationParagonTooltip,
            _G.LibDBIconTooltip, _G.SettingsTooltip,
            QuestScrollFrame and QuestScrollFrame.StoryTooltip,
            QuestScrollFrame and QuestScrollFrame.CampaignTooltip,
        }) do
            _ttHook(tt)
        end
        if SharedTooltip_SetBackdropStyle then
            hooksecurefunc("SharedTooltip_SetBackdropStyle", _ttSkin)
        end
        if GameTooltipStatusBar then
            GameTooltipStatusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            local sbBg = GameTooltipStatusBar:CreateTexture(nil, "BACKGROUND")
            sbBg:SetAllPoints(); sbBg:SetColorTexture(0, 0, 0, 0.5)
            GameTooltipStatusBar:ClearAllPoints()
            GameTooltipStatusBar:SetPoint("BOTTOMLEFT", _GameTooltip, "BOTTOMLEFT", 1, 1)
            GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", _GameTooltip, "BOTTOMRIGHT", -1, 1)
            GameTooltipStatusBar:SetHeight(3)
        end
        -- Accent-color the title line for spells/macros (not items or units)
        local function _ttAccentTitle(tt)
            if tt ~= _GameTooltip or tt:IsForbidden() or not _accentEnabled() then return end
            if not _nameL1 then _nameL1 = _G.GameTooltipTextLeft1 end
            if _nameL1 then
                local EG = EllesmereUI.ELLESMERE_GREEN
                if EG then _nameL1:SetTextColor(EG.r, EG.g, EG.b) end
            end
        end
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, _ttUnitColor)
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, _ttAccentTitle)
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, _ttAccentTitle)
        else
            _GameTooltip:HookScript("OnTooltipSetUnit", _ttUnitColor)
            _GameTooltip:HookScript("OnTooltipSetSpell", _ttAccentTitle)
        end
    end

    -- Context menu skinning
    local _menuSkinned = {}

    local function _menuSkinFrame(frame)
        if not frame or frame:IsForbidden() or not _enabled() then return end
        for i = 1, _select("#", frame:GetRegions()) do
            local region = _select(i, frame:GetRegions())
            if region and region:IsObjectType("Texture") and not region._euiOwned then
                local RS = EllesmereUI.RESKIN
                region:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, 1)
                region:SetAlpha(RS.CTX_ALPHA)
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
                region:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
            end
        end
        if not _menuSkinned[frame] then
            _menuSkinned[frame] = true
            if _PP and _PP.CreateBorder then
                local RS = EllesmereUI.RESKIN
                _PP.CreateBorder(frame, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
            end
        end
    end

    local function _menuOnOpen(manager, _, menuDescription)
        if not _enabled() then return end
        local menu = manager.GetOpenMenu and manager:GetOpenMenu()
        if menu then
            _menuSkinFrame(menu)
        end
        if menuDescription and menuDescription.AddMenuAcquiredCallback then
            menuDescription:AddMenuAcquiredCallback(_menuSkinFrame)
        end
    end

    local function _menuInit()
        if not _G.Menu or not _G.Menu.GetManager then return end
        local mgr = _G.Menu.GetManager()
        if not mgr then return end
        hooksecurefunc(mgr, "OpenMenu", function(self, ownerRegion, menuDescription)
            _menuOnOpen(self, ownerRegion, menuDescription)
        end)
        hooksecurefunc(mgr, "OpenContextMenu", function(self, ownerRegion, menuDescription)
            _menuOnOpen(self, ownerRegion, menuDescription)
        end)
    end

    -- Static popup skinning
    local function _popupSkin(popup)
        if not popup or popup:IsForbidden() then return end
        if not _enabled() then return end
        -- Strip textures on the popup frame itself
        for i = 1, _select("#", popup:GetRegions()) do
            local r = _select(i, popup:GetRegions())
            if r and r:IsObjectType("Texture") and not r._euiOwned then
                r:SetTexture(nil)
                if r.SetAtlas then r:SetAtlas("") end
            end
        end
        -- Hide the BG border frame (StaticPopupN.BG)
        if popup.BG then popup.BG:SetAlpha(0) end
        if popup.NineSlice then popup.NineSlice:SetAlpha(0) end
        -- Our dark background + border (once)
        if not popup._euiBg then
            local RS = EllesmereUI.RESKIN
            popup._euiBg = popup:CreateTexture(nil, "BACKGROUND", nil, -8)
            popup._euiBg:SetAllPoints()
            popup._euiBg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
            popup._euiBg._euiOwned = true
            if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
            if _PP and _PP.CreateBorder then
                _PP.CreateBorder(popup, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
            end
        end
        popup._euiBg:Show()
        -- Skin buttons
        for i = 1, 4 do
            local btn = popup["button" .. i] or _G[popup:GetName() and (popup:GetName() .. "Button" .. i)]
            if btn and not btn._euiSkinned then
                btn._euiSkinned = true
                for j = 1, select("#", btn:GetRegions()) do
                    local r = select(j, btn:GetRegions())
                    if r and r:IsObjectType("Texture") and r ~= btn:GetFontString() then
                        r:SetTexture(nil)
                        if r.SetAtlas then r:SetAtlas("") end
                    end
                end
                local RS = EllesmereUI.RESKIN
                local EG = EllesmereUI.ELLESMERE_GREEN
                local useAccent = _accentEnabled() and EG
                local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                btnBg._euiOwned = true
                btn._euiBg = btnBg
                if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
                if _PP and _PP.CreateBorder then
                    if useAccent then
                        _PP.CreateBorder(btn, EG.r, EG.g, EG.b, 0.5, 1, "OVERLAY", 7)
                    else
                        _PP.CreateBorder(btn, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                    end
                end

                -- Mirror Blizzard's enabled/disabled state so buttons visibly
                -- dim when locked out (e.g. Release in boss combat).
                local function _euiRefreshEnabled(self)
                    local fs = self:GetFontString()
                    local enabled = (self.IsEnabled and self:IsEnabled()) and true or false
                    if fs then
                        if enabled then
                            local EG2 = EllesmereUI.ELLESMERE_GREEN
                            if _accentEnabled() and EG2 then
                                fs:SetTextColor(EG2.r, EG2.g, EG2.b, 1)
                            else
                                fs:SetTextColor(1, 1, 1, 1)
                            end
                        else
                            fs:SetTextColor(0.4, 0.4, 0.4, 1)
                        end
                    end
                    if self._euiBg then
                        self._euiBg:SetAlpha(enabled and 1 or 0.5)
                    end
                end
                btn._euiRefreshEnabled = _euiRefreshEnabled
                btn:HookScript("OnEnable",  _euiRefreshEnabled)
                btn:HookScript("OnDisable", _euiRefreshEnabled)
                _euiRefreshEnabled(btn)
            end
        end

        -- Hook UpdateRecapButton once per popup so our per-button enabled
        -- visual stays in sync with Blizzard's enable/disable state swaps.
        if popup.UpdateRecapButton and not popup._euiRecapHooked then
            popup._euiRecapHooked = true
            hooksecurefunc(popup, "UpdateRecapButton", function(self)
                for i = 1, 4 do
                    local b = self["button" .. i]
                    if b and b._euiRefreshEnabled then b:_euiRefreshEnabled() end
                end
            end)
        end

        -- Re-sync state for popups shown already-disabled
        for i = 1, 4 do
            local b = popup["button" .. i]
            if b and b._euiRefreshEnabled then b:_euiRefreshEnabled() end
        end
        -- Skin edit box if present
        local eb = popup.editBox or (popup.GetName and _G[popup:GetName() .. "EditBox"])
        if eb and not eb._euiSkinned then
            eb._euiSkinned = true
            for j = 1, select("#", eb:GetRegions()) do
                local r = select(j, eb:GetRegions())
                if r and r:IsObjectType("Texture") then
                    r:SetTexture(nil)
                    if r.SetAtlas then r:SetAtlas("") end
                end
            end
            local ebBg = eb:CreateTexture(nil, "BACKGROUND", nil, -6)
            ebBg:SetAllPoints()
            ebBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
            ebBg._euiOwned = true
        end
    end

    local function _popupInit()
        for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
            local popup = _G["StaticPopup" .. i]
            if popup then
                popup:HookScript("OnShow", function(self) _popupSkin(self) end)
            end
        end
    end

    do
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            if not EllesmereUIDB or EllesmereUIDB.customTooltips ~= false then
                _ttInit()
                _menuInit()
                _popupInit()
            end
        end)
    end
    EllesmereUI._initTooltipSkins = function() _ttInit(); _menuInit(); _popupInit() end
end)()

-------------------------------------------------------------------------------
--  UberTooltips CVar enforcement (only if user has manually set it in EUI)
-------------------------------------------------------------------------------
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        if EllesmereUIDB.uberTooltipsManual then
            SetCVar("UberTooltips", EllesmereUIDB.uberTooltips and "1" or "0")
        else
            SetCVar("UberTooltips", "1")
        end
    end)
end
