-------------------------------------------------------------------------------
--  EllesmereUIDamageMeters.lua
--  Reskins Blizzard's built-in damage meter to match EllesmereUI.
-------------------------------------------------------------------------------
local _, ns = ...
local EUI = EllesmereUI

local DM_DEFAULTS = {
    global = {},
    profile = {
        dm = {
            visibility = "always",
        },
    },
}

local _dmDB
local _hiddenParent

local function EnsureDB()
    if _dmDB then return _dmDB end
    if not EUI or not EUI.Lite then return nil end
    _dmDB = EUI.Lite.NewDB("EllesmereUIDamageMetersDB", DM_DEFAULTS)
    _G._EDM_DB = _dmDB
    return _dmDB
end

ns.EDM = {}
ns.EDM.DB = function()
    local d = _G._EDM_DB
    if d and d.profile and d.profile.dm then return d.profile.dm end
    return {}
end

-- Hidden parent for reparenting Blizzard elements we want invisible
_hiddenParent = CreateFrame("Frame")
_hiddenParent:Hide()
ns._hiddenParent = _hiddenParent

-------------------------------------------------------------------------------
--  1. Enable CVar + force Edit Mode settings on login
-------------------------------------------------------------------------------
local function SetCVarSafe(name, value)
    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar(name, value)
    elseif SetCVar then
        SetCVar(name, value)
    end
end

-------------------------------------------------------------------------------
--  Force Edit Mode Damage Meter settings (one-shot, same pattern as CDM)
--  Ensures "Show Class Color" and "Show Spec Icon" are enabled.
-------------------------------------------------------------------------------
local _editModePolicyApplied = false
local function EnforceDamageMeterEditModeSettings()
    if _editModePolicyApplied then return end
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts
            and Enum and Enum.EditModeSystem and Enum.EditModeSystem.DamageMeter
            and Enum.EditModeDamageMeterSetting) then
        return
    end

    local layoutInfo = C_EditMode.GetLayouts()
    if type(layoutInfo) ~= "table" or type(layoutInfo.layouts) ~= "table" then return end

    -- Merge preset layouts so activeLayout index resolves correctly
    if EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        local presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
        if type(presets) == "table" then
            tAppendAll(presets, layoutInfo.layouts)
            layoutInfo.layouts = presets
        end
    end

    local activeLayout = type(layoutInfo.activeLayout) == "number"
        and layoutInfo.layouts[layoutInfo.activeLayout]
    if not activeLayout or type(activeLayout.systems) ~= "table" then return end

    local changed = false
    local dmSystem = Enum.EditModeSystem.DamageMeter
    local dmSettings = Enum.EditModeDamageMeterSetting

    local function UpsertSetting(settings, settingEnum, desiredValue)
        for _, s in ipairs(settings) do
            if s.setting == settingEnum then
                if s.value ~= desiredValue then
                    s.value = desiredValue
                    return true
                end
                return false
            end
        end
        settings[#settings + 1] = { setting = settingEnum, value = desiredValue }
        return true
    end

    for _, sysInfo in ipairs(activeLayout.systems) do
        if sysInfo.system == dmSystem and type(sysInfo.settings) == "table" then
            -- Force Show Class Color = 1
            if dmSettings.ShowClassColor and UpsertSetting(sysInfo.settings, dmSettings.ShowClassColor, 1) then
                changed = true
            end
            -- Force Show Spec Icon = 1
            if dmSettings.ShowSpecIcon and UpsertSetting(sysInfo.settings, dmSettings.ShowSpecIcon, 1) then
                changed = true
            end
        end
    end

    _editModePolicyApplied = true
    if not changed then return end

    C_EditMode.SaveLayouts(layoutInfo)

    -- Show a forced reload popup (same pattern as CDM)
    C_Timer.After(0, function()
        if not EUI or not EUI.ShowConfirmPopup then
            ReloadUI()
            return
        end
        EUI:ShowConfirmPopup({
            title = "Edit Mode Update",
            message = "EllesmereUI has updated your Damage Meter Edit Mode settings to ensure class colors and spec icons display correctly.\n\nA UI reload is required for the changes to take effect.",
            confirmText = "Reload UI",
            onConfirm = function() ReloadUI() end,
        })
        local popup = _G["EUIConfirmPopup"]
        if popup then
            if popup._cancelBtn then popup._cancelBtn:Hide() end
            if popup._confirmBtn then
                popup._confirmBtn:ClearAllPoints()
                popup._confirmBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 13)
            end
            popup:SetScript("OnKeyDown", function(self, key)
                self:SetPropagateKeyboardInput(key ~= "ESCAPE")
            end)
            if popup._dimmer then
                popup._dimmer:SetScript("OnMouseDown", nil)
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  2. Edit Mode overlay suppression + Unlock Mode registration
--     Same approach as Chat: reparent Edit Mode controls to hidden container,
--     then register with EUI's unlock system for positioning/resizing.
-------------------------------------------------------------------------------
local _dmContainer
local _ignoreSetPoint = false

local function ApplyDMPosition()
    local cfg = ns.EDM.DB()
    if not cfg or not cfg.dmPosition then return end
    local pos = cfg.dmPosition
    if not pos.point or not pos.x or not pos.y then return end
    local dmFrame = _G.DamageMeter
    if not dmFrame then return end
    _ignoreSetPoint = true
    dmFrame:ClearAllPoints()
    dmFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    _ignoreSetPoint = false
end
ns.ApplyDMPosition = ApplyDMPosition

local function ApplyDMSize()
    local cfg = ns.EDM.DB()
    if not cfg then return end
    local dmFrame = _G.DamageMeter
    if not dmFrame then return end
    if cfg.dmWidth then dmFrame:SetWidth(math.max(150, cfg.dmWidth)) end
    if cfg.dmHeight then dmFrame:SetHeight(math.max(80, cfg.dmHeight)) end
end
ns.ApplyDMSize = ApplyDMSize

local function SetupDamageMeter()
    local dmFrame = _G.DamageMeter
    if not dmFrame then return end

    -- Create a container to own the damage meter frame (same as Chat)
    _dmContainer = CreateFrame("Frame", nil, UIParent)
    _dmContainer:SetAllPoints(UIParent)
    _dmContainer:EnableMouse(false)
    dmFrame:SetParent(_dmContainer)

    -- Reparent Edit Mode overlay elements to hidden container
    if dmFrame.Selection then dmFrame.Selection:SetParent(_hiddenParent) end
    if dmFrame.EditModeResizeButton then dmFrame.EditModeResizeButton:SetParent(_hiddenParent) end

    -- Prevent Blizzard/EditMode from overriding our position
    local _ignoreReparent = false
    hooksecurefunc(dmFrame, "SetParent", function(self, parent)
        if _ignoreReparent then return end
        if parent ~= _dmContainer then
            _ignoreReparent = true
            self:SetParent(_dmContainer)
            _ignoreReparent = false
        end
    end)

    -- Position enforcement hook (same pattern as Chat)
    hooksecurefunc(dmFrame, "SetPoint", function()
        if _ignoreSetPoint then return end
        if EUI._unlockActive then return end
        ApplyDMPosition()
    end)

    dmFrame:SetClampedToScreen(true)

    -- Defer size application to avoid combat taint
    local sizeFrame = CreateFrame("Frame")
    sizeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    sizeFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        ApplyDMSize()
        ApplyDMPosition()
    end)

    -- Register with EUI Unlock Mode
    if EUI.RegisterUnlockElements then
        local MK = EUI.MakeUnlockElement
        EUI:RegisterUnlockElements({
            MK({
                key   = "EDM_DamageMeter",
                label = "Damage Meters",
                group = "Damage Meters",
                order = 650,
                noAnchorTo = true,
                getFrame = function() return _G.DamageMeter end,
                getSize  = function()
                    local cfg = ns.EDM.DB()
                    if cfg then
                        return cfg.dmWidth or 300, cfg.dmHeight or 200
                    end
                    return 300, 200
                end,
                setWidth = function(_, newW)
                    if InCombatLockdown() then return end
                    local f = _G.DamageMeter
                    if not f then return end
                    local PPd = EllesmereUI and EllesmereUI.PP
                    local snapW = PPd and PPd.Snap(math.max(150, newW)) or math.floor(math.max(150, newW) + 0.5)
                    f:SetWidth(snapW)
                    if EllesmereUI._unlockActive then
                        local cfg = ns.EDM.DB()
                        if cfg then cfg.dmWidth = snapW end
                    end
                end,
                setHeight = function(_, newH)
                    if InCombatLockdown() then return end
                    local f = _G.DamageMeter
                    if not f then return end
                    local PPd = EllesmereUI and EllesmereUI.PP
                    local snapH = PPd and PPd.Snap(math.max(80, newH)) or math.floor(math.max(80, newH) + 0.5)
                    f:SetHeight(snapH)
                    if EllesmereUI._unlockActive then
                        local cfg = ns.EDM.DB()
                        if cfg then cfg.dmHeight = snapH end
                    end
                end,
                isHidden = function()
                    local cfg = ns.EDM.DB()
                    return cfg.visibility == "never"
                end,
                savePos = function(_, point, relPoint, x, y)
                    local cfg = ns.EDM.DB()
                    if not cfg then return end
                    cfg.dmPosition = { point = point, relPoint = relPoint or point, x = x, y = y }
                    if not EUI._unlockActive then
                        ApplyDMPosition()
                    end
                end,
                loadPos = function()
                    local cfg = ns.EDM.DB()
                    if not cfg then return nil end
                    return cfg.dmPosition
                end,
                clearPos = function()
                    local cfg = ns.EDM.DB()
                    if not cfg then return end
                    cfg.dmPosition = nil
                end,
                applyPos = function()
                    ApplyDMPosition()
                end,
            }),
        })
    end
end

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Do nothing if the module is disabled / coming soon
    if EUI and EUI.ADDON_ROSTER then
        for _, info in ipairs(EUI.ADDON_ROSTER) do
            if info.folder == "EllesmereUIDamageMeters" and info.comingSoon then
                return
            end
        end
    end

    EnsureDB()

    -- Enable the Blizzard damage meter CVar
    SetCVarSafe("damageMeterEnabled", 1)

    -- Force edit mode settings (class colors + spec icons)
    EnforceDamageMeterEditModeSettings()

    -- Setup frame hooks once the damage meter frame exists
    if _G.DamageMeter then
        SetupDamageMeter()
    else
        -- Frame may load late; poll briefly
        local waitFrame = CreateFrame("Frame")
        local elapsed = 0
        waitFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if _G.DamageMeter then
                self:SetScript("OnUpdate", nil)
                SetupDamageMeter()
            elseif elapsed > 10 then
                self:SetScript("OnUpdate", nil)
            end
        end)
    end
end)
