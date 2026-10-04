if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Invite Tools core, embedded in EllesmereUI Raid Tools.
--
-- Everything the invite window used to borrow from a bigger addon lives here,
-- adapted from the standalone addon for the EUI module:
--   * the look (colours and font) of the window
--   * Raid Tools profile-backed saved variables
--   * the themed Accept/Decline prompt used by "Share list"
--   * a tiny event helper (no Ace libraries needed)
---@class JT
local _, ns = ...
local JT = {}
ns.InviteTools = JT

local CreateFrame = CreateFrame
local UIParent = UIParent
local type = type
local math_max = math.max

local L = setmetatable({}, {
    __index = function(_, key)
        return EllesmereUI.L and EllesmereUI.L(key) or key
    end,
})
JT.L = L

------------------------------------------------------------------------
-- Look
------------------------------------------------------------------------

-- Use the suite font pipeline so Invite Tools follows EUI typography.
local FONT = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or STANDARD_TEXT_FONT

JT.Theme = {
    bgDark        = { 0.06, 0.08, 0.10, 0.95 }, -- EUI-style window background
    bgMedium      = { 0.084, 0.104, 0.124, 1.00 }, -- lifted plates
    border        = { 0, 0, 0, 1 },
    accent        = { EllesmereUI.GetAccentColor() }, -- EUI accent unless overridden in Raid Tools options
    textPrimary   = { 1, 1, 1, 1 },
    textSecondary = { 1, 1, 1, 1 },
    borderSize    = 1,

    fontFace       = FONT,
    fontSizeSmall  = 11,
    fontSizeNormal = 12,
    fontSizeLarge  = 14,
    fontOutline    = "OUTLINE",
}

-- size: "small", "normal", "large" or a number.
function JT:ApplyThemeFont(fontString, size)
    if not fontString or not fontString.SetFont then return end
    local T = self.Theme
    T.fontFace = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or T.fontFace or STANDARD_TEXT_FONT
    T.fontOutline = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("extras")) or T.fontOutline or ""
    local px
    if type(size) == "number" then
        px = size
    elseif size == "small" then
        px = T.fontSizeSmall
    elseif size == "large" then
        px = T.fontSizeLarge
    else
        px = T.fontSizeNormal
    end
    if not fontString:SetFont(T.fontFace, px, T.fontOutline) then
        fontString:SetFont(STANDARD_TEXT_FONT, px, T.fontOutline)
    end
end

local function InviteToolsChatLine(msg)
    return "|cff0cd29fEllesmereUI|r |cffffffffInvite Tools:|r " .. tostring(msg)
end

function JT:Print(msg)
    EllesmereUI.Print(InviteToolsChatLine(msg))
end


------------------------------------------------------------------------
-- Saved variables
------------------------------------------------------------------------

local function InitDB()
    local get = _G._EUI_RaidTools_DB
    local root = get and get()
    JT.db = root and root.profile and root.profile.raidTools and root.profile.raidTools.inviteTools
    return JT.db
end

------------------------------------------------------------------------
-- The invite list "module" and its event helper
------------------------------------------------------------------------

---@class InviteList
local IL = {}
JT.InviteList = IL

local handlers = {}
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if IL.UpdateDB then IL:UpdateDB() end
    local method = handlers[event]
    local fn = method and IL[method]
    if fn then fn(IL, event, ...) end
end)

-- Same shape the Ace mixin had: the handler is called as IL:Method(event, ...).
function IL:RegisterEvent(event, method)
    handlers[event] = method or event
    eventFrame:RegisterEvent(event)
end

function IL:UnregisterEvent(event)
    handlers[event] = nil
    eventFrame:UnregisterEvent(event)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer.After(0, function()
        if not InitDB() then return end
        IL:UpdateDB()
        IL:OnEnable()
    end)
end)

------------------------------------------------------------------------
-- Themed prompt (used by "Share list" when somebody offers you a list)
--
--   JT:CreatePrompt({ title, text, acceptText, cancelText,
--                     acceptColor = {r,g,b}, cancelColor = {r,g,b},
--                     onAccept = fn, onCancel = fn(reason) })
------------------------------------------------------------------------

local POPUP_W, BUTTON_W, BUTTON_H, HEADER_H = 360, 100, 26, 20

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local function PromptButton(parent, label, tint, bgMedium, border)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(BUTTON_W, BUTTON_H)
    b:SetBackdrop(BACKDROP)
    b:SetBackdropColor(bgMedium[1], bgMedium[2], bgMedium[3], 1)
    b:SetBackdropBorderColor(border[1], border[2], border[3], 1)

    b.label = b:CreateFontString(nil, "OVERLAY")
    b.label:SetPoint("CENTER")
    JT:ApplyThemeFont(b.label, "normal")
    b.label:SetText(label)
    b.label:SetTextColor(1, 1, 1, 1)
    if type(tint) == "table" then
        b.label:SetTextColor(tint[1], tint[2], tint[3], 1)
        b:SetBackdropBorderColor(tint[1], tint[2], tint[3], 1)
    end

    local needed = (b.label:GetStringWidth() or 0) + 24
    if needed > BUTTON_W then b:SetWidth(math.ceil(needed)) end

    local wash = b:CreateTexture(nil, "ARTWORK", nil, -1)
    wash:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    wash:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    wash:SetColorTexture(0.851, 0.851, 0.851, 0.15)
    wash:Hide()
    b:SetScript("OnEnter", function() wash:Show() end)
    b:SetScript("OnLeave", function() wash:Hide() end)
    return b
end

function JT:CreatePrompt(opts)
    opts = opts or {}
    if self.activePrompt then
        self.activePrompt:Hide()
        self.activePrompt = nil
    end

    local T = self.Theme
    -- The prompt follows the window's background colour when one was chosen.
    local bg = T.bgDark
    local saved = self.db and self.db.BgColor
    if type(saved) == "table" and saved[1] and saved[2] and saved[3] then
        bg = { saved[1], saved[2], saved[3], saved[4] or 1 }
    end
    local border = T.border

    local dialog = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dialog:SetSize(POPUP_W, 130)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    dialog:SetFrameStrata("TOOLTIP")
    dialog:SetFrameLevel(100)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog:SetBackdrop(BACKDROP)
    dialog:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    dialog:SetBackdropBorderColor(border[1], border[2], border[3], 1)

    local function Dismiss()
        dialog:Hide()
        if JT.activePrompt == dialog then JT.activePrompt = nil end
    end

    -- Header: title and close button
    local header = CreateFrame("Frame", nil, dialog)
    header:SetHeight(HEADER_H)
    header:SetPoint("TOPLEFT", dialog, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -1, -1)

    local line = header:CreateTexture(nil, "BORDER")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    line:SetColorTexture(border[1], border[2], border[3], 1)

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetPoint("LEFT", header, "LEFT", 12, 0)
    title:SetPoint("RIGHT", header, "RIGHT", -34, 0)
    title:SetJustifyH("CENTER")
    self:ApplyThemeFont(title, "large")
    title:SetText(opts.title or "")
    title:SetTextColor(1, 1, 1, 1)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(18, 18)
    close:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    local closeTex = close:CreateTexture(nil, "ARTWORK")
    closeTex:SetPoint("CENTER")
    closeTex:SetSize(13, 13)
    closeTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    closeTex:SetVertexColor(0.851, 0.851, 0.851, 1)
    close:SetScript("OnEnter", function() closeTex:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1) end)
    close:SetScript("OnLeave", function() closeTex:SetVertexColor(0.851, 0.851, 0.851, 1) end)
    close:SetScript("OnClick", function()
        if opts.onCancel then opts.onCancel("close") end
        Dismiss()
    end)

    -- Message
    local message = dialog:CreateFontString(nil, "OVERLAY")
    message:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -12)
    message:SetWidth(POPUP_W - 24)
    message:SetJustifyH("CENTER")
    message:SetJustifyV("TOP")
    self:ApplyThemeFont(message, "normal")
    message:SetText(opts.text or "")
    message:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)

    -- Buttons
    local accept = PromptButton(dialog, opts.acceptText or L["Accept"], opts.acceptColor, T.bgMedium, border)
    local cancel = PromptButton(dialog, opts.cancelText or L["Decline"], opts.cancelColor, T.bgMedium, border)
    accept:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -6, 12)
    cancel:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 6, 12)
    accept:SetScript("OnClick", function()
        Dismiss()
        if opts.onAccept then opts.onAccept() end
    end)
    cancel:SetScript("OnClick", function()
        if opts.onCancel then opts.onCancel("decline") end
        Dismiss()
    end)

    -- Grow to fit the message: header + gap + text + gap + buttons + gap.
    local textH = math_max(14, message:GetStringHeight() or 14)
    dialog:SetHeight(HEADER_H + 12 + textH + 14 + BUTTON_H + 12)

    self.activePrompt = dialog
    dialog:Show()
    return dialog
end
