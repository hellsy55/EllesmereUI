-------------------------------------------------------------------------------
--  Themed Inspect Sheet
--  Mirrors the Character Sheet skinning for inspected characters
-------------------------------------------------------------------------------
local ADDON_NAME = ...
local skinned = false


-- ============================================================================
-- Item Styling Helpers (copied from CharacterSheet, adapted for "inspect")
-- ============================================================================

-- Upgrade track colors (shared, immutable)
local _TRACK_WHITE  = { r = 1.00, g = 1.00, b = 1.00 }
local _TRACK_CHAMP  = { r = 0.00, g = 0.44, b = 0.87 }
local _TRACK_MYTH   = { r = 1.00, g = 0.50, b = 0.00 }
local _TRACK_HERO   = { r = 1.00, g = 0.30, b = 1.00 }
local _TRACK_VET    = { r = 0.12, g = 1.00, b = 0.00 }
local _TRACK_GRAY   = { r = 0.62, g = 0.62, b = 0.62 }

local function EUI_GetUpgradeTrack(itemLink)
    if not itemLink or not (C_Item and C_Item.GetItemUpgradeInfo) then
        return "", _TRACK_WHITE
    end
    local info = C_Item.GetItemUpgradeInfo(itemLink)
    if not info then return "", _TRACK_WHITE end
    local trk = info.trackString or ""
    local cur, maxL = info.currentLevel, info.maxLevel
    local text = (cur and maxL and maxL > 0) and ("(" .. cur .. "/" .. maxL .. ")") or ""
    local color = _TRACK_WHITE
    if     trk == "Champion"     then color = _TRACK_CHAMP
    elseif trk:match("Myth")     then color = _TRACK_MYTH
    elseif trk:match("Hero")     then color = _TRACK_HERO
    elseif trk:match("Veteran")  then color = _TRACK_VET
    elseif trk:match("Adventurer") then color = _TRACK_WHITE
    elseif trk:match("Delve") or trk:match("Explorer") then color = _TRACK_GRAY
    end
    return text, color
end

-- Enchant caching
local _enchantNameCache = {}
local _ENCHANT_LINE_TYPE = (Enum and Enum.TooltipDataLineType
    and (Enum.TooltipDataLineType.ItemEnchantmentPermanent
         or Enum.TooltipDataLineType.ItemEnchant))
    or 15

local _ENCHANT_PATTERN
do
    local fmt = ENCHANTED_TOOLTIP_LINE
    if fmt then
        local head, tail = fmt:match("^(.-)%%s(.*)$")
        if head then
            local function esc(s)
                return (s:gsub("([%(%)%.%[%]%^%$%*%+%-%?%%])", "%%%1"))
            end
            _ENCHANT_PATTERN = "^" .. esc(head) .. "(.+)" .. esc(tail) .. "$"
        end
    end
end

local function _stripLineEscapes(s)
    if not s then return "" end
    s = s:gsub("|cn.-:(.-)|r", "%1")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("^%s*[%+&]%s*", "")
    return s
end

local function EUI_ScanInventoryItem_Inspect(slotID)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local inspectUnit = InspectFrame and InspectFrame.unit
    if not inspectUnit then return nil end
    local data = C_TooltipInfo.GetInventoryItem(inspectUnit, slotID)
    if not data then return nil end
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(data)
    end
    return data
end

local function EUI_GetEnchantText_Inspect(slotID)
    if not slotID then return "" end
    local inspectUnit = InspectFrame and InspectFrame.unit
    if not inspectUnit then return "" end
    local link = GetInventoryItemLink(inspectUnit, slotID)
    if not link then return "" end

    local enchantID = tonumber(link:match("item:%d+:(%d+)"))
    if not enchantID or enchantID == 0 then return "" end

    local cached = _enchantNameCache[enchantID]
    if cached ~= nil then return cached end

    local data = EUI_ScanInventoryItem_Inspect(slotID)
    if not (data and data.lines) then
        _enchantNameCache[enchantID] = ""
        return ""
    end

    for _, line in ipairs(data.lines) do
        local raw = _stripLineEscapes(line.leftText or "")
        local matched
        if line.type == _ENCHANT_LINE_TYPE then
            matched = raw
        elseif _ENCHANT_PATTERN then
            matched = raw:match(_ENCHANT_PATTERN)
        else
            matched = raw:match("^Enchanted:%s*(.+)$")
        end
        if matched and matched ~= "" then
            matched = matched:gsub("^Enchant%s+[^-]+%s*-%s*", "")
            _enchantNameCache[enchantID] = matched
            return matched
        end
    end

    _enchantNameCache[enchantID] = ""
    return ""
end

-- Equipment slot lists
local EUI_ALL_SLOTS = {
    "InspectHeadSlot", "InspectNeckSlot", "InspectShoulderSlot", "InspectBackSlot",
    "InspectChestSlot", "InspectShirtSlot", "InspectTabardSlot", "InspectWristSlot",
    "InspectHandsSlot", "InspectWaistSlot", "InspectLegsSlot", "InspectFeetSlot",
    "InspectTrinket0Slot", "InspectTrinket1Slot", "InspectFinger0Slot", "InspectFinger1Slot",
    "InspectMainHandSlot", "InspectSecondaryHandSlot",
}

-- Slot grid layout mapping
local slotGridMap = {
    InspectHeadSlot = {col = 0, row = 0},
    InspectNeckSlot = {col = 0, row = 1},
    InspectShoulderSlot = {col = 0, row = 2},
    InspectBackSlot = {col = 0, row = 3},
    InspectChestSlot = {col = 0, row = 4},
    InspectShirtSlot = {col = 0, row = 5},
    InspectTabardSlot = {col = 0, row = 6},
    InspectWristSlot = {col = 0, row = 7},
    InspectHandsSlot = {col = 1, row = 0},
    InspectWaistSlot = {col = 1, row = 1},
    InspectLegsSlot = {col = 1, row = 2},
    InspectFeetSlot = {col = 1, row = 3},
    InspectFinger0Slot = {col = 1, row = 4},
    InspectFinger1Slot = {col = 1, row = 5},
    InspectTrinket0Slot = {col = 1, row = 6},
    InspectTrinket1Slot = {col = 1, row = 7},
    InspectMainHandSlot = {slot = "MainHand"},
    InspectSecondaryHandSlot = {slot = "SecondaryHand"},
}

-- Function to style a slot with colored border, ilvl, and enchant (uses external textOverlayFrame)
local function EUI_UpdateSlotStyle(slotName, slotID, textOverlayFrame, isRightColumn)
    local slot = _G[slotName]
    if not slot or not textOverlayFrame then
        return
    end

    -- Get the inspect unit from InspectFrame
    local inspectUnit = InspectFrame and InspectFrame.unit
    if not inspectUnit then
        return
    end

    -- Get the item link using the correct API for inspect
    local itemLink = GetInventoryItemLink(inspectUnit, slotID)

    -- Cache the item link in the slot for later use
    slot._euiItemLink = itemLink

    -- Default gray border for empty slots
    local borderR, borderG, borderB = 0.4, 0.4, 0.4

    -- If item exists, get rarity color
    if itemLink then
        local rarity = C_Item.GetItemQualityByID(itemLink)
        if rarity then
            borderR, borderG, borderB = C_Item.GetItemQualityColor(rarity)
        end
    end

    -- Always update border color via SetBorderColor (works whether border exists or not)
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.SetBorderColor(slot, borderR, borderG, borderB, 1)
    end
    slot._euiBorder = true

    -- Add item level label (like CharacterSheet: CENTER with 15px/10px offset)
    if itemLink and not slot._euiILvlText then
        local ilvl = select(4, GetItemInfo(itemLink))
        if ilvl and ilvl > 0 then
            local ilvlText = textOverlayFrame:CreateFontString(nil, "OVERLAY")
            if not ilvlText then
                return
            end
            ilvlText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
            ilvlText:SetJustifyH("CENTER")

            -- Position based on slot type (match CharacterSheet logic)
            if slotName == "InspectMainHandSlot" then
                ilvlText:SetPoint("CENTER", slot, "LEFT", -15, 10)
            elseif slotName == "InspectSecondaryHandSlot" then
                ilvlText:SetPoint("CENTER", slot, "RIGHT", 15, 10)
            elseif isRightColumn then
                ilvlText:SetPoint("CENTER", slot, "LEFT", -15, 10)
            else
                ilvlText:SetPoint("CENTER", slot, "RIGHT", 15, 10)
            end

            ilvlText:SetText(ilvl)

            -- Use upgrade track color for item level
            local _, upgradeTrackColor = EUI_GetUpgradeTrack(itemLink)
            ilvlText:SetTextColor(upgradeTrackColor.r, upgradeTrackColor.g, upgradeTrackColor.b, 1)

            slot._euiILvlText = ilvlText
        end
    end

    -- Add enchant icon (like CharacterSheet: LEFT/RIGHT at 5/-5, smaller font)
    if itemLink and not slot._euiEnchantText then
        local enchantText = EUI_GetEnchantText_Inspect(slotID)
        if enchantText and enchantText ~= "" then
            -- Extract only the |A:|a atlas escapes (icons), strip all text
            local icons = {}
            for atlas in enchantText:gmatch("|A:[^|]+|a") do
                icons[#icons + 1] = atlas
            end
            local iconOnly = table.concat(icons, "")

            if iconOnly and iconOnly ~= "" then
                local enchantLabel = textOverlayFrame:CreateFontString(nil, "OVERLAY")
                enchantLabel:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
                enchantLabel:SetTextColor(1, 1, 1, 0.8)

                -- Position based on slot type (match CharacterSheet logic)
                if slotName == "InspectMainHandSlot" then
                    enchantLabel:SetPoint("RIGHT", slot, "LEFT", -5, -5)
                elseif slotName == "InspectSecondaryHandSlot" then
                    enchantLabel:SetPoint("LEFT", slot, "RIGHT", 15, -5)
                elseif isRightColumn then
                    enchantLabel:SetPoint("RIGHT", slot, "LEFT", -5, -5)
                else
                    enchantLabel:SetPoint("LEFT", slot, "RIGHT", 5, -5)
                end

                enchantLabel:SetText(iconOnly)  -- Only the icon, no text

                slot._euiEnchantText = enchantLabel

                -- Create hover frame for tooltip
                local hoverFrame = CreateFrame("Frame", nil, textOverlayFrame)
                hoverFrame:SetSize(20, 20)
                hoverFrame:SetFrameLevel(textOverlayFrame:GetFrameLevel() + 20)

                -- Position based on slot type (match CharacterSheet logic)
                if slotName == "InspectMainHandSlot" then
                    hoverFrame:SetPoint("RIGHT", slot, "LEFT", -5, -5)
                elseif slotName == "InspectSecondaryHandSlot" then
                    hoverFrame:SetPoint("LEFT", slot, "RIGHT", 15, -5)
                elseif isRightColumn then
                    hoverFrame:SetPoint("RIGHT", slot, "LEFT", -5, -5)
                else
                    hoverFrame:SetPoint("LEFT", slot, "RIGHT", 5, -5)
                end
                hoverFrame:EnableMouse(true)

                -- Strip icons and get readable enchant text for tooltip
                local tooltipText = enchantText:gsub("|A:[^|]+|a", ""):gsub("^%s+", ""):gsub("%s+$", "")
                tooltipText = tooltipText:gsub("^.-%s*%-%s*", "")

                hoverFrame:SetScript("OnEnter", function()
                    if tooltipText and tooltipText ~= "" then
                        GameTooltip:SetOwner(hoverFrame, "ANCHOR_RIGHT")
                        GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true)
                        GameTooltip:Show()
                    end
                end)
                hoverFrame:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)

                slot._euiEnchantHoverFrame = hoverFrame
            end
        end
    end

    -- Add upgrade track info (positioned relative to itemlevel like CharacterSheet)
    if itemLink and not slot._euiUpgradeText and slot._euiILvlText then
        local upgradeText, upgradeColor = EUI_GetUpgradeTrack(itemLink)
        if upgradeText and upgradeText ~= "" then
            local upgradeLabel = textOverlayFrame:CreateFontString(nil, "OVERLAY")
            upgradeLabel:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
            upgradeLabel:SetTextColor(upgradeColor.r, upgradeColor.g, upgradeColor.b, 1)
            upgradeLabel:SetJustifyH("CENTER")

            -- Position based on slot type (match CharacterSheet logic)
            if slotName == "InspectMainHandSlot" then
                -- MainHand: upgradeTrack LEFT of itemLevel
                upgradeLabel:SetPoint("RIGHT", slot._euiILvlText, "LEFT", -3, 0)
            elseif slotName == "InspectSecondaryHandSlot" then
                -- SecondaryHand: upgradeTrack RIGHT of itemLevel
                upgradeLabel:SetPoint("LEFT", slot._euiILvlText, "RIGHT", 3, 0)
            elseif isRightColumn then
                -- Right column: upgradeTrack LEFT of itemLevel
                upgradeLabel:SetPoint("RIGHT", slot._euiILvlText, "LEFT", -3, 0)
            else
                -- Left column: upgradeTrack RIGHT of itemLevel
                upgradeLabel:SetPoint("LEFT", slot._euiILvlText, "RIGHT", 3, 0)
            end

            upgradeLabel:SetText(upgradeText)

            slot._euiUpgradeText = upgradeLabel
        end
    end
end

-- Apply tab visibility: show labels only on Tab 1
-- Similar to ApplyTabVisibility in CharacterSheet.lua
-- Takes a boolean parameter: true = show labels (Tab 1), false = hide labels (Tab 2/3)
local function ApplyTabVisibility(showLabels)
    local frame = InspectFrame
    if not frame then return end

    -- Show/hide individual labels based on settings
    local showItemLevel = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowItemLevel ~= false)
    local showUpgradeTrack = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowUpgradeTrack ~= false)
    local showEnchants = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowEnchants ~= false)

    for slotName, _ in pairs(slotGridMap) do
        local slot = _G[slotName]
        if slot then
            -- Only show labels if on Tab 1 and settings allow
            if slot._euiILvlText then
                slot._euiILvlText:SetShown(showLabels and showItemLevel)
            end
            if slot._euiUpgradeText then
                slot._euiUpgradeText:SetShown(showLabels and showUpgradeTrack)
            end
            if slot._euiEnchantText then
                slot._euiEnchantText:SetShown(showLabels and showEnchants)
            end
        end
    end

    -- Hide/show average item level label on MainHandSlot
    if InspectMainHandSlot and InspectMainHandSlot._avgItemLevelLabel then
        local showAverageItemLevel = showLabels and ((not EllesmereUIDB) or (EllesmereUIDB.inspectShowAverageItemLevel ~= false))
        InspectMainHandSlot._avgItemLevelLabel:SetShown(showAverageItemLevel)
    end
end

-- Calculate average item level from inspected player
local function CalculateAverageItemLevel()
    if not InspectFrame or not InspectFrame.unit then
        return 0
    end

    local unit = InspectFrame.unit

    -- Use the proper WoW API for getting inspect item level
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
        if ilvl and ilvl > 0 then
            return ilvl
        end
    end

    return 0
end

local function SkinInspectSheet()
    if skinned then return end
    skinned = true

    local frame = InspectFrame
    if not frame then return end


    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

    -- Create custom background texture FIRST before hiding anything
    if frame._ebsBg then
        frame._ebsBg:Show()
    else
        frame._ebsBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame._ebsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
        frame._ebsBg:SetAllPoints(frame)
    end

    -- Hide Blizzard backgrounds and borders
    for _, elem in ipairs({frame.NineSlice, frame.Background, frame.TitleBg,
                           frame.TopTileStreaks, frame.Portrait, frame.Bg,
                           InspectModelFrameBackgroundOverlay,
                           InspectModelFrameBorderRight, InspectModelFrameBorderLeft,
                           InspectModelFrameBorderBottom, InspectModelFrameBorderTop}) do
        if elem then elem:Hide() end
    end


    -- Style InspectFrameBg with EUI colors
    if InspectFrameBg then
        InspectFrameBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
    end

    -- Style InspectFrameInset.Bg with EUI colors
    if InspectFrameInset and InspectFrameInset.Bg then
        InspectFrameInset.Bg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
    end

    -- Create model background directly on InspectFrame
    if not frame._euiModelBgFrame then
        -- Main background texture
        local bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, 5)
        bgTex:SetAtlas("transmog-locationBG")
        bgTex:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -40)
        bgTex:SetSize(280, 380)

        -- Glow effect at bottom
        local bgGlowTex = frame:CreateTexture(nil, "BACKGROUND", nil, 6)
        bgGlowTex:SetAtlas("transmog-locationBG-glow")
        bgGlowTex:SetPoint("BOTTOMLEFT", bgTex, "BOTTOMLEFT", 0, 0)
        bgGlowTex:SetPoint("BOTTOMRIGHT", bgTex, "BOTTOMRIGHT", 0, 0)
        local GLOW_HEIGHT_RATIO = 386 / 860
        bgGlowTex:SetHeight(math.max(1, bgTex:GetHeight() * GLOW_HEIGHT_RATIO))
        bgGlowTex:SetAlpha(0.5)

        frame._euiModelBg = bgTex
        frame._euiModelBgGlow = bgGlowTex
        frame._euiModelBgFrame = true  -- Just mark it as created
    end

    -- Hide portrait (separate handling to ensure it's fully hidden)
    if InspectFramePortrait then
        InspectFramePortrait:Hide()
        InspectFramePortrait:SetAlpha(0)
    end

    -- Hide TopTileStreaks explicitly
    if frame.TopTileStreaks then
        frame.TopTileStreaks:Hide()
        frame.TopTileStreaks:SetAlpha(0)
    end

    -- Hide InspectModelFrameBorder edges and corners explicitly
    for _, border in ipairs({InspectModelFrameBorderBottom, InspectModelFrameBorderLeft,
                             InspectModelFrameBorderTop, InspectModelFrameBorderRight,
                             InspectModelFrameBorderBottomRight, InspectModelFrameBorderBottomLeft,
                             InspectModelFrameBorderTopRight, InspectModelFrameBorderTopLeft,
                             InspectModelFrameBorderBottom2}) do
        if border then
            border:Hide()
            border:SetAlpha(0)
        end
    end

    -- Hide InspectModelFrameBackgroundOverlay explicitly
    if InspectModelFrameBackgroundOverlay then
        InspectModelFrameBackgroundOverlay:Hide()
        InspectModelFrameBackgroundOverlay:SetAlpha(0)
    end

    -- Hide InspectFrameInset.NineSlice (borders) but keep the frame for background
    if InspectFrameInset then
        if InspectFrameInset.NineSlice then
            InspectFrameInset.NineSlice:Hide()
            InspectFrameInset.NineSlice:SetAlpha(0)
        end
    end

    -- Hide InspectModelFrameBackground corners
    for _, corner in ipairs({InspectModelFrameBackgroundTopLeft, InspectModelFrameBackgroundTopRight,
                             InspectModelFrameBackgroundBotLeft, InspectModelFrameBackgroundBotRight}) do
        if corner then
            corner:Hide()
            corner:SetAlpha(0)
        end
    end

    if frame.PaperDollFrame and frame.PaperDollFrame.InnerBorder then
        for _, name in ipairs({"Top", "Bottom", "Left", "Right", "TopLeft", "TopRight", "BottomLeft", "BottomRight"}) do
            if frame.PaperDollFrame.InnerBorder[name] then
                frame.PaperDollFrame.InnerBorder[name]:Hide()
            end
        end
    end

    -- Hide PVP Frame background elements
    if InspectPVPFrame then
        local numChildren = InspectPVPFrame:GetNumChildren()
        for i = 1, numChildren do
            local child = select(i, InspectPVPFrame:GetChildren())
            if child and not child:GetName() then
                child:Hide()
            end
        end
    end

    -- Hide Guild Frame background elements
    if InspectGuildFrame then
        local numChildren = InspectGuildFrame:GetNumChildren()
        for i = 1, numChildren do
            local child = select(i, InspectGuildFrame:GetChildren())
            if child and not child:GetName() then
                child:Hide()
            end
        end
    end

    -- Hide unnamed decoration frames in main InspectFrame
    local numChildren = frame:GetNumChildren()
    for i = 1, numChildren do
        local child = select(i, frame:GetChildren())
        if child and not child:GetName() and child:GetObjectType() == "Frame" then
            -- Only hide if it's not one of our known frames and not the TitleFrame or title parent
            local isTitleFrame = (frame.TitleFrame and child == frame.TitleFrame)
            local isTitleParent = (_G.inspectFrameTitleText and child == _G.inspectFrameTitleText:GetParent())
            if child ~= frame.PaperDollFrame and child ~= InspectPVPFrame and child ~= InspectGuildFrame
               and not isTitleFrame and not isTitleParent then
                child:Hide()
            end
        end
    end

    -- Add pixel-perfect border to the frame
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(frame, 0.2, 0.2, 0.2, 1, 1, "OVERLAY", 7)
    end

    -- Style close button
    local closeBtn = frame.CloseButton or _G.InspectFrameCloseButton
    if closeBtn then
        if closeBtn.SetNormalTexture then closeBtn:SetNormalTexture("") end
        if closeBtn.SetPushedTexture then closeBtn:SetPushedTexture("") end
        if closeBtn.SetHighlightTexture then closeBtn:SetHighlightTexture("") end
        if closeBtn.SetDisabledTexture then closeBtn:SetDisabledTexture("") end

        for i = 1, select("#", closeBtn:GetRegions()) do
            local region = select(i, closeBtn:GetRegions())
            if region and region:IsObjectType("Texture") then
                region:SetAlpha(0)
            end
        end

        local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT

        if not closeBtn._ebsX then
            closeBtn._ebsX = closeBtn:CreateFontString(nil, "OVERLAY")
            closeBtn._ebsX:SetFont(fontPath, 16, nil)
            closeBtn._ebsX:SetText("x")
            closeBtn._ebsX:SetTextColor(1, 1, 1, 0.75)
            closeBtn._ebsX:SetPoint("CENTER", -2, -3)

            closeBtn:HookScript("OnEnter", function()
                if closeBtn._ebsX then closeBtn._ebsX:SetTextColor(1, 1, 1, 1) end
            end)
            closeBtn:HookScript("OnLeave", function()
                if closeBtn._ebsX then closeBtn._ebsX:SetTextColor(1, 1, 1, 0.75) end
            end)
        end
    end

    -- Style View/Talents Buttons in InspectPaperDollItemsFrame
    local paperDollItemsFrame = InspectPaperDollItemsFrame
    if paperDollItemsFrame then
        local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT

        local function StyleButton(btn, defaultLabel)
            if not btn then return end

            -- Remove all Blizzard textures via methods
            if btn.SetNormalTexture then btn:SetNormalTexture("") end
            if btn.SetPushedTexture then btn:SetPushedTexture("") end
            if btn.SetHighlightTexture then btn:SetHighlightTexture("") end
            if btn.SetDisabledTexture then btn:SetDisabledTexture("") end

            -- Hide texture parts (Left, Middle, Right, and unnamed variants)
            if btn.Left then btn.Left:SetTexture("") end
            if btn.Middle then btn.Middle:SetTexture("") end
            if btn.Right then btn.Right:SetTexture("") end
            if btn.LeftDisabled then btn.LeftDisabled:SetTexture("") end
            if btn.MiddleDisabled then btn.MiddleDisabled:SetTexture("") end
            if btn.RightDisabled then btn.RightDisabled:SetTexture("") end

            -- Hide ALL textures/regions (including unnamed variants like .1611990aeea0)
            for j = 1, select("#", btn:GetRegions()) do
                local region = select(j, btn:GetRegions())
                if region and region:IsObjectType("Texture") then
                    region:SetAlpha(0)
                end
            end

            -- Replace text with our own
            if not btn._eui_styled then
                local blizLabel = btn:GetFontString()
                local labelText = blizLabel and blizLabel:GetText() or defaultLabel
                if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end

                if not btn._label then
                    local label = btn:CreateFontString(nil, "OVERLAY")
                    label:SetFont(fontPath, 10, nil)
                    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
                    label:SetJustifyH("CENTER")
                    label:SetText(labelText)
                    label:SetTextColor(1, 1, 1, 0.6)
                    btn._label = label
                end

                -- Hover effects
                btn:HookScript("OnEnter", function()
                    if btn._label then btn._label:SetTextColor(1, 1, 1, 1) end
                end)
                btn:HookScript("OnLeave", function()
                    if btn._label then btn._label:SetTextColor(1, 1, 1, 0.6) end
                end)

                -- Add pixel-perfect border
                if EllesmereUI and EllesmereUI.PanelPP then
                    EllesmereUI.PanelPP.CreateBorder(btn, 0.4, 0.4, 0.4, 1, 1, "OVERLAY", 7)
                end

                btn._eui_styled = true
            end
        end

        -- Style InspectTalents button explicitly if it exists
        if paperDollItemsFrame.InspectTalents then
            StyleButton(paperDollItemsFrame.InspectTalents, "Talents")
        end

        -- Also style any unnamed buttons found
        local numChildren = paperDollItemsFrame:GetNumChildren()
        for i = 1, numChildren do
            local child = select(i, paperDollItemsFrame:GetChildren())
            if child and child:GetObjectType() == "Button" and not child:GetName() then
                StyleButton(child, "View")
            end
        end
    end

    -- Style ViewButton in InspectPaperDollFrame
    if InspectPaperDollFrame and InspectPaperDollFrame.ViewButton then
        local viewBtn = InspectPaperDollFrame.ViewButton
        local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT

        -- Remove all Blizzard textures via methods
        if viewBtn.SetNormalTexture then viewBtn:SetNormalTexture("") end
        if viewBtn.SetPushedTexture then viewBtn:SetPushedTexture("") end
        if viewBtn.SetHighlightTexture then viewBtn:SetHighlightTexture("") end
        if viewBtn.SetDisabledTexture then viewBtn:SetDisabledTexture("") end

        -- Hide texture parts (Left, Middle, Right, and unnamed variants)
        if viewBtn.Left then viewBtn.Left:SetTexture("") end
        if viewBtn.Middle then viewBtn.Middle:SetTexture("") end
        if viewBtn.Right then viewBtn.Right:SetTexture("") end
        if viewBtn.LeftDisabled then viewBtn.LeftDisabled:SetTexture("") end
        if viewBtn.MiddleDisabled then viewBtn.MiddleDisabled:SetTexture("") end
        if viewBtn.RightDisabled then viewBtn.RightDisabled:SetTexture("") end

        -- Hide ALL textures/regions (including unnamed variants like .160886a3ff0)
        for j = 1, select("#", viewBtn:GetRegions()) do
            local region = select(j, viewBtn:GetRegions())
            if region and region:IsObjectType("Texture") then
                region:SetAlpha(0)
            end
        end

        -- Replace text with our own
        if not viewBtn._eui_styled then
            local blizLabel = viewBtn:GetFontString()
            local labelText = blizLabel and blizLabel:GetText() or "View"
            if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end

            if not viewBtn._label then
                local label = viewBtn:CreateFontString(nil, "OVERLAY")
                label:SetFont(fontPath, 10, nil)
                label:SetPoint("CENTER", viewBtn, "CENTER", 0, 0)
                label:SetJustifyH("CENTER")
                label:SetText(labelText)
                label:SetTextColor(1, 1, 1, 0.6)
                viewBtn._label = label
            end

            -- Hover effects
            viewBtn:HookScript("OnEnter", function()
                if viewBtn._label then viewBtn._label:SetTextColor(1, 1, 1, 1) end
            end)
            viewBtn:HookScript("OnLeave", function()
                if viewBtn._label then viewBtn._label:SetTextColor(1, 1, 1, 0.6) end
            end)

            -- Add pixel-perfect border
            if EllesmereUI and EllesmereUI.PanelPP then
                EllesmereUI.PanelPP.CreateBorder(viewBtn, 0.4, 0.4, 0.4, 1, 1, "OVERLAY", 7)
            end

            viewBtn._eui_styled = true
        end
    end

    -- Hide slot wrapper frames
    for _, slotName in ipairs(EUI_ALL_SLOTS) do
        local frameName = slotName .. "Frame"
        if _G[frameName] then
            _G[frameName]:Hide()
        end
    end

    -- Show actual slot buttons and style them
    for _, slotName in ipairs(EUI_ALL_SLOTS) do
        local slot = _G[slotName]
        if slot then
            slot:Show()

            -- Hide ALL unnamed Texturen in den Slots (die Dekoration)
            local numRegions = slot:GetNumRegions()
            for i = 1, numRegions do
                local region = select(i, slot:GetRegions())
                if region and region:IsObjectType("Texture") then
                    local regionName = region:GetName()
                    -- Hide nur unnamed Texturen (nicht die Icon)
                    if not regionName or regionName ~= (slotName .. "IconTexture") then
                        region:SetAlpha(0)
                    end
                end
            end

            -- Hide Blizzard border and textures
            if slot.IconBorder then
                slot.IconBorder:Hide()
            end
            if slot.IconOverlay then
                slot.IconOverlay:Hide()
            end
            if slot.IconOverlay2 then
                slot.IconOverlay2:Hide()
            end

            -- Crop icon
            if slot.icon then
                slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            end

            local normalTexture = _G[slotName .. "NormalTexture"]
            if normalTexture then
                normalTexture:Hide()
            end

            -- Get item rarity for border color
            local itemLink = GetInventoryItemLink("inspect", slot:GetID())
            local borderR, borderG, borderB = 0.4, 0.4, 0.4  -- Default gray
            if itemLink then
                local _, _, rarity = GetItemInfo(itemLink)
                if rarity then
                    borderR, borderG, borderB = C_Item.GetItemQualityColor(rarity)
                end
            end

            -- Add rarity-colored border
            if EllesmereUI and EllesmereUI.PanelPP then
                EllesmereUI.PanelPP.CreateBorder(slot, borderR, borderG, borderB, 1, 2, "OVERLAY", 7)
            end

            local parent = slot:GetParent()
            if parent then
                parent:Show()
            end
        end
    end

    -- Grid layout: 2 columns, 8 rows
    local cellWidth = 280
    local cellHeight = 41
    local gridStartX = 14
    local gridStartY = -60

    -- Create overlay frame for text labels (above items, transparent, no mouse input)
    local textOverlayFrame = CreateFrame("Frame", "EUI_InspectSheet_TextOverlay", frame)
    textOverlayFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    textOverlayFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    textOverlayFrame:SetFrameLevel(frame:GetFrameLevel() + 10)  -- Ensure it's above the frame
    textOverlayFrame:EnableMouse(false)
    textOverlayFrame:SetAlpha(1)  -- Always visible by default
    textOverlayFrame:Show()
    frame._textOverlayFrame = textOverlayFrame

    -- Position slots and style them
    if InspectPaperDollItemsFrame then
        for slotName, gridPos in pairs(slotGridMap) do
            local slot = _G[slotName]
            if slot then
                -- Skip weapon slots (they have no col/row, positioned separately)
                if not gridPos.col then
                    -- Still style them, but don't position
                    local isRightColumn = false
                    EUI_UpdateSlotStyle(slotName, slot:GetID(), textOverlayFrame, isRightColumn)
                else
                    slot:ClearAllPoints()
                    local xOffset = gridStartX + (gridPos.col * cellWidth)
                    local yOffset = gridStartY - (gridPos.row * cellHeight)
                    slot:SetPoint("TOPLEFT", InspectPaperDollItemsFrame, "TOPLEFT", xOffset, yOffset)

                    -- Style the slot with borders, ilvl, enchants (right column = col 1)
                    local isRightColumn = gridPos.col == 1
                    EUI_UpdateSlotStyle(slotName, slot:GetID(), textOverlayFrame, isRightColumn)
                end
            end
        end
    end

    -- Position weapon slots at bottom
    if InspectMainHandSlot then
        InspectMainHandSlot:ClearAllPoints()
        InspectMainHandSlot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 115, 10)
    else
    end
    if InspectSecondaryHandSlot then
        InspectSecondaryHandSlot:ClearAllPoints()
        InspectSecondaryHandSlot:SetPoint("TOPLEFT", InspectMainHandSlot, "TOPRIGHT", 12, 0)
    end

    -- Add average item level label above MainHandSlot
    if not InspectMainHandSlot._avgItemLevelLabel then
        local avgItemLevelLabel = InspectMainHandSlot:CreateFontString(nil, "OVERLAY")
        if not avgItemLevelLabel then
            return
        end
        avgItemLevelLabel:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
        avgItemLevelLabel:SetJustifyH("CENTER")
        avgItemLevelLabel:SetPoint("TOP", InspectMainHandSlot, "TOP", 168, 335)

        InspectMainHandSlot._avgItemLevelLabel = avgItemLevelLabel
    end

    -- Update average item level
    if InspectMainHandSlot._avgItemLevelLabel then
        local avg = CalculateAverageItemLevel()
        InspectMainHandSlot._avgItemLevelLabel:SetFormattedText("avg. ilvl: |cff9933ff%d|r", math.floor(avg))
        if avg > 0 then
            InspectMainHandSlot._avgItemLevelLabel:Show()
        else
            InspectMainHandSlot._avgItemLevelLabel:Hide()
        end
    end

    -- Style Tabs (InspectFrameTab1, 2, 3)
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.51, g = 0.784, b = 1 }
    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

    for i = 1, 3 do
        local tab = _G["InspectFrameTab" .. i]
        if tab then
            -- Remove Blizzard textures
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

            -- Add custom background
            if not tab._ebsBg then
                tab._ebsBg = tab:CreateTexture(nil, "BACKGROUND", nil, 1)
                tab._ebsBg:SetAllPoints()
                tab._ebsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
            else
                -- Ensure it stays visible
                tab._ebsBg:Show()
                tab._ebsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
            end

            -- Add active highlight
            if not tab._activeHL then
                local activeHL = tab:CreateTexture(nil, "ARTWORK", nil, -6)
                activeHL:SetAllPoints()
                activeHL:SetColorTexture(1, 1, 1, 0.05)
                activeHL:SetBlendMode("ADD")
                activeHL:Hide()
                tab._activeHL = activeHL
            end

            -- Replace Blizzard label with custom font
            local blizLabel = tab:GetFontString()
            local labelText = blizLabel and blizLabel:GetText() or ("Tab " .. i)
            if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end
            tab:SetPushedTextOffset(0, 0)

            if not tab._label then
                local label = tab:CreateFontString(nil, "OVERLAY")
                label:SetFont(fontPath, 9, nil)
                label:SetPoint("CENTER", tab, "CENTER", 0, 0)
                label:SetJustifyH("CENTER")
                label:SetText(labelText)
                tab._label = label

                hooksecurefunc(tab, "SetText", function(_, newText)
                    if newText and label then label:SetText(newText) end
                end)
            end

            -- Add underline for active tab
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

    -- Update tab visuals on show
    local function UpdateTabVisuals()
        local isTab1 = (frame.selectedTab or 1) == 1

        -- Show model background only on Tab 1
        if frame._euiModelBg then
            frame._euiModelBg:SetShown(isTab1)
        end
        if frame._euiModelBgGlow then
            frame._euiModelBgGlow:SetShown(isTab1)
        end

        -- Update label visibility with ApplyTabVisibility - only show on Tab 1
        ApplyTabVisibility(isTab1)

        for i = 1, 3 do
            local tab = _G["InspectFrameTab" .. i]
            if tab then
                local isActive = (frame.selectedTab or 1) == i
                -- Ensure background is always visible
                if tab._ebsBg then
                    tab._ebsBg:Show()
                end
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

    -- Hook to update tabs when they change
    if frame.HookScript then
        frame:HookScript("OnShow", function()
            UpdateTabVisuals()
        end)
    end

    -- Hook to tabs to hide/show labels when clicked
    for i = 1, 3 do
        local tab = _G["InspectFrameTab" .. i]
        if tab then
            tab:HookScript("OnClick", function()
                UpdateTabVisuals()
                -- Check current tab dynamically
                local isTab1 = (frame.selectedTab or 1) == 1
                ApplyTabVisibility(isTab1)
            end)
        end
    end


    UpdateTabVisuals()

    -- Set frame scale and strata
    local scale = EllesmereUIDB and EllesmereUIDB.themedInspectSheetScale or 1
    frame:SetScale(scale)
    frame:SetFrameStrata("HIGH")

    -- Show TitleContainer itself and raise its layer above background
    if frame.TitleContainer then
        frame.TitleContainer:Show()
        frame.TitleContainer:SetAlpha(1)
        frame.TitleContainer:SetFrameStrata("HIGH")
        frame.TitleContainer:SetFrameLevel(20)

        -- Center the title by adjusting its size and justification
        local width = frame:GetWidth()
        frame.TitleContainer:SetWidth(width)

        -- Make sure text is centered
        for i = 1, frame.TitleContainer:GetNumChildren() do
            local child = select(i, frame.TitleContainer:GetChildren())
            if child and child:GetObjectType() == "FontString" then
                child:SetJustifyH("CENTER")
            end
        end
    end

end

-- Main function to apply themed inspect sheet
local function ApplyThemedInspectSheet()
    if not (EllesmereUIDB and EllesmereUIDB.themedInspectSheet) then
        return
    end

    if InspectFrame then
        SkinInspectSheet()
        -- Show labels on Tab 1
        ApplyTabVisibility((InspectFrame.selectedTab or 1) == 1)
    end
end

-- Persistently hide NineSlice borders
local function EnsureInspectNineSliceHidden()
    if not (EllesmereUIDB and EllesmereUIDB.themedInspectSheet) then return end
    if not InspectFrame then return end

    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05
    local frame = InspectFrame

    -- Hide InspectFrame.NineSlice
    if frame.NineSlice then
        frame.NineSlice:Hide()
        frame.NineSlice:SetAlpha(0)
    end

    -- Hide InspectFrameInset.NineSlice (borders) and cover with EUI background
    if InspectFrameInset and InspectFrameInset.NineSlice then
        InspectFrameInset.NineSlice:Hide()
        InspectFrameInset.NineSlice:SetAlpha(0)

        -- Create EUI-styled background to cover the inset area
        if not InspectFrameInset._euiBg then
            InspectFrameInset._euiBg = InspectFrameInset:CreateTexture(nil, "BACKGROUND", nil, -8)
            InspectFrameInset._euiBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
            InspectFrameInset._euiBg:SetAllPoints(InspectFrameInset)
        end
    end
end

-- Register with parent addon
if EllesmereUI then
    EllesmereUI.ApplyThemedInspectSheet = ApplyThemedInspectSheet

    -- Setup at PLAYER_LOGIN to register drag hooks early
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")

        if InspectFrame then
            -- Drag-to-move: shift = save to DB, ctrl = session-only
            InspectFrame:SetMovable(true)
            InspectFrame:SetClampedToScreen(true)

            local _ebsDragging       = false
            local _ebsTempPos        = nil
            local _ebsIgnoreSetPoint = false

            local function SaveInspectFramePos()
                if not EllesmereUIDB then EllesmereUIDB = {} end
                local point, _, relPoint, x, y = InspectFrame:GetPoint(1)
                if point then
                    EllesmereUIDB.inspectFramePos = {
                        point = point, relPoint = relPoint, x = x, y = y,
                    }
                end
            end

            local _otherPanelActive
            local function ApplyInspectFramePos()
                if InCombatLockdown() then return end
                if _otherPanelActive and _otherPanelActive() then return end
                local pos = _ebsTempPos
                    or (EllesmereUIDB and EllesmereUIDB.inspectFramePos)
                if not (pos and pos.point) then return end
                _ebsIgnoreSetPoint = true
                InspectFrame:ClearAllPoints()
                InspectFrame:SetPoint(
                    pos.point, UIParent, pos.relPoint, pos.x, pos.y)
                _ebsIgnoreSetPoint = false
            end

            -- Drag handlers via SetScript (not HookScript)
            InspectFrame:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" then return end
                if not IsShiftKeyDown() and not IsControlKeyDown() then return end
                _ebsDragging = IsShiftKeyDown() and "save" or "temp"
                self:StartMoving()
            end)

            InspectFrame:SetScript("OnMouseUp", function(self, button)
                if button ~= "LeftButton" or not _ebsDragging then return end
                self:StopMovingOrSizing()
                local point, _, relPoint, x, y = self:GetPoint(1)
                if _ebsDragging == "save" then
                    SaveInspectFramePos()
                elseif _ebsDragging == "temp" then
                    _ebsTempPos = { point = point, relPoint = relPoint, x = x, y = y }
                end
                _ebsDragging = false
            end)

            InspectFrame:HookScript("OnShow", function()
                _ebsTempPos = _ebsTempPos
                ApplyInspectFramePos()
                C_Timer.After(0, ApplyInspectFramePos)
                skinned = false
                ApplyThemedInspectSheet()
                -- Apply visibility settings when frame opens
                C_Timer.After(0.1, function()
                    if EllesmereUI._refreshInspectItemLevelVisibility then
                        EllesmereUI._refreshInspectItemLevelVisibility()
                    end
                    if EllesmereUI._refreshInspectUpgradeTrackVisibility then
                        EllesmereUI._refreshInspectUpgradeTrackVisibility()
                    end
                    if EllesmereUI._refreshInspectEnchantsVisibility then
                        EllesmereUI._refreshInspectEnchantsVisibility()
                    end
                    if EllesmereUI._refreshInspectAverageItemLevelVisibility then
                        EllesmereUI._refreshInspectAverageItemLevelVisibility()
                    end
                end)
            end)

            InspectFrame:HookScript("OnHide", function()
                _ebsTempPos = nil
                skinned = false
            end)

            -- Re-apply on SetPoint
            _otherPanelActive = function()
                local slots = { "doublewide", "fullscreen", "left", "center", "right" }
                for _, slot in ipairs(slots) do
                    local f = GetUIPanel and GetUIPanel(slot)
                    if f and f ~= InspectFrame then return true end
                end
                return false
            end

            hooksecurefunc(InspectFrame, "SetPoint", function()
                if _ebsIgnoreSetPoint then return end
                if InCombatLockdown() then return end
                if _otherPanelActive() then return end
                ApplyInspectFramePos()
            end)

            -- Apply initial position
            ApplyInspectFramePos()

            -- Event listener to keep NineSlice hidden even when Blizzard events fire
            local nineSliceHiddenFrame = CreateFrame("Frame")
            nineSliceHiddenFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
            nineSliceHiddenFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
            nineSliceHiddenFrame:SetScript("OnEvent", function(self, event, ...)
                if InspectFrame and InspectFrame:IsShown() then
                    EnsureInspectNineSliceHidden()
                end
            end)

            -- Hook OnShow to ensure NineSlice stays hidden
            InspectFrame:HookScript("OnShow", EnsureInspectNineSliceHidden)
        end
    end)

    -- Function to refresh all slot styles when inspect data changes
    local function RefreshSlotStyles()
        if not InspectPaperDollItemsFrame then return end
        if not InspectFrame then return end
        local textOverlayFrame = InspectFrame._textOverlayFrame
        if not textOverlayFrame then return end

        for slotName, gridPos in pairs(slotGridMap) do
            local slot = _G[slotName]
            if slot then
                -- Hide and clear old labels BEFORE creating new ones
                if slot._euiILvlText then
                    slot._euiILvlText:Hide()
                    slot._euiILvlText = nil
                end
                if slot._euiEnchantText then
                    slot._euiEnchantText:Hide()
                    slot._euiEnchantText = nil
                end
                if slot._euiEnchantHoverFrame then
                    slot._euiEnchantHoverFrame:Hide()
                    slot._euiEnchantHoverFrame = nil
                end
                if slot._euiUpgradeText then
                    slot._euiUpgradeText:Hide()
                    slot._euiUpgradeText = nil
                end

                -- Clear old styling
                slot._euiBorder = false
                -- Re-style (right column = col 1)
                local isRightColumn = gridPos.col == 1
                EUI_UpdateSlotStyle(slotName, slot:GetID(), textOverlayFrame, isRightColumn)
            end
        end
        -- Update label visibility after all slots have been styled
        local frame = InspectFrame
        if frame then
            ApplyTabVisibility((frame.selectedTab or 1) == 1)
            -- Update average item level label on MainHandSlot
            if InspectMainHandSlot and InspectMainHandSlot._avgItemLevelLabel then
                local avg = CalculateAverageItemLevel()
                InspectMainHandSlot._avgItemLevelLabel:SetFormattedText("avg. ilvl: |cff9933ff%d|r", math.floor(avg))
                if avg > 0 then
                    InspectMainHandSlot._avgItemLevelLabel:Show()
                else
                    InspectMainHandSlot._avgItemLevelLabel:Hide()
                end
            end
        end
    end

    -- Also hook to INSPECT_READY to reskin when new inspection data arrives
    local inspectHook = CreateFrame("Frame")
    inspectHook:RegisterEvent("INSPECT_READY")
    inspectHook:SetScript("OnEvent", function(self, event)
        skinned = false
        ApplyThemedInspectSheet()
        EnsureInspectNineSliceHidden()
        RefreshSlotStyles()
        local frame = InspectFrame
        if frame then
            ApplyTabVisibility((frame.selectedTab or 1) == 1)
            -- Apply visibility settings after styling
            if EllesmereUI._refreshInspectItemLevelVisibility then
                EllesmereUI._refreshInspectItemLevelVisibility()
            end
            if EllesmereUI._refreshInspectUpgradeTrackVisibility then
                EllesmereUI._refreshInspectUpgradeTrackVisibility()
            end
            if EllesmereUI._refreshInspectEnchantsVisibility then
                EllesmereUI._refreshInspectEnchantsVisibility()
            end
            if EllesmereUI._refreshInspectAverageItemLevelVisibility then
                EllesmereUI._refreshInspectAverageItemLevelVisibility()
            end
        end
    end)

else
    print("|cffff0000Error:|r EllesmereUI not found! Themed Inspect Sheet requires EllesmereUI.")
end

-- Initialize defaults
do
    local defaultStamp = CreateFrame("Frame")
    defaultStamp:RegisterEvent("ADDON_LOADED")
    defaultStamp:SetScript("OnEvent", function(self, _, addon)
        if addon ~= "EllesmereUI" then return end
        self:UnregisterAllEvents()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        local defaults = {
            themedInspectSheet = true,
            inspectShowItemLevel = true,
            inspectShowUpgradeTrack = true,
            inspectShowEnchants = true,
            inspectShowAverageItemLevel = true,
        }
        for k, v in pairs(defaults) do
            if EllesmereUIDB[k] == nil then
                EllesmereUIDB[k] = v
            end
        end
    end)
end

-- Function to refresh item level visibility when toggle changes
function EllesmereUI._refreshInspectItemLevelVisibility()
    if not InspectFrame or not InspectPaperDollItemsFrame then return end

    local showItemLevel = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowItemLevel ~= false)
    local isTab1 = (InspectFrame.selectedTab or 1) == 1

    for slotName, _ in pairs(slotGridMap) do
        local slot = _G[slotName]
        if slot and slot._euiILvlText then
            -- Only show if Tab 1 AND setting is enabled
            slot._euiILvlText:SetShown(isTab1 and showItemLevel)
        end
    end
end

-- Function to refresh upgrade track visibility when toggle changes
function EllesmereUI._refreshInspectUpgradeTrackVisibility()
    if not InspectFrame or not InspectPaperDollItemsFrame then return end

    local showUpgradeTrack = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowUpgradeTrack ~= false)
    local isTab1 = (InspectFrame.selectedTab or 1) == 1

    for slotName, _ in pairs(slotGridMap) do
        local slot = _G[slotName]
        if slot and slot._euiUpgradeText then
            -- Only show if Tab 1 AND setting is enabled
            slot._euiUpgradeText:SetShown(isTab1 and showUpgradeTrack)
        end
    end
end

-- Function to refresh enchants visibility when toggle changes
function EllesmereUI._refreshInspectEnchantsVisibility()
    if not InspectFrame or not InspectPaperDollItemsFrame then return end

    local showEnchants = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowEnchants ~= false)
    local isTab1 = (InspectFrame.selectedTab or 1) == 1

    for slotName, _ in pairs(slotGridMap) do
        local slot = _G[slotName]
        if slot and slot._euiEnchantText then
            -- Only show if Tab 1 AND setting is enabled
            slot._euiEnchantText:SetShown(isTab1 and showEnchants)
        end
    end
end

-- Function to refresh average item level visibility when toggle changes
function EllesmereUI._refreshInspectAverageItemLevelVisibility()
    if not InspectFrame or not InspectPaperDollItemsFrame then return end

    local showAverageItemLevel = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowAverageItemLevel ~= false)

    if InspectMainHandSlot and InspectMainHandSlot._avgItemLevelLabel then
        InspectMainHandSlot._avgItemLevelLabel:SetShown(showAverageItemLevel)
    end
end
