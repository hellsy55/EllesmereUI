-------------------------------------------------------------------------------
--  EllesmereUIFriends.lua
--  Custom Friends List with groups, notes, and realm grouping for EllesmereUI.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

local EBS = EllesmereUI.Lite.NewAddon("EllesmereUIFriends")

local PP = EllesmereUI.PP

local EG = EllesmereUI.ELLESMERE_GREEN

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-- Global friend groups storage (not tied to profiles, excluded from import/export)
local function GetFriendGroupsGlobal()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.global then EllesmereUIDB.global = {} end
    local g = EllesmereUIDB.global
    if not g.friendGroups then g.friendGroups = {} end
    if not g.friendAssignments then g.friendAssignments = {} end
    if g.friendFavCollapsed == nil then g.friendFavCollapsed = false end
    if g.friendPendingCollapsed == nil then g.friendPendingCollapsed = false end
    if g.friendUngroupedCollapsed == nil then g.friendUngroupedCollapsed = false end
    if not g.friendNotes then g.friendNotes = {} end
    if not g.friendGroupColors then g.friendGroupColors = {} end
    -- Full group order: includes "_favorites", custom group names, and "_ungrouped"
    -- Built/validated on first access to handle legacy data
    if not g.friendGroupOrder then
        g.friendGroupOrder = {}
    end
    return g
end

-- Internal keys for Favorites and ungrouped in the order list
local ORDER_FAVORITES = "_favorites"
local ORDER_UNGROUPED = "_ungrouped"

-- Validate/rebuild the full group order so it contains all groups exactly once.
-- Preserves existing order, appends any missing entries.
local function GetValidGroupOrder()
    local fg = GetFriendGroupsGlobal()
    local order = fg.friendGroupOrder

    -- Build set of what should exist
    local needed = {}
    needed[ORDER_FAVORITES] = true
    needed[ORDER_UNGROUPED] = true
    for _, g in ipairs(fg.friendGroups) do
        needed[g.name] = true
    end

    -- Remove stale entries
    local clean = {}
    local seen = {}
    for _, key in ipairs(order) do
        if needed[key] and not seen[key] then
            clean[#clean + 1] = key
            seen[key] = true
        end
    end

    -- Append missing entries (Favorites first, then custom, then ungrouped)
    if not seen[ORDER_FAVORITES] then
        table.insert(clean, 1, ORDER_FAVORITES)
        seen[ORDER_FAVORITES] = true
    end
    for _, g in ipairs(fg.friendGroups) do
        if not seen[g.name] then
            -- Insert before ungrouped if it exists, otherwise append
            local ungroupedIdx
            for i, k in ipairs(clean) do
                if k == ORDER_UNGROUPED then ungroupedIdx = i; break end
            end
            if ungroupedIdx then
                table.insert(clean, ungroupedIdx, g.name)
            else
                clean[#clean + 1] = g.name
            end
            seen[g.name] = true
        end
    end
    if not seen[ORDER_UNGROUPED] then
        clean[#clean + 1] = ORDER_UNGROUPED
        seen[ORDER_UNGROUPED] = true
    end

    fg.friendGroupOrder = clean
    return clean
end

-- Modules temporarily disabled for public release (Coming Soon).
-- Force-overrides the per-module "enabled" flag so these do absolutely nothing
-- regardless of what users have in their SavedVariables.
local TEMP_DISABLED = {
    -- minimap = true,
    -- questTracker = true,
    -- cursor  = true,
}
_G._EBS_TEMP_DISABLED = TEMP_DISABLED

local defaults = {
    profile = {
        friends = {
            enabled        = true,
            scale          = 1,
            position       = nil,
            bgR            = 0.05, bgG = 0.05, bgB = 0.055, bgAlpha = 1,
            tileR          = 0,     tileG = 0,    tileB = 0,    tileAlpha = 0.35,
            showBorder     = true,
            borderSize     = 1,
            borderR        = 0, borderG = 0, borderB = 0, borderA = 1,
            useClassColor  = false,
            useAccentTab   = true,
            showClassIcons = true,
            iconStyle      = "modern",
            classColorNames = true,
            nameColorR      = 0.863, nameColorG = 0.820, nameColorB = 0.565,
            accentColors   = true,
            factionBanners = false,
            showRegionIcons = true,
            autoAcceptFriendInvites = false,
            showOffline    = true,
            groupsEnabled  = true,
            showUngrouped  = true,
            visibility     = "always",
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
        },
    },
}

-------------------------------------------------------------------------------
--  Utility
-------------------------------------------------------------------------------
local function GetBorderColor(cfg)
    if cfg.useClassColor then
        -- Flag name is legacy ("useClassColor") but both minimap and friends
        -- now use the live EllesmereUI accent color when it's set. The flag
        -- name is kept as-is for backwards compat with stored SV data.
        return EG.r, EG.g, EG.b, 1
    end
    return cfg.borderR, cfg.borderG, cfg.borderB, cfg.borderA or 1
end

-------------------------------------------------------------------------------
--  Combat safety
-------------------------------------------------------------------------------
local pendingApply = false
local ApplyAll  -- forward declaration

local function QueueApplyAll()
    if pendingApply then return end
    pendingApply = true
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    if pendingApply then
        pendingApply = false
        ApplyAll()
    end
end)




-- Hide all textures on a frame (used by one-time skinning passes)
local function StripTextures(f)
    if not f then return end
    for i = 1, select("#", f:GetRegions()) do
        local region = select(i, f:GetRegions())
        if region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
end

-------------------------------------------------------------------------------
--  Raid Tab Skinning
-------------------------------------------------------------------------------
-- Taint-safe raid tab skinning: NEVER CreateTexture, CreateFrame, or
-- PP.CreateBorder on any frame in the RaidFrame tree. These permanently
-- taint the frame, breaking ClaimRaidFrame -> RaidFrame:SetParent().
-- Safe operations: SetTexture(""), font/color on FontStrings, HookScript,
-- BackdropTemplateMixin.

local function SkinRaidRoleIcon(icon)
    -- No-op: CreateTexture on protected parent taints
end

local function SkinRaidRoleCount(frame)
    if not frame or GetFFD(frame).skinned then return end
    GetFFD(frame).skinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    for i = 1, select("#", frame:GetRegions()) do
        local region = select(i, frame:GetRegions())
        if region:IsObjectType("FontString") then
            region:SetFont(fontPath, 10, "")
            region:SetTextColor(1, 1, 1, 0.8)
        end
    end
end

local function SkinRaidTabButton(btn)
    if not btn or GetFFD(btn).btnSkinned then return end
    GetFFD(btn).btnSkinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    -- Hide Blizzard textures with SetTexture("") (not SetAlpha)
    for i = 1, select("#", btn:GetRegions()) do
        local region = select(i, btn:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetTexture("")
        end
    end
    -- Clear state textures so Blizzard doesn't re-apply them
    if btn.SetNormalTexture then btn:SetNormalTexture("") end
    if btn.SetPushedTexture then btn:SetPushedTexture("") end
    if btn.SetHighlightTexture then btn:SetHighlightTexture("") end
    if btn.SetDisabledTexture then btn:SetDisabledTexture("") end
    -- Dark bg + border via BackdropTemplateMixin (no child frames)
    if BackdropTemplateMixin then
        Mixin(btn, BackdropTemplateMixin)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.025, 0.035, 0.045, 0.92)
        btn:SetBackdropBorderColor(1, 1, 1, 0.4)
    end
    local text = btn:GetFontString()
    if text then
        text:SetFont(fontPath, 9, "")
        text:SetTextColor(1, 1, 1, 0.5)
        text:ClearAllPoints()
        text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    end
    btn:HookScript("OnEnter", function()
        local r, g, b, a1, a2 = 1, 1, 1, 0.7, 0.6
        if GetFFD(btn).accent then
            r, g, b = EG.r, EG.g, EG.b
            a1, a2 = 1, 0.8
        end
        if text then text:SetTextColor(r, g, b, a1) end
        if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(r, g, b, a2) end
    end)
    btn:HookScript("OnLeave", function()
        local r, g, b, a1, a2 = 1, 1, 1, 0.5, 0.4
        if GetFFD(btn).accent then
            r, g, b = EG.r, EG.g, EG.b
            a1, a2 = 0.7, 0.5
        end
        if text then text:SetTextColor(r, g, b, a1) end
        if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(r, g, b, a2) end
    end)
end

local RAID_TAB_BUTTONS = {
    "RaidFrameConvertToRaidButton",
    "RaidFrameRaidInfoButton",
    "QuickJoinFrame.JoinQueueButton",
}

local function SkinCheckbox(checkbox)
    if not checkbox or GetFFD(checkbox).skinned then return end
    GetFFD(checkbox).skinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    -- Safe: SetTexture("") on existing textures, font changes on FontStrings
    if checkbox.SetNormalTexture then checkbox:SetNormalTexture("") end
    if checkbox.SetPushedTexture then checkbox:SetPushedTexture("") end
    if checkbox.SetHighlightTexture then checkbox:SetHighlightTexture("") end
    if checkbox.SetDisabledTexture then checkbox:SetDisabledTexture("") end
    for i = 1, select("#", checkbox:GetRegions()) do
        local region = select(i, checkbox:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetTexture("")
        end
    end
    local text = checkbox.Text or checkbox.text or (checkbox.GetName and _G[checkbox:GetName().."Text"])
    if text and text.SetFont then
        text:SetFont(fontPath, 10, "")
        text:SetTextColor(1, 1, 1, 0.8)
    end
end

local function SkinRaidInfoFrame()
    -- Intentionally left unstyled (Blizzard default)
end

local function SkinRaidGroup(group)
    if not group or GetFFD(group).skinned then return end
    GetFFD(group).skinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    local ar, ag, ab = EG.r, EG.g, EG.b
    local groupName = group:GetName()
    -- Hide textures with SetTexture("") (not SetAlpha)
    for i = 1, select("#", group:GetRegions()) do
        local region = select(i, group:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetTexture("")
        end
    end
    -- Bg + border via BackdropTemplateMixin (no child frames)
    if BackdropTemplateMixin then
        Mixin(group, BackdropTemplateMixin)
        group:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        group:SetBackdropColor(0.025, 0.025, 0.03, 0.98)
        group:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
    end
    -- Font changes on FontStrings are safe
    local labelFrame = _G[groupName .. "Label"]
    if labelFrame then
        for i = 1, select("#", labelFrame:GetRegions()) do
            local region = select(i, labelFrame:GetRegions())
            if region and region:IsObjectType("FontString") then
                region:SetFont(fontPath, 10, "")
                region:SetTextColor(ar, ag, ab, 1)
                region:SetShadowOffset(1, -1)
                region:SetShadowColor(0, 0, 0, 0.9)
            end
        end
        local fontString = labelFrame.GetFontString and labelFrame:GetFontString()
        if fontString and fontString.SetFont then
            fontString:SetFont(fontPath, 10, "")
            fontString:SetTextColor(ar, ag, ab, 1)
            fontString:SetShadowOffset(1, -1)
            fontString:SetShadowColor(0, 0, 0, 0.9)
        end
    end
end

local function SkinRaidSlot(slot)
    if not slot or GetFFD(slot).skinned then return end
    GetFFD(slot).skinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    -- Hide textures with SetTexture("")
    for i = 1, select("#", slot:GetRegions()) do
        local region = select(i, slot:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetTexture("")
        end
    end
    -- Bg + border via BackdropTemplateMixin
    if BackdropTemplateMixin then
        Mixin(slot, BackdropTemplateMixin)
        slot:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        slot:SetBackdropColor(0.045, 0.045, 0.05, 0.9)
        slot:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.7)
    end
    for i = 1, select("#", slot:GetRegions()) do
        local region = select(i, slot:GetRegions())
        if region and region:IsObjectType("FontString") then
            region:SetFont(fontPath, 9, "")
        end
    end
    slot:HookScript("OnEnter", function()
        if slot.SetBackdropColor then slot:SetBackdropColor(0.07, 0.07, 0.08, 0.95) end
    end)
    slot:HookScript("OnLeave", function()
        if slot.SetBackdropColor then slot:SetBackdropColor(0.045, 0.045, 0.05, 0.9) end
    end)
end

local function SkinRaidGroupButton(btn)
    if not btn or GetFFD(btn).skinned then return end
    GetFFD(btn).skinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    -- Hide textures with SetTexture("")
    for i = 1, select("#", btn:GetRegions()) do
        local region = select(i, btn:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetTexture("")
        end
    end
    -- Bg + border via BackdropTemplateMixin
    if BackdropTemplateMixin then
        Mixin(btn, BackdropTemplateMixin)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)
    end
    for i = 1, select("#", btn:GetRegions()) do
        local region = select(i, btn:GetRegions())
        if region and region:IsObjectType("FontString") then
            region:SetFont(fontPath, 9, "")
        end
    end
    btn:HookScript("OnEnter", function()
        if btn.SetBackdropColor then btn:SetBackdropColor(0.1, 0.1, 0.12, 1) end
    end)
    btn:HookScript("OnLeave", function()
        if btn.SetBackdropColor then btn:SetBackdropColor(0.06, 0.06, 0.07, 0.95) end
    end)
end

local function SkinRaidTab()

    for _, name in ipairs(RAID_TAB_BUTTONS) do
        local btn
        if name:find("%.") then
            local parts = {strsplit(".", name)}
            btn = _G[parts[1]]
            for i = 2, #parts do
                if btn then btn = btn[parts[i]] end
            end
        else
            btn = _G[name]
        end
        if btn then SkinRaidTabButton(btn) end
    end
    for i = 1, 40 do
        local playerBtn = _G["RaidGroupButton" .. i]
        if playerBtn then SkinRaidGroupButton(playerBtn) end
    end
    for i = 1, 8 do
        local groupFrame = _G["RaidGroup" .. i]
        if groupFrame then
            SkinRaidGroup(groupFrame)
            for j = 1, 5 do
                local slot = _G["RaidGroup" .. i .. "Slot" .. j]
                if slot then SkinRaidSlot(slot) end
            end
        end
    end
    local raidFrame = _G.RaidFrame
    if raidFrame then
        for i = 1, select("#", raidFrame:GetChildren()) do
            local child = select(i, raidFrame:GetChildren())
            if child then
                for j = 1, select("#", child:GetRegions()) do
                    local region = select(j, child:GetRegions())
                    if region and region:IsObjectType("Texture") then
                        local tex = region:GetTexture()
                        if tex and type(tex) == "string" then
                            local texLower = tex:lower()
                            if texLower:find("role") or texLower:find("tank") or
                               texLower:find("healer") or texLower:find("dps") or
                               texLower:find("damager") then
                                SkinRaidRoleIcon(region)
                            end
                        end
                    end
                end
            end
        end
    end
    SkinRaidInfoFrame()

    -- Border via BackdropTemplateMixin (no CreateFrame on protected frames)
    if raidFrame and not GetFFD(raidFrame).borderAdded then
        GetFFD(raidFrame).borderAdded = true
        if BackdropTemplateMixin then
            Mixin(raidFrame, BackdropTemplateMixin)
            raidFrame:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            raidFrame:SetBackdropBorderColor(1, 1, 1, 0.1)
        end
    end

    -- Skip layout changes during combat, M+, or PvP
    local inMplus2 = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
    local _, iType2 = IsInInstance()
    local inPvP2 = (iType2 == "pvp" or iType2 == "arena")
    if InCombatLockdown() or inMplus2 or inPvP2 then return end

    -- Reposition RaidFrame content
    if raidFrame then
        raidFrame:ClearAllPoints()
        raidFrame:SetPoint("TOPLEFT", FriendsFrame, "TOPLEFT", 15, -76)
        raidFrame:SetPoint("BOTTOMRIGHT", FriendsFrame, "BOTTOMRIGHT", -15, 35)
    end

    -- Reposition buttons
    local convertBtn = _G.RaidFrameConvertToRaidButton
    local raidInfoBtn = _G.RaidFrameRaidInfoButton
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if scrollBox and (convertBtn or raidInfoBtn) then
        local btnW = math.floor(raidFrame:GetWidth() / 3)
        if convertBtn then
            convertBtn:ClearAllPoints()
            convertBtn:SetSize(btnW, 22)
            convertBtn:SetPoint("BOTTOMRIGHT", scrollBox, "BOTTOMRIGHT", 0, -22)
        end
        if raidInfoBtn then
            raidInfoBtn:ClearAllPoints()
            raidInfoBtn:SetSize(btnW, 20)
            raidInfoBtn:SetPoint("TOPRIGHT", scrollBox, "TOPRIGHT", 12, 48)
        end
    end

    -- Move top bar icons
    local checkBtn = _G.RaidFrameAllAssistCheckButton
    if checkBtn and not GetFFD(checkBtn).shifted then
        GetFFD(checkBtn).shifted = true
        local p1, rel, p2, ox, oy = checkBtn:GetPoint(1)
        if p1 then checkBtn:SetPoint(p1, rel, p2, (ox or 0) - 62, (oy or 0) + 59) end
    end
    if raidFrame then
        local roleCount = raidFrame.RoleCount
        if roleCount and not GetFFD(roleCount).shifted then
            GetFFD(roleCount).shifted = true
            local p1, rel, p2, ox, oy = roleCount:GetPoint(1)
            if p1 then roleCount:SetPoint(p1, rel, p2, (ox or 0) - 62, (oy or 0) + 59) end
        end
    end

    -- Reposition raid groups: 2 columns
    if raidFrame then
        local groupW = math.floor((raidFrame:GetWidth() - 10) / 2)
        for i = 1, 8 do
            local gf = _G["RaidGroup" .. i]
            if gf then
                gf:ClearAllPoints()
                gf:SetWidth(groupW)
                for j = 1, 5 do
                    local slot = _G["RaidGroup" .. i .. "Slot" .. j]
                    if slot then slot:SetWidth(groupW - 6) end
                end
                if i == 1 then
                    gf:SetPoint("TOPLEFT", raidFrame, "TOPLEFT", 0, 0)
                elseif i == 2 then
                    gf:SetPoint("TOPRIGHT", raidFrame, "TOPRIGHT", 0, 0)
                elseif i % 2 == 1 then
                    local above = _G["RaidGroup" .. (i - 2)]
                    if above then gf:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -14) end
                else
                    local above = _G["RaidGroup" .. (i - 2)]
                    if above then gf:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -14) end
                end
            end
        end
        for i = 1, 40 do
            local btn = _G["RaidGroupButton" .. i]
            if btn then btn:SetWidth(groupW - 6) end
        end
    end
end

local function UpdateRaidTabButtonAccent()
    local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if not fp then return end
    local useAccent = fp.accentColors ~= false
    local ar, ag, ab = EG.r, EG.g, EG.b
    for _, name in ipairs(RAID_TAB_BUTTONS) do
        local btn
        if name:find("%.") then
            local parts = {strsplit(".", name)}
            btn = _G[parts[1]]
            for i = 2, #parts do
                if btn then btn = btn[parts[i]] end
            end
        else
            btn = _G[name]
        end
        if btn and GetFFD(btn).btnSkinned then
            local text = btn:GetFontString()
            GetFFD(btn).accent = useAccent
            if useAccent then
                if text then text:SetTextColor(EG.r, EG.g, EG.b, 0.7) end
                if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(EG.r, EG.g, EG.b, 0.5) end
            else
                if text then text:SetTextColor(1, 1, 1, 0.5) end
                if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(1, 1, 1, 0.4) end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Friends List Skin
-------------------------------------------------------------------------------
local friendsSkinned = false

local CLASS_ICON_SPRITE_BASE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\"
-- Sprite texture paths keyed by style name
local CLASS_ICON_SPRITE_TEX = {}
for _, style in ipairs({"modern", "dark", "light", "clean"}) do
    CLASS_ICON_SPRITE_TEX[style] = CLASS_ICON_SPRITE_BASE .. style .. ".tga"
end
local CLASS_SPRITE_COORDS = {
    WARRIOR     = { 0,     0.125, 0,     0.125 },
    MAGE        = { 0.125, 0.25,  0,     0.125 },
    ROGUE       = { 0.25,  0.375, 0,     0.125 },
    DRUID       = { 0.375, 0.5,   0,     0.125 },
    EVOKER      = { 0.5,   0.625, 0,     0.125 },
    HUNTER      = { 0,     0.125, 0.125, 0.25  },
    SHAMAN      = { 0.125, 0.25,  0.125, 0.25  },
    PRIEST      = { 0.25,  0.375, 0.125, 0.25  },
    WARLOCK     = { 0.375, 0.5,   0.125, 0.25  },
    PALADIN     = { 0,     0.125, 0.25,  0.375 },
    DEATHKNIGHT = { 0.125, 0.25,  0.25,  0.375 },
    MONK        = { 0.25,  0.375, 0.25,  0.375 },
    DEMONHUNTER = { 0.375, 0.5,   0.25,  0.375 },
}

-- Localized class name -> class file token (built once on first use)
local classFileByLocalName = {}
local function BuildClassNameLookup()
    if next(classFileByLocalName) then return end
    if LOCALIZED_CLASS_NAMES_MALE then
        for token, name in pairs(LOCALIZED_CLASS_NAMES_MALE) do
            classFileByLocalName[name] = token
        end
    end
    if LOCALIZED_CLASS_NAMES_FEMALE then
        for token, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
            classFileByLocalName[name] = token
        end
    end
end

-- Friend data cache: populated during RebuildFriendsDataProvider, read per-button.
-- BNet friends keyed by [id], WoW friends keyed by [id + 10000].
local _friendCache = {}
local _FC_WOW_OFFSET = 10000

local function GetCachedFriendInfo(button)
    if not button or not button.buttonType or not button.id then return nil, nil end
    local key
    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        key = button.id
    elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        key = button.id + _FC_WOW_OFFSET
    end
    if not key then return nil, nil end
    local cached = _friendCache[key]
    if cached then
        if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
            return cached, nil
        else
            return nil, cached
        end
    end
    -- Cache miss fallback
    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        return C_BattleNet and C_BattleNet.GetFriendAccountInfo(button.id), nil
    elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        return nil, C_FriendList and C_FriendList.GetFriendInfoByIndex(button.id)
    end
    return nil, nil
end

-- Direct API call version for non-scroll callers (menus, tooltips)
local function GetFriendInfo(button)
    if not button or not button.buttonType or not button.id then return nil, nil end
    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        return C_BattleNet and C_BattleNet.GetFriendAccountInfo(button.id), nil
    elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        return nil, C_FriendList and C_FriendList.GetFriendInfoByIndex(button.id)
    end
    return nil, nil
end

local function GetFriendClassFile(bnetInfo, wowInfo)
    BuildClassNameLookup()
    if bnetInfo and bnetInfo.gameAccountInfo then
        local gi = bnetInfo.gameAccountInfo
        if gi.classID and gi.classID > 0 then
            local _, classFile = GetClassInfo(gi.classID)
            return classFile
        end
        if gi.className then
            return classFileByLocalName[gi.className]
        end
    elseif wowInfo and wowInfo.className then
        return classFileByLocalName[wowInfo.className]
    end
    return nil
end

local function GetFriendKey(button, bnetInfo, wowInfo)
    if bnetInfo then
        return "bnet-" .. (bnetInfo.bnetAccountID or button.id)
    elseif wowInfo and wowInfo.name then
        return "wow-" .. wowInfo.name
    end
    return nil
end

-- Group tag stored in Blizzard friend notes as ||EUI:GroupName||
local EUI_NOTE_TAG = "||EUI:"
local EUI_NOTE_END = "||"

local function ParseGroupFromNote(note)
    if not note or note == "" then return nil, note end
    local tagStart = note:find(EUI_NOTE_TAG, 1, true)
    if not tagStart then return nil, note end
    local groupStart = tagStart + #EUI_NOTE_TAG
    local tagEnd = note:find(EUI_NOTE_END, groupStart, true)
    if not tagEnd then return nil, note end
    local group = note:sub(groupStart, tagEnd - 1)
    -- Strip the tag to get the clean user note
    local clean = note:sub(1, tagStart - 1)
    -- Trim trailing whitespace from user note
    clean = clean:match("^(.-)%s*$") or clean
    if group == "" then return nil, clean end
    return group, clean
end

local function WriteGroupToNote(note, group)
    -- Strip any existing EUI tag first
    local _, clean = ParseGroupFromNote(note)
    if not clean then clean = "" end
    if not group or group == "" then return clean end
    if clean ~= "" then
        return clean .. " " .. EUI_NOTE_TAG .. group .. EUI_NOTE_END
    end
    return EUI_NOTE_TAG .. group .. EUI_NOTE_END
end



-- Offline icon path (displayed when friend is not online)
local OFFLINE_ICON = "Interface\\AddOns\\EllesmereUIFriends\\Media\\offline.png"

-- Region display names for friend region tooltips
local MINI_DISPLAY = {
    namerica = "North America", samerica = "South America",
    australia = "Australia", europe = "Europe",
    russia = "Russia", korea = "Korea",
    taiwan = "Taiwan", china = "China",
}

-- Status orb atlas (online/away/dnd indicator on friend buttons)
local _orbFile, _orbL, _orbR, _orbT, _orbB
do
    local orbInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("lootroll-animreveal-a")
    if orbInfo and orbInfo.file then
        _orbFile = orbInfo.file
        local aL = orbInfo.leftTexCoord or 0
        local aR = orbInfo.rightTexCoord or 1
        local aT = orbInfo.topTexCoord or 0
        local aB = orbInfo.bottomTexCoord or 1
        local aW, aH = aR - aL, aB - aT
        _orbL, _orbR, _orbT, _orbB = aL, aL + aW/6, aT, aT + aH/2
    end
end

local function UpdateClassIcon(button, bnetInfo, wowInfo)
    -- Skip dividers
    if button.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then return end
    if not button.buttonType then return end

    local p = EBS.db.profile.friends

    -- Hide Blizzard's game icon
    local gameIcon = button.gameIcon
    if gameIcon then gameIcon:SetAlpha(0) end

    if not p.showClassIcons then
        if GetFFD(button).classIcon then GetFFD(button).classIcon:Hide() end
        return
    end

    -- Create icon texture
    if not GetFFD(button).classIcon then
        GetFFD(button).classIcon = button:CreateTexture(nil, "ARTWORK", nil, 2)
    end
    local icon = GetFFD(button).classIcon
    local h = button:GetHeight() - 4
    if h <= 0 then icon:Hide(); return end

    -- Determine online state
    local state = "offline"  -- default
    if bnetInfo and bnetInfo.gameAccountInfo then
        local gi = bnetInfo.gameAccountInfo
        if gi.isOnline then
            if gi.clientProgram == BNET_CLIENT_WOW and (gi.wowProjectID == 1 or gi.wowProjectID == nil) then
                state = "retail"
            else
                state = "other_game"
            end
        end
    elseif wowInfo then
        state = wowInfo.connected and "retail" or "offline"
    end

    -- Apply icon based on state
    icon:ClearAllPoints()

    if state == "retail" then
        -- Class icon with small inset
        local inset = math.floor(h * 0.025 + 0.5)
        icon:SetPoint("LEFT", button, "LEFT", 4, 0)
        icon:SetPoint("TOP", button, "TOP", 0, -(2 + inset))
        icon:SetPoint("BOTTOM", button, "BOTTOM", 0, 2 + inset)
        local iconH = h - inset * 2
        if iconH > 0 then icon:SetWidth(iconH) end

        local classFile = GetFriendClassFile(bnetInfo, wowInfo)
        if not classFile then icon:Hide(); return end

        local style = p.iconStyle or "modern"
        if style == "blizzard" then
            icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
            if coords then icon:SetTexCoord(unpack(coords)) end
        else
            local coords = CLASS_SPRITE_COORDS[classFile]
            if coords then
                icon:SetTexture(CLASS_ICON_SPRITE_TEX[style] or (CLASS_ICON_SPRITE_BASE .. style .. ".tga"))
                icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            end
        end
        icon:SetDesaturated(false)
        icon:SetAlpha(1)

    elseif state == "other_game" then
        -- Smaller icon using Blizzard's game icon texture
        local smallH = math.floor(h * 0.75)
        icon:SetSize(smallH, smallH)
        icon:SetPoint("LEFT", button, "LEFT", 4 + math.floor((h - smallH) / 2), 0)
        if gameIcon then
            local tex = gameIcon:GetTexture()
            if tex then
                icon:SetTexture(tex)
                icon:SetTexCoord(0, 1, 0, 1)
            end
        end
        icon:SetDesaturated(false)
        icon:SetAlpha(1)

    else -- offline
        local smallH = math.floor(h * 0.75)
        icon:SetSize(smallH, smallH)
        icon:SetPoint("LEFT", button, "LEFT", 4 + math.floor((h - smallH) / 2), 0)
        icon:SetTexture(OFFLINE_ICON)
        icon:SetTexCoord(0, 1, 0, 1)
        icon:SetDesaturated(false)
        icon:SetAlpha(0.5)
    end

    icon:Show()
end

-- Class color hex codes (built on first use per class)
local _classColorCodes = {}
local function _getClassColorCode(classFile)
    local code = _classColorCodes[classFile]
    if code then return code end
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not cc then return nil end
    code = format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
    _classColorCodes[classFile] = code
    return code
end

-- Apply class color to the character name portion of a friend button
local function UpdateNameColor(button, bnetInfo, wowInfo)
    local p = EBS.db.profile.friends
    local nameText = button.name or button.Name
    if not nameText then return end

    if not p.classColorNames then return end

    local classFile = GetFriendClassFile(bnetInfo, wowInfo)
    if not classFile then return end

    if wowInfo then
        -- WoW friend: entire name is the character
        local cc = RAID_CLASS_COLORS[classFile]
        if cc then nameText:SetTextColor(cc.r, cc.g, cc.b) end
    elseif bnetInfo then
        -- BNet friend: color only the (CharName) portion
        local text = nameText:GetText()
        if not text then return end
        local colorCode = _getClassColorCode(classFile)
        if not colorCode then return end
        local colored = text:gsub("%((.-)%)", "(" .. colorCode .. "%1|r)")
        if colored ~= text then
            nameText:SetText(colored)
        end
    end
end

-- Faction overlay texture paths
local FACTION_TEX_ALLIANCE = "Interface\\AddOns\\EllesmereUIFriends\\Media\\alliance.png"
local FACTION_TEX_HORDE    = "Interface\\AddOns\\EllesmereUIFriends\\Media\\horde.png"
local FACTION_TEX_NEUTRAL  = "Interface\\AddOns\\EllesmereUIFriends\\Media\\neutral.png"

-- Apply faction background overlay to a friend button
local function UpdateFactionOverlay(button, bnetInfo, wowInfo)
    local factionName
    local isRetail = false
    if bnetInfo and bnetInfo.gameAccountInfo then
        local gi = bnetInfo.gameAccountInfo
        factionName = gi.factionName
        if gi.clientProgram == BNET_CLIENT_WOW and (gi.wowProjectID == 1 or gi.wowProjectID == nil) and gi.isOnline then
            isRetail = true
        end
    elseif wowInfo then
        factionName = UnitFactionGroup("player")
        isRetail = true
    end

    if not GetFFD(button).factionBg then
        GetFFD(button).factionBg = button:CreateTexture(nil, "BACKGROUND", nil, 3)
    end

    local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
    local showFaction = fp and fp.factionBanners ~= false
    local texPath
    if showFaction and isRetail and factionName == "Alliance" then
        texPath = FACTION_TEX_ALLIANCE
    elseif showFaction and isRetail and factionName == "Horde" then
        texPath = FACTION_TEX_HORDE
    else
        texPath = FACTION_TEX_NEUTRAL
    end

    local tex = GetFFD(button).factionBg
    tex:SetTexture(texPath)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    tex:SetAlpha(0.2)
    tex:Show()
end



-- Skin a single friend button
local function SkinFriendButton(button)
    if GetFFD(button).skinned then return end
    GetFFD(button).skinned = true

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT

    local function ApplyFont(fs, size)
        if not fs or not fs.SetFont then return end
        fs:SetFont(fontPath, size, "")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.8)
    end

    -- Tile background
    local tileBg = button:CreateTexture(nil, "BACKGROUND", nil, 2)
    tileBg:SetAllPoints()
    tileBg:SetColorTexture(0, 0, 0, 0.10)
    GetFFD(button).tileBg = tileBg

    -- Strip Blizzard's highlight texture (SetVertexColor to avoid taint risk)
    local blizzHighlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if blizzHighlight then blizzHighlight:SetVertexColor(0, 0, 0, 0) end

    -- Hover highlight (OnEnter/OnLeave)
    local hover = button:CreateTexture(nil, "ARTWORK", nil, -7)
    hover:SetAllPoints()
    hover:SetAtlas("groupfinder-highlightbar-green")
    hover:SetDesaturated(true)
    hover:SetVertexColor(0.4, 0.7, 1.0)
    hover:SetAlpha(1)
    hover:Hide()
    local hoverFill = button:CreateTexture(nil, "ARTWORK", nil, -8)
    hoverFill:SetAllPoints()
    hoverFill:SetColorTexture(1, 1, 1, 0.02)
    hoverFill:SetBlendMode("ADD")
    hoverFill:Hide()
    button:HookScript("OnEnter", function() hover:Show(); hoverFill:Show() end)
    button:HookScript("OnLeave", function() hover:Hide(); hoverFill:Hide() end)

    -- Apply font to friend row text
    local nameText = button.name or button.Name
    ApplyFont(nameText, 12)
    local infoText = button.info or button.Info
    ApplyFont(infoText, 9)
    local statusText = button.status or button.Status
    ApplyFont(statusText, 9)
    local gameText = button.gameText or button.GameText
    ApplyFont(gameText, 9)

    -- Offset name text right for class icon
    if nameText then
        local p1, rel, p2, x, y = nameText:GetPoint(1)
        if p1 then
            nameText:SetPoint(p1, rel, p2, (x or 0) + 20, y or 0)
        end
    end
end

-- Process all visible friend buttons (used only on initial OnShow as safety net)
local function ProcessFriendButtons()
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if not scrollBox then return end
    for _, button in scrollBox:EnumerateFrames() do
        if GetFFD(button).pendingSkinned then
            -- Re-apply pending button colors (survive settings changes)
            if GetFFD(button).name then GetFFD(button).name:SetTextColor(0.51, 0.784, 1, 1) end
            if GetFFD(button).subText then GetFFD(button).subText:SetTextColor(0.5, 0.5, 0.5, 0.8) end
            if GetFFD(button).tileBg then GetFFD(button).tileBg:SetColorTexture(0.05, 0.15, 0.20, 0.30) end
        elseif button.buttonType and button.buttonType ~= FRIENDS_BUTTON_TYPE_DIVIDER then
            SkinFriendButton(button)
            local bnetInfo, wowInfo = GetCachedFriendInfo(button)
            UpdateClassIcon(button, bnetInfo, wowInfo)
            UpdateNameColor(button, bnetInfo, wowInfo)
            UpdateFactionOverlay(button, bnetInfo, wowInfo)
        end
    end
end

-- Skin a single ScrollBox+ScrollBar pair with thin EUI track
local function SkinOneScrollbar(scrollBox, scrollBar)
    if not scrollBox or not scrollBar then return end
    if GetFFD(scrollBox).track then return end

    scrollBar:SetAlpha(0)
    GetFFD(scrollBox).scrollBar = scrollBar

    -- Parent to UIParent (parenting to FriendsListFrame taints)
    local track = CreateFrame("Frame", nil, UIParent)
    track:Hide()
    track:SetFrameStrata("HIGH")
    track:SetWidth(4)
    track:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 2, 0)
    track:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 2, 0)
    track:SetFrameLevel(scrollBox:GetFrameLevel() + 10)
    GetFFD(scrollBox).track = track

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(1, 1, 1, 0)
    trackBg:SetAllPoints()

    -- Thumb
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(4)
    thumb:SetHeight(60)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetColorTexture(1, 1, 1, 0.4)
    thumbTex:SetAllPoints()

    -- Hit area (wider clickable region for the scrollbar)
    local hitArea = CreateFrame("Button", nil, UIParent)
    hitArea:SetFrameStrata("HIGH")
    hitArea:Hide()
    track._hitArea = hitArea
    hitArea:SetWidth(16)
    hitArea:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", -4, -2)
    hitArea:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", -4, 2)
    hitArea:SetFrameLevel(track:GetFrameLevel() + 2)
    hitArea:EnableMouse(true)
    hitArea:RegisterForDrag("LeftButton")

    local SCROLL_STEP = 40
    local SCROLLBAR_ALPHA = 0.35
    local isDragging = false
    local dragStartY, dragStartPct

    local function GetPct()
        return scrollBar.GetScrollPercentage and scrollBar:GetScrollPercentage() or 0
    end

    local function GetExtent()
        return scrollBar.GetVisibleExtentPercentage and scrollBar:GetVisibleExtentPercentage() or 1
    end

    local function StepToPct()
        local ext = GetExtent()
        if ext >= 1 then return 0 end
        local totalH = scrollBox:GetHeight() / ext
        if totalH <= 0 then return 0 end
        return SCROLL_STEP / totalH
    end

    local function StopScrollDrag()
        if not isDragging then return end
        isDragging = false
        thumb:SetScript("OnUpdate", nil)
    end

    local function UpdateScrollThumb()
        local ext = GetExtent()
        if ext >= 1 then track:SetAlpha(0); return end
        track:SetAlpha(SCROLLBAR_ALPHA)
        local pct = GetPct()
        local trackH = track:GetHeight()
        local thumbH = math.max(20, trackH * ext)
        thumb:SetHeight(thumbH)
        local maxTravel = trackH - thumbH
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(pct * maxTravel))
    end

    -- Direct scroll (no smoothing, no C_Timer allocations)
    scrollBox:SetScript("OnMouseWheel", function(_, delta)
        if GetExtent() >= 1 then return end
        local step = StepToPct()
        local newPct = math.max(0, math.min(1, GetPct() - delta * step))
        scrollBar:SetScrollPercentage(newPct)
        UpdateScrollThumb()
    end)

    -- Thumb drag
    local function ScrollThumbOnUpdate(self)
        if not IsMouseButtonDown("LeftButton") then StopScrollDrag(); return end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / self:GetEffectiveScale()
        local deltaY = dragStartY - cursorY
        local trackH = track:GetHeight()
        local maxTravel = trackH - self:GetHeight()
        if maxTravel <= 0 then return end
        local newPct = math.max(0, math.min(1, dragStartPct + deltaY / maxTravel))
        scrollBar:SetScrollPercentage(newPct)
        UpdateScrollThumb()
    end

    thumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        isDragging = true
        local _, cursorY = GetCursorPosition()
        dragStartY = cursorY / self:GetEffectiveScale()
        dragStartPct = GetPct()
        self:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    thumb:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        StopScrollDrag()
    end)

    -- Hit area click-to-jump
    hitArea:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        if GetExtent() >= 1 then return end
        local _, cy = GetCursorPosition()
        cy = cy / track:GetEffectiveScale()
        local top = track:GetTop() or 0
        local trackH = track:GetHeight()
        local thumbH = thumb:GetHeight()
        if trackH <= thumbH then return end
        local frac = (top - cy - thumbH / 2) / (trackH - thumbH)
        frac = math.max(0, math.min(1, frac))
        scrollBar:SetScrollPercentage(frac)
        UpdateScrollThumb()
        isDragging = true
        dragStartY = cy
        dragStartPct = frac
        thumb:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    hitArea:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        StopScrollDrag()
    end)

    -- Keep thumb in sync with Blizzard scroll changes (no C_Timer, direct call)
    if scrollBar.RegisterCallback then
        scrollBar:RegisterCallback("OnScroll", UpdateScrollThumb)
    end
    -- Update thumb when content size changes (collapse/expand, filter toggle)
    if scrollBox.RegisterCallback then
        scrollBox:RegisterCallback("OnDataRangeChanged", UpdateScrollThumb)
    end
    C_Timer.After(0.1, UpdateScrollThumb)
end

-- Skin known scrollbars by direct reference
local function SkinScrollbars()
    -- FriendsListFrame uses our own custom ScrollBox (created later),
    -- so we only hide Blizzard's native scrollbar here without creating a track.
    if FriendsListFrame then
        local bar = FriendsListFrame.ScrollBar
            or (FriendsListFrame.ScrollBox and FriendsListFrame.ScrollBox.ScrollBar)
        if bar then bar:SetAlpha(0) end
    end
    -- RecentAlliesFrame has nested structure
    if _G.RecentAlliesFrame and _G.RecentAlliesFrame.List then
        local list = _G.RecentAlliesFrame.List
        if list.ScrollBox then
            local bar = list.ScrollBox.ScrollBar or list.ScrollBar
            if bar then SkinOneScrollbar(list.ScrollBox, bar) end
        end
    end
end

-- Skin a bottom-area button (Add Friend, Send Message, etc.)
local function SkinBottomButton(btn)
    if not btn or GetFFD(btn).btnSkinned then return end
    GetFFD(btn).btnSkinned = true

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT

    StripTextures(btn)

    GetFFD(btn).bg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
    GetFFD(btn).bg:SetColorTexture(0.025, 0.035, 0.045, 0.92)
    GetFFD(btn).bg:SetAllPoints()

    PP.CreateBorder(btn, 1, 1, 1, 0.4, 1, "OVERLAY", 7)

    local text = btn:GetFontString()
    if text then
        text:SetFont(fontPath, 9, "")
        text:SetTextColor(1, 1, 1, 0.5)
        text:ClearAllPoints()
        text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    end

    btn:HookScript("OnEnter", function()
        local r, g, b, a1, a2 = 1, 1, 1, 0.7, 0.6
        if GetFFD(btn).accent then
            r, g, b = EG.r, EG.g, EG.b
            a1, a2 = 1, 0.8
        end
        if text then text:SetTextColor(r, g, b, a1) end
        if PP.GetBorders(btn) then PP.SetBorderColor(btn, r, g, b, a2) end
    end)
    btn:HookScript("OnLeave", function()
        local r, g, b, a1, a2 = 1, 1, 1, 0.5, 0.4
        if GetFFD(btn).accent then
            r, g, b = EG.r, EG.g, EG.b
            a1, a2 = 0.7, 0.5
        end
        if text then text:SetTextColor(r, g, b, a1) end
        if PP.GetBorders(btn) then PP.SetBorderColor(btn, r, g, b, a2) end
    end)
end

-- Skin known buttons by name instead of string-matching
local KNOWN_BUTTONS = {
    "FriendsFrameAddFriendButton",
    "FriendsFrameSendMessageButton",
    "WhoFrameWhoButton",
    "WhoFrameAddFriendButton",
    "WhoFrameGroupInviteButton",
}

local function SkinKnownButtons()
    for _, name in ipairs(KNOWN_BUTTONS) do
        local btn = _G[name]
        if btn then SkinBottomButton(btn) end
    end
end

-- Apply accent coloring to bottom buttons + pending accept buttons (called from ApplyFriends)
local function UpdateBottomButtonAccent()
    local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if not fp then return end
    local useAccent = fp.accentColors ~= false

    -- Helper: apply accent state to a single button (reads EG live, no caching)
    local function ApplyAccentToBtn(btn, labelFS)
        if not btn then return end
        GetFFD(btn).accent = useAccent
        if useAccent then
            if labelFS then labelFS:SetTextColor(EG.r, EG.g, EG.b, 0.7) end
            if PP.GetBorders(btn) then PP.SetBorderColor(btn, EG.r, EG.g, EG.b, 0.5) end
        else
            if labelFS then labelFS:SetTextColor(1, 1, 1, 0.5) end
            if PP.GetBorders(btn) then PP.SetBorderColor(btn, 1, 1, 1, 0.4) end
        end
    end

    -- Bottom buttons (Send Message, Who buttons -- skip Add Friend)
    for _, name in ipairs(KNOWN_BUTTONS) do
        local btn = _G[name]
        if btn and GetFFD(btn).btnSkinned and btn:IsEnabled()
           and name ~= "FriendsFrameAddFriendButton" then
            ApplyAccentToBtn(btn, btn:GetFontString())
        end
    end

    -- Pending invite accept buttons
    local sb = FriendsListFrame and FriendsListFrame.ScrollBox
    if sb then
        for _, btn in sb:EnumerateFrames() do
            if GetFFD(btn).acceptBtn then
                ApplyAccentToBtn(GetFFD(btn).acceptBtn, GetFFD(btn).acceptLabel)
            end
        end
    end

end

-- StaticPopup for creating a new friend group

StaticPopupDialogs["EBS_DELETE_FRIEND_GROUP"] = {
    text = "Delete group \"%s\"?\nFriends in this group will be moved to the default list.",
    button1 = DELETE,
    button2 = CANCEL,
    OnAccept = function(self)
        local gName = self.data
        if not gName then return end
        local fg = GetFriendGroupsGlobal()
        for i = #fg.friendGroups, 1, -1 do
            if fg.friendGroups[i].name == gName then
                -- Remove group tag from all Blizzard friend notes
                local numBN = BNGetNumFriends and BNGetNumFriends() or 0
                for bi = 1, numBN do
                    local bInfo = C_BattleNet and C_BattleNet.GetFriendAccountInfo(bi)
                    if bInfo and bInfo.note then
                        local g = ParseGroupFromNote(bInfo.note)
                        if g == gName then
                            local _, cleanNote = ParseGroupFromNote(bInfo.note)
                            BNSetFriendNote(bInfo.bnetAccountID, cleanNote or "")
                        end
                    end
                end
                table.remove(fg.friendGroups, i)
                break
            end
        end
        if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["EBS_NEW_FRIEND_GROUP"] = {
    text = "Enter group name:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 200,
    OnAccept = function(self)
        local name = (self.EditBox or self.editBox):GetText()
        if not name or name == "" then return end
        local fg = GetFriendGroupsGlobal()

        -- Rename mode
        if self.data and self.data.renameFrom then
            local oldName = self.data.renameFrom
            if name ~= oldName then
                for _, g in ipairs(fg.friendGroups) do
                    if g.name == oldName then
                        g.name = name
                        break
                    end
                end
                -- Rename group tag in all Blizzard friend notes
                local numBN = BNGetNumFriends and BNGetNumFriends() or 0
                for bi = 1, numBN do
                    local bInfo = C_BattleNet and C_BattleNet.GetFriendAccountInfo(bi)
                    if bInfo and bInfo.note then
                        local g = ParseGroupFromNote(bInfo.note)
                        if g == oldName then
                            local newNote = WriteGroupToNote(bInfo.note, name)
                            -- Re-parse to get clean user note, then rebuild with new group
                            local _, cleanNote = ParseGroupFromNote(bInfo.note)
                            BNSetFriendNote(bInfo.bnetAccountID, WriteGroupToNote(cleanNote, name))
                        end
                    end
                end
            end
        else
            -- New group mode: check for duplicate
            for _, g in ipairs(fg.friendGroups) do
                if g.name == name then return end
            end
            fg.friendGroups[#fg.friendGroups + 1] = { name = name, collapsed = false }
            -- Assign the friend who triggered the dialog
            if self.data and self.data.bnetID then
                local bInfo = C_BattleNet.GetAccountInfoByID(self.data.bnetID)
                local rawNote = bInfo and bInfo.note or ""
                BNSetFriendNote(self.data.bnetID, WriteGroupToNote(rawNote, name))
            elseif self.data and self.data.wowName then
                local numWoW = C_FriendList.GetNumFriends()
                for fi = 1, numWoW do
                    local wInfo = C_FriendList.GetFriendInfoByIndex(fi)
                    if wInfo and wInfo.name == self.data.wowName then
                        local rawNote = wInfo.notes or ""
                        C_FriendList.SetFriendNotes(self.data.wowName, WriteGroupToNote(rawNote, name))
                        break
                    end
                end
            end
        end
        if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
        -- Note: _EBS_ScrollToFriend is consumed inside RebuildFriendsDataProvider
    end,
    OnShow = function(self)
        local eb = self.EditBox or self.editBox
        eb:SetText("")
        eb:SetFocus()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}



-- Inject group assignment into Blizzard's friend right-click menu
local function EBS_ModifyFriendMenu(ownerRegion, rootDescription, contextData)
    if not contextData then return end
    -- Origin guard: only run when FriendsFrame is actually open. Without
    -- this, the callback fires during BNet whisper processing (chat
    -- right-click, social system menus) and taints secure execution paths.
    if not FriendsFrame or not FriendsFrame:IsShown() then return end
    local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if not fp or not fp.enabled then return end
    -- Don't add group options for Recent Allies entries
    local raf = _G.RecentAlliesFrame
    if raf and raf:IsShown() then return end

    -- Identify the friend and read current group from Blizzard note
    local isFavorite = false
    local currentGroup, currentNote, bnetID, wowName
    if contextData.bnetIDAccount then
        bnetID = contextData.bnetIDAccount
        local info = C_BattleNet and C_BattleNet.GetAccountInfoByID(bnetID)
        if info then
            isFavorite = info.isFavorite
            currentGroup, currentNote = ParseGroupFromNote(info.note)
        end
    elseif contextData.name then
        wowName = contextData.name
        local numWoW = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
        for fi = 1, numWoW do
            local wInfo = C_FriendList.GetFriendInfoByIndex(fi)
            if wInfo and wInfo.name == wowName then
                currentGroup, currentNote = ParseGroupFromNote(wInfo.notes)
                break
            end
        end
    end
    if not bnetID and not wowName then return end

    -- Favorites are managed by Blizzard, don't show our group options
    if isFavorite then return end

    local fg = GetFriendGroupsGlobal()
    local hasGroups = #fg.friendGroups > 0

    local ar, ag, ab = EG.r, EG.g, EG.b
    local accentHex = format("|cff%02x%02x%02x", ar * 255, ag * 255, ab * 255)

    rootDescription:CreateDivider()
    rootDescription:CreateTitle(accentHex .. "EUI Friend Groups|r")

    -- Helper: write group tag into Blizzard friend note
    local function SetFriendGroup(groupName)
        if bnetID then
            local info = C_BattleNet.GetAccountInfoByID(bnetID)
            local rawNote = info and info.note or ""
            local newNote = WriteGroupToNote(rawNote, groupName)
            BNSetFriendNote(bnetID, newNote)
        elseif wowName then
            local numWoW = C_FriendList.GetNumFriends()
            for fi = 1, numWoW do
                local wInfo = C_FriendList.GetFriendInfoByIndex(fi)
                if wInfo and wInfo.name == wowName then
                    local rawNote = wInfo.notes or ""
                    local newNote = WriteGroupToNote(rawNote, groupName)
                    C_FriendList.SetFriendNotes(wowName, newNote)
                    break
                end
            end
        end
    end

    -- "Add to Group" / "Move to Group" submenu
    local addLabel = currentGroup and "Move to Group" or "Add to Group"
    local addToGroup = rootDescription:CreateButton(addLabel)
    addToGroup:CreateButton("|cff00ff00+|r Add New Group", function()
        local dialog = StaticPopup_Show("EBS_NEW_FRIEND_GROUP")
        if dialog then dialog.data = { bnetID = bnetID, wowName = wowName } end
    end)
    if hasGroups then
        addToGroup:CreateDivider()
        local groupOrder = GetValidGroupOrder()
        for _, gName in ipairs(groupOrder) do
            if gName ~= ORDER_FAVORITES and gName ~= ORDER_UNGROUPED and gName ~= currentGroup then
                addToGroup:CreateButton(gName, function()
                    SetFriendGroup(gName)
                    if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
                end)
            end
        end
    end

    -- "Remove from Group" (disabled if not in a group)
    local removeBtn = rootDescription:CreateButton("Remove from Group", function()
        SetFriendGroup(nil)
        if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
    end)
    if not currentGroup then removeBtn:SetEnabled(false) end

end

-- Register with all friend menu types
if Menu and Menu.ModifyMenu then
    Menu.ModifyMenu("MENU_UNIT_FRIEND", EBS_ModifyFriendMenu)
    Menu.ModifyMenu("MENU_UNIT_FRIEND_OFFLINE", EBS_ModifyFriendMenu)
    Menu.ModifyMenu("MENU_UNIT_BN_FRIEND", EBS_ModifyFriendMenu)
    Menu.ModifyMenu("MENU_UNIT_BN_FRIEND_OFFLINE", EBS_ModifyFriendMenu)
end

-- Hook Blizzard's BNet note edit popup to strip/restore EUI group tag.
-- When the user opens "Set Note", they see only their personal note.
-- When they save, the EUI group tag is re-appended automatically.
do
    local _euiNoteGroup = nil  -- stashed group during note edit
    local origBNSet = BNSetFriendNote
    -- Pre-intercept: inject group tag BEFORE the note reaches Blizzard,
    -- so the saved note always contains the tag and no rebuild sees it missing.
    BNSetFriendNote = function(id, note)
        if _euiNoteGroup then
            local group = _euiNoteGroup
            _euiNoteGroup = nil
            if not note or not note:find(EUI_NOTE_TAG, 1, true) then
                note = WriteGroupToNote(note or "", group)
            end
        end
        return origBNSet(id, note)
    end
    local notePopup = StaticPopupDialogs["SET_BNFRIENDNOTE"]
    if notePopup then
        local origOnShow = notePopup.OnShow
        notePopup.OnShow = function(self, ...)
            if origOnShow then origOnShow(self, ...) end
            -- Blizzard sets the note text after OnShow; defer our strip
            local popup = self
            C_Timer.After(0, function()
                local eb = popup.EditBox or popup.editBox
                if eb then
                    local raw = eb:GetText() or ""
                    local group, clean = ParseGroupFromNote(raw)
                    _euiNoteGroup = group
                    if clean ~= raw then
                        eb:SetText(clean or "")
                    end
                end
            end)
        end
    end
end

-- Frame background color (used everywhere)
local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

-- One-time structural setup
local function SkinFriendsFrame()
    local frame = FriendsFrame
    if not frame or friendsSkinned then return end
    friendsSkinned = true
    local p = EBS.db.profile.friends
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT

    -- Hide Blizzard decorations
    if frame.NineSlice then frame.NineSlice:Hide() end
    if frame.Bg then frame.Bg:Hide() end
    if frame.TitleBg then frame.TitleBg:Hide() end
    if frame.TopTileStreaks then
        frame.TopTileStreaks:SetAlpha(0)
    end
    if frame.PortraitContainer then frame.PortraitContainer:Hide() end
    if frame.portrait then frame.portrait:Hide() end
    if frame.PortraitFrame then frame.PortraitFrame:Hide() end
    if FriendsFramePortrait then FriendsFramePortrait:Hide() end
    if FriendsFrameIcon then FriendsFrameIcon:Hide() end

    for _, key in ipairs({"TopBorder", "TopRightCorner", "RightBorder",
                          "BottomRightCorner", "BottomBorder", "BottomLeftCorner",
                          "LeftBorder", "TopLeftCorner", "BtnCornerLeft",
                          "BtnCornerRight"}) do
        if frame[key] then frame[key]:Hide() end
    end

    if frame.Inset then
        if frame.Inset.NineSlice then frame.Inset.NineSlice:Hide() end
        if frame.Inset.Bg then frame.Inset.Bg:Hide() end
    end

    -- Resize frame (deferred to avoid tainting panel management)
    if not GetFFD(frame).sizeSet then
        GetFFD(frame).sizeSet = true
        local origW = frame:GetWidth()
        local origH = frame:GetHeight()
        local origListH = FriendsListFrame:GetHeight()
        local EXTRA_H = 50
        local LIST_TOP = -92
        local LIST_BOTTOM = 35
        local LIST_LEFT = 15
        local LIST_RIGHT = -15
        local _sizeApplied = false
        local function ApplySize()
            if _sizeApplied then return end
            _sizeApplied = true
            frame:SetWidth(origW - 40)
            frame:SetHeight(origH + EXTRA_H)
            FriendsListFrame:SetHeight(origListH + EXTRA_H)
            -- Hide Blizzard's ScrollBox visually without touching its layout or
            -- creating children on it. Our own ScrollBox handles all rendering.
            FriendsListFrame.ScrollBox:SetAlpha(0)
            FriendsListFrame.ScrollBox:EnableMouse(false)
            -- Match other sub-tab content frames to the same list pane bounds
            local function FitToListPane(f)
                if not f then return end
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_LEFT, LIST_TOP)
                f:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM)
                -- Strip background textures from the frame and its children
                StripTextures(f)
                if f.Bg then f.Bg:Hide() end
                if f.NineSlice then f.NineSlice:Hide() end
                -- Force inner List container to fill parent
                if f.List then
                    f.List:ClearAllPoints()
                    f.List:SetAllPoints(f)
                    StripTextures(f.List)
                    if f.List.ScrollBox then
                        f.List.ScrollBox:ClearAllPoints()
                        f.List.ScrollBox:SetAllPoints(f.List)
                    end
                end
            end
            FitToListPane(_G.RecentAlliesFrame)
            FitToListPane(_G.RecruitAFriendFrame)
        end

        -- Backdrop is on our own ScrollBox (created later in the file)

        -- Apply size on show (scale + positioning fully owned by Blizzard)
        -- Use hooksecurefunc instead of HookScript to avoid tainting FriendsFrame's
        -- OnShow script chain (which breaks ClaimRaidFrame in combat).
        hooksecurefunc(frame, "Show", function()
            local _mplus = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
            local _, _iT = IsInInstance()
            local _pvp = (_iT == "pvp" or _iT == "arena")
            if not InCombatLockdown() and not _mplus and not _pvp then
                ApplySize()
            end
        end)
        ApplySize()
    end

    -- Dark background
    GetFFD(frame).bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    GetFFD(frame).bg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
    GetFFD(frame).bg:SetAllPoints()
    GetFFD(frame).bg:SetAlpha(1)

    -- Pixel border
    do
        local r, g, b, a = GetBorderColor(p)
        local borderAlpha = (p.showBorder ~= false) and a or 0
        PP.CreateBorder(frame, r, g, b, borderAlpha, p.borderSize or 1, "OVERLAY", 7)
    end

    -- Reparent IgnoreListWindow to UIParent so it renders above the main frame
    if frame.IgnoreListWindow then
        frame.IgnoreListWindow:SetParent(UIParent)
        frame.IgnoreListWindow:SetFrameStrata("DIALOG")
    end

    -- Raise RaidInfoFrame above the main frame without reparenting (SetParent
    -- from addon code taints the frame tree, breaking ClaimRaidFrame in combat).
    if _G.RaidInfoFrame then
        _G.RaidInfoFrame:SetFrameStrata("DIALOG")
    end

    -- Reparent FriendsTooltip to UIParent so it renders independently of the main frame
    if FriendsTooltip then
        FriendsTooltip:SetParent(UIParent)
        FriendsTooltip:SetFrameStrata("TOOLTIP")
    end

    -- Tab bar background (extends below frame for bottom tabs)
    local firstTab = _G.FriendsFrameTab1
    if firstTab then
        GetFFD(frame).tabBarBg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        GetFFD(frame).tabBarBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
        GetFFD(frame).tabBarBg:SetAlpha(1)
        GetFFD(frame).tabBarBg:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 2)
        GetFFD(frame).tabBarBg:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 2)
        GetFFD(frame).tabBarBg:SetPoint("BOTTOM", firstTab, "BOTTOM", 0, 0)
    end

    -- Restyle Blizzard's tabs in-place. No custom tab frames,
    -- no OnClick, no PanelTemplates_SetTab from addon code. Blizzard handles
    -- all tab switching securely. We just change the visuals.
    local customTabs = {}
    for i = 1, frame.numTabs or 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then
            -- Strip Blizzard's tab textures
            for j = 1, select("#", tab:GetRegions()) do
                local region = select(j, tab:GetRegions())
                if region and region:IsObjectType("Texture") then
                    region:SetTexture("")
                    if region.SetAtlas then region:SetAtlas("") end
                end
            end
            if tab.Left then tab.Left:SetTexture("") end
            if tab.Middle then tab.Middle:SetTexture("") end
            if tab.Right then tab.Right:SetTexture("") end
            if tab.LeftDisabled then tab.LeftDisabled:SetTexture("") end
            if tab.MiddleDisabled then tab.MiddleDisabled:SetTexture("") end
            if tab.RightDisabled then tab.RightDisabled:SetTexture("") end
            local hl = tab:GetHighlightTexture()
            if hl then hl:SetTexture("") end

            -- Dark background
            if not GetFFD(tab).bg then
                GetFFD(tab).bg = tab:CreateTexture(nil, "BACKGROUND")
                GetFFD(tab).bg:SetAllPoints()
                GetFFD(tab).bg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
            end

            -- Active highlight
            local tfd = GetFFD(tab)
            if not tfd.activeHL then
                local activeHL = tab:CreateTexture(nil, "ARTWORK", nil, -6)
                activeHL:SetAllPoints()
                activeHL:SetColorTexture(1, 1, 1, 0.05)
                activeHL:SetBlendMode("ADD")
                activeHL:Hide()
                tfd.activeHL = activeHL
            end

            -- Hide Blizzard's label (shifts on select) and use our own
            local blizLabel = tab:GetFontString()
            local labelText = blizLabel and blizLabel:GetText() or ("Tab " .. i)
            if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end
            tab:SetPushedTextOffset(0, 0)
            local label = tab:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, 9, "")
            label:SetPoint("CENTER", tab, "CENTER", 0, 0)
            label:SetJustifyH("CENTER")
            label:SetText(labelText)
            tfd.label = label

            -- Accent underline (1px pixel-perfect)
            if not tfd.underline then
                local underline = tab:CreateTexture(nil, "OVERLAY", nil, 6)
                PP.DisablePixelSnap(underline)
                underline:SetHeight(PP.mult or 1)
                underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
                underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
                local ar, ag, ab = EG.r, EG.g, EG.b
                underline:SetColorTexture(ar, ag, ab, 1)
                EllesmereUI.RegAccent({ type = "solid", obj = underline, a = 1 })
                underline:Hide()
                tfd.underline = underline
            end

            customTabs[i] = tab
        end
    end
    -- Track active sub-tab index (1=Friends, 2=Recent Allies) to avoid
    -- reading bliz:IsEnabled() during OnShow which taints.
    local _activeSubTab = 1

    local function UpdateCustomTabs(overrideTab)
        local selected = overrideTab or PanelTemplates_GetSelectedTab(FriendsFrame) or 1
        local isContacts = (selected == 1)
        local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
        local useAccent = fp and fp.accentColors ~= false
        for i, ct in ipairs(customTabs) do
            local isActive = (i == selected)
            local ctd = GetFFD(ct)
            if ctd.label then ctd.label:SetTextColor(1, 1, 1, isActive and 1 or 0.5) end
            if ctd.underline then
                ctd.underline:SetShown(isActive)
                if isActive then
                    if useAccent then
                        local ar, ag, ab = EG.r, EG.g, EG.b
                        ctd.underline:SetColorTexture(ar, ag, ab, 1)
                    else
                        ctd.underline:SetColorTexture(1, 1, 1, 0.6)
                    end
                end
            end
            if ctd.activeHL then ctd.activeHL:SetShown(isActive) end
        end
        -- Show/hide bottom buttons based on whether Contacts tab is active
        local addBtn = _G.FriendsFrameAddFriendButton
        local msgBtn = _G.FriendsFrameSendMessageButton
        if addBtn then addBtn:SetAlpha(isContacts and 1 or 0); addBtn:EnableMouse(isContacts) end
        if msgBtn then msgBtn:SetAlpha(isContacts and 1 or 0); msgBtn:EnableMouse(isContacts) end
        if GetFFD(frame).offlineBtn then GetFFD(frame).offlineBtn:SetShown(isContacts) end
        -- Show top links on all tabs except Raid
        local showTopUI = (selected ~= 3)
        -- Deselect all top sub-tabs when not on Contacts
        if not isContacts and GetFFD(frame).subTabs then
            for _, ct in ipairs(GetFFD(frame).subTabs) do
                ct._label:SetTextColor(1, 1, 1, 0.53)
                ct:SetShown(showTopUI)
            end
        elseif GetFFD(frame).subTabs then
            for _, ct in ipairs(GetFFD(frame).subTabs) do
                ct:Show()
            end
            -- Refresh sub-tab active states
            if GetFFD(frame).updateSubTabs then GetFFD(frame).updateSubTabs() end
        end
        -- Title, divider, search always visible; orb hidden on raid
        if GetFFD(frame).statusOrb then GetFFD(frame).statusOrb:SetShown(selected ~= 3) end
        if GetFFD(frame).broadcastBtn then GetFFD(frame).broadcastBtn:SetShown(selected ~= 3) end
        if GetFFD(frame).titleBtn then GetFFD(frame).titleBtn:Show() end
        if GetFFD(frame).titleDiv then GetFFD(frame).titleDiv:Show() end
        -- Disable/enable search bar
        local searchBox = GetFFD(frame).searchBox
        if searchBox then
            searchBox:SetShown(selected ~= 3)
            searchBox:SetEnabled(isContacts)
            searchBox:SetAlpha(isContacts and 1 or 0.3)
            if not isContacts then
                searchBox:ClearFocus()
                searchBox:EnableMouse(false)
            else
                searchBox:EnableMouse(true)
            end
        end
        -- Sync scrollbar visibility based on selected tab (don't read IsVisible
        -- from Blizzard ScrollBoxes -- that taints during OnShow in combat)
        local function SetTrackVis(sb, vis)
            if sb and GetFFD(sb).track then
                GetFFD(sb).track:SetShown(vis)
                if GetFFD(sb).track._hitArea then GetFFD(sb).track._hitArea:SetShown(vis) end
            end
        end
        -- Show/hide our custom ScrollBox (only when FriendsFrame is open)
        if GetFFD(frame).ourScrollBox then
            GetFFD(frame).ourScrollBox:SetShown(frame:IsShown() and isContacts and _activeSubTab == 1)
        end
        local shown = frame:IsShown()
        local friendsSB = FriendsListFrame and FriendsListFrame.ScrollBox
        SetTrackVis(friendsSB, shown and isContacts and _activeSubTab == 1)
        -- Also sync our ScrollBox's scrollbar track
        if GetFFD(frame).ourScrollBox then
            SetTrackVis(GetFFD(frame).ourScrollBox, shown and isContacts and _activeSubTab == 1)
        end
        local raf = _G.RecentAlliesFrame
        if raf and raf.List then SetTrackVis(raf.List.ScrollBox, shown and isContacts and _activeSubTab == 2) end
        local who = _G.WhoFrame
        if who then SetTrackVis(who.ScrollBox or (who.List and who.List.ScrollBox), shown and selected == 2) end
    end

    GetFFD(frame).updateCustomTabs = UpdateCustomTabs

    -- Detect tab changes by hooking each sub-frame's OnShow.
    -- Blizzard shows/hides these frames when tabs switch -- no global hooks needed.
    local tabFrames = {
        { _G.FriendsListFrame, 1 },
        { _G.WhoFrame,         2 },
        { _G.RaidFrame,        3 },
        { _G.QuickJoinFrame,   4 },
    }
    for _, entry in ipairs(tabFrames) do
        local sf, tabIdx = entry[1], entry[2]
        if sf then
            sf:HookScript("OnShow", function()
                UpdateCustomTabs(tabIdx)
                if tabIdx == 3 then C_Timer.After(0, SkinRaidTab); C_Timer.After(0.2, SkinRaidTab) end
            end)
        end
    end
    -- RaidFrame may not exist yet; hook it after Blizzard creates it
    if not _G.RaidFrame then
        C_Timer.After(0.25, function()
            local rf = _G.RaidFrame
            if rf then
                rf:HookScript("OnShow", function()
                    UpdateCustomTabs(3)
                    C_Timer.After(0, SkinRaidTab); C_Timer.After(0.2, SkinRaidTab)
                end)
            end
        end)
    end
    hooksecurefunc(frame, "Show", function()
        UpdateCustomTabs()
    end)

    hooksecurefunc(frame, "Hide", function()
        local function HideTrack(sb)
            if sb and GetFFD(sb).track then
                GetFFD(sb).track:Hide()
                if GetFFD(sb).track._hitArea then GetFFD(sb).track._hitArea:Hide() end
            end
        end
        HideTrack(FriendsListFrame and FriendsListFrame.ScrollBox)
        if GetFFD(frame).ourScrollBox then
            GetFFD(frame).ourScrollBox:Hide()
            HideTrack(GetFFD(frame).ourScrollBox)
        end
        _activeSubTab = 1  -- reset to match Blizzard's default on reopen
        local raf = _G.RecentAlliesFrame
        if raf and raf.List then HideTrack(raf.List.ScrollBox) end
        local who = _G.WhoFrame
        if who then HideTrack(who.ScrollBox or (who.List and who.List.ScrollBox)) end
    end)
    -- Title text -- show BNet tag, accent colored
    -- Hide Blizzard's title
    if frame.TitleContainer then
        local blizTitle = frame.TitleContainer.TitleText or frame.TitleContainer:GetFontString()
        if blizTitle then blizTitle:SetAlpha(0) end
    elseif FriendsFrameTitleText then
        FriendsFrameTitleText:SetAlpha(0)
    end

    -- Our own title button (clickable, sized to text only so drag works around it)
    local _, battleTag = BNGetInfo()
    local titleText = battleTag or (FRIENDS or "Friends")
    local titleBtn = CreateFrame("Button", nil, frame)
    titleBtn:SetFrameLevel(frame:GetFrameLevel() + 5)

    local titleLabel = titleBtn:CreateFontString(nil, "OVERLAY")
    titleLabel:SetFont(fontPath, 12, "")
    titleLabel:SetTextColor(1, 1, 1, 0.75)
    titleLabel:SetPoint("CENTER", titleBtn, "CENTER", 0, 0)
    titleLabel:SetJustifyH("CENTER")
    titleLabel:SetText(titleText)

    -- Size button to text bounds
    local textW = titleLabel:GetStringWidth() or 60
    titleBtn:SetSize(textW + 16, 20)
    titleBtn:SetPoint("TOP", frame, "TOP", 0, -5)

    titleBtn._label = titleLabel
    GetFFD(frame).titleBtn = titleBtn

    -- Hover: brighten to 100%
    titleBtn:SetScript("OnEnter", function()
        titleLabel:SetTextColor(1, 1, 1, 1)
    end)
    titleBtn:SetScript("OnLeave", function()
        titleLabel:SetTextColor(1, 1, 1, 0.75)
    end)

    -- Copy popup for BattleTag
    local copyBackdrop, copyPopup
    local function HideCopyPopup()
        if copyPopup then copyPopup:Hide() end
        if copyBackdrop then copyBackdrop:Hide() end
    end

    local function ShowCopyPopup(text, anchorBtn)
        if not copyPopup then
            copyBackdrop = CreateFrame("Button", nil, UIParent)
            copyBackdrop:SetFrameStrata("DIALOG")
            copyBackdrop:SetFrameLevel(499)
            copyBackdrop:SetAllPoints(UIParent)
            local bdTex = copyBackdrop:CreateTexture(nil, "BACKGROUND")
            bdTex:SetAllPoints()
            bdTex:SetColorTexture(0, 0, 0, 0.10)
            local fadeIn = copyBackdrop:CreateAnimationGroup()
            fadeIn:SetToFinalAlpha(true)
            local a = fadeIn:CreateAnimation("Alpha")
            a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.2)
            copyBackdrop._fadeIn = fadeIn
            copyBackdrop:RegisterForClicks("AnyUp")
            copyBackdrop:SetScript("OnClick", HideCopyPopup)
            copyBackdrop:Hide()

            copyPopup = CreateFrame("Frame", nil, UIParent)
            copyPopup:SetFrameStrata("DIALOG")
            copyPopup:SetFrameLevel(500)
            copyPopup:SetSize(220, 52)
            local popFade = copyPopup:CreateAnimationGroup()
            popFade:SetToFinalAlpha(true)
            local pa = popFade:CreateAnimation("Alpha")
            pa:SetFromAlpha(0); pa:SetToAlpha(1); pa:SetDuration(0.2)
            copyPopup._fadeIn = popFade

            local bg = copyPopup:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.08, 0.10, 0.97)
            PP.CreateBorder(copyPopup, 1, 1, 1, 0.15, 1, "OVERLAY", 7)

            local hint = copyPopup:CreateFontString(nil, "OVERLAY")
            hint:SetFont(fontPath, 8, "")
            hint:SetTextColor(1, 1, 1, 0.5)
            hint:SetPoint("TOP", copyPopup, "TOP", 0, -6)
            hint:SetText("Ctrl+C to copy, Escape to close")

            local eb = CreateFrame("EditBox", nil, copyPopup)
            eb:SetSize(160, 16)
            eb:SetPoint("TOP", hint, "BOTTOM", 0, -4)
            eb:SetFontObject(GameFontHighlight)
            eb:SetAutoFocus(false)
            eb:SetJustifyH("CENTER")
            local ebBg = eb:CreateTexture(nil, "BACKGROUND")
            ebBg:SetColorTexture(0.10, 0.12, 0.16, 1)
            ebBg:SetPoint("TOPLEFT", -6, 4); ebBg:SetPoint("BOTTOMRIGHT", 6, -4)
            PP.CreateBorder(eb, 1, 1, 1, 0.02, 1, "OVERLAY", 7)
            eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); HideCopyPopup() end)
            eb:SetScript("OnKeyDown", function(self, key)
                if key == "C" and IsControlKeyDown() then
                    C_Timer.After(0.05, HideCopyPopup)
                end
            end)
            eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
            copyPopup:EnableMouse(true)
            copyPopup:SetScript("OnMouseDown", function() copyPopup._eb:SetFocus(); copyPopup._eb:HighlightText() end)
            copyPopup._eb = eb
        end
        copyPopup._eb:SetText(text)
        copyPopup:ClearAllPoints()
        copyPopup:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 8)
        copyBackdrop:SetAlpha(0); copyBackdrop:Show(); copyBackdrop._fadeIn:Play()
        copyPopup:SetAlpha(0); copyPopup:Show(); copyPopup._fadeIn:Play()
        copyPopup._eb:SetFocus(); copyPopup._eb:HighlightText()
    end

    titleBtn:SetScript("OnClick", function(self)
        ShowCopyPopup(titleText, self)
    end)

    -- Divider under title
    GetFFD(frame).titleDiv = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    GetFFD(frame).titleDiv:SetColorTexture(1, 1, 1, 0.06)
    GetFFD(frame).titleDiv:SetHeight(1)
    GetFFD(frame).titleDiv:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)
    GetFFD(frame).titleDiv:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -30)

    -- BattleNet ID bar reskin
    -- Hide Blizzard's status dropdown and BNet bar
    local statusDD = _G.FriendsFrameStatusDropdown
    if statusDD then
        statusDD:SetAlpha(0)
        statusDD:EnableMouse(false)
        statusDD:SetSize(1, 1)
    end

    local bnetFrame = _G.FriendsFrameBattlenetFrame
    if bnetFrame then
        StripTextures(bnetFrame)
        for i = 1, select("#", bnetFrame:GetChildren()) do
            local child = select(i, bnetFrame:GetChildren())
            child:SetAlpha(0)
            child:EnableMouse(false)
        end
        for i = 1, select("#", bnetFrame:GetRegions()) do
            local region = select(i, bnetFrame:GetRegions())
            if region:IsObjectType("FontString") then
                region:SetAlpha(0)
            end
        end
        if bnetFrame.BroadcastFrame then
            local bf = bnetFrame.BroadcastFrame
            bf:SetParent(FriendsFrame)
            bf:SetAlpha(1)
            bf:EnableMouse(true)
            bf:ClearAllPoints()
            bf:SetPoint("TOPLEFT", FriendsFrame, "TOPRIGHT", 5, 0)
        end
        -- Collapse the bnet frame to reclaim vertical space
        bnetFrame:SetHeight(1)
    end

    -- Status orb + arrow will be placed on the sub-tabs row (created later in SkinSubTabs)
    -- Store references for SkinSubTabs to use
    local function GetPlayerStatusName()
        -- Guard against secret boolean return values to avoid taint
        local dnd = UnitIsDND("player")
        if not issecretvalue or not issecretvalue(dnd) then
            if dnd then return BUSY or "Busy" end
        end
        local afk = UnitIsAFK("player")
        if not issecretvalue or not issecretvalue(afk) then
            if afk then return AWAY or "Away" end
        end
        return FRIENDS_LIST_ONLINE or "Online"
    end
    GetFFD(frame).getPlayerStatus = GetPlayerStatusName

    -- Custom sub-tabs (Friends/Recent Allies/Recruit A Friend)
    local customSubTabs = {}
    GetFFD(frame).subTabs = customSubTabs
    local function SkinSubTabs()
        local tabHeader = _G.FriendsTabHeader
        if not tabHeader then return end
        local tabSystem = tabHeader.TabSystem
        if not tabSystem then return end

        -- Collect Blizzard sub-tab names and click references
        local blizSubTabs = {}
        for i = 1, select("#", tabSystem:GetChildren()) do
            local st = select(i, tabSystem:GetChildren())
            if st and st:IsObjectType("Button") then
                local text = st:GetFontString()
                local name = text and text:GetText() or ("Tab " .. i)
                blizSubTabs[#blizSubTabs + 1] = { blizTab = st, name = name }
            end
        end

        -- Hide Blizzard sub-tabs and header textures
        for _, info in ipairs(blizSubTabs) do
            info.blizTab:SetAlpha(0)
            info.blizTab:SetHeight(1)
            info.blizTab:EnableMouse(false)
        end
        StripTextures(tabHeader)
        if tabSystem then StripTextures(tabSystem) end

        -- Update function
        local function UpdateSubTabs()
            local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
            local useAccent = fp and fp.accentColors ~= false
            local ar, ag, ab = EG.r, EG.g, EG.b
            for i, ct in ipairs(customSubTabs) do
                local bliz = blizSubTabs[i] and blizSubTabs[i].blizTab
                local isSelected = bliz and bliz.IsEnabled and not bliz:IsEnabled()
                if isSelected then
                    if useAccent then
                        ct._label:SetTextColor(ar, ag, ab, 1)
                    else
                        ct._label:SetTextColor(1, 1, 1, 1)
                    end
                else
                    ct._label:SetTextColor(1, 1, 1, 0.53)
                end
            end
        end
        local function UpdateSubTabWidths()
            for _, ct in ipairs(customSubTabs) do
                local w = ct._label:GetStringWidth() or 40
                ct:SetWidth(w)
            end
        end
        GetFFD(frame).updateSubTabs = function()
            UpdateSubTabWidths()
            UpdateSubTabs()
        end

        -- Build custom sub-tabs
        local ar, ag, ab = EG.r, EG.g, EG.b
        for i, info in ipairs(blizSubTabs) do
            local ct = CreateFrame("Button", nil, frame)
            ct:SetFrameLevel(frame:GetFrameLevel() + 5)
            ct:SetHeight(20)

            local label = ct:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, 11, "")
            label:SetPoint("LEFT", ct, "LEFT", 0, 0)
            label:SetJustifyH("LEFT")
            label:SetText(info.name:match("^(%S+)") or info.name)
            ct._label = label


            -- Hover (only interactive when on Contacts bottom tab)
            ct:SetScript("OnEnter", function()
                local isContacts = (PanelTemplates_GetSelectedTab(FriendsFrame) or 1) == 1
                if not isContacts then return end
                local bliz = blizSubTabs[i] and blizSubTabs[i].blizTab
                local isSelected = bliz and bliz.IsEnabled and not bliz:IsEnabled()
                if not isSelected then ct._label:SetTextColor(1, 1, 1, 0.86) end
            end)
            ct:SetScript("OnLeave", function()
                local isContacts = (PanelTemplates_GetSelectedTab(FriendsFrame) or 1) == 1
                if not isContacts then return end
                local bliz = blizSubTabs[i] and blizSubTabs[i].blizTab
                local isSelected = bliz and bliz.IsEnabled and not bliz:IsEnabled()
                if isSelected then
                    local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
                    if fp and fp.accentColors ~= false then
                        local ar, ag, ab = EG.r, EG.g, EG.b
                        ct._label:SetTextColor(ar, ag, ab, 1)
                    else
                        ct._label:SetTextColor(1, 1, 1, 1)
                    end
                else
                    ct._label:SetTextColor(1, 1, 1, 0.53)
                end
            end)

            -- Click: switch to Contacts if needed, then trigger the Blizzard sub-tab
            ct:SetScript("OnClick", function()
                local bliz = blizSubTabs[i] and blizSubTabs[i].blizTab
                -- Skip if already selected
                local isSelected = bliz and bliz.IsEnabled and not bliz:IsEnabled()
                if isSelected then return end
                local tabName = info.name or ""
                -- Recruit A Friend opens a popup, don't switch tabs
                if strfind(tabName, "Recruit") then
                    -- Open RAF popup, then restore our tab state so nothing visually changes
                    local savedSubTab = _activeSubTab
                    if RecruitAFriendFrame and RecruitAFriendFrame.RecruitmentButton then
                        RecruitAFriendFrame.RecruitmentButton:Click()
                    end
                    _activeSubTab = savedSubTab
                    UpdateSubTabs()
                    UpdateCustomTabs()
                    return
                else
                    -- Switch to Contacts bottom tab if needed
                    local bottomTab = PanelTemplates_GetSelectedTab(FriendsFrame) or 1
                    if bottomTab ~= 1 then
                        PanelTemplates_SetTab(FriendsFrame, 1)
                        FriendsFrame_Update()
                        UpdateCustomTabs()
                    end
                    if bliz then
                        bliz:EnableMouse(true)
                        bliz:Click()
                        bliz:EnableMouse(false)
                    end
                end
                _activeSubTab = i
                UpdateSubTabs()
                UpdateCustomTabs()
            end)

            -- Width set in UpdateSubTabWidths on each OnShow
            ct:SetWidth(60)  -- placeholder
            if i == 1 then
                ct:SetPoint("TOPLEFT", FriendsListFrame, "TOPLEFT", 15, -70)
            else
                ct:SetPoint("LEFT", customSubTabs[i - 1], "RIGHT", 20, 0)
            end

            customSubTabs[i] = ct
        end

        -- Extra sub-tab: "Ignored" (opens Blizzard ignore list)
        do
            local idx = #customSubTabs + 1
            local ct = CreateFrame("Button", nil, frame)
            ct:SetFrameLevel(frame:GetFrameLevel() + 5)
            ct:SetHeight(20)

            local label = ct:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, 11, "")
            label:SetPoint("LEFT", ct, "LEFT", 0, 0)
            label:SetJustifyH("LEFT")
            label:SetText(IGNORE or "Ignored")
            ct._label = label
            ct._label:SetTextColor(1, 1, 1, 0.53)

            ct:SetScript("OnEnter", function()
                ct._label:SetTextColor(1, 1, 1, 0.86)
            end)
            ct:SetScript("OnLeave", function()
                ct._label:SetTextColor(1, 1, 1, 0.53)
            end)
            ct:SetScript("OnClick", function()
                local ilw = FriendsFrame and FriendsFrame.IgnoreListWindow
                if ilw and ilw.ToggleFrame then
                    ilw:ToggleFrame()
                end
            end)

            ct:SetWidth(60)  -- placeholder, updated in UpdateSubTabWidths
            ct:SetPoint("LEFT", customSubTabs[idx - 1], "RIGHT", 20, 0)
            customSubTabs[idx] = ct
        end

        -- Status orb on the right side of the sub-tabs row
        local lastSubTab = customSubTabs[#customSubTabs]
        if lastSubTab then
            local GetPlayerStatusName = GetFFD(frame).getPlayerStatus

            -- Status orb 
            local orbBtn = CreateFrame("Button", nil, frame)
            orbBtn:SetSize(26, 26)
            orbBtn:SetFrameLevel(frame:GetFrameLevel() + 5)
            orbBtn:SetPoint("RIGHT", FriendsListFrame, "TOPRIGHT", -10, -80)
            local orbTex = orbBtn:CreateTexture(nil, "ARTWORK", nil, 2)
            orbTex:SetAllPoints()
            orbTex:SetPoint("CENTER", orbBtn, "CENTER", 0, 0)
            local orbInfo = C_Texture.GetAtlasInfo("lootroll-animreveal-a")
            if orbInfo then
                orbTex:SetTexture(orbInfo.file)
                local aL = orbInfo.leftTexCoord or 0
                local aR = orbInfo.rightTexCoord or 1
                local aT = orbInfo.topTexCoord or 0
                local aB = orbInfo.bottomTexCoord or 1
                local aW, aH = aR - aL, aB - aT
                orbTex:SetTexCoord(aL, aL + aW/6, aT, aT + aH/2)
            end

            local function UpdatePlayerOrb()
                local status = GetPlayerStatusName()
                if status == (BUSY or "Busy") then
                    orbTex:SetVertexColor(1, 0.2, 0.2, 1)
                elseif status == (AWAY or "Away") then
                    orbTex:SetVertexColor(1, 0.8, 0, 1)
                else
                    orbTex:SetVertexColor(0.2, 1, 0.2, 1)
                end
            end
            UpdatePlayerOrb()

            orbBtn:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                local status = GetPlayerStatusName()
                if status == (FRIENDS_LIST_ONLINE or "Online") then
                    -- Online -> Away
                    SendChatMessage("", "AFK")
                    if BNSetAFK then BNSetAFK(true) end
                elseif status == (AWAY or "Away") then
                    -- Away -> Busy
                    SendChatMessage("", "AFK")  -- clear AFK
                    SendChatMessage("", "DND")
                    if BNSetAFK then BNSetAFK(false) end
                    if BNSetDND then BNSetDND(true) end
                else
                    -- Busy -> Online
                    SendChatMessage("", "DND")
                    if BNSetDND then BNSetDND(false) end
                    if BNSetAFK then BNSetAFK(false) end
                end
            end)
            local function UpdateOrbTooltip()
                if orbBtn:IsMouseOver() and EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(orbBtn, "Status: " .. GetPlayerStatusName() .. "\nClick to change")
                end
            end
            orbBtn:SetScript("OnEnter", function(self)
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "Status: " .. GetPlayerStatusName() .. "\nClick to change")
                end
            end)
            orbBtn:SetScript("OnLeave", function()
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)

            local statusEvt = CreateFrame("Frame")
            statusEvt:RegisterEvent("PLAYER_FLAGS_CHANGED")
            statusEvt:SetScript("OnEvent", function()
                UpdatePlayerOrb()
                UpdateOrbTooltip()
            end)

            GetFFD(frame).statusOrb = orbBtn

            -- Status/broadcast message button (to the left of status orb)
            local msgBtn = CreateFrame("Button", nil, frame)
            msgBtn:SetSize(20, 20)
            msgBtn:SetFrameLevel(orbBtn:GetFrameLevel())
            msgBtn:SetPoint("RIGHT", orbBtn, "LEFT", -2, 0)
            local msgIcon = msgBtn:CreateTexture(nil, "ARTWORK")
            msgIcon:SetAllPoints()
            msgIcon:SetAtlas("voicechat-icon-textchat-silenced")
            msgIcon:SetDesaturated(true)
            msgIcon:SetVertexColor(1, 1, 1)
            msgBtn:SetAlpha(0.6)
            msgBtn:SetScript("OnEnter", function(self)
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "Set Status Message")
                end
            end)
            msgBtn:SetScript("OnLeave", function()
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)
            msgBtn:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                local bf = FriendsFrameBattlenetFrame and FriendsFrameBattlenetFrame.BroadcastFrame
                if not bf then return end
                if bf:IsShown() then
                    bf:Hide()
                else
                    bf:Show()
                end
            end)
            GetFFD(frame).broadcastBtn = msgBtn
        end

        -- Initial state: default first tab to active, then verify
        if customSubTabs[1] then
            customSubTabs[1]._label:SetTextColor(1, 1, 1, 1)
        end
        C_Timer.After(0.1, UpdateSubTabs)
        C_Timer.After(0.5, UpdateSubTabs)
        -- Also update on frame show
        hooksecurefunc(frame, "Show", function()
            C_Timer.After(0.1, UpdateSubTabs)
        end)
    end
    SkinSubTabs()
    -- Recent Allies: custom element factory and DataProvider for styled buttons
    do
        local raf = _G.RecentAlliesFrame
        if raf and raf.List and raf.List.ScrollBox then
            local rafSB = raf.List.ScrollBox

            -- Race ID -> faction lookup
            local RACE_FACTION = {}
            do
                local horde = {2,5,6,8,9,10,26,27,28,31,35,36,70,85}
                local alliance = {1,3,4,7,11,22,25,29,30,32,34,37,52,84}
                for _, id in ipairs(horde) do RACE_FACTION[id] = "Horde" end
                for _, id in ipairs(alliance) do RACE_FACTION[id] = "Alliance" end
            end
            local FACTION_TEX = "Interface\\AddOns\\EllesmereUIFriends\\Media\\"

            -- Orb atlas info: uses file-scope _orbFile, _orbL, _orbR, _orbT, _orbB

            local raFontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
            local _raSelectedGUID = nil

            -- Element initializer: fully style a plain Button as an RA entry
            local function InitRAButton(btn, elementData)
                btn:SetHeight(34)
                local cd = elementData.characterData
                local sd = elementData.stateData
                local fp = EBS.db.profile.friends
                local isOnline = sd and sd.isOnline

                -- One-time texture creation
                if not GetFFD(btn).rASkinned then
                    GetFFD(btn).rASkinned = true

                    -- Blizzard's selection system expects this method
                    function btn:SetSelected(selected)
                        if GetFFD(self).selected then
                            GetFFD(self).selected:SetShown(selected)
                        end
                    end

                    GetFFD(btn).tileBg = btn:CreateTexture(nil, "BACKGROUND", nil, -4)
                    GetFFD(btn).tileBg:SetAllPoints()

                    -- 10% lighten overlay
                    local lighten = btn:CreateTexture(nil, "BACKGROUND", nil, -3)
                    lighten:SetAllPoints()
                    lighten:SetColorTexture(1, 1, 1, 0.02)

                    GetFFD(btn).factionBg = btn:CreateTexture(nil, "ARTWORK", nil, -8)
                    GetFFD(btn).factionBg:SetAllPoints()
                    GetFFD(btn).factionBg:SetAlpha(0.2)

                    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
                    hover:SetAllPoints()
                    hover:SetColorTexture(1, 1, 1, 0.05)
                    hover:SetBlendMode("ADD")

                    -- Selection highlight
                    GetFFD(btn).selected = btn:CreateTexture(nil, "ARTWORK", nil, -7)
                    GetFFD(btn).selected:SetAllPoints()
                    GetFFD(btn).selected:SetColorTexture(1, 1, 1, 0.08)
                    GetFFD(btn).selected:Hide()

                    GetFFD(btn).classIcon = btn:CreateTexture(nil, "ARTWORK", nil, 2)

                    GetFFD(btn).statusOrb = btn:CreateTexture(nil, "OVERLAY", nil, 3)
                    GetFFD(btn).statusOrb:SetSize(18, 18)
                    if _orbFile then
                        GetFFD(btn).statusOrb:SetTexture(_orbFile)
                        GetFFD(btn).statusOrb:SetTexCoord(_orbL, _orbR, _orbT, _orbB)
                    end

                    GetFFD(btn).name = btn:CreateFontString(nil, "OVERLAY")
                    GetFFD(btn).name:SetFont(raFontPath, 12, "")
                    GetFFD(btn).name:SetShadowOffset(1, -1)
                    GetFFD(btn).name:SetShadowColor(0, 0, 0, 0.8)
                    GetFFD(btn).name:SetPoint("TOPLEFT", btn, "TOPLEFT", 38, -4)
                    GetFFD(btn).name:SetJustifyH("LEFT")

                    GetFFD(btn).infoLine = btn:CreateFontString(nil, "OVERLAY")
                    GetFFD(btn).infoLine:SetFont(raFontPath, 9, "")
                    GetFFD(btn).infoLine:SetShadowOffset(1, -1)
                    GetFFD(btn).infoLine:SetShadowColor(0, 0, 0, 0.8)
                    GetFFD(btn).infoLine:SetTextColor(0.5, 0.5, 0.5, 0.8)
                    GetFFD(btn).infoLine:SetPoint("TOPLEFT", GetFFD(btn).name, "BOTTOMLEFT", 0, -3)
                    GetFFD(btn).infoLine:SetJustifyH("LEFT")

                    -- Invite to Group button (right side, matching friends list)
                    local invBtn = CreateFrame("Button", nil, btn)
                    invBtn:SetSize(24, 32)
                    invBtn:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
                    invBtn:SetFrameLevel(btn:GetFrameLevel() + 3)
                    invBtn:SetNormalAtlas("friendslist-invitebutton-default-normal")
                    invBtn:SetPushedAtlas("friendslist-invitebutton-default-pressed")
                    invBtn:SetHighlightAtlas("friendslist-invitebutton-highlight")
                    invBtn:SetScript("OnEnter", function(self)
                        if EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, PARTY_INVITE)
                        end
                    end)
                    invBtn:SetScript("OnLeave", function()
                        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                    end)
                    invBtn:SetScript("OnClick", function()
                        local ed = GetFFD(btn).elementData
                        if ed and ed.characterData then
                            local fullName = ed.characterData.fullName
                            if fullName and ed.stateData and ed.stateData.isOnline then
                                C_PartyInfo.InviteUnit(fullName)
                            end
                        end
                    end)
                    GetFFD(btn).invBtn = invBtn

                    -- Click: left = select, right = context menu
                    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    btn:SetScript("OnClick", function(self, button)
                        local ed = GetFFD(self).elementData
                        if not ed or not ed.characterData then return end
                        local c = ed.characterData
                        local guid = c.guid
                        if button == "LeftButton" then
                            _raSelectedGUID = guid
                            local st = rafSB.ScrollTarget
                            if st then
                                for j = 1, select("#", st:GetChildren()) do
                                    local b = select(j, st:GetChildren())
                                    if GetFFD(b).selected then
                                        local bGUID = GetFFD(b).elementData and GetFFD(b).elementData.characterData and GetFFD(b).elementData.characterData.guid
                                        GetFFD(b).selected:SetShown(bGUID == _raSelectedGUID)
                                    end
                                end
                            end
                        elseif button == "RightButton" then
                            -- Blizzard context menu via unit GUID
                            if guid then
                                FriendsFrame_ShowDropdown(c.fullName or c.name, ed.stateData and ed.stateData.isOnline, nil, nil, nil, true)
                            end
                        end
                    end)

                    -- Blizzard tooltip on hover
                    btn:SetScript("OnEnter", function(self)
                        local ed = GetFFD(self).elementData
                        if not ed or not ed.characterData then return end
                        local c = ed.characterData
                        local s = ed.stateData
                        local lines = {}
                        lines[#lines + 1] = c.name or ""
                        if c.realmName and c.realmName ~= "" then
                            lines[#lines + 1] = c.realmName
                        end
                        if s then
                            if s.isOnline then
                                local status = FRIENDS_LIST_ONLINE or "Online"
                                local _isv2 = issecretvalue
                                local sDND = s.isDND; local sAFK = s.isAFK
                                if (not _isv2 or not _isv2(sDND)) and sDND then status = BUSY or "Busy"
                                elseif (not _isv2 or not _isv2(sAFK)) and sAFK then status = AWAY or "Away" end
                                if s.currentLocation and s.currentLocation ~= "" then
                                    status = status .. " - " .. s.currentLocation
                                end
                                lines[#lines + 1] = status
                            else
                                lines[#lines + 1] = FRIENDS_LIST_OFFLINE or "Offline"
                            end
                        end
                        if ed.interactionData and ed.interactionData.interactions then
                            local inter = ed.interactionData.interactions
                            if #inter > 0 and inter[1].description then
                                lines[#lines + 1] = inter[1].description
                            end
                        end
                        if EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, table.concat(lines, "\n"))
                        end
                    end)
                    btn:SetScript("OnLeave", function()
                        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                    end)
                end

                -- Store elementData reference for click/tooltip handlers
                GetFFD(btn).elementData = elementData

                -- Selection highlight
                GetFFD(btn).selected:SetShown(cd.guid == _raSelectedGUID)

                -- Tile bg
                GetFFD(btn).tileBg:SetColorTexture(0, 0, 0, 0.10)

                -- Class icon
                local icon = GetFFD(btn).classIcon
                local classFile
                if cd.classID and cd.classID > 0 then
                    local _, cf = GetClassInfo(cd.classID)
                    classFile = cf
                end
                if classFile and fp.showClassIcons ~= false then
                    local h = 30
                    local inset = math.floor(h * 0.025 + 0.5)
                    icon:ClearAllPoints()
                    icon:SetPoint("LEFT", btn, "LEFT", 4, 0)
                    icon:SetPoint("TOP", btn, "TOP", 0, -(2 + inset))
                    icon:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2 + inset)
                    local iconH = h - inset * 2
                    if iconH > 0 then icon:SetWidth(iconH) end
                    local style = fp.iconStyle or "modern"
                    if style == "blizzard" then
                        icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
                        if coords then icon:SetTexCoord(unpack(coords)) end
                    else
                        local coords = CLASS_SPRITE_COORDS[classFile]
                        if coords then
                            icon:SetTexture(CLASS_ICON_SPRITE_TEX[style] or (CLASS_ICON_SPRITE_BASE .. style .. ".tga"))
                            icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                        end
                    end
                    if isOnline then
                        icon:SetDesaturated(false)
                        icon:SetAlpha(1)
                    else
                        icon:SetTexture(OFFLINE_ICON)
                        icon:SetTexCoord(0, 1, 0, 1)
                        icon:SetAlpha(0.5)
                    end
                    icon:Show()
                else
                    icon:Hide()
                end

                -- Faction overlay (respect factionBanners setting)
                local showFaction = fp and fp.factionBanners ~= false
                local faction = showFaction and isOnline and RACE_FACTION[cd.raceID] or nil
                local texPath
                if faction == "Alliance" then texPath = FACTION_TEX .. "alliance.png"
                elseif faction == "Horde" then texPath = FACTION_TEX .. "horde.png"
                else texPath = FACTION_TEX .. "neutral.png" end
                GetFFD(btn).factionBg:SetTexture(texPath)
                GetFFD(btn).factionBg:SetTexCoord(0, 1, 0, 1)

                -- Name: class-colored if online, white 75% if offline
                local nameText = cd.name or ""
                if isOnline and classFile and fp.classColorNames ~= false then
                    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                    if cc then
                        nameText = format("|cff%02x%02x%02x%s|r", cc.r * 255, cc.g * 255, cc.b * 255, nameText)
                    end
                elseif not isOnline then
                    nameText = "|cffbfbfbf" .. nameText .. "|r"
                end
                GetFFD(btn).name:SetText(nameText)
                GetFFD(btn).name:SetWidth(0)

                -- Status orb
                local orb = GetFFD(btn).statusOrb
                if isOnline then
                    local _isv3 = issecretvalue
                    local sdDND = sd.isDND; local sdAFK = sd.isAFK
                    if (not _isv3 or not _isv3(sdDND)) and sdDND then orb:SetVertexColor(1, 0.2, 0.2, 1)
                    elseif (not _isv3 or not _isv3(sdAFK)) and sdAFK then orb:SetVertexColor(1, 0.8, 0, 1)
                    else orb:SetVertexColor(0.2, 1, 0.2, 1) end
                else
                    orb:SetVertexColor(0.4, 0.4, 0.4, 0.6)
                end
                orb:ClearAllPoints()
                orb:SetPoint("LEFT", GetFFD(btn).name, "RIGHT", -3, 1)
                orb:Show()

                -- Invite button: enabled for online, disabled for offline
                if GetFFD(btn).invBtn then
                    if isOnline then
                        GetFFD(btn).invBtn:SetNormalAtlas("friendslist-invitebutton-default-normal")
                        GetFFD(btn).invBtn:Enable()
                        GetFFD(btn).invBtn:SetAlpha(1)
                    else
                        GetFFD(btn).invBtn:SetNormalAtlas("friendslist-invitebutton-default-disabled")
                        GetFFD(btn).invBtn:Disable()
                        GetFFD(btn).invBtn:SetAlpha(0.4)
                    end
                end

                -- Info line: "Activity | Location"
                local activity = ""
                if elementData.interactionData and elementData.interactionData.interactions then
                    local interactions = elementData.interactionData.interactions
                    if #interactions > 0 then
                        activity = interactions[1].description or ""
                    end
                end
                local location = sd and sd.currentLocation or ""
                if activity ~= "" and location ~= "" then
                    GetFFD(btn).infoLine:SetText(activity .. "  |cff666666|  |r" .. location)
                elseif activity ~= "" then
                    GetFFD(btn).infoLine:SetText(activity)
                elseif location ~= "" then
                    GetFFD(btn).infoLine:SetText(location)
                else
                    GetFFD(btn).infoLine:SetText("")
                end
            end

            local RA_TYPE_DIVIDER = "ra_divider"
            local RA_TYPE_ALLY = "ra_ally"

            -- Divider initializer (same style as friends list "Friends" divider)
            local function InitRADivider(btn, elementData)
                btn:SetHeight(20)
                if not GetFFD(btn).divSetup then
                    GetFFD(btn).divSetup = true
                    btn:EnableMouse(false)

                    GetFFD(btn).divBg = btn:CreateTexture(nil, "BACKGROUND")
                    GetFFD(btn).divBg:SetAllPoints()
                    GetFFD(btn).divBg:SetColorTexture(0.059, 0.062, 0.065, 1)

                    GetFFD(btn).divLabel = btn:CreateFontString(nil, "OVERLAY")
                    GetFFD(btn).divLabel:SetFont(raFontPath, 9, "")
                    GetFFD(btn).divLabel:SetShadowOffset(1, -1)
                    GetFFD(btn).divLabel:SetShadowColor(0, 0, 0, 0.8)
                    GetFFD(btn).divLabel:SetTextColor(1, 1, 1, 0.4)
                    GetFFD(btn).divLabel:SetPoint("CENTER", btn, "CENTER", 0, 0)

                    GetFFD(btn).divLineL = btn:CreateTexture(nil, "OVERLAY")
                    GetFFD(btn).divLineL:SetColorTexture(1, 1, 1, 0.1)
                    GetFFD(btn).divLineL:SetHeight(1)
                    GetFFD(btn).divLineL:SetPoint("LEFT", btn, "LEFT", 8, 0)
                    GetFFD(btn).divLineL:SetPoint("RIGHT", GetFFD(btn).divLabel, "LEFT", -6, 0)

                    GetFFD(btn).divLineR = btn:CreateTexture(nil, "OVERLAY")
                    GetFFD(btn).divLineR:SetColorTexture(1, 1, 1, 0.1)
                    GetFFD(btn).divLineR:SetHeight(1)
                    GetFFD(btn).divLineR:SetPoint("LEFT", GetFFD(btn).divLabel, "RIGHT", 6, 0)
                    GetFFD(btn).divLineR:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
                end
                GetFFD(btn).divLabel:SetText(elementData.text or "")
            end

            -- Register our own view on the RA ScrollBox
            do
                local view = CreateScrollBoxListLinearView()
                view:SetPadding(0, 0, 0, 0, 2)
                view:SetElementExtentCalculator(function(dataIndex, elementData)
                    if elementData.entryType == RA_TYPE_DIVIDER then return 20 end
                    return 34
                end)
                view:SetElementFactory(function(factory, elementData)
                    if elementData.entryType == RA_TYPE_DIVIDER then
                        factory("Frame", function(btn, ed)
                            InitRADivider(btn, ed)
                        end)
                    else
                        factory("Button", function(btn, ed)
                            InitRAButton(btn, ed)
                        end)
                    end
                end)
                local scrollBar = rafSB.ScrollBar or raf.List.ScrollBar
                ScrollUtil.InitScrollBoxListWithScrollBar(rafSB, scrollBar, view)
            end

            -- Build DataProvider from C_RecentAllies API
            local _raSearchTerm = ""
            local function RebuildRADataProvider()
                if not C_RecentAllies or not C_RecentAllies.GetRecentAllies then return end
                local allies = C_RecentAllies.GetRecentAllies()
                if not allies then return end

                -- Build DataProvider preserving Blizzard's sort order
                -- Insert dividers at online/offline boundaries
                local newDP = CreateDataProvider()
                local insertedOnline = false
                local insertedOffline = false
                for _, ally in ipairs(allies) do
                    local cd = ally.characterData
                    if _raSearchTerm == "" or strfind((cd.name or ""):lower(), _raSearchTerm, 1, true) then
                        local isOnline = ally.stateData and ally.stateData.isOnline
                        if isOnline and not insertedOnline then
                            insertedOnline = true
                            newDP:Insert({ entryType = RA_TYPE_DIVIDER, text = "Recent Allies" })
                        elseif not isOnline and not insertedOffline then
                            insertedOffline = true
                            newDP:Insert({ entryType = RA_TYPE_DIVIDER, text = "Recent Allies (Offline)" })
                        end
                        newDP:Insert({
                            entryType = RA_TYPE_ALLY,
                            characterData = cd,
                            stateData = ally.stateData,
                            interactionData = ally.interactionData,
                        })
                    end
                end
                rafSB:SetDataProvider(newDP, true)
            end

            -- Loading indicator
            local raLoader = CreateFrame("Frame", nil, raf)
            raLoader:SetAllPoints(rafSB)
            raLoader:SetFrameLevel(rafSB:GetFrameLevel() + 20)
            raLoader:Hide()
            do
                local ar, ag, ab = EG.r, EG.g, EG.b
                local ring = raLoader:CreateTexture(nil, "ARTWORK")
                ring:SetSize(28, 28)
                ring:SetPoint("CENTER", raLoader, "CENTER", 0, 0)
                ring:SetAtlas("charactercreate-icon-customize-arrow-right")
                ring:SetVertexColor(ar, ag, ab, 0.6)
                local spinGroup = ring:CreateAnimationGroup()
                spinGroup:SetLooping("REPEAT")
                local spin = spinGroup:CreateAnimation("Rotation")
                spin:SetDegrees(-360)
                spin:SetDuration(1.2)
                raLoader._spinGroup = spinGroup
                local pulseGroup = raLoader:CreateAnimationGroup()
                pulseGroup:SetLooping("BOUNCE")
                local fadeOut = pulseGroup:CreateAnimation("Alpha")
                fadeOut:SetFromAlpha(1)
                fadeOut:SetToAlpha(0.4)
                fadeOut:SetDuration(0.8)
                fadeOut:SetSmoothing("IN_OUT")
                raLoader._pulseGroup = pulseGroup
            end

            local _raLoaded = false
            local function ShowRALoader()
                raLoader:Show()
                raLoader._spinGroup:Play()
                raLoader._pulseGroup:Play()
            end
            local function _hideRALoaderDeferred()
                raLoader._spinGroup:Stop()
                raLoader._pulseGroup:Stop()
                raLoader:Hide()
            end
            local function HideRALoader()
                C_Timer.After(0, _hideRALoaderDeferred)
            end

            -- Tab show: wait for data ready, then build
            raf:HookScript("OnShow", function()
                _raLoaded = false
                ShowRALoader()
                local function TryBuild()
                    if C_RecentAllies and C_RecentAllies.IsRecentAllyDataReady
                        and C_RecentAllies.IsRecentAllyDataReady() then
                        RebuildRADataProvider()
                        _raLoaded = true
                        HideRALoader()
                    else
                        C_Timer.After(0.25, TryBuild)
                    end
                end
                TryBuild()
            end)

            -- Listen for RA-specific data updates only
            local raEvents = CreateFrame("Frame")
            raEvents:RegisterEvent("RECENT_ALLIES_DATA_READY")
            raEvents:RegisterEvent("RECENT_ALLIES_CACHE_UPDATE")
            raEvents:RegisterEvent("RECENT_ALLY_DATA_UPDATED")
            raEvents:SetScript("OnEvent", function()
                if raf:IsShown() then
                    RebuildRADataProvider()
                    if not _raLoaded then
                        _raLoaded = true
                        HideRALoader()
                    end
                end
            end)

            -- Hook Send Message button to whisper selected RA entry
            local msgBtn = _G.FriendsFrameSendMessageButton
            if msgBtn then
                msgBtn:HookScript("OnClick", function()
                    if not raf:IsShown() then return end
                    if not _raSelectedGUID then return end
                    local allyData = C_RecentAllies.GetRecentAllyByGUID(_raSelectedGUID)
                    if allyData and allyData.characterData then
                        local fullName = allyData.characterData.fullName
                        if fullName then
                            ChatFrame_SendTell(fullName)
                        end
                    end
                end)
            end

            -- Clear selection on tab switch
            raf:HookScript("OnHide", function()
                _raSelectedGUID = nil
            end)

            -- Store for search
            GetFFD(frame).rebuildRA = RebuildRADataProvider
            GetFFD(frame).rAScrollBox = rafSB
            GetFFD(frame).rASetSearch = function(term)
                _raSearchTerm = term
                if raf:IsShown() and _raLoaded then RebuildRADataProvider() end
            end
        end
    end

    -- Search bar (below sub-tabs, above ScrollBox)
    local _ebsSearchTerm = ""
    do
        local search = CreateFrame("EditBox", nil, frame)
        search:SetSize(FriendsListFrame:GetWidth() - 30, 20)
        search:SetPoint("TOPLEFT", FriendsListFrame, "TOPLEFT", 15, -40)
        search:SetPoint("TOPRIGHT", FriendsListFrame, "TOPRIGHT", -15, -40)
        search:SetFrameLevel(frame:GetFrameLevel() + 5)
        search:SetAutoFocus(false)
        search:SetMaxLetters(20)
        search:SetJustifyH("LEFT")
        search:SetFont(fontPath, 10, "")
        search:SetTextColor(1, 1, 1, 0.9)

        local sBg = search:CreateTexture(nil, "BACKGROUND")
        sBg:SetAllPoints()
        sBg:SetColorTexture(0, 0, 0, 0.4)
        PP.CreateBorder(search, 1, 1, 1, 0.1, 1, "OVERLAY", 7)

        local sPh = search:CreateFontString(nil, "OVERLAY")
        sPh:SetFont(fontPath, 10, "")
        sPh:SetTextColor(0.5, 0.5, 0.5, 0.6)
        sPh:SetPoint("LEFT", search, "LEFT", 6, 0)
        sPh:SetText("Search...")

        -- Clear button (small x on the right)
        local clearBtn = CreateFrame("Button", nil, search)
        clearBtn:SetSize(14, 14)
        clearBtn:SetPoint("RIGHT", search, "RIGHT", -4, 0)
        clearBtn:SetFrameLevel(search:GetFrameLevel() + 1)
        local clearX = clearBtn:CreateFontString(nil, "OVERLAY")
        clearX:SetFont(fontPath, 11, "")
        clearX:SetText("x")
        clearX:SetTextColor(1, 1, 1, 0.3)
        clearX:SetPoint("CENTER", 0, 0)
        clearBtn:SetScript("OnEnter", function() clearX:SetTextColor(1, 1, 1, 0.7) end)
        clearBtn:SetScript("OnLeave", function() clearX:SetTextColor(1, 1, 1, 0.3) end)
        clearBtn:SetScript("OnClick", function()
            search:SetText("")
            search:ClearFocus()
        end)
        clearBtn:Hide()

        search:SetTextInsets(6, 18, 0, 0)  -- extra right inset for clear button

        search:SetScript("OnTextChanged", function(self)
            local t = strtrim(self:GetText())
            sPh:SetShown(t == "")
            clearBtn:SetShown(t ~= "")
            _ebsSearchTerm = t:lower()
            -- Filter friends list -- "direct" bypasses the 500ms debounce
            -- so every keystroke updates the list immediately.
            if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP("direct") end
            -- Filter Recent Allies via DataProvider rebuild
            if GetFFD(frame).rASetSearch then GetFFD(frame).rASetSearch(_ebsSearchTerm) end
        end)
        search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

        GetFFD(frame).searchBox = search
    end

    -- Skin scrollbars
    SkinScrollbars()

    -- Scroll-pause: skip ALL hook work while user is actively scrolling.
    -- ProcessFriendButtons runs once when scrolling stops to catch up.
    local _ebsScrolling = false
    local _ebsScrollTimer = nil
    local _ebsScrollLast = 0
    local SCROLL_PAUSE = 0.3    -- seconds after last scroll event to resume updates
    local SCROLL_THROTTLE = 0.1 -- minimum seconds between timer resets

    local function _ebsOnScrollStop()
        _ebsScrolling = false
        _ebsScrollTimer = nil
        -- Clear stamps and restyle so live data updates (AFK, offline) are picked up
        if FriendsFrame:IsShown() then
            local sb = FriendsListFrame and FriendsListFrame.ScrollBox
            if sb then
                for _, btn in sb:EnumerateFrames() do
                    GetFFD(btn).stampType = nil
                end
            end
            ProcessFriendButtons()
        end
    end

    local function _ebsOnScrollActivity()
        _ebsScrolling = true
        local now = GetTime()
        if now - _ebsScrollLast < SCROLL_THROTTLE then return end
        _ebsScrollLast = now
        if _ebsScrollTimer then _ebsScrollTimer:Cancel() end
        _ebsScrollTimer = C_Timer.NewTimer(SCROLL_PAUSE, _ebsOnScrollStop)
    end

    -- Inject scroll detection into the friends ScrollBox and ScrollBar
    local friendsSB = FriendsListFrame and FriendsListFrame.ScrollBox
    if friendsSB then
        friendsSB:HookScript("OnMouseWheel", _ebsOnScrollActivity)
    end
    local friendsBar = FriendsListFrame and FriendsListFrame.ScrollBar
    if friendsBar and friendsBar.RegisterCallback then
        friendsBar:RegisterCallback("OnScroll", _ebsOnScrollActivity)
    end

    -- Post-update skinning for friend buttons. Called directly from our own
    -- ScrollBox factory -- NOT via hooksecurefunc on the global function.
    -- A global hook on FriendsFrame_UpdateFriendButton tainted Blizzard's
    -- secure execution paths (HistoryKeeper token creation, chat message
    -- processing) exactly like the old FriendsList_Update hook did.
    local function PostUpdateFriendButton(button)
            if not FriendsFrame:IsShown() then return end
            if not EBS.db or not EBS.db.profile.friends.enabled then return end
            if button.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then return end
            -- Structural skinning always runs (guarded by FFD skinned flag, only fires once per button)
            SkinFriendButton(button)

            -- On click, refresh all visible buttons in our ScrollBox so selection updates
            -- Selection highlight (update on every refresh for recycled buttons)
            if not GetFFD(button).selBar then
                local sel = button:CreateTexture(nil, "ARTWORK", nil, -7)
                sel:SetAllPoints()
                sel:SetAtlas("groupfinder-highlightbar-green")
                sel:SetDesaturated(true)
                sel:SetVertexColor(0.4, 0.7, 1.0)
                sel:SetAlpha(1)
                sel:Hide()
                local selFill = button:CreateTexture(nil, "ARTWORK", nil, -8)
                selFill:SetAllPoints()
                selFill:SetColorTexture(1, 1, 1, 0.02)
                selFill:SetBlendMode("ADD")
                selFill:Hide()
                GetFFD(button).selBar = sel
                GetFFD(button).selFill = selFill
            end
            local isSel = (FriendsFrame.selectedFriend == button.id)
            GetFFD(button).selBar:SetShown(isSel)
            if GetFFD(button).selFill then GetFFD(button).selFill:SetShown(isSel) end

            if not GetFFD(button).clickHooked then
                GetFFD(button).clickHooked = true
                button:HookScript("OnClick", function()
                    local sb = GetFFD(FriendsFrame).ourScrollBox
                    if sb then
                        for _, btn in sb:EnumerateFrames() do
                            if GetFFD(btn).selBar then
                                local sel = (FriendsFrame.selectedFriend == btn.id)
                                GetFFD(btn).selBar:SetShown(sel)
                                if GetFFD(btn).selFill then GetFFD(btn).selFill:SetShown(sel) end
                            end
                        end
                    end
                end)
            end

            -- Hide Blizzard elements immediately so they don't flash during scroll
            local fav = button.Favorite
            if fav then fav:SetAlpha(0) end
            local statusIcon = button.statusIcon or button.StatusIcon
            if statusIcon then statusIcon:SetAlpha(0) end
            local statusTex = button.status
            if statusTex and statusTex.IsObjectType and statusTex:IsObjectType("Texture") then
                statusTex:SetAlpha(0)
            end
            local gameIcon = button.gameIcon
            if gameIcon then gameIcon:SetAlpha(0) end

            -- Fill blank info text for BNet app users (runs every hook call, not stamped)
            if button.buttonType == FRIENDS_BUTTON_TYPE_BNET and button.id then
                local infoFS = button.info or button.Info
                if infoFS and (not infoFS:GetText() or infoFS:GetText() == "") then
                    local cached = _friendCache[button.id]
                    if cached and cached.gameAccountInfo then
                        local gi = cached.gameAccountInfo
                        local cp = gi.clientProgram
                        if gi.isOnline and (cp == "App" or cp == "BSAp") then
                            local locale = GetLocale()
                            infoFS:SetText((locale == "enUS" or locale == "enGB") and "In App" or "Battle.Net")
                        end
                    end
                end
            end

            -- Stamp: run data work once per button per friend assignment, skip repeats.
            -- Blizzard calls this hook many times for the same button+friend combo.
            -- We only need to style once -- subsequent calls for the same combo are no-ops.
            local curType = button.buttonType
            local curId = button.id or 0
            if GetFFD(button).stampType == curType and GetFFD(button).stampId == curId then return end
            GetFFD(button).stampType = curType
            GetFFD(button).stampId = curId

            local bnetInfo, wowInfo = GetCachedFriendInfo(button)

            -- Re-anchor info text below name so it lines up
            local nameText = button.name or button.Name
            local infoText = button.info or button.Info
            if infoText and nameText then
                infoText:ClearAllPoints()
                infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -3)
            end

            -- Append friend note (from Blizzard note, stripped of EUI group tag)
            if infoText and button.buttonType and button.id then
                local userNote
                if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
                    local cached = _friendCache[button.id]
                    if cached and cached.note then
                        local _, clean = ParseGroupFromNote(cached.note)
                        if clean and clean ~= "" then userNote = clean end
                    end
                elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
                    local cached = _friendCache[button.id + _FC_WOW_OFFSET]
                    if cached and cached.notes then
                        local _, clean = ParseGroupFromNote(cached.notes)
                        if clean and clean ~= "" then userNote = clean end
                    end
                end
                if userNote then
                    local curText = infoText:GetText() or ""
                    if curText ~= "" then
                        infoText:SetText(curText .. "  |cff888888|  " .. userNote .. "|r")
                    else
                        infoText:SetText("|cff888888" .. userNote .. "|r")
                    end
                end
            end
            -- Determine online/away/busy state
            local isOnline, isAFK, isDND = false, false, false
            local _isv = issecretvalue
            if bnetInfo then
                isOnline = bnetInfo.gameAccountInfo and bnetInfo.gameAccountInfo.isOnline
                local rawAFK = bnetInfo.isAFK
                local rawDND = bnetInfo.isDND
                isAFK = (not _isv or not _isv(rawAFK)) and rawAFK or false
                isDND = (not _isv or not _isv(rawDND)) and rawDND or false
            elseif wowInfo then
                isOnline = wowInfo.connected
                local rawAFK = wowInfo.afk
                local rawDND = wowInfo.dnd
                isAFK = (not _isv or not _isv(rawAFK)) and rawAFK or false
                isDND = (not _isv or not _isv(rawDND)) and rawDND or false
            end

            if not GetFFD(button).statusOrb then
                GetFFD(button).statusOrb = button:CreateTexture(nil, "OVERLAY", nil, 3)
                GetFFD(button).statusOrb:SetSize(18, 18)
                if _orbFile then
                    GetFFD(button).statusOrb:SetTexture(_orbFile)
                    GetFFD(button).statusOrb:SetTexCoord(_orbL, _orbR, _orbT, _orbB)
                else
                    GetFFD(button).statusOrb:SetAtlas("lootroll-animreveal-a")
                    GetFFD(button).statusOrb:SetTexCoord(0, 1/6, 0, 0.5)
                end
            end
            local orb = GetFFD(button).statusOrb
            orb:ClearAllPoints()
            local nm = button.name or button.Name
            if nm then
                local textW = nm:GetStringWidth() or 0
                orb:SetPoint("TOPLEFT", nm, "TOPLEFT", textW - 1, 2)
            end
            if isOnline then
                if isDND then
                    orb:SetVertexColor(1, 0.2, 0.2, 1)
                elseif isAFK then
                    orb:SetVertexColor(1, 0.8, 0, 1)
                else
                    orb:SetVertexColor(0.2, 1, 0.2, 1)
                end
                orb:Show()
            else
                orb:SetVertexColor(0.4, 0.4, 0.4, 0.6)
                orb:Show()
            end
            UpdateClassIcon(button, bnetInfo, wowInfo)
            UpdateNameColor(button, bnetInfo, wowInfo)
            UpdateFactionOverlay(button, bnetInfo, wowInfo)

            -- Region icon: show if friend is in a different full region
            local fp2 = EBS.db and EBS.db.profile and EBS.db.profile.friends
            if fp2 and fp2.showRegionIcons == false then
                if GetFFD(button).regionBtn then GetFFD(button).regionBtn:Hide() end
            else
            local myFull = EllesmereUI.GetMyFullRegion and EllesmereUI.GetMyFullRegion()
            local friendMini
            if bnetInfo and bnetInfo.gameAccountInfo then
                friendMini = EllesmereUI.GetFriendMiniRegion and EllesmereUI.GetFriendMiniRegion(bnetInfo.gameAccountInfo)
            end
            local friendFull = friendMini and EllesmereUI.GetFullRegion and EllesmereUI.GetFullRegion(friendMini)

            if friendMini and friendFull and friendFull ~= myFull then
                if not GetFFD(button).regionBtn then
                    local rb = CreateFrame("Button", nil, button)
                    rb:SetFrameLevel(button:GetFrameLevel() + 5)
                    rb._tex = rb:CreateTexture(nil, "OVERLAY", nil, 7)
                    rb._tex:SetAllPoints()
                    rb._tex:SetAlpha(0.25)
                    rb:SetScript("OnEnter", function(self)
                        if EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, self._regionLabel or "")
                        end
                    end)
                    rb:SetScript("OnLeave", function()
                        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                    end)
                    local h = button:GetHeight()
                    local iconH = math.floor(h * 0.8)
                    rb:SetSize(iconH, iconH)
                    local tpBtn = button.travelPassButton
                    if tpBtn then
                        rb:SetPoint("RIGHT", tpBtn, "LEFT", -2, 0)
                    else
                        rb:SetPoint("RIGHT", button, "RIGHT", -30, 0)
                    end
                    GetFFD(button).regionBtn = rb
                end
                local rb = GetFFD(button).regionBtn
                if rb._lastMini ~= friendMini then
                    rb._lastMini = friendMini
                    local iconPath = EllesmereUI.GetRegionIcon and EllesmereUI.GetRegionIcon(friendMini)
                    rb._tex:SetTexture(iconPath)
                    rb._tex:SetTexCoord(0, 1, 0, 1)
                    rb._regionLabel = MINI_DISPLAY[friendMini] or friendMini
                end
                rb:Show()
            else
                if GetFFD(button).regionBtn then GetFFD(button).regionBtn:Hide() end
            end
            end -- showRegionIcons else
    end

    ---------------------------------------------------------------------------
    --  Friend Grouping: Element Factory + DataProvider Rebuild
    ---------------------------------------------------------------------------
    -- Priority from already-fetched info (avoids redundant API calls and throwaway tables)
    local function GetBNetPriority(info)
        if info and info.gameAccountInfo then
            local gi = info.gameAccountInfo
            if gi.isOnline then
                if gi.clientProgram == BNET_CLIENT_WOW then
                    return (gi.wowProjectID == 1 or gi.wowProjectID == nil) and 1 or 2
                end
                local cp = gi.clientProgram
                if not cp or cp == "" or cp == "BSAp" or cp == "App" then
                    return 4  -- BNet app / desktop client
                else
                    return 3  -- Other Blizzard game
                end
            end
        end
        return 5
    end

    -- Divider initializer: called by the element factory when rendering a divider
    local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"
    local DIV_ICON_SZ = 12
    local DIV_ICON_ALPHA = 0.35
    local DIV_ICON_HOVER = 0.7

    local EBS_FAVORITES_KEY = "Favorites"  -- internal key, never displayed

    local function InitDividerButton(btn, elementData)
        local groupName = elementData._groupKey  -- internal key for logic
        local displayName = elementData.text or ""
        local isFavorites = (groupName == EBS_FAVORITES_KEY)
        local isDefault = (groupName == nil or groupName == false)
        local isPending = (groupName == "_pending")

        -- Kill any highlight on the plain Button template
        if not GetFFD(btn).hlKilled then
            GetFFD(btn).hlKilled = true
            local hl = btn:GetHighlightTexture()
            if hl then hl:SetAlpha(0) end
            btn:EnableMouse(false)  -- divider itself doesn't receive mouse; child buttons do
        end

        if not GetFFD(btn).divSetup then
            GetFFD(btn).divSetup = true
            -- Background #141516
            GetFFD(btn).divBg = btn:CreateTexture(nil, "BACKGROUND")
            GetFFD(btn).divBg:SetAllPoints()
            GetFFD(btn).divBg:SetColorTexture(0.059, 0.062, 0.065, 1)

            -- Label (centered, color set per-init)
            GetFFD(btn).divLabel = btn:CreateFontString(nil, "OVERLAY")
            GetFFD(btn).divLabel:SetFont(fontPath, 9, "")
            GetFFD(btn).divLabel:SetShadowOffset(1, -1)
            GetFFD(btn).divLabel:SetShadowColor(0, 0, 0, 0.8)
            GetFFD(btn).divLabel:SetPoint("CENTER", btn, "CENTER", 0, 0)


            -- Up arrow (move group up in order)
            local upBtn = CreateFrame("Button", nil, btn)
            upBtn:SetSize(DIV_ICON_SZ, DIV_ICON_SZ)
            upBtn:SetFrameLevel(btn:GetFrameLevel() + 2)
            local upIcon = upBtn:CreateTexture(nil, "OVERLAY")
            upIcon:SetAllPoints()
            upIcon:SetTexture(MEDIA .. "icons\\eui-arrow-up3.png")
            upBtn:SetAlpha(DIV_ICON_ALPHA)
            upBtn:SetScript("OnEnter", function(self) self:SetAlpha(DIV_ICON_HOVER) end)
            upBtn:SetScript("OnLeave", function(self) self:SetAlpha(DIV_ICON_ALPHA) end)
            GetFFD(btn).divUp = upBtn

            -- Down arrow (move group down in order)
            local downBtn = CreateFrame("Button", nil, btn)
            downBtn:SetSize(DIV_ICON_SZ, DIV_ICON_SZ)
            downBtn:SetFrameLevel(btn:GetFrameLevel() + 2)
            local downIcon = downBtn:CreateTexture(nil, "OVERLAY")
            downIcon:SetAllPoints()
            downIcon:SetTexture(MEDIA .. "icons\\eui-arrow-down3.png")
            downBtn:SetAlpha(DIV_ICON_ALPHA)
            downBtn:SetScript("OnEnter", function(self) self:SetAlpha(DIV_ICON_HOVER) end)
            downBtn:SetScript("OnLeave", function(self) self:SetAlpha(DIV_ICON_ALPHA) end)
            GetFFD(btn).divDown = downBtn

            -- Lines on either side of text
            GetFFD(btn).divLineL = btn:CreateTexture(nil, "OVERLAY")
            GetFFD(btn).divLineL:SetColorTexture(1, 1, 1, 0.1)
            GetFFD(btn).divLineL:SetHeight(1)
            GetFFD(btn).divLineL:SetPoint("LEFT", btn, "LEFT", 8, 0)
            GetFFD(btn).divLineL:SetPoint("RIGHT", GetFFD(btn).divLabel, "LEFT", -6, 0)
            GetFFD(btn).divLine = btn:CreateTexture(nil, "OVERLAY")
            GetFFD(btn).divLine:SetColorTexture(1, 1, 1, 0.1)
            GetFFD(btn).divLine:SetHeight(1)
            -- Right line starts after label
            GetFFD(btn).divLine:SetPoint("LEFT", GetFFD(btn).divLabel, "RIGHT", 6, 0)

            -- Hover highlight for collapse (10% brighter)
            GetFFD(btn).divHover = btn:CreateTexture(nil, "ARTWORK", nil, -5)
            GetFFD(btn).divHover:SetAllPoints()
            GetFFD(btn).divHover:SetColorTexture(1, 1, 1, 0.06)
            GetFFD(btn).divHover:Hide()

            -- Enable mouse on divider for hover + click-to-collapse
            btn:EnableMouse(true)
            btn:SetScript("OnEnter", function() GetFFD(btn).divHover:Show() end)
            btn:SetScript("OnLeave", function() GetFFD(btn).divHover:Hide() end)

            -- X / delete button
            local xBtn = CreateFrame("Button", nil, btn)
            xBtn:SetSize(DIV_ICON_SZ, DIV_ICON_SZ)
            xBtn:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
            xBtn:SetFrameLevel(btn:GetFrameLevel() + 2)
            local xIcon = xBtn:CreateTexture(nil, "OVERLAY")
            xIcon:SetAllPoints()
            xIcon:SetTexture(MEDIA .. "icons\\eui-close.png")
            xBtn:SetAlpha(DIV_ICON_ALPHA)
            xBtn:SetScript("OnEnter", function(self) self:SetAlpha(DIV_ICON_HOVER) end)
            xBtn:SetScript("OnLeave", function(self) self:SetAlpha(DIV_ICON_ALPHA) end)
            GetFFD(btn).divX = xBtn

            -- Edit / rename button
            local editBtn = CreateFrame("Button", nil, btn)
            editBtn:SetSize(DIV_ICON_SZ, DIV_ICON_SZ)
            editBtn:SetPoint("RIGHT", xBtn, "LEFT", -4, 0)
            editBtn:SetFrameLevel(btn:GetFrameLevel() + 2)
            local editIcon = editBtn:CreateTexture(nil, "OVERLAY")
            editIcon:SetAllPoints()
            editIcon:SetTexture(MEDIA .. "icons\\eui-edit.png")
            editBtn:SetAlpha(DIV_ICON_ALPHA)
            editBtn:SetScript("OnEnter", function(self) self:SetAlpha(DIV_ICON_HOVER) end)
            editBtn:SetScript("OnLeave", function(self) self:SetAlpha(DIV_ICON_ALPHA) end)
            GetFFD(btn).divEdit = editBtn

            -- Right line endpoint set dynamically in visibility block below
        end

        -- Update text and color
        GetFFD(btn).divLabel:SetText(displayName)
        local colorKey = groupName or (isFavorites and ORDER_FAVORITES) or (isDefault and ORDER_UNGROUPED) or "_pending"
        local fg = GetFriendGroupsGlobal()
        local gc = fg.friendGroupColors[colorKey]
        if gc then
            GetFFD(btn).divLabel:SetTextColor(gc.r, gc.g, gc.b, 1)
        else
            local ar, ag, ab = EG.r, EG.g, EG.b
            GetFFD(btn).divLabel:SetTextColor(ar, ag, ab, 1)
        end

        -- Click label to open our custom color picker
        GetFFD(btn).colorKey = colorKey
        if not GetFFD(btn).divLabelBtn then
            local labelBtn = CreateFrame("Button", nil, btn)
            labelBtn:SetHeight(20)
            labelBtn:SetFrameLevel(btn:GetFrameLevel() + 3)
            GetFFD(btn).divLabelBtn = labelBtn
        end
        GetFFD(btn).divLabelBtn:ClearAllPoints()
        GetFFD(btn).divLabelBtn:SetPoint("CENTER", GetFFD(btn).divLabel, "CENTER", 0, 0)
        GetFFD(btn).divLabelBtn:SetWidth((GetFFD(btn).divLabel:GetStringWidth() or 40) + 8)
        GetFFD(btn).divLabelBtn:SetScript("OnClick", function()
            local ck = GetFFD(btn).colorKey
            if not ck then return end
            -- Widgets file is deferred; make sure ShowColorPicker exists
            -- before we call it (CDM is normally what triggers EnsureLoaded
            -- on startup, so without CDM the picker is still nil here).
            if EllesmereUI.EnsureLoaded then EllesmereUI:EnsureLoaded() end
            local fg3 = GetFriendGroupsGlobal()
            local gc2 = fg3.friendGroupColors[ck]
            local cr, cg, cb
            if gc2 then
                cr, cg, cb = gc2.r, gc2.g, gc2.b
            else
                cr, cg, cb = EG.r, EG.g, EG.b
            end
            local snapR, snapG, snapB = cr, cg, cb
            local info = {
                r = cr, g = cg, b = cb,
                hasOpacity = false,
                swatchFunc = function()
                    local popup = EllesmereUI._colorPickerPopup
                    if not popup then return end
                    local nr, ng, nb = popup:GetColorRGB()
                    fg3.friendGroupColors[ck] = { r = nr, g = ng, b = nb }
                    if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
                end,
                cancelFunc = function()
                    fg3.friendGroupColors[ck] = { r = snapR, g = snapG, b = snapB }
                    if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
                end,
            }
            EllesmereUI:ShowColorPicker(info, GetFFD(btn).divLabelBtn)
        end)


        -- Check collapsed state
        local fg = GetFriendGroupsGlobal()
        local collapsed = false
        if isPending then
            collapsed = fg.friendPendingCollapsed
        elseif isFavorites then
            collapsed = fg.friendFavCollapsed
        elseif isDefault then
            collapsed = fg.friendUngroupedCollapsed
        else
            for _, g in ipairs(fg.friendGroups) do
                if g.name == groupName then collapsed = g.collapsed; break end
            end
        end

        -- Layout: ↑ ------- Label ------- ↓       (Favorites/Friends)
        --         ↑ ↓ ----- Label ----- ✎ ✕    (Custom groups)
        --         ------- Label -------          (Pending)
        if isFavorites or isDefault or isPending then
            GetFFD(btn).divX:Hide()
            GetFFD(btn).divEdit:Hide()
            if isPending then
                GetFFD(btn).divUp:Hide()
                GetFFD(btn).divDown:Hide()
                GetFFD(btn).divLineL:ClearAllPoints()
                GetFFD(btn).divLineL:SetPoint("LEFT", btn, "LEFT", 8, 0)
                GetFFD(btn).divLineL:SetPoint("RIGHT", GetFFD(btn).divLabel, "LEFT", -6, 0)
                GetFFD(btn).divLine:ClearAllPoints()
                GetFFD(btn).divLine:SetColorTexture(1, 1, 1, 0.1)
                GetFFD(btn).divLine:SetHeight(1)
                GetFFD(btn).divLine:SetPoint("LEFT", GetFFD(btn).divLabel, "RIGHT", 6, 0)
                GetFFD(btn).divLine:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
            else
                -- Favorites and Friends: up on left, down on right for symmetry
                GetFFD(btn).divUp:Show()
                GetFFD(btn).divDown:Show()
                GetFFD(btn).divUp:ClearAllPoints()
                GetFFD(btn).divDown:ClearAllPoints()
                GetFFD(btn).divUp:SetPoint("LEFT", btn, "LEFT", 8, 0)
                GetFFD(btn).divDown:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
                GetFFD(btn).divLineL:ClearAllPoints()
                GetFFD(btn).divLineL:SetPoint("LEFT", GetFFD(btn).divUp, "RIGHT", 6, 0)
                GetFFD(btn).divLineL:SetPoint("RIGHT", GetFFD(btn).divLabel, "LEFT", -6, 0)
                GetFFD(btn).divLine:ClearAllPoints()
                GetFFD(btn).divLine:SetColorTexture(1, 1, 1, 0.1)
                GetFFD(btn).divLine:SetHeight(1)
                GetFFD(btn).divLine:SetPoint("LEFT", GetFFD(btn).divLabel, "RIGHT", 6, 0)
                GetFFD(btn).divLine:SetPoint("RIGHT", GetFFD(btn).divDown, "LEFT", -6, 0)
            end
        else
            -- Custom group: up edit -- Label -- close down (symmetric)
            GetFFD(btn).divX:Show()
            GetFFD(btn).divEdit:Show()
            GetFFD(btn).divUp:Show()
            GetFFD(btn).divDown:Show()
            GetFFD(btn).divUp:ClearAllPoints()
            GetFFD(btn).divDown:ClearAllPoints()
            GetFFD(btn).divEdit:ClearAllPoints()
            GetFFD(btn).divX:ClearAllPoints()
            -- Left side: up arrow, then edit
            GetFFD(btn).divUp:SetPoint("LEFT", btn, "LEFT", 8, 0)
            GetFFD(btn).divEdit:SetPoint("LEFT", GetFFD(btn).divUp, "RIGHT", 4, 0)
            -- Right side: down arrow, then X (inner)
            GetFFD(btn).divDown:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
            GetFFD(btn).divX:SetPoint("RIGHT", GetFFD(btn).divDown, "LEFT", -4, 0)
            -- Left line: after edit to label
            GetFFD(btn).divLineL:ClearAllPoints()
            GetFFD(btn).divLineL:SetPoint("LEFT", GetFFD(btn).divEdit, "RIGHT", 6, 0)
            GetFFD(btn).divLineL:SetPoint("RIGHT", GetFFD(btn).divLabel, "LEFT", -6, 0)
            -- Right line: after label to X
            GetFFD(btn).divLine:ClearAllPoints()
            GetFFD(btn).divLine:SetColorTexture(1, 1, 1, 0.1)
            GetFFD(btn).divLine:SetHeight(1)
            GetFFD(btn).divLine:SetPoint("LEFT", GetFFD(btn).divLabel, "RIGHT", 6, 0)
            GetFFD(btn).divLine:SetPoint("RIGHT", GetFFD(btn).divX, "LEFT", -6, 0)
        end

        -- Click on divider bar to toggle collapse
        btn:SetScript("OnClick", function()
            local fg2 = GetFriendGroupsGlobal()
            if isPending then
                fg2.friendPendingCollapsed = not fg2.friendPendingCollapsed
            elseif isFavorites then
                fg2.friendFavCollapsed = not fg2.friendFavCollapsed
            elseif isDefault then
                fg2.friendUngroupedCollapsed = not fg2.friendUngroupedCollapsed
            else
                for _, g in ipairs(fg2.friendGroups) do
                    if g.name == groupName then g.collapsed = not g.collapsed; break end
                end
            end
            if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP("direct") end
        end)

        if not isFavorites and not isDefault and not isPending then
            GetFFD(btn).divX:SetScript("OnClick", function()
                local dialog = StaticPopup_Show("EBS_DELETE_FRIEND_GROUP", displayName)
                if dialog then dialog.data = groupName end
            end)
            GetFFD(btn).divEdit:SetScript("OnClick", function()
                local dialog = StaticPopup_Show("EBS_NEW_FRIEND_GROUP")
                if dialog then
                    dialog.data = { renameFrom = groupName }
                    local eb = dialog.EditBox or dialog.editBox
                    if eb then eb:SetText(groupName) end
                end
            end)
        end

        -- Arrow reordering for all groups (Favorites, custom, Friends -- not pending)
        if not isPending then
            local orderKey = groupName
            if isFavorites then orderKey = ORDER_FAVORITES
            elseif isDefault then orderKey = ORDER_UNGROUPED end

            local isFirst = elementData._isFirstGroup
            local isLast = elementData._isLastGroup

            -- Disable/gray out arrows at boundaries (keep mouse enabled to block hover)
            if isFirst then
                GetFFD(btn).divUp:SetAlpha(0.06)
                GetFFD(btn).divUp:SetScript("OnEnter", nil)
                GetFFD(btn).divUp:SetScript("OnLeave", nil)
            else
                GetFFD(btn).divUp:SetAlpha(DIV_ICON_ALPHA)
                GetFFD(btn).divUp:EnableMouse(true)
                GetFFD(btn).divUp:SetScript("OnEnter", function(self) self:SetAlpha(DIV_ICON_HOVER) end)
                GetFFD(btn).divUp:SetScript("OnLeave", function(self) self:SetAlpha(DIV_ICON_ALPHA) end)
            end
            if isLast then
                GetFFD(btn).divDown:SetAlpha(0.06)
                GetFFD(btn).divDown:SetScript("OnEnter", nil)
                GetFFD(btn).divDown:SetScript("OnLeave", nil)
            else
                GetFFD(btn).divDown:SetAlpha(DIV_ICON_ALPHA)
                GetFFD(btn).divDown:EnableMouse(true)
                GetFFD(btn).divDown:SetScript("OnEnter", function(self) self:SetAlpha(DIV_ICON_HOVER) end)
                GetFFD(btn).divDown:SetScript("OnLeave", function(self) self:SetAlpha(DIV_ICON_ALPHA) end)
            end

            GetFFD(btn).divUp:SetScript("OnClick", function()
                if isFirst then return end
                local order = GetValidGroupOrder()
                for idx, k in ipairs(order) do
                    if k == orderKey and idx > 1 then
                        order[idx], order[idx - 1] = order[idx - 1], order[idx]
                        if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
                        break
                    end
                end
            end)
            GetFFD(btn).divDown:SetScript("OnClick", function()
                if isLast then return end
                local order = GetValidGroupOrder()
                for idx, k in ipairs(order) do
                    if k == orderKey and idx < #order then
                        order[idx], order[idx + 1] = order[idx + 1], order[idx]
                        if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
                        break
                    end
                end
            end)
        end
    end

    -- Custom pending invite button type
    local EBS_BUTTON_TYPE_PENDING = 999

    local function InitPendingButton(btn, elementData)
        -- Height: 36 content + top/bottom spacing
        local topGap = elementData._isFirst and 1 or 0
        local bottomGap = elementData._isLast and 1 or 2
        btn:SetHeight(36 + topGap + bottomGap)
        if not GetFFD(btn).pendingSkinned then
            GetFFD(btn).pendingSkinned = true

            -- Tile bg (slightly brighter with blue tint)
            GetFFD(btn).tileBg = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
            GetFFD(btn).tileBg:SetColorTexture(0.05, 0.15, 0.20, 0.30)

            -- Neutral overlay
            GetFFD(btn).factionBg = btn:CreateTexture(nil, "BACKGROUND", nil, 3)
            GetFFD(btn).factionBg:SetTexture(FACTION_TEX_NEUTRAL)
            GetFFD(btn).factionBg:SetTexCoord(0, 1, 0, 1)
            GetFFD(btn).factionBg:SetAlpha(0.2)

            -- Hover highlight
            local hover = btn:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            hover:SetColorTexture(1, 1, 1, 0.05)
            hover:SetBlendMode("ADD")

            -- Name (12pt, shadow)
            GetFFD(btn).name = btn:CreateFontString(nil, "OVERLAY")
            GetFFD(btn).name:SetFont(fontPath, 12, "")
            GetFFD(btn).name:SetShadowOffset(1, -1)
            GetFFD(btn).name:SetShadowColor(0, 0, 0, 0.8)
            GetFFD(btn).name:SetPoint("LEFT", btn, "LEFT", 10, 4)
            GetFFD(btn).name:SetTextColor(0.51, 0.784, 1, 1)

            -- Info line (9pt, shadow)
            GetFFD(btn).subText = btn:CreateFontString(nil, "OVERLAY")
            GetFFD(btn).subText:SetFont(fontPath, 9, "")
            GetFFD(btn).subText:SetShadowOffset(1, -1)
            GetFFD(btn).subText:SetShadowColor(0, 0, 0, 0.8)
            GetFFD(btn).subText:SetPoint("TOPLEFT", GetFFD(btn).name, "BOTTOMLEFT", 0, -2)
            GetFFD(btn).subText:SetTextColor(0.5, 0.5, 0.5, 0.8)

            -- Decline button (x, right side)
            local declineBtn = CreateFrame("Button", nil, btn)
            declineBtn:SetSize(20, 20)
            declineBtn:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            declineBtn:SetFrameLevel(btn:GetFrameLevel() + 3)
            local decX = declineBtn:CreateFontString(nil, "OVERLAY")
            decX:SetFont(fontPath, 14, "")
            decX:SetText("x")
            decX:SetTextColor(1, 1, 1, 0.3)
            decX:SetPoint("CENTER", 0, 1)
            declineBtn:SetScript("OnEnter", function()
                decX:SetTextColor(1, 0.3, 0.3, 0.8)
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(declineBtn, DECLINE or "Decline")
                end
            end)
            declineBtn:SetScript("OnLeave", function()
                decX:SetTextColor(1, 1, 1, 0.3)
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)
            declineBtn:SetScript("OnClick", function()
                local invID = GetFFD(btn).inviteID
                if invID and BNDeclineFriendInvite then BNDeclineFriendInvite(invID) end
            end)
            GetFFD(btn).declineBtn = declineBtn

            -- Accept button (styled like Add Friend / Send Message buttons)
            local acceptBtn = CreateFrame("Button", nil, btn)
            local m = PP.mult or 1
            acceptBtn:SetSize(70, math.floor(18 / m + 0.5) * m)
            acceptBtn:SetPoint("RIGHT", declineBtn, "LEFT", -6, 0)
            acceptBtn:SetFrameLevel(btn:GetFrameLevel() + 3)

            local acceptBg = acceptBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
            acceptBg:SetColorTexture(0.025, 0.035, 0.045, 0.92)
            acceptBg:SetAllPoints()

            PP.CreateBorder(acceptBtn, 1, 1, 1, 0.4, 1, "OVERLAY", 7)

            local acceptLabel = acceptBtn:CreateFontString(nil, "OVERLAY")
            acceptLabel:SetFont(fontPath, 9, "")
            acceptLabel:SetTextColor(1, 1, 1, 0.5)
            acceptLabel:SetPoint("CENTER", 0, 0)
            acceptLabel:SetText(ACCEPT or "Accept")
            GetFFD(btn).acceptLabel = acceptLabel

            -- Accent support: read from DB, same pattern as bottom buttons
            GetFFD(acceptBtn).accent = false
            acceptBtn:SetScript("OnEnter", function()
                local r, g, b, a1, a2 = 1, 1, 1, 0.7, 0.6
                if GetFFD(acceptBtn).accent then
                    r, g, b = EG.r, EG.g, EG.b
                    a1, a2 = 1, 0.8
                end
                acceptLabel:SetTextColor(r, g, b, a1)
                if PP.GetBorders(acceptBtn) then PP.SetBorderColor(acceptBtn, r, g, b, a2) end
            end)
            acceptBtn:SetScript("OnLeave", function()
                local r, g, b, a1, a2 = 1, 1, 1, 0.5, 0.4
                if GetFFD(acceptBtn).accent then
                    r, g, b = EG.r, EG.g, EG.b
                    a1, a2 = 0.7, 0.5
                end
                acceptLabel:SetTextColor(r, g, b, a1)
                if PP.GetBorders(acceptBtn) then PP.SetBorderColor(acceptBtn, r, g, b, a2) end
            end)
            acceptBtn:SetScript("OnClick", function()
                local invID = GetFFD(btn).inviteID
                if invID and BNAcceptFriendInvite then BNAcceptFriendInvite(invID) end
            end)
            GetFFD(btn).acceptBtn = acceptBtn
        end

        -- Anchor tile/faction with per-element gaps (first gets top gap, last gets smaller bottom gap)
        local tGap = elementData._isFirst and -1 or 0
        local bGap = elementData._isLast and 1 or 2
        GetFFD(btn).tileBg:ClearAllPoints()
        GetFFD(btn).tileBg:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, tGap)
        GetFFD(btn).tileBg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, bGap)
        GetFFD(btn).factionBg:ClearAllPoints()
        GetFFD(btn).factionBg:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, tGap)
        GetFFD(btn).factionBg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, bGap)

        -- Apply accent state from current settings
        local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
        local useAccent = fp and fp.accentColors ~= false
        local acceptBtn = GetFFD(btn).acceptBtn
        local acceptLabel = GetFFD(btn).acceptLabel
        if acceptBtn then
            GetFFD(acceptBtn).accent = useAccent
            if useAccent then
                if acceptLabel then acceptLabel:SetTextColor(EG.r, EG.g, EG.b, 0.7) end
                if PP.GetBorders(acceptBtn) then PP.SetBorderColor(acceptBtn, EG.r, EG.g, EG.b, 0.5) end
            else
                if acceptLabel then acceptLabel:SetTextColor(1, 1, 1, 0.5) end
                if PP.GetBorders(acceptBtn) then PP.SetBorderColor(acceptBtn, 1, 1, 1, 0.4) end
            end
        end

        -- Populate data (reapply colors every init in case rebuild recycled the frame)
        GetFFD(btn).inviteID = elementData._inviteID
        GetFFD(btn).name:SetText(elementData._accountName or "")
        GetFFD(btn).name:SetTextColor(0.51, 0.784, 1, 1)
        GetFFD(btn).subText:SetText(PENDING_INVITE or "Pending")
        GetFFD(btn).subText:SetTextColor(0.5, 0.5, 0.5, 0.8)
        GetFFD(btn).tileBg:SetColorTexture(0.05, 0.15, 0.20, 0.30)
    end

    -- Our own ScrollBox + ScrollBar (parented to UIParent) to avoid tainting
    -- Blizzard's FriendsListFrame.ScrollBox. ScrollUtil.Init + SetDataProvider
    -- on our frames don't propagate taint to RaidFrame:Show().
    local _ebsOurScrollBox, _ebsOurScrollBar
    do
        local ourSB = CreateFrame("Frame", nil, UIParent, "WowScrollBoxList")
        local ourBar = CreateFrame("EventFrame", nil, UIParent, "MinimalScrollBar")
        ourSB:SetFrameStrata("HIGH")
        ourSB:SetFrameLevel(1)
        ourSB:Hide()
        ourBar:SetFrameStrata("HIGH")
        ourBar:SetFrameLevel(2)
        ourBar:Hide()

        local ourBg = ourSB:CreateTexture(nil, "BACKGROUND")
        ourBg:SetAllPoints()
        ourBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)

        ourSB:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -92)
        ourSB:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 35)
        ourBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -92)
        ourBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 35)

        local view = CreateScrollBoxListLinearView()
        view:SetElementExtentCalculator(function(dataIndex, elementData)
            if elementData.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then
                return 20
            elseif elementData.buttonType == EBS_BUTTON_TYPE_PENDING then
                local top = elementData._isFirst and 1 or 0
                local bot = elementData._isLast and 1 or 2
                return 36 + top + bot
            end
            return 34
        end)
        view:SetElementFactory(function(factory, elementData)
            if elementData.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then
                factory("Button", function(btn, ed)
                    btn:SetHeight(20)
                    btn.buttonType = FRIENDS_BUTTON_TYPE_DIVIDER
                    InitDividerButton(btn, ed)
                end)
            elseif elementData.buttonType == EBS_BUTTON_TYPE_PENDING then
                factory("Frame", function(btn, ed)
                    InitPendingButton(btn, ed)
                end)
            elseif elementData.buttonType == FRIENDS_BUTTON_TYPE_INVITE_HEADER then
                factory("FriendsPendingInviteHeaderButtonTemplate", FriendsFrame_UpdateFriendInviteHeaderButton)
            elseif elementData.buttonType == FRIENDS_BUTTON_TYPE_INVITE then
                factory("FriendsFrameFriendInviteTemplate", FriendsFrame_UpdateFriendInviteButton)
            else
                factory("FriendsListButtonTemplate", function(btn, ed)
                    FriendsFrame_UpdateFriendButton(btn, ed)
                    PostUpdateFriendButton(btn)
                end)
            end
        end)
        ScrollUtil.InitScrollBoxListWithScrollBar(ourSB, ourBar, view)
        SkinOneScrollbar(ourSB, ourBar)

        _ebsOurScrollBox = ourSB
        _ebsOurScrollBar = ourBar
        GetFFD(frame).ourScrollBox = ourSB
        GetFFD(frame).ourScrollBar = ourBar
    end

    -- Rebuild state
    local _ebsRebuilding = false
    local _ebsRebuildPending = false

    local _rebuildScheduled = false
    local _lastRebuildTime = 0
    local RebuildFriendsDataProviderImpl  -- forward decl
    local function RebuildFriendsDataProvider(source)
        if _ebsRebuilding then
            _ebsRebuildPending = true
            return
        end
        if not FriendsFrame or not FriendsFrame:IsShown() then return end
        if not EBS.db or not EBS.db.profile.friends.enabled then return end
        -- Direct user actions (collapse, initial show) run immediately.
        -- Event-driven rebuilds (Blizzard fires FriendsList_Update multiple
        -- times during the show sequence) are debounced with a short timer.
        if source == "direct" then
            if RebuildFriendsDataProviderImpl then
                RebuildFriendsDataProviderImpl()
            end
            return
        end
        if debugprofilestop() - _lastRebuildTime < 500 then return end
        if not _rebuildScheduled then
            _rebuildScheduled = true
            C_Timer.After(0.05, function()
                _rebuildScheduled = false
                if RebuildFriendsDataProviderImpl then
                    RebuildFriendsDataProviderImpl()
                end
            end)
        end
    end
    RebuildFriendsDataProviderImpl = function()
        if _ebsRebuilding then return end
        if not FriendsFrame:IsShown() then return end
        if not EBS.db or not EBS.db.profile.friends.enabled then return end
        local fp = EBS.db.profile.friends
        local sb = _ebsOurScrollBox
        if not sb then return end

        local EBS_FAVORITES = "Favorites"

        -- Read ALL friends directly from the API and populate the scroll cache.
        -- Cache is read during per-button hook so scrolling never calls the API.
        local friends = {}
        local fg = GetFriendGroupsGlobal()
        wipe(_friendCache)
        local numBNet = BNGetNumFriends and BNGetNumFriends() or 0
        for i = 1, numBNet do
            local info = C_BattleNet and C_BattleNet.GetFriendAccountInfo(i)
            if info then
                _friendCache[i] = info
                local isFavorite = info.isFavorite
                local noteGroup = ParseGroupFromNote(info.note)
                local group
                if isFavorite then
                    group = EBS_FAVORITES
                else
                    group = noteGroup
                end
                local btag = (info.battleTag or ""):lower()
                local sortName = btag:match("^(.-)#") or btag
                if sortName == "" then sortName = (info.accountName or ""):lower() end
                friends[#friends + 1] = {
                    buttonType = FRIENDS_BUTTON_TYPE_BNET,
                    id = i,
                    priority = GetBNetPriority(info),
                    name = sortName,
                    btag = btag,
                    group = group,
                }
            end
        end
        local numWoW = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
        for i = 1, numWoW do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.name then
                _friendCache[i + _FC_WOW_OFFSET] = info
                local wowGroup = ParseGroupFromNote(info.notes)
                friends[#friends + 1] = {
                    buttonType = FRIENDS_BUTTON_TYPE_WOW,
                    id = i,
                    priority = info.connected and 1 or 5,
                    name = info.name:lower(),
                    group = wowGroup,
                }
            end
        end

        -- Filter offline friends if toggle is off
        if fp.showOffline == false then
            local onlineOnly = {}
            for _, f in ipairs(friends) do
                if f.priority < 5 then  -- priority 5 = offline
                    onlineOnly[#onlineOnly + 1] = f
                end
            end
            friends = onlineOnly
        end

        -- Apply search filter
        if _ebsSearchTerm ~= "" then
            local filtered = {}
            for _, f in ipairs(friends) do
                if strfind(f.name, _ebsSearchTerm, 1, true)
                    or (f.btag and strfind(f.btag, _ebsSearchTerm, 1, true)) then
                    filtered[#filtered + 1] = f
                end
            end
            friends = filtered
        end

        if #friends == 0 then
            local sb2 = FriendsListFrame and FriendsListFrame.ScrollBox
            if sb2 then sb2:SetDataProvider(CreateDataProvider(), true) end
            _ebsRebuilding = false
            return
        end

        -- Sort: priority ascending, then name ascending
        table.sort(friends, function(a, b)
            if a.priority ~= b.priority then return a.priority < b.priority end
            return a.name < b.name
        end)


        -- Build ordered group list from saved order
        local validOrder = GetValidGroupOrder()
        local groupOrder = {}
        for _, key in ipairs(validOrder) do
            if key == ORDER_FAVORITES then
                groupOrder[#groupOrder + 1] = EBS_FAVORITES
            elseif key == ORDER_UNGROUPED then
                groupOrder[#groupOrder + 1] = false
            else
                groupOrder[#groupOrder + 1] = key
            end
        end

        -- Build a set of currently-valid group names so we can detect
        -- friends still pointing at deleted groups (e.g. user wiped their
        -- SavedVariables on another character / deleted a group manually).
        -- Without this, those friends bucket into a ghost key that no
        -- group renders -> they vanish from the list entirely.
        local validGroups = {}
        for _, g in ipairs(fg.friendGroups) do
            validGroups[g.name] = true
        end
        validGroups[EBS_FAVORITES] = true  -- favorites is a virtual group

        -- Bucket friends into groups; orphaned group references fall back
        -- to the default (no-group) bucket and the stale tag is cleared
        -- so the next save persists the recovery.
        local buckets = {}
        for _, f in ipairs(friends) do
            local key = f.group or false
            if key and not validGroups[key] then
                f.group = nil
                key = false
            end
            if not buckets[key] then buckets[key] = {} end
            buckets[key][#buckets[key] + 1] = f
        end

        -- Build new DataProvider (respect collapsed state)
        local newDP = CreateDataProvider()

        -- Pending friend invites (max 2, above all groups)
        local numInvites = BNGetNumFriendInvites and BNGetNumFriendInvites() or 0
        if numInvites > 0 then
            newDP:Insert({
                buttonType = FRIENDS_BUTTON_TYPE_DIVIDER,
                text = format(FRIEND_REQUESTS or "Friend Requests (%d)", numInvites),
                _groupKey = "_pending",
            })
            if not fg.friendPendingCollapsed then
                local maxShow = math.min(numInvites, 3)
                local inserted = 0
                for inv = 1, maxShow do
                    local inviteID, accountName = BNGetFriendInviteInfo(inv)
                    if inviteID then
                        inserted = inserted + 1
                        newDP:Insert({
                            buttonType = EBS_BUTTON_TYPE_PENDING,
                            _inviteID = inviteID,
                            _accountName = accountName or "",
                            _isFirst = (inserted == 1),
                            _isLast = (inv == maxShow),
                        })
                    end
                end
            end
        end

        -- Find which groups have members for first/last marking
        local activeGroups = {}
        for _, gName in ipairs(groupOrder) do
            if buckets[gName] and #buckets[gName] > 0 then
                activeGroups[#activeGroups + 1] = gName
            end
        end

        for gi, gName in ipairs(groupOrder) do
            local bucket = buckets[gName]
            if bucket and #bucket > 0 then
                local displayName = gName
                if gName == EBS_FAVORITES then
                    displayName = FAVORITES or "Favorites"
                elseif not gName then
                    displayName = FRIENDS or "Friends"
                end
                -- Determine if first/last active group
                local isFirstGroup = (activeGroups[1] == gName)
                local isLastGroup = (activeGroups[#activeGroups] == gName)
                newDP:Insert({
                    buttonType = FRIENDS_BUTTON_TYPE_DIVIDER,
                    text = displayName,
                    _groupKey = gName,
                    _isFirstGroup = isFirstGroup,
                    _isLastGroup = isLastGroup,
                })
                -- Check collapsed state
                local isCollapsed = false
                if gName == EBS_FAVORITES then
                    isCollapsed = fg.friendFavCollapsed
                elseif gName == false then
                    isCollapsed = fg.friendUngroupedCollapsed
                else
                    for _, g in ipairs(fg.friendGroups) do
                        if g.name == gName then isCollapsed = g.collapsed; break end
                    end
                end
                if not isCollapsed then
                    for _, f in ipairs(bucket) do
                        newDP:Insert({
                            buttonType = f.buttonType,
                            id = f.id,
                        })
                    end
                end
            end
        end

        -- Clear stamps so the hook re-applies styling with fresh data
        for _, btn in sb:EnumerateFrames() do
            GetFFD(btn).stampType = nil
        end
        _ebsRebuilding = true
        sb:SetDataProvider(newDP, true)  -- safe: sb is our own ScrollBox, not Blizzard's
        _ebsRebuilding = false
        _lastRebuildTime = debugprofilestop()

        -- Scroll to a specific friend after rebuild (e.g. after adding to group)
        if _G._EBS_ScrollToFriend then
            local targetKey = _G._EBS_ScrollToFriend
            _G._EBS_ScrollToFriend = nil
            C_Timer.After(0, function()
                local dp = sb:GetDataProvider()
                if not dp then return end
                local idx = 0
                for _, ed in dp:Enumerate() do
                    idx = idx + 1
                    if ed.buttonType and ed.buttonType ~= FRIENDS_BUTTON_TYPE_DIVIDER and ed.id then
                        local fk
                        if ed.buttonType == FRIENDS_BUTTON_TYPE_BNET then
                            local cached = _friendCache[ed.id]
                            if cached then fk = "bnet-" .. (cached.bnetAccountID or ed.id) end
                        elseif ed.buttonType == FRIENDS_BUTTON_TYPE_WOW then
                            local cached = _friendCache[ed.id + _FC_WOW_OFFSET]
                            if cached then fk = "wow-" .. (cached.name or "") end
                        end
                        if fk == targetKey then
                            sb:ScrollToElementDataIndex(idx)
                            -- Brief flash highlight on the target button (no taint)
                            local targetType, targetId = ed.buttonType, ed.id
                            C_Timer.After(0.05, function()
                                for _, btn in sb:EnumerateFrames() do
                                    if btn.buttonType == targetType and btn.id == targetId then
                                        if not GetFFD(btn).flashHL then
                                            GetFFD(btn).flashHL = btn:CreateTexture(nil, "ARTWORK", nil, -5)
                                            GetFFD(btn).flashHL:SetAllPoints()
                                            GetFFD(btn).flashHL:SetColorTexture(1, 1, 1, 0.12)
                                        end
                                        GetFFD(btn).flashHL:Show()
                                        C_Timer.After(1.5, function()
                                            if GetFFD(btn).flashHL then GetFFD(btn).flashHL:Hide() end
                                        end)
                                        break
                                    end
                                end
                            end)
                            break
                        end
                    end
                end
            end)
        end

    end

    -- Expose for menu callbacks
    _G._EBS_RebuildFriendsDP = function(source) RebuildFriendsDataProvider(source or "global") end

    -- Rebuild on the same events that drive FriendsList_Update, via our
    -- own event frame instead of hooksecurefunc("FriendsList_Update").
    -- The global hook tainted every Blizzard call site (BN whisper
    -- processing, HistoryKeeper token creation) because the wrapper
    -- injected addon code into secure execution paths.
    -- Sync our custom tab labels with Blizzard's tab text (replaces per-tab
    -- hooksecurefunc on SetText which tainted BNet whisper processing).
    local function SyncFriendsTabLabels()
        for i = 1, (FriendsFrame and FriendsFrame.numTabs) or 4 do
            local tab = _G["FriendsFrameTab" .. i]
            if tab then
                local tfd = GetFFD(tab)
                if tfd.label then
                    local bliz = tab:GetFontString()
                    local txt = bliz and bliz:GetText()
                    if txt then tfd.label:SetText(txt) end
                end
            end
        end
    end

    -- Only register friend events while FriendsFrame is shown. In Midnight,
    -- having addon code execute for BN_FRIEND_INFO_CHANGED (even an early
    -- return) taints the execution context for the entire event dispatch
    -- batch, breaking BNet whisper processing and HistoryKeeper.
    local friendsEventFrame = CreateFrame("Frame")
    friendsEventFrame:SetScript("OnEvent", function(_, event)
        RebuildFriendsDataProvider("event:" .. event)
        SyncFriendsTabLabels()
    end)
    local function RegisterFriendsEvents()
        friendsEventFrame:RegisterEvent("FRIENDLIST_UPDATE")
        friendsEventFrame:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
        friendsEventFrame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
        friendsEventFrame:RegisterEvent("BN_FRIEND_INVITE_ADDED")
        friendsEventFrame:RegisterEvent("BN_FRIEND_INVITE_REMOVED")
    end
    local function UnregisterFriendsEvents()
        friendsEventFrame:UnregisterAllEvents()
    end
    if FriendsFrame:IsShown() then RegisterFriendsEvents() end

    -- Auto-accept group invites from friends
    local _autoAcceptHideStatic = false
    local autoAcceptFrame = CreateFrame("Frame")
    autoAcceptFrame:RegisterEvent("PARTY_INVITE_REQUEST")
    autoAcceptFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    autoAcceptFrame:SetScript("OnEvent", function(_, event, _, _, _, _, _, _, inviterGUID)
        if event == "PARTY_INVITE_REQUEST" then
            local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
            if not fp or not fp.autoAcceptFriendInvites then return end
            if not inviterGUID or inviterGUID == "" or IsInGroup() then return end
            local isFriend = false
            if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
                isFriend = C_BattleNet.GetGameAccountInfoByGUID(inviterGUID) ~= nil
            end
            if not isFriend and C_FriendList and C_FriendList.IsFriend then
                isFriend = C_FriendList.IsFriend(inviterGUID)
            end
            if isFriend then
                AcceptGroup()
                _autoAcceptHideStatic = true
            end
        elseif event == "GROUP_ROSTER_UPDATE" and _autoAcceptHideStatic then
            _autoAcceptHideStatic = false
            StaticPopup_Hide("PARTY_INVITE")
            if LFGInvitePopup then
                StaticPopupSpecial_Hide(LFGInvitePopup)
            end
        end
    end)

    -- Save/restore scroll position across open/close
    local _ebsSavedScrollPct = 0
    local function _ebsOnShowDeferred()
        ProcessFriendButtons()
        if _ebsSavedScrollPct > 0 then
            local bar = FriendsListFrame.ScrollBar
            if bar and bar.SetScrollPercentage then
                bar:SetScrollPercentage(_ebsSavedScrollPct)
            end
        end
    end
    hooksecurefunc(frame, "Hide", function()
        UnregisterFriendsEvents()
        local bar = FriendsListFrame.ScrollBar
        if bar and bar.GetScrollPercentage then
            _ebsSavedScrollPct = bar:GetScrollPercentage() or 0
        end
    end)
    hooksecurefunc(frame, "Show", function()
        RegisterFriendsEvents()
        -- RebuildFriendsDataProvider is triggered by FriendsList_Update /
        -- FRIENDLIST_UPDATE events that fire on show. No need to call it
        -- here -- just defer the button styling + scroll restore.
        C_Timer.After(0, _ebsOnShowDeferred)
    end)

    -- Status events (BN_FRIEND_INFO_CHANGED, etc.) are handled by the
    -- friendsEventFrame above (only registered while FriendsFrame is shown).
    -- The rebuild re-renders buttons via our factory wrapper that calls
    -- PostUpdateFriendButton directly (no global hooksecurefunc needed).

    ---------------------------------------------------------------------------
    --  Skin Who / Raid / Quick Join tabs (simple reskins, Blizzard handles logic)
    ---------------------------------------------------------------------------

    -- Helper: strip a frame and its inset
    local function StripFrameChrome(f)
        if not f then return end
        StripTextures(f)
        if f.NineSlice then f.NineSlice:Hide() end
        if f.Bg then f.Bg:Hide() end
        if f.Inset then
            StripTextures(f.Inset)
            if f.Inset.NineSlice then f.Inset.NineSlice:Hide() end
            if f.Inset.Bg then f.Inset.Bg:Hide() end
        end
    end

    -- Who tab
    do
        local who = WhoFrame
        if who then
            StripFrameChrome(who)

            -- Reanchor Who frame to our list pane area
            who:ClearAllPoints()
            who:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, 0)
            who:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -11, 0)

            -- Custom backdrop on the list inset area
            local whoInset = _G.WhoFrameListInset
            if whoInset then
                StripTextures(whoInset)
                if whoInset.Bg then whoInset.Bg:Hide() end
                if whoInset.NineSlice then
                    StripTextures(whoInset.NineSlice)
                    whoInset.NineSlice:Hide()
                end
                whoInset:SetClipsChildren(true)
                -- Match friends list ScrollBox left/right alignment
                whoInset:ClearAllPoints()
                whoInset:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -92)
                whoInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 35)
                local whoBg = whoInset:CreateTexture(nil, "BACKGROUND", nil, -5)
                whoBg:SetAllPoints()
                whoBg:SetColorTexture(0, 0.08, 0.10, 0.35)
                PP.CreateBorder(whoInset, 1, 1, 1, 0.1, 1, "OVERLAY", 5)
            end

            -- 5px left padding + 10px up on all column headers via hooksecurefunc
            local col1 = _G["WhoFrameColumnHeader1"]
            for i = 1, 4 do
                local col = _G["WhoFrameColumnHeader" .. i]
                if col then
                    hooksecurefunc(col, "SetPoint", function(self)
                        if GetFFD(self).adjusting then return end
                        GetFFD(self).adjusting = true
                        local p1, rel, p2, x, y = self:GetPoint(1)
                        if p1 then
                            self:ClearAllPoints()
                            local xOff = (i == 1) and 5 or 0
                            self:SetPoint(p1, rel, p2, (x or 0) + xOff, (y or 0) + 10)
                        end
                        GetFFD(self).adjusting = false
                    end)
                end
            end

            -- Dark background behind the column header bar
            local whoInset2 = _G.WhoFrameListInset
            if col1 and whoInset2 then
                local headerBg = who:CreateTexture(nil, "BACKGROUND", nil, -6)
                headerBg:SetPoint("TOPLEFT", col1, "TOPLEFT", 0, 0)
                headerBg:SetPoint("RIGHT", whoInset2, "RIGHT", 0, 0)
                headerBg:SetHeight(col1:GetHeight())
                headerBg:SetColorTexture(0, 0, 0, 0.3)
            end

            -- Column headers with 1px dividers and hover highlight
            for i = 1, 4 do
                local col = _G["WhoFrameColumnHeader" .. i]
                if col then
                    StripTextures(col)
                    local text = col:GetFontString()
                    if text then
                        text:SetFont(fontPath, 10, "")
                        text:SetTextColor(1, 1, 1, 0.5)
                    end
                    -- Hover highlight (clipped within column bounds)
                    col:SetClipsChildren(true)
                    local hl = col:CreateTexture(nil, "HIGHLIGHT")
                    local nextCol = _G["WhoFrameColumnHeader" .. (i + 1)]
                    if nextCol then
                        hl:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
                        hl:SetPoint("BOTTOMRIGHT", nextCol, "BOTTOMLEFT", 0, 0)
                    else
                        -- Last column: anchor to the inset right edge
                        local whoInset3 = _G.WhoFrameListInset
                        if whoInset3 then
                            hl:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
                            hl:SetPoint("BOTTOM", col, "BOTTOM", 0, 0)
                            hl:SetPoint("RIGHT", whoInset3, "RIGHT", 0, 0)
                        else
                            hl:SetAllPoints()
                        end
                    end
                    hl:SetColorTexture(1, 1, 1, 0.1)
                    hl:SetBlendMode("ADD")
                    -- 1px divider on the left edge (skip first column)
                    if i > 1 then
                        local div = col:CreateTexture(nil, "OVERLAY", nil, 7)
                        PP.DisablePixelSnap(div)
                        div:SetWidth(PP.mult or 1)
                        div:SetColorTexture(1, 1, 1, 0.1)
                        div:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -2)
                        div:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", 0, 2)
                    end
                end
            end

            -- Replace Zone dropdown with plain "Zone" text on col2
            local zoneDropdown = _G.WhoFrameDropdown
            if zoneDropdown then
                zoneDropdown:SetAlpha(0)
                zoneDropdown:SetSize(1, 1)
                zoneDropdown:EnableMouse(false)
                zoneDropdown:ClearAllPoints()
                zoneDropdown:SetPoint("TOPLEFT", who, "TOPLEFT", 0, 0)
            end
            local col2 = _G["WhoFrameColumnHeader2"]
            if col2 then
                local zoneLabel = col2:CreateFontString(nil, "OVERLAY")
                zoneLabel:SetFont(fontPath, 10, "")
                zoneLabel:SetTextColor(1, 1, 1, 0.5)
                zoneLabel:SetPoint("LEFT", col2, "LEFT", 5, 0)
                zoneLabel:SetText("Zone")
                -- Wire click to sort by zone
                -- Wire col2 to sort by zone using col1's OnClick mixin method.
                -- Store sortType in FFD to avoid tainting the Blizzard frame.
                local col1ref = _G["WhoFrameColumnHeader1"]
                if col1ref and col1ref.OnClick then
                    GetFFD(col2).sortType = "zone"
                    col2:SetScript("OnClick", function(self)
                        self.sortType = GetFFD(self).sortType
                        col1ref.OnClick(self)
                        self.sortType = nil
                    end)
                end
            end

            -- Search box (custom background)
            local editBox = _G.WhoFrameEditBox
            if editBox then
                StripTextures(editBox)
                editBox:SetScale(0.9)
                local p1, rel, p2, ox, oy = editBox:GetPoint(1)
                if p1 then
                    editBox:SetPoint(p1, rel, p2, (ox or 0) - 1, (oy or 0) + 3)
                end
                local ebBg = editBox:CreateTexture(nil, "BACKGROUND", nil, -6)
                ebBg:SetColorTexture(0, 0, 0, 0.4)
                ebBg:SetAllPoints()
                editBox:SetTextColor(1, 1, 1, 0.8)
                PP.CreateBorder(editBox, 1, 1, 1, 0.1, 1, "OVERLAY", 7)
            end

            -- Total count
            local totalCount = _G.WhoFrameTotals
            if totalCount and totalCount.SetFont then
                totalCount:SetFont(fontPath, 10, "")
                totalCount:SetTextColor(1, 1, 1, 0.5)
            end

            -- Bottom buttons: equal thirds, flush with inset
            local whoInsetRef = _G.WhoFrameListInset
            local whoBtnNames = {"WhoFrameWhoButton", "WhoFrameAddFriendButton", "WhoFrameGroupInviteButton"}
            if whoInsetRef then
                local function LayoutWhoBtns()
                    local totalW = whoInsetRef:GetWidth()
                    local btnW = math.floor(totalW / 3)
                    local btnY = -22 - 10 + 10  -- match friends: -BTN_H - BTN_GAP + 10
                    local btns = {}
                    for _, name in ipairs(whoBtnNames) do
                        btns[#btns + 1] = _G[name]
                    end
                    if btns[1] then
                        btns[1]:ClearAllPoints()
                        btns[1]:SetSize(btnW, 22)
                        btns[1]:SetPoint("BOTTOMLEFT", whoInsetRef, "BOTTOMLEFT", 0, btnY)
                    end
                    if btns[2] then
                        btns[2]:ClearAllPoints()
                        btns[2]:SetSize(btnW, 22)
                        btns[2]:SetPoint("BOTTOMLEFT", whoInsetRef, "BOTTOMLEFT", btnW, btnY)
                    end
                    if btns[3] then
                        btns[3]:ClearAllPoints()
                        btns[3]:SetSize(btnW, 22)
                        btns[3]:SetPoint("BOTTOMRIGHT", whoInsetRef, "BOTTOMRIGHT", 0, btnY)
                    end
                end
                for _, name in ipairs(whoBtnNames) do
                    local btn = _G[name]
                    if btn then
                        SkinBottomButton(btn)
                        hooksecurefunc(btn, "Disable", function(self) self:SetAlpha(0.4) end)
                        hooksecurefunc(btn, "Enable", function(self) self:SetAlpha(1) end)
                        if not btn:IsEnabled() then btn:SetAlpha(0.4) end
                    end
                end
                LayoutWhoBtns()
                who:HookScript("OnShow", LayoutWhoBtns)
            end

            -- Skin who list rows
            local function SkinWhoRows()
                for i = 1, 22 do
                    local btn = _G["WhoFrameButton" .. i]
                    if btn and not GetFFD(btn).skinned then
                        GetFFD(btn).skinned = true
                        StripTextures(btn)
                        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
                        hover:SetAllPoints()
                        hover:SetColorTexture(1, 1, 1, 0.04)
                        hover:SetBlendMode("ADD")
                        for _, key in ipairs({"Name", "Level", "Class", "Variable"}) do
                            local txt = _G["WhoFrameButton" .. i .. key]
                            if txt and txt.SetFont then
                                txt:SetFont(fontPath, 11, "")
                            end
                        end
                    end
                end
            end
            SkinWhoRows()
            who:HookScript("OnShow", SkinWhoRows)

            -- Push the scroll list down 35px and add 5px left padding
            local sb = who.ScrollBox or (who.scrollFrame)
            if sb then
                local p1, rel, p2, x, y = sb:GetPoint(1)
                if p1 then
                    sb:SetPoint(p1, rel, p2, (x or 0) + 5, (y or 0) - 35)
                end
            end

            -- Reanchor Who background + top bar (10px gap above buttons)
            who:ClearAllPoints()
            who:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -10)
            who:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -11, 10)

            -- Reanchor column header 1 flush with list pane top (+10px shift)
            local col1 = _G["WhoFrameColumnHeader1"]
            if col1 then
                col1:ClearAllPoints()
                col1:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -102)
            end

            -- Skin scrollbar
            local bar = sb and (sb.ScrollBar or who.ScrollBar) or who.ScrollBar
            if sb and bar then SkinOneScrollbar(sb, bar) end
        end
    end

    -- Quick Join tab
    do
        local qjf = _G.QuickJoinFrame
        if qjf then
            -- Match scrollable area to friends list positioning
            local qjScroll = qjf.ScrollBox or (qjf.List and qjf.List.ScrollBox)
            if qjScroll then
                qjScroll:ClearAllPoints()
                qjScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -92)
                qjScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 35)

                -- 1px inset border (same as friends/who)
                if not GetFFD(qjScroll).borderAdded then
                    GetFFD(qjScroll).borderAdded = true
                    local bdr = CreateFrame("Frame", nil, qjf)
                    bdr:SetPoint("TOPLEFT", qjScroll, "TOPLEFT", 0, 0)
                    bdr:SetPoint("BOTTOMRIGHT", qjScroll, "BOTTOMRIGHT", 0, 0)
                    bdr:SetFrameLevel(qjScroll:GetFrameLevel() + 2)
                    PP.CreateBorder(bdr, 1, 1, 1, 0.1, 1, "OVERLAY", 7)
                end

                -- Custom scrollbar
                local qjBar = qjScroll.ScrollBar or (qjf.List and qjf.List.ScrollBar) or qjf.ScrollBar
                if qjBar then
                    SkinOneScrollbar(qjScroll, qjBar)
                end
            end

            -- Position JoinQueueButton to match rightmost button (same as friends layout)
            local joinBtn = qjf.JoinQueueButton
            if joinBtn and qjScroll then
                SkinBottomButton(joinBtn)
                joinBtn:ClearAllPoints()
                local totalW = qjScroll:GetWidth()
                local btnW = math.floor(totalW / 3)
                joinBtn:SetSize(btnW, 22)
                joinBtn:SetPoint("BOTTOMRIGHT", qjScroll, "BOTTOMRIGHT", 0, -22)
            end
        end
    end

    -- Friends list area: 1px border around our custom scrollable area
    local ourSB = GetFFD(frame).ourScrollBox
    if ourSB and not GetFFD(ourSB).borderAdded then
        GetFFD(ourSB).borderAdded = true
        local bdr = CreateFrame("Frame", nil, ourSB)
        bdr:SetAllPoints(ourSB)
        bdr:SetFrameLevel(ourSB:GetFrameLevel() + 2)
        PP.CreateBorder(bdr, 1, 1, 1, 0.1, 1, "OVERLAY", 7)
    end
    -- Shared inset: everything inside the frame uses this left/right padding
    local INSET = 3
    local BTN_H = 22
    local TAB_H = 26
    -- Skin and reposition Add Friend / Send Message buttons
    SkinKnownButtons()
    SkinRaidTab()
    local addBtn = _G.FriendsFrameAddFriendButton
    local msgBtn = _G.FriendsFrameSendMessageButton
    if addBtn and msgBtn then
        local BTN_GAP = 10
        local scrollBox = GetFFD(frame).ourScrollBox or frame
        local btnY = -BTN_H - BTN_GAP + 10

        local function LayoutFriendBtns()
            local totalW = frame:GetWidth() - 30
            local btnW = math.floor(totalW / 3)

            addBtn:ClearAllPoints()
            addBtn:SetSize(btnW, BTN_H)
            addBtn:SetPoint("BOTTOMLEFT", scrollBox or frame, "BOTTOMLEFT", 0, btnY)

            if GetFFD(frame).offlineBtn then
                GetFFD(frame).offlineBtn:ClearAllPoints()
                GetFFD(frame).offlineBtn:SetSize(totalW - btnW * 2, BTN_H)
                GetFFD(frame).offlineBtn:SetPoint("BOTTOMLEFT", scrollBox or frame, "BOTTOMLEFT", btnW, btnY)
            end

            msgBtn:ClearAllPoints()
            msgBtn:SetSize(btnW, BTN_H)
            msgBtn:SetPoint("BOTTOMRIGHT", scrollBox or frame, "BOTTOMRIGHT", 0, btnY)
        end

        -- Show/Hide Offline toggle button
        if not GetFFD(frame).offlineBtn then
            local offBtn = CreateFrame("Button", nil, frame)
            SkinBottomButton(offBtn)
            offBtn:SetSize(85, BTN_H)
            offBtn:SetPoint("BOTTOM", scrollBox or frame, "BOTTOM", 0, btnY)

            local offLabel = offBtn:CreateFontString(nil, "OVERLAY")
            local offFontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
            offLabel:SetFont(offFontPath, 9, "")
            offLabel:SetPoint("CENTER", 0, 0)
            offBtn:SetFontString(offLabel)
            offBtn:SetPushedTextOffset(2, -2)
            GetFFD(offBtn).label = offLabel

            local function UpdateOfflineLabel()
                local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
                local showOff = fp and fp.showOffline ~= false
                offLabel:SetText(showOff and (HIDE or "Hide") .. " Offline" or (SHOW or "Show") .. " Offline")
                offLabel:SetTextColor(1, 1, 1, 0.3)
            end
            UpdateOfflineLabel()

            offBtn:SetScript("OnClick", function()
                local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
                if not fp then return end
                fp.showOffline = not (fp.showOffline ~= false)
                UpdateOfflineLabel()
                if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
            end)

            -- Show Offline: 50% white, 75% on hover, no accent
            local offText = GetFFD(offBtn).label
            if offText then offText:SetTextColor(1, 1, 1, 0.3) end
            if PP.GetBorders(offBtn) then PP.SetBorderColor(offBtn, 1, 1, 1, 0.3) end
            offBtn:HookScript("OnEnter", function()
                if offText then offText:SetTextColor(1, 1, 1, 0.5) end
                if PP.GetBorders(offBtn) then PP.SetBorderColor(offBtn, 1, 1, 1, 0.5) end
            end)
            offBtn:HookScript("OnLeave", function()
                if offText then offText:SetTextColor(1, 1, 1, 0.3) end
                if PP.GetBorders(offBtn) then PP.SetBorderColor(offBtn, 1, 1, 1, 0.3) end
            end)

            GetFFD(frame).offlineBtn = offBtn
            GetFFD(frame).updateOfflineLabel = UpdateOfflineLabel
        end

        -- Add Friend: 50% white, 75% on hover, no accent
        local addText = addBtn:GetFontString()
        if addText then addText:SetTextColor(1, 1, 1, 0.3) end
        if PP.GetBorders(addBtn) then PP.SetBorderColor(addBtn, 1, 1, 1, 0.3) end
        addBtn:HookScript("OnEnter", function()
            if addText then addText:SetTextColor(1, 1, 1, 0.5) end
            if PP.GetBorders(addBtn) then PP.SetBorderColor(addBtn, 1, 1, 1, 0.5) end
        end)
        addBtn:HookScript("OnLeave", function()
            if addText then addText:SetTextColor(1, 1, 1, 0.3) end
            if PP.GetBorders(addBtn) then PP.SetBorderColor(addBtn, 1, 1, 1, 0.3) end
        end)

        LayoutFriendBtns()
        hooksecurefunc(frame, "Show", LayoutFriendBtns)
    end

    -- Position custom tabs below the frame
    local numCustomTabs = #customTabs
    if numCustomTabs > 0 then
        local m = PP.mult or 1
        local function pxSnap(x)
            if m == 1 then return x end
            return math.floor(x / m + 0.5) * m
        end
        local snappedTabH = pxSnap(TAB_H)
        local onePx = m
        local lastCT

        local TAB_WIDTHS = { 0.22, 0.22, 0.22, 0.34 }
        local frameW = frame:GetWidth() or 300
        for i, ct in ipairs(customTabs) do
            ct:ClearAllPoints()
            ct:SetHeight(snappedTabH)
            if i == 1 then
                ct:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
            else
                ct:SetPoint("TOPLEFT", customTabs[i - 1], "TOPRIGHT", 0, 0)
            end
            if i == numCustomTabs then
                ct:SetPoint("RIGHT", frame, "BOTTOMRIGHT", 0, 0)
            else
                ct:SetWidth(frameW * (TAB_WIDTHS[i] or 0.25))
            end

            -- 1px pixel-perfect divider between tabs
            if i > 1 then
                local ctd = GetFFD(ct)
                if not ctd.div then
                    ctd.div = ct:CreateTexture(nil, "OVERLAY", nil, 7)
                    PP.DisablePixelSnap(ctd.div)
                end
                ctd.div:SetColorTexture(1, 1, 1, 0.08)
                ctd.div:SetSize(onePx, snappedTabH)
                ctd.div:ClearAllPoints()
                ctd.div:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, 0)
            end
            lastCT = ct
        end

        -- Tab bar bg (parent to first custom tab so it extends below frame)
        if GetFFD(frame).tabBarBg and lastCT then
            GetFFD(frame).tabBarBg:SetParent(customTabs[1])
            GetFFD(frame).tabBarBg:ClearAllPoints()
            GetFFD(frame).tabBarBg:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
            GetFFD(frame).tabBarBg:SetPoint("BOTTOMRIGHT", lastCT, "BOTTOMRIGHT", 0, 0)
            GetFFD(frame).tabBarBg:SetDrawLayer("BACKGROUND", -8)
        end

        -- 1px top border
        if not GetFFD(frame).tabTopBorder then
            GetFFD(frame).tabTopBorder = customTabs[1]:CreateTexture(nil, "OVERLAY", nil, 7)
            PP.DisablePixelSnap(GetFFD(frame).tabTopBorder)
            GetFFD(frame).tabTopBorder:SetColorTexture(1, 1, 1, 0.08)
            GetFFD(frame).tabTopBorder:SetHeight(onePx)
            GetFFD(frame).tabTopBorder:ClearAllPoints()
            GetFFD(frame).tabTopBorder:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
            GetFFD(frame).tabTopBorder:SetPoint("TOPRIGHT", lastCT, "TOPRIGHT", 0, 0)
        end

        -- Initial state
        UpdateCustomTabs()
    end

    -- Skin close button
    local closeBtn = frame.CloseButton or _G.FriendsFrameCloseButton
    if closeBtn then
        StripTextures(closeBtn)
        GetFFD(closeBtn).x = closeBtn:CreateFontString(nil, "OVERLAY")
        GetFFD(closeBtn).x:SetFont(fontPath, 14, "")
        GetFFD(closeBtn).x:SetText("x")
        GetFFD(closeBtn).x:SetTextColor(1, 1, 1, 0.5)
        GetFFD(closeBtn).x:SetPoint("CENTER", -2, -3)
        closeBtn:HookScript("OnEnter", function()
            GetFFD(closeBtn).x:SetTextColor(1, 1, 1, 0.9)
        end)
        closeBtn:HookScript("OnLeave", function()
            GetFFD(closeBtn).x:SetTextColor(1, 1, 1, 0.5)
        end)
    end

    -- Initial underline update
    C_Timer.After(0, UpdateCustomTabs)
end

-- Live updates: colors, border, opacity
local function ApplyFriends()
    local _mplus = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
    local _, _iT = IsInInstance()
    local _pvp = (_iT == "pvp" or _iT == "arena")
    if InCombatLockdown() or _mplus or _pvp then QueueApplyAll(); return end

    local p = EBS.db.profile.friends
    p.enabled = true

    if not p.enabled then
        -- Module requires reload to fully disable (same as minimap)
        return
    end

    if not FriendsFrame then return end
    SkinFriendsFrame()

    -- Update border size and colors
    local r, g, b, a = GetBorderColor(p)
    local bs = p.borderSize or 1
    if bs > 0 then
        PP.UpdateBorder(FriendsFrame, bs, r, g, b, a)
    else
        PP.SetBorderColor(FriendsFrame, r, g, b, 0)
    end
    if GetFFD(FriendsFrame).bg then
        GetFFD(FriendsFrame).bg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
        GetFFD(FriendsFrame).bg:SetAlpha(1)
    end
    if GetFFD(FriendsFrame).tabBarBg then
        GetFFD(FriendsFrame).tabBarBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
        GetFFD(FriendsFrame).tabBarBg:SetAlpha(1)
    end
    -- Update tile backgrounds on visible buttons (friends + recent allies)
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if scrollBox then
        for _, button in scrollBox:EnumerateFrames() do
            if GetFFD(button).tileBg then
                GetFFD(button).tileBg:SetColorTexture(0, 0, 0, 0.10)
            end
        end
    end
    local rafSB = _G.RecentAlliesFrame and _G.RecentAlliesFrame.List and _G.RecentAlliesFrame.List.ScrollBox
    if rafSB and rafSB.ScrollTarget then
        for i = 1, select("#", rafSB.ScrollTarget:GetChildren()) do
            local button = select(i, rafSB.ScrollTarget:GetChildren())
            if GetFFD(button).tileBg then
                GetFFD(button).tileBg:SetColorTexture(0, 0, 0, 0.10)
            end
        end
    end

    -- Apply accent colors to bottom buttons, raid tab buttons, tab underline, and sub-tab active text
    UpdateBottomButtonAccent()
    UpdateRaidTabButtonAccent()
    if GetFFD(FriendsFrame).updateCustomTabs then GetFFD(FriendsFrame).updateCustomTabs() end
    if GetFFD(FriendsFrame).updateSubTabs then GetFFD(FriendsFrame).updateSubTabs() end

    -- Apply scale and saved position
    if GetFFD(FriendsFrame).applyScaleAndPosition then
        GetFFD(FriendsFrame).applyScaleAndPosition()
    end
end

-------------------------------------------------------------------------------
--  Visibility (registered with the shared EllesmereUI visibility dispatcher)
-------------------------------------------------------------------------------
local function UpdateFriendsVisibility()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if not p or not p.enabled then return end
    if not FriendsFrame or not FriendsFrame:IsShown() then return end
    local vis = EllesmereUI.EvalVisibility(p)
    if vis == "mouseover" then
        FriendsFrame:SetAlpha(0)
    else
        FriendsFrame:SetAlpha(vis and 1 or 0)
    end
end

-------------------------------------------------------------------------------
--  Apply All
-------------------------------------------------------------------------------
ApplyAll = function()
    ApplyFriends()
    if EllesmereUI.RequestVisibilityUpdate then
        C_Timer.After(0, EllesmereUI.RequestVisibilityUpdate)
    end
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
function EBS:OnInitialize()
    EBS.db = EllesmereUI.Lite.NewDB("EllesmereUIFriendsDB", defaults)

    -- Global bridge for options <-> main communication
    _G._EFR_DB                   = EBS.db
    _G._EFR_ApplyFriends         = ApplyFriends
    _G._EFR_ProcessFriendButtons = ProcessFriendButtons

    -- Register visibility updater + mouseover target
    if EllesmereUI.RegisterVisibilityUpdater then
        EllesmereUI.RegisterVisibilityUpdater(UpdateFriendsVisibility)
    end
    if EllesmereUI.RegisterMouseoverTarget then
        -- FriendsFrame is load-on-demand; register a target that reads it
        -- at poll time rather than now.
        local proxy = CreateFrame("Frame")
        proxy.IsShown    = function() return FriendsFrame and FriendsFrame:IsShown() end
        proxy.IsMouseOver = function() return FriendsFrame and FriendsFrame:IsMouseOver() end
        proxy.SetAlpha   = function(_, a) if FriendsFrame then FriendsFrame:SetAlpha(a) end end
        EllesmereUI.RegisterMouseoverTarget(proxy, function()
            local p = EBS.db and EBS.db.profile and EBS.db.profile.friends
            return p and p.enabled and p.visibility == "mouseover"
        end)
    end
end

function EBS:OnEnable()
    ApplyAll()

    -- Re-apply after PLAYER_ENTERING_WORLD so accent colors from the theme
    -- system (which updates ELLESMERE_GREEN at PLAYER_LOGIN) are picked up.
    local loginRefresh = CreateFrame("Frame")
    loginRefresh:RegisterEvent("PLAYER_ENTERING_WORLD")
    loginRefresh:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(0, ApplyAll)
        -- One-time popup for users whose friend group assignments were wiped
        if EllesmereUIDB and EllesmereUIDB.global and EllesmereUIDB.global._friendGroupReassignPopup then
            EllesmereUIDB.global._friendGroupReassignPopup = nil
            C_Timer.After(2, function()
                if EllesmereUI and EllesmereUI.ShowConfirmPopup then
                    EllesmereUI:ShowConfirmPopup({
                        title = "Friend Groups Updated",
                        message = "EllesmereUI Update for \"Friend Group\" assignments: Friends must be re-assigned to your groups. Blizzard changes internal bnet ids which made tracking friends this way unstable, a new tracking system is now in place so this won't happen again!",
                        confirmText = "OK",
                    })
                end
            end)
        end
    end)

    -- Hook FriendsFrame for load-on-demand
    if EBS.db.profile.friends.enabled then
        if not FriendsFrame then
            local hookFrame = CreateFrame("Frame")
            hookFrame:RegisterEvent("ADDON_LOADED")
            hookFrame:SetScript("OnEvent", function(self, event, addon)
                if addon == "Blizzard_SocialUI" then
                    C_Timer.After(0.1, function()
                        if FriendsFrame and EBS.db.profile.friends.enabled then
                            ApplyFriends()
                        end
                    end)
                    if FriendsFrame then
                        hooksecurefunc(FriendsFrame, "Show", function()
                            if not friendsSkinned and EBS.db.profile.friends.enabled then
                                C_Timer.After(0, ApplyFriends)
                            end
                        end)
                    end
                end
            end)
        else
            if EBS.db.profile.friends.enabled then
                SkinFriendsFrame()
            end
        end
    end
end

-- Secure proxy for HouseList VisitHouse button.
-- Our ScrollBox creates FriendsListButtonTemplate buttons from addon context,
-- so right-click menus open tainted. This taints HouseList's VisitHouse() call.
-- Fix: overlay a SecureActionButtonTemplate on the Visit House button when
-- the user hovers it. The secure button executes VisitHouse without taint.
do
    local _proxyBtn
    local _hookedButtons = {}

    local function CreateHouseProxy()
        if _proxyBtn then return _proxyBtn end
        if InCombatLockdown() then return nil end

        local proxy = CreateFrame("Button", "EBS_SecureHouseProxy", UIParent, "SecureActionButtonTemplate")
        proxy:SetFrameStrata("DIALOG")
        proxy:SetFrameLevel(9999)
        proxy:Hide()
        proxy:RegisterForClicks("AnyUp", "AnyDown")
        proxy:SetAttribute("type", "visithouse")

        proxy:SetScript("OnEnter", function(self)
            if self._nativeBtn then self._nativeBtn:LockHighlight() end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(HOUSING_VISIT_HOUSE or "Visit House", 1, 1, 1)
            GameTooltip:Show()
        end)

        proxy:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            self:Hide()
            self:ClearAllPoints()
            if self._nativeBtn then self._nativeBtn:UnlockHighlight() end
            self._nativeBtn = nil
        end)

        proxy:SetScript("OnMouseDown", function(self)
            if self._nativeBtn then self._nativeBtn:SetButtonState("PUSHED") end
        end)

        proxy:SetScript("OnMouseUp", function(self)
            if self._nativeBtn then self._nativeBtn:SetButtonState("NORMAL") end
        end)

        _proxyBtn = proxy
        return proxy
    end

    local function OnVisitHouseEnter(nativeBtn)
        if InCombatLockdown() then return end
        local row = nativeBtn:GetParent()
        local houseInfo = row and row.houseInfo
        if not houseInfo or not houseInfo.neighborhoodGUID or not houseInfo.houseGUID then return end

        local proxy = CreateHouseProxy()
        if not proxy then return end

        proxy:ClearAllPoints()
        proxy:SetAllPoints(nativeBtn)
        proxy:SetAttribute("house-neighborhood-guid", houseInfo.neighborhoodGUID)
        proxy:SetAttribute("house-guid", houseInfo.houseGUID)
        proxy:SetAttribute("house-plot-id", houseInfo.plotID)
        proxy._nativeBtn = nativeBtn
        proxy:Show()
        if proxy:GetScript("OnEnter") then
            proxy:GetScript("OnEnter")(proxy)
        end
    end

    local function InitHousingScrollBox()
        local houseFrame = _G.HouseListFrame
        if not houseFrame or not houseFrame.ScrollBox then return end
        houseFrame.ScrollBox:RegisterCallback("OnInitializedFrame", function(_, frame)
            local btn = frame.VisitHouseButton
            if btn and not _hookedButtons[btn] then
                btn:HookScript("OnEnter", OnVisitHouseEnter)
                _hookedButtons[btn] = true
            end
        end)
    end

    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("ADDON_LOADED")
    initFrame:SetScript("OnEvent", function(_, _, addonName)
        if addonName == "Blizzard_HouseList" then
            InitHousingScrollBox()
        end
    end)
    if C_AddOns.IsAddOnLoaded("Blizzard_HouseList") then
        InitHousingScrollBox()
    end
end
