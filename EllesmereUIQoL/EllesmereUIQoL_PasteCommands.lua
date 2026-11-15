if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- /euipaste runs a pasted block of /way lines. Off by default and reload-gated.
if not (EllesmereUIDB and EllesmereUIDB.pasteCommands == true) then return end

local ns  = select(2, ...)
local EUI = EllesmereUI

local SLASH      = "/euipaste"
local OWN_KEY    = "EUIPASTE"
local MACRO_NAME = "EUI_Paste"
local PREFIX     = EUI.COLOR_CODES.BRAND .. "EllesmereUI:|r "
-- Run executes inside our click, so a blocked or tainting command would be blamed on EllesmereUI.
local ALLOWED    = { ["/WAY"] = true, ["/EUIWAY"] = true }

local function Say(msg) EUI.Print(PREFIX .. msg) end

local function SplitLines(text)
    local lines = {}
    for line in (text:gsub("\r\n?", "\n") .. "\n"):gmatch("(.-)\n") do
        line = strtrim(line)
        if line ~= "" then lines[#lines + 1] = line end
    end
    return lines
end

-- The chat code moves commands it has imported into hash_SlashCmdList; the rest wait in SlashCmdList.
local function LookupCommand(upper)
    local handler = hash_SlashCmdList and hash_SlashCmdList[upper]
    if handler then
        local key = hash_ChatTypeInfoList and hash_ChatTypeInfoList[upper]
        if type(key) == "string" then return key, handler end
        -- Some clients import the function into the hash table but omit its
        -- owner key. Recover the declared alias before checking security.
        for name in pairs(SlashCmdList) do
            local i, alias = 1, _G["SLASH_" .. name .. "1"]
            while type(alias) == "string" do
                if alias:upper() == upper then return name, handler end
                i = i + 1
                alias = _G["SLASH_" .. name .. i]
            end
        end
        return nil, handler
    end
    for key, fn in pairs(SlashCmdList) do
        local i, alias = 1, _G["SLASH_" .. key .. "1"]
        while type(alias) == "string" do
            if alias:upper() == upper then return key, fn end
            i = i + 1
            alias = _G["SLASH_" .. key .. i]
        end
    end
end

-- The handler of whichever addon owns the command, or nil when nothing does; a secure alias means
-- Blizzard's, which is never called.
local function WaypointOwner(upper)
    local key, handler = LookupCommand(upper)
    if key and not issecurevariable("SLASH_" .. key .. "1") then return handler end
end

-- WoW runs Lua 5.1: xpcall does not forward extra arguments portably.
-- Capture the slash parameters explicitly so external and EUI handlers both
-- receive the actual waypoint text (not nil).
local function CallCommand(handler, args, editBox)
    return xpcall(function() handler(args, editBox) end, geterrorhandler())
end

local function Run(text)
    local lines, skipped, unowned = SplitLines(text), 0, 0
    -- The owner post-hook must not print a second set of links for commands
    -- executed through Paste. One combined pass at the bottom prints those.
    ns._pasteWaypointRunning = true
    local editBox = DEFAULT_CHAT_FRAME.editBox
    local ours = ns.WaypointHandle  -- our own /way handler, while enabled
    local list                      -- our own lines, handed over in one call
    local linkList = {}             -- every valid line, in original input order
    for _, line in ipairs(lines) do
        local cmd, args = line:match("^(/%S+)%s*(.-)$")
        local upper = cmd and cmd:upper()
        if not (upper and ALLOWED[upper]) then
            skipped = skipped + 1
        else
            local handler = WaypointOwner(upper)
            if ours and handler == ours then
                list = list or {}
                list[#list + 1] = args
            elseif handler then
                -- External owners still receive their original slash lines.
                CallCommand(handler, args, editBox)
            elseif not ns.WaypointPasteLinks then
                unowned = unowned + 1
            end
            if ns.WaypointPasteLinks then
                linkList[#linkList + 1] = args
            end
        end
    end
    -- Our route is registered once, silently, preserving arrival tracking.
    -- A single read-only pass prints EVERY link in the pasted order, including
    -- /way lines owned by other addons; it does not move the user's map pin.
    if list then CallCommand(ns.WaypointPasteRoute or ours, table.concat(list, " ; "), editBox) end
    if #linkList > 0 then
        CallCommand(ns.WaypointPasteLinks, table.concat(linkList, " ; "), editBox)
    end
    if unowned > 0 then
        Say(EllesmereUI.L("Some waypoint lines could not run: nothing handles their command. Turn on Enable /way Command."))
    end
    if skipped > 0 then
        Say(EllesmereUI.Lf("Skipped %1$d of %2$d lines: only /way and /euiway waypoint lines can be pasted.", skipped, #lines))
    end
    ns._pasteWaypointRunning = nil
end

-- The window is built once (keep) and shown again with an empty box.
local function Open()
    EUI:ShowImportPopup(Run, EllesmereUI.L("Paste Waypoints"),
        EllesmereUI.L("Paste /way or /euiway lines, one waypoint per line"),
        { confirmLabel = "Run", rawPaste = true, keep = "pasteWaypoints" })
end

-- The macro is the action bar button: created once, then handed to the cursor to drop on a bar.
function EUI._createPasteMacro()
    if InCombatLockdown() then
        Say(EllesmereUI.L("Leave combat to create the macro."))
        return
    end
    if GetMacroIndexByName(MACRO_NAME) == 0 then
        if GetNumMacros() >= Constants.MacroConsts.MAX_ACCOUNT_MACROS then
            Say(EllesmereUI.L("All account macro slots are in use. Delete one to create the macro."))
            return
        end
        CreateMacro(MACRO_NAME, "INV_Misc_Note_01", SLASH, nil)
    end
    -- Found again by name: other addons' macro event handlers run inside CreateMacro and may reorder the list.
    local index = GetMacroIndexByName(MACRO_NAME)
    if index > 0 then PickupMacro(index) end
end

-- When another addon (Waypoint UI, TomTom, etc.) owns /way, directly
-- typing /way in chat bypasses our own handler. Attach one secure post-hook
-- to the actual slash dispatcher, without replacing the existing function.
-- Imported slash entries live in hash_SlashCmdList; other entries still live
-- in SlashCmdList. Only the active dispatch entry is hooked.
local directWayHooked = false
local function HookExternalWay()
    if directWayHooked or not ns.WaypointChatLinks or not hooksecurefunc then return end
    local key, handler = LookupCommand("/WAY")
    if type(handler) ~= "function" or handler == ns.WaypointHandle then return end
    local target, name
    if hash_SlashCmdList and type(hash_SlashCmdList["/WAY"]) == "function" then
        target, name = hash_SlashCmdList, "/WAY"
    elseif key and type(SlashCmdList[key]) == "function" then
        target, name = SlashCmdList, key
    end
    if not target then return end
    local function AfterExternalWay(msg)
        if type(msg) == "string" then ns.WaypointChatLinks(msg) end
    end
    directWayHooked = pcall(hooksecurefunc, target, name, AfterExternalWay)
    -- Imported entries are normally hookable, but allow the registered owner
    -- as a fallback if the client protects its imported dispatch table.
    if not directWayHooked and target ~= SlashCmdList and key
        and type(SlashCmdList[key]) == "function" then
        directWayHooked = pcall(hooksecurefunc, SlashCmdList, key, AfterExternalWay)
    end
end

-- One frame after loading, so a /paste another addon registers at load or login is seen.
C_Timer.After(0, function()
    SLASH_EUIPASTE1 = SLASH
    local _, taken = LookupCommand("/PASTE")
    if not taken then SLASH_EUIPASTE2 = "/paste" end
    SlashCmdList[OWN_KEY] = Open
    HookExternalWay()
end)

-- Support addons that register their slash commands at PLAYER_LOGIN rather
-- than ADDON_LOADED. No persistent events or polling once a hook is attached.
local hookEvent = CreateFrame("Frame")
hookEvent:RegisterEvent("PLAYER_LOGIN")
hookEvent:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    HookExternalWay()
end)
