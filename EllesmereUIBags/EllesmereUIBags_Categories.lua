if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBags_Categories.lua
--  Category system based on Enum.ItemClass numeric IDs (locale-safe).
--  Categories are hardcoded definitions. Users can rename, reorder, and group
--  them via sidebar context menus. Icons and type rules are not customizable.
-------------------------------------------------------------------------------

local CategoryManager = {}
-- Profile access helper (DB created in EUI_Bags_Options.lua, loaded first per TOC)
local EUI = EllesmereUI
local _emptyP = {}
local function BP() return (EUI._bagsDB and EUI._bagsDB.profile) or _emptyP end

-- Enum.ItemClass numeric IDs (locale-independent)
local IC = Enum.ItemClass
local IC_CONSUMABLE    = IC.Consumable       -- 0
local IC_CONTAINER     = IC.Container        -- 1
local IC_WEAPON        = IC.Weapon           -- 2
local IC_GEM           = IC.Gem              -- 3
local IC_ARMOR         = IC.Armor            -- 4
local IC_REAGENT       = IC.Reagent          -- 5
local IC_TRADESKILL    = IC.Tradegoods       -- 7
local IC_ITEM_ENHANCE  = IC.ItemEnhancement  -- 8
local IC_RECIPE        = IC.Recipe           -- 9
local IC_QUEST         = IC.Questitem        -- 12
local IC_MISC          = IC.Miscellaneous    -- 15
local IC_PROFESSION    = 19                  -- Enum.ItemClass.Profession (Midnight)
local IC_HOUSING       = 20                  -- Enum.ItemClass.Housing (Midnight)

-- Hardcoded category definitions. Order here is the default order.
-- types = list of Enum.ItemClass numeric IDs to match
-- Empty types = catch-all (Uncategorized)
local DEFAULT_CATEGORIES = {
    { name = "Pinned Items",       types = {}, isPinned = true, noGroup = true, noMove = true, icon = "friendslist-recentallies-Pin-yellow", isAtlas = true },
    { name = "Recent Items",       types = {}, isRecent = true, noGroup = true, noMove = true, icon = "auctionhouse-icon-clock", isAtlas = true },
    { name = "Reagent Bag",        types = {}, isReagentBag = true, noGroup = true, icon = 3622222 },
    { name = "Item Set Gear",      types = { IC_ARMOR, IC_WEAPON }, isSetGear = true, icon = 4871338 },
    { name = "Quest Items",        types = { IC_QUEST },                     icon = "Crosshair_Quest_64", isAtlas = true },
    { name = "Weapons / Trinkets", types = { IC_WEAPON }, equipSlots = { "INVTYPE_TRINKET" }, icon = 3751725 },
    { name = "Armor",              types = { IC_ARMOR }, excludeEquipSlots = { "INVTYPE_TRINKET" }, icon = 4382688 },
    { name = "Consumables",        types = { IC_CONSUMABLE },                icon = 7548911 },
    { name = "Trade Goods",        types = { IC_TRADESKILL, IC_REAGENT },    icon = 132996 },
    { name = "Gear Enhancements",  types = { IC_GEM, IC_ITEM_ENHANCE },     icon = 7549094 },
    { name = "Professions",        types = { IC_PROFESSION, IC_RECIPE },     icon = 7548925 },
    { name = "Housing",            types = { IC_HOUSING },                   icon = 7726459 },
    { name = "Miscellaneous",      types = { IC_MISC, IC_CONTAINER }, isCatchAll = true, icon = 5524917 },
}

-------------------------------------------------------------------------------
--  Init
--  Builds the runtime category list from hardcoded defaults + saved user state
--  (renames, reorder, grouping). Saved state keyed by default name.
-------------------------------------------------------------------------------
function CategoryManager:InitCategories()
    -- The category list is a DERIVATION of db.profile, cached in _categories
    -- and read BACK by SaveState. In a standalone build every file executes
    -- before the SavedVariables load, so an early build necessarily sees
    -- defaults and BP()'s empty-table fallback hides that. Record whether this
    -- build saw a trustworthy profile; GetCategories re-runs until one did.
    -- Missing framework counts as NOT ready, so the answer can only improve.
    local Lite = EllesmereUI and EllesmereUI.Lite
    self._builtReady = (Lite and Lite.IsDBReady and Lite.IsDBReady()) or false
    -- User state: { [defaultName] = { rename, groupName, groupNameCustom } }
    local userState = BP().bagCategoryState or {}
    -- User order: list of default names in display order
    local userOrder = BP().bagCategoryOrder

    -- Build ordered list of default names
    -- Index DEFAULT_CATEGORIES by name for fast lookup
    local defByName = {}
    for _, def in ipairs(DEFAULT_CATEGORIES) do
        defByName[def.name] = def
    end
    -- Index user-created custom categories by key
    local userCatByKey = {}
    local userCats = BP().bagUserCategories
    if userCats then
        for _, uc in ipairs(userCats) do
            userCatByKey[uc.key] = uc
        end
    end

    local orderedDefs = {}
    if userOrder and #userOrder > 0 then
        -- Use saved order, restoring both built-in and custom categories
        -- at their saved positions
        local seen = {}
        for _, defName in ipairs(userOrder) do
            local def = defByName[defName]
            if def then
                orderedDefs[#orderedDefs + 1] = def
                seen[defName] = true
            elseif userCatByKey[defName] then
                -- Custom category placeholder: mark with _isCustom so the
                -- category builder below can create it at this position
                orderedDefs[#orderedDefs + 1] = { name = defName, _isCustom = true }
                seen[defName] = true
            end
        end
        -- Append any new built-in defaults not in the saved order
        for _, def in ipairs(DEFAULT_CATEGORIES) do
            if not seen[def.name] then
                if def.noMove then
                    -- noMove categories always go to the top
                    table.insert(orderedDefs, 1, def)
                else
                    -- Insert before catch-all
                    local insertIdx = #orderedDefs
                    for i, od in ipairs(orderedDefs) do
                        if od.isCatchAll then insertIdx = i; break end
                    end
                    table.insert(orderedDefs, insertIdx, def)
                end
            end
        end
    else
        for _, def in ipairs(DEFAULT_CATEGORIES) do
            orderedDefs[#orderedDefs + 1] = def
        end
    end

    -- Force noMove categories to the top (in their DEFAULT_CATEGORIES order)
    local pinnedSet = {}
    for _, def in ipairs(orderedDefs) do
        if def.noMove then pinnedSet[def.name] = true end
    end
    local pinned = {}
    -- Use DEFAULT_CATEGORIES order for noMove items (not saved order)
    for _, def in ipairs(DEFAULT_CATEGORIES) do
        if def.noMove and pinnedSet[def.name] then pinned[#pinned + 1] = def end
    end
    local rest = {}
    for _, def in ipairs(orderedDefs) do
        if not def.noMove then rest[#rest + 1] = def end
    end
    orderedDefs = {}
    for _, d in ipairs(pinned) do orderedDefs[#orderedDefs + 1] = d end
    for _, d in ipairs(rest) do orderedDefs[#orderedDefs + 1] = d end

    -- Build runtime categories from ordered defaults + user state.
    -- Custom category placeholders (_isCustom) are expanded inline so
    -- they keep their saved position relative to built-in categories.
    local cats = {}
    local customInserted = {}
    for _, def in ipairs(orderedDefs) do
        if def._isCustom then
            -- Expand custom category placeholder at its saved position
            local uc = userCatByKey[def.name]
            if uc then
                local ucState = userState[uc.key]
                local ucIcon = uc.icon or 134400
                local ucIsAtlas = type(ucIcon) == "string"
                cats[#cats + 1] = {
                    _defaultName  = uc.key,
                    name          = (ucState and ucState.rename) or uc.name,
                    types         = {},
                    icon          = ucIcon,
                    isAtlas       = ucIsAtlas or nil,
                    isUserCreated = true,
                    groupName     = ucState and ucState.groupName,
                    groupNameCustom = ucState and ucState.groupNameCustom,
                }
                customInserted[uc.key] = true
            end
        else
            -- Split mode: expand the "Item Set Gear" anchor into one category per
            -- equipment set, named after the set. Runtime-only -- SaveState collapses
            -- the block back to the anchor so per-character set names never reach
            -- the shared profile. Zero sets falls through to the normal category so
            -- the anchor keeps its saved order position and state.
            local splitSets
            if def.isSetGear and BP().bagSplitSetGearBySet then
                local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
                if setIDs then
                    for _, setID in ipairs(setIDs) do
                        local sname, sicon = C_EquipmentSet.GetEquipmentSetInfo(setID)
                        if sname then
                            splitSets = splitSets or {}
                            splitSets[#splitSets + 1] = { id = setID, name = sname, icon = sicon }
                        end
                    end
                end
            end
            if splitSets then
                table.sort(splitSets, function(a, b) return a.name < b.name end)
                -- Nested under the anchor's display name via the group system:
                -- sidebar shows an "Item Set Gear" header with the sets indented.
                local astate = userState[def.name]
                local anchorName = (astate and astate.rename) or EllesmereUI.L(def.name)
                for _, s in ipairs(splitSets) do
                    cats[#cats + 1] = {
                        _defaultName = "EquipSet:" .. s.id,
                        name         = s.name,
                        types        = def.types,
                        icon         = s.icon or def.icon,
                        isSetGear    = true,   -- keeps gear sorting/type-walk exclusion
                        isEquipSet   = true,
                        equipSetID   = s.id,
                        noGroup      = true,
                        groupName    = anchorName,
                    }
                end
            else
            local state = userState[def.name]
            cats[#cats + 1] = {
                _defaultName      = def.name,
                name              = (state and state.rename) or EllesmereUI.L(def.name),
                types             = def.types,
                icon              = def.icon,
                isAtlas           = def.isAtlas,
                equipSlots        = def.equipSlots,
                excludeEquipSlots = def.excludeEquipSlots,
                isCatchAll        = def.isCatchAll,
                isSetGear         = def.isSetGear,
                isReagentBag      = def.isReagentBag,
                isPinned          = def.isPinned,
                isRecent          = def.isRecent,
                noGroup           = def.noGroup,
                noMove            = def.noMove,
                groupName         = state and state.groupName,
                groupNameCustom   = state and state.groupNameCustom,
            }
            end
        end
    end

    -- Insert any new custom categories not in the saved order (freshly
    -- created since the last save) before the catch-all.
    if userCats then
        local catchIdx
        for i, c in ipairs(cats) do
            if c.isCatchAll then catchIdx = i; break end
        end
        if not catchIdx then catchIdx = #cats + 1 end
        for _, uc in ipairs(userCats) do
            if not customInserted[uc.key] then
                local ucState = userState[uc.key]
                local ucIcon = uc.icon or 134400
                local ucIsAtlas = type(ucIcon) == "string"
                table.insert(cats, catchIdx, {
                    _defaultName  = uc.key,
                    name          = (ucState and ucState.rename) or uc.name,
                    types         = {},
                    icon          = ucIcon,
                    isAtlas       = ucIsAtlas or nil,
                    isUserCreated = true,
                    groupName     = ucState and ucState.groupName,
                    groupNameCustom = ucState and ucState.groupNameCustom,
                })
                catchIdx = catchIdx + 1
            end
        end
    end

    self._categories = cats

    -- setID -> category index, for split-mode classification
    local setCatIdx = {}
    for i, cat in ipairs(cats) do
        if cat.equipSetID then setCatIdx[cat.equipSetID] = i end
    end
    self._setCatIdxBySetID = setCatIdx

    -- Clean up legacy DB keys
    EllesmereUIDB.bagCategoryDefs = nil
    EllesmereUIDB.categoryItems = nil
    EllesmereUIDB.categoryPositions = nil
    EllesmereUIDB.categoryColumns = nil
end

-- Save user state (renames, grouping) and order back to DB
function CategoryManager:SaveState()
    -- Never write a snapshot built before the SavedVariables merged. This is
    -- the destructive half of the bug: the category list is cached and then
    -- written straight back, so a cache built from the pre-SavedVariables
    -- orphan profile does not merely display defaults, it stamps them over
    -- the user's real categories on the very next save.
    local Lite = EllesmereUI and EllesmereUI.Lite
    if Lite and Lite.IsDBReady and not Lite.IsDBReady() then return end
    local cats = self._categories
    if not cats then return end

    local userState = {}
    local userOrder = {}
    local wroteSetAnchor = false
    for _, cat in ipairs(cats) do
        if cat.isEquipSet then
            -- Split-mode set categories are runtime-only: collapse the block to
            -- its "Item Set Gear" anchor (once) and persist no per-set state.
            if not wroteSetAnchor then
                userOrder[#userOrder + 1] = "Item Set Gear"
                wroteSetAnchor = true
            end
        else
            userOrder[#userOrder + 1] = cat._defaultName
            local hasState = false
            local entry = {}
            -- Compare against the LOCALIZED default name. cat.name is the localized
            -- display string (state.rename or L(_defaultName)) while _defaultName is the
            -- English identity key. On a non-English client a plain inequality would see
            -- every untouched default category as "renamed" and freeze its localized name
            -- into the DB, so only treat it as a rename when it differs from the locale default.
            if cat.name ~= EllesmereUI.L(cat._defaultName) then
                entry.rename = cat.name
                hasState = true
            end
            if cat.groupName then
                entry.groupName = cat.groupName
                hasState = true
            end
            if cat.groupNameCustom then
                entry.groupNameCustom = cat.groupNameCustom
                hasState = true
            end
            if hasState then
                userState[cat._defaultName] = entry
            end
        end
    end
    -- Split mode removed the merged anchor from cats, so the loop above never
    -- re-emits its saved rename/group entry -- carry it over or it is lost
    -- (e.g. the seeded "The Armory" grouping) the first time split-mode saves.
    if wroteSetAnchor then
        local prev = BP().bagCategoryState and BP().bagCategoryState["Item Set Gear"]
        if prev then userState["Item Set Gear"] = prev end
    end
    BP().bagCategoryState = userState
    BP().bagCategoryOrder = userOrder

    -- Rebuild user-created categories list from runtime state
    local ucList = {}
    for _, cat in ipairs(cats) do
        if cat.isUserCreated then
            ucList[#ucList + 1] = { key = cat._defaultName, name = cat._defaultName, icon = cat.icon }
        end
    end
    BP().bagUserCategories = #ucList > 0 and ucList or nil
end

-------------------------------------------------------------------------------
--  Accessors
-------------------------------------------------------------------------------
function CategoryManager:GetCategories()
    -- Rebuild not just when empty, but while the cached list was built before
    -- the profile could be trusted. Pull, not push: a callback registered at
    -- file scope would depend on the framework having loaded first, which is
    -- the same ordering assumption that caused this bug -- and unverifiable in
    -- the standalone TOC. By the time anything READS categories the framework
    -- is certainly present.
    if not self._categories or not self._builtReady then
        self:InitCategories()
    end
    return self._categories
end

function CategoryManager:GetCategoryCount()
    local cats = self:GetCategories()
    return #cats
end

-------------------------------------------------------------------------------
--  Classification
-------------------------------------------------------------------------------
-- Equipment set lookup: built once per ClassifyAll pass.
-- Maps "bag*1000+slot" -> setID. A slot in several sets keeps the first
-- (enumeration order), matching split-mode classification's first-set-wins.
local _setGearLookup = {}
-- setID -> set name, for the on-item set name label (no API call at stamp time)
local _setNames = {}

local function BuildSetGearLookup()
    wipe(_setGearLookup)
    wipe(_setNames)
    local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
    if not setIDs then return end
    for _, setID in ipairs(setIDs) do
        _setNames[setID] = C_EquipmentSet.GetEquipmentSetInfo(setID)
        local locs = C_EquipmentSet.GetItemLocations(setID)
        if locs then
            for _, loc in pairs(locs) do
                if loc and loc ~= 0 and loc ~= 1 and loc ~= -1 then
                    local data = EquipmentManager_GetLocationData(loc)
                    if data.isBags then
                        local key = data.bag * 1000 + data.slot
                        if not _setGearLookup[key] then _setGearLookup[key] = setID end
                    end
                end
            end
        end
    end
end

-- Manual overrides: itemID -> classID
local ITEM_TYPE_OVERRIDES = {
    [180653] = IC_MISC,
}

-- Classify a single item. Returns category index (1-based) or nil for empty slots.
-- bag/slot are needed for C_Container.GetContainerItemQuestInfo
function CategoryManager:ClassifyItem(itemLink, itemID, bag, slot)
    if not itemLink then return nil end

    local cats = self:GetCategories()

    -- Reagent bag items always go to the Reagent Bag category
    if bag == 5 then
        for i, cat in ipairs(cats) do
            if cat.isReagentBag then return i end
        end
    end

    -- User item assignments: itemID -> category _defaultName.
    -- Checked before type matching so users can override auto-classification.
    if itemID then
        local assignments = EllesmereUIDB and EllesmereUIDB.bagItemAssignments
        local assignedKey = assignments and assignments[itemID]
        if assignedKey then
            for i, cat in ipairs(cats) do
                if cat._defaultName == assignedKey then return i end
            end
        end
    end

    -- Check manual overrides first
    if itemID and ITEM_TYPE_OVERRIDES[itemID] then
        local overrideClassID = ITEM_TYPE_OVERRIDES[itemID]
        for i, cat in ipairs(cats) do
            if cat.types then
                for _, t in ipairs(cat.types) do
                    if t == overrideClassID then return i end
                end
            end
        end
    end

    -- Check quest status via dedicated API (catches "begins a quest" items too)
    if bag and slot then
        local questInfo = C_Container.GetContainerItemQuestInfo(bag, slot)
        if questInfo and (questInfo.isQuestItem or questInfo.questID) then
            for i, cat in ipairs(cats) do
                if cat.types then
                    for _, t in ipairs(cat.types) do
                        if t == IC_QUEST then return i end
                    end
                end
            end
        end
    end

    -- Get classID + equip slot via GetItemInfoInstant (locale-safe numeric IDs)
    local _, _, _, equipSlot, _, classID = GetItemInfoInstant(itemLink)
    if not classID then
        -- Item data not available; classify as catch-all for now
        for i, cat in ipairs(cats) do
            if cat.isCatchAll then return i end
        end
        return #cats
    end

    -- Equipment set gear check: if item is Armor/Weapon AND in an equipment set,
    -- route to its own set's category (split mode; first set wins for items in
    -- several) or the merged "Item Set Gear" category, before normal type matching
    if bag and slot and (classID == IC_ARMOR or classID == IC_WEAPON) then
        local setID = _setGearLookup[bag * 1000 + slot]
        if setID then
            local byID = self._setCatIdxBySetID
            local idx = byID and byID[setID]
            if idx then return idx end
            for i, cat in ipairs(cats) do
                if cat.isSetGear then return i end
            end
        end
    end

    -- Walk categories and check if item classID + equip slot matches
    for i, cat in ipairs(cats) do
        if cat.types and #cat.types > 0 and not cat.isSetGear then
            local typeMatch = false
            for _, t in ipairs(cat.types) do
                if t == classID then typeMatch = true; break end
            end

            -- equipSlots: match items of OTHER types that have these equip slots
            -- (e.g. trinkets are classID Armor but equipSlot "INVTYPE_TRINKET")
            if not typeMatch and cat.equipSlots and equipSlot then
                for _, es in ipairs(cat.equipSlots) do
                    if es == equipSlot then typeMatch = true; break end
                end
            end

            -- excludeEquipSlots: reject items that match the classID but have excluded equip slots
            if typeMatch and cat.excludeEquipSlots and equipSlot then
                for _, es in ipairs(cat.excludeEquipSlots) do
                    if es == equipSlot then typeMatch = false; break end
                end
            end

            if typeMatch then return i end
        end
    end

    -- No match: use catch-all category
    for i, cat in ipairs(cats) do
        if cat.isCatchAll then return i end
    end
    return #cats
end

-- Classify all items and return counts per category + total.
-- Each item in the array gets a .categoryIndex field set.
-- Reusable tables for ClassifyAll (wiped each call, avoids per-refresh allocation)
local _claCounts = {}
local _claDisabledIdxSet = {}

function CategoryManager:ClassifyAll(items)
    BuildSetGearLookup()
    local cats = self:GetCategories()
    -- Rebuild setID -> index every pass: drag-reorder and custom-category
    -- add/remove mutate cats in place without InitCategories, shifting indices.
    local setCatIdx = self._setCatIdxBySetID or {}
    wipe(setCatIdx)
    for i, cat in ipairs(cats) do
        if cat.equipSetID then setCatIdx[cat.equipSetID] = i end
    end
    self._setCatIdxBySetID = setCatIdx
    wipe(_claCounts)
    for i = 1, #cats do _claCounts[i] = 0 end
    local counts = _claCounts
    local total = 0

    -- Disabled categories: items route to catch-all instead (keyed by _defaultName)
    local disabledCats = BP().bagDisabledCategories
    local catchAllIdx
    wipe(_claDisabledIdxSet)
    local disabledIdxSet
    if disabledCats then
        disabledIdxSet = _claDisabledIdxSet
        for i, cat in ipairs(cats) do
            if cat.isCatchAll then catchAllIdx = i end
            if cat._defaultName and disabledCats[cat._defaultName] then
                disabledIdxSet[i] = true
            end
        end
    end

    for _, data in ipairs(items) do
        if data.info and data.itemLink then
            local idx = self:ClassifyItem(data.itemLink, data.info.itemID, data.bag, data.slot)
            -- Set name for the on-item label; explicit nil clears recycled tables
            local sid = _setGearLookup[data.bag * 1000 + data.slot]
            data._setName = sid and _setNames[sid] or nil
            -- Reroute disabled categories to catch-all
            if disabledIdxSet and idx and disabledIdxSet[idx] and catchAllIdx then
                idx = catchAllIdx
            end
            data.categoryIndex = idx
            if idx then
                counts[idx] = (counts[idx] or 0) + 1
            end
            total = total + 1
        end
    end

    return counts, total
end

-------------------------------------------------------------------------------
--  Rename / Reorder (user-facing operations)
-------------------------------------------------------------------------------
function CategoryManager:RenameCategory(index, newName)
    local cats = self:GetCategories()
    if not cats[index] then return false end
    if not newName or newName == "" then return false end
    local oldGroup = cats[index].groupName
    local shouldRegenerate = oldGroup and not self:IsGroupNameCustom(oldGroup)
    cats[index].name = newName
    if shouldRegenerate then
        self:RegenerateGroupName(oldGroup)
    end
    self:SaveState()
    return true
end

-- Move category from fromIndex to toIndex.
-- Callers should NOT adjust for remove/insert -- this function handles it internally.
function CategoryManager:ReorderCategory(fromIndex, toIndex)
    local cats = self:GetCategories()
    if not cats[fromIndex] or fromIndex == toIndex then return end
    -- Equip-set categories move as a block via their anchor; a single one dragged
    -- out would snap back on the next rebuild (SaveState collapses the block).
    if cats[fromIndex].isEquipSet then return end
    if toIndex < 1 or toIndex > #cats + 1 then return end
    local entry = table.remove(cats, fromIndex)
    local insertAt = toIndex
    if fromIndex < toIndex then insertAt = toIndex - 1 end
    table.insert(cats, insertAt, entry)
    self:SaveState()
end

-------------------------------------------------------------------------------
--  Grouping
-------------------------------------------------------------------------------
-- Group two or more categories together under a shared name.
function CategoryManager:GroupCategories(indices, groupName)
    local cats = self:GetCategories()
    if not indices or #indices < 2 then return end
    if not groupName then
        local names = {}
        for _, idx in ipairs(indices) do
            if cats[idx] then names[#names + 1] = cats[idx].name end
        end
        if #names == 2 then
            groupName = names[1] .. " & " .. names[2]
        elseif #names >= 3 then
            local last = names[#names]
            names[#names] = nil
            groupName = table.concat(names, ", ") .. ", & " .. last
        else
            groupName = "Group"
        end
    end
    for _, idx in ipairs(indices) do
        if cats[idx] then
            cats[idx].groupName = groupName
            cats[idx].groupNameCustom = nil
        end
    end
    self:SaveState()
end

-- Add a category to an existing group.
function CategoryManager:AddToGroup(catIndex, groupName)
    local cats = self:GetCategories()
    if not cats[catIndex] or not groupName then return end
    -- The runtime equip-set group only holds set categories; a normal category
    -- added to it would persist while the group itself rebuilds around it.
    for _, cat in ipairs(cats) do
        if cat.groupName == groupName and cat.isEquipSet then return end
    end
    cats[catIndex].groupName = groupName
    self:RegenerateGroupName(groupName)
    self:SaveState()
end

-- Remove a category from its group.
function CategoryManager:UngroupCategory(catIndex)
    local cats = self:GetCategories()
    if not cats[catIndex] or not cats[catIndex].groupName then return end
    local oldGroup = cats[catIndex].groupName
    local wasCustom = self:IsGroupNameCustom(oldGroup)
    cats[catIndex].groupName = nil
    local remaining = {}
    for i, cat in ipairs(cats) do
        if cat.groupName == oldGroup then remaining[#remaining + 1] = i end
    end
    if #remaining == 0 then
        -- No members left, nothing to do
    elseif #remaining == 1 then
        -- Only 1 member left, auto-disband
        cats[remaining[1]].groupName = nil
    elseif not wasCustom then
        self:RegenerateGroupName(oldGroup)
    end
    self:SaveState()
end

-- Ungroup all members of a group.
function CategoryManager:DisbandGroup(groupName)
    local cats = self:GetCategories()
    for _, cat in ipairs(cats) do
        if cat.groupName == groupName then cat.groupName = nil end
    end
    self:SaveState()
end

-- Rename a group (updates all members).
function CategoryManager:RenameGroup(oldName, newName)
    if not newName or newName == "" then return end
    local cats = self:GetCategories()
    -- Refuse names in use by the runtime equip-set group: sharing its raw
    -- groupName string would merge the two groups in every keyed lookup.
    for _, cat in ipairs(cats) do
        if cat.isEquipSet and cat.groupName == newName then return end
    end
    for _, cat in ipairs(cats) do
        if cat.groupName == oldName then cat.groupName = newName end
    end
    self:SaveState()
end

-- Check if the group name was manually customized by the user.
function CategoryManager:IsGroupNameCustom(groupName)
    local cats = self:GetCategories()
    for _, cat in ipairs(cats) do
        if cat.groupName == groupName and cat.groupNameCustom then return true end
    end
    return false
end

-- Mark a group name as manually customized (set on all members).
function CategoryManager:SetGroupNameCustom(groupName, isCustom)
    local cats = self:GetCategories()
    for _, cat in ipairs(cats) do
        if cat.groupName == groupName then
            cat.groupNameCustom = isCustom or nil
        end
    end
    self:SaveState()
end

-- Auto-regenerate group name from member names.
function CategoryManager:RegenerateGroupName(groupName)
    local cats = self:GetCategories()
    local names = {}
    for _, cat in ipairs(cats) do
        -- The runtime equip-set group keeps its anchor-derived name
        if cat.groupName == groupName and cat.isEquipSet then return end
        if cat.groupName == groupName then names[#names + 1] = cat.name end
    end
    local newName
    if #names == 2 then
        newName = names[1] .. " & " .. names[2]
    elseif #names >= 3 then
        local last = names[#names]
        newName = table.concat(names, ", ", 1, #names - 1) .. ", & " .. last
    else
        return
    end
    if newName ~= groupName then
        self:RenameGroup(groupName, newName)
        self:SetGroupNameCustom(newName, false)
    end
end

-- Get all unique group names. The runtime equip-set group is excluded: it is
-- not a valid "Add to Group" target (see AddToGroup).
function CategoryManager:GetGroupNames()
    local cats = self:GetCategories()
    local seen = {}
    local groups = {}
    for _, cat in ipairs(cats) do
        if cat.groupName and not seen[cat.groupName] and not cat.isEquipSet then
            seen[cat.groupName] = true
            groups[#groups + 1] = cat.groupName
        end
    end
    return groups
end

-- Get all member indices for a group.
function CategoryManager:GetGroupMembers(groupName)
    local cats = self:GetCategories()
    local members = {}
    for i, cat in ipairs(cats) do
        if cat.groupName == groupName then members[#members + 1] = i end
    end
    return members
end

-- Check if a category is in a group.
function CategoryManager:IsGrouped(catIndex)
    local cats = self:GetCategories()
    return cats[catIndex] and cats[catIndex].groupName or nil
end

-------------------------------------------------------------------------------
--  Custom Category CRUD
-------------------------------------------------------------------------------
-- Create a new user category. Returns the new category index.
function CategoryManager:AddCustomCategory(name)
    if not name or name == "" then return nil end
    if not BP().bagUserCategories then BP().bagUserCategories = {} end

    -- Generate a unique key
    local maxN = 0
    for _, uc in ipairs(BP().bagUserCategories) do
        local n = tonumber(uc.key:match("Custom_(%d+)"))
        if n and n > maxN then maxN = n end
    end
    local key = "Custom_" .. (maxN + 1)

    BP().bagUserCategories[#BP().bagUserCategories + 1] = { key = key, name = name }

    -- Insert into runtime list before catch-all
    local cats = self:GetCategories()
    local catchIdx = #cats + 1
    for i, c in ipairs(cats) do
        if c.isCatchAll then catchIdx = i; break end
    end
    table.insert(cats, catchIdx, {
        _defaultName  = key,
        name          = name,
        types         = {},
        icon          = "Petjournalv2-Icon-PlusButton",
        isAtlas       = true,
        isUserCreated = true,
    })
    self:SaveState()
    return catchIdx
end

-- Remove a user-created category. Unassigns all items in it.
function CategoryManager:RemoveCustomCategory(catIndex)
    local cats = self:GetCategories()
    local cat = cats[catIndex]
    if not cat or not cat.isUserCreated then return false end
    local key = cat._defaultName

    -- Remove item assignments pointing to this category
    local assignments = EllesmereUIDB and EllesmereUIDB.bagItemAssignments
    if assignments then
        for itemID, aKey in pairs(assignments) do
            if aKey == key then assignments[itemID] = nil end
        end
    end

    -- Remove from runtime list
    table.remove(cats, catIndex)

    -- Remove from disabled list
    if BP().bagDisabledCategories then
        BP().bagDisabledCategories[key] = nil
    end

    self:SaveState()
    return true
end

-------------------------------------------------------------------------------
--  Item Assignment (user overrides auto-classification)
-------------------------------------------------------------------------------
-- Assign an itemID to a category. Pass nil to unassign.
function CategoryManager:AssignItem(itemID, categoryKey)
    if not itemID then return end
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.bagItemAssignments then EllesmereUIDB.bagItemAssignments = {} end
    EllesmereUIDB.bagItemAssignments[itemID] = categoryKey
end

-- Unassign an itemID (returns to auto-classification).
function CategoryManager:UnassignItem(itemID)
    if not itemID then return end
    local assignments = EllesmereUIDB and EllesmereUIDB.bagItemAssignments
    if assignments then
        assignments[itemID] = nil
    end
end

-- Check if a category can accept item assignments (drag targets).
-- Excludes Pinned, Recent, Reagent Bag (physical bag, not logical).
function CategoryManager:CanAssignToCategory(catIndex)
    local cats = self:GetCategories()
    local cat = cats[catIndex]
    if not cat then return false end
    if cat.isPinned or cat.isRecent or cat.isReagentBag then return false end
    if cat.isEquipSet then return false end  -- membership comes from the set itself
    return true
end

-- Equipment sets changed (created/renamed/deleted): drop the cached list so the
-- next GetCategories rebuilds split-mode categories from the current sets.
function CategoryManager:OnEquipmentSetsChanged()
    self._categories = nil
end

-------------------------------------------------------------------------------
--  Global accessor
-------------------------------------------------------------------------------
if not _G.EUI_CategoryManager then
    _G.EUI_CategoryManager = CategoryManager
end

CategoryManager:InitCategories()
