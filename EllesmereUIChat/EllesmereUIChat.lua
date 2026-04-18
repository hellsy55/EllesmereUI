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
    if not text or text == "" then return end
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
    "%f[%S](www%.[-%w_%%]+%.%a%a+/%S+)",
    "%f[%S](www%.[-%w_%%]+%.%a%a+)",
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
        text = text:gsub(p, "|cff3fc7eb|H" .. addonName .. "url:%1|h[%1]|h|r")
    end
    return text
end

local copyPopup, copyBackdrop

local function HideCopyPopup()
    if copyPopup then copyPopup:Hide() end
    if copyBackdrop then copyBackdrop:Hide() end
end

local function ShowCopyPopup(text, width, height, multiline)
    width = width or 300
    height = height or 52

    if not copyPopup then
        copyBackdrop = CreateFrame("Button", nil, UIParent)
        copyBackdrop:SetFrameStrata("DIALOG")
        copyBackdrop:SetFrameLevel(499)
        copyBackdrop:SetAllPoints(UIParent)
        local bdTex = copyBackdrop:CreateTexture(nil, "BACKGROUND")
        bdTex:SetAllPoints()
        bdTex:SetColorTexture(0, 0, 0, 0.25)
        copyBackdrop:RegisterForClicks("AnyUp")
        copyBackdrop:SetScript("OnClick", HideCopyPopup)
        copyBackdrop:Hide()

        copyPopup = CreateFrame("Frame", nil, UIParent)
        copyPopup:SetFrameStrata("DIALOG")
        copyPopup:SetFrameLevel(500)
        copyPopup:EnableMouse(true)

        local bg = copyPopup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.08, 0.10, 0.97)
        if PP and PP.CreateBorder then
            PP.CreateBorder(copyPopup, 1, 1, 1, 0.15, 1, "OVERLAY", 7)
        end

        local hint = copyPopup:CreateFontString(nil, "OVERLAY")
        hint:SetFont(GetFont(), 8, "")
        hint:SetTextColor(1, 1, 1, 0.5)
        hint:SetPoint("TOP", copyPopup, "TOP", 0, -6)
        hint:SetText("Ctrl+C to copy, Escape to close")
        copyPopup._hint = hint
    end

    if copyPopup._eb then copyPopup._eb:Hide(); copyPopup._eb:SetParent(nil); copyPopup._eb = nil end
    if copyPopup._sf then copyPopup._sf:Hide(); copyPopup._sf:SetParent(nil); copyPopup._sf = nil end

    copyPopup:SetSize(width, height)

    if multiline then
        local sf = CreateFrame("ScrollFrame", nil, copyPopup, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", copyPopup._hint, "BOTTOMLEFT", -4, -4)
        sf:SetPoint("BOTTOMRIGHT", copyPopup, "BOTTOMRIGHT", -26, 8)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFont(GetFont(), 11, "")
        eb:SetTextColor(1, 1, 1, 0.9)
        eb:SetWidth(width - 40)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); HideCopyPopup() end)
        sf:SetScrollChild(eb)
        eb:SetText(text)
        eb:SetCursorPosition(0)
        C_Timer.After(0, function() eb:SetFocus(); eb:HighlightText() end)
        copyPopup._eb = eb
        copyPopup._sf = sf
    else
        local eb = CreateFrame("EditBox", nil, copyPopup)
        eb:SetSize(width - 40, 16)
        eb:SetPoint("TOP", copyPopup._hint, "BOTTOM", 0, -4)
        eb:SetFont(GetFont(), 11, "")
        eb:SetAutoFocus(false)
        eb:SetJustifyH("CENTER")
        local ebBg = eb:CreateTexture(nil, "BACKGROUND")
        ebBg:SetColorTexture(0.10, 0.12, 0.16, 1)
        ebBg:SetPoint("TOPLEFT", -6, 4); ebBg:SetPoint("BOTTOMRIGHT", 6, -4)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); HideCopyPopup() end)
        eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        eb:SetText(text); eb:SetFocus(); eb:HighlightText()
        copyPopup._eb = eb
    end

    copyPopup:ClearAllPoints()
    copyPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    copyBackdrop:Show()
    copyPopup:Show()
end

hooksecurefunc("SetItemRef", function(link)
    if not link then return end
    local url = link:match("^" .. addonName .. "url:(.+)$")
    if url then ShowCopyPopup(url, 400, 52) end
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
        bg:SetPoint("TOPLEFT", cf, "TOPLEFT", -4, 4)
        bg:SetPoint("BOTTOMRIGHT", eb or cf, "BOTTOMRIGHT", 4, eb and -4 or -6)
        bg:SetFrameLevel(math.max(0, cf:GetFrameLevel() - 1))

        local bgTex = bg:CreateTexture(nil, "BACKGROUND")
        bgTex._euiOwned = true
        bgTex:SetAllPoints()
        bgTex:SetColorTexture(BG_R, BG_G, BG_B, BG_A)

        if PP and PP.CreateBorder then
            PP.CreateBorder(bg, 1, 1, 1, 0.06, 1, "OVERLAY", 7)
        end
        cf._euiBg = bg
    end

    -- Vertical timestamp divider at x=42 (timestamps sit left, messages right)
    if not cf._euiTimestampDiv then
        local onePx = (PP and PP.mult) or 1
        local div = cf._euiBg:CreateTexture(nil, "OVERLAY", nil, 7)
        div._euiOwned = true
        div:SetWidth(onePx)
        div:SetColorTexture(1, 1, 1, 0.06)
        div:SetPoint("TOPLEFT", cf, "TOPLEFT", 42, 0)
        div:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 42, 0)
        if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(div) end
        cf._euiTimestampDiv = div
    end

    -- Horizontal divider above input field
    if not cf._euiInputDiv then
        local onePx = (PP and PP.mult) or 1
        local div = cf._euiBg:CreateTexture(nil, "OVERLAY", nil, 7)
        div._euiOwned = true
        div:SetHeight(onePx)
        div:SetColorTexture(1, 1, 1, 0.06)
        div:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", -4, 0)
        div:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 4, 0)
        if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(div) end
        cf._euiInputDiv = div
    end

    -- Set custom font on the message frame
    local _, fontSize = cf:GetFont()
    cf:SetFont(GetFont(), fontSize or 12, "")
    if cf.SetShadowOffset then cf:SetShadowOffset(1, -1) end
    if cf.SetShadowColor then cf:SetShadowColor(0, 0, 0, 0.8) end

    -- Disable Blizzard timestamps -- we prepend our own via AddMessage hook
    -- so the timestamp sits in the left column and message text starts right
    -- of the vertical divider.
    if SetCVar then
        SetCVar("showTimestamps", "none")
    end

    -- Wrapped lines indent to match the first line's text start position,
    -- keeping continuation lines aligned with the message (not the timestamp).
    cf:SetIndentedWordWrap(true)

    -- Hook AddMessage to prepend a dim timestamp. The timestamp renders
    -- at x=0, and the message text follows naturally after it. The divider
    -- is positioned to sit between the timestamp and the start of messages.
    if not cf._euiAddMsgHooked then
        cf._euiAddMsgHooked = true
        local origAddMessage = cf.AddMessage
        cf.AddMessage = function(self, text, r, g, b, ...)
            if text and text ~= "" then
                local ts = date("%H:%M")
                text = "|cff666666" .. ts .. "|r  " .. text
            end
            return origAddMessage(self, text, r, g, b, ...)
        end
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
        eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -4, 0)
        eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 4, 0)
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

        -- Shrink tab height by 10px
        local origH = tab:GetHeight()
        if origH and origH > 15 then
            tab:SetHeight(origH - 10)
        end

        -- Dark tab background (solid, matches CharSheet)
        if not tab._euiBg then
            tab._euiBg = tab:CreateTexture(nil, "BACKGROUND")
            tab._euiBg:SetAllPoints()
            tab._euiBg:SetColorTexture(BG_R, BG_G, BG_B, 1)
        end

        -- Active highlight overlay (subtle ADD blend)
        if not tab._euiActiveHL then
            local hl = tab:CreateTexture(nil, "ARTWORK", nil, -6)
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.05)
            hl:SetBlendMode("ADD")
            hl:Hide()
            tab._euiActiveHL = hl
        end

        -- Replace Blizzard label with our own FontString (matches CharSheet)
        local blizLabel = tab:GetFontString()
        local labelText = blizLabel and blizLabel:GetText() or ("Tab")
        if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end
        tab:SetPushedTextOffset(0, 0)

        if not tab._euiLabel then
            local label = tab:CreateFontString(nil, "OVERLAY")
            label:SetFont(GetFont(), 9, "")
            label:SetPoint("CENTER", tab, "CENTER", 0, 0)
            label:SetJustifyH("CENTER")
            label:SetText(labelText)
            tab._euiLabel = label
            hooksecurefunc(tab, "SetText", function(_, newText)
                if newText and label then label:SetText(newText) end
            end)
        end

        -- Accent underline (active tab indicator)
        if not tab._euiUnderline then
            local EG = EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
            local ul = tab:CreateTexture(nil, "OVERLAY", nil, 6)
            if PP and PP.DisablePixelSnap then
                PP.DisablePixelSnap(ul)
                ul:SetHeight(PP.mult or 1)
            else
                ul:SetHeight(1)
            end
            ul:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
            ul:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
            ul:SetColorTexture(EG.r, EG.g, EG.b, 1)
            if EUI.RegAccent then
                EUI.RegAccent({ type = "solid", obj = ul, a = 1 })
            end
            ul:Hide()
            tab._euiUnderline = ul
        end
    end

    -- Hide Blizzard button frame + its background
    local btnFrame = _G[name .. "ButtonFrame"]
    if btnFrame then
        btnFrame:SetAlpha(0)
        btnFrame:EnableMouse(false)
        btnFrame:SetWidth(0.1)
        if btnFrame.Background then btnFrame.Background:SetAlpha(0) end
    end

    -- Hide scroll buttons + scroll-to-bottom
    for _, suffix in ipairs({"BottomButton", "DownButton", "UpButton"}) do
        local btn = _G[name .. suffix]
        if btn then btn:SetAlpha(0); btn:EnableMouse(false) end
    end
    if cf.ScrollToBottomButton then
        cf.ScrollToBottomButton:SetAlpha(0)
        cf.ScrollToBottomButton:EnableMouse(false)
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
    -- Parented to our bg frame so it follows the chat frame naturally.
    if not cf._euiScrollTrack and cf.ScrollBar then
        local blizSB = cf.ScrollBar
        local track = CreateFrame("Frame", nil, cf._euiBg)
        track:SetFrameLevel(cf._euiBg:GetFrameLevel() + 10)
        track:SetWidth(3)
        track:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 3, -2)
        track:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 3, 2)

        local thumb = track:CreateTexture(nil, "ARTWORK")
        thumb:SetColorTexture(1, 1, 1, 0.25)
        thumb:SetWidth(3)
        thumb:Hide()

        local function UpdateThumb()
            -- Read scroll percentage from Blizzard's ScrollBar
            local pct = blizSB.GetScrollPercentage and blizSB:GetScrollPercentage()
            local ext = blizSB.GetVisibleExtentPercentage and blizSB:GetVisibleExtentPercentage()
            if not pct or not ext or ext >= 1 then
                thumb:Hide()
                return
            end

            local trackH = track:GetHeight()
            if trackH <= 0 then thumb:Hide(); return end

            local thumbH = math.max(20, trackH * ext)
            local yOff = (trackH - thumbH) * pct

            thumb:ClearAllPoints()
            thumb:SetHeight(thumbH)
            thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -yOff)
            thumb:Show()
        end

        track:SetScript("OnUpdate", function(self, dt)
            self._elapsed = (self._elapsed or 0) + dt
            if self._elapsed < 0.1 then return end
            self._elapsed = 0
            UpdateThumb()
        end)

        cf._euiScrollTrack = track
    end
end

-------------------------------------------------------------------------------
--  Tab color updater (active = accent + underline, inactive = dimmed)
-------------------------------------------------------------------------------
local function UpdateTabColors()
    for i = 1, NUM_CHAT_WINDOWS do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and tab:IsShown() then
            local cf = _G["ChatFrame" .. i]
            local isActive = cf and cf == SELECTED_CHAT_FRAME
            if tab._euiLabel then
                tab._euiLabel:SetTextColor(1, 1, 1, isActive and 1 or 0.5)
            end
            if tab._euiUnderline then
                tab._euiUnderline:SetShown(isActive)
            end
            if tab._euiActiveHL then
                tab._euiActiveHL:SetShown(isActive)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Copy + Search buttons (ChatFrame1)
-------------------------------------------------------------------------------
local function BuildUtilityButtons(cf)
    if cf._euiCopyBtn then return end

    -- Copy button
    local copyBtn = CreateFrame("Button", nil, cf)
    copyBtn:SetSize(14, 14)
    copyBtn:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 0, 2)
    copyBtn:SetFrameLevel(cf:GetFrameLevel() + 10)
    local copyIcon = copyBtn:CreateTexture(nil, "ARTWORK")
    copyIcon:SetAllPoints()
    copyIcon:SetAtlas("communities-icon-searchmagnifyingglass")
    copyIcon:SetDesaturated(true)
    copyIcon:SetVertexColor(1, 1, 1, 0.3)
    copyBtn:HookScript("OnEnter", function(self)
        copyIcon:SetVertexColor(1, 1, 1, 0.9)
        if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Copy Chat") end
    end)
    copyBtn:HookScript("OnLeave", function(self)
        copyIcon:SetVertexColor(1, 1, 1, 0.3)
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)
    copyBtn:SetScript("OnClick", function()
        local lines = {}
        for i = 1, #chatHistory do
            lines[#lines + 1] = StripUIEscapes(chatHistory[i])
        end
        local fullText = table.concat(lines, "\n")
        if fullText == "" then fullText = "(No chat history this session)" end
        ShowCopyPopup(fullText, 500, 400, true)
    end)
    cf._euiCopyBtn = copyBtn

    -- Search bar (hidden by default)
    local bar = CreateFrame("EditBox", nil, cf)
    bar:SetSize(140, 18)
    bar:SetPoint("TOPRIGHT", copyBtn, "TOPLEFT", -6, 1)
    bar:SetFrameLevel(cf:GetFrameLevel() + 10)
    bar:SetFont(GetFont(), 10, "")
    bar:SetTextColor(1, 1, 1, 0.9)
    bar:SetAutoFocus(false)
    bar:SetMaxLetters(50)
    bar:SetTextInsets(6, 6, 0, 0)
    bar:Hide()

    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetColorTexture(EDIT_BG_R, EDIT_BG_G, EDIT_BG_B, 0.92)
    barBg:SetAllPoints()
    if PP and PP.CreateBorder then
        PP.CreateBorder(bar, 1, 1, 1, 0.06, 1, "OVERLAY", 7)
    end

    local ph = bar:CreateFontString(nil, "OVERLAY")
    ph:SetFont(GetFont(), 10, "")
    ph:SetTextColor(1, 1, 1, 0.25)
    ph:SetPoint("LEFT", bar, "LEFT", 6, 0)
    ph:SetText("Search...")
    bar._placeholder = ph

    local function RestoreChat()
        cf:Clear()
        for i = 1, #chatHistory do cf:AddMessage(chatHistory[i]) end
    end

    bar:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local query = self:GetText()
        ph:SetShown(query == "")
        if query == "" then RestoreChat(); return end
        local lowerQ = query:lower()
        cf:Clear()
        for i = 1, #chatHistory do
            if StripUIEscapes(chatHistory[i]):lower():find(lowerQ, 1, true) then
                cf:AddMessage(chatHistory[i])
            end
        end
    end)

    local function CloseSearch()
        bar:SetText(""); bar:ClearFocus(); bar:Hide()
        RestoreChat()
    end
    bar:SetScript("OnEscapePressed", CloseSearch)
    bar:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self:Hide() end
    end)
    cf._euiSearchBar = bar

    -- Search toggle button
    local searchBtn = CreateFrame("Button", nil, cf)
    searchBtn:SetSize(14, 14)
    searchBtn:SetPoint("RIGHT", copyBtn, "LEFT", -4, 0)
    searchBtn:SetFrameLevel(cf:GetFrameLevel() + 10)
    local searchIcon = searchBtn:CreateTexture(nil, "ARTWORK")
    searchIcon:SetAllPoints()
    searchIcon:SetAtlas("common-search-magnifyingglass")
    searchIcon:SetDesaturated(true)
    searchIcon:SetVertexColor(1, 1, 1, 0.3)
    searchBtn:HookScript("OnEnter", function(self)
        searchIcon:SetVertexColor(1, 1, 1, 0.9)
        if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Search Chat") end
    end)
    searchBtn:HookScript("OnLeave", function(self)
        searchIcon:SetVertexColor(1, 1, 1, 0.3)
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)
    searchBtn:SetScript("OnClick", function()
        if bar:IsShown() then CloseSearch()
        else bar:Show(); bar:SetFocus() end
    end)
    cf._euiSearchBtn = searchBtn
end

-------------------------------------------------------------------------------
--  Initialization
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()

    for i = 1, NUM_CHAT_WINDOWS do
        local cf = _G["ChatFrame" .. i]
        if cf then
            SkinChatFrame(cf)
            hooksecurefunc(cf, "AddMessage", CaptureMessage)
        end
    end

    hooksecurefunc("FCF_OpenTemporaryWindow", function()
        for i = 1, NUM_CHAT_WINDOWS do
            local cf = _G["ChatFrame" .. i]
            if cf then SkinChatFrame(cf) end
        end
    end)

    UpdateTabColors()
    hooksecurefunc("FCF_Tab_OnClick", UpdateTabColors)
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

    BuildUtilityButtons(ChatFrame1)

    -- Hide global Blizzard social buttons
    for _, frameName in ipairs({
        "QuickJoinToastButton", "ChatFrameMenuButton", "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
    }) do
        local f = _G[frameName]
        if f then f:SetAlpha(0); f:EnableMouse(false) end
    end
end)
