if EUI_CLIENT_BLOCKED then return end
-------------------------------------------------------------------------------
-- Raid Groups: non-protected planning surface and serialized roster application.
-- Draft edits never call protected group functions. Character-Realm identity
-- stays separate from display nicknames, and reserved Guest seats are dynamic.
-------------------------------------------------------------------------------
local _, ns = ...
-- Keep labels in the suite locale pipeline; stored names and identities are
-- never translated. Missing catalog keys fall back to English by design.
local function L(key) return EllesmereUI.L(key) end
local function LF(key, ...) return EllesmereUI.Lf(key, ...) end
local FONT_KEY = "extras"
local db -- declared before appearance helpers so profile settings use the real local DB
local trackedFonts = {}
local function TrackFont(widget, size)
    trackedFonts[#trackedFonts+1] = {widget=widget, size=size}
    local path = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath(FONT_KEY)
    if path and widget.SetFont then
        local _, _, flags = widget:GetFont()
        widget:SetFont(path, size, flags or "")
    end
    return widget
end
local RGStyle = {fonts={main=10,unlisted=10,current=11,after=11,available=11,nicknameManager=11}, panels={}}
function RGStyle.PlayerFontSize(key)
    local p=db and db.profile and db.profile.raidGroups
    if p and p.playerNamesFontEnabled==false then return RGStyle.fonts[key] or 11 end
    local sizes=p and p.playerFontSizes
    local value=sizes and tonumber(sizes[key])
    return value and math.max(8,math.min(18,value)) or RGStyle.fonts[key] or 11
end
function RGStyle.MarkPlayerFont(widget,key)
    for _,entry in ipairs(trackedFonts) do
        if entry.widget==widget then entry.playerFontKey=key;break end
    end
    local path=EllesmereUI.GetFontPath and EllesmereUI.GetFontPath(FONT_KEY)
    if path and widget.SetFont then
        local _,_,flags=widget:GetFont()
        widget:SetFont(path,RGStyle.PlayerFontSize(key),flags or "")
    end
end
local function ApplyFonts()
    local path = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath(FONT_KEY)
    if not path then return end
    for _, entry in ipairs(trackedFonts) do
        local widget = entry.widget
        local _, _, flags = widget:GetFont()
        widget:SetFont(path, entry.playerFontKey and RGStyle.PlayerFontSize(entry.playerFontKey) or entry.size, flags or "")
    end
end
local NUM_GROUPS, GROUP_SIZE, SLOT_COUNT = 8, 5, 40
local PAD, SLOT_W, SLOT_H, SLOT_GAP, COL_GAP = 14, 157, 23, 3, 12
local data, win, setupWindow, nickWindow, transferWindow, splitWindow, promptWindow, previewWindow, backupWindow
local slots, extras, setupRows, nickRows = {}, {}, {}, {}
local draft = {}                     -- nil (empty), "GUEST", or Character-Realm
local dirty, selectedSetup, chosenExtra, dragFrom, dragGhost, dragTarget = false, nil, nil, nil, nil, nil
local statusLabel, dirtyLabel, extrasLabel, applyButton, keepButton, listModeButton, exactButton, mainHelp
local editorButtons, unlistedButtons, splitButtons = {}, {}, {}
local rosterByKey, rosterSorted = {}, {}
local applyState, updatePending, lastRosterSignature = nil, false, nil
local extraOffset, setupOffset, nickOffset, listGuild = 0, 0, 0, false
local firstDraftLoaded = false
local undoStack, UNDO_LIMIT = {}, 20
RGStyle.redoStack = {}
local previewDraftState, previewConfirmButton = nil, nil
-- The shared UI style state tracks combat-suspended previews without
-- adding another module-level Lua local (WoW limits a chunk to 200 locals).
RGStyle.previewSuspendedForCombat = false
local previewGuestAnnotations = {}
-- Exclusions are temporary to the draft/preview. Removing a character from
-- the plan must not silently reassign that character as an automatic Guest.
local removedGuestKeys={}
local draftPinned={} -- named Pinned Guests: never replaced by automatic assignments
local draftGuest={} -- named normal Guests: may be replaced by automatic assignments
RGStyle.emptyPinnedDraft={} -- explicit vacant seats that must stay unassigned
RGStyle.SETUP_GUEST="SETUP_GUEST" -- anonymous pinned Guest, one unique eligible raid member per seat
local seatMenuOverlay, seatMenuFrame
local footerControls = {}
local nickSearch = ""
local nickCollapsed -- account-wide per-nickname collapse state, separate from nickname records
local nsrtRegistered = false
local Refresh, RefreshSetups, RefreshNicknames, RefreshExtras, ProcessApply, StopApply

-- Per-profile presentation and automation switches. Nil means enabled so
-- existing profiles retain all the behavior introduced by earlier versions.
local DEFAULTS = { profile = { raidGroups = { scale = 1, showNicknames = true, pos = {},
    editorTools = true, editorDrag = true, editorCurrentRoster = true, editorClearDraft = true,
    editorRedoDraft = true,
    guestFeatures = true, guestImportSeats = true, guestAutoDetect = true,
    guestRightClick = true, guestFillSeats = true, guestAutoEmptySeats = true,
    unlistedFeatures = true, unlistedAsterisk = true, unlistedList = true, unlistedGuild = true,
    nicknameLearning = true, nicknameRosterLearn = true, nicknameNSRTUpdates = true,
    splitRaidEnabled = true,
    chatNotifications = true, chatNicknames = true, chatCombat = true,
    chatLeader = true, chatMissing = true, chatSuccess = true,
    backupEnabled = true, exportFormat = "native", importFormat = "auto",
    windowScalingEnabled = true, playerNamesFontEnabled = true,
    leaderIconStyle = "blizzard", leaderIconPosition = "right", leaderIconSize = 14,
    leaderIconOffsetX = 0, leaderIconOffsetY = 0, leaderIconInCombat = true,
} } }
local function P() return db and db.profile and db.profile.raidGroups end
local function Enabled(key)
    local p=P()
    return not p or p[key] ~= false
end
-- Options page uses the same live QoL profile as the runtime; reads never
-- seed the DB (important for Spec Overrides capture proxies).
function ns.RaidGroupsOption(key, value)
    local p=P()
    if value==nil then return Enabled(key) end
    if p then
        p[key]=value and true or false
        if key=="windowScalingEnabled" then RGStyle.ApplyAllPanelScales()
        elseif key=="playerNamesFontEnabled" then ApplyFonts() end
        if Refresh then Refresh() end
    end
end
function ns.RaidGroupsExactPositions(value)
    if value==nil then return not not (data and data.exactPositions) end
    if data then data.exactPositions=value and true or false end
    if Refresh then Refresh() end
end
local EXPORT_FORMATS={native=true,compact=true,invitelist=true,pair=true,eight=true,vertical=true}
function ns.RaidGroupsDefaultImportFormat(value)
    local p=P()
    if value==nil then
        return p and ({auto=true,native=true,compact=true,invitelist=true,pair=true,eight=true,vertical=true})[p.importFormat] and p.importFormat or "auto"
    end
    if p and ({auto=true,native=true,compact=true,invitelist=true,pair=true,eight=true,vertical=true})[value] then p.importFormat=value end
end
function ns.RaidGroupsDefaultExportFormat(value)
    local p=P()
    if value==nil then
        return p and EXPORT_FORMATS[p.exportFormat] and p.exportFormat or "native"
    end
    if p and EXPORT_FORMATS[value] then p.exportFormat=value end
end
local LEADER_ICON_DEFAULTS = {leaderIconStyle="blizzard",leaderIconPosition="right",
    leaderIconSize=14,leaderIconOffsetX=0,leaderIconOffsetY=0,leaderIconInCombat=true}
function ns.RaidGroupsLeaderIconOption(key,value)
    local p=P()
    if value==nil then
        if p and p[key]~=nil then return p[key] end
        return LEADER_ICON_DEFAULTS[key]
    end
    if p and LEADER_ICON_DEFAULTS[key]~=nil then
        p[key]=value
        if Refresh and win and win:IsShown() then Refresh() end
    end
end
-- All Raid Groups messages share one UTF-8-safe, bounded local-chat writer.
-- Leave room for the colored prefix and avoid splitting inside multibyte names.
-- Chat editbox/send limits are 255 bytes; use a conservative 240-byte line.
local CHAT_PREFIX = "|cff0cd29fEllesmereUI:|r "
local CHAT_BUDGET = 240 - #CHAT_PREFIX
local function PrintChatLine(line)
    if EllesmereUI and EllesmereUI.Print then
        EllesmereUI.Print(CHAT_PREFIX..line)
    else
        print("EllesmereUI: "..line)
    end
end
local function PrintWrapped(text)
    text=tostring(text or "")
    -- Normalize multiline messages to independently bounded chat lines.
    text=text:gsub("\r\n", "\n"):gsub("\r", "\n")
    for paragraph in (text.."\n"):gmatch("(.-)\n") do
        local rest=paragraph
        if rest=="" then
            PrintChatLine("")
        else
            while #rest>CHAT_BUDGET do
                local slice=rest:sub(1,CHAT_BUDGET)
                local cut
                -- Prefer the most recent comma between names; otherwise a word boundary.
                local search=1
                while true do
                    local pos=slice:find(", ",search,true)
                    if not pos then break end
                    if pos>1 then cut=pos end
                    search=pos+2
                end
                if not cut then
                    local space=1
                    while true do
                        local pos=slice:find(" ",space,true)
                        if not pos then break end
                        if pos>1 then cut=pos-1 end
                        space=pos+1
                    end
                end
                if not cut then
                    cut=CHAT_BUDGET
                    -- The trailing UTF-8 continuation bytes must stay with their lead byte.
                    while cut>1 do
                        local following=rest:byte(cut+1)
                        if not following or following<128 or following>=192 then break end
                        cut=cut-1
                    end
                end
                PrintChatLine(rest:sub(1,cut))
                rest=rest:sub(cut+1):gsub("^%s+", "")
            end
            if rest~="" then PrintChatLine(rest) end
        end
    end
end
-- Only optional, nonfatal notices are filtered. Errors keep their existing
-- diagnostic channel, regardless of the player's notification preferences.
local CHAT_OPTIONS={nickname="chatNicknames",combat="chatCombat",leader="chatLeader",
    missing="chatMissing",success="chatSuccess"}
local function Notice(message,kind)
    if kind and CHAT_OPTIONS[kind] and
        (not Enabled("chatNotifications") or not Enabled(CHAT_OPTIONS[kind])) then return end
    PrintWrapped(L(message))
end
local function SafeText(s)
    if type(s) ~= "string" or (issecretvalue and issecretvalue(s)) then return nil end
    return s
end
local function Trim(v) return (v or ""):match("^%s*(.-)%s*$") end
local function Realm()
    local r = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName() or ""
    return (r:gsub("%s+", ""))
end
local function FullName(name)
    name=SafeText(name)
    if not name then return nil end
    name=Trim(name)
    if name=="" or name=="GUEST" or name=="BUYER" then return nil end
    if not name:find("-",1,true) then name=name.."-"..Realm() end
    return name
end
local function Canonical(name)
    local full=FullName(name)
    -- Keep legacy SavedVariables keys stable; normalize only comparisons and
    -- presentation separately so existing accented entries remain accessible.
    return full and full:lower()
end
-- Uppercase only the first complete UTF-8 character. Byte slicing a
-- multibyte initial before calling :upper() can damage non-ASCII names.
-- Preserve deliberate mixed case everywhere else in the entry.
RGStyle.AccentedInitialUpper={
    ["\195\160"]="\195\128",
    ["\195\161"]="\195\129",
    ["\195\162"]="\195\130",
    ["\195\163"]="\195\131",
    ["\195\164"]="\195\132",
    ["\195\165"]="\195\133",
    ["\195\166"]="\195\134",
    ["\195\167"]="\195\135",
    ["\195\168"]="\195\136",
    ["\195\169"]="\195\137",
    ["\195\170"]="\195\138",
    ["\195\171"]="\195\139",
    ["\195\172"]="\195\140",
    ["\195\173"]="\195\141",
    ["\195\174"]="\195\142",
    ["\195\175"]="\195\143",
    ["\195\176"]="\195\144",
    ["\195\177"]="\195\145",
    ["\195\178"]="\195\146",
    ["\195\179"]="\195\147",
    ["\195\180"]="\195\148",
    ["\195\181"]="\195\149",
    ["\195\182"]="\195\150",
    ["\195\184"]="\195\152",
    ["\195\185"]="\195\153",
    ["\195\186"]="\195\154",
    ["\195\187"]="\195\155",
    ["\195\188"]="\195\156",
    ["\195\189"]="\195\157",
    ["\195\190"]="\195\158",
    ["\195\191"]="\197\184",
    ["\197\147"]="\197\146",
    ["\197\161"]="\197\160",
    ["\197\190"]="\197\189",
    ["\197\130"]="\197\129",
    ["\196\145"]="\196\144",
    ["\196\177"]="\073",
}
-- Character and nickname comparisons are case-insensitive but accent-sensitive.
-- Lua's :lower() handles ASCII, not the UTF-8 uppercase letters permitted in
-- character names. Keep display strings untouched and fold only lookup keys.
RGStyle.AccentedLower={}
for lower,upper in pairs(RGStyle.AccentedInitialUpper) do
    if #upper>1 then RGStyle.AccentedLower[upper]=lower end
end
function RGStyle.UTF8Casefold(value)
    return (value:gsub("[\194-\244][\128-\191]+",function(character)
        return RGStyle.AccentedLower[character] or character
    end):lower())
end
function RGStyle.CapitalizeEntry(value)
    value=Trim(value or "")
    local first=value:byte(1)
    if not first then return value end
    if first<128 then return value:sub(1,1):upper()..value:sub(2) end
    local length=first>=240 and 4 or first>=224 and 3 or first>=192 and 2 or 1
    local initial=value:sub(1,length)
    return (RGStyle.AccentedInitialUpper[initial] or initial)..value:sub(length+1)
end
-- Reuse Invite List's official realm spelling table and unambiguous fuzzy
-- correction for names entered manually.  InviteTools loads after RaidGroups
-- in the TOC, so resolve the service at click time, not during file loading.
-- Returns the corrected Character-Realm, a correction description, or an
-- unrecognized realm. Never guess when the resolver reports an ambiguity.
function RGStyle.CorrectEnteredRealm(entered)
    local name=SafeText(entered)
    if not name then return entered end
    name=RGStyle.CapitalizeEntry(name)
    local character,realm=name:match("^([^%-]+)%-(.+)$")
    if not character or not realm then return name end
    local realmNames=ns.InviteTools and ns.InviteTools.RealmNames
    if not realmNames or type(realmNames.Resolve)~="function" then return name end
    local corrected=realmNames.Resolve(realm)
    if corrected then
        if corrected~=realm then
            return character.."-"..corrected, realm.." -> "..corrected
        end
        return name
    end
    return name,nil,realm
end
function RGStyle.ReportRealmCorrection(_,unknown)
    -- Correct valid realm spellings silently; warn only for unknown realms.
    if unknown then Notice("Realm not recognized (kept as typed): "..unknown) end
end
local function CopyKeys(source)
    local result={}
    for key,value in pairs(source or {}) do if value then result[key]=true end end
    return result
end
local function CopyPinned(from)
    local copy={}
    for i=1,SLOT_COUNT do if from and from[i] then copy[i]=true end end
    return copy
end
local function CopyDraft(from)
    local t = {}
    for i = 1, SLOT_COUNT do
        local seat = from and from[i] or nil
        t[i] = seat == "BUYER" and "GUEST" or seat
    end
    return t
end
-- Upgrade Buyer settings from earlier EUI Raid Groups releases once. Both
-- positive and negative overrides are preserved, including boolean values.
local function MigrateGuestModes(current, previous)
    current = type(current)=="table" and current or {}
    if type(previous)=="table" then
        for key,value in pairs(previous) do
            if current[key]==nil then current[key]=value end
        end
    end
    for key,value in pairs(current) do
        if value=="buyer" then current[key]="guest"
        elseif value=="notbuyer" then current[key]="notguest" end
    end
    return current
end
local function Defaults()
    EllesmereUIRaidGroupsData = type(EllesmereUIRaidGroupsData) == "table" and EllesmereUIRaidGroupsData or {}
    data = EllesmereUIRaidGroupsData
    data.setups = type(data.setups) == "table" and data.setups or {}
    data.nicknames = type(data.nicknames) == "table" and data.nicknames or {}
    data.suppressed = type(data.suppressed) == "table" and data.suppressed or {}
    data.nicknameSharing = type(data.nicknameSharing) == "table" and data.nicknameSharing or {}
    data.nicknameGroups = type(data.nicknameGroups) == "table" and data.nicknameGroups or {}
    -- Persist visual expansion between /reload and game sessions. An absent key
    -- keeps the existing default (expanded) for older saved databases.
    data.nicknameCollapsed = type(data.nicknameCollapsed) == "table" and data.nicknameCollapsed or {}
    nickCollapsed = data.nicknameCollapsed
    data.nextNicknameGroupID = tonumber(data.nextNicknameGroupID) or 0
    -- Upgrade the prior per-character database once, retaining manual flags.
    -- Existing identical nicknames were displayed together; preserve that
    -- visual grouping without ever using the nickname as a future group ID.
    local legacy = {}
    for key, rec in pairs(data.nicknames) do
        if type(rec)=="table" and SafeText(rec.name) and SafeText(rec.nickname) then
            if not rec.groupId or not data.nicknameGroups[rec.groupId] then
                local label=RGStyle.UTF8Casefold(rec.nickname)
                if not legacy[label] then
                    data.nextNicknameGroupID=data.nextNicknameGroupID+1
                    legacy[label]="g"..data.nextNicknameGroupID
                    data.nicknameGroups[legacy[label]]={nickname=rec.nickname,locked=false,
                        source=rec.manual and "Manual" or "Legacy",updated=0}
                end
                rec.groupId=legacy[label]
            end
            rec.nickname=data.nicknameGroups[rec.groupId].nickname
        end
    end
    -- Discard obsolete group IDs and false/non-boolean values without
    -- modifying the nickname database or the user's valid collapsed groups.
    for id,collapsed in pairs(nickCollapsed) do
        if collapsed ~= true or not data.nicknameGroups[id] then nickCollapsed[id]=nil end
    end
    data.guests = MigrateGuestModes(data.guests,data.buyers)
    data.buyers = nil
    for _,setup in ipairs(data.setups) do
        if type(setup)=="table" then
            setup.slots=CopyDraft(setup.slots)
            setup.emptyPinnedSeats=CopyPinned(setup.emptyPinnedSeats)
            setup.normalGuestSeats=CopyPinned(setup.normalGuestSeats)
            for i=1,SLOT_COUNT do
                if setup.slots[i] then setup.emptyPinnedSeats[i]=nil end
            end
            setup.guestModes=MigrateGuestModes(setup.guestModes,setup.buyerModes)
            setup.buyerModes=nil
            if type(setup.pinnedSeats)~="table" then
                -- Older saved setups identified a fixed Guest by a named slot
                -- plus a per-setup Guest classification. Preserve that intent.
                setup.pinnedSeats={}
                for i=1,SLOT_COUNT do
                    local name=setup.slots[i]
                    if name and name~="GUEST" and name~=RGStyle.SETUP_GUEST and setup.guestModes[Canonical(name)]=="guest" then
                        setup.pinnedSeats[i]=true
                    end
                end
            end
            setup.pinnedSeats=CopyPinned(setup.pinnedSeats)
            for i=1,SLOT_COUNT do
                if not setup.slots[i] or setup.slots[i]=="GUEST" or setup.slots[i]==RGStyle.SETUP_GUEST or setup.pinnedSeats[i] then
                    setup.normalGuestSeats[i]=nil
                end
            end
        end
    end
    data.split = type(data.split) == "table" and data.split or {}
    if type(data.split.groups) ~= "table" then
        data.split.groups = {true,true,true,true,false,false,false,false}
    end
    if type(data.split.parts) ~= "number" then data.split.parts = 2 end
    if data.split.alternate == nil then data.split.alternate = false end
    -- One-time migration: this release enables Exact Positions by default, as
    -- requested. Later changes to the toggle are never overridden.
    if not data.exactPositionsDefaultV2 then
        data.exactPositions = true
        data.exactPositionsDefaultV2 = true
    end
    if data.keepChanges == nil then data.keepChanges = false end
end
-- One canonical character belongs to exactly one immutable nickname group.
-- Groups survive changes to their displayed labels, including NSRT's empty
-- nickname/unshare notifications. Only confirmed UI actions remove entries.
local function NewNicknameGroup(nickname,manual,source)
    data.nextNicknameGroupID=data.nextNicknameGroupID+1
    local id="g"..data.nextNicknameGroupID
    data.nicknameGroups[id]={nickname=nickname,locked=false,
        source=source or (manual and "Manual" or "Provider"),updated=time()}
    return id
end
-- Warn when a confirmed nickname change takes a label already used by a
-- different identity group. Never merge groups or block the update on this
-- basis; shared labels do not prove that the characters belong together.
local function OtherNicknameOwner(id,nickname)
    local otherIDs={}
    for otherID,other in pairs(data.nicknameGroups) do
        if otherID~=id and type(other)=="table" and SafeText(other.nickname)
            and RGStyle.UTF8Casefold(other.nickname)==RGStyle.UTF8Casefold(nickname) then
            otherIDs[otherID]=true
        end
    end
    local owner
    for _,rec in pairs(data.nicknames) do
        if type(rec)=="table" and otherIDs[rec.groupId] and SafeText(rec.name) then
            if not owner or RGStyle.UTF8Casefold(rec.name)<RGStyle.UTF8Casefold(owner) then owner=rec.name end
        end
    end
    return owner
end
local function RenameNicknameGroup(id,nickname,manual,source,changedCharacter)
    local group=data.nicknameGroups[id]
    if not group or (group.locked and not manual) then return false end
    if manual then nickname=RGStyle.CapitalizeEntry(nickname) end
    if group.nickname==nickname then return false end
    local previous=group.nickname
    local existingOwner=not manual and source=="NSRT event"
        and SafeText(changedCharacter) and OtherNicknameOwner(id,nickname)
    group.nickname=nickname
    group.source=source or (manual and "Manual" or "Provider")
    group.updated=time()
    for _,rec in pairs(data.nicknames) do
        if type(rec)=="table" and rec.groupId==id then rec.nickname=nickname end
    end
    if changedCharacter and not manual and source=="NSRT event" then
        Notice(LF("Nickname changed: %s changed %s to %s.", changedCharacter,previous,nickname),"nickname")
    end
    if existingOwner then
        Notice(LF("Nickname collision: %s changed %s to %s; %s already uses that nickname.",
            changedCharacter,previous,nickname,existingOwner),"nickname")
    end
    return true
end
local function StoreNickname(name,nickname,manual,source,confirmed)
    if not data then return false end
    name,nickname=SafeText(name),SafeText(nickname)
    if manual then nickname=RGStyle.CapitalizeEntry(nickname) end
    local key=name and Canonical(name)
    if not key or not nickname then return false end
    nickname=Trim(nickname)
    -- A nickname may legitimately match the character's short name (for
    -- example Hellsy-Area52 -> Hellsy). Presence of a nickname is sufficient.
    if nickname=="" then return false end
    local rec=data.nicknames[key]
    -- Deletions are persistent tombstones, never undone by stale provider caches.
    if data.suppressed[key] and not manual then return false end
    if rec then
        local group=data.nicknameGroups[rec.groupId]
        if not group then return false end
        if RGStyle.UTF8Casefold(group.nickname)==RGStyle.UTF8Casefold(nickname) then
            if manual and group.nickname~=nickname then
                return RenameNicknameGroup(rec.groupId,nickname,true,source)
            end
            return false
        end
        if group.locked and not manual then return false end
        -- An ordinary provider lookup is an unversioned cache read. It may
        -- populate a new identity, but cannot override a known label.
        if not confirmed and not manual then return false end
        if manual then
            -- Editing an individual character is different from choosing
            -- "Edit" on a group. Detach without renaming all other alts.
            local target,conflict=nil,false
            for id,g in pairs(data.nicknameGroups) do
                if id~=rec.groupId and RGStyle.UTF8Casefold(g.nickname)==RGStyle.UTF8Casefold(nickname) then
                    if target then conflict=true;break end
                    target=id
                end
            end
            local id=(not conflict and target) or NewNicknameGroup(nickname,true,source)
            rec.groupId=id
            rec.nickname=nickname
            rec.manual=true
            -- Leave old group metadata intact; linked alts stay together.
            return true
        end
        return RenameNicknameGroup(rec.groupId,nickname,manual,source,FullName(name))
    end
    -- Adopt an existing group only if its label uniquely identifies one
    -- group; equal labels can belong to different people.
    local uniqueID,ambiguous=nil,false
    for id,group in pairs(data.nicknameGroups) do
        if type(group)=="table" and RGStyle.UTF8Casefold(group.nickname)==RGStyle.UTF8Casefold(nickname) then
            if uniqueID then ambiguous=true;break end
            uniqueID=id
        end
    end
    local id=(not ambiguous and uniqueID) or NewNicknameGroup(nickname,manual,source)
    data.nicknames[key]={name=FullName(name),nickname=nickname,groupId=id,manual=manual or false}
    if manual then data.suppressed[key]=nil end
    return true
end
-- Old setup snapshots are legacy input only. Character-Realm in setup.slots is
-- authoritative; displayed nicknames are always resolved from the live global
-- history, so renames cannot leave stale labels in saved compositions.
local function MigrateSetupNicknameSnapshots()
    for _,setup in ipairs(data.setups) do
        if type(setup)=="table" and type(setup.nicknames)=="table" then
            for _,name in pairs(setup.slots or {}) do
                local key=Canonical(name)
                local nick=key and setup.nicknames[key]
                if key and SafeText(nick) and not data.nicknames[key] then
                    StoreNickname(name,nick,false,"Legacy setup",false)
                end
            end
            setup.nicknames=nil
        end
    end
end
local function SavedNickname(name)
    local key=Canonical(name)
    local rec=key and data and data.nicknames[key]
    if not rec then return nil end
    local group=data.nicknameGroups[rec.groupId]
    return (group and group.nickname) or rec.nickname
end
-- Resolve chat labels from the persistent nickname database, independently of
-- the editor's Show Nicknames display toggle. Name-change/unshare notices use
-- the real Character-Realm identity explicitly and do not call this helper.
local function ChatName(name)
    return (name and SavedNickname(name)) or FullName(name) or SafeText(name) or "Unknown"
end
local function GuestMode(name)
    local key=Canonical(name)
    if not key or not data or not Enabled("guestFeatures") then return false end
    local setup=selectedSetup and data.setups[selectedSetup]
    local localModes=setup and setup.guestModes or nil
    local value=localModes and localModes[key]
    if value==nil then value=data.guests[key] end
    if value=="guest" or value==true then return true end
    if value=="notguest" or value==false then return false end
    return Enabled("guestAutoDetect") and not SavedNickname(name)
end
local function Display(name, unit)
    if name == "GUEST" then return L("Guest") end
    if name == RGStyle.SETUP_GUEST then return "Pinned Guest (Setup)" end
    local p = P()
    if p and p.showNicknames == false then return name or "" end
    return (name and SavedNickname(name)) or name or ""
end
local function RememberFromUnit(unit, realName)
    if not Enabled("nicknameLearning") or not Enabled("nicknameRosterLearn")
        or not ns.GetNicknameForUnit or not data then return end
    local ok, nick = pcall(ns.GetNicknameForUnit, unit)
    if ok and nick and SafeText(nick) then StoreNickname(realName, nick, false, "Provider", false) end
end
-- Store class information only when a Blizzard roster supplies a verified
-- class token. Nickname history alone cannot determine an offline alt's class.
-- This cache belongs to the nickname record and never changes raid planning.
function RGStyle.RememberNicknameClass(name, class)
    if issecretvalue and (issecretvalue(name) or issecretvalue(class)) then return end
    if type(name)~="string" or type(class)~="string" then return end
    local coords=CLASS_ICON_TCOORDS
    if not coords or not coords[class] then return end
    local key=Canonical(name)
    local rec=key and data and data.nicknames[key]
    if rec and rec.class~=class then rec.class=class end
end
function RGStyle.LearnNicknameClasses()
    if not data then return end
    -- The main editor may not be open, so check the current raid independently.
    if IsInRaid() then
        local count=math.min(SLOT_COUNT,GetNumGroupMembers() or 0)
        for i=1,count do
            local name,_,_,_,_,class=GetRaidRosterInfo(i)
            RGStyle.RememberNicknameClass(name,class)
        end
    elseif UnitName and UnitClass then
        local name=UnitName("player")
        local _,class=UnitClass("player")
        RGStyle.RememberNicknameClass(name,class)
    end
    if IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        for i=1,GetNumGuildMembers() do
            local name,_,_,_,_,_,_,_,_,_,class=GetGuildRosterInfo(i)
            RGStyle.RememberNicknameClass(name,class)
        end
    end
end
local function Roster()
    rosterByKey, rosterSorted = {}, {}
    if not IsInRaid() then return end
    local count = GetNumGroupMembers() or 0
    for i = 1, SLOT_COUNT do
        local name, rank, group, _, _, class, _, online = GetRaidRosterInfo(i)
        if SafeText(name) and name ~= "Unknown" and type(group) == "number" and group >= 1 and group <= 8 then
            local key = Canonical(name)
            if key then
                local info = {name=FullName(name), key=key, index=i, group=group, class=class,
                              online=online, rank=rank, unit="raid"..i}
                rosterByKey[key] = info
                rosterSorted[#rosterSorted+1] = info
                RGStyle.RememberNicknameClass(info.name, info.class)
                RememberFromUnit(info.unit, info.name)
            end
        end
    end
    table.sort(rosterSorted, function(a,b)
        if a.group ~= b.group then return a.group < b.group end
        return a.index < b.index
    end)
end
function ns.RaidGroupsPermitted()
    return IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
end
-- Identify individual raid members blocking protected subgroup changes, as
-- well as local combat lockdown. Avoid printing secret or unavailable values.
local function CombatBlockers()
    local names, seen = {}, {}
    if IsInRaid() then
        for i=1,SLOT_COUNT do
            local unit="raid"..i
            local ok,fighting=pcall(UnitAffectingCombat,unit)
            if ok and not (issecretvalue and issecretvalue(fighting)) and fighting then
                local name=SafeText((GetRaidRosterInfo(i)))
                if name and not seen[RGStyle.UTF8Casefold(name)] then
                    seen[RGStyle.UTF8Casefold(name)]=true
                    names[#names+1]=FullName(name) or name
                end
            end
        end
    end
    table.sort(names)
    return names, InCombatLockdown()
end
local function InGroupCombat()
    local names,locked=CombatBlockers()
    return locked or #names>0
end
local function WarnCombat(interrupted)
    local names,locked=CombatBlockers()
    if #names>0 then
        local labels={}
        for _,name in ipairs(names) do labels[#labels+1]=ChatName(name) end
        local heading=interrupted and "Group application interrupted: raid members in combat:" or
            "Cannot apply groups: raid members in combat:"
        Notice(LF("%s %s",L(heading),table.concat(labels,", ")),"combat")
    elseif locked then
        Notice(interrupted and "Group application interrupted by combat." or
            "Cannot apply groups while in combat.","combat")
    end
end
-- Resolve saved character identities against the *current* raid without
-- rewriting the setup. Exact character matches are reserved first; otherwise
-- use only a unique, unused raid character in the very same nickname group.
-- A shared displayed nickname is not sufficient: separate nickname groups
-- may legitimately have identical labels.
function ns.RaidGroupsResolveRosterSource(source,pinnedSeats)
    source=source or draft
    if pinnedSeats==nil and source==draft then pinnedSeats=draftPinned end
    local resolved,used,groupMembers,links,ambiguous=CopyDraft(source),{},{},{},{}
    for i=1,SLOT_COUNT do
        local name=source[i]
        local key=name and name~="GUEST" and name~=RGStyle.SETUP_GUEST and Canonical(name)
        if key and rosterByKey[key] then used[key]=true end
    end
    for _,member in ipairs(rosterSorted) do
        if not used[member.key] then
            local record=data.nicknames[member.key]
            local id=record and record.groupId
            if id and data.nicknameGroups[id] then
                groupMembers[id]=groupMembers[id] or {}
                groupMembers[id][#groupMembers[id]+1]=member
            end
        end
    end
    for i=1,SLOT_COUNT do
        local name=source[i]
        local key=name and name~="GUEST" and name~=RGStyle.SETUP_GUEST and Canonical(name)
        if key and not rosterByKey[key] and not (pinnedSeats and pinnedSeats[i]) then
            local record=data.nicknames[key]
            local id=record and record.groupId
            local candidates=id and data.nicknameGroups[id] and groupMembers[id]
            if candidates then
                local match,count=nil,0
                for _,member in ipairs(candidates) do
                    if not used[member.key] then
                        match=member
                        count=count+1
                    end
                end
                if count==1 then
                    resolved[i]=match.name
                    used[match.key]=true
                    links[#links+1]={source=name,target=match.name,seat=i}
                elseif count>1 then
                    ambiguous[#ambiguous+1]=name
                end
            end
        end
    end
    return resolved,links,ambiguous
end
local function Membership(source)
    local names = {}
    local resolved=ns.RaidGroupsResolveRosterSource(source or draft)
    for i=1,SLOT_COUNT do
        local name=resolved[i]
        local key = name and name~="GUEST" and name~=RGStyle.SETUP_GUEST and Canonical(name)
        if key then names[key] = true end
    end
    return names
end
-- Return eligible unlisted guests in a deterministic order, putting explicit
-- Guest assignments before nickname-less automatically recognized players.
local function GuestCandidates(source,excluded)
    local used=Membership(source)
    excluded=excluded or removedGuestKeys
    local available={}
    if not Enabled("guestFeatures") or not Enabled("guestFillSeats") then return available end
    local selected=selectedSetup and data.setups[selectedSetup]
    local modes=selected and selected.guestModes
    for _,m in ipairs(rosterSorted) do
        if not used[m.key] and not excluded[m.key] and GuestMode(m.name) then
            local mode=modes and modes[m.key]
            if mode==nil then mode=data.guests[m.key] end
            available[#available+1]={member=m,
                manual=(mode=="guest" or mode==true) and 0 or 1,
                unknown=SavedNickname(m.name) and 1 or 0}
        end
    end
    table.sort(available,function(a,b)
        if a.manual~=b.manual then return a.manual<b.manual end
        if a.unknown~=b.unknown then return a.unknown<b.unknown end
        return a.member.index<b.member.index
    end)
    return available
end

-- Only use this expansion when preparing a fresh Apply or opening a Preview.
-- It never writes to the editable draft or a saved setup. The earliest empty
-- positions (such as Group 4 seats 4-5) are used before later empty groups.
local function AutoGuestSource(source,excluded,emptyPinned)
    local expanded=CopyDraft(source)
    if not Enabled("guestAutoEmptySeats") then return expanded end
    local count=#GuestCandidates(expanded,excluded)
    for i=1,SLOT_COUNT do
        if expanded[i]=="GUEST" or expanded[i]==RGStyle.SETUP_GUEST then count=count-1 end
    end
    if count>0 then
        for i=1,SLOT_COUNT do
            if not expanded[i] and not (emptyPinned and emptyPinned[i]) then
                expanded[i]="GUEST"
                count=count-1
                if count==0 then break end
            end
        end
    end
    return expanded
end

local function GuestAssignments(source, fixedGuestNames, excluded)
    source=source or draft
    -- Each Setup placeholder is a protected individual reservation. It may
    -- only receive a raid member absent from the planned roster and Nicknames.
    local assigned, reserved = {}, {}
    local used=Membership(source)
    excluded=excluded or removedGuestKeys
    local genericEligible={}
    for _,member in ipairs(rosterSorted) do
        local key=member.key
        local mode=data.guests[key]
        local selected=selectedSetup and data.setups[selectedSetup]
        if selected and selected.guestModes and selected.guestModes[key]~=nil then
            mode=selected.guestModes[key]
        end
        if not used[key] and not excluded[key] and not SavedNickname(member.name)
            and mode~="notguest" and mode~=false then
            genericEligible[key]=member
        end
    end
    -- Preview choices are retained only if they still satisfy the generic
    -- eligibility rule. One character can never satisfy two Guest seats.
    for i=1,SLOT_COUNT do
        local value=source[i]
        local fixedName=fixedGuestNames and fixedGuestNames[i]
        if fixedName and (value=="GUEST" or value==RGStyle.SETUP_GUEST) then
            local member=rosterByKey[Canonical(fixedName)]
            if member and not used[member.key] and not excluded[member.key]
                and not reserved[member.key] and
                (value=="GUEST" or genericEligible[member.key]) then
                assigned[i]=member
                reserved[member.key]=true
            end
        end
    end
    -- Reserve generic pinned seats *before* ordinary replaceable Guests.
    local candidatePos=1
    for i=1,SLOT_COUNT do
        if source[i]==RGStyle.SETUP_GUEST and not assigned[i] then
            while rosterSorted[candidatePos] and
                (not genericEligible[rosterSorted[candidatePos].key] or
                 reserved[rosterSorted[candidatePos].key]) do
                candidatePos=candidatePos+1
            end
            local member=rosterSorted[candidatePos]
            if member then
                assigned[i]=member
                reserved[member.key]=true
                candidatePos=candidatePos+1
            end
        end
    end
    -- Ordinary Guests retain their pre-existing preference/ordering rules.
    if Enabled("guestFeatures") and Enabled("guestFillSeats") then
        local eligible=GuestCandidates(source,excluded)
        local pos=1
        for i=1,SLOT_COUNT do
            if source[i]=="GUEST" and not assigned[i] then
                while eligible[pos] and reserved[eligible[pos].member.key] do pos=pos+1 end
                if eligible[pos] then
                    local member=eligible[pos].member
                    assigned[i]=member
                    reserved[member.key]=true
                    pos=pos+1
                end
            end
        end
    end
    return assigned
end

local function IsUnlisted(name)
    local k = Canonical(name)
    if not k then return false end
    return not Membership()[k]
end
-- The two history stacks hold complete snapshots, including selected setup
-- persistence when Keep Changes is enabled. Avoid a module-level local here:
-- RaidGroups is close to Lua 5.1's 200-local limit.
function RGStyle.CaptureDraftSnapshot()
    local selected=selectedSetup and data.setups[selectedSetup]
    return {draft=CopyDraft(draft),pinned=CopyPinned(draftPinned),
        normalGuests=CopyPinned(draftGuest),
        emptyPinned=CopyPinned(RGStyle.emptyPinnedDraft),selected=selected,
        exclusions=CopyKeys(removedGuestKeys),
        dirty=dirty,saved=selected and CopyDraft(selected.slots),
        savedPinned=selected and CopyPinned(selected.pinnedSeats),
        savedNormalGuests=selected and CopyPinned(selected.normalGuestSeats),
        savedEmptyPinned=selected and CopyPinned(selected.emptyPinnedSeats),
        updated=selected and selected.updated}
end
function RGStyle.RestoreDraftSnapshot(snapshot)
    draft=CopyDraft(snapshot.draft)
    draftPinned=CopyPinned(snapshot.pinned)
    draftGuest=CopyPinned(snapshot.normalGuests)
    RGStyle.emptyPinnedDraft=CopyPinned(snapshot.emptyPinned)
    removedGuestKeys=CopyKeys(snapshot.exclusions)
    previewGuestAnnotations={}
    selectedSetup=nil
    if snapshot.selected then
        for i,entry in ipairs(data.setups) do
            if entry==snapshot.selected then selectedSetup=i;break end
        end
        if selectedSetup and snapshot.saved then
            snapshot.selected.slots=CopyDraft(snapshot.saved)
            snapshot.selected.pinnedSeats=CopyPinned(snapshot.savedPinned)
            snapshot.selected.normalGuestSeats=CopyPinned(snapshot.savedNormalGuests)
            snapshot.selected.emptyPinnedSeats=CopyPinned(snapshot.savedEmptyPinned)
            snapshot.selected.updated=snapshot.updated
        end
    end
    dirty=snapshot.dirty
    if Refresh then Refresh() end
    if RefreshSetups then RefreshSetups() end
end
local function PushUndo()
    undoStack[#undoStack+1]=RGStyle.CaptureDraftSnapshot()
    if #undoStack>UNDO_LIMIT then table.remove(undoStack,1) end
    -- A new edit creates a new branch: old redos are no longer applicable.
    RGStyle.redoStack={}
end
local function UndoDraft()
    if applyState then Notice("Cannot undo while applying raid groups.");return end
    local last=table.remove(undoStack)
    if not last then Notice("No draft changes to undo.");return end
    RGStyle.setupLoadToggle=nil
    local redos=RGStyle.redoStack
    redos[#redos+1]=RGStyle.CaptureDraftSnapshot()
    if #redos>UNDO_LIMIT then table.remove(redos,1) end
    RGStyle.RestoreDraftSnapshot(last)
end
function RGStyle.RedoDraft()
    if applyState then Notice("Cannot redo while applying raid groups.");return end
    local last=table.remove(RGStyle.redoStack)
    if not last then Notice("No draft changes to redo.");return end
    RGStyle.setupLoadToggle=nil
    undoStack[#undoStack+1]=RGStyle.CaptureDraftSnapshot()
    if #undoStack>UNDO_LIMIT then table.remove(undoStack,1) end
    RGStyle.RestoreDraftSnapshot(last)
end
local function SaveEdit()
    if applyState then StopApply("Group application stopped: draft changed during Apply Groups.") end
    dirty = true
    if selectedSetup and data.keepChanges and data.setups[selectedSetup] then
        data.setups[selectedSetup].slots = CopyDraft(draft)
        data.setups[selectedSetup].pinnedSeats=CopyPinned(draftPinned)
        data.setups[selectedSetup].normalGuestSeats=CopyPinned(draftGuest)
        data.setups[selectedSetup].emptyPinnedSeats=CopyPinned(RGStyle.emptyPinnedDraft)
        data.setups[selectedSetup].updated = time()
        dirty = false
    end
    if Refresh then Refresh() end
    if RefreshSetups and setupWindow and setupWindow:IsShown() then RefreshSetups() end
end
local function SetDraft(i, name, guestKind)
    if i < 1 or i > SLOT_COUNT then return end
    name = SafeText(name)
    if name then name = Trim(name) end
    if not name or name == "" then name = nil end
    if name == "BUYER" then name = "GUEST" end
    if name and name ~= "GUEST" and name~=RGStyle.SETUP_GUEST then
        local key = Canonical(name)
        if not key then return end
        for j=1,SLOT_COUNT do
            if j ~= i and Canonical(draft[j]) == key then
                Notice("Character already assigned to another slot.")
                return
            end
        end
    end
    if draft[i] == name and not RGStyle.emptyPinnedDraft[i] and
        (not guestKind or ((not not draftPinned[i])==(guestKind=="pinned") and
            (not not draftGuest[i])==(guestKind=="guest"))) then return end
    previewGuestAnnotations={}
    local previous=draft[i]
    PushUndo()
    draft[i] = name
    draftPinned[i]=(name and name~="GUEST" and name~=RGStyle.SETUP_GUEST and guestKind=="pinned") or nil
    draftGuest[i]=(name and name~="GUEST" and name~=RGStyle.SETUP_GUEST and guestKind=="guest") or nil
    RGStyle.emptyPinnedDraft[i]=nil
    if previous and previous~="GUEST" and previous~=RGStyle.SETUP_GUEST and previous~=name then
        local oldKey=Canonical(previous)
        if oldKey then removedGuestKeys[oldKey]=true end
    end
    if name and name~="GUEST" and name~=RGStyle.SETUP_GUEST then
        local key=Canonical(name)
        if key then removedGuestKeys[key]=nil end
    end
    SaveEdit()
end
function RGStyle.SetEmptyPinned(i, pinned)
    if i<1 or i>SLOT_COUNT then return end
    pinned=not not pinned
    if (not not RGStyle.emptyPinnedDraft[i])==pinned then return end
    PushUndo()
    if pinned then
        local previous=draft[i]
        if previous and previous~="GUEST" and previous~=RGStyle.SETUP_GUEST then
            local key=Canonical(previous)
            if key then removedGuestKeys[key]=true end
        end
        draft[i]=nil
        draftPinned[i]=nil
        draftGuest[i]=nil
        previewGuestAnnotations[i]=nil
        RGStyle.emptyPinnedDraft[i]=true
    else
        RGStyle.emptyPinnedDraft[i]=nil
    end
    SaveEdit()
end
function RGStyle.SetNamedGuestKind(i,kind)
    local name=draft[i]
    if not name or name=="GUEST" or name==RGStyle.SETUP_GUEST or RGStyle.emptyPinnedDraft[i] then return end
    local pinned=kind=="pinned"
    local normal=kind=="guest"
    if (not not draftPinned[i])==pinned and (not not draftGuest[i])==normal then return end
    PushUndo()
    draftPinned[i]=pinned or nil
    draftGuest[i]=normal or nil
    SaveEdit()
end
local function FromRoster(skipUndo)
    Roster()
    local seatCount = {}
    for g=1,NUM_GROUPS do seatCount[g] = 0 end
    local nextDraft = {}
    for _,m in ipairs(rosterSorted) do
        seatCount[m.group] = seatCount[m.group] + 1
        if seatCount[m.group] <= GROUP_SIZE then
            nextDraft[(m.group-1)*GROUP_SIZE+seatCount[m.group]] = m.name
        end
    end
    if not skipUndo then PushUndo() end
    draft = nextDraft
    draftPinned={}
    draftGuest={}
    RGStyle.emptyPinnedDraft={}
    removedGuestKeys={}
    selectedSetup = nil
    RGStyle.setupLoadToggle=nil
    SaveEdit()
end
-- Clicking the already loaded row toggles back to the exact editor and
-- independent preview state from before that setup was loaded. This only
-- changes the planning UI; it never reverses a confirmed raid rearrangement.
local function LoadSetup(i, toggleOnClick)
    local entry = data.setups[i]
    if not entry then return end
    local toggle=RGStyle.setupLoadToggle
    if toggleOnClick and toggle and toggle.entry==entry and selectedSetup==i then
        if applyState then Notice("Cannot restore the draft while applying raid groups.");return end
        RGStyle.setupLoadToggle=nil
        PushUndo()
        RGStyle.RestoreDraftSnapshot(toggle.draft)
        if RGStyle.RestorePreviewFromSetupToggle then
            RGStyle.RestorePreviewFromSetupToggle(toggle.preview)
        end
        return
    end
    -- Before the main window's first opening, its default composition would
    -- have been the current raid. Capture that rather than an empty draft.
    if not firstDraftLoaded and not selectedSetup and not next(draft) then
        FromRoster(true)
        dirty=false
        firstDraftLoaded=true
    end
    local before=RGStyle.CaptureDraftSnapshot()
    local beforePreview=RGStyle.CapturePreviewSnapshot and RGStyle.CapturePreviewSnapshot()
    PushUndo()
    RGStyle.setupLoadToggle={entry=entry,draft=before,preview=beforePreview}
    draft = CopyDraft(entry.slots)
    draftPinned=CopyPinned(entry.pinnedSeats)
    draftGuest=CopyPinned(entry.normalGuestSeats)
    RGStyle.emptyPinnedDraft=CopyPinned(entry.emptyPinnedSeats)
    removedGuestKeys={}
    firstDraftLoaded=true
    selectedSetup = i
    dirty = false
    if Refresh then Refresh() end
    if RefreshSetups then RefreshSetups() end
    -- A setup load from its manager or /euirg opens the composition even
    -- when the main window was not previously visible. Never toggle it off.
    if (not win or not win:IsShown()) and ns.ShowRaidGroupsWindow then
        ns.ShowRaidGroupsWindow()
    end
    -- Loading a new setup replaces any live (or combat-suspended) preview
    -- with the just-loaded composition; it never confirms Apply Groups.
    if RGStyle.RefreshPreviewFromSetup then RGStyle.RefreshPreviewFromSetup() end
end
local function UniqueSetupName(name, skip)
    for i,setup in ipairs(data.setups) do
        if i ~= skip and setup.name:lower() == name:lower() then return false end
    end
    return true
end
local function SaveSetup(name)
    name = Trim(SafeText(name) or "")
    if name == "" then Notice("Enter a setup name."); return end
    if not UniqueSetupName(name) then Notice("A setup with that name already exists."); return end
    table.insert(data.setups, {name=name, slots=CopyDraft(draft),
        pinnedSeats=CopyPinned(draftPinned),normalGuestSeats=CopyPinned(draftGuest),
        emptyPinnedSeats=CopyPinned(RGStyle.emptyPinnedDraft),
        guestModes={},updated=time()})
    selectedSetup = #data.setups
    RGStyle.setupLoadToggle=nil
    dirty = false
    if Refresh then Refresh() end
    if RefreshSetups then RefreshSetups() end
end

-------------------------------------------------------------------------------
-- Presentation helpers. All input and controls use ordinary insecure frames:
-- they can be edited in combat because they never invoke protected APIs.
-------------------------------------------------------------------------------
-- Raid Tools / Window Skins visual primitives: flat dark background,
-- 25px title band, 1px neutral line, and white 10% native hover highlight.
-- This intentionally does not depend on EllesmereUIBlizzardSkin being enabled.
local function Text(parent, size, content, color)
    local fontSize = size or 11
    local f = TrackFont(EllesmereUI.MakeFont(parent, fontSize, nil, 1, 1, 1), fontSize)
    if content then f:SetText(L(content)) end
    if color then f:SetTextColor(unpack(color)) end
    return f
end
RGStyle.windowNames={
    EllesmereUIRaidGroupsWindow="main",
    EllesmereUIRaidGroupVisualPreview="preview",
    EllesmereUIRaidGroupSetups="setups",
    EllesmereUIRaidGroupNicknames="nicknames",
    EllesmereUIRaidGroupsTransfer="import",
    EllesmereUIRaidGroupSplit="split",
    EllesmereUIRaidGroupBackup="backup",
    EllesmereUIRaidGroupInput="prompt",
}
function RGStyle.WindowScaleValue(key)
    local p=P()
    if p and p.windowScalingEnabled==false then return 1 end
    if key=="main" then return tonumber(p and p.scale) or 1 end
    local scales=p and p.windowScales
    return tonumber(scales and scales[key]) or 1
end
function RGStyle.ApplyPanelScale(frame,key)
    if not frame then return end
    key=key or frame._raidGroupsScaleKey
    local w,h=frame:GetWidth(),frame:GetHeight()
    local sw=UIParent.GetWidth and UIParent:GetWidth() or w+40
    local sh=UIParent.GetHeight and UIParent:GetHeight() or h+40
    local base=EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale() or 1
    local scale=base*RGStyle.WindowScaleValue(key)
    if sw>40 and sh>40 and w>0 and h>0 then
        scale=math.min(scale,(sw-30)/w,(sh-30)/h)
    end
    frame:SetScale(math.max(.35,scale))
end
function RGStyle.ApplyAllPanelScales()
    for _,panel in pairs(RGStyle.panels) do RGStyle.ApplyPanelScale(panel) end
end
function ns.RaidGroupsWindowScale(key,value)
    local p=P()
    if key~="main" and key~="preview" and key~="setups" and key~="nicknames" and
       key~="import" and key~="export" and key~="split" and key~="backup" and key~="prompt" then return 1 end
    if value==nil then return RGStyle.WindowScaleValue(key) end
    if p then
        value=math.max(.5,math.min(2,tonumber(value) or 1))
        if key=="main" then p.scale=value
        else p.windowScales=p.windowScales or {};p.windowScales[key]=value end
        RGStyle.ApplyAllPanelScales()
    end
end
function ns.RaidGroupsPlayerFontSize(key,value)
    if not RGStyle.fonts[key] then return 11 end
    if value==nil then return RGStyle.PlayerFontSize(key) end
    local p=P()
    if p then
        p.playerFontSizes=p.playerFontSizes or {}
        p.playerFontSizes[key]=math.max(8,math.min(18,tonumber(value) or RGStyle.fonts[key]))
        ApplyFonts()
    end
end
-- Reusable list scrollbar: the WoW vertical slider increases from top to
-- bottom, so its value must match the list offset (0 = first entry).
-- Keep its hitbox inside the list and clear of interactive controls.
function RGStyle.ListScrollbar(parent,x,y,height,getOffset,setOffset,getMaximum)
    local bar=CreateFrame("Slider",nil,parent)
    bar:SetOrientation("VERTICAL")
    bar:SetSize(10,height)
    bar:SetPoint("TOPLEFT",x,y)
    bar:SetFrameLevel(parent:GetFrameLevel()+8)
    bar:SetMinMaxValues(0,1)
    bar:SetValueStep(1)
    local track=EllesmereUI.SolidTex(bar,"BACKGROUND",.12,.15,.17,.85)
    track:SetAllPoints()
    bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb=bar:GetThumbTexture()
    thumb:SetSize(10,28)
    local color=EllesmereUI.ELLESMERE_GREEN or {r=.08,g=.75,b=.60}
    thumb:SetColorTexture(color.r,color.g,color.b,.92)
    local syncing=false
    bar:SetScript("OnValueChanged",function(_,value)
        if syncing then return end
        local max=math.max(0,getMaximum())
        local offset=math.max(0,math.min(max,math.floor(value+.5)))
        if offset~=getOffset() then setOffset(offset) end
    end)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel",function(_,delta)
        local max=math.max(0,getMaximum())
        local offset=math.max(0,math.min(max,getOffset()-(delta>0 and 1 or -1)))
        if offset~=getOffset() then setOffset(offset) end
    end)
    function bar:Sync()
        local max=math.max(0,getMaximum())
        syncing=true
        self:SetMinMaxValues(0,math.max(1,max))
        self:SetValue(math.max(0,math.min(max,getOffset())))
        syncing=false
        self:SetShown(max>0)
    end
    bar:Sync()
    return bar
end
function RGStyle.ListWheel(target,handler)
    target:EnableMouseWheel(true)
    target:SetScript("OnMouseWheel",handler)
    for _,child in ipairs({target:GetChildren()}) do
        if child.EnableMouseWheel then
            child:EnableMouseWheel(true)
            child:SetScript("OnMouseWheel",handler)
        end
    end
end
-- Panel positions are checked only on a subsequent opening. While open,
-- users may drag any Raid Groups window beyond the viewport without clamping.
-- Compare coordinates in screen pixels to account for per-window scaling.
function RGStyle.PanelOutsideScreen(frame)
    if not frame or not UIParent then return false end
    local left,right,top,bottom = frame:GetLeft(),frame:GetRight(),frame:GetTop(),frame:GetBottom()
    if not (left and right and top and bottom) then return false end
    local scale=frame:GetEffectiveScale()
    local parentScale=UIParent:GetEffectiveScale()
    if not (scale and parentScale and scale>0 and parentScale>0) then return false end
    local screenLeft=(UIParent:GetLeft() or 0)*parentScale
    local screenBottom=(UIParent:GetBottom() or 0)*parentScale
    local screenRight=(UIParent:GetRight() or UIParent:GetWidth())*parentScale
    local screenTop=(UIParent:GetTop() or UIParent:GetHeight())*parentScale
    local tolerance=1
    return left*scale<screenLeft-tolerance or right*scale>screenRight+tolerance
        or bottom*scale<screenBottom-tolerance or top*scale>screenTop+tolerance
end
function RGStyle.ResetPanelPosition(frame)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
    -- The main window alone persists its position between openings/reloads.
    -- An offscreen coordinate must not be restored on the next opening.
    if frame._raidGroupsScaleKey=="main" then
        local profile=P()
        if profile then profile.pos={} end
    end
end
local function Panel(name, width, height)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    -- OnMouseUp here belongs to the panel background; interactive children
    -- (seats, dropdown choices, inputs, buttons) handle their own mouse clicks.
    -- Left-click and dragging retain their original behavior.
    f:SetScript("OnMouseUp",function(self,button)
        if button=="RightButton" then self:Hide() end
    end)
    EllesmereUI.SolidTex(f, "BACKGROUND", 0, 0, 0, 1):SetAllPoints()
    local titleBand = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    titleBand:SetColorTexture(0, 0, 0, .5)
    titleBand:SetPoint("TOPLEFT")
    titleBand:SetPoint("TOPRIGHT")
    titleBand:SetHeight(25)
    EllesmereUI.MakeBorder(f, .2, .2, .2, 1, EllesmereUI.PP)
    f:Hide()
    EllesmereUI.RegisterEscapeClose(f)
    f._raidGroupsScaleKey=RGStyle.windowNames[name]
    -- The window may remain offscreen until it is closed. Only a later
    -- opening resets it to the original centered position.
    f:HookScript("OnHide",function(self)
        if RGStyle.PanelOutsideScreen(self) then self._resetPositionOnNextOpen=true end
    end)
    f:HookScript("OnShow",function(self)
        if self._resetPositionOnNextOpen or RGStyle.PanelOutsideScreen(self) then
            RGStyle.ResetPanelPosition(self)
        end
        self._resetPositionOnNextOpen=nil
    end)
    RGStyle.panels[name]=f
    RGStyle.ApplyPanelScale(f)
    local close = CreateFrame("Button", nil, f)
    close:SetSize(21,21)
    close:SetPoint("TOPRIGHT", -7,-7)
    local l = Text(close, 16, "x"); l:SetPoint("CENTER")
    local hover = close:CreateTexture(nil,"HIGHLIGHT")
    hover:SetColorTexture(1,1,1,.1)
    hover:SetAllPoints(close)
    close:SetScript("OnClick",function() f:Hide() end)
    return f
end
local function Button(parent, title, w, h, action)
    local b = CreateFrame("Button",nil,parent)
    b:SetSize(w or 98,h or 23)
    local bg=EllesmereUI.SolidTex(b,"BACKGROUND",.08,.08,.08,.92)
    bg:SetAllPoints()
    b._bg=bg
    b._border=EllesmereUI.MakeBorder(b,.2,.2,.2,1,EllesmereUI.PP)
    local hover = b:CreateTexture(nil,"HIGHLIGHT")
    hover:SetColorTexture(1,1,1,.1)
    hover:SetAllPoints(b)
    local l = Text(b,11,title)
    l:SetPoint("CENTER",0,0)
    l:SetWidth((w or 98)-8)
    l:SetJustifyH("CENTER")
    b._lbl = l
    if action then b:SetScript("OnClick",action) end
    return b
end
-- Same accent source as the EUI toggle/checkbox widgets. Use a colored state
-- rather than font-dependent Unicode symbols (not all EUI fonts contain them).
local function SetChoiceButtonState(button, enabled, redWhenOff, prominent)
    if not button then return end
    local color
    if enabled then
        color=EllesmereUI.ELLESMERE_GREEN or {r=.05,g=.82,b=.62}
    elseif redWhenOff then
        color={r=.82,g=.22,b=.24}
    end
    if color then
        button._bg:SetColorTexture(color.r,color.g,color.b,prominent and .68 or .40)
        button._border:SetColor(color.r,color.g,color.b,.9)
    else
        button._bg:SetColorTexture(.08,.08,.08,.92)
        button._border:SetColor(.2,.2,.2,1)
    end
    button._lbl:SetTextColor(1,1,1)
end
-- EUI's signature blue is also used by the Nameplates EUI Glow default;
-- keep Preview Apply visually distinct from destructive/active-state controls.
local function ColorPreviewButton(button)
    if not button then return end
    local r,g,b=.4117,.6667,1.0
    button._bg:SetColorTexture(r,g,b,.32)
    button._border:SetColor(r,g,b,.95)
    button._lbl:SetTextColor(1,1,1)
end
-- One compact, EUI-styled context dropdown serves the main editor, unlisted
-- roster, and the independent Preview. Right-click never edits a seat until
-- an explicit menu action is selected. Clicking outside dismisses the menu.
local function ShowSeatMenu(anchor, choices)
    if not choices or #choices==0 then return end
    if not seatMenuOverlay then
        seatMenuOverlay=CreateFrame("Button",nil,UIParent)
        seatMenuOverlay:SetAllPoints(UIParent)
        seatMenuOverlay:SetFrameStrata("FULLSCREEN_DIALOG")
        seatMenuOverlay:EnableMouse(true)
        seatMenuOverlay:RegisterForClicks("LeftButtonUp","RightButtonUp")
        seatMenuOverlay:SetScript("OnClick",function(self) self:Hide() end)
        seatMenuFrame=CreateFrame("Frame",nil,seatMenuOverlay)
        seatMenuFrame._items={}
        seatMenuFrame:SetFrameLevel(seatMenuOverlay:GetFrameLevel()+2)
        EllesmereUI.SolidTex(seatMenuFrame,"BACKGROUND",.035,.045,.05,.98):SetAllPoints()
        EllesmereUI.MakeBorder(seatMenuFrame,.25,.32,.32,1,EllesmereUI.PP)
        seatMenuOverlay:Hide()
    end
    -- Reuse buttons rather than allocating new frames/fonts on each click.
    -- Each invocation replaces the callback through a fresh _choice binding.
    local width,height=236,8+#choices*25
    seatMenuFrame:SetSize(width,height)
    for i,choice in ipairs(choices) do
        local row=seatMenuFrame._items[i]
        if not row then
            row=Button(seatMenuFrame,"",width-8,23)
            row:SetPoint("TOPLEFT",4,-4-(i-1)*25)
            row:SetScript("OnClick",function(self)
                local selected=self._choice
                seatMenuOverlay:Hide()
                if selected and selected.action then selected.action() end
            end)
            row:SetScript("OnEnter",function(self)
                local choice=self._choice
                if choice and (choice.label=="Remove Player from Slot" or
                    choice.label=="Remove Player / Clear Slot") then
                    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                    GameTooltip:AddLine(L("Remove Player"),1,1,1)
                    GameTooltip:AddLine(L("Removes the character from the planned composition only; never kicks them from the raid."),.8,.85,.85,true)
                    GameTooltip:AddLine(L("The character remains available for reassignment; the game may swap their subgroup when Apply Groups runs."),.75,.75,.75,true)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave",function() GameTooltip:Hide() end)
            seatMenuFrame._items[i]=row
        end
        row._choice=choice
        row._lbl:SetText(L(choice.label))
        row:Show()
    end
    for i=#choices+1,#seatMenuFrame._items do
        seatMenuFrame._items[i]._choice=nil
        seatMenuFrame._items[i]:Hide()
    end
    seatMenuFrame:ClearAllPoints()
    local x,y
    if GetCursorPosition and UIParent.GetEffectiveScale then
        local scale=UIParent:GetEffectiveScale()
        if scale and scale>0 then
            local mx,my=GetCursorPosition()
            local w=UIParent:GetWidth()
            local h=UIParent:GetHeight()
            if type(mx)=="number" and type(my)=="number" and
               type(w)=="number" and type(h)=="number" then
                x=math.max(8,math.min(w-width-8,mx/scale))
                y=math.max(height+8,math.min(h-8,my/scale))
            end
        end
    end
    if x then seatMenuFrame:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",x,y)
    else seatMenuFrame:SetPoint("TOPLEFT",anchor,"BOTTOMLEFT",0,-3) end
    seatMenuOverlay:Show()
    ApplyFonts()
end

local function Input(parent, w, h, multiline)
    local bg = CreateFrame("Frame",nil,parent)
    bg:SetSize(w,h)
    EllesmereUI.SolidTex(bg,"BACKGROUND",.08,.08,.08,1):SetAllPoints()
    EllesmereUI.MakeBorder(bg,.2,.2,.2,1,EllesmereUI.PP)
    local e = CreateFrame("EditBox",nil,bg)
    e:SetPoint("TOPLEFT",5,-4)
    e:SetPoint("BOTTOMRIGHT",-5,4)
    e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    TrackFont(e, 11)
    e:SetTextInsets(1,1,1,1)
    e:SetMultiLine(multiline or false)
    e:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    return bg,e
end
-- Guild completion uses the full cached guild roster, including offline
-- members. Tab cycles matches in name order; Enter fills the field first,
-- then a second Enter performs the normal OK action.
function RGStyle.GuildCharacterCandidates(value)
    local matches={}
    value=SafeText(value)
    if not value or not IsInGuild() or not GetNumGuildMembers or
        not GetGuildRosterInfo then return matches end
    value=Trim(value)
    if value=="" or value:upper()=="GUEST" or value:upper()=="BUYER" then
        return matches
    end
    local needle=RGStyle.UTF8Casefold(value)
    local seen={}
    for i=1,(GetNumGuildMembers() or 0) do
        -- GetGuildRosterInfo includes offline characters; do not filter online.
        local name=SafeText((GetGuildRosterInfo(i)))
        -- Use the same realm spelling resolver as manual entries, so guild
        -- results carry a normalized, ready-to-save Character-Realm.
        local full=name and RGStyle.CorrectEnteredRealm(FullName(name))
        local key=full and RGStyle.UTF8Casefold(full)
        if key and key:sub(1,#needle)==needle and not seen[key] then
            seen[key]=true
            matches[#matches+1]=full
        end
    end
    table.sort(matches,function(a,b)
        local aa,bb=RGStyle.UTF8Casefold(a),RGStyle.UTF8Casefold(b)
        return aa==bb and a<b or aa<bb
    end)
    return matches
end
-- Read the current Nicknames database, not the guild roster, for the status
-- indicator. Legacy saved keys keep their original UTF-8 spelling, so use a
-- casefolded fallback only for display when their capitalization differs.
function RGStyle.GuildCharacterNickname(name)
    if not data or type(data.nicknames)~="table" or
        type(data.nicknameGroups)~="table" then return nil end
    local key=Canonical(name)
    if not key then return nil end
    local record=data.nicknames[key]
    local group=record and data.nicknameGroups[record.groupId]
    if group and SafeText(group.nickname) then return group.nickname end
    local folded=RGStyle.UTF8Casefold(key)
    for storedKey,entry in pairs(data.nicknames) do
        if type(storedKey)=="string" and type(entry)=="table" and
            RGStyle.UTF8Casefold(storedKey)==folded then
            local linked=data.nicknameGroups[entry.groupId]
            if linked and SafeText(linked.nickname) then return linked.nickname end
        end
    end
end
function RGStyle.DrawGuildCompletion()
    local popup=promptWindow
    if not popup or not popup._hint then return end
    local matches=popup._guildMatches or {}
    local count=#matches
    local active=popup._guildIndex or 0
    local visible=math.min(count,#popup._guildRows)
    local offset=math.max(0,math.min(count-visible,active-visible))
    -- Scroll the visible group only when selection moves outside the window.
    if active<=((popup._guildOffset or 0)) or active>(popup._guildOffset or 0)+visible then
        popup._guildOffset=offset
    end
    local scroll=popup._guildOffset or 0
    scroll=math.max(0,math.min(count-visible,scroll))
    popup._guildOffset=scroll
    for i,row in ipairs(popup._guildRows) do
        local index=scroll+i
        row._guildIndex=index
        local name=matches[index]
        local showing=name~=nil and popup._guildAutocomplete and not popup._guildCommitted
        row:SetShown(showing)
        row._guildNickname=name and RGStyle.GuildCharacterNickname(name) or nil
        row._guildRegisteredCheck:SetShown(showing and row._guildNickname~=nil)
        if name then
            row._lbl:SetText(name)
            SetChoiceButtonState(row,index==active,false)
        end
    end
    if not popup._guildAutocomplete then
        popup._hint:Hide()
        popup:SetHeight(122)
    elseif popup._guildCommitted then
        popup._hint:SetText(L("Press Enter again to confirm, or edit the name."))
        popup._hint:SetTextColor(.50,.85,.73,1)
        popup._hint:Show()
        popup:SetHeight(151)
    elseif count>0 then
        popup._hint:SetText(LF("%d guild matches | Tab: next | Enter: use",count))
        popup._hint:SetTextColor(.75,.78,.78,1)
        popup._hint:Show()
        popup:SetHeight(151+visible*23)
    else
        popup._hint:Hide()
        popup:SetHeight(151)
    end
    RGStyle.ApplyPanelScale(popup)
end
function RGStyle.UpdateGuildCompletion(edit,refreshOnly)
    if not promptWindow or not edit or not promptWindow._guildAutocomplete then
        if promptWindow then
            promptWindow._guildMatches={}
            promptWindow._guildIndex=0
            promptWindow._guildOffset=0
            promptWindow._guildCommitted=false
            RGStyle.DrawGuildCompletion()
        end
        return
    end
    if promptWindow._guildSettingText then return end
    if not refreshOnly then promptWindow._guildCommitted=false end
    if promptWindow._guildCommitted then return end
    local old=promptWindow._guildMatches or {}
    local previouslySelected=old[promptWindow._guildIndex or 0]
    local matches=RGStyle.GuildCharacterCandidates(edit:GetText())
    promptWindow._guildMatches=matches
    promptWindow._guildIndex=0
    if refreshOnly and previouslySelected then
        for i,name in ipairs(matches) do
            if name==previouslySelected then promptWindow._guildIndex=i;break end
        end
    else
        promptWindow._guildOffset=0
    end
    RGStyle.DrawGuildCompletion()
end
function RGStyle.ChooseGuildCompletion(index)
    local popup=promptWindow
    if not popup or not popup._guildAutocomplete or popup._guildCommitted then return false end
    local selected=popup._guildMatches and popup._guildMatches[index]
    if not selected then return false end
    popup._guildSettingText=true
    popup._edit:SetText(selected)
    popup._edit:SetCursorPosition(popup._edit:GetNumLetters())
    popup._guildSettingText=false
    popup._guildCommitted=true
    RGStyle.DrawGuildCompletion()
    popup._edit:SetFocus()
    return true
end
local function InputPrompt(title, initial, onAccept, characterAutocomplete)
    if not promptWindow then
        promptWindow = Panel("EllesmereUIRaidGroupInput",410,122)
        promptWindow:SetFrameStrata("FULLSCREEN_DIALOG")
        promptWindow._title = Text(promptWindow,13)
        promptWindow._title:SetPoint("TOPLEFT",12,-12)
        local _, edit = Input(promptWindow,376,26,false)
        edit:GetParent():SetPoint("TOPLEFT",12,-45)
        promptWindow._edit = edit
        local hint=Text(promptWindow,10)
        hint:SetPoint("TOPLEFT",16,-79)
        hint:SetWidth(379)
        hint:SetJustifyH("LEFT")
        hint:Hide()
        promptWindow._hint=hint
        promptWindow._guildRows={}
        for i=1,6 do
            local row=Button(promptWindow,"",376,21,function(self)
                RGStyle.ChooseGuildCompletion(self._guildIndex)
            end)
            row:SetPoint("TOPLEFT",12,-99-(i-1)*23)
            row._lbl:SetJustifyH("LEFT")
            row._lbl:ClearAllPoints()
            row._lbl:SetPoint("LEFT",row,"LEFT",8,0)
            row._lbl:SetWidth(336) -- leave room for the registered check on the right
            local check=row:CreateTexture(nil,"ARTWORK")
            check:SetAtlas("UI-LFG-ReadyMark-Raid") -- same ready check as Raid Check
            check:SetSize(18,18)
            check:SetAlpha(.9)
            check:SetPoint("RIGHT",row,"RIGHT",-8,0)
            check:Hide()
            row._guildRegisteredCheck=check
            row:SetScript("OnEnter",function(self)
                if not self._guildNickname then return end
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                GameTooltip:AddLine(LF("Already registered in Nicknames as '%s'.",self._guildNickname),
                    .50,.85,.73)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave",function() GameTooltip:Hide() end)
            row:Hide()
            promptWindow._guildRows[i]=row
        end
        edit:SetScript("OnTextChanged",function(self)
            RGStyle.UpdateGuildCompletion(self)
        end)
        edit:SetScript("OnTabPressed",function()
            local popup=promptWindow
            if not popup._guildAutocomplete or popup._guildCommitted then return end
            local count=#(popup._guildMatches or {})
            if count==0 then return end
            popup._guildIndex=(popup._guildIndex or 0)%count+1
            RGStyle.DrawGuildCompletion()
        end)
        local function AcceptPrompt()
            local cb=promptWindow._accept
            local v=edit:GetText()
            promptWindow:Hide()
            if cb then cb(v) end
        end
        Button(promptWindow,"Cancel",86,23,function() promptWindow:Hide() end):SetPoint("BOTTOMRIGHT",-108,11)
        Button(promptWindow,"OK",86,23,AcceptPrompt):SetPoint("BOTTOMRIGHT",-12,11)
        edit:SetScript("OnEnterPressed",function()
            local popup=promptWindow
            if popup._guildAutocomplete and not popup._guildCommitted and
                RGStyle.ChooseGuildCompletion((popup._guildIndex or 0)>0 and popup._guildIndex or 1) then return end
            AcceptPrompt()
        end)
    end
    promptWindow._title:SetText(L(title))
    promptWindow._accept = onAccept
    promptWindow._guildAutocomplete=characterAutocomplete and true or false
    promptWindow._guildCommitted=false
    promptWindow._guildIndex=0
    promptWindow._guildOffset=0
    promptWindow._guildMatches={}
    promptWindow._guildSettingText=true
    promptWindow._edit:SetText(initial or "")
    promptWindow._guildSettingText=false
    promptWindow:Show()
    ApplyFonts()
    promptWindow._edit:SetFocus()
    promptWindow._edit:HighlightText()
    RGStyle.UpdateGuildCompletion(promptWindow._edit)
    if characterAutocomplete and IsInGuild() then
        -- Roster updates are asynchronous and include offline guild members.
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        elseif GuildRoster then GuildRoster() end
    end
end
local function Confirm(title, onConfirm)
    StaticPopupDialogs.EUI_RAIDGROUP_CONFIRM = {
        text = "%s", button1 = YES, button2 = NO, timeout = 0,
        whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnAccept = function(_, cb) if cb then cb() end end,
    }
    StaticPopup_Show("EUI_RAIDGROUP_CONFIRM", L(title), nil, onConfirm)
end
-- Reset only Raid Groups presentation. The live profile is authoritative;
-- removing these optional overrides restores the same defaults used by every
-- scale/font getter, without touching setup data, guest tags or saved positions.
function ns.RaidGroupsRequestAppearanceReset()
    Confirm("Reset Raid Groups window scales and player name sizes to their defaults? Saved setups, nicknames and window positions will be kept.", function()
        local p=P()
        if not p then return end
        p.scale=1
        p.windowScales=nil
        p.playerFontSizes=nil
        p.windowScalingEnabled=true
        p.playerNamesFontEnabled=true
        RGStyle.ApplyAllPanelScales()
        ApplyFonts()
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
    end)
end
local function SetStatus(message)
    if statusLabel then statusLabel:SetText(L(message or "")) end
end

-------------------------------------------------------------------------------
-- Import and export. Text format EUIRG1 is lossless (40 seats + GUEST markers).
-- Use printable delimiters in the editor; legacy tab-prefixed records still import.
-- A note can contain arbitrary unrelated lines: only invitelist:...; matters.
-------------------------------------------------------------------------------
-- Only metadata that actually names the encounter becomes the setup title.
-- Notes normally begin with EncounterID:...;Name:Boss and end in invitelist:.
-- Importing a bare list/native layout without a heading uses a safe fallback.
function ns.RaidGroupsImportedSetupName(source)
    local first=Trim((source or ""):match("^%s*([^\r\n]+)") or "")
    local name
    if first:find("[Ee][Nn][Cc][Oo][Uu][Nn][Tt][Ee][Rr][Ii][Dd]%s*:") then
        name=first:match("[Nn][Aa][Mm][Ee]%s*:%s*([^;]+)")
    elseif first:match("^[Nn][Aa][Mm][Ee]%s*:") then
        name=first:match("^[Nn][Aa][Mm][Ee]%s*:%s*(.+)$")
    elseif first~="" and #first<=80 and
        not first:match("^[Ee][Uu][Ii][Rr][Gg][12]") and
        not first:match("^[Ii][Nn][Vv][Ii][Tt][Ee][Ll][Ii][Ss][Tt]%s*:") and
        not first:match("^[Tt][Ii][Mm][Ee]%s*:") and
        not first:find("[\t,;]") then
        -- Plain title line preceding an embedded invitation list.
        if source:lower():find("invitelist%s*:") then name=first end
    end
    name=Trim(name or "")
    if name=="" then return "Imported Setup" end
    -- Recognize the common unpunctuated alias without changing other names.
    if name:lower():gsub("[%s%p]","")=="nekzali" then return "Nek'zali" end
    return name
end
local function ImportText(source, format)
    source = SafeText(source)
    if not source then return nil,"Invalid or protected input." end
    local compact = source:match("^%s*EUIRG2:(%S+)")
    if compact then
        local codec = LibStub and LibStub("LibDeflate", true)
        if not codec then return nil,"Compact codec is unavailable." end
        local ok, decoded = pcall(function()
            local bytes=codec:DecodeForPrint(compact)
            return bytes and codec:DecompressDeflate(bytes)
        end)
        if not ok or not decoded then return nil,"Invalid compact group setup." end
        return ImportText(decoded,"native")
    end
    local lower = source:lower()
    local startPos, afterPrefix = lower:find("invitelist%s*:")
    local values, kind = {}, format
    local normalGuestSeats, pinnedGuestSeats = {}, {}
    if not startPos and lower:match("^%s*encounterid%s*:") then
        return nil,"This encounter note has no invitelist: field."
    end
    if startPos then
        kind = "invitelist"
        local semi = source:find(";",afterPrefix+1,true)
        local newline = source:find("\n",afterPrefix+1,true)
        local finish = #source+1
        if semi and semi < finish then finish = semi end
        if newline and newline < finish then finish = newline end
        local raw = source:sub(afterPrefix+1,finish-1)
        if raw == "" then return nil,"The invitelist is empty." end
        local offset, count = 1, 0
        while true do
            local comma = raw:find(",", offset, true)
            count = count + 1
            if count > SLOT_COUNT then return nil,"The invitelist has more than 40 seats." end
            local v = Trim(raw:sub(offset, comma and comma-1 or #raw))
            values[count] = v ~= "" and v or false
            if not comma then break end
            offset = comma + 1
        end
    elseif source:match("^%s*EUIRG1%s*\n") or kind == "native" then
        kind = "native"
        local first = true
        local count = 0
        local native = source:gsub("\r\n", "\n"):gsub("\n+$", "")
        for line in (native.."\n"):gmatch("(.-)\n") do
            if first then
                first = false
                if Trim(line) ~= "EUIRG1" then return nil,"Invalid EUIRG1 header." end
            else
                count = count + 1
                if count > SLOT_COUNT then return nil,"More than 40 seats." end
                if line == "G" or line == "B" then values[count] = "GUEST"
                elseif line == "S" then values[count]=RGStyle.SETUP_GUEST
                elseif line == "E" then values[count] = "EMPTY_PINNED"
                elseif line:sub(1,2)=="N|" or line:sub(1,2)=="N\t" then
                    values[count]=Trim(line:sub(3)); normalGuestSeats[count]=true
                elseif line:sub(1,2)=="F|" or line:sub(1,2)=="F\t" then
                    values[count]=Trim(line:sub(3)); pinnedGuestSeats[count]=true
                elseif line == "-" or line == "" then values[count] = false
                elseif line:sub(1,2) == "P|" or line:sub(1,2) == "P\t" then values[count] = Trim(line:sub(3))
                else return nil,LF("Invalid record at seat %d",count) end
            end
        end
        if count ~= SLOT_COUNT then return nil,"Expected 40 seats in EUIRG1 format." end
    else
        -- Plain text: two-column pairs (group 1 / 2, 3 / 4, ...), eight
        -- columns (one seat per row), or 40 vertical lines. Tabs are preferred
        -- to whitespace because cross-realm names can contain punctuation.
        local lines = {}
        local normalized=source:gsub("\r\n","\n"):gsub("\n+$", "")
        for line in (normalized.."\n"):gmatch("(.-)\n") do
            lines[#lines+1]=line
        end
        if #lines == 0 or (lines[1] == "" and #lines == 1) then
            return nil,"The import text is empty."
        end
        if kind == "auto" or not kind then
            local firstLine = lines[1]
            local count = 0
            for _ in firstLine:gmatch("[^\t ]+") do count = count + 1 end
            local tabs=select(2,firstLine:gsub("\t",""))
            local pipes=select(2,firstLine:gsub("|",""))
            if tabs>=4 or pipes>=4 or count>=5 then kind="eight"
            elseif tabs==1 or pipes==1 or count==2 then kind="pair"
            else kind="vertical" end
        end
        local function Cells(line)
            -- The editable export window cannot render literal tabs cleanly.
            -- Accept both legacy TSV and visible pipe-delimited columns,
            -- preserving empty cells and the original group/slot indexing.
            local delimiter=line:find("|",1,true) and "|" or
                (line:find("\t",1,true) and "\t")
            if not delimiter then
                local t={}
                for field in line:gmatch("%S+") do
                    t[#t+1]=field=="-" and "" or field
                end
                return t
            end
            local t,offset={},1
            while true do
                local at=line:find(delimiter,offset,true)
                local field=Trim(line:sub(offset,at and at-1 or #line))
                t[#t+1]=field=="-" and "" or field
                if not at then break end
                offset=at+1
            end
            return t
        end
        if kind == "pair" then
            for idx,line in ipairs(lines) do
                local block=math.floor((idx-1)/5)
                local seat=(idx-1)%5+1
                if block>=4 then break end
                local cells=Cells(line)
                values[block*10+seat]=cells[1] and cells[1]~="" and cells[1] or false
                values[block*10+5+seat]=cells[2] and cells[2]~="" and cells[2] or false
            end
        elseif kind == "eight" then
            for seat,line in ipairs(lines) do
                if seat>5 then break end
                for g,field in ipairs(Cells(line)) do
                    if g>8 then break end
                    values[(g-1)*5+seat]=field~="" and field or false
                end
            end
        elseif kind == "vertical" then
            for i,line in ipairs(lines) do
                if i>SLOT_COUNT then break end
                values[i]=Trim(line)
            end
        else return nil,"Unknown import format." end
    end
    local result, seen, players, guests, emptyPins = {}, {}, 0, 0, {}
    local populatedGroups={}
    for i=1,SLOT_COUNT do
        local value=values[i]
        if value and value~=false and Trim(value)~="" then
            populatedGroups[math.floor((i-1)/GROUP_SIZE)+1]=true
        end
    end
    for i=1,SLOT_COUNT do
        -- Only partially populated groups receive generic Guest reservations.
        -- Completely empty groups remain available to unplanned raid members.
        local group=math.floor((i-1)/GROUP_SIZE)+1
        if populatedGroups[group] and (not values[i] or values[i]=="") and
            Enabled("guestImportSeats") then
            values[i]=RGStyle.SETUP_GUEST
        end
    end
    for i=1,SLOT_COUNT do
        local v = values[i]
        if v == "EMPTY_PINNED" then emptyPins[i]=true
        elseif v == "GUEST" or v == "BUYER" or v==RGStyle.SETUP_GUEST then
            result[i] = v==RGStyle.SETUP_GUEST and v or "GUEST"; guests = guests+1
        elseif v and v ~= false and Trim(v) ~= "" then
            v = Trim(v)
            local key = Canonical(v)
            if not key then return nil,LF("Invalid character name at seat %d",i) end
            if seen[key] then return nil,LF("Duplicate character: %s",v) end
            seen[key] = true
            result[i] = v
            players = players+1
        end
    end
    for i=1,SLOT_COUNT do
        if (normalGuestSeats[i] or pinnedGuestSeats[i]) and not result[i] then
            return nil,LF("Missing Guest character at seat %d",i)
        end
    end
    return result, nil, players, guests, kind, emptyPins,
        normalGuestSeats, pinnedGuestSeats
end
local function ExportText(mode)
    mode = mode or "native"
    if mode == "compact" then
        local codec = LibStub and LibStub("LibDeflate", true)
        if not codec then return "Compact codec unavailable" end
        local compressed = codec:CompressDeflate(ExportText("native"), {level=5})
        return "EUIRG2:"..codec:EncodeForPrint(compressed)
    end
    local lines = {}
    if mode == "native" then
        lines[1] = "EUIRG1"
        for i=1,SLOT_COUNT do
            local v = draft[i]
            lines[#lines+1] = RGStyle.emptyPinnedDraft[i] and "E" or
                (v == "GUEST" and "G" or (v==RGStyle.SETUP_GUEST and "S" or (v and ((draftPinned[i] and "F|" or
                    (draftGuest[i] and "N|" or "P|"))..v) or "-")))
        end
    elseif mode == "invitelist" then
        local last = 0
        for i=1,SLOT_COUNT do if draft[i] then last=i end end
        local vals = {}
        for i=1,last do
            vals[i] = (draft[i]=="GUEST" or draft[i]==RGStyle.SETUP_GUEST) and "" or draft[i] or ""
        end
        return "invitelist:"..table.concat(vals,",")..";"
    elseif mode == "vertical" then
        for i=1,SLOT_COUNT do lines[#lines+1] = draft[i]==RGStyle.SETUP_GUEST and "" or draft[i] or "" end
    elseif mode == "pair" then
        -- Visible delimiters instead of tabs: the game's chat font renders
        -- literal tab characters as square missing-glyph symbols.
        local lastRow=0
        for pair=0,3 do
            for n=1,5 do
                local a=draft[pair*10+n]
                local b=draft[pair*10+5+n]
                if a or b then lastRow=pair*5+n end
            end
        end
        for index=1,lastRow do
            local pair=math.floor((index-1)/5)
            local n=(index-1)%5+1
            local a=draft[pair*10+n]
            local b=draft[pair*10+5+n]
            lines[#lines+1]=(a and a~=RGStyle.SETUP_GUEST and a or "-")..
                " | "..(b and b~=RGStyle.SETUP_GUEST and b or "-")
        end
    elseif mode == "eight" then
        local lastRow=0
        for n=1,5 do
            for g=1,8 do
                if draft[(g-1)*5+n] then lastRow=n end
            end
        end
        for n=1,lastRow do
            local fields={}
            for g=1,8 do
                local v=draft[(g-1)*5+n]
                fields[g]=v and v~=RGStyle.SETUP_GUEST and v or "-"
            end
            lines[#lines+1]=table.concat(fields," | ")
        end
    end
    return table.concat(lines,"\n")
end
-------------------------------------------------------------------------------
-- Account-wide Raid Groups backup. Versioned, escaped records; strictly data,
-- NEVER loadstring/execute imported text. Includes linked nicknames, tombstones,
-- Guest overrides, setup order, and saved split preferences.
-------------------------------------------------------------------------------
local BACKUP_HEADER="EUIRGBACKUP1"
local function EscapeField(value)
    return (tostring(value or ""):gsub("[^%w%-_%.]",function(byte)
        return string.format("%%%02X",byte:byte())
    end))
end
local function UnescapeField(value)
    if value:gsub("%%[%x][%x]", ""):find("%",1,true) then return nil end
    return (value:gsub("%%(%x%x)",function(pair)
        return string.char(tonumber(pair,16))
    end))
end
local function ExportBackup(plain)
    local lines={BACKUP_HEADER}
    local function Record(...)
        local values={...}
        for i=1,#values do values[i]=EscapeField(values[i]) end
        lines[#lines+1]=table.concat(values,"\t")
    end
    Record("META",data.nextNicknameGroupID,data.exactPositions and 1 or 0,
        data.keepChanges and 1 or 0)
    local ids={}
    for id in pairs(data.nicknameGroups) do ids[#ids+1]=id end
    table.sort(ids)
    for _,id in ipairs(ids) do
        local group=data.nicknameGroups[id]
        if type(group)=="table" and SafeText(group.nickname) then
            Record("GROUP",id,group.nickname,group.locked and 1 or 0,
                group.source or "Saved",group.updated or 0)
        end
    end
    local keys={}
    for key in pairs(data.nicknames) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do
        local rec=data.nicknames[key]
        if type(rec)=="table" and SafeText(rec.name) and SafeText(rec.groupId) then
            -- Optional class metadata keeps icons available after Backup/Restore.
            -- Legacy NICK records without the final column are still accepted.
            Record("NICK",key,rec.name,rec.groupId,rec.manual and 1 or 0,rec.class or "")
        end
    end
    local function ExportMap(kind,map)
        local sorted={}
        for key in pairs(map or {}) do sorted[#sorted+1]=key end
        table.sort(sorted)
        for _,key in ipairs(sorted) do
            local value=map[key]
            if kind=="SUP" and value then Record(kind,key)
            elseif kind~="SUP" and (type(value)=="string" or type(value)=="boolean") then
                Record(kind,key,type(value)=="boolean" and (value and "true" or "false") or value)
            end
        end
    end
    ExportMap("SUP",data.suppressed)
    ExportMap("SHARE",data.nicknameSharing)
    ExportMap("GUEST",data.guests)
    for i,setup in ipairs(data.setups) do
        local fields={"SET",i,setup.name or "",setup.updated or 0}
        for seat=1,SLOT_COUNT do
            local value=setup.slots and setup.slots[seat]
            fields[#fields+1]=value=="GUEST" and "G" or (value==RGStyle.SETUP_GUEST and "S" or value or "")
        end
        Record(unpack(fields))
        local modes=setup.guestModes or {}
        local skeys={}
        for key in pairs(modes) do skeys[#skeys+1]=key end
        table.sort(skeys)
        for _,key in ipairs(skeys) do
            local v=modes[key]
            if type(v)=="string" or type(v)=="boolean" then
                Record("SETGUEST",i,key,type(v)=="boolean" and (v and "true" or "false") or v)
            end
        end
        for seat=1,SLOT_COUNT do
            if setup.emptyPinnedSeats and setup.emptyPinnedSeats[seat] then Record("SETEMPTY",i,seat) end
        end
        Record("SETPINS",i) -- explicit empty map distinguishes new from legacy backups
        for seat=1,SLOT_COUNT do
            if setup.pinnedSeats and setup.pinnedSeats[seat] then Record("SETPIN",i,seat) end
            if setup.normalGuestSeats and setup.normalGuestSeats[seat] then Record("SETNORMAL",i,seat) end
        end
    end
    local split=data.split or {}
    local fields={"SPLIT",split.parts or 2,split.alternate and 1 or 0}
    for g=1,NUM_GROUPS do fields[#fields+1]=split.groups and split.groups[g] and 1 or 0 end
    Record(unpack(fields))
    local text=table.concat(lines,"\n")
    local codec=LibStub and LibStub("LibDeflate",true)
    if plain or not codec then return text end
    local zipped=codec:CompressDeflate(text,{level=6})
    return "EUIRGBACKUP2:"..codec:EncodeForPrint(zipped)
end
local function ParseBackup(source)
    source=SafeText(source)
    if not source or #source>4000000 then return nil,"Backup is invalid or exceeds 4 MB." end
    source=Trim(source)
    if source:sub(1,13)=="EUIRGBACKUP2:" then
        local codec=LibStub and LibStub("LibDeflate",true)
        if not codec then return nil,"Backup codec is unavailable." end
        local encoded=source:sub(14)
        local raw=codec:DecodeForPrint(encoded)
        local expanded=raw and codec:DecompressDeflate(raw)
        if not expanded or #expanded>4000000 then return nil,"Compressed backup is invalid or too large." end
        source=expanded
    end
    local result={setups={},nicknames={},nicknameGroups={},suppressed={},
        nicknameSharing={},guests={},split={groups={}},nextNicknameGroupID=0}
    local head=true
    local seenSetup={}
    local seenMeta, seenSplit = false, false
    local lines=0
    for line in (source.."\n"):gmatch("(.-)\n") do
        line=line:gsub("\r$","")
        if head then
            if line~=BACKUP_HEADER then return nil,"Unrecognized backup format." end
            head=false
        elseif line~="" then
            lines=lines+1
            if lines>20000 then return nil,"Too many backup records." end
            local fields={}
            for raw in (line.."\t"):gmatch("(.-)\t") do
                local value=UnescapeField(raw)
                if not value then return nil,"Invalid backup field encoding." end
                fields[#fields+1]=value
            end
            local kind=fields[1]
            if kind=="META" then
                if seenMeta or #fields~=4 or not tonumber(fields[2]) then
                    return nil,"Invalid or duplicate backup metadata." end
                seenMeta=true
                result.nextNicknameGroupID=tonumber(fields[2])
                result.exactPositions=fields[3]=="1"
                result.keepChanges=fields[4]=="1"
            elseif kind=="GROUP" then
                if #fields~=6 or fields[2]=="" or fields[3]=="" or result.nicknameGroups[fields[2]] then
                    return nil,"Invalid or duplicate nickname group." end
                result.nicknameGroups[fields[2]]={nickname=fields[3],locked=fields[4]=="1",
                    source=fields[5],updated=tonumber(fields[6]) or 0}
            elseif kind=="NICK" then
                if (#fields~=5 and #fields~=6) or not Canonical(fields[3]) or result.nicknames[fields[2]] then
                    return nil,"Invalid or duplicate character association." end
                if fields[2]~=Canonical(fields[3]) then return nil,"Character key mismatch." end
                local class=fields[6]
                if class and class~="" and (#class>20 or not class:match("^[A-Z]+$")) then
                    return nil,"Invalid character class metadata." end
                result.nicknames[fields[2]]={name=FullName(fields[3]),groupId=fields[4],
                    manual=fields[5]=="1",class=class and class~="" and class or nil}
            elseif kind=="SUP" then
                if #fields~=2 or fields[2]=="" then return nil,"Invalid suppression record." end
                result.suppressed[fields[2]]=true
            elseif kind=="SHARE" or kind=="GUEST" then
                if #fields~=3 or fields[2]=="" then return nil,"Invalid player preference." end
                local dest=kind=="SHARE" and result.nicknameSharing or result.guests
                local value=fields[3]
                dest[fields[2]]=value=="true" and true or (value=="false" and false or value)
            elseif kind=="SET" then
                if #fields~=44 then return nil,"Invalid setup record." end
                local index=tonumber(fields[2])
                if not index or index<1 or index>200 or seenSetup[index] or fields[3]=="" then
                    return nil,"Invalid or duplicate setup index." end
                seenSetup[index]=true
                local entry={name=fields[3],updated=tonumber(fields[4]) or 0,slots={},guestModes={}}
                local used={}
                for i=1,SLOT_COUNT do
                    local value=fields[i+4]
                    if value=="G" then entry.slots[i]="GUEST"
                    elseif value=="S" then entry.slots[i]=RGStyle.SETUP_GUEST
                    elseif value~="" then
                        local key=Canonical(value)
                        if not key or used[key] then return nil,"Invalid or duplicate setup character." end
                        used[key]=true
                        entry.slots[i]=FullName(value)
                    end
                end
                result.setups[index]=entry
            elseif kind=="SETGUEST" then
                if #fields~=4 or not tonumber(fields[2]) or fields[3]=="" then
                    return nil,"Invalid setup Guest override." end
                result._setupModes=result._setupModes or {}
                result._setupModes[#result._setupModes+1]={tonumber(fields[2]),fields[3],fields[4]}
            elseif kind=="SETEMPTY" then
                if #fields~=3 or not tonumber(fields[2]) or not tonumber(fields[3]) then
                    return nil,"Invalid Pinned Empty seat." end
                result._emptyRecords=result._emptyRecords or {}
                result._emptyRecords[#result._emptyRecords+1]={tonumber(fields[2]),tonumber(fields[3])}
            elseif kind=="SETPINS" then
                if #fields~=2 or not tonumber(fields[2]) then return nil,"Invalid pinned Guest metadata." end
                result._pinSets=result._pinSets or {}
                local index=tonumber(fields[2])
                if result._pinSets[index] then return nil,"Duplicate pinned Guest metadata." end
                result._pinSets[index]={}
            elseif kind=="SETPIN" then
                if #fields~=3 or not tonumber(fields[2]) or not tonumber(fields[3]) then
                    return nil,"Invalid pinned Guest seat." end
                result._pinRecords=result._pinRecords or {}
                result._pinRecords[#result._pinRecords+1]={tonumber(fields[2]),tonumber(fields[3])}
            elseif kind=="SETNORMAL" then
                if #fields~=3 or not tonumber(fields[2]) or not tonumber(fields[3]) then
                    return nil,"Invalid normal Guest seat." end
                result._normalRecords=result._normalRecords or {}
                result._normalRecords[#result._normalRecords+1]={tonumber(fields[2]),tonumber(fields[3])}
            elseif kind=="SPLIT" then
                if seenSplit or #fields~=11 then return nil,"Invalid split raid preferences." end
                seenSplit=true
                result.split.parts=tonumber(fields[2]) or 2
                if result.split.parts<1 or result.split.parts>8 then
                    return nil,"Invalid split division count." end
                result.split.alternate=fields[3]=="1"
                for i=1,NUM_GROUPS do result.split.groups[i]=fields[i+3]=="1" end
            else
                return nil,"Unsupported backup record: "..tostring(kind)
            end
        end
    end
    if not seenMeta then return nil,"Backup metadata is missing." end
    local highest=0
    for index in pairs(seenSetup) do highest=math.max(highest,index) end
    for i=1,highest do
        if not seenSetup[i] then return nil,"Setup indices are not consecutive." end
    end
    for key,rec in pairs(result.nicknames) do
        local group=result.nicknameGroups[rec.groupId]
        if not group then return nil,"Nickname group missing for "..key end
        rec.nickname=group.nickname
    end
    for _,record in ipairs(result._setupModes or {}) do
        local setup=result.setups[record[1]]
        if not setup then return nil,"Guest override references a missing setup." end
        local value=record[3]
        setup.guestModes[record[2]]=value=="true" and true or (value=="false" and false or value)
    end
    result._setupModes=nil
    for index,pins in pairs(result._pinSets or {}) do
        if not result.setups[index] then return nil,"Pinned metadata references a missing setup." end
        result.setups[index].pinnedSeats=pins
    end
    for _,record in ipairs(result._pinRecords or {}) do
        local setup=result.setups[record[1]]
        local seat=record[2]
        if not setup or not setup.pinnedSeats or seat<1 or seat>SLOT_COUNT or
            setup.pinnedSeats[seat] or not setup.slots[seat] or setup.slots[seat]=="GUEST" or
            setup.slots[seat]==RGStyle.SETUP_GUEST then
            return nil,"Pinned Guest references an invalid or duplicate seat." end
        setup.pinnedSeats[seat]=true
    end
    result._pinSets=nil
    result._pinRecords=nil
    for _,record in ipairs(result._normalRecords or {}) do
        local setup=result.setups[record[1]]
        local seat=record[2]
        if not setup or seat<1 or seat>SLOT_COUNT or not setup.slots[seat] or
            setup.slots[seat]=="GUEST" or setup.slots[seat]==RGStyle.SETUP_GUEST or
            (setup.pinnedSeats and setup.pinnedSeats[seat]) or
            (setup.normalGuestSeats and setup.normalGuestSeats[seat]) then
            return nil,"Normal Guest references an invalid, pinned or duplicate seat." end
        setup.normalGuestSeats=setup.normalGuestSeats or {}
        setup.normalGuestSeats[seat]=true
    end
    result._normalRecords=nil
    for _,record in ipairs(result._emptyRecords or {}) do
        local setup=result.setups[record[1]]
        local seat=record[2]
        if not setup or seat<1 or seat>SLOT_COUNT or setup.slots[seat] or
            (setup.emptyPinnedSeats and setup.emptyPinnedSeats[seat]) then
            return nil,"Pinned Empty references an invalid, occupied or duplicate seat." end
        setup.emptyPinnedSeats=setup.emptyPinnedSeats or {}
        setup.emptyPinnedSeats[seat]=true
    end
    result._emptyRecords=nil
    -- Legacy backups without explicit pin markers retain their old meaning.
    for _,setup in ipairs(result.setups) do
        if type(setup.pinnedSeats)~="table" then
            setup.pinnedSeats={}
            for i=1,SLOT_COUNT do
                local value=setup.slots[i]
                if value and value~="GUEST" and value~=RGStyle.SETUP_GUEST and setup.guestModes[Canonical(value)]=="guest" then
                    setup.pinnedSeats[i]=true
                end
            end
        end
    end
    if not result.split.parts then
        result.split={parts=2,alternate=false,groups={true,true,true,true,false,false,false,false}}
    end
    -- Avoid allocating previously-used IDs after importing a backup.
    for id in pairs(result.nicknameGroups) do
        local suffix=tonumber(id:match("^g(%d+)$"))
        if suffix then result.nextNicknameGroupID=math.max(result.nextNicknameGroupID,suffix) end
    end
    return result
end
local function ShowBackupWindow()
    if not Enabled("backupEnabled") then return end
    if not backupWindow then
        backupWindow=Panel("EllesmereUIRaidGroupBackup",690,490)
        local title=Text(backupWindow,14,"Raid Groups Backup / Restore")
        title:SetPoint("TOPLEFT",14,-13)
        local help=Text(backupWindow,10,
            "Export account-wide setups and nicknames; Restore replaces saved records after confirmation.")
        help:SetPoint("TOPLEFT",14,-37)
        help:SetWidth(660)
        local scroll=CreateFrame("ScrollFrame",nil,backupWindow,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",16,-70)
        scroll:SetPoint("BOTTOMRIGHT",-36,52)
        local edit=CreateFrame("EditBox",nil,scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        TrackFont(edit,11)
        edit:SetWidth(624)
        edit:SetHeight(1500)
        edit:SetTextInsets(5,5,5,5)
        edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        edit:SetScript("OnTextChanged",function(self)
            local measured=self.GetStringHeight and self:GetStringHeight() or 0
            self:SetHeight(math.max(1500,math.min(100000,measured+40)))
        end)
        scroll:SetScrollChild(edit)
        backupWindow._edit=edit
        Button(backupWindow,"Export",110,26,function()
            edit:SetText(ExportBackup(false));edit:HighlightText();edit:SetFocus()
        end):SetPoint("BOTTOMLEFT",14,13)
        Button(backupWindow,"Plain Text",110,26,function()
            edit:SetText(ExportBackup(true));edit:HighlightText();edit:SetFocus()
        end):SetPoint("BOTTOMLEFT",131,13)
        Button(backupWindow,"Restore",110,26,function()
            local restored,err=ParseBackup(edit:GetText())
            if not restored then Notice(LF("Cannot restore Raid Groups backup: %s",err));return end
            Confirm("Replace saved Raid Groups setups, nickname history, and Guest settings with this backup?",function()
                data.setups=restored.setups
                data.nicknames=restored.nicknames
                data.nicknameGroups=restored.nicknameGroups
                -- The restored nickname identities may reuse group IDs, so
                -- do not carry over collapse preferences from unrelated groups.
                data.nicknameCollapsed={}
                nickCollapsed=data.nicknameCollapsed
                data.suppressed=restored.suppressed
                data.nicknameSharing=restored.nicknameSharing
                data.guests=restored.guests
                data.split=restored.split
                data.nextNicknameGroupID=restored.nextNicknameGroupID
                data.exactPositions=restored.exactPositions
                data.keepChanges=restored.keepChanges
                selectedSetup=nil;draft={};draftPinned={};draftGuest={};RGStyle.emptyPinnedDraft={};removedGuestKeys={};dirty=false;undoStack={}
                RGStyle.setupLoadToggle=nil
                if previewWindow then previewWindow:Hide() end
                if applyState then StopApply("Group application cancelled: data restored.") end
                if Refresh then Refresh() end
                if RefreshSetups then RefreshSetups() end
                if RefreshNicknames then RefreshNicknames() end
                Notice("Raid Groups backup restored.","success")
            end)
        end):SetPoint("BOTTOMRIGHT",-14,13)
    end
    backupWindow._edit:SetText(ExportBackup(false))
    backupWindow:Show()
    ApplyFonts()
    backupWindow._edit:SetFocus()
    backupWindow._edit:HighlightText()
end

function ns.ImportRaidGroupsIntoSetups(source, format)
    local parsed,err,players,guests,_,emptyPins,normalGuests,pinnedGuests=ImportText(source,format)
    if not parsed then Notice(err);return false end
    local basename=ns.RaidGroupsImportedSetupName(source)
    local name=basename
    local suffix=2
    while not UniqueSetupName(name) do
        name=basename.." ("..suffix..")"
        suffix=suffix+1
    end
    PushUndo()
    draft=parsed
    draftPinned=CopyPinned(pinnedGuests)
    draftGuest=CopyPinned(normalGuests)
    RGStyle.emptyPinnedDraft=CopyPinned(emptyPins)
    removedGuestKeys={}
    selectedSetup=nil -- never overwrite a previously selected Keep Changes setup
    RGStyle.setupLoadToggle=nil
    firstDraftLoaded=true
    SaveEdit()
    SaveSetup(name)
    Notice(LF("Imported setup '%s': %d characters and %d Guest seats.",name,players,guests),"success")
    return true
end
local function TransferWindow(isImport)
    if not transferWindow then
        transferWindow = Panel("EllesmereUIRaidGroupsTransfer",655,420)
        transferWindow._title = Text(transferWindow,14)
        transferWindow._title:SetPoint("TOPLEFT",13,-12)
        local scroll = CreateFrame("ScrollFrame",nil,transferWindow,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",16,-83)
        scroll:SetPoint("BOTTOMRIGHT",-36,51)
        transferWindow._scroll=scroll
        local edit = CreateFrame("EditBox",nil,scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        TrackFont(edit, 11)
        edit:SetWidth(580)
        edit:SetHeight(1200)
        edit:SetTextInsets(5,5,4,4)
        edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        scroll:SetScrollChild(edit)
        transferWindow._edit = edit
        transferWindow._mode = "auto"
        local names = {{"Auto","auto"},{"Invitelist","invitelist"},{"2 columns","pair"},
                       {"8 Columns","eight"},{"Vertical","vertical"},{"EUIRG1","native"},{"Compact","compact"}}
        transferWindow._formatButtons={}
        for i,v in ipairs(names) do
            local b=Button(transferWindow,v[1],86,21,function(self)
                transferWindow._mode = v[2]
                transferWindow._activeMode = v[2]
                if not transferWindow._import then
                    edit:SetText(ExportText(v[2] == "auto" and "native" or v[2]))
                    edit:SetFocus()
                    edit:HighlightText()
                end
            end)
            b:SetPoint("TOPLEFT",14+(i-1)*90,-49)
            transferWindow._formatButtons[#transferWindow._formatButtons+1]=b
        end
        transferWindow._help = Text(transferWindow,10)
        -- Reserve a dedicated text column to the left of the Import button.
        -- Long localized hints wrap within this column instead of overlapping
        -- the action button at the bottom right of the transfer window.
        transferWindow._help:SetPoint("BOTTOMLEFT",15,9)
        transferWindow._help:SetWidth(490)
        transferWindow._help:SetHeight(43)
        transferWindow._help:SetJustifyH("LEFT")
        transferWindow._help:SetJustifyV("MIDDLE")
        transferWindow._action = Button(transferWindow,"Import",103,24,function()
            if transferWindow._import then
                if ns.ImportRaidGroupsIntoSetups(edit:GetText(),transferWindow._mode) then
                    transferWindow:Hide()
                end
            else
                edit:SetFocus()
                edit:HighlightText()
            end
        end)
        transferWindow._action:SetPoint("BOTTOMRIGHT",-15,12)
    end
    transferWindow._import = isImport
    local preferred = ns.RaidGroupsDefaultExportFormat()
    transferWindow._mode = isImport and ns.RaidGroupsDefaultImportFormat() or preferred
    for _,button in ipairs(transferWindow._formatButtons) do
        button:SetShown(not isImport)
    end
    transferWindow._scroll:ClearAllPoints()
    transferWindow._scroll:SetPoint("TOPLEFT",16,isImport and -52 or -83)
    transferWindow._scroll:SetPoint("BOTTOMRIGHT",-36,66)
    transferWindow._title:SetText(L(isImport and "Import Raid Group Setup" or "Export Raid Group Setup"))
    transferWindow._action._lbl:SetText(L(isImport and "Import" or "Select All"))
    local importTip=Enabled("guestFeatures") and Enabled("guestImportSeats")
        and "Notes: only invitelist: is parsed when present. Empty seats in populated groups become Pinned Guest (Setup)."
        or "Notes: only invitelist: is parsed when present. Empty entries remain vacant."
    transferWindow._help:SetText(L(isImport and importTip or "EUIRG1 and Compact preserve Guest, Pinned Guest and Pinned Empty seats; other formats are plain text."))
    transferWindow._edit:SetText(isImport and "" or ExportText(preferred))
    transferWindow._raidGroupsScaleKey=isImport and "import" or "export"
    RGStyle.ApplyPanelScale(transferWindow)
    transferWindow:Show()
    ApplyFonts()
    transferWindow._edit:SetFocus()
    if not isImport then transferWindow._edit:HighlightText() end
end

-------------------------------------------------------------------------------
-- Application: one protected operation per roster update. Each step checks
-- authority/combat and re-reads raid indices; it never caches an index across
-- updates. Missing characters in saved plans are intentionally skipped.
-------------------------------------------------------------------------------
StopApply=function(reason)
    applyState = nil
    if applyButton then
        applyButton._lbl:SetText(L("Apply Groups"))
        SetChoiceButtonState(applyButton,false,false)
    end
    if reason then Notice(reason); SetStatus(reason) end
    if Refresh then Refresh() end
end
local function TargetGroups(source, fixedGuestNames, excluded, emptyPinned)
    source = source or draft
    Roster()
    local wanted, order = {}, {}
    local assignedGuests = GuestAssignments(source, fixedGuestNames, excluded)
    local seen = {}
    for i=1,SLOT_COUNT do
        local v = source[i]
        local item = (v=="GUEST" or v==RGStyle.SETUP_GUEST) and assignedGuests[i]
            or (v and rosterByKey[Canonical(v)])
        if item and not seen[item.key] then
            wanted[item.key] = {group=math.floor((i-1)/GROUP_SIZE)+1, seat=(i-1)%GROUP_SIZE+1}
            order[#order+1] = item.key
            seen[item.key] = true
        end
    end
    -- Pinned Empty is a planner reservation, not an actual WoW raid slot.
    -- Reserve the corresponding subgroup *capacity* by providing concrete
    -- destinations to raid members not named by the saved composition.
    local reservedEmpty=CopyPinned(emptyPinned)
    for i=1,SLOT_COUNT do
        if source[i]==RGStyle.SETUP_GUEST and not assignedGuests[i] then
            reservedEmpty[i]=true
        end
    end
    if not next(reservedEmpty) then return wanted,order,assignedGuests,{} end
    local free, lastPinnedGroup, extras = {},0,{}
    for g=1,NUM_GROUPS do
        free[g]={}
        for n=1,GROUP_SIZE do
            local i=(g-1)*GROUP_SIZE+n
            if reservedEmpty[i] then
                lastPinnedGroup=math.max(lastPinnedGroup,g)
                if source[i] and source[i]~=RGStyle.SETUP_GUEST then
                    return wanted,order,assignedGuests,extras,"Pinned Empty conflicts with an occupied planned slot."
                end
            elseif not source[i] then
                free[g][#free[g]+1]=n
            end
        end
    end
    local function PlaceExtra(member,group)
        local seats=free[group]
        if #seats==0 then return false end
        local seat=table.remove(seats,1)
        wanted[member.key]={group=group,seat=seat,extra=true}
        order[#order+1]=member.key
        extras[member.key]=wanted[member.key]
        return true
    end
    for _,member in ipairs(rosterSorted) do
        if not seen[member.key] then
            local placed=PlaceExtra(member,member.group)
            if not placed then
                -- Prefer groups following the final deliberately vacant group.
                for g=lastPinnedGroup+1,NUM_GROUPS do
                    if PlaceExtra(member,g) then placed=true;break end
                end
            end
            if not placed then
                for g=1,NUM_GROUPS do
                    if g~=member.group and PlaceExtra(member,g) then placed=true;break end
                end
            end
            if not placed then
                return wanted,order,assignedGuests,extras,
                    "Not enough free group capacity to preserve Pinned Empty and unfilled Pinned Guest (Setup) seats."
            end
        end
    end
    return wanted,order,assignedGuests,extras
end
-- The current raid leader may be pinned to the first roster position of a
-- subgroup by the client. Build a temporary application target instead of
-- changing draft/setup data. This is repeated on every Apply, so transferring
-- leadership and applying again uses the user's original seat order.
local function AutomaticShiftLeader(wanted, silent, emptyPinned)
    local leader
    for _,member in ipairs(rosterSorted) do
        if member.rank==2 then leader=member; break end
    end
    if not leader then return end
    local planned=wanted[leader.key]
    if not planned or planned.seat==1 or planned.extra then return end
    -- A visual Pinned Empty slot must never be repurposed by leader shifting.
    if emptyPinned and emptyPinned[(planned.group-1)*GROUP_SIZE+1] then return end

    local targetGroup,plannedSeat=planned.group,planned.seat
    local originalFirst, candidates={},{ }
    -- Capture candidates *before* shifting any positions. Prefer the player
    -- originally first in the leader's group, then those first in other groups.
    for _,member in ipairs(rosterSorted) do
        local slot=wanted[member.key]
        if slot and slot.seat==1 and member.key~=leader.key then
            if slot.group==targetGroup then
                originalFirst[#originalFirst+1]=LF("%s (Group %d)",ChatName(member.name),slot.group)
            else
                candidates[#candidates+1]={group=slot.group,name=ChatName(member.name)}
            end
        end
    end
    table.sort(originalFirst)
    table.sort(candidates,function(a,b)
        if a.group~=b.group then return a.group<b.group end
        return a.name<b.name
    end)
    local labels=originalFirst
    for _,c in ipairs(candidates) do
        labels[#labels+1]=LF("%s (Group %d)",c.name,c.group)
    end

    -- A local shift inside the planned group: existing seats 1..N-1 move one
    -- place down; the leader occupies seat 1. No persisted table is touched.
    for key,slot in pairs(wanted) do
        if key~=leader.key and slot.group==targetGroup and slot.seat<plannedSeat then
            slot.seat=slot.seat+1
        end
    end
    planned.seat=1

    local message=LF("Automatic Shift Leader: %s will occupy Group %d, position 1 instead of planned position %d for this application.",
        ChatName(leader.name),targetGroup,plannedSeat)
    local guidance=(#labels>0) and
        LF("Transfer raid leadership to a player planned for position 1: %s. Then use Apply Groups again to restore the original order.",
            table.concat(labels,", ")) or
        L("No available players are planned for position 1 of another group. Transfer leadership manually when possible, then use Apply Groups again to restore the original order.")
    if not silent then Notice(message,"leader");Notice(guidance,"leader") end
    return {message=message,guidance=guidance,leader=leader.name}
end
-- Fingerprint only identities and leadership for the in-flight safety guard.
-- Group/index changes are expected after every protected operation and must
-- NOT be confused with an unexpected raid membership change.
local function RosterMembersSignature()
    local keys={}
    for _,m in ipairs(rosterSorted) do
        keys[#keys+1]=m.key..":"..(m.rank==2 and "L" or "")
    end
    table.sort(keys)
    return table.concat(keys,";")
end
local function PreviewFingerprint(guests, source)
    local t={RosterMembersSignature()}
    for i=1,SLOT_COUNT do
        local m=guests and guests[i]
        t[#t+1]=((source or draft)[i] or "_")..":"..(m and m.key or "_")
    end
    for _,m in ipairs(rosterSorted) do
        t[#t+1]=m.key..":"..m.group..":"..m.index
    end
    return table.concat(t,"|")
end
local function BuildApplyPlan(source,fixedGuestNames,skipAutoEmpty,excluded,emptyPinned)
    -- Resolve current eligible Guests from the latest roster, even when a
    -- setup is applied by slash command before any raid window was opened.
    Roster()
    excluded=excluded or removedGuestKeys
    emptyPinned=emptyPinned or RGStyle.emptyPinnedDraft
    local resolved,links,ambiguous=ns.RaidGroupsResolveRosterSource(source or draft)
    source=skipAutoEmpty and CopyDraft(resolved) or AutoGuestSource(resolved,excluded,emptyPinned)
    local wanted,order,guests,extras,blockedReason=TargetGroups(source,fixedGuestNames,excluded,emptyPinned)
    local lines,missing,used={}, {}, {}
    local unfilledGeneric=0
    for _,link in ipairs(links) do
        lines[#lines+1]=LF("Nickname match: %s -> %s",link.source,link.target)
    end
    for _,name in ipairs(ambiguous) do
        lines[#lines+1]=LF("Ambiguous nickname match (not assigned): %s",name)
    end
    for i=1,SLOT_COUNT do
        local v=source[i]
        if v and v~="GUEST" and v~=RGStyle.SETUP_GUEST then
            local key=Canonical(v)
            if key and not rosterByKey[key] then missing[#missing+1]=v end
        elseif (v=="GUEST" or v==RGStyle.SETUP_GUEST) and guests[i] then
            lines[#lines+1]=LF(v==RGStyle.SETUP_GUEST and "Pinned Guest (Setup): %s -> Group %d, position %d"
                or "Guest: %s -> Group %d, position %d",
                ChatName(guests[i].name),math.floor((i-1)/5)+1,(i-1)%5+1)
        elseif v=="GUEST" or v==RGStyle.SETUP_GUEST then
            if v==RGStyle.SETUP_GUEST then unfilledGeneric=unfilledGeneric+1 end
            lines[#lines+1]=LF(v==RGStyle.SETUP_GUEST and "Pinned Guest (Setup) in Group %d, position %d has no eligible player"
                or "Guest seat in Group %d, position %d remains unfilled",
                math.floor((i-1)/5)+1,(i-1)%5+1)
        end
    end
    table.sort(missing,function(a,b) return a:lower()<b:lower() end)
    local signature=PreviewFingerprint(guests,source)
    local shift=AutomaticShiftLeader(wanted,true,emptyPinned)
    local moved=0
    for _,key in ipairs(order) do
        local member=rosterByKey[key]
        local target=wanted[key]
        if member and target and member.group~=target.group then
            moved=moved+1
            lines[#lines+1]=LF("Move: %s | Group %d -> Group %d",
                ChatName(member.name),member.group,target.group)
        end
    end
    if moved==0 then lines[#lines+1]=L("No subgroup changes required for listed players.") end
    if shift then
        lines[#lines+1]=L("Automatic Shift Leader (temporary):").." "..shift.message
        lines[#lines+1]=shift.guidance
    end
    if data.exactPositions then
        lines[#lines+1]=L("Exact Positions enabled: individual seat order is best effort.")
    end
    for _,name in ipairs(missing) do
        lines[#lines+1]=LF("Missing: %s",ChatName(name))
    end
    return {wanted=wanted,order=order,guests=guests,missing=missing,
        unfilledGeneric=unfilledGeneric,extraTargets=extras,emptyPinned=CopyPinned(emptyPinned),blockedReason=blockedReason,
        shift=shift,signature=signature,members=RosterMembersSignature(),
        lines=lines,moved=moved,source=CopyDraft(source),fixedGuestNames=fixedGuestNames,
        excludedGuests=CopyKeys(excluded)}
end
-- The comparison uses ordinary insecure frames. These are a visual simulation
-- of the roster, not protected raid unit frames, so planning works in combat.
-- A preview carries its own 40-seat arrangement; neither drafts nor saved
-- setups are modified until the user expressly confirms an operation.
local function PreviewSeatSource(model)
    local source, fixed = {}, {}
    for i=1,SLOT_COUNT do
        if model.genericPinnedSeats[i] then
            source[i]=RGStyle.SETUP_GUEST
            if model.seats[i] then fixed[i]=model.seats[i] end
        elseif model.guestSeats[i] then
            source[i]="GUEST"
            if model.seats[i] then fixed[i]=model.seats[i] end
        else
            -- A named player who is offline must survive Overwrite Setup.
            source[i]=model.seats[i] or (model.absentNames and model.absentNames[i])
        end
    end
    return source, fixed
end
local function NewPreviewModel()
    local plan=BuildApplyPlan()
    local model={seats={},guestSeats={},emptyPinned=CopyPinned(RGStyle.emptyPinnedDraft),rosterMembers=plan.members,
        excludedGuests=CopyKeys(removedGuestKeys),
        originalSource=CopyDraft(draft),originalSetupEntry=selectedSetup and data.setups[selectedSetup],openingPlan=plan}
    local assigned={}
    model.pinnedGuests={}
    model.genericPinnedSeats={}
    model.normalGuests={}
    model.absentNames={}
    for i=1,SLOT_COUNT do
        -- The resolved opening plan includes automatically reserved empty seats.
        -- A previously pinned Guest is a fixed Character-Realm in the setup.
        local v=plan.source[i]
        local anonymous=(v=="GUEST" or v==RGStyle.SETUP_GUEST)
        local info=anonymous and plan.guests[i] or (v and rosterByKey[Canonical(v)])
        if v=="GUEST" then model.guestSeats[i]=true end
        if v==RGStyle.SETUP_GUEST then model.genericPinnedSeats[i]=true end
        if v and not anonymous and draftPinned[i] then model.pinnedGuests[i]=true end
        if v and not anonymous and draftGuest[i] then model.normalGuests[i]=true end
        if info and not assigned[info.key] then
            model.seats[i]=info.name
            assigned[info.key]=true
        elseif v and not anonymous then
            model.absentNames[i]=v
        end
    end
    -- Model unlisted members at their capacity-safe target when the setup
    -- contains Pinned Empty seats, never filling a visibly reserved vacancy.
    for _,m in ipairs(rosterSorted) do
        if not assigned[m.key] then
            local target
            local extra=plan.extraTargets and plan.extraTargets[m.key]
            if extra then
                local slot=(extra.group-1)*GROUP_SIZE+extra.seat
                if not model.seats[slot] and not model.guestSeats[slot] and
                    not model.absentNames[slot] and not model.emptyPinned[slot] and
                    not model.genericPinnedSeats[slot] then target=slot end
            end
            if not target and not extra then
                for n=1,GROUP_SIZE do
                    local slot=(m.group-1)*GROUP_SIZE+n
                    if not model.seats[slot] and not model.guestSeats[slot] and
                        not model.absentNames[slot] and not model.emptyPinned[slot] and
                        not model.genericPinnedSeats[slot] then target=slot;break end
                end
            end
            if not target then
                for slot=1,SLOT_COUNT do
                    if not model.seats[slot] and not model.guestSeats[slot] and
                        not model.absentNames[slot] and not model.emptyPinned[slot] and
                        not model.genericPinnedSeats[slot] then target=slot;break end
                end
            end
            if target then model.seats[target]=m.name;assigned[m.key]=true end
        end
    end
    model.initialSeats=CopyDraft(model.seats)
    model.initialEmptyPinned=CopyPinned(model.emptyPinned)
    model.initialGuestSeats={}
    model.initialExcludedGuests=CopyKeys(model.excludedGuests)
    model.initialPinnedGuests={}
    model.initialGenericPinnedSeats=CopyPinned(model.genericPinnedSeats)
    model.initialNormalGuests=CopyPinned(model.normalGuests)
    model.initialAbsentNames={}
    for i=1,SLOT_COUNT do
        model.initialGuestSeats[i]=model.guestSeats[i]
        model.initialPinnedGuests[i]=model.pinnedGuests[i]
        model.initialAbsentNames[i]=model.absentNames[i]
    end
    return model
end
local function PreviewRebuildGuests(model)
    -- Seats marked Guest retain their current occupant. Right-clicking an
    -- empty seat may move an eligible unlisted Guest from another position.
    local occupiedGuests={}
    local plannedMembers=Membership(model.originalSource)
    for i=1,SLOT_COUNT do
        if model.guestSeats[i] and model.seats[i] then
            occupiedGuests[Canonical(model.seats[i])]=true
        end
    end
    for i=1,SLOT_COUNT do
        if model.guestSeats[i] and not model.seats[i] then
            local candidates={}
            for j=1,SLOT_COUNT do
                local name=model.seats[j]
                if name and j~=i and not model.guestSeats[j] and not model.genericPinnedSeats[j]
                    and not model.pinnedGuests[j] and GuestMode(name)
                    and not plannedMembers[Canonical(name)]
                    and not model.excludedGuests[Canonical(name)]
                    and not occupiedGuests[Canonical(name)] then
                    candidates[#candidates+1]={seat=j,name=name,
                        manual=(data.guests[Canonical(name)]=="guest") and 0 or 1}
                end
            end
            table.sort(candidates,function(a,b)
                if a.manual~=b.manual then return a.manual<b.manual end
                return a.seat<b.seat
            end)
            local candidate=candidates[1]
            if candidate then
                model.seats[i]=candidate.name
                model.seats[candidate.seat]=nil
                occupiedGuests[Canonical(candidate.name)]=true
            end
        end
    end
end
-- Players removed from After Apply are not kicked from the raid. They
-- remain in the live roster and are available for a different draft seat.
-- Their eventual subgroup may change if the real Apply requires a swap.
local function PreviewAvailableMembers(model)
    local used={}
    for i=1,SLOT_COUNT do
        if model.seats[i] then used[Canonical(model.seats[i])]=true end
    end
    local available={}
    for _,member in ipairs(rosterSorted) do
        if not used[member.key] then available[#available+1]=member end
    end
    return available
end
local function PreviewAssignAvailable(model,name,i)
    local member=rosterByKey[Canonical(name)]
    if not member or i<1 or i>SLOT_COUNT then return false end
    -- If an explicitly reserved vacancy was clicked, continue to the next
    -- truly available slot rather than assigning into the pinned position.
    if model.emptyPinned[i] then
        local target
        for step=1,SLOT_COUNT-1 do
            local j=((i-1+step)%SLOT_COUNT)+1
            if not model.emptyPinned[j] and not model.genericPinnedSeats[j] and not model.seats[j] and
                not model.absentNames[j] and not model.guestSeats[j] then
                target=j;break
            end
        end
        if not target then return false end
        i=target
    end
    if model.genericPinnedSeats[i] or model.pinnedGuests[i] then return false end
    if (model.seats[i] or model.absentNames[i]) and
        not (model.normalGuests[i] or model.guestSeats[i]) then return false end
    for j=1,SLOT_COUNT do
        if model.seats[j] and Canonical(model.seats[j])==member.key then return false end
    end
    if model.seats[i] and Canonical(model.seats[i])~=member.key then
        model.excludedGuests[Canonical(model.seats[i])]=true
    end
    model.seats[i]=member.name
    model.absentNames[i]=nil
    model.normalGuests[i]=nil
    model.guestSeats[i]=nil
    model.excludedGuests[member.key]=nil
    -- An explicit assignment replaces only a normal Guest, never a Pinned Guest.
    model.selectedAvailableKey=nil
    return true
end
-- Keep the two right-click seat menus consistent: removal first, then
-- a fixed (pinned) Guest, then a replaceable (dynamic) Guest. Additional
-- classification and edit actions stay below those primary actions.
local SEAT_MENU_PRIORITY = {
    ["Unpin Pinned Empty (Make Available)"]=1,
    ["Mark as Pinned Empty"]=2,
    ["Remove Player / Clear Slot"]=1,
    ["Remove Player from Slot"]=1,
    ["Clear Guest Seat"]=1,
    ["Add Pinned Guest"]=2,
    ["Add Pinned Guest..."]=2,
    ["Pin Current Guest"]=2,
    ["Assign as Pinned Guest"]=2,
    ["Remove Pinned Guest"]=2,
    ["Mark as Guest (Replaceable)"]=3,
    ["Pin Guest to This Player"]=2,
    ["Mark Player as Guest"]=4,
    ["Unpin Guest (Make Dynamic)"]=3,
    ["Mark as Dynamic Guest"]=3,
    ["Replace with Dynamic Guest Seat"]=3,
    ["Reserve Dynamic Guest Seat"]=3,
    ["Remove Guest Tag"]=4,
    ["Automatic Guest Classification"]=5,
    ["Edit Slot / Character"]=6,
}
local function OrderSeatMenuActions(choices)
    local indexed={}
    for i,choice in ipairs(choices) do
        indexed[i]={choice=choice,ordinal=i}
    end
    table.sort(indexed,function(a,b)
        local ap=SEAT_MENU_PRIORITY[a.choice.label] or 100
        local bp=SEAT_MENU_PRIORITY[b.choice.label] or 100
        if ap~=bp then return ap<bp end
        return a.ordinal<b.ordinal
    end)
    for i,item in ipairs(indexed) do choices[i]=item.choice end
    return choices
end
-- Relocate players displaced by a new preview-only Pinned Empty marker.
-- Preserve their membership and show actual intended destinations in After Apply.
function RGStyle.RelocatePreviewExtras(model)
    local source,fixed=PreviewSeatSource(model)
    local plan=BuildApplyPlan(source,fixed,true,model.excludedGuests,model.emptyPinned)
    if plan.blockedReason then return end
    local used={}
    for i=1,SLOT_COUNT do
        if model.seats[i] then used[Canonical(model.seats[i])]=true end
    end
    for _,member in ipairs(rosterSorted) do
        local extra=plan.extraTargets and plan.extraTargets[member.key]
        if extra and not used[member.key] then
            local i=(extra.group-1)*GROUP_SIZE+extra.seat
            if not model.seats[i] and not model.guestSeats[i] and
                not model.absentNames[i] and not model.emptyPinned[i] and not model.genericPinnedSeats[i] then
                model.seats[i]=member.name
                model.excludedGuests[member.key]=nil
                used[member.key]=true
            end
        end
    end
end
-- A preview displays all raid members, including extras, so resolving an
-- added generic pin against the visible 40 cells would leave no candidates.
-- Resolve against original planned identities, then move the unique eligible
-- member from Available/another unprotected preview seat if necessary.
function RGStyle.AssignPreviewGenericSeat(model,i)
    local source=CopyDraft(model.originalSource)
    local fixed={}
    for j=1,SLOT_COUNT do
        if model.genericPinnedSeats[j] then
            source[j]=RGStyle.SETUP_GUEST
            if model.seats[j] then fixed[j]=model.seats[j] end
        elseif model.pinnedGuests[j] and model.seats[j] then
            source[j]=model.seats[j]
        end
    end
    local member=GuestAssignments(source,fixed,model.excludedGuests)[i]
    if not member then return end
    for j=1,SLOT_COUNT do
        if j~=i and model.seats[j] and Canonical(model.seats[j])==member.key then
            if model.genericPinnedSeats[j] or model.pinnedGuests[j] or model.guestSeats[j] then return end
            model.seats[j]=nil
            model.absentNames[j]=nil
            break
        end
    end
    model.seats[i]=member.name
end
local function PreviewSeatMenu(anchor,i)
    local model=previewDraftState
    if not model then return end
    local name=model.seats[i] or model.absentNames[i]
    local isGuest=model.guestSeats[i] or model.pinnedGuests[i] or model.genericPinnedSeats[i]
    local options={}
    if model.emptyPinned[i] then
        options[#options+1]={label="Unpin Pinned Empty (Make Available)",action=function()
            model.emptyPinned[i]=nil
            previewWindow._render()
        end}
    else
        options[#options+1]={label="Mark as Pinned Empty",action=function()
            if model.seats[i] then
                local key=Canonical(model.seats[i])
                if key then model.excludedGuests[key]=true end
            end
            model.seats[i]=nil
            model.absentNames[i]=nil
            model.guestSeats[i]=nil
            model.pinnedGuests[i]=nil
            model.genericPinnedSeats[i]=nil
            model.normalGuests[i]=nil
            model.emptyPinned[i]=true
            model.selectedAvailableKey=nil
            RGStyle.RelocatePreviewExtras(model)
            previewWindow._render()
        end}
    end
    if not model.emptyPinned[i] and Enabled("guestFeatures") and Enabled("guestRightClick") then
        if name then
            if not model.normalGuests[i] then
                options[#options+1]={label="Mark as Guest (Replaceable)",action=function()
                    model.normalGuests[i]=true
                    model.guestSeats[i]=nil
                    model.pinnedGuests[i]=nil
                    model.genericPinnedSeats[i]=nil
                    previewWindow._render()
                end}
            end
            if model.pinnedGuests[i] or model.genericPinnedSeats[i] then
                options[#options+1]={label="Remove Pinned Guest",action=function()
                    -- Keep the player in the preview; only remove protection.
                    model.pinnedGuests[i]=nil
                    model.genericPinnedSeats[i]=nil
                    previewWindow._render()
                end}
            else
                options[#options+1]={label="Add Pinned Guest",action=function()
                    model.guestSeats[i]=nil
                    model.normalGuests[i]=nil
                    model.genericPinnedSeats[i]=nil
                    model.pinnedGuests[i]=true
                    previewWindow._render()
                end}
            end
            if model.normalGuests[i] or model.guestSeats[i] then
                options[#options+1]={label="Remove Guest Tag",action=function()
                    model.guestSeats[i]=nil
                    model.normalGuests[i]=nil
                    previewWindow._render()
                end}
            end
        elseif model.genericPinnedSeats[i] then
            options[#options+1]={label="Remove Pinned Guest",action=function()
                model.genericPinnedSeats[i]=nil
                previewWindow._render()
            end}
        elseif model.guestSeats[i] then
            options[#options+1]={label="Clear Guest Seat",action=function()
                model.guestSeats[i]=nil
                previewWindow._render()
            end}
        else
            options[#options+1]={label="Reserve Dynamic Guest Seat",action=function()
                model.guestSeats[i]=true
                if Enabled("guestFillSeats") then PreviewRebuildGuests(model) end
                previewWindow._render()
            end}
        end
        if not name then
            options[#options+1]={label="Add Pinned Guest...",action=function()
                InputPrompt("Pinned Guest — Character-Realm (or setup):","",function(value)
                    value=Trim(value)
                    if value:lower()=="setup" then
                        model.seats[i]=nil
                        model.absentNames[i]=nil
                        model.guestSeats[i]=nil
                        model.normalGuests[i]=nil
                        model.pinnedGuests[i]=nil
                        model.genericPinnedSeats[i]=true
                        model.selectedAvailableKey=nil
                        RGStyle.AssignPreviewGenericSeat(model,i)
                        previewWindow._render()
                        return
                    end
                    if value=="" or value:upper()=="GUEST" or value:upper()=="BUYER" then
                        Notice("Enter a Character-Realm for Pinned Guest.");return
                    end
                    local change,unknown
                    value,change,unknown=RGStyle.CorrectEnteredRealm(value)
                    RGStyle.ReportRealmCorrection(change,unknown)
                    local key=Canonical(value)
                    if not key then return end
                    for j=1,SLOT_COUNT do
                        if j~=i and (Canonical(model.seats[j])==key or
                            Canonical(model.absentNames[j])==key) then
                            Notice("Character already assigned to another slot.");return
                        end
                    end
                    local member=rosterByKey[key]
                    model.seats[i]=member and member.name or nil
                    if member then
                        model.absentNames[i]=nil
                    else
                        model.absentNames[i]=value
                    end
                    model.guestSeats[i]=nil
                    model.normalGuests[i]=nil
                    model.pinnedGuests[i]=true
                    model.genericPinnedSeats[i]=nil
                    model.excludedGuests[key]=nil
                    model.selectedAvailableKey=nil
                    previewWindow._render()
                end,true)
            end}
        end
    end
    if name or isGuest then
        options[#options+1]={label="Remove Player / Clear Slot",action=function()
            -- Clear the name, missing-name snapshot and both Guest flags.
            -- The removed present player immediately appears in Available.
            if model.seats[i] then
                local key=Canonical(model.seats[i])
                if key then model.excludedGuests[key]=true end
            end
            model.seats[i]=nil
            model.absentNames[i]=nil
            model.guestSeats[i]=nil
            model.pinnedGuests[i]=nil
            model.genericPinnedSeats[i]=nil
            model.normalGuests[i]=nil
            model.selectedAvailableKey=nil
            previewWindow._render()
        end}
    end
    ShowSeatMenu(anchor,OrderSeatMenuActions(options))
end

local function PreviewSwapGroups(model,a,b)
    if a==b or a<1 or b<1 or a>NUM_GROUPS or b>NUM_GROUPS then return end
    for n=1,GROUP_SIZE do
        local x,y=(a-1)*GROUP_SIZE+n,(b-1)*GROUP_SIZE+n
        model.seats[x],model.seats[y]=model.seats[y],model.seats[x]
        model.guestSeats[x],model.guestSeats[y]=model.guestSeats[y],model.guestSeats[x]
        model.pinnedGuests[x],model.pinnedGuests[y]=model.pinnedGuests[y],model.pinnedGuests[x]
        model.genericPinnedSeats[x],model.genericPinnedSeats[y]=model.genericPinnedSeats[y],model.genericPinnedSeats[x]
        model.normalGuests[x],model.normalGuests[y]=model.normalGuests[y],model.normalGuests[x]
        model.absentNames[x],model.absentNames[y]=model.absentNames[y],model.absentNames[x]
        model.emptyPinned[x],model.emptyPinned[y]=model.emptyPinned[y],model.emptyPinned[x]
    end
end
local function PreviewSwapSeats(model,a,b)
    if a==b or a<1 or b<1 or a>SLOT_COUNT or b>SLOT_COUNT then return end
    model.seats[a],model.seats[b]=model.seats[b],model.seats[a]
    model.guestSeats[a],model.guestSeats[b]=model.guestSeats[b],model.guestSeats[a]
    model.pinnedGuests[a],model.pinnedGuests[b]=model.pinnedGuests[b],model.pinnedGuests[a]
    model.genericPinnedSeats[a],model.genericPinnedSeats[b]=model.genericPinnedSeats[b],model.genericPinnedSeats[a]
    model.normalGuests[a],model.normalGuests[b]=model.normalGuests[b],model.normalGuests[a]
    model.absentNames[a],model.absentNames[b]=model.absentNames[b],model.absentNames[a]
    model.emptyPinned[a],model.emptyPinned[b]=model.emptyPinned[b],model.emptyPinned[a]
end
local function BuildPreviewPlan(model)
    local source,fixed=PreviewSeatSource(model)
    local plan=BuildApplyPlan(source,fixed,true,model.excludedGuests,model.emptyPinned)
    plan.fromPreview=true
    -- Missing characters from the source setup remain visible as notices,
    -- even though the projected raid frame only contains present players.
    plan.previewNamedDraft=CopyDraft(model.seats)
    plan.previewGuestFlags={}
    plan.previewPinnedFlags=CopyPinned(model.pinnedGuests)
    plan.previewGenericPinnedFlags=CopyPinned(model.genericPinnedSeats)
    plan.previewNormalGuestFlags=CopyPinned(model.normalGuests)
    plan.previewEmptyPinnedFlags=CopyPinned(model.emptyPinned)
    for i=1,SLOT_COUNT do plan.previewGuestFlags[i]=model.guestSeats[i] end
    plan.previewSource=CopyDraft(source)
    plan.previewModel=model
    return plan
end
local function PreviewLeaderProjection(model,plan)
    local view=CopyDraft(model.seats)
    -- Displayed seats can differ from source seats while Automatic Shift
    -- Leader is projected. Always route clicks and drags through this map.
    local seatMap={}
    for i=1,SLOT_COUNT do seatMap[i]=i end
    -- Apply uses a temporary Shift Leader. Show that effective order in the
    -- preview without mutating the editable source seats or saved presets.
    if plan.shift and plan.shift.leader then
        local leaderKey=Canonical(plan.shift.leader)
        local seat
        for i=1,SLOT_COUNT do
            if view[i] and Canonical(view[i])==leaderKey then seat=i;break end
        end
        if seat then
            local first=math.floor((seat-1)/GROUP_SIZE)*GROUP_SIZE+1
            if seat>first then
                local leaderName=view[seat]
                local sourceSeat=seatMap[seat]
                for i=seat,first+1,-1 do
                    view[i]=view[i-1]
                    seatMap[i]=seatMap[i-1]
                end
                view[first]=leaderName
                seatMap[first]=sourceSeat
            end
        end
    end
    return view,seatMap
end
local BeginConfirmedApply
local function ShowApplyPreview(model)
    model=model or NewPreviewModel()
    previewDraftState=model
    if not previewWindow then
        previewWindow=Panel("EllesmereUIRaidGroupVisualPreview",1420,700)
        Text(previewWindow,16,"Preview Apply Groups"):SetPoint("TOPLEFT",15,-13)
        local subtitle=Text(previewWindow,11)
        subtitle:SetPoint("TOPLEFT",15,-42)
        subtitle:SetWidth(1355)
        previewWindow._subtitle=subtitle
        Text(previewWindow,13,"Current Raid"):SetPoint("TOPLEFT",15,-68)
        Text(previewWindow,13,"After Apply (Editable)"):SetPoint("TOPLEFT",728,-68)
        local currentRows,afterRows,afterHeaders={}, {}, {}
        previewWindow._currentRows=currentRows
        previewWindow._afterRows=afterRows
        previewWindow._afterHeaders=afterHeaders
        for side=1,2 do
            local left=side==1 and 16 or 728
            for g=1,NUM_GROUPS do
                local col=(g-1)%4
                local row=math.floor((g-1)/4)
                local x=left+col*(SLOT_W+COL_GAP)
                local y=-90-row*159
                local group=CreateFrame("Frame",nil,previewWindow)
                group:SetSize(SLOT_W,153)
                group:SetPoint("TOPLEFT",x,y)
                -- Match the main editor's borderless group headings and compact slots.
                local header=Button(group,LF("Group %d",g),SLOT_W,16)
                header:SetPoint("TOPLEFT",0,0)
                header._bg:SetColorTexture(0,0,0,0)
                header._border:SetColor(0,0,0,0)
                header._lbl:SetJustifyH("LEFT")
                header._lbl:SetTextColor(.65,.8,.78)
                if side==2 then
                    header._previewGroup=g
                    header:RegisterForDrag("LeftButton")
                    header:SetScript("OnDragStart",function(self)
                        if previewDraftState then previewWindow._drag={kind="group",index=self._previewGroup} end
                    end)
                    header:SetScript("OnDragStop",function()
                        local dragging=previewWindow._drag
                        previewWindow._drag=nil
                        if not dragging or dragging.kind~="group" or not previewDraftState then return end
                        for k,target in ipairs(afterHeaders) do
                            if k~=dragging.index and target:IsMouseOver() then
                                PreviewSwapGroups(previewDraftState,dragging.index,k)
                                previewWindow._render()
                                break
                            end
                        end
                    end)
                    afterHeaders[g]=header
                end
                for n=1,GROUP_SIZE do
                    local pos=(g-1)*GROUP_SIZE+n
                    local seat=Button(group,"",SLOT_W,SLOT_H)
                    seat:SetPoint("TOPLEFT",0,-17-(n-1)*(SLOT_H+SLOT_GAP))
                    seat._bg:SetColorTexture(.12,.15,.17,.85)
                    seat._border:SetColor(0,0,0,0)
                    seat._lbl:ClearAllPoints()
                    seat._lbl:SetPoint("LEFT",5,0)
                    seat._lbl:SetPoint("RIGHT",-4,0)
                    RGStyle.MarkPlayerFont(seat._lbl,side==1 and "current" or "after")
                    seat._label=seat._lbl
                    seat._previewSeat=pos
                    local icon=seat:CreateTexture(nil,"OVERLAY")
                    icon:Hide()
                    seat._previewLeaderIcon=icon
                    seat._lbl:SetJustifyH("LEFT")
                    if side==1 then
                        currentRows[pos]=seat
                        seat:Disable()
                    else
                        afterRows[pos]=seat
                        seat:RegisterForClicks("LeftButtonUp","RightButtonUp")
                        seat:RegisterForDrag("LeftButton")
                        seat:SetScript("OnDragStart",function(self)
                            if previewDraftState then previewWindow._drag={kind="seat",index=self._previewSeat} end
                        end)
                        seat:SetScript("OnDragStop",function()
                            local dragging=previewWindow._drag
                            previewWindow._drag=nil
                            if not dragging or dragging.kind~="seat" or not previewDraftState then return end
                            for _,target in ipairs(afterRows) do
                                if target~=seat and target:IsMouseOver() then
                                    local map=previewWindow._seatMap or {}
                                PreviewSwapSeats(previewDraftState,map[dragging.index] or dragging.index,
                                    map[target._previewSeat] or target._previewSeat)
                                    previewWindow._render()
                                    break
                                end
                            end
                        end)
                        seat:SetScript("OnClick",function(self,button)
                            if not previewDraftState then return end
                            if button=="RightButton" then
                                local map=previewWindow._seatMap or {}
                                PreviewSeatMenu(self,map[self._previewSeat] or self._previewSeat)
                            elseif button=="LeftButton" and previewDraftState.selectedAvailableKey then
                                local name=previewDraftState.selectedAvailableKey
                                local map=previewWindow._seatMap or {}
                                if PreviewAssignAvailable(previewDraftState,name,map[self._previewSeat] or self._previewSeat) then
                                    previewWindow._render()
                                end
                            end
                        end)
                        seat:SetScript("OnEnter",function(self)
                            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                            local map=previewWindow._seatMap or {}
                            local source=map[self._previewSeat] or self._previewSeat
                            if previewDraftState and previewDraftState.emptyPinned[source] then
                                GameTooltip:AddLine("Pinned Empty: this position remains vacant",.65,.68,.71)
                            elseif previewDraftState and previewDraftState.genericPinnedSeats[source] then
                                GameTooltip:AddLine(L("* Pinned Guest (Setup): one unique raid member without a saved nickname or planned seat"),1,.72,.31)
                            elseif previewDraftState and previewDraftState.pinnedGuests[source] then
                                GameTooltip:AddLine(L("* Pinned Guest: protected from player assignments"),1,.72,.31)
                            elseif previewDraftState and previewDraftState.normalGuests[source] then
                                GameTooltip:AddLine(L("* Guest: replaceable when assigning a player"),1,.72,.31)
                            elseif previewDraftState and previewDraftState.guestSeats[source] then
                                GameTooltip:AddLine(L("* Dynamic Guest: any eligible Guest can occupy this slot"),1,.72,.31)
                            elseif previewDraftState and previewDraftState.seats[source] and
                                GuestMode(previewDraftState.seats[source]) then
                                GameTooltip:AddLine(L("* Guest: character classified as Guest"),1,.72,.31)
                            end
                            GameTooltip:AddLine(L("Drag to swap; right-click for Guest and Remove Player actions"),.9,.9,.9)
                            GameTooltip:AddLine(L("Select Available, then click an empty seat or replaceable Guest to assign"),.7,.85,.8)
                            GameTooltip:Show()
                        end)
                        seat:SetScript("OnLeave",function() GameTooltip:Hide() end)
                    end
                end
            end
        end
        -- Available roster players include anyone removed from the proposed
        -- layout. The real raid is never modified merely by unassigning them.
        local availableTitle=Text(previewWindow,11,"Available Players")
        availableTitle:SetPoint("TOPLEFT",728,-415)
        availableTitle:SetWidth(678)
        previewWindow._availableTitle=availableTitle
        local availableRows={}
        for n=1,10 do
            local row=Button(previewWindow,"",319,23)
            row:SetPoint("TOPLEFT",728+math.floor((n-1)/5)*333,-440-((n-1)%5)*26)
            row._bg:SetColorTexture(.12,.15,.17,.85)
            RGStyle.MarkPlayerFont(row._lbl,"available")
            row._availableName=nil
            row:RegisterForDrag("LeftButton")
            row:SetScript("OnClick",function(self)
                if not previewDraftState or not self._availableName then return end
                local selected=Canonical(self._availableName)
                previewDraftState.selectedAvailableKey=(previewDraftState.selectedAvailableKey==selected) and nil or selected
                previewWindow._render()
            end)
            row:SetScript("OnDragStart",function(self)
                if self._availableName and previewDraftState then
                    previewWindow._drag={kind="available",name=self._availableName}
                end
            end)
            row:SetScript("OnEnter",function(self)
                if not self._availableName then return end
                GameTooltip:SetOwner(self,"ANCHOR_TOP")
                GameTooltip:AddLine(Display(self._availableName),1,1,1)
                GameTooltip:AddLine(L("Not assigned a destination in this preview; remains in the raid"),.8,.8,.8)
                if self._maySwap then
                    GameTooltip:AddLine(L("May be moved to a different subgroup to make room for a planned player"),1,.72,.31)
                end
                GameTooltip:AddLine(L("Click then choose an empty After Apply seat, or drag this player"),.7,.85,.8)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave",function() GameTooltip:Hide() end)
            row:SetScript("OnDragStop",function()
                local dragging=previewWindow._drag
                previewWindow._drag=nil
                if not previewDraftState or not dragging or dragging.kind~="available" then return end
                for _,target in ipairs(afterRows) do
                    if target:IsMouseOver() and PreviewAssignAvailable(previewDraftState,dragging.name,
                        (previewWindow._seatMap and previewWindow._seatMap[target._previewSeat]) or target._previewSeat) then
                        previewWindow._render()
                        break
                    end
                end
            end)
            availableRows[n]=row
        end
        previewWindow._availableRows=availableRows
        local function WheelAvailable(_,delta)
            if not previewDraftState then return end
            local maxOffset=math.max(0,#PreviewAvailableMembers(previewDraftState)-10)
            local old=previewDraftState.availableOffset or 0
            previewDraftState.availableOffset=math.max(0,math.min(maxOffset,old-(delta>0 and 1 or -1)))
            if old~=previewDraftState.availableOffset then previewWindow._render() end
        end
        local availableWheel=CreateFrame("Frame",nil,previewWindow)
        availableWheel:SetPoint("TOPLEFT",728,-440)
        availableWheel:SetSize(666,127)
        availableWheel:EnableMouseWheel(true)
        availableWheel:SetScript("OnMouseWheel",WheelAvailable)
        -- Keep the wheel surface behind the selectable Available rows.
        availableWheel:SetFrameLevel(previewWindow:GetFrameLevel()+1)
        for _,r in ipairs(availableRows) do
            r:SetFrameLevel(availableWheel:GetFrameLevel()+1)
            r:EnableMouseWheel(true)
            r:SetScript("OnMouseWheel",WheelAvailable)
        end
        previewWindow._availableScrollbar=RGStyle.ListScrollbar(previewWindow,1400,-440,127,
            function() return previewDraftState and (previewDraftState.availableOffset or 0) or 0 end,
            function(offset)
                if previewDraftState then previewDraftState.availableOffset=offset;previewWindow._render() end
            end,
            function() return previewDraftState and math.max(0,#PreviewAvailableMembers(previewDraftState)-10) or 0 end)
        local status=Text(previewWindow,11)
        status:SetPoint("TOPLEFT",16,-420)
        status:SetWidth(675)
        previewWindow._status=status
        local missing=Text(previewWindow,11)
        missing:SetPoint("TOPLEFT",16,-475)
        missing:SetWidth(675)
        missing:SetJustifyH("LEFT")
        previewWindow._missing=missing
        local leadership=Text(previewWindow,11)
        leadership:SetPoint("TOPLEFT",16,-515)
        leadership:SetWidth(675)
        leadership:SetJustifyH("LEFT")
        previewWindow._leadership=leadership
        local guide=Text(previewWindow,10,
            "Right-click to manage Pinned Empty and add/remove Pinned Guest or replaceable Guest. Reserved empty seats remain vacant during Apply.")
        guide:SetPoint("TOPLEFT",16,-590)
        guide:SetWidth(675)
        guide:SetJustifyH("LEFT")
        Button(previewWindow,"Reset Preview",123,26,function()
            if not previewDraftState then return end
            previewDraftState.seats=CopyDraft(previewDraftState.initialSeats)
            previewDraftState.guestSeats={}
            previewDraftState.excludedGuests=CopyKeys(previewDraftState.initialExcludedGuests)
            previewDraftState.pinnedGuests={}
            previewDraftState.genericPinnedSeats=CopyPinned(previewDraftState.initialGenericPinnedSeats)
            previewDraftState.normalGuests=CopyPinned(previewDraftState.initialNormalGuests)
            previewDraftState.emptyPinned=CopyPinned(previewDraftState.initialEmptyPinned)
            previewDraftState.absentNames={}
            previewDraftState.selectedAvailableKey=nil
            previewDraftState.availableOffset=0
            for i=1,SLOT_COUNT do
                previewDraftState.guestSeats[i]=previewDraftState.initialGuestSeats[i]
                previewDraftState.pinnedGuests[i]=previewDraftState.initialPinnedGuests[i]
                previewDraftState.absentNames[i]=previewDraftState.initialAbsentNames[i]
            end
            previewWindow._render()
        end):SetPoint("BOTTOMLEFT",15,14)
        previewWindow._overwrite=Button(previewWindow,"Overwrite Setup",133,26,function()
            if not previewDraftState then return end
            local setup=previewDraftState.originalSetupEntry
            local exists=false
            for _,entry in ipairs(data.setups) do if entry==setup then exists=true;break end end
            if not exists then Notice("Select a saved setup first.");return end
            Confirm(LF("Overwrite setup '%s' with the preview composition?",setup.name),function()
                if not previewDraftState then return end
                local source=PreviewSeatSource(previewDraftState)
                setup.slots=CopyDraft(source)
                setup.pinnedSeats=CopyPinned(previewDraftState.pinnedGuests)
                setup.normalGuestSeats=CopyPinned(previewDraftState.normalGuests)
                setup.emptyPinnedSeats=CopyPinned(previewDraftState.emptyPinned)
                -- Eligibility tags remain independent of a fixed seat.
                setup.guestModes=setup.guestModes or {}
                setup.updated=time()
                if RefreshSetups then RefreshSetups() end
                Notice(LF("Setup updated: %s",setup.name),"success")
            end)
        end)
        previewWindow._overwrite:SetPoint("BOTTOMLEFT",146,14)
        local previewCancelButton=Button(previewWindow,"Cancel",92,26,function()
            previewWindow:Hide()
            previewDraftState=nil
        end)
        previewCancelButton:SetPoint("BOTTOMRIGHT",-157,14)
        SetChoiceButtonState(previewCancelButton,false,true,true)
        previewConfirmButton=Button(previewWindow,"Confirm Apply",143,26,function()
            if not previewDraftState then return end
            Roster()
            if previewDraftState.rosterMembers~=RosterMembersSignature() then
                Notice("Raid membership or leadership changed. Refresh the preview before applying.")
                ShowApplyPreview(NewPreviewModel())
                return
            end
            local plan=BuildPreviewPlan(previewDraftState)
            if plan.blockedReason then Notice(plan.blockedReason);return end
            previewWindow:Hide()
            BeginConfirmedApply(plan)
        end)
        previewConfirmButton:SetPoint("BOTTOMRIGHT",-12,14)
        SetChoiceButtonState(previewConfirmButton,true,false,true)
        previewWindow._render=function()
            local model=previewDraftState
            if not model then return end
            Roster()
            local plan=BuildPreviewPlan(model)
            local projected,seatMap=PreviewLeaderProjection(model,plan)
            previewWindow._seatMap=seatMap
            local current={}
            local counts={}
            for _,m in ipairs(rosterSorted) do
                counts[m.group]=(counts[m.group] or 0)+1
                local i=(m.group-1)*GROUP_SIZE+counts[m.group]
                if i<=SLOT_COUNT then current[i]=m end
            end
            for i=1,SLOT_COUNT do
                local left=currentRows[i]
                local mem=current[i]
                left._lbl:SetText(mem and (Display(mem.name,mem.unit)..(GuestMode(mem.name) and "*" or "")) or L("Empty"))
                if mem and mem.class then
                    local c=EllesmereUI.GetClassColor(mem.class)
                    if c then left._lbl:SetTextColor(c.r,c.g,c.b) end
                else left._lbl:SetTextColor(.45,.45,.45) end
                local right=afterRows[i]
                local sourceIndex=seatMap[i]
                local name=projected[i]
                local info=name and rosterByKey[Canonical(name)]
                local absent=model.absentNames[sourceIndex] and not name and model.absentNames[sourceIndex]
                local isGuest=model.guestSeats[sourceIndex] or model.pinnedGuests[sourceIndex] or
                    model.genericPinnedSeats[sourceIndex] or model.normalGuests[sourceIndex] or
                    (name and GuestMode(name))
                local label=model.emptyPinned[sourceIndex] and "Pinned Empty" or
                    (name and (Display(name,info and info.unit)..(isGuest and "*" or "")) or
                    (absent and (Display(absent)..(isGuest and "*" or "").." ["..L("Missing").."]") or
                        (model.genericPinnedSeats[sourceIndex] and "Pinned Guest (Setup)" or
                            (model.guestSeats[sourceIndex] and L("Guest") or L("Empty")))))
                right._lbl:SetText(label)
                local leaderIcon=right._previewLeaderIcon
                local style=ns.RaidGroupsLeaderIconOption("leaderIconStyle")
                local leaderArt={
                    blizzard="Interface\\GroupFrame\\UI-Group-LeaderIcon",
                    star="Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
                    diamond="Interface\\TargetingFrame\\UI-RaidTargetingIcon_3"
                }
                if leaderIcon then
                    if info and info.rank==2 and leaderArt[style] and
                        (ns.RaidGroupsLeaderIconOption("leaderIconInCombat")~=false or not InCombatLockdown()) then
                        local size=tonumber(ns.RaidGroupsLeaderIconOption("leaderIconSize")) or 14
                        leaderIcon:SetSize(math.max(8,math.min(30,size)),math.max(8,math.min(30,size)))
                        leaderIcon:ClearAllPoints()
                        local pos=(ns.RaidGroupsLeaderIconOption("leaderIconPosition") or "right"):upper()
                        leaderIcon:SetPoint(pos,right,pos,
                            tonumber(ns.RaidGroupsLeaderIconOption("leaderIconOffsetX")) or 0,
                            tonumber(ns.RaidGroupsLeaderIconOption("leaderIconOffsetY")) or 0)
                        leaderIcon:SetTexture(leaderArt[style])
                        leaderIcon:Show()
                    else leaderIcon:Hide() end
                end
                if model.emptyPinned[sourceIndex] then
                    right._lbl:SetTextColor(.45,.48,.51)
                elseif model.guestSeats[sourceIndex] or model.normalGuests[sourceIndex] or model.genericPinnedSeats[sourceIndex] then
                    right._lbl:SetTextColor(1,.72,.31)
                elseif info and info.class then
                    local c=EllesmereUI.GetClassColor(info.class)
                    if c then right._lbl:SetTextColor(c.r,c.g,c.b) end
                else right._lbl:SetTextColor(.64,.66,.68) end
            end
            previewWindow._subtitle:SetText(LF("%d raid players | %d subgroup moves | %d missing",#rosterSorted,plan.moved,#plan.missing))
            local available=PreviewAvailableMembers(model)
            local maxOffset=math.max(0,#available-10)
            model.availableOffset=math.min(model.availableOffset or 0,maxOffset)
            previewWindow._availableTitle:SetText(LF("Available Players (%d) — select or drag into After Apply",#available))
            local groupCounts,neededIncoming={},{}
            for _,m in ipairs(rosterSorted) do groupCounts[m.group]=(groupCounts[m.group] or 0)+1 end
            for key,w in pairs(plan.wanted) do
                local member=rosterByKey[key]
                if member and member.group~=w.group then neededIncoming[w.group]=true end
            end
            for n,row in ipairs(previewWindow._availableRows) do
                local member=available[model.availableOffset+n]
                row._availableName=member and member.name or nil
                row._maySwap=false
                row:SetShown(member~=nil)
                if member then
                    local atRisk=groupCounts[member.group]>=GROUP_SIZE and neededIncoming[member.group]
                    row._maySwap=not not atRisk
                    local label=LF("%s (Group %d%s)",ChatName(member.name)..(GuestMode(member.name) and "*" or ""),member.group,
                        atRisk and "; may swap" or "; unassigned")
                    row._lbl:SetText(label)
                    row._lbl:SetTextColor(model.selectedAvailableKey==member.key and .22 or 1,
                        model.selectedAvailableKey==member.key and 1 or (atRisk and .7 or .82),
                        atRisk and .34 or .77)
                end
            end
            if previewWindow._availableScrollbar then previewWindow._availableScrollbar:Sync() end
            previewWindow._status:SetText(LF("Guest seats: %d | Exact Positions: %s | Pinned Empty reserves vacant seats; Pinned Guest (Setup) reserves a different nickname-free player for each slot",(function()
                local n=0;for i=1,SLOT_COUNT do
                    if model.guestSeats[i] or model.normalGuests[i] or model.pinnedGuests[i] or model.genericPinnedSeats[i] then n=n+1 end
                end;return n
            end)(),data.exactPositions and "ON (best effort)" or "OFF (subgroup order only)"))
            local missing={}
            for _,n in ipairs(plan.missing) do missing[#missing+1]=ChatName(n) end
            local missingNote=#missing>0 and
                LF("Missing players (not applied): %s",table.concat(missing,", ")) or
                L("Missing players: none")
            if plan.unfilledGeneric>0 then
                missingNote=missingNote..LF(" | Pinned Guest (Setup) without eligible players: %d",plan.unfilledGeneric)
            end
            previewWindow._missing:SetText(missingNote)
            previewWindow._leadership:SetText(plan.shift and
                (plan.shift.message.." "..plan.shift.guidance) or
                L("Raid leader: no automatic adjustment needed."))
            local setup=model.originalSetupEntry
            local exists=false
            for _,entry in ipairs(data.setups) do if entry==setup then exists=true;break end end
            previewWindow._overwrite:SetShown(exists)
            local stale=model.rosterMembers~=RosterMembersSignature()
            if previewConfirmButton then
                previewConfirmButton:SetEnabled(not stale and not plan.blockedReason)
                previewConfirmButton:SetAlpha((stale or plan.blockedReason) and .4 or 1)
            end
            if plan.blockedReason then
                previewWindow._status:SetText(L(plan.blockedReason))
            end
            if stale then
                previewWindow._status:SetText(L("Raid changed since this preview opened. Close and reopen to refresh."))
            end
        end
    end
    previewWindow._render()
    -- Personal scale is independent, with a viewport fit safety cap.
    RGStyle.ApplyPanelScale(previewWindow,"preview")
    previewWindow:Show()
    ApplyFonts()
end
-- Copy editable preview state without cloning saved setup identities, the
-- immutable opening plan, or live frame references. All other preview tables
-- are flat seat/flag maps and can be copied without mutating the original.
function RGStyle.CopyPreviewModel(model)
    if not model then return nil end
    local clone={}
    for key,value in pairs(model) do
        if type(value)=="table" and key~="originalSetupEntry" and key~="openingPlan" then
            clone[key]={}
            for index,item in pairs(value) do clone[key][index]=item end
        else
            clone[key]=value
        end
    end
    return clone
end
function RGStyle.CapturePreviewSnapshot()
    local visible=previewWindow and previewWindow:IsShown()
    if not previewDraftState or not (visible or RGStyle.previewSuspendedForCombat) then return nil end
    return {model=RGStyle.CopyPreviewModel(previewDraftState),wasShown=not not visible}
end
function RGStyle.RestorePreviewFromSetupToggle(saved)
    if applyState then return end
    local visible=previewWindow and previewWindow:IsShown()
    local suspended=RGStyle.previewSuspendedForCombat
    if saved and saved.model then
        previewDraftState=RGStyle.CopyPreviewModel(saved.model)
    elseif visible or suspended then
        -- Preview opened only after loading the setup: keep it open, but
        -- rebuild it from the now-restored editor instead of showing stale data.
        previewDraftState=NewPreviewModel()
    else
        previewDraftState=nil
    end
    if previewWindow then previewWindow._drag=nil end
    if previewDraftState and (visible or (saved and saved.wasShown and not suspended and not InGroupCombat())) then
        ShowApplyPreview(previewDraftState)
    end
end
-- Keep the independent preview synchronized when a different saved setup is
-- loaded. Rebuild its plan/Guest assignments/Pinned Empty slots and reset its
-- temporary edits, but leave the preview on screen and never apply the raid.
function RGStyle.RefreshPreviewFromSetup()
    if not previewDraftState or applyState then return end
    if previewWindow and previewWindow:IsShown() then
        previewDraftState=NewPreviewModel()
        previewWindow._drag=nil
        previewWindow._render()
    elseif RGStyle.previewSuspendedForCombat then
        -- Combat hides the panel without discarding its model. Ensure reopening
        -- resumes with the newly loaded setup rather than the previous one.
        previewDraftState=NewPreviewModel()
    end
end
BeginConfirmedApply=function(plan)
    if applyState then return end
    if not ns.RaidGroupsPermitted() then Notice("Raid leader or assistant required to apply groups.");return end
    if InGroupCombat() then WarnCombat(false);return end
    -- Revalidate against the actual roster immediately before any protected
    -- operation. Draft and preview operate on independent source tables.
    local now=BuildApplyPlan(plan.source,plan.fixedGuestNames,true,plan.excludedGuests,plan.emptyPinned)
    if now.blockedReason then Notice(now.blockedReason);return end
    if now.signature~=plan.signature then
        Notice("Raid composition changed since the plan was prepared. Review it before applying.")
        ShowApplyPreview(NewPreviewModel())
        return
    end
    if not next(now.wanted) then Notice("No available players from this setup are in the raid.");return end
    local missing=plan.fromPreview and plan.missing or now.missing
    if now.unfilledGeneric>0 then
        Notice(LF("%d Pinned Guest (Setup) seats have no eligible nickname-free raid member.",now.unfilledGeneric))
    end
    if #missing>0 then
        local names={}
        for _,name in ipairs(missing) do names[#names+1]=ChatName(name) end
        Notice(LF("Missing players from setup: %s",table.concat(names,", ")),"missing")
    end
    if now.shift then
        Notice(now.shift.message,"leader")
        Notice(now.shift.guidance,"leader")
    end
    applyState={wanted=now.wanted,order=now.order,members=now.members,
        steps=0,unchanged=0,phase="groups",attemptedExact={},lastOperation=nil,
        previewDraft=plan.fromPreview and CopyDraft(plan.previewSource) or nil,
        previewExcludedGuests=plan.fromPreview and CopyKeys(plan.excludedGuests) or nil,
        previewGuestFlags=plan.previewGuestFlags,
        previewPinnedFlags=plan.previewPinnedFlags,
        previewGenericPinnedFlags=plan.previewGenericPinnedFlags,
        previewNormalGuestFlags=plan.previewNormalGuestFlags,
        previewEmptyPinnedFlags=plan.previewEmptyPinnedFlags}
    if applyButton then
        applyButton._lbl:SetText(L("Cancel Apply"))
        SetChoiceButtonState(applyButton,false,true,true)
    end
    ProcessApply()
end
local function RequestApply()
    if applyState then StopApply("Group application cancelled.");return end
    if not ns.RaidGroupsPermitted() then Notice("Raid leader or assistant required to apply groups.");return end
    if InGroupCombat() then WarnCombat(false);return end
    local plan=BuildApplyPlan()
    if plan.blockedReason then Notice(plan.blockedReason);return end
    if not next(plan.wanted) then Notice("No available players from this setup are in the raid.");return end
    BeginConfirmedApply(plan)
end
local function RequestPreview()
    if applyState then Notice("Cannot open a new preview while applying raid groups.");return end
    -- Closing on entering combat is only a visual dismissal. Reopening the
    -- preview must retain its swaps, Guest seats and pending assignments.
    if RGStyle.previewSuspendedForCombat and previewDraftState then
        RGStyle.previewSuspendedForCombat=false
        ShowApplyPreview(previewDraftState)
    else
        RGStyle.previewSuspendedForCombat=false
        ShowApplyPreview(NewPreviewModel())
    end
end
function ns.ShowRaidGroupsPreviewWindow()
    if not data then Defaults() end
    if not firstDraftLoaded then
        if not selectedSetup and not next(draft) then FromRoster(true);dirty=false end
        firstDraftLoaded=true
    end
    RequestPreview()
end
local function QueueApply()
    if not applyState or updatePending then return end
    updatePending = true
    C_Timer.After(.55,function()
        updatePending = false
        if applyState then ProcessApply() end
    end)
end
local function RosterSignature()
    local t={}
    for _,m in ipairs(rosterSorted) do
        t[#t+1] = m.key..":"..m.group..":"..m.index
    end
    return table.concat(t,";")
end
function ProcessApply()
    local state = applyState
    if not state then return end
    if not ns.RaidGroupsPermitted() then
        StopApply("Group application interrupted: raid leader or assistant permission required.")
        return
    end
    if InGroupCombat() then
        StopApply()
        WarnCombat(true)
        return
    end
    Roster()
    if state.members~=RosterMembersSignature() then
        StopApply("Group application stopped: raid membership or leadership changed. Review Apply Groups preview again.")
        return
    end
    local signature = RosterSignature()
    if state.lastOperation then
        if signature == state.lastOperation then
            state.unchanged=state.unchanged+1
        else
            state.unchanged=0
        end
        state.lastOperation=nil
    end
    if state.unchanged >= 4 or state.steps >= 90 then
        StopApply("Stopped: raid roster is not accepting group changes.")
        return
    end
    local counts={}
    for g=1,NUM_GROUPS do counts[g]=0 end
    for _,m in ipairs(rosterSorted) do counts[m.group]=counts[m.group]+1 end
    -- Resolve every bridge swap against freshly queried roster indices. A
    -- cycle is resumed BEFORE the ordinary group pass so its temporary
    -- inter-group moves are not undone by the regular placement algorithm.
    if state.bridgeCycle then
        local cycle=state.bridgeCycle
        local a,b,c=rosterByKey[cycle.a],rosterByKey[cycle.b],rosterByKey[cycle.c]
        if not a or not b or not c or a.rank==2 or b.rank==2 or c.rank==2 then
            StopApply("Exact Positions stopped: bridge member unavailable or raid leader changed.")
            return
        end
        local left,right
        if cycle.stage==1 and a.group==cycle.group and b.group==cycle.group and c.group==cycle.other then
            left,right=a,c
        elseif cycle.stage==2 and a.group==cycle.other and b.group==cycle.group and c.group==cycle.group then
            left,right=a,b
        elseif cycle.stage==3 and a.group==cycle.group and b.group==cycle.other and c.group==cycle.group then
            left,right=b,c
        else
            StopApply("Exact Positions stopped: raid roster changed during a bridge swap.")
            return
        end
        state.steps=state.steps+1
        state.lastOperation=signature
        SwapRaidSubgroup(left.index,right.index)
        cycle.stage=cycle.stage+1
        if cycle.stage>3 then state.bridgeCycle=nil end
        QueueApply()
        return
    end
    local wrong, needGroup
    for _,k in ipairs(state.order) do
        local m, want = rosterByKey[k], state.wanted[k]
        if m and want and m.group ~= want.group then wrong=m; needGroup=want.group; break end
    end
    if wrong then
        local partner
        if counts[needGroup] < GROUP_SIZE then
            state.lastOperation=signature
            state.steps=state.steps+1
            SetRaidSubgroup(wrong.index,needGroup)
            QueueApply()
            return
        end
        -- Prefer an occupant that itself needs to leave the destination
        -- group. Otherwise select an unspecified occupant as a last resort.
        for _,m in ipairs(rosterSorted) do
            if m.group == needGroup and m.key ~= wrong.key then
                local expected = state.wanted[m.key]
                if expected and expected.group ~= m.group then partner=m;break end
            end
        end
        if not partner then
            for _,m in ipairs(rosterSorted) do
                if m.group == needGroup and not state.wanted[m.key] then partner=m;break end
            end
        end
        if not partner then
            StopApply(LF("Unable to place %s: no movable destination member.",wrong.name))
            return
        end
        state.lastOperation=signature
        state.steps=state.steps+1
        SwapRaidSubgroup(wrong.index,partner.index)
        QueueApply()
        return
    end
    -- Exact order is best effort. Use one swap per roster update; never issue
    -- three protected calls against indices that have already been invalidated.
    if data.exactPositions then
        local currentSeat={}
        for g=1,NUM_GROUPS do currentSeat[g]=0 end
        for _,m in ipairs(rosterSorted) do
            currentSeat[m.group]=currentSeat[m.group]+1
            local want=state.wanted[m.key]
            local actual=currentSeat[m.group]
            if want and actual~=want.seat and m.rank~=2 then
                local attempt=m.key..":"..want.group..":"..want.seat
                if not state.attemptedExact[attempt] then
                    state.attemptedExact[attempt]=true
                    local occupant,bridge
                    local pos=0
                    for _,x in ipairs(rosterSorted) do
                        if x.group==m.group then
                            pos=pos+1
                            if pos==want.seat then occupant=x end
                        elseif not bridge and x.rank~=2 then bridge=x end
                    end
                    if occupant and bridge and occupant.rank~=2 and occupant.key~=m.key then
                        state.bridgeCycle={a=m.key,b=occupant.key,c=bridge.key,
                            group=m.group,other=bridge.group,stage=1}
                        -- Call the next iteration directly: it will execute
                        -- only stage one using the current roster, then wait.
                        ProcessApply()
                        return
                    end
                end
            end
        end
        -- A successful subgroup assignment need not guarantee internal
        -- ordering: WoW controls raid indices, and leaders may sort first.
        Roster()
        local seen={}
        local unsatisfied=0
        for _,m in ipairs(rosterSorted) do
            seen[m.group]=(seen[m.group] or 0)+1
            local want=state.wanted[m.key]
            if want and seen[m.group]~=want.seat then unsatisfied=unsatisfied+1 end
        end
        if unsatisfied>0 then
            Notice(LF("Exact Positions: %d player positions could not be confirmed in the desired order.",unsatisfied))
        end
    end
    -- Group membership is authoritative; internal ordering is not guaranteed
    -- by WoW even when the eight-group preview keeps all five seat positions.
    -- Report any remaining seat differences for preview-confirmed plans,
    -- including when Exact Positions was deliberately disabled.
    if state.previewDraft and not data.exactPositions then
        Roster()
        local seen,unsatisfied={},0
        for _,m in ipairs(rosterSorted) do
            seen[m.group]=(seen[m.group] or 0)+1
            local wanted=state.wanted[m.key]
            if wanted and (wanted.group~=m.group or wanted.seat~=seen[m.group]) then
                unsatisfied=unsatisfied+1
            end
        end
        if unsatisfied>0 then
            Notice(LF("After Apply: %d internal raid-frame positions differ from the preview. Exact Positions is disabled; subgroup assignments were applied.",unsatisfied))
        end
    end
    local acceptedPreview=state.previewDraft
    local acceptedExcluded=state.previewExcludedGuests
    local acceptedFlags=state.previewGuestFlags
    local acceptedPins=state.previewPinnedFlags
    local acceptedNormals=state.previewNormalGuestFlags
    local acceptedEmpty=state.previewEmptyPinnedFlags
    StopApply()
    if acceptedPreview then
        PushUndo()
        draft=CopyDraft(acceptedPreview)
        draftPinned=CopyPinned(acceptedPins)
        draftGuest=CopyPinned(acceptedNormals)
        RGStyle.emptyPinnedDraft=CopyPinned(acceptedEmpty)
        removedGuestKeys=CopyKeys(acceptedExcluded)
        previewGuestAnnotations={}
        for i=1,SLOT_COUNT do
            if acceptedFlags and acceptedFlags[i] and draft[i] then
                previewGuestAnnotations[i]=true
            end
        end
        dirty=true
        if Refresh then Refresh() end
        if RefreshSetups and setupWindow and setupWindow:IsShown() then RefreshSetups() end
    end
    Notice("Raid groups applied (available players only).","success")
end

-------------------------------------------------------------------------------
-- Split Raid: balance by role/class priority, round-robin across subdivisions
-- and selected groups. The operation only changes the editable draft.
-------------------------------------------------------------------------------
local CLASS_PRIORITY = {WARRIOR=15,PALADIN=14,ROGUE=13,DEATHKNIGHT=12,
 DEMONHUNTER=11,SHAMAN=10,MONK=9,DRUID=8,HUNTER=7,PRIEST=6,MAGE=5,
 WARLOCK=4,EVOKER=3}
local function SplitDraft()
    if not Enabled("splitRaidEnabled") then return end
    local chosen, people = {}, {}
    for g=1,NUM_GROUPS do
        if data.split.groups[g] then
            chosen[#chosen+1]=g
            for n=1,GROUP_SIZE do
                local name=draft[(g-1)*GROUP_SIZE+n]
                if name and name~="GUEST" and name~=RGStyle.SETUP_GUEST then
                    local priority=0
                    local m=rosterByKey[Canonical(name)]
                    if m then
                        priority=100+(CLASS_PRIORITY[m.class] or 0)
                        local role=UnitGroupRolesAssigned(m.unit)
                        if role=="TANK" then priority=priority+60
                        elseif role=="DAMAGER" then priority=priority+40
                        elseif role=="HEALER" then priority=priority+20 end
                    end
                    people[#people+1]={name=name,priority=priority}
                end
            end
        end
    end
    local parts=data.split.parts
    if #chosen==0 or parts<1 or #chosen%parts~=0 then
        Notice("Selected group count must be divisible by the number of parts."); return
    end
    table.sort(people,function(a,b)
        if a.priority~=b.priority then return a.priority>b.priority end
        return a.name<b.name
    end)
    local buckets={}
    for p=1,parts do buckets[p]={} end
    local groupsPerPart=#chosen/parts
    for i,g in ipairs(chosen) do
        local part
        if data.split.alternate then part=((i-1)%parts)+1
        else part=math.floor((i-1)/groupsPerPart)+1 end
        buckets[part][#buckets[part]+1]=g
    end
    local nextDraft=CopyDraft(draft)
    for _,g in ipairs(chosen) do
        for n=1,GROUP_SIZE do
            local i=(g-1)*GROUP_SIZE+n
            if nextDraft[i]~="GUEST" and nextDraft[i]~=RGStyle.SETUP_GUEST then
                nextDraft[i]=nil
            end
        end
    end
    local destinations={}
    for p=1,parts do
        destinations[p]={}
        for _,g in ipairs(buckets[p]) do
            for n=1,GROUP_SIZE do
                local seat=(g-1)*GROUP_SIZE+n
                if not RGStyle.emptyPinnedDraft[seat] and not nextDraft[seat] then
                    destinations[p][#destinations[p]+1]=seat
                end
            end
        end
    end
    local cursors={}
    for p=1,parts do cursors[p]=1 end
    for i,person in ipairs(people) do
        local p=((i-1)%parts)+1
        local seat=destinations[p][cursors[p]]
        if not seat then
            -- Preserve every player when pinned vacancies make one split
            -- division smaller than another; do not silently drop a name.
            for alternate=1,parts do
                if destinations[alternate][cursors[alternate]] then
                    p=alternate
                    seat=destinations[p][cursors[p]]
                    break
                end
            end
        end
        if not seat then
            Notice("Split Raid has insufficient unpinned seats for the selected players.")
            return
        end
        nextDraft[seat]=person.name
        cursors[p]=cursors[p]+1
    end
    PushUndo()
    local pinnedNames,normalGuestNames={},{}
    for i=1,SLOT_COUNT do
        if draft[i] and draft[i]~="GUEST" and draft[i]~=RGStyle.SETUP_GUEST then
            local key=Canonical(draft[i])
            if key and draftPinned[i] then pinnedNames[key]=true end
            if key and draftGuest[i] then normalGuestNames[key]=true end
        end
    end
    draft=nextDraft
    draftPinned={}
    draftGuest={}
    for i=1,SLOT_COUNT do
        local key=draft[i] and draft[i]~="GUEST" and draft[i]~=RGStyle.SETUP_GUEST and Canonical(draft[i])
        if key and pinnedNames[key] then draftPinned[i]=true
        elseif key and normalGuestNames[key] then draftGuest[i]=true end
    end
    removedGuestKeys={}
    SaveEdit()
end

-------------------------------------------------------------------------------
-- Saved setup management: load/edit/rename/delete/reorder; editing an active
-- preset only updates its saved copy when Keep Changes is explicitly enabled.
-------------------------------------------------------------------------------
-- Achievement portraits for boss-named setups. The IDs match AlterEgo's
-- RaidLockouts feature. Aliases cover concise setup titles such as "M Nek'zali".
RGStyle.bossAchievementIDs={
    nekzali=63523,nekzalithesoulcoiler=63523,
    explorers=63525,thelostexplorers=63525,
    sszorak=63527,
    sentinels=63524,entombedsentinels=63524,
    vashnik=63526,vashnikthemalignant=63526,
    twinfangs=63528,thetwinfangs=63528,
    nymrissa=63682,nymrissawavecaller=63682,
    coiledaltar=63529,thecoiledaltar=63529,
    ulatek=63476,
}
function RGStyle.SetupBossKey(setupName)
    if type(setupName)~="string" then return nil end
    local name=setupName:lower()
    name=name:gsub("^%s*mythic%s*[:%-]?%s*", "")
        :gsub("^%s*heroic%s*[:%-]?%s*", "")
        :gsub("^%s*normal%s*[:%-]?%s*", "")
        :gsub("^%s*hc%s+", ""):gsub("^%s*[mn]%s+", "")
    -- One portrait per setup row; a combined setup uses its first boss.
    name=name:match("^([^/]+)") or name
    name=name:gsub("[^%w]", "")
    return name~="" and name or nil
end
function RGStyle.SetupBossIcon(setupName)
    local key=RGStyle.SetupBossKey(setupName)
    if not key then return nil end
    local knownID=RGStyle.bossAchievementIDs[key]
    if knownID and GetAchievementInfo then
        local ok,_,_,_,_,_,_,_,_,_,icon=pcall(GetAchievementInfo,knownID)
        if ok and icon then return icon end
    end
    -- Achievement catalog fallback for bosses introduced in later seasons.
    if not RGStyle._bossAchievementScanDone and GetCategoryList and
        GetCategoryNumAchievements and GetAchievementInfo then
        RGStyle._bossAchievementScanDone=true
        local found={}
        local ok=pcall(function()
            local mythic=(PLAYER_DIFFICULTY6 or "Mythic"):lower()..": "
            for _,categoryID in ipairs(GetCategoryList() or {}) do
                for index=1,(GetCategoryNumAchievements(categoryID) or 0) do
                    local _,name,_,_,_,_,_,_,_,icon=GetAchievementInfo(categoryID,index)
                    if type(name)=="string" and icon then
                        local prefix,boss=name:lower():match("^(.-: )(.+)$")
                        if boss then
                            local bossKey=boss:gsub("[^%w]", "")
                            local current=found[bossKey]
                            if prefix==mythic or not current then
                                found[bossKey]={icon=icon,mythic=(prefix==mythic)}
                            end
                        end
                    end
                end
            end
        end)
        if ok then RGStyle._bossAchievementCatalog=found end
    end
    local record=RGStyle._bossAchievementCatalog and RGStyle._bossAchievementCatalog[key]
    return record and record.icon or nil
end
local function EnsureSetupWindow()
    if setupWindow then return end
    setupWindow=Panel("EllesmereUIRaidGroupSetups",540,495)
    local title=Text(setupWindow,15,"Raid Group Setup")
    title:SetPoint("TOPLEFT",14,-15)
    local help=Text(setupWindow,10,"Click a setup to load it. Drag a setup to reorder.")
    help:SetPoint("TOPLEFT",14,-39)
    local make=Button(setupWindow,"Save as New",120,23,function()
        InputPrompt("Save current raid group setup as:","",SaveSetup)
    end)
    make:SetPoint("BOTTOMLEFT",14,44)
    keepButton=Button(setupWindow,"Keep Changes: OFF",148,23,function()
        data.keepChanges=not data.keepChanges
        keepButton._lbl:SetText(L(data.keepChanges and "Keep Changes: ON" or "Keep Changes: OFF"))
        SetChoiceButtonState(keepButton,not not data.keepChanges,true,true)
    end)
    keepButton:SetPoint("LEFT",make,"RIGHT",9,0)
    SetChoiceButtonState(keepButton,not not data.keepChanges,true,true)
    local save=Button(setupWindow,"Update Selected",128,23,function()
        if not selectedSetup or not data.setups[selectedSetup] then
            Notice("Select a saved setup first."); return
        end
        Confirm("Overwrite the selected setup with the current draft?",function()
            data.setups[selectedSetup].slots=CopyDraft(draft)
            data.setups[selectedSetup].pinnedSeats=CopyPinned(draftPinned)
            data.setups[selectedSetup].normalGuestSeats=CopyPinned(draftGuest)
            data.setups[selectedSetup].emptyPinnedSeats=CopyPinned(RGStyle.emptyPinnedDraft)
            data.setups[selectedSetup].updated=time()
            dirty=false
            Refresh(); RefreshSetups()
        end)
    end)
    save:SetPoint("LEFT",keepButton,"RIGHT",9,0)
    local setupImport=Button(setupWindow,"Import",103,23,function()
        TransferWindow(true)
    end)
    setupImport:SetPoint("BOTTOMLEFT",14,14)
    Button(setupWindow,"Export",103,23,function()
        TransferWindow(false)
    end):SetPoint("LEFT",setupImport,"RIGHT",9,0)
    local function SetupWheel(_,delta)
        setupOffset=math.max(0,math.min(math.max(0,#data.setups-10),setupOffset-(delta>0 and 1 or -1)))
        RefreshSetups()
    end
    local setupWheel=CreateFrame("Frame",nil,setupWindow)
    setupWheel:SetPoint("TOPLEFT",13,-74)
    setupWheel:SetSize(494,298)
    setupWheel:EnableMouseWheel(true)
    setupWheel:SetScript("OnMouseWheel",SetupWheel)
    setupWheel:SetFrameLevel(setupWindow:GetFrameLevel()+1)
    setupWindow._listScrollbar=RGStyle.ListScrollbar(setupWindow,516,-74,298,
        function() return setupOffset end,
        function(offset) setupOffset=offset;RefreshSetups() end,
        function() return math.max(0,#data.setups-10) end)
    for j=1,10 do
        local row=CreateFrame("Button",nil,setupWindow)
        row:SetSize(494,28)
        row:SetPoint("TOPLEFT",13,-74-(j-1)*30)
        local bg=EllesmereUI.SolidTex(row,"BACKGROUND",.10,.13,.15,.75);bg:SetAllPoints()
        row._bg=bg
        -- Reuse Raid Check's ready-mark atlas for the selected setup, rather
        -- than using a font-dependent checkmark character.
        local check=row:CreateTexture(nil,"ARTWORK")
        check:SetAtlas("UI-LFG-ReadyMark-Raid")
        check:SetSize(15,15)
        check:SetPoint("LEFT",row,"LEFT",6,0)
        check:Hide()
        local bossIcon=row:CreateTexture(nil,"ARTWORK")
        bossIcon:SetSize(18,18)
        bossIcon:SetPoint("LEFT",row,"LEFT",27,0)
        bossIcon:SetTexCoord(.07,.93,.07,.93)
        bossIcon:Hide()
        local label=Text(row,11);label:SetPoint("LEFT",49,0)
        label:SetWidth(325);label:SetJustifyH("LEFT")
        row._bossIcon=bossIcon
        row._selectedCheck=check
        local rename=Button(row,"Rename",61,21,function()
            local i=row._index
            if not i then return end
            InputPrompt("Rename raid group setup:",data.setups[i].name,function(v)
                v=Trim(v)
                if v=="" or not UniqueSetupName(v,i) then Notice("Invalid or duplicate setup name."); return end
                data.setups[i].name=v
                RefreshSetups()
            end)
        end)
        rename:SetPoint("RIGHT",row,"RIGHT",-36,0)
        Button(row,"X",24,21,function()
            local i=row._index
            if not i then return end
            local entry=data.setups[i]
            Confirm(LF("Delete setup '%s'?",entry.name),function()
                -- Position can change while a popup is visible: follow entry.
                for k,v in ipairs(data.setups) do
                    if v==entry then
                        table.remove(data.setups,k)
                        if RGStyle.setupLoadToggle and RGStyle.setupLoadToggle.entry==entry then
                            RGStyle.setupLoadToggle=nil
                        end
                        if selectedSetup==k then selectedSetup=nil
                        elseif selectedSetup and selectedSetup>k then selectedSetup=selectedSetup-1 end
                        break
                    end
                end
                RefreshSetups();Refresh()
            end)
        end):SetPoint("RIGHT",row,"RIGHT",-4,0)
        row._label=label;setupRows[j]=row
        row:SetFrameLevel(setupWheel:GetFrameLevel()+1)
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnClick",function(self) if self._index then LoadSetup(self._index,true) end end)
        row:SetScript("OnDragStart",function(self) self._dragEntry=self._index end)
        row:SetScript("OnDragStop",function(self)
            local i=self._dragEntry
            self._dragEntry=nil
            if not i then return end
            for _,other in ipairs(setupRows) do
                local j=other._index
                if j and i~=j and other:IsMouseOver() then
                    local item=table.remove(data.setups,i)
                    table.insert(data.setups,j,item)
                    if selectedSetup==i then selectedSetup=j
                    elseif selectedSetup then
                        if i<selectedSetup and j>=selectedSetup then selectedSetup=selectedSetup-1 end
                        if i>selectedSetup and j<=selectedSetup then selectedSetup=selectedSetup+1 end
                    end
                    RefreshSetups()
                    break
                end
            end
        end)
        RGStyle.ListWheel(row,SetupWheel)
    end
end
function RefreshSetups()
    if not setupWindow then return end
    if keepButton then
        keepButton._lbl:SetText(L(data.keepChanges and "Keep Changes: ON" or "Keep Changes: OFF"))
        SetChoiceButtonState(keepButton,not not data.keepChanges,true,true)
    end
    setupOffset=math.max(0,math.min(setupOffset,math.max(0,#data.setups-10)))
    if setupWindow._listScrollbar then setupWindow._listScrollbar:Sync() end
    for j,row in ipairs(setupRows) do
        local i=j+setupOffset
        local entry=data.setups[i]
        row._index=entry and i or nil
        row:SetShown(entry~=nil)
        if entry then
            local selected=i==selectedSetup
            row._selectedCheck:SetShown(selected)
            local achievementIcon=RGStyle.SetupBossIcon(entry.name)
            if achievementIcon then row._bossIcon:SetTexture(achievementIcon) end
            row._bossIcon:SetShown(not not achievementIcon)
            -- Selection uses Raid Check's ready icon plus the EUI accent color.
            local accent=EllesmereUI.ELLESMERE_GREEN or {r=.05,g=.82,b=.62}
            row._label:SetTextColor(selected and accent.r or 1,
                selected and accent.g or 1,selected and accent.b or 1)
            row._bg:SetColorTexture(selected and .06 or .10,
                selected and .23 or .13,selected and .18 or .15,.75)
            row._label:SetText(entry.name..(selected and dirty and " |cffffbc5a*|r" or ""))
        end
    end
end
local function ShowSetupWindow()
    EnsureSetupWindow()
    RefreshSetups()
    setupWindow:Show()
    ApplyFonts()
end
-- The Raid Tools + button exposes each native Raid Groups surface directly.
function ns.ShowRaidGroupsSetupWindow()
    if not data then Defaults() end
    ShowSetupWindow()
end

-------------------------------------------------------------------------------
-- Nicknames: globally persisted, grouped by nickname, alphabetized by both
-- nickname and full character identity. Deletion removes the entire group.
-------------------------------------------------------------------------------
local function NickGroups()
    local groups,indexed={},{}
    -- A manually created nickname can exist before any character is linked.
    for id,group in pairs(data.nicknameGroups) do
        if type(group)=="table" and SafeText(group.nickname) and
            (nickSearch=="" or RGStyle.UTF8Casefold(group.nickname):find(nickSearch,1,true)) then
            indexed[id]={id=id,nickname=group.nickname,locked=group.locked,
                source=group.source,updated=group.updated,children={}}
            groups[#groups+1]=indexed[id]
        end
    end
    for key,rec in pairs(data.nicknames) do
        local group=type(rec)=="table" and data.nicknameGroups[rec.groupId]
        if group and SafeText(rec.name) and SafeText(group.nickname) then
            local nick=group.nickname
            if nickSearch=="" or RGStyle.UTF8Casefold(nick):find(nickSearch,1,true)
                or RGStyle.UTF8Casefold(rec.name):find(nickSearch,1,true) then
                local id=rec.groupId
                if not indexed[id] then
                    indexed[id]={id=id,nickname=nick,locked=group.locked,source=group.source,
                        updated=group.updated,children={}}
                    groups[#groups+1]=indexed[id]
                end
                indexed[id].children[#indexed[id].children+1]={key=key,name=rec.name,
                    nickname=nick,id=id,class=rec.class}
            end
        end
    end
    table.sort(groups,function(a,b)
        if RGStyle.UTF8Casefold(a.nickname)~=RGStyle.UTF8Casefold(b.nickname) then
            return RGStyle.UTF8Casefold(a.nickname)<RGStyle.UTF8Casefold(b.nickname) end
        return a.id<b.id
    end)
    local flattened={}
    for _,group in ipairs(groups) do
        table.sort(group.children,function(a,b) return RGStyle.UTF8Casefold(a.name)<RGStyle.UTF8Casefold(b.name) end)
        flattened[#flattened+1]={type="nickname",id=group.id,nickname=group.nickname,
            locked=group.locked,source=group.source,updated=group.updated,children=group.children}
        if not nickCollapsed[group.id] then
            for _,child in ipairs(group.children) do
                flattened[#flattened+1]={type="character",name=child.name,key=child.key,
                    nickname=group.nickname,id=group.id,class=child.class}
            end
        end
    end
    return flattened
end
-- Changing a saved character identity must not detach it from its nickname
-- group or leave stale Character-Realm references in saved raid compositions.
-- A case-only correction retains the canonical key; a new identity rekeys it.
function RGStyle.RenameStoredCharacter(oldKey,entered)
    if not data or type(data.nicknames)~="table" then return false,"Nickname database unavailable." end
    local rec=oldKey and data.nicknames[oldKey]
    if not rec then return false,"Character association no longer exists." end
    local full=SafeText(entered)
    if not full then return false,"Enter a valid Character-Realm." end
    full=RGStyle.CapitalizeEntry(full)
    local realmChange,unknownRealm
    full,realmChange,unknownRealm=RGStyle.CorrectEnteredRealm(full)
    local character,realm=full:match("^([^%-]+)%-(.+)$")
    if not character or not realm or full:find("[%s%c|]") then
        return false,"Enter the full name as Character-Realm (without spaces)."
    end
    local newKey=Canonical(full)
    if not newKey then return false,"Enter a valid Character-Realm." end
    if newKey~=oldKey and data.nicknames[newKey] then
        return false,"That Character-Realm is already registered. No identities were merged."
    end
    if rec.name==full and newKey==oldKey then
        RGStyle.ReportRealmCorrection(realmChange,unknownRealm)
        return true
    end
    -- Update names in existing plans, undo snapshots and stored setups so the
    -- corrected identity still resolves through the nickname database.
    local function ReplaceNames(slots)
        if type(slots)~="table" then return end
        for i=1,SLOT_COUNT do
            local name=slots[i]
            if name and name~="GUEST" and name~=RGStyle.SETUP_GUEST and Canonical(name)==oldKey then slots[i]=full end
        end
    end
    for _,setup in ipairs(data.setups) do
        if type(setup)=="table" then
            ReplaceNames(setup.slots)
            if newKey~=oldKey and type(setup.guestModes)=="table" then
                if setup.guestModes[newKey]==nil then setup.guestModes[newKey]=setup.guestModes[oldKey] end
                setup.guestModes[oldKey]=nil
            end
            if newKey~=oldKey and type(setup.nicknames)=="table" then
                if setup.nicknames[newKey]==nil then setup.nicknames[newKey]=setup.nicknames[oldKey] end
                setup.nicknames[oldKey]=nil
            end
        end
    end
    ReplaceNames(draft)
    for _,entry in ipairs(undoStack) do
        ReplaceNames(entry.draft)
        ReplaceNames(entry.saved)
        if newKey~=oldKey and entry.exclusions and entry.exclusions[oldKey] then
            entry.exclusions[newKey]=true
            entry.exclusions[oldKey]=nil
        end
    end
    if previewDraftState then
        ReplaceNames(previewDraftState.originalSource)
        ReplaceNames(previewDraftState.absentNames)
        ReplaceNames(previewDraftState.initialAbsentNames)
        if newKey~=oldKey then
            for _,map in ipairs({previewDraftState.excludedGuests,previewDraftState.initialExcludedGuests}) do
                if map and map[oldKey] then map[newKey]=true;map[oldKey]=nil end
            end
        end
    end
    if newKey~=oldKey then
        -- A different Character-Realm may also be a different class. Never
        -- carry an icon from the old identity to an unverified new character.
        rec.class=nil
        data.nicknames[oldKey]=nil
        data.nicknames[newKey]=rec
        -- Explicit edits take precedence over stale provider names and old
        -- deletion tombstones, without silently merging another record.
        data.suppressed[oldKey]=true
        data.suppressed[newKey]=nil
        if data.nicknameSharing[oldKey]~=nil then
            if data.nicknameSharing[newKey]==nil then
                data.nicknameSharing[newKey]=data.nicknameSharing[oldKey]
            end
            data.nicknameSharing[oldKey]=nil
        end
        if data.guests[oldKey]~=nil then
            if data.guests[newKey]==nil then data.guests[newKey]=data.guests[oldKey] end
            data.guests[oldKey]=nil
        end
        if removedGuestKeys[oldKey] then
            removedGuestKeys[newKey]=true
            removedGuestKeys[oldKey]=nil
        end
    end
    rec.name=full
    RGStyle.ReportRealmCorrection(realmChange,unknownRealm)
    if Refresh then Refresh() end
    if RefreshSetups then RefreshSetups() end
    if previewWindow and previewWindow:IsShown() and previewWindow._render then
        previewWindow._render()
    end
    return true
end
local function AddNickname()
    InputPrompt("Character-Realm (optional):","",function(name)
        name=RGStyle.CapitalizeEntry(name)
        local realmChange,unknownRealm
        if name~="" then
            name,realmChange,unknownRealm=RGStyle.CorrectEnteredRealm(name)
            local character,realm=name:match("^([^%-]+)%-(.+)$")
            if not character or not realm or name:find("[%s%c|]") or not Canonical(name) then
                Notice("Enter a valid Character-Realm, or leave it blank.")
                return
            end
            local existing=data.nicknames[Canonical(name)]
            if existing then
                Notice(LF("Character '%s' is already registered in Nicknames.",existing.name or name))
                return
            end
        end
        InputPrompt(name=="" and "Nickname:" or LF("Nickname for %s:",name),"",function(nick)
            nick=RGStyle.CapitalizeEntry(nick)
            if nick=="" then Notice("Nickname cannot be empty."); return end
            if name=="" then
                for _,group in pairs(data.nicknameGroups) do
                    if type(group)=="table" and SafeText(group.nickname)
                        and RGStyle.UTF8Casefold(group.nickname)==RGStyle.UTF8Casefold(nick) then
                        Notice(LF("Nickname '%s' is already registered in Nicknames.",group.nickname))
                        return
                    end
                end
                NewNicknameGroup(nick,true,"Manual")
                Notice(LF("Nickname '%s' added to Nicknames.",nick),"success")
            else
                -- Recheck because roster or provider learning may have added the
                -- character while the nickname prompt was open.
                local existing=data.nicknames[Canonical(name)]
                if existing then
                    Notice(LF("Character '%s' is already registered in Nicknames.",existing.name or name))
                    return
                end
                if not StoreNickname(name,nick,true) then
                    Notice("Unable to save nickname association. Please try again.")
                    return
                end
                local rec=data.nicknames[Canonical(name)]
                local group=rec and data.nicknameGroups[rec.groupId]
                Notice(LF("Character '%s' added to nickname '%s'.",
                    rec and rec.name or name,group and group.nickname or nick),"success")
                RGStyle.ReportRealmCorrection(realmChange,unknownRealm)
            end
            RGStyle.LearnNicknameClasses()
            RefreshNicknames();Refresh()
        end)
    end, true)
end
local function DeleteNicknameGroup(name)
    local affected={}
    local id=name
    for key,rec in pairs(data.nicknames) do
        if rec.groupId==id then affected[#affected+1]={key=key,name=rec.nickname} end
    end
    local label=data.nicknameGroups[id] and data.nicknameGroups[id].nickname or id
    Confirm(LF("Delete nickname '%s' and all %d character associations?",label,#affected),function()
        for _,item in ipairs(affected) do
            data.nicknames[item.key]=nil
            data.suppressed[item.key]=true
        end
        data.nicknameGroups[id]=nil
        nickCollapsed[id]=nil
        RefreshNicknames();Refresh()
    end)
end
local function EnsureNickWindow()
    if nickWindow then return end
    nickWindow=Panel("EllesmereUIRaidGroupNicknames",525,495)
    nickWindow:RegisterEvent("GROUP_ROSTER_UPDATE")
    nickWindow:RegisterEvent("GUILD_ROSTER_UPDATE")
    nickWindow:SetScript("OnEvent",function(self)
        if not self:IsShown() then return end
        RGStyle.LearnNicknameClasses()
        RefreshNicknames()
    end)
    -- Class icons are exclusive to the Nicknames manager; no other player
    -- rows or windows use these textures.
    local title=Text(nickWindow,15,"Nicknames")
    title:SetPoint("TOPLEFT",14,-15)
    local _,search=Input(nickWindow,338,25)
    search:GetParent():SetPoint("TOPLEFT",14,-45)
    -- Same muted edit-box placeholder pattern used by EUI options widgets.
    local searchHint=Text(search,11,"Search")
    searchHint:SetTextColor(.5,.5,.5,.6)
    searchHint:SetPoint("LEFT",search,"LEFT",4,0)
    searchHint:SetShown(search:GetText()=="")
    search:SetScript("OnTextChanged",function(self)
        searchHint:SetShown(self:GetText()=="")
        nickSearch=RGStyle.UTF8Casefold(Trim(self:GetText()))
        nickOffset=0
        RefreshNicknames()
    end)
    Button(nickWindow,"Add Nickname",138,24,AddNickname):SetPoint("TOPRIGHT",-14,-45)
    local help=Text(nickWindow,10,"Edit: group nickname or character name/realm. Delete requires confirmation.")
    help:SetPoint("BOTTOMLEFT",14,21)
    local function NickWheel(_,delta)
        nickOffset=math.max(0,math.min(math.max(0,#NickGroups()-#nickRows),nickOffset-(delta>0 and 1 or -1)))
        RefreshNicknames()
    end
    local nickWheel=CreateFrame("Frame",nil,nickWindow)
    nickWheel:SetPoint("TOPLEFT",14,-84)
    nickWheel:SetSize(481,348)
    nickWheel:EnableMouseWheel(true)
    nickWheel:SetScript("OnMouseWheel",NickWheel)
    nickWheel:SetFrameLevel(nickWindow:GetFrameLevel()+1)
    nickWindow._listScrollbar=RGStyle.ListScrollbar(nickWindow,503,-84,348,
        function() return nickOffset end,
        function(offset) nickOffset=offset;RefreshNicknames() end,
        function() return math.max(0,#NickGroups()-12) end)
    for j=1,12 do
        local row=CreateFrame("Button",nil,nickWindow)
        row:RegisterForClicks("LeftButtonUp")
        row:SetSize(481,29)
        row:SetFrameLevel(nickWheel:GetFrameLevel()+1)
        row:SetPoint("TOPLEFT",14,-84-(j-1)*29)
        EllesmereUI.SolidTex(row,"BACKGROUND",.10,.13,.15,j%2==0 and .6 or .9):SetAllPoints()
        local hover=row:CreateTexture(nil,"HIGHLIGHT")
        hover:SetColorTexture(1,1,1,.08)
        hover:SetAllPoints(row)
        local label=Text(row,11)
        RGStyle.MarkPlayerFont(label,"nicknameManager")
        label:SetPoint("LEFT",8,0)
        label:SetWidth(275)
        label:SetJustifyH("LEFT")
        local classIcon=row:CreateTexture(nil,"ARTWORK")
        classIcon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        classIcon:SetSize(16,16)
        classIcon:SetPoint("LEFT",row,"LEFT",20,0)
        classIcon:Hide()
        row._classIcon=classIcon
        local edit=Button(row,"Edit",62,22,function()
            local r=row._record
            if not r then return end
            if r.type=="nickname" then
                -- Nickname-row Edit changes the shared nickname only.
                InputPrompt("Rename nickname for all characters:",r.nickname,function(value)
                    if Trim(value)=="" then return end
                    RenameNicknameGroup(r.id,Trim(value),true,"Manual")
                    RefreshNicknames();Refresh()
                end)
            else
                -- Character-row Edit changes Character-Realm only.
                InputPrompt("Edit Character-Realm:",r.name,function(value)
                    local ok,reason=RGStyle.RenameStoredCharacter(r.key,value)
                    if not ok then Notice(reason);return end
                    RefreshNicknames()
                end, true)
            end
        end)
        edit:RegisterForClicks("LeftButtonUp")
        edit:SetPoint("RIGHT",row,"RIGHT",-75,0)
        local remove=Button(row,"Delete",65,22,function()
            local r=row._record
            if not r then return end
            if r.type=="nickname" then DeleteNicknameGroup(r.id)
            else
                Confirm(LF("Delete nickname association for '%s'?",r.name),function()
                    data.suppressed[r.key]=true
                    data.nicknames[r.key]=nil
                    -- Keep the nickname group available for future characters.
                    RefreshNicknames();Refresh()
                end)
            end
        end)
        remove:SetPoint("RIGHT",row,"RIGHT",-5,0)
        local lock=Button(row,"Lock",42,22,function()
            local r=row._record
            if not r then return end
            local group=data.nicknameGroups[r.id]
            if group then group.locked=not group.locked;RefreshNicknames() end
        end)
        lock:SetPoint("RIGHT",edit,"LEFT",-3,0)
        row._lock=lock
        row._label=label;nickRows[j]=row
        row:SetScript("OnClick",function(self)
            local rec=self._record
            if not rec or rec.type~="nickname" then return end
            if nickCollapsed[rec.id] then
                nickCollapsed[rec.id]=nil
            else
                nickCollapsed[rec.id]=true
            end
            RefreshNicknames()
        end)
        RGStyle.ListWheel(row,NickWheel)
    end
end
function RefreshNicknames()
    if not nickWindow then return end
    local records=NickGroups()
    nickOffset=math.max(0,math.min(nickOffset,math.max(0,#records-#nickRows)))
    if nickWindow._listScrollbar then nickWindow._listScrollbar:Sync() end
    for i,row in ipairs(nickRows) do
        local rec=records[nickOffset+i]
        row._record=rec
        row:SetShown(rec~=nil)
        if rec then
            row._label:ClearAllPoints()
            row._label:SetPoint("LEFT",rec.type=="nickname" and 8 or 43,0)
            local coords=rec.type=="character" and CLASS_ICON_TCOORDS and
                CLASS_ICON_TCOORDS[rec.class]
            if coords then
                row._classIcon:SetTexCoord(unpack(coords))
                row._classIcon:Show()
            else
                row._classIcon:Hide()
            end
            row._label:SetText(rec.type=="nickname" and
                ((nickCollapsed[rec.id] and "+ " or "- ")..
                    "|cff0cd29f"..rec.nickname.."|r "..LF("(%d characters)",#rec.children)..
                    (rec.locked and (" — "..L("Locked")) or "").." — "..L(rec.source or "Saved"))
                or rec.name)
            row._lock:SetShown(rec.type=="nickname")
            if rec.type=="nickname" then
                row._lock._lbl:SetText(L(rec.locked and "Unlock" or "Lock"))
                -- Unlock is the action offered for a protected nickname;
                -- make that action red, while ordinary Lock stays neutral.
                SetChoiceButtonState(row._lock,false,rec.locked,true)
            end
        end
    end
end
local function ShowNickWindow()
    EnsureNickWindow()
    RGStyle.LearnNicknameClasses()
    RefreshNicknames()
    nickWindow:Show()
    ApplyFonts()
    -- Blizzard refreshes guild data asynchronously. When the guild roster
    -- arrives, the manager's event handler adds verified class icons.
    if IsInGuild() then
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        elseif GuildRoster then GuildRoster() end
    end
end

-------------------------------------------------------------------------------
-- Split options are intentionally independent of the main grid; editing them
-- never touches the raid roster or runs protected functions.
-------------------------------------------------------------------------------
local function EnsureSplitWindow()
    if splitWindow then return end
    splitWindow=Panel("EllesmereUIRaidGroupSplit",478,231)
    local title=Text(splitWindow,14,"Split Raid Settings")
    title:SetPoint("TOPLEFT",14,-14)
    local help=Text(splitWindow,11,"Groups included in the split:")
    help:SetPoint("TOPLEFT",14,-46)
    splitWindow._groupButtons={}
    for g=1,NUM_GROUPS do
        local b=Button(splitWindow,LF("Group %d",g),103,24,function()
            data.split.groups[g]=not data.split.groups[g]
            splitWindow._refresh()
        end)
        b:SetPoint("TOPLEFT",14+((g-1)%4)*115,-67-math.floor((g-1)/4)*30)
        splitWindow._groupButtons[g]=b
    end
    splitWindow._partButton=Button(splitWindow,LF("Parts: %d",2),106,25,function()
        local n=(data.split.parts or 2)+1
        if n>8 then n=2 end
        data.split.parts=n
        splitWindow._refresh()
    end)
    splitWindow._partButton:SetPoint("TOPLEFT",14,-148)
    splitWindow._ruleButton=Button(splitWindow,"Order: Contiguous",176,25,function()
        data.split.alternate=not data.split.alternate
        splitWindow._refresh()
    end)
    splitWindow._ruleButton:SetPoint("LEFT",splitWindow._partButton,"RIGHT",10,0)
    splitWindow._refresh=function()
        for g,b in ipairs(splitWindow._groupButtons) do
            b._lbl:SetText(LF("Group %d",g))
            SetChoiceButtonState(b,not not data.split.groups[g],false)
        end
        splitWindow._partButton._lbl:SetText(LF("Parts: %d",data.split.parts))
        splitWindow._ruleButton._lbl:SetText(L(data.split.alternate and "Order: Alternating" or "Order: Contiguous"))
    end
    Button(splitWindow,"Split Current Draft",182,25,function()
        SplitDraft()
        splitWindow:Hide()
    end):SetPoint("BOTTOMRIGHT",-14,14)
end
local function ShowSplitWindow()
    if not Enabled("splitRaidEnabled") then return end
    EnsureSplitWindow()
    splitWindow._refresh()
    splitWindow:Show()
    ApplyFonts()
end

-------------------------------------------------------------------------------
-- Main window: optional drag/drop and manual Guest classification. Reserved
-- Guest seats can show an eligible raid member; unlisted * markers are optional.
-------------------------------------------------------------------------------
local function SetGuestClassification(name,mode)
    if not Enabled("guestFeatures") or not Enabled("guestRightClick") then return end
    local key=Canonical(name)
    if not key then return end
    local setup=selectedSetup and data.setups[selectedSetup]
    local modes=setup and setup.guestModes or data.guests
    if not modes then modes={};setup.guestModes=modes end
    -- An explicit 'notguest' override removes the visual tag even when the
    -- automatic no-nickname classification would otherwise recreate it.
    modes[key]=mode
    if setup then setup.updated=time() end
    if Refresh then Refresh() end
    if RefreshExtras then RefreshExtras() end
end
local function GuestMenuActions(name)
    if not Enabled("guestFeatures") or not Enabled("guestRightClick") then return {} end
    local choices={}
    if GuestMode(name) then
        choices[#choices+1]={label="Remove Guest Tag",action=function()
            SetGuestClassification(name,"notguest") end}
    else
        choices[#choices+1]={label="Mark Player as Guest",action=function()
            SetGuestClassification(name,"guest") end}
    end
    choices[#choices+1]={label="Automatic Guest Classification",action=function()
        SetGuestClassification(name,nil) end}
    return choices
end
local function MainSeatMenu(row)
    local i,v=row._seat,row._value
    local choices={}
    if RGStyle.emptyPinnedDraft[i] then
        choices[#choices+1]={label="Unpin Pinned Empty (Make Available)",action=function()
            RGStyle.SetEmptyPinned(i,false) end}
    else
        choices[#choices+1]={label="Mark as Pinned Empty",action=function()
            RGStyle.SetEmptyPinned(i,true) end}
    end
    if v and v~="GUEST" and v~=RGStyle.SETUP_GUEST then
        if Enabled("guestFeatures") and Enabled("guestRightClick") then
            if not draftGuest[i] then
                choices[#choices+1]={label="Mark as Guest (Replaceable)",action=function()
                    RGStyle.SetNamedGuestKind(i,"guest") end}
            end
            if draftPinned[i] then
                choices[#choices+1]={label="Remove Pinned Guest",action=function()
                    -- Retain this Character-Realm; remove just the pinned flag.
                    RGStyle.SetNamedGuestKind(i,nil) end}
            else
                choices[#choices+1]={label="Add Pinned Guest",action=function()
                    RGStyle.SetNamedGuestKind(i,"pinned") end}
            end
            if draftGuest[i] then
                choices[#choices+1]={label="Remove Guest Tag",action=function()
                    RGStyle.SetNamedGuestKind(i,nil) end}
            end
        end
        for _,choice in ipairs(GuestMenuActions(v)) do
            if choice.label=="Remove Guest Tag" then
                choice.label="Stop Classifying Character as Guest"
            elseif choice.label=="Mark Player as Guest" then
                choice.label="Classify Character as Guest"
            end
            choices[#choices+1]=choice
        end
        choices[#choices+1]={label="Remove Player from Slot",action=function()
            SetDraft(i,nil) end}
    elseif v==RGStyle.SETUP_GUEST then
        choices[#choices+1]={label="Remove Pinned Guest",action=function() SetDraft(i,nil) end}
    elseif v=="GUEST" then
        if row._member and Enabled("guestFeatures") and Enabled("guestRightClick") then
            local guestName=row._member.name
            choices[#choices+1]={label="Pin Current Guest",action=function()
                SetDraft(i,guestName,"pinned")
            end}
        end
        choices[#choices+1]={label="Clear Guest Seat",action=function() SetDraft(i,nil) end}
    else
        if Enabled("guestFeatures") and Enabled("guestRightClick") then
            choices[#choices+1]={label="Reserve Dynamic Guest Seat",action=function()
                SetDraft(i,"GUEST") end}
        end
    end
    if not RGStyle.emptyPinnedDraft[i] and (not v or v=="GUEST" or v==RGStyle.SETUP_GUEST) and
        Enabled("guestFeatures") and Enabled("guestRightClick") then
        choices[#choices+1]={label="Add Pinned Guest...",action=function()
            InputPrompt("Pinned Guest — Character-Realm (or setup):","",function(value)
                value=Trim(value)
                if value:lower()=="setup" then
                    SetDraft(i,RGStyle.SETUP_GUEST)
                    return
                end
                if value=="" or value:upper()=="GUEST" or value:upper()=="BUYER" then
                    Notice("Enter a Character-Realm for Pinned Guest.");return
                end
                local change,unknown
                value,change,unknown=RGStyle.CorrectEnteredRealm(value)
                RGStyle.ReportRealmCorrection(change,unknown)
                SetDraft(i,value,"pinned")
            end,true)
        end}
    end
    choices[#choices+1]={label="Edit Slot / Character",action=function()
        InputPrompt("Character-Realm (blank to clear; GUEST to reserve):",v==RGStyle.SETUP_GUEST and "setup" or (v or ""),function(value)
            value=Trim(value)
            if value:lower()=="setup" then
                value=RGStyle.SETUP_GUEST
            elseif value:upper()=="GUEST" or value:upper()=="BUYER" then
                value="GUEST"
            elseif value~="" then
                local change,unknown
                value,change,unknown=RGStyle.CorrectEnteredRealm(value)
                RGStyle.ReportRealmCorrection(change,unknown)
            end
            SetDraft(i,value)
        end, true)
    end}
    ShowSeatMenu(row,OrderSeatMenuActions(choices))
end
local function StopDrag()
    if not dragFrom then return end
    dragFrom._lbl:SetAlpha(1)
    dragFrom=nil
    dragTarget=nil
    if dragGhost then
        dragGhost:SetScript("OnUpdate",nil)
        dragGhost:Hide()
    end
    for _,s in ipairs(slots) do s._highlight:Hide() end
end
local function DragUpdate(self)
    local x,y=GetCursorPosition()
    local scale=self:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("CENTER",UIParent,"BOTTOMLEFT",x/scale,y/scale)
    dragTarget=nil
    if win and win:IsMouseOver() then
        for _,s in ipairs(slots) do
            if s:IsMouseOver() and s~=dragFrom then
                dragTarget=s
                break
            end
        end
    end
    for _,s in ipairs(slots) do s._highlight:SetShown(s==dragTarget) end
end
local function StartDrag(s)
    if not Enabled("editorTools") or not Enabled("editorDrag") or not s._value or dragFrom then return end
    dragFrom=s
    s._lbl:SetAlpha(.35)
    dragGhost._lbl:SetText(s._lbl:GetText())
    dragGhost:Show()
    dragGhost:SetScript("OnUpdate",DragUpdate)
end
local function EndDrag()
    if not dragFrom then return end
    local a=dragFrom._seat
    local b=dragTarget and dragTarget._seat
    StopDrag()
    if b and a~=b then
        PushUndo()
        draft[a],draft[b]=draft[b],draft[a]
        draftPinned[a],draftPinned[b]=draftPinned[b],draftPinned[a]
        draftGuest[a],draftGuest[b]=draftGuest[b],draftGuest[a]
        RGStyle.emptyPinnedDraft[a],RGStyle.emptyPinnedDraft[b]=RGStyle.emptyPinnedDraft[b],RGStyle.emptyPinnedDraft[a]
        SaveEdit()
    end
end
local function UnlistedPlayers()
    if not Enabled("unlistedFeatures") or not Enabled("unlistedList") then return {} end
    local used=Membership()
    local result={}
    if listGuild and Enabled("unlistedGuild") then
        if IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
            for i=1,GetNumGuildMembers() do
                local name,_,_,_,_,_,_,_,_,_,class=GetGuildRosterInfo(i)
                if SafeText(name) then
                    local key=Canonical(name)
                    if key and not used[key] then
                        result[#result+1]={name=FullName(name),key=key,class=class,online=rosterByKey[key] and true or false,
                                           group=rosterByKey[key] and rosterByKey[key].group,
                                           rank=rosterByKey[key] and rosterByKey[key].rank}
                    end
                end
            end
        end
        table.sort(result,function(a,b) return RGStyle.UTF8Casefold(a.name)<RGStyle.UTF8Casefold(b.name) end)
    else
        for _,m in ipairs(rosterSorted) do
            if not used[m.key] then result[#result+1]=m end
        end
    end
    return result
end
local function AssignExtra(name,pinGuest)
    -- Normal Guest seats are replaceable. A Pinned Guest or Pinned Empty is not.
    -- Fill ordinary vacancies first, then replace a normal Guest or dynamic seat.
    local target
    for i=1,SLOT_COUNT do
        if not draft[i] and not RGStyle.emptyPinnedDraft[i] then target=i;break end
    end
    if not target then
        for i=1,SLOT_COUNT do
            if draftGuest[i] and draft[i] and not draftPinned[i] and
                not RGStyle.emptyPinnedDraft[i] then target=i;break end
        end
    end
    if not target then
        for i=1,SLOT_COUNT do
            if draft[i]=="GUEST" and not RGStyle.emptyPinnedDraft[i] then
                target=i;break
            end
        end
    end
    if not target then Notice("No free or replaceable Guest slot in the planned groups.");return end
    SetDraft(target,name,pinGuest and "pinned" or nil)
end
local RAID_LEADER_TEXTURES={
    blizzard="Interface\\GroupFrame\\UI-Group-LeaderIcon",
    star="Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    diamond="Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
}
local function UpdateLeaderIcon(row,member)
    local icon=row and row._leaderIcon
    if not icon then return end
    local style=ns.RaidGroupsLeaderIconOption("leaderIconStyle")
    if not member or member.rank~=2 or not RAID_LEADER_TEXTURES[style] or
       (ns.RaidGroupsLeaderIconOption("leaderIconInCombat")==false and InCombatLockdown()) then
        icon:Hide()
        return
    end
    local size=tonumber(ns.RaidGroupsLeaderIconOption("leaderIconSize")) or 14
    size=math.max(8,math.min(30,size))
    icon:SetSize(size,size)
    icon:ClearAllPoints()
    local pos=ns.RaidGroupsLeaderIconOption("leaderIconPosition") or "right"
    pos=pos:upper()
    local allowed={TOPLEFT=true,TOP=true,TOPRIGHT=true,LEFT=true,CENTER=true,
        RIGHT=true,BOTTOMLEFT=true,BOTTOM=true,BOTTOMRIGHT=true}
    if not allowed[pos] then pos="RIGHT" end
    icon:SetPoint(pos,row,pos,
        tonumber(ns.RaidGroupsLeaderIconOption("leaderIconOffsetX")) or 0,
        tonumber(ns.RaidGroupsLeaderIconOption("leaderIconOffsetY")) or 0)
    icon:SetTexture(RAID_LEADER_TEXTURES[style])
    icon:SetTexCoord(0,1,0,1)
    icon:Show()
end
local function AddLeaderIcon(row)
    local icon=row:CreateTexture(nil,"OVERLAY")
    icon:Hide()
    row._leaderIcon=icon
end
function RefreshExtras()
    if not win or not win:IsShown() then return end
    local show=Enabled("unlistedFeatures") and Enabled("unlistedList")
    if extrasLabel then extrasLabel:SetShown(show) end
    for _,b in ipairs(unlistedButtons) do
        b:SetShown(show and (b ~= listModeButton or Enabled("unlistedGuild")))
    end
    if not show then
        if win._unlistedScrollbar then win._unlistedScrollbar:Hide() end
        for _,row in ipairs(extras) do row._member=nil;row:Hide() end
        return
    end
    if not Enabled("unlistedGuild") then listGuild=false end
    local list=UnlistedPlayers()
    extraOffset=math.max(0,math.min(extraOffset,math.max(0,#list-10)))
    if win._unlistedScrollbar then win._unlistedScrollbar:Sync() end
    if extrasLabel then extrasLabel:SetText(LF("%s — Unlisted (%d)",L(listGuild and "Guild" or "Raid"),#list)) end
    if listModeButton then listModeButton._lbl:SetText(L(listGuild and "Guild / Raid" or "Raid / Guild")) end
    for j,row in ipairs(extras) do
        local info=list[extraOffset+j]
        row._member=info
        row:SetShown(info~=nil)
        UpdateLeaderIcon(row,info)
        if info then
            local setup=selectedSetup and data.setups[selectedSetup]
            local mode=(setup and setup.guestModes and setup.guestModes[info.key]) or data.guests[info.key]
            local guest=GuestMode(info.name)
            row._lbl:SetText(Display(info.name)..(guest and "*" or (Enabled("unlistedAsterisk") and " *" or ""))..
                (not guest and mode=="notguest" and (" ["..L("Not Guest").."]") or ""))
            local c=info.class and EllesmereUI.GetClassColor(info.class)
            if c then row._lbl:SetTextColor(c.r,c.g,c.b) else row._lbl:SetTextColor(1,1,1) end
        end
    end
end
function Refresh()
    if not win then return end
    Roster()
    local resolved=ns.RaidGroupsResolveRosterSource(draft)
    local mapped=GuestAssignments(resolved)
    for i,s in ipairs(slots) do
        local v=draft[i]
        s._value=v
        local effective=resolved[i]
        local player = (v=="GUEST" or v==RGStyle.SETUP_GUEST) and mapped[i]
            or (effective and rosterByKey[Canonical(effective)])
        s._member=player
        UpdateLeaderIcon(s,player)
        if RGStyle.emptyPinnedDraft[i] then
            s._lbl:SetText("Pinned Empty")
            s._lbl:SetTextColor(.45,.48,.51)
        elseif v=="GUEST" then
            s._lbl:SetText(player and (Display(player.name,player.unit).."*") or L("Guest"))
            s._lbl:SetTextColor(1,.72,.31)
        elseif v==RGStyle.SETUP_GUEST then
            s._lbl:SetText(player and (Display(player.name,player.unit).."* [Pinned]") or "Pinned Guest (Setup)")
            s._lbl:SetTextColor(1,.72,.31)
        elseif v then
            local nick=Display(v,player and player.unit)
            local explicitGuest=GuestMode(v)
            local setup=selectedSetup and data.setups[selectedSetup]
            local fixedGuest=not not draftPinned[i]
            if fixedGuest or draftGuest[i] or explicitGuest or previewGuestAnnotations[i] then nick=nick.."*" end
            s._lbl:SetText(nick)
            local color=player and player.class and EllesmereUI.GetClassColor(player.class)
            if color then s._lbl:SetTextColor(color.r,color.g,color.b,player.online and 1 or .5)
            else s._lbl:SetTextColor(.82,.82,.82,player and 1 or .48) end
        else
            s._lbl:SetText("")
        end
    end
    if mainHelp then
        local text="Shift+click to edit"
        text=text.." • Right-click: slot menu"
        if Enabled("editorTools") and Enabled("editorDrag") then text=text.." • Drag seats or group titles to swap (also in combat)" end
        mainHelp:SetText(L(text))
    end
    if dirtyLabel then
        dirtyLabel:SetText(dirty and ("|cffffb84e"..L("Unsaved changes").."|r") or
            (selectedSetup and LF("Setup: %s",data.setups[selectedSetup].name) or L("Temporary composition")))
    end
    if applyButton then
        applyButton._lbl:SetText(L(applyState and "Cancel Apply" or "Apply Groups"))
        SetChoiceButtonState(applyButton,false,applyState~=nil,true)
    end
    if exactButton then
        exactButton._lbl:SetText(L(data.exactPositions and "Exact Positions: ON" or "Exact Positions: OFF"))
        SetChoiceButtonState(exactButton,false,not data.exactPositions,true)
    end
    for _,rec in ipairs(editorButtons) do
        rec.button:SetShown(Enabled("editorTools") and Enabled(rec.option))
    end
    -- Layout active controls consecutively, without changing panel dimensions.
    local x,row,spacing,maxWidth=14,0,6,886
    for _,entry in ipairs(footerControls) do
        local visible=not entry.visible or entry.visible()
        entry.button:SetShown(visible)
        if visible then
            local w=entry.button:GetWidth()
            if x+w>maxWidth and row==0 then row=1;x=14 end
            entry.button:ClearAllPoints()
            entry.button:SetPoint("TOPLEFT",x,-384-row*30)
            x=x+w+spacing
        end
    end
    RefreshExtras()
end
-- Build the repeated group slot widgets separately to respect WoW Lua 5.1's
-- 60-upvalue limit on individual functions (the main initializer grew beyond it).
function ns._BuildRaidGroupsMainSlots()
    -- Swap whole groups as one draft edit. Guest reservations, pinned assignments,
    -- and accepted-preview annotations travel with their individual seats.
    local function SwapDraftGroups(a,b)
        if not Enabled("editorTools") or not Enabled("editorDrag") or
           not a or not b or a==b or a<1 or b<1 or a>NUM_GROUPS or b>NUM_GROUPS then return end
        local changed=false
        for n=1,GROUP_SIZE do
            local i,j=(a-1)*GROUP_SIZE+n,(b-1)*GROUP_SIZE+n
            if draft[i]~=draft[j] or draftPinned[i]~=draftPinned[j] or
               draftGuest[i]~=draftGuest[j] or
               RGStyle.emptyPinnedDraft[i]~=RGStyle.emptyPinnedDraft[j] or
               previewGuestAnnotations[i]~=previewGuestAnnotations[j] then
                changed=true
                break
            end
        end
        if not changed then return end
        PushUndo()
        for n=1,GROUP_SIZE do
            local i,j=(a-1)*GROUP_SIZE+n,(b-1)*GROUP_SIZE+n
            draft[i],draft[j]=draft[j],draft[i]
            draftPinned[i],draftPinned[j]=draftPinned[j],draftPinned[i]
            draftGuest[i],draftGuest[j]=draftGuest[j],draftGuest[i]
            RGStyle.emptyPinnedDraft[i],RGStyle.emptyPinnedDraft[j]=RGStyle.emptyPinnedDraft[j],RGStyle.emptyPinnedDraft[i]
            previewGuestAnnotations[i],previewGuestAnnotations[j]=
                previewGuestAnnotations[j],previewGuestAnnotations[i]
        end
        SaveEdit()
    end

    local cols, groupHeight = 4, 159
    local groupHeaders={}
    win._groupHeaders=groupHeaders
    for g=1,NUM_GROUPS do
        local col=(g-1)%cols
        local row=math.floor((g-1)/cols)
        local x=PAD+col*(SLOT_W+COL_GAP)
        local y=-63-row*groupHeight
        local hdr=Button(win,LF("Group %d",g),SLOT_W,16)
        hdr:SetPoint("TOPLEFT",x,y)
        hdr._bg:SetColorTexture(0,0,0,0)
        hdr._border:SetColor(0,0,0,0)
        hdr._lbl:ClearAllPoints()
        hdr._lbl:SetPoint("LEFT",3,0)
        hdr._lbl:SetPoint("RIGHT",-4,0)
        hdr._lbl:SetJustifyH("LEFT")
        hdr._lbl:SetTextColor(.65,.8,.78)
        hdr._group=g
        hdr:RegisterForDrag("LeftButton")
        hdr:SetScript("OnDragStart",function(self)
            if not Enabled("editorTools") or not Enabled("editorDrag") then return end
            self._groupDragging=true
            self._lbl:SetAlpha(.4)
        end)
        hdr:SetScript("OnDragStop",function(self)
            if not self._groupDragging then return end
            self._groupDragging=nil
            self._lbl:SetAlpha(1)
            for targetGroup,targetHeader in ipairs(groupHeaders) do
                if targetGroup~=self._group then
                    local over=targetHeader:IsMouseOver()
                    if not over then
                        for n=1,GROUP_SIZE do
                            local targetSeat=slots[(targetGroup-1)*GROUP_SIZE+n]
                            if targetSeat and targetSeat:IsMouseOver() then
                                over=true
                                break
                            end
                        end
                    end
                    if over then
                        SwapDraftGroups(self._group,targetGroup)
                        break
                    end
                end
            end
        end)
        groupHeaders[g]=hdr
        for n=1,GROUP_SIZE do
            local index=(g-1)*GROUP_SIZE+n
            local s=CreateFrame("Button",nil,win)
            s:SetSize(SLOT_W,SLOT_H)
            s:SetPoint("TOPLEFT",x,y-17-(n-1)*(SLOT_H+SLOT_GAP))
            EllesmereUI.SolidTex(s,"BACKGROUND",.12,.15,.17,.85):SetAllPoints()
            s._highlight=EllesmereUI.SolidTex(s,"ARTWORK",.12,.83,.63,.27)
            s._highlight:SetAllPoints();s._highlight:Hide()
            s._lbl=Text(s,10)
            RGStyle.MarkPlayerFont(s._lbl,"main")
            s._lbl:SetPoint("LEFT",5,0)
            s._lbl:SetPoint("RIGHT",-4,0)
            s._lbl:SetJustifyH("LEFT")
            s._seat=index
            AddLeaderIcon(s)
            s:RegisterForClicks("LeftButtonUp","RightButtonUp")
            s:RegisterForDrag("LeftButton")
            s:SetScript("OnDragStart",StartDrag)
            s:SetScript("OnDragStop",EndDrag)
            s:SetScript("OnClick",function(self,mouseButton)
                if mouseButton=="RightButton" then
                    MainSeatMenu(self)
                elseif IsShiftKeyDown() then
                    InputPrompt("Character-Realm (blank to clear; GUEST to reserve):",self._value==RGStyle.SETUP_GUEST and "setup" or (self._value or ""),function(value)
                        value=Trim(value)
                        if value:lower()=="setup" then
                            value=RGStyle.SETUP_GUEST
                        elseif value:upper()=="GUEST" or value:upper()=="BUYER" then
                            value="GUEST"
                        elseif value~="" then
                            local change,unknown
                            value,change,unknown=RGStyle.CorrectEnteredRealm(value)
                            RGStyle.ReportRealmCorrection(change,unknown)
                        end
                        SetDraft(self._seat,value)
                    end, true)
                end
            end)
            s:SetScript("OnEnter",function(self)
                if self._value or self._member or RGStyle.emptyPinnedDraft[self._seat] then
                    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                    GameTooltip:AddLine(RGStyle.emptyPinnedDraft[self._seat] and "Pinned Empty: reserved vacant seat" or
                        (self._value==RGStyle.SETUP_GUEST and "Pinned Guest (Setup)" or
                            (self._value=="GUEST" and L("Guest seat") or (self._value or ""))))
                    if self._member then GameTooltip:AddLine(LF("Roster: %s",self._member.name), .7,.8,.8) end
                    if self._value and self._value~="GUEST" and draftPinned[self._seat] then
                        GameTooltip:AddLine(L("* Pinned Guest: protected from Unlisted assignments"),1,.72,.31)
                    elseif self._value==RGStyle.SETUP_GUEST then
                        GameTooltip:AddLine(L("* Unique nickname-free raid player not in the setup; cannot be overwritten"),1,.72,.31)
                    elseif self._value=="GUEST" then
                        GameTooltip:AddLine(L("* Dynamic Guest: any eligible Guest can occupy this seat"),1,.72,.31)
                    elseif self._value and draftGuest[self._seat] then
                        GameTooltip:AddLine(L("* Guest: replaceable by Unlisted assignments"),1,.72,.31)
                    elseif self._value and (GuestMode(self._value) or previewGuestAnnotations[self._seat]) then
                        GameTooltip:AddLine(L("* Guest: character classified as Guest"),1,.72,.31)
                    end
                    if Enabled("guestFeatures") and Enabled("guestRightClick") then
                        GameTooltip:AddLine(L("Right-click opens slot actions / Guest options"),.7,.7,.7)
                    end
                    GameTooltip:AddLine(L("Shift+click edits this seat"),.7,.7,.7)
                    GameTooltip:Show()
                end
            end)
            s:SetScript("OnLeave",function() GameTooltip:Hide() end)
            slots[index]=s
        end
    end
    dragGhost=CreateFrame("Frame",nil,UIParent)
    dragGhost:SetSize(SLOT_W,SLOT_H)
    dragGhost:SetFrameStrata("TOOLTIP")
    EllesmereUI.SolidTex(dragGhost,"BACKGROUND",.09,.16,.16,.94):SetAllPoints()
    EllesmereUI.MakeBorder(dragGhost,1,1,1,.7,EllesmereUI.PP)
    dragGhost._lbl=Text(dragGhost,11)
    dragGhost._lbl:SetPoint("CENTER")
    dragGhost:Hide()

end
local function EnsureMainWindow()
    if win then return end
    win=Panel("EllesmereUIRaidGroupsWindow",914,465)
    -- Panel creation registers a movable background; main window remembers
    -- the position in the ordinary QoL profile.
    win:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        local p=P()
        if p then
            local point,_,rel,x,y=self:GetPoint()
            p.pos={point=point,relPoint=rel,x=x,y=y}
        end
    end)
    local ar,ag,ab=EllesmereUI.GetAccentColor()
    local title=Text(win,15,"Raid Groups")
    title:SetTextColor(ar,ag,ab)
    title:SetPoint("TOPLEFT",14,-13)
    EllesmereUI.RegAccent({type="callback",fn=function()
        title:SetTextColor(EllesmereUI.GetAccentColor())
        SetChoiceButtonState(exactButton,false,not (data and data.exactPositions),true)
        if splitWindow and splitWindow._refresh then splitWindow._refresh() end
    end})
    dirtyLabel=Text(win,10)
    dirtyLabel:SetPoint("TOPLEFT",14,-36)
    mainHelp=Text(win,10,"Shift+click to edit")
    mainHelp:SetPoint("TOPRIGHT",-205,-36)
    mainHelp:SetTextColor(.72,.75,.78)
    ns._BuildRaidGroupsMainSlots()
    local left=703
    extrasLabel=Text(win,11,"Raid — Unlisted")
    extrasLabel:SetPoint("TOPLEFT",left,-60)
    for i=1,10 do
        local r=CreateFrame("Button",nil,win)
        r:SetSize(184,25)
        r:SetPoint("TOPLEFT",left,-79-(i-1)*26)
        EllesmereUI.SolidTex(r,"BACKGROUND",.12,.15,.17,.8):SetAllPoints()
        r._lbl=Text(r,10)
        RGStyle.MarkPlayerFont(r._lbl,"unlisted")
        r._lbl:SetPoint("LEFT",5,0);r._lbl:SetPoint("RIGHT",-4,0)
        AddLeaderIcon(r)
        r:RegisterForClicks("LeftButtonUp","RightButtonUp")
        r:SetScript("OnClick",function(self,mouseButton)
            if not self._member then return end
            if mouseButton=="RightButton" then
                local playerName=self._member.name
                local actions=GuestMenuActions(playerName)
                actions[#actions+1]={label="Assign to Next Available Slot",action=function()
                    AssignExtra(playerName) end}
                if Enabled("guestFeatures") and Enabled("guestRightClick") then
                    actions[#actions+1]={label="Assign as Pinned Guest",action=function()
                        AssignExtra(playerName,true) end}
                end
                ShowSeatMenu(self,actions)
            else AssignExtra(self._member.name) end
        end)
        r:SetScript("OnEnter",function(self)
            if self._member then
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                GameTooltip:AddLine(LF("%s (not in setup)",self._member.name))
                if Enabled("guestFeatures") and Enabled("guestRightClick") then
                    GameTooltip:AddLine(L("Left: assign • Right: player actions"),.8,.8,.8)
                else
                    GameTooltip:AddLine(L("Left: assign"),.8,.8,.8)
                end
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave",function() GameTooltip:Hide() end)
        extras[i]=r
    end
    local function WheelUnlisted(_,delta)
        if not Enabled("unlistedFeatures") or not Enabled("unlistedList") then return end
        extraOffset=math.max(0,math.min(math.max(0,#UnlistedPlayers()-10),extraOffset-(delta>0 and 1 or -1)))
        RefreshExtras()
    end
    local unlistedWheel=CreateFrame("Frame",nil,win)
    unlistedWheel:SetPoint("TOPLEFT",left,-79)
    unlistedWheel:SetSize(184,259)
    unlistedWheel:EnableMouseWheel(true)
    unlistedWheel:SetScript("OnMouseWheel",WheelUnlisted)
    unlistedWheel:SetFrameLevel(win:GetFrameLevel()+1)
    for _,row in ipairs(extras) do
        row:SetFrameLevel(unlistedWheel:GetFrameLevel()+1)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel",WheelUnlisted)
    end
    win._unlistedScrollbar=RGStyle.ListScrollbar(win,left+186,-79,259,
        function() return extraOffset end,
        function(offset) extraOffset=offset;RefreshExtras() end,
        function()
            if not Enabled("unlistedFeatures") or not Enabled("unlistedList") then return 0 end
            return math.max(0,#UnlistedPlayers()-10)
        end)
    listModeButton=Button(win,"Raid / Guild",195,21,function()
        listGuild=not listGuild
        extraOffset=0
        if listGuild and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        RefreshExtras()
    end)
    listModeButton:SetPoint("TOPLEFT",left,-349)
    unlistedButtons={listModeButton}

    -- Buttons reflow in a fixed 914px window. Hiding Split Raid, Backup,
    -- Current Roster or Clear Draft never leaves empty horizontal gaps.
    local footerY=-384
    local function AddFooterButton(text,width,action,visibility,kind)
        local b=Button(win,text,width,25,action)
        footerControls[#footerControls+1]={button=b,visible=visibility}
        if kind=="apply" then applyButton=b end
        return b
    end
    local currentButton=AddFooterButton("Current Roster",120,FromRoster,
        function() return Enabled("editorTools") and Enabled("editorCurrentRoster") end)
    editorButtons[#editorButtons+1]={button=currentButton,option="editorCurrentRoster"}
    AddFooterButton("Apply Groups",115,RequestApply,nil,"apply")
    local previewButton=AddFooterButton("Preview Apply Groups",159,RequestPreview)
    ColorPreviewButton(previewButton)
    local setupManagerButton=AddFooterButton("Raid Group Setup",132,ShowSetupWindow)
    SetChoiceButtonState(setupManagerButton,true,false,true)
    AddFooterButton("Nicknames",103,ShowNickWindow)
    AddFooterButton("Import",91,function() TransferWindow(true) end)
    AddFooterButton("Export",91,function() TransferWindow(false) end)
    local splitNow=AddFooterButton("Split Raid",97,SplitDraft,
        function() return Enabled("splitRaidEnabled") end)
    local splitSettings=AddFooterButton("Split Settings",112,ShowSplitWindow,
        function() return Enabled("splitRaidEnabled") end)
    splitButtons={splitNow,splitSettings}
    local exact=AddFooterButton("Exact Positions: OFF",153,function(self)
        data.exactPositions=not data.exactPositions
        self._lbl:SetText(L(data.exactPositions and "Exact Positions: ON" or "Exact Positions: OFF"))
        SetChoiceButtonState(self,false,not data.exactPositions,true)
    end)
    exactButton=exact
    exact._lbl:SetText(L(data.exactPositions and "Exact Positions: ON" or "Exact Positions: OFF"))
    SetChoiceButtonState(exact,false,not data.exactPositions,true)
    local clearButton=AddFooterButton("Clear Draft",101,function()
        Confirm("Clear all 40 planned raid group seats?",function()
            PushUndo(); draft={};draftPinned={};draftGuest={};RGStyle.emptyPinnedDraft={};removedGuestKeys={};selectedSetup=nil;RGStyle.setupLoadToggle=nil;SaveEdit()
        end)
    end,function() return Enabled("editorTools") and Enabled("editorClearDraft") end)
    editorButtons[#editorButtons+1]={button=clearButton,option="editorClearDraft"}
    AddFooterButton("Undo Draft",97,UndoDraft)
    AddFooterButton("Redo Draft",97,RGStyle.RedoDraft,
        function() return Enabled("editorTools") and Enabled("editorRedoDraft") end)
    AddFooterButton("Backup",91,ShowBackupWindow,function() return Enabled("backupEnabled") end)
    statusLabel=Text(win,10,"Changes stay provisional until Apply Groups.")
    statusLabel:SetPoint("TOPLEFT",14,-452)
    statusLabel:SetTextColor(.8,.78,.6)
end
function ns.ApplyRaidGroupsScale()
    if win then RGStyle.ApplyPanelScale(win,"main") end
end
function ns.RaidGroupsScale(value)
    return ns.RaidGroupsWindowScale("main",value)
end
function ns.RaidGroupsShowNicknames(value)
    local p=P()
    if value==nil then return not p or p.showNicknames~=false end
    if p then p.showNicknames=value and true or false end
    if win and win:IsShown() then Refresh() end
end
function ns.ShowRaidGroupsWindow()
    if not data then Defaults() end
    EnsureMainWindow()
    if win:IsShown() then win:Hide(); return end
    ns.ApplyRaidGroupsScale()
    win:ClearAllPoints()
    local p=P()
    local pos=p and p.pos
    if pos and pos.point then win:SetPoint(pos.point,UIParent,pos.relPoint or pos.point,pos.x or 0,pos.y or 0)
    else win:SetPoint("CENTER") end
    win:Show()
    ApplyFonts()
    if not firstDraftLoaded then
        -- A setup loaded through /euirg before this window was ever opened is
        -- already a valid draft; do not replace it with the current roster.
        if not selectedSetup and not next(draft) then
            FromRoster(true)
            dirty=false
        end
        firstDraftLoaded=true
    end
    Refresh()
end

-------------------------------------------------------------------------------
-- Lifecycle. The account-wide nickname/setup store survives QoL profile
-- changes, and no nickname is inferred from a name-only invite import.
-------------------------------------------------------------------------------
-- Raid Frames and Unit Frames already subscribe for display refreshes.
-- Raid Groups needs its own lightweight listener solely to persist *confirmed*
-- changes in its account-wide history; those display-only listeners cannot do it.
-- Reuse NSRT's public NSAPI registration contract, not its internal namespace.
local function RegisterRaidNicknameUpdates()
    if nsrtRegistered or not data then return end
    local api = _G.NSAPI
    if not api or type(api.RegisterCallback) ~= "function" then return end
    local function OnNickname(_, all, unit, name, realm, oldnick, newnick)
        if not data or not Enabled("nicknameLearning") or not Enabled("nicknameNSRTUpdates")
            or not SafeText(name) or not SafeText(realm) then return end
        local full=name.."-"..realm
        local key=Canonical(full)
        if not key then return end
        -- Only an explicit empty string from a character-specific update is
        -- evidence sharing stopped. A global refresh may pass nil instead.
        if newnick=="" then
            if not all and data.nicknames[key] and data.nicknameSharing[key]~="stopped" then
                data.nicknameSharing[key]="stopped"
                Notice(LF("Nickname sharing stopped: %s stopped sharing %s. Saved nickname retained.",
                    FullName(full),SavedNickname(full) or SafeText(oldnick) or ""),"nickname")
            end
            return
        end
        if not SafeText(newnick) or Trim(newnick)=="" then return end
        local stored=StoreNickname(full,newnick,false,"NSRT event",true)
        if data.nicknames[key] then data.nicknameSharing[key]="sharing" end
        -- No chat notification for adding another character to an existing
        -- group; RenameNicknameGroup is the single change-notification path.
        if stored then
            if RefreshNicknames then RefreshNicknames() end
            if Refresh then Refresh() end
        end
    end
    -- CallbackHandler keys each subscriber by this stable, distinct identifier.
    local ok = pcall(api.RegisterCallback, "EllesmereUIRaidGroups",
        "NSRT_NICKNAME_UPDATED", OnNickname)
    if ok then nsrtRegistered = true end
end
local boot=CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent",function(self)
    self:UnregisterAllEvents()
    if not (EllesmereUI and EllesmereUI.Lite and EllesmereUI.Lite.NewDB) then return end
    Defaults()
    MigrateSetupNicknameSnapshots()
    db=EllesmereUI.Lite.NewDB("EllesmereUIQoLDB",DEFAULTS,true)
    if not EllesmereUI._onScaleChanged then EllesmereUI._onScaleChanged={} end
    EllesmereUI._onScaleChanged[#EllesmereUI._onScaleChanged+1]=ns.ApplyRaidGroupsScale
    -- NSRT may be loaded before or after EUI; both paths are supported.
    RegisterRaidNicknameUpdates()
    -- Current draft is intentionally session-local. Named setups are persisted.
    Roster()
end)
local events=CreateFrame("Frame")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PARTY_LEADER_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent",function(self,event,addonName)
    if not data then return end
    if event=="GUILD_ROSTER_UPDATE" and promptWindow and promptWindow:IsShown() and
        promptWindow._guildAutocomplete then
        RGStyle.UpdateGuildCompletion(promptWindow._edit,true)
    end
    if event=="ADDON_LOADED" then
        if addonName=="NorthernSkyRaidTools" then
            RegisterRaidNicknameUpdates()
            if nsrtRegistered then self:UnregisterEvent("ADDON_LOADED") end
        end
        return
    end
    if event=="PLAYER_REGEN_DISABLED" then
        if applyState then StopApply();WarnCombat(true) end
        -- Dismiss every Raid Groups-owned panel only on the combat transition.
        -- The frames remain insecure and may be opened again during combat.
        -- Keep both editors' underlying data: hiding is not Cancel/Reset.
        if previewWindow and previewWindow:IsShown() and previewDraftState then
            RGStyle.previewSuspendedForCombat=true
        end
        if previewWindow then previewWindow._drag=nil end
        StopDrag() -- prevent a drag ghost (parented to UIParent) remaining visible
        if win and win._groupHeaders then
            for _,header in ipairs(win._groupHeaders) do
                header._groupDragging=nil
                header._lbl:SetAlpha(1)
            end
        end
        if seatMenuOverlay then seatMenuOverlay:Hide() end
        for _,panel in pairs(RGStyle.panels) do
            if panel:IsShown() then
                panel:StopMovingOrSizing()
                panel:Hide()
            end
        end
        return
    end
    if event=="GROUP_ROSTER_UPDATE" or event=="PARTY_LEADER_CHANGED" then
        Roster()
        if applyState then QueueApply() end
    end
    if win and win:IsShown() then Refresh() end
end)
-- A slash alias identifies a saved setup without changing its displayed name.
-- Only cosmetic punctuation/spacing and common Latin accents are folded; this
-- deliberately does not perform fuzzy or partial matches.
local SETUP_FOLD = {
    ["á"]="a",["à"]="a",["â"]="a",["ã"]="a",["ä"]="a",["å"]="a",
    ["Á"]="a",["À"]="a",["Â"]="a",["Ã"]="a",["Ä"]="a",["Å"]="a",
    ["é"]="e",["è"]="e",["ê"]="e",["ë"]="e",
    ["É"]="e",["È"]="e",["Ê"]="e",["Ë"]="e",
    ["í"]="i",["ì"]="i",["î"]="i",["ï"]="i",
    ["Í"]="i",["Ì"]="i",["Î"]="i",["Ï"]="i",
    ["ó"]="o",["ò"]="o",["ô"]="o",["õ"]="o",["ö"]="o",
    ["Ó"]="o",["Ò"]="o",["Ô"]="o",["Õ"]="o",["Ö"]="o",
    ["ú"]="u",["ù"]="u",["û"]="u",["ü"]="u",
    ["Ú"]="u",["Ù"]="u",["Û"]="u",["Ü"]="u",
    ["ç"]="c",["Ç"]="c",["ñ"]="n",["Ñ"]="n",["ý"]="y",["Ý"]="y",
    ["’"]="",["‘"]="",["´"]="",["`"]="",[" "]="",
}
local function SetupAliasKey(value)
    value=Trim(value or "")
    for character, folded in pairs(SETUP_FOLD) do
        value=value:gsub(character,folded)
    end
    return (value:lower():gsub("[%s%p]", ""))
end
local function FindSavedSetupByAlias(name)
    if not data or type(data.setups)~="table" then return nil,"unavailable" end
    name=Trim(name or "")
    if name=="" then return nil,"missing" end
    -- Preserve precedence for an exact spelling when two setups normalize
    -- to the same alias. Ambiguous shorthand must never apply a random setup.
    for i,setup in ipairs(data.setups) do
        if type(setup.name)=="string" and setup.name:lower()==name:lower() then
            return i
        end
    end
    local alias=SetupAliasKey(name)
    if alias=="" then return nil,"missing" end
    local index
    for i,setup in ipairs(data.setups) do
        if type(setup.name)=="string" and SetupAliasKey(setup.name)==alias then
            if index then return nil,"ambiguous" end
            index=i
        end
    end
    return index, index and nil or "missing"
end
local function ApplySavedSetupByAlias(name, reportMissing)
    local index,reason=FindSavedSetupByAlias(name)
    if index then
        LoadSetup(index)
        RequestApply()
        return true
    end
    if reason=="ambiguous" then
        Notice(LF("Ambiguous setup name: %s. Use its exact saved name.",name))
        return true
    end
    if reportMissing then
        Notice(LF("Setup not found: %s",name))
        return true
    end
    return false
end
-- Saved setup shortcuts are intentionally scoped to /euirg only.
SLASH_EUIRAIDGROUPS1="/euirg"
SlashCmdList.EUIRAIDGROUPS=function(arg)
    arg=Trim(arg or "")
    if arg=="" then
        ns.ShowRaidGroupsWindow()
        return
    end
    if arg:lower()=="apply" then
        Notice("Usage: /euirg [apply] <setup name>")
        return
    end
    local name=arg:match("^[Aa][Pp][Pp][Ll][Yy]%s+(.+)$") or arg
    ApplySavedSetupByAlias(name,true)
end
