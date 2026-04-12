--------------------------------------------------------------------------------
--  Themed Character Sheet
--------------------------------------------------------------------------------
local ADDON_NAME = ...
local skinned = false
local activeEquipmentSetID = nil  -- Track currently equipped set

-- Apply EUI theme to character sheet frame
local function SkinCharacterSheet()
    if skinned then return end
    skinned = true

    local frame = CharacterFrame
    if not frame then return end

    -- Hide Blizzard decorations
    if CharacterFrame.NineSlice then CharacterFrame.NineSlice:Hide() end
    -- NOTE: Don't hide frame.Bg - we need it as anchor for slots!
    if frame.Background then frame.Background:Hide() end
    if frame.TitleBg then frame.TitleBg:Hide() end
    if frame.TopTileStreaks then frame.TopTileStreaks:Hide() end
    if frame.Portrait then frame.Portrait:Hide() end
    if CharacterFramePortrait then CharacterFramePortrait:Hide() end
    -- NOTE: Don't hide CharacterFrameBg - we use it as anchor point for item slots!
    if CharacterModelFrameBackgroundOverlay then CharacterModelFrameBackgroundOverlay:Hide() end
    if CharacterModelFrameBackgroundTopLeft then CharacterModelFrameBackgroundTopLeft:Hide() end
    if CharacterModelFrameBackgroundBotLeft then CharacterModelFrameBackgroundBotLeft:Hide() end
    if CharacterModelFrameBackgroundTopRight then CharacterModelFrameBackgroundTopRight:Hide() end
    if CharacterModelFrameBackgroundBotRight then CharacterModelFrameBackgroundBotRight:Hide() end
    -- NOTE: Don't hide CharacterFrameBg - we need it as anchor point for item slots!
    if CharacterFrameInsetRight then
        if CharacterFrameInsetRight.NineSlice then CharacterFrameInsetRight.NineSlice:Hide() end
        CharacterFrameInsetRight:ClearAllPoints()
        CharacterFrameInsetRight:SetPoint("TOPLEFT", frame, "TOPLEFT", 500, -500)
    end
    if CharacterFrameInsetBG then CharacterFrameInsetBG:Hide() end
    if CharacterFrameInset and CharacterFrameInset.NineSlice then
        for _, edge in ipairs({"TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner"}) do
            if CharacterFrameInset.NineSlice[edge] then
                CharacterFrameInset.NineSlice[edge]:Hide()
            end
        end
    end
    -- Add colored backgrounds to CharacterFrameInset (EUI FriendsList style)
    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05
    if CharacterFrameInset then
        if CharacterFrameInset.AbsBg then
            CharacterFrameInset.AbsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
        end
        if CharacterFrameInset.Bg then
            CharacterFrameInset.Bg:SetColorTexture(0.02, 0.02, 0.025, 1)  -- Darker for ScrollBox
        end
    end

    if CharacterModelScene then
        CharacterModelScene:Show()
        CharacterModelScene:ClearAllPoints()
        CharacterModelScene:SetPoint("TOPLEFT", frame, "TOPLEFT", 110, -100)
        CharacterModelScene:SetFrameLevel(2)  -- Keep model behind text

        -- Hide control frame (zoom, rotation buttons)
        if CharacterModelScene.ControlFrame then
            CharacterModelScene.ControlFrame:Hide()
        end

        -- Create update loop to keep all control buttons hidden
        local hideControlButtons = CreateFrame("Frame")
        hideControlButtons:SetScript("OnUpdate", function()
            if CharacterModelScene.ControlFrame then
                -- Hide zoom buttons
                if CharacterModelScene.ControlFrame.zoomInButton and CharacterModelScene.ControlFrame.zoomInButton:IsShown() then
                    CharacterModelScene.ControlFrame.zoomInButton:Hide()
                end
                if CharacterModelScene.ControlFrame.zoomOutButton and CharacterModelScene.ControlFrame.zoomOutButton:IsShown() then
                    CharacterModelScene.ControlFrame.zoomOutButton:Hide()
                end
                -- Hide all other buttons in ControlFrame (rotation buttons, etc)
                for i = 1, CharacterModelScene.ControlFrame:GetNumChildren() do
                    local child = select(i, CharacterModelScene.ControlFrame:GetChildren())
                    if child and child:IsShown() then
                        child:Hide()
                    end
                end
            end
        end)
    end

    -- Center the level text under character name
    if CharacterLevelText and CharacterFrameTitleText then
        CharacterLevelText:ClearAllPoints()
        CharacterLevelText:SetPoint("TOP", CharacterFrameTitleText, "BOTTOM", 0, -5)
        CharacterLevelText:SetJustifyH("CENTER")
    end

    -- Hide model control help text
    if CharacterModelFrameHelpText then CharacterModelFrameHelpText:Hide() end

    if CharacterFrameInsetBG then CharacterFrameInsetBG:Hide() end
    if CharacterFrameInset and CharacterFrameInset.NineSlice then
        for _, edge in ipairs({"TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner"}) do
            if CharacterFrameInset.NineSlice[edge] then
                CharacterFrameInset.NineSlice[edge]:Hide()
            end
        end
    end


    -- Hide PaperDoll borders (Blizzard's outer window frame)
    if frame.PaperDollFrame then
        if frame.PaperDollFrame.InnerBorder then
            for _, name in ipairs({"Top", "Bottom", "Left", "Right", "TopLeft", "TopRight", "BottomLeft", "BottomRight"}) do
                if frame.PaperDollFrame.InnerBorder[name] then
                    frame.PaperDollFrame.InnerBorder[name]:Hide()
                end
            end
        end
    end

    -- Hide all PaperDollInnerBorder textures
    for _, name in ipairs({"TopLeft", "TopRight", "BottomLeft", "BottomRight", "Top", "Bottom", "Left", "Right", "Bottom2"}) do
        if _G["PaperDollInnerBorder" .. name] then
            _G["PaperDollInnerBorder" .. name]:Hide()
        end
    end

    if PaperDollItemsFrame then PaperDollItemsFrame:Hide() end
    if CharacterStatPane then
        -- Hide ClassBackground
        if CharacterStatPane.ClassBackground then
            CharacterStatPane.ClassBackground:Hide()
        end
        -- Move CharacterStatPane off-screen
        CharacterStatPane:ClearAllPoints()
        CharacterStatPane:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -500)
    end

    -- Hide secondary hand slot extra element for testing
    if _G["CharacterSecondaryHandSlot.26129b81ae0"] then
        _G["CharacterSecondaryHandSlot.26129b81ae0"]:Hide()
    end


    -- Hide all SlotFrame wrapper containers
    _G.CharacterBackSlotFrame:Hide()
    _G.CharacterChestSlotFrame:Hide()
    _G.CharacterFeetSlotFrame:Hide()
    _G.CharacterFinger0SlotFrame:Hide()
    _G.CharacterFinger1SlotFrame:Hide()
    _G.CharacterHandsSlotFrame:Hide()
    _G.CharacterHeadSlotFrame:Hide()
    _G.CharacterLegsSlotFrame:Hide()
    _G.CharacterMainHandSlotFrame:Hide()
    _G.CharacterNeckSlotFrame:Hide()
    _G.CharacterSecondaryHandSlotFrame:Hide()
    _G.CharacterShirtSlotFrame:Hide()
    _G.CharacterShoulderSlotFrame:Hide()
    _G.CharacterTabardSlotFrame:Hide()
    _G.CharacterTrinket0SlotFrame:Hide()
    _G.CharacterTrinket1SlotFrame:Hide()
    _G.CharacterWaistSlotFrame:Hide()
    _G.CharacterWristSlotFrame:Hide()

    -- Custom flexible grid layout (NO REPARENTING!)
    -- Slots stay in original parents, positioned via grid system
    if CharacterFrameBg then CharacterFrameBg:Show() end

    local slotNames = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
        "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }

    -- Show all slots AND their parents
    for _, slotName in ipairs(slotNames) do
        local slot = _G[slotName]
        if slot then
            slot:Show()
            local parent = slot:GetParent()
            if parent then
                parent:Show()
            end
        end
    end

    -- Grid-based layout system (2 columns)
    local gridCols = 2
    local cellWidth = 360
    local cellHeight = 45
    local gridStartX = 30
    local gridStartY = -60

    -- Equipment slot grid positions (2 columns: left & right)
    local slotGridMap = {
        -- Left column
        CharacterHeadSlot = {col = 0, row = 0},
        CharacterNeckSlot = {col = 0, row = 1},
        CharacterShoulderSlot = {col = 0, row = 2},
        CharacterBackSlot = {col = 0, row = 3},
        CharacterChestSlot = {col = 0, row = 4},
        CharacterShirtSlot = {col = 0, row = 5},
        CharacterTabardSlot = {col = 0, row = 6},
        CharacterWristSlot = {col = 0, row = 7},

        -- Right column
        CharacterHandsSlot = {col = 1, row = 0},
        CharacterWaistSlot = {col = 1, row = 1},
        CharacterLegsSlot = {col = 1, row = 2},
        CharacterFeetSlot = {col = 1, row = 3},
        CharacterFinger0Slot = {col = 1, row = 4},
        CharacterFinger1Slot = {col = 1, row = 5},
        CharacterTrinket0Slot = {col = 1, row = 6},
        CharacterTrinket1Slot = {col = 1, row = 7},
    }

    -- Position main grid slots using anchor calculations
    for slotName, gridPos in pairs(slotGridMap) do
        local slot = _G[slotName]
        if slot then
            slot:ClearAllPoints()
            local xOffset = gridStartX + (gridPos.col * cellWidth)
            local yOffset = gridStartY - (gridPos.row * cellHeight)
            slot:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", xOffset, yOffset)
        end
    end

    -- Weapons positioned in bottom-right area (separate from grid)
    _G.CharacterMainHandSlot:ClearAllPoints()
    _G.CharacterMainHandSlot:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", 175, 25)
    _G.CharacterSecondaryHandSlot:ClearAllPoints()
    _G.CharacterSecondaryHandSlot:SetPoint("TOPLEFT", _G.CharacterMainHandSlot, "TOPRIGHT", 12, 0)



    -- Hook slot enter to show flyout when equipment mode is active
    if not frame._slotHookDone then
        local origOnEnter = PaperDollItemSlotButton_OnEnter
        PaperDollItemSlotButton_OnEnter = function(button)
            origOnEnter(button)
            -- If flyout mode is active, also show flyout
            if frame._flyoutModeActive and button:GetID() then
                if EquipmentFlyout_Show then
                    pcall(EquipmentFlyout_Show, button)
                end
            end
        end
        frame._slotHookDone = true
    end

    -- Hide slot textures and borders (Chonky style)
    select(16, _G.CharacterMainHandSlot:GetRegions()):SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)
    select(17, _G.CharacterMainHandSlot:GetRegions()):SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)
    select(16, _G.CharacterSecondaryHandSlot:GetRegions()):SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)
    select(17, _G.CharacterSecondaryHandSlot:GetRegions()):SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)

    -- Hide icon borders and adjust texcoords
    local slotsToHide = {
        "CharacterBackSlot", "CharacterChestSlot", "CharacterFeetSlot",
        "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterHandsSlot",
        "CharacterHeadSlot", "CharacterLegsSlot", "CharacterMainHandSlot",
        "CharacterNeckSlot", "CharacterSecondaryHandSlot", "CharacterShirtSlot",
        "CharacterShoulderSlot", "CharacterTabardSlot", "CharacterTrinket0Slot",
        "CharacterTrinket1Slot", "CharacterWaistSlot", "CharacterWristSlot"
    }

    for _, slotName in ipairs(slotsToHide) do
        local slot = _G[slotName]
        if slot then
            slot:Show()
            if slot.IconBorder then
                slot.IconBorder:SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)
            end
            local iconTexture = _G[slotName .. "IconTexture"]
            if iconTexture then
                iconTexture:SetTexCoord(.07,.07,.07,.93,.93,.07,.93,.93)
            end
            local normalTexture = _G[slotName .. "NormalTexture"]
            if normalTexture then
                normalTexture:Hide()
            end
        end
    end

    -- Hide special regions on weapon slots
    select(16, _G.CharacterMainHandSlot:GetRegions()):SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    select(17, _G.CharacterMainHandSlot:GetRegions()):SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    select(16, _G.CharacterSecondaryHandSlot:GetRegions()):SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    select(17, _G.CharacterSecondaryHandSlot:GetRegions()):SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)

    -- Show all slots with blending
    local slotNames = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
        "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }
    for _, slotName in ipairs(slotNames) do
        local slot = _G[slotName]
        if slot then
            slot:Show()
            if slot._slotBg then
                slot._slotBg:SetBlendMode("BLEND")
            end
        end
    end

    -- Apply scale if saved
    local scale = EllesmereUIDB and EllesmereUIDB.themedCharacterSheetScale or 1
    frame:SetScale(scale)

    -- Raise frame strata for visibility
    frame:SetFrameStrata("HIGH")

    -- Resize frame to be wider
    -- Resize frame and hook to keep the size
    -- Set fixed frame size directly (not expanding from original)
    local newWidth = 698  -- Fixed width
    local newHeight = 480  -- Fixed height
    frame:SetWidth(newWidth)
    frame:SetHeight(newHeight)

    -- Also expand CharacterFrameInset to match
    if CharacterFrameInset then
        CharacterFrameInset:SetWidth(newWidth - 20)
        CharacterFrameInset:SetHeight(newHeight - 90)
        CharacterFrameInset:SetClipsChildren(false)  -- Prevent clipping
    end

    -- Hook SetWidth to prevent Blizzard from changing it back (skip in combat)
    hooksecurefunc(frame, "SetWidth", function(self, w)
        if w ~= newWidth and not InCombatLockdown() then
            self:SetWidth(newWidth)
        end
    end)

    -- Hook SetHeight to prevent Blizzard from changing it back (skip in combat)
    hooksecurefunc(frame, "SetHeight", function(self, h)
        if h ~= newHeight and not InCombatLockdown() then
            self:SetHeight(newHeight)
        end
    end)

    -- Add SetPoint hook too - Blizzard might resize via SetPoint
    local hookLock = false
    hooksecurefunc(frame, "SetPoint", function(self, ...)
        if not hookLock and frame._sizeCheckDone then
            hookLock = true
            if not InCombatLockdown() then
                self:SetSize(newWidth, newHeight)
                if self._ebsBg then
                    self._ebsBg:SetSize(newWidth, newHeight)
                end
            end
            hookLock = false
        end
    end)

    -- Aggressive size enforcement with immediate re-setup
    if not frame._sizeCheckDone then
        local function EnforceSize()
            if frame:IsShown() and not InCombatLockdown() then
                frame:SetSize(newWidth, newHeight)
                -- Regenerate background immediately
                if frame._ebsBg then
                    frame._ebsBg:SetSize(newWidth, newHeight)
                    frame._ebsBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
                end
                if CharacterFrameInset then
                    CharacterFrameInset:SetClipsChildren(false)
                    CharacterFrameInset:SetSize(newWidth - 20, newHeight - 90)
                end
            end
        end

        -- Continuous check with OnUpdate (no event registration needed)
        local updateFrame = CreateFrame("Frame")
        updateFrame:SetScript("OnUpdate", EnforceSize)

        frame._sizeCheckDone = true
    end

    -- Strip textures from frame regions
    for i = 1, select("#", frame:GetRegions()) do
        local region = select(i, frame:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end

    -- Add custom background with EUI colors (same as FriendsFrame)
    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

    -- Main frame background at BACKGROUND layer -8 (fixed size, not scaled)
    frame._ebsBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame._ebsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
    frame._ebsBg:SetSize(newWidth, newHeight)
    frame._ebsBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame._ebsBg:SetAlpha(1)

    -- Create dark gray border using PP.CreateBorder
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(frame, 0.2, 0.2, 0.2, 1, 1, "OVERLAY", 7)
    end

    -- Skin close button
    local closeBtn = frame.CloseButton or _G.CharacterFrameCloseButton
    if closeBtn then
        -- Strip button textures
        if closeBtn.SetNormalTexture then closeBtn:SetNormalTexture("") end
        if closeBtn.SetPushedTexture then closeBtn:SetPushedTexture("") end
        if closeBtn.SetHighlightTexture then closeBtn:SetHighlightTexture("") end
        if closeBtn.SetDisabledTexture then closeBtn:SetDisabledTexture("") end

        -- Strip texture regions
        for i = 1, select("#", closeBtn:GetRegions()) do
            local region = select(i, closeBtn:GetRegions())
            if region and region:IsObjectType("Texture") then
                region:SetAlpha(0)
            end
        end

        -- Get font path for close button
        local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT

        -- Create X text
        closeBtn._ebsX = closeBtn:CreateFontString(nil, "OVERLAY")
        closeBtn._ebsX:SetFont(fontPath, 14, "")
        closeBtn._ebsX:SetText("x")
        closeBtn._ebsX:SetTextColor(1, 1, 1, 0.5)
        closeBtn._ebsX:SetPoint("CENTER", -2, -3)

        -- Hover effect
        closeBtn:HookScript("OnEnter", function()
            if closeBtn._ebsX then closeBtn._ebsX:SetTextColor(1, 1, 1, 0.9) end
        end)
        closeBtn:HookScript("OnLeave", function()
            if closeBtn._ebsX then closeBtn._ebsX:SetTextColor(1, 1, 1, 0.5) end
        end)
    end

    -- Restyle character frame tabs (matching FriendsFrame pattern)
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.51, g = 0.784, b = 1 }

    for i = 1, 3 do
        local tab = _G["CharacterFrameTab" .. i]
        if tab then
            -- Strip Blizzard's tab textures
            for j = 1, select("#", tab:GetRegions()) do
                local region = select(j, tab:GetRegions())
                if region and region:IsObjectType("Texture") then
                    region:SetTexture("")
                    if region.SetAtlas then region:SetAtlas("") end
                end
            end
            if tab.Left then tab.Left:SetTexture("") end
            if tab.Middle then tab.Middle:SetTexture("") end
            if tab.Right then tab.Right:SetTexture("") end
            if tab.LeftDisabled then tab.LeftDisabled:SetTexture("") end
            if tab.MiddleDisabled then tab.MiddleDisabled:SetTexture("") end
            if tab.RightDisabled then tab.RightDisabled:SetTexture("") end
            local hl = tab:GetHighlightTexture()
            if hl then hl:SetTexture("") end

            -- Dark background
            if not tab._ebsBg then
                tab._ebsBg = tab:CreateTexture(nil, "BACKGROUND")
                tab._ebsBg:SetAllPoints()
                tab._ebsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
            end

            -- Active highlight
            if not tab._activeHL then
                local activeHL = tab:CreateTexture(nil, "ARTWORK", nil, -6)
                activeHL:SetAllPoints()
                activeHL:SetColorTexture(1, 1, 1, 0.05)
                activeHL:SetBlendMode("ADD")
                activeHL:Hide()
                tab._activeHL = activeHL
            end

            -- Hide Blizzard's label and use our own
            local blizLabel = tab:GetFontString()
            local labelText = blizLabel and blizLabel:GetText() or ("Tab " .. i)
            if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end
            tab:SetPushedTextOffset(0, 0)

            if not tab._label then
                local label = tab:CreateFontString(nil, "OVERLAY")
                label:SetFont(fontPath, 9, "")
                label:SetPoint("CENTER", tab, "CENTER", 0, 0)
                label:SetJustifyH("CENTER")
                label:SetText(labelText)
                tab._label = label
                -- Sync our label when Blizzard updates the text
                hooksecurefunc(tab, "SetText", function(_, newText)
                    if newText and label then label:SetText(newText) end
                end)
            end

            -- Accent underline (pixel-perfect)
            if not tab._underline then
                local underline = tab:CreateTexture(nil, "OVERLAY", nil, 6)
                if EllesmereUI and EllesmereUI.PanelPP and EllesmereUI.PanelPP.DisablePixelSnap then
                    EllesmereUI.PanelPP.DisablePixelSnap(underline)
                    underline:SetHeight(EllesmereUI.PanelPP.mult or 1)
                else
                    underline:SetHeight(1)
                end
                underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
                underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
                underline:SetColorTexture(EG.r or 0.51, EG.g or 0.784, EG.b or 1, 1)
                if EllesmereUI and EllesmereUI.RegAccent then
                    EllesmereUI.RegAccent({ type = "solid", obj = underline, a = 1 })
                end
                underline:Hide()
                tab._underline = underline
            end
        end
    end

    -- Hook to update tab visuals when selection changes
    local function UpdateTabVisuals()
        for i = 1, 3 do
            local tab = _G["CharacterFrameTab" .. i]
            if tab then
                -- PanelTemplates_GetSelectedTab doesn't work reliably, use frame's attribute
                local isActive = (frame.selectedTab or 1) == i
                if tab._label then
                    tab._label:SetTextColor(1, 1, 1, isActive and 1 or 0.5)
                end
                if tab._underline then
                    tab._underline:SetShown(isActive)
                end
                if tab._activeHL then
                    tab._activeHL:SetShown(isActive)
                end
            end
        end
    end

    -- Helper function to safely show frames (deferred in combat)
    local function SafeShow(element)
        if InCombatLockdown() then
            -- Defer until out of combat
            local deferredShow = CreateFrame("Frame")
            deferredShow:RegisterEvent("PLAYER_REGEN_ENABLED")
            deferredShow:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if element then element:Show() end
                self:Hide()
            end)
        else
            if element then element:Show() end
        end
    end

    -- Hook Blizzard's tab selection to update our visuals and show/hide slots
    hooksecurefunc("PanelTemplates_SetTab", function(panel)
        if panel == frame then
            UpdateTabVisuals()

            -- Show slots only on tab 1 (Character tab)
            local isCharacterTab = (frame.selectedTab or 1) == 1
            if frame._themedSlots then
                for _, slotName in ipairs(frame._themedSlots) do
                    local slot = _G[slotName]
                    if slot then
                        if isCharacterTab then
                            if InCombatLockdown() then
                                SafeShow(slot)
                            else
                                slot:Show()
                            end
                            if slot._itemLevelLabel then slot._itemLevelLabel:Show() end
                            if slot._enchantLabel then slot._enchantLabel:Show() end
                            if slot._upgradeTrackLabel then slot._upgradeTrackLabel:Show() end
                        else
                            slot:Hide()
                            if slot._itemLevelLabel then slot._itemLevelLabel:Hide() end
                            if slot._enchantLabel then slot._enchantLabel:Hide() end
                            if slot._upgradeTrackLabel then slot._upgradeTrackLabel:Hide() end
                        end
                    end
                end
            end

            -- Show/hide custom buttons based on tab (deferred in combat)
            for _, btnName in ipairs({"EUI_CharSheet_Stats", "EUI_CharSheet_Titles", "EUI_CharSheet_Equipment"}) do
                local btn = _G[btnName]
                if btn then
                    if isCharacterTab then
                        SafeShow(btn)
                    else
                        btn:Hide()
                    end
                end
            end

            -- Show/hide stats panel and titles panel based on tab (deferred in combat)
            if frame._statsPanel then
                if isCharacterTab then
                    SafeShow(frame._statsPanel)
                else
                    frame._statsPanel:Hide()
                end
            end

            -- Hide average itemlevel text when not on character tab
            if frame._iLvlText then
                if isCharacterTab then
                    frame._iLvlText:Show()
                else
                    frame._iLvlText:Hide()
                end
            end

            -- Hide/show all stat sections based on tab
            if frame._statsSections then
                for _, sectionData in ipairs(frame._statsSections) do
                    if sectionData.container then
                        if isCharacterTab then
                            sectionData.container:Show()
                        else
                            sectionData.container:Hide()
                        end
                    end
                end
            end

            -- Hide/show stat panel background, scrollFrame and scrollBar
            if frame._statsBg then
                if isCharacterTab then
                    frame._statsBg:Show()
                else
                    frame._statsBg:Hide()
                end
            end

            if frame._scrollFrame then
                if isCharacterTab then
                    frame._scrollFrame:Show()
                else
                    frame._scrollFrame:Hide()
                end
            end

            if frame._scrollBar then
                if isCharacterTab then
                    frame._scrollBar:Show()
                else
                    frame._scrollBar:Hide()
                end
            end

            if frame._titlesPanel then
                if not isCharacterTab then
                    frame._titlesPanel:Hide()
                end
            end

            if frame._equipPanel then
                if not isCharacterTab then
                    frame._equipPanel:Hide()
                end
            end

            if frame._socketContainer then
                if not isCharacterTab then
                    frame._socketContainer:Hide()
                else
                    frame._socketContainer:Show()
                end
            end
        end
    end)
    UpdateTabVisuals()

    -- Create custom stats panel with scroll
    local statsPanel = CreateFrame("Frame", "EUI_CharSheet_StatsPanel", frame)
    statsPanel:SetSize(220 + 360, 340)  -- Also expand with frame
    statsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 452, -90)
    statsPanel:SetFrameLevel(50)

    -- Hook to prevent size reset
    hooksecurefunc(statsPanel, "SetSize", function(self, w, h)
        if w ~= (220 + 360) then
            self:SetSize(220 + 360, 340)
        end
    end)

    hooksecurefunc(statsPanel, "SetWidth", function(self, w)
        if w ~= (220 + 360) then
            self:SetWidth(220 + 360)
        end
    end)

    -- Stats panel background (fixed width, not scaled)
    local statsBg = statsPanel:CreateTexture(nil, "BACKGROUND")
    statsBg:SetColorTexture(0.03, 0.045, 0.05, 0.95)
    statsBg:SetSize(220, 340)  -- Fixed size, doesn't expand
    statsBg:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 0, 0)
    frame._statsBg = statsBg  -- Store on frame for tab visibility control

    -- Map INVTYPE to inventory slot numbers and display names
    local INVTYPE_TO_SLOT = {
        INVTYPE_HEAD = {slot = 1, name = "Head"},
        INVTYPE_NECK = {slot = 2, name = "Neck"},
        INVTYPE_SHOULDER = {slot = 3, name = "Shoulder"},
        INVTYPE_CHEST = {slot = 5, name = "Chest"},
        INVTYPE_WAIST = {slot = 6, name = "Waist"},
        INVTYPE_LEGS = {slot = 7, name = "Legs"},
        INVTYPE_FEET = {slot = 8, name = "Feet"},
        INVTYPE_WRIST = {slot = 9, name = "Wrist"},
        INVTYPE_HAND = {slot = 10, name = "Hands"},
        INVTYPE_FINGER = {slots = {11, 12}, name = "Ring"},
        INVTYPE_TRINKET = {slots = {13, 14}, name = "Trinket"},
        INVTYPE_BACK = {slot = 15, name = "Back"},
        INVTYPE_MAINHAND = {slot = 16, name = "Main Hand"},
        INVTYPE_OFFHAND = {slot = 17, name = "Off Hand"},
        INVTYPE_RELIC = {slot = 18, name = "Relic"},
        INVTYPE_BODY = {slot = 4, name = "Body"},
        INVTYPE_SHIELD = {slot = 17, name = "Shield"},
        INVTYPE_2HWEAPON = {slot = 16, name = "Two-Hand"},
    }

    -- Function to get itemlevel of equipped item in a specific slot
    local function GetEquippedItemLevel(slot)
        local itemLink = GetInventoryItemLink("player", slot)
        if itemLink then
            local _, _, _, itemLevel = GetItemInfo(itemLink)
            return tonumber(itemLevel) or 0
        end
        return 0
    end

    -- Function to get better items from inventory (equipment only)
    local function GetBetterInventoryItems()
        local betterItems = {}

        -- Check all bag slots (0 = backpack, 1-4 = bag slots)
        for bagSlot = 0, 4 do
            local bagSize = C_Container.GetContainerNumSlots(bagSlot)
            for slotIndex = 1, bagSize do
                local itemLink = C_Container.GetContainerItemLink(bagSlot, slotIndex)
                if itemLink then
                    local itemName, _, itemRarity, itemLevel, _, itemType, _, _, equipSlot, itemIcon = GetItemInfo(itemLink)
                    itemLevel = tonumber(itemLevel)

                    -- Only show Weapon and Armor items
                    if itemLevel and itemName and (itemType == "Weapon" or itemType == "Armor") and equipSlot then
                        -- Get the slot(s) this item can equip to
                        local slotInfo = INVTYPE_TO_SLOT[equipSlot]
                        if slotInfo then
                            local isBetter = false
                            local compareSlots = slotInfo.slots or {slotInfo.slot}

                            -- Check if item is better than ANY of its possible slots
                            for _, slot in ipairs(compareSlots) do
                                local equippedLevel = GetEquippedItemLevel(slot)
                                if itemLevel > equippedLevel then
                                    isBetter = true
                                    break
                                end
                            end

                            if isBetter then
                                table.insert(betterItems, {
                                    name = itemName,
                                    level = itemLevel,
                                    rarity = itemRarity or 1,
                                    icon = itemIcon,
                                    slot = slotInfo.name
                                })
                            end
                        end
                    end
                end
            end
        end

        -- Sort by level descending
        table.sort(betterItems, function(a, b) return a.level > b.level end)

        return betterItems
    end

    -- Mythic+ Rating display (anchor above itemlevel)
    local mythicRatingLabel = statsPanel:CreateFontString(nil, "OVERLAY")
    mythicRatingLabel:SetFont(fontPath, 11, "")
    mythicRatingLabel:SetPoint("TOP", statsBg, "TOP", 0, 80)
    mythicRatingLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    mythicRatingLabel:SetText("Mythic+ Rating:")
    frame._mythicRatingLabel = mythicRatingLabel

    local mythicRatingValue = statsPanel:CreateFontString(nil, "OVERLAY")
    mythicRatingValue:SetFont(fontPath, 13, "")
    mythicRatingValue:SetPoint("TOP", mythicRatingLabel, "BOTTOM", 0, -2)
    frame._mythicRatingValue = mythicRatingValue

    -- Itemlevel display (anchor to center of statsBg background)
    local iLvlText = statsPanel:CreateFontString(nil, "OVERLAY")
    iLvlText:SetFont(fontPath, 18, "")
    iLvlText:SetPoint("TOP", statsBg, "TOP", 0, 50)
    iLvlText:SetTextColor(0.6, 0.2, 1, 1)
    frame._iLvlText = iLvlText  -- Store on frame for tab visibility control

    -- Button overlay for itemlevel tooltip
    local iLvlButton = CreateFrame("Button", nil, statsPanel)
    iLvlButton:SetPoint("TOP", statsBg, "TOP", 0, 60)
    iLvlButton:SetSize(100, 30)
    iLvlButton:EnableMouse(true)
    iLvlButton:SetScript("OnEnter", function(self)
        local betterItems = GetBetterInventoryItems()

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Equipped Item Level", 0.6, 0.2, 1, 1)

        if #betterItems > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(
                string.format("You have %d better item%s in inventory", #betterItems, #betterItems == 1 and "" or "s"),
                0.2, 1, 0.2
            )
            GameTooltip:AddLine(" ")

            -- Show up to 10 items with icons and slots (slot on right side)
            local maxShow = math.min(#betterItems, 10)
            for i = 1, maxShow do
                local item = betterItems[i]
                local leftText = string.format("|T%s:16|t  %s (iLvl %d)", item.icon, item.name, item.level)
                GameTooltip:AddDoubleLine(leftText, item.slot, 1, 1, 1, 0.7, 0.7, 0.7)
            end

            if #betterItems > 10 then
                GameTooltip:AddLine(
                    string.format("  ... and %d more", #betterItems - 10),
                    0.7, 0.7, 0.7
                )
            end
        else
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("No better items in inventory", 0.7, 0.7, 0.7, true)
        end

        -- Calculate minimum width based on longest item text
        local maxWidth = 250
        if #betterItems > 0 then
            local maxShow = math.min(#betterItems, 10)
            for i = 1, maxShow do
                local item = betterItems[i]
                local text = string.format("%s (iLvl %d) - %s", item.name, item.level, item.slot)
                -- Rough estimate: ~6 pixels per character + icon space
                local estimatedWidth = #text * 6 + 30
                if estimatedWidth > maxWidth then
                    maxWidth = estimatedWidth
                end
            end
        end
        GameTooltip:SetMinimumWidth(maxWidth)
        GameTooltip:Show()
    end)
    iLvlButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Function to update itemlevel and mythic+ rating
    local function UpdateItemLevelDisplay()
        local avgItemLevel, avgItemLevelEquipped = GetAverageItemLevel()

        -- Format with two decimals
        local avgFormatted = format("%.2f", avgItemLevel)
        local avgEquippedFormatted = format("%.2f", avgItemLevelEquipped)

        -- Display format: equipped / average
        iLvlText:SetText(format("%s / %s", avgEquippedFormatted, avgFormatted))

        -- Update Mythic+ Rating if option is enabled
        if EllesmereUIDB and EllesmereUIDB.showMythicRating and frame._mythicRatingValue then
            local mythicRating = C_ChallengeMode.GetOverallDungeonScore()
            if mythicRating and mythicRating > 0 then
                -- Color brackets based on rating
                local r, g, b = 0.7, 0.7, 0.7  -- Gray default

                if mythicRating >= 2500 then
                    r, g, b = 1.0, 0.64, 0.0  -- Orange/Gold
                elseif mythicRating >= 2000 then
                    r, g, b = 0.64, 0.21, 1.0  -- Purple
                elseif mythicRating >= 1500 then
                    r, g, b = 0.0, 0.44, 0.87  -- Blue
                elseif mythicRating >= 1000 then
                    r, g, b = 0.12, 1.0, 0.0  -- Green
                end

                frame._mythicRatingValue:SetText(tostring(math.floor(mythicRating)))
                frame._mythicRatingValue:SetTextColor(r, g, b, 1)
                frame._mythicRatingLabel:Show()
                frame._mythicRatingValue:Show()

                -- Adjust itemlevel display when mythic+ rating is shown
                iLvlText:SetFont(fontPath, 18, "")
                iLvlText:SetPoint("TOP", statsBg, "TOP", 0, 50)
            else
                frame._mythicRatingLabel:Hide()
                frame._mythicRatingValue:Hide()

                -- Restore itemlevel display when mythic+ rating is not available
                iLvlText:SetFont(fontPath, 20, "")
                iLvlText:SetPoint("TOP", statsBg, "TOP", 0, 60)
            end
        elseif frame._mythicRatingValue then
            frame._mythicRatingLabel:Hide()
            frame._mythicRatingValue:Hide()

            -- Restore itemlevel display when mythic+ rating is disabled
            iLvlText:SetFont(fontPath, 20, "")
            iLvlText:SetPoint("TOP", statsBg, "TOP", 0, 60)
        end
    end

    -- Create update frame for itemlevel and spec changes
    local iLvlUpdateFrame = CreateFrame("Frame")
    iLvlUpdateFrame:SetScript("OnUpdate", function()
        UpdateItemLevelDisplay()
        -- RefreshAttributeStats will be called later after it's defined
    end)

    UpdateItemLevelDisplay()

    -- Store callback for option changes
    EllesmereUI._updateMythicRatingDisplay = function()
        UpdateItemLevelDisplay()
    end

    --[[ Stats panel border
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(statsPanel, 0.15, 0.15, 0.15, 1, 1, "OVERLAY", 1)
    end
    ]]--

    -- Create scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "EUI_CharSheet_ScrollFrame", statsPanel)
    scrollFrame:SetSize(260, 320)
    scrollFrame:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 5, -10)
    scrollFrame:SetFrameLevel(51)
    frame._scrollFrame = scrollFrame  -- Store on frame for tab visibility control

    -- Create scroll child
    local scrollChild = CreateFrame("Frame", "EUI_CharSheet_ScrollChild", scrollFrame)
    scrollChild:SetWidth(200)
    scrollFrame:SetScrollChild(scrollChild)

    -- Create scrollbar (without template to avoid unwanted textures)
    local scrollBar = CreateFrame("Slider", "EUI_CharSheet_ScrollBar", statsPanel)
    scrollBar:SetSize(8, 320)
    scrollBar:SetPoint("TOPRIGHT", statsPanel, "TOPRIGHT", -5, -10)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValue(0)
    scrollBar:SetOrientation("VERTICAL")
    frame._scrollBar = scrollBar  -- Store on frame for tab visibility control

    -- Scrollbar background (disabled - causes visual glitches)
    -- local scrollBarBg = scrollBar:CreateTexture(nil, "BACKGROUND")
    -- scrollBarBg:SetAllPoints()
    -- scrollBarBg:SetTexture("Interface/Tooltips/UI-Tooltip-Background")
    -- scrollBarBg:SetVertexColor(0.1, 0.1, 0.1, 0.5)

    -- Scrollbar thumb
    local scrollBarThumb = scrollBar:GetThumbTexture()
    if scrollBarThumb then
        scrollBarThumb:SetTexture("Interface/Buttons/UI-SliderBar-Button-Horizontal")
        scrollBarThumb:SetSize(8, 20)
    end

    -- Scroll handler
    scrollBar:SetScript("OnValueChanged", function(self, value)
        scrollFrame:SetVerticalScroll(value)
    end)

    -- Update scrollbar visibility
    scrollChild:SetScript("OnSizeChanged", function()
        local scrollHeight = scrollChild:GetHeight()
        local viewHeight = scrollFrame:GetHeight()
        if scrollHeight > viewHeight then
            scrollBar:SetMinMaxValues(0, scrollHeight - viewHeight)
            scrollBar:Show()
        else
            scrollBar:SetValue(0)
            scrollBar:Hide()
        end
    end)

    -- Enable mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local minVal, maxVal = scrollBar:GetMinMaxValues()
        local newVal = scrollBar:GetValue() - (delta * 20)
        newVal = math.max(minVal, math.min(maxVal, newVal))
        scrollBar:SetValue(newVal)
    end)

    -- Helper function to get crest values
    local function GetCrestValue(currencyID)
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
            if info then
                return info.quantity or 0
            end
        end
        return 0
    end

    -- Crest maximum values (per season)
    local crestMaxValues = {
        [3347] = 400,  -- Myth
        [3345] = 400,  -- Hero
        [3343] = 700,  -- Champion
        [3341] = 700,  -- Veteran
        [3383] = 700,  -- Adventurer
    }

    -- Helper function to get crest maximum value (now using API to get seasonal max)
    local function GetCrestMaxValue(currencyID)
        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if currencyInfo and currencyInfo.maxQuantity then
            return currencyInfo.maxQuantity
        end
        return crestMaxValues[currencyID] or 3000  -- Fallback to hardcoded values if API fails
    end

    -- Check if a stat should be shown based on class/spec conditions
    local function ShouldShowStat(statShowWhen)
        if not statShowWhen then return true end  -- Show by default if no condition

        if statShowWhen == "brewmaster" then
            local specIndex = GetSpecialization()
            if specIndex then
                local specId = (GetSpecializationInfo(specIndex))
                return specId == 268  -- Brewmaster Monk
            end
            return false
        end

        return true
    end

    -- Determine which stats to show based on class/spec
    local function GetFilteredAttributeStats()
        local spec = GetSpecialization()
        local primaryStatIndex = 4  -- default Intellect

        if spec then
            -- Get primary stat directly from spec info (6th return value)
            local _, _, _, _, _, primaryStat = GetSpecializationInfo(spec)
            primaryStatIndex = primaryStat or 4
        end

        local primaryStatNames = { "Strength", "Agility", "Stamina", "Intellect" }
        local primaryStat = primaryStatNames[primaryStatIndex]

        -- Return fixed order: Primary Stat, Stamina, Health
        return {
            { name = primaryStat, func = function() return UnitStat("player", primaryStatIndex) end, statIndex = primaryStatIndex, tooltip = (primaryStatIndex == 1 and "Increases melee attack power") or (primaryStatIndex == 2 and "Increases dodge chance and melee attack power") or (primaryStatIndex == 4 and "Increase the magnitude of your attacks and Abilities") or "Primary stat" },
            { name = "Stamina", func = function() return UnitStat("player", 3) end, statIndex = 3, tooltip = "Increases health" },
            { name = "Health", func = function() return UnitHealthMax("player") end, tooltip = "The amount of damage you can take" },
        }
    end

    -- Default category colors
    local DEFAULT_CATEGORY_COLORS = {
        Attributes = { r = 0.047, g = 0.824, b = 0.616 },
        ["Secondary Stats"] = { r = 0.471, g = 0.255, b = 0.784 },
        Attack = { r = 1, g = 0.353, b = 0.122 },
        Defense = { r = 0.247, g = 0.655, b = 1 },
        Crests = { r = 1, g = 0.784, b = 0.341 },
    }

    -- Get category color, applying customization if available
    local function GetCategoryColor(title)
        local custom = EllesmereUIDB and EllesmereUIDB.statCategoryColors and EllesmereUIDB.statCategoryColors[title]
        if custom then return custom end
        return DEFAULT_CATEGORY_COLORS[title] or { r = 1, g = 1, b = 1 }
    end

    -- Load stat sections order from saved data or use defaults
    local function GetStatSectionsOrder()
        local defaultOrder = {
            {
                title = "Attributes",
                color = GetCategoryColor("Attributes"),
                stats = GetFilteredAttributeStats()
            },
            {
                title = "Secondary Stats",
                color = GetCategoryColor("Secondary Stats"),
                stats = {
                    { name = "Crit", func = function() return GetCritChance("player") or 0 end, format = "%.2f%%", rawFunc = function() return GetCombatRating(CR_CRIT_MELEE) or 0 end },
                    { name = "Haste", func = function() return UnitSpellHaste("player") or 0 end, format = "%.2f%%", rawFunc = function() return GetCombatRating(CR_HASTE_MELEE) or 0 end },
                    { name = "Mastery", func = function() return GetMasteryEffect() or 0 end, format = "%.2f%%", rawFunc = function() return GetCombatRating(CR_MASTERY) or 0 end },
                    { name = "Versatility", func = function() return GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) or 0 end, format = "%.2f%%", rawFunc = function() return GetCombatRating(CR_VERSATILITY_DAMAGE_DONE) or 0 end },
                }
            },
            {
                title = "Attack",
                color = GetCategoryColor("Attack"),
                stats = {
                    { name = "Spell Power", func = function() return GetSpellBonusDamage(7) end, tooltip = "Increases the power of your spells and abilities" },
                    { name = "Attack Speed", func = function() return UnitAttackSpeed("player") or 0 end, format = "%.2f", tooltip = "Attacks per second" },
                }
            },
            {
                title = "Defense",
                color = GetCategoryColor("Defense"),
                stats = {
                    { name = "Armor", func = function() local base, effectiveArmor = UnitArmor("player") return effectiveArmor end, tooltip = "Reduces physical damage taken" },
                    { name = "Dodge", func = function() return GetDodgeChance() or 0 end, format = "%.2f%%", tooltip = "Chance to avoid melee attacks" },
                    { name = "Parry", func = function() return GetParryChance() or 0 end, format = "%.2f%%", tooltip = "Chance to block melee attacks" },
                    { name = "Stagger Effect", func = function() return C_PaperDollInfo.GetStaggerPercentage("player") or 0 end, format = "%.2f%%", showWhen = "brewmaster", tooltip = "Converts damage into a delayed effect" },
                }
            },
            {
                title = "Crests",
                color = GetCategoryColor("Crests"),
                stats = {
                    { name = "Myth", func = function() return GetCrestValue(3347) end, format = "%d", currencyID = 3347 },
                    { name = "Hero", func = function() return GetCrestValue(3345) end, format = "%d", currencyID = 3345 },
                    { name = "Champion", func = function() return GetCrestValue(3343) end, format = "%d", currencyID = 3343 },
                    { name = "Veteran", func = function() return GetCrestValue(3341) end, format = "%d", currencyID = 3341 },
                    { name = "Adventurer", func = function() return GetCrestValue(3383) end, format = "%d", currencyID = 3383 },
                }
            }
        }

        -- Apply saved order if exists
        if EllesmereUIDB and EllesmereUIDB.statSectionsOrder then
            local orderedSections = {}
            for _, title in ipairs(EllesmereUIDB.statSectionsOrder) do
                for _, section in ipairs(defaultOrder) do
                    if section.title == title then
                        table.insert(orderedSections, section)
                        break
                    end
                end
            end
            return #orderedSections == #defaultOrder and orderedSections or defaultOrder
        end
        return defaultOrder
    end

    local statSections = GetStatSectionsOrder()

    frame._statsPanel = statsPanel
    frame._statsValues = {}  -- Will be filled as sections are created
    frame._statsSections = {}  -- Store sections for collapse/expand
    frame._lastSpec = GetSpecialization()  -- Track current spec

    -- Function to refresh attributes stats if spec changed
    local function RefreshAttributeStats()
        local currentSpec = GetSpecialization()
        if currentSpec == frame._lastSpec then return end

        frame._lastSpec = currentSpec

        -- Find and update Attributes section
        for sectionIdx, sectionData in ipairs(frame._statsSections) do
            if sectionData.sectionTitle == "Attributes" then
                -- Get new stats for current spec
                local newStats = GetFilteredAttributeStats()

                -- Update existing stat elements with new names and functions
                local labelIndex = 0
                for _, stat in ipairs(sectionData.stats) do
                    if stat.label then
                        labelIndex = labelIndex + 1

                        if newStats[labelIndex] then
                            -- Update label text
                            stat.label:SetText(newStats[labelIndex].name)
                            stat.label:Show()

                            if stat.value then
                                -- Find and update the corresponding entry in frame._statsValues
                                for _, statsValueEntry in ipairs(frame._statsValues) do
                                    if statsValueEntry.value == stat.value then
                                        -- Update the function
                                        statsValueEntry.func = newStats[labelIndex].func
                                        statsValueEntry.format = newStats[labelIndex].format or "%d"
                                        -- Update display immediately
                                        local newValue = newStats[labelIndex].func()
                                        if newValue ~= nil then
                                            local fmt = statsValueEntry.format
                                            if fmt:find("%%") then
                                                stat.value:SetText(format(fmt, newValue))
                                            else
                                                stat.value:SetText(format(fmt, newValue))
                                            end
                                        end
                                        break
                                    end
                                end
                                stat.value:Show()
                            end
                        else
                            -- Hide stats that aren't in newStats
                            stat.label:Hide()
                            if stat.value then stat.value:Hide() end
                        end
                    elseif stat.divider then
                        -- Show dividers only between visible stats
                        stat.divider:SetShown(labelIndex < #newStats)
                    end
                end

                frame._recalculateSections()
                break
            end
        end
    end

    -- Function to refresh visibility based on showWhen conditions
    local function RefreshStatsVisibility()
        local currentSpec = GetSpecialization()

        for _, sectionData in ipairs(frame._statsSections) do
            for _, stat in ipairs(sectionData.stats) do
                if stat.label and stat.showWhen then
                    local shouldShow = ShouldShowStat(stat.showWhen)
                    if stat.label then stat.label:SetShown(shouldShow) end
                    if stat.value then stat.value:SetShown(shouldShow) end
                end
            end
        end
    end

    -- Create update frame to monitor spec changes
    local specUpdateFrame = CreateFrame("Frame")
    specUpdateFrame:SetScript("OnUpdate", function()
        RefreshAttributeStats()  -- Update Primary Stat
        RefreshStatsVisibility()  -- Update showWhen visibility
    end)

    -- Function to update visibility of stat categories
    local function UpdateStatCategoryVisibility()
        if not frame._statsSections or #frame._statsSections == 0 then return end

        for _, sectionData in ipairs(frame._statsSections) do
            local categoryTitle = sectionData.sectionTitle
            local settingKey = "showStatCategory_" .. categoryTitle:gsub(" ", "")
            local shouldShow = not (EllesmereUIDB and EllesmereUIDB[settingKey] == false)

            if shouldShow then
                sectionData.container:Show()
            else
                sectionData.container:Hide()
            end
        end
        frame._recalculateSections()
    end
    EllesmereUI._updateStatCategoryVisibility = UpdateStatCategoryVisibility

    -- Function to recalculate all section positions
    local function RecalculateSectionPositions()
        local yOffset = 0
        for _, sectionData in ipairs(frame._statsSections) do
            -- Skip hidden categories
            if sectionData.container:IsShown() then
                local sectionHeight = sectionData.isCollapsed and 16 or sectionData.height
                sectionData.container:ClearAllPoints()
                sectionData.container:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
                sectionData.container:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, yOffset)
                sectionData.container:SetHeight(sectionHeight)
                yOffset = yOffset - sectionHeight - 16
            end
        end
        scrollChild:SetHeight(-yOffset)
    end
    frame._recalculateSections = RecalculateSectionPositions

    -- Create sections in scroll child
    local yOffset = 0
    for sectionIdx, section in ipairs(statSections) do
        -- Section container
        local sectionContainer = CreateFrame("Frame", nil, scrollChild)
        sectionContainer:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        sectionContainer:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, yOffset)
        sectionContainer:SetWidth(260)

        -- Container for title and bars (clickable)
        local titleContainer = CreateFrame("Button", nil, sectionContainer)
        titleContainer:SetPoint("TOP", sectionContainer, "TOPLEFT", 100, 0)
        titleContainer:SetSize(200, 16)
        titleContainer:RegisterForClicks("LeftButtonUp")

        -- Section title (centered in container)
        local sectionTitle = titleContainer:CreateFontString(nil, "OVERLAY")
        sectionTitle:SetFont(fontPath, 13, "")
        sectionTitle:SetTextColor(section.color.r, section.color.g, section.color.b, 1)
        sectionTitle:SetPoint("CENTER", titleContainer, "CENTER", 0, 0)
        sectionTitle:SetText(section.title)

        -- Left bar (from left edge of container to text)
        local leftBar = titleContainer:CreateTexture(nil, "ARTWORK")
        leftBar:SetColorTexture(section.color.r, section.color.g, section.color.b, 0.8)
        leftBar:SetPoint("LEFT", titleContainer, "LEFT", 0, 0)
        leftBar:SetPoint("RIGHT", sectionTitle, "LEFT", -8, 0)
        leftBar:SetHeight(2)

        -- Right bar (from text to right edge of container)
        local rightBar = titleContainer:CreateTexture(nil, "ARTWORK")
        rightBar:SetColorTexture(section.color.r, section.color.g, section.color.b, 0.8)
        rightBar:SetPoint("LEFT", sectionTitle, "RIGHT", 8, 0)
        rightBar:SetPoint("RIGHT", titleContainer, "RIGHT", 0, 0)
        rightBar:SetHeight(2)

        local statYOffset = -22

        -- Store section data for collapse/expand
        local sectionData = {
            title = titleContainer,
            container = sectionContainer,
            stats = {},
            isCollapsed = false,
            height = 0,
            sectionTitle = section.title,  -- Store title for reordering
            titleFS = sectionTitle,  -- Store title fontstring for color updates
            leftBar = leftBar,  -- Store left bar for color updates
            rightBar = rightBar  -- Store right bar for color updates
        }
        table.insert(frame._statsSections, sectionData)

        -- Stats in section
        for statIdx, stat in ipairs(section.stats) do
            -- Skip stats that don't meet the show conditions
            if ShouldShowStat(stat.showWhen) then
                -- Stat label
                local label = sectionContainer:CreateFontString(nil, "OVERLAY")
                label:SetFont(fontPath, 12, "")
                label:SetTextColor(0.7, 0.7, 0.7, 0.8)
                label:SetPoint("TOPLEFT", sectionContainer, "TOPLEFT", 15, statYOffset)
                label:SetText(stat.name)

                -- Stat value
                local value = sectionContainer:CreateFontString(nil, "OVERLAY")
                value:SetFont(fontPath, 12, "")
                value:SetTextColor(section.color.r, section.color.g, section.color.b, 1)
                value:SetPoint("TOPRIGHT", sectionContainer, "TOPRIGHT", -2, statYOffset)
                value:SetJustifyH("RIGHT")
                value:SetText("0")

                -- Create button overlay for all stats with tooltips
                local valueButton = CreateFrame("Button", nil, sectionContainer)
                valueButton:SetPoint("TOPRIGHT", sectionContainer, "TOPRIGHT", -2, statYOffset)
                valueButton:SetSize(90, 16)
                valueButton:EnableMouse(true)

                valueButton:SetScript("OnEnter", function()
                    local statValue = stat.func()
                    GameTooltip:SetOwner(valueButton, "ANCHOR_RIGHT")

                    -- Format value according to stat's format string
                    local displayValue = statValue
                    if stat.format then
                        displayValue = string.format(stat.format, statValue)
                    else
                        displayValue = tostring(statValue)
                    end

                    -- Build title line based on stat type
                    local titleLine = stat.name .. " " .. displayValue

                    -- Currency (Crests)
                    if stat.currencyID then
                        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(stat.currencyID)
                        if currencyInfo then
                            local earned = currencyInfo.totalEarned or 0
                            local maximum = currencyInfo.maxQuantity or 0
                            GameTooltip:AddLine(stat.name .. " Crests", section.color.r, section.color.g, section.color.b, 1)
                            GameTooltip:AddLine(string.format("%d / %d", earned, maximum), 1, 1, 1, true)
                        end
                    -- Secondary stats with raw rating
                    elseif stat.rawFunc then
                        local percentValue = stat.func()
                        local rawValue = stat.rawFunc()
                        GameTooltip:AddLine(
                            string.format("%s %.2f%% (%d rating)", stat.name, percentValue, rawValue),
                            section.color.r, section.color.g, section.color.b, 1  -- Use category color
                        )
                        -- Description for secondary stats
                        local description = ""
                        if stat.name == "Crit" then
                            description = string.format("Increases your chance to critically hit by %.2f%%.", percentValue)
                        elseif stat.name == "Haste" then
                            description = string.format("Increases attack and casting speed by %.2f%%.", percentValue)
                        elseif stat.name == "Mastery" then
                            description = string.format("Increases the effectiveness of your Mastery by %.2f%%.", percentValue)
                        elseif stat.name == "Versatility" then
                            description = string.format("Increases damage and healing done by %.2f%% and reduces damage taken by %.2f%%.", percentValue, percentValue / 2)
                        end
                        GameTooltip:AddLine(description, 1, 1, 1, true)
                    -- Attributes
                    elseif stat.statIndex then
                        local base, _, posBuff, negBuff = UnitStat("player", stat.statIndex)
                        local statLabel = stat.name

                        -- Map to Blizzard global names
                        if stat.name == "Strength" then
                            statLabel = STAT_STRENGTH or "Strength"
                        elseif stat.name == "Agility" then
                            statLabel = STAT_AGILITY or "Agility"
                        elseif stat.name == "Intellect" then
                            statLabel = STAT_INTELLECT or "Intellect"
                        elseif stat.name == "Stamina" then
                            statLabel = STAT_STAMINA or "Stamina"
                        end

                        local bonus = (posBuff or 0) + (negBuff or 0)
                        local statLine = statLabel .. " " .. statValue
                        if bonus ~= 0 then
                            statLine = statLine .. " (" .. base .. (bonus > 0 and "+" or "") .. bonus .. ")"
                        end
                        GameTooltip:AddLine(statLine, section.color.r, section.color.g, section.color.b, 1)
                        GameTooltip:AddLine(stat.tooltip, 1, 1, 1, true)
                    -- Generic stats (Attack, Defense, etc.)
                    else
                        GameTooltip:AddLine(titleLine, section.color.r, section.color.g, section.color.b, 1)
                        if stat.tooltip then
                            GameTooltip:AddLine(stat.tooltip, 1, 1, 1, true)
                        end
                    end

                    GameTooltip:Show()
                end)

                valueButton:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)

                -- Store for updates
                table.insert(frame._statsValues, {
                    value = value,
                    func = stat.func,
                    rawFunc = stat.rawFunc,
                    format = stat.format or "%d"
                })

                -- Store stat elements for collapse/expand (include showWhen for visibility checks)
                table.insert(sectionData.stats, {label = label, value = value, button = valueButton, showWhen = stat.showWhen})

                -- Divider line between stats
                if statIdx < #section.stats then
                    local divider = sectionContainer:CreateTexture(nil, "OVERLAY")
                    divider:SetColorTexture(0.1, 0.1, 0.1, 0.4)
                    divider:SetPoint("TOPLEFT", sectionContainer, "TOPLEFT", 10, statYOffset - 8)
                    divider:SetPoint("TOPRIGHT", sectionContainer, "TOPRIGHT", -10, statYOffset - 8)
                    divider:SetHeight(1)
                    table.insert(sectionData.stats, {divider = divider})
                end

                statYOffset = statYOffset - 16
            end
        end

        sectionData.height = -statYOffset

        -- Click handler for collapse/expand
        titleContainer:SetScript("OnClick", function()
            sectionData.isCollapsed = not sectionData.isCollapsed
            for _, stat in ipairs(sectionData.stats) do
                if sectionData.isCollapsed then
                    if stat.label then stat.label:Hide() end
                    if stat.value then stat.value:Hide() end
                    if stat.button then stat.button:Hide() end
                    if stat.divider then stat.divider:Hide() end
                else
                    if stat.label then stat.label:Show() end
                    if stat.value then stat.value:Show() end
                    if stat.button then stat.button:Show() end
                    if stat.divider then stat.divider:Show() end
                end
            end

            frame._recalculateSections()
        end)

        -- Up/Down arrow buttons (shown on hover)
        do
            local arrowSize = 10
            local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"

            -- Up arrow button
            local upBtn = CreateFrame("Button", nil, titleContainer)
            upBtn:SetSize(arrowSize, arrowSize)
            upBtn:SetPoint("RIGHT", titleContainer, "RIGHT", 32, 0)
            upBtn:SetAlpha(0)  -- Hidden by default
            local upIcon = upBtn:CreateTexture(nil, "OVERLAY")
            upIcon:SetAllPoints()
            upIcon:SetTexture(MEDIA .. "icons\\eui-arrow-up3.png")
            upBtn:SetScript("OnClick", function()
                -- Find current index in _statsSections
                local currentIdx = nil
                for i, sec in ipairs(frame._statsSections) do
                    if sec == sectionData then
                        currentIdx = i
                        break
                    end
                end

                if currentIdx and currentIdx > 1 then
                    -- Swap with previous section
                    frame._statsSections[currentIdx], frame._statsSections[currentIdx - 1] = frame._statsSections[currentIdx - 1], frame._statsSections[currentIdx]

                    -- Save new order
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.statSectionsOrder = {}
                    for _, sec in ipairs(frame._statsSections) do
                        table.insert(EllesmereUIDB.statSectionsOrder, sec.sectionTitle)
                    end

                    frame._recalculateSections()
                end
            end)

            -- Down arrow button
            local downBtn = CreateFrame("Button", nil, titleContainer)
            downBtn:SetSize(arrowSize, arrowSize)
            downBtn:SetPoint("RIGHT", upBtn, "LEFT", -4, 0)
            downBtn:SetAlpha(0)  -- Hidden by default
            local downIcon = downBtn:CreateTexture(nil, "OVERLAY")
            downIcon:SetAllPoints()
            downIcon:SetTexture(MEDIA .. "icons\\eui-arrow-down3.png")
            downBtn:SetScript("OnClick", function()
                -- Find current index in _statsSections
                local currentIdx = nil
                for i, sec in ipairs(frame._statsSections) do
                    if sec == sectionData then
                        currentIdx = i
                        break
                    end
                end

                if currentIdx and currentIdx < #frame._statsSections then
                    -- Swap with next section
                    frame._statsSections[currentIdx], frame._statsSections[currentIdx + 1] = frame._statsSections[currentIdx + 1], frame._statsSections[currentIdx]

                    -- Save new order
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.statSectionsOrder = {}
                    for _, sec in ipairs(frame._statsSections) do
                        table.insert(EllesmereUIDB.statSectionsOrder, sec.sectionTitle)
                    end

                    frame._recalculateSections()
                end
            end)

            -- Show arrows on hover (both on titleContainer and arrow buttons)
            local function ShowArrows()
                upBtn:SetAlpha(0.8)
                downBtn:SetAlpha(0.8)
            end
            local function HideArrows()
                upBtn:SetAlpha(0)
                downBtn:SetAlpha(0)
            end

            titleContainer:SetScript("OnEnter", ShowArrows)
            titleContainer:SetScript("OnLeave", HideArrows)
            upBtn:SetScript("OnEnter", ShowArrows)
            upBtn:SetScript("OnLeave", HideArrows)
            downBtn:SetScript("OnEnter", ShowArrows)
            downBtn:SetScript("OnLeave", HideArrows)
        end

        sectionContainer:SetHeight(sectionData.height)
        yOffset = yOffset - sectionData.height - 16
    end

    -- Set scroll child height
    scrollChild:SetHeight(-yOffset)

    -- Save initial order if not already saved
    if not (EllesmereUIDB and EllesmereUIDB.statSectionsOrder) then
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.statSectionsOrder = {}
        for _, sec in ipairs(frame._statsSections) do
            table.insert(EllesmereUIDB.statSectionsOrder, sec.sectionTitle)
        end
    end

    -- Apply initial visibility settings
    UpdateStatCategoryVisibility()

    -- Function to update all stats
    local function UpdateAllStats()
        for _, statEntry in ipairs(frame._statsValues) do
            local result = statEntry.func()
            if result ~= nil then
                if statEntry.format:find("%%") then
                    statEntry.value:SetText(format(statEntry.format, result))
                else
                    statEntry.value:SetText(format(statEntry.format, result))
                end
            else
                statEntry.value:SetText("0")
            end
        end
    end

    -- Update stats immediately once
    UpdateAllStats()

    -- Monitor to update stats
    local statsMonitor = CreateFrame("Frame")
    statsMonitor:SetScript("OnUpdate", function()
        if not (EllesmereUIDB and EllesmereUIDB.themedCharacterSheet) then
            return
        end
        if frame and frame:IsShown() and (frame.selectedTab or 1) == 1 then
            UpdateAllStats()
        end
    end)

    -- Apply custom rarity borders to slots (like CharacterSheetINSPO style)
    local function ApplyCustomSlotBorder(slotName)
        local slot = _G[slotName]
        if not slot then return end

        -- Hide Blizzard IconBorder
        if slot.IconBorder then
            slot.IconBorder:Hide()
        end

        -- Hide overlay textures
        if slot.IconOverlay then
            slot.IconOverlay:Hide()
        end
        if slot.IconOverlay2 then
            slot.IconOverlay2:Hide()
        end

        -- Crop icon inward
        if slot.icon then
            slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end

        -- Hide NormalTexture
        local normalTexture = _G[slotName .. "NormalTexture"]
        if normalTexture then
            normalTexture:Hide()
        end

        -- Get item rarity color for border
        local itemLink = GetInventoryItemLink("player", slot:GetID())
        local borderR, borderG, borderB = 0.4, 0.4, 0.4  -- Default dark gray
        if itemLink then
            local _, _, rarity = GetItemInfo(itemLink)
            if rarity then
                borderR, borderG, borderB = C_Item.GetItemQualityColor(rarity)
            end
        end

        -- Add border directly on the slot with item color (2px thickness)
        if EllesmereUI and EllesmereUI.PanelPP then
            EllesmereUI.PanelPP.CreateBorder(slot, borderR, borderG, borderB, 1, 2, "OVERLAY", 7)
        end
    end

    -- Apply custom rarity borders to all item slots
    local itemSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
        "CharacterChestSlot", "CharacterWaistSlot", "CharacterLegsSlot",
        "CharacterFeetSlot", "CharacterWristSlot", "CharacterHandsSlot",
        "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot",
        "CharacterBackSlot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot",
        "CharacterShirtSlot", "CharacterTabardSlot"
    }

    -- Store on frame for use in tab hooks
    frame._themedSlots = itemSlots

    -- Create custom buttons for right side (Character, Titles, Equipment Manager)
    local buttonWidth = 70
    local buttonHeight = 25
    local buttonSpacing = 5
    -- Center buttons in right column (right column is ~268px wide starting at x=420)
    local totalButtonWidth = (buttonWidth * 3) + (buttonSpacing * 2)
    local rightColumnWidth = 268
    local startX = 425 + (rightColumnWidth - totalButtonWidth) / 2
    local startY = -60  -- Position near bottom of frame, but within bounds

    local function CreateEUIButton(name, label, onClick)
        local btn = CreateFrame("Button", "EUI_CharSheet_" .. name, frame, "SecureActionButtonTemplate")
        btn:SetSize(buttonWidth, buttonHeight)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", startX, startY)

        -- Background
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(0.03, 0.045, 0.05, 1)
        bg:SetAllPoints()

        -- Border
        if EllesmereUI and EllesmereUI.PanelPP then
            EllesmereUI.PanelPP.CreateBorder(btn, 0.2, 0.2, 0.2, 1, 1, "OVERLAY", 2)
        end

        -- Text
        local text = btn:CreateFontString(nil, "OVERLAY")
        text:SetFont(fontPath, 11, "")
        text:SetTextColor(1, 1, 1, 0.8)
        text:SetPoint("CENTER", btn, "CENTER", 0, 0)
        text:SetText(label)

        -- Hover effect
        btn:SetScript("OnEnter", function()
            text:SetTextColor(1, 1, 1, 1)
            bg:SetColorTexture(0.05, 0.07, 0.08, 1)
        end)
        btn:SetScript("OnLeave", function()
            text:SetTextColor(1, 1, 1, 0.8)
            bg:SetColorTexture(0.03, 0.045, 0.05, 1)
        end)

        -- Click handler
        btn:SetScript("OnClick", onClick)

        return btn
    end

    -- Character button (will be updated after stats panel is created)
    local characterBtn = CreateEUIButton("Stats", "Character", function() end)

    -- Create Titles Panel (same position and size as stats panel)
    local titlesPanel = CreateFrame("Frame", "EUI_CharSheet_TitlesPanel", frame)
    titlesPanel:SetSize(220, 340)
    titlesPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 452, -90)
    titlesPanel:SetFrameLevel(50)
    titlesPanel:Hide()
    frame._titlesPanel = titlesPanel  -- Store reference on frame

    -- Titles panel background
    local titlesBg = titlesPanel:CreateTexture(nil, "BACKGROUND")
    titlesBg:SetColorTexture(0.03, 0.045, 0.05, 0.95)
    titlesBg:SetAllPoints()

    -- Search box for titles
    local titlesSearchBox = CreateFrame("EditBox", "EUI_CharSheet_TitlesSearchBox", titlesPanel)
    titlesSearchBox:SetSize(200, 24)
    titlesSearchBox:SetPoint("TOPLEFT", titlesPanel, "TOPLEFT", 10, -10)
    titlesSearchBox:SetAutoFocus(false)
    titlesSearchBox:SetMaxLetters(20)

    local searchBg = titlesSearchBox:CreateTexture(nil, "BACKGROUND")
    searchBg:SetColorTexture(0.1, 0.12, 0.14, 0.9)
    searchBg:SetAllPoints()

    titlesSearchBox:SetTextColor(1, 1, 1, 1)
    titlesSearchBox:SetFont(fontPath, 10, "")

    -- Hint text
    local hintText = titlesSearchBox:CreateFontString(nil, "OVERLAY")
    hintText:SetFont(fontPath, 10, "")
    hintText:SetText("search for title")
    hintText:SetTextColor(0.6, 0.6, 0.6, 0.7)
    hintText:SetPoint("LEFT", titlesSearchBox, "LEFT", 5, 0)

    -- Create scroll frame for titles
    local titlesScrollFrame = CreateFrame("ScrollFrame", "EUI_CharSheet_TitlesScrollFrame", titlesPanel)
    titlesScrollFrame:SetSize(200, 300)
    titlesScrollFrame:SetPoint("TOPLEFT", titlesPanel, "TOPLEFT", 5, -40)
    titlesScrollFrame:EnableMouseWheel(true)

    -- Create scroll child
    local titlesScrollChild = CreateFrame("Frame", "EUI_CharSheet_TitlesScrollChild", titlesScrollFrame)
    titlesScrollChild:SetWidth(200)
    titlesScrollFrame:SetScrollChild(titlesScrollChild)

    -- Mousewheel support
    titlesScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local currentScroll = titlesScrollFrame:GetVerticalScroll()
        local maxScroll = math.max(0, titlesScrollChild:GetHeight() - titlesScrollFrame:GetHeight())
        local newScroll = currentScroll - delta * 20
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        titlesScrollFrame:SetVerticalScroll(newScroll)
    end)

    -- Populate titles
    local function RefreshTitlesList()
        -- Clear old buttons
        for _, child in ipairs({titlesScrollChild:GetChildren()}) do
            child:Hide()
        end

        local currentTitle = GetCurrentTitle()
        local yOffset = 0
        local searchText = titlesSearchBox:GetText():lower()
        local titleButtons = {}  -- Store button references

        -- Add "No Title" button
        local noTitleBtn = CreateFrame("Button", nil, titlesScrollChild)
        noTitleBtn:SetWidth(240)
        noTitleBtn:SetHeight(24)
        noTitleBtn:SetPoint("TOPLEFT", titlesScrollChild, "TOPLEFT", 10, yOffset)

        local noTitleBg = noTitleBtn:CreateTexture(nil, "BACKGROUND")
        noTitleBg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
        noTitleBg:SetAllPoints()
        titleButtons[0] = { btn = noTitleBtn, bg = noTitleBg }

        local noTitleText = noTitleBtn:CreateFontString(nil, "OVERLAY")
        noTitleText:SetFont(fontPath, 11, "")
        noTitleText:SetText("No Title")
        noTitleText:SetTextColor(1, 1, 1, 1)
        noTitleText:SetPoint("LEFT", noTitleBtn, "LEFT", 10, 0)

        noTitleBtn:SetScript("OnClick", function()
            SetCurrentTitle(0)
            titlesSearchBox:SetText("")
            hintText:Show()
            RefreshTitlesList()
        end)

        noTitleBtn:SetScript("OnEnter", function()
            noTitleBg:SetColorTexture(0.047, 0.824, 0.616, 0.2)
        end)

        noTitleBtn:SetScript("OnLeave", function()
            if GetCurrentTitle() == 0 then
                noTitleBg:SetColorTexture(0.1, 0.12, 0.14, 0.9)  -- Lighter gray for active title
            else
                noTitleBg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
            end
        end)

        yOffset = yOffset - 28

        -- Add all available titles
        for titleIndex = 1, GetNumTitles() do
            if IsTitleKnown(titleIndex) then
                local titleName = GetTitleName(titleIndex)
                if titleName and (searchText == "" or titleName:lower():find(searchText, 1, true)) then
                    local titleBtn = CreateFrame("Button", nil, titlesScrollChild)
                    titleBtn:SetWidth(240)
                    titleBtn:SetHeight(24)
                    titleBtn:SetPoint("TOPLEFT", titlesScrollChild, "TOPLEFT", 10, yOffset)
                    titleBtn._titleIndex = titleIndex

                    local btnBg = titleBtn:CreateTexture(nil, "BACKGROUND")
                    btnBg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
                    btnBg:SetAllPoints()
                    titleButtons[titleIndex] = { btn = titleBtn, bg = btnBg }

                    local titleText = titleBtn:CreateFontString(nil, "OVERLAY")
                    titleText:SetFont(fontPath, 11, "")
                    titleText:SetText(titleName)
                    titleText:SetTextColor(1, 1, 1, 1)
                    titleText:SetPoint("LEFT", titleBtn, "LEFT", 10, 0)

                    titleBtn:SetScript("OnClick", function()
                        SetCurrentTitle(titleBtn._titleIndex)
                        titlesSearchBox:SetText("")
                        hintText:Show()
                        -- Schedule refresh after a frame to ensure the title is updated
                        C_Timer.After(0, RefreshTitlesList)
                    end)

                    titleBtn:SetScript("OnEnter", function()
                        btnBg:SetColorTexture(0.047, 0.824, 0.616, 0.2)
                    end)

                    titleBtn:SetScript("OnLeave", function()
                        if GetCurrentTitle() == titleIndex then
                            btnBg:SetColorTexture(0.1, 0.12, 0.14, 0.9)  -- Lighter gray for active title
                        else
                            btnBg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
                        end
                    end)

                    yOffset = yOffset - 28
                end
            end
        end

        -- Re-read current title to ensure it's updated
        currentTitle = GetCurrentTitle()

        -- Update colors based on current title
        for titleIndex, btnData in pairs(titleButtons) do
            if currentTitle == titleIndex then
                btnData.bg:SetColorTexture(0.1, 0.12, 0.14, 0.9)
            else
                btnData.bg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
            end
        end

        titlesScrollChild:SetHeight(-yOffset)
    end

    -- Search input handler
    titlesSearchBox:SetScript("OnTextChanged", function()
        RefreshTitlesList()
    end)

    -- Focus gained handler
    titlesSearchBox:SetScript("OnEditFocusGained", function()
        if titlesSearchBox:GetText() == "" then
            hintText:Hide()
        end
    end)

    -- Focus lost handler
    titlesSearchBox:SetScript("OnEditFocusLost", function()
        if titlesSearchBox:GetText() == "" then
            hintText:Show()
        end
    end)

    -- Populate initially
    RefreshTitlesList()

    -- Hook to refresh titles when shown
    frame._titlesPanel:HookScript("OnShow", function()
        titlesSearchBox:SetText("")
        RefreshTitlesList()
    end)

    -- Update the Character button to show stats
    characterBtn:SetScript("OnClick", function()
        if not statsPanel:IsShown() then
            statsPanel:Show()
            CharacterFrame._titlesPanel:Hide()
            CharacterFrame._equipPanel:Hide()
        end
    end)

    -- Titles button to show titles
    CreateEUIButton("Titles", "Titles", function()
        if not CharacterFrame._titlesPanel:IsShown() then
            CharacterFrame._titlesPanel:Show()
            statsPanel:Hide()
            CharacterFrame._equipPanel:Hide()
        end
    end)

    -- Create Equipment Panel (same position and size as stats panel)
    local equipPanel = CreateFrame("Frame", "EUI_CharSheet_EquipPanel", frame)
    equipPanel:SetSize(220, 340)
    equipPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 452, -90)
    equipPanel:SetFrameLevel(50)
    equipPanel:Hide()
    frame._equipPanel = equipPanel

    -- Equipment panel background
    local equipBg = equipPanel:CreateTexture(nil, "BACKGROUND")
    equipBg:SetColorTexture(0.03, 0.045, 0.05, 0.95)
    equipBg:SetAllPoints()

    -- Create scroll frame for equipment
    local equipScrollFrame = CreateFrame("ScrollFrame", "EUI_CharSheet_EquipScrollFrame", equipPanel)
    equipScrollFrame:SetSize(200, 320)
    equipScrollFrame:SetPoint("TOPLEFT", equipPanel, "TOPLEFT", 5, -10)
    equipScrollFrame:EnableMouseWheel(true)

    -- Create scroll child
    local equipScrollChild = CreateFrame("Frame", "EUI_CharSheet_EquipScrollChild", equipScrollFrame)
    equipScrollChild:SetWidth(200)
    equipScrollFrame:SetScrollChild(equipScrollChild)

    -- Mousewheel support
    equipScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local currentScroll = equipScrollFrame:GetVerticalScroll()
        local maxScroll = math.max(0, equipScrollChild:GetHeight() - equipScrollFrame:GetHeight())
        local newScroll = currentScroll - delta * 20
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        equipScrollFrame:SetVerticalScroll(newScroll)
    end)

    -- Track selected equipment set
    local selectedSetID = nil

    -- Forward declare the refresh function (will be defined after buttons)
    local RefreshEquipmentSets

    -- Create "New Set" button once (outside refresh to avoid recreation)
    local newSetBtn = CreateFrame("Button", nil, equipScrollChild)
    newSetBtn:SetWidth(65)
    newSetBtn:SetHeight(24)
    newSetBtn:SetPoint("TOPLEFT", equipScrollChild, "TOPLEFT", 0, -5)

    local newSetBg = newSetBtn:CreateTexture(nil, "BACKGROUND")
    newSetBg:SetColorTexture(0.05, 0.07, 0.08, 1)
    newSetBg:SetAllPoints()

    -- Create border using pixelperfect
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(newSetBtn, 0.8, 0.8, 0.8, 1, 1, "OVERLAY", 1)
    end

    local newSetText = newSetBtn:CreateFontString(nil, "OVERLAY")
    newSetText:SetFont(fontPath, 10, "")
    newSetText:SetText("New Set")
    newSetText:SetTextColor(1, 1, 1, 0.7)
    newSetText:SetPoint("CENTER", newSetBtn, "CENTER", 0, 0)

    newSetBtn:SetScript("OnClick", function()
        if InCombatLockdown() then return end

        StaticPopupDialogs["EUI_NEW_EQUIPMENT_SET"] = {
            text = "New equipment set name:",
            button1 = "Create",
            button2 = "Cancel",
            OnAccept = function(dialog)
                local newName = dialog.EditBox:GetText()
                if newName ~= "" then
                    C_EquipmentSet.CreateEquipmentSet(newName)
                    RefreshEquipmentSets()
                end
            end,
            hasEditBox = true,
            editBoxWidth = 350,
            timeout = 0,
            whileDead = false,
            hideOnEscape = true,
        }
        StaticPopup_Show("EUI_NEW_EQUIPMENT_SET")
    end)

    newSetBtn:SetScript("OnEnter", function()
        newSetBg:SetColorTexture(0.047, 0.824, 0.616, 0.2)
        newSetText:SetTextColor(0.15, 1, 0.8, 1)
        if EllesmereUI and EllesmereUI.PanelPP then
            EllesmereUI.PanelPP.SetBorderColor(newSetBtn, 0.03, 0.6, 0.45, 1)
        end
    end)

    newSetBtn:SetScript("OnLeave", function()
        newSetBg:SetColorTexture(0.05, 0.07, 0.08, 1)
        newSetText:SetTextColor(1, 1, 1, 0.7)
        if EllesmereUI and EllesmereUI.PanelPP then
            EllesmereUI.PanelPP.SetBorderColor(newSetBtn, 0.8, 0.8, 0.8, 1)
        end
    end)

    -- Create Equip button once (outside refresh to preserve animation closure)
    local equipTopBtn = CreateFrame("Button", nil, equipScrollChild)
    equipTopBtn:SetWidth(60)
    equipTopBtn:SetHeight(24)
    equipTopBtn:SetPoint("TOPLEFT", equipScrollChild, "TOPLEFT", 67, -5)

    local equipTopBg = equipTopBtn:CreateTexture(nil, "BACKGROUND")
    equipTopBg:SetColorTexture(0.05, 0.07, 0.08, 1)
    equipTopBg:SetAllPoints()

    -- Create border using pixelperfect
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(equipTopBtn, 0.8, 0.8, 0.8, 1, 1, "OVERLAY", 1)
    end

    local equipTopText = equipTopBtn:CreateFontString(nil, "OVERLAY")
    equipTopText:SetFont(fontPath, 10, "")
    equipTopText:SetText("Equip")
    equipTopText:SetTextColor(1, 1, 1, 0.7)
    equipTopText:SetPoint("CENTER", equipTopBtn, "CENTER", 0, 0)

    equipTopBtn:SetScript("OnEnter", function()
        equipTopBg:SetColorTexture(0.047, 0.824, 0.616, 0.2)
        equipTopText:SetTextColor(0.15, 1, 0.8, 1)
        if EllesmereUI and EllesmereUI.PanelPP then
            EllesmereUI.PanelPP.SetBorderColor(equipTopBtn, 0.03, 0.6, 0.45, 1)
        end
    end)

    equipTopBtn:SetScript("OnLeave", function()
        equipTopBg:SetColorTexture(0.05, 0.07, 0.08, 1)
        equipTopText:SetTextColor(1, 1, 1, 0.7)
        if EllesmereUI and EllesmereUI.PanelPP then
            EllesmereUI.PanelPP.SetBorderColor(equipTopBtn, 0.8, 0.8, 0.8, 1)
        end
    end)

    equipTopBtn:SetScript("OnClick", function()
        if InCombatLockdown() then return end

        -- Visual feedback: change text to "Equipped!" and color it green
        equipTopText:SetText("Equipped!")
        equipTopText:SetTextColor(0.047, 0.824, 0.616, 1)  -- Green

        if selectedSetID then
            C_EquipmentSet.UseEquipmentSet(selectedSetID)
            activeEquipmentSetID = selectedSetID
            -- Save to DB for persistence
            if EllesmereUIDB then
                EllesmereUIDB.lastEquippedSet = selectedSetID
            end
            RefreshEquipmentSets()
        end

        -- Change back to "Equip" after 1 second
        C_Timer.After(1, function()
            if equipTopText then
                equipTopText:SetText("Equip")
                equipTopText:SetTextColor(1, 1, 1, 0.7)  -- Zurück zu Standard
            end
        end)
    end)

    -- Create Save button once (outside refresh to preserve animation closure)
    local saveTopBtn = CreateFrame("Button", nil, equipScrollChild)
    saveTopBtn:SetWidth(71)
    saveTopBtn:SetHeight(24)
    saveTopBtn:SetPoint("TOPLEFT", equipScrollChild, "TOPLEFT", 129, -5)

    local saveTopBg = saveTopBtn:CreateTexture(nil, "BACKGROUND")
    saveTopBg:SetColorTexture(0.05, 0.07, 0.08, 1)
    saveTopBg:SetAllPoints()

    -- Create border using pixelperfect
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(saveTopBtn, 0.8, 0.8, 0.8, 1, 1, "OVERLAY", 1)
    end

    local saveTopText = saveTopBtn:CreateFontString(nil, "OVERLAY")
    saveTopText:SetFont(fontPath, 10, "")
    saveTopText:SetText("Save")
    saveTopText:SetTextColor(1, 1, 1, 0.7)
    saveTopText:SetPoint("CENTER", saveTopBtn, "CENTER", 0, 0)

    saveTopBtn:SetScript("OnEnter", function()
        saveTopBg:SetColorTexture(0.047, 0.824, 0.616, 0.2)
        saveTopText:SetTextColor(0.15, 1, 0.8, 1)
        if EllesmereUI and EllesmereUI.PanelPP then
            EllesmereUI.PanelPP.SetBorderColor(saveTopBtn, 0.03, 0.6, 0.45, 1)
        end
    end)

    saveTopBtn:SetScript("OnLeave", function()
        saveTopBg:SetColorTexture(0.05, 0.07, 0.08, 1)
        saveTopText:SetTextColor(1, 1, 1, 0.7)
        if EllesmereUI and EllesmereUI.PanelPP then
            EllesmereUI.PanelPP.SetBorderColor(saveTopBtn, 0.8, 0.8, 0.8, 1)
        end
    end)

    saveTopBtn:SetScript("OnClick", function()
        if InCombatLockdown() then return end

        -- Visual feedback: change text to "Saved!" and color it green
        saveTopText:SetText("Saved!")
        saveTopText:SetTextColor(0.047, 0.824, 0.616, 1)  -- Green

        if selectedSetID then
            C_EquipmentSet.SaveEquipmentSet(selectedSetID)
        end

        -- Change back to "Save" after 1 second
        C_Timer.After(1, function()
            if saveTopText then
                saveTopText:SetText("Save")
                saveTopText:SetTextColor(1, 1, 1, 0.7)  -- Zurück zu Standard
            end
        end)
    end)

    -- Create "Sets" section header
    local setsHeaderFrame = CreateFrame("Frame", nil, equipScrollChild)
    setsHeaderFrame:SetWidth(200)
    setsHeaderFrame:SetHeight(15)
    setsHeaderFrame:SetPoint("TOPLEFT", equipScrollChild, "TOPLEFT", 0, -27)

    -- Left line
    local leftLine = setsHeaderFrame:CreateTexture(nil, "BACKGROUND")
    leftLine:SetColorTexture(0.047, 0.824, 0.616, 1)
    leftLine:SetPoint("LEFT", setsHeaderFrame, "LEFT", 0, -14)
    leftLine:SetPoint("RIGHT", setsHeaderFrame, "CENTER", -25, -14)
    leftLine:SetHeight(2)

    -- Text
    local setsHeaderText = setsHeaderFrame:CreateFontString(nil, "OVERLAY")
    setsHeaderText:SetFont(fontPath, 13, "")
    setsHeaderText:SetText("Sets")
    setsHeaderText:SetTextColor(0.047, 0.824, 0.616, 1)
    setsHeaderText:SetPoint("CENTER", setsHeaderFrame, "CENTER", 0, -14)

    -- Right line
    local rightLine = setsHeaderFrame:CreateTexture(nil, "BACKGROUND")
    rightLine:SetColorTexture(0.047, 0.824, 0.616, 1)
    rightLine:SetPoint("LEFT", setsHeaderFrame, "CENTER", 25, -14)
    rightLine:SetPoint("RIGHT", setsHeaderFrame, "RIGHT", 0, -14)
    rightLine:SetHeight(2)

    -- Function to check if all items of a set are equipped
    local function IsEquipmentSetComplete(setName)
        if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetID then
            return true  -- API not available
        end

        -- Get the set ID from the name
        local setID = C_EquipmentSet.GetEquipmentSetID(setName)
        if not setID then
            return true  -- Set not found
        end

        -- Get the items in this set
        local setItems = C_EquipmentSet.GetItemIDs(setID)
        if not setItems then
            return true  -- No items in set
        end

        -- Compare each slot
        for slot, setItemID in pairs(setItems) do
            if setItemID and setItemID ~= 0 then
                local equippedID = GetInventoryItemID("player", slot)
                if equippedID ~= setItemID then
                    return false  -- Mismatch = incomplete set
                end
            end
        end

        return true  -- All items match
    end

    -- Function to get missing items from a set
    local function GetMissingSetItems(setName)
        if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetID then
            return {}
        end

        local setID = C_EquipmentSet.GetEquipmentSetID(setName)
        if not setID then return {} end

        local setItems = C_EquipmentSet.GetItemIDs(setID)
        if not setItems then return {} end

        local missing = {}
        local slotNames = {
            "Head", "Neck", "Shoulder", "Back",
            "Chest", "Waist", "Legs", "Feet",
            "Wrist", "Hands", "Finger 1", "Finger 2",
            "Trinket 1", "Trinket 2", "Main Hand", "Off Hand",
            "Tabard", "Chest (Relic)", "Back (Relic)"
        }

        for slot, setItemID in pairs(setItems) do
            if setItemID and setItemID ~= 0 then
                local equippedID = GetInventoryItemID("player", slot)
                if equippedID ~= setItemID then
                    local itemName = GetItemInfo(setItemID)
                    table.insert(missing, {
                        slot = slotNames[slot] or "Unknown",
                        itemID = setItemID,
                        itemName = itemName or "Unknown Item"
                    })
                end
            end
        end

        return missing
    end

    -- Function to reload equipment sets
    RefreshEquipmentSets = function()
        -- Clear old set buttons (but keep the new set, equip, save buttons, and header)
        for _, child in ipairs({equipScrollChild:GetChildren()}) do
            if child ~= newSetBtn and child ~= equipTopBtn and child ~= saveTopBtn and child ~= setsHeaderFrame then
                child:Hide()
            end
        end

        local equipmentSets = {}
        if C_EquipmentSet then
            local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
            if setIDs then
                for _, setID in ipairs(setIDs) do
                    local setName = C_EquipmentSet.GetEquipmentSetInfo(setID)
                    if setName and setName ~= "" then
                        table.insert(equipmentSets, {id = setID, name = setName})
                    end
                end
            end
        end

        local yOffset = -59  -- After buttons and header
        for _, setData in ipairs(equipmentSets) do
            local setBtn = CreateFrame("Button", nil, equipScrollChild)
            setBtn:SetWidth(200)
            setBtn:SetHeight(24)
            setBtn:SetPoint("TOPLEFT", equipScrollChild, "TOPLEFT", 0, yOffset)

            -- Background
            local btnBg = setBtn:CreateTexture(nil, "BACKGROUND")
            if activeEquipmentSetID == setData.id then
                btnBg:SetColorTexture(0.1, 0.12, 0.14, 0.9)  -- Lighter gray for active set
            else
                btnBg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
            end
            btnBg:SetAllPoints()

            -- Text
            local setText = setBtn:CreateFontString(nil, "OVERLAY")
            setText:SetFont(fontPath, 10, "")
            setText:SetText(setData.name)

            -- Check if all items are equipped, if not, color red
            if IsEquipmentSetComplete(setData.name) then
                setText:SetTextColor(1, 1, 1, 1)  -- White
            else
                setText:SetTextColor(1, 0.3, 0.3, 1)  -- Red
            end

            setText:SetPoint("LEFT", setBtn, "LEFT", 10, 0)

            -- Store references for the color monitor
            setBtn._setText = setText
            setBtn._setName = setData.name

            -- Spec icon
            local assignedSpec = C_EquipmentSet.GetEquipmentSetAssignedSpec(setData.id)
            if assignedSpec then
                local _, specName, _, specIcon = GetSpecializationInfo(assignedSpec)
                if specIcon then
                    local specIconTexture = setBtn:CreateTexture(nil, "OVERLAY")
                    specIconTexture:SetTexture(specIcon)
                    specIconTexture:SetSize(16, 16)
                    specIconTexture:SetPoint("RIGHT", setBtn, "RIGHT", -45, 0)
                end
            end


            -- Click handler (select set)
            setBtn:SetScript("OnClick", function()
                selectedSetID = setData.id
                RefreshEquipmentSets()
            end)

            -- Hover effect and tooltip for missing items
            setBtn:SetScript("OnEnter", function()
                btnBg:SetColorTexture(0.047, 0.824, 0.616, 0.2)

                -- Show tooltip if set is incomplete
                if not IsEquipmentSetComplete(setData.name) then
                    local missing = GetMissingSetItems(setData.name)
                    if #missing > 0 then
                        GameTooltip:SetOwner(setBtn, "ANCHOR_RIGHT")
                        GameTooltip:AddLine("Missing Items:", 1, 0.3, 0.3, 1)

                        for _, item in ipairs(missing) do
                            local icon = GetItemIcon(item.itemID)
                            local iconText = icon and string.format("|T%s:16|t", icon) or ""
                            GameTooltip:AddLine(
                                string.format("%s %s: %s", iconText, item.slot, item.itemName),
                                1, 1, 1, true
                            )
                        end

                        GameTooltip:Show()
                    end
                end
            end)

            setBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()

                if selectedSetID == setData.id then
                    btnBg:SetColorTexture(0.047, 0.824, 0.616, 0.5)
                elseif activeEquipmentSetID == setData.id then
                    btnBg:SetColorTexture(0.1, 0.12, 0.14, 0.9)  -- Lighter gray for active set
                else
                    btnBg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
                end
            end)

            -- Highlight selected set
            if selectedSetID == setData.id then
                btnBg:SetColorTexture(0.047, 0.824, 0.616, 0.5)
            end

            -- Border for active set
            if activeEquipmentSetID == setData.id then
                if EllesmereUI and EllesmereUI.PanelPP then
                    EllesmereUI.PanelPP.CreateBorder(setBtn, 0.15, 0.17, 0.19, 1, 1, "OVERLAY", 1)
                end
            end

            -- Cogwheel button for spec assignment
            local cogBtn = CreateFrame("Button", nil, setBtn)
            cogBtn:SetWidth(14)
            cogBtn:SetHeight(14)
            cogBtn:SetPoint("RIGHT", setBtn, "RIGHT", -5, 0)

            local cogIcon = cogBtn:CreateTexture(nil, "OVERLAY")
            cogIcon:SetTexture("Interface/Buttons/UI-OptionsButton")
            cogIcon:SetAllPoints()

            -- Hover highlight
            local cogHL = cogBtn:CreateTexture(nil, "HIGHLIGHT")
            cogHL:SetColorTexture(0.047, 0.824, 0.616, 0.3)
            cogHL:SetAllPoints()
            cogBtn:SetHighlightTexture(cogHL)

            cogBtn:SetScript("OnClick", function(self, button)
                -- Create a simple spec selection menu
                local specs = {}
                local numSpecs = GetNumSpecializations()
                for i = 1, numSpecs do
                    local id, name = GetSpecializationInfo(i)
                    if id then
                        table.insert(specs, {index = i, name = name})
                    end
                end

                -- Create or reuse menu frame
                if not cogBtn.menuFrame then
                    -- Create invisible backdrop to catch clicks outside menu
                    local backdrop = CreateFrame("Button", nil, UIParent)
                    backdrop:SetFrameStrata("DIALOG")
                    backdrop:SetFrameLevel(99)
                    backdrop:SetSize(2560, 1440)
                    backdrop:SetPoint("CENTER", UIParent, "CENTER")
                    backdrop:SetScript("OnClick", function()
                        cogBtn.menuFrame:Hide()
                        backdrop:Hide()
                    end)
                    cogBtn.menuBackdrop = backdrop

                    cogBtn.menuFrame = CreateFrame("Frame", nil, UIParent)
                    cogBtn.menuFrame:SetFrameStrata("DIALOG")
                    cogBtn.menuFrame:SetFrameLevel(100)
                    cogBtn.menuFrame:SetSize(120, #specs * 24 + 10)

                    -- Add background texture
                    local bg = cogBtn.menuFrame:CreateTexture(nil, "BACKGROUND")
                    bg:SetColorTexture(0.05, 0.07, 0.08, 0.9)
                    bg:SetAllPoints()

                    -- Add border
                    local border = cogBtn.menuFrame:CreateTexture(nil, "BORDER")
                    border:SetColorTexture(0.047, 0.824, 0.616, 1)
                    border:SetPoint("TOPLEFT", cogBtn.menuFrame, "TOPLEFT", 0, 0)
                    border:SetPoint("TOPRIGHT", cogBtn.menuFrame, "TOPRIGHT", 0, 0)
                    border:SetHeight(1)

                    border = cogBtn.menuFrame:CreateTexture(nil, "BORDER")
                    border:SetColorTexture(0.047, 0.824, 0.616, 1)
                    border:SetPoint("BOTTOMLEFT", cogBtn.menuFrame, "BOTTOMLEFT", 0, 0)
                    border:SetPoint("BOTTOMRIGHT", cogBtn.menuFrame, "BOTTOMRIGHT", 0, 0)
                    border:SetHeight(1)

                    border = cogBtn.menuFrame:CreateTexture(nil, "BORDER")
                    border:SetColorTexture(0.047, 0.824, 0.616, 1)
                    border:SetPoint("TOPLEFT", cogBtn.menuFrame, "TOPLEFT", 0, 0)
                    border:SetPoint("BOTTOMLEFT", cogBtn.menuFrame, "BOTTOMLEFT", 0, 0)
                    border:SetWidth(1)

                    border = cogBtn.menuFrame:CreateTexture(nil, "BORDER")
                    border:SetColorTexture(0.047, 0.824, 0.616, 1)
                    border:SetPoint("TOPRIGHT", cogBtn.menuFrame, "TOPRIGHT", 0, 0)
                    border:SetPoint("BOTTOMRIGHT", cogBtn.menuFrame, "BOTTOMRIGHT", 0, 0)
                    border:SetWidth(1)
                end

                -- Clear previous buttons
                for _, btn in ipairs(cogBtn.menuFrame.specButtons or {}) do
                    btn:Hide()
                end
                cogBtn.menuFrame.specButtons = {}

                -- Create spec buttons
                local yOffset = 0
                for _, spec in ipairs(specs) do
                    local btn = CreateFrame("Button", nil, cogBtn.menuFrame)
                    btn:SetSize(110, 24)
                    btn:SetPoint("TOP", cogBtn.menuFrame, "TOP", 0, -5 - (yOffset * 24))
                    btn:SetNormalFontObject(GameFontNormal)
                    btn:SetText(spec.name)

                    local texture = btn:CreateTexture(nil, "BACKGROUND")
                    texture:SetColorTexture(0.05, 0.07, 0.08, 0.5)
                    texture:SetAllPoints()
                    btn:SetNormalTexture(texture)

                    local hlTexture = btn:CreateTexture(nil, "HIGHLIGHT")
                    hlTexture:SetColorTexture(0.047, 0.824, 0.616, 0.3)
                    hlTexture:SetAllPoints()
                    btn:SetHighlightTexture(hlTexture)

                    btn:SetScript("OnClick", function()
                        C_EquipmentSet.AssignSpecToEquipmentSet(setData.id, spec.index)
                        RefreshEquipmentSets()
                        cogBtn.menuFrame:Hide()
                        cogBtn.menuBackdrop:Hide()
                    end)

                    table.insert(cogBtn.menuFrame.specButtons, btn)
                    yOffset = yOffset + 1
                end

                -- Position and show menu
                cogBtn.menuFrame:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -5)
                cogBtn.menuFrame:Show()
                cogBtn.menuBackdrop:Show()
            end)

            -- Delete button (X) for removing equipment set
            local deleteBtn = CreateFrame("Button", nil, setBtn)
            deleteBtn:SetWidth(14)
            deleteBtn:SetHeight(14)
            deleteBtn:SetPoint("RIGHT", cogBtn, "LEFT", -5, 0)

            local deleteText = deleteBtn:CreateFontString(nil, "OVERLAY")
            deleteText:SetFont(fontPath, 18, "")
            deleteText:SetText("×")
            deleteText:SetTextColor(1, 1, 1, 0.8)
            deleteText:SetPoint("CENTER", deleteBtn, "CENTER", 0, 0)

            deleteBtn:SetScript("OnEnter", function()
                deleteText:SetTextColor(1, 0.2, 0.2, 1)  -- Red
            end)

            deleteBtn:SetScript("OnLeave", function()
                deleteText:SetTextColor(1, 1, 1, 0.8)
            end)

            deleteBtn:SetScript("OnClick", function()
                -- Show confirmation dialog
                StaticPopupDialogs["EUI_DELETE_EQUIPMENT_SET"] = {
                    text = "Delete equipment set '" .. setData.name .. "'?",
                    button1 = "Delete",
                    button2 = "Cancel",
                    OnAccept = function()
                        C_EquipmentSet.DeleteEquipmentSet(setData.id)
                        RefreshEquipmentSets()
                    end,
                    timeout = 0,
                    whileDead = false,
                    hideOnEscape = true,
                }
                StaticPopup_Show("EUI_DELETE_EQUIPMENT_SET")
            end)

            yOffset = yOffset - 30
        end

        equipScrollChild:SetHeight(-yOffset)
    end

    -- Continuous monitor to update set colors when equipment changes
    local equipmentColorMonitor = CreateFrame("Frame")
    equipmentColorMonitor:SetScript("OnUpdate", function()
        if not (CharacterFrame and CharacterFrame:IsShown() and CharacterFrame._equipPanel and CharacterFrame._equipPanel:IsShown()) then
            return
        end

        -- Update colors of all visible set buttons
        for _, child in ipairs({equipScrollChild:GetChildren()}) do
            if child._setText and child._setName then
                if IsEquipmentSetComplete(child._setName) then
                    child._setText:SetTextColor(1, 1, 1, 1)  -- White
                else
                    child._setText:SetTextColor(1, 0.3, 0.3, 1)  -- Red
                end
            end
        end
    end)

    -- Event handler for equipment set changes
    local equipSetChangeFrame = CreateFrame("Frame")
    equipSetChangeFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
    equipSetChangeFrame:SetScript("OnEvent", function(self, event)
        -- Full refresh when sets change
        if CharacterFrame and CharacterFrame:IsShown() and CharacterFrame._equipPanel and CharacterFrame._equipPanel:IsShown() then
            RefreshEquipmentSets()
        end
    end)

    -- Hook to refresh equipment sets when shown
    equipPanel:HookScript("OnShow", function()
        RefreshEquipmentSets()
    end)

    -- Equipment Manager button
    CreateEUIButton("Equipment", "Equipment", function()
        if not CharacterFrame._equipPanel:IsShown() then
            CharacterFrame._equipPanel:Show()
            statsPanel:Hide()
            CharacterFrame._titlesPanel:Hide()

            -- Activate Flyout-Style mode: show flyout menu on hover for all slots
            frame._flyoutModeActive = true
        else
            frame._flyoutModeActive = false
        end
    end)

    -- Update button positions to stack horizontally
    local buttons = {
        "EUI_CharSheet_Stats",
        "EUI_CharSheet_Titles",
        "EUI_CharSheet_Equipment"
    }
    for i, btnName in ipairs(buttons) do
        local btn = _G[btnName]
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", startX + (i - 1) * (buttonWidth + buttonSpacing), startY)
        end
    end

    -- Left column slots (show itemlevel on right)
    local leftColumnSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
        "CharacterBackSlot", "CharacterChestSlot", "CharacterShirtSlot",
        "CharacterTabardSlot", "CharacterWristSlot"
    }

    -- Right column slots (show itemlevel on left)
    local rightColumnSlots = {
        "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot",
        "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot"
    }

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT

    -- Create global socket container for all slot icons
    local globalSocketContainer = CreateFrame("Frame", "EUI_CharSheet_SocketContainer", frame)
    globalSocketContainer:SetFrameLevel(100)
    -- Only show if on character tab
    local isCharacterTab = (frame.selectedTab or 1) == 1
    if isCharacterTab then
        globalSocketContainer:Show()
    else
        globalSocketContainer:Hide()
    end
    frame._socketContainer = globalSocketContainer  -- Store reference on frame

    -- Create overlay frame for text labels (above model, transparent, no mouse input)
    local textOverlayFrame = CreateFrame("Frame", "EUI_CharSheet_TextOverlay", frame)
    textOverlayFrame:SetFrameLevel(5)  -- Higher than model (FrameLevel 2)
    textOverlayFrame:EnableMouse(false)
    textOverlayFrame:Show()
    frame._textOverlayFrame = textOverlayFrame

    for _, slotName in ipairs(itemSlots) do
        ApplyCustomSlotBorder(slotName)

        -- Create itemlevel labels
        local slot = _G[slotName]
        if slot and not slot._itemLevelLabel then
            local itemLevelSize = EllesmereUIDB and EllesmereUIDB.charSheetItemLevelSize or 11
            local label = textOverlayFrame:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, itemLevelSize, "")
            label:SetTextColor(1, 1, 1, 0.8)
            label:SetJustifyH("CENTER")

            -- Position based on column
            if tContains(leftColumnSlots, slotName) then
                -- Left column: show on right side
                label:SetPoint("CENTER", slot, "RIGHT", 15, 10)
            elseif tContains(rightColumnSlots, slotName) then
                -- Right column: show on left side
                label:SetPoint("CENTER", slot, "LEFT", -15, 10)
            elseif slotName == "CharacterMainHandSlot" then
                -- MainHand: show on left side
                label:SetPoint("CENTER", slot, "LEFT", -15, 10)
            elseif slotName == "CharacterSecondaryHandSlot" then
                -- OffHand: show on right side
                label:SetPoint("CENTER", slot, "RIGHT", 15, 10)
            end

            slot._itemLevelLabel = label
        end

        -- Create enchant labels
        if slot and not slot._enchantLabel then
            local enchantSize = EllesmereUIDB and EllesmereUIDB.charSheetEnchantSize or 9
            local enchantLabel = textOverlayFrame:CreateFontString(nil, "OVERLAY")
            enchantLabel:SetFont(fontPath, enchantSize, "")
            enchantLabel:SetTextColor(1, 1, 1, 0.8)
            enchantLabel:SetJustifyH("CENTER")

            -- Position based on column (below itemlevel)
            if tContains(leftColumnSlots, slotName) then
                enchantLabel:SetPoint("LEFT", slot, "RIGHT", 5, -5)
            elseif tContains(rightColumnSlots, slotName) then
                enchantLabel:SetPoint("Right", slot, "LEFT", -5, -5)
            elseif slotName == "CharacterMainHandSlot" then
                enchantLabel:SetPoint("RIGHT", slot, "LEFT", -5, -5)
            elseif slotName == "CharacterSecondaryHandSlot" then
                enchantLabel:SetPoint("LEFT", slot, "RIGHT", 15, -5)
            end

            slot._enchantLabel = enchantLabel
        end

        -- Create upgrade track labels (positioned relative to itemlevel)
        if slot and not slot._upgradeTrackLabel and slot._itemLevelLabel then
            local upgradeTrackSize = EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackSize or 11
            local upgradeTrackLabel = textOverlayFrame:CreateFontString(nil, "OVERLAY")
            upgradeTrackLabel:SetFont(fontPath, upgradeTrackSize, "")
            upgradeTrackLabel:SetTextColor(1, 1, 1, 0.6)
            upgradeTrackLabel:SetJustifyH("CENTER")

            -- Position beside itemlevel label based on column
            if tContains(leftColumnSlots, slotName) then
                -- Left column: upgradeTrack RIGHT of itemLevel
                upgradeTrackLabel:SetPoint("LEFT", slot._itemLevelLabel, "RIGHT", 3, 0)
            elseif tContains(rightColumnSlots, slotName) then
                -- Right column: upgradeTrack LEFT of itemLevel
                upgradeTrackLabel:SetPoint("RIGHT", slot._itemLevelLabel, "LEFT", -3, 0)
            elseif slotName == "CharacterMainHandSlot" then
                -- MainHand: upgradeTrack LEFT of itemLevel
                upgradeTrackLabel:SetPoint("RIGHT", slot._itemLevelLabel, "LEFT", -3, 0)
            elseif slotName == "CharacterSecondaryHandSlot" then
                -- OffHand: upgradeTrack RIGHT of itemLevel
                upgradeTrackLabel:SetPoint("LEFT", slot._itemLevelLabel, "RIGHT", 3, 0)
            end

            slot._upgradeTrackLabel = upgradeTrackLabel
        end
    end

    -- Update slot borders on inventory changes
    local function UpdateSlotBorders()
        for _, slotName in ipairs(itemSlots) do
            local slot = _G[slotName]
            if slot then
                local itemLink = GetInventoryItemLink("player", slot:GetID())
                local borderR, borderG, borderB = 0.4, 0.4, 0.4  -- Default dark gray
                if itemLink then
                    local _, _, rarity = GetItemInfo(itemLink)
                    if rarity then
                        borderR, borderG, borderB = C_Item.GetItemQualityColor(rarity)
                    end
                end
                if EllesmereUI and EllesmereUI.PanelPP then
                    EllesmereUI.PanelPP.SetBorderColor(slot, borderR, borderG, borderB, 1)
                end
            end
        end
    end

    -- Listen for inventory changes and update borders
    local inventoryFrame = CreateFrame("Frame")
    inventoryFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    inventoryFrame:SetScript("OnEvent", function(self, event, unit)
        if event == "UNIT_INVENTORY_CHANGED" and unit == "player" then
            UpdateSlotBorders()
        end
    end)

    -- Socket icon creation and display logic
    local function GetOrCreateSocketIcons(slot, side, slotIndex)
        if slot._euiCharSocketsIcons then return slot._euiCharSocketsIcons end

        slot._euiCharSocketsIcons = {}
        slot._euiCharSocketsBtns = {}
        slot._gemLinks = {}

        for i = 1, 4 do  -- Max 4 sockets per item
            local icon = globalSocketContainer:CreateTexture(nil, "OVERLAY")
            icon:SetSize(16, 16)
            icon:Hide()
            slot._euiCharSocketsIcons[i] = icon

            -- Create invisible button for gem tooltip
            local socketBtn = CreateFrame("Button", nil, globalSocketContainer)
            socketBtn:SetSize(16, 16)
            socketBtn:EnableMouse(true)
            socketBtn:Hide()
            slot._euiCharSocketsBtns[i] = socketBtn
        end

        slot._euiCharSocketsSide = side
        slot._euiCharSocketsSlotIndex = slotIndex

        return slot._euiCharSocketsIcons
    end

    -- Update socket icons for all slots
    local function UpdateSocketIcons(slotName)
        local slot = _G[slotName]
        if not slot then return end

        local slotIndex = slot:GetID()
        local side = tContains(leftColumnSlots, slotName) and "RIGHT" or "LEFT"

        local socketIcons = GetOrCreateSocketIcons(slot, side, slotIndex)

        local link = GetInventoryItemLink("player", slotIndex)
        if not link then
            for _, icon in ipairs(socketIcons) do icon:Hide() end
            return
        end

        -- Create tooltip to extract socket textures
        local tooltip = CreateFrame("GameTooltip", "EUI_CharSheet_SocketTooltip_" .. slotName, nil, "GameTooltipTemplate")
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:SetInventoryItem("player", slotIndex)

        -- Extract socket textures from tooltip
        local socketTextures = {}
        for i = 1, 10 do
            local texture = _G["EUI_CharSheet_SocketTooltip_" .. slotName .. "Texture" .. i]
            if texture and texture:IsShown() then
                local tex = texture:GetTexture() or texture:GetTextureFileID()
                if tex then
                    table.insert(socketTextures, tex)
                end
            end
        end

        tooltip:Hide()

        -- Extract gem links directly from item link
        slot._gemLinks = {}
        local itemLink = GetInventoryItemLink("player", slotIndex)
        if itemLink then
            -- Item link format: |cff...|Hitem:itemID:enchant:gem1:gem2:gem3:gem4:...|h[Name]|h|r
            -- Extract the item data part
            local itemData = string.match(itemLink, "|H(item:[^|]+)|h")
            if itemData then
                local parts = {}
                for part in string.gmatch(itemData, "([^:]+)") do
                    table.insert(parts, part)
                end

                -- parts[1] = "item", parts[2] = itemID, parts[3] = enchantID, parts[4-7] = gem IDs
                if #parts >= 4 then
                    for i = 4, 7 do
                        local gemID = tonumber(parts[i])
                        if gemID and gemID > 0 then
                            -- Create a gem link from the ID
                            local gemName = GetItemInfo(gemID)
                            if gemName then
                                -- Create a valid link: |cff...|Hitem:gemID|h[Name]|h|r
                                local gemLink = "|cff9d9d9d|Hitem:" .. gemID .. "|h[" .. gemName .. "]|h|r"
                                table.insert(slot._gemLinks, gemLink)
                            end
                        end
                    end
                end
            end
        end

        -- Position and show socket icons
        if #socketTextures > 0 then
            for i, icon in ipairs(socketIcons) do
                if socketTextures[i] then
                    icon:SetTexture(socketTextures[i])
                    icon:SetScale(1)

                    -- Position icons based on column
                    if side == "LEFT" then
                        icon:SetPoint("RIGHT", slot, "RIGHT", 20, 0 - (i-1)*18)
                    else
                        icon:SetPoint("LEFT", slot, "LEFT", -20, 0 - (i-1)*18)
                    end
                    icon:Show()

                    -- Position button wrapper
                    local btn = slot._euiCharSocketsBtns[i]
                    btn:SetPoint("CENTER", icon, "CENTER")
                    btn:Show()
                else
                    icon:Hide()
                    local btn = slot._euiCharSocketsBtns[i]
                    if btn then btn:Hide() end
                end
            end

            -- Setup tooltip scripts for all gem buttons
            for i, btn in ipairs(slot._euiCharSocketsBtns) do
                btn:SetScript("OnEnter", function(self)
                    if slot._gemLinks[i] then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink(slot._gemLinks[i])
                        GameTooltip:Show()
                    end
                end)
                btn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end
        else
            for _, icon in ipairs(socketIcons) do
                icon:Hide()
            end
            for _, btn in ipairs(slot._euiCharSocketsBtns or {}) do
                btn:Hide()
            end
        end
    end

    -- Refresh socket icons for all slots
    local function RefreshAllSocketIcons()
        for _, slotName in ipairs(itemSlots) do
            UpdateSocketIcons(slotName)
        end
    end

    -- Hook into equipment changes
    local socketWatcher = CreateFrame("Frame")
    socketWatcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    socketWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    socketWatcher:SetScript("OnEvent", function()
        if EllesmereUIDB and EllesmereUIDB.themedCharacterSheet then
            -- Only refresh if on character tab and frame is shown
            local isCharacterTab = (frame.selectedTab or 1) == 1
            if frame:IsShown() and isCharacterTab then
                C_Timer.After(0.1, RefreshAllSocketIcons)
            end
        end
    end)

    -- Hook frame show/hide
    frame:HookScript("OnShow", function()
        -- Only refresh sockets and show container if on character tab
        local isCharacterTab = (frame.selectedTab or 1) == 1
        if isCharacterTab then
            RefreshAllSocketIcons()
            globalSocketContainer:Show()
        else
            globalSocketContainer:Hide()
        end
        -- Reset to Stats panel on open
        if statsPanel and CharacterFrame._titlesPanel and CharacterFrame._equipPanel then
            statsPanel:Show()
            CharacterFrame._titlesPanel:Hide()
            CharacterFrame._equipPanel:Hide()
        end
    end)

    frame:HookScript("OnHide", function()
        globalSocketContainer:Hide()
    end)


    -- Create reusable tooltip for enchant scanning
    local enchantTooltip = CreateFrame("GameTooltip", "EUICharacterSheetEnchantTooltip", nil, "GameTooltipTemplate")
    enchantTooltip:SetOwner(UIParent, "ANCHOR_NONE")

    -- Cache item info (ID, level, upgrade track) to update when items change
    local itemCache = {}

    -- Slots that can have enchants in current expansion
    local ENCHANT_SLOTS = {
        [INVSLOT_HEAD] = true,
        [INVSLOT_SHOULDER] = true,
        [INVSLOT_BACK] = false,
        [INVSLOT_CHEST] = true,
        [INVSLOT_WRIST] = false,
        [INVSLOT_LEGS] = true,
        [INVSLOT_FEET] = true,
        [INVSLOT_FINGER1] = true,
        [INVSLOT_FINGER2] = true,
        [INVSLOT_MAINHAND] = true,
    }

    -- Function to update enchant text and upgrade track for a slot
    local function UpdateSlotInfo(slotName)
        local slot = _G[slotName]
        if not slot then return end

        local itemLink = GetInventoryItemLink("player", slot:GetID())
        local itemLevel = ""
        local enchantText = ""
        local upgradeTrackText = ""
        local upgradeTrackColor = { r = 1, g = 1, b = 1 }
        local itemQuality = nil
        local slotID = slot:GetID()
        local canHaveEnchant = ENCHANT_SLOTS[slotID]

        if itemLink then
            local _, _, quality, ilvl = GetItemInfo(itemLink)
            itemLevel = ilvl or ""
            itemQuality = quality

            -- Get enchant and upgrade track from tooltip
            enchantTooltip:SetInventoryItem("player", slot:GetID())
            for i = 1, enchantTooltip:NumLines() do
                local textLeft = _G["EUICharacterSheetEnchantTooltipTextLeft" .. i]:GetText() or ""

                -- Get enchant text
                if textLeft:match("Enchanted:") then
                    enchantText = textLeft:gsub("Enchanted:%s*", "")
                    enchantText = enchantText:gsub("^Enchant%s+[^-]+%s*-%s*", "")
                end

                -- Get upgrade track
                if textLeft:match("Upgrade Level:") then
                    local trackInfo = textLeft:gsub("Upgrade Level:%s*", "")
                    local trk, nums = trackInfo:match("^(%w+)%s+(.+)$")

                    if trk and nums then
                        -- Map track types to short names and colors
                        if trk == "Champion" then
                            upgradeTrackText = "(Champion " .. nums .. ")"
                            upgradeTrackColor = { r = 0.00, g = 0.44, b = 0.87 }  -- blue
                        elseif trk:match("Myth") then
                            upgradeTrackText = "(Myth " .. nums .. ")"
                            upgradeTrackColor = { r = 1.00, g = 0.50, b = 0.00 }  -- orange
                        elseif trk:match("Hero") then
                            upgradeTrackText = "(Hero " .. nums .. ")"
                            upgradeTrackColor = { r = 1.00, g = 0.30, b = 1.00 }  -- purple
                        elseif trk:match("Veteran") then
                            upgradeTrackText = "(Veteran " .. nums .. ")"
                            upgradeTrackColor = { r = 0.12, g = 1.00, b = 0.00 }  -- green
                        elseif trk:match("Adventurer") then
                            upgradeTrackText = "(Adventurer " .. nums .. ")"
                            upgradeTrackColor = { r = 1.00, g = 1.00, b = 1.00 }  -- white
                        elseif trk:match("Delve") or trk:match("Explorer") then
                            upgradeTrackText = "(" .. trk .. " " .. nums .. ")"
                            upgradeTrackColor = { r = 0.62, g = 0.62, b = 0.62 }  -- gray
                        end
                    end
                end
            end
        end

        -- Update itemlevel label with optional rarity color
        if slot._itemLevelLabel then
            -- Check if itemlevel is enabled (default: true)
            local showItemLevel = (not EllesmereUIDB) or (EllesmereUIDB.showItemLevel ~= false)

            if showItemLevel then
                slot._itemLevelLabel:SetText(tostring(itemLevel) or "")
                slot._itemLevelLabel:Show()

                -- Determine color to use
                local displayColor
                if EllesmereUIDB and EllesmereUIDB.charSheetItemLevelUseColor and EllesmereUIDB.charSheetItemLevelColor then
                    -- Use custom color if enabled
                    displayColor = EllesmereUIDB.charSheetItemLevelColor
                else
                    -- Use rarity color by default, unless explicitly disabled
                    if (not EllesmereUIDB or EllesmereUIDB.charSheetColorItemLevel ~= false) and itemQuality then
                        local r, g, b = GetItemQualityColor(itemQuality)
                        displayColor = { r = r, g = g, b = b }
                    else
                        displayColor = { r = 1, g = 1, b = 1 }
                    end
                end

                slot._itemLevelLabel:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 0.9)
            else
                slot._itemLevelLabel:Hide()
            end
        end

        -- Update enchant label
        if slot._enchantLabel then
            -- Check if enchants are enabled (default: true)
            local showEnchants = (not EllesmereUIDB) or (EllesmereUIDB.showEnchants ~= false)

            if showEnchants then
                -- Check if enchant is missing (only for slots that can have enchants)
                local isMissing = canHaveEnchant and itemLink and (enchantText == "" or not enchantText)

                if isMissing then
                    slot._enchantLabel:SetText("<missing enchant>")
                    slot._enchantLabel:Show()
                    -- Red for missing enchant
                    slot._enchantLabel:SetTextColor(1, 0, 0, 1)
                elseif enchantText and enchantText ~= "" then
                    slot._enchantLabel:SetText(enchantText)
                    slot._enchantLabel:Show()

                    -- Determine color to use
                    local displayColor
                    if EllesmereUIDB and EllesmereUIDB.charSheetEnchantUseColor and EllesmereUIDB.charSheetEnchantColor then
                        -- Use custom color if enabled
                        displayColor = EllesmereUIDB.charSheetEnchantColor
                    else
                        -- Use default white color
                        displayColor = { r = 1, g = 1, b = 1 }
                    end
                    slot._enchantLabel:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 1)
                else
                    slot._enchantLabel:Hide()
                end
            else
                slot._enchantLabel:Hide()
            end
        end

        -- Update upgrade track label
        if slot._upgradeTrackLabel then
            -- Check if upgradetrack is enabled (default: true)
            local showUpgradeTrack = (not EllesmereUIDB) or (EllesmereUIDB.showUpgradeTrack ~= false)

            if showUpgradeTrack then
                slot._upgradeTrackLabel:SetText(upgradeTrackText or "")
                slot._upgradeTrackLabel:Show()

                -- Determine color to use
                local displayColor
                if EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackUseColor and EllesmereUIDB.charSheetUpgradeTrackColor then
                    -- Use custom color if enabled
                    displayColor = EllesmereUIDB.charSheetUpgradeTrackColor
                else
                    -- Use original rarity color by default
                    displayColor = upgradeTrackColor
                end

                slot._upgradeTrackLabel:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 0.8)
            else
                slot._upgradeTrackLabel:Hide()
            end
        end
    end

    -- Monitor and update only when items change (including upgrade level)
    if not frame._itemLevelMonitor then
        frame._itemLevelMonitor = CreateFrame("Frame")
        frame._itemLevelMonitor:SetScript("OnUpdate", function()
            if not (EllesmereUIDB and EllesmereUIDB.themedCharacterSheet) then
                return
            end
            if frame and frame:IsShown() then
                for _, slotName in ipairs(itemSlots) do
                    -- Get full item link (includes itemlevel and upgrade info)
                    local itemLink = GetInventoryItemLink("player", _G[slotName]:GetID())

                    -- Compare full link to detect changes in itemlevel or upgrade track
                    if itemCache[slotName] ~= itemLink then
                        itemCache[slotName] = itemLink
                        UpdateSlotInfo(slotName)
                    end
                end
            end
        end)
    end
end

-- Get item rarity color from link
local function GetRarityColorFromLink(itemLink)
    if not itemLink then
        return 0.9, 0.9, 0.9, 1  -- Default gray
    end

    local itemRarity = select(3, GetItemInfo(itemLink))
    if not itemRarity then
        return 0.9, 0.9, 0.9, 1
    end

    -- WoW standard rarity colors
    local rarityColors = {
        [0] = { 0.62, 0.62, 0.62 },  -- Poor
        [1] = { 1, 1, 1 },            -- Common
        [2] = { 0.12, 1, 0 },         -- Uncommon
        [3] = { 0, 0.44, 0.87 },      -- Rare
        [4] = { 0.64, 0.21, 0.93 },   -- Epic
        [5] = { 1, 0.5, 0 },          -- Legendary
        [6] = { 0.9, 0.8, 0.5 },      -- Artifact
        [7] = { 0.9, 0.8, 0.5 },      -- Heirloom
    }

    local color = rarityColors[itemRarity] or rarityColors[1]
    return color[1], color[2], color[3], 1
end

-- Style a character slot with rarity-based border
local function SkinCharacterSlot(slotName, slotID)
    local slot = _G[slotName]
    if not slot or slot._ebsSkinned then return end
    slot._ebsSkinned = true

    -- Hide Blizzard IconBorder
    if slot.IconBorder then
        slot.IconBorder:Hide()
    end

    -- Adjust IconTexture
    local iconTexture = _G[slotName .. "IconTexture"]
    if iconTexture then
        iconTexture:SetTexCoord(0.07, 0.07, 0.07, 0.93, 0.93, 0.07, 0.93, 0.93)
    end

    -- Test: Hide CharacterHandsSlot completely
    if slotName == "CharacterHandsSlot" then
        slot:Hide()
    end

    -- Hide NormalTexture
    local normalTexture = _G[slotName .. "NormalTexture"]
    if normalTexture then
        normalTexture:Hide()
    end

    -- EUI-style background for the slot
    local slotBg = slot:CreateTexture(nil, "BACKGROUND", nil, -5)
    slotBg:SetAllPoints(slot)
    slotBg:SetColorTexture(0.5, 0.5, 0.5, 0.7)  -- Gray background with transparency
    slot._slotBg = slotBg

    -- Create custom border on the slot using PP.CreateBorder
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(slot, 1, 1, 1, 0.4, 2, "OVERLAY", 7)
    end
end

-- Main function to apply themed character sheet
local function ApplyThemedCharacterSheet()
    if not (EllesmereUIDB and EllesmereUIDB.themedCharacterSheet) then
        return
    end

    if CharacterFrame then
        SkinCharacterSheet()
    end
end

-- Register the feature
if EllesmereUI then
    EllesmereUI.ApplyThemedCharacterSheet = ApplyThemedCharacterSheet

    -- Setup at PLAYER_LOGIN to register drag hooks early
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        if CharacterFrame then
            -- Setup drag functionality at login (before first open)
            CharacterFrame:SetMovable(true)
            CharacterFrame:SetClampedToScreen(true)
            local _ebsDragging = false

            CharacterFrame:SetScript("OnMouseDown", function(btn, button)
                if button ~= "LeftButton" then return end
                if not IsShiftKeyDown() and not IsControlKeyDown() then return end
                _ebsDragging = IsShiftKeyDown() and "save" or "temp"
                btn:StartMoving()
            end)

            CharacterFrame:SetScript("OnMouseUp", function(btn, button)
                if button ~= "LeftButton" or not _ebsDragging then return end
                btn:StopMovingOrSizing()
                _ebsDragging = false
            end)

            -- Hook styling on OnShow
            CharacterFrame:HookScript("OnShow", ApplyThemedCharacterSheet)
            ApplyThemedCharacterSheet()

            -- Function to detect and set active equipment set
            local function UpdateActiveEquipmentSet()
                local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
                if setIDs then
                    for _, setID in ipairs(setIDs) do
                        local setItems = GetEquipmentSetItemIDs(setID)
                        if setItems then
                            local allMatch = true
                            for slotIndex, itemID in pairs(setItems) do
                                if itemID ~= 0 then
                                    local currentItemID = GetInventoryItemID("player", slotIndex)
                                    if currentItemID ~= itemID then
                                        allMatch = false
                                        break
                                    end
                                end
                            end
                            if allMatch then
                                activeEquipmentSetID = setID
                                return
                            end
                        end
                    end
                end
                activeEquipmentSetID = nil
            end

            -- Auto-equip equipment set when spec changes
            local specChangeFrame = CreateFrame("Frame")
            local lastSpecIndex = GetSpecialization()
            specChangeFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            specChangeFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
            specChangeFrame:SetScript("OnEvent", function(self, event)
                if event == "EQUIPMENT_SETS_CHANGED" then
                    -- Update active set when equipment changes
                    -- UpdateActiveEquipmentSet()  -- API no longer available in current WoW version
                    -- RefreshEquipmentSets()  -- Function not in scope here
                    if CharacterFrame and CharacterFrame:IsShown() and CharacterFrame._equipPanel and CharacterFrame._equipPanel:IsShown() then
                        -- Equipment panel will be refreshed by the equipSetChangeFrame handler
                    end
                else
                    -- Auto-equip when spec actually changes (not just event noise)
                    local currentSpecIndex = GetSpecialization()
                    if currentSpecIndex ~= lastSpecIndex then
                        lastSpecIndex = currentSpecIndex
                        local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
                        if setIDs then
                            for _, setID in ipairs(setIDs) do
                                local assignedSpec = C_EquipmentSet.GetEquipmentSetAssignedSpec(setID)
                                if assignedSpec then
                                    if assignedSpec == currentSpecIndex then
                                        C_EquipmentSet.UseEquipmentSet(setID)
                                        activeEquipmentSetID = setID
                                        if EllesmereUIDB then
                                            EllesmereUIDB.lastEquippedSet = setID
                                        end
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end)

            -- Initialize active set on login
            local loginFrame = CreateFrame("Frame")
            loginFrame:RegisterEvent("PLAYER_LOGIN")
            loginFrame:SetScript("OnEvent", function()
                loginFrame:UnregisterEvent("PLAYER_LOGIN")
                -- Restore last equipped set if available
                if EllesmereUIDB and EllesmereUIDB.lastEquippedSet then
                    activeEquipmentSetID = EllesmereUIDB.lastEquippedSet
                end
            end)
        end
    end)
end

-- Function to apply character sheet text size settings
function EllesmereUI._applyCharSheetTextSizes()
    if not CharacterFrame then return end

    local itemLevelSize = EllesmereUIDB and EllesmereUIDB.charSheetItemLevelSize or 11
    local upgradeTrackSize = EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackSize or 11
    local enchantSize = EllesmereUIDB and EllesmereUIDB.charSheetEnchantSize or 9

    local itemLevelShadow = EllesmereUIDB and EllesmereUIDB.charSheetItemLevelShadow or false
    local itemLevelOutline = EllesmereUIDB and EllesmereUIDB.charSheetItemLevelOutline or false
    local upgradeTrackShadow = EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackShadow or false
    local upgradeTrackOutline = EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackOutline or false
    local enchantShadow = EllesmereUIDB and EllesmereUIDB.charSheetEnchantShadow or false
    local enchantOutline = EllesmereUIDB and EllesmereUIDB.charSheetEnchantOutline or false

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT

    -- Update all slot labels
    local itemSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterWristSlot", "CharacterHandsSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot then
            if slot._itemLevelLabel then
                local flags = ""
                if itemLevelOutline then
                    flags = "OUTLINE"
                end
                slot._itemLevelLabel:SetFont(fontPath, itemLevelSize, flags)
                -- Apply shadow effect if enabled
                if itemLevelShadow then
                    slot._itemLevelLabel:SetShadowColor(0, 0, 0, 1)
                    slot._itemLevelLabel:SetShadowOffset(1, -1)
                else
                    slot._itemLevelLabel:SetShadowColor(0, 0, 0, 0)
                end
            end
            if slot._upgradeTrackLabel then
                local flags = ""
                if upgradeTrackOutline then
                    flags = "OUTLINE"
                end
                slot._upgradeTrackLabel:SetFont(fontPath, upgradeTrackSize, flags)
                -- Apply shadow effect if enabled
                if upgradeTrackShadow then
                    slot._upgradeTrackLabel:SetShadowColor(0, 0, 0, 1)
                    slot._upgradeTrackLabel:SetShadowOffset(1, -1)
                else
                    slot._upgradeTrackLabel:SetShadowColor(0, 0, 0, 0)
                end
            end
            if slot._enchantLabel then
                local flags = ""
                if enchantOutline then
                    flags = "OUTLINE"
                end
                slot._enchantLabel:SetFont(fontPath, enchantSize, flags)
                -- Apply shadow effect if enabled
                if enchantShadow then
                    slot._enchantLabel:SetShadowColor(0, 0, 0, 1)
                    slot._enchantLabel:SetShadowOffset(1, -1)
                else
                    slot._enchantLabel:SetShadowColor(0, 0, 0, 0)
                end
            end
        end
    end
end

-- Function to recolor item level labels based on rarity setting
function EllesmereUI._applyCharSheetItemColors()
    if not CharacterFrame then return end

    local itemSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterWristSlot", "CharacterHandsSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and slot._itemLevelLabel then
            local itemLink = GetInventoryItemLink("player", slot:GetID())
            if itemLink then
                local _, _, quality = GetItemInfo(itemLink)
                -- Use rarity color by default, unless explicitly disabled
                if (not EllesmereUIDB or EllesmereUIDB.charSheetColorItemLevel ~= false) and quality then
                    local r, g, b = GetItemQualityColor(quality)
                    slot._itemLevelLabel:SetTextColor(r, g, b, 0.9)
                else
                    slot._itemLevelLabel:SetTextColor(1, 1, 1, 0.9)
                end
            else
                slot._itemLevelLabel:SetTextColor(1, 1, 1, 0.9)
            end
        end
    end
end

-- Function to refresh category colors when changed in options
function EllesmereUI._refreshCharacterSheetColors()
    local charFrame = CharacterFrame
    if not charFrame or not charFrame._statsSections then return end

    -- Default category colors
    local DEFAULT_CATEGORY_COLORS = {
        Attributes = { r = 0.047, g = 0.824, b = 0.616 },
        ["Secondary Stats"] = { r = 0.471, g = 0.255, b = 0.784 },
        Attack = { r = 1, g = 0.353, b = 0.122 },
        Defense = { r = 0.247, g = 0.655, b = 1 },
        Crests = { r = 1, g = 0.784, b = 0.341 },
    }

    -- Helper to get category color
    local function GetCategoryColor(title)
        -- Check if custom color is enabled for this category
        local useCustom = EllesmereUIDB and EllesmereUIDB.statCategoryUseColor and EllesmereUIDB.statCategoryUseColor[title]
        if useCustom then
            local custom = EllesmereUIDB and EllesmereUIDB.statCategoryColors and EllesmereUIDB.statCategoryColors[title]
            if custom then return custom end
        end
        return DEFAULT_CATEGORY_COLORS[title] or { r = 1, g = 1, b = 1 }
    end

    -- Update each section's colors
    for _, sectionData in ipairs(charFrame._statsSections) do
        local categoryName = sectionData.sectionTitle
        local newColor = GetCategoryColor(categoryName)

        -- Update title color
        if sectionData.titleFS then
            sectionData.titleFS:SetTextColor(newColor.r, newColor.g, newColor.b, 1)
        end

        -- Update bars
        if sectionData.leftBar then
            sectionData.leftBar:SetColorTexture(newColor.r, newColor.g, newColor.b, 0.8)
        end
        if sectionData.rightBar then
            sectionData.rightBar:SetColorTexture(newColor.r, newColor.g, newColor.b, 0.8)
        end

        -- Update stat values
        for _, stat in ipairs(sectionData.stats) do
            if stat.value then
                stat.value:SetTextColor(newColor.r, newColor.g, newColor.b, 1)
            end
        end
    end
end

-- Function to refresh upgrade track visibility when toggle changes
function EllesmereUI._refreshUpgradeTrackVisibility()
    local itemSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterWristSlot", "CharacterHandsSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }

    local showUpgradeTrack = (not EllesmereUIDB) or (EllesmereUIDB.showUpgradeTrack ~= false)

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and slot._upgradeTrackLabel then
            if showUpgradeTrack then
                slot._upgradeTrackLabel:Show()
            else
                slot._upgradeTrackLabel:Hide()
            end
        end
    end
end

-- Function to refresh enchants visibility when toggle changes
function EllesmereUI._refreshEnchantsVisibility()
    local itemSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterWristSlot", "CharacterHandsSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }

    local showEnchants = (not EllesmereUIDB) or (EllesmereUIDB.showEnchants ~= false)

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and slot._enchantLabel then
            if showEnchants then
                slot._enchantLabel:Show()
            else
                slot._enchantLabel:Hide()
            end
        end
    end
end

-- Function to refresh enchants colors
function EllesmereUI._refreshEnchantsColors()
    local itemSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterWristSlot", "CharacterHandsSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and slot._enchantLabel then
            -- Determine color to use
            local displayColor
            if EllesmereUIDB and EllesmereUIDB.charSheetEnchantUseColor and EllesmereUIDB.charSheetEnchantColor then
                -- Use custom color if enabled
                displayColor = EllesmereUIDB.charSheetEnchantColor
            else
                -- Use default color
                displayColor = { r = 1, g = 1, b = 1 }
            end

            slot._enchantLabel:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 1)
        end
    end
end

-- Function to refresh item level visibility when toggle changes
function EllesmereUI._refreshItemLevelVisibility()
    local itemSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterWristSlot", "CharacterHandsSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }

    local showItemLevel = (not EllesmereUIDB) or (EllesmereUIDB.showItemLevel ~= false)

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and slot._itemLevelLabel then
            if showItemLevel then
                slot._itemLevelLabel:Show()
            else
                slot._itemLevelLabel:Hide()
            end
        end
    end
end

-- Function to refresh item level colors
function EllesmereUI._refreshItemLevelColors()
    local itemSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterWristSlot", "CharacterHandsSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and slot._itemLevelLabel then
            -- Determine color to use
            local displayColor
            if EllesmereUIDB and EllesmereUIDB.charSheetItemLevelUseColor and EllesmereUIDB.charSheetItemLevelColor then
                -- Use custom color if enabled
                displayColor = EllesmereUIDB.charSheetItemLevelColor
            else
                -- Use rarity color by default, unless explicitly disabled
                local itemLink = GetInventoryItemLink("player", slot:GetID())
                if itemLink and (not EllesmereUIDB or EllesmereUIDB.charSheetColorItemLevel ~= false) then
                    local _, _, quality = GetItemInfo(itemLink)
                    if quality then
                        local r, g, b = GetItemQualityColor(quality)
                        displayColor = { r = r, g = g, b = b }
                    else
                        displayColor = { r = 1, g = 1, b = 1 }
                    end
                else
                    displayColor = { r = 1, g = 1, b = 1 }
                end
            end

            slot._itemLevelLabel:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 0.9)
        end
    end
end

-- Function to refresh upgrade track colors
function EllesmereUI._refreshUpgradeTrackColors()
    local itemSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterWristSlot", "CharacterHandsSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and slot._upgradeTrackLabel then
            local itemLink = GetInventoryItemLink("player", slot:GetID())
            if itemLink then
                -- Get the upgrade track text to determine the color
                local enchantTooltip = CreateFrame("GameTooltip", "EUICharacterSheetEnchantTooltip", nil, "GameTooltipTemplate")
                enchantTooltip:SetOwner(UIParent, "ANCHOR_NONE")
                enchantTooltip:SetInventoryItem("player", slot:GetID())

                local upgradeTrackColor = { r = 1, g = 1, b = 1 }
                for i = 1, enchantTooltip:NumLines() do
                    local textLeft = _G["EUICharacterSheetEnchantTooltipTextLeft" .. i]:GetText() or ""
                    if textLeft:match("Upgrade Level:") then
                        local trackInfo = textLeft:gsub("Upgrade Level:%s*", "")
                        local trk, nums = trackInfo:match("^(%w+)%s+(.+)$")

                        if trk and nums then
                            if trk == "Champion" then
                                upgradeTrackColor = { r = 0.00, g = 0.44, b = 0.87 }
                            elseif trk:match("Myth") then
                                upgradeTrackColor = { r = 1.00, g = 0.50, b = 0.00 }
                            elseif trk:match("Hero") then
                                upgradeTrackColor = { r = 1.00, g = 0.30, b = 1.00 }
                            elseif trk:match("Veteran") then
                                upgradeTrackColor = { r = 0.12, g = 1.00, b = 0.00 }
                            elseif trk:match("Adventurer") then
                                upgradeTrackColor = { r = 1.00, g = 1.00, b = 1.00 }
                            elseif trk:match("Delve") or trk:match("Explorer") then
                                upgradeTrackColor = { r = 0.62, g = 0.62, b = 0.62 }
                            end
                        end
                        break
                    end
                end

                -- Apply color
                local displayColor
                if EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackUseColor and EllesmereUIDB.charSheetUpgradeTrackColor then
                    displayColor = EllesmereUIDB.charSheetUpgradeTrackColor
                else
                    displayColor = upgradeTrackColor
                end

                slot._upgradeTrackLabel:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 0.8)
            end
        end
    end
end
