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
            bgAlpha    = 0.65,
            bgR        = 0.03,
            bgG        = 0.045,
            bgB        = 0.05,
            timestampFormat = "%I:%M ",
            font = "__global",
            outlineMode = "__global",
            fontSize = 12,
            tabFontSize = 10,
            sidebarVisibility = "always",
            hideCombatLogTab = false,
            hideBorders = false,
            showFriends = true,
            showCopy = true,
            showPortals = true,
            showVoice = false,
            showSettings = true,
            showScroll = true,
            hideTooltipOnHover = true,
            sidebarRight = false,
            iconR = 1,
            iconG = 1,
            iconB = 1,
            iconUseAccent = false,
            idleFadeDelay = 15,
            idleFadeStrength = 40,
            inputOnTop = false,
            lockChatSize = false,
            hideSidebarBg = false,
            sidebarIconScale = 1.0,
            sidebarIconSpacing = 10,
            freeMoveIcons = false,
            iconPositions = {},
            sidebarIconOrder = {
                showCopy = 1,
                showPortals = 2,
                showVoice = 3,
                showSettings = 4,
            },
        },
    },
}

local _chatDB
local function EnsureDB()
    if _chatDB then return _chatDB end
    if not EUI.Lite then return nil end
    _chatDB = EUI.Lite.NewDB("EllesmereUIChatDB", CHAT_DEFAULTS)
    _G._ECHAT_DB = _chatDB
    -- One-time migration: mouseover -> always (idle fade replaces it)
    if _chatDB.profile and _chatDB.profile.chat
        and _chatDB.profile.chat.visibility == "mouseover" then
        _chatDB.profile.chat.visibility = "always"
    end
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
local function GetFont()
    local cfg = ECHAT.DB()
    local fontKey = cfg.font or "__global"
    if fontKey == "__global" then
        return (EUI.GetFontPath and EUI.GetFontPath()) or STANDARD_TEXT_FONT
    end
    return (EUI.ResolveFontName and EUI.ResolveFontName(fontKey)) or STANDARD_TEXT_FONT
end

local function GetOutlineFlag()
    local cfg = ECHAT.DB()
    local mode = cfg.outlineMode or "__global"
    if mode == "__global" then
        return (EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag()) or ""
    end
    if mode == "outline" then return "OUTLINE" end
    if mode == "thick" then return "THICKOUTLINE" end
    return ""
end

local _hiddenParent = CreateFrame("Frame")
_hiddenParent:Hide()

-- Unified fade system: all alpha changes go through a target + lerp.
local _visChatVisible = true
local function GetIdleFadeAlpha()
    local cfg = ECHAT.DB()
    local strength = cfg.idleFadeStrength or 40
    return 1 - (strength / 100)
end
local _idleFadeActive = false
local FADE_IN_DURATION = 0.35
local FADE_OUT_DURATION = 1.0
local IDLE_FADE_OUT_DURATION = 2.0
local _chatAlphaTarget = 1
local _chatAlphaCurrent = 1
local _chatFadeFrame = CreateFrame("Frame")
_chatFadeFrame:Hide()

-- Taint-safe mouse-over check using cursor position instead of IsMouseOver().
-- IsMouseOver() returns secret booleans on temporary frames in M+.
local function IsCursorOver(frame)
    if not frame or not frame:IsVisible() then return false end
    local left, bottom, width, height = frame:GetRect()
    if not left then return false end
    local cx, cy = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    return cx >= left and cx <= left + width and cy >= bottom and cy <= bottom + height
end

-- Batch cursor check: reads cursor position once, tests a frame using
-- pre-fetched raw cursor coords. Avoids repeated GetCursorPosition calls.
local _rawCX, _rawCY = 0, 0
local function RefreshCursorPos()
    _rawCX, _rawCY = GetCursorPosition()
end
local function IsCursorOverCached(frame)
    if not frame or not frame:IsVisible() then return false end
    local left, bottom, width, height = frame:GetRect()
    if not left then return false end
    local scale = frame:GetEffectiveScale()
    local cx, cy = _rawCX / scale, _rawCY / scale
    return cx >= left and cx <= left + width and cy >= bottom and cy <= bottom + height
end

local BG_R, BG_G, BG_B, BG_A = 0.03, 0.045, 0.05, 0.70

local EDIT_BG_R, EDIT_BG_G, EDIT_BG_B = 0.05, 0.065, 0.08
local function GetFontSize()
    local cfg = ECHAT.DB()
    return cfg.fontSize or 12
end
local function GetTabFontSize()
    local cfg = ECHAT.DB()
    return cfg.tabFontSize or 10
end

-- Apply background settings from DB to all skinned chat frames
function ECHAT.ApplyBackground()
    local p = ECHAT.DB()
    BG_R = p.bgR or 0.03
    BG_G = p.bgG or 0.045
    BG_B = p.bgB or 0.05
    BG_A = p.bgAlpha or 0.65

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

-- Re-apply font and size to all skinned chat frames, tabs, and edit boxes
function ECHAT.ApplyFonts()
    local font = GetFont()
    local size = GetFontSize()
    local tabSize = GetTabFontSize()
    local outline = GetOutlineFlag()
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.SetFont then
            cf:SetFont(font, size, outline)
        end
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and tab._euiLabel then
            tab._euiLabel:SetFont(font, tabSize, outline)
        end
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            eb:SetFont(font, size, outline)
            if i <= 10 then
                if eb.header then eb.header:SetFont(font, size, outline) end
                if eb.headerSuffix then eb.headerSuffix:SetFont(font, size, outline) end
            end
        end
    end
end

-- Sidebar visibility: always, mouseover, never
local _sidebarFadeTarget = 1
local _sidebarFadeAlpha = 1
local _sidebarFadeFrame

function ECHAT.ApplySidebarVisibility()
    local cfg = ECHAT.DB()
    local mode = cfg.sidebarVisibility or "always"
    local cf1 = _G.ChatFrame1
    local sidebar = cf1 and cf1._euiSidebar
    if not sidebar then return end

    if mode == "never" then
        _sidebarFadeTarget = 0
        _sidebarFadeAlpha = 0
        sidebar:SetAlpha(0)
        sidebar:EnableMouse(false)
    elseif mode == "mouseover" then
        _sidebarFadeTarget = 0
        _sidebarFadeAlpha = 0
        sidebar:SetAlpha(0)
        sidebar:EnableMouse(true)
    else
        _sidebarFadeTarget = 1
        _sidebarFadeAlpha = 1
        sidebar:SetAlpha(1)
        sidebar:EnableMouse(true)
    end

    -- Create fade frame once, reuse
    if not _sidebarFadeFrame then
        _sidebarFadeFrame = CreateFrame("Frame")
        _sidebarFadeFrame:Hide()
        _sidebarFadeFrame:SetScript("OnUpdate", function(self, dt)
            local step = dt * 4  -- 0.25s fade
            if _sidebarFadeTarget > _sidebarFadeAlpha then
                _sidebarFadeAlpha = math.min(_sidebarFadeTarget, _sidebarFadeAlpha + step)
            else
                _sidebarFadeAlpha = math.max(_sidebarFadeTarget, _sidebarFadeAlpha - step)
            end
            local sb = _G.ChatFrame1 and _G.ChatFrame1._euiSidebar
            if sb then sb:SetAlpha(math.min(_sidebarFadeAlpha, _chatAlphaCurrent)) end
            if _sidebarFadeAlpha == _sidebarFadeTarget then self:Hide() end
        end)
    end
end

-- Hide/show Combat Log tab by shrinking it to invisible (taint-safe)
local _combatLogTabState = nil
function ECHAT.ApplyHideCombatLogTab()
    local cfg = ECHAT.DB()
    if not cfg.hideCombatLogTab and not _combatLogTabState then return end
    local tab = _G.ChatFrame2Tab
    if not tab then return end

    if cfg.hideCombatLogTab then
        -- Save original state once
        if not _combatLogTabState then
            _combatLogTabState = {
                name = ChatFrame2.name or (GetChatWindowInfo and select(1, GetChatWindowInfo(2))) or "Combat Log",
                scale = tab:GetScale(),
                mouseEnabled = tab:IsMouseEnabled(),
                shown = tab:IsShown(),
            }
        end
        tab:EnableMouse(false)
        tab:SetText(" ")
        tab:SetScale(0.01)
        tab:Hide()
    else
        -- Restore
        if _combatLogTabState then
            tab:SetScale(_combatLogTabState.scale or 1)
            tab:EnableMouse(_combatLogTabState.mouseEnabled ~= false)
            if _combatLogTabState.shown ~= false then tab:Show() end
            local restoreName = _combatLogTabState.name or "Combat Log"
            tab:SetText(restoreName)
            _combatLogTabState = nil
        end
    end
end

-- Show/hide all borders and dividers (not the active tab underline)
function ECHAT.ApplyBorders()
    local cfg = ECHAT.DB()
    local hide = cfg.hideBorders

    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf._euiBg and cf._euiBg._ppBorders then
            cf._euiBg._ppBorders:SetShown(not hide)
        end
        if cf and cf._euiInputDiv then
            cf._euiInputDiv:SetShown(not hide)
        end
    end
    local cf1 = _G.ChatFrame1
    if cf1 and cf1._euiSidebar then
        local sbBgHidden = cfg.hideSidebarBg
        if cf1._euiSidebar._ppBorders then
            cf1._euiSidebar._ppBorders:SetShown(not hide and not sbBgHidden)
        end
        if cf1._euiSidebar._euiDiv then
            cf1._euiSidebar._euiDiv:SetShown(not hide)
        end
    end
end

-- Show/hide individual sidebar icons and re-anchor visible ones to close gaps
function ECHAT.ApplySidebarIcons()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and cf1._euiSidebar
    if not sb then return end

    local ICON_GAP = cfg.sidebarIconSpacing or 10
    local showFriends = cfg.showFriends ~= false
    local showCopy = cfg.showCopy ~= false
    local showPortals = cfg.showPortals ~= false
    local showVoice = cfg.showVoice ~= false
    local showSettings = cfg.showSettings ~= false

    -- Friends + count (re-anchor with custom spacing)
    if sb._friendsBtn then
        sb._friendsBtn:SetShown(showFriends)
        if showFriends then
            sb._friendsBtn:ClearAllPoints()
            sb._friendsBtn:SetPoint("TOP", sb, "TOP", 0, -ICON_GAP)
        end
    end
    if sb._friendsCount then sb._friendsCount:SetShown(showFriends) end

    -- Build ordered list of visible top-group buttons, sorted by check order
    local iconOrder = cfg.sidebarIconOrder or {}
    local allMiddle = {
        { key = "showCopy",     ref = "_copyBtn" },
        { key = "showPortals",  ref = "_portalBtn" },
        { key = "showVoice",    ref = "_voiceBtn" },
        { key = "showSettings", ref = "_settingsBtn" },
    }
    local topBtns = {}
    for _, info in ipairs(allMiddle) do
        if cfg[info.key] ~= false and sb[info.ref] then
            local ord = iconOrder[info.key]
            if type(ord) ~= "number" then ord = 999 end
            topBtns[#topBtns + 1] = { btn = sb[info.ref], order = ord }
        end
    end
    table.sort(topBtns, function(a, b) return a.order < b.order end)

    -- Hide all first
    if sb._copyBtn then sb._copyBtn:Hide() end
    if sb._portalBtn then sb._portalBtn:Hide() end
    if sb._voiceBtn then sb._voiceBtn:Hide() end
    if sb._settingsBtn then sb._settingsBtn:Hide() end

    -- Re-anchor visible buttons in chain (sorted by order)
    local anchor = showFriends and sb._friendsCount or nil
    for _, entry in ipairs(topBtns) do
        entry.btn:ClearAllPoints()
        if anchor then
            entry.btn:SetPoint("TOP", anchor, "BOTTOM", 0, -ICON_GAP)
        else
            entry.btn:SetPoint("TOP", sb, "TOP", 0, -ICON_GAP)
        end
        entry.btn:Show()
        anchor = entry.btn
    end

    -- Scroll is independent
    if sb._scrollBtn then sb._scrollBtn:SetShown(cfg.showScroll ~= false) end

    -- Re-apply free move offsets after chain layout
    if ECHAT.ApplyIconFreeMove then ECHAT.ApplyIconFreeMove() end
end

-- Chat frame position: owned by EUI unlock mode when a saved position exists.
-- SetPoint hook enforces saved position, blocking Blizzard's Edit Mode.
local _cfIgnoreSetPoint = false
local _cfResizing = false

local function ApplyChatPosition()
    local cfg = ECHAT.DB()
    if not cfg or not cfg.chatPosition then return end
    local pos = cfg.chatPosition
    local cf1 = _G.ChatFrame1
    if not cf1 then return end
    local px, py = pos.x, pos.y
    local PPa = EllesmereUI and EllesmereUI.PP
    if PPa and px and py then
        local es = cf1:GetEffectiveScale()
        local isCenterAnchor = (pos.point == "CENTER")
            and (pos.relPoint == "CENTER" or pos.relPoint == nil)
        if isCenterAnchor and PPa.SnapCenterForDim then
            px = PPa.SnapCenterForDim(px, cf1:GetWidth() or 0, es)
            py = PPa.SnapCenterForDim(py, cf1:GetHeight() or 0, es)
        elseif PPa.SnapForES then
            px = PPa.SnapForES(px, es)
            py = PPa.SnapForES(py, es)
        end
    end
    if not pos.point or not (px and py) then return end
    _cfIgnoreSetPoint = true
    cf1:ClearAllPoints()
    cf1:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, px or 0, py or 0)
    _cfIgnoreSetPoint = false
end

-- Chat frame size: apply saved width/height from DB.
local function ApplyChatSize()
    local cfg = ECHAT.DB()
    if not cfg then return end
    local cf1 = _G.ChatFrame1
    if not cf1 then return end
    if cfg.chatWidth then cf1:SetWidth(cfg.chatWidth) end
    if cfg.chatHeight then cf1:SetHeight(cfg.chatHeight) end
end
ECHAT.ApplyChatSize = ApplyChatSize

function ECHAT.ApplyLockChatSize()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    if not cf1 or not cf1._euiResizeGrip then return end
    cf1._euiResizeGrip:SetShown(not cfg.lockChatSize)
end

-- Flip sidebar to left or right side of chat bg
function ECHAT.ApplySidebarPosition()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and cf1._euiSidebar
    if not sb or not cf1._euiBg then return end
    local PP = EllesmereUI and EllesmereUI.PP
    local onePx = (PP and PP.mult) or 1
    sb:ClearAllPoints()
    if cfg.sidebarRight then
        sb:SetPoint("TOPLEFT", cf1._euiBg, "TOPRIGHT", -onePx, 0)
        sb:SetPoint("BOTTOMLEFT", cf1._euiBg, "BOTTOMRIGHT", -onePx, 0)
    else
        sb:SetPoint("TOPRIGHT", cf1._euiBg, "TOPLEFT", onePx, 0)
        sb:SetPoint("BOTTOMRIGHT", cf1._euiBg, "BOTTOMLEFT", onePx, 0)
    end
    -- Move the divider to the correct edge
    if sb._euiDiv then
        sb._euiDiv:ClearAllPoints()
        if cfg.sidebarRight then
            sb._euiDiv:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
            sb._euiDiv:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, 0)
        else
            sb._euiDiv:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0)
            sb._euiDiv:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
        end
    end

end

-- Apply icon color to all sidebar icons
function ECHAT.ApplyIconColor()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and cf1._euiSidebar
    if not sb then return end
    local r, g, b
    if cfg.iconUseAccent and EllesmereUI.GetAccentColor then
        r, g, b = EllesmereUI.GetAccentColor()
    else
        r, g, b = cfg.iconR or 1, cfg.iconG or 1, cfg.iconB or 1
    end
    local ICON_ALPHA = 0.4
    local ICON_HOVER_ALPHA = 0.9
    local ICON_LABELS = {
        _friendsBtn = "Friends", _copyBtn = "Copy Chat", _portalBtn = "M+ Portals",
        _voiceBtn = "Voice/Channels", _settingsBtn = "Settings", _scrollBtn = "Scroll to Bottom",
    }
    local fc = sb._friendsCount
    for _, key in ipairs({ "_friendsBtn", "_copyBtn", "_portalBtn", "_voiceBtn", "_settingsBtn", "_scrollBtn" }) do
        local btn = sb[key]
        if btn and btn._icon then
            btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
            local label = ICON_LABELS[key]
            if key == "_friendsBtn" and fc then
                fc:SetTextColor(r, g, b, 0.5)
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    fc:SetTextColor(r, g, b, 0.9)
                    if not self._freeMoveJustDragged and EUI.ShowWidgetTooltip then
                        EUI.ShowWidgetTooltip(self, label)
                    end
                end)
                btn:SetScript("OnLeave", function()
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    fc:SetTextColor(r, g, b, 0.5)
                    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
                end)
            else
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    if not self._freeMoveJustDragged and EUI.ShowWidgetTooltip then
                        EUI.ShowWidgetTooltip(self, label)
                    end
                end)
                btn:SetScript("OnLeave", function()
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
                end)
            end
        end
    end
end

-- Hide/show the sidebar background texture
function ECHAT.ApplySidebarBackground()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and cf1._euiSidebar
    if not sb then return end
    local show = not cfg.hideSidebarBg
    local sbBg = sb:GetRegions()
    if sbBg and sbBg.SetShown then
        sbBg:SetShown(show)
    end
    if sb._ppBorders then
        sb._ppBorders:SetShown(show)
    end
end

-- Scale sidebar icon buttons and friends count text
function ECHAT.ApplySidebarIconScale()
    local cfg = ECHAT.DB()
    local scale = cfg.sidebarIconScale or 1.0
    local cf1 = _G.ChatFrame1
    local sb = cf1 and cf1._euiSidebar
    if not sb then return end

    local BASE_FRIEND = 26
    local BASE_ICON = 22
    local BASE_FONT = 9

    for _, key in ipairs({ "_copyBtn", "_portalBtn", "_voiceBtn", "_settingsBtn", "_scrollBtn" }) do
        local btn = sb[key]
        if btn then btn:SetSize(BASE_ICON * scale, BASE_ICON * scale) end
    end
    if sb._friendsBtn then
        sb._friendsBtn:SetSize(BASE_FRIEND * scale, BASE_FRIEND * scale)
    end
    if sb._friendsCount then
        sb._friendsCount:SetFont(GetFont(), math.max(7, BASE_FONT * scale), "")
    end
end

-- Free move: shift+drag sidebar icons to custom positions
local _freeMoveIconHooked = {}

local function GetIconOffset(key)
    local cfg = ECHAT.DB()
    if not cfg.freeMoveIcons or not cfg.iconPositions then return 0, 0 end
    local pos = cfg.iconPositions[key]
    if not pos then return 0, 0 end
    return pos.x or 0, pos.y or 0
end

local function SaveIconOffset(key, x, y)
    local cfg = ECHAT.DB()
    if not cfg.iconPositions then cfg.iconPositions = {} end
    cfg.iconPositions[key] = { x = x, y = y }
end

local function ApplyIconOffset(btn, sb)
    if not btn or not sb or not btn:IsShown() then return end
    local key = btn._freeMoveKey
    if not key then return end
    local ox, oy = GetIconOffset(key)
    -- Break the chain for ALL icons: re-anchor directly to sidebar
    -- using current center position so moving one doesn't drag the rest.
    local bx, by = btn:GetCenter()
    local sx, sy = sb:GetCenter()
    if not bx or not sx then return end
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", sb, "CENTER", (bx - sx) + ox, (by - sy) + oy)
end

local function EnableIconFreeMove(btn)
    if not btn or _freeMoveIconHooked[btn] then return end
    _freeMoveIconHooked[btn] = true

    local key = btn._freeMoveKey
    if not key then return end

    btn:SetMovable(true)
    btn:SetClampedToScreen(true)

    local origClick = btn:GetScript("OnClick")
    if origClick then
        btn:SetScript("OnClick", function(self, ...)
            if self._freeMoveJustDragged then return end
            origClick(self, ...)
        end)
    end

    local isDragging = false
    local startX, startY, origOffX, origOffY
    local origPoint, origRel, origRelPoint, origX, origY

    local function FreeMoveOnUpdate(self)
        if not IsMouseButtonDown("LeftButton") then
            isDragging = false
            self:SetScript("OnUpdate", nil)
            C_Timer.After(0, function() self._freeMoveJustDragged = nil end)
            local es = self:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / es, cy / es
            local dx, dy = cx - startX, cy - startY
            SaveIconOffset(key, origOffX + dx, origOffY + dy)
            return
        end
        local es = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / es, cy / es
        local dx, dy = cx - startX, cy - startY
        if origPoint then
            self:ClearAllPoints()
            self:SetPoint(origPoint, origRel, origRelPoint, origX + origOffX + dx, origY + origOffY + dy)
        end
    end

    btn:HookScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if not IsShiftKeyDown() then return end
        local cfg = ECHAT.DB()
        if not cfg.freeMoveIcons then return end
        isDragging = true
        self._freeMoveJustDragged = true
        local es = self:GetEffectiveScale()
        startX, startY = GetCursorPosition()
        startX, startY = startX / es, startY / es
        origOffX, origOffY = GetIconOffset(key)
        origPoint, origRel, origRelPoint, origX, origY = self:GetPoint(1)
        origX = (origX or 0) - origOffX
        origY = (origY or 0) - origOffY
        self:SetScript("OnUpdate", FreeMoveOnUpdate)
    end)

    btn:HookScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not isDragging then return end
        isDragging = false
        self:SetScript("OnUpdate", nil)
        local es = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / es, cy / es
        local dx, dy = cx - startX, cy - startY
        SaveIconOffset(key, origOffX + dx, origOffY + dy)
        C_Timer.After(0, function() self._freeMoveJustDragged = nil end)
    end)
end

function ECHAT.ApplyIconFreeMove()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and cf1._euiSidebar
    if not sb then return end

    local btns = {
        { ref = "_friendsBtn", key = "friends" },
        { ref = "_copyBtn",    key = "copy" },
        { ref = "_portalBtn",  key = "portals" },
        { ref = "_voiceBtn",   key = "voice" },
        { ref = "_settingsBtn", key = "settings" },
        { ref = "_scrollBtn",  key = "scroll" },
    }

    for _, info in ipairs(btns) do
        local btn = sb[info.ref]
        if btn then
            btn._freeMoveKey = info.key
            EnableIconFreeMove(btn)
            if cfg.freeMoveIcons then
                ApplyIconOffset(btn, sb)
            end
        end
    end
end

-- Portal flyout: dungeon portal spell buttons
local PORTAL_SPELLS = {
    1254400, 1254572, 1254563, 1254559,
    159898,  1254555, 1254551, 393273,
}

local _portalFlyout, _portalBtns

local function RefreshPortalButtons()
    if not _portalBtns then return end
    for _, btn in ipairs(_portalBtns) do
        local spellID = btn.spellID
        local known = IsPlayerSpell(spellID)
        if btn._lastKnown ~= known then
            btn._lastKnown = known
            btn.icon:SetDesaturated(not known)
            btn.icon:SetAlpha(known and 1 or 0.4)
        end
        if known then
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
                btn.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
            else
                btn.cooldown:Clear()
            end
        else
            btn.cooldown:Clear()
        end
    end
end

local function CreatePortalFlyout()
    if _portalFlyout then return _portalFlyout end

    local BTN_SIZE = 32
    local SPACING = 1
    local PADDING = 2
    local COLS = 4
    local ROWS = math.ceil(#PORTAL_SPELLS / COLS)

    local flyW = PADDING * 2 + BTN_SIZE * COLS + SPACING * (COLS - 1)
    local flyH = PADDING * 2 + BTN_SIZE * ROWS + SPACING * (ROWS - 1)

    local flyout = CreateFrame("Frame", "EUIChatPortalFlyout", UIParent)
    flyout:SetSize(flyW, flyH)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetFrameLevel(100)
    flyout:Hide()

    local bg = flyout:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(BG_R, BG_G, BG_B, 0.95)

    if PP and PP.CreateBorder then
        PP.CreateBorder(flyout, 1, 1, 1, 0.06, 1, "OVERLAY", 7)
    end

    -- Close in combat
    local guard = CreateFrame("Frame")
    guard:RegisterEvent("PLAYER_REGEN_DISABLED")
    guard:SetScript("OnEvent", function()
        flyout:Hide()
    end)

    -- Spell buttons
    _portalBtns = {}
    for i, spellID in ipairs(PORTAL_SPELLS) do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)

        local btn = CreateFrame("Button", "EUIChatPortal" .. i, flyout, "SecureActionButtonTemplate")
        btn:SetSize(BTN_SIZE, BTN_SIZE)
        btn:SetPoint("TOPLEFT", flyout, "TOPLEFT",
            PADDING + col * (BTN_SIZE + SPACING),
            -(PADDING + row * (BTN_SIZE + SPACING)))

        btn.spellID = spellID

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo then icon:SetTexture(spellInfo.iconID) end
        btn.icon = icon

        -- 1px black border
        if PP and PP.CreateBorder then
            PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end

        local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetHideCountdownNumbers(true)
        cd:SetDrawSwipe(true)
        cd:SetDrawBling(false)
        cd:SetDrawEdge(false)
        btn.cooldown = cd

        -- Hover highlight (HIGHLIGHT layer auto-shows on mouseover)
        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.20)

        -- Casting highlight overlay
        local castHL = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        castHL:SetAllPoints()
        castHL:SetColorTexture(1, 1, 1, 0.4)
        castHL:Hide()
        btn._castHL = castHL

        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", spellID)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        _portalBtns[i] = btn
    end

    -- Cooldown + casting highlight refresh while visible
    flyout:SetScript("OnShow", function(self)
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        self:RegisterEvent("UNIT_SPELLCAST_START")
        self:RegisterEvent("UNIT_SPELLCAST_STOP")
        self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        self:RegisterEvent("UNIT_SPELLCAST_FAILED")
        self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
        RefreshPortalButtons()
    end)
    flyout:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        for _, btn in ipairs(_portalBtns) do
            if btn._castHL then btn._castHL:Hide() end
        end
    end)
    flyout:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
        if event == "SPELL_UPDATE_COOLDOWN" then
            RefreshPortalButtons()
        elseif unit == "player" then
            local casting = (event == "UNIT_SPELLCAST_START") and spellID or nil
            for _, btn in ipairs(_portalBtns) do
                if btn._castHL then
                    btn._castHL:SetShown(casting and casting == btn.spellID)
                end
            end
        end
    end)

    -- Escape to close
    tinsert(UISpecialFrames, "EUIChatPortalFlyout")

    _portalFlyout = flyout
    return flyout
end

function ECHAT.TogglePortalFlyout(anchorBtn)
    if InCombatLockdown() then return end
    local flyout = CreatePortalFlyout()
    if flyout:IsShown() then
        flyout:Hide()
    else
        -- Compute absolute screen position (protected frame can't anchor to non-secure region)
        local bs = anchorBtn:GetEffectiveScale()
        local fs = flyout:GetEffectiveScale()
        local bTop = anchorBtn:GetTop() * bs
        local cfg = ECHAT.DB()
        flyout:ClearAllPoints()
        if cfg.sidebarRight then
            local bLeft = anchorBtn:GetLeft() * bs
            flyout:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", (bLeft - 4) / fs, (bTop + 4) / fs)
        else
            local bRight = anchorBtn:GetRight() * bs
            flyout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (bRight + 4) / fs, (bTop + 4) / fs)
        end
        flyout:Show()
    end
end

-- Flip edit box between bottom (default) and top of chat panel
function ECHAT.ApplyInputPosition()
    local cfg = ECHAT.DB()
    local onTop = cfg.inputOnTop

    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf._euiBg then
            local name = cf:GetName()
            if not name then break end
            local eb = _G[name .. "EditBox"]
            local bg = cf._euiBg
            local div = cf._euiInputDiv
            local fsc = cf.FontStringContainer
            local track = cf._euiScrollTrack

            if eb then
                eb:ClearAllPoints()
                if onTop then
                    eb:SetPoint("TOPLEFT", cf, "TOPLEFT", -10, 3)
                    eb:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 5, 3)
                else
                    eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -10, -8)
                    eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 5, -8)
                end
            end

            if div then
                div:ClearAllPoints()
                if onTop then
                    div:SetPoint("TOPLEFT", cf, "TOPLEFT", -10, -20)
                    div:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 10, -20)
                else
                    div:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", -10, -8)
                    div:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 10, -8)
                end
            end

            if bg then
                bg:ClearAllPoints()
                bg:SetPoint("TOPLEFT", cf, "TOPLEFT", -10, 3)
                if onTop then
                    bg:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 10, -6)
                else
                    bg:SetPoint("BOTTOMRIGHT", eb or cf, "BOTTOMRIGHT", 5, eb and -4 or -6)
                end
            end

            if fsc then
                fsc:ClearAllPoints()
                if onTop then
                    fsc:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, -22)
                else
                    fsc:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, -6)
                end
                fsc:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)
            end

            if track then
                track:ClearAllPoints()
                if onTop then
                    track:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 5, -22)
                else
                    track:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 5, -2)
                end
                track:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 5, 2)
            end
        end
    end
end

-- Internal: immediately apply alpha to all chat elements
-- Cache frames for _ApplyAlpha to avoid repeated _G lookups
local _alphaFrames
local function _BuildAlphaCache()
    _alphaFrames = {}
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf._euiBg then
            _alphaFrames[#_alphaFrames + 1] = {
                cf = cf,
                tab = _G["ChatFrame" .. i .. "Tab"],
                eb = _G["ChatFrame" .. i .. "EditBox"],
            }
        end
    end
end

local function _ApplyAlpha(alpha)
    _chatAlphaCurrent = alpha
    if not _alphaFrames then _BuildAlphaCache() end
    for i = 1, #_alphaFrames do
        local af = _alphaFrames[i]
        local cf = af.cf
        -- Always set tab alpha (tabs are visible even for inactive docked frames)
        local tab = af.tab
        if tab and tab:IsShown() then
            tab:SetAlpha(alpha)
            if tab._euiUnderline then tab._euiUnderline:SetAlpha(alpha) end
        end
        if cf:IsShown() or cf._euiBg:IsShown() then
            -- bg is a child of cf, so it inherits cf's alpha automatically.
            -- Don't set bg alpha explicitly or it compounds (0.5 * 0.5 = 0.25).
            cf:SetAlpha(alpha)
            local eb = af.eb
            if eb then
                if cf.isTemporary then
                    eb:SetAlpha(alpha)
                else
                    local hasFocus = eb:HasFocus()
                    if issecretvalue and issecretvalue(hasFocus) then hasFocus = false end
                    if not hasFocus then
                        eb:SetAlpha(alpha)
                    end
                end
            end
            if cf._euiScrollTrack then cf._euiScrollTrack:SetAlpha(alpha) end
            if cf._euiResizeGrip then cf._euiResizeGrip:SetAlpha(alpha * 0.2) end
        end
    end
    local cf1 = _G.ChatFrame1
    if cf1 and cf1._euiSidebar then
        local sbMode = ECHAT.DB().sidebarVisibility or "always"
        if sbMode == "mouseover" then
            cf1._euiSidebar:SetAlpha(math.min(alpha, _sidebarFadeAlpha))
        elseif sbMode ~= "never" then
            cf1._euiSidebar:SetAlpha(alpha)
        end
    end
end

-- Animate alpha toward target over FADE_DURATION
local function _SetAlphaTarget(target)
    _chatAlphaTarget = target
    _chatFadeFrame:Show()
end

_chatFadeFrame:SetScript("OnUpdate", function(self, dt)
    if _chatAlphaCurrent == _chatAlphaTarget then
        self:Hide()
        return
    end
    local fadingIn = _chatAlphaTarget > _chatAlphaCurrent
    local duration = fadingIn and FADE_IN_DURATION
        or (_idleFadeActive and IDLE_FADE_OUT_DURATION or FADE_OUT_DURATION)
    local speed = dt / duration
    if fadingIn then
        _chatAlphaCurrent = math.min(_chatAlphaTarget, _chatAlphaCurrent + speed)
    else
        _chatAlphaCurrent = math.max(_chatAlphaTarget, _chatAlphaCurrent - speed)
    end
    _ApplyAlpha(_chatAlphaCurrent)
    if _chatAlphaCurrent == _chatAlphaTarget then
        self:Hide()
    end
end)

-- Set alpha for the visibility/mouseover system (animated)
-- This is the top-level authority; idle fade cannot exceed this.
local _visAlpha = 1
function ECHAT.SetChatAlpha(alpha)
    _visAlpha = alpha
    _visChatVisible = (alpha >= 1)
    _SetAlphaTarget(alpha)
end

-- Set alpha for idle fade (animated), clamped to visibility alpha
function ECHAT.SetIdleFadeAlpha(alpha)
    _SetAlphaTarget(math.min(alpha, _visAlpha))
end

-- Refresh visibility based on DB settings (combat, mouseover, always, etc.)
function ECHAT.RefreshVisibility()
    local cfg = ECHAT.DB()

    local vis = true
    if EUI and EUI.EvalVisibility then
        vis = EUI.EvalVisibility(cfg)
    end

    local alpha
    if vis == false then
        alpha = 0
    else
        alpha = 1
    end

    if alpha == 1 and _idleFadeActive then
        ECHAT.SetIdleFadeAlpha(GetIdleFadeAlpha())
    else
        ECHAT.SetChatAlpha(alpha)
    end
end

-------------------------------------------------------------------------------
--  Chat text helpers
-------------------------------------------------------------------------------
local function StripUIEscapes(text)
    if not text then return "" end
    text = text:gsub("|H.-|h(.-)|h", "%1")   -- hyperlinks -> display text
    text = text:gsub("|T.-|t", "")            -- textures
    text = text:gsub("|A.-|a", "")            -- atlas
    text = text:gsub("|K.-|k", "")            -- secret value placeholders
    text = text:gsub("|n", "\n")              -- newlines
    text = text:gsub("||", "|")               -- escaped pipes
    -- Keep |cXXXXXXXX and |r color codes so the copy popup preserves colors
    return text
end

local function IsInProtectedInstance()
    local _, instanceType = IsInInstance()
    if instanceType == "raid" and InCombatLockdown() then return true end
    if instanceType == "party" and C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive() then
        return true
    end
    return false
end

-- Read all messages directly from the active chat frame on demand.
-- No hooks needed: ScrollingMessageFrame:GetMessageInfo(i) returns
-- the rendered text for each line.
local function ReadActiveChatText()
    local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    local cf = selected or ChatFrame1
    if not cf or not cf.GetNumMessages then return "" end
    local n = cf:GetNumMessages()
    if n == 0 then return "(No chat history)" end
    local lines = {}
    for i = 1, n do
        local ok, text = pcall(cf.GetMessageInfo, cf, i)
        if ok and text and not (issecretvalue and issecretvalue(text)) then
            local sok, stripped = pcall(StripUIEscapes, text)
            if sok and stripped then
                lines[#lines + 1] = stripped
            end
        end
    end
    return table.concat(lines, "\n")
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

        -- ScrollingEditBox (Blizzard template: scrolling + selection built-in)
        local textBox = CreateFrame("Frame", nil, popup, "ScrollingEditBoxTemplate")
        textBox:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -20)
        textBox:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -20, 60)

        local editBox = textBox:GetEditBox()
        editBox:SetFont(GetFont(), 12, EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag() or "")
        editBox:SetTextColor(1, 1, 1, 0.75)
        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            dimmer:Hide()
        end)
        editBox:SetScript("OnChar", function(self)
            if self._readOnlyText then
                self:SetText(self._readOnlyText)
                self:HighlightText()
            end
        end)

        -- Thin interactive scrollbar reading from the template's ScrollBox
        local scrollBox = textBox:GetScrollBox()
        local track = CreateFrame("Button", nil, popup)
        track:SetWidth(8)
        track:SetPoint("TOPRIGHT", textBox, "TOPRIGHT", 2, -2)
        track:SetPoint("BOTTOMRIGHT", textBox, "BOTTOMRIGHT", 2, 2)
        track:SetFrameLevel(popup:GetFrameLevel() + 5)
        track:EnableMouse(true)
        track:RegisterForClicks("AnyUp")

        local thumb = track:CreateTexture(nil, "ARTWORK")
        thumb:SetColorTexture(1, 1, 1, 0.27)
        thumb:SetWidth(4)
        thumb:SetHeight(40)
        thumb:SetPoint("TOP", track, "TOP", 0, 0)

        local _sbDragging = false
        local _sbDragOffsetY = 0

        local function UpdateThumb()
            if not scrollBox then thumb:Hide(); return end
            local ext = scrollBox:GetVisibleExtentPercentage()
            if not ext or ext >= 1 then thumb:Hide(); return end
            thumb:Show()
            local trackH = track:GetHeight()
            local thumbH = math.max(20, trackH * ext)
            thumb:SetHeight(thumbH)
            local pct = scrollBox:GetScrollPercentage() or 0
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -(pct * (trackH - thumbH)))
        end

        local function SetScrollFromY(cursorY)
            local trackH = track:GetHeight()
            local ext = scrollBox:GetVisibleExtentPercentage() or 1
            local thumbH = math.max(20, trackH * ext)
            local maxTravel = trackH - thumbH
            if maxTravel <= 0 then return end
            local trackTop = track:GetTop()
            if not trackTop then return end
            local scale = track:GetEffectiveScale()
            local localY = trackTop - (cursorY / scale) - _sbDragOffsetY
            local pct = math.max(0, math.min(1, localY / maxTravel))
            scrollBox:SetScrollPercentage(pct)
        end

        track:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            local _, cursorY = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local trackTop = self:GetTop()
            if not trackTop then return end
            -- Check if click is on the thumb
            local thumbTop = thumb:GetTop()
            local thumbBot = thumb:GetBottom()
            if thumbTop and thumbBot then
                local localCursor = cursorY / scale
                if localCursor <= thumbTop and localCursor >= thumbBot then
                    _sbDragOffsetY = thumbTop - localCursor
                    _sbDragging = true
                    return
                end
            end
            -- Click on track: jump to position
            _sbDragOffsetY = (thumb:GetHeight() or 20) / 2
            _sbDragging = true
            SetScrollFromY(cursorY)
        end)
        track:SetScript("OnMouseUp", function() _sbDragging = false end)

        -- Poll only while popup is open
        local pollFrame = CreateFrame("Frame")
        pollFrame:Hide()
        local _lastPct, _lastExt = -1, -1
        pollFrame:SetScript("OnUpdate", function()
            if _sbDragging then
                local _, cursorY = GetCursorPosition()
                SetScrollFromY(cursorY)
            end
            local ext = scrollBox:GetVisibleExtentPercentage() or 1
            local pct = scrollBox:GetScrollPercentage() or 0
            if ext == _lastExt and pct == _lastPct then return end
            _lastExt, _lastPct = ext, pct
            UpdateThumb()
        end)
        dimmer:HookScript("OnShow", function() _lastPct, _lastExt = -1, -1; pollFrame:Show() end)
        dimmer:HookScript("OnHide", function() _sbDragging = false; pollFrame:Hide() end)

        popup._textBox = textBox
        popup._editBox = editBox

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

        -- Escape to close (combat-safe: use pcall for SetPropagateKeyboardInput)
        popup:EnableKeyboard(true)
        popup:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                pcall(self.SetPropagateKeyboardInput, self, false)
                dimmer:Hide()
            else
                pcall(self.SetPropagateKeyboardInput, self, true)
            end
        end)

        popup._dimmer = dimmer
        copyDimmer = dimmer
        copyDimmer._popup = popup
    end

    -- Populate
    local popup = copyDimmer._popup
    popup._textBox:SetText(text)
    popup._editBox._readOnlyText = text
    copyDimmer:Show()
    C_Timer.After(0.05, function()
        popup._editBox:SetFocus()
        popup._editBox:HighlightText()
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

-- Hyperlink tooltip on hover + click-to-toggle item detail popup
local TOOLTIP_LINK_TYPES = {
    achievement = true, apower = true, currency = true, enchant = true,
    glyph = true, instancelock = true, item = true, keystone = true,
    quest = true, spell = true, talent = true, unit = true,
}

local _hyperlinkEntered = nil

local function OnHyperlinkEnter(self, hyperlink)
    if IsInProtectedInstance() then return end
    local cfg = ECHAT.DB()
    if cfg.hideTooltipOnHover then return end
    local linkType = hyperlink:match("^([^:]+)")
    if TOOLTIP_LINK_TYPES[linkType] then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(hyperlink)
        GameTooltip:Show()
        _hyperlinkEntered = self
    end
end

local function OnHyperlinkLeave(self)
    if _hyperlinkEntered then
        _hyperlinkEntered = nil
        GameTooltip:Hide()
    end
end

-- Toggle ItemRefTooltip on click (click once to show, click again to close)
local _lastClickedLink = nil
hooksecurefunc("SetItemRef", function(link)
    if not link then return end
    local url = link:match("^" .. addonName .. "url:(.+)$")
    if url then ShowUrlPopup(url); return end

    if IsInProtectedInstance() then return end
    local linkType = link:match("^([^:]+)")
    if linkType == "item" or linkType == "spell" or linkType == "enchant"
        or linkType == "keystone" or linkType == "currency" then
        if _lastClickedLink == link and ItemRefTooltip and ItemRefTooltip:IsShown() then
            ItemRefTooltip:Hide()
            _lastClickedLink = nil
        else
            _lastClickedLink = link
        end
    end
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

    -- Hyperlink tooltip on hover
    if not cf._euiHyperlinkHooked then
        cf._euiHyperlinkHooked = true
        cf:HookScript("OnHyperlinkEnter", OnHyperlinkEnter)
        cf:HookScript("OnHyperlinkLeave", OnHyperlinkLeave)
    end

    -- Sidebar: 40px panel to the left of the main chat frame for icons.
    -- Parented to UIParent so it stays visible regardless of active tab.
    if name == "ChatFrame1" and not cf._euiSidebar then
        local sidebar = CreateFrame("Frame", nil, UIParent)
        sidebar:SetWidth(40)
        local onePxSB = (PP and PP.mult) or 1
        sidebar:SetPoint("TOPRIGHT", cf._euiBg, "TOPLEFT", onePxSB, 0)
        sidebar:SetPoint("BOTTOMRIGHT", cf._euiBg, "BOTTOMLEFT", onePxSB, 0)
        sidebar:SetFrameStrata(cf:GetFrameStrata())
        sidebar:SetFrameLevel(cf:GetFrameLevel() + 1)

        local sbBg = sidebar:CreateTexture(nil, "BACKGROUND")
        sbBg:SetAllPoints()
        sbBg:SetColorTexture(BG_R, BG_G, BG_B, BG_A)

        if PP and PP.CreateBorder then
            PP.CreateBorder(sidebar, 1, 1, 1, 0.06, 1, "OVERLAY", 7)
        end

        -- Sidebar mouseover hover (for "mouseover" visibility mode)
        sidebar:EnableMouse(true)
        sidebar:SetScript("OnEnter", function()
            local cfg = ECHAT.DB()
            if cfg.sidebarVisibility == "mouseover" then
                _sidebarFadeTarget = 1
                if _sidebarFadeFrame then _sidebarFadeFrame:Show() end
            end
        end)
        sidebar:SetScript("OnLeave", function()
            local cfg = ECHAT.DB()
            if cfg.sidebarVisibility == "mouseover" then
                C_Timer.After(0, function()
                    if not sidebar:IsMouseOver() then
                        _sidebarFadeTarget = 0
                        if _sidebarFadeFrame then _sidebarFadeFrame:Show() end
                    end
                end)
            end
        end)

        -- 1px divider between sidebar and chat bg
        local onePx = (PP and PP.mult) or 1
        local sbDiv = sidebar:CreateTexture(nil, "OVERLAY", nil, 7)
        sbDiv:SetWidth(onePx)
        sbDiv:SetColorTexture(1, 1, 1, 0.06)
        sbDiv:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
        sbDiv:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
        if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(sbDiv) end
        sidebar._euiDiv = sbDiv

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

        -- Highlight count + tooltip when hovering friends icon
        friendsBtn:HookScript("OnEnter", function(self)
            friendsCount:SetTextColor(1, 1, 1, 0.9)
            if not self._freeMoveJustDragged and EUI.ShowWidgetTooltip then
                EUI.ShowWidgetTooltip(self, "Friends")
            end
        end)
        friendsBtn:HookScript("OnLeave", function()
            friendsCount:SetTextColor(1, 1, 1, 0.5)
            if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
        end)

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

        -- Sidebar icon tooltips
        local function HookIconTooltip(btn, label)
            btn:HookScript("OnEnter", function(self)
                if not self._freeMoveJustDragged and EUI.ShowWidgetTooltip then
                    EUI.ShowWidgetTooltip(self, label)
                end
            end)
            btn:HookScript("OnLeave", function()
                if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            end)
        end
        HookIconTooltip(copyBtn, "Copy Chat")
        HookIconTooltip(voiceBtn, "Voice/Channels")
        HookIconTooltip(settingsBtn, "Settings")
        HookIconTooltip(scrollBtn, "Scroll to Bottom")

        -- Scroll to bottom
        scrollBtn:SetScript("OnClick", function()
            local cf1 = ChatFrame1
            if cf1 and cf1.ScrollBar and cf1.ScrollBar.SetScrollPercentage then
                cf1.ScrollBar:SetScrollPercentage(1)
            end
        end)

        -- Copy chat history from the active tab (reads directly from the frame)
        copyBtn:SetScript("OnClick", function()
            local fullText = ReadActiveChatText()
            if fullText == "" then fullText = "(No chat history)" end
            ShowCopyPopup(fullText)
        end)

        -- Friends button toggles FriendsFrame
        friendsBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            ToggleFriendsFrame()
        end)

        -- Portals button toggles dungeon portal flyout
        local portalBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_portal.png")
        portalBtn:SetSize(26, 26)
        portalBtn:ClearAllPoints()
        portalBtn:SetPoint("TOP", friendsCount, "BOTTOM", 0, -ICON_SPACING)

        portalBtn:SetScript("OnClick", function(self)
            if InCombatLockdown() then return end
            ECHAT.TogglePortalFlyout(self)
        end)
        HookIconTooltip(portalBtn, "M+ Portals")

        -- Voice button toggles ChannelFrame
        voiceBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            ToggleChannelFrame()
        end)

        -- Settings button toggles EUI options on Chat module
        settingsBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            local mf = EUI._mainFrame
            if mf and mf:IsShown() and EUI:GetActiveModule() == "EllesmereUIChat" then
                mf:Hide()
            else
                EUI:ShowModule("EllesmereUIChat")
                -- Scroll sidebar to bottom so Chat (in the reskin group) is visible
                C_Timer.After(0, function()
                    local sf = EUI._addonScrollFrame
                    if sf then
                        local max = sf:GetVerticalScrollRange() or 0
                        sf:SetVerticalScroll(max)
                        -- Poke scroll child to trigger OnScrollRangeChanged (updates thumb)
                        local sc = sf:GetScrollChild()
                        if sc then
                            local h = sc:GetHeight()
                            sc:SetHeight(h + 0.01)
                            sc:SetHeight(h)
                        end
                    end
                end)
            end
        end)

        sidebar._friendsBtn = friendsBtn
        sidebar._copyBtn = copyBtn
        sidebar._portalBtn = portalBtn
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
    cf:SetFont(GetFont(), GetFontSize(), GetOutlineFlag())
    if cf.SetShadowOffset then cf:SetShadowOffset(1, -1) end
    if cf.SetShadowColor then cf:SetShadowColor(0, 0, 0, 0.8) end

    -- Timestamps set once in PLAYER_LOGIN, not per-frame

    -- Disable Blizzard's message text auto-fade (our idle fade handles it)
    cf:SetFading(false)

    -- Prevent tabs from auto-fading (Blizzard's idle fade), but respect
    -- our visibility system which may legitimately set alpha to 0.
    -- Hook suspends during instanced combat to avoid tainting Blizzard's
    -- chat history pipeline (HistoryKeeper accessIDs table).
    local tab = _G[name .. "Tab"]
    if tab then
        tab:SetAlpha(1)
        local _ignoreTabAlpha = false
        hooksecurefunc(tab, "SetAlpha", function(self, a)
            if _ignoreTabAlpha then return end
            if IsInProtectedInstance() then return end
            if not _visChatVisible then
                if a > 0 then
                    _ignoreTabAlpha = true
                    self:SetAlpha(0)
                    _ignoreTabAlpha = false
                end
                return
            end
            if _idleFadeActive then return end
            if a > 0 and a < 1 then
                _ignoreTabAlpha = true
                self:SetAlpha(1)
                _ignoreTabAlpha = false
            end
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

        eb:SetFont(GetFont(), GetFontSize(), "")
        eb:SetTextInsets(8, 8, 0, 0)

        -- Style the channel header only for the first 10 frames (1-10 are
        -- never temporary). Frames 11-20 can become whisper windows in M+
        -- where SetFont on their headers taints Blizzard's UpdateHeader math.
        local frameIdx = tonumber(name:match("ChatFrame(%d+)"))
        if frameIdx and frameIdx <= 10 then
            if eb.header then eb.header:SetFont(GetFont(), GetFontSize(), "") end
            if eb.headerSuffix then eb.headerSuffix:SetFont(GetFont(), GetFontSize(), "") end
        end
        -- Up/Down arrow recalls message history without requiring Alt.
        eb:SetAltArrowKeyMode(false)
        if not eb._euiHistory then
            eb._euiHistory = {}
            eb._euiHistIdx = 0
            hooksecurefunc(eb, "AddHistoryLine", function(self, text)
                local h = self._euiHistory
                if h[#h] ~= text then
                    h[#h + 1] = text
                    if #h > 50 then table.remove(h, 1) end
                end
            end)
            eb:HookScript("OnKeyDown", function(self, key)
                if key ~= "UP" and key ~= "DOWN" then return end
                local h = self._euiHistory
                if #h == 0 then return end
                if key == "UP" then
                    self._euiHistIdx = self._euiHistIdx + 1
                    if self._euiHistIdx > #h then self._euiHistIdx = #h end
                elseif key == "DOWN" then
                    self._euiHistIdx = self._euiHistIdx - 1
                    if self._euiHistIdx < 0 then self._euiHistIdx = 0 end
                end
                if self._euiHistIdx == 0 then
                    self:SetText("")
                else
                    self:SetText(h[#h - self._euiHistIdx + 1])
                end
            end)
            eb:HookScript("OnEditFocusLost", function(self)
                self._euiHistIdx = 0
            end)
        end

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
            local tex = tab[key]
            if tex then
                tex:SetAlpha(0)
                tex:SetSize(1, 1)
            end
        end
        local hl = tab:GetHighlightTexture()
        if hl then hl:SetTexture("") end
        -- Hide glow frame
        if tab.glow then tab.glow:SetAlpha(0) end

        -- Force consistent tab height (pixel-snapped)
        local function GetSnappedTabH()
            local es = tab:GetEffectiveScale()
            if PP and PP.SnapForES then
                return PP.SnapForES(24, es)
            end
            return 24
        end
        tab:SetHeight(GetSnappedTabH())
        do
            local _ignoreH = false
            hooksecurefunc(tab, "SetHeight", function(self, h)
                if _ignoreH then return end
                local targetH = GetSnappedTabH()
                if h ~= targetH then
                    _ignoreH = true
                    self:SetHeight(targetH)
                    _ignoreH = false
                end
            end)
        end

        -- Set minimum tab width once at skin time. No SetWidth hook —
        -- hooking SetWidth taints the tab's width value, which propagates
        -- to PanelTemplates_TabResize when FCF_OpenTemporaryWindow runs.

        -- Match tabs to main text area strata, just +1 level
        tab:SetFrameStrata(cf:GetFrameStrata())
        tab:SetFrameLevel(cf:GetFrameLevel() + 1)

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
                    -- Only shift for docked tabs. Undocked tabs anchor to
                    -- their own chat frame and shouldn't be shifted.
                    if rel ~= cf then
                        _tabIgnoreSetPoint = true
                        self:SetPoint(point, rel, relPoint, (x or 0) - 10, y or 0)
                        _tabIgnoreSetPoint = false
                    end
                end
            end)
            -- Chain after the previous visible tab directly.
            -- Only for frames that are in the main dock; undocked frames
            -- have their tabs positioned by Blizzard on their own window.
            local tabIdx = tonumber(name:match("ChatFrame(%d+)"))
            local isInDock = false
            if GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES then
                for _, f in ipairs(GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES) do
                    if f == cf then isInDock = true; break end
                end
            end
            if tabIdx and tabIdx > 1 and isInDock then
                for prev = tabIdx - 1, 1, -1 do
                    local prevTab = _G["ChatFrame" .. prev .. "Tab"]
                    if prevTab and prevTab:IsShown() then
                        _tabIgnoreSetPoint = true
                        tab:ClearAllPoints()
                        tab:SetPoint("LEFT", prevTab, "RIGHT", 1, 0)
                        _tabIgnoreSetPoint = false
                        break
                    end
                end
            end
        end

        -- Dark tab background (matches chat box opacity)
        if not tab._euiBg then
            tab._euiBg = tab:CreateTexture(nil, "BACKGROUND")
            tab._euiBg._euiOwned = true
            tab._euiBg:SetAllPoints()
            tab._euiBg:SetColorTexture(BG_R, BG_G, BG_B, BG_A)
        end

        -- New message pulse overlay (accent colored, pulses 25-40% opacity)
        if not tab._euiNewMsg then
            local pulse = tab:CreateTexture(nil, "ARTWORK")
            pulse._euiOwned = true
            pulse:SetAllPoints()
            local eg = EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
            pulse:SetColorTexture(eg.r, eg.g, eg.b, 0.40)
            pulse:Hide()

            local ag = pulse:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local fade = ag:CreateAnimation("Alpha")
            fade:SetFromAlpha(0.4)
            fade:SetToAlpha(0.68)
            fade:SetDuration(0.65)
            fade:SetSmoothing("IN_OUT")
            pulse._euiAnim = ag

            tab._euiNewMsg = pulse
        end

        -- Field kept for UpdateTabColors compatibility.
        tab._euiActiveHL = nil

        local blizLabel = tab:GetFontString()
        local labelText = blizLabel and blizLabel:GetText() or "Tab"
        tab:SetPushedTextOffset(0, 0)

        if cf.isTemporary then
            -- Temporary tabs: restyle Blizzard's own label (avoids width issues)
            if blizLabel and not tab._euiLabel then
                blizLabel:SetFont(GetFont(), GetTabFontSize(), "")
                blizLabel:SetTextColor(1, 1, 1, 0.5)
                blizLabel:SetJustifyH("CENTER")
                blizLabel:ClearAllPoints()
                blizLabel:SetPoint("CENTER", tab, "CENTER", 0, 0)
                local _ignoreLabelPt = false
                hooksecurefunc(blizLabel, "SetPoint", function(self)
                    if _ignoreLabelPt then return end
                    _ignoreLabelPt = true
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", tab, "CENTER", 0, 0)
                    _ignoreLabelPt = false
                end)
                tab._euiLabel = blizLabel
            end
        else
            -- Regular tabs: our own label renders the text; Blizzard's is hidden.
            -- We don't modify Blizzard's label text or call tab:SetWidth to avoid
            -- taint propagation to PanelTemplates_TabResize.
            if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end
            if not tab._euiLabel then
                local label = tab:CreateFontString(nil, "OVERLAY")
                label:SetFont(GetFont(), GetTabFontSize(), "")
                label:SetPoint("CENTER", tab, "CENTER", 0, 0)
                label:SetJustifyH("CENTER")
                label:SetWordWrap(false)
                label:SetText(labelText)
                tab._euiLabel = label
                hooksecurefunc(tab, "SetText", function(_, newText)
                    if not newText or not label then return end
                    label:SetText(newText)
                end)
                -- Tab width is managed by Blizzard. We don't call SetWidth
                -- from addon code to avoid tainting the tab's width value.
            end
        end

        -- Accent underline (active tab indicator).
        -- Parented to UIParent so Blizzard's tab alpha/show/hide cycles
        -- don't affect it. Anchored to the tab for positioning.
        if not tab._euiUnderline then
            local EG = EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
            local ulFrame = CreateFrame("Frame", nil, tab)
            ulFrame:SetFrameLevel(tab:GetFrameLevel() + 5)
            local ulY = (name == "ChatFrame1" or name == "ChatFrame2") and 0 or 1
            ulFrame:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, ulY)
            ulFrame:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, ulY)
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

    -- Hide Blizzard button frame by reparenting to hidden container
    local btnFrame = _G[name .. "ButtonFrame"]
    if btnFrame then
        btnFrame:SetParent(_hiddenParent)
    end

    -- Reposition Blizzard's resize button to align with our bg.
    -- ChatFrame1: hidden (we have our own grip). Others: repositioned.
    local resizeBtn = _G[name .. "ResizeButton"]
    if resizeBtn then
        if name == "ChatFrame1" then
            resizeBtn:SetParent(_hiddenParent)
        else
            resizeBtn:ClearAllPoints()
            resizeBtn:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 7, -30)
        end
    end

    -- Custom resize grip on ChatFrame1's bg (bottom-right corner)
    if name == "ChatFrame1" and cf._euiBg and not cf._euiResizeGrip then
        local grip = CreateFrame("Button", nil, UIParent)
        grip:SetSize(18, 18)
        grip:SetPoint("BOTTOMRIGHT", cf._euiBg, "BOTTOMRIGHT", -2, 2)
        grip:SetFrameStrata("HIGH")
        grip:SetFrameLevel(100)
        local gripTex = grip:CreateTexture(nil, "OVERLAY")
        gripTex:SetAllPoints()
        gripTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\resize_element.png")
        gripTex:SetDesaturated(true)
        gripTex:SetVertexColor(1, 1, 1)
        grip:SetAlpha(0.2)
        grip:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        grip:SetScript("OnLeave", function(self)
            if not self._dragging then self:SetAlpha(0.2) end
        end)

        local function FinishResize(self)
            self._dragging = false
            _cfResizing = false
            cf._euiResizeTarget = nil
            self:SetAlpha(0.2)
            -- Save size and update position to reflect new dimensions
            local cfg = ECHAT.DB()
            if cfg then
                cfg.chatWidth = cf:GetWidth()
                cfg.chatHeight = cf:GetHeight()
                -- Update saved position from current TOPLEFT anchor
                local cfS = cf:GetEffectiveScale()
                local uiS = UIParent:GetEffectiveScale()
                local cCX, cCY = cf:GetCenter()
                local uCX, uCY = UIParent:GetCenter()
                if cCX and uCX then
                    cfg.chatPosition = {
                        point = "CENTER", relPoint = "CENTER",
                        x = (cCX * cfS - uCX * uiS) / uiS,
                        y = (cCY * cfS - uCY * uiS) / uiS,
                    }
                end
            end
            ApplyChatPosition()
        end

        grip:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            if InCombatLockdown() then return end
            self._startCX, self._startCY = GetCursorPosition()
            self._startW = cf:GetWidth()
            self._startH = cf:GetHeight()
            -- Capture current anchor so we can compensate for center-based resize
            local pt, _, relPt, px, py = cf:GetPoint(1)
            self._anchorPt = pt
            self._anchorRelPt = relPt
            self._anchorX = px or 0
            self._anchorY = py or 0
            self._dragging = true
            _cfResizing = true
        end)
        grip:SetScript("OnMouseUp", function(self)
            if not self._dragging then return end
            FinishResize(self)
        end)
        grip:SetScript("OnUpdate", function(self)
            if not self._dragging then return end
            if not IsMouseButtonDown("LeftButton") then
                FinishResize(self)
                return
            end
            local es = cf:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            local dx = (cx - self._startCX) / es
            local dy = (cy - self._startCY) / es
            local newW = math.max(200, self._startW + dx)
            local newH = math.max(100, self._startH - dy)
            -- Compensate position so top-left stays fixed (CENTER anchor
            -- grows equally in all directions; shift center by half the delta)
            local dW = newW - self._startW
            local dH = newH - self._startH
            local tgtX = self._anchorX + dW / 2
            local tgtY = self._anchorY - dH / 2
            -- Store target so the SetPoint hook can enforce it against Blizzard
            cf._euiResizeTarget = { self._anchorPt, self._anchorRelPt, tgtX, tgtY }
            _cfIgnoreSetPoint = true
            cf:SetSize(newW, newH)
            cf:ClearAllPoints()
            cf:SetPoint(self._anchorPt, UIParent, self._anchorRelPt, tgtX, tgtY)
            _cfIgnoreSetPoint = false
        end)
        cf._euiResizeGrip = grip
    end

    -- Hide scroll buttons + scroll-to-bottom
    for _, suffix in ipairs({"BottomButton", "DownButton", "UpButton"}) do
        local btn = _G[name .. suffix]
        if btn then btn:SetAlpha(0); btn:EnableMouse(false) end
    end
    if cf.ScrollToBottomButton then
        cf.ScrollToBottomButton:SetParent(_hiddenParent)
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

    -- Let clicks pass through to the game world
    cf:SetHyperlinksEnabled(true)

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
                            fs:SetFont(GetFont(), GetTabFontSize(), "")
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
            local _ignoreQbfAlpha = false
            hooksecurefunc(qbf, "SetAlpha", function(self, a)
                if _ignoreQbfAlpha then return end
                if a < 1 then
                    _ignoreQbfAlpha = true
                    self:SetAlpha(1)
                    _ignoreQbfAlpha = false
                end
            end)

            -- Don't extend bg upward -- the filter bar has its own bg (qbfBg).
            -- Keeping both chat frame bgs the same size prevents visual
            -- jumping when switching between General and Combat Log tabs.
        end
    end

    -- Skip scrollbar entirely for undocked temporary frames in M+ / raid combat
    if cf.isTemporary and not cf.isDocked then
        local _, instanceType = IsInInstance()
        local inMPlus = instanceType == "party" and C_ChallengeMode
            and C_ChallengeMode.IsChallengeModeActive
            and C_ChallengeMode.IsChallengeModeActive()
        local inRaidCombat = instanceType == "raid" and InCombatLockdown()
        if inMPlus or inRaidCombat then return end
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
        track:SetClipsChildren(true)
        track:EnableMouse(true)
        track:RegisterForClicks("AnyUp")

        local thumb = track:CreateTexture(nil, "ARTWORK")
        thumb:SetColorTexture(1, 1, 1, 0.25)
        thumb:SetWidth(3)
        thumb:Hide()

        -- Only show scrollbar when hovering the chat area.
        -- Scrollbar fade in/out with hover + drag awareness.
        -- Track stays visible (for OnUpdate) but alpha controls visibility.
        local _hovered = false
        local _dragging = false
        local _dragOffsetY = 0
        local _trackAlpha = 0
        local _trackTarget = 0
        local _lastPct, _lastExt = -1, -1
        local FADE_SPEED = 1 / 0.25  -- full fade in 0.25s

        local function ShowTrack() _trackTarget = 1; _lastPct = -1; _lastExt = -1; track:Show() end
        local function HideTrack() _trackTarget = 0 end

        local function CheckHover()
            local ok, over = pcall(function()
                return _dragging or cf._euiBg:IsMouseOver() or track:IsMouseOver()
            end)
            if ok and over then
                _hovered = true; ShowTrack()
            else
                _hovered = false; HideTrack()
            end
        end

        cf._euiBg:EnableMouse(false)
        -- bg OnEnter/OnLeave removed — hover detection moved to _euiHoverZone
        track._showTrack = ShowTrack
        track._hideTrack = HideTrack
        track._isHovered = function() return _hovered end
        track._isDragging = function() return _dragging end
        track._setHovered = function(v) _hovered = v end
        track:HookScript("OnEnter", function() _hovered = true; ShowTrack() end)
        track:HookScript("OnLeave", function()
            if not _dragging then
                _hovered = false; HideTrack()
            end
        end)
        track:SetAlpha(0)
        track:Hide()

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
            thumb:SetHeight(thumbH)
            thumb:ClearAllPoints()
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

        track:SetScript("OnMouseUp", function()
            _dragging = false
            C_Timer.After(0, CheckHover)
        end)

        track:SetScript("OnUpdate", function(self, dt)
            -- Fade alpha toward target
            if _trackAlpha ~= _trackTarget then
                local step = FADE_SPEED * dt
                if _trackTarget > _trackAlpha then
                    _trackAlpha = math.min(_trackTarget, _trackAlpha + step)
                else
                    _trackAlpha = math.max(_trackTarget, _trackAlpha - step)
                end
                self:SetAlpha(_trackAlpha)
                if _trackAlpha <= 0 and _trackTarget <= 0 then
                    self:Hide()
                    return
                end
            end

            if _dragging then
                if not IsMouseButtonDown("LeftButton") then
                    _dragging = false
                    CheckHover()
                    return
                end
                local _, cursorY = GetCursorPosition()
                cursorY = cursorY / self:GetEffectiveScale()
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
                        if blizSB.SetScrollPercentage then
                            blizSB:SetScrollPercentage(visualPct)
                        end
                    end
                end
            else
                self._elapsed = (self._elapsed or 0) + dt
                if self._elapsed < 0.15 then return end
                self._elapsed = 0
                local pct = blizSB.GetScrollPercentage and blizSB:GetScrollPercentage()
                local ext = blizSB.GetVisibleExtentPercentage and blizSB:GetVisibleExtentPercentage()
                if pct == _lastPct and ext == _lastExt then return end
                _lastPct, _lastExt = pct, ext
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
                if tab._euiNewMsg then
                    if isActive then
                        tab._euiHasNew = false
                        tab._euiNewMsg:Hide()
                        tab._euiNewMsg._euiAnim:Stop()
                    elseif tab._euiHasNew then
                        if not tab._euiNewMsg:IsShown() then
                            tab._euiNewMsg:Show()
                            tab._euiNewMsg._euiAnim:Play()
                        end
                    else
                        tab._euiNewMsg:Hide()
                        tab._euiNewMsg._euiAnim:Stop()
                    end
                end
            elseif tab._euiUnderline then
                tab._euiUnderline:Hide()
            end
        end
    end
    -- Only show resize grip when General (ChatFrame1) is the active tab
    local cf1 = _G.ChatFrame1
    if cf1 and cf1._euiResizeGrip then
        local cfg = ECHAT.DB()
        local locked = cfg and cfg.lockChatSize
        cf1._euiResizeGrip:SetShown(not locked and selected == cf1)
    end
end


-------------------------------------------------------------------------------
--  Initialization (PLAYER_LOGIN)
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    EnsureDB()

    ---------------------------------------------------------------------------
    --  1. Load saved background color/opacity before skinning any frames
    ---------------------------------------------------------------------------
    local p = ECHAT.DB()
    BG_R = p.bgR or BG_R
    BG_G = p.bgG or BG_G
    BG_B = p.bgB or BG_B
    BG_A = p.bgAlpha or BG_A

    ---------------------------------------------------------------------------
    --  2. Skin all 20 chat frames (bg, tabs, scrollbar, edit box, etc.)
    ---------------------------------------------------------------------------
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf then SkinChatFrame(cf) end
    end

    ---------------------------------------------------------------------------
    --  3. Temporary window hook (whisper windows)
    --     When Blizzard creates a new temp window, skin it, re-hide chrome
    --     Blizzard may have re-shown, and re-chain tab positions.
    ---------------------------------------------------------------------------
    hooksecurefunc("FCF_OpenTemporaryWindow", function()
        C_Timer.After(0, function()
            for i = 1, 20 do
                local cf = _G["ChatFrame" .. i]
                if cf and not _skinned[cf] then
                    SkinChatFrame(cf)
                end
                if cf and cf._euiBg and not cf._euiBg:IsShown() and cf:IsShown() then
                    cf._euiBg:Show()
                end
                if cf then
                    local cfName = cf:GetName()
                    if cfName then
                        local btnFrame = _G[cfName .. "ButtonFrame"]
                        if btnFrame and btnFrame:GetParent() ~= _hiddenParent then
                            btnFrame:SetParent(_hiddenParent)
                        end
                    end
                end
                if i > 1 then
                    local tab = _G["ChatFrame" .. i .. "Tab"]
                    if tab and tab:IsShown() then
                        for j = 1, select("#", tab:GetRegions()) do
                            local region = select(j, tab:GetRegions())
                            if region and region:IsObjectType("Texture") and not region._euiOwned then
                                region:SetTexture("")
                                region:SetAlpha(0)
                            end
                        end
                        for prev = i - 1, 1, -1 do
                            local prevTab = _G["ChatFrame" .. prev .. "Tab"]
                            if prevTab and prevTab:IsShown() then
                                tab:ClearAllPoints()
                                tab:SetPoint("LEFT", prevTab, "RIGHT", 1, 0)
                                break
                            end
                        end
                    end
                end
            end
            UpdateTabColors()
            ECHAT.ApplyInputPosition()
        end)
    end)

    ---------------------------------------------------------------------------
    --  4. Tab auto-fade: per-tab hooks are installed in SkinChatFrame.
    --     Deferred one-shot ensures tabs are visible after login (Blizzard
    --     may fade them before our hooks are installed).
    ---------------------------------------------------------------------------
    C_Timer.After(1, function()
        if not _visChatVisible then return end
        for i = 1, 20 do
            local t = _G["ChatFrame" .. i .. "Tab"]
            if t and t:IsShown() then t:SetAlpha(1) end
        end
    end)

    ---------------------------------------------------------------------------
    --  5. Tab color management
    --     Deferred update batches multiple tab changes into one pass.
    --     Hooks: tab click, dock/undock, close, new message flash.
    ---------------------------------------------------------------------------
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
    hooksecurefunc("FCF_Tab_OnClick", DeferredTabColorUpdate)
    hooksecurefunc("FCF_DockUpdate", DeferredTabColorUpdate)
    hooksecurefunc("FCF_UnDockFrame", function() DeferredTabColorUpdate() end)
    hooksecurefunc("FCF_Close", DeferredTabColorUpdate)

    -- New message pulse: flag tabs with unread messages
    if FCF_StartAlertFlash then
        hooksecurefunc("FCF_StartAlertFlash", function(cf)
            if not cf then return end
            local ok, tabName = pcall(function() return cf:GetName() .. "Tab" end)
            if not ok then return end
            local tab = _G[tabName]
            if tab then tab._euiHasNew = true; DeferredTabColorUpdate() end
        end)
    end
    if FCF_StopAlertFlash then
        hooksecurefunc("FCF_StopAlertFlash", function(cf)
            if not cf then return end
            local ok, tabName = pcall(function() return cf:GetName() .. "Tab" end)
            if not ok then return end
            local tab = _G[tabName]
            if tab then tab._euiHasNew = false; DeferredTabColorUpdate() end
        end)
    end


    ---------------------------------------------------------------------------
    --  6. Idle fade system
    --     Dims chat after N seconds of inactivity. Resets on: new message
    --     on active tab, whisper window, edit box focus/typing, or cursor
    --     entering the chat area (event-driven via OnEnter/OnLeave).
    ---------------------------------------------------------------------------
    do
        local idleTimer = nil

        local function IsIdleApplicable()
            local cfg = ECHAT.DB()
            local vis = cfg.visibility or "always"
            return vis ~= "never"
        end

        local function StartIdleFade()
            if _idleFadeActive then return end
            _idleFadeActive = true
            ECHAT.SetIdleFadeAlpha(GetIdleFadeAlpha())
        end

        local function CancelIdleFade()
            _idleFadeActive = false
            if idleTimer then
                idleTimer:Cancel()
                idleTimer = nil
            end
            if _visChatVisible then
                ECHAT.SetIdleFadeAlpha(1)
            end
        end

        function ECHAT.ResetIdleTimer()
            if not IsIdleApplicable() then return end
            CancelIdleFade()
            local cfg = ECHAT.DB()
            local delay = cfg.idleFadeDelay or 15
            idleTimer = C_Timer.NewTimer(delay, StartIdleFade)
        end

        -- Hook AddMessage on the active chat frame to detect new messages.
        -- Use the selected dock frame to know which is active.
        local _lastIdleReset = 0
        local function OnActiveMessage()
            if not IsIdleApplicable() then return end
            local now = GetTime()
            if now - _lastIdleReset < 1 then return end
            _lastIdleReset = now
            if _idleMouseOver then
                CancelIdleFade()
            else
                ECHAT.ResetIdleTimer()
            end
        end

        -- Single message filter to reset idle on any chat message.
        -- Replaces 18 per-frame AddMessage hooks with one filter that
        -- fires once per message event (not per frame).
        local function IdleMessageFilter(self, event, msg, ...)
            OnActiveMessage()
        end
        for _, ev in ipairs({
            "CHAT_MSG_SAY", "CHAT_MSG_YELL",
            "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
            "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
            "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
            "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_RAID_WARNING",
            "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
            "CHAT_MSG_CHANNEL", "CHAT_MSG_SYSTEM",
            "CHAT_MSG_LOOT",
        }) do
            ChatFrame_AddMessageEventFilter(ev, IdleMessageFilter)
        end

        -- Also reset on new temporary window (whisper)
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            OnActiveMessage()
        end)

        -- Reset idle when user types in chat (focus or any keystroke)
        for i = 1, 20 do
            local eb = _G["ChatFrame" .. i .. "EditBox"]
            if eb then
                eb:HookScript("OnEditFocusGained", OnActiveMessage)
                eb:HookScript("OnTextChanged", OnActiveMessage)
            end
        end

        -- Hover detection: lightweight ticker checks cursor position for
        -- idle fade + scrollbar. Fires 4x/sec. Tabs and sidebar use
        -- OnEnter/OnLeave (they have EnableMouse for click handling).
        local _idleMouseOver = false
        local _pollFrames = {}
        for i = 1, 20 do
            local cf = _G["ChatFrame" .. i]
            if cf and cf.isTemporary then break end
            if cf then
                _pollFrames[#_pollFrames + 1] = {
                    cf    = cf,
                    tab   = _G["ChatFrame" .. i .. "Tab"],
                    bg    = cf._euiBg,
                    track = cf._euiScrollTrack,
                }
            end
        end
        local _pollSidebar = ChatFrame1._euiSidebar

        C_Timer.NewTicker(0.15, function()
            RefreshCursorPos()
            local over = false
            local hoverCF = nil
            local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
                and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
            for pi = 1, #_pollFrames do
                local pf = _pollFrames[pi]
                local cf = pf.cf
                if cf:IsShown() or cf == selected then
                    if not over then
                        if IsCursorOverCached(pf.tab) then
                            over = true; hoverCF = cf
                        elseif cf:IsShown() then
                            if IsCursorOverCached(pf.bg) or IsCursorOverCached(cf) then
                                over = true; hoverCF = cf
                            end
                        end
                    end
                    local track = pf.track
                    if track then
                        local isOverThis = (hoverCF == cf)
                        if isOverThis and not track._isHovered() then
                            track._setHovered(true)
                            track._showTrack()
                        elseif not isOverThis and track._isHovered() and not track._isDragging() then
                            track._setHovered(false)
                            track._hideTrack()
                        end
                    end
                end
            end
            if not over and IsCursorOverCached(_pollSidebar) then
                over = true
            end
            if IsIdleApplicable() then
                if over and not _idleMouseOver then
                    _idleMouseOver = true
                    CancelIdleFade()
                elseif not over and _idleMouseOver then
                    _idleMouseOver = false
                    ECHAT.ResetIdleTimer()
                end
            end
        end)

        -- Start the initial timer
        ECHAT.ResetIdleTimer()
    end

    ---------------------------------------------------------------------------
    --  7. Accent color + timestamps
    ---------------------------------------------------------------------------
    if EUI.RegAccent then
        EUI.RegAccent({ type = "callback", fn = UpdateTabColors })
    end

    -- Enable scroll-to-scroll chat (Blizzard disables by default)
    if SetCVar then SetCVar("chatMouseScroll", 1) end

    local function ApplyTimestampCVar()
        if not SetCVar then return end
        local cfg = ECHAT.DB()
        local fmt = cfg.timestampFormat or "%I:%M "
        if fmt == "__blizzard" then return end
        SetCVar("showTimestamps", fmt)
    end
    ApplyTimestampCVar()
    C_Timer.After(2, ApplyTimestampCVar)
    ECHAT.ApplyTimestampCVar = ApplyTimestampCVar

    ---------------------------------------------------------------------------
    --  8. Apply all visual settings from DB
    ---------------------------------------------------------------------------
    ECHAT.ApplySidebarVisibility()
    ECHAT.ApplyHideCombatLogTab()
    ECHAT.ApplyBorders()
    ECHAT.ApplySidebarIcons()
    ECHAT.ApplySidebarPosition()
    ECHAT.ApplyIconColor()
    ECHAT.ApplyInputPosition()
    ECHAT.ApplySidebarBackground()
    ECHAT.ApplySidebarIconScale()
    ECHAT.ApplyIconFreeMove()
    ECHAT.ApplyLockChatSize()

    ---------------------------------------------------------------------------
    --  9. Chat frame positioning + sizing
    --     Deferred to PLAYER_ENTERING_WORLD because at PLAYER_LOGIN,
    --     Blizzard's Edit Mode hasn't positioned ChatFrame1 yet.
    --     First login: captures Blizzard's position/size into DB.
    --     Subsequent logins: applies saved position/size from DB.
    ---------------------------------------------------------------------------
    do
        local captureFrame = CreateFrame("Frame")
        captureFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        captureFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            local cfg = ECHAT.DB()
            if not cfg then return end
            if not cfg.chatPosition then
                local pt, _, relPt, x, y = ChatFrame1:GetPoint(1)
                if pt and x and y then
                    cfg.chatPosition = { point = pt, relPoint = relPt or pt, x = x, y = y }
                    ApplyChatPosition()
                end
            end
            if not cfg.chatWidth then
                cfg.chatWidth = ChatFrame1:GetWidth()
            end
            if not cfg.chatHeight then
                cfg.chatHeight = ChatFrame1:GetHeight()
            end
        end)
    end
    ---------------------------------------------------------------------------
    --  10. Reparent ChatFrame1 to our own container
    --      Breaks it out of Blizzard's Edit Mode hierarchy so we can call
    --      SetSize without tainting. Hides Edit Mode overlay + resize button.
    ---------------------------------------------------------------------------
    local chatContainer = CreateFrame("Frame", nil, UIParent)
    chatContainer:SetAllPoints(UIParent)
    chatContainer:EnableMouse(false)
    ChatFrame1:SetParent(chatContainer)
    if ChatFrame1.Selection then ChatFrame1.Selection:SetParent(_hiddenParent) end
    if ChatFrame1.EditModeResizeButton then ChatFrame1.EditModeResizeButton:SetParent(_hiddenParent) end

    local _ignoreSetParent = false
    hooksecurefunc(ChatFrame1, "SetParent", function(self, parent)
        if _ignoreSetParent then return end
        if parent ~= chatContainer then
            _ignoreSetParent = true
            self:SetParent(chatContainer)
            _ignoreSetParent = false
        end
    end)
    ChatFrame1:SetClampedToScreen(false)

    -- Defer SetSize to PLAYER_ENTERING_WORLD (taints during PLAYER_LOGIN)
    do
        local sizeFrame = CreateFrame("Frame")
        sizeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        sizeFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            ApplyChatSize()
        end)
    end

    ---------------------------------------------------------------------------
    --  11. Position enforcement hook
    --      Blocks Blizzard/Edit Mode from overriding our saved position.
    --      Allows unlock mode dragging and resize grip repositioning.
    ---------------------------------------------------------------------------
    pcall(ApplyChatPosition)
    hooksecurefunc(ChatFrame1, "SetPoint", function(self, pt, rel, relPt, x, y)
        if _cfIgnoreSetPoint then return end
        if EllesmereUI._unlockActive then return end
        if _cfResizing then
            local rp = self._euiResizeTarget
            if rp then
                _cfIgnoreSetPoint = true
                self:ClearAllPoints()
                self:SetPoint(rp[1], UIParent, rp[2], rp[3], rp[4])
                _cfIgnoreSetPoint = false
            end
            return
        end
        local cfg = ECHAT.DB()
        if not cfg or not cfg.chatPosition then return end
        local pos = cfg.chatPosition
        if not pos.point or not pos.x or not pos.y then return end
        _cfIgnoreSetPoint = true
        self:ClearAllPoints()
        self:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
        _cfIgnoreSetPoint = false
    end)

    ---------------------------------------------------------------------------
    --  12. Unlock mode registration (position + resize via EUI unlock mode)
    ---------------------------------------------------------------------------
    if EUI.RegisterUnlockElements then
        local MK = EUI.MakeUnlockElement
        EUI:RegisterUnlockElements({
            MK({
                key   = "ECHAT_ChatFrame",
                label = "Chat",
                group = "Chat",
                order = 600,
                noAnchorTo = true,
                getFrame = function() return ChatFrame1 end,
                getSize  = function()
                    local cf1 = _G.ChatFrame1
                    if not cf1 then return 400, 200 end
                    return cf1:GetWidth(), cf1:GetHeight()
                end,
                setWidth = function(_, newW)
                    if InCombatLockdown() then return end
                    local cf1 = _G.ChatFrame1
                    if not cf1 then return end
                    cf1:SetWidth(math.max(200, newW))
                    local cfg = ECHAT.DB()
                    if cfg then cfg.chatWidth = cf1:GetWidth() end
                end,
                setHeight = function(_, newH)
                    if InCombatLockdown() then return end
                    local cf1 = _G.ChatFrame1
                    if not cf1 then return end
                    cf1:SetHeight(math.max(100, newH))
                    local cfg = ECHAT.DB()
                    if cfg then cfg.chatHeight = cf1:GetHeight() end
                end,
                isHidden = function()
                    local cfg = ECHAT.DB()
                    return cfg.visibility == "never"
                end,
                savePos = function(_, point, relPoint, x, y)
                    local cfg = ECHAT.DB()
                    if not cfg then return end
                    cfg.chatPosition = { point = point, relPoint = relPoint or point, x = x, y = y }
                    if not EllesmereUI._unlockActive then
                        ApplyChatPosition()
                    end
                end,
                loadPos = function()
                    local cfg = ECHAT.DB()
                    if not cfg then return nil end
                    return cfg.chatPosition
                end,
                clearPos = function()
                    local cfg = ECHAT.DB()
                    if not cfg then return end
                    cfg.chatPosition = nil
                end,
                applyPos = function()
                    ApplyChatPosition()
                end,
            }),
        })
    end

    ---------------------------------------------------------------------------
    --  13. Visibility system registration
    ---------------------------------------------------------------------------
    ECHAT.RefreshVisibility()
    if EUI.RegisterVisibilityUpdater then
        EUI.RegisterVisibilityUpdater(ECHAT.RefreshVisibility)
    end

    ---------------------------------------------------------------------------
    --  14. URL wrapping (clickable links in chat)
    --      Disabled in M+ and raid combat to avoid taint.
    ---------------------------------------------------------------------------
    local URL_EVENTS = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
        "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
        "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
        "CHAT_MSG_CHANNEL",
    }
    local function URLFilter(self, event, msg, ...)
        if msg and ContainsURL(msg) then
            return false, WrapURLs(msg), ...
        end
    end

    local _urlFiltersActive = false
    local function EnableURLFilters()
        if _urlFiltersActive then return end
        _urlFiltersActive = true
        for _, ev in ipairs(URL_EVENTS) do
            ChatFrame_AddMessageEventFilter(ev, URLFilter)
        end
    end
    local function DisableURLFilters()
        if not _urlFiltersActive then return end
        _urlFiltersActive = false
        for _, ev in ipairs(URL_EVENTS) do
            ChatFrame_RemoveMessageEventFilter(ev, URLFilter)
        end
    end

    local urlGuard = CreateFrame("Frame")
    urlGuard:RegisterEvent("CHALLENGE_MODE_START")
    urlGuard:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    urlGuard:RegisterEvent("PLAYER_ENTERING_WORLD")
    urlGuard:RegisterEvent("PLAYER_REGEN_DISABLED")
    urlGuard:RegisterEvent("PLAYER_REGEN_ENABLED")
    urlGuard:SetScript("OnEvent", function(_, event)
        if event == "CHALLENGE_MODE_START" then

            DisableURLFilters()
        elseif event == "CHALLENGE_MODE_COMPLETED" then

            EnableURLFilters()
        elseif event == "PLAYER_REGEN_DISABLED" then
            local _, instanceType = IsInInstance()
            if instanceType == "raid" then
                DisableURLFilters()
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            local _, instanceType = IsInInstance()
            if instanceType == "raid" then
                EnableURLFilters()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            local _, instanceType = IsInInstance()
            local inMPlus = instanceType == "party" and C_ChallengeMode
                and C_ChallengeMode.IsChallengeModeActive
                and C_ChallengeMode.IsChallengeModeActive()

            if inMPlus then
                DisableURLFilters()
            else
                EnableURLFilters()
            end
        end
    end)
    EnableURLFilters()

    ---------------------------------------------------------------------------
    --  15. Hide Blizzard social buttons (quick join, menu, channel, voice)
    ---------------------------------------------------------------------------
    for _, frameName in ipairs({
        "QuickJoinToastButton", "ChatFrameMenuButton", "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
    }) do
        local f = _G[frameName]
        if f then f:SetAlpha(0); f:EnableMouse(false) end
    end
end)
