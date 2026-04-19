-------------------------------------------------------------------------------
--  EllesmereUIChat.lua
--
--  Visual reskin + utility features:
--    - Dark unified background (chat + input as one panel)
--    - Tab restyling (accent underline, flat dark bg — matches CharSheet)
--    - Blizzard chrome removal
--    - Top-edge fade gradient
--    - Timestamps
--    - Thin EUI scrollbar
--    - Clickable URL links with copy popup
--    - Copy Chat button (session history)
--    - Search bar to filter messages
-------------------------------------------------------------------------------
local addonName, ns = ...
local EUI = _G.EllesmereUI
if not EUI then return end

ns.ECHAT = ns.ECHAT or {}
local ECHAT = ns.ECHAT

local CHAT_DEFAULTS = {
    profile = {
        chat = {
            enabled    = true,
            visibility = "always",
            bgAlpha    = 0.75,
            bgR        = 0.03,
            bgG        = 0.045,
            bgB        = 0.05,
        },
    },
}

local _chatDB
local function EnsureDB()
    if _chatDB then return _chatDB end
    if not EUI.Lite then return nil end
    _chatDB = EUI.Lite.NewDB("EllesmereUIChatDB", CHAT_DEFAULTS)
    _G._ECHAT_DB = _chatDB
    return _chatDB
end

function ECHAT.DB()
    local d = EnsureDB()
    if d and d.profile and d.profile.chat then
        return d.profile.chat
    end
    return { enabled = true, visibility = "always" }
end

local PP = EUI.PP
local fontPath
local function GetFont()
    if not fontPath then
        fontPath = (EUI.GetFontPath and EUI.GetFontPath()) or STANDARD_TEXT_FONT
    end
    return fontPath
end

local BG_R, BG_G, BG_B, BG_A = 0.03, 0.045, 0.05, 0.75
local EDIT_BG_R, EDIT_BG_G, EDIT_BG_B = 0.05, 0.065, 0.08
local TAB_FONT_SIZE = 10

-- Apply background settings from DB to all skinned chat frames
function ECHAT.ApplyBackground()
    local p = ECHAT.DB()
    BG_R = p.bgR or 0.03
    BG_G = p.bgG or 0.045
    BG_B = p.bgB or 0.05
    BG_A = p.bgAlpha or 0.75

    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf._euiBg then
            -- Update main bg texture
            local bgTex = cf._euiBg:GetRegions()
            if bgTex and bgTex.SetColorTexture then
                bgTex:SetColorTexture(BG_R, BG_G, BG_B, BG_A)
            end
        end
        -- Update tab backgrounds
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and tab._euiBg then
            tab._euiBg:SetColorTexture(BG_R, BG_G, BG_B, BG_A)
        end
    end
    -- Update sidebar bg
    local cf1 = _G.ChatFrame1
    if cf1 and cf1._euiSidebar then
        local sbBg = cf1._euiSidebar:GetRegions()
        if sbBg and sbBg.SetColorTexture then
            sbBg:SetColorTexture(BG_R, BG_G, BG_B, BG_A)
        end
    end
end

-- Refresh visibility based on DB settings (combat, mouseover, always, etc.)
function ECHAT.RefreshVisibility()
    local cfg = ECHAT.DB()
    if not cfg.enabled then
        -- Module disabled: hide everything
        for i = 1, 20 do
            local cf = _G["ChatFrame" .. i]
            if cf and cf._euiBg then cf._euiBg:SetAlpha(0) end
        end
        local cf1 = _G.ChatFrame1
        if cf1 and cf1._euiSidebar then cf1._euiSidebar:SetAlpha(0) end
        return
    end

    local vis = true
    if EUI and EUI.EvalVisibility then
        vis = EUI.EvalVisibility(cfg)
    end

    local alpha
    if vis == false then
        alpha = 0
    elseif vis == "mouseover" then
        alpha = 0
    else
        alpha = 1
    end

    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf._euiBg then cf._euiBg:SetAlpha(alpha) end
    end
    local cf1 = _G.ChatFrame1
    if cf1 and cf1._euiSidebar then cf1._euiSidebar:SetAlpha(alpha) end
end

-------------------------------------------------------------------------------
--  Chat history buffer (session only)
-------------------------------------------------------------------------------
local MAX_HISTORY = 2500
local chatHistory = {}

local function StripUIEscapes(text)
    if not text then return "" end
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    return text
end

local function CaptureMessage(frame, text)
    if not text then return end
    chatHistory[#chatHistory + 1] = text
    if #chatHistory > MAX_HISTORY then
        table.remove(chatHistory, 1)
    end
end

-------------------------------------------------------------------------------
--  URL detection + copy popup
-------------------------------------------------------------------------------
local URL_PATTERNS = {
    "%f[%S](%a[%w+.-]+://%S+)",
    "^(%a[%w+.-]+://%S+)",
    "%f[%S](www%.[-%w_%%]+%.%a%a+/%S+)",
    "^(www%.[-%w_%%]+%.%a%a+/%S+)",
    "%f[%S](www%.[-%w_%%]+%.%a%a+)",
    "^(www%.[-%w_%%]+%.%a%a+)",
}

local function ContainsURL(text)
    if not text then return false end
    for _, p in ipairs(URL_PATTERNS) do
        if text:match(p) then return true end
    end
    return false
end

local function WrapURLs(text)
    if not text then return text end
    for _, p in ipairs(URL_PATTERNS) do
        local eg = EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
        local hex = string.format("|cff%02x%02x%02x", eg.r * 255, eg.g * 255, eg.b * 255)
        text = text:gsub(p, hex .. "|H" .. addonName .. "url:%1|h[%1]|h|r")
    end
    return text
end

local copyDimmer

local function HideCopyPopup()
    if copyDimmer then copyDimmer:Hide() end
end

local function ShowCopyPopup(text)
    if not EUI.EnsureLoaded then return end
    EUI:EnsureLoaded()

    if not copyDimmer then
        local POPUP_W, POPUP_H = 520, 340
        local SCROLL_STEP = 60
        local SMOOTH_SPEED = 12

        -- Dimmer
        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:EnableMouseWheel(true)
        dimmer:SetScript("OnMouseWheel", function() end)
        dimmer:Hide()
        local dimTex = EUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25)
        dimTex:SetAllPoints()

        -- Popup frame
        local popup = CreateFrame("Frame", nil, dimmer)
        popup:SetSize(POPUP_W, POPUP_H)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:EnableMouse(true)

        local bg = EUI.SolidTex(popup, "BACKGROUND", 0.06, 0.08, 0.10, 0.95)
        bg:SetAllPoints()
        EUI.MakeBorder(popup, 1, 1, 1, 0.15, EUI.PanelPP)

        -- Plain ScrollFrame
        local sf = CreateFrame("ScrollFrame", nil, popup)
        sf:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -20)
        sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -20, 60)
        sf:SetFrameLevel(popup:GetFrameLevel() + 1)
        sf:EnableMouseWheel(true)

        local sc = CreateFrame("Frame", nil, sf)
        sc:SetWidth(sf:GetWidth() or (POPUP_W - 40))
        sc:SetHeight(1)
        sf:SetScrollChild(sc)

        -- EditBox inside scroll child
        local editBox = CreateFrame("EditBox", nil, sc)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFont(GetFont(), 12, EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag() or "")
        editBox:SetTextColor(1, 1, 1, 0.75)
        editBox:SetAllPoints(sc)
        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            dimmer:Hide()
        end)
        editBox:SetScript("OnChar", function(self)
            if self._readOnlyText then
                local cursor = self:GetCursorPosition()
                self:SetText(self._readOnlyText)
                self:SetCursorPosition(cursor)
            end
        end)
        editBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput and self._readOnlyText and self:GetText() ~= self._readOnlyText then
                local cursor = self:GetCursorPosition()
                self:SetText(self._readOnlyText)
                self:SetCursorPosition(cursor)
            end
        end)
        editBox:SetScript("OnMouseDown", function(self)
            self:SetFocus()
        end)
        sf:SetScript("OnMouseDown", function()
            editBox:SetFocus()
        end)

        -- Smooth scroll state
        local scrollTarget = 0
        local isSmoothing = false
        local smoothFrame = CreateFrame("Frame")
        smoothFrame:Hide()

        -- Custom scrollbar track
        local scrollTrack = CreateFrame("Frame", nil, sf)
        scrollTrack:SetWidth(4)
        scrollTrack:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -2, -4)
        scrollTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -2, 4)
        scrollTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
        scrollTrack:Hide()

        local trackBg = EUI.SolidTex(scrollTrack, "BACKGROUND", 1, 1, 1, 0.02)
        trackBg:SetAllPoints()

        -- Thumb
        local scrollThumb = CreateFrame("Button", nil, scrollTrack)
        scrollThumb:SetWidth(4)
        scrollThumb:SetHeight(60)
        scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
        scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 1)
        scrollThumb:EnableMouse(true)
        scrollThumb:RegisterForDrag("LeftButton")
        scrollThumb:SetScript("OnDragStart", function() end)
        scrollThumb:SetScript("OnDragStop", function() end)

        local thumbTex = EUI.SolidTex(scrollThumb, "ARTWORK", 1, 1, 1, 0.27)
        thumbTex:SetAllPoints()

        local isDragging = false
        local dragStartY, dragStartScroll

        local function UpdateThumb()
            local maxScroll = EUI.SafeScrollRange(sf)
            if maxScroll <= 0 then scrollTrack:Hide(); return end
            scrollTrack:Show()
            local trackH = scrollTrack:GetHeight()
            local visH = sf:GetHeight()
            local ratio = visH / (visH + maxScroll)
            local thumbH = math.max(30, trackH * ratio)
            scrollThumb:SetHeight(thumbH)
            local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
            scrollThumb:ClearAllPoints()
            scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -(scrollRatio * (trackH - thumbH)))
        end

        smoothFrame:SetScript("OnUpdate", function(_, elapsed)
            local cur = sf:GetVerticalScroll()
            local maxScroll = EUI.SafeScrollRange(sf)
            scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
            local diff = scrollTarget - cur
            if math.abs(diff) < 0.3 then
                sf:SetVerticalScroll(scrollTarget)
                UpdateThumb()
                isSmoothing = false
                smoothFrame:Hide()
                return
            end
            local newScroll = cur + diff * math.min(1, SMOOTH_SPEED * elapsed)
            newScroll = math.max(0, math.min(maxScroll, newScroll))
            sf:SetVerticalScroll(newScroll)
            UpdateThumb()
        end)

        local function SmoothScrollTo(target)
            local maxScroll = EUI.SafeScrollRange(sf)
            scrollTarget = math.max(0, math.min(maxScroll, target))
            if not isSmoothing then
                isSmoothing = true
                smoothFrame:Show()
            end
        end

        sf:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = EUI.SafeScrollRange(self)
            if maxScroll <= 0 then return end
            local base = isSmoothing and scrollTarget or self:GetVerticalScroll()
            SmoothScrollTo(base - delta * SCROLL_STEP)
        end)
        sf:SetScript("OnScrollRangeChanged", function() UpdateThumb() end)

        -- Thumb drag
        local function StopDrag()
            if not isDragging then return end
            isDragging = false
            scrollThumb:SetScript("OnUpdate", nil)
        end

        scrollThumb:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            isSmoothing = false; smoothFrame:Hide()
            isDragging = true
            local _, cy = GetCursorPosition()
            dragStartY = cy / self:GetEffectiveScale()
            dragStartScroll = sf:GetVerticalScroll()
            self:SetScript("OnUpdate", function(self2)
                if not IsMouseButtonDown("LeftButton") then StopDrag(); return end
                isSmoothing = false; smoothFrame:Hide()
                local _, cy2 = GetCursorPosition()
                cy2 = cy2 / self2:GetEffectiveScale()
                local deltaY = dragStartY - cy2
                local trackH = scrollTrack:GetHeight()
                local maxTravel = trackH - self2:GetHeight()
                if maxTravel <= 0 then return end
                local maxScroll = EUI.SafeScrollRange(sf)
                local newScroll = math.max(0, math.min(maxScroll, dragStartScroll + (deltaY / maxTravel) * maxScroll))
                scrollTarget = newScroll
                sf:SetVerticalScroll(newScroll)
                UpdateThumb()
            end)
        end)
        scrollThumb:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then StopDrag() end
        end)

        popup._editBox = editBox
        popup._scrollFrame = sf
        popup._scrollChild = sc

        -- Close button
        local closeBtn = CreateFrame("Button", nil, popup)
        closeBtn:SetSize(90, 24)
        closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
        closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EUI.MakeStyledButton(closeBtn, "Close", 10,
            EUI.RB_COLOURS, function() dimmer:Hide() end)

        -- Click dimmer to close
        dimmer:SetScript("OnMouseDown", function()
            if not popup:IsMouseOver() then dimmer:Hide() end
        end)

        -- Escape to close
        popup:EnableKeyboard(true)
        popup:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                dimmer:Hide()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        -- Reset scroll on hide
        dimmer:HookScript("OnHide", function()
            isSmoothing = false; smoothFrame:Hide()
            scrollTarget = 0
            sf:SetVerticalScroll(0)
        end)

        popup._dimmer = dimmer
        copyDimmer = dimmer
        copyDimmer._popup = popup
    end

    -- Populate
    local popup = copyDimmer._popup
    popup._editBox:SetText(text)
    popup._editBox._readOnlyText = text
    local sfW = popup._scrollFrame:GetWidth()
    popup._scrollChild:SetWidth(sfW)
    popup._editBox:SetWidth(sfW - 12)
    C_Timer.After(0.01, function()
        local h = popup._editBox:GetHeight()
        popup._scrollChild:SetHeight(h)
    end)
    copyDimmer:Show()
    C_Timer.After(0.05, function()
        popup._editBox:SetFocus()
        popup._editBox:SetCursorPosition(0)
    end)
end

-------------------------------------------------------------------------------
--  Small inline URL copy popup (matches friends list BattleTag popup)
-------------------------------------------------------------------------------
local urlBackdrop, urlPopup

local function HideUrlPopup()
    if urlPopup then urlPopup:Hide() end
    if urlBackdrop then urlBackdrop:Hide() end
end

local function ShowUrlPopup(url)
    if not urlPopup then
        urlBackdrop = CreateFrame("Button", nil, UIParent)
        urlBackdrop:SetFrameStrata("DIALOG")
        urlBackdrop:SetFrameLevel(499)
        urlBackdrop:SetAllPoints(UIParent)
        local bdTex = urlBackdrop:CreateTexture(nil, "BACKGROUND")
        bdTex:SetAllPoints()
        bdTex:SetColorTexture(0, 0, 0, 0.10)
        local fadeIn = urlBackdrop:CreateAnimationGroup()
        fadeIn:SetToFinalAlpha(true)
        local a = fadeIn:CreateAnimation("Alpha")
        a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.2)
        urlBackdrop._fadeIn = fadeIn
        urlBackdrop:RegisterForClicks("AnyUp")
        urlBackdrop:SetScript("OnClick", HideUrlPopup)
        urlBackdrop:Hide()

        urlPopup = CreateFrame("Frame", nil, UIParent)
        urlPopup:SetFrameStrata("DIALOG")
        urlPopup:SetFrameLevel(500)
        urlPopup:SetSize(340, 52)
        urlPopup:EnableMouse(true)
        local popFade = urlPopup:CreateAnimationGroup()
        popFade:SetToFinalAlpha(true)
        local pa = popFade:CreateAnimation("Alpha")
        pa:SetFromAlpha(0); pa:SetToAlpha(1); pa:SetDuration(0.2)
        urlPopup._fadeIn = popFade

        local bg = urlPopup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.08, 0.10, 0.97)
        if PP and PP.CreateBorder then
            PP.CreateBorder(urlPopup, 1, 1, 1, 0.15, 1, "OVERLAY", 7)
        end

        local hint = urlPopup:CreateFontString(nil, "OVERLAY")
        hint:SetFont(GetFont(), 8, "")
        hint:SetTextColor(1, 1, 1, 0.5)
        hint:SetPoint("TOP", urlPopup, "TOP", 0, -6)
        hint:SetText("Ctrl+C to copy, Escape to close")

        local eb = CreateFrame("EditBox", nil, urlPopup)
        eb:SetSize(300, 16)
        eb:SetPoint("TOP", hint, "BOTTOM", 0, -4)
        eb:SetFont(GetFont(), 11, "")
        eb:SetAutoFocus(false)
        eb:SetJustifyH("CENTER")
        local ebBg = eb:CreateTexture(nil, "BACKGROUND")
        ebBg:SetColorTexture(0.10, 0.12, 0.16, 1)
        ebBg:SetPoint("TOPLEFT", -6, 4); ebBg:SetPoint("BOTTOMRIGHT", 6, -4)
        if PP and PP.CreateBorder then
            PP.CreateBorder(eb, 1, 1, 1, 0.02, 1, "OVERLAY", 7)
        end
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); HideUrlPopup() end)
        eb:SetScript("OnKeyDown", function(self, key)
            if key == "C" and IsControlKeyDown() then
                C_Timer.After(0.05, HideUrlPopup)
            end
        end)
        eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        urlPopup:SetScript("OnMouseDown", function() urlPopup._eb:SetFocus(); urlPopup._eb:HighlightText() end)
        urlPopup._eb = eb
    end
    urlPopup._eb:SetText(url)
    urlPopup:ClearAllPoints()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    urlPopup:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx / scale, cy / scale + 10)
    urlBackdrop:SetAlpha(0); urlBackdrop:Show(); urlBackdrop._fadeIn:Play()
    urlPopup:SetAlpha(0); urlPopup:Show(); urlPopup._fadeIn:Play()
    urlPopup._eb:SetFocus(); urlPopup._eb:HighlightText()
end

hooksecurefunc("SetItemRef", function(link)
    if not link then return end
    local url = link:match("^" .. addonName .. "url:(.+)$")
    if url then ShowUrlPopup(url) end
end)

-------------------------------------------------------------------------------
--  Chat frame reskin
-------------------------------------------------------------------------------
local _skinned = {}

local function SkinChatFrame(cf)
    if not cf or _skinned[cf] then return end
    _skinned[cf] = true

    local name = cf:GetName()
    if not name then return end

    -- Unified dark background (covers chat + edit box as one panel)
    if not cf._euiBg then
        local bg = CreateFrame("Frame", nil, cf)
        local eb = _G[name .. "EditBox"]
        bg:SetPoint("TOPLEFT", cf, "TOPLEFT", -10, 3)
        bg:SetPoint("BOTTOMRIGHT", eb or cf, "BOTTOMRIGHT", 5, eb and -4 or -6)
        bg:SetFrameLevel(math.max(0, cf:GetFrameLevel() - 1))

        local bgTex = bg:CreateTexture(nil, "BACKGROUND")
        bgTex._euiOwned = true
        bgTex:SetAllPoints()
        bgTex:SetColorTexture(BG_R, BG_G, BG_B, BG_A)

        if PP and PP.CreateBorder then
            PP.CreateBorder(bg, 1, 1, 1, 0.06, 1, "OVERLAY", 7)
        end
        -- Hide bg for frames not yet visible to prevent flash on first show
        if not cf:IsShown() then
            bg:Hide()
            cf:HookScript("OnShow", function() bg:Show() end)
        end
        cf._euiBg = bg
    end

    -- Sidebar: 40px panel to the left of the main chat frame for icons.
    -- Parented to UIParent so it stays visible regardless of active tab.
    if name == "ChatFrame1" and not cf._euiSidebar then
        local sidebar = CreateFrame("Frame", nil, UIParent)
        sidebar:SetWidth(40)
        sidebar:SetPoint("TOPRIGHT", cf._euiBg, "TOPLEFT", 0, 0)
        sidebar:SetPoint("BOTTOMRIGHT", cf._euiBg, "BOTTOMLEFT", 0, 0)
        sidebar:SetFrameLevel(cf._euiBg:GetFrameLevel() + 1)

        local sbBg = sidebar:CreateTexture(nil, "BACKGROUND")
        sbBg:SetAllPoints()
        sbBg:SetColorTexture(BG_R, BG_G, BG_B, BG_A)

        if PP and PP.CreateBorder then
            PP.CreateBorder(sidebar, 1, 1, 1, 0.06, 1, "OVERLAY", 7)
        end

        -- 1px divider between sidebar and chat bg
        local onePx = (PP and PP.mult) or 1
        local sbDiv = sidebar:CreateTexture(nil, "OVERLAY", nil, 7)
        sbDiv:SetWidth(onePx)
        sbDiv:SetColorTexture(1, 1, 1, 0.06)
        sbDiv:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
        sbDiv:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
        if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(sbDiv) end

        -- Sidebar icons
        local MEDIA = "Interface\\AddOns\\EllesmereUIChat\\Media\\"
        local ICON_SIZE = 22
        local ICON_SPACING = 10
        local ICON_ALPHA = 0.4
        local ICON_HOVER_ALPHA = 0.9

        local function MakeSidebarIcon(parent, texPath, anchorTo, anchorPoint, yOff)
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(ICON_SIZE, ICON_SIZE)
            if anchorTo then
                btn:SetPoint("TOP", anchorTo, "BOTTOM", 0, -ICON_SPACING)
            else
                btn:SetPoint(anchorPoint or "TOP", parent, anchorPoint or "TOP", 0, yOff or -ICON_SPACING)
            end
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexture(texPath)
            icon:SetDesaturated(true)
            icon:SetVertexColor(1, 1, 1, ICON_ALPHA)
            btn:HookScript("OnEnter", function() icon:SetVertexColor(1, 1, 1, ICON_HOVER_ALPHA) end)
            btn:HookScript("OnLeave", function() icon:SetVertexColor(1, 1, 1, ICON_ALPHA) end)
            btn._icon = icon
            return btn
        end

        -- Top group: Friends, Count, Copy, Voice, Settings
        local friendsBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_friends.png", nil, "TOP", -ICON_SPACING)
        friendsBtn:SetSize(26, 26)

        -- Online friends count below the friends icon
        local friendsCount = sidebar:CreateFontString(nil, "OVERLAY")
        friendsCount:SetFont(GetFont(), 9, "")
        friendsCount:SetTextColor(1, 1, 1, 0.5)
        friendsCount:SetPoint("TOP", friendsBtn, "BOTTOM", 0, 7)
        friendsCount:SetText("0")

        -- Highlight count when hovering friends icon
        friendsBtn:HookScript("OnEnter", function() friendsCount:SetTextColor(1, 1, 1, 0.9) end)
        friendsBtn:HookScript("OnLeave", function() friendsCount:SetTextColor(1, 1, 1, 0.5) end)

        local function UpdateFriendsCount()
            local _, numOnline = BNGetNumFriends()
            local wowOnline = C_FriendList.GetNumOnlineFriends()
            friendsCount:SetText(numOnline + wowOnline)
        end

        local fcEvents = CreateFrame("Frame")
        fcEvents:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
        fcEvents:RegisterEvent("BN_FRIEND_INFO_CHANGED")
        fcEvents:RegisterEvent("FRIENDLIST_UPDATE")
        fcEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
        fcEvents:SetScript("OnEvent", UpdateFriendsCount)

        sidebar._friendsCount = friendsCount

        local copyBtn    = MakeSidebarIcon(sidebar, MEDIA .. "chat_copy.png")
        copyBtn:ClearAllPoints()
        copyBtn:SetPoint("TOP", friendsCount, "BOTTOM", 0, -ICON_SPACING)
        local voiceBtn   = MakeSidebarIcon(sidebar, MEDIA .. "chat_voice.png", copyBtn)
        local settingsBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_settings.png", voiceBtn)

        -- Bottom: Scroll (anchored to bottom with gap)
        local scrollBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_scroll2.png")
        scrollBtn:SetSize(22, 22)
        scrollBtn:ClearAllPoints()
        scrollBtn:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, ICON_SPACING)

        -- Scroll to bottom
        scrollBtn:SetScript("OnClick", function()
            local cf1 = ChatFrame1
            if cf1 and cf1.ScrollBar and cf1.ScrollBar.SetScrollPercentage then
                cf1.ScrollBar:SetScrollPercentage(1)
            end
        end)

        -- Copy chat history
        copyBtn:SetScript("OnClick", function()
            local lines = {}
            for i = 1, #chatHistory do
                lines[#lines + 1] = StripUIEscapes(chatHistory[i])
            end
            local fullText = table.concat(lines, "\n")
            if fullText == "" then fullText = "(No chat history this session)" end
            ShowCopyPopup(fullText, 500, 400, true)
        end)

        -- Friends button toggles FriendsFrame
        friendsBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            ToggleFriendsFrame()
        end)

        -- Voice button toggles ChannelFrame
        voiceBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            ToggleChannelFrame()
        end)

        -- Settings button opens EUI options directly to Chat module
        settingsBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            EUI:ShowModule("EllesmereUIChat")
        end)

        sidebar._friendsBtn = friendsBtn
        sidebar._copyBtn = copyBtn
        sidebar._voiceBtn = voiceBtn
        sidebar._settingsBtn = settingsBtn
        sidebar._scrollBtn = scrollBtn

        cf._euiSidebar = sidebar
    end

    -- Top clip: prevent text bleeding into the tab area.
    -- Left/right padding is not possible without a custom renderer --
    -- Blizzard's font strings are positioned absolutely by the layout
    -- engine and ignore FSC container bounds.
    local fsc = cf.FontStringContainer
    if fsc and not cf._euiTopClipped then
        cf._euiTopClipped = true
        fsc:ClearAllPoints()
        fsc:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, -6)
        fsc:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)
    end

    -- Horizontal divider above input field
    if not cf._euiInputDiv then
        local onePx = (PP and PP.mult) or 1
        local div = cf._euiBg:CreateTexture(nil, "OVERLAY", nil, 7)
        div._euiOwned = true
        div:SetHeight(onePx)
        div:SetColorTexture(1, 1, 1, 0.06)
        div:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", -10, -8)
        div:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 10, -8)
        if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(div) end
        cf._euiInputDiv = div
    end

    -- Set custom font on the message frame
    local _, fontSize = cf:GetFont()
    cf:SetFont(GetFont(), fontSize or 12, "")
    if cf.SetShadowOffset then cf:SetShadowOffset(1, -1) end
    if cf.SetShadowColor then cf:SetShadowColor(0, 0, 0, 0.8) end

    -- Compact 24-hour timestamps inline with message text
    if SetCVar then
        SetCVar("showTimestamps", "%H:%M ")
    end

    -- Prevent tabs and combat log filter bar from auto-fading.
    -- Force tabs to stay visible by keeping their alpha at 1.
    local tab = _G[name .. "Tab"]
    if tab then
        tab:SetAlpha(1)
        hooksecurefunc(tab, "SetAlpha", function(self, a)
            if a < 1 then self:SetAlpha(1) end
        end)
    end

    -- Edit box reskin
    local eb = _G[name .. "EditBox"]
    if eb and not eb._euiSkinned then
        eb._euiSkinned = true
        for _, texName in ipairs({
            name .. "EditBoxLeft", name .. "EditBoxMid", name .. "EditBoxRight",
            name .. "EditBoxFocusLeft", name .. "EditBoxFocusMid", name .. "EditBoxFocusRight",
        }) do
            local tex = _G[texName]
            if tex then tex:SetAlpha(0) end
        end
        -- Position flush below chat frame (23px tall)
        eb:ClearAllPoints()
        eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -10, -8)
        eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 5, -8)
        eb:SetHeight(23)

        eb:SetFont(GetFont(), 12, "")
        eb:SetTextInsets(8, 8, 0, 0)

        -- Style the channel header (e.g. "[2. Trade - City]: ")
        if eb.header then eb.header:SetFont(GetFont(), 12, "") end
        if eb.headerSuffix then eb.headerSuffix:SetFont(GetFont(), 12, "") end
        -- Also hide the focus border textures (Blizzard's input chrome)
        if eb.focusLeft then eb.focusLeft:SetAlpha(0) end
        if eb.focusMid then eb.focusMid:SetAlpha(0) end
        if eb.focusRight then eb.focusRight:SetAlpha(0) end
    end

    -- Style tabs (same pattern as CharSheet/InspectSheet)
    local tab = _G[name .. "Tab"]
    if tab and not tab._euiSkinned then
        tab._euiSkinned = true
        -- Strip all Blizzard tab textures
        for j = 1, select("#", tab:GetRegions()) do
            local region = select(j, tab:GetRegions())
            if region and region:IsObjectType("Texture") then
                region:SetTexture("")
            end
        end
        -- Hide named texture fields (normal, active, highlight variants)
        for _, key in ipairs({
            "Left", "Middle", "Right",
            "ActiveLeft", "ActiveMiddle", "ActiveRight",
            "HighlightLeft", "HighlightMiddle", "HighlightRight",
            "leftTexture", "middleTexture", "rightTexture",
            "leftSelectedTexture", "middleSelectedTexture", "rightSelectedTexture",
            "leftHighlightTexture", "middleHighlightTexture", "rightHighlightTexture",
        }) do
            if tab[key] then tab[key]:SetAlpha(0) end
        end
        local hl = tab:GetHighlightTexture()
        if hl then hl:SetTexture("") end
        -- Hide glow frame
        if tab.glow then tab.glow:SetAlpha(0) end

        -- Shrink tab height by 8px and enforce it via hook
        local targetH = tab:GetHeight() - 8
        if targetH > 15 then
            tab:SetHeight(targetH)
            local _ignoreH = false
            hooksecurefunc(tab, "SetHeight", function(self, h)
                if _ignoreH then return end
                if h ~= targetH and h > 15 then
                    _ignoreH = true
                    self:SetHeight(targetH)
                    _ignoreH = false
                end
            end)
        end

        -- Raise tabs above all chat frames so they aren't occluded
        tab:SetFrameStrata("HIGH")

        -- Persistent SetPoint hook to correct tab anchoring.
        -- ChatFrame1: shift 10px left to align with extended bg.
        -- Other tabs: fix Blizzard's LEFT/LEFT temp tab pattern to LEFT/RIGHT.
        local _tabIgnoreSetPoint = false
        if name == "ChatFrame1" then
            hooksecurefunc(tab, "SetPoint", function(self, point, rel, relPoint, x, y)
                if _tabIgnoreSetPoint then return end
                _tabIgnoreSetPoint = true
                self:SetPoint(point, rel, relPoint, (x or 0) - 10, y or 0)
                _tabIgnoreSetPoint = false
            end)
            if tab:GetPoint(1) then
                local pt, rel, relPt, x, y = tab:GetPoint(1)
                _tabIgnoreSetPoint = true
                tab:SetPoint(pt, rel, relPt, (x or 0) - 10, y or 0)
                _tabIgnoreSetPoint = false
            end
        else
            hooksecurefunc(tab, "SetPoint", function(self, point, rel, relPoint, x, y)
                if _tabIgnoreSetPoint then return end
                if point == "LEFT" and relPoint == "LEFT" then
                    _tabIgnoreSetPoint = true
                    self:SetPoint("LEFT", rel, "RIGHT", 0, -5)
                    _tabIgnoreSetPoint = false
                elseif point == "BOTTOMLEFT" then
                    _tabIgnoreSetPoint = true
                    self:SetPoint(point, rel, relPoint, (x or 0) - 10, y or 0)
                    _tabIgnoreSetPoint = false
                end
            end)
        end

        -- Dark tab background (matches chat box opacity)
        if not tab._euiBg then
            tab._euiBg = tab:CreateTexture(nil, "BACKGROUND")
            tab._euiBg._euiOwned = true
            tab._euiBg:SetAllPoints()
            tab._euiBg:SetColorTexture(BG_R, BG_G, BG_B, BG_A)
        end

        -- Active highlight overlay removed -- accent underline is sufficient.
        -- Field kept for UpdateTabColors compatibility.
        tab._euiActiveHL = nil

        -- Replace Blizzard label with our own FontString (matches CharSheet)
        local blizLabel = tab:GetFontString()
        local labelText = blizLabel and blizLabel:GetText() or ("Tab")
        if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end
        tab:SetPushedTextOffset(0, 0)

        if not tab._euiLabel then
            local label = tab:CreateFontString(nil, "OVERLAY")
            label:SetFont(GetFont(), TAB_FONT_SIZE, "")
            label:SetPoint("CENTER", tab, "CENTER", 0, 0)
            label:SetJustifyH("CENTER")
            label:SetWordWrap(false)
            label:SetWidth(tab:GetWidth() * 0.8)
            label:SetText(labelText)
            tab._euiLabel = label
            hooksecurefunc(tab, "SetWidth", function(self)
                label:SetWidth(self:GetWidth() * 0.8)
            end)
            hooksecurefunc(tab, "SetText", function(_, newText)
                if newText and label then label:SetText(newText) end
            end)
        end

        -- Accent underline (active tab indicator).
        -- Parented to UIParent so Blizzard's tab alpha/show/hide cycles
        -- don't affect it. Anchored to the tab for positioning.
        if not tab._euiUnderline then
            local EG = EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
            local ulFrame = CreateFrame("Frame", nil, UIParent)
            ulFrame:SetFrameStrata("HIGH")
            ulFrame:SetFrameLevel(tab:GetFrameLevel() + 5)
            ulFrame:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
            ulFrame:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
            if PP and PP.DisablePixelSnap then
                ulFrame:SetHeight(PP.mult or 1)
            else
                ulFrame:SetHeight(1)
            end
            local ul = ulFrame:CreateTexture(nil, "OVERLAY", nil, 6)
            ul:SetAllPoints()
            ul:SetColorTexture(EG.r, EG.g, EG.b, 1)
            if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(ul) end
            if EUI.RegAccent then
                EUI.RegAccent({ type = "solid", obj = ul, a = 1 })
            end
            ulFrame:Hide()
            tab._euiUnderline = ulFrame
        end
    end

    -- Hide Blizzard button frame + its background (persistent)
    local btnFrame = _G[name .. "ButtonFrame"]
    if btnFrame then
        btnFrame:SetAlpha(0)
        btnFrame:EnableMouse(false)
        btnFrame:SetWidth(0.1)
        if btnFrame.Background then btnFrame.Background:SetAlpha(0) end
        hooksecurefunc(btnFrame, "SetAlpha", function(self, a)
            if a > 0 then self:SetAlpha(0) end
        end)
    end

    -- Reposition resize button to align with our bg
    local resizeBtn = _G[name .. "ResizeButton"]
    if resizeBtn then
        resizeBtn:ClearAllPoints()
        resizeBtn:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 7, -30)
    end

    -- Hide scroll buttons + scroll-to-bottom
    for _, suffix in ipairs({"BottomButton", "DownButton", "UpButton"}) do
        local btn = _G[name .. suffix]
        if btn then btn:SetAlpha(0); btn:EnableMouse(false) end
    end
    if cf.ScrollToBottomButton then
        cf.ScrollToBottomButton:SetAlpha(0)
        cf.ScrollToBottomButton:EnableMouse(false)
        hooksecurefunc(cf.ScrollToBottomButton, "SetAlpha", function(self, a)
            if a > 0 then self:SetAlpha(0) end
        end)
        -- Walk children (arrow textures, flash frames)
        if cf.ScrollToBottomButton.GetChildren then
            for i = 1, select("#", cf.ScrollToBottomButton:GetChildren()) do
                local child = select(i, cf.ScrollToBottomButton:GetChildren())
                if child then child:SetAlpha(0); child:EnableMouse(false) end
            end
        end
    end

    -- Minimize button
    local minBtn = _G[name .. "MinimizeButton"]
    if minBtn then minBtn:SetAlpha(0); minBtn:EnableMouse(false) end

    -- Strip ALL Blizzard textures from the chat frame by walking every
    -- region. Only targets Texture objects and skips anything we created
    -- (our textures have _eui prefix fields).
    if cf.GetRegions then
        for i = 1, select("#", cf:GetRegions()) do
            local region = select(i, cf:GetRegions())
            if region and region:IsObjectType("Texture") and not region._euiOwned then
                region:SetTexture("")
                region:SetAtlas("")
                region:SetAlpha(0)
            end
        end
    end
    -- Also strip the Background child frame and its regions
    if cf.Background then
        cf.Background:SetAlpha(0)
        if cf.Background.GetRegions then
            for i = 1, select("#", cf.Background:GetRegions()) do
                local region = select(i, cf.Background:GetRegions())
                if region and region:IsObjectType("Texture") then
                    region:SetAlpha(0)
                end
            end
        end
    end

    -- Combat Log: replace Blizzard's filter tab bar with our own dark bar
    -- that matches the chat panel's width and style.
    if name == "ChatFrame2" then
        local qbf = _G.CombatLogQuickButtonFrame_Custom
        if qbf and not qbf._euiSkinned then
            qbf._euiSkinned = true

            -- Strip all default textures
            if qbf.GetRegions then
                for i = 1, select("#", qbf:GetRegions()) do
                    local region = select(i, qbf:GetRegions())
                    if region and region:IsObjectType("Texture") then
                        region:SetAlpha(0)
                    end
                end
            end

            -- Anchor flush: bottom of filter bar meets top of bg (cf top + 3),
            -- width matches bg (-10 left, +5 right)
            qbf:ClearAllPoints()
            qbf:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -10, 3)
            qbf:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", 10, 3)
            qbf:SetHeight(24)

            -- Dark background matching our panel
            local qbfBg = qbf:CreateTexture(nil, "BACKGROUND")
            qbfBg:SetAllPoints()
            qbfBg:SetColorTexture(BG_R, BG_G, BG_B, 1)


            -- Bottom divider (separates filter tabs from messages)
            local onePx = (PP and PP.mult) or 1
            local qbfDiv = qbf:CreateTexture(nil, "OVERLAY", nil, 7)
            qbfDiv._euiOwned = true
            qbfDiv:SetHeight(onePx)
            qbfDiv:SetColorTexture(1, 1, 1, 0.06)
            qbfDiv:SetPoint("BOTTOMLEFT", qbf, "BOTTOMLEFT", 0, 0)
            qbfDiv:SetPoint("BOTTOMRIGHT", qbf, "BOTTOMRIGHT", 0, 0)
            if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(qbfDiv) end

            -- Restyle the filter buttons and accent-color the active one
            local EG = EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
            local clFilterBtns = {}
            local function UpdateCLFilterColors()
                for _, btn in ipairs(clFilterBtns) do
                    local fs = btn:GetFontString()
                    if not fs then return end
                    local isActive = btn.GetChecked and btn:GetChecked()
                    if isActive then
                        local eg = EUI.ELLESMERE_GREEN or EG
                        fs:SetTextColor(eg.r, eg.g, eg.b, 1)
                    else
                        fs:SetTextColor(1, 1, 1, 0.5)
                    end
                end
            end
            if qbf.GetChildren then
                for i = 1, select("#", qbf:GetChildren()) do
                    local btn = select(i, qbf:GetChildren())
                    if btn and btn:IsObjectType("CheckButton") or (btn and btn:IsObjectType("Button")) then
                        clFilterBtns[#clFilterBtns + 1] = btn
                        -- Strip button textures
                        if btn.GetRegions then
                            for j = 1, select("#", btn:GetRegions()) do
                                local rgn = select(j, btn:GetRegions())
                                if rgn and rgn:IsObjectType("Texture") then
                                    rgn:SetAlpha(0)
                                end
                            end
                        end
                        -- Restyle the text
                        local fs = btn:GetFontString()
                        if fs then
                            fs:SetFont(GetFont(), TAB_FONT_SIZE, "")
                        end
                        -- Update colors on click
                        btn:HookScript("OnClick", UpdateCLFilterColors)
                    end
                end
            end
            UpdateCLFilterColors()
            if EUI.RegAccent then
                EUI.RegAccent({ type = "callback", fn = UpdateCLFilterColors })
            end

            -- Prevent the filter bar from fading with the chat frame
            qbf:SetAlpha(1)
            hooksecurefunc(qbf, "SetAlpha", function(self, a)
                if a < 1 then self:SetAlpha(1) end
            end)

            -- Don't extend bg upward -- the filter bar has its own bg (qbfBg).
            -- Keeping both chat frame bgs the same size prevents visual
            -- jumping when switching between General and Combat Log tabs.
        end
    end

    -- Hide Blizzard's ScrollBar + all descendants (track, thumb, arrows)
    if cf.ScrollBar then
        local function KillFrame(f)
            f:SetAlpha(0)
            f:EnableMouse(false)
            if f.GetChildren then
                for i = 1, select("#", f:GetChildren()) do
                    local child = select(i, f:GetChildren())
                    if child then KillFrame(child) end
                end
            end
        end
        KillFrame(cf.ScrollBar)
    end

    -- Thin scrollbar: reads scroll state from Blizzard's own ScrollBar.
    -- Clickable + draggable. Parented to our bg frame.
    if not cf._euiScrollTrack and cf.ScrollBar then
        local blizSB = cf.ScrollBar
        local track = CreateFrame("Button", nil, cf._euiBg)
        track:SetFrameLevel(cf._euiBg:GetFrameLevel() + 10)
        track:SetWidth(8)
        track:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 5, -2)
        track:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 5, 2)
        track:EnableMouse(true)
        track:RegisterForClicks("AnyUp")

        local thumb = track:CreateTexture(nil, "ARTWORK")
        thumb:SetColorTexture(1, 1, 1, 0.25)
        thumb:SetWidth(3)
        thumb:Hide()

        -- Only show scrollbar when hovering the chat area
        local _hovered = false
        cf._euiBg:EnableMouse(true)
        cf._euiBg:SetScript("OnEnter", function() _hovered = true end)
        cf._euiBg:SetScript("OnLeave", function() _hovered = false end)
        track:HookScript("OnEnter", function() _hovered = true end)
        track:HookScript("OnLeave", function() _hovered = false end)

        local _dragging = false
        local _dragOffsetY = 0

        local function GetThumbState()
            local pct = blizSB.GetScrollPercentage and blizSB:GetScrollPercentage()
            local ext = blizSB.GetVisibleExtentPercentage and blizSB:GetVisibleExtentPercentage()
            if not pct or not ext or ext >= 1 then return nil end
            local trackH = track:GetHeight()
            if trackH <= 0 then return nil end
            local thumbH = math.max(20, trackH * ext)
            return pct, ext, trackH, thumbH
        end

        local function UpdateThumb()
            local pct, ext, trackH, thumbH = GetThumbState()
            if not pct or (not _hovered and not _dragging) then thumb:Hide(); return end
            local yOff = (trackH - thumbH) * pct
            thumb:ClearAllPoints()
            thumb:SetHeight(thumbH)
            thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -yOff)
            thumb:Show()
        end

        local function SetScrollFromY(cursorY)
            local pct, ext, trackH, thumbH = GetThumbState()
            if not pct then return end
            local _, trackTop = track:GetCenter()
            trackTop = select(2, track:GetRect()) + trackH
            local localY = trackTop - cursorY - _dragOffsetY
            local scrollRange = trackH - thumbH
            if scrollRange <= 0 then return end
            local newPct = math.max(0, math.min(1, localY / scrollRange))
            if blizSB.SetScrollPercentage then
                blizSB:SetScrollPercentage(newPct)
            end
        end

        -- Click on track: jump to that position
        track:SetScript("OnClick", function(self, button)
            local pct, ext, trackH, thumbH = GetThumbState()
            if not pct then return end
            local _, cursorY = GetCursorPosition()
            cursorY = cursorY / self:GetEffectiveScale()
            local trackBottom = select(2, track:GetRect())
            local localY = cursorY - trackBottom
            local scrollRange = trackH - thumbH
            if scrollRange <= 0 then return end
            local newPct = math.max(0, math.min(1, 1 - (localY - thumbH / 2) / scrollRange))
            if blizSB.SetScrollPercentage then
                blizSB:SetScrollPercentage(newPct)
            end
            UpdateThumb()
        end)

        -- Drag: mousedown on track starts drag, mouseup ends
        track:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            local pct, ext, trackH, thumbH = GetThumbState()
            if not pct then return end
            local _, cursorY = GetCursorPosition()
            cursorY = cursorY / self:GetEffectiveScale()
            -- Calculate offset from thumb top so dragging feels anchored
            local trackBottom = select(2, track:GetRect())
            local thumbTop = trackBottom + trackH - (trackH - thumbH) * pct
            _dragOffsetY = cursorY - thumbTop + thumbH
            _dragging = true
        end)

        track:SetScript("OnMouseUp", function() _dragging = false end)

        track:SetScript("OnUpdate", function(self, dt)
            if _dragging then
                local _, cursorY = GetCursorPosition()
                cursorY = cursorY / self:GetEffectiveScale()
                -- Position thumb directly from cursor for smooth visual
                local pct, ext, trackH, thumbH = GetThumbState()
                if pct then
                    local trackBottom = select(2, track:GetRect())
                    local localY = cursorY - trackBottom - _dragOffsetY
                    local scrollRange = trackH - thumbH
                    if scrollRange > 0 then
                        local visualPct = math.max(0, math.min(1, 1 - localY / scrollRange))
                        local yOff = (trackH - thumbH) * visualPct
                        thumb:ClearAllPoints()
                        thumb:SetHeight(thumbH)
                        thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -yOff)
                        thumb:Show()
                        -- Feed scroll position to Blizzard
                        if blizSB.SetScrollPercentage then
                            blizSB:SetScrollPercentage(visualPct)
                        end
                    end
                end
            else
                self._elapsed = (self._elapsed or 0) + dt
                if self._elapsed < 0.1 then return end
                self._elapsed = 0
                UpdateThumb()
            end
        end)

        cf._euiScrollTrack = track
    end
end

-------------------------------------------------------------------------------
--  Tab color updater (active = accent + underline, inactive = dimmed)
-------------------------------------------------------------------------------
local function UpdateTabColors()
    local selected = SELECTED_CHAT_FRAME
    if GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow then
        selected = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) or selected
    end
    for i = 1, 20 do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab then
            if tab:IsShown() then
                local cf = _G["ChatFrame" .. i]
                local isActive = cf and cf == selected
                if tab._euiLabel then
                    tab._euiLabel:SetTextColor(1, 1, 1, isActive and 1 or 0.5)
                end
                if tab._euiUnderline then
                    tab._euiUnderline:SetShown(isActive)
                end
                if tab._euiActiveHL then
                    tab._euiActiveHL:SetShown(isActive)
                end
                if tab._euiBg then
                    tab._euiBg:SetColorTexture(BG_R, BG_G, BG_B, isActive and BG_A or (BG_A * 0.67))
                end
            elseif tab._euiUnderline then
                tab._euiUnderline:Hide()
            end
        end
    end
end


-------------------------------------------------------------------------------
--  Initialization
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    EnsureDB()

    -- Apply saved bg settings before skinning
    local p = ECHAT.DB()
    BG_R = p.bgR or BG_R
    BG_G = p.bgG or BG_G
    BG_B = p.bgB or BG_B
    BG_A = p.bgAlpha or BG_A

    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf then
            SkinChatFrame(cf)
            hooksecurefunc(cf, "AddMessage", CaptureMessage)
        end
    end
    hooksecurefunc("FCF_OpenTemporaryWindow", function()
        C_Timer.After(0, function()
            for i = 1, 20 do
                local cf = _G["ChatFrame" .. i]
                if cf and not _skinned[cf] then
                    SkinChatFrame(cf)
                    hooksecurefunc(cf, "AddMessage", CaptureMessage)
                end
                -- Show bg if it was hidden at login
                if cf and cf._euiBg and not cf._euiBg:IsShown() and cf:IsShown() then
                    cf._euiBg:Show()
                end
                -- Re-hide ButtonFrame that Blizzard may have re-shown
                if cf then
                    local cfName = cf:GetName()
                    if cfName then
                        local btnFrame = _G[cfName .. "ButtonFrame"]
                        if btnFrame then
                            btnFrame:SetAlpha(0)
                            btnFrame:EnableMouse(false)
                            btnFrame:SetWidth(0.1)
                            if btnFrame.Background then btnFrame.Background:SetAlpha(0) end
                        end
                    end
                end
                -- Re-trigger SetPoint and re-strip textures on non-primary tabs
                if i > 1 then
                    local tab = _G["ChatFrame" .. i .. "Tab"]
                    if tab and tab:IsShown() then
                        -- Strip textures Blizzard re-added (chat bubble icon)
                        for j = 1, select("#", tab:GetRegions()) do
                            local region = select(j, tab:GetRegions())
                            if region and region:IsObjectType("Texture") and not region._euiOwned then
                                region:SetTexture("")
                                region:SetAlpha(0)
                            end
                        end
                        -- Re-trigger SetPoint so our hooks can correct anchors
                        if tab:GetPoint(1) then
                            local pt, rel, relPt, x, y = tab:GetPoint(1)
                            tab:SetPoint(pt, rel, relPt, x, y)
                        end
                    end
                end
            end
            UpdateTabColors()
        end)
    end)

    UpdateTabColors()
    local _tabColorTimer
    local function DeferredTabColorUpdate()
        if _tabColorTimer then return end
        _tabColorTimer = true
        C_Timer.After(0, function()
            _tabColorTimer = nil
            UpdateTabColors()
        end)
    end
    -- Tab click, dock/undock all trigger active tab refresh
    hooksecurefunc("FCF_Tab_OnClick", DeferredTabColorUpdate)
    hooksecurefunc("FCF_DockUpdate", DeferredTabColorUpdate)
    hooksecurefunc("FCF_UnDockFrame", function()
        DeferredTabColorUpdate()
    end)
    hooksecurefunc("FCF_Close", DeferredTabColorUpdate)


    if EUI.RegAccent then
        EUI.RegAccent({ type = "callback", fn = UpdateTabColors })
    end

    -- Timestamps are handled by our AddMessage hook, not Blizzard's CVar.

    -- URL filter
    local function URLFilter(self, event, msg, ...)
        if msg and ContainsURL(msg) then
            return false, WrapURLs(msg), ...
        end
        return false, msg, ...
    end
    for _, ev in ipairs({
        "CHAT_MSG_SAY", "CHAT_MSG_YELL",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
        "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
        "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
        "CHAT_MSG_CHANNEL",
    }) do
        ChatFrame_AddMessageEventFilter(ev, URLFilter)
    end

    -- Hide global Blizzard social buttons
    for _, frameName in ipairs({
        "QuickJoinToastButton", "ChatFrameMenuButton", "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
    }) do
        local f = _G[frameName]
        if f then f:SetAlpha(0); f:EnableMouse(false) end
    end
end)
