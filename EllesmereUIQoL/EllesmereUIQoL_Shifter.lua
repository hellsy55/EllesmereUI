-------------------------------------------------------------------------------
--  EllesmereUIQoL_Shifter.lua
--  Shift+drag to permanently reposition Blizzard panels.
--  Ctrl+drag for a temporary move that resets when the panel closes.
-------------------------------------------------------------------------------
local GetFFD = EllesmereUI._GetFFD

-- Temporary positions (per-frame, cleared on hide, not persisted)
local tempPos = {}

-- Frames that loaded during combat and need SetMovable/SetClampedToScreen deferred
local deferredMovable = {}

-- Forward-declare; created in the event-driven initialization section below
local eventFrame

-------------------------------------------------------------------------------
--  Frame registry
-------------------------------------------------------------------------------
local PRELOADED = {
    "CharacterFrame",
    "FriendsFrame",
    "PVEFrame",
    "DressUpFrame",
    "BankFrame",
    "MailFrame",
    "GossipFrame",
    "MerchantFrame",
    "AddonList",
    "BonusRollFrame",
    "ChatConfigFrame",
    "ItemTextFrame",
    "LFGDungeonReadyDialog",
    "GuildInviteFrame",
    "TabardFrame",
    "GuildRegistrarFrame",
}

local ADDON_FRAMES = {
    ["Blizzard_AchievementUI"]                     = { "AchievementFrame" },
    ["Blizzard_AlliedRacesUI"]                     = { "AlliedRacesFrame" },
    ["Blizzard_ArchaeologyUI"]                     = { "ArchaeologyFrame" },
    ["Blizzard_ArtifactUI"]                        = { "ArtifactFrame" },
    ["Blizzard_AuctionHouseUI"]                    = { "AuctionHouseFrame" },
    ["Blizzard_BlackMarketUI"]                     = { "BlackMarketFrame" },
    ["Blizzard_Calendar"]                          = { "CalendarFrame", "CalendarViewEventFrame" },
    ["Blizzard_ChallengesUI"]                      = { "ChallengesKeystoneFrame" },
    ["Blizzard_ChromieTimeUI"]                     = { "ChromieTimeFrame" },
    ["Blizzard_ClassTalentUI"]                     = { "ClassTalentFrame" },
    ["Blizzard_Collections"]                       = { "CollectionsJournal", "WardrobeFrame" },
    ["Blizzard_Communities"]                       = { "CommunitiesFrame" },
    ["Blizzard_CooldownViewer"]                    = { "CooldownViewerSettings" },
    ["Blizzard_EncounterJournal"]                  = { "EncounterJournal" },
    ["Blizzard_ExpansionLandingPage"]              = { "ExpansionLandingPage" },
    ["Blizzard_FlightMap"]                         = { "FlightMapFrame" },
    ["Blizzard_GenericTraitUI"]                    = { "GenericTraitFrame" },
    ["Blizzard_GuildBankUI"]                       = { "GuildBankFrame" },
    ["Blizzard_GuildControlUI"]                    = { "GuildControlUI" },
    ["Blizzard_InspectUI"]                         = { "InspectFrame" },
    ["Blizzard_ItemInteractionUI"]                 = { "ItemInteractionFrame" },
    ["Blizzard_ItemSocketingUI"]                   = { "ItemSocketingFrame" },
    ["Blizzard_ItemUpgradeUI"]                     = { "ItemUpgradeFrame" },
    ["Blizzard_MacroUI"]                           = { "MacroFrame" },
    ["Blizzard_MajorFactions"]                     = { "MajorFactionRenownFrame" },
    ["Blizzard_PlayerSpells"]                      = { "PlayerSpellsFrame" },
    ["Blizzard_Professions"]                       = { "ProfessionsFrame" },
    ["Blizzard_ProfessionsBook"]                   = { "ProfessionsBookFrame" },
    ["Blizzard_ProfessionsCustomerOrders"]         = { "ProfessionsCustomerOrdersFrame" },
    ["Blizzard_ScrappingMachineUI"]                = { "ScrappingMachineFrame" },
    ["Blizzard_StableUI"]                          = { "StableFrame" },
    ["Blizzard_TokenUI"]                           = { "CurrencyTransferMenu" },
    ["Blizzard_TrainerUI"]                         = { "ClassTrainerFrame" },
    ["Blizzard_TradeSkillUI"]                      = { "TradeSkillFrame" },
    ["Blizzard_Transmog"]                          = { "TransmogFrame" },
    ["Blizzard_WeeklyRewards"]                     = { "WeeklyRewardsFrame" },
    ["Blizzard_WorldMap"]                          = { "WorldMapFrame" },
    -- Midnight Housing
    ["Blizzard_HousingDashboard"]                  = { "HousingDashboardFrame" },
    ["Blizzard_HousingCornerstone"]                = { "HousingCornerstonePurchaseFrame" },
    ["Blizzard_HousingHouseFinder"]                = { "HouseFinderFrame" },
    ["Blizzard_HousingHouseSettings"]              = { "HousingHouseSettingsFrame" },
    ["Blizzard_HousingBulletinBoard"]              = { "HousingBulletinBoardFrame" },
    ["Blizzard_HousingModelPreview"]               = { "HousingModelPreviewFrame" },
    -- Delves
    ["Blizzard_DelvesCompanionConfigurationFrame"] = { "DelvesCompanionConfigurationFrame", "DelvesCompanionAbilityListFrame" },
    ["Blizzard_DelvesDifficultyPicker"]            = { "DelvesDifficultyPickerFrame" },
}

-- For these frames the drag target is a child header element, not the frame
-- itself (avoids fighting model-rotate or interior click regions).
local DRAG_HEADERS = {
    ["AchievementFrame"] = "AchievementFrameHeader",
    ["WorldMapFrame"]    = "WorldMapTitleButton",
}

-------------------------------------------------------------------------------
--  Position helpers
-------------------------------------------------------------------------------
local function IsEnabled()
    return EllesmereUIDB and EllesmereUIDB.shifterEnabled or false
end

local function GetSavedPos(name)
    local db = EllesmereUIDB
    return db and db.shifterPositions and db.shifterPositions[name]
end

local function SavePos(name, point, relPoint, x, y)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.shifterPositions then
        EllesmereUIDB.shifterPositions = {}
    end
    EllesmereUIDB.shifterPositions[name] = {
        point = point, relPoint = relPoint, x = x, y = y,
    }
    if EllesmereUI.RefreshPage then
        EllesmereUI:RefreshPage(true)
    end
end

-------------------------------------------------------------------------------
--  Secure repositioning (for PROTECTED frames)
--
--  A plain frame:SetPoint() / StartMoving() / SetMovable() called from insecure
--  addon code TAINTS the frame's execution. That is invisible on most panels,
--  but PVEFrame parents the LFGList applicant viewer, which does secret-value
--  comparisons in 12.0 -- a tainted tree throws "attempt to compare a secret
--  number" there. So protected frames are NEVER touched with those calls; we
--  run ClearAllPoints/SetPoint inside a SecureHandler restricted-environment
--  snippet instead, which executes securely and never taints the frame.
--  Parented to UIParent so self:GetParent() inside the snippet IS UIParent.
-------------------------------------------------------------------------------
local securePositioner = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
local function SecureSetPoint(frame, point, relPoint, x, y)
    if InCombatLockdown() then return false end
    securePositioner:SetFrameRef("f", frame)
    securePositioner:SetAttribute("p", point)
    securePositioner:SetAttribute("rp", relPoint)
    securePositioner:SetAttribute("x", x)
    securePositioner:SetAttribute("y", y)
    securePositioner:Execute([[
        local f = self:GetFrameRef("f")
        if not f then return end
        f:ClearAllPoints()
        f:SetPoint(self:GetAttribute("p"), self:GetParent(), self:GetAttribute("rp"), self:GetAttribute("x"), self:GetAttribute("y"))
    ]])
    return true
end

local function ApplyPosition(frame, name)
    if InCombatLockdown() and frame:IsProtected() then return end
    local pos = tempPos[frame] or GetSavedPos(name)
    if not pos or not pos.point then return end
    local ffd = GetFFD(frame)
    ffd._shIgnoreSP = true
    if frame:IsProtected() then
        SecureSetPoint(frame, pos.point, pos.relPoint, pos.x, pos.y)
    else
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end
    ffd._shIgnoreSP = false
end

-------------------------------------------------------------------------------
--  Cursor-delta drag (for PROTECTED frames)
--
--  We can't StartMoving a protected frame without tainting it, so for those we
--  track the cursor ourselves and reposition the frame live via SecureSetPoint
--  each update. Position is stored center-relative to UIParent (scale-clean).
--  Only one protected frame can be dragged at a time.
-------------------------------------------------------------------------------
local secureDrag = {}  -- { frame, name, mode, cursorX, cursorY, startX, startY, curX, curY }
local secureDragUpdater = CreateFrame("Frame")
secureDragUpdater:Hide()

local function StopSecureDrag()
    secureDragUpdater:Hide()
    local frame = secureDrag.frame
    if not frame then return end
    if secureDrag.curX then
        if secureDrag.mode == "save" then
            SavePos(secureDrag.name, "CENTER", "CENTER", secureDrag.curX, secureDrag.curY)
            tempPos[frame] = nil
        else
            tempPos[frame] = { point = "CENTER", relPoint = "CENTER", x = secureDrag.curX, y = secureDrag.curY }
        end
    end
    secureDrag.frame = nil
end

secureDragUpdater:SetScript("OnUpdate", function()
    local frame = secureDrag.frame
    if not frame then secureDragUpdater:Hide(); return end
    if InCombatLockdown() then StopSecureDrag(); return end
    local cx, cy = GetCursorPosition()
    local es = frame:GetEffectiveScale()
    local ues = UIParent:GetEffectiveScale()
    local ucx, ucy = UIParent:GetCenter()
    local newScreenX = secureDrag.startX + (cx - secureDrag.cursorX)
    local newScreenY = secureDrag.startY + (cy - secureDrag.cursorY)
    -- Keep the frame's center on screen (protected frames skip SetClampedToScreen).
    local sw, sh = GetScreenWidth() * ues, GetScreenHeight() * ues
    if newScreenX < 0 then newScreenX = 0 elseif newScreenX > sw then newScreenX = sw end
    if newScreenY < 0 then newScreenY = 0 elseif newScreenY > sh then newScreenY = sh end
    local x = (newScreenX - ucx * ues) / es
    local y = (newScreenY - ucy * ues) / es
    secureDrag.curX, secureDrag.curY = x, y
    local ffd = GetFFD(frame)
    ffd._shIgnoreSP = true
    SecureSetPoint(frame, "CENTER", "CENTER", x, y)
    ffd._shIgnoreSP = false
end)

local function StartSecureDrag(frame, name, mode)
    local fcx, fcy = frame:GetCenter()
    if not fcx then return end
    local es = frame:GetEffectiveScale()
    secureDrag.frame = frame
    secureDrag.name = name
    secureDrag.mode = mode
    secureDrag.cursorX, secureDrag.cursorY = GetCursorPosition()
    secureDrag.startX, secureDrag.startY = fcx * es, fcy * es
    secureDrag.curX, secureDrag.curY = nil, nil
    secureDragUpdater:Show()
end

-------------------------------------------------------------------------------
--  Hook a single frame
-------------------------------------------------------------------------------
local function HookFrame(frame, name)
    local ffd = GetFFD(frame)
    if ffd._shHooked then return end
    ffd._shHooked = true

    -- Non-protected frames use the cheap native StartMoving path. Protected
    -- frames are NEVER made movable / SetMovable'd / StartMoving'd / SetPoint'd
    -- by insecure code (it taints them); they drag via the secure cursor-delta
    -- path above. SetMovable is only needed for StartMoving, so protected frames
    -- skip it entirely.
    if not frame:IsProtected() then
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
    end

    -- Determine drag target (header child or the frame itself)
    local headerName = DRAG_HEADERS[name]
    local dragTarget = (headerName and _G[headerName]) or frame

    local dragging  -- non-protected only: "save" | "temp" | nil

    dragTarget:HookScript("OnMouseDown", function(_, button)
        if not IsEnabled() then return end
        if button ~= "LeftButton" then return end
        if InCombatLockdown() and frame:IsProtected() then return end
        local noShift = EllesmereUIDB and EllesmereUIDB.shifterNoShift
        local mode
        if IsShiftKeyDown() or noShift then
            mode = "save"
        elseif IsControlKeyDown() then
            mode = "temp"
        else
            return
        end
        if frame:IsProtected() then
            StartSecureDrag(frame, name, mode)
        else
            dragging = mode
            frame:StartMoving()
        end
    end)

    dragTarget:HookScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        if frame:IsProtected() then
            if secureDrag.frame == frame then StopSecureDrag() end
            return
        end
        if not dragging then return end
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
        local p, _, rp, x, y = frame:GetPoint(1)
        if p then
            if dragging == "save" then
                SavePos(name, p, rp, x, y)
                tempPos[frame] = nil
            else
                tempPos[frame] = {
                    point = p, relPoint = rp, x = x, y = y,
                }
            end
        end
        dragging = nil
    end)

    frame:HookScript("OnShow", function()
        if not IsEnabled() then return end
        ApplyPosition(frame, name)
    end)

    frame:HookScript("OnHide", function()
        if secureDrag.frame == frame then StopSecureDrag() end
        tempPos[frame] = nil
    end)

    hooksecurefunc(frame, "SetPoint", function()
        if not IsEnabled() then return end
        if ffd._shIgnoreSP then return end
        if secureDrag.frame == frame then return end  -- don't fight an active drag
        if InCombatLockdown() and frame:IsProtected() then return end
        if tempPos[frame] or GetSavedPos(name) then
            ApplyPosition(frame, name)
        end
    end)

    -- If the frame is already visible, apply saved position now
    if frame:IsVisible() then
        ApplyPosition(frame, name)
    end
end

local function TryHook(name)
    local frame = _G[name]
    if frame and frame.HookScript then HookFrame(frame, name) end
end

-------------------------------------------------------------------------------
--  Event-driven initialization
-------------------------------------------------------------------------------
local pendingAddons = {}
eventFrame = CreateFrame("Frame")

local function InitShifter()
    for i = 1, #PRELOADED do
        TryHook(PRELOADED[i])
    end
    for addon, frames in pairs(ADDON_FRAMES) do
        if C_AddOns.IsAddOnLoaded(addon) then
            for i = 1, #frames do TryHook(frames[i]) end
        else
            pendingAddons[addon] = frames
        end
    end
    if next(pendingAddons) then
        eventFrame:RegisterEvent("ADDON_LOADED")
    end
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if IsEnabled() then InitShifter() end
    elseif event == "ADDON_LOADED" then
        local frames = pendingAddons[arg1]
        if frames then
            pendingAddons[arg1] = nil
            for i = 1, #frames do TryHook(frames[i]) end
            if not next(pendingAddons) then
                self:UnregisterEvent("ADDON_LOADED")
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        for i = 1, #deferredMovable do
            local f = deferredMovable[i]
            f:SetMovable(true)
            f:SetClampedToScreen(true)
        end
        wipe(deferredMovable)
    end
end)

-- Exposed for the options toggle (mid-session enable without /reload)
function EllesmereUI._InitShifter()
    InitShifter()
end

-- Exposed for the options reset button
function EllesmereUI._ResetShifterPositions()
    if EllesmereUIDB then
        EllesmereUIDB.shifterPositions = nil
    end
    wipe(tempPos)
end
