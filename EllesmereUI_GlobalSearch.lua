-------------------------------------------------------------------------------
--  EllesmereUI_GlobalSearch.lua
--  Unified fuzzy search across every registered EllesmereUI sub-addon's
--  options.
--
--  Optional / modular by design: TagOptionRow and SectionHeader in
--  EllesmereUI_Widgets.lua call EllesmereUI._RegisterSearchEntry only if it
--  exists, so this file can be added (or removed) independently of the rest
--  of the addon with no other changes required.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Index storage
-------------------------------------------------------------------------------
local _searchIndex = {}
local _seenKeys = {}

-- Registered by TagOptionRow / SectionHeader as each option row / section
-- header is built during normal navigation, and by the one-time pre-build
-- pass below for pages nobody has opened yet this session.
function EllesmereUI._RegisterSearchEntry(label, labelLoc, tooltip, moduleFolder, page, sectionName, selectorSetter, selectorKey)
    -- Composite labels (DualRow/TripleRow with an empty slot) can come in as
    -- whitespace only (e.g. a single joining space with nothing on either
    -- side) -- trim before the emptiness check so those don't register as
    -- inert, unmatchable junk entries.
    if label then label = label:match("^%s*(.-)%s*$") end
    if not label or label == "" or not moduleFolder or not page then return end
    local key = moduleFolder .. "\1" .. page .. "\1" .. label
    if _seenKeys[key] then return end
    _seenKeys[key] = true
    _searchIndex[#_searchIndex + 1] = {
        label = label,
        labelLoc = labelLoc,
        tooltip = tooltip,
        module = moduleFolder,
        section = sectionName,
        page = page,
        -- Present only for entries built while a page's own internal
        -- selector (CDM bar / action bar / unit dropdown) was set to a
        -- specific value -- lets JumpToResult restore that exact selection
        -- before navigating, so a setting that only exists under one
        -- selector value (e.g. HoverCast-only options) is actually there to
        -- find and highlight instead of silently not matching.
        selectorSetter = selectorSetter,
        selectorKey = selectorKey,
    }
end

-------------------------------------------------------------------------------
--  Fuzzy scoring: subsequence match with a substring-match boost. Cheap
--  enough to run per keystroke over the whole index -- no Levenshtein needed.
-------------------------------------------------------------------------------
local function FuzzyScore(haystack, needle)
    local subIdx = haystack:find(needle, 1, true)
    if subIdx then
        return 10000 - subIdx -- exact substring always outranks a subsequence match
    end
    local hLen, nLen = #haystack, #needle
    local hi, ni = 1, 1
    local firstMatch, lastMatch = nil, nil
    local consecutiveRun = 0
    local score = 0
    while hi <= hLen and ni <= nLen do
        if haystack:byte(hi) == needle:byte(ni) then
            if not firstMatch then firstMatch = hi end
            lastMatch = hi
            consecutiveRun = consecutiveRun + 1
            score = score + consecutiveRun -- reward tight clustering (a run of k scores 1+2+...+k)
            ni = ni + 1
        else
            consecutiveRun = 0
        end
        hi = hi + 1
    end
    if ni <= nLen then return nil end -- not every needle char found in order

    -- Reject overly sparse matches. Without this, a long enough haystack
    -- makes almost any needle findable as SOME subsequence somewhere in it
    -- (e.g. "interrupt" spuriously matching an unrelated 50-character
    -- concatenated row label) -- that's noise, not a real fuzzy match.
    -- Short needles (abbreviations like "aoc") get more slack via the +6.
    local span = lastMatch - firstMatch + 1
    if span > nLen * 2 + 6 then return nil end

    return (score * 100) / span -- density: tighter matches for the same needle score higher
end

local function ScoreEntry(entry, needle)
    local best = nil
    -- Score each field explicitly rather than looping a { } constructor with
    -- ipairs: entry.labelLoc is nil on English clients (and for any entry
    -- whose localized text matches the English key), which leaves a hole at
    -- index 2 -- ipairs stops at the first nil, so entry.tooltip (index 3)
    -- would never be reached and tooltip search would be silently dead in
    -- the common case. type(f) == "string" also guards against a function-
    -- typed tooltip (ShowWidgetTooltip supports dynamic tooltip functions,
    -- re-evaluated on each show) which has no :lower() method.
    local function Consider(f)
        if type(f) == "string" and f ~= "" then
            local s = FuzzyScore(f:lower(), needle)
            if s and (not best or s > best) then best = s end
        end
    end
    Consider(entry.label)
    Consider(entry.labelLoc)
    Consider(entry.tooltip)
    return best
end

-------------------------------------------------------------------------------
--  Coarse (whole-page) candidates: "Damage Meters -> Spell History" as a
--  single jump target, not just its individual options. Built directly from
--  the module registry's static config (title/pages), so unlike the
--  fine-grained index above it needs no build pass or navigation to exist --
--  page/module identity is known the moment a sub-addon registers, before
--  any of its widgets are ever constructed.
-------------------------------------------------------------------------------
local _coarseCandidates

local function BuildCoarseCandidates()
    _coarseCandidates = {}
    for folder, config in pairs(EllesmereUI._modules or {}) do
        if config.pages then
            local moduleLabel = EllesmereUI.L(config.title or folder)
            for _, page in ipairs(config.pages) do
                local pageLabel = EllesmereUI.L(page)
                _coarseCandidates[#_coarseCandidates + 1] = {
                    kind = "page",
                    -- Combined haystack so a query spanning both module and
                    -- page words (e.g. "damage spell") still matches, not
                    -- just one half of it.
                    label = moduleLabel .. " " .. pageLabel,
                    displayLabel = pageLabel,
                    moduleLabel = moduleLabel,
                    module = folder,
                    page = page,
                }
            end
        end
    end
end

local function SearchIndex(query, maxResults)
    maxResults = maxResults or 30
    local needle = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if needle == "" then return {} end
    if not _coarseCandidates then BuildCoarseCandidates() end
    local scored = {}
    for _, entry in ipairs(_searchIndex) do
        local score = ScoreEntry(entry, needle)
        if score then
            scored[#scored + 1] = { entry = entry, score = score }
        end
    end
    for _, entry in ipairs(_coarseCandidates) do
        local score = ScoreEntry(entry, needle)
        if score then
            scored[#scored + 1] = { entry = entry, score = score }
        end
    end
    table.sort(scored, function(a, b) return a.score > b.score end)
    local out = {}
    for i = 1, math.min(maxResults, #scored) do out[i] = scored[i].entry end
    return out
end

-------------------------------------------------------------------------------
--  One-time, staggered, off-screen pre-build pass.
--  Populates the index for pages the user hasn't opened yet this session,
--  without ever showing that UI. The hidden root frame is never shown, so
--  nothing built under it ever renders or runs OnUpdate scripts -- WoW gates
--  both on the frame's (and its ancestors') shown state. Rebuilt fresh every
--  login (no SavedVariables caching), so the index can never go stale
--  relative to the actual option code.
-------------------------------------------------------------------------------
local _prebuildDone = false
local _hiddenParent

-- The main panel's content-header chrome is ONE real, shared frame -- not
-- scoped to whatever parent/wrapper a buildPage happens to be given -- and
-- several sub-addons call these directly from buildPage. For real navigation
-- that's fine (there's only ever one visible page), but during a hidden
-- pre-build it would overwrite whatever header the user is actually looking
-- at. These methods are also nil outright until the panel's first Show()
-- (they're defined inside CreateMainFrame), which a plain guard clause
-- inside them can't help with -- so stub them out here for the duration of
-- each pre-build call instead, then restore whatever was there before
-- (nil or the real function).
local _CONTENT_HEADER_METHODS = {
    "SetContentHeader", "UpdateContentHeaderHeight", "SetContentHeaderHeightSilent",
    "ClearContentHeader", "HideContentHeader",
}

-- A single hidden build of one (folder, page). Optionally switches the
-- page's own internal selector (CDM bar / action bar key / unit) to
-- selectorKey first via selectorSetter, so options gated behind a
-- non-default selector value get indexed too -- otherwise they'd only ever
-- be searchable after the player manually visits that selector value once.
local function PrebuildOnce(config, folder, page, selectorSetter, selectorKey)
    if not _hiddenParent then
        _hiddenParent = CreateFrame("Frame", nil, UIParent)
        _hiddenParent:Hide()
    end
    if selectorSetter and selectorKey then selectorSetter(selectorKey) end

    local wrapper = CreateFrame("Frame", nil, _hiddenParent)
    wrapper:SetSize(1030, 4000)
    EllesmereUI._buildingModule = folder
    EllesmereUI._buildingPage = page
    EllesmereUI._prebuilding = true

    -- Isolate the shared widget-refresh registry so this off-screen build's
    -- widgets can never leak their refresh closures into whatever page the
    -- user is actually looking at (or into that page's cache snapshot).
    local refreshSnap = EllesmereUI._SnapshotAndClearWidgetRefreshList and EllesmereUI._SnapshotAndClearWidgetRefreshList()
    -- buildPage functions call some live game APIs (currency lists, class
    -- info) directly during construction, not only inside getValue closures.
    -- pcall so one module's edge case can never block indexing the rest; any
    -- such page simply falls back to being indexed by live navigation instead.
    pcall(config.buildPage, page, wrapper, -6)
    if refreshSnap then EllesmereUI._RestoreWidgetRefreshList(refreshSnap) end

    -- Some buildPage implementations register cleanup (event listeners, etc.)
    -- via parent:HookScript("OnHide", ...), expecting it to fire once the
    -- user navigates away. Hide the wrapper on the chance that helps -- but
    -- don't rely on it: a frame that's never been effectively visible (its
    -- ancestor, _hiddenParent, was hidden before wrapper was ever shown) may
    -- not fire OnHide just because wrapper:Hide() is called on it. Any
    -- buildPage that registers session-long listeners (event frames, etc.)
    -- must guard their creation with EllesmereUI._prebuilding itself rather
    -- than depend on this to clean them up.
    wrapper:Hide()

    EllesmereUI._buildingModule = nil
    EllesmereUI._buildingPage = nil
    EllesmereUI._buildingSelector = nil
    EllesmereUI._prebuilding = nil
end

local function PrebuildModulePage(config, folder, page)
    if not config.buildPage then return end
    -- Re-check (not just at job-list-build time): the staggered pass runs
    -- over several seconds, so the player may have visited and cached this
    -- exact page live in the meantime -- rebuilding it hidden would be a
    -- redundant, wasted build.
    local cacheKey = folder .. "::" .. page
    if EllesmereUI._pageCache and EllesmereUI._pageCache[cacheKey] then return end

    local savedMethods = {}
    for _, name in ipairs(_CONTENT_HEADER_METHODS) do
        savedMethods[name] = EllesmereUI[name]
        EllesmereUI[name] = function() end
    end

    -- Pages whose content depends on an internal selector (CDM bar type,
    -- action bar key, unit) can expose getPrebuildVariants to have this pass
    -- build once per selector value instead of just once at whatever value
    -- happens to be default -- otherwise settings gated behind a non-default
    -- value are never indexed until the player picks that value themselves.
    local variants = config.getPrebuildVariants and config.getPrebuildVariants(page)
    if variants and variants.keys and #variants.keys > 0 then
        for _, key in ipairs(variants.keys) do
            PrebuildOnce(config, folder, page, variants.setter, key)
        end
        -- Restore whatever the player actually had selected so a later live
        -- visit to this page isn't left showing the last-built variant.
        if variants.setter and variants.currentKey then
            variants.setter(variants.currentKey)
        end
    else
        PrebuildOnce(config, folder, page)
    end

    for _, name in ipairs(_CONTENT_HEADER_METHODS) do
        EllesmereUI[name] = savedMethods[name]
    end
end

local function RunPrebuildPass()
    if _prebuildDone then return end
    _prebuildDone = true

    local jobs = {}
    for folder, config in pairs(EllesmereUI._modules or {}) do
        if config.pages then
            for _, page in ipairs(config.pages) do
                -- Already indexed by live navigation -- skip it. Rebuilding it
                -- hidden would be redundant, and would also reassign whatever
                -- module-global closures (header builders, etc.) that page's
                -- buildPage captures to hidden-build versions that a later
                -- cache-restore could pick up instead of the live ones.
                local cacheKey = folder .. "::" .. page
                if not (EllesmereUI._pageCache and EllesmereUI._pageCache[cacheKey]) then
                    jobs[#jobs + 1] = { folder = folder, page = page, config = config }
                end
            end
        end
    end

    local i = 0
    local function StepJob()
        i = i + 1
        local job = jobs[i]
        if not job then return end
        PrebuildModulePage(job.config, job.folder, job.page)
        if jobs[i + 1] then
            C_Timer.After(0.05, StepJob)
        end
    end
    if jobs[1] then StepJob() end
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        -- Delay a few seconds past login so other addons/systems settle
        -- before we start building hidden option pages.
        C_Timer.After(5, RunPrebuildPass)
    end)
end

-------------------------------------------------------------------------------
--  Persistent search entry point + results popup.
--
--  Reuses the existing always-visible sidebar search box (placeholder
--  "Search Features...", EllesmereUI._sidebarSearchBox) as the entry point
--  rather than adding a new button/box of our own -- it's already the
--  natural, always-visible "search" affordance in the panel. We only add a
--  results popup beneath it via HookScript, so the box's existing behavior
--  (filtering the sidebar addon/page list) is untouched.
-------------------------------------------------------------------------------
local _searchUIBuilt = false
local popup, resultRows

local RESULT_ROW_H = 34
local MAX_VISIBLE_RESULTS = 12

local function GetModuleDisplayName(folder)
    local config = EllesmereUI._modules and EllesmereUI._modules[folder]
    if config and config.title then return EllesmereUI.L(config.title) end
    if EllesmereUI.ADDON_ROSTER then
        for _, entry in ipairs(EllesmereUI.ADDON_ROSTER) do
            if entry.folder == folder then return EllesmereUI.L(entry.display) end
        end
    end
    return folder
end

-- Category lookup: reverse-map each module folder to its ADDON_GROUPS label
-- (e.g. "Core Addons") so results can show the full sidebar breadcrumb.
-- Read lazily (not at file load) since standalone builds rewrite
-- ADDON_GROUPS' membership during EllesmereUI.lua's own load sequence --
-- by the time a search actually runs, that rewrite has long since settled.
local _categoryByFolder

local function GetCategoryLabel(folder)
    if not _categoryByFolder then
        _categoryByFolder = {}
        for _, group in ipairs(EllesmereUI.ADDON_GROUPS or {}) do
            for _, memberFolder in ipairs(group.members) do
                _categoryByFolder[memberFolder] = EllesmereUI.L(group.label)
            end
        end
    end
    return _categoryByFolder[folder]
end

local function JoinBreadcrumb(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v and v ~= "" then parts[#parts + 1] = v end
    end
    return table.concat(parts, "  |  ")
end

local function JumpToResult(entry, sidebarSearchBox)
    -- Coarse (whole-page) results have no single option to highlight -- just
    -- land on the page. Fine-grained option/section results scroll to and
    -- glow the specific matching row via EllesmereUI:NavigateToElementSettings
    -- (the same deep-link machinery the What's New page uses) instead of
    -- ApplyInlineSearch: that function is a *filter* -- it hides every
    -- section that doesn't match -- so reusing it here to "highlight" a
    -- single row could collapse the whole page down to just that one row's
    -- section, or even to nothing at all if the matched row isn't part of
    -- the page's current state (e.g. a CDM bar-type-specific option while a
    -- different bar is selected). NavigateToElementSettings only scrolls +
    -- glows; it never hides anything, so a row it can't currently find (same
    -- bar-type case) just means no scroll/glow happens -- the page is left
    -- exactly as the player already had it, not blanked out.
    if entry.kind == "page" or not entry.section then
        EllesmereUI:SelectModule(entry.module)
        EllesmereUI:SelectPage(entry.page)
    else
        -- Some pages (CDM Bars, Action Bars Display, Unit Frames) show
        -- entirely different content depending on an internal selector --
        -- which bar/unit is picked via that page's own dropdown -- so the
        -- matched row may not exist under whatever selection happens to be
        -- active right now. If this entry was registered under a specific
        -- selection, restore that exact selection first (NavigateToElement-
        -- Settings' preSelectFn) so the row is actually there to find.
        local preSelectFn
        if entry.selectorSetter and entry.selectorKey then
            preSelectFn = function() entry.selectorSetter(entry.selectorKey) end
        end
        EllesmereUI:NavigateToElementSettings(entry.module, entry.page, entry.section, preSelectFn, entry.label)
    end
    if popup then popup:Hide() end
    if sidebarSearchBox then sidebarSearchBox:SetText("") end
end

local function EnsureSearchUI()
    if _searchUIBuilt then return end
    local clickArea = EllesmereUI._clickArea
    local sidebarSearchBox = EllesmereUI._sidebarSearchBox
    if not clickArea or not sidebarSearchBox then return end
    _searchUIBuilt = true

    local PP = EllesmereUI.PanelPP or EllesmereUI.PP
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
    local GS_GREEN = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.63 }

    -- Results popup, anchored below the existing sidebar search box.
    popup = CreateFrame("Frame", nil, clickArea)
    popup:SetSize(380, MAX_VISIBLE_RESULTS * RESULT_ROW_H + 8)
    popup:SetPoint("TOPLEFT", sidebarSearchBox, "BOTTOMLEFT", 0, -4)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(220)
    popup:SetClampedToScreen(true)
    popup:Hide()
    local popupBg = popup:CreateTexture(nil, "BACKGROUND")
    popupBg:SetAllPoints()
    popupBg:SetColorTexture(0.10, 0.10, 0.12, 0.97)
    if EllesmereUI.MakeBorder then EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.12, PP) end

    local resultsFrame = CreateFrame("Frame", nil, popup)
    resultsFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, -4)
    resultsFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -4, 4)

    resultRows = {}
    for i = 1, MAX_VISIBLE_RESULTS do
        local row = CreateFrame("Button", nil, resultsFrame)
        row:SetHeight(RESULT_ROW_H)
        row:SetPoint("TOPLEFT", resultsFrame, "TOPLEFT", 1, -(i - 1) * RESULT_ROW_H)
        row:SetPoint("TOPRIGHT", resultsFrame, "TOPRIGHT", -1, -(i - 1) * RESULT_ROW_H)

        local hl = row:CreateTexture(nil, "ARTWORK")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0)

        local lbl = row:CreateFontString(nil, "OVERLAY")
        if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(lbl, true) end
        lbl:SetFont(fontPath, 12, "")
        lbl:SetTextColor(0.85, 0.85, 0.88, 1)
        lbl:SetPoint("LEFT", row, "LEFT", 8, 7)
        lbl:SetPoint("RIGHT", row, "RIGHT", -8, 7)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)

        local sub = row:CreateFontString(nil, "OVERLAY")
        if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(sub, true) end
        sub:SetFont(fontPath, 10, "")
        sub:SetTextColor(GS_GREEN.r, GS_GREEN.g, GS_GREEN.b, 0.85)
        sub:SetPoint("LEFT", row, "LEFT", 8, -8)
        sub:SetJustifyH("LEFT")

        row:SetScript("OnEnter", function() hl:SetColorTexture(1, 1, 1, 0.08) end)
        row:SetScript("OnLeave", function() hl:SetColorTexture(1, 1, 1, 0) end)

        row._label = lbl
        row._sub = sub
        row:Hide()
        resultRows[i] = row
    end

    local function RunSearch()
        local query = sidebarSearchBox:GetText()
        local results = SearchIndex(query, MAX_VISIBLE_RESULTS)
        for i, row in ipairs(resultRows) do
            local entry = results[i]
            if entry then
                if entry.kind == "page" then
                    -- Coarse whole-page result -- marked with a leading ">"
                    -- (plain ASCII, safe across every locale font this addon
                    -- supports) so it reads as "go to this page", not a
                    -- specific option on it.
                    row._label:SetText("> " .. entry.displayLabel)
                    row._sub:SetText(JoinBreadcrumb(GetCategoryLabel(entry.module), entry.moduleLabel))
                else
                    row._label:SetText(entry.labelLoc and (entry.label .. "  (" .. entry.labelLoc .. ")") or entry.label)
                    row._sub:SetText(JoinBreadcrumb(GetCategoryLabel(entry.module), GetModuleDisplayName(entry.module), EllesmereUI.L(entry.page)))
                end
                row:SetScript("OnClick", function() JumpToResult(entry, sidebarSearchBox) end)
                row:Show()
            else
                row:Hide()
            end
        end
        if #results > 0 then
            popup:SetHeight(math.min(#results, MAX_VISIBLE_RESULTS) * RESULT_ROW_H + 8)
            popup:Show()
        else
            popup:Hide()
        end
    end

    -- HookScript adds to the box's existing handlers rather than replacing
    -- them, so the sidebar addon/page filtering it already does keeps working.
    sidebarSearchBox:HookScript("OnTextChanged", RunSearch)
    sidebarSearchBox:HookScript("OnEnterPressed", function(self)
        local results = SearchIndex(self:GetText(), 1)
        if results[1] then JumpToResult(results[1], self) end
    end)

    popup:SetScript("OnUpdate", function()
        if popup:IsShown() and not popup:IsMouseOver() and not sidebarSearchBox:IsMouseOver()
           and IsMouseButtonDown("LeftButton") then
            popup:Hide()
        end
    end)
end

-------------------------------------------------------------------------------
--  Wire the search hooks into the panel the first time it's opened, via any
--  entry point (Show / Toggle / ShowModule all funnel through the panel's
--  internal CreateMainFrame, which is what creates the sidebar search box
--  this file hooks into). No edits to EllesmereUI.lua needed for this --
--  standard same-addon method wrapping from a later-loaded file.
-------------------------------------------------------------------------------
for _, methodName in ipairs({ "Show", "Toggle", "ShowModule" }) do
    local original = EllesmereUI[methodName]
    if original then
        EllesmereUI[methodName] = function(self, ...)
            original(self, ...)
            EnsureSearchUI()
        end
    end
end
