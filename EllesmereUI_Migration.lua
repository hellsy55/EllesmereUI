--------------------------------------------------------------------------------
--  EllesmereUI_Migration.lua
--  Loaded via TOC after EllesmereUI_Lite.lua, before EllesmereUI_Profiles.lua.
--  Runs at ADDON_LOADED time for "EllesmereUI" (before child addons init).
--
--  All legacy migrations have been removed. The beta-exit wipe (reset
--  version 5) guarantees every user starts from a clean slate.
--------------------------------------------------------------------------------

local floor = math.floor

--- Round all width/height values in a table to whole pixels.
--- Call from each child addon's OnInitialize after its DB is loaded.
--- keys: list of field names to round (e.g. {"width", "height"})
--- tables: list of profile sub-tables to scan
function EllesmereUI.RoundSizeFields(keys, tables)
    for _, tbl in ipairs(tables) do
        if type(tbl) == "table" then
            for _, key in ipairs(keys) do
                local v = tbl[key]
                if type(v) == "number" then
                    tbl[key] = floor(v + 0.5)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
--  ONE-TIME MIGRATION RUNNER
--
--  Single, global system for any addon to register a one-time data migration
--  that needs to run reliably across upgrades, multiple characters, multiple
--  profiles, and multiple specs.
--
--  USAGE:
--    EllesmereUI.RegisterMigration({
--        id          = "cdm_pandemic_glow_color_table",
--        scope       = "profile",  -- "global" | "profile" | "specProfile"
--        description = "Migrate flat pandemicR/G/B keys to pandemicGlowColor table",
--        body        = function(ctx)
--            -- ctx fields depend on scope:
--            --   global       -> ctx.db (= EllesmereUIDB)
--            --   profile      -> ctx.profile, ctx.profileName
--            --   specProfile  -> ctx.specProfile, ctx.specKey
--            local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
--            local bars = cdm and cdm.cdmBars and cdm.cdmBars.bars
--            if not bars then return end
--            for _, b in ipairs(bars) do
--                if b.pandemicR and not b.pandemicGlowColor then
--                    b.pandemicGlowColor = { r = b.pandemicR, g = b.pandemicG, b = b.pandemicB }
--                end
--            end
--        end,
--    })
--
--  GUARANTEES:
--    - Migration body wraps in pcall: a buggy body cannot break the runner.
--    - Flag is stamped only on success: a failed body retries next session.
--    - "global" scope flag lives at EllesmereUIDB._migrations[id]
--    - "profile" scope flag lives at profileData._migrations[id], runner walks
--      ALL profiles so multi-character is handled in one pass.
--    - "specProfile" scope flag lives at specProfData._migrations[id], runner
--      walks ALL spec profiles so multi-spec is handled in one pass.
--    - Phase: currently only "early" (parent ADDON_LOADED, before child
--      addons init). Add more phases lazily if a real need appears.
--
--  AUTHORING RULES:
--    1. IDs are forever. Never change an existing migration's id; register a
--       new migration with a new id if logic needs to change.
--    2. Bodies must be idempotent. Even with the flag, the body should be
--       safe to re-run on already-migrated data (predicate-gated).
--    3. Don't iterate profiles inside a body if scope = "profile" -- the
--       runner does that for you. Same for "specProfile".
--    4. Don't call live game APIs (UnitClass, GetSpecialization,
--       C_CooldownViewer, etc.) -- only "early" phase exists, none of these
--       are reliable yet.
--    5. Walk raw stored data via ctx.profile / ctx.specProfile, not via
--       child.db.profile -- child addons haven't initialized yet.
--------------------------------------------------------------------------------

local _migrations = {}              -- ordered registration list (1..N)
local _migrationsById = {}          -- id -> spec, for dedup + lookup
local _migrationErrors = {}         -- session-only error buffer for /eui migrations
EllesmereUI._migrationErrors = _migrationErrors

local VALID_SCOPES = { global = true, profile = true, specProfile = true }

function EllesmereUI.RegisterMigration(spec)
    if type(spec) ~= "table" then
        error("RegisterMigration: spec must be a table", 2)
    end
    if type(spec.id) ~= "string" or spec.id == "" then
        error("RegisterMigration: spec.id must be a non-empty string", 2)
    end
    if type(spec.body) ~= "function" then
        error("RegisterMigration: spec.body must be a function", 2)
    end
    if not VALID_SCOPES[spec.scope] then
        error("RegisterMigration: spec.scope must be 'global', 'profile', or 'specProfile' (got '" .. tostring(spec.scope) .. "')", 2)
    end
    if _migrationsById[spec.id] then
        error("RegisterMigration: duplicate migration id '" .. spec.id .. "'", 2)
    end
    _migrations[#_migrations + 1] = spec
    _migrationsById[spec.id] = spec
end

-- Get (and lazily create) the per-scope flag table on the host table.
local function GetFlagTable(host)
    if not host._migrations then host._migrations = {} end
    return host._migrations
end

-- Run a single migration body, stamp the flag on success, log on error.
local function RunOne(spec, ctx, flagHost)
    local flags = GetFlagTable(flagHost)
    if flags[spec.id] then return end
    local ok, err = pcall(spec.body, ctx)
    if ok then
        flags[spec.id] = true
    else
        _migrationErrors[#_migrationErrors + 1] = {
            id    = spec.id,
            scope = spec.scope,
            err   = tostring(err),
            time  = GetTime(),
        }
    end
end

-- Iterate one migration across the appropriate set of targets for its scope.
local function RunMigration(spec)
    if spec.scope == "global" then
        RunOne(spec, { db = EllesmereUIDB }, EllesmereUIDB)

    elseif spec.scope == "profile" then
        if EllesmereUIDB.profiles then
            for profName, profData in pairs(EllesmereUIDB.profiles) do
                if type(profData) == "table" then
                    RunOne(spec, {
                        profile     = profData,
                        profileName = profName,
                    }, profData)
                end
            end
        end

    elseif spec.scope == "specProfile" then
        local sa = EllesmereUIDB.spellAssignments
        local sp = sa and sa.specProfiles
        if sp then
            for specKey, specProfData in pairs(sp) do
                if type(specProfData) == "table" then
                    RunOne(spec, {
                        specProfile = specProfData,
                        specKey     = specKey,
                    }, specProfData)
                end
            end
        end
    end
end

-- Public: run all registered migrations. Currently called once from the
-- parent ADDON_LOADED handler after PerformResetWipe + StampResetVersion.
function EllesmereUI.RunRegisteredMigrations()
    if not EllesmereUIDB then return end
    for _, spec in ipairs(_migrations) do
        RunMigration(spec)
    end
end

-- Inspection helper for the slash command.
function EllesmereUI.GetMigrationStatus()
    local out = {
        registered = {},
        errors     = _migrationErrors,
    }
    for _, spec in ipairs(_migrations) do
        local entry = {
            id          = spec.id,
            scope       = spec.scope,
            description = spec.description or "",
            ranScopes   = {}, -- list of {target, ran}
        }
        if spec.scope == "global" then
            local flags = EllesmereUIDB and EllesmereUIDB._migrations
            entry.ranScopes[1] = { target = "global", ran = (flags and flags[spec.id]) and true or false }
        elseif spec.scope == "profile" then
            if EllesmereUIDB and EllesmereUIDB.profiles then
                for profName, profData in pairs(EllesmereUIDB.profiles) do
                    if type(profData) == "table" then
                        local flags = profData._migrations
                        entry.ranScopes[#entry.ranScopes + 1] = {
                            target = profName,
                            ran    = (flags and flags[spec.id]) and true or false,
                        }
                    end
                end
            end
        elseif spec.scope == "specProfile" then
            local sp = EllesmereUIDB and EllesmereUIDB.spellAssignments and EllesmereUIDB.spellAssignments.specProfiles
            if sp then
                for specKey, specProfData in pairs(sp) do
                    if type(specProfData) == "table" then
                        local flags = specProfData._migrations
                        entry.ranScopes[#entry.ranScopes + 1] = {
                            target = specKey,
                            ran    = (flags and flags[spec.id]) and true or false,
                        }
                    end
                end
            end
        end
        out.registered[#out.registered + 1] = entry
    end
    return out
end

-- /eui migrations slash command. Lists registered migrations, run status
-- per scope target, and any session errors.
SLASH_EUIMIGRATIONS1 = "/euimig"
SLASH_EUIMIGRATIONS2 = "/euimigrations"
SlashCmdList["EUIMIGRATIONS"] = function()
    local status = EllesmereUI.GetMigrationStatus()
    print("|cff0cd29fEllesmereUI Migrations|r")
    print(string.format("  Registered: %d", #status.registered))
    for _, entry in ipairs(status.registered) do
        local ranCount, totalCount = 0, #entry.ranScopes
        for _, s in ipairs(entry.ranScopes) do if s.ran then ranCount = ranCount + 1 end end
        local marker
        if totalCount == 0 then
            marker = "|cffaaaaaa(no targets)|r"
        elseif ranCount == totalCount then
            marker = "|cff00ff00OK|r"
        elseif ranCount == 0 then
            marker = "|cffff8800PENDING|r"
        else
            marker = string.format("|cffffff00%d/%d|r", ranCount, totalCount)
        end
        print(string.format("  [%s] %s (%s)", marker, entry.id, entry.scope))
        if entry.description ~= "" then
            print("      |cffaaaaaa" .. entry.description .. "|r")
        end
    end
    if #status.errors > 0 then
        print(string.format("|cffff4444Errors this session: %d|r", #status.errors))
        for _, e in ipairs(status.errors) do
            print(string.format("  |cffff4444[%s]|r %s", e.id, e.err))
        end
    else
        print("|cff00ff00No errors this session.|r")
    end
end

--------------------------------------------------------------------------------
--  Position snap helpers
--  File-scope helpers used by the position_snap_v3 migration below AND
--  exposed on EllesmereUI for profile import (import path calls
--  EllesmereUI.SnapProfilePositions(profData) to snap imported positions).
--
--  These are FUNCTION definitions only -- the bodies run on demand, not at
--  file load. Reads of EllesmereUIDB.ppUIScale and GetPhysicalScreenSize()
--  inside MakeSnappers() happen whenever the function is called, by which
--  time SavedVariables are loaded and the screen size API is available.
--------------------------------------------------------------------------------

local function MakeSnappers()
    local physH = select(2, GetPhysicalScreenSize())
    local perfect = physH and physH > 0 and (768 / physH) or 1
    local uiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or perfect
    if uiScale <= 0 then uiScale = perfect end
    local onePixel = perfect / uiScale

    local function snap(v)
        if type(v) ~= "number" or v == 0 then return v end
        return floor(v / onePixel + 0.5) * onePixel
    end
    local function snapPos(tbl)
        if type(tbl) ~= "table" then return end
        if tbl.x then tbl.x = snap(tbl.x) end
        if tbl.y then tbl.y = snap(tbl.y) end
    end
    local function snapPosMap(map)
        if type(map) ~= "table" then return end
        for _, pos in pairs(map) do snapPos(pos) end
    end
    local function snapAnchors(anchors)
        if type(anchors) ~= "table" then return end
        for _, info in pairs(anchors) do
            if type(info) == "table" then
                if info.offsetX then info.offsetX = snap(info.offsetX) end
                if info.offsetY then info.offsetY = snap(info.offsetY) end
            end
        end
    end
    return snapPos, snapPosMap, snapAnchors
end

-- Snap all positions in a single profile data table.
-- Called by the position_snap_v3 migration (for each profile) and by
-- profile import (for a single imported profile).
local function SnapProfilePositions(profData)
    if type(profData) ~= "table" then return end
    local snapPos, snapPosMap, snapAnchors = MakeSnappers()

    local ul = profData.unlockLayout
    if ul then snapAnchors(ul.anchors) end

    local addons = profData.addons
    if type(addons) ~= "table" then return end

    local uf = addons.EllesmereUIUnitFrames
    if uf then snapPosMap(uf.positions) end

    local eab = addons.EllesmereUIActionBars
    if eab then snapPosMap(eab.barPositions) end

    local cdm = addons.EllesmereUICooldownManager
    if cdm then snapPosMap(cdm.cdmBarPositions) end

    local erb = addons.EllesmereUIResourceBars
    if type(erb) == "table" then
        for _, section in pairs(erb) do
            if type(section) == "table" and section.unlockPos then
                snapPos(section.unlockPos)
            end
        end
    end

    local abr = addons.EllesmereUIAuraBuffReminders
    if type(abr) == "table" and abr.unlockPos then
        snapPos(abr.unlockPos)
    end

    local basics = addons.EllesmereUIBasics
    if type(basics) == "table" then
        if basics.questTracker then snapPos(basics.questTracker.pos) end
        if basics.minimap then snapPos(basics.minimap.position) end
        if basics.friends then snapPos(basics.friends.position) end
    end

    local cursor = addons.EllesmereUICursor
    if type(cursor) == "table" then
        if cursor.gcd then snapPos(cursor.gcd.pos) end
        if cursor.cast then snapPos(cursor.cast.pos) end
    end
end

-- Expose for profile import
EllesmereUI.SnapProfilePositions = SnapProfilePositions

--------------------------------------------------------------------------------
--  Registered migrations
--  Each migration below is a one-time data transformation gated by the runner's
--  per-scope flag. Bodies must be idempotent. Legacy flag checks bridge the
--  transition from old inline migrations; they can be removed after a few
--  release cycles once all existing users have been through the new system.
--------------------------------------------------------------------------------

EllesmereUI.RegisterMigration({
    id          = "quest_tracker_sec_color_default",
    scope       = "profile",
    description = "Clear questTracker.secColor if it matches the legacy hardcoded green default, so accent color fallback can take over.",
    body = function(ctx)
        -- Legacy bridge: skip if the old inline migration already ran.
        -- Old flag location: EllesmereUIDB._questTrackerSecColorMigrated
        if EllesmereUIDB and EllesmereUIDB._questTrackerSecColorMigrated then return end

        local addons = ctx.profile.addons
        local basics = addons and addons.EllesmereUIBasics
        if not basics or not basics.questTracker then return end
        local sc = basics.questTracker.secColor
        if type(sc) == "table"
           and sc.r == 0.047 and sc.g == 0.824 and sc.b == 0.624 then
            basics.questTracker.secColor = nil
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "quest_tracker_blizzard_skin_rebuild_v1",
    scope       = "global",
    description = "Archive obsolete custom-tracker keys (width/height/alignment/bg/font/color/zone/world/prey/topLine) into _legacy so they stop polluting questTracker defaults after the rebuild to a skin+QoL layer.",
    body = function()
        local sv = _G.EllesmereUIQuestTrackerDB
        if type(sv) ~= "table" then return end
        local profiles = sv.profiles
        if type(profiles) ~= "table" then return end

        local OBSOLETE = {
            "width", "height", "alignment",
            "bgR", "bgG", "bgB", "bgAlpha",
            "showTopLine",
            "showZoneQuests", "showWorldQuests", "showPreyQuests",
            "showQuestItems", "questItemSize",
            "zoneCollapsed", "worldCollapsed", "preyCollapsed",
            "delveCollapsed", "questsCollapsed", "achievementsCollapsed",
            "titleFontSize", "objFontSize", "completedFontSize",
            "secFontSize", "focusedFontSize",
            "titleColor", "objColor", "completedColor", "secColor", "focusedColor",
            "secColorUseAccent",
            "focusBgOpacity",
            "hideBlizzardTracker",
        }

        for _, prof in pairs(profiles) do
            if type(prof) == "table" and type(prof.questTracker) == "table" then
                local qt = prof.questTracker
                local legacy = qt._legacy or {}
                local moved = false
                for _, k in ipairs(OBSOLETE) do
                    if qt[k] ~= nil then
                        legacy[k] = qt[k]
                        qt[k] = nil
                        moved = true
                    end
                end
                if moved then qt._legacy = legacy end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "friends_data_wipe_v1",
    scope       = "profile",
    description = "Wipe legacy friends list data across all profiles (sessions 15-17 module rebuild).",
    body = function(ctx)
        -- Legacy bridge: skip if the old inline migration already ran.
        -- Old flag location: EllesmereUIDB._friendsWipeDone
        -- DESTRUCTIVE: this resets basics.friends to { enabled = wasEnabled }.
        -- The bridge is critical -- without it, re-running would wipe any
        -- configuration the user has made since the original migration.
        if EllesmereUIDB and EllesmereUIDB._friendsWipeDone then return end

        local addons = ctx.profile.addons
        local basics = addons and addons.EllesmereUIBasics
        if not basics or not basics.friends then return end

        local wasEnabled = basics.friends.enabled
        basics.friends = { enabled = wasEnabled }
    end,
})

EllesmereUI.RegisterMigration({
    id          = "friend_notes_wipe_v1",
    scope       = "global",
    description = "Wipe legacy bnetAccountID-keyed friendAssignments and friendNotes (sessions 15-17 rebuild).",
    body = function(ctx)
        -- Legacy bridge: skip if the old inline migration already ran.
        -- Old flag location: EllesmereUIDB.global._friendNotesMigrated
        -- DESTRUCTIVE: wipes EllesmereUIDB.global.friendAssignments and
        -- .friendNotes. Without the bridge, re-running would destroy any
        -- data the user has accumulated since the original migration.
        if EllesmereUIDB and EllesmereUIDB.global
           and EllesmereUIDB.global._friendNotesMigrated then return end

        local g = ctx.db.global
        if not g then return end

        -- Set the one-time popup flag only if the user actually had
        -- group assignments pre-wipe (so users who never used the feature
        -- don't see a popup about it being "reset").
        local hadAssignments = false
        if g.friendAssignments then
            for _ in pairs(g.friendAssignments) do
                hadAssignments = true
                break
            end
        end
        if hadAssignments then
            g._friendGroupReassignPopup = true
        end

        g.friendAssignments = {}
        g.friendNotes = {}
    end,
})

EllesmereUI.RegisterMigration({
    id          = "position_snap_v3",
    scope       = "global",
    description = "Re-snap all stored positions (unlock anchors + every profile's position fields) to the physical pixel grid.",
    body = function(ctx)
        -- Legacy bridge: skip if the old inline migration already ran.
        -- Old flag location: EllesmereUIDB._positionSnapV3Done
        -- Idempotence: snapping already-snapped positions is a fixpoint
        -- (floor(n/onePixel + 0.5) * onePixel returns n for grid values),
        -- so the bridge is belt-and-suspenders here, not strictly required.
        if EllesmereUIDB and EllesmereUIDB._positionSnapV3Done then return end

        -- Mixed scope: one global thing (unlockAnchors) + one pass per
        -- profile (via SnapProfilePositions). Registered as "global" so
        -- the runner invokes the body exactly once; the body does its own
        -- profile walk because the two operations are conceptually one
        -- migration with a single flag.
        local _, _, snapAnchors = MakeSnappers()
        snapAnchors(ctx.db.unlockAnchors)

        if ctx.db.profiles then
            for _, profData in pairs(ctx.db.profiles) do
                SnapProfilePositions(profData)
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "eab_round_button_sizes",
    scope       = "profile",
    description = "Round EllesmereUIActionBars buttonWidth/buttonHeight to whole pixels.",
    body = function(ctx)
        -- No legacy flag to bridge: the old inline code had no gate and
        -- ran every login. Migration is naturally idempotent (floor(x+0.5)
        -- is a fixpoint on integers) so running it once per profile via
        -- the runner's per-profile flag produces the same result.
        local eab = ctx.profile.addons and ctx.profile.addons.EllesmereUIActionBars
        local bars = eab and eab.bars
        if type(bars) ~= "table" or not EllesmereUI.RoundSizeFields then return end

        local sizeKeys = { "buttonWidth", "buttonHeight" }
        for _, barSettings in pairs(bars) do
            if type(barSettings) == "table" then
                EllesmereUI.RoundSizeFields(sizeKeys, { barSettings })
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "erb_round_size_fields",
    scope       = "profile",
    description = "Round EllesmereUIResourceBars width/height/pipWidth/pipHeight on primary, secondary, health, and castBar tables to whole pixels.",
    body = function(ctx)
        -- No legacy flag to bridge: the old inline code had no gate and
        -- ran every login. Migration is naturally idempotent.
        local erb = ctx.profile.addons and ctx.profile.addons.EllesmereUIResourceBars
        if type(erb) ~= "table" or not EllesmereUI.RoundSizeFields then return end

        local sizeKeys = { "width", "height", "pipWidth", "pipHeight" }
        EllesmereUI.RoundSizeFields(sizeKeys, {
            erb.primary, erb.secondary, erb.health, erb.castBar,
        })
    end,
})

EllesmereUI.RegisterMigration({
    id          = "basics_minimap_hide_buttons_split",
    scope       = "profile",
    description = "Split legacy minimap.hideButtons boolean into per-button keys (hideZoomButtons, hideTrackingButton, hideGameTime).",
    body = function(ctx)
        -- Self-gating: only fires when the legacy hideButtons key still
        -- exists. After running once, mp.hideButtons is nil and the body
        -- is a no-op for that profile.
        local basics = ctx.profile.addons and ctx.profile.addons.EllesmereUIBasics
        local mp = basics and basics.minimap
        if not mp or mp.hideButtons == nil then return end

        if mp.hideButtons == true then
            mp.hideZoomButtons    = true
            mp.hideTrackingButton = true
            mp.hideGameTime       = true
        else
            mp.hideZoomButtons    = false
            mp.hideTrackingButton = false
            mp.hideGameTime       = false
        end
        mp.hideButtons = nil
    end,
})

EllesmereUI.RegisterMigration({
    id          = "basics_minimap_round_to_circle",
    scope       = "profile",
    description = "Rename minimap.shape value 'round' to 'circle'.",
    body = function(ctx)
        local basics = ctx.profile.addons and ctx.profile.addons.EllesmereUIBasics
        local mp = basics and basics.minimap
        if not mp then return end
        if mp.shape == "round" then
            mp.shape = "circle"
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "basics_minimap_strip_scale",
    scope       = "profile",
    description = "Strip the deprecated minimap.scale field. Direct sizing via the snapshot replaces it.",
    body = function(ctx)
        local basics = ctx.profile.addons and ctx.profile.addons.EllesmereUIBasics
        local mp = basics and basics.minimap
        if not mp then return end
        mp.scale = nil
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_pandemic_glow_color_table",
    scope       = "profile",
    description = "Migrate CDM bar flat pandemicR/G/B keys into a pandemicGlowColor table, plus default pandemicGlowStyle.",
    body = function(ctx)
        -- No legacy flag to bridge: original inline migration was self-gated
        -- by the `pandemicR and not pandemicGlowColor` predicate. Body is
        -- naturally idempotent (only fires when the legacy flat keys exist
        -- AND the new table is missing) so the runner's per-profile flag
        -- stops further runs after the first successful pass.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        for _, barData in ipairs(bars) do
            if type(barData) == "table"
               and barData.pandemicR
               and not barData.pandemicGlowColor then
                barData.pandemicGlowColor = {
                    r = barData.pandemicR or 1,
                    g = barData.pandemicG or 1,
                    b = barData.pandemicB or 0,
                }
                barData.pandemicGlowStyle = barData.pandemicGlowStyle or 1
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_repair_bar_keys_v1",
    scope       = "profile",
    description = "Repair CDM bars that lost their `key` field via Lite DB delta-strip. Assigns missing core keys (cooldowns, utility, buffs) in order.",
    body = function(ctx)
        -- Self-gating via `if not bd.key` -- once every bar has a key,
        -- the loop is a no-op. The runner's per-profile flag stops
        -- further runs after the first successful pass.
        --
        -- Originally paired with a Tier 2 defensive guard in
        -- BuildAllCDMBars; that inline guard was deleted after verifying
        -- the round-trip (StripDefaults -> save -> load -> DeepMergeDefaults)
        -- correctly restores identity fields in every code path
        -- including profile switch and import. The runner pass is the
        -- one-time recovery for any user with pre-existing broken data.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        local CORE_KEYS = { "cooldowns", "utility", "buffs" }
        local CORE_NAMES = { cooldowns = "Cooldowns", utility = "Utility", buffs = "Buffs" }

        local present = {}
        for _, bd in ipairs(bars) do
            if bd.key then present[bd.key] = true end
        end
        local missing = {}
        for _, ck in ipairs(CORE_KEYS) do
            if not present[ck] then missing[#missing + 1] = ck end
        end
        if #missing == 0 then return end

        local mi = 1
        for _, bd in ipairs(bars) do
            if not bd.key and mi <= #missing then
                bd.key = missing[mi]
                bd.name = bd.name or CORE_NAMES[missing[mi]]
                if bd.enabled == nil then bd.enabled = true end
                mi = mi + 1
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_remove_misc_bars",
    scope       = "profile",
    description = "Remove obsolete CDM bars with barType=='misc' and clear anchorTo references that pointed at them.",
    body = function(ctx)
        -- Self-gating via the barType check -- once misc bars are gone,
        -- the predicate is false and the body is a no-op. Previously ran
        -- every BuildAllCDMBars call against the active profile only;
        -- the runner promotes this to once-per-profile-ever and walks
        -- all profiles automatically.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        -- Pass 1: find and remove misc bars (reverse iteration so removal
        -- doesn't shift indices we still need to visit).
        local miscKeys = {}
        for i = #bars, 1, -1 do
            if bars[i].barType == "misc" then
                miscKeys[bars[i].key] = true
                table.remove(bars, i)
            end
        end

        -- Pass 2: clear anchorTo on any remaining bar that referenced
        -- a removed misc bar.
        if next(miscKeys) then
            for _, bd in ipairs(bars) do
                if bd.anchorTo and miscKeys[bd.anchorTo] then
                    bd.anchorTo = "none"
                end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_active_state_anim_none_to_hideactive",
    scope       = "profile",
    description = "Rename CDM bar activeStateAnim value 'none' (No Animation) to 'hideActive' (Hide Active State).",
    body = function(ctx)
        -- Self-gating via the value check -- once no bar holds the legacy
        -- 'none' value, the body is a no-op. MUST register before
        -- cdm_active_state_per_bar_to_per_icon, which depends on bars
        -- carrying the post-rename 'hideActive' value.
        --
        -- Previously ran every BuildAllCDMBars call against the active
        -- profile only; the runner promotes this to once-per-profile-ever
        -- and walks all profiles automatically.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        for _, bd in ipairs(bars) do
            if bd.activeStateAnim == "none" then
                bd.activeStateAnim = "hideActive"
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_mouseover_visibility_to_always",
    scope       = "profile",
    description = "Rewrite CDM bar barVisibility 'mouseover' to 'always' (mouseover mode was removed).",
    body = function(ctx)
        -- Self-gating: once no bar carries 'mouseover', the body is a no-op.
        -- Previously ran every CDMFinishSetup against the active profile;
        -- the runner promotes this to once-per-profile-ever and walks
        -- all profiles automatically.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        for _, bd in ipairs(bars) do
            if bd.barVisibility == "mouseover" then
                bd.barVisibility = "always"
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_strip_tbb_linked_frames",
    scope       = "specProfile",
    description = "Strip stale _linkedFrame/_linkedCdID/_linkedGen fields from Tracked Buff Bar configs (legacy bloat from removed frame-tree serialization).",
    body = function(ctx)
        -- Naturally idempotent: setting nil to nil is a no-op. The runner's
        -- per-spec-profile flag stops further runs after the first pass.
        --
        -- Previously ran every CDM OnInitialize against every spec profile.
        -- The runner promotes this to once-per-spec-profile-ever.
        --
        -- The bug-producing code (frame tree serialization into TBB
        -- configs) was removed -- this migration is pure legacy cleanup,
        -- nothing in the live codebase writes these fields anymore.
        local tbb = ctx.specProfile.trackedBuffBars
        local tbbBars = tbb and tbb.bars
        if type(tbbBars) ~= "table" then return end

        for _, barCfg in ipairs(tbbBars) do
            barCfg._linkedFrame = nil
            barCfg._linkedCdID = nil
            barCfg._linkedGen = nil
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_removed_spells_to_ghost_cd_bar",
    scope       = "specProfile",
    description = "Move per-bar removedSpells (legacy filter mechanic) into the ghost CD bar's assignedSpells. The ghost bar replaced the per-bar removedSpells filter.",
    body = function(ctx)
        -- Naturally idempotent: removedSpells is wiped after migration,
        -- so a second run finds nothing. The runner's per-spec-profile
        -- flag also stops further runs after the first pass.
        --
        -- Previously ran in EnsureGhostBars which was called from
        -- BuildAllCDMBars on every CDM rebuild (login, spec change,
        -- profile swap, options change, layout reset, etc.). The runner
        -- promotes this to a single per-spec-profile pass.
        --
        -- Skips work entirely if no bar has any removedSpells, so cold
        -- specs without legacy data don't get an empty ghost bar entry
        -- pre-created on their behalf -- the runtime getter creates the
        -- ghost bar entry when something actually needs to write to it.
        local barSpells = ctx.specProfile.barSpells
        if type(barSpells) ~= "table" then return end

        local GHOST_CD   = "__ghost_cd"
        local GHOST_BUFF = "__ghost_buffs"

        -- First pass: is there anything to migrate?
        local hasWork = false
        for barKey, bs in pairs(barSpells) do
            if barKey ~= GHOST_CD and barKey ~= GHOST_BUFF
               and type(bs) == "table"
               and bs.removedSpells and next(bs.removedSpells) then
                hasWork = true
                break
            end
        end
        if not hasWork then return end

        -- Ensure ghost CD bar entry exists in the spell store.
        local ghostBS = barSpells[GHOST_CD]
        if not ghostBS then
            ghostBS = {}
            barSpells[GHOST_CD] = ghostBS
        end
        if not ghostBS.assignedSpells then ghostBS.assignedSpells = {} end

        -- Build dedupe set from any spells already on the ghost bar.
        local existing = {}
        for _, sid in ipairs(ghostBS.assignedSpells) do existing[sid] = true end

        -- Second pass: migrate and wipe.
        for barKey, bs in pairs(barSpells) do
            if barKey ~= GHOST_CD and barKey ~= GHOST_BUFF
               and type(bs) == "table"
               and bs.removedSpells and next(bs.removedSpells) then
                for sid in pairs(bs.removedSpells) do
                    if not existing[sid] then
                        existing[sid] = true
                        ghostBS.assignedSpells[#ghostBS.assignedSpells + 1] = sid
                    end
                end
                wipe(bs.removedSpells)
            end
        end
    end,
})

-- Inline copy of every racial spell ID across every race. Mirrors
-- RACE_RACIALS in EllesmereUICooldownManager.lua. Used by the ghost CD
-- bar cleanup migration so we can identify racials without depending
-- on the CDM child addon (which loads after the migration runner fires)
-- or the per-character _myRacialsSet (which only contains the current
-- character's racials). If a new race ships, update both copies.
local CDM_ALL_RACIAL_SPELL_IDS = {
    [7744]    = true, [20549]   = true,
    [20572]   = true, [33697]   = true, [33702]   = true,
    [202719]  = true, [50613]   = true, [25046]   = true, [69179]   = true,
    [80483]   = true, [155145]  = true, [129597]  = true, [232633]  = true, [28730]   = true,
    [20594]   = true, [26297]   = true,
    [28880]   = true, [59543]   = true, [59545]   = true, [121093]  = true,
    [59544]   = true, [370626]  = true, [59547]   = true, [59548]   = true, [59542]   = true, [416250]  = true,
    [58984]   = true, [59752]   = true,
    [265221]  = true, [20589]   = true, [69041]   = true, [68992]   = true, [69070]   = true,
    [107079]  = true, [274738]  = true, [255647]  = true, [256948]  = true, [287712]  = true,
    [291944]  = true, [312411]  = true, [312924]  = true,
    [357214]  = true, [368970]  = true,
    [436344]  = true, [1287685] = true,
}

EllesmereUI.RegisterMigration({
    id          = "cdm_ghost_cd_bar_cleanup_v3",
    scope       = "specProfile",
    description = "Strip junk entries from the ghost CD bar: negative IDs (presets/trinkets), racials, customs (best-effort), and duplicates of spells already on a real bar.",
    body = function(ctx)
        -- Naturally idempotent: after the first run, the junk entries
        -- are gone, and the runner's per-spec-profile flag stops
        -- further runs anyway.
        --
        -- Previously ran in EnsureGhostBars on every CDM rebuild and
        -- gated by a manual prof._ghostBarCleaned3 flag. The runner
        -- promotes this to a single per-spec-profile pass with its
        -- own flag, so the manual one is gone.
        --
        -- Customs detection is best-effort: the bs.customSpellIDs
        -- stamping was added in v6.1, so customs added before that
        -- won't be detected. Customs that were tracked via the legacy
        -- bs.customSpells field are also undetectable now (C5 wiped
        -- those). Stale customs that slip through stay on the ghost
        -- bar (which is hidden, so the impact is purely cosmetic).
        local barSpells = ctx.specProfile.barSpells
        if type(barSpells) ~= "table" then return end

        local GHOST_CD   = "__ghost_cd"
        local GHOST_BUFF = "__ghost_buffs"

        local ghostBS = barSpells[GHOST_CD]
        if not (ghostBS and ghostBS.assignedSpells) then return end

        -- Build sets of spells currently on real bars + currently stamped as custom.
        local realBarSpells = {}
        local customSet = {}
        for bk, bs in pairs(barSpells) do
            if bk ~= GHOST_CD and bk ~= GHOST_BUFF and type(bs) == "table" then
                if bs.assignedSpells then
                    for _, sid in ipairs(bs.assignedSpells) do
                        if sid and sid > 0 then realBarSpells[sid] = true end
                    end
                end
                if bs.customSpellIDs then
                    for sid in pairs(bs.customSpellIDs) do
                        customSet[sid] = true
                    end
                end
            end
        end

        for i = #ghostBS.assignedSpells, 1, -1 do
            local sid = ghostBS.assignedSpells[i]
            if sid and (
                sid <= 0
                or customSet[sid]
                or CDM_ALL_RACIAL_SPELL_IDS[sid]
                or realBarSpells[sid]
            ) then
                table.remove(ghostBS.assignedSpells, i)
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_strip_legacy_spell_keys",
    scope       = "specProfile",
    description = "Strip legacy trackedSpells/customSpells keys from CDM bar data. The current shape is bs.assignedSpells; legacy keys are no longer written by any code path.",
    body = function(ctx)
        -- Naturally idempotent: setting nil to nil is a no-op. The runner's
        -- per-spec-profile flag stops further runs after the first pass.
        --
        -- Previously ran on every GetBarSpellData/GetBarSpellDataForSpec
        -- call as a lazy in-getter migration. That hot read path executed
        -- the nil-check on every spell read, route lookup, picker query,
        -- BuildAllCDMBars iteration, etc. The runner promotes this to a
        -- single per-spec-profile pass.
        --
        -- Cold profiles with legacy data lose those entries rather than
        -- being auto-ported into the new shape -- the schema has drifted
        -- enough that auto-porting would likely produce broken entries.
        -- The bar simply comes up with assignedSpells == nil, which the
        -- new-spec auto-population path correctly interprets as "never
        -- seen" and fills with defaults.
        local barSpells = ctx.specProfile.barSpells
        if type(barSpells) ~= "table" then return end

        for _, bs in pairs(barSpells) do
            if type(bs) == "table" then
                bs.trackedSpells = nil
                bs.customSpells  = nil
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_consolidate_buff_bars",
    scope       = "global",
    description = "Remove all extra (custom) buff bars across every parent profile, nil stale assignedSpells on the main buffs bar across every spec profile, and prune orphaned spell data for the deleted bars. Replaces the old _buffBarMigrationV2Done and _buffsBarCleanupV2 inline migrations.",
    body = function(ctx)
        -- Naturally idempotent: after the first run, no extra buff bars
        -- exist to remove and main-buffs assignedSpells is already nil.
        -- The runner's global flag also stops further runs.
        --
        -- The main "buffs" bar is Blizzard-owned and auto-populated from
        -- the CDM viewer -- it should never have manual assignedSpells.
        -- Extra/custom buff bars (custom_5_1234 etc.) were removed from
        -- the system entirely; their bar list entries and spell data
        -- both need to go.
        --
        -- This consolidates two previous inline migrations:
        --   _buffBarMigrationV2Done (v5.6.5) -- the full cleanup
        --   _buffsBarCleanupV2      (v6.0.4) -- defensive re-run of the
        --                                       main-buffs nil step
        -- Both have been live since late March / early April 2026 so
        -- most users have already had them run; for those users the
        -- new migration is a pure no-op.
        local removedBuffBarKeys = {}

        -- 1. Walk every parent profile, drop extra buff bars from the
        -- bar list, and remember their keys for the spell-data prune.
        if ctx.db.profiles then
            for _, profData in pairs(ctx.db.profiles) do
                local cdm = profData.addons and profData.addons.EllesmereUICooldownManager
                local cdmBars = cdm and cdm.cdmBars
                local bars = cdmBars and cdmBars.bars
                if type(bars) == "table" then
                    local kept = {}
                    for _, bd in ipairs(bars) do
                        if bd.barType == "buffs" and bd.key ~= "buffs" then
                            removedBuffBarKeys[bd.key] = true
                        else
                            kept[#kept + 1] = bd
                        end
                    end
                    cdmBars.bars = kept
                end
            end
        end

        -- 2. Walk every spec profile, nil stale main-buffs assignedSpells
        -- and prune orphaned spell data for deleted extra bars.
        local sa = ctx.db.spellAssignments
        local specProfiles = sa and sa.specProfiles
        if type(specProfiles) == "table" then
            for _, specProf in pairs(specProfiles) do
                local barSpells = specProf.barSpells
                if type(barSpells) == "table" then
                    if barSpells["buffs"] then
                        barSpells["buffs"].assignedSpells = nil
                    end
                    for removedKey in pairs(removedBuffBarKeys) do
                        barSpells[removedKey] = nil
                    end
                end
            end
        end

        -- 3. Wipe the old manual flag bytes -- the runner's own flag
        -- replaces them and the old ones are dead bloat in SV.
        ctx.db._buffBarMigrationV2Done = nil
        ctx.db._buffsBarCleanupV2      = nil
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_wipe_legacy_glows_tbb_locations",
    scope       = "global",
    description = "Wipe legacy bar glows / TBB / tbbPositions storage locations. The data was moved to per-spec storage in v5.5.7. No live code writes to these locations anymore -- they are dead bytes that the previous inline migration was still trying to copy out.",
    body = function(ctx)
        -- Naturally idempotent: nil = nil. The runner's global flag
        -- also stops further runs.
        --
        -- Previously the inline CDMFinishSetup migration COPIED these
        -- locations into the active spec profile, then left the
        -- legacy data in place. After ~2 weeks of v5.5.7+ shipping,
        -- any still-unmigrated data in these locations belongs to
        -- cold profiles/specs the user hasn't logged into. Active
        -- users have already had their data ported to per-spec
        -- storage and don't need this migration to do anything.
        --
        -- Discriminator is location, not content: anything at the
        -- top-level spellAssignments.barGlows or under the parent
        -- profile's CDM addon block is by definition legacy because
        -- no current code writes there. Live code writes to
        -- spellAssignments.specProfiles[specKey].X exclusively.

        -- 1. Wipe global barGlows on the spellAssignments root.
        local sa = ctx.db.spellAssignments
        if sa then
            sa.barGlows = nil
        end

        -- 2. Wipe per-parent-profile CDM trackedBuffBars / tbbPositions.
        if ctx.db.profiles then
            for _, profData in pairs(ctx.db.profiles) do
                local cdm = profData.addons and profData.addons.EllesmereUICooldownManager
                if cdm then
                    cdm.trackedBuffBars = nil
                    cdm.tbbPositions    = nil
                end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_strip_position_based_glow_keys",
    scope       = "specProfile",
    description = "Strip old position-based CDM bar glow assignment keys (101_*, 102_*) from barGlows.assignments. These were tied to bar index + button index and broke when CDM icons reordered during reanchor. The new format keys are cdm_<cooldownID>.",
    body = function(ctx)
        -- Naturally idempotent: after the first run no 10[12]_ keys
        -- remain. The runner's per-spec-profile flag also stops further
        -- runs. Action bar keys (1_* through 8_*) and the new cdm_<id>
        -- format keys are left alone.
        --
        -- Previously ran in MigrateCDMAssignments, called from
        -- ns.InitBarGlows, called once from CDMFinishSetup on every
        -- login/reload. The runner promotes this to a single
        -- per-spec-profile pass.
        local bg = ctx.specProfile.barGlows
        local assignments = bg and bg.assignments
        if type(assignments) ~= "table" then return end

        for key in pairs(assignments) do
            if type(key) == "string" and key:match("^10[12]_") then
                assignments[key] = nil
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_remove_discontinued_presets",
    scope       = "specProfile",
    description = "Remove preset versions of discontinued spells (Bloodlust + variants, Time Spiral, warlock pets) from CDM bars and TBB bars. These presets were removed from the picker because they can't be tracked via cooldown detection.",
    body = function(ctx)
        -- Naturally idempotent: after the first run the IDs and TBB bars
        -- are gone, and re-running finds nothing. The runner's per-spec-
        -- profile flag also stops further runs.
        --
        -- Previously ran in CDMFinishSetup on every login/reload, walking
        -- every spec profile every time. The runner promotes this to a
        -- single per-spec-profile pass.
        --
        -- The customSpellDurations guard is the safety mechanism: a real
        -- class spell with the same ID (e.g. a Shaman's Heroism (32182))
        -- has no customSpellDurations stamp because it was added via the
        -- regular picker, not the preset adder. Only spells added as a
        -- preset variant get the duration stamp, so the guard prevents
        -- collateral damage to real class spells.
        --
        -- The presetVariants wipe is a separate stale-field cleanup --
        -- nothing in the live codebase reads or writes presetVariants
        -- anymore, but old data may still have it on bars.
        local removedPresets = { [2825] = true, [32182] = true, [80353] = true,
            [264667] = true, [390386] = true, [381301] = true, [444062] = true, [444257] = true, -- Bloodlust variants
            [104316] = true, [265187] = true, [264119] = true, [111898] = true, -- Warlock pets
        }
        local removedPopularKeys = { bloodlust = true, time_spiral = true,
            call_dreadstalkers = true, demonic_tyrant = true,
            summon_vilefiend = true, grimoire_felguard = true }

        -- Clean preset versions of these spells from ALL bars + wipe stale presetVariants.
        local barSpells = ctx.specProfile.barSpells
        if type(barSpells) == "table" then
            for _, bs in pairs(barSpells) do
                if type(bs) == "table" then
                    if bs.assignedSpells and bs.customSpellDurations then
                        for i = #bs.assignedSpells, 1, -1 do
                            local sid = bs.assignedSpells[i]
                            if removedPresets[sid] and bs.customSpellDurations[sid] then
                                table.remove(bs.assignedSpells, i)
                                bs.customSpellDurations[sid] = nil
                            end
                        end
                    end
                    bs.presetVariants = nil
                end
            end
        end

        -- Clean removed presets from TBB. Other popular presets (potions etc.) are kept.
        local tbb = ctx.specProfile.trackedBuffBars
        if tbb and type(tbb.bars) == "table" then
            for i = #tbb.bars, 1, -1 do
                local bar = tbb.bars[i]
                if bar.popularKey and removedPopularKeys[bar.popularKey] then
                    table.remove(tbb.bars, i)
                end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_unanchor_buff_bars",
    scope       = "global",
    description = "Clear unlock anchors that target CDM buff/custom_buff bars or the AuraBuff Reminders frame. Dynamic bars (resize with auras) cause cascading position shifts when used as anchor targets.",
    body = function(ctx)
        -- Self-gating implicitly: once anchors targeting buff bars are
        -- cleared, the predicate `buffKeys[info.target]` is false on
        -- the next pass and the body is a no-op.
        --
        -- Previously ran every CDMFinishSetup and read only the active
        -- profile's bar list to build the buff key set. The runner
        -- promotes this to once-per-install and the body now unions
        -- across ALL profiles so buff bars defined in inactive profiles
        -- are also recognized.
        local anchors = ctx.db.unlockAnchors
        if not anchors then return end

        -- Collect every buff/custom_buff bar key across every profile.
        local buffKeys = {}
        if ctx.db.profiles then
            for _, profData in pairs(ctx.db.profiles) do
                local cdm = profData.addons and profData.addons.EllesmereUICooldownManager
                local bars = cdm and cdm.cdmBars and cdm.cdmBars.bars
                if type(bars) == "table" then
                    for _, bd in ipairs(bars) do
                        if bd.barType == "buffs" or bd.key == "buffs" or bd.barType == "custom_buff" then
                            buffKeys["CDM_" .. bd.key] = true
                        end
                    end
                end
            end
        end
        -- AuraBuff Reminders is also dynamic regardless of profile.
        buffKeys["EABR_Reminders"] = true

        for childKey, info in pairs(anchors) do
            if info.target and buffKeys[info.target] then
                anchors[childKey] = nil
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_active_state_per_bar_to_per_icon",
    scope       = "profile",
    description = "Promote per-bar activeStateAnim='hideActive' to per-icon activeSwipeMode='none' across every spec profile, then reset the bar-level value to 'blizzard'.",
    body = function(ctx)
        -- Mixed scope: outer walk is per-profile (cdmBars.bars), inner
        -- walk is per-spec-profile (barSpells/spellSettings). Body does
        -- its own spec-profile iteration; the runner's per-profile flag
        -- gates the outer pass.
        --
        -- Self-gating via the bar value reset: after migrating, the body
        -- writes bd.activeStateAnim = "blizzard", so the next pass sees
        -- nothing to migrate.
        --
        -- Depends on cdm_active_state_anim_none_to_hideactive having run
        -- first (which renames legacy 'none' values into 'hideActive'
        -- so this body has something to migrate).
        --
        -- Previously ran every BuildAllCDMBars call against the active
        -- profile's bar list only. The runner promotes this to
        -- once-per-profile-ever and the new "walk all profiles" behavior
        -- catches custom bars that exist in inactive profiles too.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        -- The spec profile store is global (not nested in any profile),
        -- so we read EllesmereUIDB.spellAssignments.specProfiles directly.
        -- We avoid touching ns.GetSpecProfiles since CDM hasn't initialized
        -- by the time this runs (early phase, before child OnInitialize).
        local sa = EllesmereUIDB and EllesmereUIDB.spellAssignments
        local specProfiles = sa and sa.specProfiles

        for _, bd in ipairs(bars) do
            if bd.activeStateAnim == "hideActive" and not bd.isGhostBar then
                if specProfiles then
                    for _, prof in pairs(specProfiles) do
                        local barSpells = prof and prof.barSpells
                        local bs = barSpells and barSpells[bd.key]
                        if bs and bs.assignedSpells then
                            if not bs.spellSettings then bs.spellSettings = {} end
                            for _, sid in ipairs(bs.assignedSpells) do
                                if sid and sid > 0 then
                                    if not bs.spellSettings[sid] then bs.spellSettings[sid] = {} end
                                    local ss = bs.spellSettings[sid]
                                    -- Only migrate if the user hasn't already
                                    -- explicitly set a per-icon active state.
                                    if not ss.activeSwipeMode and not ss.activeSwipeR then
                                        ss.activeSwipeMode = "none"
                                    end
                                end
                            end
                        end
                    end
                end
                -- Clear old per-bar setting so the body's predicate
                -- becomes false on any future re-run.
                bd.activeStateAnim = "blizzard"
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_buff_assignedspells_reseed_v1",
    scope       = "specProfile",
    description = "Clear buffs.assignedSpells so the unified model re-seeds from live icons (buff/CD unification).",
    body = function(ctx)
        -- The buff bar previously never wrote to assignedSpells. With the
        -- unified model, EnsureAssignedSpells lazily seeds from live icons.
        -- Any stale data from the first options-panel open (before the route
        -- map fix for TBB diversions) must be cleared so it re-seeds cleanly.
        local bs = ctx.specProfile.barSpells
        if not bs then return end
        local buffData = bs["buffs"]
        if buffData and buffData.assignedSpells then
            buffData.assignedSpells = nil
        end
    end,
})

--------------------------------------------------------------------------------
--  v6.6 addon split: copy per-module saved data out of EllesmereUIBasics
--  into the new per-addon folders. Lite stores everything under
--  EllesmereUIDB.profiles[p].addons[folder], so this is a straight copy
--  from addons.EllesmereUIBasics.<key> to addons.EllesmereUI<Name>.<key>.
--------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "v66_basics_split_data",
    scope       = "profile",
    description = "Move Basics per-module data into new per-addon folders (Minimap/Friends/Chat/QuestTracker/QoL cursor).",
    body = function(ctx)
        local addons = ctx.profile.addons
        if type(addons) ~= "table" then return end
        local basics = addons.EllesmereUIBasics
        if type(basics) ~= "table" then return end

        local function ensureFolder(name)
            if type(addons[name]) ~= "table" then addons[name] = {} end
            return addons[name]
        end

        -- minimap -> EllesmereUIMinimap.minimap
        if type(basics.minimap) == "table" then
            local dst = ensureFolder("EllesmereUIMinimap")
            if dst.minimap == nil then
                dst.minimap = basics.minimap
            end
        end

        -- friends -> EllesmereUIFriends.friends
        if type(basics.friends) == "table" then
            local dst = ensureFolder("EllesmereUIFriends")
            if dst.friends == nil then
                dst.friends = basics.friends
            end
        end

        -- chat -> EllesmereUIChat.chat (kept for future rebuild even though UI is coming-soon)
        if type(basics.chat) == "table" then
            local dst = ensureFolder("EllesmereUIChat")
            if dst.chat == nil then
                dst.chat = basics.chat
            end
        end

        -- questTracker -> EllesmereUIQuestTracker.questTracker
        if type(basics.questTracker) == "table" then
            local dst = ensureFolder("EllesmereUIQuestTracker")
            if dst.questTracker == nil then
                dst.questTracker = basics.questTracker
            end
        end

        -- cursor -> EllesmereUIQoL.cursor
        if type(basics.cursor) == "table" then
            local dst = ensureFolder("EllesmereUIQoL")
            if dst.cursor == nil then
                dst.cursor = basics.cursor
            end
        end
    end,
})

--------------------------------------------------------------------------------
--  v6.6 addon split: if the user had EllesmereUIBasics disabled for this
--  character, disable the new Minimap/Friends/QuestTracker addons to match
--  (since those now host what Basics used to host). Prompt a reload so the
--  change takes effect.
--------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "v66_basics_split_disabled_state",
    scope       = "global",
    description = "Carry EllesmereUIBasics disabled state onto Minimap/Friends/QuestTracker addons.",
    body = function(ctx)
        if not C_AddOns or not C_AddOns.GetAddOnEnableState then return end
        local char = UnitName("player")
        if not char then return end

        -- GetAddOnEnableState: 0 = disabled, 1 = enabled-for-char, 2 = enabled-for-all
        local basicsState = C_AddOns.GetAddOnEnableState("EllesmereUIBasics", char)
        if basicsState == nil or basicsState ~= 0 then return end

        -- Basics is disabled for this character. Mirror that onto the new addons.
        local targets = { "EllesmereUIMinimap", "EllesmereUIFriends", "EllesmereUIQuestTracker" }
        local disabled = {}
        for _, name in ipairs(targets) do
            local state = C_AddOns.GetAddOnEnableState(name, char)
            if state ~= 0 then
                if C_AddOns.DisableAddOn then
                    C_AddOns.DisableAddOn(name, char)
                    disabled[#disabled + 1] = name
                end
            end
        end

        if #disabled > 0 then
            -- Defer the popup: UI systems aren't ready at this phase.
            C_Timer.After(3, function()
                if EllesmereUI and EllesmereUI.ShowConfirmPopup then
                    EllesmereUI:ShowConfirmPopup({
                        title       = "EllesmereUI Addon Split",
                        message     = "EllesmereUI Basics has been split into separate addons. Since you had Basics disabled, Minimap, Friends, and Quest Tracker have been disabled to match. A reload is required to apply this change.",
                        confirmText = "Reload Now",
                        cancelText  = "Later",
                        onConfirm   = function() ReloadUI() end,
                    })
                end
            end)
        end
    end,
})

--------------------------------------------------------------------------------
--  v67 Bar Texture -> global setting
--
--  The Bar Texture dropdown now writes to db.profile.healthBarTexture instead
--  of per-unit keys. Find the first non-"none" texture among player/target/
--  focus (in that order) and promote it to the global key, then strip the
--  per-unit overrides so nothing silently shadows the global.
--------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "v67_bar_texture_global",
    scope       = "profile",
    description = "Promote per-unit healthBarTexture to a single global profile key.",
    body = function(ctx)
        local uf = ctx.profile.addons and ctx.profile.addons.EllesmereUIUnitFrames
        if type(uf) ~= "table" then return end

        -- Pick the first non-"none" override in the canonical order.
        local winner
        for _, unit in ipairs({ "player", "target", "focus" }) do
            local s = uf[unit]
            local v = type(s) == "table" and s.healthBarTexture
            if type(v) == "string" and v ~= "" and v ~= "none" then
                winner = v; break
            end
        end

        if winner and (uf.healthBarTexture == nil or uf.healthBarTexture == "none") then
            uf.healthBarTexture = winner
        end

        -- Strip per-unit overrides so the global value is the single source.
        for _, unit in ipairs({ "player", "target", "focus", "pet", "totPet", "boss" }) do
            local s = uf[unit]
            if type(s) == "table" then s.healthBarTexture = nil end
        end
    end,
})

--------------------------------------------------------------------------------
--  v6.7.1 Quest Tracker: reset stale enabled=false inherited from Basics.
--
--  The v66_basics_split_data migration copied the entire old
--  EllesmereUIBasics.questTracker table into the new QT addon's profile.
--  The old "enabled" flag meant "disable the custom overlay" (Blizzard's
--  tracker still showed). The new QT uses "enabled" in EvalVisibility to
--  mean "completely hide the tracker." Users who had the old custom tracker
--  disabled inherited enabled=false, which hid the tracker with no way to
--  re-enable it (the option isn't exposed in the new QT settings).
--------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "qt_minimap_reset_stale_enabled_false",
    scope       = "profile",
    description = "Reset quest tracker / minimap enabled=false inherited from the old Basics module.",
    body = function(ctx)
        local addons = ctx.profile.addons
        if type(addons) ~= "table" then return end
        local qt = addons.EllesmereUIQuestTracker
            and addons.EllesmereUIQuestTracker.questTracker
        if type(qt) == "table" and qt.enabled == false then
            qt.enabled = true
        end
        local mm = addons.EllesmereUIMinimap
            and addons.EllesmereUIMinimap.minimap
        if type(mm) == "table" and mm.enabled == false then
            mm.enabled = true
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "mt_bestruns_wipe_v1",
    scope       = "global",
    description = "Wipe obsolete Mythic+ bestRuns data (feature removed). Clears EllesmereUIDB.global.bestRuns and every profile's addons.EllesmereUIMythicTimer.bestRuns.",
    body = function(ctx)
        if ctx.db.global then ctx.db.global.bestRuns = nil end

        local profiles = ctx.db.profiles
        if type(profiles) == "table" then
            for _, profData in pairs(profiles) do
                local mt = profData and profData.addons and profData.addons.EllesmereUIMythicTimer
                if type(mt) == "table" then mt.bestRuns = nil end
            end
        end
    end,
})

local migrationFrame = CreateFrame("Frame")
migrationFrame:RegisterEvent("ADDON_LOADED")
migrationFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "EllesmereUI" then return end
    self:UnregisterEvent("ADDON_LOADED")

    ---------------------------------------------------------------------------
    --  Boot sequence (runs at parent ADDON_LOADED, before child addons init)
    --
    --  1. Beta wipe (NUCLEAR)
    --     For users coming from a pre-v9 SV layout that can't be safely
    --     migrated. If this fires, every SV file is reset and there is
    --     literally nothing left to migrate -- we early-exit so the
    --     registered migrations don't run on already-empty data and waste
    --     cycles attempting to bridge legacy flags that were just wiped.
    --
    --  2. StampResetVersion
    --     Marks fresh installs (no _resetVersion at all) so they never see
    --     the beta-wipe popup on a future load. No-op if already stamped.
    --
    --  3. RunRegisteredMigrations
    --     Runs every migration registered via EllesmereUI.RegisterMigration.
    --     Each migration's body sees the user's intact data because the
    --     beta wipe (step 1) has already returned false here -- if it had
    --     fired we'd never reach this line.
    ---------------------------------------------------------------------------
    if EllesmereUI.PerformResetWipe() then
        -- Wipe fired. Stamp the new reset version and bail. There is no
        -- user data left for migrations to operate on.
        EllesmereUI.StampResetVersion()
        return
    end

    -- Stamp fresh installs early (before child addons can create DBs
    -- that would make StampResetVersion think it's an old install).
    EllesmereUI.StampResetVersion()

    -- Run all migrations registered via EllesmereUI.RegisterMigration.
    -- The runner walks every registered migration and iterates the
    -- appropriate scope (global/profile/specProfile), pcall-wrapping
    -- each body and stamping per-scope flags on success.
    EllesmereUI.RunRegisteredMigrations()

end)
