-------------------------------------------------------------------------------
-- EUI_QuestTracker_Options.lua
-------------------------------------------------------------------------------
local addonName, ns = ...
local EQT = ns.EQT

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    if not EQT then return end

    local function DB()
        EllesmereUIQuestTrackerDB = EllesmereUIQuestTrackerDB or {}
        return EllesmereUIQuestTrackerDB
    end
    local function Cfg(k)    return DB()[k]  end
    local function Set(k, v) DB()[k] = v     end
    local function Refresh() if EQT.Refresh       then EQT:Refresh()       end end
    local function ApplyPos() if EQT.ApplyPosition then EQT:ApplyPosition() end end

    local function BuildFontDropdown()
        local vals  = { ["__default"] = { text = "Default (Global EUI Font)" } }
        local order = { "__default", "---" }
        local MEDIA = EllesmereUI.MEDIA_PATH
        for _, name in ipairs(EllesmereUI.FONT_ORDER or {}) do
            if name == "---" then
                order[#order+1] = "---"
            else
                local path = (EllesmereUI.FONT_BLIZZARD and EllesmereUI.FONT_BLIZZARD[name])
                    or (MEDIA and EllesmereUI.FONT_FILES and EllesmereUI.FONT_FILES[name]
                        and MEDIA.."fonts\\"..EllesmereUI.FONT_FILES[name])
                local display = (EllesmereUI.FONT_DISPLAY_NAMES and EllesmereUI.FONT_DISPLAY_NAMES[name]) or name
                if path then vals[name] = { text=display, font=path }; order[#order+1] = name end
            end
        end
        if EllesmereUI.AppendSharedMediaFonts then
            EllesmereUI.AppendSharedMediaFonts(vals, order, { keyByName=true })
        end
        return vals, order
    end

    local function MakeCogBtn(rgn, showFn)
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints()
        cogTex:SetTexture(EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
        cogBtn:SetScript("OnClick", function(self) showFn(self) end)
        return cogBtn
    end

    -- Attaches font controls (label + dropdown + cog + swatch) into one half-region of a DualRow.
    -- Call after W:DualRow, pass the _leftRegion or _rightRegion.
    -- The region already has a dropdown built by DualRow; we just add cog+swatch next to it.
    local SHADOW_VALS  = { NONE="None", OUTLINE="Outline", THICK="Thick", THICKOUTLINE="Thick Outline" }
    local SHADOW_ORDER = { "NONE", "OUTLINE", "THICK", "THICKOUTLINE" }

    local function AttachFontControls(rgn, label, sizeKey, sizeDef, sizeMin, sizeMax, colorKey, colorDef, shadowKey)
        -- Cog: font size + shadow
        local cogRows = {
            { type="slider", label="Size", min=sizeMin, max=sizeMax, step=1,
              get=function() return Cfg(sizeKey) or sizeDef end,
              set=function(v) Set(sizeKey, v); Refresh() end },
        }
        if shadowKey then
            local colorKey2 = shadowKey.."Color"
            local offsetKey = shadowKey.."Offset"
            table.insert(cogRows, {
                type="dropdown", label="Shadow",
                values=SHADOW_VALS, order=SHADOW_ORDER,
                get=function() return Cfg(shadowKey) or "NONE" end,
                set=function(v) Set(shadowKey, v); Refresh() end,
            })
            table.insert(cogRows, {
                type="colorpicker", label="Shadow Color", hasAlpha=true,
                get=function()
                    local c = Cfg(colorKey2) or {}
                    return c.r or 0, c.g or 0, c.b or 0, c.a or 0.8
                end,
                set=function(r,g,b,a)
                    local c = Cfg(colorKey2) or {}
                    c.r=r; c.g=g; c.b=b; c.a=(a or 0.8)
                    Set(colorKey2, c); Refresh()
                end,
            })

        end
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = label.." Settings",
            rows = cogRows,
        })
        MakeCogBtn(rgn, cogShow)
        -- Inline color swatch – sits left of the cog
        if colorKey then
            local dr, dg, db = colorDef[1], colorDef[2], colorDef[3]
            local sw = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                function()
                    local c = Cfg(colorKey) or {}
                    return c.r or dr, c.g or dg, c.b or db
                end,
                function(r,g,b)
                    local c = Cfg(colorKey) or {}
                    c.r=r; c.g=g; c.b=b; Set(colorKey,c); Refresh()
                end,
                false, 20)
            sw:SetPoint("RIGHT", rgn._lastInline, "LEFT", -8, 0)
            sw:SetScript("OnEnter", function(s) EllesmereUI.ShowWidgetTooltip(s, label.." Color") end)
            sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            rgn._lastInline = sw
        end
    end

    local function GetColor(key, dr, dg, db)
        local c = Cfg(key)
        if not c then Set(key, {r=dr,g=dg,b=db}); c = Cfg(key) end
        return c.r, c.g, c.b
    end

    local function BuildPage(_, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        local fontVals, fontOrder = BuildFontDropdown()

        -- ── GENERAL ─────────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "GENERAL", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Quest Tracker",
              getValue=function() return Cfg("enabled") ~= false end,
              setValue=function(v)
                  Set("enabled", v)
                  local f = EQT and EQT.frame
                  if f then if v then f:Show(); Refresh() else f:Hide() end end
                  if EQT.ApplyBlizzardTrackerVisibility then EQT.ApplyBlizzardTrackerVisibility() end
              end },
            { type="toggle", text="Lock Position",
              getValue=function() return Cfg("locked") or false end,
              setValue=function(v) Set("locked", v) end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Zone Quests",
              getValue=function() return Cfg("showZoneQuests") ~= false end,
              setValue=function(v) Set("showZoneQuests", v); Refresh() end },
            { type="toggle", text="Show World Quests",
              getValue=function() return Cfg("showWorldQuests") ~= false end,
              setValue=function(v) Set("showWorldQuests", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Quest Items",
              getValue=function() return Cfg("showQuestItems") ~= false end,
              setValue=function(v) Set("showQuestItems", v); Refresh() end },
            { type="toggle", text="Show Top Line",
              getValue=function() return Cfg("showTopLine") ~= false end,
              setValue=function(v)
                  Set("showTopLine", v)
                  local f = EQT and EQT.frame
                  if f and f.topLine then
                      if v then f.topLine:Show() else f.topLine:Hide() end
                  end
              end })
        -- Cog on Show Quest Items for item size
        do
            local rgn = row._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Quest Item Settings",
                rows = {
                    { type="slider", label="Item Size", min=16, max=36, step=2,
                      get=function() return Cfg("questItemSize") or 22 end,
                      set=function(v) Set("questItemSize", v); Refresh() end },
                },
            })
            MakeCogBtn(rgn, cogShow)
        end
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Auto Accept Quests",
              getValue=function() return Cfg("autoAccept") or false end,
              setValue=function(v) Set("autoAccept", v) end },
            { type="toggle", text="Auto Turn In Quests",
              getValue=function() return Cfg("autoTurnIn") or false end,
              setValue=function(v) Set("autoTurnIn", v) end })
        do
            local rgn = row._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Auto Turn In Settings",
                rows = {
                    { type="toggle", label="Hold Shift to Skip",
                      get=function() return Cfg("autoTurnInShiftSkip") ~= false end,
                      set=function(v) Set("autoTurnInShiftSkip", v) end },
                },
            })
            MakeCogBtn(rgn, cogShow)
        end
        y = y - h

        -- Quest Item Hotkey
        do
            local ROW_H  = 50
            local SIDE_PAD = 16
            local KB_W, KB_H = 140, 30

            local kbFrame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - (EllesmereUI.CONTENT_PAD or 10) * 2
            kbFrame:SetSize(totalW, ROW_H)
            kbFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD or 10, y)
            if EllesmereUI.RowBg then EllesmereUI.RowBg(kbFrame, parent) end

            local label = kbFrame:CreateFontString(nil, "OVERLAY")
            if EllesmereUI.MakeFont then
                label = EllesmereUI.MakeFont(kbFrame, 14, nil, 1, 1, 1)
            else
                label:SetFont("Fonts\\FRIZQT__.TTF", 14)
                label:SetTextColor(1, 1, 1)
            end
            label:SetPoint("LEFT", kbFrame, "LEFT", SIDE_PAD, 0)
            label:SetText("Quest Item Hotkey")

            local kbBtn = CreateFrame("Button", nil, kbFrame)
            kbBtn:SetSize(KB_W, KB_H)
            kbBtn:SetPoint("RIGHT", kbFrame, "RIGHT", -SIDE_PAD, 0)
            kbBtn:SetFrameLevel(kbFrame:GetFrameLevel() + 2)
            kbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            -- Style matching EllesmereUI dropdowns
            local kbBg = kbBtn:CreateTexture(nil, "BACKGROUND")
            kbBg:SetAllPoints()
            kbBg:SetColorTexture(EllesmereUI.DD_BG_R or 0.08, EllesmereUI.DD_BG_G or 0.08, EllesmereUI.DD_BG_B or 0.08, EllesmereUI.DD_BG_A or 0.9)
            if EllesmereUI.MakeBorder then
                EllesmereUI.MakeBorder(kbBtn, 1, 1, 1, EllesmereUI.DD_BRD_A or 0.15)
            end

            local kbLbl = kbBtn:CreateFontString(nil, "OVERLAY")
            kbLbl:SetFont("Fonts\\FRIZQT__.TTF", 13)
            kbLbl:SetTextColor(1, 1, 1)
            kbLbl:SetPoint("CENTER")

            local function FormatKey(key)
                if not key or key == "" then return "Not Bound" end
                local parts = {}
                for mod in key:gmatch("(%u+)%-") do
                    parts[#parts+1] = mod:sub(1,1)..mod:sub(2):lower()
                end
                parts[#parts+1] = key:match("[^%-]+$") or key
                return table.concat(parts, " + ")
            end

            local function RefreshLabel()
                kbLbl:SetText(FormatKey(Cfg("questItemHotkey")))
            end
            RefreshLabel()

            local listening = false

            kbBtn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    listening = false
                    self:EnableKeyboard(false)
                    Set("questItemHotkey", nil)
                    if EQT and EQT.ApplyQuestItemHotkey then EQT.ApplyQuestItemHotkey() end
                    RefreshLabel()
                    return
                end
                if listening then return end
                listening = true
                kbLbl:SetText("Press a key...")
                kbBtn:EnableKeyboard(true)
            end)

            kbBtn:SetScript("OnKeyDown", function(self, key)
                if not listening then self:SetPropagateKeyboardInput(true); return end
                if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
                   or key == "LALT" or key == "RALT" then
                    self:SetPropagateKeyboardInput(true); return
                end
                self:SetPropagateKeyboardInput(false)
                if key == "ESCAPE" then
                    listening = false; self:EnableKeyboard(false); RefreshLabel(); return
                end
                local mods = ""
                if IsShiftKeyDown()   then mods = mods.."SHIFT-"   end
                if IsControlKeyDown() then mods = mods.."CTRL-"    end
                if IsAltKeyDown()     then mods = mods.."ALT-"     end
                local fullKey = mods..key
                Set("questItemHotkey", fullKey)
                if EQT and EQT.ApplyQuestItemHotkey then EQT.ApplyQuestItemHotkey() end
                listening = false; self:EnableKeyboard(false); RefreshLabel()
            end)

            kbBtn:SetScript("OnEnter", function(self)
                if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "Left-click to set key\nRight-click to clear")
                end
            end)
            kbBtn:SetScript("OnLeave", function()
                if EllesmereUI and EllesmereUI.HideWidgetTooltip then
                    EllesmereUI.HideWidgetTooltip()
                end
            end)

            h = ROW_H
        end
        y = y - h

        y = y - 10

        -- ── FONT SETTINGS ────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "FONT SETTINGS", y); y = y - h

        -- Row 1: Section Headers (left) | Quest Titles (right)
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Section Headers",
              values=fontVals, order=fontOrder,
              getValue=function() local v=Cfg("secFont"); return (v and v~="") and v or "__default" end,
              setValue=function(v) Set("secFont",(v=="__default") and nil or v); Refresh() end },
            { type="dropdown", text="Quest Titles",
              values=fontVals, order=fontOrder,
              getValue=function() local v=Cfg("titleFont"); return (v and v~="") and v or "__default" end,
              setValue=function(v) Set("titleFont",(v=="__default") and nil or v); Refresh() end })
        AttachFontControls(row._leftRegion,  "Section Headers", "secFontSize",   8,  6, 24, "secColor",   {0.047,0.824,0.624}, "secShadow")
        AttachFontControls(row._rightRegion, "Quest Titles",    "titleFontSize", 11, 8, 24, "titleColor", {1.0,  0.85, 0.1  }, "titleShadow")
        y = y - h

        -- Row 2: Objectives (left) | Header "OBJECTIVES" text (right)
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Objectives",
              values=fontVals, order=fontOrder,
              getValue=function() local v=Cfg("objFont"); return (v and v~="") and v or "__default" end,
              setValue=function(v) Set("objFont",(v=="__default") and nil or v); Refresh() end },
            { type="dropdown", text="Header Text",
              values=fontVals, order=fontOrder,
              getValue=function() local v=Cfg("hdrFont"); return (v and v~="") and v or "__default" end,
              setValue=function(v) Set("hdrFont",(v=="__default") and nil or v); Refresh() end })
        AttachFontControls(row._leftRegion,  "Objectives",   "objFontSize", 10, 7, 24, "objColor", {0.72,0.72,0.72}, "objShadow")
        AttachFontControls(row._rightRegion, "Header Text",  "hdrFontSize", 11, 8, 24, "hdrColor", {1.0, 1.0,  1.0 }, "hdrShadow")
        y = y - h

        y = y - 10

        -- ── SIZE & BACKGROUND ────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "SIZE & BACKGROUND", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="slider", text="Width", min=160, max=400, step=5,
              getValue=function() return Cfg("width") or 220 end,
              setValue=function(v)
                  Set("width", v)
                  if EQT.frame then EQT.frame:SetWidth(v) end
                  Refresh()
              end },
            { type="slider", text="Background Opacity", min=0, max=100, step=5,
              getValue=function() return math.floor(((Cfg("bgAlpha") or 0.35)*100)+0.5) end,
              setValue=function(v)
                  Set("bgAlpha", v/100)
                  if EQT.frame and EQT.frame.bg then EQT.frame.bg:SetColorTexture(0,0,0,v/100) end
              end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Fixed Height",
              getValue=function() return Cfg("fixedHeight") or false end,
              setValue=function(v) Set("fixedHeight", v); Refresh() end },
            { type="label", text="" })
        do
            local rgn = row._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Fixed Height",
                rows = {
                    { type="slider", label="Height", min=80, max=800, step=10,
                      get=function() return Cfg("fixedHeightValue") or 300 end,
                      set=function(v) Set("fixedHeightValue", v); Refresh() end },
                },
            })
            MakeCogBtn(rgn, cogShow)
        end
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="slider", text="Max Height",
              min=100, max=800, step=10,
              getValue=function() return Cfg("maxHeight") or 600 end,
              setValue=function(v) Set("maxHeight", v); Refresh() end },
            { type="label", text="" })
        y = y - h

        y = y - 10

        -- ── POSITION ─────────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "POSITION", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="button", text="Reset Position",
              onClick=function() Set("xPos",nil); Set("yPos",nil); ApplyPos() end },
            { type="label", text="" })
        y = y - h

        return math.abs(y)
    end

    _G._EBS_BuildQuestTrackerPage = BuildPage
    _G._EBS_ResetQuestTracker = function()
        EllesmereUIQuestTrackerDB = nil
        if EQT and EQT.Refresh then EQT:Refresh() end
    end
end)
