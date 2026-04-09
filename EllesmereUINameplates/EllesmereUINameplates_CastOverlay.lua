-------------------------------------------------------------------------------
--  EllesmereUINameplates_CastOverlay.lua
--
--  Renders a duplicate of the casting unit's cast bar above its nameplate at
--  HIGH frame strata so casting plates are always visible above stacked or
--  occluded plates. The overlay is parented to UIParent (independent strata)
--  but anchored to the Blizzard nameplate via SetPoint, so it tracks the
--  plate's screen position automatically with no OnUpdate position polling.
--
--  Lifecycle is driven by the existing NameplateFrame:UpdateCast pipeline:
--  RefreshCastOverlay(plate) is called from UpdateCast and ClearUnit. The
--  overlay reads cast info from the same APIs the on-plate cast bar uses
--  and applies the same secret value guards.
-------------------------------------------------------------------------------
local addonName, ns = ...
if not ns then return end

local PP = EllesmereUI and EllesmereUI.PP

local pairs, tremove = pairs, table.remove
local CreateFrame = CreateFrame
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local UnitCastingDuration, UnitChannelDuration = UnitCastingDuration, UnitChannelDuration
local UnitEmpoweredChannelDuration = UnitEmpoweredChannelDuration
local UnitIsUnit = UnitIsUnit
local UnitName = UnitName
local UnitSpellTargetName = UnitSpellTargetName
local UnitSpellTargetClass = UnitSpellTargetClass
local C_ClassColor = C_ClassColor
local _isSecret = issecretvalue

local function FP() return ns.db and ns.db.profile end

-- Debug: set _eui_overlay_debug = true in chat to enable spam, false to silence
_G._eui_overlay_debug = _G._eui_overlay_debug
local function dprint(...)
    if not _G._eui_overlay_debug then return end
    print("|cff0cd29fEUI-Overlay|r", ...)
end

-------------------------------------------------------------------------------
--  Pool state
-------------------------------------------------------------------------------
local overlayPool = {}    -- inactive overlays awaiting reuse
local activePlates = {}   -- [plate] = overlay  (active overlays keyed by plate)

local OVERLAY_W = 160
local OVERLAY_H = 18

-- Timer text only displays %.1f precision so updating faster than 10 Hz
-- is wasted work. Throttling cuts the OnUpdate body from ~60 calls/sec
-- per overlay down to ~10/sec, with no visible difference.
local TIMER_UPDATE_INTERVAL = 0.1

-------------------------------------------------------------------------------
--  Text settings helper: applies all the cast bar text settings
--  (size/color/width zones/showTimer) the same way the on-plate cast bar
--  does. Mirrors the block in EllesmereUINameplates.lua at the layout
--  function (around line 3096-3121).
-------------------------------------------------------------------------------
local function ApplyCastBarTextSettings(ov)
    local cfg = FP() or {}
    local cns = cfg.castNameSize or 10
    local cts = cfg.castTargetSize or 10
    local cnc = cfg.castNameColor or { r = 1, g = 1, b = 1 }
    local ctmSz = cfg.castTimerSize or 10
    local ctmC = cfg.castTimerColor or { r = 1, g = 1, b = 1 }

    if ns.SetFSFont and ns.GetNPOutline then
        local outline = ns.GetNPOutline()
        ns.SetFSFont(ov.name,   cns,   outline)
        ns.SetFSFont(ov.target, cts,   outline)
        ns.SetFSFont(ov.timer,  ctmSz, outline)
    end

    -- SetFont can reset justify; reapply
    ov.name:SetJustifyH("LEFT")
    ov.target:SetJustifyH("RIGHT")
    ov.timer:SetJustifyH("RIGHT")

    ov.name:SetTextColor(cnc.r, cnc.g, cnc.b, 1)
    ov.timer:SetTextColor(ctmC.r, ctmC.g, ctmC.b, 1)

    -- Show/hide cast timer per user setting
    local showTimer = (cfg.showCastTimer ~= false)
    ov.timer:SetShown(showTimer)

    -- Width zones identical to the on-plate cast bar:
    -- castName 42%, castTimer = ctmSz * 2.2, castTarget 42% (anchored
    -- to right minus timer width). All three truncate to "..." when
    -- the spell name is too long because of fixed width + no wrap.
    local castW = ov.bar:GetWidth()
    local timerW = ctmSz * 2.2
    if castW and castW > 0 then
        ov.name:SetWidth(castW * 0.42)
        ov.timer:SetWidth(timerW)
        ov.target:SetWidth(castW * 0.42)
        ov.target:ClearAllPoints()
        ov.target:SetPoint("RIGHT", ov.bar, "RIGHT", -3 - timerW, 0)
    end
end

-------------------------------------------------------------------------------
--  Cast target read + class color helper: mirrors the block in
--  NameplateFrame:UpdateCast around lines 4280-4313.
-------------------------------------------------------------------------------
local function ApplyCastBarTargetText(ov, plate)
    local unit = plate.unit
    if not unit then
        ov.target:SetText("")
        ov.target:Hide()
        return
    end

    local spellTarget, spellTargetClass
    local rawTarget = UnitSpellTargetName and UnitSpellTargetName(unit)
    if rawTarget then
        local shortName = UnitName(rawTarget)
        spellTarget = shortName or rawTarget
        spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(unit)
    end
    local hasTarget = spellTarget and true or false
    ov.target:SetText(spellTarget or "")
    ov.target:SetShown(hasTarget)

    local cfg = FP() or {}
    local useClassColor = cfg.castTargetClassColor
    if useClassColor == nil then useClassColor = true end

    if useClassColor then
        local applied = false
        if spellTargetClass and C_ClassColor then
            local c = C_ClassColor.GetClassColor(spellTargetClass)
            if c then
                ov.target:SetTextColor(c:GetRGB())
                applied = true
            end
        end
        if not applied then
            ov.target:SetTextColor(1, 1, 1, 1)
        end
    else
        local ctc = cfg.castTargetColor or { r = 1, g = 1, b = 1 }
        ov.target:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
    end
end

-------------------------------------------------------------------------------
--  Layout helper: matches the on-plate cast bar's exact size and effective
--  scale at any point in time. Cheap because it caches last-applied values
--  and only calls Set* when something changed. Called from the acquire path
--  (immediate) and from the throttled OnUpdate (catches mid-cast changes
--  like target acquired or focus changed).
--
--  Three settings affect the on-plate cast bar's visual size:
--    1. targetScale       (NameplateFrame:ApplyScale, when unit is target)
--    2. castScale         (NameplateFrame:ApplyScale, when unit is casting)
--    3. focusCastHeight   (per-plate height multiplier when unit is focus)
--
--  (1) and (2) are applied as a SetScale on the plate frame. We mirror that
--  by setting the overlay's own SetScale to the plate's effective scale
--  (relative to UIParent so the math is consistent across UIParent scales).
--  (3) is a height multiplier we compute and apply directly.
-------------------------------------------------------------------------------
local function ApplyOverlayLayout(ov, plate)
    if not plate or not plate.health then return end
    if plate:IsForbidden() then return end

    -- Match the plate's effective scale (handles target/cast scale)
    local plateES = plate:GetEffectiveScale()
    local uiES    = UIParent:GetEffectiveScale()
    local desiredScale = (uiES > 0) and (plateES / uiES) or 1
    if ov._lastScale ~= desiredScale then
        ov._lastScale = desiredScale
        ov:SetScale(desiredScale)
    end

    -- Match the cast bar height including focus multiplier
    local castH = (ns.GetCastBarHeight and ns.GetCastBarHeight()) or 17
    if plate.unit and ns.GetFocusCastHeight and UnitIsUnit(plate.unit, "focus") then
        local pct = ns.GetFocusCastHeight()
        if pct and pct ~= 100 then
            castH = math.floor(castH * pct / 100 + 0.5)
        end
    end
    if ov._lastHeight ~= castH then
        ov._lastHeight = castH
        ov:SetHeight(castH)
        ov.iconFrame:SetSize(castH, castH)
        local shH = castH * 0.75
        ov.shieldFrame:SetSize(shH * (29 / 35), shH)
    end
end

-------------------------------------------------------------------------------
--  Build a single overlay frame from scratch (parent = UIParent so we get
--  HIGH strata independent of the nameplate's strata).
-------------------------------------------------------------------------------
local function BuildOverlay()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(OVERLAY_W, OVERLAY_H)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(50)
    f:EnableMouse(false)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    f.bg = bg

    if PP and PP.CreateBorder then
        PP.CreateBorder(f, 0, 0, 0, 1, 1, "OVERLAY", 7)
    end

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:GetStatusBarTexture():SetVertexColor(0.70, 0.40, 0.90)
    f.bar = bar

    -- Uninterruptible overlay (alpha controlled via SetAlphaFromBoolean
    -- because the kickProtected flag is a secret value on Midnight)
    local barOverlay = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    barOverlay:SetAllPoints(bar:GetStatusBarTexture())
    barOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    barOverlay:SetAlpha(0)
    f.barOverlay = barOverlay

    -- Shield icon for uninterruptible casts (matches the on-plate
    -- castShieldFrame. Visibility is gated via SetAlphaFromBoolean so
    -- the secret-valued kickProtected flag stays safe.)
    local shieldFrame = CreateFrame("Frame", nil, bar)
    local shieldHeight = OVERLAY_H * 0.75
    local shieldWidth  = shieldHeight * (29 / 35)
    shieldFrame:SetSize(shieldWidth, shieldHeight)
    shieldFrame:SetPoint("CENTER", bar, "LEFT", 0, 0)
    shieldFrame:SetFrameLevel(bar:GetFrameLevel() + 5)
    shieldFrame:Hide()
    local shield = shieldFrame:CreateTexture(nil, "OVERLAY")
    shield:SetAllPoints()
    shield:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\shield.png")
    f.shieldFrame = shieldFrame
    f.shield = shield

    -- Icon frame on the left edge of the bar
    local iconFrame = CreateFrame("Frame", nil, f)
    iconFrame:SetSize(OVERLAY_H, OVERLAY_H)
    iconFrame:SetPoint("TOPRIGHT", f, "TOPLEFT", -2, 0)
    if PP and PP.CreateBorder then
        PP.CreateBorder(iconFrame, 0, 0, 0, 1, 1, "OVERLAY", 7)
    end
    f.iconFrame = iconFrame

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon

    -- Three independent text zones, matching the on-plate cast bar layout:
    -- [castName LEFT 42%]  [castTarget anchored before timer 42%]  [castTimer RIGHT]
    -- All three use SetWordWrap(false) + SetMaxLines(1) + a fixed width
    -- so they truncate automatically when the spell name is too long.
    local fontPath = (ns.GetFont and ns.GetFont()) or STANDARD_TEXT_FONT
    local outline  = (ns.GetNPOutline and ns.GetNPOutline()) or "OUTLINE"

    local name = bar:CreateFontString(nil, "OVERLAY")
    name:SetFont(fontPath, 10, outline)
    name:SetPoint("LEFT", bar, "LEFT", 5, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetNonSpaceWrap(false)
    name:SetMaxLines(1)
    f.name = name

    local target = bar:CreateFontString(nil, "OVERLAY")
    target:SetFont(fontPath, 10, outline)
    target:SetJustifyH("RIGHT")
    target:SetWordWrap(false)
    target:SetNonSpaceWrap(false)
    target:SetMaxLines(1)
    f.target = target

    local timer = bar:CreateFontString(nil, "OVERLAY")
    timer:SetFont(fontPath, 10, outline)
    timer:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    timer:SetJustifyH("RIGHT")
    timer:SetWordWrap(false)
    timer:SetMaxLines(1)
    f.timer = timer

    -- Important cast glow host frame. Stays persistently above the bar;
    -- the glow animation is started/stopped via ConfigureImportantCastGlow.
    -- Separate from the on-plate glow (_importantCastOverlay on plate.cast)
    -- since that one is hidden alongside the on-plate cast bar when this
    -- overlay is active.
    local glowHost = CreateFrame("Frame", nil, bar)
    glowHost:SetAllPoints(bar)
    glowHost:SetFrameLevel(bar:GetFrameLevel() + 5)
    glowHost:EnableMouse(false)
    glowHost:SetAlpha(0)
    f.glowHost = glowHost
    f._glowActive = false
    f._glowStyle  = nil

    -- Per-overlay OnUpdate: update the timer text from the cached duration
    -- object and re-apply the layout (catches mid-cast scale/height changes
    -- like target acquired or focus changed). Throttled to
    -- TIMER_UPDATE_INTERVAL (10 Hz) since the text only changes at %.1f
    -- precision. The bar fill itself is animated by SetTimerDuration on
    -- the C side and needs no Lua tick.
    f._elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        self._elapsed = self._elapsed + dt
        if self._elapsed < TIMER_UPDATE_INTERVAL then return end
        self._elapsed = 0

        local plate = self.plate
        if not plate or not plate.unit or not plate.isCasting then return end
        if plate:IsForbidden() then return end

        -- Sync size and scale (cached, no-op if unchanged)
        ApplyOverlayLayout(self, plate)

        local durObj = self.durObj
        if not durObj then return end

        local remaining = durObj:GetRemainingDuration()
        if remaining then
            self.timer:SetFormattedText("%.1f", remaining)
        else
            self.timer:SetText("")
        end
    end)

    return f
end

-------------------------------------------------------------------------------
--  Important cast glow: mirrors NameplateFrame:UpdateImportantCastGlow so
--  the overlay shows the same glow the on-plate cast bar would (if the
--  on-plate bar weren't hidden underneath our overlay).
-------------------------------------------------------------------------------
local function ConfigureImportantCastGlow(ov, spellID)
    local cfg = FP() or {}
    local enabled = cfg.importantCastGlow
    if enabled == nil then enabled = true end
    if not enabled or not ov.glowHost then
        if ov._glowActive then
            local Glows = _G.EllesmereUI and _G.EllesmereUI.Glows
            if Glows then Glows.StopAllGlows(ov.glowHost) end
            ov._glowActive = false
            ov._glowStyle = nil
        end
        if ov.glowHost then ov.glowHost:SetAlpha(0) end
        return
    end

    if not C_Spell or not C_Spell.IsSpellImportant then
        return
    end

    local Glows = _G.EllesmereUI and _G.EllesmereUI.Glows
    if not Glows then return end

    local style = cfg.importantCastGlowStyle or 1
    if style ~= 1 and style ~= 4 then style = 1 end
    local c = cfg.importantCastGlowColor or { r = 1, g = 0.2, b = 0.2 }

    -- Start (or restart, if style changed) the glow animation. This is
    -- idempotent while the style is stable.
    if not ov._glowActive or ov._glowStyle ~= style then
        Glows.StopAllGlows(ov.glowHost)
        local pW, pH = ov.bar:GetWidth(), ov.bar:GetHeight()
        if pW < 5 then pW = 100 end
        if pH < 5 then pH = 14 end
        if style == 4 then
            Glows.StartAutoCastShine(ov.glowHost, pW, c.r, c.g, c.b, 1.0, pH)
        else
            local N       = cfg.importantCastGlowLines     or 8
            local th      = cfg.importantCastGlowThickness or 2
            local period  = cfg.importantCastGlowSpeed     or 4
            local lineLen = math.floor((pW + pH) * (2 / N - 0.1))
            lineLen = math.min(lineLen, math.min(pW, pH))
            if lineLen < 1 then lineLen = 1 end
            Glows.StartProceduralAnts(ov.glowHost, N, th, period, lineLen, c.r, c.g, c.b, pW, pH)
        end
        ov._glowActive = true
        ov._glowStyle = style
    end

    -- SetAlphaFromBoolean handles the secret boolean return of
    -- IsSpellImportant safely. Important = visible (alpha 1), not = hidden.
    ov.glowHost:Show()
    local ok, isImportant = pcall(C_Spell.IsSpellImportant, spellID or 0)
    if ok then
        ov.glowHost:SetAlphaFromBoolean(isImportant)
    else
        ov.glowHost:SetAlpha(0)
    end
end

local function ClearImportantCastGlow(ov)
    if not ov or not ov.glowHost then return end
    if ov._glowActive then
        local Glows = _G.EllesmereUI and _G.EllesmereUI.Glows
        if Glows then Glows.StopAllGlows(ov.glowHost) end
        ov._glowActive = false
        ov._glowStyle = nil
    end
    ov.glowHost:SetAlpha(0)
end

-------------------------------------------------------------------------------
--  Pool acquire / release
-------------------------------------------------------------------------------
local function AcquireOverlay()
    local pooled = tremove(overlayPool)
    if pooled then
        dprint("AcquireOverlay: reused pooled")
        return pooled
    end
    dprint("AcquireOverlay: built new")
    return BuildOverlay()
end

local function ReleaseOverlay(plate)
    local ov = activePlates[plate]
    if not ov then return end
    activePlates[plate] = nil
    ov:ClearAllPoints()
    ov:Hide()
    ov.bar:SetMinMaxValues(0, 1)
    ov.bar:SetValue(1)
    ov.icon:SetTexture(nil)
    ov.name:SetText("")
    ov.target:SetText("")
    ov.timer:SetText("")
    ov.barOverlay:SetAlpha(0)
    if ov.shieldFrame then ov.shieldFrame:Hide() end
    -- Stop any active important cast glow animation on the overlay
    ClearImportantCastGlow(ov)
    -- Restore the on-plate cast bar's alpha so it renders normally again
    -- (we hid it while the overlay was driving the visual).
    if plate and plate.cast then plate.cast:SetAlpha(1) end
    ov.plate = nil
    ov.durObj = nil
    -- Clear cached layout values so the next acquire from the pool
    -- always re-applies size/scale on first use
    ov._lastScale = nil
    ov._lastHeight = nil
    overlayPool[#overlayPool + 1] = ov
end

-------------------------------------------------------------------------------
--  Configure overlay contents from current cast info. Re-runnable on every
--  refresh (covers cast start, channel start, delayed, channel update).
-------------------------------------------------------------------------------
local function ConfigureOverlay(ov, plate)
    local unit = plate.unit
    dprint("ConfigureOverlay: unit=", unit, "isCasting=", plate.isCasting)
    if not unit then return end

    -- Match the on-plate cast bar's UnitCastingInfo/UnitChannelInfo tuple
    -- positions exactly: UnitCastingInfo returns kickProtected at 8 and
    -- castSpellID at 9; UnitChannelInfo shifts both down one slot because
    -- it has no castID field.
    local name, _, texture, _, _, _, _, kickProtected, castSpellID = UnitCastingInfo(unit)
    local isChannel = false
    local isEmpowered = false
    -- type(name) == "nil" is the taint-safe nil check for secret strings:
    -- comparing the secret string directly to a literal (like "") taints,
    -- but type() returns a plain string that's safe to compare.
    if type(name) == "nil" then
        name, _, texture, _, _, _, kickProtected, castSpellID = UnitChannelInfo(unit)
        isChannel = true
    end
    if type(name) == "nil" then dprint("  bail: no name") return end

    -- Apply all cast text settings (sizes/colors/widths/showTimer) the
    -- same way the on-plate cast bar does. Run on every config so option
    -- changes mid-session take effect on the next cast event.
    ApplyCastBarTextSettings(ov)

    -- Spell name. Pass through directly: secret-flagged values still
    -- render correctly in FontStrings (they only taint when used in
    -- arithmetic/comparisons). The existing on-plate cast bar does the
    -- same thing.
    ov.name:SetText(name)

    -- Cast target read + class color (1:1 with on-plate cast bar)
    ApplyCastBarTargetText(ov, plate)

    -- Spell icon: respect the user's "Spell Icon" toggle and icon scale
    -- so the overlay matches the on-plate cast bar exactly.
    local showIcon = (ns.GetShowCastIcon == nil) or ns.GetShowCastIcon()
    if showIcon then
        if texture ~= nil then ov.icon:SetTexture(texture) end
        local iconScale = (ns.GetCastIconScale and ns.GetCastIconScale()) or 1
        ov.iconFrame:SetScale(iconScale)
        ov.iconFrame:Show()
    else
        ov.iconFrame:Hide()
    end

    -- Bar tint. Mirror the on-plate cast bar's ComputeCastBarTint, which
    -- blends castBar <-> interruptReady based on whether the player's
    -- interrupt is off cooldown. Falls back to castBar when the helper
    -- isn't exposed yet (shouldn't happen in practice; the main nameplate
    -- file is required before this file).
    local cfg = FP() or {}
    local baseTint  = cfg.castBar         or { r = 0.70, g = 0.40, b = 0.90 }
    local readyTint = cfg.interruptReady  or { r = 0.92, g = 0.35, b = 0.20 }
    local cr, cg, cb
    if ns.ComputeCastBarTint then
        cr, cg, cb = ns.ComputeCastBarTint(readyTint, baseTint)
    else
        cr, cg, cb = baseTint.r, baseTint.g, baseTint.b
    end
    ov.bar:SetMinMaxValues(0, 1)
    ov.bar:GetStatusBarTexture():SetVertexColor(cr, cg, cb)

    -- Drive the bar via SetTimerDuration EXACTLY the same way the on-plate
    -- cast bar in NameplateFrame:UpdateCast does. Wrapped in pcall as a
    -- safety net in case this overlay's StatusBar (parented to UIParent
    -- instead of the nameplate hierarchy) rejects the call. If pcall
    -- fails, fall back to a constant-full bar so the user still sees
    -- which unit is casting. The duration object is cached on the overlay
    -- so the OnUpdate handler can read remaining time without re-calling
    -- UnitCastingDuration every tick.
    local timerOk = false
    local castDuration
    if UnitCastingDuration and ov.bar.SetTimerDuration and Enum and Enum.StatusBarTimerDirection then
        if isChannel then
            -- Empowered channels (Evoker) need UnitEmpoweredChannelDuration;
            -- UnitChannelDuration can return nil during the empower phase.
            if UnitEmpoweredChannelDuration then
                castDuration = UnitEmpoweredChannelDuration(unit, true)
                if castDuration then isEmpowered = true end
            end
            if not castDuration then
                castDuration = UnitChannelDuration(unit)
            end
        else
            castDuration = UnitCastingDuration(unit)
        end
        if castDuration then
            -- Empowered channels fill forward (stages), normal channels
            -- fill backward (remaining), normal casts fill forward (elapsed).
            local direction = (isChannel and not isEmpowered)
                and Enum.StatusBarTimerDirection.RemainingTime
                or Enum.StatusBarTimerDirection.ElapsedTime
            ov.bar:SetReverseFill(false)
            timerOk = pcall(ov.bar.SetTimerDuration, ov.bar, castDuration, nil, direction)
        end
    end
    ov.durObj = castDuration
    if not timerOk then
        -- Fallback: keep the bar at full so it's still a visible indicator
        ov.bar:SetValue(1)
    end
    -- Prime the timer text immediately so we don't have a 100ms blank
    -- before the first throttled OnUpdate run.
    if castDuration then
        local remaining = castDuration:GetRemainingDuration()
        if remaining then
            ov.timer:SetFormattedText("%.1f", remaining)
        end
    end
    ov._elapsed = 0

    -- Uninterruptible overlay (gray tint) and shield icon. kickProtected
    -- is a secret boolean on Midnight; SetAlphaFromBoolean handles it
    -- safely. We default both to hidden (alpha 0) before applying so
    -- channels-after-casts don't leak the previous state.
    local unintColor = cfg.castBarUninterruptible or { r = 0.45, g = 0.45, b = 0.45 }
    ov.barOverlay:SetVertexColor(unintColor.r, unintColor.g, unintColor.b)
    ov.barOverlay:SetAlpha(0)
    ov.shieldFrame:Show()
    ov.shieldFrame:SetAlpha(0)
    if ov.barOverlay.SetAlphaFromBoolean and ov.shieldFrame.SetAlphaFromBoolean then
        ov.barOverlay:SetAlphaFromBoolean(kickProtected)
        ov.shieldFrame:SetAlphaFromBoolean(kickProtected)
    elseif kickProtected then
        ov.barOverlay:SetAlpha(1)
        ov.shieldFrame:SetAlpha(1)
    end

    -- Important cast glow (mirrors NameplateFrame:UpdateImportantCastGlow)
    ConfigureImportantCastGlow(ov, castSpellID)
end

-------------------------------------------------------------------------------
--  Public: refresh overlay state for a plate. Acquires when casting, releases
--  when not. Called from NameplateFrame:UpdateCast and :ClearUnit.
-------------------------------------------------------------------------------
function ns.RefreshCastOverlay(plate)
    if not plate then return end

    local fp = FP()
    if not fp or not fp.castOverlayEnabled then
        if activePlates[plate] then ReleaseOverlay(plate) end
        return
    end

    -- Plate must be a valid frame we can SetPoint to. Forbidden frames
    -- throw on any C call so guard before reading anything.
    if plate.IsForbidden and plate:IsForbidden() then
        if activePlates[plate] then ReleaseOverlay(plate) end
        return
    end

    local shouldShow = plate.unit and plate.isCasting
    dprint("RefreshCastOverlay: unit=", plate.unit, "isCasting=", plate.isCasting, "shouldShow=", tostring(shouldShow))
    if shouldShow then
        local ov = activePlates[plate]
        if not ov then
            ov = AcquireOverlay()
            ov.plate = plate
            activePlates[plate] = ov

            -- Anchor exactly the same way as the on-plate cast bar:
            -- TOPLEFT/TOPRIGHT to the health bar's BOTTOMLEFT/BOTTOMRIGHT
            -- so the overlay sits flush below the health bar at the
            -- health bar's full width.
            local anchorTo = plate.health
            if not anchorTo then
                dprint("  bail: no plate.health")
                ReleaseOverlay(plate)
                return
            end
            ov:ClearAllPoints()
            ov:SetPoint("TOPLEFT",  anchorTo, "BOTTOMLEFT",  0, 0)
            ov:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, 0)
            -- Apply size and scale (height, icon size, shield size,
            -- effective scale to match target/cast scale settings)
            ApplyOverlayLayout(ov, plate)

            -- Hide the on-plate cast bar visually so its background and
            -- text don't bleed through the overlay (the on-plate bar is
            -- still functional, just invisible). Restored in ReleaseOverlay.
            if plate.cast then plate.cast:SetAlpha(0) end

            dprint("  anchored flush to plate.health")
            ov:Show()
        end
        ConfigureOverlay(ov, plate)
    else
        if activePlates[plate] then
            ReleaseOverlay(plate)
        end
    end
end

-------------------------------------------------------------------------------
--  Refresh the overlay's bar color for a given plate. Called from the
--  main file's NameplateFrame:ApplyCastColor so the overlay's fill tracks
--  kick-ready / uninterruptible state in lockstep with the on-plate bar.
--  The main bar's apply path runs on:
--    * cast start (UpdateCast)
--    * SPELL_UPDATE_COOLDOWN / SPELL_UPDATE_USABLE (kickWatcher)
--    * A 0.2s poll ticker while any cast is active (fallback for CD expiry)
--  So by hooking into ApplyCastColor we inherit all those refresh paths
--  without duplicating any event wiring here.
-------------------------------------------------------------------------------
function ns.RefreshCastOverlayColor(plate, uninterruptible)
    if not plate then return end
    local ov = activePlates[plate]
    if not ov then return end
    local cfg = FP() or {}
    local baseTint  = cfg.castBar        or { r = 0.70, g = 0.40, b = 0.90 }
    local readyTint = cfg.interruptReady or { r = 0.92, g = 0.35, b = 0.20 }
    local cr, cg, cb
    if ns.ComputeCastBarTint then
        cr, cg, cb = ns.ComputeCastBarTint(readyTint, baseTint)
    else
        cr, cg, cb = baseTint.r, baseTint.g, baseTint.b
    end
    ov.bar:GetStatusBarTexture():SetVertexColor(cr, cg, cb)
    -- Also sync the uninterruptible overlay/shield state. kickProtected is
    -- a secret boolean on Midnight; SetAlphaFromBoolean handles it safely.
    if ov.barOverlay and ov.barOverlay.SetAlphaFromBoolean and ov.shieldFrame.SetAlphaFromBoolean then
        ov.barOverlay:SetAlphaFromBoolean(uninterruptible)
        ov.shieldFrame:SetAlphaFromBoolean(uninterruptible)
    end
end

-------------------------------------------------------------------------------
--  Safety sweep on plate-removal events. NAME_PLATE_UNIT_REMOVED gives us
--  the unit token; we walk active overlays and release any whose plate's
--  unit no longer matches (covers plate recycling races).
-------------------------------------------------------------------------------
local sweepFrame = CreateFrame("Frame")
sweepFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
sweepFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
sweepFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        for plate in pairs(activePlates) do
            if not plate.unit or plate.unit == unit then
                ReleaseOverlay(plate)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        for plate in pairs(activePlates) do
            ReleaseOverlay(plate)
        end
    end
end)

-------------------------------------------------------------------------------
--  Disable hook: when the toggle is flipped off at runtime, sweep all
--  active overlays back to the pool.
-------------------------------------------------------------------------------
function ns.ClearAllCastOverlays()
    for plate in pairs(activePlates) do
        ReleaseOverlay(plate)
    end
end

-------------------------------------------------------------------------------
--  Slash debug: /eui_overlay_count prints active vs pooled counts.
-------------------------------------------------------------------------------
SLASH_EUICASTOVERLAY1 = "/eui_overlay_count"
SlashCmdList["EUICASTOVERLAY"] = function()
    local active = 0
    for _ in pairs(activePlates) do active = active + 1 end
    print(("|cff0cd29fEUI|r CastOverlay: active=%d, pooled=%d"):format(active, #overlayPool))
    for plate, _ in pairs(activePlates) do
        local unit = plate.unit or "nil"
        print(("  - unit=%s casting=%s"):format(unit, tostring(plate.isCasting)))
    end
end

-- Debug toggle: /eui_overlay_debug on|off
SLASH_EUIOVERLAYDEBUG1 = "/eui_overlay_debug"
SlashCmdList["EUIOVERLAYDEBUG"] = function(msg)
    msg = (msg or ""):lower():gsub("%s", "")
    if msg == "on" or msg == "1" or msg == "true" then
        _G._eui_overlay_debug = true
        print("|cff0cd29fEUI|r CastOverlay debug: ON")
    elseif msg == "off" or msg == "0" or msg == "false" then
        _G._eui_overlay_debug = false
        print("|cff0cd29fEUI|r CastOverlay debug: OFF")
    else
        _G._eui_overlay_debug = not _G._eui_overlay_debug
        print("|cff0cd29fEUI|r CastOverlay debug:", _G._eui_overlay_debug and "ON" or "OFF")
    end
end

-- Visual test: /eui_overlay_test pops up a centered overlay with placeholder
-- text/icon so we can verify the visual independent of the cast plumbing.
local _testOverlay
SLASH_EUIOVERLAYTEST1 = "/eui_overlay_test"
SlashCmdList["EUIOVERLAYTEST"] = function()
    if _testOverlay and _testOverlay:IsShown() then
        _testOverlay:Hide()
        print("|cff0cd29fEUI|r CastOverlay test: hidden")
        return
    end
    if not _testOverlay then
        _testOverlay = BuildOverlay()
        _testOverlay:ClearAllPoints()
        _testOverlay:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        _testOverlay.name:SetText("Test Spell")
        _testOverlay.timer:SetText("3.5")
        _testOverlay.icon:SetTexture("Interface\\Icons\\Spell_Holy_HolySmite")
    end
    _testOverlay:Show()
    print("|cff0cd29fEUI|r CastOverlay test: shown at screen center")
end
