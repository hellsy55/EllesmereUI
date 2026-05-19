-------------------------------------------------------------------------------
--  EllesmereUIChat_SessionHistory.lua
--
--  Persists recent chat per docked tab (SavedVariablesPerCharacter) across
--  /reload and relog. Snapshots historyBuffer on logout/reload only (no
--  AddMessage hooks). Restores via BackFillMessage. Skips capture and restore
--  in protected instances and when addon chat restrictions are forced. Each tab
--  only stores what Blizzard delivered to that frame. Combat log and temp
--  windows excluded.
-------------------------------------------------------------------------------
local _, ns = ...
local ECHAT = ns.ECHAT
if not ECHAT then return end

local strsub = string.sub
local wipe = wipe
local GetTime = GetTime
local GetServerTime = GetServerTime
local pairs = pairs
local ipairs = ipairs
local type = type
local pcall = pcall

local SV_NAME = "EllesmereUIChatScrollDB"
local SV_VERSION = 2
local MAX_TEXT_LEN = 4096
local RESTORE_DELAY_SEC = 2.0
local DIVIDER_PLAIN = "--- Previous session ---"

local lifecycleHooksInstalled = false
local restoreToken = 0
local restoredFrames = {} -- [frameName] = true this reload

local eventFrame = CreateFrame("Frame")
local deferFrame = CreateFrame("Frame")
local UnarmDeferredRestore

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function InProtectedInstance()
    return EllesmereUI.InProtectedInstance and EllesmereUI.InProtectedInstance()
end

local function PersistEnabled()
    if not ECHAT.DB then return true end
    local db = ECHAT.DB()
    if not db then return true end
    return db.persistChatHistory ~= false
end

local function SessionHistorySafe()
    if not PersistEnabled() then return false end
    if InProtectedInstance() then return false end
    if GetCVarBool and GetCVarBool("addonChatRestrictionsForced") then return false end
    return true
end

local function MaxLines()
    local maxN = 100
    if ECHAT.DB then
        local db = ECHAT.DB()
        if db and db.persistChatHistoryMaxLines then
            maxN = db.persistChatHistoryMaxLines
        end
    end
    if maxN < 10 then maxN = 10 end
    if maxN > 500 then maxN = 500 end
    return maxN
end

local function IsCombatLogChatFrame(cf)
    if not cf then return false end
    local combat = _G.COMBATLOG
    if combat and cf == combat then
        return true
    end
    local fn = _G.IsCombatLog
    if type(fn) == "function" then
        local ok, r = pcall(fn, cf)
        if ok and r then
            return true
        end
    end
    return false
end

function ECHAT.ShouldTrackChatFrameForHistory(cf)
    if not cf or not cf.GetName then return false end
    if cf.isTemporary then return false end
    local name = cf:GetName()
    if not name or not name:match("^ChatFrame%d+$") then return false end
    return not IsCombatLogChatFrame(cf)
end

local ShouldTrackFrame = ECHAT.ShouldTrackChatFrameForHistory

local function GetSV()
    local sv = _G[SV_NAME]
    if type(sv) ~= "table" then
        sv = { v = SV_VERSION, byFrame = {} }
        _G[SV_NAME] = sv
    end
    if type(sv.byFrame) ~= "table" then
        sv.byFrame = {}
    end
    sv.v = SV_VERSION
    return sv
end

local function IsValidMessage(msg)
    if type(msg) ~= "string" or msg == "" then return false end
    if issecretvalue and issecretvalue(msg) then return false end
    return true
end

local function IsDividerMessage(msg)
    if not msg then return true end
    return msg:find(DIVIDER_PLAIN, 1, true) ~= nil
end

local function ShouldPersistLine(msg)
    return IsValidMessage(msg) and not IsDividerMessage(msg)
end

local TrimLinesToMax

local function PurgeCombatLogFromSV()
    local sv = GetSV()
    local bf = sv.byFrame
    if not bf then return end
    for frameName in pairs(bf) do
        local fr = _G[frameName]
        if fr and IsCombatLogChatFrame(fr) then
            bf[frameName] = nil
        end
    end
end

TrimLinesToMax = function(lines, maxN)
    local n = #lines
    if n <= maxN then return lines end
    local out = {}
    local start = n - maxN + 1
    for i = start, n do
        out[#out + 1] = lines[i]
    end
    return out
end

local function SanitizeLineList(lines)
    if type(lines) ~= "table" then return nil end
    local out = {}
    for _, L in ipairs(lines) do
        if type(L) == "table" then
            local msg = L.message or L.t
            if ShouldPersistLine(msg) then
                local entry = {
                    message = (#msg > MAX_TEXT_LEN) and strsub(msg, 1, MAX_TEXT_LEN) or msg,
                    r = (type(L.r) == "number" and L.r) or 1,
                    g = (type(L.g) == "number" and L.g) or 1,
                    b = (type(L.b) == "number" and L.b) or 1,
                    id = (type(L.id) == "number" and L.id) or 1,
                    timestamp = (type(L.timestamp) == "number" and L.timestamp) or GetTime(),
                    serverTime = (type(L.serverTime) == "number" and L.serverTime) or GetServerTime(),
                }
                out[#out + 1] = entry
            end
        end
    end
    return TrimLinesToMax(out, MaxLines())
end

local function SanitizeSV()
    local sv = GetSV()
    if not sv.byFrame then return end
    for frameName, lines in pairs(sv.byFrame) do
        local cleaned = SanitizeLineList(lines)
        if cleaned and #cleaned > 0 then
            sv.byFrame[frameName] = cleaned
        else
            sv.byFrame[frameName] = nil
        end
    end
end

local function NormalizeStoredLine(L)
    if type(L) ~= "table" then return nil end
    local msg = L.message or L.t
    if not ShouldPersistLine(msg) then return nil end
    if #msg > MAX_TEXT_LEN then
        msg = strsub(msg, 1, MAX_TEXT_LEN)
    end
    return {
        message = msg,
        r = (type(L.r) == "number" and L.r) or 1,
        g = (type(L.g) == "number" and L.g) or 1,
        b = (type(L.b) == "number" and L.b) or 1,
        id = (type(L.id) == "number" and L.id) or 1,
        timestamp = (type(L.timestamp) == "number" and L.timestamp) or GetTime(),
        serverTime = (type(L.serverTime) == "number" and L.serverTime) or GetServerTime(),
    }
end

local function CopyBufferEntryForStorage(entry)
    if type(entry) ~= "table" then return nil end
    local msg = entry.message
    if not ShouldPersistLine(msg) then return nil end
    if #msg > MAX_TEXT_LEN then
        msg = strsub(msg, 1, MAX_TEXT_LEN)
    end
    return {
        message = msg,
        r = (type(entry.r) == "number" and entry.r) or 1,
        g = (type(entry.g) == "number" and entry.g) or 1,
        b = (type(entry.b) == "number" and entry.b) or 1,
        id = (type(entry.id) == "number" and entry.id) or 1,
        timestamp = (type(entry.timestamp) == "number" and entry.timestamp) or GetTime(),
        serverTime = (type(entry.serverTime) == "number" and entry.serverTime) or GetServerTime(),
    }
end

local function GetBufferEntryAt(buf, index)
    if not buf or not index or index < 1 then return nil end
    if buf.GetEntryAtIndex then
        local ok, entry = pcall(buf.GetEntryAtIndex, buf, index)
        if ok then return entry end
    end
    if type(buf.elements) ~= "table" or #buf.elements == 0 then return nil end
    local headIndex = type(buf.headIndex) == "table" and buf.headIndex.value or buf.headIndex
    local maxElements = type(buf.maxElements) == "table" and buf.maxElements.value or buf.maxElements
    if not headIndex or not maxElements then return nil end
    if index > #buf.elements then return nil end
    local globalIndex = headIndex - index + 1
    local elementIndex = (globalIndex - 1) % maxElements + 1
    return buf.elements[elementIndex]
end

local function GetBufferEntryCount(buf)
    if not buf or type(buf.elements) ~= "table" then return 0 end
    return #buf.elements
end

local function WriteFrameLinesToSV(frameName, lines)
    if not frameName or not lines or #lines == 0 then return end
    local cleaned = SanitizeLineList(lines)
    if not cleaned or #cleaned == 0 then return end
    GetSV().byFrame[frameName] = cleaned
end

-------------------------------------------------------------------------------
--  Snapshot (buffer -> SV)
-------------------------------------------------------------------------------
local function SnapshotFrame(cf)
    if not ShouldTrackFrame(cf) then return nil end
    local lines = {}
    local buf = cf.historyBuffer

    if buf and GetBufferEntryCount(buf) > 0 then
        local count = GetBufferEntryCount(buf)
        local newestFirst = {}
        for i = 1, count do
            local stored = CopyBufferEntryForStorage(GetBufferEntryAt(buf, i))
            if stored then
                newestFirst[#newestFirst + 1] = stored
            end
        end
        for i = #newestFirst, 1, -1 do
            lines[#lines + 1] = newestFirst[i]
        end
    elseif cf.GetNumMessages and cf.GetMessageInfo then
        local ok, n = pcall(cf.GetNumMessages, cf)
        if ok and type(n) == "number" and n > 0 then
            local srv = GetServerTime()
            local t0 = GetTime() - n * 0.05
            for i = 1, n do
                local mok, text = pcall(cf.GetMessageInfo, cf, i)
                if mok and ShouldPersistLine(text) then
                    if #text > MAX_TEXT_LEN then
                        text = strsub(text, 1, MAX_TEXT_LEN)
                    end
                    lines[#lines + 1] = {
                        message = text,
                        r = 1,
                        g = 1,
                        b = 1,
                        id = 1,
                        timestamp = t0 + i * 0.05,
                        serverTime = srv,
                    }
                end
            end
        end
    end

    return SanitizeLineList(lines)
end

local function ClearSavedSessionHistory()
    restoreToken = restoreToken + 1
    wipe(restoredFrames)
    UnarmDeferredRestore()
    local sv = GetSV()
    wipe(sv.byFrame)
end

function ECHAT.SnapshotChatSessionHistory()
    if not SessionHistorySafe() then return end
    local sv = GetSV()
    PurgeCombatLogFromSV()

    for i = 1, 50 do
        local cf = _G["ChatFrame" .. i]
        if cf and ShouldTrackFrame(cf) then
            local name = cf:GetName()
            if name then
                local lines = SnapshotFrame(cf)
                if lines and #lines > 0 then
                    WriteFrameLinesToSV(name, lines)
                end
            end
        end
    end

    for frameName in pairs(sv.byFrame) do
        local cf = _G[frameName]
        if not cf or not ShouldTrackFrame(cf) then
            sv.byFrame[frameName] = nil
        end
    end
end

-------------------------------------------------------------------------------
--  Restore (SV -> historyBuffer)
-------------------------------------------------------------------------------
UnarmDeferredRestore = function()
    deferFrame:UnregisterAllEvents()
    deferFrame:SetScript("OnEvent", nil)
end

local function RefreshFrameDisplay(cf)
    if cf.ResetAllFadeTimes then
        pcall(cf.ResetAllFadeTimes, cf)
    end
    if cf.UpdateDisplay then
        pcall(cf.UpdateDisplay, cf)
    end
    if cf.ScrollToBottom then
        pcall(cf.ScrollToBottom, cf)
    end
end

local function SortLinesChronological(lines)
    table.sort(lines, function(a, b)
        local ta = a.serverTime or a.timestamp or 0
        local tb = b.serverTime or b.timestamp or 0
        if ta ~= tb then
            return ta < tb
        end
        return (a.timestamp or 0) < (b.timestamp or 0)
    end)
    return lines
end

local function RestoreFrame(cf, frameName, rawLines)
    if not cf or not rawLines or #rawLines == 0 then return false end
    if not ShouldTrackFrame(cf) then return false end
    if restoredFrames[frameName] then return false end

    local lines = SanitizeLineList(rawLines)
    if not lines or #lines == 0 then return false end
    lines = SortLinesChronological(lines)

    restoredFrames[frameName] = true

    -- BackFillMessage prepends each line; fill newest-first so oldest ends up at the top
    -- of the window and newest sits just above the current session (normal chat order).
    if cf.BackFillMessage then
        for i = #lines, 1, -1 do
            local entry = NormalizeStoredLine(lines[i])
            if entry and entry.message then
                pcall(cf.BackFillMessage, cf, entry.message, entry.r, entry.g, entry.b)
            end
        end
    else
        local buf = cf.historyBuffer
        if not buf or type(buf.PushBack) ~= "function" then
            restoredFrames[frameName] = nil
            return false
        end
        for i = #lines, 1, -1 do
            local entry = NormalizeStoredLine(lines[i])
            if entry then
                pcall(buf.PushBack, buf, entry)
            end
        end
    end

    RefreshFrameDisplay(cf)
    C_Timer.After(0, function()
        if cf and cf.ScrollToBottom then
            pcall(cf.ScrollToBottom, cf)
        end
    end)
    return true
end

local function RunRestore(token)
    if token ~= restoreToken then return end
    if not SessionHistorySafe() then return end

    local sv = GetSV()
    if not sv.byFrame then return end

    for frameName, rawLines in pairs(sv.byFrame) do
        if type(rawLines) == "table" and #rawLines > 0 then
            local cf = _G[frameName]
            if cf then
                RestoreFrame(cf, frameName, rawLines)
            end
        end
    end
end

local function ArmDeferredRestore(token)
    UnarmDeferredRestore()
    local function onDefer(_, event, ...)
        if token ~= restoreToken then
            UnarmDeferredRestore()
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            local _, isReloadingUi = ...
            if isReloadingUi then return end
        end
        if not SessionHistorySafe() then return end
        UnarmDeferredRestore()
        RunRestore(token)
    end
    deferFrame:SetScript("OnEvent", onDefer)
    deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    deferFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    if C_ChallengeMode then
        deferFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    end
end

local function TryRestore(token)
    if token ~= restoreToken then return end
    if not PersistEnabled() then return end
    if not SessionHistorySafe() then
        ArmDeferredRestore(token)
        return
    end
    RunRestore(token)
end

function ECHAT.RestoreChatSessionHistory()
    UnarmDeferredRestore()
    restoreToken = restoreToken + 1
    wipe(restoredFrames)
    local token = restoreToken
    if not PersistEnabled() then return end
    C_Timer.After(RESTORE_DELAY_SEC, function()
        TryRestore(token)
    end)
end

function ECHAT.OnSessionHistoryToggled(enabled)
    if enabled then
        ECHAT.InitChatSessionHistory()
        ECHAT.RestoreChatSessionHistory()
    else
        ClearSavedSessionHistory()
    end
end

-------------------------------------------------------------------------------
--  Frame lifecycle
-------------------------------------------------------------------------------
local function InstallLifecycleHooks()
    if lifecycleHooksInstalled then return end
    lifecycleHooksInstalled = true

    if FCF_Close then
        hooksecurefunc("FCF_Close", function(frame)
            if not frame or not frame.GetName then return end
            local name = frame:GetName()
            if frame.isTemporary then
                local sv = GetSV()
                if sv.byFrame then
                    sv.byFrame[name] = nil
                end
            end
        end)
    end
end

function ECHAT.InitChatSessionHistory()
    if not PersistEnabled() then
        ClearSavedSessionHistory()
        InstallLifecycleHooks()
        return
    end
    PurgeCombatLogFromSV()
    SanitizeSV()
    InstallLifecycleHooks()
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGOUT" then
        if PersistEnabled() then
            ECHAT.SnapshotChatSessionHistory()
        else
            ClearSavedSessionHistory()
        end
        return
    end

    if event == "PLAYER_LEAVING_WORLD" then
        if PersistEnabled() then
            ECHAT.SnapshotChatSessionHistory()
        else
            ClearSavedSessionHistory()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if not isInitialLogin and not isReloadingUi then
            if SessionHistorySafe() then
                ECHAT.RestoreChatSessionHistory()
            end
            return
        end
        ECHAT.InitChatSessionHistory()
        if PersistEnabled() then
            ECHAT.RestoreChatSessionHistory()
        end
    end
end)
