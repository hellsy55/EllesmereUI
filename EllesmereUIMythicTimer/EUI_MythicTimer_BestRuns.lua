-------------------------------------------------------------------------------
--  EUI_MythicTimer_BestRuns.lua  —  Best Runs viewer tab
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local floor = math.floor
local format = string.format
local abs = math.abs

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI then return end

    local db
    C_Timer.After(0, function() db = _G._EMT_AceDB end)

    local function DB()
        if not db then db = _G._EMT_AceDB end
        return db and db.profile
    end

    -- Font helpers (mirrors main file, reads fontPath from same DB)
    local FALLBACK_FONT = "Fonts/FRIZQT__.TTF"
    local function SFont()
        local p = DB()
        if p and p.fontPath then return p.fontPath end
        if EllesmereUI and EllesmereUI.GetFontPath then
            local path = EllesmereUI.GetFontPath("unitFrames")
            if path and path ~= "" then return path end
        end
        return FALLBACK_FONT
    end
    local function SOutline()
        if EllesmereUI.GetFontOutlineFlag then return EllesmereUI.GetFontOutlineFlag() end
        return ""
    end
    local function SetFS(fs, size, flags)
        if not fs then return end
        local p = SFont()
        flags = flags or SOutline()
        fs:SetFont(p, size, flags)
        if not fs:GetFont() then fs:SetFont(FALLBACK_FONT, size, flags) end
    end
    local function ApplyShadow(fs)
        if not fs then return end
        if EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow() then
            fs:SetShadowColor(0, 0, 0, 0.8); fs:SetShadowOffset(1, -1)
        else
            fs:SetShadowOffset(0, 0)
        end
    end

    local function FormatTime(seconds)
        if not seconds or seconds < 0 then seconds = 0 end
        local whole = floor(seconds)
        local m = floor(whole / 60)
        local s = floor(whole % 60)
        return format("%d:%02d", m, s)
    end

    -- State
    local selectedMapID = nil
    local selectedScopeKey = nil
    local deleteConfirmKey = nil

    -- Frame pools
    local dungeonBtns = {}
    local levelBtns = {}
    local detailLines = {}
    local deleteBtn = nil

    local function GetButton(pool, parent, idx)
        if pool[idx] then
            pool[idx]:SetParent(parent)
            return pool[idx]
        end
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn.text = btn:CreateFontString(nil, "OVERLAY")
        btn.text:SetPoint("CENTER")
        btn.text:SetWordWrap(false)
        pool[idx] = btn
        return btn
    end

    local function GetDetailLine(parent, idx)
        if detailLines[idx] then
            detailLines[idx]:SetParent(parent)
            return detailLines[idx]
        end
        local fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetWordWrap(false)
        detailLines[idx] = fs
        return fs
    end

    local function StyleButton(btn, size, selected)
        local bgR, bgG, bgB, bgA = 0.12, 0.12, 0.14, 0.9
        local borderR, borderG, borderB, borderA = 0.25, 0.25, 0.25, 0.6
        if selected then
            bgR, bgG, bgB = 0.08, 0.30, 0.18
            borderR, borderG, borderB = 0.05, 0.83, 0.62
        end
        btn:SetBackdropColor(bgR, bgG, bgB, bgA)
        btn:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
        SetFS(btn.text, size)
        ApplyShadow(btn.text)
        btn.text:SetTextColor(selected and 1 or 0.75, selected and 1 or 0.75, selected and 1 or 0.75)
        btn._selected = selected
        btn:SetScript("OnEnter", function(self)
            if not self._selected then
                self:SetBackdropColor(0.18, 0.18, 0.20, 0.9)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if not self._selected then
                self:SetBackdropColor(0.12, 0.12, 0.14, 0.9)
            end
        end)
    end

    -- Parse bestRuns into grouped structure
    local function GetDungeonData()
        local p = DB()
        if not p or not p.bestRuns then return {}, {} end

        local dungeons = {}
        local dungeonOrder = {}

        for scopeKey, runData in pairs(p.bestRuns) do
            local mapIDStr, levelStr = scopeKey:match("^(%d+):(%d+):")
            local mapID = tonumber(mapIDStr)
            local level = runData.level or tonumber(levelStr) or 0

            local mapName = runData.mapName
            if not mapName and mapID then
                mapName = C_ChallengeMode.GetMapUIInfo(mapID)
            end
            mapName = mapName or ("Dungeon " .. (mapID or "?"))

            if mapID then
                if not dungeons[mapID] then
                    dungeons[mapID] = { mapName = mapName, entries = {} }
                    dungeonOrder[#dungeonOrder + 1] = mapID
                end
                dungeons[mapID].entries[#dungeons[mapID].entries + 1] = {
                    scopeKey = scopeKey,
                    level = level,
                    data = runData,
                }
            end
        end

        table.sort(dungeonOrder, function(a, b)
            return (dungeons[a].mapName or "") < (dungeons[b].mapName or "")
        end)

        for _, dung in pairs(dungeons) do
            table.sort(dung.entries, function(a, b) return a.level > b.level end)
        end

        return dungeons, dungeonOrder
    end

    local function RebuildPage()
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
    end

    -- Build the Best Runs page
    _G._EMT_BuildBestRunsPage = function(parent, yOffset)
        local y = yOffset
        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = false

        local p = DB()
        if not p then
            parent:SetHeight(40)
            return
        end

        local dungeons, dungeonOrder = GetDungeonData()

        -- Hide all pooled frames
        for i = 1, #dungeonBtns do dungeonBtns[i]:Hide() end
        for i = 1, #levelBtns do levelBtns[i]:Hide() end
        for i = 1, #detailLines do detailLines[i]:Hide() end
        if deleteBtn then deleteBtn:Hide() end

        -- No data state
        if #dungeonOrder == 0 then
            local noData = GetDetailLine(parent, 1)
            SetFS(noData, 14)
            ApplyShadow(noData)
            noData:SetTextColor(0.5, 0.5, 0.5)
            noData:SetText("No best runs recorded yet. Complete a Mythic+ dungeon to see data here.")
            noData:ClearAllPoints()
            noData:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y - 20)
            noData:SetWidth(500)
            noData:SetWordWrap(true)
            noData:Show()
            parent:SetHeight(60)
            return
        end

        -- Auto-select first dungeon if none selected
        if not selectedMapID or not dungeons[selectedMapID] then
            selectedMapID = dungeonOrder[1]
            selectedScopeKey = nil
        end

        local selectedDungeon = dungeons[selectedMapID]

        -- Auto-select first level
        if selectedDungeon and (not selectedScopeKey or not p.bestRuns[selectedScopeKey]) then
            if selectedDungeon.entries[1] then
                selectedScopeKey = selectedDungeon.entries[1].scopeKey
            end
        end

        -- Layout constants
        local DUNGEON_W = 200
        local LEVEL_W = 70
        local PANEL_GAP = 12
        local BTN_H = 36
        local BTN_GAP = 5
        local DETAIL_LEFT = DUNGEON_W + LEVEL_W + PANEL_GAP * 3

        -- Dungeon buttons (left column)
        local dungY = y
        for i, mapID in ipairs(dungeonOrder) do
            local dung = dungeons[mapID]
            local btn = GetButton(dungeonBtns, parent, i)
            btn:SetSize(DUNGEON_W, BTN_H)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, dungY)

            local isSelected = (mapID == selectedMapID)
            StyleButton(btn, 14, isSelected)

            local displayName = dung.mapName or ("Map " .. mapID)
            if #displayName > 22 then
                displayName = displayName:sub(1, 21) .. "…"
            end
            btn.text:SetText(displayName)

            btn:SetScript("OnClick", function()
                selectedMapID = mapID
                selectedScopeKey = nil
                deleteConfirmKey = nil
                RebuildPage()
            end)
            btn:Show()
            dungY = dungY - BTN_H - BTN_GAP
        end

        -- Level buttons (middle column)
        local levelY = y
        if selectedDungeon then
            for i, entry in ipairs(selectedDungeon.entries) do
                local btn = GetButton(levelBtns, parent, i)
                btn:SetSize(LEVEL_W, BTN_H)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", parent, "TOPLEFT", DUNGEON_W + PANEL_GAP, levelY)

                local isSelected = (entry.scopeKey == selectedScopeKey)
                StyleButton(btn, 16, isSelected)
                btn.text:SetText("+" .. entry.level)

                btn:SetScript("OnClick", function()
                    selectedScopeKey = entry.scopeKey
                    deleteConfirmKey = nil
                    RebuildPage()
                end)
                btn:Show()
                levelY = levelY - BTN_H - BTN_GAP
            end
        end

        -- Detail panel (right area)
        local detailIdx = 0
        local detailY = y

        local function AddLine(text, r, g, b, size)
            detailIdx = detailIdx + 1
            local fs = GetDetailLine(parent, detailIdx)
            SetFS(fs, size or 14)
            ApplyShadow(fs)
            fs:SetTextColor(r or 0.9, g or 0.9, b or 0.9)
            fs:SetText(text)
            fs:SetWordWrap(false)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", parent, "TOPLEFT", DETAIL_LEFT, detailY)
            fs:SetWidth(500)
            fs:Show()
            detailY = detailY - (fs:GetStringHeight() or 18) - 7
        end

        local function AddSpacer(h)
            detailY = detailY - (h or 6)
        end

        if selectedScopeKey and p.bestRuns[selectedScopeKey] then
            local run = p.bestRuns[selectedScopeKey]
            local mapName = run.mapName or (selectedDungeon and selectedDungeon.mapName) or "Unknown"
            local level = run.level or 0

            -- Delete button (top-right of detail panel)
            if not deleteBtn then
                deleteBtn = CreateFrame("Button", nil, parent, "BackdropTemplate")
                deleteBtn:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                })
                deleteBtn.text = deleteBtn:CreateFontString(nil, "OVERLAY")
                deleteBtn.text:SetPoint("CENTER")
                deleteBtn.text:SetWordWrap(false)
            end
            deleteBtn:SetParent(parent)
            deleteBtn:SetSize(140, 34)
            deleteBtn:ClearAllPoints()
            deleteBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, y)

            local isConfirm = (deleteConfirmKey == selectedScopeKey)
            SetFS(deleteBtn.text, 13)
            ApplyShadow(deleteBtn.text)
            if isConfirm then
                deleteBtn:SetBackdropColor(0.5, 0.1, 0.1, 0.9)
                deleteBtn:SetBackdropBorderColor(0.9, 0.2, 0.2, 0.8)
                deleteBtn.text:SetTextColor(1, 0.4, 0.4)
                deleteBtn.text:SetText("Confirm Delete")
            else
                deleteBtn:SetBackdropColor(0.15, 0.12, 0.12, 0.9)
                deleteBtn:SetBackdropBorderColor(0.4, 0.2, 0.2, 0.6)
                deleteBtn.text:SetTextColor(0.9, 0.4, 0.4)
                deleteBtn.text:SetText("Delete Run")
            end

            local capturedKey = selectedScopeKey
            local capturedRun = run
            deleteBtn:SetScript("OnClick", function()
                if deleteConfirmKey == capturedKey then
                    -- Remove from bestRuns
                    if p.bestRuns then
                        p.bestRuns[capturedKey] = nil
                    end
                    -- Remove matching bestObjectiveSplits entries
                    if p.bestObjectiveSplits and capturedRun then
                        local mapID = capturedRun.mapID
                        local lv = capturedRun.level or 0
                        if mapID then
                            local affixKey = capturedKey:match("^%d+:%d+:(.+)$")
                            -- Exact scope: mapID:level:affixKey
                            if affixKey then
                                p.bestObjectiveSplits[format("%s:%d:%s", mapID, lv, affixKey)] = nil
                            end
                            -- Level scope: mapID:level
                            p.bestObjectiveSplits[format("%s:%d", mapID, lv)] = nil
                            -- Dungeon scope: mapID (only if no other runs for this dungeon)
                            local hasOtherRuns = false
                            for key in pairs(p.bestRuns) do
                                if key:match("^" .. tostring(mapID) .. ":") then
                                    hasOtherRuns = true
                                    break
                                end
                            end
                            if not hasOtherRuns then
                                p.bestObjectiveSplits[tostring(mapID)] = nil
                            end
                        end
                    end
                    deleteConfirmKey = nil
                    if capturedKey == selectedScopeKey then
                        selectedScopeKey = nil
                    end
                    RebuildPage()
                else
                    deleteConfirmKey = capturedKey
                    RebuildPage()
                end
            end)
            deleteBtn:SetScript("OnLeave", function()
                if deleteConfirmKey then
                    deleteConfirmKey = nil
                    RebuildPage()
                end
            end)
            deleteBtn:Show()

            -- Header
            AddLine(format("%s  +%d", mapName, level), 1, 1, 1, 18)
            AddSpacer(12)

            -- Total time
            AddLine(format("Time: %s", FormatTime(run.elapsed or 0)), 0.05, 0.83, 0.62, 18)
            AddSpacer(8)

            -- Objective splits
            if run.objectiveTimes then
                local maxIdx = 0
                for idx in pairs(run.objectiveTimes) do
                    if idx > maxIdx then maxIdx = idx end
                end
                for idx = 1, maxIdx do
                    local t = run.objectiveTimes[idx]
                    if t then
                        local name = (run.objectiveNames and run.objectiveNames[idx]) or ("Objective " .. idx)
                        AddLine(format("%s:  %s", name, FormatTime(t)), 0.75, 0.75, 0.75)
                    end
                end
            end

            -- Enemy forces
            if run.enemyForcesTime then
                AddLine(format("Enemy Forces:  %s", FormatTime(run.enemyForcesTime)), 0.75, 0.75, 0.75)
            end

            AddSpacer(6)

            -- Deaths
            if run.deaths and run.deaths > 0 then
                AddLine(format("Deaths: %d  (-%s)", run.deaths, FormatTime(run.deathTimeLost or 0)), 0.93, 0.33, 0.33)
            else
                AddLine("Deaths: 0", 0.5, 0.5, 0.5)
            end

            -- Affixes
            if run.affixes and #run.affixes > 0 then
                local names = {}
                for _, id in ipairs(run.affixes) do
                    local name = C_ChallengeMode.GetAffixInfo(id)
                    names[#names + 1] = name or ("Affix " .. id)
                end
                AddLine("Affixes: " .. table.concat(names, ", "), 0.55, 0.55, 0.55)
            end

            -- Date
            if run.date then
                AddLine(format("Date: %s", date("%d/%m/%y  %H:%M", run.date)), 0.55, 0.55, 0.55)
            else
                AddLine("Date: Unknown (pre-tracking)", 0.4, 0.4, 0.4)
            end
        end

        -- Calculate and set content height
        local dungH = abs(dungY - y)
        local levelH = abs(levelY - y)
        local detailH = abs(detailY - y)
        local maxH = dungH
        if levelH > maxH then maxH = levelH end
        if detailH > maxH then maxH = detailH end
        parent:SetHeight(maxH + 20)
    end
end)
