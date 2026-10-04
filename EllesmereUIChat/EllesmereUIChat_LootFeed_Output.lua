local rootNS = select(2, ...)
rootNS.LootFeed = rootNS.LootFeed or {}
local ns = rootNS.LootFeed ---@class LootFeedNS

local db = ns.Settings.db
local GetChatFrame = ns.Settings.GetChatFrame
local TableCopy = ns.Utils.TableCopy
local TableCombine = ns.Utils.TableCombine
local TableGroup = ns.Utils.TableGroup
local TableMap = ns.Utils.TableMap
local Format = ns.Formatter.Format

---@class LootFeedBufferItem
---@field public message LootFeedMessage
---@field public result LootFeedMessageFormatSimpleParserResults

---@class LootFeedBufferItemGroup
---@field public name LootFeedMessageGroup
---@field public results LootFeedMessageFormatSimpleParserResults[]

---@class LootFeedNSBuffer
local LootFeedNSBuffer = {}

function LootFeedNSBuffer:OnLoad()
    self.buffer = {} ---@type LootFeedBufferItem[]
    self.length = 0
end

function LootFeedNSBuffer:Length()
    return self.length
end

function LootFeedNSBuffer:IsEmpty()
    return self.length == 0
end

function LootFeedNSBuffer:Clear()
    table.wipe(self.buffer)
    self.length = 0
end

---@param group LootFeedMessageGroup
function LootFeedNSBuffer:ClearGroup(group)
    local length = self.length
    for i = #self.buffer, 1, -1 do
        local item = self.buffer[i]
        if item.message.group == group then
            length = length - 1
            table.remove(self.buffer, i)
        end
    end
    self.length = length
end

function LootFeedNSBuffer:GroupResults()
    local groups, keys = TableGroup(
        self.buffer,
        function(item)
            return item.message.group
        end
    )
    local results = {} ---@type LootFeedBufferItemGroup[]
    local index = 0
    ---@param item LootFeedBufferItem
    local function map(item)
        return item.result
    end
    for i = 1, #groups do
        local k = keys[i]
        local v = groups[i]
        v = TableMap(v, map)
        index = index + 1
        results[index] = { name = k, results = v }
    end
    return results
end

---@param index number
---@return LootFeedBufferItem item
function LootFeedNSBuffer:Get(index)
    return self.buffer[index]
end

---@param item LootFeedBufferItem
---@return number index
function LootFeedNSBuffer:Add(item)
    local index = self.length + 1
    self.length = index
    self.buffer[index] = item
    return index
end

function LootFeedNSBuffer:New()
    local buffer = TableCopy(LootFeedNSBuffer) ---@type LootFeedNSBuffer
    buffer:OnLoad()
    return buffer
end

local function CreateBuffer()
    return LootFeedNSBuffer:New()
end

---@class LootFeedNSOutputHandler
local LootFeedNSOutputHandler = {}

---@param chatFrame? LootFeedChatFramePolyfill
function LootFeedNSOutputHandler:OnLoad(chatFrame)
    self.chatFrame = chatFrame
    self.buffer = CreateBuffer()
    self.lastAdd = 0
    self.lastOutput = 0
    self.prevInCombat = nil ---@type boolean?
    self.inCombat = nil ---@type boolean?
    self.timer = nil ---@type FunctionContainer?
    self.timerOnTick = function()
        if not db.DebounceInCombat then
            self.prevInCombat = self.inCombat
            self.inCombat = InCombatLockdown()
            if self.inCombat then
                return
            end
            if self.prevInCombat then
                self:OnAdd()
                return
            end
        end
        if self.timer then
            self.timer:Cancel()
            self.timer = nil
        end
        self:Flush()
        self.lastOutput = GetTime()
    end
end

function LootFeedNSOutputHandler:OnAdd()
    self.lastAdd = GetTime()
    if self.timer then
        self.timer:Cancel()
    end
    self.timer = C_Timer.NewTimer(db.Debounce, self.timerOnTick)
end

---@param flushGroup? LootFeedMessageGroup
function LootFeedNSOutputHandler:Flush(flushGroup)
    local buffer = self.buffer
    if buffer:IsEmpty() then
        return
    end
    local chatFrame = self.chatFrame or GetChatFrame()
    local lines = {} ---@type string[]
    local groups = buffer:GroupResults()
    for _, group in ipairs(groups) do
        if not flushGroup or group.name == flushGroup then
            local itemLines = Format(group.name, group.results)
            if itemLines then
                local lineType = type(itemLines)
                if lineType == "table" then
                    TableCombine(lines, itemLines)
                elseif lineType == "string" then
                    lines[#lines + 1] = itemLines
                else
                    lines[#lines + 1] = tostring(itemLines)
                end
            end
        end
    end
    for _, line in ipairs(lines) do
        chatFrame:AddMessage(line, 1, 1, 0)
    end
    if flushGroup then
        buffer:ClearGroup(flushGroup)
    else
        buffer:Clear()
    end
end

---@param item LootFeedBufferItem
function LootFeedNSOutputHandler:Add(item)
    self.buffer:Add(item)
    if db.Debounce == 0 then
        self:Flush()
        return
    end
    local group = item.message.group
    local debounce = db.DebounceGroups[group]
    if debounce == 0 then
        self:Flush(group)
        return
    end
    self:OnAdd()
end

---@param chatFrame? LootFeedChatFramePolyfill
function LootFeedNSOutputHandler:New(chatFrame)
    local handler = TableCopy(LootFeedNSOutputHandler) ---@type LootFeedNSOutputHandler
    handler:OnLoad(chatFrame)
    return handler
end

---@param chatFrame? LootFeedChatFramePolyfill
local function CreateOutputHandler(chatFrame)
    return LootFeedNSOutputHandler:New(chatFrame)
end

---@class LootFeedNSOutput
ns.Output = {
    CreateBuffer = CreateBuffer,
    CreateOutputHandler = CreateOutputHandler,
}
