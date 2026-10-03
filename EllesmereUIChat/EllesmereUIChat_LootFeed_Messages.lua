local rootNS = select(2, ...)
rootNS.LootFeed = rootNS.LootFeed or {}
local ns = rootNS.LootFeed ---@class LootFeedNS

local SimpleHexColors = ns.Utils.SimpleHexColors
local TableCopy = ns.Utils.TableCopy
local TableContains = ns.Utils.TableContains
local TableMerge = ns.Utils.TableMerge
local TableReverse = ns.Utils.TableReverse
local PatternToFormat = ns.Utils.PatternToFormat
local ConvertToNumber = ns.Utils.ConvertToNumber
local ConvertToMoney = ns.Utils.ConvertToMoney
local ValuesAreSameish = ns.Utils.ValuesAreSameish

---@enum LootFeedMessageGroup
local LootFeedMessageGroup = {
    Reputation = "Reputation",
    Honor = "Honor",
    Experience = "Experience",
    -- GuildExperience = "GuildExperience",
    FollowerExperience = "FollowerExperience",
    Currency = "Currency",
    Money = "Money",
    Loot = "Loot",
    LootRoll = "LootRoll",
    LootRollYouDecide = "LootRollYouDecide",
    LootRollDecide = "LootRollDecide",
    -- LootRollYouRolled = "LootRollYouRolled",
    LootRollRolled = "LootRollRolled",
    LootRollYouResult = "LootRollYouResult",
    LootRollResult = "LootRollResult",
    LootRollInfo = "LootRollInfo",
    ItemChanged = "ItemChanged",
    AnimaPower = "AnimaPower",
    ArtifactPower = "ArtifactPower",
    Transmogrification = "Transmogrification",
    Ignore = "Ignore",
}

---@enum LootFeedMessageFormatField
local LootFeedMessageFormatField = {
    Name = "Name",
    NameExtra = "NameExtra",
    Value = "Value",
    ValueExtra = "ValueExtra",
    Bonus = "Bonus",
    BonusExtra = "BonusExtra",
    Link = "Link",
    LinkExtra = "LinkExtra",
    Zone = "Zone",
    ZoneExtra = "ZoneExtra",
}

---@enum LootFeedMessageFormatTokenType
local LootFeedMessageFormatTokenType = {
    Float = "Float",
    Link = "Link",
    Money = "Money",
    Number = "Number",
    String = "String",
    Target = "Target",
}

---@type table<LootFeedMessageFormatSimpleParserResultExperienceKeys, LootFeedMessageFormatToken>
local Tokens = {
    NameString = {
        field = LootFeedMessageFormatField.Name,
        type = LootFeedMessageFormatTokenType.String,
    },
    NameExtraString = {
        field = LootFeedMessageFormatField.NameExtra,
        type = LootFeedMessageFormatTokenType.String,
    },
    NameTarget = {
        field = LootFeedMessageFormatField.Name,
        type = LootFeedMessageFormatTokenType.Target,
    },
    NameExtraTarget = {
        field = LootFeedMessageFormatField.NameExtra,
        type = LootFeedMessageFormatTokenType.Target,
    },
    ValueNumber = {
        field = LootFeedMessageFormatField.Value,
        type = LootFeedMessageFormatTokenType.Number,
    },
    ValueExtraNumber = {
        field = LootFeedMessageFormatField.ValueExtra,
        type = LootFeedMessageFormatTokenType.Number,
    },
    ValueFloat = {
        field = LootFeedMessageFormatField.Value,
        type = LootFeedMessageFormatTokenType.Float,
    },
    ValueExtraFloat = {
        field = LootFeedMessageFormatField.ValueExtra,
        type = LootFeedMessageFormatTokenType.Float,
    },
    ValueString = {
        field = LootFeedMessageFormatField.Value,
        type = LootFeedMessageFormatTokenType.String,
    },
    ValueExtraString = {
        field = LootFeedMessageFormatField.ValueExtra,
        type = LootFeedMessageFormatTokenType.String,
    },
    ValueMoney = {
        field = LootFeedMessageFormatField.Value,
        type = LootFeedMessageFormatTokenType.Money,
    },
    ValueExtraMoney = {
        field = LootFeedMessageFormatField.ValueExtra,
        type = LootFeedMessageFormatTokenType.Money,
    },
    BonusNumber = {
        field = LootFeedMessageFormatField.Bonus,
        type = LootFeedMessageFormatTokenType.Number,
    },
    BonusExtraNumber = {
        field = LootFeedMessageFormatField.BonusExtra,
        type = LootFeedMessageFormatTokenType.Number,
    },
    BonusFloat = {
        field = LootFeedMessageFormatField.Bonus,
        type = LootFeedMessageFormatTokenType.Float,
    },
    BonusExtraFloat = {
        field = LootFeedMessageFormatField.BonusExtra,
        type = LootFeedMessageFormatTokenType.Float,
    },
    BonusString = {
        field = LootFeedMessageFormatField.Bonus,
        type = LootFeedMessageFormatTokenType.String,
    },
    BonusExtraString = {
        field = LootFeedMessageFormatField.BonusExtra,
        type = LootFeedMessageFormatTokenType.String,
    },
    Link = {
        field = LootFeedMessageFormatField.Link,
        type = LootFeedMessageFormatTokenType.Link,
    },
    LinkExtra = {
        field = LootFeedMessageFormatField.LinkExtra,
        type = LootFeedMessageFormatTokenType.Link,
    },
    ZoneString = {
        field = LootFeedMessageFormatField.Zone,
        type = LootFeedMessageFormatTokenType.String,
    },
    ZoneExtraString = {
        field = LootFeedMessageFormatField.ZoneExtra,
        type = LootFeedMessageFormatTokenType.String,
    },
}

---@alias LootFeedMessageFormatSimpleParserResultType
---|"Fallback"
---|LootFeedMessageFormatSimpleParserResultReputationTypes
---|LootFeedMessageFormatSimpleParserResultHonorTypes
---|LootFeedMessageFormatSimpleParserResultExperienceTypes
-- ---|LootFeedMessageFormatSimpleParserResultGuildExperienceTypes
---|LootFeedMessageFormatSimpleParserResultFollowerExperienceTypes
---|LootFeedMessageFormatSimpleParserResultCurrencyTypes
---|LootFeedMessageFormatSimpleParserResultMoneyTypes
---|LootFeedMessageFormatSimpleParserResultLootTypes
---|LootFeedMessageFormatSimpleParserResultLootRollTypes
---|LootFeedMessageFormatSimpleParserResultItemChangedTypes
---|LootFeedMessageFormatSimpleParserResultAnimaPowerTypes
---|LootFeedMessageFormatSimpleParserResultArtifactPowerTypes
---|LootFeedMessageFormatSimpleParserResultTransmogrificationTypes
---|LootFeedMessageFormatSimpleParserResultIgnoreTypes

---@alias LootFeedMessageFormatSimpleParserResultKeys
---|LootFeedMessageFormatSimpleParserResultReputationKeys
---|LootFeedMessageFormatSimpleParserResultHonorKeys
---|LootFeedMessageFormatSimpleParserResultExperienceKeys
-- ---|LootFeedMessageFormatSimpleParserResultGuildExperienceKeys
---|LootFeedMessageFormatSimpleParserResultFollowerExperienceKeys
---|LootFeedMessageFormatSimpleParserResultCurrencyKeys
---|LootFeedMessageFormatSimpleParserResultMoneyKeys
---|LootFeedMessageFormatSimpleParserResultLootKeys
---|LootFeedMessageFormatSimpleParserResultLootRollKeys
---|LootFeedMessageFormatSimpleParserResultItemChangedKeys
---|LootFeedMessageFormatSimpleParserResultAnimaPowerKeys
---|LootFeedMessageFormatSimpleParserResultArtifactPowerKeys
---|LootFeedMessageFormatSimpleParserResultTransmogrificationKeys
---|LootFeedMessageFormatSimpleParserResultIgnoreKeys

---@alias LootFeedMessageFormatSimpleParserResults
---|LootFeedMessageFormatSimpleParserResultFallback
---|LootFeedMessageFormatSimpleParserResultReputation
---|LootFeedMessageFormatSimpleParserResultHonor
---|LootFeedMessageFormatSimpleParserResultExperience
-- ---|LootFeedMessageFormatSimpleParserResultGuildExperience
---|LootFeedMessageFormatSimpleParserResultFollowerExperience
---|LootFeedMessageFormatSimpleParserResultCurrency
---|LootFeedMessageFormatSimpleParserResultMoney
---|LootFeedMessageFormatSimpleParserResultLoot
---|LootFeedMessageFormatSimpleParserResultLootRoll
---|LootFeedMessageFormatSimpleParserResultItemChanged
---|LootFeedMessageFormatSimpleParserResultAnimaPower
---|LootFeedMessageFormatSimpleParserResultArtifactPower
---|LootFeedMessageFormatSimpleParserResultTransmogrification
---|LootFeedMessageFormatSimpleParserResultIgnore

---@class LootFeedMessageFormatSimpleParserResultFallback
---@field public Type LootFeedMessageFormatSimpleParserResultType

---@alias LootFeedMessageFormatSimpleParser fun(result: LootFeedMessageFormatSimpleParserResults): LootFeedMessageFormatSimpleParserResults|false?

---@alias LootFeedMessageFormatSimpleMap fun(result: LootFeedMessageFormatSimpleParserResults): LootFeedMessageFormatSimpleParserResults|false?

---@alias LootFeedMessageFormatSimpleParserMap fun(results: LootFeedMessageFormatTokenResult[], mapper: LootFeedMessageFormatSimpleMap): LootFeedMessageFormatSimpleParserResults|false?

---@class LootFeedMessageFormatToken
---@field public field LootFeedMessageFormatField
---@field public type LootFeedMessageFormatTokenType
---@field public fallbackValue? any

---@class LootFeedMessageFormatTokenResult : LootFeedMessageFormatToken
---@field public value any

---@class LootFeedMessageFormatSimpleResult : table

---@class LootFeedMessageFormat
---@field public formats string[]
---@field public patterns? string[]
---@field public tokens LootFeedMessageFormatToken[]
---@field public result? LootFeedMessageFormatSimpleParserResults
---@field public parser? LootFeedMessageFormatSimpleParser

---@class LootFeedMessage
---@field public group LootFeedMessageGroup
---@field public events WowEvent[]
---@field public formats LootFeedMessageFormat[]
---@field public result? LootFeedMessageFormatSimpleParserResults
---@field public parser? LootFeedMessageFormatSimpleParser
---@field public tests? any[]
---@field public skipTests? boolean
---@field public defaultDebounce? number

---@class LootFeedMessagePartial : LootFeedMessage
---@field public group? LootFeedMessageGroup
---@field public events? WowEvent[]
---@field public formats? LootFeedMessageFormat[]

---@type LootFeedMessage[]
local MessagesCollection = {}

---@param message LootFeedMessage
local function FillMessageStruct(message)
    if not message.events then
        message.events = {}
    end
    if not message.formats then
        message.formats = {}
    end
    if not message.group then
        message.group = LootFeedMessageGroup.Ignore
    end
    return message
end

---@param ... LootFeedMessagePartial
local function AppendMessages(...)
    local data = {...}
    local first = FillMessageStruct(data[1])
    local index = #MessagesCollection
    for _, message in ipairs(data) do
        local temp = message
        if temp ~= first then
            temp = TableCopy(first)
            TableMerge(temp, message)
        end
        index = index + 1
        MessagesCollection[index] = temp
    end
end

---@param messageFormat LootFeedMessageFormat
---@return any[]
local function CreateMessageTests(messageFormat)
    local tests = {} ---@type any[]
    local testIndex = 0
    for i = 1, #messageFormat.formats do
        local msgFormat = messageFormat.formats[i]
        local args = {} ---@type any[]
        local argIndex = 0
        for j = 1, #messageFormat.tokens do
            local token = messageFormat.tokens[j]
            if token.type == LootFeedMessageFormatTokenType.Float then
                argIndex = argIndex + 1
                args[argIndex] = random(10000, 99999)/100
            elseif token.type == LootFeedMessageFormatTokenType.Link then
                argIndex = argIndex + 1
                args[argIndex] = "|cffffffff|Hitem:6948::::::::70:::::|h[Hearthstone]|h|r"
            elseif token.type == LootFeedMessageFormatTokenType.Money then
                argIndex = argIndex + 1
                args[argIndex] = C_CurrencyInfo.GetCoinText(random(12345, 67890))
            elseif token.type == LootFeedMessageFormatTokenType.Number then
                argIndex = argIndex + 1
                args[argIndex] = random(1, 99)
            elseif token.type == LootFeedMessageFormatTokenType.String then
                argIndex = argIndex + 1
                args[argIndex] = "SampleText"
            elseif token.type == LootFeedMessageFormatTokenType.Target then
                argIndex = argIndex + 1
                args[argIndex] = "SampleName-SampleRealm"
            end
        end
        if args[1] ~= nil then
            local tries = 10
            local success ---@type boolean?
            local text ---@type string?
            while tries > 0 and not success do
                success, text = pcall(format, msgFormat, unpack(args))
                if success then
                    break
                end
                tries = tries - 1
                argIndex = argIndex + 1
                args[argIndex] = "5"
            end
            if text then
                testIndex = testIndex + 1
                tests[testIndex] = {text, unpack(args)}
            end
        end
    end
    return tests
end

local MessageMetaTableTests = {
    ---@param self LootFeedMessage
    __index = function(self, key)
        if key ~= "tests" then
            return
        end
        if self.skipTests then
            return
        end
        if self.group == LootFeedMessageGroup.Ignore then
            return
        end
        local messageFormats = self.formats
        local numMessageFormats = #messageFormats
        local index = 0
        local tests = {}
        for messageFormatIndex = 1, numMessageFormats do
            local messageFormat = messageFormats[messageFormatIndex]
            local messageFormatTests = CreateMessageTests(messageFormat)
            for messageFormatTestIndex = 1, #messageFormatTests do
                index = index + 1
                tests[index] = messageFormatTests[messageFormatTestIndex]
            end
        end
        rawset(self, key, tests)
        return tests
    end,
}

local function FinalizeMessages()
    local numMessages = #MessagesCollection

    for messageIndex = numMessages, 1, -1 do

        local message = MessagesCollection[messageIndex]
        local messageFormats = message.formats
        local numMessageFormats = #messageFormats

        for messageFormatIndex = numMessageFormats, 1, -1 do

            local messageFormat = messageFormats[messageFormatIndex]
            local messageSubFormats = messageFormat.formats
            local numMessageSubFormats = #messageSubFormats

            for messageSubFormatIndex = numMessageSubFormats, 1, -1 do

                local messageSubFormat = messageSubFormats[messageSubFormatIndex]
                local messageSubFormatGlobal = _G[messageSubFormat]

                if type(messageSubFormatGlobal) ~= "string" then
                    numMessageSubFormats = numMessageSubFormats - 1
                    table.remove(messageSubFormats, messageSubFormatIndex)
                else
                    messageSubFormats[messageSubFormatIndex] = messageSubFormatGlobal
                end

            end

            if numMessageSubFormats == 0 then
                numMessageFormats = numMessageFormats - 1
                table.remove(messageFormats, messageFormatIndex)
            end

        end

        if numMessageFormats == 0 then
            numMessages = numMessages - 1
            table.remove(MessagesCollection, messageIndex)
        end

    end

    for messageIndex = numMessages, 1, -1 do

        local message = MessagesCollection[messageIndex]
        local messageResult = message.result
        local messageParser = message.parser
        local messageFormats = message.formats
        local numMessageFormats = #messageFormats

        for messageFormatIndex = numMessageFormats, 1, -1 do

            local messageFormat = messageFormats[messageFormatIndex]
            local messageFormatResult = messageFormat.result
            local messageFormatParser = messageFormat.parser

            if not messageFormatResult then
                messageFormatResult = messageResult
                messageFormat.result = messageFormatResult
            end

            if not messageFormatParser then
                messageFormatParser = messageParser
                messageFormat.parser = messageFormatParser
            end

            local messageSubFormats = messageFormat.formats
            local numMessageSubFormats = #messageSubFormats

            local messageSubPatterns = messageFormat.patterns
            local numMessageSubPatterns = messageSubPatterns and #messageSubPatterns
            local createdMessageSubPatterns ---@type boolean?

            if not messageSubPatterns then
                createdMessageSubPatterns = true
                messageSubPatterns = {}
                numMessageSubPatterns = #messageSubPatterns
                messageFormat.patterns = messageSubPatterns
            end

            for messageSubFormatIndex = numMessageSubFormats, 1, -1 do

                local messageSubFormat = messageSubFormats[messageSubFormatIndex]

                messageSubFormat = PatternToFormat(messageSubFormat)
                messageSubFormat = format("^%s$", messageSubFormat)

                if not TableContains(messageSubPatterns, messageSubFormat) then
                    numMessageSubPatterns = numMessageSubPatterns + 1
                    messageSubPatterns[numMessageSubPatterns] = messageSubFormat
                end

            end

            if createdMessageSubPatterns then
                messageSubPatterns = TableReverse(messageSubPatterns)
                messageFormat.patterns = messageSubPatterns
            end

        end

        setmetatable(message, MessageMetaTableTests)

    end
end

do

    -- Reputation
    do

        ---@alias LootFeedMessageFormatSimpleParserResultReputationKeys "Name"|"Value"|"Bonus"|"BonusExtra"

        ---@alias LootFeedMessageFormatSimpleParserResultReputationTypes "Reputation"|"ReputationLoss"|"ReputationWarband"|"ReputationLossWarband"

        ---@class LootFeedMessageFormatSimpleParserResultReputation
        ---@field public Type LootFeedMessageFormatSimpleParserResultReputationTypes
        ---@field public Name string The name of the faction.
        ---@field public Value number? If provided, the amount of reputation earned.
        ---@field public Bonus number? If provided, the amount of bonus reputation earned.
        ---@field public BonusExtra number? If provided, the amount of bonus reputation earned.

        ---@class LootFeedMessageFormatSimpleParserResultReputationArgs : LootFeedMessageFormatSimpleParserResultReputation
        ---@field public Name? string

        ---@class LootFeedMessageFormatReputation : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultReputationArgs

        AppendMessages(
            {
                group = LootFeedMessageGroup.Reputation,
                events = {
                    "CHAT_MSG_COMBAT_FACTION_CHANGE",
                },
                ---@type LootFeedMessageFormatSimpleParserResultReputationArgs
                result = {
                    Type = "Reputation",
                },
            },
            {
                ---@type LootFeedMessageFormatReputation[]
                formats = {
                    {
                        formats = {
                            "FACTION_STANDING_INCREASED_DOUBLE_BONUS",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                            Tokens.BonusFloat,
                            Tokens.BonusExtraFloat,
                        },
                    },
                    {
                        formats = {
                            "FACTION_STANDING_INCREASED_BONUS",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                            Tokens.BonusFloat,
                        },
                    },
                    {
                        formats = {
                            "FACTION_STANDING_INCREASED_ACH_BONUS",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                            Tokens.BonusFloat,
                        },
                    },
                    {
                        formats = {
                            "FACTION_STANDING_INCREASED_ACCOUNT_WIDE",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                        },
                        result = {
                            Type = "ReputationWarband",
                        },
                    },
                    {
                        formats = {
                            "FACTION_STANDING_INCREASED",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                        },
                    },
                    {
                        formats = {
                            "FACTION_STANDING_INCREASED_GENERIC_ACCOUNT_WIDE",
                        },
                        tokens = {
                            Tokens.NameString,
                        },
                        result = {
                            Type = "ReputationWarband",
                        },
                    },
                    {
                        formats = {
                            "FACTION_STANDING_INCREASED_GENERIC",
                        },
                        tokens = {
                            Tokens.NameString,
                        },
                    },
                    {
                        formats = {
                            "FACTION_STANDING_DECREASED_ACCOUNT_WIDE",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                        },
                        result = {
                            Type = "ReputationLossWarband",
                        },
                    },
                    {
                        formats = {
                            "FACTION_STANDING_DECREASED",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                        },
                        result = {
                            Type = "ReputationLoss",
                        },
                    },
                    {
                        formats = {
                            "FACTION_STANDING_DECREASED_GENERIC_ACCOUNT_WIDE",
                        },
                        tokens = {
                            Tokens.NameString,
                        },
                        result = {
                            Type = "ReputationLossWarband",
                        },
                    },
                    {
                        formats = {
                            "FACTION_STANDING_DECREASED_GENERIC",
                        },
                        tokens = {
                            Tokens.NameString,
                        },
                        result = {
                            Type = "ReputationLoss",
                        },
                    },
                },
            }
        )

    end

    -- Honor
    do

        ---@alias LootFeedMessageFormatSimpleParserResultHonorKeys "Name"|"NameExtra"|"Value"

        ---@alias LootFeedMessageFormatSimpleParserResultHonorTypes "Honor"

        ---@class LootFeedMessageFormatSimpleParserResultHonor
        ---@field public Type LootFeedMessageFormatSimpleParserResultHonorTypes
        ---@field public Name? string If provided, this is the name of the player that granted us Honor.
        ---@field public NameExtra? string If provided, this is the rank of the player that granted us Honor.
        ---@field public Value number The amount of Honor earned.

        ---@class LootFeedMessageFormatSimpleParserResultHonorArgs : LootFeedMessageFormatSimpleParserResultHonor
        ---@field public Value? number

        ---@class LootFeedMessageFormatHonor : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultHonorArgs

        AppendMessages(
            {
                group = LootFeedMessageGroup.Honor,
                events = {
                    "CHAT_MSG_COMBAT_HONOR_GAIN",
                },
                ---@type LootFeedMessageFormatSimpleParserResultHonorArgs
                result = {
                    Type = "Honor",
                },
            },
            {
                ---@type LootFeedMessageFormatHonor[]
                formats = {
                    {
                        formats = {
                            "COMBATLOG_HONORGAIN",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.NameExtraString,
                            Tokens.ValueNumber,
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_HONORGAIN_NO_RANK",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_HONORAWARD",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                        },
                    },
                },
            }
        )

    end

    -- Experience
    do

        ---@alias LootFeedMessageFormatSimpleParserResultExperienceKeys "Name"|"Value"|"ValueExtra"|"Bonus"|"BonusExtra"

        ---@alias LootFeedMessageFormatSimpleParserResultExperienceTypes
        ---|"Experience"
        ---|"ExperienceLoss"
        ---|"ExperienceBonusBonus"
        ---|"ExperienceBonusPenalty"
        ---|"ExperiencePenaltyBonus"
        ---|"ExperiencePenaltyPenalty"
        ---|"ExperienceBonus"
        ---|"ExperiencePenalty"

        ---@class LootFeedMessageFormatSimpleParserResultExperience
        ---@field public Type LootFeedMessageFormatSimpleParserResultExperienceTypes
        ---@field public Name? string If provided, the name of the NPC that died and granted XP.
        ---@field public Value number The amount of XP.
        ---@field public ValueExtra? number If provided, this is bonus XP.
        ---@field public Bonus? string If provided, this is bonus XP.
        ---@field public BonusExtra? string If provided, this is bonus XP.

        ---@class LootFeedMessageFormatSimpleParserResultExperienceArgs : LootFeedMessageFormatSimpleParserResultExperience
        ---@field public Value? number

        ---@class LootFeedMessageFormatExperience : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultExperienceArgs

        AppendMessages(
            {
                group = LootFeedMessageGroup.Experience,
                ---@type LootFeedMessageFormatSimpleParserResultExperienceArgs
                result = {
                    Type = "Experience",
                },
            },
            {
                events = {
                    "CHAT_MSG_SYSTEM",
                },
                ---@type LootFeedMessageFormatExperience[]
                formats = {
                    {
                        formats = {
                            "ERR_ZONE_EXPLORED_XP",
                        },
                        tokens = {
                            Tokens.ZoneString,
                            Tokens.ValueNumber,
                        },
                    },
                },
            },
            {
                events = {
                    "CHAT_MSG_COMBAT_XP_GAIN",
                },
                ---@type LootFeedMessageFormatExperience[]
                formats = {
                    {
                        formats = {
                            "COMBATLOG_XPGAIN_EXHAUSTION1_RAID",
                            "COMBATLOG_XPGAIN_EXHAUSTION2_RAID",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                            Tokens.BonusString,
                            Tokens.ValueExtraString,
                            Tokens.BonusExtraNumber,
                        },
                        result = {
                            Type = "ExperienceBonusPenalty",
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_XPGAIN_EXHAUSTION4_RAID",
                            "COMBATLOG_XPGAIN_EXHAUSTION5_RAID",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                            Tokens.BonusString,
                            Tokens.ValueExtraString,
                            Tokens.BonusExtraNumber,
                        },
                        result = {
                            Type = "ExperiencePenaltyPenalty",
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_XPGAIN_EXHAUSTION1_GROUP",
                            "COMBATLOG_XPGAIN_EXHAUSTION2_GROUP",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                            Tokens.BonusString,
                            Tokens.ValueExtraString,
                            Tokens.BonusExtraNumber,
                        },
                        result = {
                            Type = "ExperienceBonusBonus",
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_XPGAIN_EXHAUSTION4_GROUP",
                            "COMBATLOG_XPGAIN_EXHAUSTION5_GROUP",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                            Tokens.BonusString,
                            Tokens.ValueExtraString,
                            Tokens.BonusExtraNumber,
                        },
                        result = {
                            Type = "ExperiencePenaltyBonus",
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_XPGAIN_EXHAUSTION1",
                            "COMBATLOG_XPGAIN_EXHAUSTION2",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                            Tokens.BonusString,
                            Tokens.BonusExtraString,
                        },
                        result =  {
                            Type = "ExperienceBonus",
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_XPGAIN_EXHAUSTION4",
                            "COMBATLOG_XPGAIN_EXHAUSTION5",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                            Tokens.BonusString,
                            Tokens.BonusExtraString,
                        },
                        result =  {
                            Type = "ExperiencePenalty",
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_XPGAIN_FIRSTPERSON_RAID",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                            Tokens.ValueExtraNumber,
                        },
                        result = {
                            Type = "ExperiencePenalty",
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                            Tokens.ValueExtraNumber,
                        },
                        result = {
                            Type = "ExperienceBonus",
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_XPGAIN_FIRSTPERSON",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_RAID",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.ValueExtraNumber,
                        },
                        result = {
                            Type = "ExperiencePenalty",
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.ValueExtraNumber,
                        },
                        result = {
                            Type = "ExperienceBonus",
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_XPGAIN_QUEST",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.BonusString,
                            Tokens.BonusExtraString,
                        },
                        result = {
                            Type = "ExperienceBonus",
                        },
                    },
                    {
                        formats = {
                            "COMBATLOG_XPLOSS_FIRSTPERSON_UNNAMED",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                        },
                        result = {
                            Type = "ExperienceLoss",
                        },
                    },
                },
            }
        )

    end

    -- Guild Experience
    --[[
    do

        ---@alias LootFeedMessageFormatSimpleParserResultGuildExperienceKeys "Value"

        ---@alias LootFeedMessageFormatSimpleParserResultGuildExperienceTypes "GuildExperience"

        ---@class LootFeedMessageFormatSimpleParserResultGuildExperience
        ---@field public Type LootFeedMessageFormatSimpleParserResultGuildExperienceTypes
        ---@field public Value number The amount of guild XP earned.

        ---@class LootFeedMessageFormatSimpleParserResultGuildExperienceArgs : LootFeedMessageFormatSimpleParserResultGuildExperience
        ---@field public Value? number

        ---@class LootFeedMessageFormatGuildExperience : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultGuildExperienceArgs

        AppendMessages(
            {
                group = LootFeedMessageGroup.GuildExperience,
                events = {
                    "CHAT_MSG_COMBAT_GUILD_XP_GAIN",
                },
                ---@type LootFeedMessageFormatSimpleParserResultGuildExperienceArgs
                result = {
                    Type = "GuildExperience",
                },
            },
            {
                ---@type LootFeedMessageFormatGuildExperience[]
                formats = {
                    {
                        formats = {
                            "COMBATLOG_GUILD_XPGAIN",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                        },
                    },
                },
            }
        )

    end
    --]]

    -- Follower Experience
    do

        ---@alias LootFeedMessageFormatSimpleParserResultFollowerExperienceKeys "Name"|"Value"

        ---@alias LootFeedMessageFormatSimpleParserResultFollowerExperienceTypes "FollowerExperience"

        ---@class LootFeedMessageFormatSimpleParserResultFollowerExperience
        ---@field public Type LootFeedMessageFormatSimpleParserResultFollowerExperienceTypes
        ---@field public Name string The name of the follower earning the XP.
        ---@field public Value number The amount of XP earned.

        ---@class LootFeedMessageFormatSimpleParserResultFollowerExperienceArgs : LootFeedMessageFormatSimpleParserResultFollowerExperience
        ---@field public Name? string
        ---@field public Value? number

        ---@class LootFeedMessageFormatFollowerExperience : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultFollowerExperienceArgs

        AppendMessages(
            {
                group = LootFeedMessageGroup.FollowerExperience,
                events = {
                    "CHAT_MSG_SYSTEM",
                    "CHAT_MSG_COMBAT_XP_GAIN",
                },
                ---@type LootFeedMessageFormatSimpleParserResultFollowerExperienceArgs
                result = {
                    Type = "FollowerExperience",
                },
            },
            {
                ---@type LootFeedMessageFormatFollowerExperience[]
                formats = {
                    {
                        formats = {
                            "GARRISON_FOLLOWER_XP_ADDED_ZONE_SUPPORT",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                        },
                    },
                },
            }
        )

        -- TODO: globalstrings doesn't contain this particular string, so the solution is to provide
        -- the translations with hack, until, hopefully, one day, the string is added to the globalstrings table
        local Locale = GetLocale()
        local FollowerExperience = "%s has gained %d experience."
        if Locale == "deDE" then
            FollowerExperience = "%s hat %d Erfahrung erhalten."
        elseif Locale == "esES" then
            FollowerExperience = "%s ha obtenido %d p. de experiencia."
        elseif Locale == "esMX" then
            FollowerExperience = "%s ha obtenido %d puntos de experiencia."
        elseif Locale == "frFR" then
            FollowerExperience = "%s a obtenu %d points d’expérience."
        elseif Locale == "itIT" then
            FollowerExperience = "%s ha ottenuto %d punti esperienza."
        elseif Locale == "koKR" then
            FollowerExperience = "%s|1이;가; %d 경험을 획득했습니다."
        elseif Locale == "ptBR" then
            FollowerExperience = "%s ganhou %d pontos de experiência."
        elseif Locale == "ruRU" then
            FollowerExperience = "%s получает %d ед. опыта."
        elseif Locale == "zhCN" then
            FollowerExperience = "%s获得了%d点经验值。"
        elseif Locale == "zhTW" then
            FollowerExperience = "%s獲得%d點經驗值。"
        end
        _G.LOOTFEED_DELVE_EXPERIENCE_GAIN_POLYFILL = FollowerExperience

        AppendMessages(
            {
                group = LootFeedMessageGroup.FollowerExperience,
                events = {
                    "CHAT_MSG_COMBAT_FACTION_CHANGE",
                },
                ---@type LootFeedMessageFormatSimpleParserResultFollowerExperienceArgs
                result = {
                    Type = "FollowerExperience",
                },
            },
            {
                ---@type LootFeedMessageFormatFollowerExperience[]
                formats = {
                    {
                        formats = {
                            "LOOTFEED_DELVE_EXPERIENCE_GAIN_POLYFILL",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueNumber,
                        },
                    },
                },
            }
        )

    end

    -- Currency
    do

        ---@alias LootFeedMessageFormatSimpleParserResultCurrencyKeys "Link"|"Value"

        ---@alias LootFeedMessageFormatSimpleParserResultCurrencyTypes "Currency"|"CurrencyWarband"|"CurrencyWarbandOverflow"

        ---@class LootFeedMessageFormatSimpleParserResultCurrency
        ---@field public Type LootFeedMessageFormatSimpleParserResultCurrencyTypes
        ---@field public Link string The currency link.
        ---@field public Value? number If provided, the number of items received.

        ---@class LootFeedMessageFormatSimpleParserResultCurrencyArgs : LootFeedMessageFormatSimpleParserResultCurrency
        ---@field public Link? string

        ---@class LootFeedMessageFormatCurrency : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultCurrencyArgs

        AppendMessages(
            {
                group = LootFeedMessageGroup.Currency,
                events = {
                    "CHAT_MSG_CURRENCY",
                },
                ---@type LootFeedMessageFormatSimpleParserResultCurrencyArgs
                result = {
                    Type = "Currency",
                },
            },
            {
                ---@type LootFeedMessageFormatCurrency[]
                formats = {
                    {
                        formats = {
                            "ACCOUNT_CURRENCY_GAINED_MULTIPLE_OVERFLOW",
                        },
                        tokens = {
                            Tokens.Link,
                            Tokens.ValueNumber,
                            Tokens.ValueString,
                        },
                        result = {
                            Type = "CurrencyWarbandOverflow",
                        },
                    },
                    {
                        formats = {
                            "ACCOUNT_CURRENCY_GAINED_MULTIPLE_BONUS",
                            "ACCOUNT_CURRENCY_GAINED_MULTIPLE",
                        },
                        tokens = {
                            Tokens.Link,
                            Tokens.ValueNumber,
                        },
                        result = {
                            Type = "CurrencyWarband",
                        },
                    },
                    {
                        formats = {
                            "CURRENCY_GAINED_MULTIPLE_BONUS",
                            "CURRENCY_GAINED_MULTIPLE",
                            "LOOT_CURRENCY_REFUND",
                        },
                        tokens = {
                            Tokens.Link,
                            Tokens.ValueNumber,
                        },
                    },
                    {
                        formats = {
                            "CURRENCY_GAINED",
                        },
                        tokens = {
                            Tokens.Link,
                        },
                    },
                },
            }
        )

    end

    -- Money
    do

        ---@alias LootFeedMessageFormatSimpleParserResultMoneyKeys "Name"|"Value"|"ValueExtra"

        ---@alias LootFeedMessageFormatSimpleParserResultMoneyTypes "Money"

        ---@class LootFeedMessageFormatSimpleParserResultMoney
        ---@field public Type LootFeedMessageFormatSimpleParserResultMoneyTypes
        ---@field public Name? string If provided, this player earned the gold.
        ---@field public Value number The amount of money in copper.
        ---@field public ValueExtra? number If provided, the gold sent to the guild bank.

        ---@class LootFeedMessageFormatSimpleParserResultMoneyArgs : LootFeedMessageFormatSimpleParserResultMoney
        ---@field public Value? number

        ---@class LootFeedMessageFormatMoney : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultMoneyArgs

        AppendMessages(
            {
                group = LootFeedMessageGroup.Money,
                events = {
                    "CHAT_MSG_MONEY",
                },
                ---@type LootFeedMessageFormatSimpleParserResultMoneyArgs
                result = {
                    Type = "Money",
                },
            },
            {
                ---@type LootFeedMessageFormatMoney[]
                formats = {
                    {
                        formats = {
                            "YOU_LOOT_MONEY_GUILD",
                            "LOOT_MONEY_SPLIT_GUILD",
                        },
                        tokens = {
                            Tokens.ValueMoney,
                            Tokens.ValueExtraMoney,
                        },
                    },
                    {
                        formats = {
                            "YOU_LOOT_MONEY",
                            "LOOT_MONEY_SPLIT",
                            "LOOT_MONEY_REFUND",
                        },
                        tokens = {
                            Tokens.ValueMoney,
                        },
                    },
                    {
                        formats = {
                            "LOOT_MONEY",
                        },
                        tokens = {
                            Tokens.NameString,
                            Tokens.ValueMoney,
                        },
                    },
                },
            }
        )

    end

    -- Loot
    do

        ---@alias LootFeedMessageFormatSimpleParserResultLootKeys "Name"|"Link"|"Value"

        ---@alias LootFeedMessageFormatSimpleParserResultLootTypes "Loot"

        ---@class LootFeedMessageFormatSimpleParserResultLoot
        ---@field public Type LootFeedMessageFormatSimpleParserResultLootTypes
        ---@field public Name? string If provided, the name of the player looting.
        ---@field public Link string The item link.
        ---@field public Value? number If provided, the number of items looted.

        ---@class LootFeedMessageFormatSimpleParserResultLootArgs : LootFeedMessageFormatSimpleParserResultLoot
        ---@field public Link? string

        ---@class LootFeedMessageFormatLoot : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultLootArgs

        AppendMessages(
            {
                group = LootFeedMessageGroup.Loot,
                events = {
                    "CHAT_MSG_LOOT",
                },
                ---@type LootFeedMessageFormatSimpleParserResultLootArgs
                result = {
                    Type = "Loot",
                },
            },
            {
                ---@type LootFeedMessageFormatLoot[]
                formats = {
                    {
                        formats = {
                            "CREATED_ITEM_MULTIPLE",
                        },
                        tokens = {
                            Tokens.NameTarget,
                            Tokens.Link,
                            Tokens.ValueNumber,
                        },
                    },
                    {
                        formats = {
                            "CREATED_ITEM",
                        },
                        tokens = {
                            Tokens.NameTarget,
                            Tokens.Link,
                        },
                    },
                    {
                        formats = {
                            "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
                            "LOOT_ITEM_SELF_MULTIPLE",
                            "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
                            "LOOT_ITEM_CREATED_SELF_MULTIPLE",
                            "LOOT_ITEM_REFUND_MULTIPLE",
                        },
                        tokens = {
                            Tokens.Link,
                            Tokens.ValueNumber,
                        },
                    },
                    {
                        formats = {
                            "LOOT_ITEM_BONUS_ROLL_SELF",
                            "LOOT_ITEM_SELF",
                            "LOOT_ITEM_PUSHED_SELF",
                            "LOOT_ITEM_CREATED_SELF",
                            "LOOT_ITEM_REFUND",
                        },
                        tokens = {
                            Tokens.Link,
                        },
                    },
                    {
                        formats = {
                            "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
                            "LOOT_ITEM_SELF_MULTIPLE",
                            "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
                            "LOOT_ITEM_CREATED_SELF_MULTIPLE",
                            "LOOT_ITEM_REFUND_MULTIPLE",
                        },
                        tokens = {
                            Tokens.Link,
                            Tokens.ValueNumber,
                        },
                    },
                    {
                        formats = {
                            "LOOT_ITEM_BONUS_ROLL_SELF",
                            "LOOT_ITEM_SELF",
                            "LOOT_ITEM_PUSHED_SELF",
                            "LOOT_ITEM_CREATED_SELF",
                            "LOOT_ITEM_REFUND",
                        },
                        tokens = {
                            Tokens.Link,
                        },
                    },
                    {
                        formats = {
                            "LOOT_ITEM_BONUS_ROLL_MULTIPLE",
                            "LOOT_ITEM_MULTIPLE",
                            "LOOT_ITEM_PUSHED_MULTIPLE",
                        },
                        tokens = {
                            Tokens.NameTarget,
                            Tokens.Link,
                            Tokens.ValueNumber,
                        },
                    },
                    {
                        formats = {
                            "LOOT_ITEM_BONUS_ROLL",
                            "LOOT_ITEM",
                            "LOOT_ITEM_PUSHED",
                        },
                        tokens = {
                            Tokens.NameTarget,
                            Tokens.Link,
                        },
                    },
                },
            }
        )

    end

    -- Loot Roll
    do

        ---@alias LootFeedMessageFormatSimpleParserResultLootRollKeys "Name"|"Link"|"Value"|"ValueExtra"

        ---@alias LootFeedMessageFormatSimpleParserResultLootRollTypes
        ---|"FallbackRoll"
        ---|"AllPass"
        ---|"YouPass"
        ---|"Pass"
        ---|"YouDisenchant"
        ---|"Disenchant"
        ---|"YouGreed"
        ---|"Greed"
        ---|"YouNeed"
        ---|"Need"
        ---|"YouTransmog"
        ---|"DisenchantRoll"
        ---|"GreedRoll"
        ---|"NeedRoll"
        ---|"TransmogRoll"
        ---|"DisenchantCredit"
        ---|"YouDisenchantResult"
        ---|"DisenchantResult"
        ---|"YouGreedResult"
        ---|"GreedResult"
        ---|"YouNeedResult"
        ---|"NeedResult"
        ---|"YouTransmogResult"
        ---|"TransmogResult"
        ---|"IneligibleResult"
        ---|"LostResult"
        ---|"YouWinnerResult"
        ---|"WinnerResult"
        ---|"StartRoll"

        ---@class LootFeedMessageFormatSimpleParserResultLootRoll
        ---@field public Type LootFeedMessageFormatSimpleParserResultLootRollTypes
        ---@field public Name? string If provided, the name of the player looting.
        ---@field public Link string The item link.
        ---@field public Value? number If provided, the loot history ID.
        ---@field public ValueExtra? number If provided, the loot history ID.

        ---@class LootFeedMessageFormatSimpleParserResultLootRollArgs : LootFeedMessageFormatSimpleParserResultLootRoll
        ---@field public Link? string

        ---@class LootFeedMessageFormatSimpleParserResultLootRoll_LootRollInfo
        ---@field public Type "AllPass"
        ---@field public Link string The item link.
        ---@field public Value number Loot history ID.
        ---@field public Name? string The name of the player. Relevant for `DisenchantCredit` and `IneligibleResult`.

        ---@class LootFeedMessageFormatSimpleParserResultLootRoll_LootRollYouDecide
        ---@field public Type "YouPass"|"YouDisenchant"|"YouGreed"|"YouNeed"|"YouTransmog"
        ---@field public Link string The item link.
        ---@field public Value number Loot history ID.
        ---@field public ValueExtra? number Loot history ID.

        ---@class LootFeedMessageFormatSimpleParserResultLootRoll_LootRollDecide
        ---@field public Type "Pass"|"Disenchant"|"Greed"|"Need"
        ---@field public Link string The item link.
        ---@field public Name string The name of the player.

        ---@class LootFeedMessageFormatSimpleParserResultLootRoll_LootRollRolled
        ---@field public Type "DisenchantRoll"|"GreedRoll"|"NeedRoll"|"TransmogRoll"
        ---@field public Link string The item link.
        ---@field public Name string The name of the player.
        ---@field public Value number The number rolled.

        ---@class LootFeedMessageFormatSimpleParserResultLootRoll_LootRollYouResult
        ---@field public Type "YouDisenchantResult"|"YouGreedResult"|"YouNeedResult"|"YouTransmogResult"
        ---@field public Link string The item link.
        ---@field public Value number Loot history ID.
        ---@field public ValueExtra number The number rolled.

        -- Note that `YouWinnerResult` and `WinnerResult` only have `Link` and `Name` assigned.
        ---@class LootFeedMessageFormatSimpleParserResultLootRoll_LootRollResult
        ---@field public Type "DisenchantResult"|"GreedResult"|"NeedResult"|"TransmogResult"|"LostResult"|"YouWinnerResult"|"WinnerResult"
        ---@field public Link string The item link.
        ---@field public Name string The name of the player.
        ---@field public Value number Loot history ID.
        ---@field public ValueExtra number The number rolled.
        ---@field public NameExtra? string The roll type like `Need`, `Greed`, or `Transmog`.

        ---@class LootFeedMessageFormatLootRoll : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultLootRollArgs

        AppendMessages(
            {
                group = LootFeedMessageGroup.LootRoll,
                events = {
                    "CHAT_MSG_LOOT",
                },
                ---@type LootFeedMessageFormatSimpleParserResultLootRollArgs
                result = {
                    Type = "FallbackRoll",
                },
                defaultDebounce = 0,
            },
            {
                group = LootFeedMessageGroup.LootRollInfo,
                ---@type LootFeedMessageFormatLootRoll[]
                formats = {
                    {
                        formats = {
                            "LOOT_ROLL_ALL_PASSED",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.Link,
                        },
                        result = {
                            Type = "AllPass",
                        },
                    },
                },
            },
            {
                group = LootFeedMessageGroup.LootRollYouDecide,
                ---@type LootFeedMessageFormatLootRoll[]
                formats = {
                    {
                        formats = {
                            "LOOT_ROLL_PASSED_SELF_AUTO",
                            "LOOT_ROLL_PASSED_SELF",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.Link,
                            Tokens.ValueExtraNumber,
                        },
                        result = {
                            Type = "YouPass",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_DISENCHANT_SELF",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.Link,
                        },
                        result = {
                            Type = "YouDisenchant",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_GREED_SELF",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.Link,
                            Tokens.ValueExtraNumber,
                        },
                        result = {
                            Type = "YouGreed",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_NEED_SELF",
                            "LOOT_ROLL_NEED_SELF_OFF_SPEC",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.Link,
                            Tokens.ValueExtraNumber,
                        },
                        result = {
                            Type = "YouNeed",
                        },
                    },
                },
            },
            {
                group = LootFeedMessageGroup.LootRollDecide,
                ---@type LootFeedMessageFormatLootRoll[]
                formats = {
                    {
                        formats = {
                            "LOOT_ROLL_PASSED_AUTO",
                            "LOOT_ROLL_PASSED_AUTO_FEMALE",
                            "LOOT_ROLL_PASSED",
                        },
                        tokens = {
                            Tokens.NameTarget,
                            Tokens.Link,
                        },
                        result = {
                            Type = "Pass",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_DISENCHANT",
                        },
                        tokens = {
                            Tokens.NameTarget,
                            Tokens.Link,
                        },
                        result = {
                            Type = "Disenchant",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_GREED",
                        },
                        tokens = {
                            Tokens.NameTarget,
                            Tokens.Link,
                        },
                        result = {
                            Type = "Greed",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_NEED",
                        },
                        tokens = {
                            Tokens.NameTarget,
                            Tokens.Link,
                        },
                        result = {
                            Type = "Need",
                        },
                    },
                },
            },
            {
                group = LootFeedMessageGroup.LootRollRolled,
                ---@type LootFeedMessageFormatLootRoll[]
                formats = {
                    {
                        formats = {
                            "LOOT_ROLL_ROLLED_DE",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.Link,
                            Tokens.NameTarget,
                        },
                        result = {
                            Type = "DisenchantRoll",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_ROLLED_GREED",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.Link,
                            Tokens.NameTarget,
                        },
                        result = {
                            Type = "GreedRoll",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS",
                            "LOOT_ROLL_ROLLED_NEED",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.Link,
                            Tokens.NameTarget,
                        },
                        result = {
                            Type = "NeedRoll",
                        },
                    },
                },
            },
            {
                group = LootFeedMessageGroup.LootRollYouResult,
                ---@type LootFeedMessageFormatLootRoll[]
                formats = {
                    {
                        formats = {
                            "LOOT_ROLL_YOU_WON_NO_SPAM_DE",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.ValueExtraNumber,
                            Tokens.Link,
                        },
                        result = {
                            Type = "YouDisenchantResult",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_YOU_WON_NO_SPAM_GREED",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.ValueExtraNumber,
                            Tokens.Link,
                        },
                        result = {
                            Type = "YouGreedResult",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_YOU_WON_NO_SPAM_NEED",
                            "LOOT_ROLL_YOU_WON_NO_SPAM_NEED_OFF_SPEC",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.ValueExtraNumber,
                            Tokens.Link,
                        },
                        result = {
                            Type = "YouNeedResult",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_YOU_WON_NO_SPAM_TRANSMOG",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.ValueExtraNumber,
                            Tokens.Link,
                        },
                        result = {
                            Type = "YouTransmogResult",
                        },
                    },
                },
            },
            {
                group = LootFeedMessageGroup.LootRollResult,
                ---@type LootFeedMessageFormatLootRoll[]
                formats = {
                    {
                        formats = {
                            "LOOT_ROLL_WON_NO_SPAM_DE",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.NameTarget,
                            Tokens.ValueExtraNumber,
                            Tokens.Link,
                        },
                        result = {
                            Type = "DisenchantResult",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_WON_NO_SPAM_GREED",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.NameTarget,
                            Tokens.ValueExtraNumber,
                            Tokens.Link,
                        },
                        result = {
                            Type = "GreedResult",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_WON_NO_SPAM_NEED",
                            "LOOT_ROLL_WON_NO_SPAM_NEED_OFF_SPEC",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.NameTarget,
                            Tokens.ValueExtraNumber,
                            Tokens.Link,
                        },
                        result = {
                            Type = "NeedResult",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_WON_NO_SPAM_TRANSMOGRIFICATION",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.NameTarget,
                            Tokens.ValueExtraNumber,
                            Tokens.Link,
                        },
                        result = {
                            Type = "TransmogResult",
                        },
                    },
                },
            },
            {
                group = LootFeedMessageGroup.LootRollResult,
                ---@type LootFeedMessageFormatLootRoll[]
                formats = {
                    {
                        formats = {
                            "LOOT_ROLL_LOST_ROLL",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.NameExtraString,
                            Tokens.ValueExtraNumber,
                            Tokens.Link,
                        },
                        result = {
                            Type = "LostResult",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_YOU_WON",
                        },
                        tokens = {
                            Tokens.Link,
                        },
                        result = {
                            Type = "YouWinnerResult",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ROLL_WON",
                        },
                        tokens = {
                            Tokens.NameTarget,
                            Tokens.Link,
                        },
                        result = {
                            Type = "WinnerResult",
                        },
                    },
                },
            },
            {
                group = LootFeedMessageGroup.LootRollInfo,
                ---@type LootFeedMessageFormatLootRoll[]
                formats = {
                    {
                        formats = {
                            "LOOT_ROLL_STARTED",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                            Tokens.Link,
                        },
                        result = {
                            Type = "StartRoll",
                        },
                    },
                    {
                        formats = {
                            "LOOT_DISENCHANT_CREDIT",
                        },
                        tokens = {
                            Tokens.Link,
                            Tokens.NameTarget,
                        },
                        result = {
                            Type = "DisenchantCredit",
                        },
                    },
                    {
                        formats = {
                            "LOOT_ITEM_WHILE_PLAYER_INELIGIBLE",
                        },
                        tokens = {
                            Tokens.NameTarget,
                            Tokens.Link,
                        },
                        result = {
                            Type = "IneligibleResult",
                        },
                    },
                },
            }
        )

    end

    -- Item Changed
    do

        ---@alias LootFeedMessageFormatSimpleParserResultItemChangedKeys "Link"|"LinkExtra"

        ---@alias LootFeedMessageFormatSimpleParserResultItemChangedTypes "ItemChanged"|"YouItemChanged"

        ---@class LootFeedMessageFormatSimpleParserResultItemChanged
        ---@field public Type LootFeedMessageFormatSimpleParserResultItemChangedTypes
        ---@field public Name? string The player name changing their item.
        ---@field public Link string The original item link.
        ---@field public LinkExtra string The new item link.

        ---@class LootFeedMessageFormatSimpleParserResultItemChangedArgs : LootFeedMessageFormatSimpleParserResultItemChanged
        ---@field public Link? string
        ---@field public LinkExtra? string

        ---@class LootFeedMessageFormatItemChanged : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultItemChangedArgs

        AppendMessages(
            {
                group = LootFeedMessageGroup.ItemChanged,
                events = {
                    "CHAT_MSG_LOOT",
                },
                ---@type LootFeedMessageFormatSimpleParserResultItemChangedArgs
                result = {
                    Type = "ItemChanged",
                },
            },
            {
                ---@type LootFeedMessageFormatItemChanged[]
                formats = {
                    {
                        formats = {
                            "CHANGED_OWN_ITEM",
                        },
                        tokens = {
                            Tokens.Link,
                            Tokens.LinkExtra,
                        },
                        result = {
                            Type = "YouItemChanged",
                        },
                    },
                },
            },
            {
                ---@type LootFeedMessageFormatItemChanged[]
                formats = {
                    {
                        formats = {
                            "CHANGED_ITEM",
                        },
                        tokens = {
                            Tokens.NameTarget,
                            Tokens.Link,
                            Tokens.LinkExtra,
                        },
                        result = {
                            Type = "ItemChanged",
                        },
                    },
                },
            }
        )

    end

    -- Anima Power
    do

        ---@alias LootFeedMessageFormatSimpleParserResultAnimaPowerKeys "Link"

        ---@alias LootFeedMessageFormatSimpleParserResultAnimaPowerTypes "AnimaPower"

        ---@class LootFeedMessageFormatSimpleParserResultAnimaPower
        ---@field public Type LootFeedMessageFormatSimpleParserResultAnimaPowerTypes
        ---@field public Name string? The person gaining the power.
        ---@field public Link string The anima power link.

        ---@class LootFeedMessageFormatSimpleParserResultAnimaPowerArgs : LootFeedMessageFormatSimpleParserResultAnimaPower
        ---@field public Name? string
        ---@field public Link? string

        ---@class LootFeedMessageFormatAnimaPower : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultAnimaPowerArgs

        AppendMessages(
            {
                group = LootFeedMessageGroup.AnimaPower,
                events = {
                    "CHAT_MSG_LOOT",
                },
                ---@type LootFeedMessageFormatSimpleParserResultAnimaPowerArgs
                result = {
                    Type = "AnimaPower",
                },
            },
            {
                formats = {
                    {
                        formats = {
                            "GAIN_MAW_POWER_SELF",
                        },
                        tokens = {
                            Tokens.Link,
                        },
                    },
                },
            },
            {
                formats = {
                    {
                        formats = {
                            "GAIN_MAW_POWER",
                        },
                        tokens = {
                            Tokens.NameTarget,
                            Tokens.Link,
                        },
                    },
                },
            }
        )

    end

    -- Artifact Power
    do

        ---@alias LootFeedMessageFormatSimpleParserResultArtifactPowerKeys "Link"|"Value"

        ---@alias LootFeedMessageFormatSimpleParserResultArtifactPowerTypes "ArtifactPower"

        ---@class LootFeedMessageFormatSimpleParserResultArtifactPower
        ---@field public Type LootFeedMessageFormatSimpleParserResultArtifactPowerTypes
        ---@field public Link string The artifact item link.
        ---@field public Value number The amount of power gained.

        ---@class LootFeedMessageFormatSimpleParserResultArtifactPowerArgs : LootFeedMessageFormatSimpleParserResultArtifactPower
        ---@field public Link? string
        ---@field public Value? number

        ---@class LootFeedMessageFormatArtifactPower : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultArtifactPowerArgs

        AppendMessages(
            {
                group = LootFeedMessageGroup.ArtifactPower,
                events = {
                    "CHAT_MSG_SYSTEM",
                },
                ---@type LootFeedMessageFormatSimpleParserResultArtifactPowerArgs
                result = {
                    Type = "ArtifactPower",
                },
            },
            {
                ---@type LootFeedMessageFormatArtifactPower[]
                formats = {
                    {
                        formats = {
                            "ARTIFACT_XP_GAIN",
                            "AZERITE_XP_GAIN",
                        },
                        tokens = {
                            Tokens.Link,
                            Tokens.ValueNumber,
                        },
                    },
                },
            }
        )

    end

    -- Transmogrification
    do

        ---@alias LootFeedMessageFormatSimpleParserResultTransmogrificationKeys "Link"|"Value"

        ---@alias LootFeedMessageFormatSimpleParserResultTransmogrificationTypes "Transmogrification"|"TransmogrificationLoss"

        ---@class LootFeedMessageFormatSimpleParserResultTransmogrification
        ---@field public Type LootFeedMessageFormatSimpleParserResultTransmogrificationTypes
        ---@field public Link string

        ---@class LootFeedMessageFormatSimpleParserResultTransmogrificationArgs : LootFeedMessageFormatSimpleParserResultTransmogrification
        ---@field public Link? string

        ---@class LootFeedMessageFormatTransmogrification : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultTransmogrificationArgs

        AppendMessages(
            {
                group = LootFeedMessageGroup.Transmogrification,
                events = {
                    "CHAT_MSG_SYSTEM",
                },
                ---@type LootFeedMessageFormatSimpleParserResultTransmogrificationArgs
                result = {
                    Type = "Transmogrification",
                },
                defaultDebounce = 0,
            },
            {
                ---@type LootFeedMessageFormatTransmogrification[]
                formats = {
                    {
                        formats = {
                            "ERR_LEARN_TRANSMOG_S",
                        },
                        tokens = {
                            Tokens.Link,
                        },
                    },
                    {
                        formats = {
                            "ERR_REVOKE_TRANSMOG_S",
                        },
                        tokens = {
                            Tokens.Link,
                        },
                        result = {
                            Type = "TransmogrificationLoss",
                        },
                    },
                },
            }
        )

    end

    -- Ignore
    do

        ---@alias LootFeedMessageFormatSimpleParserResultIgnoreKeys "Value"|"Link"

        ---@alias LootFeedMessageFormatSimpleParserResultIgnoreTypes "Ignore"|"IgnoreExperience"|"IgnoreMoney"|"IgnoreArtifactPower"

        ---@class LootFeedMessageFormatSimpleParserResultIgnore
        ---@field public Type LootFeedMessageFormatSimpleParserResultIgnoreTypes
        ---@field public Value? number
        ---@field public Link? string

        ---@class LootFeedMessageFormatSimpleParserResultIgnoreArgs : LootFeedMessageFormatSimpleParserResultIgnore

        ---@class LootFeedMessageFormatIgnore : LootFeedMessageFormat
        ---@field public result? LootFeedMessageFormatSimpleParserResultIgnoreArgs

        ---@type LootFeedMessageFormatSimpleParser
        ---@param result LootFeedMessageFormatSimpleParserResultIgnore
        local function CustomItemParser(result)
            if not result.Link then
                return
            end
            local currencyInfo = C_CurrencyInfo.GetCurrencyInfoFromLink(result.Link)
            if not currencyInfo then
                return
            end
            if currencyInfo.quantity == 0 and currencyInfo.maxQuantity == 0 then
                result.Type = "IgnoreArtifactPower"
            end
        end

        AppendMessages(
            {
                group = LootFeedMessageGroup.Ignore,
                events = {
                    "CHAT_MSG_SYSTEM",
                },
                ---@type LootFeedMessageFormatSimpleParserResultIgnoreArgs
                result = {
                    Type = "Ignore",
                },
            },
            {
                ---@type LootFeedMessageFormatIgnore[]
                formats = {
                    {
                        formats = {
                            "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
                        },
                        tokens = {
                            Tokens.Link,
                            Tokens.ValueNumber,
                        },
                        parser = CustomItemParser,
                    },
                    {
                        formats = {
                            "LOOT_ITEM_PUSHED_SELF",
                        },
                        tokens = {
                            Tokens.Link,
                        },
                        parser = CustomItemParser,
                    },
                    {
                        formats = {
                            "ERR_QUEST_REWARD_EXP_I",
                        },
                        tokens = {
                            Tokens.ValueNumber,
                        },
                        result = {
                            Type = "IgnoreExperience",
                        },
                    },
                    {
                        formats = {
                            "ERR_QUEST_REWARD_MONEY_S",
                        },
                        tokens = {
                            Tokens.ValueMoney,
                        },
                        result = {
                            Type = "IgnoreMoney",
                        },
                    },
                },
            }
        )

    end

end

local ProcessTokensLinkPattern1 = "(|c[^|]-|H[^|]-|h[^|]-|h|r)"
local ProcessTokensLinkPattern2 = "(|H[^|]-|h[^|]-|h)"

---@param token LootFeedMessageFormatToken
---@param match? string
---@return string? key, any value
local function ProcessTokens(token, match)
    local tokenType = token.type

    if tokenType == LootFeedMessageFormatTokenType.Float
        or tokenType == LootFeedMessageFormatTokenType.Number then

        local value = ConvertToNumber(match)
        return token.field, value or token.fallbackValue

    elseif tokenType == LootFeedMessageFormatTokenType.Link
        or tokenType == LootFeedMessageFormatTokenType.String
        or tokenType == LootFeedMessageFormatTokenType.Target then

        local value ---@type string?

        if type(match) == "string" and match:len() > 0 then
            value = match
        end

        if value then
            if tokenType == LootFeedMessageFormatTokenType.Link then
                local temp ---@type string?
                if not temp then
                    temp = value:match(ProcessTokensLinkPattern1) ---@type string?
                end
                if not temp then
                    temp = value:match(ProcessTokensLinkPattern2) ---@type string?
                end
                if temp then
                    value = temp
                end
            -- elseif tokenType == LootFeedMessageFormatTokenType.Target then
            --     if not UnitExists(value) then
            --         value = nil
            --     end
            end
        end

        return token.field, value or token.fallbackValue

    elseif tokenType == LootFeedMessageFormatTokenType.Money then

        local value = ConvertToMoney(match)
        return token.field, value or token.fallbackValue

    end
end

---@param messageFormat LootFeedMessageFormat
---@param matches string[]
---@return LootFeedMessageFormatSimpleParserResults?
local function ProcessMatchedToResult(messageFormat, matches)
    local tokens = messageFormat.tokens
    local numTokens = #tokens
    local result ---@type LootFeedMessageFormatSimpleParserResults?
    if messageFormat.result then
        result = TableCopy(messageFormat.result)
    end
    for i = 1, numTokens do
        local token = tokens[i]
        local match = matches[i] ---@type string?
        local key, value = ProcessTokens(token, match)
        if key then
            if not result then
                result = { Type = "Fallback" }
            end
            result[key] = value
        end
    end
    local parser = messageFormat.parser
    if parser and result then
        local parserResult = parser(result)
        if parserResult ~= nil then
            if parserResult == false then
                result = nil
            else
                result = parserResult
            end
        end
    end
    return result
end

---@param event WowEvent
local function IsChatEventRelevant(event)
    for _, message in ipairs(MessagesCollection) do
        if TableContains(message.events, event) then
            return true
        end
    end
    return false
end

---@param event WowEvent
---@param text string
---@param playerName? string
---@param languageName? string
---@param channelName? string
---@param playerName2? string
---@param specialFlags? string
---@param zoneChannelID? number
---@param channelIndex? number
---@param channelBaseName? string
---@param languageID? number
---@param lineID? number
---@param guid? string
---@param bnSenderID? number
---@param isMobile? boolean
---@param isSubtitle? boolean
---@param hideSenderInLetterbox? boolean
---@param supressRaidIcons? boolean
---@return LootFeedMessageFormatSimpleParserResults?, LootFeedMessage
local function ProcessChatMessage(event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons)
    for _, message in ipairs(MessagesCollection) do
        if TableContains(message.events, event) then
            for _, messageFormat in ipairs(message.formats) do
                local messageFormatPatterns = messageFormat.patterns
                if messageFormatPatterns then
                    for _, messageFormatPattern in ipairs(messageFormatPatterns) do
                        local matches = {text:match(messageFormatPattern)} ---@type string[]
                        if matches[1] then
                            local result = ProcessMatchedToResult(messageFormat, matches)
                            if result then
                                return result, message
                            end
                        end
                    end
                end
            end
        end
    end
    return ---@diagnostic disable-line: missing-return-value
end

---@param message LootFeedMessage
---@param includeResult? boolean
---@return string? text, LootFeedMessageFormatSimpleParserResults? result
local function GenerateChatMessage(message, includeResult)
    local tests = message.tests
    if not tests then
        return
    end
    local testIndex = random(1, #message.tests)
    local test = message.tests[testIndex]
    if not includeResult then
        return test[1]
    end
    local args = TableCopy(test) ---@type any[]
    local text = table.remove(args, 1) ---@type string
    local eventIndex = random(1, #message.events)
    local event = message.events[eventIndex]
    local result = ProcessChatMessage(event, text)
    return text, result
end

---@param includeResult? boolean
---@param predicate (fun(message: LootFeedMessage): boolean?)?
---@return fun(): LootFeedMessage?, string?, LootFeedMessageFormatSimpleParserResults?
local function CreateChatMessageGenerator(includeResult, predicate)
    local count = #MessagesCollection
    local index = 0
    return function()
        index = index + 1
        if index > count then
            index = 1
        end
        for i = index, count do
            local message = MessagesCollection[i]
            if not predicate or predicate(message) then
                index = i
                return message, GenerateChatMessage(message, includeResult)
            end
        end
        local message = MessagesCollection[index]
        return message, GenerateChatMessage(message, includeResult)
    end
end

---@param result LootFeedMessageFormatSimpleParserResults
---@param args any[]
---@param isMoney boolean
---@return boolean success
local function CompareTestResults(result, args, isMoney)
    if not result.Type then
        return false
    end
    local numArgs = #args
    local usedKeys = {}
    local count = 0
    for i = 1, numArgs do
        local arg = args[i]
        for k, v in pairs(result) do
            if k ~= "Type" then
                if not usedKeys[k] then
                    if ValuesAreSameish(v, arg) or (isMoney and ValuesAreSameish(C_CurrencyInfo.GetCoinText(v), arg)) then
                        usedKeys[k] = i
                        count = count + 1
                        break
                    end
                end
            end
        end
    end
    if numArgs ~= count then
        return false
    end
    return true
end

---@param message LootFeedMessage
---@param test any[]
---@return LootFeedMessageFormatSimpleParserResults? successResult, LootFeedMessageFormatSimpleParserResults[]? closeResults
local function RunAndEvaluateTest(message, test)
    local isMoney = message.group == LootFeedMessageGroup.Money
    local successResult ---@type LootFeedMessageFormatSimpleParserResults?
    local closeResults ---@type LootFeedMessageFormatSimpleParserResults[]?
    local closeIndex ---@type number?
    local args = TableCopy(test) ---@type any[]
    local text = table.remove(args, 1) ---@type string
    for _, event in ipairs(message.events) do
        local result = ProcessChatMessage(event, text)
        if result then
            local isMoneyResult = result.Type == "IgnoreMoney"
            local success = CompareTestResults(result, args, isMoney or isMoneyResult)
            if success then
                successResult = result
                break
            end
            if not closeResults then
                closeResults = {}
                closeIndex = 0
            end
            closeIndex = closeIndex + 1
            closeResults[closeIndex] = result
        end
    end
    return successResult, closeResults
end

---@param message LootFeedMessage
local function RunAndEvaluateTests(message)
    for _, test in ipairs(message.tests) do
        local testResult, closeResults = RunAndEvaluateTest(message, test)
        if not testResult then
            print(format("%s |cff%sfailed|r %s", message.group, SimpleHexColors.Red, test[1]))
            if closeResults then
                for _, closeResult in ipairs(closeResults) do
                    for k, v in pairs(closeResult) do
                        print(format(" - |cff%s%s|r %s", SimpleHexColors.Yellow, tostringall(k, v)))
                    end
                end
            end
        end
    end
end

local function RunMessageTests()
    if not ns.DebugRunTests then
        return
    end
    for _, message in ipairs(MessagesCollection) do
        if not message.skipTests then
            RunAndEvaluateTests(message)
        end
    end
end

FinalizeMessages()
RunMessageTests()

---@class LootFeedNSMessages
ns.Messages = {
    LootFeedMessageGroup = LootFeedMessageGroup,
    MessagesCollection = MessagesCollection,
    IsChatEventRelevant = IsChatEventRelevant,
    ProcessChatMessage = ProcessChatMessage,
    CreateChatMessageGenerator = CreateChatMessageGenerator,
}
