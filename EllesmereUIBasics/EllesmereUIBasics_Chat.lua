-------------------------------------------------------------------------------
--  EllesmereUIBasics_Chat.lua
--  Message-level chat enhancements: class colors, URLs, channel shortening,
--  timestamps, copy dialog, and search.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

local function GetChatDB()
    local db = _G._EBS_AceDB
    return db and db.profile and db.profile.chat
end

-------------------------------------------------------------------------------
--  Channel Shortening
-------------------------------------------------------------------------------
local CHANNEL_ABBREVS = {
    ["General"]         = "G",
    ["Trade"]           = "T",
    ["LocalDefense"]    = "LD",
    ["LookingForGroup"] = "LFG",
    ["WorldDefense"]    = "WD",
    ["Newcomer"]        = "N",
    ["Services"]        = "S",
}

local function ShortenChannelName(channelName, mode)
    if mode == "off" then return nil end
    -- Match "N. ChannelName" pattern (e.g., "2. Trade - City")
    local num, name = channelName:match("^(%d+)%.%s*(.+)")
    if not num then return nil end
    -- Strip region suffix: "Trade - City" → "Trade"
    local baseName = name:match("^(%S+)") or name
    local short = CHANNEL_ABBREVS[baseName]
    if short then
        if mode == "minimal" then
            return short
        else
            return num .. ". " .. short
        end
    end
    return nil
end

-- Filter: rewrite channel headers in chat messages
local CHANNEL_EVENTS = {
    "CHAT_MSG_CHANNEL",
}

local function ChannelFilter(self, event, msg, author, lang, channelName, ...)
    local p = GetChatDB()
    if not p or p.shortenChannels == "off" then return false end
    local short = ShortenChannelName(channelName, p.shortenChannels)
    if short then
        return false, msg, author, lang, short, ...
    end
    return false
end

for _, event in ipairs(CHANNEL_EVENTS) do
    ChatFrame_AddMessageEventFilter(event, ChannelFilter)
end

-------------------------------------------------------------------------------
--  Class-Colored Names
--  Hook GetColoredName() which is called by ChatFrame_MessageEventHandler
--  to produce the display name shown in chat. This runs AFTER message filters
--  but BEFORE the final AddMessage, so it's the correct place to inject
--  class color codes into the player name.
-------------------------------------------------------------------------------
local origGetColoredName

local function ClassColoredGetColoredName(event, ...)
    local p = GetChatDB()
    if not p or not p.classColorNames then
        return origGetColoredName(event, ...)
    end

    -- GetColoredName args: event, arg1(msg), arg2(author), ... arg12(guid)
    local guid = select(12, ...)
    if guid and guid ~= "" then
        local _, engClass = GetPlayerInfoByGUID(guid)
        if engClass then
            local cc = RAID_CLASS_COLORS[engClass]
            if cc then
                local name = origGetColoredName(event, ...)
                -- Strip any existing color codes from the name
                local plainName = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                return ("|cff%02x%02x%02x%s|r"):format(
                    math.floor(cc.r * 255 + 0.5),
                    math.floor(cc.g * 255 + 0.5),
                    math.floor(cc.b * 255 + 0.5),
                    plainName)
            end
        end
    end
    return origGetColoredName(event, ...)
end

-- Install hook once at load time
if GetColoredName then
    origGetColoredName = GetColoredName
    GetColoredName = ClassColoredGetColoredName
end

-------------------------------------------------------------------------------
--  Clickable URLs
-------------------------------------------------------------------------------
local URL_PATTERNS = {
    -- protocol://anything
    "(https?://[%w_.~!*'();:@&=+$,/?#%%%-]+)",
    -- www.domain.tld/path
    "(www%.[%w_%-]+%.%w+[%w_.~!*'();:@&=+$,/?#%%%-]*)",
}

local function LinkifyURLs(msg)
    for _, pat in ipairs(URL_PATTERNS) do
        msg = msg:gsub(pat, function(url)
            return "|Heuiurl:" .. url .. "|h|cff3399FF[" .. url .. "]|r|h"
        end)
    end
    return msg
end

local URL_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL",
}

local function URLFilter(self, event, msg, ...)
    local p = GetChatDB()
    if not p or not p.clickableURLs then return false end
    if msg:find("|Heuiurl:") then return false end
    local linked = LinkifyURLs(msg)
    if linked ~= msg then
        return false, linked, ...
    end
    return false
end

for _, event in ipairs(URL_EVENTS) do
    ChatFrame_AddMessageEventFilter(event, URLFilter)
end

-- Hook SetItemRef to handle euiurl clicks → copy dialog
local origSetItemRef = SetItemRef
function SetItemRef(link, text, button, chatFrame)
    local url = link:match("^euiurl:(.+)")
    if url then
        local popup = _G["EBS_URLCopyDialog"]
        if not popup then
            popup = CreateFrame("Frame", "EBS_URLCopyDialog", UIParent, "BackdropTemplate")
            popup:SetSize(450, 80)
            popup:SetPoint("CENTER")
            popup:SetFrameStrata("DIALOG")
            popup:SetBackdrop({
                bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            popup:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
            popup:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

            local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            title:SetPoint("TOPLEFT", 12, -8)
            title:SetText("Copy URL (Ctrl+C)")
            title:SetTextColor(0.7, 0.7, 0.7)

            local eb = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
            eb:SetSize(420, 20)
            eb:SetPoint("BOTTOM", 0, 16)
            eb:SetAutoFocus(true)
            eb:SetScript("OnEscapePressed", function() popup:Hide() end)
            eb:SetScript("OnEnterPressed", function() popup:Hide() end)
            popup._editBox = eb

            popup:SetScript("OnShow", function(self)
                self._editBox:SetText(self._url or "")
                self._editBox:HighlightText()
                self._editBox:SetFocus()
            end)
            popup:EnableMouse(true)
            popup:SetMovable(true)
            popup:RegisterForDrag("LeftButton")
            popup:SetScript("OnDragStart", popup.StartMoving)
            popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
            tinsert(UISpecialFrames, "EBS_URLCopyDialog")
        end
        popup._url = url
        popup:Show()
        return
    end
    return origSetItemRef(link, text, button, chatFrame)
end

-------------------------------------------------------------------------------
--  Timestamps
-------------------------------------------------------------------------------
local TIMESTAMP_FORMATS = {
    ["none"]         = "none",
    ["HH:MM"]        = "[%H:%M] ",
    ["HH:MM:SS"]     = "[%H:%M:%S] ",
    ["HH:MM AP"]     = "[%I:%M %p] ",
    ["HH:MM:SS AP"]  = "[%I:%M:%S %p] ",
}

local function ApplyTimestamps()
    local p = GetChatDB()
    if not p then return end
    local fmt = p.timestamps or "none"
    local cvarFmt = TIMESTAMP_FORMATS[fmt] or "none"
    SetCVar("showTimestamps", cvarFmt)
end

_G._EBS_ApplyTimestamps = ApplyTimestamps

local tsFrame = CreateFrame("Frame")
tsFrame:RegisterEvent("PLAYER_LOGIN")
tsFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer.After(0.5, ApplyTimestamps)
end)
