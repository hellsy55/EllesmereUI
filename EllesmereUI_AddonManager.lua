if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- Addon Manager. All configuration belongs to the active EllesmereUI profile.
-- Off by default; the only registration while off is /euiaddons.
-------------------------------------------------------------------------------
local EUI = EllesmereUI
local AM = {}
EUI.AddonManager = AM
local CORE = "EllesmereUI"
local OPTIONS = "EllesmereUIOptions"
local NONE = Enum.AddOnEnableState.None

-- The core owns this manager; the load-on-demand options addon owns its UI.
-- Neither may be disabled by the manager, including bulk/profile actions.
function AM.Protected(name) return name == CORE or name == OPTIONS end

local function Store(create)
    local profile = EUI.GetActiveProfileData()
    if not profile then return end
    local s = profile.addonManager
    if not s and create then s = {}; profile.addonManager = s end
    if s then
        s.defaults = s.defaults or {}
        s.chars = s.chars or {}
        s.categories = s.categories or {}
        s.catOf = s.catOf or {}
    end
    return s
end
-- Startup view is profile-scoped; absent values preserve the original character view.
function AM.GetStartView()
    local s = Store()
    return s and s.startView == "account" and "account" or "character"
end
function AM.SetStartView(value)
    local s = Store(true)
    if s then s.startView = value == "account" and "account" or nil end
end
local function CharKey()
    return UnitName("player") .. " - " .. GetRealmName()
end
local function Remember(s)
    local key = CharKey()
    local c = s.chars[key]
    if not c then c = { overrides = {} }; s.chars[key] = c end
    c.overrides = c.overrides or {}
    c.class = select(2, UnitClass("player"))
    local name, surname = UnitName("player")
    c.label = EUI.IS_FOREVER and type(surname) == "string" and surname ~= "" and not (issecretvalue and issecretvalue(surname)) and name .. " " .. surname or key
end
local function Plain(text)
    text = (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
function AM.List()
    local out, guid = {}, UnitGUID("player")
    local s = Store()
    for i = 1, C_AddOns.GetNumAddOns() do
        local name, title, notes = C_AddOns.GetAddOnInfo(i)
        if name then
            local category = C_AddOns.GetAddOnMetadata(i, "Category")
            local declared = category
            local put = s and s.catOf[name]
            if put ~= nil then category = put or nil; declared = nil end
            local iconTexture = C_AddOns.GetAddOnMetadata(i, "IconTexture")
            local iconAtlas = C_AddOns.GetAddOnMetadata(i, "IconAtlas")
            local icon
            if iconAtlas and not iconTexture then
                icon = CreateAtlasMarkup(iconAtlas, 16, 16)
            else
                icon = CreateSimpleTextureMarkup(iconTexture or [[Interface\ICONS\INV_Misc_QuestionMark]], 16, 16)
            end
            local loadable, reason = C_AddOns.IsAddOnLoadable(i, UnitName("player"))
            out[#out + 1] = {
                index = i, name = name, notes = notes,
                title = Plain(title ~= "" and title or name),
                shown = title ~= "" and title or name,
                icon = icon,
                lod = C_AddOns.IsAddOnLoadOnDemand(i),
                group = C_AddOns.GetAddOnMetadata(i, "Group") or name,
                category = category and category ~= "" and Plain(category) or nil,
                categoryShown = declared and declared ~= "" and declared or nil,
                on = C_AddOns.GetAddOnEnableState(i, guid) > NONE,
                loaded = C_AddOns.IsAddOnLoaded(i), loadable = loadable,
                reason = reason, locked = AM.Protected(name),
            }
        end
    end
    table.sort(out, function(a, b)
        local x, y = a.title:lower(), b.title:lower()
        if x ~= y then return x < y end
        return a.name < b.name
    end)
    return out
end
function AM.Wanted(name, charKey)
    if AM.Protected(name) then return true end
    local s = Store()
    if not s then return nil end
    local c = s.chars[charKey]
    local o = c and c.overrides and c.overrides[name]
    if o ~= nil then return o end
    return s.defaults[name]
end
function AM.Needed(charKey)
    local needed, visiting = {}, {}
    local guid = UnitGUID("player")
    local current = charKey == CharKey()
    local function Need(name, by)
        if visiting[name] then return end
        visiting[name] = true
        for _, dep in ipairs({ C_AddOns.GetAddOnDependencies(name) }) do
            if type(dep) == "string" and dep ~= "" and not needed[dep] then
                needed[dep] = by
                Need(dep, by)
            end
        end
    end
    -- Unmanaged addons keep their native enable state. Their dependencies
    -- must also remain enabled, not just dependencies of explicitly-on addons.
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name then
            local want = AM.Wanted(name, charKey)
            if want == true or (want == nil and current and C_AddOns.GetAddOnEnableState(i, guid) > NONE) then
                Need(name, name)
            end
        end
    end
    return needed
end
function AM.Pending()
    local out = {}
    if not Store() then return out end
    local key, guid = CharKey(), UnitGUID("player")
    local needed = AM.Needed(key)
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and name ~= CORE then
            local want = AM.Wanted(name, key)
            if needed[name] then want = true end
            if want ~= nil and want ~= (C_AddOns.GetAddOnEnableState(i, guid) > NONE) then
                out[#out + 1] = { name = name, on = want }
            end
        end
    end
    return out
end
local function ApplyError(name)
    if EUI.PrintError then
        EUI.PrintError("Addon Manager: could not apply " .. name .. "; previous addon states restored where possible.")
    end
end
function AM.ApplyNative()
    if InCombatLockdown() then ApplyError("changes in combat"); return 0, false end
    local guid, pending = UnitGUID("player"), AM.Pending()
    local previous = {}
    for _, item in ipairs(pending) do
        if AM.Protected(item.name) and not item.on then
            ApplyError(item.name)
            return 0, false
        end
        previous[item.name] = C_AddOns.GetAddOnEnableState(item.name, guid) > NONE
    end
    -- Native enable-state changes are reversible, but SaveAddOns is not a
    -- transaction. Check every result and restore the previous states on error.
    local function Change(name, enabled)
        local action = enabled and C_AddOns.EnableAddOn or C_AddOns.DisableAddOn
        local ok = pcall(action, name, guid)
        return ok and (C_AddOns.GetAddOnEnableState(name, guid) > NONE) == enabled
    end
    local function Restore()
        for i = #pending, 1, -1 do
            local name = pending[i].name
            local before = previous[name]
            if (C_AddOns.GetAddOnEnableState(name, guid) > NONE) ~= before then
                Change(name, before)
            end
        end
        pcall(C_AddOns.SaveAddOns)
    end
    -- Dependencies are generally enabled before their consumers by the
    -- native API; enable passes before disables avoid a transient missing dep.
    for _, enabled in ipairs({ true, false }) do
        for _, item in ipairs(pending) do
            if item.on == enabled and not Change(item.name, enabled) then
                Restore()
                ApplyError(item.name)
                return 0, false
            end
        end
    end
    local ok = pcall(C_AddOns.SaveAddOns)
    if not ok then
        Restore()
        ApplyError("addon settings")
        return 0, false
    end
    local s = Store()
    if s then s.backup = nil end
    return #pending, true
end
function AM.SetDefault(name, value)
    if AM.Protected(name) then return end
    local s = Store(true)
    if s then s.defaults[name] = value end
end
function AM.SetOverride(key, name, value)
    if AM.Protected(name) then return end
    local s = Store(true)
    local c = s.chars[key]
    if not c then c = { overrides = {} }; s.chars[key] = c end
    c.overrides = c.overrides or {}
    c.overrides[name] = value
end
function AM.SetDefaults(addons, value)
    for _, a in ipairs(addons) do AM.SetDefault(a.name, value) end
end
function AM.SetOverrides(key, addons, value)
    for _, a in ipairs(addons) do AM.SetOverride(key, a.name, value) end
end
function AM.DefaultsFromThisCharacter()
    local s, guid = Store(true), UnitGUID("player")
    wipe(s.defaults)
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and not AM.Protected(name) then
            s.defaults[name] = C_AddOns.GetAddOnEnableState(i, guid) > NONE
        end
    end
end
function AM.Tree(list, folded, query)
    local out = {}
    if query ~= "" then
        for _, a in ipairs(list) do
            if a.title:lower():find(query, 1, true) or a.name:lower():find(query, 1, true) then
                out[#out + 1] = { kind = "addon", addon = a, depth = 0 }
            end
        end
        return out
    end
    local byName, children, roots = {}, {}, {}
    for _, a in ipairs(list) do byName[a.name] = a end
    for _, a in ipairs(list) do
        local parent = byName[a.group]
        if parent and parent ~= a and parent.group == parent.name then
            children[parent.name] = children[parent.name] or {}
            table.insert(children[parent.name], a)
        else roots[#roots + 1] = a end
    end
    local cats, order, loose, shownAs = {}, {}, {}, {}
    for _, a in ipairs(roots) do
        local c = a.category
        if c then
            if not cats[c] then cats[c] = {}; order[#order + 1] = c end
            shownAs[c] = shownAs[c] or a.categoryShown
            table.insert(cats[c], a)
        else loose[#loose + 1] = a end
    end
    local s, made = Store(), {}
    for _, c in ipairs(s and s.categories or {}) do
        made[c] = true
        if not cats[c] then cats[c] = {}; order[#order + 1] = c end
    end
    table.sort(order, function(x, y) return x:lower() < y:lower() end)
    local function Add(a, depth)
        local sub = children[a.name]
        local entry = { kind = "addon", addon = a, depth = depth }
        if sub then
            entry.members = { a }
            for _, c in ipairs(sub) do entry.members[#entry.members + 1] = c end
            entry.foldKey = "GROUP:" .. a.name
            entry.folded = folded[entry.foldKey] == true
        end
        out[#out + 1] = entry
        if not entry.folded then
            for _, c in ipairs(sub or {}) do
                out[#out + 1] = { kind = "addon", addon = c, depth = depth + 1, sub = true }
            end
        end
    end
    local function Category(key, label, members, user)
        local all = {}
        for _, a in ipairs(members) do
            all[#all + 1] = a
            for _, c in ipairs(children[a.name] or {}) do all[#all + 1] = c end
        end
        local isFolded = folded[key] == true
        out[#out + 1] = {
            kind = "category", key = key, name = label, count = #all,
            folded = isFolded, user = user, addons = all,
        }
        if not isFolded then for _, a in ipairs(members) do Add(a, 1) end end
    end
    for _, c in ipairs(order) do Category(c, shownAs[c] or c, cats[c], made[c]) end
    if #loose > 0 then Category("", EUI.L("Uncategorized"), loose) end
    return out
end
function AM.Categories()
    local seen, out, s = {}, {}, Store()
    for _, a in ipairs(AM.List()) do
        if a.category and not seen[a.category] then
            seen[a.category] = true
            out[#out + 1] = a.category
        end
    end
    for _, c in ipairs(s and s.categories or {}) do
        if not seen[c] then seen[c] = true; out[#out + 1] = c end
    end
    table.sort(out, function(x, y) return x:lower() < y:lower() end)
    return out
end
function AM.AddCategory(name)
    name = Plain(name or "")
    if name == "" then return false end
    for _, c in ipairs(AM.Categories()) do
        if c:lower() == name:lower() then return false end
    end
    table.insert(Store(true).categories, name)
    return true
end
function AM.RemoveCategory(name)
    local s = Store(true)
    for i, c in ipairs(s.categories) do
        if c == name then table.remove(s.categories, i); break end
    end
    for addon, category in pairs(s.catOf) do
        if category == name then s.catOf[addon] = nil end
    end
end
function AM.SetCategory(name, value) Store(true).catOf[name] = value end
function AM.Cpu(name)
    if not (C_AddOnProfiler and C_AddOnProfiler.IsEnabled()) then return nil end
    local metric = Enum.AddOnProfilerMetric.SessionAverageTime
    local mine = C_AddOnProfiler.GetAddOnMetric(name, metric)
    local total = C_AddOnProfiler.GetApplicationMetric(metric) - C_AddOnProfiler.GetOverallMetric(metric) + mine
    if total <= 0 then return nil end
    return mine / total * 100
end
local lastMemory = 0
function AM.RefreshMemory(force)
    local now = GetTime()
    if not force and now - lastMemory < 15 then return end
    lastMemory = now
    UpdateAddOnMemoryUsage()
end
function AM.Memory(name) return GetAddOnMemoryUsage(name) end
function AM.Characters()
    local s, me = Store(), CharKey()
    local out, seen = { me }, { [me] = true }
    if s then
        local keys = {}
        for key in pairs(s.chars) do
            if not seen[key] then keys[#keys + 1] = key end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do out[#out + 1] = key end
    end
    return out
end
local hooked, bypass = false, false
function AM.HookMenu()
    if hooked then return end
    hooked = true
    EventUtil.ContinueOnAddOnLoaded("Blizzard_AddOnList", function()
        local addonList = _G.AddonList
        if not addonList then return end
        addonList:HookScript("OnShow", function(self)
            local s = Store()
            if not (s and s.enabled and s.menu) then return end
            if bypass then bypass = false; return end
            if InCombatLockdown() then return end
            HideUIPanel(self)
            AM.Open(true)
            local menu = _G.GameMenuFrame
            local function CloseMenu()
                if menu and menu:IsShown() and not InCombatLockdown() then HideUIPanel(menu) end
            end
            CloseMenu()
            C_Timer.After(0, CloseMenu)
        end)
    end)
end
function AM.ShowBlizzardList()
    bypass = true
    ShowUIPanel(_G.AddonList)
end
local function Offer()
    local s = Store()
    if not (s and s.enabled) or s.quiet or InCombatLockdown() then return end
    local n = #AM.Pending()
    if n == 0 then return end
    EUI:ShowConfirmPopup({
        title = EUI.L("Addon Manager"),
        message = EUI.Lf("Your addons on this character differ from your profile (%d). Apply the changes and reload?", n),
        confirmText = EUI.L("Apply and Reload"), cancelText = EUI.L("Later"),
        reload = true, onConfirm = AM.ApplyNative,
    })
end
local function Copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end
local function Same(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end
function AM.BeginEdit()
    local s = Store()
    if not s or s.backup then return end
    local overrides = {}
    for key, c in pairs(s.chars) do overrides[key] = Copy(c.overrides or {}) end
    s.backup = { defaults = Copy(s.defaults), overrides = overrides }
end
function AM.Edited()
    local s = Store()
    local b = s and s.backup
    if not b then return false end
    if not Same(b.defaults, s.defaults) then return true end
    for key, c in pairs(s.chars) do
        if not Same(b.overrides[key] or {}, c.overrides or {}) then return true end
    end
    for key, o in pairs(b.overrides) do
        if not s.chars[key] and next(o) then return true end
    end
    return false
end
function AM.Discard()
    local s = Store()
    local b = s and s.backup
    if not b then return end
    s.defaults = b.defaults
    for key, c in pairs(s.chars) do c.overrides = b.overrides[key] or {} end
    s.backup = nil
end
function AM.EndEdit(keep)
    if keep then local s = Store(); if s then s.backup = nil end
    else AM.Discard() end
end
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local s = Store()
    if s and s.backup then AM.Discard() end
    if not (s and s.enabled) then return end
    Remember(s)
    if s.menu then AM.HookMenu() end
    C_Timer.After(3, Offer)
end)
AM.Store, AM.CharKey = Store, CharKey
function AM.Label(key)
    local s = Store()
    local c = s and s.chars[key]
    if c and c.label then return c.label end
    if EUI.IS_FOREVER then return key:match("^(.-) %- ") or key end
    return key
end
function AM.SetEnabled(on)
    if on then
        local s = Store(true)
        s.enabled = true
        Remember(s)
        if s.menu then AM.HookMenu() end
    else
        local s = Store()
        if s then s.enabled = nil end
    end
end
function AM.Open(show)
    EUI:EnsureLoaded()
    if EUI.AddonManagerWindow then EUI.AddonManagerWindow(show) end
end
SLASH_EUIADDONS1 = "/euiaddons"
SlashCmdList["EUIADDONS"] = function() AM.Open() end
