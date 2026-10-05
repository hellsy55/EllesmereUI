local rootNS = select(2, ...)
rootNS.LootFeed = rootNS.LootFeed or {}
local ns = rootNS.LootFeed ---@class LootFeedNS

local LootFeedMessageGroup = ns.Messages.LootFeedMessageGroup
local MessagesCollection = ns.Messages.MessagesCollection
local TableCopy = ns.Utils.TableCopy
local GetTimerunningSeasonID = ns.Utils.GetTimerunningSeasonID

---@enum LootFeedChatFrame
local LootFeedChatFrame = {
    ChatFrame1 = "ChatFrame1",
    ChatFrame2 = "ChatFrame2",
    ChatFrame3 = "ChatFrame3",
    ChatFrame4 = "ChatFrame4",
    ChatFrame5 = "ChatFrame5",
    ChatFrame6 = "ChatFrame6",
    ChatFrame7 = "ChatFrame7",
    ChatFrame8 = "ChatFrame8",
    ChatFrame9 = "ChatFrame9",
}

---@class LootFeedNSSettingsOptions
---@field ChatFrame LootFeedChatFrame
---@field EnabledGroups table<LootFeedMessageGroup, boolean?>
---@field IgnoredGroups table<LootFeedMessageGroup, boolean?>
---@field DebounceGroups table<LootFeedMessageGroup, number?>
---@field EnabledTooltips table<LootFeedTooltipHandlerType, boolean?>
---@field Filters LootFeedFilters

---@class LootFeedNSSettingsOptions
local DefaultOptions = {
    Enabled = true, --- actively monitor loot messages and apply transformations
    EnableTooltips = true, --- show tooltips above chat frame when hovering links
    EnableRemixMode = true, --- enable separate profile with settings when on a remix character
    ChatFrame = LootFeedChatFrame.ChatFrame1, --- the default output chat frame
    Debounce = 2, --- gather loot messages and when it settles this many seconds later we print the summary
    DebounceInCombat = true, --- if debounce should wait until combat ends before counting down
    ShortenPlayerNames = true, --- enable to remove the realm name
    ShortenFactionNames = true, --- enable to reduce the length of faction names
    ShortenFactionNamesLength = 10, --- specify the length before reduction activates
    IconTrim = 8, --- the px we want to trim from the texture icons
    IconSize = 12, --- the px size we want the texture icon to be shown at
    ItemCount = false, --- enable to add item count behind icons
    ItemCountBank = true, --- enable to also include items in the bank
    ItemCountUses = true, --- enable to count uses/charges as "one item"
    ItemCountReagentBank = true, --- enable to also include items in the reagent bank
    ItemCountCurrency = true, --- enable to count currency items
    ItemLevel = true, --- enable to add item level behind icons
    ItemLevelEquipmentOnly = true, --- enable to only show item level on equippable items
    ItemTier = true, --- enable to add quality tier behind icons (DF crafting tier system)
    ItemTierAsText = true, --- enable to convert the texture indicator into text
    EnabledGroups = {}, --- these groups are enabled for processing
    IgnoredGroups = {}, --- these groups are ignored and will be filtered from the chat
    DebounceGroups = {}, --- these groups use a custom `Debounce` value
    EnabledTooltips = {}, --- only used if `EnableTooltips` is enabled, only tooltips of this type will be shown when hovering links
    Filters = {}, --- list of filters (rules or rule groups) to better specify what we wish to see printed to the chat frame
}

do

    for _, message in ipairs(MessagesCollection) do
        local defaultDebounce = message.defaultDebounce
        if defaultDebounce then
            DefaultOptions.DebounceGroups[message.group] = defaultDebounce
        end
    end

end

---@class LootFeedNSSettingsOptions
local DefaultRemixOptions = TableCopy(DefaultOptions)

if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then

    ---@type LootFeedFilterRule
    local ItemIsQuest = {
        group = LootFeedMessageGroup.Loot,
        type = "Loot",
        key = "Link",
        convert = "quest",
        comparator = "eq",
        value = true,
    }

    ---@type LootFeedFilterRule
    local ItemIsGem = {
        group = LootFeedMessageGroup.Loot,
        type = "Loot",
        key = "Link",
        convert = "itemClass",
        comparator = "eq",
        value = Enum.ItemClass.Gem,
    }

    ---@type LootFeedFilterRule
    local ItemQualityCommonOrHigher = {
        group = LootFeedMessageGroup.Loot,
        type = "Loot",
        key = "Link",
        convert = "quality",
        comparator = "ge",
        value = Enum.ItemQuality.Common,
    }

    ---@type LootFeedFilterRule
    local ItemQualityRareOrHigher = {
        group = LootFeedMessageGroup.Loot,
        type = "Loot",
        key = "Link",
        convert = "quality",
        comparator = "ge",
        value = Enum.ItemQuality.Rare,
    }

    DefaultOptions.Filters[#DefaultOptions.Filters + 1] = {
        logic = "or",
        children = {
            ItemIsQuest,
            ItemQualityCommonOrHigher,
        },
    }

    DefaultRemixOptions.Filters[#DefaultRemixOptions.Filters + 1] = {
        logic = "or",
        children = {
            ItemIsQuest,
            ItemIsGem,
            ItemQualityRareOrHigher,
        },
    }

end

---@class LootFeedNSSettingsMetatable
local OptionsMetatable = {
    __index = function(self, key)
        local value = DefaultOptions[key]
        if type(value) == "table" then
            value = TableCopy(value)
            rawset(self, key, value)
        end
        return value
    end,
}

---@class LootFeedNSSettingsMetatable
local RemixOptionsMetatable = {
    __index = function(self, key)
        local value = DefaultRemixOptions[key]
        if type(value) == "table" then
            value = TableCopy(value)
            rawset(self, key, value)
        end
        return value
    end,
}

---@return LootFeedNSSettingsOptions db, LootFeedNSSettingsOptions remixDb
local function ProcessSavedVariables()
    -- LootFeed is embedded in EllesmereUI Chat, so its settings belong to the
    -- Chat profile instead of standalone LootFeed SavedVariables.
    if rootNS.ECHAT and rootNS.ECHAT.DB then
        rootNS.ECHAT.DB() -- ensures _ECHAT_DB exists
    end

    local chatDB = _G._ECHAT_DB
    local profile = chatDB and chatDB.profile
    if not profile then
        -- This should only be reachable extremely early in loading. Keep a
        -- stable fallback so reads are safe until the profile DB is available.
        rootNS._lootFeedFallbackProfile = rootNS._lootFeedFallbackProfile or {
            lootFeed = {},
            lootFeedRemix = {},
        }
        profile = rootNS._lootFeedFallbackProfile
    end

    local db = profile.lootFeed
    local remixDb = profile.lootFeedRemix
    if type(db) ~= "table" then
        db = {}
        profile.lootFeed = db
    end
    if type(remixDb) ~= "table" then
        remixDb = {}
        profile.lootFeedRemix = remixDb
    end
    if not getmetatable(db) then
        setmetatable(db, OptionsMetatable)
    end
    if not getmetatable(remixDb) then
        setmetatable(remixDb, RemixOptionsMetatable)
    end

    -- Enabled and Ignored are mutually exclusive states. Preserve Ignored as
    -- the stronger state when migrating profiles that predate this rule.
    local function NormalizeMessageGroups(options)
        local enabled = options.EnabledGroups
        local ignored = options.IgnoredGroups
        for group, isIgnored in pairs(ignored) do
            if isIgnored then
                enabled[group] = false
            end
        end
    end
    NormalizeMessageGroups(db)
    NormalizeMessageGroups(remixDb)

    return db, remixDb
end

---@class LootFeedNSSettings
---@field public db LootFeedNSSettingsOptions

---@param db LootFeedNSSettingsOptions
---@param key string
local function CanUseRemixDB(db, key)
    if key == "EnableRemixMode" or db.EnableRemixMode == false then
        return false
    end
    local seasonID = GetTimerunningSeasonID()
    return not not seasonID
end

---@type LootFeedNSSettingsOptions
local flexDbProxy = setmetatable({}, {
    __index = function(self, key)
        local db, remixDb = ProcessSavedVariables()
        if CanUseRemixDB(db, key) then
            return remixDb[key]
        end
        return db[key]
    end,
    __newindex = function (self, key, value)
        local db, remixDb = ProcessSavedVariables()
        if CanUseRemixDB(db, key) then
            remixDb[key] = value
        else
            db[key] = value
        end
    end,
})

local function ResetSavedVariables()
    local db, remixDb = ProcessSavedVariables()
    table.wipe(db)
    table.wipe(remixDb)
end

local function GetChatFrame()
    local chatName = flexDbProxy.ChatFrame
    local chatFrame = _G[chatName] ---@type LootFeedChatFramePolyfill
    return chatFrame
end

---@class LootFeedNSSettings
ns.Settings = {
    db = flexDbProxy,
    DefaultOptions = DefaultOptions,
    ResetSavedVariables = ResetSavedVariables,
    GetChatFrame = GetChatFrame,
}
