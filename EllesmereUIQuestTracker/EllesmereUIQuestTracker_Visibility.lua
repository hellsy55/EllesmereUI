-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_Visibility.lua
--
-- Visibility and positioning for ObjectiveTrackerFrame.
--
-- Rules that must never be broken:
--   1. Never SetScript on ObjectiveTrackerFrame -- HookScript only.
--   2. Never walk the tracker's children to call EnableMouse. We hide the
--      frame by reparenting the top-level to a hidden container.
--   3. Positioning is delegated to Blizzard's Edit Mode; we provide a
--      ctrl-drag session-only nudge on top, nothing persistent.
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT

-- Hidden reparent target -- NEVER recursed into.
local hiddenFrame = CreateFrame("Frame", "EllesmereUIQTHiddenParent", UIParent)
hiddenFrame:Hide()

local _eqtCollapsed       = false
local _eqtSuppressed      = false

-- Forward-declared so the auto-hide path can toggle BG visibility. The BG
-- is actually created further down (EnsureBG / InitVisibility).
local _bgFrame

local function GetTracker() return _G.ObjectiveTrackerFrame end

-------------------------------------------------------------------------------
-- Top-level collapse / expand via SetParent. No child recursion.
-------------------------------------------------------------------------------
local function Collapse()
    local otf = GetTracker()
    if not otf then return end
    if InCombatLockdown() then return end
    if _eqtCollapsed then return end
    _eqtCollapsed = true
    otf:SetParent(hiddenFrame)
end

local function Expand()
    local otf = GetTracker()
    if not otf then return end
    if InCombatLockdown() then return end
    if not _eqtCollapsed then return end
    _eqtCollapsed = false
    otf:SetParent(UIParent)
end

-- Suppression API (cross-module hide). Uses alpha only -- safe because alpha
-- inherits to children without touching mouse state. Combined with the
-- collapse-on-actual-hide path, this covers both use cases.
function EQT.ApplySuppression(on)
    _eqtSuppressed = on and true or false
    local otf = GetTracker()
    if not otf then return end
    otf:SetAlpha(on and 0 or 1)
end

-------------------------------------------------------------------------------
-- Auto-hide: hard-coded to raids and arenas only. Uses the same hook-on-Show
-- pattern as the M+ timer (EllesmereUIMythicTimer.lua line ~502) since that
-- pattern is proven taint-free: we never SetScript, never recurse into
-- children, never touch mouse state, just :Hide() the tracker top-level
-- whenever Blizzard tries to :Show() it in a raid or arena.
-------------------------------------------------------------------------------
local function ShouldAutoHide()
    local _, instanceType = GetInstanceInfo()
    return instanceType == "raid" or instanceType == "arena"
end

local _showHookInstalled = false
local function InstallShowHook()
    if _showHookInstalled then return end
    local otf = GetTracker()
    if not otf then return end
    _showHookInstalled = true
    -- Raid/arena auto-hide. Runs before other Show hooks (hooksecurefunc
    -- stacks); the M+ timer installs its own similar hook for M+.
    hooksecurefunc(otf, "Show", function(self)
        if ShouldAutoHide() then self:Hide() end
    end)
    -- BG follows the tracker's actual IsShown() state, regardless of who
    -- hid it (us, M+ timer, Blizzard). OnHide fires after the Hide lands,
    -- OnShow fires after Show lands but the M+ timer's Show-hook re-hides
    -- it synchronously, so by the time OnShow fires the frame may already
    -- be hidden again -- we re-check IsShown().
    otf:HookScript("OnHide", function() if _bgFrame then _bgFrame:Hide() end end)
    otf:HookScript("OnShow", function(self)
        if _bgFrame then
            if self:IsShown() then _bgFrame:Show() else _bgFrame:Hide() end
        end
    end)
end

local function UpdateVisibility()
    InstallShowHook()
    local otf = GetTracker()
    if not otf then return end
    if ShouldAutoHide() then
        otf:Hide()
        if _bgFrame then _bgFrame:Hide() end
    else
        if not otf:IsShown() then otf:Show() end
        if _bgFrame then _bgFrame:Show() end
    end
end
EQT.UpdateVisibility = UpdateVisibility

-- Kept as a no-op so the options-refresh path that used to trigger a state-
-- driver rebuild doesn't error.
function EQT.RefreshStateDriver() UpdateVisibility() end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Background frame. Our own UIParent-parented frame anchored to the tracker's
-- bounds. Never a child of ObjectiveTrackerFrame -- keeps us off the secure
-- tree. Color and alpha driven by DB (bgR/G/B/Alpha).
-------------------------------------------------------------------------------
local function EnsureBG()
    if _bgFrame then return _bgFrame end
    local otf = GetTracker()
    if not otf then return nil end
    _bgFrame = CreateFrame("Frame", "EllesmereUIQTBackground", UIParent)
    _bgFrame:SetFrameStrata(otf:GetFrameStrata() or "MEDIUM")
    _bgFrame:SetFrameLevel(math.max(0, otf:GetFrameLevel() - 1))
    -- Cut 30px off the top so the background doesn't bleed behind the
    -- master header area. Bottom edge extends 6px past the last block.
    _bgFrame:SetPoint("TOPLEFT", otf, "TOPLEFT", -6, -30)
    -- Bottom is re-anchored dynamically in ResizeBGToContent(); this is
    -- only the fallback extent when no content has loaded yet.
    _bgFrame:SetPoint("BOTTOMRIGHT", otf, "TOPRIGHT", 11, -60)
    local tex = _bgFrame:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    _bgFrame._tex = tex

    -- 1px physical-pixel-perfect accent divider at the very top of the BG
    -- (i.e. at the -30px cutoff line). Full width of the tracker, anchored
    -- directly to it so the line matches tracker width regardless of BG
    -- padding. Same snap pattern as PP.CreateBorder.
    local divider = _bgFrame:CreateTexture(nil, "OVERLAY")
    divider:SetPoint("TOPLEFT",  otf, "TOPLEFT",  -6, -30)
    divider:SetPoint("TOPRIGHT", otf, "TOPRIGHT",  11, -30)
    _bgFrame._divider = divider
    return _bgFrame
end

local function ApplyTopDivider()
    local bg = _bgFrame
    if not bg or not bg._divider then return end
    local tex = bg._divider
    if EQT.Cfg("showTopLine") == false then
        tex:Hide()
        return
    end
    local PP_CORE = EllesmereUI and EllesmereUI.PP
    local PP_SEC  = EllesmereUI and EllesmereUI.PanelPP
    if PP_SEC and PP_SEC.DisablePixelSnap then PP_SEC.DisablePixelSnap(tex) end
    local perfect = (PP_CORE and PP_CORE.perfect) or (PP_SEC and PP_SEC.mult) or 1
    local otf = GetTracker()
    local es = (otf and otf.GetEffectiveScale and otf:GetEffectiveScale()) or 1
    local onePixel = (es and es > 0) and (perfect / es) or (PP_SEC and PP_SEC.mult) or 1
    tex:SetHeight(onePixel)
    local eg = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    local r, g, b = (eg and eg.r) or 0.047, (eg and eg.g) or 0.824, (eg and eg.b) or 0.624
    tex:SetColorTexture(r, g, b, 1)
    tex:Show()
end

-- Find the frame that sits at the absolute bottom of all visible content
-- across every tracker module. Used to anchor the BG's bottom edge.
local function GetLowestContentFrame()
    local otf = GetTracker()
    if not otf then return nil end
    local modules = otf.modules or otf.MODULES
    if not modules then return nil end
    local lowestFrame, lowestY
    for _, tracker in ipairs(modules) do
        local function consider(frame)
            if not frame or type(frame) ~= "table" then return end
            if not frame.GetBottom or not frame.GetObjectType then return end
            if not (frame.IsShown and frame:IsShown()) then return end
            local ok, otype = pcall(frame.GetObjectType, frame)
            if not ok then return end
            if otype ~= "Frame" and otype ~= "Button" then return end
            local y = frame:GetBottom()
            if y and (not lowestY or y < lowestY) then
                lowestY, lowestFrame = y, frame
            end
        end
        if tracker.usedBlocks then
            for _, v in pairs(tracker.usedBlocks) do
                if type(v) == "table" then
                    if v.GetBottom then
                        consider(v)
                    else
                        for _, block in pairs(v) do consider(block) end
                    end
                end
            end
        end
        -- Only consider the Header as content if the tracker actually has
        -- something to display. Empty trackers leave their Header shown at
        -- stale positions and would otherwise stretch the BG past real
        -- content when a section clears.
        if tracker.hasContents then
            consider(tracker.Header)
        end
    end
    return lowestFrame
end

-- Event-driven resize with a debounce. Every QueueResize call coalesces
-- into a single deferred ResizeBGToContent pass; bursts of layout events
-- that used to trigger up to 60 frames of per-frame work now fire the
-- resize once per tick. If the measured lowest frame keeps shifting after
-- a resize (e.g. Blizzard's collapse/expand animation), each shift re-
-- queues exactly one more pass -- never a continuous OnUpdate loop.
local _resizePending = false
local function QueueResize()
    if _resizePending then return end
    _resizePending = true
    C_Timer.After(0.05, function()
        _resizePending = false
        if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end
    end)
end
EQT.QueueResize = QueueResize

local function ResizeBGToContent()
    local bg = _bgFrame
    local otf = GetTracker()
    if not bg or not otf then return end
    -- Sync BG visibility to the tracker every layout pass. Cheaper and
    -- more reliable than hooking OnHide/OnShow, since ResizeBGToContent
    -- is already called whenever content changes / anything re-lays out.
    if not otf:IsShown() then
        if bg:IsShown() then bg:Hide() end
        return
    elseif not bg:IsShown() then
        bg:Show()
    end
    local lowest = GetLowestContentFrame()
    -- Transient "no visible content" states happen for a frame during
    -- collapse/expand. Keep the previous anchor in that case to avoid
    -- snapping the BG to the thin-strip fallback for one flicker.
    if not lowest and bg._lastLowest and bg._lastLowest.IsShown
       and bg._lastLowest:IsShown() then
        return
    end
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT",  otf, "TOPLEFT",  -6, -30)
    bg:SetPoint("TOPRIGHT", otf, "TOPRIGHT", 11, -30)
    if lowest then
        bg:SetPoint("BOTTOMLEFT",  lowest, "BOTTOMLEFT",   0, -15)
        bg:SetPoint("BOTTOMRIGHT", lowest, "BOTTOMRIGHT",  0, -15)
        bg._lastLowest = lowest
    else
        bg:SetPoint("BOTTOMLEFT",  otf, "TOPLEFT",  -6, -60)
        bg:SetPoint("BOTTOMRIGHT", otf, "TOPRIGHT", 11, -60)
        bg._lastLowest = nil
    end
end
EQT.ResizeBGToContent = ResizeBGToContent

function EQT.ApplyBackground()
    local bg = EnsureBG()
    if not bg then return end
    local cfg = EQT.DB()
    local r = cfg.bgR or 0
    local g = cfg.bgG or 0
    local b = cfg.bgB or 0
    local a = cfg.bgAlpha or 0.5
    bg._tex:SetColorTexture(r, g, b, a)
    ResizeBGToContent()
    ApplyTopDivider()
end

function EQT.InitVisibility()
    local otf = GetTracker()
    if not otf then return end

    EnsureBG()
    EQT.ApplyBackground()
    InstallShowHook()

    -- After init, sync BG to the tracker's current shown state. On /reload
    -- inside M+ (or a raid), otf may already be hidden by the time we run
    -- and OnHide won't fire again, leaving BG + divider visible alone.
    local function SyncBGToTracker()
        if not _bgFrame then return end
        if otf:IsShown() then _bgFrame:Show() else _bgFrame:Hide() end
    end
    SyncBGToTracker()
    C_Timer.After(0.1, SyncBGToTracker)
    C_Timer.After(0.5, SyncBGToTracker)

    local evt = CreateFrame("Frame")
    evt:RegisterEvent("PLAYER_ENTERING_WORLD")
    evt:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    evt:SetScript("OnEvent", function()
        UpdateVisibility()
        SyncBGToTracker()
    end)

    C_Timer.After(0.5, UpdateVisibility)
end
