if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Realm names used by the Invite List to fix wrong realms in pasted names
-- (Bartilas -> Barthilas, zuljin -> Zul'jin).
--
-- The list below is the one to edit: add or remove realms here. Spaces are
-- dropped when a name is written ("Argent Dawn" -> "ArgentDawn"), because that
-- is how the client wants them in an invite; apostrophes, hyphens and accents
-- stay as written here.
---@class InviteTools
local _, ns = ...
local InviteTools = ns.InviteTools
if not InviteTools then return end

local REALMS = {
    "Aegwynn",
    "Aerie Peak",
    "Agamaggan",
    "Aggramar",
    "Aggra",
    "Ahn'Qiraj",
    "Akama",
    "Al'Akir",
    "Alonsus",
    "Alexstrasza",
    "Alleria",
    "Alterac Mountains",
    "Aman'Thul",
    "Ambossar",
    "Andorhal",
    "Anetheron",
    "Antonidas",
    "Anub'arak",
    "Arak-arahm",
    "Arathi",
    "Archimonde",
    "Argent Dawn",
    "Area 52",
    "Arthas",
    "Arathor",
    "Arygos",
    "Aszune",
    "Auchindoun",
    "Azuremyst",
    "Azjol-Nerub",
    "Azralon",
    "Azshara",
    "Baelgun",
    "Balnazzar",
    "Barthilas",
    "Black Dragonflight",
    "Blackhand",
    "Blackrock",
    "Blackwater Raiders",
    "Blackwing Lair",
    "Blade's Edge",
    "Bladefist",
    "Bloodfeather",
    "Bloodhoof",
    "Bloodscalp",
    "Blutkessel",
    "Boulderfist",
    "Borean Tundra",
    "Bonechewer",
    "Bronze Dragonflight",
    "Bronzebeard",
    "Burning Blade",
    "Burning Legion",
    "Burning Steppes",
    "Caelestrasz",
    "Cairne",
    "Cenarion Circle",
    "Chamber of Aspects",
    "Chants éternels",
    "Cho'gall",
    "Chromaggus",
    "Coilfang",
    "Confrérie du Thorium",
    "Conseil des Ombres",
    "Crushridge",
    "Culte de la Rive Noire",
    "Daggerspine",
    "Dalaran",
    "Dalvengyr",
    "Dark Iron",
    "Darkmoon Faire",
    "Darksorrow",
    "Darkspear",
    "Deathwing",
    "Demon Soul",
    "Dentarg",
    "Der abyssische Rat",
    "Der Mithrilorden",
    "Der Rat von Dalaran",
    "Der Syndikat",
    "Destromath",
    "Dethecus",
    "Detheroc",
    "Doomhammer",
    "Draka",
    "Drakkari",
    "Drak'thul",
    "Draenor",
    "Dragonblight",
    "Dragonmaw",
    "Dreadmaul",
    "Drek'Thar",
    "Dun Morogh",
    "Dunemaul",
    "Durotan",
    "Duskwood",
    "Dath'Remar",
    "Earthen Ring",
    "Echo Isles",
    "Echsenkessel",
    "Eitrigg",
    "Eldre'Thalas",
    "Emerald Dream",
    "Emeriss",
    "Elune",
    "Eonar",
    "Eredar",
    "Exarche",
    "Executus",
    "Exodar",
    "Farstriders",
    "Feathermoon",
    "Fenris",
    "Festung der Stürme",
    "Firetree",
    "Fizzcrank",
    "Frostmane",
    "Frostmourne",
    "Frostwhisper",
    "Frostwolf",
    "Gallywix",
    "Galakrond",
    "Garithos",
    "Garona",
    "Garrosh",
    "Genjuros",
    "Ghostlands",
    "Gilneas",
    "Gnomeregan",
    "Gorefiend",
    "Gorgonnash",
    "Greymane",
    "Grim Batol",
    "Grizzly Hills",
    "Gundrak",
    "Gul'dan",
    "Gurubashi",
    "Hakkar",
    "Haomarush",
    "Hellfire",
    "Hellscream",
    "Hyjal",
    "Hydraxis",
    "Icecrown",
    "Illidan",
    "Jaedenar",
    "Jubei'Thos",
    "Kael'thas",
    "Kael'Thas",
    "Kargath",
    "Karazhan",
    "Kazzak",
    "Khadgar",
    "Khaz Modan",
    "Khaz'goroth",
    "Kel'Thuzad",
    "Kirin Tor",
    "Korgall",
    "Krasus",
    "Krag'jin",
    "Kul Tiras",
    "La Croisade écarlate",
    "Laughing Skull",
    "Lethon",
    "Les Clairvoyants",
    "Les Sentinelles",
    "Lightbringer",
    "Lightninghoof",
    "Lightning's Blade",
    "Llane",
    "Lordaeron",
    "Lothar",
    "Madoran",
    "Madmortem",
    "Maelstrom",
    "Magtheridon",
    "Mal'Ganis",
    "Malfurion",
    "Malorne",
    "Malygos",
    "Mannoroth",
    "Marécage de Zangar",
    "Mazrigos",
    "Medivh",
    "Misha",
    "Molten Core",
    "Moon Guard",
    "Moonrunner",
    "Moonglade",
    "Mug'thol",
    "Muradin",
    "Nagrand",
    "Nathrezim",
    "Nazgrel",
    "Nazjatar",
    "Naxxramas",
    "Nefarian",
    "Nera'thor",
    "Ner'zhul",
    "Neptulon",
    "Nesingwary",
    "Nethersturm",
    "Nemesis",
    "Norgannon",
    "Nordrassil",
    "Nozdormu",
    "Onyxia",
    "Outland",
    "Perenolde",
    "Proudmoore",
    "Quel'Thalas",
    "Quel'Dorei",
    "Ragnaros",
    "Rashgarroth",
    "Ravencrest",
    "Ravenholdt",
    "Rexxar",
    "Rivendare",
    "Runetotem",
    "Sargeras",
    "Saurfang",
    "Scilla",
    "Scarlet Crusade",
    "Sen'jin",
    "Sentinels",
    "Shadow Council",
    "Shadowmoon",
    "Shadowsong",
    "Shattered Halls",
    "Shattered Hand",
    "Silver Hand",
    "Silvermoon",
    "Sinstralis",
    "Sisters of Elune",
    "Skywall",
    "Skullcrusher",
    "Smolderthorn",
    "Spinebreaker",
    "Sporeggar",
    "Staghelm",
    "Steamwheedle Cartel",
    "Stormrage",
    "Stormreaver",
    "Stormscale",
    "Sunstrider",
    "Suramar",
    "Sylvanas",
    "Talnivarr",
    "Tanaris",
    "Tarren Mill",
    "Teldrassil",
    "Terokkar",
    "Terenas",
    "Terrordar",
    "The Maelstrom",
    "The Scryers",
    "The Sha'tar",
    "The Underbog",
    "The Venture Co",
    "Theradras",
    "Thorium Brotherhood",
    "Thaurissan",
    "Thunderhorn",
    "Thunderlord",
    "Tichondrius",
    "Tirion",
    "Tol Barad",
    "Tortheldrin",
    "Turalyon",
    "Twisting Nether",
    "Twilight's Hammer",
    "Uldaman",
    "Uldum",
    "Ulduar",
    "Undermine",
    "Un'Goro",
    "Ursin",
    "Uther",
    "Vashj",
    "Vek'nilash",
    "Vek'lor",
    "Velen",
    "Varimathras",
    "Warsong",
    "Whisperwind",
    "Wildhammer",
    "Windrunner",
    "Winterhoof",
    "Wrathbringer",
    "Wyrmrest Accord",
    "Xavius",
    "Ysera",
    "Ysondre",
    "Zangarmarsh",
    "Zenedar",
    "Zul'jin",
    "Zuluhed",
}

local RN = {}
InviteTools.RealmNames = RN

------------------------------------------------------------------------
-- Matching
------------------------------------------------------------------------

-- Accented letters (UTF-8, lead byte 195) folded to plain ones.
local FOLD = { [159] = "ss" }
for letter, bytes in pairs({
    a = { 128, 129, 130, 131, 132, 133, 160, 161, 162, 163, 164, 165 },
    c = { 135, 167 },
    e = { 136, 137, 138, 139, 168, 169, 170, 171 },
    i = { 140, 141, 142, 143, 172, 173, 174, 175 },
    n = { 145, 177 },
    o = { 146, 147, 148, 149, 150, 178, 179, 180, 181, 182 },
    u = { 153, 154, 155, 156, 185, 186, 187, 188 },
    y = { 157, 189, 191 },
}) do
    for _, b in ipairs(bytes) do FOLD[b] = letter end
end

-- Case, spaces, apostrophes, hyphens and accents do not matter when comparing.
local function Key(s)
    s = s:gsub("\195(.)", function(c) return FOLD[c:byte()] end)
    s = s:lower():gsub("[^%w]", "")
    return s
end
RN.Key = Key

-- Edit distance with swapped neighbours counting as one change; gives up (and
-- returns max + 1) as soon as it is clear the distance exceeds `max`.
local function Distance(a, b, max)
    local la, lb = #a, #b
    if math.abs(la - lb) > max then return max + 1 end
    local prev2, prev, cur = {}, {}, {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        cur[0] = i
        local rowMin = cur[0]
        local ca = a:byte(i)
        for j = 1, lb do
            local cost = (ca == b:byte(j)) and 0 or 1
            local v = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            if i > 1 and j > 1 and ca == b:byte(j - 1) and a:byte(i - 1) == b:byte(j) then
                v = math.min(v, prev2[j - 2] + 1)
            end
            cur[j] = v
            if v < rowMin then rowMin = v end
        end
        if rowMin > max then return max + 1 end
        prev2, prev, cur = prev, cur, prev2
    end
    return prev[lb]
end

local byKey, entries
local function Build()
    if byKey then return end
    byKey, entries = {}, {}
    for _, name in ipairs(REALMS) do
        local k = Key(name)
        if k ~= "" and not byKey[k] then
            local canon = name:gsub("%s+", "")
            byKey[k] = canon
            entries[#entries + 1] = { key = k, canon = canon }
        end
    end
end

-- Returns the correct spelling for `input` and how it was found:
--   "exact"  same realm, just written differently (case, apostrophe, spaces)
--   "fuzzy"  a typo, fixed because exactly one realm is that close
-- Returns nil when the realm is unknown, or when two realms are equally close
-- (it does not guess).
function RN.Resolve(input)
    if type(input) ~= "string" then return nil end
    Build()
    local k = Key(input)
    if k == "" then return nil end

    local exact = byKey[k]
    if exact then return exact, "exact" end

    local len = #k
    local max = (len <= 4) and 0 or ((len <= 7) and 1 or 2)
    if max == 0 then return nil end

    local best, bestCanon, ties = max + 1, nil, 0
    for _, e in ipairs(entries) do
        local d = Distance(k, e.key, max)
        if d < best then
            best, bestCanon, ties = d, e.canon, 1
        elseif d == best and e.canon ~= bestCanon then
            ties = ties + 1
        end
    end
    if best <= max and ties == 1 then
        return bestCanon, "fuzzy"
    end
    return nil
end
