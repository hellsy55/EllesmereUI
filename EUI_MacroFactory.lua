-------------------------------------------------------------------------------
--  EUI_MacroFactory.lua
--  Builds the Macro Factory UI for the Quality of Life options page.
--  Called by BuildQoLPage via EllesmereUI.BuildMacroFactory(parent, y, PP)
-------------------------------------------------------------------------------

function EllesmereUI.BuildMacroFactory(parent, startY, PP)
    local ICON_SIZE = 40
    local ICON_GAP = 40
    local ICONS_PER_ROW = 4
    local FIRST_ICON_Y = -24
    local ROW_STRIDE = 66
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    local EG = EllesmereUI.ELLESMERE_GREEN
    local y = startY

    ---------------------------------------------------------------------------
    --  Macro definitions
    ---------------------------------------------------------------------------
    local GENERAL_DEFS = {
        {
            name = "EUI_Potion",
            icon = "Interface\\Icons\\inv_potion_54",
            label = "Potion",
            checkboxes = {
                { key = "opt1", label = "Fleeting Light's Potential", items = {245898, 245897} },
                { key = "opt2", label = "Light's Potential",          items = {241308, 241309} },
                { key = "opt3", label = "Fleeting Recklessness",      items = {245902, 245903} },
                { key = "opt4", label = "Recklessness",               items = {241288, 241289} },
            },
        },
        {
            name = "EUI_Health",
            icon = "Interface\\Icons\\inv_potion_131",
            label = "Health Potion",
            checkboxes = {
                { key = "opt1", label = "Silvermoon Health Potion", items = {241304, 241305} },
                { key = "opt2", label = "Healthstone",              items = {5512} },
                { key = "opt3", label = "Demonic Healthstone",      items = {224464} },
            },
        },
        {
            name = "EUI_Food",
            icon = "Interface\\Icons\\inv_misc_food_73cinnamonroll",
            label = "Food",
            checkboxes = {
                { key = "opt1", label = "Conjured Mana Bun",         items = {113509} },
                { key = "opt2", label = "Fairbreeze Feast",           items = {260262} },
                { key = "opt3", label = "Silvermoon Soiree Spread",   items = {260263} },
                { key = "opt4", label = "Quel'Danas Rations",         items = {260264} },
                { key = "opt5", label = "Mana Lily Tea",              items = {242297} },
                { key = "opt6", label = "Springrunner Sparkling",     items = {260260} },
            },
        },
        {
            name = "EUI_Trinket1",
            icon = "Interface\\Icons\\inv_jewelry_trinketpvp_01",
            label = "Trinket 1",
            fixedBody = "/use 13",
            fixedTooltip = "13",
        },
        {
            name = "EUI_Trinket2",
            icon = "Interface\\Icons\\inv_jewelry_trinketpvp_02",
            label = "Trinket 2",
            fixedBody = "/use 14",
            fixedTooltip = "14",
        },
        {
            name = "EUI_Focus",
            icon = "Interface\\Icons\\ability_hunter_focusedaim",
            label = "Focus Mouseover",
            fixedBody = "/focus [@mouseover]",
        },
    }

    ---------------------------------------------------------------------------
    --  DB helper (global scope for polling)
    ---------------------------------------------------------------------------
    local function GetMacroDBByName(macroName)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        if not EllesmereUIDB.macroFactory then EllesmereUIDB.macroFactory = {} end
        if not EllesmereUIDB.macroFactory[macroName] then EllesmereUIDB.macroFactory[macroName] = {} end
        return EllesmereUIDB.macroFactory[macroName]
    end

    ---------------------------------------------------------------------------
    --  Macro body generation
    ---------------------------------------------------------------------------
    local function GetFirstAvailableItemID(def, db)
        if not def.checkboxes then return nil end
        local cbs = def.checkboxes
        local order = db.order
        if not order or #order < #cbs then
            order = {}
            for i = 1, #cbs do order[i] = i end
        end
        for _, idx in ipairs(order) do
            local cb = cbs[idx]
            if cb and db[cb.key] ~= false then
                for _, itemID in ipairs(cb.items) do
                    if C_Item.GetItemCount(itemID) > 0 then
                        return itemID
                    end
                end
            end
        end
        return nil
    end

    local function BuildMacroBody(def, db)
        if def.checkboxes then
            local cbs = def.checkboxes
            local order = db.order
            if not order or #order < #cbs then
                order = {}
                for i = 1, #cbs do order[i] = i end
            end
            local lines = {}
            local firstItemID
            for _, idx in ipairs(order) do
                local cb = cbs[idx]
                if cb and db[cb.key] ~= false then
                    for _, itemID in ipairs(cb.items) do
                        if not firstItemID then firstItemID = itemID end
                        lines[#lines + 1] = "/use item:" .. itemID
                    end
                end
            end
            if #lines == 0 then return "" end
            local body = ""
            if db.showTooltip ~= false then
                local availableItemID = GetFirstAvailableItemID(def, db)
                if availableItemID then
                    body = "#showtooltip item:" .. availableItemID .. "\n"
                elseif firstItemID then
                    body = "#showtooltip item:" .. firstItemID .. "\n"
                end
            end
            return body .. table.concat(lines, "\n")
        elseif def.fixedBody then
            local body = ""
            if db.showTooltip ~= false and def.fixedTooltip then
                body = "#showtooltip " .. def.fixedTooltip .. "\n"
            elseif db.showTooltip ~= false then
                body = "#showtooltip\n"
            end
            return body .. def.fixedBody
        end
        return ""
    end

    local pendingMacroUpdates = {}

    local function UpdateMacro(def, db)
        local idx = GetMacroIndexByName(def.name)
        if idx and idx ~= 0 then
            if InCombatLockdown() then
                pendingMacroUpdates[def.name] = db
            else
                EditMacro(idx, nil, nil, BuildMacroBody(def, db))
            end
        end
    end

    local function ProcessPendingMacroUpdates()
        for macroName, db in pairs(pendingMacroUpdates) do
            local mdef = nil
            for _, def in ipairs(GENERAL_DEFS) do
                if def.name == macroName then
                    mdef = def
                    break
                end
            end
            if mdef then
                local idx = GetMacroIndexByName(mdef.name)
                if idx and idx ~= 0 then
                    EditMacro(idx, nil, nil, BuildMacroBody(mdef, db))
                end
            end
            pendingMacroUpdates[macroName] = nil
        end
    end

    ---------------------------------------------------------------------------
    --  Layout
    ---------------------------------------------------------------------------
    local generalRows = math.ceil(#GENERAL_DEFS / ICONS_PER_ROW)
    local SECTION_H = 92 + ROW_STRIDE * (generalRows - 1)

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(parent:GetWidth(), SECTION_H)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    local halfW = parent:GetWidth() / 2
    local allMacroButtons = {}
    local allCogPopups = {}
    local lastAvailableItems = {}

    -- Center divider (1px absolute pixel)
    local divider = container:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(1)
    divider:SetPoint("TOP", container, "TOP", 0, 0)
    divider:SetPoint("BOTTOM", container, "BOTTOM", 0, 0)
    divider:SetColorTexture(1, 1, 1, 0.15)
    if divider.SetSnapToPixelGrid then
        divider:SetSnapToPixelGrid(false)
        divider:SetTexelSnappingBias(0)
    end

    ---------------------------------------------------------------------------
    --  BuildMacroGroup: creates a titled grid of macro icons
    ---------------------------------------------------------------------------
    local function BuildMacroGroup(defs, anchorSide, titleText)
        local isLeft = (anchorSide == "LEFT")
        local centerX = isLeft and (halfW / 2) or (halfW + halfW / 2)

        local titleFS = container:CreateFontString(nil, "OVERLAY")
        titleFS:SetFont(fontPath, 16, "")
        titleFS:SetTextColor(1, 1, 1, 1)
        titleFS:SetPoint("TOP", container, "TOPLEFT", centerX, 0)
        titleFS:SetText(titleText)

        local numIcons = #defs

        for gi, def in ipairs(defs) do
            local rowIdx = math.floor((gi - 1) / ICONS_PER_ROW)
            local colIdx = (gi - 1) % ICONS_PER_ROW
            local iconsInRow = math.min(ICONS_PER_ROW, numIcons - rowIdx * ICONS_PER_ROW)
            local rowW = iconsInRow * ICON_SIZE + (iconsInRow - 1) * ICON_GAP
            local iconX = centerX - rowW / 2 + ICON_SIZE / 2 + colIdx * (ICON_SIZE + ICON_GAP)
            local iconY = FIRST_ICON_Y - rowIdx * ROW_STRIDE

            local btn = CreateFrame("Button", nil, container)
            PP.Size(btn, ICON_SIZE, ICON_SIZE)
            btn:SetPoint("TOP", container, "TOPLEFT", iconX, iconY)
            btn:SetFrameLevel(container:GetFrameLevel() + 5)

            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints(); tex:SetTexture(def.icon); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._tex = tex

            local bdr = CreateFrame("Frame", nil, btn)
            bdr:SetAllPoints(); bdr:SetFrameLevel(btn:GetFrameLevel() + 1)
            PP.CreateBorder(bdr, 0, 0, 0, 1, 1)

            local hoverBdr = CreateFrame("Frame", nil, btn)
            hoverBdr:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
            hoverBdr:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
            hoverBdr:SetFrameLevel(btn:GetFrameLevel() + 2)
            local ar, ag, ab = EllesmereUI.GetAccentColor()
            PP.CreateBorder(hoverBdr, ar, ag, ab, 1, 2)
            hoverBdr:Hide()
            btn._hoverBdr = hoverBdr

            local labelFS = container:CreateFontString(nil, "OVERLAY")
            labelFS:SetFont(fontPath, 11, ""); labelFS:SetTextColor(1, 1, 1, 0.9)
            labelFS:SetPoint("TOP", btn, "BOTTOM", 0, -4); labelFS:SetText(def.label)
            btn._label = labelFS

            -- Flash system (OnUpdate, no AnimationGroup)
            local flashFS = container:CreateFontString(nil, "OVERLAY")
            flashFS:SetFont(fontPath, 9, ""); flashFS:SetTextColor(1, 1, 1, 0)
            flashFS:SetPoint("TOP", btn, "BOTTOM", 0, -4); flashFS:Hide()
            local flashTex = btn:CreateTexture(nil, "OVERLAY")
            flashTex:SetAllPoints(); flashTex:SetColorTexture(1, 1, 1, 0)
            local flashDriver = CreateFrame("Frame", nil, container); flashDriver:Hide()
            local flashElapsed = 0
            flashDriver:SetScript("OnUpdate", function(self, dt)
                flashElapsed = flashElapsed + dt
                if flashElapsed < 0.08 then flashTex:SetColorTexture(1, 1, 1, 0.7 * (flashElapsed / 0.08))
                elseif flashElapsed < 0.38 then flashTex:SetColorTexture(1, 1, 1, 0.7 * (1 - (flashElapsed - 0.08) / 0.3))
                else flashTex:SetColorTexture(1, 1, 1, 0) end
                if flashElapsed < 0.15 then flashFS:SetTextColor(1, 1, 1, flashElapsed / 0.15)
                elseif flashElapsed < 0.95 then flashFS:SetTextColor(1, 1, 1, 1)
                elseif flashElapsed < 1.55 then flashFS:SetTextColor(1, 1, 1, 1 - (flashElapsed - 0.95) / 0.6)
                else flashFS:Hide(); flashTex:SetColorTexture(1, 1, 1, 0); btn._label:Show(); self:Hide() end
            end)
            local function PlayFlash()
                flashElapsed = 0; flashFS:SetText("Macro Created"); flashFS:SetTextColor(1, 1, 1, 0)
                flashFS:Show(); btn._label:Hide(); flashDriver:Show()
            end
            btn._playFlash = PlayFlash

            -- State
            local function MacroExists() return GetMacroIndexByName(def.name) ~= 0 end
            local function RefreshState()
                local exists = MacroExists()
                tex:SetDesaturated(exists)
                btn._isGray = exists
            end

            -- DB helper
            local function GetDB()
                if not EllesmereUIDB then EllesmereUIDB = {} end
                if not EllesmereUIDB.macroFactory then EllesmereUIDB.macroFactory = {} end
                if not EllesmereUIDB.macroFactory[def.name] then EllesmereUIDB.macroFactory[def.name] = {} end
                return EllesmereUIDB.macroFactory[def.name]
            end

            -- Dynamic icon: show the first selected item or equipped trinket
            local function RefreshIcon()
                local db = GetDB()
                local icon
                if def.checkboxes then
                    local cbs = def.checkboxes
                    local order = db.order
                    if not order or #order < #cbs then
                        order = {}
                        for i = 1, #cbs do order[i] = i end
                    end
                    for _, idx in ipairs(order) do
                        local cb = cbs[idx]
                        if cb and db[cb.key] ~= false and cb.items and cb.items[1] then
                            icon = C_Item.GetItemIconByID(cb.items[1])
                            if icon then break end
                        end
                    end
                elseif def.fixedTooltip then
                    local slot = tonumber(def.fixedTooltip)
                    if slot then
                        icon = GetInventoryItemTexture("player", slot)
                    end
                end
                tex:SetTexture(icon or def.icon)
            end
            btn._refreshIcon = RefreshIcon
            RefreshIcon()

            -------------------------------------------------------------------
            --  Right-click dropdown menu (lazy-built)
            -------------------------------------------------------------------
            local menuFrame
            local function BuildMenu()
                if menuFrame then return end
                local MH, DH, HH, MW = 28, 14, 20, 240
                local cbItems = def.checkboxes
                local hasCheckboxes = cbItems and #cbItems > 0

                local menuH = 4 + MH + MH + 4
                if hasCheckboxes then
                    menuH = menuH + DH + HH + (#cbItems * MH)
                end

                menuFrame = CreateFrame("Frame", nil, UIParent)
                menuFrame:SetFrameStrata("FULLSCREEN_DIALOG"); menuFrame:SetFrameLevel(200)
                menuFrame:SetClampedToScreen(true); menuFrame:EnableMouse(true)
                menuFrame:SetSize(MW, menuH)
                menuFrame:Hide()
                local mBg = menuFrame:CreateTexture(nil, "BACKGROUND"); mBg:SetAllPoints()
                mBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA or 0.92)
                EllesmereUI.MakeBorder(menuFrame, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
                local mY = -4

                -- Create/Delete action row
                local aR = CreateFrame("Button", nil, menuFrame)
                aR:SetHeight(MH); aR:SetFrameLevel(menuFrame:GetFrameLevel() + 2)
                aR:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                aR:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                local aL = aR:CreateFontString(nil, "OVERLAY")
                aL:SetFont(fontPath, 13, ""); aL:SetTextColor(0.75, 0.75, 0.75, 1)
                aL:SetPoint("LEFT", aR, "LEFT", 12, 0)
                local aHL = aR:CreateTexture(nil, "ARTWORK"); aHL:SetAllPoints(); aHL:SetColorTexture(1, 1, 1, 0)
                local function RefAct()
                    if MacroExists() then aL:SetText("|cffff4444Delete Macro|r") else aL:SetText("Create Macro") end
                end
                RefAct(); menuFrame._refreshAction = RefAct
                aR:SetScript("OnEnter", function() aL:SetTextColor(1, 1, 1, 1); aHL:SetColorTexture(1, 1, 1, 0.04) end)
                aR:SetScript("OnLeave", function() RefAct(); aHL:SetColorTexture(1, 1, 1, 0) end)
                aR:SetScript("OnClick", function()
                    if InCombatLockdown() then return end
                    if MacroExists() then
                        DeleteMacro(def.name)
                    else
                        local db = GetDB()
                        CreateMacro(def.name, "INV_MISC_QUESTIONMARK", BuildMacroBody(def, db), nil)
                        lastAvailableItems[def.name] = GetFirstAvailableItemID(def, db)
                        PlayFlash()
                    end
                    C_Timer.After(0.1, function() RefreshState(); RefAct() end)
                end)
                mY = mY - MH

                -- Show Tooltip checkbox
                local tR = CreateFrame("Button", nil, menuFrame)
                tR:SetHeight(MH); tR:SetFrameLevel(menuFrame:GetFrameLevel() + 2)
                tR:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                tR:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                local tB = CreateFrame("Frame", nil, tR); tB:SetSize(16, 16); tB:SetPoint("RIGHT", tR, "RIGHT", -10, 0)
                local tBg = tB:CreateTexture(nil, "BACKGROUND"); tBg:SetAllPoints(); tBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                local tBrd = EllesmereUI.MakeBorder(tB, 0.4, 0.4, 0.4, 0.6, PP)
                local tCk = tB:CreateTexture(nil, "ARTWORK"); PP.SetInside(tCk, tB, 2, 2)
                tCk:SetColorTexture(EG.r, EG.g, EG.b, 1); tCk:SetSnapToPixelGrid(false)
                local tL = tR:CreateFontString(nil, "OVERLAY"); tL:SetFont(fontPath, 13, "")
                tL:SetTextColor(0.75, 0.75, 0.75, 1); tL:SetPoint("LEFT", tR, "LEFT", 12, 0); tL:SetText("Show Tooltip")
                local tHL = tR:CreateTexture(nil, "ARTWORK"); tHL:SetAllPoints(); tHL:SetColorTexture(1, 1, 1, 0)
                local function RefTT()
                    local db = GetDB()
                    if db.showTooltip ~= false then tCk:Show(); tBrd:SetColor(EG.r, EG.g, EG.b, 0.8)
                    else tCk:Hide(); tBrd:SetColor(0.4, 0.4, 0.4, 0.6) end
                end
                RefTT()
                tR:SetScript("OnEnter", function() tL:SetTextColor(1, 1, 1, 1); tHL:SetColorTexture(1, 1, 1, 0.04) end)
                tR:SetScript("OnLeave", function() tL:SetTextColor(0.75, 0.75, 0.75, 1); tHL:SetColorTexture(1, 1, 1, 0) end)
                tR:SetScript("OnClick", function()
                    local db = GetDB()
                    if db.showTooltip ~= false then db.showTooltip = false
                    else db.showTooltip = true end
                    RefTT()
                    UpdateMacro(def, db)
                end)
                mY = mY - MH

                -- Item checkboxes (only for item-based macros)
                if hasCheckboxes then
                    -- Divider
                    local dv = CreateFrame("Frame", nil, menuFrame); dv:SetHeight(DH)
                    dv:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                    dv:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                    local dl = dv:CreateTexture(nil, "ARTWORK"); dl:SetHeight(1)
                    dl:SetPoint("LEFT", dv, "LEFT", 10, 0); dl:SetPoint("RIGHT", dv, "RIGHT", -10, 0)
                    dl:SetColorTexture(1, 1, 1, 0.08)
                    mY = mY - DH

                    -- Hint text
                    local ht = CreateFrame("Frame", nil, menuFrame); ht:SetHeight(HH)
                    ht:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                    ht:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                    local hfs = ht:CreateFontString(nil, "OVERLAY"); hfs:SetFont(fontPath, 10, "")
                    hfs:SetTextColor(1, 1, 1, 0.25); hfs:SetPoint("CENTER"); hfs:SetText("Drag to Reorder")
                    mY = mY - HH

                    -- Checkbox rows with drag reorder
                    local cbBaseY = mY
                    local rowFrames = {}
                    local isDragging = false
                    local insLine = menuFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                    insLine:SetHeight(2); insLine:SetColorTexture(EG.r, EG.g, EG.b, 0.9); insLine:Hide()

                    for ci, cb in ipairs(cbItems) do
                        local row = CreateFrame("Button", nil, menuFrame)
                        row:SetHeight(MH); row._baseY = mY; row._cbIndex = ci; row._cb = cb
                        row:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                        row:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                        row:SetFrameLevel(menuFrame:GetFrameLevel() + 2)

                        local rl = row:CreateFontString(nil, "OVERLAY"); rl:SetFont(fontPath, 13, "")
                        rl:SetTextColor(0.75, 0.75, 0.75, 1); rl:SetPoint("LEFT", row, "LEFT", 12, 0); rl:SetText(cb.label)
                        local rb = CreateFrame("Frame", nil, row); rb:SetSize(16, 16); rb:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                        local rBg = rb:CreateTexture(nil, "BACKGROUND"); rBg:SetAllPoints(); rBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                        local rBrd = EllesmereUI.MakeBorder(rb, 0.4, 0.4, 0.4, 0.6, PP)
                        local rCk = rb:CreateTexture(nil, "ARTWORK"); PP.SetInside(rCk, rb, 2, 2)
                        rCk:SetColorTexture(EG.r, EG.g, EG.b, 1); rCk:SetSnapToPixelGrid(false)
                        local rHL = row:CreateTexture(nil, "ARTWORK"); rHL:SetAllPoints(); rHL:SetColorTexture(1, 1, 1, 0)

                        local function UC()
                            local db = GetDB()
                            local key = row._cb.key
                            if db[key] ~= false then rCk:Show(); rBrd:SetColor(EG.r, EG.g, EG.b, 0.8)
                            else rCk:Hide(); rBrd:SetColor(0.4, 0.4, 0.4, 0.6) end
                        end
                        UC(); row._updateCheck = UC; row._lbl = rl

                        row:SetScript("OnEnter", function()
                            if isDragging then return end
                            rl:SetTextColor(1, 1, 1, 1); rHL:SetColorTexture(1, 1, 1, 0.04)
                        end)
                        row:SetScript("OnLeave", function()
                            if isDragging then return end
                            rl:SetTextColor(0.75, 0.75, 0.75, 1); rHL:SetColorTexture(1, 1, 1, 0)
                        end)
                        row:SetScript("OnClick", function()
                            if isDragging then return end
                            local db = GetDB()
                            local key = row._cb.key
                            if db[key] ~= false then db[key] = false
                            else db[key] = true end
                            UC()
                            UpdateMacro(def, db)
                            RefreshIcon()
                        end)

                        -- Drag (3px threshold via OnMouseDown/Up/Update)
                        local dsY, dgO
                        row:SetScript("OnMouseDown", function(_, b)
                            if b ~= "LeftButton" then return end
                            local _, cy = GetCursorPosition(); dsY = cy
                        end)
                        row:SetScript("OnMouseUp", function(self, b)
                            if b ~= "LeftButton" then return end
                            dsY = nil
                            if not isDragging then return end
                            isDragging = false; insLine:Hide()
                            self:SetFrameLevel(menuFrame:GetFrameLevel() + 2); self:SetAlpha(1)
                            local _, cy = GetCursorPosition()
                            local sc = menuFrame:GetEffectiveScale(); cy = cy / sc
                            local from = self._cbIndex; local to = from
                            for ri, rf in ipairs(rowFrames) do
                                if rf._baseY then
                                    local rm = (menuFrame:GetTop() or 0) + rf._baseY - MH / 2
                                    if cy > rm then to = ri; break end
                                    to = ri
                                end
                            end
                            to = math.max(1, math.min(to, #cbItems))
                            if from ~= to then
                                local db = GetDB()
                                if not db.order then db.order = {}; for oi = 1, #cbItems do db.order[oi] = oi end end
                                local mv = table.remove(db.order, from); table.insert(db.order, to, mv)
                            end
                            local db = GetDB()
                            if not db.order then db.order = {}; for oi = 1, #cbItems do db.order[oi] = oi end end
                            for ri = 1, #rowFrames do
                                local rf = rowFrames[ri]; local oi = db.order[ri]; local it = cbItems[oi]
                                rf._cbIndex = ri; rf._cb = it; rf._lbl:SetText(it.label)
                                local ry = cbBaseY - (ri - 1) * MH; rf._baseY = ry; rf:ClearAllPoints()
                                rf:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, ry)
                                rf:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, ry)
                                rf._updateCheck()
                            end
                            UpdateMacro(def, db)
                            RefreshIcon()
                        end)
                        row:SetScript("OnUpdate", function(self)
                            if not dsY then return end
                            local _, cy = GetCursorPosition()
                            if not isDragging then
                                if math.abs(cy - dsY) < 3 then return end
                                isDragging = true
                                local sc = menuFrame:GetEffectiveScale()
                                dgO = (cy / sc) - (self:GetTop() or 0)
                                self:SetFrameLevel(menuFrame:GetFrameLevel() + 10); self:SetAlpha(0.8)
                                for _, rf in ipairs(rowFrames) do
                                    if rf._lbl then rf._lbl:SetTextColor(0.75, 0.75, 0.75, 1) end
                                end
                            end
                            local sc = menuFrame:GetEffectiveScale()
                            local cY = cy / sc; local mT = menuFrame:GetTop() or 0
                            local lY = cY - (dgO or 0) - mT
                            lY = math.max(cbBaseY - (#cbItems - 1) * MH, math.min(lY, cbBaseY))
                            self:ClearAllPoints()
                            self:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, lY)
                            self:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, lY)
                            local iI = #cbItems
                            for ri, rf in ipairs(rowFrames) do
                                if rf ~= self and rf._baseY then
                                    local rm = mT + rf._baseY - MH / 2
                                    if cY > rm then iI = ri; break end
                                    iI = ri + 1
                                end
                            end
                            iI = math.max(1, math.min(iI, #cbItems + 1))
                            local lnY = (iI <= 1) and (cbBaseY + 1) or (cbBaseY - (iI - 1) * MH + 1)
                            insLine:ClearAllPoints()
                            insLine:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, lnY)
                            insLine:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -8, lnY)
                            insLine:Show()
                        end)

                        rowFrames[ci] = row; mY = mY - MH
                    end
                end  -- hasCheckboxes

                -- Close on click outside
                menuFrame:SetScript("OnUpdate", function(self)
                    if not self:IsMouseOver() and not btn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                        self:Hide()
                    end
                end)
            end -- BuildMenu

            btn._showMenu = function()
                BuildMenu()
                for _, pf in pairs(allCogPopups) do if pf and pf:IsShown() then pf:Hide() end end
                if menuFrame:IsShown() then menuFrame:Hide(); return end
                local bs = btn:GetEffectiveScale(); local us = UIParent:GetEffectiveScale()
                menuFrame:SetScale(bs / us); menuFrame:ClearAllPoints()
                menuFrame:SetPoint("TOP", btn, "BOTTOM", 0, -18)
                if menuFrame._refreshAction then menuFrame._refreshAction() end
                menuFrame:Show(); allCogPopups[gi] = menuFrame
            end

            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnEnter", function(self)
                self._hoverBdr:Show()
                if self._isGray then
                    EllesmereUI.ShowWidgetTooltip(self, def.label .. " macro created. Right-click to configure.")
                else
                    EllesmereUI.ShowWidgetTooltip(self, "Click to create " .. def.label .. " macro\nRight-click to configure")
                end
            end)
            btn:SetScript("OnLeave", function(self) self._hoverBdr:Hide(); EllesmereUI.HideWidgetTooltip() end)
            btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then self._showMenu(); return end
                if self._isGray then return end
                if InCombatLockdown() then return end
                local db = GetDB()
                CreateMacro(def.name, "INV_MISC_QUESTIONMARK", BuildMacroBody(def, db), nil)
                lastAvailableItems[def.name] = GetFirstAvailableItemID(def, db)
                self._playFlash()
                C_Timer.After(0.1, RefreshState)
            end)

            RefreshState()
            allMacroButtons[gi] = btn
        end -- for gi
    end -- BuildMacroGroup

    -- Build general macros on left side
    BuildMacroGroup(GENERAL_DEFS, "LEFT", "General Macros")

    -- "Coming Soon" text on right side
    local comingSoonFS = container:CreateFontString(nil, "OVERLAY")
    comingSoonFS:SetFont(fontPath, 14, "")
    comingSoonFS:SetTextColor(1, 1, 1, 0.3)
    comingSoonFS:SetPoint("CENTER", container, "TOPLEFT", halfW + halfW / 2, -SECTION_H / 2)
    comingSoonFS:SetText("EllesmereUI Spec Macros are coming soon!")
    comingSoonFS:SetJustifyH("CENTER")

    -- Update macros when inventory changes
    local function UpdateInventoryDependentMacros()
        for mi, btn in pairs(allMacroButtons) do
            if btn and btn._tex then
                local mdef = GENERAL_DEFS[mi]
                if mdef and mdef.checkboxes then
                    local ex = GetMacroIndexByName(mdef.name) ~= 0
                    if ex then
                        local db = GetMacroDBByName(mdef.name)
                        local newAvailableItemID = GetFirstAvailableItemID(mdef, db)
                        local oldAvailableItemID = lastAvailableItems[mdef.name]
                        if newAvailableItemID ~= oldAvailableItemID then
                            lastAvailableItems[mdef.name] = newAvailableItemID
                            -- Defer macro update to avoid protected function error
                            C_Timer.After(0, function() UpdateMacro(mdef, db) end)
                        end
                    end
                end
            end
        end
    end

    -- Poll for macro state changes (2s interval)
    local pollFrame = CreateFrame("Frame", nil, container)
    local elapsed = 0
    pollFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 2 then return end
        elapsed = 0
        for mi, btn in pairs(allMacroButtons) do
            if btn and btn._tex then
                local mdef = GENERAL_DEFS[mi]
                if mdef then
                    local ex = GetMacroIndexByName(mdef.name) ~= 0
                    if btn._isGray and not ex then btn._tex:SetDesaturated(false); btn._isGray = false
                    elseif not btn._isGray and ex then btn._tex:SetDesaturated(true); btn._isGray = true end
                    if btn._refreshIcon then btn._refreshIcon() end
                    local pf = allCogPopups[mi]
                    if pf and pf:IsShown() and pf._refreshAction then pf._refreshAction() end
                end
            end
        end
    end)

    -- Update macros immediately when bag changes
    local bagUpdateFrame = CreateFrame("Frame", nil, container)
    bagUpdateFrame:RegisterEvent("BAG_UPDATE")
    bagUpdateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    bagUpdateFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            ProcessPendingMacroUpdates()
        else
            UpdateInventoryDependentMacros()
        end
    end)

    return SECTION_H
end
