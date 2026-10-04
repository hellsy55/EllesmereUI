local rootNS = select(2, ...)
rootNS.LootFeed = rootNS.LootFeed or {}
local ns = rootNS.LootFeed ---@class LootFeedNS

local GetLinkQuality = ns.Utils.GetLinkQuality
local IsQuestItem = ns.Utils.IsQuestItem

---@alias LootFeedFilterComparators
---|"eq"
---|"ne"
---|"gt"
---|"ge"
---|"lt"
---|"le"

---@alias LootFeedFilterConverters
---|"quality"
---|"quest"
---|"itemClass"

---@alias LootFeedFilter LootFeedFilterRule|LootFeedFilterRuleGroup
---@alias LootFeedFilters LootFeedFilterRule[]|LootFeedFilterRuleGroup[]

---@class LootFeedFilterRule
---@field public group? LootFeedMessageGroup
---@field public type? LootFeedMessageFormatSimpleParserResultType
---@field public key LootFeedMessageFormatSimpleParserResultKeys
---@field public convert? LootFeedFilterConverters
---@field public comparator LootFeedFilterComparators
---@field public value any

---@class LootFeedFilterRuleGroup
---@field public logic "and"|"or"
---@field public children LootFeedFilters

---@param value any
---@param convert LootFeedFilterConverters
---@return any
local function ConvertValue(value, convert)
    local valueType = type(value)
    if convert == "quality" then
        local quality ---@type number?
        if valueType == "string" then
            quality = GetLinkQuality(value)
        end
        return quality
    elseif convert == "quest" then
        local quest ---@type boolean?
        if valueType == "string" then
            quest = IsQuestItem(value)
        end
        return quest
    elseif convert == "itemClass" then
        local itemClass, _ ---@type number?
        if valueType == "string" then
            _, _, _, _, _, itemClass = C_Item.GetItemInfoInstant(value)
        end
        return itemClass
    end
    return value
end

---@param value1 any
---@param comparator LootFeedFilterComparators
---@param value2 any
---@return boolean
local function CompareValues(value1, comparator, value2)
    if comparator == "eq" then
        if value1 == value2 then
            return true
        end
    elseif comparator == "ne" then
        if value1 ~= value2 then
            return true
        end
    end
    local type1 = type(value1)
    local type2 = type(value2)
    local comparable = (type1 == "number" or type1 == "string") and (type2 == "number" or type2 == "string")
    if comparable then
        if comparator == "gt" then
            return value1 > value2
        elseif comparator == "ge" then
            return value1 >= value2
        elseif comparator == "lt" then
            return value1 < value2
        elseif comparator == "le" then
            return value1 <= value2
        end
    end
    comparable = (type1 == "boolean" or type1 == "nil") and (type2 == "boolean" or type2 == "nil")
    if comparable then
        value1 = not not value1
        value2 = not not value2
        if comparator == "eq" then
            return value1 and value2
        elseif comparator == "ne" then
            return not (value1 and value2)
        end
    end
    return false
end

---@param rule LootFeedFilterRule
---@param result LootFeedMessageFormatSimpleParserResults
---@param message LootFeedMessage
---@return boolean isRelevant
local function IsRuleRelevant(rule, result, message)
    if rule.group and rule.group ~= message.group then
        return false
    end
    if rule.type and rule.type ~= result.Type then
        return false
    end
    return true
end

---@param ruleGroup LootFeedFilterRuleGroup
---@param result LootFeedMessageFormatSimpleParserResults
---@param message LootFeedMessage
---@return boolean isRelevant
local function IsRuleGroupRelevant(ruleGroup, result, message)
    for _, child in ipairs(ruleGroup.children) do
        if child.logic then
            ---@type LootFeedFilterRuleGroup
            local childRuleGroup = child ---@diagnostic disable-line: assign-type-mismatch
            if not IsRuleGroupRelevant(childRuleGroup, result, message) then
                return false
            end
        else
            ---@type LootFeedFilterRule
            local childRule = child ---@diagnostic disable-line: assign-type-mismatch
            if not IsRuleRelevant(childRule, result, message) then
                return false
            end
        end
    end
    return true
end

---@param rule LootFeedFilterRule
---@param result LootFeedMessageFormatSimpleParserResults
---@return boolean satisfiesRule
local function EvaluateRule(rule, result)
    local resultValue = result[rule.key] ---@type any
    if rule.convert then
        resultValue = ConvertValue(resultValue, rule.convert)
    end
    return CompareValues(resultValue, rule.comparator, rule.value)
end

---@param rules LootFeedFilterRule[]
---@param result LootFeedMessageFormatSimpleParserResults
---@param message LootFeedMessage
---@return boolean? isFiltered, LootFeedFilterRule? filteredBy
local function EvaluateRules(rules, result, message)
    local numRelevant = 0
    for _, rule in ipairs(rules) do
        if IsRuleRelevant(rule, result, message) then
            numRelevant = numRelevant + 1
            local satisfiesRule = EvaluateRule(rule, result)
            if not satisfiesRule then
                return true, rule
            end
        end
    end
    if numRelevant > 0 then
        return false
    end
end

---@param ruleGroup LootFeedFilterRuleGroup
---@param result LootFeedMessageFormatSimpleParserResults
---@param message LootFeedMessage
---@return boolean satisfiesRuleGroup
local function EvaluateRuleGroup(ruleGroup, result, message)
    local logic = ruleGroup.logic
    local satisfiesRuleGroup = logic == "and"
    for _, child in ipairs(ruleGroup.children) do
        local satisfiesChild = satisfiesRuleGroup
        if child.logic then
            ---@type LootFeedFilterRuleGroup
            local childRuleGroup = child ---@diagnostic disable-line: assign-type-mismatch
            satisfiesChild = EvaluateRuleGroup(childRuleGroup, result, message)
        else
            ---@type LootFeedFilterRule
            local childRule = child ---@diagnostic disable-line: assign-type-mismatch
            if IsRuleRelevant(childRule, result, message) then
                satisfiesChild = EvaluateRule(childRule, result)
            end
        end
        if logic == "and" then
            satisfiesRuleGroup = satisfiesRuleGroup and satisfiesChild
            if not satisfiesRuleGroup then
                break
            end
        else
            satisfiesRuleGroup = satisfiesRuleGroup or satisfiesChild
            if satisfiesRuleGroup then
                break
            end
        end
    end
    return satisfiesRuleGroup
end

---@param ruleGroups LootFeedFilterRuleGroup[]
---@param result LootFeedMessageFormatSimpleParserResults
---@param message LootFeedMessage
---@return boolean? isFiltered, LootFeedFilterRuleGroup? filteredBy
local function EvaluateRuleGroups(ruleGroups, result, message)
    local numRelevant = 0
    for _, ruleGroup in ipairs(ruleGroups) do
        if IsRuleGroupRelevant(ruleGroup, result, message) then
            numRelevant = numRelevant + 1
            local satisfiesRuleGroup = EvaluateRuleGroup(ruleGroup, result, message)
            if not satisfiesRuleGroup then
                return true, ruleGroup
            end
        end
    end
    if numRelevant > 0 then
        return false
    end
end

---@param entries LootFeedFilters
---@param result LootFeedMessageFormatSimpleParserResults
---@param message LootFeedMessage
---@return boolean isFiltered, LootFeedFilter? filteredBy
local function EvaluateFilters(entries, result, message)
    for _, entry in ipairs(entries) do
        local satisfies ---@type boolean?
        if entry.logic then
            ---@type LootFeedFilterRuleGroup
            local temp = entry ---@diagnostic disable-line: assign-type-mismatch
            if IsRuleGroupRelevant(temp, result, message) then
                satisfies = EvaluateRuleGroup(temp, result, message)
            end
        else
            ---@type LootFeedFilterRule
            local rule = entry ---@diagnostic disable-line: assign-type-mismatch
            if IsRuleRelevant(rule, result, message) then
                satisfies = EvaluateRule(rule, result)
            end
        end
        if satisfies == false then
            return true, entry
        end
    end
    return false
end

---@class LootFeedNSFilters
ns.Filters = {
    EvaluateFilters = EvaluateFilters,
}
