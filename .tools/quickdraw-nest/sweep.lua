-- Nest-arming sweep for the block layouts.
--
-- Asks the one question the arming gates exist to answer: can a straight reach
-- from a parent entry to each of its children be made without ever crossing
-- ground the claim does not hold? A reach that leaves the claim's regions
-- part-way disarms it, and the nest closes in the user's hand.
--
-- Ground inside ANOTHER claim's parent cell does not count against a reach:
-- handing the claim over there is deliberate (see ParentHoles).
--
-- Run it as:  python3 extract.py && lua5.1 sweep.lua
--
-- It also reports the worst region count any single claim came to, which is
-- what REGION_MAX has to cover -- the sweep the constant's own comment in
-- EllesmereUIQuickdraw.lua refers to. Raising MAX_SLOTS or MAX_CHILDREN means
-- running this again and re-deriving that number.
local min, max, abs, floor, ceil, sqrt = math.min, math.max, math.abs,
    math.floor, math.ceil, math.sqrt
local MAX_SLOTS, MAX_CHILDREN, MAX_CHILD_ROWS, REGION_MAX = 12, 8, 4, 9
local NEST_BAND_DEFAULT = 40
local PaletteView = {}
local DEFAULTS = { iconSize = 40, fanGap = 10, nestScale = 0.8,
    nestBand = NEST_BAND_DEFAULT, gridNestStyle = "PERIMETER",
    gridAutoColumns = true, gridColumns = 4 }
function PaletteView:P() return self.profile end
function PaletteView:Geom() return 0, self.profile.iconSize or 40 end
function PaletteView:LayoutMode() return self.mode or "GRID" end
function PaletteView:FanHoriz() return self.horiz ~= false end
function PaletteView:IsGrid() return self:LayoutMode() == "GRID" end
function PaletteView:Pitch()
    local p = self:P(); local _, i = self:Geom(); return i + ((p and p.fanGap) or 10)
end
local env = setmetatable({ min = min, max = max, abs = abs, floor = floor,
    ceil = ceil, sqrt = sqrt, tsort = table.sort, pi = math.pi,
    cos = math.cos, sin = math.sin, atan2 = math.atan2, sqrt = math.sqrt,
    MAX_SLOTS = MAX_SLOTS, MAX_CHILDREN = MAX_CHILDREN,
    MAX_CHILD_ROWS = MAX_CHILD_ROWS, NEST_BAND_DEFAULT = NEST_BAND_DEFAULT,
    PaletteView = PaletteView }, { __index = _G })
local chunk = assert(loadfile((arg and arg[0] or "")
    :gsub("sweep%.lua$", "") .. "geom_extract.lua")); setfenv(chunk, env); chunk()

local function Inside(regions, x, y, upTo)
    for r = 1, min(#regions, upTo or #regions) do
        local b = regions[r]
        if abs(x - b.x) <= b.hw and abs(y - b.y) <= b.hh then return true end
    end
end
-- A reach is broken only where it crosses ground belonging to NOBODY. Ground
-- inside another claim's own parent cell is a deliberate hand-over (ParentHoles),
-- not a defect, so it does not count against the claim being reached for.
local function Broken(c, upTo, claims)
    local bad = 0
    for j = 1, c.n do
        local t0 = c.cells[j]
        for s = 0, 40 do
            local t = s / 40
            local x = c.parentBox.x + (t0.x - c.parentBox.x) * t
            local y = c.parentBox.y + (t0.y - c.parentBox.y) * t
            if not Inside(c.regions, x, y, upTo) then
                local handover = false
                for i = 1, #claims do
                    local o = claims[i].parentBox
                    if claims[i] ~= c and abs(x - o.x) <= o.hw
                       and abs(y - o.y) <= o.hh then handover = true break end
                end
                if not handover then bad = bad + 1 break end
            end
        end
    end
    return bad
end

local worstRegions, cases, brokenCases, droppedCases = 0, 0, 0, 0
local tally, detail = {}, {}
local function Case(mode, style, horiz, shown, nesting, childN, pinned)
    local p = {}
    for k, v in pairs(DEFAULTS) do p[k] = v end
    p.gridNestStyle = style
    if pinned then p.gridAutoColumns, p.gridColumns = false, pinned end
    local view = setmetatable({ profile = p, mode = mode, horiz = horiz,
        shownCount = shown, slotCount = shown }, { __index = PaletteView })
    local claims = {}
    for _, parent in ipairs(nesting) do
        claims[#claims + 1] = { parent = parent, n = childN }
    end
    view:CellChildGeom(claims, shown)
    cases = cases + 1
    local broke, dropped = false, false
    for i = 1, #claims do
        local c = claims[i]
        worstRegions = max(worstRegions, #c.regions)
        if #c.regions > REGION_MAX then dropped = true end
        -- Reaches are judged on the regions that actually survive the push:
        -- PushPalette writes only REGION_MAX of them.
        if Broken(c, REGION_MAX, claims) > 0 then broke = true end
    end
    if broke then
        brokenCases = brokenCases + 1
        local key = style .. (dropped and " over-budget" or " within-budget")
        tally[key] = (tally[key] or 0) + 1
        local k2 = ("%s shown=%d nests=%d childN=%d"):format(style, shown, #nesting, childN)
        detail[k2] = (detail[k2] or 0) + 1
    end
    if dropped then droppedCases = droppedCases + 1 end
end

local function Subsets(shown, pick)
    -- every arrangement of `pick` nesting entries among `shown`
    local out = {}
    local function rec(start, acc)
        if #acc == pick then out[#out + 1] = { unpack(acc) } return end
        for i = start, shown do
            acc[#acc + 1] = i; rec(i + 1, acc); acc[#acc] = nil
        end
    end
    rec(1, {})
    return out
end

for _, style in ipairs({ "PERIMETER", "HALO" }) do
    for _, mode in ipairs({ "GRID", "FAN" }) do
        for shown = 2, 12 do
            for pick = 1, min(shown, 4) do
                for _, sub in ipairs(Subsets(shown, pick)) do
                    for _, childN in ipairs({ 1, 2, 3, 5, 8, 12 }) do
                        for _, pinned in ipairs({ false, 3, 4, 6 }) do
                            Case(mode, style, true, shown, sub, childN,
                                 pinned or nil)
                        end
                    end
                end
            end
        end
    end
end
-- every entry nesting, the case the REGION_MAX comment calls out
for shown = 2, 12 do
    local all = {}
    for i = 1, shown do all[i] = i end
    for _, childN in ipairs({ 2, 8, 12 }) do
        Case("GRID", "PERIMETER", true, shown, all, childN)
        Case("GRID", "HALO", true, shown, all, childN)
        Case("FAN", "PERIMETER", true, shown, all, childN)
        Case("FAN", "PERIMETER", false, shown, all, childN)
    end
end

for k, v in pairs(tally) do print(("  %-28s %d"):format(k, v)) end
local rows = {}
for k, v in pairs(detail) do rows[#rows+1] = { k, v } end
table.sort(rows, function(a,b) return a[2] > b[2] end)
for i = 1, math.min(#rows, 10) do print(("    %-40s %d"):format(rows[i][1], rows[i][2])) end
print(("cases=%d  worst region count=%d (REGION_MAX=%d)  over budget=%d  broken reaches=%d")
    :format(cases, worstRegions, REGION_MAX, droppedCases, brokenCases))
