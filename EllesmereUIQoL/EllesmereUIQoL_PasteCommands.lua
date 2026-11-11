if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- /euipaste runs a pasted block of addon slash commands. Off by default and reload-gated.
if not (EllesmereUIDB and EllesmereUIDB.pasteCommands == true) then return end

local EUI = EllesmereUI

local SLASH      = "/euipaste"
local OWN_KEY    = "EUIPASTE"
local MACRO_NAME = "EUI_Paste"
local PREFIX     = EUI.COLOR_CODES.BRAND .. "EllesmereUI:|r "

local function Say(msg) EUI.Print(PREFIX .. msg) end

local function SplitLines(text)
    local lines = {}
    for line in (text:gsub("\r\n?", "\n") .. "\n"):gmatch("(.-)\n") do
        line = strtrim(line)
        if line ~= "" then lines[#lines + 1] = line end
    end
    return lines
end

local function CountWayCommands(text)
    local count = 0
    for _, line in ipairs(SplitLines(text or "")) do
        local cmd = line:match("^(/%S+)")
        if cmd and cmd:lower() == "/way" then count = count + 1 end
    end
    return count
end

-- The chat code moves commands it has imported into hash_SlashCmdList; the rest wait in SlashCmdList.
local function LookupCommand(upper)
    local handler = hash_SlashCmdList[upper]
    if handler then return hash_ChatTypeInfoList[upper], handler end
    for key, fn in pairs(SlashCmdList) do
        local i, alias = 1, _G["SLASH_" .. key .. "1"]
        while type(alias) == "string" do
            if alias:upper() == upper then return key, fn end
            i = i + 1
            alias = _G["SLASH_" .. key .. i]
        end
    end
end

-- A secure alias means Blizzard registered the command, so it is never called from this addon.
local function AddonCommand(cmd)
    local key, handler = LookupCommand(cmd:upper())
    if key and key ~= OWN_KEY and not issecurevariable("SLASH_" .. key .. "1") then return handler end
end

local function Run(text)
    local lines, skipped = SplitLines(text), 0
    local editBox = DEFAULT_CHAT_FRAME.editBox
    for _, line in ipairs(lines) do
        local cmd, args = line:match("^(/%S+)%s*(.-)$")
        local handler = cmd and AddonCommand(cmd)
        if handler then
            xpcall(handler, geterrorhandler(), args, editBox)
        else
            skipped = skipped + 1
        end
    end
    if skipped > 0 then
        Say(EllesmereUI.Lf("Skipped %1$d of %2$d lines: only addon slash commands can be pasted.", skipped, #lines))
    end
end

local reopenWindow
local function Open()
    -- Keep one owned popup for the session, rather than creating a complete
    -- frame tree on every /euipaste invocation.
    if reopenWindow then reopenWindow(); return end
    local POPUP_W, POPUP_H = 520, 340
    local FONT = EllesmereUI.EXPRESSWAY

    local dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.25)

    local popup = CreateFrame("Frame", nil, dimmer)
    popup:SetSize(POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    popup:EnableMouse(true)
    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.077, 0.068, 0.058, 1)
    EllesmereUI.MakeRoundedBorder(popup, 1, 1, 1, 0.15, bg)

    local titleFS = EllesmereUI.MakeFont(popup, 15, "", 1, 1, 1)
    titleFS:SetPoint("TOP", popup, "TOP", 0, -20)
    titleFS:SetText(EllesmereUI.L("Paste Commands"))

    local subFS = EllesmereUI.MakeFont(popup, 11, "", 1, 1, 1)
    subFS:SetAlpha(0.45)
    subFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -4)
    subFS:SetText(EllesmereUI.L("One addon slash command per line, such as /way lines"))

    local field = CreateFrame("Frame", nil, popup)
    field:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -52)
    field:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -14, 74)
    field:SetFrameLevel(popup:GetFrameLevel() + 1)
    EllesmereUI.SolidTex(field, "BACKGROUND", 0, 0, 0, 0.3):SetAllPoints()
    EllesmereUI.MakeBorder(field, 1, 1, 1, 0.12, EllesmereUI.PanelPP)

    local sf = CreateFrame("ScrollFrame", nil, popup)
    sf:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -58)
    sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -20, 80)
    sf:SetFrameLevel(popup:GetFrameLevel() + 2)
    sf:EnableMouseWheel(true)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth() or (POPUP_W - 40))
    sc:SetHeight(1)
    sf:SetScrollChild(sc)

    local editBox = CreateFrame("EditBox", nil, sc)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(FONT, 11, "")
    editBox:SetTextColor(1, 1, 1, 0.75)
    editBox:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, 0)
    editBox:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -14, 0)
    editBox:SetHeight(1)

    local UpdateThumb, scrollTo = EllesmereUI.AttachSmoothScrollbar(sf)
    local absorber
    dimmer:HookScript("OnHide", function()
        scrollTo(0)
        editBox:ClearFocus()
        if absorber then absorber.Reset() end
    end)

    editBox:SetScript("OnMouseUp", function(self)
        self:SetFocus()
    end)
    sf:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)

    local function RefreshHeight()
        C_Timer.After(0.01, function()
            local lineH = (editBox.GetLineHeight and editBox:GetLineHeight()) or 14
            local h = editBox:GetNumLines() * lineH
            local sfH = sf:GetHeight() or 100
            if h <= sfH then
                sc:SetHeight(sfH)
                editBox:SetHeight(sfH)
            else
                sc:SetHeight(h + 4)
                editBox:SetHeight(h + 4)
            end
            UpdateThumb()
        end)
    end

    absorber = EllesmereUI.AttachImportPasteAbsorber(editBox)
    local warn = EllesmereUI.MakeFont(popup, 11, "", 1, 0.82, 0.45)
    warn:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 20, 50)
    warn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -20, 50)
    warn:SetJustifyH("LEFT")
    warn:SetWordWrap(true)
    warn:SetText("")

    local function CurrentText()
        return absorber and absorber.GetText and absorber.GetText() or editBox:GetText() or ""
    end

    local function RefreshWarning()
        if CountWayCommands(CurrentText()) > 1 then
            warn:SetText(EUI.L("Recommended: use TomTom or a similar addon so every /way pinpoint from this paste can be saved."))
        else
            warn:SetText("")
        end
    end

    editBox:SetScript("OnTextChanged", function()
        RefreshHeight()
        RefreshWarning()
    end)

    local confirmBtn = CreateFrame("Button", nil, popup)
    confirmBtn:SetSize(120, 26)
    confirmBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 14)
    confirmBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    EllesmereUI.MakeStyledButton(confirmBtn, "Run", 11, EllesmereUI.WB_COLOURS, function()
        local str = CurrentText()
        if str and #str > 0 then
            dimmer:Hide()
            Run(str)
        end
    end)

    local cancelBtn = CreateFrame("Button", nil, popup)
    cancelBtn:SetSize(120, 26)
    cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 14)
    cancelBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    EllesmereUI.MakeStyledButton(cancelBtn, "Cancel", 11, EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)

    dimmer:SetScript("OnMouseDown", function()
        if not popup:IsMouseOver() then dimmer:Hide() end
    end)

    EllesmereUI.PopupTakeKeys(popup, dimmer)
    popup:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            dimmer:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    reopenWindow = function()
        dimmer:Show()
        RefreshHeight()
        RefreshWarning()
        C_Timer.After(0.05, function()
            if dimmer:IsShown() then editBox:SetFocus() end
        end)
    end
    reopenWindow()
end

-- The macro is the action bar button: created once, then handed to the cursor to drop on a bar.
function EUI._createPasteMacro()
    if InCombatLockdown() then
        Say(EllesmereUI.L("Leave combat to create the macro."))
        return
    end
    if GetMacroIndexByName(MACRO_NAME) == 0 then
        if GetNumMacros() >= Constants.MacroConsts.MAX_ACCOUNT_MACROS then
            Say(EllesmereUI.L("All account macro slots are in use. Delete one to create the macro."))
            return
        end
        CreateMacro(MACRO_NAME, "INV_Misc_Note_01", SLASH, nil)
    end
    -- Found again by name: other addons' macro event handlers run inside CreateMacro and may reorder the list.
    local index = GetMacroIndexByName(MACRO_NAME)
    if index > 0 then PickupMacro(index) end
end

-- One frame after loading, so a /paste another addon registers at load or login is seen.
C_Timer.After(0, function()
    SLASH_EUIPASTE1 = SLASH
    local _, taken = LookupCommand("/PASTE")
    if not taken then SLASH_EUIPASTE2 = "/paste" end
    SlashCmdList[OWN_KEY] = Open
end)
