-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin_GreatVault.lua
--  Great Vault reskin matching the EllesmereUI BlizzardSkin module style.
-------------------------------------------------------------------------------
local LOCK_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"

-------------------------------------------------------------------------------
--  Config / Theme Access
-------------------------------------------------------------------------------
local DEFAULT_ACCENT = { r = 0.05, g = 0.82, b = 0.61 }
local DEFAULT_RESKIN = {
    BG_R = 0.03, BG_G = 0.045, BG_B = 0.05,
    QT_ALPHA = 0.96,
    BRD_ALPHA = 0.4,
}

local STYLE = {
    paddings = {
        inset = 3,
        activityCard = 4,
        concessionCard = 6,
        icon = 2,
    },
    sizes = {
        closeButtonFont = 15,
        buttonFont = 10,
        typeTitle = 16,
        itemName = 10,
        threshold = 10,
        progress = 11,
        overlayTitle = 18,
        overlayText = 11,
        warningText = 10,
        headerTitle = 18,
        headerHeight = 90,
        previousReward = 10,
        progressBarHeight = 3,
        lockIcon = 28,
        completedIcon = 16,
    },
    offsets = {
        closeButtonLabel = { x = -1, y = -2 },
        header = {
            topY = -20,
            textY = -6,
            dividerInset = 30,
            dividerY = -4,
        },
        progressBar = { x = 1, y = 1 },
        lockIcon = { x = 0, y = -7 },
        selectRewardButton = { x = 0, y = 30 },
    },
    alpha = {
        selectedGlow = 0.08,
        selectedBorder = 0.75,
        activityUnlockedBorder = 0.45,
        activityLockedBorder = 0.15,
        buttonEnabledBorder = 0.5,
        buttonDisabledBackground = 0.55,
        closeButton = 0.55,
        closeButtonHover = 0.95,
        previousReward = 0.82,
        overlayText = 0.9,
        warningText = 0.85,
        typeBackground = 0.82,
        headerDivider = 0.08,
        blackout = 0.72,
        lockIcon = 0.5,
        progressRewardFill = 0.95,
        progressUnlockedFill = 0.7,
        progressRewardTrack = 0.16,
        progressUnlockedTrack = 0.12,
        progressLockedTrack = 0.10,
        thresholdUnlocked = 0.92,
        thresholdLocked = 0.65,
        progressUnlockedText = 0.9,
        rewardsLabel = 0.75,
        iconBackground = 0.95,
        itemName = 0.95,
        buttonHighlight = 0.08,
    },
    colors = {
        white = { r = 1, g = 1, b = 1 },
        buttonBackground = { r = 0.08, g = 0.09, b = 0.10, a = 0.92 },
        buttonDisabledText = { r = 0.45, g = 0.45, b = 0.45, a = 1 },
        buttonDisabledBorder = { r = 0.35, g = 0.35, b = 0.35, a = 0.4 },
        itemSlotBackground = { r = 0.5, g = 0.5, b = 0.5, a = 0.7 },
        itemDefaultBorder = { r = 0.4, g = 0.4, b = 0.4, a = 1 },
        typeBackground = { r = 0.01, g = 0.015, b = 0.02, a = 0.18 },
        typeShade = { r = 0.01, g = 0.015, b = 0.02, a = 0.24 },
        iconBackground = { r = 0.02, g = 0.02, b = 0.025, a = 0.95 },
        activitySelectedBackground = { r = 0.04, g = 0.07, b = 0.06, a = 0.97 },
        activityUnlockedBackground = { r = 0.03, g = 0.04, b = 0.05, a = 0.96 },
        activityLockedBackground = { r = 0.03, g = 0.04, b = 0.05, a = 0.9 },
        progressInactive = { r = 0.55, g = 0.55, b = 0.55, a = 1 },
        progressWarning = { r = 1.00, g = 0.55, b = 0.10, a = 1 },
    },
    progressAccentThreshold = 0.75,
}

local function IsGreatVaultSkinEnabled()
    return not EllesmereUIDB or EllesmereUIDB.reskinGreatVault ~= false
end

local function ResolveAccentColor()
    if EllesmereUI then
        if EllesmereUI.GetAccentColor then
            local r, g, b = EllesmereUI.GetAccentColor()
            if r and g and b then
                return { r = r, g = g, b = b }
            end
        end

        if EllesmereUI.ResolveThemeColor then
            local db = EllesmereUIDB
            local r, g, b

            if db and db.useClassAccentColor and EllesmereUI.GetPlayerClassColor then
                r, g, b = EllesmereUI.GetPlayerClassColor()
            else
                local theme = db and db.theme
                r, g, b = EllesmereUI.ResolveThemeColor(theme)
            end

            if r and g and b then
                return { r = r, g = g, b = b }
            end
        end

        if EllesmereUI.ELLESMERE_GREEN then
            return {
                r = EllesmereUI.ELLESMERE_GREEN.r,
                g = EllesmereUI.ELLESMERE_GREEN.g,
                b = EllesmereUI.ELLESMERE_GREEN.b,
            }
        end
    end

    return {
        r = DEFAULT_ACCENT.r,
        g = DEFAULT_ACCENT.g,
        b = DEFAULT_ACCENT.b,
    }
end

local function BuildThemeContext()
    return {
        accent = ResolveAccentColor(),
        borderAPI = EllesmereUI and (EllesmereUI.PP or EllesmereUI.PanelPP),
        fontPath = EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT,
        reskin = EllesmereUI and EllesmereUI.RESKIN or DEFAULT_RESKIN,
    }
end

-------------------------------------------------------------------------------
--  Low-Level Skin Primitives
-------------------------------------------------------------------------------
local function ApplyColorTexture(texture, color, alpha)
    if not texture or not color then return end
    texture:SetColorTexture(color.r or 1, color.g or 1, color.b or 1, alpha or color.a or 1)
end

local function SetBorderColor(frame, theme, color, alpha)
    local pp = theme and theme.borderAPI
    if pp and pp.SetBorderColor and frame and frame._ppBorders and color then
        pp.SetBorderColor(frame, color.r or 1, color.g or 1, color.b or 1, alpha or color.a or 1)
    end
end

local function StripTexture(texture)
    if texture and texture.SetAlpha and not texture._euiOwned then
        texture:SetAlpha(0)
    end
end

local function SuppressTexture(texture)
    if not texture or texture._euiOwned or texture._euiSuppressed then return end

    texture._euiSuppressed = true
    if texture.Hide then texture:Hide() end
    if texture.SetAlpha then texture:SetAlpha(0) end

    if texture.HookScript then
        texture:HookScript("OnShow", function(self)
            self:Hide()
            if self.SetAlpha then self:SetAlpha(0) end
        end)
    end

    if texture.SetAlpha then
        hooksecurefunc(texture, "SetAlpha", function(self, alpha)
            if alpha and alpha > 0 then
                self:SetAlpha(0)
            end
        end)
    end

    if texture.Show then
        hooksecurefunc(texture, "Show", function(self)
            self:Hide()
            if self.SetAlpha then self:SetAlpha(0) end
        end)
    end
end

local function StripFrameRegions(frame)
    if not frame then return end

    for i = 1, select("#", frame:GetRegions()) do
        local region = select(i, frame:GetRegions())
        if region and region:IsObjectType("Texture") and not region._euiOwned then
            region:SetAlpha(0)
        end
    end
end

local function ApplyFont(fontString, theme, size, r, g, b, a, flags)
    if not fontString then return end

    fontString:SetFont((theme and theme.fontPath) or STANDARD_TEXT_FONT, size, flags or "")
    fontString:SetTextColor(r or 1, g or 1, b or 1, a or 1)
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, 0.9)
end

local function EnsureBackdrop(frame, theme, alpha)
    if not frame then return end

    local rs = theme.reskin
    if not frame._euiBg then
        frame._euiBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame._euiBg:SetAllPoints()
        frame._euiBg._euiOwned = true
    end

    frame._euiBg:SetColorTexture(rs.BG_R, rs.BG_G, rs.BG_B, alpha or rs.QT_ALPHA)
    frame._euiBg:Show()

    local pp = theme.borderAPI
    if pp and pp.CreateBorder and not frame._euiBorderCreated then
        frame._euiBorderCreated = true
        pp.CreateBorder(frame, 1, 1, 1, rs.BRD_ALPHA, 1, "OVERLAY", 7)
    end
end

local function EnsureInsetBackdrop(frame, theme, padding, alpha)
    if not frame then return nil end

    local pad = padding or STYLE.paddings.inset
    local rs = theme.reskin
    local pp = theme.borderAPI

    if not frame._euiSkinFrame then
        local skinFrame = CreateFrame("Frame", nil, frame)
        local bg = skinFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg:SetAllPoints()
        bg._euiOwned = true

        skinFrame._euiBg = bg
        frame._euiSkinFrame = skinFrame
    end

    local skinFrame = frame._euiSkinFrame
    skinFrame:ClearAllPoints()
    skinFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    skinFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    skinFrame:SetFrameLevel(math.max(1, frame:GetFrameLevel()))

    if pp and pp.CreateBorder and not skinFrame._euiBorderCreated then
        skinFrame._euiBorderCreated = true
        pp.CreateBorder(skinFrame, 1, 1, 1, rs.BRD_ALPHA, 1, "OVERLAY", 7)
    end

    skinFrame._euiBg:SetColorTexture(rs.BG_R, rs.BG_G, rs.BG_B, alpha or 0.92)
    skinFrame:Show()
    return skinFrame
end

local function EnsureSelectionGlow(frame, anchorFrame)
    if not frame then return nil end

    if not frame._euiSelectedGlow then
        local glow = frame:CreateTexture(nil, "ARTWORK", nil, -5)
        glow._euiOwned = true
        glow:Hide()
        frame._euiSelectedGlow = glow
    end

    local glow = frame._euiSelectedGlow
    local anchor = anchorFrame or frame
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    glow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    return glow
end

local function EnsureProgressBar(frame, anchorFrame)
    if not frame then return nil end

    if not frame._euiProgressBarFrame then
        local barFrame = CreateFrame("Frame", nil, frame)
        local track = barFrame:CreateTexture(nil, "BACKGROUND", nil, -4)
        local fill = barFrame:CreateTexture(nil, "ARTWORK", nil, -3)

        track:SetAllPoints()
        track._euiOwned = true
        fill:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
        fill:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
        fill._euiOwned = true

        barFrame._euiTrack = track
        barFrame._euiFill = fill
        barFrame:SetScript("OnSizeChanged", function(self)
            if self._euiFill then
                local ratio = self._euiRatio or 0
                local width = math.max(0, self:GetWidth() * ratio)
                self._euiFill:SetWidth(width)
                self._euiFill:SetShown(width > 0)
            end
        end)

        frame._euiProgressBarFrame = barFrame
    end

    local barFrame = frame._euiProgressBarFrame
    local anchor = anchorFrame or frame
    barFrame:ClearAllPoints()
    barFrame:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", STYLE.offsets.progressBar.x, STYLE.offsets.progressBar.y)
    barFrame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -STYLE.offsets.progressBar.x, STYLE.offsets.progressBar.y)
    barFrame:SetHeight(STYLE.sizes.progressBarHeight)
    return barFrame
end

local function EnsureLockIcon(frame, anchorFrame)
    if not frame then return nil end

    if not frame._euiLockIcon then
        local lock = frame:CreateTexture(nil, "ARTWORK", nil, -3)
        lock:SetTexture(LOCK_TEXTURE)
        lock._euiOwned = true
        frame._euiLockIcon = lock
    end

    local lock = frame._euiLockIcon
    local anchor = anchorFrame or frame
    lock:SetSize(STYLE.sizes.lockIcon, STYLE.sizes.lockIcon)
    lock:ClearAllPoints()
    lock:SetPoint("CENTER", anchor, "CENTER", STYLE.offsets.lockIcon.x, STYLE.offsets.lockIcon.y)
    lock:SetVertexColor(1, 1, 1, STYLE.alpha.lockIcon)
    return lock
end

local function ResolveWeeklyRewardItemLink(activityFrame, itemFrame)
    if itemFrame then
        if itemFrame.itemLink then
            return itemFrame.itemLink
        end
        if itemFrame.itemHyperlink then
            return itemFrame.itemHyperlink
        end
        if itemFrame.itemDBID and C_WeeklyRewards and C_WeeklyRewards.GetItemHyperlink then
            local itemLink = C_WeeklyRewards.GetItemHyperlink(itemFrame.itemDBID)
            if itemLink then
                return itemLink
            end
        end
    end

    local info = activityFrame and activityFrame.info
    local rewards = info and info.rewards
    if type(rewards) ~= "table" then
        return nil
    end

    for _, reward in ipairs(rewards) do
        if reward and reward.itemDBID and C_WeeklyRewards and C_WeeklyRewards.GetItemHyperlink then
            local itemLink = C_WeeklyRewards.GetItemHyperlink(reward.itemDBID)
            if itemLink then
                return itemLink
            end
        end
    end

    return nil
end

local function ResolveItemBorderColor(itemLink)
    if not itemLink then
        return STYLE.colors.itemDefaultBorder
    end

    local quality
    if C_Item and C_Item.GetItemQualityByID then
        quality = C_Item.GetItemQualityByID(itemLink)
    end
    if not quality then
        local _, _, itemQuality = GetItemInfo(itemLink)
        quality = itemQuality
    end

    if quality then
        local r, g, b
        if C_Item and C_Item.GetItemQualityColor then
            r, g, b = C_Item.GetItemQualityColor(quality)
        elseif GetItemQualityColor then
            r, g, b = GetItemQualityColor(quality)
        end
        if r and g and b then
            return { r = r, g = g, b = b, a = 1 }
        end
    end

    return STYLE.colors.itemDefaultBorder
end

local function EnsureIconChrome(itemFrame, theme, borderColor)
    if not itemFrame or not itemFrame.Icon then return end

    local icon = itemFrame.Icon
    local pad = STYLE.paddings.icon
    local pp = theme.borderAPI

    if not itemFrame._euiIconBg then
        local bg = itemFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
        bg._euiOwned = true
        itemFrame._euiIconBg = bg
    end

    itemFrame._euiIconBg:ClearAllPoints()
    itemFrame._euiIconBg:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
    itemFrame._euiIconBg:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
    ApplyColorTexture(itemFrame._euiIconBg, STYLE.colors.itemSlotBackground)

    if not itemFrame._euiIconBorder then
        local borderHost = CreateFrame("Frame", nil, itemFrame)
        itemFrame._euiIconBorder = borderHost

        if pp and pp.CreateBorder then
            pp.CreateBorder(borderHost, 1, 1, 1, 1, 2, "OVERLAY", 7)
        end
    end

    local borderHost = itemFrame._euiIconBorder
    borderHost:ClearAllPoints()
    borderHost:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
    borderHost:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
    borderHost:SetFrameLevel(itemFrame:GetFrameLevel() + 1)
    SetBorderColor(borderHost, theme, borderColor or STYLE.colors.itemDefaultBorder, 1)

    return borderHost
end

local function SuppressItemButtonChrome(itemFrame)
    if not itemFrame then return end

    for _, key in ipairs({
        "Border", "Background", "IconBorder", "IconOverlay", "IconOverlay2",
        "SlotBackground", "Highlight", "Glow", "NormalTexture", "PushedTexture",
    }) do
        SuppressTexture(itemFrame[key])
    end

    if itemFrame.GetNormalTexture then
        SuppressTexture(itemFrame:GetNormalTexture())
    end
    if itemFrame.GetPushedTexture then
        SuppressTexture(itemFrame:GetPushedTexture())
    end
    if itemFrame.GetHighlightTexture then
        SuppressTexture(itemFrame:GetHighlightTexture())
    end

    for i = 1, select("#", itemFrame:GetRegions()) do
        local region = select(i, itemFrame:GetRegions())
        if region and region:IsObjectType("Texture") and region ~= itemFrame.Icon and not region._euiOwned then
            SuppressTexture(region)
        end
    end
end

local function EnsureCloseButtonChrome(button)
    if not button or button._euiStyled then return end

    button._euiStyled = true
    StripFrameRegions(button)
    if button.NormalTexture then button.NormalTexture:SetAlpha(0) end
    if button.PushedTexture then button.PushedTexture:SetAlpha(0) end
    if button.HighlightTexture then button.HighlightTexture:SetAlpha(0) end
    if button.DisabledTexture then button.DisabledTexture:SetAlpha(0) end

    local label = button:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER", button, "CENTER", STYLE.offsets.closeButtonLabel.x, STYLE.offsets.closeButtonLabel.y)
    button._euiX = label

    button:HookScript("OnEnter", function(self)
        if self._euiX then
            self._euiX:SetTextColor(1, 1, 1, STYLE.alpha.closeButtonHover)
        end
    end)

    button:HookScript("OnLeave", function(self)
        if self._euiX then
            self._euiX:SetTextColor(1, 1, 1, STYLE.alpha.closeButton)
        end
    end)
end

local function HideButtonTextures(button)
    if not button then return end

    StripFrameRegions(button)
    if button.Left then button.Left:SetAlpha(0) end
    if button.Middle then button.Middle:SetAlpha(0) end
    if button.Right then button.Right:SetAlpha(0) end
    if button.Background then button.Background:SetAlpha(0) end
end

local function EnsureButtonChrome(button, theme)
    if not button or button._euiStyled then return end

    button._euiStyled = true
    HideButtonTextures(button)

    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        local texture = button[key]
        if texture and texture.SetAlpha then
            hooksecurefunc(texture, "SetAlpha", function(self, alpha)
                if alpha and alpha > 0 then
                    self:SetAlpha(0)
                end
            end)
        end
    end

    local bg = button:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetAllPoints()
    bg._euiOwned = true
    button._euiBg = bg

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight._euiOwned = true
    button._euiHighlight = highlight

    local pp = theme.borderAPI
    if pp and pp.CreateBorder then
        pp.CreateBorder(button, 1, 1, 1, theme.reskin.BRD_ALPHA, 1, "OVERLAY", 7)
    end
end

local function ApplyStoredAnchorOffset(frame, cacheKey, offsetX, offsetY)
    if not frame then return end

    local appliedOffsetKey = cacheKey .. "AppliedOffset"
    local appliedOffset = frame[appliedOffsetKey] or { x = 0, y = 0 }
    local cachedPoints = {}

    for i = 1, frame:GetNumPoints() do
        local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(i)
        cachedPoints[i] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = (xOfs or 0) - appliedOffset.x,
            y = (yOfs or 0) - appliedOffset.y,
        }
    end

    frame[cacheKey] = cachedPoints
    frame[appliedOffsetKey] = { x = offsetX or 0, y = offsetY or 0 }

    if #cachedPoints == 0 then return end

    frame:ClearAllPoints()
    for _, anchor in ipairs(cachedPoints) do
        frame:SetPoint(
            anchor.point,
            anchor.relativeTo,
            anchor.relativePoint,
            (anchor.x or 0) + (offsetX or 0),
            (anchor.y or 0) + (offsetY or 0)
        )
    end
end

-------------------------------------------------------------------------------
--  Component Stylers
-------------------------------------------------------------------------------
local function RefreshCloseButtonState(button, theme)
    if not button then return end

    EnsureCloseButtonChrome(button)
    if not button._euiX then return end

    ApplyFont(button._euiX, theme, STYLE.sizes.closeButtonFont, 1, 1, 1, STYLE.alpha.closeButton)
    button._euiX:SetText("x")
end

local function RefreshButtonState(button, theme)
    if not button then return end

    EnsureButtonChrome(button, theme)
    HideButtonTextures(button)

    ApplyColorTexture(button._euiBg, STYLE.colors.buttonBackground)
    ApplyColorTexture(button._euiHighlight, STYLE.colors.white, STYLE.alpha.buttonHighlight)

    local fontString = button.GetFontString and button:GetFontString()
    local enabled = not button.IsEnabled or button:IsEnabled()

    if fontString then
        if enabled then
            ApplyFont(fontString, theme, STYLE.sizes.buttonFont, theme.accent.r, theme.accent.g, theme.accent.b, 1)
        else
            local disabledText = STYLE.colors.buttonDisabledText
            ApplyFont(fontString, theme, STYLE.sizes.buttonFont, disabledText.r, disabledText.g, disabledText.b, disabledText.a)
        end
    end

    if button._euiBg then
        button._euiBg:SetAlpha(enabled and 1 or STYLE.alpha.buttonDisabledBackground)
    end

    if enabled then
        SetBorderColor(button, theme, theme.accent, STYLE.alpha.buttonEnabledBorder)
    else
        local disabledBorder = STYLE.colors.buttonDisabledBorder
        SetBorderColor(button, theme, disabledBorder, disabledBorder.a)
    end
end

local function EnsureTypeFrameChrome(frame, theme)
    if not frame then return nil end

    StripTexture(frame.Border)

    if not frame._euiTypeContainer then
        local container = CreateFrame("Frame", nil, frame)
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame._euiTypeContainer = container
    end

    local container = frame._euiTypeContainer
    container:SetFrameLevel(math.max(1, frame:GetFrameLevel()))

    local pp = theme.borderAPI
    if pp and pp.CreateBorder and not container._euiBorderCreated then
        container._euiBorderCreated = true
        pp.CreateBorder(container, 1, 1, 1, theme.reskin.BRD_ALPHA, 1, "OVERLAY", 7)
    end

    if not container._euiBg then
        local bg = container:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg:SetAllPoints()
        bg._euiOwned = true
        container._euiBg = bg
    end

    if not container._euiShade then
        local shade = container:CreateTexture(nil, "ARTWORK", nil, 1)
        shade:SetAllPoints()
        shade._euiOwned = true
        container._euiShade = shade
    end

    if frame.Background then
        frame.Background:ClearAllPoints()
        frame.Background:SetPoint("TOPLEFT", container, "TOPLEFT", -10, 2)
        frame.Background:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 10, -5)
        frame.Background:SetAlpha(STYLE.alpha.typeBackground)
        if frame.Background.SetDesaturated then
            frame.Background:SetDesaturated(false)
        end
    end

    return container
end

local function RefreshTypeFrameState(frame, theme)
    if not frame then return end

    local container = EnsureTypeFrameChrome(frame, theme)
    if not container then return end

    ApplyColorTexture(container._euiBg, STYLE.colors.typeBackground)
    ApplyColorTexture(container._euiShade, STYLE.colors.typeShade)
    SetBorderColor(container, theme, STYLE.colors.white, theme.reskin.BRD_ALPHA)

    if frame.Name then
        ApplyFont(frame.Name, theme, STYLE.sizes.typeTitle, theme.accent.r, theme.accent.g, theme.accent.b, 1)
    end

    if frame._euiDivider then
        frame._euiDivider:Hide()
    end
end

local function RefreshActivityItemState(itemFrame, activityFrame, theme)
    if not itemFrame then return end

    SuppressItemButtonChrome(itemFrame)

    if itemFrame.Icon then
        itemFrame.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end

    local itemLink = ResolveWeeklyRewardItemLink(activityFrame, itemFrame)
    local borderColor = ResolveItemBorderColor(itemLink)
    EnsureIconChrome(itemFrame, theme, borderColor)

    if itemFrame.Name then
        ApplyFont(itemFrame.Name, theme, STYLE.sizes.itemName, 1, 1, 1, STYLE.alpha.itemName)
    end
end

local function GetProgressTextColor(theme, progress, threshold)
    if not progress or not threshold or threshold <= 0 or progress <= 0 then
        return STYLE.colors.progressInactive
    end

    local ratio = math.max(0, math.min(1, progress / threshold))
    if ratio >= STYLE.progressAccentThreshold then
        return { r = theme.accent.r, g = theme.accent.g, b = theme.accent.b, a = 1 }
    end

    return STYLE.colors.progressWarning
end

local function GetActivityState(frame, selectedActivity, theme)
    local hasRewards = frame and frame.hasRewards or false
    local isUnlocked = frame and (frame.unlocked or frame.hasRewards) or false
    local progress = frame and frame.info and frame.info.progress or 0
    local threshold = frame and frame.info and frame.info.threshold or 0

    return {
        hasRewards = hasRewards,
        isSelected = selectedActivity and selectedActivity == frame and hasRewards or false,
        isUnlocked = isUnlocked,
        progress = progress,
        threshold = threshold,
        ratio = (threshold and threshold > 0) and (progress / threshold) or 0,
        progressColor = GetProgressTextColor(theme, progress, threshold),
    }
end

local function SetActivityProgressBar(frame, ratio, color, alpha, trackAlpha)
    if not frame or not frame._euiProgressBarFrame then return end

    local barFrame = frame._euiProgressBarFrame
    local clampedRatio = math.max(0, math.min(1, ratio or 0))
    barFrame._euiRatio = clampedRatio

    if barFrame._euiTrack then
        barFrame._euiTrack:SetColorTexture(1, 1, 1, trackAlpha or STYLE.alpha.progressLockedTrack)
    end

    if barFrame._euiFill then
        ApplyColorTexture(barFrame._euiFill, color or STYLE.colors.white, alpha or 1)
        local width = math.max(0, barFrame:GetWidth() * clampedRatio)
        barFrame._euiFill:SetWidth(width)
        barFrame._euiFill:SetShown(width > 0)
    end
end

local function RefreshSelectableCardState(theme, skinFrame, glow, state)
    if glow then
        ApplyColorTexture(glow, theme.accent, STYLE.alpha.selectedGlow)
        glow:SetShown(state.isSelected and true or false)
    end

    if skinFrame and skinFrame._euiBg and state.backgroundColor then
        ApplyColorTexture(skinFrame._euiBg, state.backgroundColor)
    end

    if not skinFrame then return end

    if state.isSelected then
        SetBorderColor(skinFrame, theme, theme.accent, STYLE.alpha.selectedBorder)
    else
        SetBorderColor(skinFrame, theme, state.borderColor or STYLE.colors.white, state.borderAlpha)
    end
end

local function RefreshActivityVisualState(frame, selectedActivity, theme)
    if not frame then return end

    StripTexture(frame.Background)
    StripTexture(frame.Border)
    StripTexture(frame.SelectedTexture)
    StripTexture(frame.ItemGlow)
    StripTexture(frame.UncollectedGlow)
    if frame.UnselectedFrame then
        frame.UnselectedFrame:SetAlpha(0)
    end

    local skinFrame = EnsureInsetBackdrop(frame, theme, STYLE.paddings.activityCard, 0.96)
    local glow = EnsureSelectionGlow(frame, skinFrame)
    EnsureProgressBar(frame, skinFrame)
    EnsureLockIcon(frame, skinFrame)

    local activityState = GetActivityState(frame, selectedActivity, theme)
    local backgroundColor = activityState.isSelected and STYLE.colors.activitySelectedBackground
        or (activityState.isUnlocked and STYLE.colors.activityUnlockedBackground or STYLE.colors.activityLockedBackground)

    RefreshSelectableCardState(theme, skinFrame, glow, {
        isSelected = activityState.isSelected,
        backgroundColor = backgroundColor,
        borderColor = activityState.isUnlocked and theme.accent or STYLE.colors.white,
        borderAlpha = activityState.isUnlocked and STYLE.alpha.activityUnlockedBorder or STYLE.alpha.activityLockedBorder,
    })

    if activityState.hasRewards then
        SetActivityProgressBar(frame, 1, theme.accent, STYLE.alpha.progressRewardFill, STYLE.alpha.progressRewardTrack)
    elseif activityState.isUnlocked then
        SetActivityProgressBar(frame, 1, theme.accent, STYLE.alpha.progressUnlockedFill, STYLE.alpha.progressUnlockedTrack)
    else
        SetActivityProgressBar(
            frame,
            activityState.ratio,
            activityState.progressColor,
            activityState.progressColor.a,
            STYLE.alpha.progressLockedTrack
        )
    end

    if frame._euiLockIcon then
        frame._euiLockIcon:SetShown(not activityState.isUnlocked)
    end

    if frame.Threshold then
        local thresholdAlpha = activityState.isUnlocked and STYLE.alpha.thresholdUnlocked or STYLE.alpha.thresholdLocked
        ApplyFont(frame.Threshold, theme, STYLE.sizes.threshold, 1, 1, 1, thresholdAlpha)
    end

    if frame.Progress then
        if activityState.hasRewards then
            ApplyFont(frame.Progress, theme, STYLE.sizes.progress, theme.accent.r, theme.accent.g, theme.accent.b, 1)
        elseif activityState.isUnlocked then
            ApplyFont(
                frame.Progress,
                theme,
                STYLE.sizes.progress,
                theme.accent.r,
                theme.accent.g,
                theme.accent.b,
                STYLE.alpha.progressUnlockedText
            )
        else
            local progressColor = activityState.progressColor
            ApplyFont(
                frame.Progress,
                theme,
                STYLE.sizes.progress,
                progressColor.r,
                progressColor.g,
                progressColor.b,
                progressColor.a
            )
        end
    end

    if frame.CompletedIcon then
        frame.CompletedIcon:SetSize(STYLE.sizes.completedIcon, STYLE.sizes.completedIcon)
        if activityState.hasRewards then
            frame.CompletedIcon:SetVertexColor(theme.accent.r, theme.accent.g, theme.accent.b, 1)
        else
            frame.CompletedIcon:SetVertexColor(1, 1, 1, 0.9)
        end
    end

    RefreshActivityItemState(frame.ItemFrame, frame, theme)
end

local function RefreshConcessionVisualState(frame, selectedActivity, theme)
    if not frame then return end

    StripTexture(frame.Background)
    StripTexture(frame.SelectedTexture)
    StripTexture(frame.Divider1)
    StripTexture(frame.Divider2)
    if frame.UnselectedFrame then
        frame.UnselectedFrame:SetAlpha(0)
    end

    local skinFrame = EnsureInsetBackdrop(frame, theme, STYLE.paddings.concessionCard, 0.96)
    local glow = EnsureSelectionGlow(frame, skinFrame)

    RefreshSelectableCardState(theme, skinFrame, glow, {
        isSelected = selectedActivity and selectedActivity == frame or false,
        borderColor = STYLE.colors.white,
        borderAlpha = STYLE.alpha.activityLockedBorder,
    })

    if frame.RewardsFrame then
        if frame.RewardsFrame.Label then
            ApplyFont(frame.RewardsFrame.Label, theme, STYLE.sizes.itemName, 1, 1, 1, STYLE.alpha.rewardsLabel)
        end
        if frame.RewardsFrame.Text then
            ApplyFont(frame.RewardsFrame.Text, theme, STYLE.sizes.itemName, theme.accent.r, theme.accent.g, theme.accent.b, 1)
        end
    end
end

local function RefreshOverlayState(overlay, theme)
    if not overlay then return end

    EnsureBackdrop(overlay, theme, 0.97)
    if overlay.Background then overlay.Background:SetAlpha(0) end
    if overlay.NineSlice then overlay.NineSlice:SetAlpha(0) end

    if overlay.Title then
        ApplyFont(overlay.Title, theme, STYLE.sizes.overlayTitle, theme.accent.r, theme.accent.g, theme.accent.b, 1)
    end
    if overlay.Text then
        ApplyFont(overlay.Text, theme, STYLE.sizes.overlayText, 1, 1, 1, STYLE.alpha.overlayText)
    end
end

local function RefreshWarningDialogState(frame, theme)
    if not frame then return end

    EnsureBackdrop(frame, theme, 0.97)
    if frame.NineSlice then frame.NineSlice:SetAlpha(0) end
    if frame.WarningIcon and frame.WarningIcon.SetDesaturated then
        frame.WarningIcon:SetDesaturated(true)
    end
    if frame.Description then
        ApplyFont(frame.Description, theme, STYLE.sizes.warningText, 1, 1, 1, STYLE.alpha.warningText)
    end
end

local function RefreshHeaderState(headerFrame, parentFrame, theme)
    if not headerFrame or not parentFrame then return end

    headerFrame:ClearAllPoints()
    headerFrame:SetPoint("TOP", parentFrame, "TOP", 0, STYLE.offsets.header.topY)
    headerFrame:SetHeight(STYLE.sizes.headerHeight)

    if headerFrame.Text then
        ApplyFont(headerFrame.Text, theme, STYLE.sizes.headerTitle, theme.accent.r, theme.accent.g, theme.accent.b, 1)
        headerFrame.Text:ClearAllPoints()
        headerFrame.Text:SetPoint("CENTER", headerFrame, "CENTER", 0, STYLE.offsets.header.textY)
    end

    StripTexture(headerFrame.HeaderDivider)
    if not headerFrame._euiDivider then
        local divider = headerFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        divider:SetHeight(1)
        divider:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", STYLE.offsets.header.dividerInset, STYLE.offsets.header.dividerY)
        divider:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", -STYLE.offsets.header.dividerInset, STYLE.offsets.header.dividerY)
        divider._euiOwned = true
        headerFrame._euiDivider = divider
    end

    ApplyColorTexture(headerFrame._euiDivider, STYLE.colors.white, STYLE.alpha.headerDivider)
end

-------------------------------------------------------------------------------
--  Frame Orchestration / Hooks
-------------------------------------------------------------------------------
local RefreshGreatVaultFrame

local function ScheduleGreatVaultRefresh(frame)
    if not frame or frame._euiGreatVaultRefreshQueued then return end

    frame._euiGreatVaultRefreshQueued = true
    C_Timer.After(0, function()
        frame._euiGreatVaultRefreshQueued = nil
        if frame and not frame:IsForbidden() then
            RefreshGreatVaultFrame(frame)
        end
    end)
end

RefreshGreatVaultFrame = function(frame)
    if not frame or frame:IsForbidden() or not IsGreatVaultSkinEnabled() then return end

    local theme = BuildThemeContext()
    EnsureBackdrop(frame, theme, 0.98)

    StripTexture(frame.Background)
    StripTexture(frame.BorderShadow)
    StripTexture(frame.Divider1)
    StripTexture(frame.Divider2)

    if frame.BorderContainer then
        if frame.BorderContainer.Border then frame.BorderContainer.Border:SetAlpha(0) end
        if frame.BorderContainer.TopDecor then frame.BorderContainer.TopDecor:SetAlpha(0) end
    end

    if frame.Blackout and frame.Blackout.Texture then
        frame.Blackout.Texture:SetColorTexture(0, 0, 0, STYLE.alpha.blackout)
    end

    RefreshHeaderState(frame.HeaderFrame, frame, theme)

    if frame.PreviousRewardNotification then
        ApplyFont(frame.PreviousRewardNotification, theme, STYLE.sizes.previousReward, 1, 1, 1, STYLE.alpha.previousReward)
    end

    for _, typeFrame in ipairs({ frame.RaidFrame, frame.MythicFrame, frame.PVPFrame, frame.WorldFrame }) do
        if typeFrame and typeFrame:IsShown() then
            RefreshTypeFrameState(typeFrame, theme)
        end
    end

    local concessionType = Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Concession
    if frame.Activities then
        for _, activityFrame in ipairs(frame.Activities) do
            if activityFrame.type == concessionType then
                RefreshConcessionVisualState(activityFrame, frame.selectedActivity, theme)
            else
                RefreshActivityVisualState(activityFrame, frame.selectedActivity, theme)
            end
        end
    end

    ApplyStoredAnchorOffset(
        frame.SelectRewardButton,
        "_euiOriginalPoints",
        STYLE.offsets.selectRewardButton.x,
        STYLE.offsets.selectRewardButton.y
    )
    RefreshButtonState(frame.SelectRewardButton, theme)
    RefreshCloseButtonState(frame.CloseButton, theme)
    RefreshOverlayState(frame.Overlay, theme)
    RefreshWarningDialogState(_G.WeeklyRewardExpirationWarningDialog, theme)
end

local function HookGreatVault()
    local frame = _G.WeeklyRewardsFrame
    if not frame or frame._euiGreatVaultHooked then return end

    frame._euiGreatVaultHooked = true

    frame:HookScript("OnShow", function(self)
        ScheduleGreatVaultRefresh(self)
    end)

    for _, methodName in ipairs({ "Refresh", "UpdateSelection", "SetUpConditionalActivities" }) do
        hooksecurefunc(frame, methodName, function(self)
            ScheduleGreatVaultRefresh(self)
        end)
    end

    RefreshGreatVaultFrame(frame)
end

local function InitializeGreatVaultDefaults()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if EllesmereUIDB.reskinGreatVault == nil then
        EllesmereUIDB.reskinGreatVault = true
    end
end

local function RegisterGreatVaultHooks()
    HookGreatVault()
end

InitializeGreatVaultDefaults()

do
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("ADDON_LOADED")
    hookFrame:RegisterEvent("PLAYER_LOGIN")
    hookFrame:SetScript("OnEvent", function(self, _, addon)
        if addon and addon ~= "Blizzard_WeeklyRewards" then return end

        if addon == "Blizzard_WeeklyRewards" or (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards")) then
            RegisterGreatVaultHooks()
            self:UnregisterEvent("ADDON_LOADED")
            self:UnregisterEvent("PLAYER_LOGIN")
        end
    end)
end
