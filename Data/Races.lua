local L = LibStub("AceLocale-3.0"):GetLocale("WoWLarn")
local _, ns = ...

-- Pre-made characters for the race pick: the display ids of a dressed non-player character of
-- every playable race (retail data, so the allied races are there too), by the race token that
-- UnitRace gives.  { male, female }.  (The models of the character creation have no textures
-- without a customization, so these are creature displays, the earliest plain ones.)
ns.RaceModels = {
   Human = { 1276, 176 },
   Orc = { 1139, 1312 },
   Dwarf = { 115, 1286 },
   NightElf = { 1285, 1543 },
   Scourge = { 1027, 1029 },
   Tauren = { 1624, 1905 },
   Gnome = { 1832, 1890 },
   Troll = { 1976, 1882 },
   Goblin = { 6882, 7175 },
   BloodElf = { 4471, 15505 },
   Draenei = { 16199, 16200 },
   Worgen = { 30164, 31689 },
   Pandaren = { 39574, 39705 },
   Nightborne = { 81832, 81847 },
   HighmountainTauren = { 81848, 81849 },
   VoidElf = { 80975, 80977 },
   LightforgedDraenei = { 76240, 76338 },
   ZandalariTroll = { 15003, 14996 },
   KulTiran = { 78517, 77936 },
   DarkIronDwarf = { 8803, 69941 },
   Vulpera = { 78401, 79314 },
   MagharOrc = { 86324, 86325 },
   Mechagnome = { 90771, 90797 },
   Dracthyr = { 104619, 105018 },
   EarthenDwarf = { 114403, 114678 },
   Haranir = { 117229, 117243 },
   Harronir = { 117229, 117243 },
   -- Forever, from the NPCs Tel'daeor the Stormspeaker (259385) and Ayessa Dawnsinger (253849);
   -- which is a man and which a woman is a guess from the names
   Skyborne = { 141474, 137633 }, SkyborneElf = { 141474, 137633 },
}

-- The races to pick from, by name; the token is that of UnitRace.
local NAMES = {
   Human = L["Human"], Orc = L["Orc"], Dwarf = L["Dwarf"], NightElf = L["Night Elf"], Scourge = L["Undead"],
   Tauren = L["Tauren"], Gnome = L["Gnome"], Troll = L["Troll"], Goblin = L["Goblin"], BloodElf = L["Blood Elf"],
   Draenei = L["Draenei"], Worgen = L["Worgen"], Pandaren = L["Pandaren"], Nightborne = L["Nightborne"],
   HighmountainTauren = L["Highmountain Tauren"], VoidElf = L["Void Elf"], LightforgedDraenei = L["Lightforged Draenei"],
   ZandalariTroll = L["Zandalari Troll"], KulTiran = L["Kul Tiran"], DarkIronDwarf = L["Dark Iron Dwarf"],
   Vulpera = L["Vulpera"], MagharOrc = L["Mag'har Orc"], Mechagnome = L["Mechagnome"], Dracthyr = L["Dracthyr"],
   EarthenDwarf = L["Earthen"], Haranir = L["Haranir"], Skyborne = L["Skyborne Elf"],
}
ns.RaceNames = NAMES

-- Which races the client has.  Retail has them all (the Skyborne elves aside); the others have
-- the races of their expansion: the classic ones, the ones of The Burning Crusade (blood
-- elves, draenei), of Cataclysm (goblins, worgen) and of Mists of Pandaria (pandaren).  The
-- Skyborne elves are only in Forever (interface 16xxx).
local build = select(4, GetBuildInfo()) or 0
local FOREVER = build >= 16000 and build < 17000
local MAINLINE = WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local EXPANSION = {  -- (the expansion that has it; races not here are retail only)
   Human = 0, Orc = 0, Dwarf = 0, NightElf = 0, Scourge = 0, Tauren = 0, Gnome = 0, Troll = 0,
   BloodElf = 1, Draenei = 1, Goblin = 3, Worgen = 3, Pandaren = 4,
}
local level = not FOREVER and GetClassicExpansionLevel and GetClassicExpansionLevel() or 0  -- (Forever is Classic, with the Skyborne)
function ns.RaceAvailable(token)
   if token == "Skyborne" then return FOREVER end
   if MAINLINE then return true end
   return EXPANSION[token] ~= nil and EXPANSION[token] <= level
end

ns.RaceList = {}
for token, name in pairs(NAMES) do
   if ns.RaceAvailable(token) then ns.RaceList[#ns.RaceList + 1] = { token, name } end
end
table.sort(ns.RaceList, function(a, b) return a[2] < b[2] end)
