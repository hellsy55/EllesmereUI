if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- Addon Manager window; runtime and profile storage live in the core module.
-------------------------------------------------------------------------------
local EUI = EllesmereUI
local AM = EUI.AddonManager
local Pool = EUI._Pool
local CreateFrame = Pool.CreateFrame
local ROW_H, INDENT, PAD = 28, 22, 12
local ACCOUNT_VIEW = "\001EUI_ACCOUNT_DEFAULTS"
local state = { query = "", queryRaw = "", folded = {} }
local win
local function Accent()
    local c = EUI.ELLESMERE_GREEN
    if c then return c.r, c.g, c.b end
    return 0.05, 0.82, 0.62
end
local function Font(parent, size, r, g, b, a)
    return EUI.MakeFont(parent, size, nil, r, g, b, a)
end
local function Border(parent, r, g, b, a)
    return EUI.MakeBorder(parent, r, g, b, a, EUI.PanelPP)
end
local function Tip(owner, message)
    EUI.ShowWidgetTooltip(owner, message, { anchor = "right" })
end
local function Untip() EUI.HideWidgetTooltip() end
local function Selected()
    local me, chars = AM.CharKey(), AM.Characters()
    table.insert(chars, 1, ACCOUNT_VIEW)
    local sel, known = state.sel, false
    for _, key in ipairs(chars) do if key == sel then known = true end end
    if not known then sel = me end
    state.sel = sel
    local account = sel == ACCOUNT_VIEW
    local who = account and EUI.L("All Characters")
        or (EUI.IS_FOREVER and AM.Label(sel) or sel:match("^(.-) %- ") or sel)
    return sel, who, chars, account
end
local function Button(parent, label, width, click)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 23)
    EUI.MakeStyledButton(b, label, 12, EUI.RB_COLOURS, click)
    return b
end
local function Choice(parent, width, click)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 20)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    EUI.SolidTex(b, "BACKGROUND", 0.05, 0.05, 0.05, 0.9):SetAllPoints()
    b.border = Border(b, 1, 1, 1, 0.25)
    b.label = Font(b, 12, 1, 1, 1, 0.8)
    b.label:SetPoint("CENTER")
    b:SetScript("OnClick", click)
    b:SetScript("OnLeave", Untip)
    return b
end
local function PaintChoice(b, value, fallback, locked, isDefault)
    local r, g, bl = Accent()
    local on = value == nil and fallback or value
    local label = value == nil and (isDefault and "-" or "Default") or (value and "On" or "Off")
    b.label:SetText(EUI.L(label))
    b.label:SetTextColor(on and r or 1, on and g or 0.45, on and bl or 0.45, locked and 0.5 or value == nil and 0.6 or 1)
    b.border:SetColor(r, g, bl, value == nil and 0.16 or 0.55)
    b:SetEnabled(not locked)
end

local function BuildList(page, host)
    local store = AM.Store()
    local sel, who, _, account = Selected()
    local me = AM.CharKey()
    local totalW = page:GetWidth() - 2 * PAD
    local showUsage = store.usage == true
    local rows, y = {}, -4
    local defaultX = totalW - 222
    local charX = totalW - 116
    local statusX = totalW - (showUsage and 490 or 370)
    local titleWidth = statusX - 18
    local needed = AM.Needed(sel)
    local menu, catcher
    local function Update()
        local pending = #AM.Pending()
        if account then
            if pending > 0 then
                host.pending:SetText(EUI.Lf("%d changes to apply on this character.", pending))
            else
                host.pending:SetText(EUI.L("Editing account defaults for all characters."))
            end
        elseif sel ~= me then
            host.pending:SetText(EUI.Lf("%s is brought in line when it logs in.", who))
        elseif pending > 0 then
            host.pending:SetText(EUI.Lf("%d changes to apply on this character.", pending))
        else
            host.pending:SetText(EUI.L("This character matches the profile."))
        end
        for _, row in ipairs(rows) do
            local a = row.entry.addon
            local def = store.defaults[a.name]
            local c = store.chars[sel]
            local override = c and c.overrides and c.overrides[a.name]
            PaintChoice(row.def, def, a.on, a.locked, true)
            if row.override then PaintChoice(row.override, override, true, a.locked) end
            local current = account and def or override
            if current == nil then current = def end
            if current == nil then current = a.on end
            if needed[a.name] then current = true end
            row.title:SetAlpha(current and 1 or 0.45)
            if sel == me then
                local want = AM.Wanted(a.name, sel)
                if needed[a.name] then want = true end
                row.change:SetText(want ~= nil and want ~= a.on and "*" or "")
            end
            if showUsage then
                if a.loaded then
                    local cpu = AM.Cpu(a.name)
                    row.cpu:SetText(cpu and string.format("%.2f%%", cpu) or "-")
                    row.mem:SetText(string.format("%.1f MB", AM.Memory(a.name) / 1024))
                else row.cpu:SetText(""); row.mem:SetText("") end
            end
        end
        host.RefreshApply()
    end
    local function ShowMenu(anchor, items)
        if not menu then
            catcher = CreateFrame("Button", nil, page)
            catcher:SetAllPoints(page)
            catcher:SetFrameLevel(page:GetFrameLevel() + 15)
            catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            catcher:SetScript("OnClick", function() menu:Hide() end)
            catcher:Hide()
            menu = CreateFrame("Frame", nil, page)
            menu:SetFrameLevel(page:GetFrameLevel() + 20)
            EUI.SolidTex(menu, "BACKGROUND", 0.075, 0.065, 0.06, 1):SetAllPoints()
            Border(menu, 1, 1, 1, 0.3)
            menu.buttons = {}
            menu:SetScript("OnShow", function() catcher:Show() end)
            menu:SetScript("OnHide", function() catcher:Hide() end)
        end
        for _, b in ipairs(menu.buttons) do b:Hide() end
        for i, item in ipairs(items) do
            local b = menu.buttons[i]
            if not b then
                b = CreateFrame("Button", nil, menu)
                b:SetSize(235, 25)
                b:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -(i - 1) * 25)
                b.label = Font(b, 12, 1, 1, 1, 1)
                b.label:SetPoint("LEFT", 10, 0)
                b:SetScript("OnClick", function(self)
                    menu:Hide()
                    if self.callback then self.callback() end
                end)
                menu.buttons[i] = b
            end
            b.label:SetText(item[1])
            b.callback = item[2]
            b:Show()
        end
        menu:SetSize(235, #items * 25)
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 35, -2)
        menu:Show()
    end
    local function CategoryMenu(row)
        local addons, items = row.entry.addons, {}
        local function Add(label, everyone, v)
            items[#items + 1] = { EUI.L(label), function()
                if everyone then AM.SetDefaults(addons, v) else AM.SetOverrides(sel, addons, v) end
                Update()
            end }
        end
        Add("Default: all on", true, true)
        Add("Default: all off", true, false)
        Add("Default: stop managing", true, nil)
        if not account then
            items[#items + 1] = { EUI.Lf("%s: all on", who), function() AM.SetOverrides(sel, addons, true); Update() end }
            items[#items + 1] = { EUI.Lf("%s: all off", who), function() AM.SetOverrides(sel, addons, false); Update() end }
            items[#items + 1] = { EUI.Lf("%s: back to default", who), function() AM.SetOverrides(sel, addons, nil); Update() end }
        end
        ShowMenu(row, items)
    end
    local function MoveMenu(row)
        local a, items = row.entry.addon, {}
        for _, c in ipairs(AM.Categories()) do
            local category = c
            items[#items + 1] = { category, function() AM.SetCategory(a.name, category); host.Rebuild() end }
        end
        items[#items + 1] = { EUI.L("Uncategorized"), function()
            AM.SetCategory(a.name, false); host.Rebuild()
        end }
        items[#items + 1] = { EUI.L("As the addon declares it"), function()
            AM.SetCategory(a.name, nil); host.Rebuild()
        end }
        ShowMenu(row, items)
    end
    y = y - 10
    local headers = {
        { "Addon", 24 }, { "Status", statusX },
        { account and "Account Defaults" or "Default", account and charX or defaultX },
    }
    if not account then headers[#headers + 1] = { who, charX } end
    if showUsage then
        headers[#headers + 1] = { "CPU", totalW - 355 }
        headers[#headers + 1] = { "Memory", totalW - 292 }
    end
    for _, col in ipairs(headers) do
        local h = Font(page, 12, 1, 1, 1, 0.5)
        h:SetPoint("TOPLEFT", page, "TOPLEFT", PAD + col[2], y)
        h:SetText(EUI.L(col[1]))
    end
    y = y - 25
    for index, entry in ipairs(AM.Tree(AM.List(), state.folded, state.query)) do
        local row = CreateFrame(entry.kind == "category" and "Button" or "Frame", nil, page)
        row:SetSize(totalW, ROW_H)
        row:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
        row.entry = entry
        y = y - ROW_H
        EUI.SolidTex(row, "BACKGROUND", 0.15, 0.12, 0.1, entry.kind == "category" and 0.5 or index % 2 == 0 and 0.24 or 0.12):SetAllPoints()
        if entry.kind == "category" then
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local label = Font(row, 13, Accent())
            if entry.count > 0 then
                local symbol = Font(row, 16, 1, 1, 1, 1)
                symbol:SetPoint("LEFT", row, "LEFT", 12, 0)
                symbol:SetWidth(18)
                symbol:SetJustifyH("CENTER")
                symbol:SetText(entry.folded and "+" or "-")
                label:SetPoint("LEFT", symbol, "RIGHT", 4, 0)
            else
                label:SetPoint("LEFT", 14, 0)
            end
            label:SetText(entry.name .. " (" .. entry.count .. ")")
            row:SetScript("OnClick", function(self, button)
                if button == "RightButton" then CategoryMenu(self)
                elseif entry.count > 0 then
                    state.folded[entry.key] = not entry.folded or nil
                    host.Rebuild()
                end
            end)
            row:SetScript("OnEnter", function(self)
                if entry.count > 0 then
                    Tip(self, EUI.L("Click to fold. Right-click to switch all of its addons on or off."))
                else
                    Tip(self, EUI.L("Right-click to manage this category."))
                end
            end)
            row:SetScript("OnLeave", Untip)
            if entry.user then
                local b = Button(row, "Remove", 70, function()
                    EUI:ShowConfirmPopup({
                        title = EUI.L("Remove the category"),
                        message = EUI.Lf("Remove the category %s? Its addons go back to the category they declare.", entry.name),
                        confirmText = EUI.L("Remove"), cancelText = EUI.L("Cancel"),
                        onConfirm = function() AM.RemoveCategory(entry.name); host.Rebuild() end,
                    })
                end)
                b:SetPoint("RIGHT", -8, 0)
            end
        else
            local a = entry.addon
            row:EnableMouse(true)
            local leftX = 10 + INDENT * (entry.depth or 0)
            if entry.members and #entry.members > 1 then
                local foldBtn = CreateFrame("Button", nil, row)
                foldBtn:SetSize(16, 16)
                foldBtn:SetPoint("LEFT", row, "LEFT", leftX, 0)
                local symbol = Font(foldBtn, 16, 1, 1, 1, 1)
                symbol:SetPoint("CENTER")
                symbol:SetText(entry.folded and "+" or "-")
                foldBtn:SetScript("OnClick", function()
                    state.folded[entry.foldKey] = not entry.folded or nil
                    host.Rebuild()
                end)
                foldBtn:SetScript("OnEnter", function(self)
                    Tip(self, EUI.L(entry.folded and "Expand this addon group." or "Collapse this addon group."))
                end)
                foldBtn:SetScript("OnLeave", Untip)
                leftX = leftX + 20
            end
            row.title = Font(row, 13, 1, 1, 1, 1)
            row.title:SetPoint("LEFT", leftX, 0)
            row.title:SetWidth(titleWidth - leftX)
            row.title:SetJustifyH("LEFT")
            row.title:SetWordWrap(false)
            row.title:SetText(a.icon .. " " .. a.shown)
            row.change = Font(row, 12, Accent())
            row.change:SetPoint("LEFT", row.title, "RIGHT", 2, 0)
            row.status = Font(row, 11, 1, 0.5, 0.4, 1)
            row.status:SetPoint("LEFT", row, "LEFT", statusX, 0)
            row.status:SetWidth(100)
            row.status:SetJustifyH("LEFT")
            if not a.loadable and a.reason ~= "DISABLED" then
                row.status:SetText(_G["ADDON_" .. (a.reason or "")] or "")
            end
            row.def = Choice(row, 68, function(self, button)
                local target = self:GetParent().entry
                if target.addon.locked then return end
                local d = store.defaults[target.addon.name]
                if d == nil then d = target.addon.on end
                local v = button == "RightButton" and nil or not d
                for _, member in ipairs(IsShiftKeyDown() and target.members or { target.addon }) do
                    AM.SetDefault(member.name, v)
                end
                Update()
            end)
            row.def:SetPoint("CENTER", row, "LEFT", account and charX or defaultX, 0)
            row.def:SetScript("OnEnter", function(self)
                Tip(self, EUI.L("Default for every character. Click to switch it, right-click to stop managing this addon. Shift acts on the whole group."))
            end)
            if not account then
                row.override = Choice(row, 90, function(self, button)
                    local target = self:GetParent().entry
                    if target.addon.locked then return end
                    local c = store.chars[sel]
                    local v = c and c.overrides and c.overrides[target.addon.name]
                    if button == "RightButton" then v = nil
                    elseif v == nil then v = true
                    elseif v then v = false
                    else v = nil end
                    for _, member in ipairs(IsShiftKeyDown() and target.members or { target.addon }) do
                        AM.SetOverride(sel, member.name, v)
                    end
                    Update()
                end)
                row.override:SetPoint("CENTER", row, "LEFT", charX, 0)
                row.override:SetScript("OnEnter", function(self)
                    Tip(self, EUI.Lf("Override for %s. Click to cycle: default, on, off. Right-click for the default. Shift acts on the whole group.", sel))
                end)
            end
            if showUsage then
                row.cpu = Font(row, 11, 1, 1, 1, 0.8)
                row.cpu:SetPoint("LEFT", row, "LEFT", totalW - 355, 0)
                row.mem = Font(row, 11, 1, 1, 1, 0.8)
                row.mem:SetPoint("LEFT", row, "LEFT", totalW - 292, 0)
            end
            row:SetScript("OnEnter", function(self)
                local lines = { a.notes or "", a.name }
                local deps = { C_AddOns.GetAddOnDependencies(a.name) }
                if #deps > 0 then lines[#lines + 1] = EUI.Lf("Needs: %s", table.concat(deps, ", ")) end
                if entry.members and #entry.members > 1 then
                    lines[#lines + 1] = EUI.L(entry.folded and "Click + to expand this addon group." or "Click - to collapse this addon group.")
                end
                if needed[a.name] then lines[#lines + 1] = EUI.Lf("Kept on for %s", needed[a.name]) end
                Tip(self, table.concat(lines, "\n"))
            end)
            row:SetScript("OnLeave", Untip)
            row:SetScript("OnMouseUp", function(self, button)
                if button == "RightButton" and not self.entry.sub then MoveMenu(self) end
            end)
            rows[#rows + 1] = row
        end
    end
    if showUsage then AM.RefreshMemory() end
    Update()
    return math.abs(y) + 20
end

local WIN_W, WIN_H = 820, 660
local function CreateWindow()
    local f = CreateFrame("Frame", "EllesmereUIAddonManagerWindow", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    EUI.SolidTex(f, "BACKGROUND", 0.077, 0.068, 0.058, 0.98):SetAllPoints()
    Border(f, 1, 1, 1, 0.15)
    local level = f:GetFrameLevel()
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(36)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local title = Font(bar, 16, 1, 1, 1, 1)
    title:SetPoint("LEFT", 16, 0)
    title:SetText(EUI.L("Addon Manager"))
    local close = Button(bar, "X", 26, function() f:Hide() end)
    close:SetPoint("RIGHT", -8, 0)
    local line = EUI.SolidTex(f, "BORDER", 1, 1, 1, 0.08)
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -36)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -36)
    line:SetHeight(1)
    local function Enabled()
        local s = AM.Store()
        return s ~= nil and s.enabled == true
    end
    local toggle, _, snap = EUI.BuildToggleControl(f, level + 3, Enabled, function(v)
        AM.SetEnabled(v)
        AM.BeginEdit()
        f.Rebuild()
    end)
    toggle:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -48)
    local enableLabel = Font(f, 13, 1, 1, 1, 1)
    enableLabel:SetPoint("LEFT", toggle, "RIGHT", 10, 0)
    enableLabel:SetText(EUI.L("Enable Addon Manager"))
    local cogRows = {
        { type = "dropdown", label = "Open With",
          tooltip = "Choose whether the Addon Manager starts with account-wide defaults or the logged-in character. You can still switch views in its character selector.",
          values = { character = "Current Character", account = "All Characters" },
          order = { "character", "account" },
          get = AM.GetStartView, set = AM.SetStartView },
        { type = "toggle", label = "Open from the game menu",
          tooltip = "The game menu's AddOns button opens this window instead of the game's AddOn list. Out of combat only.",
          get = function() local s = AM.Store(); return s and s.menu == true end,
          set = function(v) local s = AM.Store(); if s then s.menu = v or nil end; if v then AM.HookMenu() end end },
        { type = "toggle", label = "Offer to apply at login",
          tooltip = "When a character differs from the profile at login, offers to apply the changes and reload.",
          get = function() local s = AM.Store(); return s and not s.quiet end,
          set = function(v) local s = AM.Store(); if s then s.quiet = not v or nil end end },
        { type = "toggle", label = "Show CPU and memory use",
          tooltip = "Adds CPU and memory columns for the addons that are loaded.",
          get = function() local s = AM.Store(); return s and s.usage == true end,
          set = function(v) local s = AM.Store(); if s then s.usage = v or nil end; f.Rebuild(true) end },
        { type = "button", label = "Add a Category", action = function()
            EUI:ShowInputPopup({
                title = EUI.L("Add a Category"),
                message = EUI.L("Name of the category. Right-click an addon to put it in one."),
                placeholder = EUI.L("Category name"), confirmText = EUI.L("Add"),
                onConfirm = function(name)
                    if AM.AddCategory(name) then f.Rebuild(true)
                    else UIErrorsFrame:AddMessage(EUI.L("That category already exists."), 1, 0.3, 0.3) end
                end,
            })
        end },
        { type = "button", label = "Defaults From This Character", action = function()
            EUI:ShowConfirmPopup({
                title = EUI.L("Defaults From This Character"),
                message = EUI.L("Makes the addons that are on for this character the default for every character."),
                confirmText = EUI.L("Replace"), cancelText = EUI.L("Cancel"),
                onConfirm = function() AM.DefaultsFromThisCharacter(); f.Rebuild(true) end,
            })
        end },
        { type = "button", label = "Blizzard AddOn Menu", action = function() AM.ShowBlizzardList() end },
        { type = "button", label = "Refresh Usage", hidden = function()
            local s = AM.Store(); return not (s and s.usage)
        end, action = function() AM.RefreshMemory(true); f.Rebuild(true) end },
    }
    local cog = EUI.BuildInlineCog(f, { title = "Addon Manager", rows = cogRows,
        anchorTo = enableLabel, relPoint = "RIGHT", gap = -34, chain = false })
    local ddHolder = CreateFrame("Frame", nil, f)
    ddHolder:SetSize(300, 26)
    ddHolder:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -47)
    local charLabel = Font(f, 13, 1, 1, 1, 0.6)
    charLabel:SetPoint("RIGHT", ddHolder, "LEFT", -10, 0)
    charLabel:SetText(EUI.L("Character"))
    local box = CreateFrame("EditBox", nil, f)
    box:SetSize(300, 26)
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -86)
    box:SetAutoFocus(false)
    box:SetTextInsets(8, 8, 0, 0)
    local face, _, flags = Font(f, 13, 1, 1, 1, 1):GetFont()
    box:SetFont(face, 13, flags)
    box:SetTextColor(1, 1, 1, 1)
    EUI.SolidTex(box, "BACKGROUND", 0.05, 0.05, 0.05, 0.9):SetAllPoints()
    Border(box, 1, 1, 1, 0.2)
    local hint = Font(box, 13, 1, 1, 1, 0.35)
    hint:SetPoint("LEFT", 8, 0)
    hint:SetText(EUI.L("Search addons"))
    box:SetScript("OnTextChanged", function(self, user)
        hint:SetShown(self:GetText() == "")
        if not user then return end
        local raw = self:GetText()
        if raw == state.queryRaw then return end
        state.queryRaw, state.query = raw, raw:lower()
        local stamp = (self._stamp or 0) + 1
        self._stamp = stamp
        C_Timer.After(0.25, function() if self._stamp == stamp then f.Rebuild(true) end end)
    end)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    local function ApplyAllForSelection(value)
        local sel, _, _, account = Selected()
        local addons = AM.List()
        if account then AM.SetDefaults(addons, value)
        else AM.SetOverrides(sel, addons, value) end
        f.Rebuild(true)
    end
    local apply = Button(f, "Apply and Reload", 170, function()
        if InCombatLockdown() or #AM.Pending() == 0 then return end
        f.applying = true
        EUI.RequestReload(nil, nil, AM.ApplyNative)
    end)
    apply:SetHeight(26)
    apply:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -86)
    local enableAll = Button(f, "Enable All", 104, function() ApplyAllForSelection(true) end)
    enableAll:SetHeight(26)
    enableAll:SetPoint("RIGHT", apply, "LEFT", -8, 0)
    enableAll:SetScript("OnEnter", function(self)
        local _, who, _, account = Selected()
        Tip(self, account and EUI.L("Turns every account default on.") or EUI.Lf("Turns every addon on for %s.", who))
    end)
    enableAll:SetScript("OnLeave", Untip)
    local disableAll = Button(f, "Disable All", 104, function() ApplyAllForSelection(false) end)
    disableAll:SetHeight(26)
    disableAll:SetPoint("RIGHT", enableAll, "LEFT", -8, 0)
    disableAll:SetScript("OnEnter", function(self)
        local _, who, _, account = Selected()
        Tip(self, account and EUI.L("Turns every account default off.") or EUI.Lf("Turns every addon off for %s.", who))
    end)
    disableAll:SetScript("OnLeave", Untip)
    function f.RefreshApply()
        local ok = Enabled() and not InCombatLockdown() and #AM.Pending() > 0
        apply:SetEnabled(ok)
        apply:SetAlpha(ok and 1 or 0.4)
        local canEdit = Enabled()
        enableAll:SetEnabled(canEdit)
        enableAll:SetAlpha(canEdit and 1 or 0.4)
        disableAll:SetEnabled(canEdit)
        disableAll:SetAlpha(canEdit and 1 or 0.4)
    end
    local pending = Font(f, 12, 1, 1, 1, 0.5)
    pending:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -122)
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -146)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 10)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(WIN_W - 14, 10)
    sf:SetScrollChild(content)
    local updateThumb = EUI.AttachSmoothScrollbar(sf, { child = content, step = 56 })
    local off = Font(f, 13, 1, 1, 1, 0.5)
    off:SetPoint("TOP", sf, "TOP", 0, -40)
    off:SetText(EUI.L("The Addon Manager is off. Switch it on above."))
    local host = {
        pending = pending, Selected = Selected,
        RefreshApply = function() f.RefreshApply() end,
        Rebuild = function()
            -- Do not reset pooled rows while their click handler is running.
            C_Timer.After(0, function() if f:IsShown() then f.Rebuild(true) end end)
        end,
    }
    local page, ddRegion
    function f.Rebuild(keepSearch)
        local on = Enabled()
        snap()
        cog:SetShown(on); box:SetShown(on); apply:SetShown(on); enableAll:SetShown(on); disableAll:SetShown(on); pending:SetShown(on)
        charLabel:SetShown(on); ddHolder:SetShown(on); off:SetShown(not on)
        if not on then
            if ddRegion then ddRegion:Hide() end
            if page then page:Hide() end
            content:SetHeight(10); pending:SetText(""); f.RefreshApply()
            return
        end
        local _, _, chars = Selected()
        local values = {}
        for _, key in ipairs(chars) do
            values[key] = key == ACCOUNT_VIEW and EUI.L("All Characters") or AM.Label(key)
        end
        -- Kept hosts reset their pooled descendants on rebuild. Searching,
        -- folding and switching characters no longer leave detached UI frames.
        ddRegion = Pool.Kept(f, "addon-manager-selector", "Frame", ddHolder, nil, nil, true)
        ddRegion:SetAllPoints(ddHolder)
        local dd = EUI.BuildDropdownControl(ddRegion, 300, level + 3, values, chars,
            function() return state.sel end,
            function(key)
                state.sel = key
                -- The dropdown's menu is still handling this click.
                C_Timer.After(0, function() if f:IsShown() then f.Rebuild(true) end end)
            end)
        dd:SetPoint("TOPRIGHT", ddRegion, "TOPRIGHT", 0, 0)
        ddRegion:Show()
        if keepSearch ~= true then box:SetText(state.queryRaw or "") end
        local keep = sf:GetVerticalScroll()
        page = Pool.Kept(f, "addon-manager-list", "Frame", content, nil, nil, true)
        page:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        page:SetSize(content:GetWidth(), 10)
        local h = BuildList(page, host)
        page:SetHeight(h)
        content:SetHeight(h)
        page:Show()
        sf:SetVerticalScroll(math.min(keep, math.max(0, h - sf:GetHeight())))
        if updateThumb then updateThumb() end
        f.RefreshApply()
    end
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(self) self.RefreshApply() end)
    f:SetScript("OnShow", function(self)
        state.sel = AM.GetStartView() == "account" and ACCOUNT_VIEW or AM.CharKey()
        self:Raise(); AM.BeginEdit(); self.Rebuild()
    end)
    f:SetScript("OnHide", function(self)
        if self.applying then return end
        if not AM.Edited() or #AM.Pending() == 0 then AM.EndEdit(true); return end
        EUI:ShowConfirmPopup({
            title = EUI.L("Addon Manager"),
            message = EUI.L("Your changes only apply after a reload. Apply them and reload now? Otherwise they are discarded."),
            confirmText = EUI.L("Apply and Reload"), cancelText = EUI.L("Discard Changes"),
            confirmDisabled = InCombatLockdown(), reload = true,
            onConfirm = AM.ApplyNative,
            onCancel = function() AM.EndEdit(false) end,
        })
    end)
    EUI.RegisterEscapeClose(f)
    return f
end
function EUI.AddonManagerWindow(show)
    if not win then win = CreateWindow() end
    if show == nil then show = not win:IsShown() end
    if show then
        if win:IsShown() then win:Raise(); win.Rebuild()
        else win:Show() end
    else win:Hide() end
end
