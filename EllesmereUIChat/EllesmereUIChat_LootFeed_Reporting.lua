local rootNS = select(2, ...)
rootNS.LootFeed = rootNS.LootFeed or {}
local ns = rootNS.LootFeed ---@class LootFeedNS

local db = ns.Settings.db
local LootFeedMessageGroup = ns.Messages.LootFeedMessageGroup
local MessagesCollection = ns.Messages.MessagesCollection
local ProcessChatMessage = ns.Messages.ProcessChatMessage
local EvaluateFilters = ns.Filters.EvaluateFilters
local TableContains = ns.Utils.TableContains

local AddMessageEventFilter = ChatFrame_AddMessageEventFilter or ChatFrameUtil.AddMessageEventFilter ---@type fun(event: WowEvent, callback: fun())
local RemoveMessageEventFilter = ChatFrame_RemoveMessageEventFilter or ChatFrameUtil.RemoveMessageEventFilter  ---@type fun(event: WowEvent, callback: fun())

local PendingSelfRolls = {}
local LootRollLinks = {}
local PENDING_SELF_ROLL_TTL = 90
local RollTypeToResultType = {
    [0] = "YouPass",
    [1] = "YouNeed",
    [2] = "YouGreed",
    [3] = "YouDisenchant",
    [4] = "YouTransmog",
}

local SyntheticSelfRollMessage = {
    group = LootFeedMessageGroup.LootRollYouDecide,
    events = { "CHAT_MSG_LOOT" },
    formats = {},
    defaultDebounce = 0,
}

local rollOnLootHooked = false
local confirmLootRollHooked = false
local syntheticSelfRollHandler = nil
local suppressRawTransmogMessages = 0
local suppressRawTransmogUntil = 0

---@param value any
---@return boolean
local function IsSafeValue(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

---@param rollID number
---@return string?
local function GetCachedLootRollLink(rollID)
    local link = LootRollLinks[rollID]
    if link then
        return link
    end
    if type(GetLootRollItemLink) ~= "function" then
        return
    end
    link = GetLootRollItemLink(rollID)
    if type(link) ~= "string" or link == "" or not IsSafeValue(link) then
        return
    end
    LootRollLinks[rollID] = link
    return link
end

---@param rollID number
local function RemovePendingSelfRollByID(rollID)
    for i = #PendingSelfRolls, 1, -1 do
        if PendingSelfRolls[i].rollID == rollID then
            table.remove(PendingSelfRolls, i)
        end
    end
end

local function PrunePendingSelfRolls()
    local now = GetTime()
    for i = #PendingSelfRolls, 1, -1 do
        if now - PendingSelfRolls[i].time > PENDING_SELF_ROLL_TTL then
            table.remove(PendingSelfRolls, i)
        end
    end
end

local function CanOutputSyntheticSelfRoll(result, message)
    if not db.Enabled then
        return false
    end
    local group = message.group
    if db.IgnoredGroups[group] or message.group == LootFeedMessageGroup.Ignore then
        return false
    end
    if db.EnabledGroups[group] == false then
        return false
    end
    return not EvaluateFilters(db.Filters, result, message)
end

---@param rollID number
local function EmitPendingTransmogRoll(rollID)
    for i, pending in ipairs(PendingSelfRolls) do
        if pending.rollID == rollID and pending.Type == "YouTransmog" then
            local link = pending.Link or GetCachedLootRollLink(rollID)
            if not link then
                return
            end
            table.remove(PendingSelfRolls, i)
            local result = {
                Type = "YouTransmog",
                Link = link,
            }
            if syntheticSelfRollHandler and CanOutputSyntheticSelfRoll(result, SyntheticSelfRollMessage) then
                syntheticSelfRollHandler(result, SyntheticSelfRollMessage)
                suppressRawTransmogMessages = suppressRawTransmogMessages + 1
                suppressRawTransmogUntil = GetTime() + 2
            end
            return
        end
    end
end

---@param rollID number
---@param rollType number
local function CacheSelfRoll(rollID, rollType)
    local resultType = RollTypeToResultType[rollType]
    if not resultType or type(rollID) ~= "number" then
        return
    end
    RemovePendingSelfRollByID(rollID)
    PendingSelfRolls[#PendingSelfRolls + 1] = {
        rollID = rollID,
        Type = resultType,
        Link = GetCachedLootRollLink(rollID),
        time = GetTime(),
    }

    -- Unlike Need/Greed/Pass, Retail does not provide a reliable self-chat
    -- format for Transmog. Emit it from the actual roll action instead. The
    -- short delay gives CONFIRM_LOOT_ROLL time to remove the provisional
    -- entry for bind-on-pickup items; ConfirmLootRoll will then cache it again
    -- only after the player accepts the confirmation.
    if resultType == "YouTransmog" and C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            EmitPendingTransmogRoll(rollID)
        end)
    end
end

local function EnsureLootRollHook()
    if type(hooksecurefunc) ~= "function" then
        return
    end
    if not rollOnLootHooked and type(RollOnLoot) == "function" then
        hooksecurefunc("RollOnLoot", CacheSelfRoll)
        rollOnLootHooked = true
    end
    if not confirmLootRollHooked and type(ConfirmLootRoll) == "function" then
        hooksecurefunc("ConfirmLootRoll", CacheSelfRoll)
        confirmLootRollHooked = true
    end
end

---@param text string
---@return number?
local function GetLootHistoryIDFromText(text)
    if type(text) ~= "string" or not IsSafeValue(text) then
        return
    end
    local linkedID = text:match("|HlootHistory:(%d+)|h")
    if linkedID then
        return tonumber(linkedID)
    end
    if #text == 0 or #text > 4 or text:find("|", 1, true) then
        return
    end
    local value = 0
    local multiplier = 1
    for i = 1, #text do
        value = value + text:byte(i) * multiplier
        multiplier = multiplier * 256
    end
    return value
end

---@param text string
---@param link string
---@return boolean
local function TextContainsLootLink(text, link)
    if text:find(link, 1, true) then
        return true
    end
    local hyperlink = link:match("|H([^|]+)|h")
    return hyperlink ~= nil and text:find("|H" .. hyperlink .. "|h", 1, true) ~= nil
end

---@param text string
---@param transmogOnly boolean
---@return table?, number?
local function FindPendingSelfRoll(text, transmogOnly)
    PrunePendingSelfRolls()
    for i, pending in ipairs(PendingSelfRolls) do
        if (not transmogOnly or pending.Type == "YouTransmog") and
            (transmogOnly or (pending.Link and TextContainsLootLink(text, pending.Link))) then
            return pending, i
        end
    end
end

---@param event WowEvent
---@param text string
---@return LootFeedMessageFormatSimpleParserResults?, LootFeedMessage?
local function ProcessPendingSelfRoll(event, text)
    if event ~= "CHAT_MSG_LOOT" or type(text) ~= "string" or not IsSafeValue(text) then
        return
    end
    local lootHistoryID = GetLootHistoryIDFromText(text)
    if not lootHistoryID then
        return
    end

    -- Transmog has no LOOT_ROLL_*_SELF GlobalString. The client currently emits
    -- the loot-history ID as a tiny raw string, so pair it with the oldest
    -- pending Transmog click instead of assuming that ID is the rollID.
    local isRawLootHistoryID = #text <= 4 and not text:find("|", 1, true)
    local pending, index = FindPendingSelfRoll(text, isRawLootHistoryID)
    if not pending then
        return
    end
    table.remove(PendingSelfRolls, index)

    local link = pending.Link or GetCachedLootRollLink(pending.rollID)
    if not link then
        return
    end
    return {
        Type = pending.Type,
        Link = link,
        Value = lootHistoryID,
    }, SyntheticSelfRollMessage
end

---@param result LootFeedMessageFormatSimpleParserResults?
---@param message LootFeedMessage?
local function ClearPendingSelfRoll(result, message)
    if not result or not message or message.group ~= LootFeedMessageGroup.LootRollYouDecide then
        return
    end
    for i = #PendingSelfRolls, 1, -1 do
        local pending = PendingSelfRolls[i]
        if pending.Type == result.Type and (not pending.Link or not result.Link or pending.Link == result.Link) then
            table.remove(PendingSelfRolls, i)
            return
        end
    end
end

---@type LootFeedNSEventCallbackResult
local ProcessChatEvent

---@type table<WowEvent, LootFeedNSEventCallbackResult>
local EventHandlers = {
    START_LOOT_ROLL = function(event, rollID)
        if type(rollID) == "number" then
            GetCachedLootRollLink(rollID)
        end
    end,
    CONFIRM_LOOT_ROLL = function(event, rollID)
        if type(rollID) == "number" then
            RemovePendingSelfRollByID(rollID)
        end
    end,
    CANCEL_ALL_LOOT_ROLLS = function()
        table.wipe(PendingSelfRolls)
        table.wipe(LootRollLinks)
    end,
    QUEST_TURNED_IN = function(event, ...)
        ---@type number?, number?, number?
        local questID, xp, money = ...
        if xp and xp > 0 then
            return ProcessChatEvent("CHAT_MSG_COMBAT_XP_GAIN", format(COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED, xp))
        end
        if money and money > 0 then
            return ProcessChatEvent("CHAT_MSG_MONEY", format(YOU_LOOT_MONEY, C_CurrencyInfo.GetCoinText(money)))
        end
    end,
}

local function GetMessageEvents()
    local events = {} ---@type WowEvent[]
    local numEvents = #events
    for _, message in ipairs(MessagesCollection) do
        for _, event in ipairs(message.events) do
            if not TableContains(events, event) then
                numEvents = numEvents +  1
                events[numEvents] = event
            end
        end
    end
    return events
end

local MessageEvents = GetMessageEvents()

---@param frame LootFeedNSEventFrame
local function RegisterEvents(frame)
    for event, _ in pairs(EventHandlers) do
        pcall(frame.RegisterEvent, frame, event)
    end
end

---@param frame LootFeedNSEventFrame
local function UnregisterEvents(frame)
    for event, _ in pairs(EventHandlers) do
        pcall(frame.UnregisterEvent, frame, event)
    end
end

---@param onChatEvent LootFeedNSEventChatEventCallback
local function RegisterChatEvents(onChatEvent)
    local numEvents = #MessageEvents
    for i = numEvents, 1, -1 do
        local event = MessageEvents[i]
        local success = pcall(AddMessageEventFilter, event, onChatEvent)
        if not success then
            table.remove(MessageEvents, i)
        end
    end
end

---@param onChatEvent LootFeedNSEventChatEventCallback
local function UnregisterChatEvents(onChatEvent)
    local numEvents = #MessageEvents
    for i = numEvents, 1, -1 do
        local event = MessageEvents[i]
        local success = pcall(RemoveMessageEventFilter, event, onChatEvent)
        if not success then
            table.remove(MessageEvents, i)
        end
    end
end

---@type LootFeedNSEventCallbackResult
function ProcessChatEvent(event, ...)
    local text = ...
    if suppressRawTransmogMessages > 0 and GetTime() > suppressRawTransmogUntil then
        suppressRawTransmogMessages = 0
    end
    if event == "CHAT_MSG_LOOT" and suppressRawTransmogMessages > 0 and type(text) == "string" and IsSafeValue(text) and #text > 0 and #text <= 4 and not text:find("|", 1, true) then
        suppressRawTransmogMessages = suppressRawTransmogMessages - 1
        return nil, nil, true
    end

    local result, message = ProcessChatMessage(event, ...)
    if result then
        ClearPendingSelfRoll(result, message)
    else
        result, message = ProcessPendingSelfRoll(event, text)
    end
    if not result or not message then
        return
    end
    local group = message.group
    if db.IgnoredGroups[group] or message.group == LootFeedMessageGroup.Ignore then
        return result, message, true
    end
    if db.EnabledGroups[group] == false then
        return
    end
    local isFiltered = EvaluateFilters(db.Filters, result, message)
    if isFiltered then
        return result, message, true
    end
    return result, message
end

---@class LootFeedNSReporting
local function SetSyntheticSelfRollHandler(handler)
    syntheticSelfRollHandler = handler
end

ns.Reporting = {
    EventHandlers = EventHandlers,
    MessageEvents = MessageEvents,
    RegisterEvents = RegisterEvents,
    UnregisterEvents = UnregisterEvents,
    RegisterChatEvents = RegisterChatEvents,
    UnregisterChatEvents = UnregisterChatEvents,
    ProcessChatEvent = ProcessChatEvent,
    EnsureLootRollHook = EnsureLootRollHook,
    SetSyntheticSelfRollHandler = SetSyntheticSelfRollHandler,
}
