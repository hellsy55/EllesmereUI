if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local _, ns = ...
local JT = ns.InviteTools
if not JT then return end
local IL = JT.InviteList
local L = JT.L
local Theme = JT.Theme

local CreateFrame = CreateFrame
local UIParent = UIParent
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local UnitName, UnitIsGroupLeader, UnitIsGroupAssistant = UnitName, UnitIsGroupLeader, UnitIsGroupAssistant
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local strsplit = strsplit
local math_max, math_min = math.max, math.min

------------------------------------------------------------------------
-- Invite by List
--
-- Ported from the "Invite by list" part of MRT's Invite Tools module.
-- You keep up to four lists of names ("Name-Realm", one per line), and one
-- button invites everyone on the active list who is not already in your group.
--
-- HOW THE RAID CONVERSION WORKS (same flow as MRT): a party holds five, so
-- with no raid yet only the first four names are invited. The remainder stays
-- queued; once somebody accepts and the group exists, it is converted to a raid
-- and the queue is invited in full. The queue expires so a half-finished
-- attempt cannot invite people minutes later when you have moved on.
------------------------------------------------------------------------

local PREFIX -- addon-message prefix, set in the Share list section
local NUM_LISTS = 1 -- a single list; List2-4 in the saved data are ignored
local PARTY_SIZE = 5
local PENDING_TTL = 120 -- seconds a queued invite stays valid

IL.pendingList = nil
IL.pendingUntil = 0
IL.convertToRaid = false

function IL:UpdateDB()
    local get = _G._EUI_RaidTools_DB
    local root = get and get()
    local current = root and root.profile and root.profile.raidTools and root.profile.raidTools.inviteTools
    if current then
        JT.db = current
    end
    self.db = current or JT.db
end

------------------------------------------------------------------------
-- Names and parsing
------------------------------------------------------------------------

-- Cleans up text that came from chat/Discord before it is split into names:
--   * look-alike apostrophes (` ´ ’ ʼ ...) become a plain ' (Zul`jin -> Zul'jin)
--   * fancy dashes become a plain -
--   * invisible characters (zero-width, non-breaking space, BOM) are removed
-- Returns the cleaned text and how many fixes were made.
local function Sanitize(s)
    local total = 0
    local function rep(pat, with)
        local c
        s, c = s:gsub(pat, with)
        total = total + c
    end
    rep("\226\128[\139-\143]", "")  -- zero-width space/joiners, LRM/RLM
    rep("\226\128[\170-\174]", "")  -- bidi embedding marks
    rep("\226\129\160", "")         -- word joiner
    rep("\239\187\191", "")         -- BOM
    s = s:gsub("\194\160", " ")     -- non-breaking space
    for _, pat in ipairs({ "`", "\194\180", "\202\188", "\202\187", "\226\128\152",
                           "\226\128\153", "\226\128\178", "\239\188\135" }) do
        rep(pat, "'")
    end
    for _, pat in ipairs({ "\226\128\144", "\226\128\145", "\226\128\146", "\226\128\147",
                           "\226\128\148", "\226\136\146" }) do
        rep(pat, "-")
    end
    -- Quotes and bullet dots around names just become spacing.
    for _, pat in ipairs({ "\226\128\156", "\226\128\157", "\226\128\158", "\194\171",
                           "\194\187", "\"", "\226\128\162", "\194\183" }) do
        s = s:gsub(pat, " ")
    end
    return s, total
end

local JUNK_L = "^[%s'%(%)%[%]{}<>%*,;:!%?%.@]+"
local JUNK_R = "[%s'%(%)%[%]{}<>%*,;:!%?%.@]+$"
local function StripJunk(w)
    w = w:gsub(JUNK_L, "")
    w = w:gsub(JUNK_R, "")
    return w
end

local function IsHyphenWord(w)
    return w:find("%S%-%S") ~= nil
end

-- Splits pasted text into character names.
--   * one entry per line (or per comma/semicolon)
--   * "/inv", "/invite", "invite" and other slash commands are dropped
--   * leading bullets/numbers ("-", "*", "1.") are dropped
--   * "Name - Realm" becomes "Name-Realm"; a realm written with spaces after a
--     single Name-Realm ("Name-Argent Dawn", "Name-Area 52") is joined up
-- Returns the list and how many fixes were made.
local function ParseList(text, report)
    local list = {}
    if not text then return list, 0 end
    local seen = {}
    local clean, fixes = Sanitize(text)

    local function add(name)
        name = StripJunk(name)

        -- Check the realm against the realm list (Bartilas -> Barthilas).
        local char, realm = name:match("^([^%-]+)%-(.+)$")
        local RN = JT.RealmNames
        if char and realm and RN then
            local canon, how = RN.Resolve(realm)
            if canon then
                if how == "fuzzy" and report then
                    report.fixed[#report.fixed + 1] = realm .. " -> " .. canon
                end
                name = char .. "-" .. canon
            elseif report then
                report.unknown[#report.unknown + 1] = realm
            end
        end

        if name ~= "" and not seen[name:lower()] then
            seen[name:lower()] = true
            list[#list + 1] = name
        end
    end

    for line in clean:gmatch("[^\n\r;,]+") do
        local words = {}
        for w in line:gmatch("%S+") do words[#words + 1] = w end

        -- Bullets and numbering at the start of a line.
        while words[1] and (words[1]:find("^[%-%*>]+$") or words[1]:find("^%d+[%.%)%:]$")) do
            table.remove(words, 1)
        end

        -- Slash commands (/inv, /invite, /i ...) are not part of the name.
        local kept = {}
        for _, w in ipairs(words) do
            if w:sub(1, 1) == "/" then
                fixes = fixes + 1
            else
                kept[#kept + 1] = w
            end
        end
        words = kept
        if #words > 1 and (words[1]:lower() == "inv" or words[1]:lower() == "invite") then
            table.remove(words, 1)
            fixes = fixes + 1
        end

        -- "Name - Realm"
        local joined, i = {}, 1
        while i <= #words do
            if words[i] == "-" and #joined > 0 and words[i + 1] then
                joined[#joined] = joined[#joined] .. "-" .. words[i + 1]
                i = i + 2
                fixes = fixes + 1
            else
                joined[#joined + 1] = words[i]
                i = i + 1
            end
        end
        words = joined

        local hyphens, firstHyphen = 0, nil
        for idx, w in ipairs(words) do
            if IsHyphenWord(w) then
                hyphens = hyphens + 1
                firstHyphen = firstHyphen or idx
            end
        end

        if hyphens == 1 then
            -- Anything after the only Name-Realm is the rest of the realm name.
            for idx = 1, firstHyphen - 1 do add(words[idx]) end
            add(table.concat(words, "", firstHyphen))
        else
            local acc = {}
            for _, w in ipairs(words) do
                if hyphens >= 2 and #acc > 0 and w:find("^%d+$") and IsHyphenWord(acc[#acc]) then
                    acc[#acc] = acc[#acc] .. w -- "Area 52"
                else
                    acc[#acc + 1] = w
                end
            end
            for _, w in ipairs(acc) do add(w) end
        end
    end
    return list, fixes
end

-- What was typed into ONE row of the list: a single name, so spaces typed by
-- accident ("Name-Ser ver") never turn into extra names. Commas, new lines or
-- several Name-Realm entries still split it.
local function ParseRow(text, report)
    local list, fixes = ParseList(text, report)
    if #list > 1 then
        local clean = Sanitize(text or "")
        if not clean:find("[\n\r;,]") then
            local hyphens = 0
            for w in clean:gmatch("%S+") do
                if IsHyphenWord(w) then hyphens = hyphens + 1 end
            end
            if hyphens < 2 then
                return { table.concat(list, "") }, fixes
            end
        end
    end
    return list, fixes
end

local function NewReport()
    return { fixed = {}, unknown = {} }
end

-- Tells the player which realms were corrected and which were not recognized.
local function PrintReport(report)
    if not report then return end
    local function Uniq(t)
        local out, seen = {}, {}
        for _, v in ipairs(t) do
            if not seen[v:lower()] then
                seen[v:lower()] = true
                out[#out + 1] = v
            end
        end
        return out
    end
    local function Join(t)
        local shown = {}
        for i = 1, math_min(#t, 8) do shown[i] = t[i] end
        local text = table.concat(shown, ", ")
        if #t > 8 then text = text .. " (+" .. (#t - 8) .. ")" end
        return text
    end
    local fixed = Uniq(report.fixed)
    if #fixed > 0 then
        JT:Print(string.format(L["Realm corrected: %s"], Join(fixed)))
    end
    local unknown = Uniq(report.unknown)
    if #unknown > 0 then
        JT:Print(string.format(L["Realm not recognized (kept as typed): %s"], Join(unknown)))
    end
end

local function ShortName(name)
    return (strsplit("-", name))
end

-- Realm-aware character matching ------------------------------------------
-- "Fulano-Server1" and "Fulano-Server2" are two different characters. A name
-- without a realm means a character of MY realm.

-- My realm in comparable form (lower-case, no spaces/apostrophes/dashes).
local function MyRealmKey()
    local r = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
    if type(r) ~= "string" or r == "" then return nil end
    return (r:gsub("[%s'%-]", ""):lower())
end

-- "Name-Realm" -> lower-case name, realm in comparable form (nil if no realm).
local function SplitRealm(n)
    local c, r = n:match("^([^%-]+)%-(.+)$")
    if not c then return n:lower(), nil end
    r = r:gsub("[%s'%-]", "")
    return c:lower(), r:lower()
end

-- Same character? "Foo" (my realm) equals "Foo-MyRealm", never "Foo-OtherRealm".
local function SameChar(a, b)
    local ca, ra = SplitRealm(a)
    local cb, rb = SplitRealm(b)
    if ca ~= cb then return false end
    local mine = MyRealmKey()
    ra = ra or mine
    rb = rb or mine
    if not ra or not rb then return true end
    return ra == rb
end

-- Does this unit token have that character name and (if given) realm?
local function UnitMatches(unit, char, realm)
    if not UnitExists(unit) then return false end
    local uname, urealm = UnitFullName(unit)
    if type(uname) ~= "string" or (issecretvalue and issecretvalue(uname)) then return false end
    if uname:lower() ~= char then return false end
    if not realm then return true end -- no realm written: the name is enough
    if type(urealm) ~= "string" or urealm == "" or (issecretvalue and issecretvalue(urealm)) then
        urealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    end
    return (urealm:gsub("[%s'%-]", ""):lower()) == realm
end

-- Unit token (player / partyN / raidN) of a character in my group, or nil.
local function FindGroupUnit(name)
    if type(name) ~= "string" then return nil end
    local char, realm = SplitRealm(name)
    if UnitMatches("player", char, realm) then return "player" end
    if not IsInGroup() then return nil end
    local n = GetNumGroupMembers() or 0
    if IsInRaid() then
        for i = 1, n do
            if UnitMatches("raid" .. i, char, realm) then return "raid" .. i end
        end
    else
        for i = 1, n - 1 do
            if UnitMatches("party" .. i, char, realm) then return "party" .. i end
        end
    end
    return nil
end

local function InGroup(name)
    return FindGroupUnit(name) ~= nil
end

-- Class file name ("WARRIOR") of a name that is already in the group, or nil.
local function GroupClass(name)
    if not name then return nil end
    local unit = FindGroupUnit(name)
    if not unit then return nil end
    local _, classFile = UnitClass(unit)
    if not classFile or (issecretvalue and issecretvalue(classFile)) then return nil end
    return classFile
end

-- Raid subgroup of everybody in the raid, looked up with SubgroupOf().
-- Returns nil outside a raid (a party has no subgroups).
local function SubgroupMap()
    if not IsInRaid() or not GetRaidRosterInfo then return nil end
    local map = { full = {}, char = {} }
    local mine = MyRealmKey()
    for i = 1, (GetNumGroupMembers() or 0) do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if type(name) == "string" and type(subgroup) == "number"
            and not (issecretvalue and (issecretvalue(name) or issecretvalue(subgroup))) then
            local c, r = SplitRealm(name)
            r = r or mine
            if r then map.full[c .. "-" .. r] = subgroup end
            map.char[c] = map.char[c] or subgroup
        end
    end
    return map
end

local function SubgroupOf(map, name)
    if not map or not name then return nil end
    local c, r = SplitRealm(name)
    if r then return map.full[c .. "-" .. r] end
    local mine = MyRealmKey()
    return (mine and map.full[c .. "-" .. mine]) or map.char[c]
end

local function IsMe(name)
    if type(name) ~= "string" then return false end
    local me = UnitName("player")
    if not me then return false end
    local c, r = SplitRealm(name)
    if c ~= me:lower() then return false end
    return not r or r == MyRealmKey()
end

local function InviteUnit(name)
    -- The client refuses very long "Name-Realm" strings; the short name is
    -- enough then (same guard MRT has).
    if name:len() >= 45 then
        name = ShortName(name)
    end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif _G.InviteUnit then
        _G.InviteUnit(name)
    end
end

local function ConvertToRaid()
    if C_PartyInfo and C_PartyInfo.ConvertToRaid then
        C_PartyInfo.ConvertToRaid()
    elseif _G.ConvertToRaid then
        _G.ConvertToRaid()
    end
end

------------------------------------------------------------------------
-- Invite status + Auto-invite
--
-- Every name that gets invited is tracked, so the list shows what happened
-- to it: queued, pending, suggested (the leader has to accept it), offline,
-- in another group, declined, unfriendly (other faction) or in your group.
--
-- With "Auto-invite" ticked, the names that are still pending, offline or in
-- another group are invited again every N seconds (30 by default, click the
-- timer to change it) until they join, you press Stop, or a name has been
-- tried MAX_ATTEMPTS times. Unfriendly and declined names are never retried.
--
-- Nothing runs while idle: the 1-second ticker and the two event listeners
-- exist only while an invite session is active, and nothing here sends
-- anything in combat (a round that comes due waits until combat is over).
------------------------------------------------------------------------

local INVITE_SPACING = 0.4      -- seconds between invites, so an error can be tied to a name
local DEFAULT_INTERVAL = 30     -- default seconds between automatic retries
local MIN_INTERVAL, MAX_INTERVAL = 5, 600
local MAX_ATTEMPTS = 4          -- a name is invited at most this many times (the first invite counts), then it is marked "Gave up"
local ATTRIBUTION_WINDOW = 3    -- seconds an unnamed error is blamed on the last invite sent
local INVITE_EXPIRE = 60        -- seconds the game keeps an invite open

-- "open" statuses are still being worked on.
local STATUS_INFO = {
    queued     = { text = "Queued",           color = { 0.70, 0.70, 0.70 }, open = true },
    pending    = { text = "Pending",          color = { 1.00, 0.82, 0.00 }, open = true },
    suggested  = { text = "Suggested",        color = { 0.45, 0.75, 1.00 }, open = true },
    offline    = { text = "Offline",          color = { 1.00, 0.55, 0.15 }, open = true },
    othergroup = { text = "In another group", color = { 1.00, 0.55, 0.15 }, open = true },
    ingroup    = { text = "In group",         color = { 0.35, 0.90, 0.35 } },
    declined   = { text = "Declined",         color = { 1.00, 0.30, 0.30 } },
    unfriendly = { text = "Unfriendly",       color = { 1.00, 0.30, 0.30 } },
    noresponse = { text = "No response",      color = { 1.00, 0.30, 0.30 } },
    gaveup     = { text = "Gave up",          color = { 1.00, 0.30, 0.30 } },
    stopped    = { text = "Stopped",          color = { 0.55, 0.55, 0.55 } },
}
-- What the automatic retry goes after.
local RETRY = { pending = true, offline = true, othergroup = true }

IL.state = {}       -- lowercase "name-realm" -> { name, status, attempts, sentAt, order }
IL.sendQueue = {}   -- names waiting to be invited, in order
IL.pumping = false
IL.session = false
IL.nextAt = nil
IL.lastInvite = nil

local function IsReadable(msg)
    return type(msg) == "string" and not (issecretvalue and issecretvalue(msg))
end

-- Turns a localized global string ("Cannot find player '%s'.") into a pattern
-- once, and returns the name it carries (or nil). Works on every client language.
local patternCache = {}
local function MatchGlobal(msg, globalStr)
    if type(globalStr) ~= "string" or not IsReadable(msg) then return nil end
    local pattern = patternCache[globalStr]
    if not pattern then
        pattern = globalStr:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        pattern = pattern:gsub("%%%%s", "(.+)")
        patternCache[globalStr] = pattern
    end
    return msg:match(pattern)
end

local UNFRIENDLY_GLOBALS = {
    "ERR_PLAYER_WRONG_FACTION", "SPELL_FAILED_TARGET_UNFRIENDLY",
    "ERR_TARGET_UNFRIENDLY", "ERR_UNIT_NOT_FRIENDLY",
}

local function IsUnfriendly(msg)
    if not IsReadable(msg) then return false end
    for _, g in ipairs(UNFRIENDLY_GLOBALS) do
        local text = _G[g]
        if type(text) == "string" and msg == text then return true end
    end
    return msg:lower():find("unfriendly", 1, true) ~= nil -- English fallback
end

local function IsOpenStatus(status)
    local info = STATUS_INFO[status]
    return info and info.open or false
end

-- Settings ---------------------------------------------------------------

function IL:AutoOn()
    return not self.db or self.db.AutoInvite ~= false
end

-- Accept party invites from friends, Battle.net friends and guild members.
function IL:FriendlyOn()
    return self.db and self.db.AutoAcceptFriendly == true
end

function IL:SetFriendly(on)
    if not self.db then return end
    self.db.AutoAcceptFriendly = on and true or false
    self:UpdateUI()
end

-- Automatically accept shared lists only when the sender is the current group
-- leader or a raid assistant. Other senders still use the normal popup.
function IL:SharedOn()
    return self.db and self.db.AutoAcceptShared == true
end

function IL:SetShared(on)
    if not self.db then return end
    self.db.AutoAcceptShared = on and true or false
    self:UpdateUI()
end

function IL:GetInterval()
    local v = tonumber(self.db and self.db.AutoInviteInterval) or DEFAULT_INTERVAL
    return math_max(MIN_INTERVAL, math_min(MAX_INTERVAL, math.floor(v)))
end

function IL:SetInterval(v)
    v = math_max(MIN_INTERVAL, math_min(MAX_INTERVAL, math.floor(tonumber(v) or DEFAULT_INTERVAL)))
    self.db.AutoInviteInterval = v
    -- The countdown restarts from the new time.
    if self.session and self:AutoOn() then self.nextAt = GetTime() + v end
    self:UpdateUI()
end

function IL:SetAuto(on)
    self.db.AutoInvite = on and true or false
    if self.session and on then self.nextAt = GetTime() + self:GetInterval() end
    self:UpdateUI()
end

function IL:UpdateUI()
    local f = self.frame
    if f and f.UpdateStatusUI then f.UpdateStatusUI() end
end

-- Tracking ---------------------------------------------------------------

function IL:ForgetName(name)
    if name then self.state[name:lower()] = nil end
end

-- Finds a tracked name from text that may lack the realm. Several tracked
-- characters can share a name (Fulano-Server1 / Fulano-Server2): then the
-- realm decides, and without a realm the one invited last / still open wins.
function IL:FindState(name)
    if not name then return nil end
    local st = self.state[name:lower()]
    if st then return st end
    local char, realm = SplitRealm(name)
    local cands = {}
    for _, s2 in pairs(self.state) do
        local c2, r2 = SplitRealm(s2.name)
        if c2 == char and (not realm or not r2 or r2 == realm) then cands[#cands + 1] = s2 end
    end
    if #cands <= 1 then return cands[1] end
    local li = self.lastInvite
    if li and (GetTime() - li.t) <= ATTRIBUTION_WINDOW then
        for _, c in ipairs(cands) do
            if c.name:lower() == li.name:lower() then return c end
        end
    end
    local best
    for _, c in ipairs(cands) do
        if c.status == "queued" or c.status == "pending" or c.status == "suggested" then
            if not best or (c.order or 0) < (best.order or 0) then best = c end
        end
    end
    return best or cands[1]
end

-- Is the whole roster readable right now? During loading screens or a
-- party -> raid conversion some units are missing for a moment; nobody is
-- treated as gone until the roster is complete.
local function RosterComplete()
    if not IsInGroup() then return false end
    local n = GetNumGroupMembers() or 0
    local raid = IsInRaid()
    local expected = raid and n or n - 1
    local found = 0
    for i = 1, expected do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) then
            local nm = UnitFullName(unit)
            if type(nm) == "string" and nm ~= "" and nm ~= UNKNOWNOBJECT
                and not (issecretvalue and issecretvalue(nm)) then
                found = found + 1
            end
        end
    end
    return found == expected
end

-- Someone in the group right now is "In group". If a tracked list member
-- leaves or is kicked, remove them from the Invite List but preserve History.
-- If I am the one who left the group, keep the Invite List unchanged.
function IL:RefreshMembership()
    local complete, gone
    for key, st in pairs(self.state) do
        if InGroup(st.name) then
            self:MarkInGroup(st)
        elseif st.status == "ingroup" then
            if not IsInGroup() then
                self.state[key] = nil
            else
                if complete == nil then complete = RosterComplete() end
                if complete then
                    self.state[key] = nil
                    gone = gone or {}
                    gone[#gone + 1] = st.name
                end
            end
        end
    end
    if gone then self:DropFromList(gone) end
end

-- History ----------------------------------------------------------------
-- Names that came INTO the group (status "In group") are remembered, newest
-- first, in the saved variables. Only HISTORY_MAX are kept: the 26th pushes
-- the oldest one out, so the file never grows.
local HISTORY_MAX = 25

-- kind: "joined" (default), "declined" or "removed". `how` records why
-- the entry exists ("list", "declined", "removed" or "cleared"). Newest goes
-- first and the same realm-aware character is never listed twice.
function IL:RecordJoin(name, kind, class, how)
    local db = self.db
    if not db or type(name) ~= "string" or name == "" or IsMe(name) then return end
    local hist = db.History
    if type(hist) ~= "table" then
        hist = {}
        db.History = hist
    end
    local keepName = name
    for i = #hist, 1, -1 do
        local e = hist[i]
        if type(e) ~= "table" or type(e.name) ~= "string" then
            table.remove(hist, i)
        elseif SameChar(e.name, name) then
            -- Keep the spelling that carries the realm (it re-invites reliably).
            if e.name:find("-", 1, true) and not name:find("-", 1, true) then keepName = e.name end
            class = class or e.class
            table.remove(hist, i)
        end
    end
    table.insert(hist, 1, {
        name = keepName,
        kind = kind or "joined",
        how = how,
        class = class or GroupClass(keepName),
        t = time(),
    })
    for i = #hist, HISTORY_MAX + 1, -1 do hist[i] = nil end
    local f = self.frame
    if f and f.RefreshHistory then f.RefreshHistory() end
end

-- Adds the time a list-invited player left the current group. History entries
-- created by a decline/removal do not receive a leave time.
function IL:RecordLeave(name)
    local hist = self.db and self.db.History
    if type(hist) ~= "table" or not name then return end
    for i = 1, #hist do
        local e = hist[i]
        if type(e) == "table" and e.kind == "joined" and not e.leftAt
            and type(e.name) == "string" and SameChar(e.name, name) then
            e.leftAt = time()
            local f = self.frame
            if f and f.RefreshHistory then f.RefreshHistory() end
            return
        end
    end
end

-- Safety net for leaves missed by a roster snapshot (for example join+leave
-- inside one fight or a reload). Never reconciles during combat.
function IL:ReconcileLeaves()
    local hist = self.db and self.db.History
    if type(hist) ~= "table" or InCombatLockdown() then return end
    local now = time()
    for i = 1, #hist do
        local e = hist[i]
        if type(e) == "table" and e.kind == "joined" and not e.leftAt
            and type(e.name) == "string" and (now - (e.t or now)) >= 5 and not InGroup(e.name) then
            e.leftAt = now
        end
    end
    local f = self.frame
    if f and f.RefreshHistory then f.RefreshHistory() end
end

-- Keeps a snapshot of the roster. Joining the group by itself no longer writes
-- to History: only a tracked Invite List state reaching MarkInGroup does that.
-- Departures are still observed so joined entries can show their leave time.
function IL:TrackRoster(silent)
    local cur = {}
    local inGroup = IsInGroup()
    if inGroup then
        local n = GetNumGroupMembers() or 0
        local raid = IsInRaid()
        for i = 1, (raid and n or n - 1) do
            local unit = (raid and "raid" or "party") .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local name = GetUnitName(unit, true)
                if IsReadable(name) and name ~= "" and name ~= UNKNOWNOBJECT then
                    local _, classFile = UnitClass(unit)
                    if classFile and issecretvalue and issecretvalue(classFile) then classFile = nil end
                    cur[name:lower()] = { name = name, class = classFile }
                end
            end
        end
    end

    local prev = self.roster
    if inGroup and not self.wasInGroup and not UnitIsGroupLeader("player") then
        self.quietUntil = GetTime() + 5
    end
    if prev then
        for key, e in pairs(prev) do
            if not cur[key] then self:RecordLeave(e.name) end
        end
    end
    self.roster = cur
    self.wasInGroup = inGroup
    if not silent then self:ReconcileLeaves() end
end

function IL:RemoveHistory(name)
    local hist = self.db and self.db.History
    if type(hist) ~= "table" or not name then return end
    local key = name:lower()
    for i = #hist, 1, -1 do
        local e = hist[i]
        if type(e) == "table" and type(e.name) == "string" and e.name:lower() == key then
            table.remove(hist, i)
        end
    end
    local f = self.frame
    if f and f.RefreshHistory then f.RefreshHistory() end
end

function IL:ClearHistory()
    if type(self.db and self.db.History) == "table" then wipe(self.db.History) end
    local f = self.frame
    if f and f.RefreshHistory then f.RefreshHistory() end
end

-- Direct Friend List invites are deliberately excluded from History. If the
-- Invite List later invites the same character, ClearFriendInvited removes the
-- exclusion before that invite is sent.
IL.friendInvited = IL.friendInvited or {}

function IL:IsFriendInvited(name)
    if not name then return false end
    for n in pairs(self.friendInvited) do
        if SameChar(n, name) then return true end
    end
    return false
end

function IL:ClearFriendInvited(name)
    if not name then return end
    for n in pairs(self.friendInvited) do
        if SameChar(n, name) then self.friendInvited[n] = nil end
    end
end

-- Single place that flips a name to "In group", so a list join is recorded once.
function IL:MarkInGroup(st)
    if st.status ~= "ingroup" then
        st.status = "ingroup"
        if not self:IsFriendInvited(st.name) then
            self:RecordJoin(st.name, "joined", nil, "list")
        end
    end
end

function IL:InFlight(name)
    for _, n in ipairs(self.sendQueue) do
        if n == name then return true end
    end
    if self.pendingList then
        for _, n in ipairs(self.pendingList) do
            if n == name then return true end
        end
    end
    return false
end

function IL:StartSession(list)
    self.orderSeq = (self.orderSeq or 0)
    for _, name in ipairs(list) do
        if not IsMe(name) then
            self.orderSeq = self.orderSeq + 1
            self.state[name:lower()] = {
                name = name, attempts = 0, order = self.orderSeq,
                status = InGroup(name) and "ingroup" or "queued",
            }
        end
    end
    self.session = true
    self.nextAt = GetTime() + self:GetInterval()
    if not self.ticker then
        self.ticker = C_Timer.NewTicker(1, function() IL:Tick() end)
    end
    self:RegisterEvent("UI_ERROR_MESSAGE", "OnInviteUIError")
    self:UpdateUI()
end

function IL:EndSession()
    self.session = false
    self.nextAt = nil
    self.lastInvite = nil
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    self:UnregisterEvent("UI_ERROR_MESSAGE")
    self:UpdateUI()
end

-- The Stop button: nothing more is sent, whatever was still open is marked
-- Stopped, and a half-finished raid conversion is dropped.
function IL:StopAuto()
    wipe(self.sendQueue)
    for _, st in pairs(self.state) do
        if IsOpenStatus(st.status) then st.status = "stopped" end
    end
    self.pendingList = nil
    self.convertToRaid = false
    self:EndSession()
end

-- Sending -----------------------------------------------------------------

function IL:QueueInvite(name)
    local key = name:lower()
    local st = self.state[key]
    if not st then
        self.orderSeq = (self.orderSeq or 0) + 1
        st = { name = name, attempts = 0, order = self.orderSeq }
        self.state[key] = st
    end
    for _, n in ipairs(self.sendQueue) do
        if n:lower() == key then return end -- already waiting its turn
    end
    st.status = "queued"
    self.sendQueue[#self.sendQueue + 1] = name
    if not self.pumping then self:Pump() end
end

-- Sends one invite and schedules the next, so each error that comes back can
-- be tied to the name it belongs to.
function IL:Pump()
    self.pumping = false
    if InCombatLockdown() then
        -- Safety guard for a spacing callback that races combat entry. The
        -- combat event clears the queue/session, so nothing resumes afterward.
        self:UpdateUI()
        return
    end

    -- Next name still waiting; skip any that were removed or stopped meanwhile.
    local name, st
    while #self.sendQueue > 0 do
        local candidate = table.remove(self.sendQueue, 1)
        local cst = self.state[candidate:lower()]
        if cst and cst.status == "queued" then
            name, st = candidate, cst
            break
        end
    end

    if name then
        if InGroup(name) then
            self:MarkInGroup(st)
        else
            self.lastInvite = { name = name, t = GetTime() }
            self:ClearFriendInvited(name)
            InviteUnit(name)
            st.status = "pending"
            st.attempts = (st.attempts or 0) + 1
            st.sentAt = GetTime()
        end
    end

    if #self.sendQueue > 0 then
        self.pumping = true
        C_Timer.After(INVITE_SPACING, function() IL:Pump() end)
    end
    self:UpdateUI()
end

-- Re-invites everything that is still worth another try.
function IL:RunRound()
    if InCombatLockdown() then return end
    local retry = {}
    for _, st in pairs(self.state) do
        if RETRY[st.status] or (st.status == "queued" and not self:InFlight(st.name)) then
            if (st.attempts or 0) >= MAX_ATTEMPTS then
                st.status = "gaveup"
            else
                retry[#retry + 1] = st
            end
        end
    end
    if #retry == 0 then return end
    table.sort(retry, function(a, b) return (a.order or 0) < (b.order or 0) end)
    local list = {}
    for i, st in ipairs(retry) do list[i] = st.name end
    self:InviteNames(list, false)
end

-- Once a second while a session is active.
function IL:Tick()
    -- Paused in combat: no retries, no timers moving. The countdown is moved
    -- forward when combat ends (PLAYER_REGEN_ENABLED), so it resumes where it
    -- stopped.
    if InCombatLockdown() then
        self:UpdateUI()
        return
    end
    local now = GetTime()
    local auto = self:AutoOn()

    for _, st in pairs(self.state) do
        if st.status ~= "ingroup" and InGroup(st.name) then self:MarkInGroup(st) end
        if st.status == "suggested" and st.sentAt and (now - st.sentAt) > INVITE_EXPIRE then
            st.status = "noresponse" -- never accepted; a suggestion is not sent again
        end
        if not auto then
            -- Nobody will send these again, so they are final.
            if st.status == "queued" and not self:InFlight(st.name) then
                st.status = "stopped"
            elseif st.status == "pending" and st.sentAt and (now - st.sentAt) > INVITE_EXPIRE then
                st.status = "noresponse"
            end
        end
    end

    if auto and self.nextAt and now >= self.nextAt and not InCombatLockdown() then
        self.nextAt = now + self:GetInterval()
        self:RunRound()
    end

    -- Done when nothing is left to wait for. With Auto-invite off an offline or
    -- "in another group" answer is final too.
    local open = false
    for _, st in pairs(self.state) do
        if st.status == "queued" or st.status == "pending" or st.status == "suggested"
            or (auto and (st.status == "offline" or st.status == "othergroup")) then
            open = true
            break
        end
    end
    if open then
        self:UpdateUI()
    else
        self:EndSession()
    end
end

-- Answers from the game ----------------------------------------------------

-- UI_ERROR_MESSAGE: errorType, message
function IL:OnInviteUIError(_, _, msg)
    if InCombatLockdown() or not IsUnfriendly(msg) then return end
    local li = self.lastInvite
    if not li or (GetTime() - li.t) > ATTRIBUTION_WINDOW then return end
    self.lastInvite = nil
    local st = self.state[li.name:lower()]
    if st then st.status = "unfriendly" end
    JT:Print("|cffff4040" .. string.format(L["Invite to %s failed: %s"], ShortName(li.name), msg) .. "|r")
    self:UpdateUI()
end

-- CHAT_MSG_SYSTEM: text. Always listening (a cheap match), so a decline is
-- recorded in the History even when no invite session is running.
function IL:OnSystemMsg(_, msg)
    if not IsReadable(msg) then return end
    -- Stamp leave time immediately from Blizzard's localized system message,
    -- including while in combat.
    local left = MatchGlobal(msg, _G.ERR_RAID_MEMBER_REMOVED_S) or MatchGlobal(msg, _G.ERR_LEFT_GROUP_S)
    if left then self:RecordLeave(left) end
    if InCombatLockdown() then return end
    local who = MatchGlobal(msg, _G.ERR_DECLINE_GROUP_S)
    if who then
        local st = self:FindState(who)
        if st and not self:IsFriendInvited(st.name) then
            self:RecordJoin(st.name, "declined", nil, "declined")
        end
    end
    if self.session then self:OnInviteSystemMsg(nil, msg) end
end

function IL:PLAYER_ENTERING_WORLD()
    -- Loading screens: take the roster as it is, without recording anyone.
    self:TrackRoster(true)
end

function IL:OnInviteSystemMsg(_, msg)
    if InCombatLockdown() or not IsReadable(msg) then return end

    -- "Invite suggestion sent": you are not the leader, so the invite went to
    -- the leader as a suggestion instead of reaching the player directly.
    local who = MatchGlobal(msg, _G.ERR_INVITE_SUGGESTION_SENT)
    local status = who and "suggested"
    if not who then
        who = MatchGlobal(msg, _G.ERR_DECLINE_GROUP_S)
        status = who and "declined"
    end
    if not who then
        who = MatchGlobal(msg, _G.ERR_ALREADY_IN_GROUP_S)
        status = who and "othergroup"
    end
    if not who then
        who = MatchGlobal(msg, _G.ERR_BAD_PLAYER_NAME_S)
        status = who and "offline"
    end
    if not who then
        -- The "unfriendly" error can show up as a chat line as well.
        self:OnInviteUIError(nil, nil, msg)
        return
    end

    local st = self:FindState(who)
    if not st then return end
    if status == "othergroup" and InGroup(st.name) then
        self:MarkInGroup(st) -- "already in a group": it is yours
    elseif IsOpenStatus(st.status) then
        st.status = status
    end
    self:UpdateUI()
end

------------------------------------------------------------------------
-- Inviting
------------------------------------------------------------------------

-- Invites everyone in `list` who is not already here. Returns how many invites
-- were sent right now.
function IL:InviteNames(list, isContinuation)
    -- Nothing here runs in combat.
    if InCombatLockdown() then return 0 end
    local inRaid = IsInRaid()

    local todo = {}
    for i = 1, #list do
        local name = list[i]
        if not IsMe(name) and not InGroup(name) then
            todo[#todo + 1] = name
        end
    end

    if #todo == 0 then
        self.pendingList = nil
        self.convertToRaid = false
        return 0
    end

    local slots
    if inRaid then
        slots = #todo
    else
        -- A party holds five including you. Whoever does not fit waits for the
        -- raid conversion.
        slots = math_max(0, PARTY_SIZE - math_max(1, GetNumGroupMembers() or 0))
    end

    if not inRaid and #todo > slots then
        self.convertToRaid = true
        if not isContinuation then
            self.pendingList = list
            self.pendingUntil = GetTime() + PENDING_TTL
        end
        -- Already sitting in a full party: no roster event is coming to
        -- trigger the conversion, so do it now.
        self:TryConvertToRaid()
    elseif not inRaid and not isContinuation then
        -- Everyone fits in the party; nothing to queue.
        self.pendingList = nil
        self.convertToRaid = false
    end

    -- Sent one by one (see IL:Pump), so a failure can be tied to a name.
    local sent = 0
    for i = 1, #todo do
        if inRaid or sent < slots then
            self:QueueInvite(todo[i])
            sent = sent + 1
        else
            break
        end
    end
    return sent
end

function IL:TryConvertToRaid()
    if IsInRaid() or not IsInGroup() then return end
    if not UnitIsGroupLeader("player") then return end
    if InCombatLockdown() then return end
    ConvertToRaid()
end

function IL:GetListText(index)
    return self.db["List" .. index] or ""
end

function IL:InviteFromList(index)
    if InCombatLockdown() then
        JT:Print(L["Invite List is disabled in combat."])
        return
    end
    index = tonumber(index) or self.db.Current or 1
    if index < 1 or index > NUM_LISTS then index = 1 end

    local list = ParseList(self:GetListText(index))
    if #list == 0 then
        JT:Print(L["List is empty."])
        return
    end

    self:StartSession(list)
    local sent = self:InviteNames(list, false)
    if sent == 0 and not self.pendingList then
        JT:Print(L["Everyone on the list is already in your group."])
    end
end

local inviteAccepted = false

-- Friend, Battle.net friend or guild member?
local function IsFriendlyGUID(guid)
    if not guid then return false end
    if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID and C_BattleNet.GetGameAccountInfoByGUID(guid) then
        return true
    end
    local wowFriend = C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid)
    local guildFriend = IsGuildMember and IsGuildMember(guid)
    return (wowFriend or guildFriend) and true or false
end

function IL:PARTY_INVITE_REQUEST(_, ...)
    if InCombatLockdown() or not self:FriendlyOn() or IsInGroup() then return end

    local guid
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and not (issecretvalue and issecretvalue(v)) and v:find("^Player%-") then
            guid = v
            break
        end
    end
    if not guid then return end

    -- Do not accept an invite that would pull the player out of a queue.
    local queueButton = _G.QueueStatusButton
    if queueButton and queueButton:IsShown() then return end

    if IsFriendlyGUID(guid) then
        inviteAccepted = true
        AcceptGroup()
    end
end

-- Friend/guild Quick Join requests use Blizzard's confirmation event rather
-- than PARTY_INVITE_REQUEST. Accept only friendly requests that do not carry
-- a queue warning.
function IL:GROUP_INVITE_CONFIRMATION()
    if InCombatLockdown() or not self:FriendlyOn() then return end
    if not (GetNextPendingInviteConfirmation and GetInviteConfirmationInfo and RespondToInviteConfirmation) then return end

    local pending = GetPendingInviteConfirmations and GetPendingInviteConfirmations()
    if type(pending) ~= "table" then
        local one = GetNextPendingInviteConfirmation()
        pending = one and { one } or {}
    end

    local answered
    for _, invite in ipairs(pending) do
        local ctype, _, guid = GetInviteConfirmationInfo(invite)
        local isRequest = ctype == (LE_INVITE_CONFIRMATION_REQUEST or 1)
        if isRequest and type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) then
            local invalid = C_PartyInfo and C_PartyInfo.GetInviteConfirmationInvalidQueues
                and C_PartyInfo.GetInviteConfirmationInvalidQueues(invite)
            local blocked = type(invalid) == "table" and #invalid > 0

            local friendly = IsFriendlyGUID(guid)
            if not friendly and C_PartyInfo and C_PartyInfo.GetInviteReferralInfo then
                local _, _, relation = C_PartyInfo.GetInviteReferralInfo(invite)
                friendly = relation == 1 or relation == 2
            end

            if friendly and not blocked then
                RespondToInviteConfirmation(invite, true)
                answered = true
            end
        end
    end
    if answered then
        StaticPopup_Hide("GROUP_INVITE_CONFIRMATION")
        C_Timer.After(0, function() StaticPopup_Hide("GROUP_INVITE_CONFIRMATION") end)
    end
end

function IL:GROUP_ROSTER_UPDATE()
    if inviteAccepted then
        inviteAccepted = false
        if _G.LFGInvitePopup then StaticPopupSpecial_Hide(_G.LFGInvitePopup) end
        StaticPopup_Hide("PARTY_INVITE")
    end
    if InCombatLockdown() then return end
    self:TrackRoster()
    if next(self.state) then self:RefreshMembership() end
    self:UpdateUI()
    local inRaid = IsInRaid()

    if inRaid then
        self.convertToRaid = false
    elseif self.convertToRaid then
        if self.pendingList and GetTime() > self.pendingUntil then
            self.convertToRaid = false
            self.pendingList = nil
        else
            self:TryConvertToRaid()
        end
    end

    if self.pendingList and inRaid then
        local list = self.pendingList
        self.pendingList = nil
        if GetTime() <= self.pendingUntil then
            self:InviteNames(list, true)
        end
    end
end

function IL:OnEnable()
    self:UpdateDB()
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("PARTY_INVITE_REQUEST")
    self:RegisterEvent("GROUP_INVITE_CONFIRMATION")
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
    self:RegisterEvent("CHAT_MSG_ADDON")
    self:RegisterEvent("CHAT_MSG_SYSTEM", "OnSystemMsg")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("ENCOUNTER_END")
    -- Reloaded while already in combat.
    if self.frame then self.frame.SetLocked(InCombatLockdown()) end
end

-- Combat starts: the window becomes read-only, sharing is cancelled, and
-- auto-invite is PAUSED. Queues, retries and raid-conversion state are kept.
function IL:PLAYER_REGEN_DISABLED()
    self.combatStart = GetTime()
    self:CancelShare()
    if self.frame then self.frame.SetLocked(true) end
    self:UpdateUI()
end

-- Combat ends: move time-based deadlines forward by the paused duration and
-- resume the invite queue/retries exactly where they stopped.
function IL:PLAYER_REGEN_ENABLED()
    local started = self.combatStart
    self.combatStart = nil
    if started then
        local paused = GetTime() - started
        if self.nextAt then self.nextAt = self.nextAt + paused end
        if self.pendingList then self.pendingUntil = self.pendingUntil + paused end
    end
    if self.frame then self.frame.SetLocked(false) end
    if self.pendingKillClear then
        local boss = self.pendingKillClear
        self.pendingKillClear = nil
        if self:KillClearOn() then self:ClearOnKill(boss) end
    end
    if next(self.state) then self:RefreshMembership() end
    if #self.sendQueue > 0 and not self.pumping then self:Pump() end
    self:GROUP_ROSTER_UPDATE()
    self:UpdateUI()
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Share list
--
-- "Share list" offers your list to your group, your guild or the player you
-- are targeting. Everything goes through addon messages, which never show up
-- in chat. To keep it cheap and quiet:
--   * only ONE tiny message is sent first (an offer: id + number of names);
--   * the other side sees a popup and has to press Accept; the names are sent
--     ONLY to people who accepted, by whisper, a few per message and paced
--     out so the game's addon-message limit is never hit;
--   * Decline (or ignoring the popup) costs nothing and sends nothing back;
--   * receivers ignore offers in combat, from people on their ignore list,
--     while another popup is open, and optionally from the same person for
--     the user-configured repeat-share interval;
--   * an offer expires after 1 minute and serves at most 21 people. A new
--     accept is also ignored when the queue could not finish sending to it
--     before the offer expires, so the whole thing is always done within 1 min;
--   * entering combat CANCELS every share (outgoing queue, my offer, the popup
--     and anything I was waiting for). Nothing resumes: somebody has to share
--     again once combat is over;
--   * the list is capped at 100 names (a safety net; real lists are ~15) and
--     every received name is checked.
------------------------------------------------------------------------

PREFIX = "JTInvList"
local SHARE_MAX_NAMES = 100
local SHARE_OFFER_TTL = 60     -- seconds an offer can still be accepted (and the whole send must finish)
local SHARE_MAX_RECIPIENTS = 21  -- only people with the addon receive anything, so this is plenty
local SHARE_COOLDOWN = 5       -- seconds between two shares
local SHARE_CHUNK = 220        -- bytes of names per message
local SHARE_SEND_GAP = 0.3     -- seconds between two outgoing messages
local WAIT_DATA_TTL = 60       -- seconds to wait for the names after Accept
local SEND_MARGIN = 3           -- seconds of slack when checking that a new accept still fits in the offer's time

IL.offer = nil      -- the offer I made: { id, expires, chunks, served, sent = {} }
IL.incoming = nil   -- an offer whose popup is on screen
IL.awaiting = nil   -- an offer I accepted: { sender, id, untilT, parts, got, total }
IL.lastShare = 0
IL.offerSeen = {}

local function NormSender(name)
    return ((Ambiguate and Ambiguate(name, "none")) or name):lower()
end

-- Class colours for share feedback. The class travels with the offer/reply on
-- newer Invite Tools versions; group roster lookup is the fallback.
local classCache = {}
local function ValidClass(classFile)
    return type(classFile) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] and classFile or nil
end
local function ClassOf(name, classFile)
    local key = NormSender(name)
    local cf = ValidClass(classFile)
    if cf then
        local n = 0
        for _ in pairs(classCache) do n = n + 1 end
        if n > 100 then wipe(classCache) end
        classCache[key] = cf
        return cf
    end
    return classCache[key] or ValidClass(GroupClass(name))
end
local function MyClass()
    local _, classFile = UnitClass("player")
    return ValidClass(classFile) or ""
end
local function Who(name, classFile, resume)
    local short = ShortName(name)
    local cf = ClassOf(name, classFile)
    local color = cf and RAID_CLASS_COLORS[cf]
    if not color then return short end
    return string.format("|cff%02x%02x%02x%s|r%s", color.r * 255 + 0.5, color.g * 255 + 0.5, color.b * 255 + 0.5, short, resume or "")
end
local YELLOW, RED = "|cffffd100", "|cffff4040"

local function HistoryClass(db, name)
    local hist = db and db.History
    if type(hist) ~= "table" then return nil end
    for _, e in ipairs(hist) do
        if type(e) == "table" and type(e.name) == "string" and SameChar(e.name, name) then return e.class end
    end
end

function IL:DropFromList(gone)
    if type(self.names) ~= "table" then self.names = ParseList(self:GetListText(1)) end
    local changed = false
    for _, name in ipairs(gone) do
        for k = #self.names, 1, -1 do
            if SameChar(self.names[k], name) then
                local removed = table.remove(self.names, k)
                changed = true
                JT:Print(string.format(L["%s left the group: removed from the list."], Who(removed, HistoryClass(self.db, removed))))
            end
        end
    end
    if changed then
        self:SaveNames()
        if self.frame and self.frame.Layout then self.frame.Layout() end
    end
end

-- Returns true when the game took the message. When it did not, the second
-- value says whether it was only the game's send limit (worth retrying).
local function SafeSend(msg, dist, target)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false, false end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, dist, target)
    if not ok then return false, false end
    local E = Enum and Enum.SendAddonMessageResult
    if res == nil or res == true or res == 0 or (E and res == E.Success) then return true end
    local throttled = E and ((E.AddonMessageThrottle and res == E.AddonMessageThrottle)
        or (E.ChannelThrottle and res == E.ChannelThrottle)) or false
    return false, throttled and true or false
end

-- Outgoing messages go through ONE queue and ONE pacer, so ten people (or
-- forty) accepting at the same moment cannot flood the game's send limit:
--   * a small bucket allows a short burst and then refills slowly (about one
--     message per second), well under what the game tolerates;
--   * if the game still answers "throttled", the message stays at the front
--     of the queue, the bucket is emptied and it is tried again a moment
--     later instead of being lost. A message is tried MAX_SEND_RETRIES times
--     in total (the first send counts), then it is dropped;
--   * nothing is sent in combat: combat cancels the whole queue (see
--     IL:CancelShare).
local BUCKET_MAX = 8               -- messages allowed in a burst
local BUCKET_REFILL = 1            -- messages regained per second
local THROTTLE_RETRY = 1.5         -- seconds before trying again after "throttled"
local MAX_SEND_RETRIES = 4          -- total attempts per message
local tokens, tokensAt = BUCKET_MAX, 0

local function TakeToken()
    local now = GetTime()
    if tokensAt == 0 then tokensAt = now end
    tokens = math_min(BUCKET_MAX, tokens + (now - tokensAt) * BUCKET_REFILL)
    tokensAt = now
    if tokens >= 1 then
        tokens = tokens - 1
        return true
    end
    return false
end

local outQueue, outBusy = {}, false

-- Seconds until the last of `extra` new messages, queued behind what is
-- already waiting, would have been sent.
local function QueueETA(extra)
    local avail = BUCKET_MAX
    if tokensAt ~= 0 then
        avail = math_min(BUCKET_MAX, tokens + (GetTime() - tokensAt) * BUCKET_REFILL)
    end
    local waiting = #outQueue + extra - math.floor(avail)
    return math_max(0, waiting) / BUCKET_REFILL
end

-- Combat started (or sending is otherwise no longer allowed): drop EVERYTHING
-- that has to do with sharing. Nothing resumes by itself; somebody has to
-- share again.
function IL:CancelShare()
    wipe(outQueue)
    self.offer = nil
    if self.awaiting then
        JT:Print(YELLOW .. string.format(L["Cancelled: the list from %s was not received because you entered combat."], Who(self.awaiting.sender, self.awaiting.classFile, YELLOW)) .. "|r")
    end
    self.awaiting = nil
    if self.incoming then
        self.incoming = nil
        if JT.activePrompt then
            JT.activePrompt:Hide()
            JT.activePrompt = nil
        end
    end
    self.lastShare = 0
end

local function PumpOut()
    local item = outQueue[1]
    if not item then
        outBusy = false
        return
    end
    if InCombatLockdown() then
        -- Combat cancels every share; nothing waits for it to end.
        IL:CancelShare()
        outBusy = false
        return
    end
    if not TakeToken() then
        C_Timer.After(0.4, PumpOut)
        return
    end
    local sent, throttled = SafeSend(item.msg, item.dist, item.target)
    if not sent and throttled then
        item.tries = (item.tries or 0) + 1
        if item.tries < MAX_SEND_RETRIES then
            tokens = 0 -- back off: the game said we are going too fast
            C_Timer.After(THROTTLE_RETRY, PumpOut)
            return
        end
    end
    if not sent then
        JT:Print(RED .. L["A share message could not be sent (game limit or unavailable). Try sharing again."] .. "|r")
    end
    table.remove(outQueue, 1)
    C_Timer.After(SHARE_SEND_GAP, PumpOut)
end
local function Enqueue(msg, dist, target)
    outQueue[#outQueue + 1] = { msg = msg, dist = dist, target = target }
    if not outBusy then
        outBusy = true
        PumpOut()
    end
end

local function ValidName(n)
    return type(n) == "string" and #n >= 2 and #n <= 60 and not n:find("[%c~,]")
end

-- Packs names into messages of at most SHARE_CHUNK bytes ("a,b,c").
local function BuildChunks(names)
    local chunks, cur, total = {}, "", 0
    for _, n in ipairs(names) do
        if total >= SHARE_MAX_NAMES then break end
        if ValidName(n) then
            total = total + 1
            if cur == "" then
                cur = n
            elseif #cur + 1 + #n <= SHARE_CHUNK then
                cur = cur .. "," .. n
            else
                chunks[#chunks + 1] = cur
                cur = n
            end
        end
    end
    if cur ~= "" then chunks[#chunks + 1] = cur end
    return chunks, total
end

-- Adds names to my list (skipping duplicates and myself). Works with or
-- without the window ever having been opened.
function IL:MergeNames(incoming)
    local names = self.names or ParseList(self:GetListText(1))
    local have, added, duplicates = {}, 0, 0
    for _, n in ipairs(names) do have[n:lower()] = true end
    for _, n in ipairs(incoming) do
        local key = n:lower()
        if have[key] then
            duplicates = duplicates + 1
        elseif not IsMe(n) then
            have[key] = true
            names[#names + 1] = n
            added = added + 1
        end
    end
    self.names = names
    self:SaveNames()
    if self.frame and self.frame:IsShown() and self.frame.Layout then self.frame.Layout() end
    return added, duplicates
end

local ULATEK_ENCOUNTER_ID = 3492

function IL:KillClearOn()
    return not self.db or self.db.ClearOnBossKill ~= false
end

function IL:SetKillClear(on)
    if not self.db then return end
    self.db.ClearOnBossKill = on and true or false
    self:UpdateUI()
end

function IL:ClearOnKill(bossName)
    self:ClearList("killed")
    JT:Print(string.format(L["%s defeated: list cleared."], bossName or "Ula'tek"))
end

function IL:ENCOUNTER_END(_, encounterID, encounterName, _, _, success)
    if not self:KillClearOn() or success ~= 1 or encounterID ~= ULATEK_ENCOUNTER_ID then return end
    local boss = IsReadable(encounterName) and encounterName or "Ula'tek"
    if InCombatLockdown() then
        self.pendingKillClear = boss
    else
        self:ClearOnKill(boss)
    end
end

local function JoinedEntry(db, name)
    local hist = db and db.History
    if type(hist) ~= "table" then return nil end
    for _, e in ipairs(hist) do
        if type(e) == "table" and e.kind == "joined" and type(e.name) == "string" and SameChar(e.name, name) then
            return e
        end
    end
    return nil
end

-- Empties the whole list. `how` distinguishes a manual Clear List from the
-- automatic Ula'tek kill clear so History can preserve the reason. Existing
-- joined entries keep their joined/left timestamps; a kill adds a green note.
function IL:ClearList(how)
    how = how or "cleared"
    local old = self.names or ParseList(self:GetListText(1))
    for i = #old, 1, -1 do
        local name = old[i]
        if type(name) == "string" and name ~= "" then
            local joined = JoinedEntry(self.db, name)
            if not joined then
                self:RecordJoin(name, "removed", nil, how)
            elseif how == "killed" then
                joined.clearedBy = "killed"
            end
        end
    end
    local f = self.frame
    if f and f.RefreshHistory then f.RefreshHistory() end
    self:StopAuto()
    wipe(self.state)
    self.pendingList = nil
    self.convertToRaid = false
    self.names = {}
    self:SaveNames()
    if self.frame and self.frame.Layout then self.frame.Layout() end
end

-- Sharing is only available while grouped, and only to the group leader or a
-- raid assistant. This rank requirement applies to every destination.
function IL:CanShare()
    if not IsInGroup() then return false end
    return UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant("player")) or false
end

-- Is `name` the leader / a raid assistant of the group I am currently in?
-- Auto Accept Shared Lists trusts only these senders.
function IL:IsLeadOrAssist(name)
    if not name or not IsInGroup() then return false end
    local raid = IsInRaid()
    local n = GetNumGroupMembers() or 0
    for i = 1, (raid and n or n - 1) do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local uname = GetUnitName(unit, true)
            if IsReadable(uname) and type(uname) == "string" and SameChar(uname, name) then
                return UnitIsGroupLeader(unit) or (raid and UnitIsGroupAssistant(unit)) or false
            end
        end
    end
    return false
end

-- mode: "GROUP", "GUILD" or "TARGET". Returns true, or false and a reason.
function IL:Share(mode)
    if InCombatLockdown() then return false, "combat" end
    if not self:CanShare() then return false, "leader" end
    local now = GetTime()
    if now - self.lastShare < SHARE_COOLDOWN then return false, "wait" end

    local dist, target
    if mode == "GROUP" then
        if not IsInGroup() then return false, "unavailable" end
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
            dist = "INSTANCE_CHAT"
        else
            dist = IsInRaid() and "RAID" or "PARTY"
        end
    elseif mode == "GUILD" then
        if not IsInGuild() then return false, "unavailable" end
        dist = "GUILD"
    elseif mode == "TARGET" then
        if not UnitIsPlayer("target") or UnitIsUnit("target", "player") then return false, "unavailable" end
        target = GetUnitName("target", true)
        if not target then return false, "unavailable" end
        dist = "WHISPER"
    else
        return false, "unavailable"
    end

    local names = self.names or ParseList(self:GetListText(1))
    local chunks, count = BuildChunks(names)
    if count == 0 then return false, "empty" end

    local id = string.format("%04x", math.random(0, 65535))
    self.offer = {
        id = id, expires = now + SHARE_OFFER_TTL, chunks = chunks, served = 0,
        sent = {}, replied = {}, replies = 0, result = {},
    }
    self.lastShare = now
    local _, classFile = UnitClass("player")
    Enqueue("O~" .. id .. "~" .. count .. "~" .. (classFile or ""), dist, target)
    return true
end

-- Tiny reply sent back to the player who offered a list. Newer standalone
-- JacaInviteTools versions use the same R packet, while older versions simply
-- ignore it, so the basic O/A/D protocol remains backward-compatible.
-- code: d = declined, t = popup timed out, b = busy, r~added~total = result.
local function SendShareReply(sender, id, code)
    if InCombatLockdown() or type(id) ~= "string" or not id:match("^%x%x%x%x$") then return end
    Enqueue("R~" .. id .. "~" .. code .. "~" .. MyClass(), "WHISPER", sender)
end

-- Somebody offered me their list: ask first, take nothing yet.
function IL:OnShareOffer(sender, id, count, classFile)
    if InCombatLockdown() or IsMe(sender) then return end
    local key = NormSender(sender)

    -- Do not stack share prompts or receive two lists at once. Tell a newer
    -- sender why its offer was not shown; old senders harmlessly ignore R.
    local pending = self.incoming
    if pending and pending.dialog and not pending.dialog:IsShown() then
        self.incoming = nil
        pending = nil
    end
    if pending and GetTime() < pending.untilT then
        SendShareReply(sender, id, "b")
        return
    end
    local awaiting = self.awaiting
    if awaiting and GetTime() > awaiting.untilT then
        self.awaiting = nil
        awaiting = nil
    end
    if awaiting then
        SendShareReply(sender, id, "b")
        return
    end
    if not id:match("^%x%x%x%x$") then return end
    count = tonumber(count)
    if not count or count < 1 or count > SHARE_MAX_NAMES then return end

    local now = GetTime()
    local ignoreSeconds = tonumber(self.db and self.db.ShareIgnoreSeconds) or 30
    ignoreSeconds = math_max(0, ignoreSeconds)
    if ignoreSeconds > 0 then
        local seen = self.offerSeen[key]
        if seen and now - seen < ignoreSeconds then
            SendShareReply(sender, id, "b")
            return
        end
        -- Keep the table small on a long session.
        local n = 0
        for _ in pairs(self.offerSeen) do n = n + 1 end
        if n > 50 then wipe(self.offerSeen) end
        self.offerSeen[key] = now
    end

    if C_FriendList and C_FriendList.IsIgnored then
        local ok, ignored = pcall(C_FriendList.IsIgnored, sender)
        if ok and ignored then return end
    end

    -- Auto-accept only trusted group leadership. The accepted list stays silent
    -- UI-wise: the transfer result is printed in chat, but the main window is
    -- not opened automatically.
    if self:SharedOn() and self:IsLeadOrAssist(sender) then
        self:AcceptShare({
            sender = sender, id = id, count = count, auto = true,
            classFile = ClassOf(sender, classFile),
        })
        return
    end

    -- Sender's name in their class colour (the class comes with the offer).
    local shown = ShortName(sender)
    local color = type(classFile) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then
        shown = string.format("|cff%02x%02x%02x%s|r", color.r * 255 + 0.5, color.g * 255 + 0.5, color.b * 255 + 0.5, shown)
    end

    local data = {
        sender = sender, id = id, count = count, untilT = now + 60,
        classFile = ClassOf(sender, classFile),
    }
    self.incoming = data
    local dialog
    dialog = JT:CreatePrompt({
        title = L["List Share"],
        text = string.format(L["%s wants to share an invite list with you."], shown),
        acceptText = L["Accept"],
        cancelText = L["Decline"],
        acceptColor = { 0.25, 0.90, 0.25 },
        cancelColor = { 1.00, 0.30, 0.30 },
        onAccept = function() IL:AcceptShare(data) end,
        onCancel = function(reason)
            if IL.incoming == data then IL.incoming = nil end
            if not data.answered then
                data.answered = true
                -- The standalone treats either Decline or closing the popup as
                -- a decline for protocol purposes. Keep the local chat print
                -- specific to the explicit Decline button, as requested.
                SendShareReply(data.sender, data.id, "d")
            end
            if reason == "decline" then
                JT:Print(string.format(L["Shared list from %s declined."], shown))
            end
        end,
    })
    data.dialog = dialog

    -- Unanswered offers expire after one minute and report that fact to the
    -- sender.
    C_Timer.After(60, function()
        if not data.answered then
            data.answered = true
            SendShareReply(data.sender, data.id, "t")
        end
        if IL.incoming == data then IL.incoming = nil end
        if dialog and dialog:IsShown() and JT.activePrompt == dialog then
            dialog:Hide()
            JT.activePrompt = nil
        end
    end)
end

-- Accept pressed: tell the sender, then wait for the names. The optional class
-- appended to A is understood by current standalone/EUI and ignored by old
-- parsers that only cared about the id.
function IL:AcceptShare(data)
    self.incoming = nil
    if not data then return end
    data.answered = true
    -- Once accepted, allow a later share from this sender instead of leaving
    -- the anti-repeat timestamp active.
    self.offerSeen[NormSender(data.sender)] = nil
    local awaiting = {
        sender = data.sender, id = data.id, sentCount = data.count,
        untilT = GetTime() + WAIT_DATA_TTL, parts = {}, got = 0,
        classFile = data.classFile, auto = data.auto and true or false,
    }
    self.awaiting = awaiting
    Enqueue("A~" .. data.id .. "~" .. MyClass(), "WHISPER", data.sender)

    -- If the accepted transfer never finishes, report that locally so the
    -- receiver also knows why no names appeared.
    C_Timer.After(WAIT_DATA_TTL + 1, function()
        if IL.awaiting ~= awaiting then return end
        IL.awaiting = nil
        local who = Who(awaiting.sender, awaiting.classFile, RED)
        local msg
        if awaiting.got > 0 then
            msg = string.format(L["List from %s was not received: only part of it arrived within %ds."], who, WAIT_DATA_TTL)
        else
            msg = string.format(L["List from %s was not received: no answer within %ds (they may be in combat, offline, or the offer expired)."], who, WAIT_DATA_TTL)
        end
        JT:Print(RED .. msg .. "|r")
    end)
end

-- Somebody accepted my offer: send them the names and print the sender-side
-- state in the same EllesmereUI Invite Tools chat style as the rest of the
-- module.
function IL:OnShareAccepted(sender, id, classFile)
    ClassOf(sender, classFile)
    local o = self.offer
    if not o or o.id ~= id then return end
    if GetTime() > o.expires then
        JT:Print(YELLOW .. string.format(L["%s accepted your list after the offer expired. Share again."], Who(sender, nil, YELLOW)) .. "|r")
        return
    end
    local key = NormSender(sender)
    if o.sent[key] then return end
    if o.served >= SHARE_MAX_RECIPIENTS then
        JT:Print(YELLOW .. string.format(L["%s accepted your list, but the limit of %d people was reached."], Who(sender, nil, YELLOW), SHARE_MAX_RECIPIENTS) .. "|r")
        return
    end
    -- Would the last message for this person still go out before the offer
    -- expires? If not, do not start a transfer that cannot finish in time.
    if GetTime() + QueueETA(#o.chunks) + SEND_MARGIN > o.expires then
        JT:Print(YELLOW .. string.format(L["%s accepted your list too late to be sent in time. Share again."], Who(sender, nil, YELLOW)) .. "|r")
        return
    end
    o.sent[key] = true
    o.served = o.served + 1
    JT:Print(string.format(L["%s accepted your list. Sending it."], Who(sender)))
    local n = #o.chunks
    for i, chunk in ipairs(o.chunks) do
        Enqueue("D~" .. id .. "~" .. i .. "~" .. n .. "~" .. chunk, "WHISPER", sender)
    end
end

-- R reply from a current standalone/EUI receiver. This is sender-side feedback
-- only; old addon versions never send R and continue to work normally.
local MAX_REPLY_LINES = 10
function IL:OnShareReply(sender, id, code, c, d, e)
    local o = self.offer
    if not o or o.id ~= id then return end
    ClassOf(sender, code == "r" and e or c)
    local key = NormSender(sender)

    if code == "r" then
        if GetTime() > o.expires + WAIT_DATA_TTL + 5 then return end
        if not o.sent[key] or o.result[key] then return end
        local added, total = tonumber(c), tonumber(d)
        if not added or not total or added < 0 or total < 0 or added > total or total > SHARE_MAX_NAMES then return end
        o.result[key] = true
        local whoYellow, who = Who(sender, nil, YELLOW), Who(sender)
        if total == 0 then
            JT:Print(YELLOW .. string.format(L["%s received your list, but it had no usable names."], whoYellow) .. "|r")
        elseif added == 0 then
            JT:Print(YELLOW .. string.format(L["%s received your list, but nothing changed: the names were already on their list."], whoYellow) .. "|r")
        else
            JT:Print(string.format(L["%s received your list: %d new of %d."], who, added, total))
        end
        return
    end

    if GetTime() > o.expires + 30 then return end
    if o.replied[key] or o.sent[key] then return end
    local text
    if code == "d" then
        text = L["%s declined your list."]
    elseif code == "t" then
        text = L["%s did not answer your list (popup ignored)."]
    elseif code == "b" then
        text = L["%s could not look at your list right now (busy)."]
    else
        return
    end
    o.replied[key] = true
    o.replies = o.replies + 1
    if o.replies <= MAX_REPLY_LINES then
        JT:Print(YELLOW .. string.format(text, Who(sender, nil, YELLOW)) .. "|r")
    elseif o.replies == MAX_REPLY_LINES + 1 then
        JT:Print(YELLOW .. L["More people declined or ignored your list."] .. "|r")
    end
end

-- A piece of the names I accepted arrived.
function IL:OnShareData(sender, id, i, n, payload)
    local a = self.awaiting
    if not a or a.id ~= id or GetTime() > a.untilT then return end
    if NormSender(sender) ~= NormSender(a.sender) then return end
    i, n = tonumber(i), tonumber(n)
    if not i or not n or n < 1 or n > 40 or i < 1 or i > n then return end
    if a.total and a.total ~= n then return end
    if type(payload) ~= "string" then return end
    a.total = n
    if not a.parts[i] then
        a.parts[i] = payload
        a.got = a.got + 1
    end
    if a.got < n then return end

    self.awaiting = nil
    self.offerSeen[NormSender(a.sender)] = nil
    local names = {}
    for k = 1, n do
        for name in (a.parts[k] or ""):gmatch("[^,]+") do
            if ValidName(name) and #names < SHARE_MAX_NAMES then names[#names + 1] = name end
        end
    end
    if #names == 0 then
        SendShareReply(a.sender, a.id, "r~0~0")
        JT:Print(YELLOW .. string.format(L["Shared list from %s had no usable names."], Who(a.sender, a.classFile, YELLOW)) .. "|r")
        return
    end

    local added, duplicates = self:MergeNames(names)
    -- Tell a current sender exactly what its list did here. Older senders
    -- ignore this packet.
    SendShareReply(a.sender, a.id, "r~" .. added .. "~" .. #names)

    local sent = tonumber(a.sentCount) or #names
    local msg = string.format(L["Shared list received: %d of %d names accepted."], added, sent)
    if duplicates > 0 then
        msg = msg .. " " .. string.format(L["%d duplicate names ignored."], duplicates)
    end
    JT:Print(msg)
    -- Accepted lists open the window so the new names are right there.
    -- (Declining never gets here, so nothing opens.)
    if not a.auto and not InCombatLockdown() and not (self.frame and self.frame:IsShown()) then
        self:Toggle()
    end
end

function IL:CHAT_MSG_ADDON(_, prefix, text, _, sender)
    if prefix ~= PREFIX then return end
    if type(text) ~= "string" or type(sender) ~= "string" then return end
    if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then return end
    if #text > 255 then return end
    local kind, a, b, c, d, e = strsplit("~", text, 6)
    if kind == "O" and a and b then
        self:OnShareOffer(sender, a, b, c)
    elseif kind == "A" and a then
        if not IsMe(sender) then self:OnShareAccepted(sender, a, b) end
    elseif kind == "R" and a and b then
        if not IsMe(sender) then self:OnShareReply(sender, a, b, c, d, e) end
    elseif kind == "D" and a and b and c and d then
        if not IsMe(sender) then self:OnShareData(sender, a, b, c, d) end
    end
end

local function Color(c, fallback)
    if type(c) == "table" then return c end
    return fallback
end

local function StyleFont(fs, size)
    if JT.ApplyThemeFont then
        JT:ApplyThemeFont(fs, size or "normal")
    else
        fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    end
end

local FRAME_W, FRAME_H = 430, 436
local MIN_W, MIN_H, MAX_W, MAX_H = 380, 300, 800, 900

-- One row per name: a single-line edit box (click it, type, fix a typo, delete
-- letters, Enter to save) and an X to remove the name. This replaces the old
-- big multi-line edit box inside a scroll frame, whose clicks and cursor never
-- behaved reliably. The list is still stored as one name per line, so
-- inviting and the settings tab are unchanged.
local ROW_H = 24
local ROW_GAP = 2
local STATUS_W = 96 -- width of the status column
local CLASS_W = 16  -- class icon next to the number
local HEADER_H = 18 -- column header strip at the top of the list

-- List size: one factor scales everything in the list (row height, number,
-- class icon, name, status, X button, header). 1.00 is the original size and
-- the smallest; the largest is 35% bigger.
local SCALE_MIN, SCALE_MAX = 1.00, 1.35
local listScale = 1
local headerH = HEADER_H

local function ClampScale(v)
    v = tonumber(v) or 1
    return math_max(SCALE_MIN, math_min(SCALE_MAX, v))
end
local function M(v) return math.floor(v * listScale + 0.5) end
local function RowH() return M(ROW_H) end

local function Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- nil resets to the theme colour. The window repaints itself right away.
function IL:SetAccent(r, g, b)
    local f = self.frame
    if r then
        self.db.AccentColor = { r, g, b }
    else
        self.db.AccentColor = nil
        local d = f and f.defaultAccent
        if d then r, g, b = d[1], d[2], d[3] end
    end
    if f and f.ApplyAccent and r then f.ApplyAccent(r, g, b) end
end

-- nil resets the background to the default. The window repaints right away.
-- Alpha is kept with the colour, so the picker's opacity slider works too.
function IL:SetBackground(r, g, b, a)
    local f = self.frame
    if r then
        self.db.BgColor = { r, g, b, a or 1 }
    else
        self.db.BgColor = nil
        local d = f and f.defaultBg
        if d then r, g, b, a = d[1], d[2], d[3], d[4] end
    end
    if f and f.ApplyBackground and r then f.ApplyBackground(r, g, b, a or 1) end
end

-- Background of the names list only (the window has its own, see above).
-- nil goes back to following the window's colour.
function IL:SetListBackground(r, g, b, a)
    local f = self.frame
    if r then
        self.db.ListBgColor = { r, g, b, a or 1 }
    else
        self.db.ListBgColor = nil
    end
    if f and f.ApplyListBackground then f.ApplyListBackground(r, g, b, a) end
end

function IL:SaveNames()
    if not self.names then return end
    self.db["List" .. (self.currentList or 1)] = table.concat(self.names, "\n")
end

function IL:CreateFrame()
    listScale = ClampScale(IL.db.ListScale)
    headerH = M(HEADER_H)
    -- This window's own background colour. Like the accent it is a COPY of
    -- the default, so changing it never touches anything else; the colour set
    -- in the cog menu is saved. bgDark is the window (with its alpha) and the
    -- input plates; bgMedium is the slightly lifted shade used for the list
    -- holder, buttons and slider track, always derived from bgDark.
    local defaultBg = Color(Theme.bgDark, { 0.031, 0.031, 0.031, 0.80 })
    local bgDark = { defaultBg[1], defaultBg[2], defaultBg[3], defaultBg[4] or 1 }
    local savedBg = IL.db.BgColor
    if type(savedBg) == "table" and savedBg[1] and savedBg[2] and savedBg[3] then
        bgDark[1], bgDark[2], bgDark[3], bgDark[4] = savedBg[1], savedBg[2], savedBg[3], savedBg[4] or 1
    end
    local BG_LIFT = 0.024
    local bgMedium = {
        math_min(1, bgDark[1] + BG_LIFT), math_min(1, bgDark[2] + BG_LIFT),
        math_min(1, bgDark[3] + BG_LIFT), 1,
    }
    -- Everything painted with the background colours is registered here, so a
    -- new colour repaints the whole window at once.
    local bgItems = {}
    local function PaintBG(item)
        local o, kind = item[1], item[2]
        local c, a
        if kind == "main" then
            c, a = bgDark, bgDark[4] or 1
        elseif kind == "dark" then
            c, a = bgDark, 1
        else
            c, a = bgMedium, 1
        end
        if item[3] then
            o:SetColorTexture(c[1], c[2], c[3], a)
        else
            o:SetBackdropColor(c[1], c[2], c[3], a)
        end
    end
    local function BG(obj, kind, isTexture)
        local item = { obj, kind, isTexture }
        bgItems[#bgItems + 1] = item
        PaintBG(item)
    end
    local border   = Color(Theme.border,   { 0, 0, 0, 1 })
    -- This window's own accent colour. It is a COPY, so changing it never
    -- touches the addon theme; the colour set in the cog menu is saved.
    local themeAccent = Color(Theme.accent, { 1, 0.82, 0, 1 })
    local accent = { themeAccent[1], themeAccent[2], themeAccent[3], 1 }
    local savedAccent = IL.db.AccentColor
    if type(savedAccent) == "table" and savedAccent[1] and savedAccent[2] and savedAccent[3] then
        accent[1], accent[2], accent[3] = savedAccent[1], savedAccent[2], savedAccent[3]
    end
    Theme.accent[1], Theme.accent[2], Theme.accent[3], Theme.accent[4] = accent[1], accent[2], accent[3], 1
    local textPri  = Color(Theme.textPrimary,   { 1, 1, 1, 1 })
    -- Text that follows the accent colour (labels, buttons, names, title).
    -- Status colours and the red "disabled in combat" stay as they are.
    local tinted = {}
    local function Tint(obj)
        tinted[#tinted + 1] = obj
        obj:SetTextColor(accent[1], accent[2], accent[3], 1)
    end
    local textSec  = Color(Theme.textSecondary, { 0.7, 0.7, 0.7, 1 })

    -- Fonts that follow the list size. The base size is read right after the
    -- theme font is applied, so the scale always starts from the original.
    local scaledFonts = {}
    local function ScaleFont(fs)
        local path, size, flags = fs:GetFont()
        if not path then return end
        scaledFonts[#scaledFonts + 1] = { fs, path, size, flags }
        fs:SetFont(path, math_max(1, M(size)), flags)
    end
    local function ApplyFontScale()
        for i = 1, #scaledFonts do
            local e = scaledFonts[i]
            e[1]:SetFont(e[2], math_max(1, M(e[3])), e[4])
        end
    end

    local backdrop = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    }

    local f = CreateFrame("Frame", "EllesmereUIInviteToolsFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)

    -- Keep the Invite Tools window where the user left it across sessions.
    -- Store a CENTER-to-CENTER offset rather than WoW's transient drag anchor
    -- so the saved position remains stable across reloads and resolution/UI
    -- scale changes. Invalid or now-offscreen values are clamped safely.
    local function ClampSavedPosition(x, y)
        x, y = tonumber(x) or 0, tonumber(y) or 50
        local parentW, parentH = UIParent:GetWidth(), UIParent:GetHeight()
        local frameW, frameH = f:GetWidth(), f:GetHeight()
        local maxX = math_max(0, (parentW - frameW) * 0.5)
        local maxY = math_max(0, (parentH - frameH) * 0.5)
        x = math_max(-maxX, math_min(maxX, x))
        y = math_max(-maxY, math_min(maxY, y))
        return x, y
    end

    local function SavePosition()
        local cx, cy = f:GetCenter()
        local px, py = UIParent:GetCenter()
        if not cx or not cy or not px or not py or not IL.db then return end
        local x, y = ClampSavedPosition(cx - px, cy - py)
        IL.db.PositionX, IL.db.PositionY = x, y
        -- Normalize the anchor after every drag so future reads are predictable.
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end

    -- Resizable through the handle the cog menu's "Unlock" shows. The window
    -- itself is always free to move.
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H) end
    do
        local w, h = tonumber(IL.db.Width), tonumber(IL.db.Height)
        if w and h then
            f:SetSize(math_max(MIN_W, math_min(MAX_W, w)), math_max(MIN_H, math_min(MAX_H, h)))
        end
    end
    do
        -- Clamp only after the saved size is restored, otherwise a larger
        -- window could come back partially offscreen after a resolution change.
        local x, y = ClampSavedPosition(IL.db.PositionX, IL.db.PositionY)
        IL.db.PositionX, IL.db.PositionY = x, y
        f:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    -- Right-clicking the bare window background closes Invite Tools. Child
    -- controls consume their own mouse input, so buttons, edit boxes, the
    -- scrolling list and other interactive widgets are unaffected.
    f:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        GameTooltip:Hide()
        self:Hide()
    end)
    f:SetBackdrop(backdrop)
    BG(f, "main")
    f:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    f:Hide()
    -- Escape closes it, like the other windows.
    tinsert(UISpecialFrames, "EllesmereUIInviteToolsFrame")

    -- Title bar -------------------------------------------------------
    -- EUI embeds the launcher icon in Raid Tools only; the Invite Tools
    -- window keeps the suite's simple centered text header.
    local title = f:CreateFontString(nil, "OVERLAY")
    StyleFont(title, "large")
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText(L["Invite Tools"])
    Tint(title)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -5)
    local closeTex = close:CreateTexture(nil, "ARTWORK")
    closeTex:SetPoint("CENTER")
    closeTex:SetSize(13, 13)
    closeTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    closeTex:SetVertexColor(0.851, 0.851, 0.851, 1)
    close:SetScript("OnEnter", function() closeTex:SetVertexColor(accent[1], accent[2], accent[3], 1) end)
    close:SetScript("OnLeave", function() closeTex:SetVertexColor(0.851, 0.851, 0.851, 1) end)
    close:SetScript("OnClick", function() f:Hide() end)

    -- One combat shield locks the entire Invite Tools window instead of
    -- disabling its children one by one. This avoids stale-widget references
    -- when the UI changes and guarantees that every interaction is blocked in
    -- combat. A translucent grey layer gives the same disabled visual language
    -- as Raid Tools; only the close button is kept above the shield.
    local combatBlocker = CreateFrame("Frame", nil, f)
    combatBlocker:SetAllPoints(f)
    combatBlocker:SetFrameLevel(f:GetFrameLevel() + 100)
    combatBlocker:EnableMouse(true)
    combatBlocker:EnableMouseWheel(true)
    combatBlocker:RegisterForDrag("LeftButton")
    combatBlocker:SetScript("OnMouseWheel", function() end)
    -- Read-only in combat, but the whole disabled surface remains a drag handle.
    combatBlocker:SetScript("OnDragStart", function()
        f:StartMoving()
    end)
    combatBlocker:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SavePosition()
    end)
    -- Right-click is still allowed to close the locked window.
    combatBlocker:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            GameTooltip:Hide()
            f:Hide()
        end
    end)
    local combatShade = combatBlocker:CreateTexture(nil, "BACKGROUND")
    combatShade:SetAllPoints(combatBlocker)
    combatShade:SetColorTexture(0.22, 0.22, 0.22, 0.58)

    local combatText = combatBlocker:CreateFontString(nil, "OVERLAY")
    combatText:SetPoint("CENTER", combatBlocker, "CENTER", 0, 0)
    combatText:SetJustifyH("CENTER")
    combatText:SetJustifyV("MIDDLE")
    StyleFont(combatText, "large")
    combatText:SetScale(1.35)
    combatText:SetTextColor(0.9, 0.9, 0.9, 1)
    combatText:SetText(L["Disabled in combat"])

    combatBlocker:Hide()
    close:SetFrameLevel(combatBlocker:GetFrameLevel() + 1)

    -- Invite Tools settings live exclusively in EllesmereUI Options > Raid Tools.

    -- A small flat button used for the tabs and the invite button.
    local function MakeButton(parent, label)
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetBackdrop(backdrop)
        BG(b, "medium")
        b:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        b.text = b:CreateFontString(nil, "OVERLAY")
        b.text:SetPoint("CENTER")
        StyleFont(b.text, "normal")
        b.text:SetText(label)
        Tint(b.text)
        b:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        end)
        b:SetScript("OnLeave", function(self)
            if self.selected then
                self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
            else
                self:SetBackdropBorderColor(border[1], border[2], border[3], 1)
            end
        end)
        return b
    end

    f.tabs = {}

    -- Hint ------------------------------------------------------------
    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
    hint:SetPoint("TOPRIGHT", f, "TOPRIGHT", -168, -32)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    StyleFont(hint, "small")
    hint:SetTextColor(textSec[1], textSec[2], textSec[3], 1)
    hint:SetText("")

    -- Names (scroll of rows) ------------------------------------------
    -- The list has its own background colour once one is picked in the cog
    -- menu; until then it follows the window (the lifted shade).
    local listBg
    do
        local sv = IL.db.ListBgColor
        if type(sv) == "table" and sv[1] and sv[2] and sv[3] then
            listBg = { sv[1], sv[2], sv[3], sv[4] or 1 }
        end
    end
    local holder = CreateFrame("Frame", nil, f, "BackdropTemplate")
    holder:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -50)
    holder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 124)
    holder:SetBackdrop(backdrop)
    local function ListColor()
        if listBg then return listBg[1], listBg[2], listBg[3], listBg[4] or 1 end
        return bgMedium[1], bgMedium[2], bgMedium[3], 1
    end
    local function PaintList() holder:SetBackdropColor(ListColor()) end
    PaintList()
    holder:SetBackdropBorderColor(border[1], border[2], border[3], 1)

    local scroll = CreateFrame("ScrollFrame", nil, holder)
    scroll:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, -(4 + headerH))
    scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -10, 4)
    scroll:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    content:SetSize(FRAME_W - 20 - 14, 1)
    scroll:SetScrollChild(content)

    -- Column headers at the top: Class, Name and Status. Nothing above the
    -- number column.
    local function NameX() return 4 + 2 + M(22) + 4 + M(CLASS_W) + 4 + 6 end -- scroll inset, number, icon, edit text inset
    local headName = holder:CreateFontString(nil, "OVERLAY")
    headName:SetPoint("TOPLEFT", holder, "TOPLEFT", NameX(), -5)
    headName:SetJustifyH("LEFT")
    StyleFont(headName, "small")
    Tint(headName)
    ScaleFont(headName)
    headName:SetText(L["Name"])

    -- "Class" is centred over the class icon column.
    local function ClassX() return 4 + 2 + M(22) + 4 + math.floor(M(CLASS_W) / 2) end
    local headClass = holder:CreateFontString(nil, "OVERLAY")
    headClass:SetPoint("TOP", holder, "TOPLEFT", ClassX(), -5)
    StyleFont(headClass, "small")
    Tint(headClass)
    ScaleFont(headClass)
    headClass:SetText(L["Class"])

    local headStatus = holder:CreateFontString(nil, "OVERLAY")
    headStatus:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -(10 + 2 + M(20) + 4), -5) -- lines up with the status column
    headStatus:SetWidth(M(STATUS_W))
    headStatus:SetJustifyH("RIGHT")
    StyleFont(headStatus, "small")
    Tint(headStatus)
    ScaleFont(headStatus)
    headStatus:SetText(L["Status"])

    local headLine = holder:CreateTexture(nil, "ARTWORK")
    headLine:SetHeight(1)
    headLine:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, -(4 + headerH) + 1)
    headLine:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -4, -(4 + headerH) + 1)
    headLine:SetColorTexture(border[1], border[2], border[3], 1)

    local emptyText = holder:CreateFontString(nil, "OVERLAY")
    emptyText:SetPoint("TOP", holder, "TOP", 0, -(14 + headerH))
    StyleFont(emptyText, "normal")
    emptyText:SetTextColor(textSec[1], textSec[2], textSec[3], 1)
    emptyText:SetText(L["List is empty."])
    emptyText:Hide()

    -- Re-anchors everything that depends on the list size.
    local function PlaceHeaders()
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, -(4 + headerH))
        scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -10, 4)
        headLine:ClearAllPoints()
        headLine:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, -(4 + headerH) + 1)
        headLine:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -4, -(4 + headerH) + 1)
        headClass:ClearAllPoints()
        headClass:SetPoint("TOP", holder, "TOPLEFT", ClassX(), -5)
        headName:ClearAllPoints()
        headName:SetPoint("TOPLEFT", holder, "TOPLEFT", NameX(), -5)
        headStatus:ClearAllPoints()
        headStatus:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -(10 + 2 + M(20) + 4), -5)
        headStatus:SetWidth(M(STATUS_W))
        emptyText:ClearAllPoints()
        emptyText:SetPoint("TOP", holder, "TOP", 0, -(14 + headerH))
    end

    -- Thin scroll indicator on the right.
    local thumb = holder:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(accent[1], accent[2], accent[3], 0.6)
    thumb:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -4, -(4 + headerH))
    thumb:Hide()

    local function UpdateThumb()
        local viewH = scroll:GetHeight()
        local contentH = content:GetHeight()
        if not viewH or viewH <= 0 or contentH <= viewH + 1 then
            thumb:Hide()
            return
        end
        local range = contentH - viewH
        local thumbH = math_max(16, viewH * (viewH / contentH))
        local pos = ((scroll:GetVerticalScroll() or 0) / range) * (viewH - thumbH)
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -4, -(4 + headerH) - pos)
        thumb:Show()
    end

    scroll:SetScript("OnMouseWheel", function(self, delta)
        if InCombatLockdown() then return end -- no scrolling in combat either
        local range = self:GetVerticalScrollRange() or 0
        local new = (self:GetVerticalScroll() or 0) - delta * (RowH() + ROW_GAP) * 2
        self:SetVerticalScroll(math_max(0, math_min(range, new)))
    end)
    scroll:SetScript("OnVerticalScroll", UpdateThumb)
    scroll:SetScript("OnScrollRangeChanged", UpdateThumb)

    local rows = {}
    local locked = false
    local friendlyFill
    local layingOut = false

    local function SetWidgetEnabled(w, enabled)
        if not w then return end
        if w.SetEnabled then
            w:SetEnabled(enabled)
        elseif enabled then
            w:Enable()
        else
            w:Disable()
        end
        -- Belt and braces: a locked widget takes no clicks at all.
        if w.EnableMouse then w:EnableMouse(enabled) end
    end
    local Layout -- forward declaration

    local addBox -- forward declaration (used by ClearAllFocus)
    local timerEdit -- forward declaration (used by ClearAllFocus)

    local function ClearAllFocus()
        for i = 1, #rows do
            if rows[i].edit:HasFocus() then rows[i].edit:ClearFocus() end
        end
        if addBox and addBox:HasFocus() then addBox:ClearFocus() end
        if timerEdit and timerEdit:HasFocus() then timerEdit:ClearFocus() end
    end

    -- Applies what was typed in a row to the stored list.
    local function Commit(row)
        if layingOut then return end
        local names = IL.names
        local i = row.index
        if not (names and i and row.name and names[i] == row.name) then return end

        local report = NewReport()
        local tokens = ParseRow(Trim(row.edit:GetText() or ""), report)
        PrintReport(report)
        if #tokens == 1 and tokens[1] == row.name then
            -- Same name; just tidy what is shown (stray spaces etc.).
            row.edit:SetText(row.name)
            row.edit:SetCursorPosition(0)
            return
        end

        IL:ForgetName(row.name) -- renamed or removed: its status goes with it
        if #tokens == 0 then
            table.remove(names, i) -- emptied the row: the name is gone
        else
            names[i] = tokens[1]
            -- Several names typed/pasted into one row: split them into rows.
            for k = 2, #tokens do
                table.insert(names, i + k - 1, tokens[k])
            end
        end
        IL:SaveNames()
        Layout()
    end

    local function MakeRow()
        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(RowH())

        row.num = row:CreateFontString(nil, "OVERLAY")
        row.num:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.num:SetWidth(M(22))
        row.num:SetJustifyH("RIGHT")
        StyleFont(row.num, "small")
        ScaleFont(row.num)
        row.num:SetTextColor(textSec[1], textSec[2], textSec[3], 1)

        -- Class icon, filled in only for names that are already in the group.
        row.class = row:CreateTexture(nil, "ARTWORK")
        row.class:SetSize(M(CLASS_W), M(CLASS_W))
        row.class:SetPoint("LEFT", row.num, "RIGHT", 4, 0)
        row.class:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        row.class:Hide()

        local del = CreateFrame("Button", nil, row)
        del:SetSize(M(20), RowH())
        del:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        local delTex = del:CreateTexture(nil, "ARTWORK")
        delTex:SetPoint("CENTER")
        delTex:SetSize(M(11), M(11))
        delTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
        delTex:SetVertexColor(0.6, 0.6, 0.6, 1)
        del:SetScript("OnEnter", function() delTex:SetVertexColor(1, 0.3, 0.3, 1) end)
        del:SetScript("OnLeave", function() delTex:SetVertexColor(0.6, 0.6, 0.6, 1) end)
        del:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            local name = row.name
            -- Drop whatever was half-typed in this row instead of saving it.
            if row.edit:HasFocus() then row.edit.revert = true end
            ClearAllFocus()
            if not name or not IL.names then return end
            for k, n in ipairs(IL.names) do
                if n:lower() == name:lower() then
                    table.remove(IL.names, k)
                    IL:RecordJoin(n, "removed", nil, "removed") -- removed with the X: goes to the history
                    break
                end
            end
            IL:ForgetName(name)
            IL:SaveNames()
            Layout()
        end)

        row.status = row:CreateFontString(nil, "OVERLAY")
        row.status:SetPoint("RIGHT", del, "LEFT", -4, 0)
        row.status:SetWidth(M(STATUS_W))
        row.status:SetJustifyH("RIGHT")
        StyleFont(row.status, "small")
        ScaleFont(row.status)

        local e = CreateFrame("EditBox", nil, row, "BackdropTemplate")
        e:SetAutoFocus(false)
        e:SetMaxLetters(100)
        e:SetTextInsets(6, 6, 0, 0)
        e:SetHeight(RowH() - 2)
        e:SetPoint("LEFT", row.class, "RIGHT", 4, 0)
        e:SetPoint("RIGHT", row.status, "LEFT", -4, 0)
        StyleFont(e, "normal")
        ScaleFont(e)
        Tint(e)
        e:SetBackdrop(backdrop)
        BG(e, "dark")
        e:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        e:SetScript("OnEditFocusGained", function(self)
            self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        end)
        e:SetScript("OnEditFocusLost", function(self)
            self:SetBackdropBorderColor(border[1], border[2], border[3], 1)
            if self.revert then
                self.revert = nil
                self:SetText(row.name or "")
                self:SetCursorPosition(0)
            else
                Commit(row)
            end
        end)
        e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        e:SetScript("OnEscapePressed", function(self)
            self.revert = true
            self:ClearFocus()
        end)
        e:SetScript("OnTabPressed", function(self)
            local nxt = rows[(row.index or 0) + 1]
            if nxt and nxt:IsShown() then
                nxt.edit:SetFocus()
            else
                self:ClearFocus()
            end
        end)

        row.edit = e
        row.del = del
        row.delTex = delTex
        if locked then
            SetWidgetEnabled(e, false)
            SetWidgetEnabled(del, false)
        end
        return row
    end

    -- Paints each visible row's status from the tracked state.
    local function UpdateRowStatuses()
        local states = IL.state
        local subgroups = SubgroupMap() -- raid only
        for i = 1, #rows do
            local row = rows[i]
            local st = row.name and states and states[row.name:lower()]
            local info = st and STATUS_INFO[st.status]
            -- Class icon: only while the name is in the group, blank otherwise.
            local coords
            local classFile = row.name and GroupClass(row.name)
            if classFile then coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile] end
            if coords then
                row.class:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                row.class:Show()
            else
                row.class:Hide()
            end
            -- "In group - G8": which raid subgroup the name sits in.
            local sub = SubgroupOf(subgroups, row.name)
            local subText = sub and (" - G" .. sub) or ""
            if info then
                row.status:SetText(L[info.text] .. (st.status == "ingroup" and subText or ""))
                row.status:SetTextColor(info.color[1], info.color[2], info.color[3], 1)
            elseif row.name and InGroup(row.name) then
                -- Nothing happened to this name, but it is already with you.
                row.status:SetText(L["In group"] .. subText)
                row.status:SetTextColor(0.35, 0.90, 0.35, 1)
            elseif row.name then
                -- Default: not in the group and no invite activity yet.
                row.status:SetText(L["Not in group"])
                row.status:SetTextColor(0.55, 0.55, 0.55, 1)
            else
                row.status:SetText("")
            end
        end
    end

    Layout = function()
        local names = IL.names or {}
        layingOut = true
        for i = 1, #names do
            local row = rows[i]
            if not row then
                row = MakeRow()
                rows[i] = row
            end
            row.index = i
            row.name = names[i]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i - 1) * (RowH() + ROW_GAP)))
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((i - 1) * (RowH() + ROW_GAP)))
            row.num:SetText(i)
            -- Leave the text alone while someone is typing in it, so the cursor
            -- does not jump.
            if row.edit:GetText() ~= names[i] then
                row.edit:SetText(names[i])
                row.edit:SetCursorPosition(0)
            end
            row:Show()
        end
        for i = #names + 1, #rows do
            local row = rows[i]
            if row.edit:HasFocus() then row.edit:ClearFocus() end
            row.edit.revert = nil
            row.name = nil
            row.index = nil
            row:Hide()
        end
        content:SetHeight(math_max(1, #names * (RowH() + ROW_GAP)))
        emptyText:SetShown(#names == 0)
        layingOut = false
        UpdateRowStatuses()
        UpdateThumb()
    end

    scroll:SetScript("OnSizeChanged", function(_, w)
        if w and w > 0 then content:SetWidth(w) end
        Layout()
    end)

    -- Add box ---------------------------------------------------------
    addBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    -- Multi-line on purpose: a single-line edit box strips the line breaks when
    -- you paste, which glued "Name-Realm" entries together into one long name.
    addBox:SetMultiLine(true)
    addBox:SetAutoFocus(false)
    addBox:SetMaxLetters(0)
    addBox:SetTextInsets(6, 6, 4, 0)
    addBox:SetHeight(24)
    addBox:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 40)
    addBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 40)
    StyleFont(addBox, "normal")
    Tint(addBox)
    addBox:SetBackdrop(backdrop)
    BG(addBox, "dark")
    addBox:SetBackdropBorderColor(border[1], border[2], border[3], 1)

    local placeholder = addBox:CreateFontString(nil, "OVERLAY")
    placeholder:SetPoint("LEFT", addBox, "LEFT", 7, 0)
    StyleFont(placeholder, "normal")
    placeholder:SetTextColor(textSec[1], textSec[2], textSec[3], 0.8)
    placeholder:SetText(L["Paste names here"])

    -- Adds every name in the box to the current list and clears the box.
    local adding = false
    local function ProcessAdd()
        if adding then return end
        local report = NewReport()
        local tokens, fixes = ParseList(addBox:GetText() or "", report)
        if #tokens == 0 or not IL.names then return end
        PrintReport(report)
        if fixes and fixes > 0 then
            JT:Print(L["Cleaned up the pasted names (fixed odd characters, removed /inv and similar)."])
        end
        adding = true
        addBox:SetText("")
        adding = false
        placeholder:Show()

        local have = {}
        for _, n in ipairs(IL.names) do have[n:lower()] = true end
        for _, n in ipairs(tokens) do
            local key = n:lower()
            if not have[key] then
                have[key] = true
                IL.names[#IL.names + 1] = n
            end
        end
        IL:SaveNames()
        Layout()
        -- The scroll range is only updated on the next frame.
        C_Timer.After(0, function()
            scroll:SetVerticalScroll(scroll:GetVerticalScrollRange() or 0)
            UpdateThumb()
        end)
    end

    -- Typing adds one character per change; a paste adds several at once. A
    -- paste (a whole list or a single name) or Enter adds right away.
    local prevLen = 0
    addBox:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText() or ""
        local len = strlenutf8(text)
        placeholder:SetShown(text == "")
        local pasted = userInput and (len - prevLen) > 1
        prevLen = len
        if userInput and (pasted or text:find("[\n\r]")) then
            ProcessAdd()
            prevLen = 0
        end
    end)
    addBox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    end)
    addBox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        -- Clicking away leaves what was typed in the box. Enter (or pasting) adds it.
    end)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    addBox:SetScript("OnEnterPressed", ProcessAdd)

    addBox:ClearAllPoints()
    addBox:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 40)
    addBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 40)

    -- Invite button ---------------------------------------------------
    local invite = MakeButton(f, L["Invite"])
    invite:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
    invite:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    invite:SetHeight(24)
    invite:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        ClearAllFocus()
        IL:InviteFromList(IL.currentList)
    end)

    -- Auto-invite controls: [x] Auto-invite [30s]            [Stop] ---------
    local bar = CreateFrame("Frame", nil, f)
    bar:SetHeight(22)
    bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 68)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 68)

    local check = CreateFrame("Button", nil, bar, "BackdropTemplate")
    check:SetSize(18, 18)
    check:SetPoint("LEFT", bar, "LEFT", 0, 0)
    check:SetBackdrop(backdrop)
    BG(check, "dark")
    check:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    local checkFill = check:CreateTexture(nil, "ARTWORK")
    checkFill:SetPoint("TOPLEFT", check, "TOPLEFT", 4, -4)
    checkFill:SetPoint("BOTTOMRIGHT", check, "BOTTOMRIGHT", -4, 4)
    checkFill:SetColorTexture(accent[1], accent[2], accent[3], 1)

    local checkLabel = bar:CreateFontString(nil, "OVERLAY")
    checkLabel:SetPoint("LEFT", check, "RIGHT", 6, 0)
    StyleFont(checkLabel, "normal")
    Tint(checkLabel)
    checkLabel:SetText(L["Auto-invite"])
    -- Clicking the words ticks the box too.
    check:SetHitRectInsets(0, -((checkLabel:GetStringWidth() or 0) + 8), 0, 0)

    local timerBtn = MakeButton(bar, "")
    timerBtn:SetSize(58, 20)
    timerBtn:SetPoint("LEFT", checkLabel, "RIGHT", 12, 0)

    local stop = MakeButton(bar, L["Stop"])
    stop:SetSize(70, 20)
    stop:SetPoint("RIGHT", bar, "RIGHT", 0, 0)

    -- Typing box that appears over the timer when it is clicked.
    timerEdit = CreateFrame("EditBox", nil, bar, "BackdropTemplate")
    timerEdit:SetAutoFocus(false)
    timerEdit:SetMaxLetters(5)
    timerEdit:SetJustifyH("CENTER")
    timerEdit:SetAllPoints(timerBtn)
    timerEdit:SetFrameLevel(timerBtn:GetFrameLevel() + 3)
    StyleFont(timerEdit, "normal")
    Tint(timerEdit)
    timerEdit:SetBackdrop(backdrop)
    BG(timerEdit, "dark")
    timerEdit:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    timerEdit:Hide()

    local function UpdateStatusUI()
        UpdateRowStatuses()
        checkFill:SetShown(IL:AutoOn())
        local text, c
        if IL.session and InCombatLockdown() then
            text = L["Paused"] -- combat: the countdown is frozen
            c = textSec
        elseif IL.session and IL:AutoOn() and IL.nextAt then
            text = math_max(0, math.ceil(IL.nextAt - GetTime())) .. "s"
            c = accent
        elseif IL.session then
            text = "--" -- running, but Auto-invite is off
            c = textSec
        else
            text = IL:GetInterval() .. "s" -- idle: shows the retry time
            c = textSec
        end
        timerBtn.text:SetText(text)
        timerBtn.text:SetTextColor(c[1], c[2], c[3], 1)
        stop:SetAlpha(IL.session and 1 or 0.5)
        if friendlyFill then friendlyFill:SetShown(IL:FriendlyOn()) end
    end

    check:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        IL:SetAuto(not IL:AutoOn())
    end)
    check:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(L["Auto-invite"], 1, 1, 1)
        GameTooltip:AddLine(L["Invites again the names that are pending, offline or in another group, until they join or you press Stop."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        GameTooltip:Hide()
    end)

    timerBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(string.format(L["Retry every %ds"], IL:GetInterval()), 1, 1, 1)
        GameTooltip:AddLine(L["Click to change the time."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    timerBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    timerBtn:SetScript("OnClick", function()
        if InCombatLockdown() or locked then return end
        GameTooltip:Hide()
        timerEdit:SetText(tostring(IL:GetInterval()))
        timerEdit:Show()
        timerEdit:SetFocus()
        timerEdit:HighlightText()
    end)

    timerEdit:SetScript("OnEnterPressed", function(self)
        local n = tonumber((self:GetText() or ""):match("%d+"))
        self:ClearFocus() -- hides the box
        if n and not InCombatLockdown() then IL:SetInterval(n) end
    end)
    timerEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    timerEdit:SetScript("OnEditFocusLost", function(self)
        self:Hide()
        UpdateStatusUI()
    end)

    stop:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        ClearAllFocus()
        IL:StopAuto()
    end)

    -- Clear list -----------------------------------------------------------
    local clear = MakeButton(f, L["Clear list"])
    clear:SetSize(70, 20)
    clear:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 94)
    local clearToken = 0
    local function DisarmClear()
        clearToken = clearToken + 1
        clear.text:SetText(L["Clear list"])
        clear.armed = nil
    end
    clear:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Clear list"], 1, 1, 1)
        GameTooltip:AddLine(L["Removes every name from the list. Click twice to confirm."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    clear:HookScript("OnLeave", function() GameTooltip:Hide() end)
    clear:SetScript("OnClick", function()
        if InCombatLockdown() or locked then return end
        if #(IL.names or {}) == 0 then return end
        if not clear.armed then
            -- First click arms it, so one slip cannot wipe the list.
            clear.armed = true
            clear.text:SetText(L["Confirm?"])
            clearToken = clearToken + 1
            local mine = clearToken
            C_Timer.After(3, function()
                if clearToken == mine and clear.armed then DisarmClear() end
            end)
            return
        end
        DisarmClear()
        ClearAllFocus()
        IL:ClearList()
    end)

    -- Share list: button above the Status column, with a small menu --------
    local shareBtn = MakeButton(f, L["Share list"])
    shareBtn:SetSize(84, 18)
    shareBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -29)

    local shareMenu = CreateFrame("Frame", nil, f, "BackdropTemplate")
    shareMenu:SetSize(84, 3 * 20 + 4)
    shareMenu:SetPoint("TOPRIGHT", shareBtn, "BOTTOMRIGHT", 0, -2)
    shareMenu:SetFrameLevel(f:GetFrameLevel() + 40)
    shareMenu:EnableMouse(true)
    shareMenu:SetBackdrop(backdrop)
    BG(shareMenu, "dark")
    shareMenu:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    shareMenu:Hide()

    local shareToken = 0
    local function ShareFeedback(text)
        shareToken = shareToken + 1
        local mine = shareToken
        shareBtn.text:SetText(text)
        C_Timer.After(2, function()
            if shareToken == mine then shareBtn.text:SetText(L["Share list"]) end
        end)
    end

    local function ModeAvailable(mode)
        if not IL:CanShare() then return false end
        if mode == "GROUP" then return IsInGroup() end
        if mode == "GUILD" then return IsInGuild() end
        return UnitIsPlayer("target") and not UnitIsUnit("target", "player")
    end

    local shareOptions = {}
    for idx, opt in ipairs({
        { mode = "GROUP",  label = L["Group"] },
        { mode = "GUILD",  label = L["Guild"] },
        { mode = "TARGET", label = L["Target"] },
    }) do
        local b = MakeButton(shareMenu, opt.label)
        b:SetPoint("TOPLEFT", shareMenu, "TOPLEFT", 2, -2 - (idx - 1) * 20)
        b:SetPoint("TOPRIGHT", shareMenu, "TOPRIGHT", -2, -2 - (idx - 1) * 20)
        b:SetHeight(20)
        b.mode = opt.mode
        b:SetScript("OnClick", function(self)
            if InCombatLockdown() or locked then return end
            shareMenu:Hide()
            if not IL:CanShare() then
                ShareFeedback(L["Leader/assist only"])
                return
            end
            if not ModeAvailable(self.mode) then
                ShareFeedback(L["Not available"])
                return
            end
            local ok, why = IL:Share(self.mode)
            if ok then
                ShareFeedback(L["Sent"])
            elseif why == "empty" then
                ShareFeedback(L["List is empty."])
            elseif why == "leader" then
                ShareFeedback(L["Leader/assist only"])
            else
                ShareFeedback(L["Not available"])
            end
        end)
        shareOptions[#shareOptions + 1] = b
    end

    local function OpenShareMenu()
        GameTooltip:Hide()
        for _, b in ipairs(shareOptions) do
            b:SetAlpha(ModeAvailable(b.mode) and 1 or 0.4)
        end
        shareMenu:Show()
    end

    shareBtn:SetScript("OnClick", function()
        if InCombatLockdown() or locked then return end
        if shareMenu:IsShown() then shareMenu:Hide() else OpenShareMenu() end
    end)
    shareBtn:HookScript("OnEnter", function(self)
        if shareMenu:IsShown() then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Share list"], 1, 1, 1)
        GameTooltip:AddLine(L["Offers your list to your group, your guild or your target. They get a popup and choose Accept or Decline. Nothing is written in chat."], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["Only the group leader or a raid assistant can share."], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    shareBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- The menu closes by itself when the mouse stays away from it.
    do
        local away = 0
        shareMenu:SetScript("OnShow", function() away = 0 end)
        shareMenu:SetScript("OnUpdate", function(self, elapsed)
            if self:IsMouseOver() or shareBtn:IsMouseOver() then
                away = 0
            else
                away = away + elapsed
                if away > 0.6 then self:Hide() end
            end
        end)
    end

    -- Friend List is built after History; History needs to know which side it occupies.
    local friends, friendsOnLeft = nil, true
    local PlaceHistory, PlaceFriends

    -- History: names that joined your group, with a Re-invite button --------
    local HIST_W, HIST_ROW_H, HIST_GAP = 250, 22, 2
    local historyBtn = MakeButton(f, L["History"])
    historyBtn:SetSize(64, 18)
    historyBtn:SetPoint("RIGHT", shareBtn, "LEFT", -4, 0)

    local histOnLeft = false
    local hist = CreateFrame("Frame", nil, f, "BackdropTemplate")
    hist:SetWidth(HIST_W)
    hist:SetFrameStrata(f:GetFrameStrata())
    hist:EnableMouse(true)
    hist:SetBackdrop(backdrop)
    BG(hist, "main")
    hist:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    hist:Hide()

    local histTitle = hist:CreateFontString(nil, "OVERLAY")
    histTitle:SetPoint("TOP", hist, "TOP", 0, -8)
    StyleFont(histTitle, "large")
    histTitle:SetText(L["History"])
    Tint(histTitle)

    local histClose = CreateFrame("Button", nil, hist)
    histClose:SetSize(18, 18)
    histClose:SetPoint("TOPRIGHT", hist, "TOPRIGHT", -6, -5)
    local histCloseTex = histClose:CreateTexture(nil, "ARTWORK")
    histCloseTex:SetPoint("CENTER")
    histCloseTex:SetSize(13, 13)
    histCloseTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    histCloseTex:SetVertexColor(0.851, 0.851, 0.851, 1)
    histClose:SetScript("OnEnter", function() histCloseTex:SetVertexColor(accent[1], accent[2], accent[3], 1) end)
    histClose:SetScript("OnLeave", function() histCloseTex:SetVertexColor(0.851, 0.851, 0.851, 1) end)
    histClose:SetScript("OnClick", function() hist:Hide() end)

    -- Clear list: right under the close X. Two clicks, like the main window.
    local histClear = MakeButton(hist, L["Clear list"])
    histClear:SetSize(84, 18)
    histClear:SetPoint("TOPRIGHT", hist, "TOPRIGHT", -10, -29)
    local histClearToken = 0
    local function DisarmHistClear()
        histClearToken = histClearToken + 1
        histClear.text:SetText(L["Clear list"])
        histClear.armed = nil
    end
    histClear:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Clear list"], 1, 1, 1)
        GameTooltip:AddLine(L["Removes every name from the history. Click twice to confirm."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    histClear:HookScript("OnLeave", function() GameTooltip:Hide() end)
    histClear:SetScript("OnClick", function()
        if InCombatLockdown() or locked then return end
        if #(IL.db.History or {}) == 0 then return end
        if not histClear.armed then
            histClear.armed = true
            histClear.text:SetText(L["Confirm?"])
            histClearToken = histClearToken + 1
            local mine = histClearToken
            C_Timer.After(3, function()
                if histClearToken == mine and histClear.armed then DisarmHistClear() end
            end)
            return
        end
        DisarmHistClear()
        IL:ClearHistory()
    end)

    local histCount = hist:CreateFontString(nil, "OVERLAY")
    histCount:SetPoint("TOPLEFT", hist, "TOPLEFT", 12, -32)
    histCount:SetJustifyH("LEFT")
    StyleFont(histCount, "small")
    histCount:SetTextColor(textSec[1], textSec[2], textSec[3], 1)

    local histHolder = CreateFrame("Frame", nil, hist, "BackdropTemplate")
    histHolder:SetPoint("TOPLEFT", hist, "TOPLEFT", 10, -50)
    histHolder:SetPoint("BOTTOMRIGHT", hist, "BOTTOMRIGHT", -10, 10)
    histHolder:SetBackdrop(backdrop)
    BG(histHolder, "medium")
    histHolder:SetBackdropBorderColor(border[1], border[2], border[3], 1)

    local hscroll = CreateFrame("ScrollFrame", nil, histHolder)
    hscroll:SetPoint("TOPLEFT", histHolder, "TOPLEFT", 4, -4)
    hscroll:SetPoint("BOTTOMRIGHT", histHolder, "BOTTOMRIGHT", -4, 4)
    hscroll:EnableMouseWheel(true)
    local hcontent = CreateFrame("Frame", nil, hscroll)
    hcontent:SetPoint("TOPLEFT", hscroll, "TOPLEFT", 0, 0)
    hcontent:SetSize(HIST_W - 28, 1)
    hscroll:SetScrollChild(hcontent)
    hscroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local cur = self:GetVerticalScroll() or 0
        self:SetVerticalScroll(math_max(0, math_min(range, cur - delta * HIST_ROW_H * 2)))
    end)

    local histEmpty = histHolder:CreateFontString(nil, "OVERLAY")
    histEmpty:SetPoint("CENTER", histHolder, "CENTER", 0, 0)
    StyleFont(histEmpty, "normal")
    histEmpty:SetTextColor(textSec[1], textSec[2], textSec[3], 0.8)
    histEmpty:SetText(L["Nobody has joined yet."])

    local hrows = {}
    local function MakeHistRow()
        local row = CreateFrame("Frame", nil, hcontent)
        row:SetHeight(HIST_ROW_H)
        row:EnableMouse(true)

        -- X: removes the name from the history.
        local del = CreateFrame("Button", nil, row)
        del:SetSize(20, HIST_ROW_H)
        del:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        local delTex = del:CreateTexture(nil, "ARTWORK")
        delTex:SetPoint("CENTER")
        delTex:SetSize(11, 11)
        delTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
        delTex:SetVertexColor(0.6, 0.6, 0.6, 1)
        del:SetScript("OnEnter", function() delTex:SetVertexColor(1, 0.3, 0.3, 1) end)
        del:SetScript("OnLeave", function() delTex:SetVertexColor(0.6, 0.6, 0.6, 1) end)
        del:SetScript("OnClick", function()
            if InCombatLockdown() or locked then return end
            local e = row.entry
            if e then IL:RemoveHistory(e.name) end
        end)
        row.del = del

        local btn = MakeButton(row, L["Re-invite"])
        btn:SetSize(66, HIST_ROW_H - 4)
        btn:SetPoint("RIGHT", del, "LEFT", -2, 0)
        row.btn = btn

        row.nameText = row:CreateFontString(nil, "OVERLAY")
        -- Small square: green = joined the group, red = declined the invite, grey = removed from the list.
        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetSize(6, 6)
        row.mark:SetPoint("LEFT", row, "LEFT", 4, 0)

        row.nameText:SetPoint("LEFT", row.mark, "RIGHT", 5, 0)
        row.nameText:SetPoint("RIGHT", btn, "LEFT", -6, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        StyleFont(row.nameText, "normal")

        row:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(e.name, 1, 1, 1)
            local how = e.how
            if not how then
                how = (e.kind == "declined" and "declined") or (e.kind == "removed" and "removed") or "list"
            end
            if how == "killed" then
                GameTooltip:AddLine(L["Cleared by killing Ula'tek"], 0.35, 0.9, 0.35)
            else
                local why = (how == "list" and L["Invited via list"])
                    or (how == "declined" and L["Declined your invite"])
                    or (how == "cleared" and L["Cleared from list"])
                    or L["Removed from list"]
                GameTooltip:AddLine(why, 0.8, 0.8, 0.8)
            end
            if e.t then
                local fmt = (e.kind == "declined" and L["Declined at %s"])
                    or (e.kind == "removed" and L["Removed at %s"]) or L["Joined at %s"]
                GameTooltip:AddLine(string.format(fmt, date("%H:%M", e.t)), 0.65, 0.65, 0.65)
            end
            if e.kind == "joined" and e.leftAt then
                GameTooltip:AddLine(string.format(L["Left at %s"], date("%H:%M", e.leftAt)), 0.65, 0.65, 0.65)
            end
            if e.kind == "joined" and e.clearedBy == "killed" then
                GameTooltip:AddLine(L["Cleared by killing Ula'tek"], 0.35, 0.9, 0.35)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Puts the name back on the invite list, exactly as if it had been
        -- typed in by hand. It leaves the history (it is back on the list).
        btn:SetScript("OnClick", function()
            if InCombatLockdown() or locked then return end
            local e = row.entry
            if not e or not IL.names then return end
            ClearAllFocus()
            -- The entry STAYS in the history (it only leaves by its X, by Clear
            -- list or when the 25 limit pushes it out).
            local added = IL:MergeNames({ e.name })
            local shown = added > 0 and L["Added"] or L["In list"] -- "In list": already there (or it is you)
            if added > 0 then
                C_Timer.After(0, function()
                    scroll:SetVerticalScroll(scroll:GetVerticalScrollRange() or 0)
                    UpdateThumb()
                end)
            end
            btn.text:SetText(shown)
            C_Timer.After(1.5, function()
                if btn.text:GetText() == shown then btn.text:SetText(L["Re-invite"]) end
            end)
        end)
        return row
    end

    local function RefreshHistory()
        local list = IL.db and IL.db.History
        if type(list) ~= "table" then list = {} end
        for i = 1, #list do
            local e = list[i]
            local row = hrows[i]
            if not row then
                row = MakeHistRow()
                hrows[i] = row
            end
            row.entry = e
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", hcontent, "TOPLEFT", 0, -((i - 1) * (HIST_ROW_H + HIST_GAP)))
            row:SetPoint("TOPRIGHT", hcontent, "TOPRIGHT", 0, -((i - 1) * (HIST_ROW_H + HIST_GAP)))
            row.nameText:SetText(e.name)
            if e.kind == "declined" then
                row.mark:SetColorTexture(1.00, 0.30, 0.30, 1)
            elseif e.kind == "removed" then
                row.mark:SetColorTexture(0.65, 0.65, 0.65, 1)
            else
                row.mark:SetColorTexture(0.35, 0.90, 0.35, 1)
            end
            local c = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
            if c then
                row.nameText:SetTextColor(c.r, c.g, c.b, 1)
            else
                row.nameText:SetTextColor(textPri[1], textPri[2], textPri[3], 1)
            end
            row.btn.text:SetText(L["Re-invite"])
            SetWidgetEnabled(row.btn, not locked)
            SetWidgetEnabled(row.del, not locked)
            row:Show()
        end
        for i = #list + 1, #hrows do
            hrows[i].entry = nil
            hrows[i]:Hide()
        end
        hcontent:SetHeight(math_max(1, #list * (HIST_ROW_H + HIST_GAP)))
        histEmpty:SetShown(#list == 0)
        histCount:SetText(#list .. "/" .. HISTORY_MAX)
    end

    -- History/Friends placement is decided together below so their order is
    -- deterministic regardless of which panel is opened first.
    local PlacePanels
    PlaceHistory = function()
        if PlacePanels then PlacePanels("hist") end
    end

    hist:SetScript("OnShow", function()
        historyBtn.selected = true
        historyBtn:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    end)
    hist:SetScript("OnHide", function()
        historyBtn.selected = nil
        historyBtn:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        DisarmHistClear()
        GameTooltip:Hide()
        if PlacePanels and friends and friends:IsShown() then PlacePanels() end
    end)

    historyBtn:SetScript("OnClick", function()
        if InCombatLockdown() or locked then return end
        if hist:IsShown() then
            hist:Hide()
        else
            PlaceHistory()
            RefreshHistory()
            hscroll:SetVerticalScroll(0)
            hist:Show()
        end
    end)
    historyBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["History"], 1, 1, 1)
        GameTooltip:AddLine(L["Names that joined your group, declined your invite or were removed from the list, newest first. Re-invite puts a name back on the list."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    historyBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- Friend List: favourite Battle.net friends, online WoW characters first. ----
    -- Invites go straight to the player; they are never added to the main list.
    local FR_W, FR_ROW_H, FR_GAP = 300, 24, 2
    local FRIEND_EVENTS = {
        "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
        "BN_FRIEND_LIST_SIZE_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    }

    friends = CreateFrame("Frame", nil, f, "BackdropTemplate")
    friends:SetWidth(FR_W)
    friends:SetFrameStrata(f:GetFrameStrata())
    friends:EnableMouse(true)
    friends:SetBackdrop(backdrop)
    BG(friends, "main")
    friends:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    friends:Hide()

    local friendsTitle = friends:CreateFontString(nil, "OVERLAY")
    friendsTitle:SetPoint("TOP", friends, "TOP", 0, -8)
    StyleFont(friendsTitle, "large")
    friendsTitle:SetText(L["Friend list"])
    Tint(friendsTitle)

    local friendsClose = CreateFrame("Button", nil, friends)
    friendsClose:SetSize(18, 18)
    friendsClose:SetPoint("TOPRIGHT", friends, "TOPRIGHT", -6, -5)
    local friendsCloseTex = friendsClose:CreateTexture(nil, "ARTWORK")
    friendsCloseTex:SetPoint("CENTER")
    friendsCloseTex:SetSize(13, 13)
    friendsCloseTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    friendsCloseTex:SetVertexColor(0.851, 0.851, 0.851, 1)
    friendsClose:SetScript("OnEnter", function() friendsCloseTex:SetVertexColor(accent[1], accent[2], accent[3], 1) end)
    friendsClose:SetScript("OnLeave", function() friendsCloseTex:SetVertexColor(0.851, 0.851, 0.851, 1) end)
    friendsClose:SetScript("OnClick", function() friends:Hide() end)

    local friendsCount = friends:CreateFontString(nil, "OVERLAY")
    friendsCount:SetPoint("TOPLEFT", friends, "TOPLEFT", 12, -32)
    friendsCount:SetJustifyH("LEFT")
    StyleFont(friendsCount, "small")
    friendsCount:SetTextColor(textSec[1], textSec[2], textSec[3], 1)

    local showHidden = false
    local RefreshFriends
    local InviteAllFriends

    -- Invite All occupies the old Hidden-button slot. Hidden stays immediately
    -- to its left so the two list-level actions remain grouped together.
    local inviteAllBtn = MakeButton(friends, L["Invite All"])
    inviteAllBtn:SetSize(88, 18)
    inviteAllBtn:SetPoint("TOPRIGHT", friends, "TOPRIGHT", -10, -29)
    inviteAllBtn:SetScript("OnClick", function()
        if InCombatLockdown() or locked then return end
        InviteAllFriends()
    end)
    inviteAllBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Invite All"], 1, 1, 1)
        GameTooltip:AddLine(L["Invites every online friend in this list who is not already in the group. One character per Battle.net friend; hidden friends are skipped. Converts to a raid when there is not enough room for everybody."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    inviteAllBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- Hidden friends are only hidden from Invite Tools; Battle.net itself is untouched.
    local hiddenBtn = MakeButton(friends, "")
    hiddenBtn:SetSize(88, 18)
    hiddenBtn:SetPoint("RIGHT", inviteAllBtn, "LEFT", -4, 0)
    hiddenBtn:SetScript("OnClick", function()
        if InCombatLockdown() or locked then return end
        showHidden = not showHidden
        RefreshFriends()
    end)
    hiddenBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Hidden friends"], 1, 1, 1)
        GameTooltip:AddLine(L["Shows the friends you removed from this list. Right-click one to bring it back."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    hiddenBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local friendsHolder = CreateFrame("Frame", nil, friends, "BackdropTemplate")
    friendsHolder:SetPoint("TOPLEFT", friends, "TOPLEFT", 10, -50)
    friendsHolder:SetPoint("BOTTOMRIGHT", friends, "BOTTOMRIGHT", -10, 36)
    friendsHolder:SetBackdrop(backdrop)
    BG(friendsHolder, "medium")
    friendsHolder:SetBackdropBorderColor(border[1], border[2], border[3], 1)

    local fscroll = CreateFrame("ScrollFrame", nil, friendsHolder)
    fscroll:SetPoint("TOPLEFT", friendsHolder, "TOPLEFT", 4, -4)
    fscroll:SetPoint("BOTTOMRIGHT", friendsHolder, "BOTTOMRIGHT", -4, 4)
    fscroll:EnableMouseWheel(true)
    local fcontent = CreateFrame("Frame", nil, fscroll)
    fcontent:SetPoint("TOPLEFT", fscroll, "TOPLEFT", 0, 0)
    fcontent:SetSize(FR_W - 28, 1)
    fscroll:SetScrollChild(fcontent)
    fscroll:SetScript("OnMouseWheel", function(self, delta)
        if InCombatLockdown() or locked then return end
        local range = self:GetVerticalScrollRange() or 0
        local cur = self:GetVerticalScroll() or 0
        self:SetVerticalScroll(math_max(0, math_min(range, cur - delta * FR_ROW_H * 2)))
    end)

    local friendsEmpty = friendsHolder:CreateFontString(nil, "OVERLAY")
    friendsEmpty:SetPoint("CENTER", friendsHolder, "CENTER", 0, 0)
    friendsEmpty:SetWidth(FR_W - 50)
    StyleFont(friendsEmpty, "normal")
    friendsEmpty:SetTextColor(textSec[1], textSec[2], textSec[3], 0.8)
    friendsEmpty:SetText(L["No favourite Battle.net friends found."])

    -- Auto accept friendly invites: bottom row of the Friends panel. This is
    -- deliberately kept with Friends rather than the general EUI options.
    local friendlyCheck = CreateFrame("Button", nil, friends, "BackdropTemplate")
    friendlyCheck:SetSize(18, 18)
    friendlyCheck:SetPoint("BOTTOMLEFT", friends, "BOTTOMLEFT", 12, 10)
    friendlyCheck:SetBackdrop(backdrop)
    BG(friendlyCheck, "dark")
    friendlyCheck:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    friendlyFill = friendlyCheck:CreateTexture(nil, "ARTWORK")
    friendlyFill:SetPoint("TOPLEFT", friendlyCheck, "TOPLEFT", 4, -4)
    friendlyFill:SetPoint("BOTTOMRIGHT", friendlyCheck, "BOTTOMRIGHT", -4, 4)
    friendlyFill:SetColorTexture(accent[1], accent[2], accent[3], 1)
    friendlyFill:SetShown(IL:FriendlyOn())

    local friendlyLabel = friends:CreateFontString(nil, "OVERLAY")
    friendlyLabel:SetPoint("LEFT", friendlyCheck, "RIGHT", 6, 0)
    friendlyLabel:SetWidth(FR_W - 60)
    friendlyLabel:SetJustifyH("LEFT")
    friendlyLabel:SetWordWrap(false)
    StyleFont(friendlyLabel, "normal")
    Tint(friendlyLabel)
    friendlyLabel:SetText(L["Auto accept friendly invites"])
    friendlyCheck:SetHitRectInsets(0, -((friendlyLabel:GetStringWidth() or 0) + 8), 0, 0)

    friendlyCheck:SetScript("OnClick", function()
        if InCombatLockdown() or locked then return end
        IL:SetFriendly(not IL:FriendlyOn())
        friendlyFill:SetShown(IL:FriendlyOn())
    end)
    friendlyCheck:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(L["Auto accept friendly invites"], 1, 1, 1)
        GameTooltip:AddLine(L["Accepts party invites from friends, Battle.net friends and guild members. Ignored while you are in a group or queued."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    friendlyCheck:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        GameTooltip:Hide()
    end)

    local classByName
    local function ClassFromLocalized(name)
        if not classByName then
            classByName = {}
            for _, tbl in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
                for file, loc in pairs(tbl) do classByName[loc] = file end
            end
        end
        return classByName[name]
    end

    -- Blizzard-style Battle.net blue; offline favourites are grey and sorted last.
    local LIGHT_BLUE, OFFLINE_GREY = "|cff82c5ff", "|cff8c8c8c"

    local function HiddenSet()
        local db = IL.db
        if type(db.HiddenFriends) ~= "table" then db.HiddenFriends = {} end
        return db.HiddenFriends
    end

    -- Online WoW favourites get one row per character; offline/other-game
    -- favourites get one grey Battle.net-name row. Hidden entries are shown only
    -- through the Hidden button and always sort after normal entries.
    local function FavoriteFriends()
        local out = {}
        if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo
            and C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo) then
            return out
        end
        local mine = MyRealmKey()
        local hiddenSet = HiddenSet()
        for i = 1, (BNGetNumFriends() or 0) do
            local acc = C_BattleNet.GetFriendAccountInfo(i)
            if acc and acc.isFavorite then
                local tag = IsReadable(acc.battleTag) and acc.battleTag ~= "" and acc.battleTag or nil
                local key = tag and tag:lower() or nil
                local isHidden = key ~= nil and hiddenSet[key] == true
                if showHidden or not isHidden then
                    local bnet
                    if IsReadable(acc.accountName) and acc.accountName ~= "" then
                        bnet = acc.accountName
                    elseif tag then
                        bnet = (tag:gsub("#%d+$", ""))
                    else
                        bnet = "?"
                    end
                    local sortName = (tag or "~"):lower()
                    local found = false
                    for j = 1, (C_BattleNet.GetFriendNumGameAccounts(i) or 0) do
                        local g = C_BattleNet.GetFriendGameAccountInfo(i, j)
                        if g and g.isOnline and g.clientProgram == (BNET_CLIENT_WOW or "WoW")
                            and (not g.wowProjectID or not WOW_PROJECT_ID or g.wowProjectID == WOW_PROJECT_ID)
                            and IsReadable(g.characterName) and g.characterName ~= "" then
                            found = true
                            local realm = IsReadable(g.realmName) and g.realmName or ""
                            local realmKey = (realm:gsub("[%s'%-]", ""):lower())
                            local other = realm ~= "" and realmKey ~= mine
                            local inviteName = g.characterName
                            if other then inviteName = inviteName .. "-" .. (realm:gsub("[%s%-]", "")) end

                            local cf = IsReadable(g.className) and ClassFromLocalized(g.className) or nil
                            if not cf and g.playerGuid and GetPlayerInfoByGUID then
                                local _, eng = GetPlayerInfoByGUID(g.playerGuid)
                                cf = ValidClass(eng)
                            end
                            local c = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
                            local cc = c and string.format("|cff%02x%02x%02x", c.r * 255 + 0.5, c.g * 255 + 0.5, c.b * 255 + 0.5) or "|cffffffff"
                            local realmPart = other and ("|cff999999-" .. realm .. "|r") or ""
                            local text = LIGHT_BLUE .. bnet .. "|r " .. cc .. "(" .. g.characterName .. "|r" .. realmPart .. cc .. ")|r"
                            out[#out + 1] = {
                                key = key, bnet = bnet, online = true, hidden = isHidden, invite = inviteName,
                                text = text, char = g.characterName .. (other and ("-" .. realm) or ""),
                                rank = isHidden and 3 or 1, sort = sortName .. "|" .. g.characterName:lower(),
                            }
                        end
                    end
                    if not found then
                        out[#out + 1] = {
                            key = key, bnet = bnet, online = false, hidden = isHidden,
                            text = OFFLINE_GREY .. bnet .. "|r",
                            rank = isHidden and 3 or 2, sort = sortName,
                        }
                    end
                end
            end
        end
        table.sort(out, function(x, y)
            if x.rank ~= y.rank then return x.rank < y.rank end
            return x.sort < y.sort
        end)
        return out
    end

    local function InviteFriend(inviteName)
        if InCombatLockdown() or locked then return end
        IL.friendInvited[inviteName] = true
        if IsInGroup() and not IsInRaid() and (GetNumGroupMembers() or 0) >= 5 and UnitIsGroupLeader("player") then
            ConvertToRaid()
            C_Timer.After(0.6, function()
                if not InCombatLockdown() then InviteUnit(inviteName) end
            end)
        else
            InviteUnit(inviteName)
        end
    end

    -- One online WoW character per favourite Battle.net friend. If any
    -- character from that Battle.net friend is already in the group, that
    -- friend is skipped entirely.
    local function InviteAllCandidates()
        local out, seen, inGroupKeys = {}, {}, {}
        local list = FavoriteFriends()
        for i = 1, #list do
            local e = list[i]
            if e.online and e.invite and InGroup(e.invite) then
                inGroupKeys[e.key or e.invite] = true
            end
        end
        for i = 1, #list do
            local e = list[i]
            local k = e.key or e.invite
            if e.online and e.invite and not e.hidden and not seen[k] and not inGroupKeys[k]
                and not InGroup(e.invite) then
                seen[k] = true
                out[#out + 1] = e.invite
            end
        end
        return out
    end

    local inviteAllToken = 0
    local function SendStaggered(names, from)
        for i = from, #names do
            local name = names[i]
            C_Timer.After((i - from) * 0.5, function()
                if not InCombatLockdown() and not InGroup(name) then InviteFriend(name) end
            end)
        end
    end

    InviteAllFriends = function()
        if InCombatLockdown() or locked then return end
        local names = InviteAllCandidates()
        if #names == 0 then return end
        inviteAllToken = inviteAllToken + 1
        local mine = inviteAllToken

        -- Count the player even while solo. If the future total would exceed a
        -- party, convert before/after the first acceptance as appropriate.
        local total = math_max(1, GetNumGroupMembers() or 0) + #names
        if total <= PARTY_SIZE or IsInRaid() then
            SendStaggered(names, 1)
        elseif IsInGroup() then
            if UnitIsGroupLeader("player") then
                ConvertToRaid()
                C_Timer.After(0.6, function()
                    if inviteAllToken == mine and not InCombatLockdown() then SendStaggered(names, 1) end
                end)
            else
                SendStaggered(names, 1)
            end
        else
            -- Solo: send only the four slots a party can hold. As soon as one
            -- accepts and a group exists, convert to raid and send the rest.
            local first = math_min(4, #names)
            for i = 1, first do
                local name = names[i]
                C_Timer.After((i - 1) * 0.5, function()
                    if inviteAllToken == mine and not InCombatLockdown() and not InGroup(name) then
                        InviteFriend(name)
                    end
                end)
            end
            local waited = 0
            local ticker
            ticker = C_Timer.NewTicker(1, function()
                waited = waited + 1
                if inviteAllToken ~= mine or InCombatLockdown() or waited > 90 then
                    ticker:Cancel()
                    return
                end
                if IsInGroup() and UnitIsGroupLeader("player") then
                    ticker:Cancel()
                    if not IsInRaid() then ConvertToRaid() end
                    C_Timer.After(0.6, function()
                        if inviteAllToken == mine and not InCombatLockdown() then
                            SendStaggered(names, first + 1)
                        end
                    end)
                end
            end)
        end
        if RefreshFriends then C_Timer.After(0.2, RefreshFriends) end
    end

    -- A small confirmation popup sits directly on the row after a right-click.
    local confirmPop = CreateFrame("Button", nil, friends, "BackdropTemplate")
    confirmPop:SetSize(84, 20)
    confirmPop:SetFrameLevel(friends:GetFrameLevel() + 60)
    confirmPop:SetBackdrop(backdrop)
    BG(confirmPop, "medium")
    confirmPop:SetBackdropBorderColor(1, 0.3, 0.3, 1)
    confirmPop.text = confirmPop:CreateFontString(nil, "OVERLAY")
    confirmPop.text:SetPoint("CENTER")
    StyleFont(confirmPop.text, "normal")
    confirmPop.text:SetTextColor(1, 0.3, 0.3, 1)
    confirmPop.text:SetText(L["Confirm?"])
    confirmPop:Hide()
    local confirmToken = 0
    local function DismissConfirm()
        confirmToken = confirmToken + 1
        confirmPop.entry = nil
        confirmPop:Hide()
    end

    local function SetFriendHidden(e)
        if not e or not e.key then return end
        local set = HiddenSet()
        if set[e.key] then set[e.key] = nil else set[e.key] = true end
        RefreshFriends()
    end
    confirmPop:SetScript("OnClick", function()
        local e = confirmPop.entry
        DismissConfirm()
        if InCombatLockdown() or locked then return end
        SetFriendHidden(e)
    end)

    local function ToggleHideFriend(e, row)
        if not e or not e.key or InCombatLockdown() or locked then return end
        if e.hidden then
            DismissConfirm()
            SetFriendHidden(e)
            return
        end
        confirmPop:ClearAllPoints()
        confirmPop:SetPoint("LEFT", row, "LEFT", 16, 0)
        confirmPop.entry = e
        confirmPop:Show()
        confirmToken = confirmToken + 1
        local mine = confirmToken
        C_Timer.After(4, function()
            if confirmToken == mine then DismissConfirm() end
        end)
    end

    local frows = {}
    local function MakeFriendRow()
        local row = CreateFrame("Frame", nil, fcontent)
        row:SetHeight(FR_ROW_H)
        row:EnableMouse(true)

        local btn = MakeButton(row, L["Invite"])
        btn:SetSize(70, FR_ROW_H - 4)
        btn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.btn = btn

        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetSize(6, 6)
        row.mark:SetPoint("LEFT", row, "LEFT", 4, 0)

        row.text = row:CreateFontString(nil, "OVERLAY")
        row.text:SetPoint("LEFT", row.mark, "RIGHT", 5, 0)
        row.text:SetPoint("RIGHT", btn, "LEFT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        StyleFont(row.text, "normal")
        row.text:SetTextColor(textPri[1], textPri[2], textPri[3], 1)

        btn:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then
                ToggleHideFriend(row.entry, row)
                return
            end
            local e = row.entry
            if InCombatLockdown() or locked or not e or not e.invite then return end
            InviteFriend(e.invite)
            btn.text:SetText(L["Sent"])
            C_Timer.After(2, function()
                if btn.text:GetText() == L["Sent"] then btn.text:SetText(L["Invite"]) end
            end)
        end)
        row:SetScript("OnMouseUp", function(self, mouseButton)
            if mouseButton == "RightButton" then ToggleHideFriend(self.entry, self) end
        end)
        row:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(e.bnet, 0.51, 0.77, 1)
            if e.online then
                GameTooltip:AddLine(e.char, 1, 1, 1)
            else
                GameTooltip:AddLine(L["Not online in WoW"], 0.6, 0.6, 0.6)
            end
            GameTooltip:AddLine(e.hidden and L["Right-click: show this friend in the list again."]
                or L["Right-click: remove this friend from this list."], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end

    RefreshFriends = function()
        if confirmPop:IsShown() then DismissConfirm() end
        local list = FavoriteFriends()
        local combat = InCombatLockdown() or locked
        local online = 0
        for i = 1, #list do
            local e = list[i]
            local row = frows[i]
            if not row then
                row = MakeFriendRow()
                frows[i] = row
            end
            row.entry = e
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", fcontent, "TOPLEFT", 0, -((i - 1) * (FR_ROW_H + FR_GAP)))
            row:SetPoint("TOPRIGHT", fcontent, "TOPRIGHT", 0, -((i - 1) * (FR_ROW_H + FR_GAP)))
            row.text:SetText(e.text)
            row:SetAlpha(e.hidden and 0.5 or 1)
            if e.online then
                online = online + 1
                row.mark:SetColorTexture(0.35, 0.90, 0.35, 1)
                local here = InGroup(e.invite)
                if here then
                    row.btn.text:SetText(L["In group"])
                elseif row.btn.text:GetText() ~= L["Sent"] then
                    row.btn.text:SetText(L["Invite"])
                end
                SetWidgetEnabled(row.btn, not combat and not here)
                if combat or here then
                    row.btn.text:SetTextColor(0.5, 0.5, 0.5, 1)
                else
                    row.btn.text:SetTextColor(accent[1], accent[2], accent[3], 1)
                end
                row.btn:Show()
            else
                row.mark:SetColorTexture(0.55, 0.55, 0.55, 1)
                row.btn:Hide()
            end
            row:Show()
        end
        for i = #list + 1, #frows do
            frows[i].entry = nil
            frows[i]:Hide()
        end
        fcontent:SetHeight(math_max(1, #list * (FR_ROW_H + FR_GAP)))
        friendsEmpty:SetShown(#list == 0)
        friendsCount:SetText(string.format(L["%d online"], online))

        local nHidden = 0
        for _ in pairs(HiddenSet()) do nHidden = nHidden + 1 end
        hiddenBtn.text:SetText(string.format(L["Hidden: %d"], nHidden))
        hiddenBtn.selected = showHidden or nil
        if showHidden then
            hiddenBtn:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        else
            hiddenBtn:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        end
        hiddenBtn:SetShown(nHidden > 0 or showHidden)

        local canInviteAll = not combat and #InviteAllCandidates() > 0
        SetWidgetEnabled(inviteAllBtn, canInviteAll)
        inviteAllBtn.text:SetTextColor(canInviteAll and accent[1] or 0.5, canInviteAll and accent[2] or 0.5, canInviteAll and accent[3] or 0.5, 1)
    end

    -- Deterministic order, left to right: Friends then History. Normally the
    -- main window sits between them; near a screen edge both panels move to the
    -- side that fits while preserving Friends -> History.
    PlacePanels = function(opening)
        local fShown = friends:IsShown() or opening == "friends"
        local hShown = hist:IsShown() or opening == "hist"
        local left, right, screen = f:GetLeft(), f:GetRight(), UIParent:GetRight()
        local layout = "normal"
        if left and right and screen then
            local fw = fShown and (FR_W + 4) or 0
            local hw = hShown and (HIST_W + 4) or 0
            if left - fw < 0 or right + hw > screen then
                if left - fw - hw >= 0 then
                    layout = "left"   -- Friends | History | window
                elseif right + fw + hw <= screen then
                    layout = "right"  -- window | Friends | History
                end
            end
        end

        friends:ClearAllPoints()
        hist:ClearAllPoints()
        if layout == "normal" then
            friendsOnLeft, histOnLeft = true, false
            friends:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, 0)
            friends:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -4, 0)
            hist:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
            hist:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 4, 0)
        elseif layout == "left" then
            friendsOnLeft, histOnLeft = true, true
            hist:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, 0)
            hist:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -4, 0)
            local anchor = hShown and hist or f
            friends:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
            friends:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", -4, 0)
        else
            friendsOnLeft, histOnLeft = false, false
            friends:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
            friends:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 4, 0)
            local anchor = fShown and friends or f
            hist:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
            hist:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 4, 0)
        end
    end
    PlaceFriends = function()
        PlacePanels("friends")
    end
    f:HookScript("OnDragStop", function() if PlacePanels then PlacePanels() end end)

    -- Text button immediately to the left of History, as part of the EUI header row.
    local friendsBtn = MakeButton(f, L["Friend list"])
    friendsBtn:SetSize(78, 18)
    friendsBtn:SetPoint("RIGHT", historyBtn, "LEFT", -4, 0)
    friendsBtn:SetScript("OnClick", function()
        if InCombatLockdown() or locked then return end
        if friends:IsShown() then
            friends:Hide()
        else
            PlaceFriends()
            RefreshFriends()
            fscroll:SetVerticalScroll(0)
            friends:Show()
        end
    end)
    friendsBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Friend list"], 1, 1, 1)
        GameTooltip:AddLine(L["Your favourite Battle.net friends, online ones first. Invite goes straight to the player, without using the list. Right-click a friend to remove it from this list."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    friendsBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local friendsQueued = false
    friends:SetScript("OnEvent", function()
        if friendsQueued then return end
        friendsQueued = true
        C_Timer.After(0.3, function()
            friendsQueued = false
            if friends:IsShown() then RefreshFriends() end
        end)
    end)
    friends:SetScript("OnShow", function()
        for _, ev in ipairs(FRIEND_EVENTS) do pcall(friends.RegisterEvent, friends, ev) end
        friendsBtn.selected = true
        friendsBtn:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    end)
    friends:SetScript("OnHide", function()
        DismissConfirm()
        friends:UnregisterAllEvents()
        friendsBtn.selected = nil
        friendsBtn:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        GameTooltip:Hide()
        if PlacePanels and hist:IsShown() then PlacePanels() end
    end)

    -- Runtime settings -------------------------------------------------------
    -- The standalone cog panel is intentionally not ported. Raid Tools options
    -- own these settings; this block only applies them to the already-built UI.
    local function ApplyListScale(v)
        listScale = ClampScale(v)
        headerH = M(HEADER_H)
        ApplyFontScale()
        for i = 1, #rows do
            local row = rows[i]
            row.num:SetWidth(M(22))
            row.class:SetSize(M(CLASS_W), M(CLASS_W))
            row.del:SetSize(M(20), RowH())
            row.delTex:SetSize(M(11), M(11))
            row.status:SetWidth(M(STATUS_W))
            row.edit:SetHeight(RowH() - 2)
            row:SetHeight(RowH())
        end
        PlaceHeaders()
        Layout()
        RefreshHistory()
    end

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetSize(11, 11)
    gripTex:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -1, 1)
    gripTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
    gripTex:SetRotation(-math.pi / 4) -- one arrow, permanently pointing toward the lower-right resize corner
    gripTex:SetVertexColor(textSec[1], textSec[2], textSec[3], 0.8)
    grip:SetScript("OnEnter", function() gripTex:SetVertexColor(accent[1], accent[2], accent[3], 1) end)
    grip:SetScript("OnLeave", function() gripTex:SetVertexColor(textSec[1], textSec[2], textSec[3], 0.8) end)
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or InCombatLockdown() or locked or not IL.db.Unlocked then return end
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        IL.db.Width = math.floor(f:GetWidth() + 0.5)
        IL.db.Height = math.floor(f:GetHeight() + 0.5)
        SavePosition()
    end)
    grip:SetShown(IL.db.Unlocked and true or false)

    local function ApplyBackground(r, g, b, a)
        bgDark[1], bgDark[2], bgDark[3], bgDark[4] = r, g, b, a or 1
        bgMedium[1] = math_min(1, r + BG_LIFT)
        bgMedium[2] = math_min(1, g + BG_LIFT)
        bgMedium[3] = math_min(1, b + BG_LIFT)
        for i = 1, #bgItems do PaintBG(bgItems[i]) end
        PaintList()
    end
    f.ApplyBackground = ApplyBackground

    local function ApplyListBackground(r, g, b, a)
        listBg = r and { r, g, b, a or 1 } or nil
        PaintList()
    end
    f.ApplyListBackground = ApplyListBackground
    f.defaultBg = defaultBg

    local function ApplyAccent(r, g, b)
        accent[1], accent[2], accent[3] = r, g, b
        Theme.accent[1], Theme.accent[2], Theme.accent[3], Theme.accent[4] = r, g, b, 1
        thumb:SetColorTexture(r, g, b, 0.6)
        checkFill:SetColorTexture(r, g, b, 1)
        if friendlyFill then friendlyFill:SetColorTexture(r, g, b, 1) end
        timerEdit:SetBackdropBorderColor(r, g, b, 1)
        for i = 1, #tinted do tinted[i]:SetTextColor(r, g, b, 1) end
        UpdateStatusUI()
    end
    f.ApplyAccent = ApplyAccent
    f.defaultAccent = themeAccent
    f.ApplyListScale = ApplyListScale
    f.ApplyResizable = function(on)
        local enabled = on and not locked
        SetWidgetEnabled(grip, enabled)
        grip:SetShown(enabled)
    end

    -- In combat the whole window is locked by one overlay; only Close sits
    -- above it. Do not touch individual controls here: some are created or
    -- removed independently, and stale references were the source of the
    -- previous stale-widget combat errors.
    local function SetLocked(state)
        state = state and true or false
        if state == locked then return end
        locked = state
        if locked then
            f:StopMovingOrSizing() -- combat started mid-drag/resize
            ClearAllFocus()
            GameTooltip:Hide()
            shareMenu:Hide()
            hist:Hide()
            friends:Hide()
            DisarmHistClear()
            grip:Hide()
            combatBlocker:Show()
        else
            combatBlocker:Hide()
            grip:SetShown(IL.db.Unlocked == true)
            hint:SetText("")
            hint:SetTextColor(textSec[1], textSec[2], textSec[3], 1)
        end
    end

    f.SetLocked = SetLocked
    f.UpdateStatusUI = UpdateStatusUI
    f.scroll = scroll
    f.Layout = Layout
    f.RefreshHistory = RefreshHistory
    f.ClearAllFocus = ClearAllFocus
    -- Anything half-typed is saved (focus loss) when the window closes.
    f:SetScript("OnHide", function()
        f:StopMovingOrSizing()
        SavePosition()
        hist:Hide()
        friends:Hide()
        ClearAllFocus()
    end)
    self.frame = f
    return f
end

function IL:SelectList(index)
    if not self.frame then return end
    index = tonumber(index) or 1
    if index < 1 or index > NUM_LISTS then index = 1 end

    -- Save a half-typed name into the list it was typed in, BEFORE switching.
    self.frame.ClearAllFocus()

    local accent = Color(Theme.accent, { 1, 0.82, 0, 1 })
    local border = Color(Theme.border, { 0, 0, 0, 1 })

    self.currentList = index
    self.db.Current = index

    for i, tab in ipairs(self.frame.tabs) do
        tab.selected = (i == index)
        if tab.selected then
            tab:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        else
            tab:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        end
    end

    self.names = ParseList(self:GetListText(index))
    -- Back to the top when switching lists.
    self.frame.scroll:SetVerticalScroll(0)
    self.frame.Layout()
end

function IL:Toggle()
    self:UpdateDB()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
        return
    end
    if not self.frame then self:CreateFrame() end
    local combat = InCombatLockdown()
    self.frame.SetLocked(combat)
    self.frame:Show()
    self:SelectList(self.db.Current or 1)
    if not combat and next(self.state) then self:RefreshMembership() end
    self.frame.UpdateStatusUI()
end

------------------------------------------------------------------------
-- Slash commands
-- With no argument they toggle the window. A numeric argument invites that
-- list directly without opening the UI (the EUI port currently has List 1).
------------------------------------------------------------------------

SLASH_EUIINVITETOOLS1 = "/invlist"
SLASH_EUIINVITETOOLS2 = "/invitelist"
SLASH_EUIINVITETOOLS3 = "/invitetools"
SLASH_EUIINVITETOOLS4 = "/jaca"
SLASH_EUIINVITETOOLS5 = "/jacatools"
SLASH_EUIINVITETOOLS6 = "/il"
SLASH_EUIINVITETOOLS7 = "/jt"
SlashCmdList["EUIINVITETOOLS"] = function(msg)
    IL:UpdateDB()
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local n = tonumber(msg)
    if n then
        IL:InviteFromList(n)
    else
        if IL.frame and IL.frame:IsShown() then return end
        IL:Toggle()
    end
end

------------------------------------------------------------------------
-- EUI exports
------------------------------------------------------------------------
ns.ToggleInviteTools = function() IL:Toggle() end
ns.InviteToolsSetAccent = function(r, g, b) IL:SetAccent(r, g, b) end
ns.InviteToolsSetBackground = function(r, g, b, a) IL:SetBackground(r, g, b, a) end
ns.InviteToolsSetListBackground = function(r, g, b, a) IL:SetListBackground(r, g, b, a) end
ns.InviteToolsApplySettings = function()
    IL:UpdateDB()
    if not IL.db then return end
    local f = IL.frame
    if not f then return end
    local ac = IL.db.AccentColor
    local ar, ag, ab
    if type(ac) == "table" then ar, ag, ab = ac[1], ac[2], ac[3] end
    if not ar then ar, ag, ab = EllesmereUI.GetAccentColor() end
    if f.ApplyAccent then f.ApplyAccent(ar, ag, ab) end
    local bg = IL.db.BgColor
    if type(bg) == "table" and bg[1] then
        if f.ApplyBackground then f.ApplyBackground(bg[1], bg[2], bg[3], bg[4] or 1) end
    elseif f.defaultBg and f.ApplyBackground then
        f.ApplyBackground(f.defaultBg[1], f.defaultBg[2], f.defaultBg[3], f.defaultBg[4] or 1)
    end
    local lb = IL.db.ListBgColor
    if f.ApplyListBackground then
        if type(lb) == "table" and lb[1] then f.ApplyListBackground(lb[1], lb[2], lb[3], lb[4] or 1) else f.ApplyListBackground(nil) end
    end
    if f.ApplyListScale then f.ApplyListScale(IL.db.ListScale or 1) end
    if f.ApplyResizable then f.ApplyResizable(IL.db.Unlocked == true) end
end


-- Follow the suite accent live unless Invite Tools has an explicit override.
if EllesmereUI.RegAccent then
    EllesmereUI.RegAccent({ type = "callback", fn = function()
        if IL.db and not IL.db.AccentColor then
            local r, g, b = EllesmereUI.GetAccentColor()
            Theme.accent[1], Theme.accent[2], Theme.accent[3], Theme.accent[4] = r, g, b, 1
            if IL.frame and IL.frame.ApplyAccent then IL.frame.ApplyAccent(r, g, b) end
        end
    end })
end
