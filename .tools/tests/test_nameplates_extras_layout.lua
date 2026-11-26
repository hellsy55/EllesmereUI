local cvars = { "nameplateMotionSpeed", "nameplateTopInset", "nameplateBottomInset" }
local labels = { "Stacking Speed", "Top Screen Inset", "Bottom Screen Inset" }
local clickable = "Clickable Cast Bar"
local tracked = { [clickable] = true }
for _, label in ipairs(labels) do tracked[label] = true end

local function noop() end
local function blank() return { type = "label", text = "" } end
local function empty(cfg)
    return cfg.type == "spacer" or (cfg.type == "label" and (cfg.text or "") == "")
end

local function check(buildModule)
    for mask = 0, 7 do
        local available, expected = {}, {}
        for i, name in ipairs(cvars) do
            if math.floor(mask / 2^(i - 1)) % 2 == 1 then
                available[name] = true
                expected[#expected + 1] = labels[i]
            end
        end

        local sections, group, section = {}, {}
        local hasClickable
        local function fail(message)
            error(("Nameplates Extras [%s]: %s"):format(table.concat(
                { tostring(available[cvars[1]] == true), tostring(available[cvars[2]] == true),
                  tostring(available[cvars[3]] == true) }, "/"), message), 0)
        end
        local function row() return { _leftRegion = {}, _rightRegion = {} }, 50 end
        local widgets = { Spacer = row }
        function widgets:SectionHeader(_, name)
            section = { name = name }
            sections[#sections + 1] = section
            return row()
        end
        function widgets:DualRow(_, _, left, right)
            local entry = { left = left, right = right, section = section, index = #section + 1 }
            section[entry.index] = entry
            local l, r = left and left.text, right and right.text
            if l == clickable or r == clickable then hasClickable = true end
            if tracked[l] or tracked[r] then group[#group + 1] = entry end
            return row()
        end

        local ns = { _NPO_OptEnv = {
            DBVal = noop, defaults = {}, SearchWords = noop,
            SECTION_ENEMY_NP = "SPACING", SECTION_AURA = "AURAS", SECTION_MISC = "EXTRAS",
        } }
        EllesmereUI = {
            _ModuleNS = { EllesmereUINameplates = ns }, _Pool = {}, _prebuilding = true,
            Widgets = widgets, ClearContentHeader = noop, BuildInlineCog = noop, BlankRowCfg = blank,
            GlowOptions = {
                DropdownSpec = function(_, label) return { type = "dropdown", text = label } end,
                AttachInline = noop,
            },
        }
        C_CVar = { GetCVarInfo = function(name) return available[name] end,
                   GetCVarDefault = function() return "0.1" end }
        UnitClass = function() return "Mage", "MAGE" end
        C_SpecializationInfo = { GetSpecialization = noop }
        buildModule()
        ns.NPO_BuildGeneralPage("Extras", {}, 0)

        -- The current page has no clickable toggle. If it returns, it leads
        -- the same group as the available sliders.
        if hasClickable then table.insert(expected, 1, clickable) end
        local expectedRows = math.ceil(#expected / 2)
        for i = 1, math.min(#group, expectedRows) do
            local entry = group[i]
            local left, right = expected[2*i - 1], expected[2*i]
            if i > 1 and (entry.section ~= group[1].section or entry.index ~= group[i - 1].index + 1) then
                fail("the conditional rows must be consecutive within one section")
            end
            if not entry.left or entry.left.text ~= left or not entry.right
                    or (right and entry.right.text ~= right) or (not right and not empty(entry.right)) then
                fail(("%s row %d: expected %s | %s, got %s | %s"):format(
                    entry.section.name, entry.index, left, right or "<blank>",
                    entry.left and entry.left.text or "<missing>",
                    entry.right and not empty(entry.right) and entry.right.text or "<blank or missing>"))
            end
        end
        if #group ~= expectedRows then
            fail(("expected %d packed rows, got %d"):format(expectedRows, #group))
        end

        for _, rows in ipairs(sections) do
            if rows.name == "SPACING" or rows.name == "EXTRAS" then
                for i, entry in ipairs(rows) do
                    if not entry.left or empty(entry.left) then fail(rows.name .. ": empty left slot in row " .. i) end
                    -- DualRow gives the left control full width when the right config is nil.
                    if entry.right and empty(entry.right) and i < #rows then
                        fail(rows.name .. ": empty right slot before the last row (row " .. i .. ")")
                    end
                end
            end
        end
    end
end

local function regressionFixture(splitFirstRow)
    return function()
        local ns = EllesmereUI._ModuleNS.EllesmereUINameplates
        local widgets = EllesmereUI.Widgets
        ns.NPO_BuildGeneralPage = function(_, parent, y)
            widgets:SectionHeader(parent, "EXTRAS", y)
            local clickableCfg = { type = "toggle", text = clickable }
            local slots = {}
            if splitFirstRow then
                widgets:DualRow(parent, y, clickableCfg, blank())
            else
                slots[1] = clickableCfg
            end
            for i, name in ipairs(cvars) do
                if C_CVar.GetCVarInfo(name) then
                    slots[#slots + 1] = { type = "slider", text = labels[i] }
                end
            end
            for i = 1, #slots, 2 do
                widgets:DualRow(parent, y, slots[i], slots[i + 1] or blank())
            end
        end
    end
end

local accepted, failure = pcall(check, regressionFixture(true))
assert(not accepted and failure:find("expected Clickable Cast Bar | Stacking Speed", 1, true), failure)
check(regressionFixture(false))
print("Nameplates Extras fixture: split row rejected, packed rows passed all 8 combinations")
