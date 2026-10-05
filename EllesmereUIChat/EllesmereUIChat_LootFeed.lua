local rootNS = select(2, ...)
rootNS.LootFeed = rootNS.LootFeed or {}
local ns = rootNS.LootFeed ---@class LootFeedNS

local addOnName = ... ---@type string

local db = ns.Settings.db
local GetChatFrame = ns.Settings.GetChatFrame
local EventHandlers = ns.Reporting.EventHandlers
local IsChatEventRelevant = ns.Messages.IsChatEventRelevant
local ProcessChatEvent = ns.Reporting.ProcessChatEvent
local RegisterEvents = ns.Reporting.RegisterEvents
local UnregisterEvents = ns.Reporting.UnregisterEvents
local RegisterChatEvents = ns.Reporting.RegisterChatEvents
local UnregisterChatEvents = ns.Reporting.UnregisterChatEvents
local EnsureLootRollHook = ns.Reporting.EnsureLootRollHook
local SetSyntheticSelfRollHandler = ns.Reporting.SetSyntheticSelfRollHandler
local CreateOutputHandler = ns.Output.CreateOutputHandler
local ChattynatorUtil = ns.Utils.ChattynatorUtil
local GetChatFrames = ns.Utils.GetChatFrames
local EnableHyperlinks = ns.Tooltip.EnableHyperlinks
local DisableHyperlinks = ns.Tooltip.DisableHyperlinks

---@class ScrollingMessageFrame

---@class ScrollingMessageFramePolyfill : MessageFrame, ScrollingMessageFrame
---@field public name string @The name of the chat frame as shown on its tab.
---@field public SetMaxLines fun(self: ScrollingMessageFramePolyfill, count: number)
---@field public SetInsertMode fun(self: ScrollingMessageFramePolyfill, mode: number)

---@class LootFeedChatFramePolyfill : ScrollingMessageFramePolyfill

---@alias LootFeedNSEventCallbackResult fun(event: WowEvent, ...: any): result: LootFeedMessageFormatSimpleParserResults?, message: LootFeedMessage?, hideChatIgnoreResult: boolean?

---@alias LootFeedNSEventChatEventCallback fun(chatFrame: LootFeedChatFramePolyfill, event: WowEvent, ...: any): filter: boolean?, ...

---@class LootFeedNSEventFrame : Frame
---@field public isLoaded boolean
---@field public isEnabled? boolean
---@field public OnChatEvent LootFeedNSEventChatEventCallback

---@class LootFeedNSEventFrame
local frame = CreateFrame("Frame")

local output = CreateOutputHandler()

SetSyntheticSelfRollHandler(function(result, message)
    output:Add({ result = result, message = message })
end)

---@type LootFeedNSEventChatEventCallback
local function OnChatEvent(chatFrame, event, ...)
    if chatFrame ~= GetChatFrame() then
        return false, ...
    end
    local result, message, hideChatIgnoreResult = ProcessChatEvent(event, ...)
    if hideChatIgnoreResult then
        return true
    end
    if result and message then
        output:Add({ result = result, message = message })
        return true
    end
    return false, ...
end

---@type ChattynatorChatFilter
local function OnChattynatorChatEventFilter(data)
    if not ChattynatorUtil:IsChatFrameActive(1) then
        return
    end
    if not IsChatEventRelevant(data.typeInfo.event) then
        return true
    end
    local _, _, hideChatIgnoreResult = ProcessChatEvent(data.typeInfo.event, data.text, data.recordedBy, "", "", data.recordedBy, "", 0, 0, "", 0, 0, "", 0, false, false, false, false)
    if hideChatIgnoreResult then
        return false
    end
    return true
end

---@type LootFeedChatFramePolyfill
---@diagnostic disable-next-line: missing-fields
local ChattynatorChatModifierFakeChatFrame = {}

---@param data ChattynatorChatData
local function WrapChattynatorChatModifierWithFakeChatFrame(data)
    ChattynatorChatModifierFakeChatFrame.AddMessage = function(_, line, r, g, b)
        data.text = line
        data.color.r, data.color.g, data.color.b = r, g, b
    end
    return ChattynatorChatModifierFakeChatFrame
end

---@type ChattynatorChatModifier
local function OnChattynatorChatEventModifier(data)
    if not ChattynatorUtil:IsChatFrameActive(1) then
        return
    end
    if not IsChatEventRelevant(data.typeInfo.event) then
        return
    end
    local result, message, hideChatIgnoreResult = ProcessChatEvent(data.typeInfo.event, data.text, data.recordedBy, "", "", data.recordedBy, "", 0, 0, "", 0, 0, "", 0, false, false, false, false)
    if hideChatIgnoreResult then
        return
    end
    if not result or not message then
        return
    end
    local origChatFrame = output.chatFrame
    output.chatFrame = WrapChattynatorChatModifierWithFakeChatFrame(data)
    output:Add({ result = result, message = message })
    output:Flush(message.group)
    output.chatFrame = origChatFrame
end

---@param event WowEvent
---@param ... any
function frame:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        EnsureLootRollHook()
        local name = ...
        if name == addOnName then
            self.isLoaded = true
            self:UpdateState()
            ns.Links:Init()
        end
    end
    if not self.isLoaded then
        return
    end
    local eventHandler = EventHandlers[event]
    if not eventHandler then
        return
    end
    local result, message, hideChatIgnoreResult = eventHandler(event, ...)
    if hideChatIgnoreResult then
        return
    end
    if result and message then
        output:Add({ result = result, message = message })
    end
end

---@param key string
---@param value any
---@param oldValue any
function frame:OnSettingsChanged(key, value, oldValue)
    frame:UpdateState()
end

function frame:Enable()
    if self.isEnabled then
        return
    end
    self.isEnabled = true
    RegisterEvents(frame)
    if ChattynatorUtil.Loaded then
        ChattynatorUtil:AddFilter(OnChattynatorChatEventFilter)
        ChattynatorUtil:AddModifier(OnChattynatorChatEventModifier)
    else
        RegisterChatEvents(OnChatEvent)
    end
end

function frame:Disable()
    if self.isEnabled == false then
        return
    end
    self.isEnabled = false
    UnregisterEvents(frame)
    if ChattynatorUtil.Loaded then
        ChattynatorUtil:RemoveFilter(OnChattynatorChatEventFilter)
        ChattynatorUtil:RemoveModifier(OnChattynatorChatEventModifier)
    else
        UnregisterChatEvents(OnChatEvent)
    end
end

---@param forceUpdate? boolean
function frame:UpdateState(forceUpdate)
    if forceUpdate then
        self.isEnabled = nil
    end
    if db.Enabled then
        self:Enable()
    else
        self:Disable()
    end
    for _, chatFrame in ipairs(GetChatFrames()) do
        if db.Enabled and db.EnableTooltips then
            EnableHyperlinks(chatFrame)
        else
            DisableHyperlinks(chatFrame)
        end
    end
end

ns.EventFrame = frame

frame:SetScript("OnEvent", frame.OnEvent)
frame:RegisterEvent("ADDON_LOADED")
