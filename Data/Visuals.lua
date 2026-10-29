--[[
**********************************************************************
WoWLarn - Object visuals.
**********************************************************************
Copyright (C) 2026 NeoTron

This file is part of WoWLarn, a World of Warcraft Addon

WoWLarn is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 2 of the License.

WoWLarn is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with WoWLarn.  If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0.html>.

**********************************************************************
]]
local _, ns = ...
local K = ns.K
local L = LibStub("AceLocale-3.0"):GetLocale("WoWLarn")

-- How things are drawn. Every object id has an ASCII glyph (Tables.objglyphs); icons are
-- optional. The icon names are placeholders: they are checked in game and curated later.
local V = {}
ns.Visuals = V

local ICONS = "Interface\\Icons\\"

V.object = {
   [K.OENTRANCE] = { icon = "INV_Misc_Map_01" },
   [K.ODNDSTORE] = { icon = "INV_Sword_04" },
   [K.OSCHOOL] = { icon = "INV_Misc_Book_09" },
   [K.OBANK] = { icon = "INV_Misc_Coin_01" },
   [K.OVOLDOWN] = { icon = "Spell_Fire_SelfDestruct" },
   [K.OHOME] = { icon = "INV_Misc_Key_03" },
   [K.OTRADEPOST] = { icon = "INV_Misc_Bag_08" },
   [K.OLRS] = { icon = "INV_Misc_Note_01" },
   -- items (placeholders)
   [K.OPOTION] = { icon = "INV_Potion_54" },
   [K.OSCROLL] = { icon = "INV_Scroll_03" },
   [K.OBOOK] = { icon = "INV_Misc_Book_09" },
   [K.OCOOKIE] = { icon = "INV_Misc_Food_15" },
   [K.OGOLDPILE] = { icon = "INV_Misc_Coin_01" },
   [K.ODGOLD] = { icon = "INV_Misc_Coin_01" },
   [K.OMAXGOLD] = { icon = "INV_Misc_Coin_01" },
   [K.OKGOLD] = { icon = "INV_Misc_Coin_01" },
   [K.ODIAMOND] = { icon = "INV_Misc_Gem_Diamond_01" },
   [K.ORUBY] = { icon = "INV_Misc_Gem_Ruby_01" },
   [K.OEMERALD] = { icon = "INV_Misc_Gem_Emerald_01" },
   [K.OSAPPHIRE] = { icon = "INV_Misc_Gem_Sapphire_01" },
   [K.OCHEST] = { icon = "INV_Box_01" },
   [K.ODAGGER] = { icon = "INV_Weapon_ShortBlade_01" },
   [K.OSPEAR] = { icon = "INV_Spear_02" },
   [K.OFLAIL] = { icon = "INV_Mace_01" },
   [K.OBATTLEAXE] = { icon = "INV_Axe_01" },
   [K.OLONGSWORD] = { icon = "INV_Sword_04" },
   [K.O2SWORD] = { icon = "INV_Sword_27" },
   [K.OSWORD] = { icon = "INV_Sword_04" },
   [K.OLEATHER] = { icon = "INV_Chest_Leather_01" },
   [K.OSTUDLEATHER] = { icon = "INV_Chest_Leather_01" },
   [K.ORING] = { icon = "INV_Chest_Chain" },
   [K.OCHAIN] = { icon = "INV_Chest_Chain" },
   [K.OSPLINT] = { icon = "INV_Chest_Plate01" },
   [K.OPLATE] = { icon = "INV_Chest_Plate01" },
   [K.OSHIELD] = { icon = "INV_Shield_04" },
}

V.GROUND = {
   town = { 0.16, 0.30, 0.12 },
   dungeon = { 0.26, 0.23, 0.20 },
   volcano = { 0.34, 0.15, 0.10 },
   deep = { 0.15, 0.16, 0.24 },
   lava = { 0.50, 0.17, 0.07 },
}
V.WALL = { 0.52, 0.48, 0.43 }
V.GLYPH_COLOR = { 1, 0.9, 0.5 }
V.MISSILE_COLOR = { 0.6, 0.85, 1 }

local ground = {}
function V.Blend(from, to, t)
   for i = 1, 3 do ground[i] = from[i] + (to[i] - from[i]) * t end
   return ground
end

-- The status effects shown in the effects row: the 17 of the C bottom line (botside) and a
-- few more that the C only showed through the stats. The icons are placeholders to curate.
V.EFFECTS = {
   { K.STEALTH, L["Stealth"], "Ability_Stealth" },
   { K.UNDEADPRO, L["Undead protection"], "Spell_Holy_PrayerOfSpirit" },
   { K.SPIRITPRO, L["Spirit protection"], "Spell_Holy_DivineSpirit" },
   { K.CHARMCOUNT, L["Charm"], "Spell_Shadow_Charm" },
   { K.TIMESTOP, L["Time stop"], "Spell_Frost_Stun" },
   { K.HOLDMONST, L["Hold monsters"], "Spell_Nature_Slow" },
   { K.GIANTSTR, L["Giant strength"], "Spell_Nature_Strength" },
   { K.FIRERESISTANCE, L["Fire resistance"], "Spell_Fire_FireArmor" },
   { K.DEXCOUNT, L["Dexterity"], "Spell_Nature_Invisibilty" },
   { K.STRCOUNT, L["Strength"], "Spell_Nature_Strength" },
   { K.SCAREMONST, L["Scare monsters"], "Spell_Shadow_PsychicScream" },
   { K.HASTESELF, L["Haste"], "Spell_Nature_Bloodlust" },
   { K.CANCELLATION, L["Cancellation"], "Spell_Holy_DispelMagic" },
   { K.INVISIBILITY, L["Invisible"], "Ability_Vanish" },
   { K.ALTPRO, L["Protection 3"], "Spell_Holy_PowerWordShield" },
   { K.PROTECTIONTIME, L["Protection 2"], "Spell_Holy_SealOfProtection" },
   { K.WTW, L["Walk through walls"], "Spell_Arcane_Blink" },
   { K.BLINDCOUNT, L["Blind"], "Spell_Shadow_MindSteal" },
   { K.CONFUSE, L["Confused"], "Spell_Shadow_MindBomb" },
   { K.HERO, L["Hero"], "Ability_Warrior_BattleShout" },
   { K.SEEINVISIBLE, L["See invisible"], "Spell_Holy_Heal" },
   { K.AWARENESS, L["Awareness"], "Spell_Holy_MindVision" },
   { K.AGGRAVATE, L["Aggravated"], "Ability_Warrior_Rampage" },
   { K.HALFDAM, L["Half damage"], "Spell_Shadow_CurseOfMannoroth" },
   { K.ITCHING, L["Itching"], "Spell_Nature_NullifyDisease" },
   { K.CLUMSINESS, L["Clumsy"], "Spell_Shadow_CurseOfTounges" },
   { K.HASTEMONST, L["Monsters hasted"], "Spell_Nature_Bloodlust" },
}

-- The effects that hurt rather than help: the ones in the effects row that a scroll of
-- remove curse lifts (Magic.lua, CURSE).
V.CURSE = {
   [K.BLINDCOUNT] = true, [K.CONFUSE] = true, [K.AGGRAVATE] = true, [K.HASTEMONST] = true,
   [K.ITCHING] = true, [K.CLUMSINESS] = true, [K.HALFDAM] = true,
}

function V.ObjectIcon(id)
   local visual = V.object[id]
   return visual and visual.icon and (ICONS .. visual.icon)
end

-- Monsters are drawn as their ASCII letter until they get icons and models (milestone 10).
V.MONSTER_COLOR = { 1, 0.35, 0.3 }
V.PLAYER_COLOR = { 0.3, 1, 0.3 }

-- A list of displays from single numbers and { first, last } ranges.
local function Displays(...)
   local list = {}
   for _, part in ipairs({ ... }) do
      if type(part) == "table" then
         for display = part[1], part[2] do list[#list + 1] = display end
      else
         list[#list + 1] = part
      end
   end
   return list
end

-- Whether the client has a display (some are only in the newer clients).  A display is
-- tried on a model that is never shown; the answer is kept.  One that is not known at once
-- is tried again when its model has loaded, and the map is drawn again then.
-- A display the client does not know is shown as a placeholder model (it has a model file id
-- too), so the file of a display that cannot exist is learned first and counts as "not there".
local usable, probe, missing = {}, nil, nil
local NO_SUCH_DISPLAY = 99999999
local function Has(model)
   local file = model.GetModelFileID and model:GetModelFileID()
   return file ~= nil and file ~= 0 and file ~= missing
end
local function Usable(display)
   if usable[display] ~= nil then return usable[display] end
   if not probe then
      probe = CreateFrame("PlayerModel", nil, UIParent)
      probe:SetSize(8, 8)
      probe:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 100, -100)  -- (off screen)
      probe:SetScript("OnModelLoaded", function(model)
         if model.display == NO_SUCH_DISPLAY then
            missing = model.GetModelFileID and model:GetModelFileID()
         elseif model.display and not usable[model.display] and Has(model) then
            usable[model.display] = true
            ns.ui:Refresh("map")
         end
      end)
      probe.display = NO_SUCH_DISPLAY
      probe:SetDisplayInfo(NO_SUCH_DISPLAY)
      missing = probe.GetModelFileID and probe:GetModelFileID()
   end
   probe.display = display
   if display < 0 then probe:SetModel(-display) else probe:SetDisplayInfo(display) end
   -- (until the placeholder is known, the answer waits for OnModelLoaded)
   usable[display] = (not probe.GetModelFileID) or (missing ~= nil and Has(probe))
   return usable[display]
end

-- Displays to try in turn: { first choices..., backup = { used if none of those is there } }.
local function Prefer(first, backup)
   first.backup = backup
   return first
end

-- The list of displays a monster is shown as: its first choices that the client has, else
-- the backup.
local function Choices(display)
   if type(display) ~= "table" then return { display } end
   if not display.backup then return display end
   local list = {}
   for _, id in ipairs(display) do
      if Usable(id) then list[#list + 1] = id end
   end
   if #list == 0 then return display.backup end
   return list
end

-- The creature display each monster is shown as in the 2.5D view.  V.DISPLAY is the list that
-- goes with the addon; what the player picked in the model viewer (/larn models) is kept in
-- the saved variables and wins.
-- A monster has a display or a list of displays, one of which each monster gets by chance.
V.DISPLAY = {
   -- [monster id] = displayID, or a list of them
   [K.LEMMING] = Displays(1141, 1418),  -- (Rat and Dig Rat)
   [K.JACKAL] = Displays({ 10902, 10903 }, 1536, 2710, 2712, 2713, 2714, 1535, 12966),  -- (the hyena)
   [K.CENTIPEDE] = 15533,
   [K.ANT] = 11096,
   [K.ASSASSINBUG] = 7511,
   [K.BUGBEAR] = 11088,
   [K.JACULI] = Displays(2705, 2703, 10991),
   -- (the demon lords, I to VII: the felguards, the doomguard, a dreadlord)
   [K.DEMONLORD] = 5048,
   [K.DEMONLORD + 1] = 5047,
   [K.DEMONLORD + 2] = 9017,
   [K.DEMONLORD + 3] = 7970,
   [K.DEMONLORD + 4] = 14152,
   [K.DEMONLORD + 5] = Displays(1912, 4426),
   [K.DEMONLORD + 6] = 10543,
   [K.DEMONPRINCE] = 12449,  -- (Lord Kazzak)
   [K.LUCIFER] = 12990,  -- (Echo of Archimonde)
   [K.ELF] = 7874,  -- (Blood Elf Defender)
   [K.SILVERDRAGON] = 6373,  -- (a teal drake)
   [K.GREENDRAGON] = 6375,
   [K.REDDRAGON] = 6376,  -- (Flamescale Drake)
   [K.PLATINUMDRAGON] = 11460,  -- (Azuregos)
   [K.BRONZEDRAGON] = 2719,  -- (Anachronos)
   [K.WHITEDRAGON] = 10585,  -- (a cobalt whelp)
   [K.WATERLORD] = 110,  -- (Baron Aquanis)
   [K.EYE] = 2421,  -- (Eye of Kilrogg)
   [K.LEPRECHAUN] = Prefer({ 61712, 51994 }, { 7109, 7197, 7202, 7203, 7228, 7230, 7234 }),  -- (the treasure goblin, else Venture Co. goblins)
   [K.QUASIT] = Prefer({ 4449, 14380, 12345, 1015, 568, 2452, 6810, 118973 }, { 4449 }),  -- (those the client has)
   [K.NYMPH] = Displays(12432, 1825),
   [K.RUSTMONSTER] = Displays(7763, 15436),
   [K.CUBE] = Displays(11141, 4754, 767, 1306, 11137, 1146, 11140, 11139, 682, 11138, 2569, 358, 1145, 2028),
   [K.YETI] = Displays(3206, 10579, 3207),
   [K.ZOMBIE] = Displays({ 10970, 10979 }),
   [K.WRAITH] = Displays(14368, 146),
   [K.POLTERGEIST] = 10728,
   [K.SPIRITNAGA] = 8782,
   [K.VAMPIRE] = 8808,
   [K.VORTEX] = Displays(14525, 5327),
   [K.HELLHOUND] = Displays(11997, 12168),
   [K.CENTAUR] = Displays(9419, 9410, 9447, 11640, 1349),
   [K.TROLL] = Displays(5608, 5626, 5605, 5610, 5612, 5607, 5613, 10249, 11442, 3986, 3999, 6487, 6489, 3993, 1157, 6485),
   [K.GREENURCHIN] = 13109,  -- (Phase Lasher)
   [K.XVART] = Displays(506, 391, 486, 11293),  -- (Bluegill and Saltscale murlocs)
   [K.PURPLEWORM] = Displays(7549, 13009),  -- (Murk Worm and Rock Worm)
   -- (a negative number is a model file data id, negated: the chests are objects, not creatures)
   [K.MIMIC] = Displays(-196976, -196979, -196982, -196987, -196988, -196989, -197063, -341746, -341870),  -- (treasure chests)
   [K.METAMORPH] = Displays(4629, 7857, 14703),  -- (Haunting Phantasm and the two wraiths)
   [K.FORVALAKA] = Displays(633, 11452),  -- (Shadowmaw panthers)
   [K.ZILLER] = Displays(6087, 2187, 6086, 1531),  -- (Zhevra Runner, Charger, Courser and Tamed Zhevra)
   [K.ICELIZARD] = 8797,  -- (Cold Eye Basilisk)
   [K.UMBERHULK] = 12156,  -- (Hive'Regal Burrower)
   [K.YELLOWMOLD] = 16111,  -- (the Spore, Loatheb)
   [K.VIOLETFUNGI] = Prefer({ 121735 }, { 8389 }),  -- (the Dread Fungus, else the Rotting Behemoth)
   [K.DISENCHANTRESS] = 1937,  -- (Anaya Dawnrunner)
   [K.INVISIBLESTALKER] = 4870,  -- (Restless Shade)
   [K.ROTHE] = Displays(1230, 1308, 1232, 2767, 10914, 1453, 179),  -- (kodos)
   [K.OSEQUIP] = Displays(381, 389, 1208),  -- (boars)
   [K.LAMANOBE] = Displays(6825, 6826, 936, 2000, 1999, 2003),  -- (the Timbermaw furbolgs)
   [K.XORN] = Displays(2169, 2170, 2075),  -- (the stone spirits)
   [K.SHAMBLINGMOUND] = Displays(2023, 713, 2024),  -- (the fen creeper, dweller and lord)
   [K.GNOMEKING] = 7006,  -- (High Tinker Mekkatorque)
   [K.GNOME] = Displays({ 6920, 6931 }),
   [K.KOBOLD] = Displays({ 114157, 114160 }, { 114709, 114718 }),
   [K.HOBGOBLIN] = Displays(30244, { 30261, 30267 }),
   [K.ORC] = Displays({ 9794, 9805 }),
   [K.SNAKE] = Displays(1206, 1986, 2954, 2955, 2957, 4268, 8173, 6303),
   [K.TROGLODYTE] = Displays(160, 606, 611, 721, 722, 723, 726, 730, 763, 764, 1194, 11166, 11609, 11610),
}

-- The sounds of the monsters, by monster id; any of attack, wound, die and special may be
-- left out (the default sound is played, a special attack falls back to the attack sound).
-- A sound is a sound kit name ("LEVELUP"), a sound kit id (888), a list of kit ids (one is
-- played, { 1, 2, 3 }) or { file = file data id }.
V.MONSTER_SOUND = {
   [K.HOBGOBLIN] = { attack = 397, wound = 398, die = 400, special = 396 },  -- (Dunemaul Ogre)
   [K.NYMPH] = { attack = { 6339, 6340, 6341 }, wound = { 6343, 6344, 6345 }, die = { 6346, 6347, 6348 }, special = 6342 },  -- (the wisp voice)
   -- (the demon lords: the doomguard voice, or the dreadlord voice for the felguards)
   [K.DEMONLORD] = { attack = 1091, wound = 1092, die = 1094, special = 1095 },
   [K.DEMONLORD + 1] = { attack = 1098, wound = 1099, die = 1101, special = 1102 },
   [K.DEMONLORD + 2] = { attack = 1091, wound = 1092, die = 1094, special = 1095 },
   [K.DEMONLORD + 3] = { attack = 1098, wound = 1099, die = 1101, special = 1102 },
   [K.DEMONLORD + 4] = { attack = 1098, wound = 1099, die = 1101, special = 1102 },
   [K.DEMONLORD + 5] = { attack = 1098, wound = 1099, die = 1101, special = 1102 },
   [K.DEMONLORD + 6] = { attack = 1091, wound = 1092, die = 1094, special = 1095 },
   [K.LUCIFER] = { attack = 1091, wound = 1092, die = 1094, special = 1095 },  -- (Echo of Archimonde)
   [K.DEMONPRINCE] = { attack = 8092, wound = 8093, die = 8095, special = 8096 },  -- (Lord Kazzak)
   [K.ELF] = { attack = 1307, wound = 1308, die = 1310 },  -- (Blood Elf Defender)
   [K.SILVERDRAGON] = { attack = 4060, wound = 4061, die = 4063, special = 4065 },  -- (Flamescale Drake)
   [K.GREENDRAGON] = { attack = 4060, wound = 4061, die = 4063, special = 4065 },  -- (Flamescale Drake)
   [K.REDDRAGON] = { attack = 4060, wound = 4061, die = 4063, special = 4065 },  -- (Flamescale Drake)
   [K.PLATINUMDRAGON] = { attack = 3520, wound = 3521, die = 3523, special = 3525 },  -- (Azuregos)
   [K.BRONZEDRAGON] = { attack = 3520, wound = 3521, die = 3523, special = 3525 },  -- (Anachronos)
   [K.WHITEDRAGON] = { attack = 429, wound = 430, die = 432, special = 428 },  -- (Cobalt Whelp)
   [K.WATERLORD] = { attack = 1403, wound = 1404, die = 1406, special = 1408 },  -- (Baron Aquanis)
   [K.EYE] = { attack = 8697, wound = 8698, die = 8700, special = { 8580, 8581, 8582, 8583, 8584, 8585, 8586, 8587 } },  -- (C'Thun)
   [K.QUASIT] = { attack = 766, wound = 767, die = 769, special = 770 },  -- (Vicious Grell)
   [K.INVISIBLESTALKER] = { attack = 3419, wound = 3420, die = 3422, special = 3424 },  -- (Restless Shade)
   [K.GREENURCHIN] = { attack = 5045, wound = 5046, die = 5048, special = 5050 },  -- (Phase Lasher)
   [K.XVART] = { attack = 417, wound = 418, die = 420, special = 416 },  -- (Bluegill Warrior)
   [K.PURPLEWORM] = { attack = 5038, wound = 5039, die = 5041, special = 5043 },  -- (Murk Worm)
   [K.MIMIC] = { attack = 721, wound = 722, die = 723, special = 724 },  -- (the ooze sounds, as the cube)
   [K.METAMORPH] = { attack = 3419, wound = 3420, die = 3422, special = 3424 },  -- (Haunting Phantasm)
   [K.FORVALAKA] = { attack = 643, wound = 644, die = 646 },  -- (Shadowmaw Panther)
   [K.ZILLER] = { attack = 725, wound = 726, die = 728, special = 729 },  -- (Zhevra Runner)
   [K.ICELIZARD] = { attack = 565, wound = 567, die = 569, special = 570 },  -- (Cold Eye Basilisk)
   [K.UMBERHULK] = { attack = 1225, wound = 1226, die = 1228, special = 1230 },  -- (Hive'Regal Burrower)
   [K.YELLOWMOLD] = { attack = 8742, wound = 8743, die = 8745 },  -- (the Spore)
   [K.VIOLETFUNGI] = { attack = 456, wound = 459, die = 458, special = 462 },  -- (the Rotting Behemoth)
   [K.DISENCHANTRESS] = { attack = 2933, wound = 2934, die = 2936, special = 23291 },  -- (Anaya Dawnrunner; the reforging sound for disenchanting)
   [K.ROTHE] = { attack = 772, wound = 773, die = 775, special = 771 },  -- (the kodo voice)
   [K.OSEQUIP] = { attack = 380, wound = 381, die = 383, special = 379 },  -- (the boar voice)
   [K.LAMANOBE] = { attack = 355, wound = 358, die = 357, special = 356 },  -- (the furbolg voice)
   [K.XORN] = { attack = 736, wound = 737, die = 738, special = 739 },  -- (the earth elemental voice)
   [K.SHAMBLINGMOUND] = { attack = 456, wound = 459, die = 458, special = 462 },  -- (the bog beast voice)
   [K.GNOMEKING] = { attack = 3275, wound = 3276, die = 3278, special = 7226 },  -- (High Tinker Mekkatorque)
   [K.GNOME] = { attack = 3275, wound = 3276, die = 3278 },  -- (Addled Leper)
   [K.TROLL] = { attack = 3307, wound = 3308, die = 3310 },  -- (a Frostmane troll; tools/npc-sounds.py)
-- (the sounds of one NPC of each kind: attack, injury, death, aggro; tools/npc-sounds.py)
   [K.LEMMING] = { wound = 1379, die = 1380 },  -- (Rat; it has no attack sound, so that is the default bite)
   [K.JACKAL] = { attack = 2506, wound = 2507, die = 2509, special = 2511 },  -- (Bonepaw Hyena)
   [K.SNAKE] = { attack = 4494, wound = 4495, die = 4497, special = 4499 },  -- (Razzashi Cobra)
   [K.KOBOLD] = { attack = 312, wound = 315, die = 314, special = 694 },  -- (Kobold Laborer)
   [K.ORC] = { attack = 1319, wound = 1320, die = 1322 },  -- (Blackrock Grunt)
   [K.CENTIPEDE] = { attack = 715, wound = 716, die = 718, special = 719 },  -- (Vekniss Hive Crawler)
   [K.JACULI] = { attack = 586, wound = 587, die = 589, special = 590 },  -- (Cloud Serpent)
   [K.TROGLODYTE] = { attack = 655, wound = 656, die = 658, special = 659 },  -- (Stonesplinter Skullthumper)
   [K.ANT] = { attack = 715, wound = 716, die = 718, special = 719 },  -- (Silithid Harvester)
   [K.LEPRECHAUN] = { attack = 1409, wound = 1410, die = 1413, special = 1415 },  -- (Venture Co. Operator)
   [K.RUSTMONSTER] = { attack = 721, wound = 722, die = 723, special = 724 },  -- (Oozeling)
   [K.ZOMBIE] = { attack = 1468, wound = 1469, die = 1471, special = 1473 },  -- (Blighted Zombie)
   [K.ASSASSINBUG] = { attack = 715, wound = 716, die = 718, special = 719 },  -- (Beetle)
   [K.BUGBEAR] = { attack = 715, wound = 716, die = 718, special = 719 },  -- (Hive'Zora Wasp)
   [K.HELLHOUND] = { attack = 6814, wound = 6815, die = 6817, special = 6819 },  -- (Core Hound)
   [K.CENTAUR] = { attack = 1040, wound = 1041, die = 1043, special = 1044 },  -- (Galak Centaur)
   [K.YETI] = { attack = 1239, wound = 1240, die = 1242, special = 1243 },  -- (Cave Yeti)
   [K.CUBE] = { attack = 721, wound = 722, die = 723, special = 724 },  -- (Glutinous Ooze)
   [K.VORTEX] = { attack = 3784, wound = 3785, die = 3787, special = 3789 },  -- (Dust Devil)
   [K.WRAITH] = { attack = 3419, wound = 3420, die = 3422, special = 3424 },  -- (Eldreth Wraith)
   [K.VAMPIRE] = { attack = 3364, wound = 3365, die = 3367, special = 3369 },  -- (Vampiric Duskbat)
   [K.POLTERGEIST] = { attack = 1167, wound = 1169, die = 1171, special = 1173 },  -- (Shrieking Banshee)
   [K.SPIRITNAGA] = { attack = 1167, wound = 1169, die = 1171, special = 1173 },  -- (Wailing Banshee)
   -- [K.SNAKE] = { attack = "...", wound = 0, die = { file = 0 } },
}

-- Models that stand too high (or low) on their shadow, by display id: how far to move the
-- model, as a fraction of its width; positive is down, negative up.
V.LOWER = {
   [1206] = 0.12,  -- snake
}

-- (what is set in the model viewer, global.lowers, wins)
function V.Lower(display)
   local own = ns.mod.db.global.lowers
   return (own and own[display]) or V.LOWER[display] or 0
end

-- Models that are too big or too small for their tile, by display id: how far the camera
-- stands from the model, 1 is the usual; above 1 shrinks the model.  What is set in the model
-- viewer (global.scales) wins.
V.SCALE = {
   [146] = 0.68,
   [391] = 1.33,
   [486] = 1.33,
   [506] = 1.33,
   [713] = 1.1,
   [936] = 1.1,
   [1999] = 1.21,
   [2000] = 1.21,
   [2003] = 1.21,
   [2023] = 1.1,
   [2024] = 1.1,
   [2710] = 1.33,
   [3206] = 0.51,
   [3207] = 0.51,
   [4449] = 1.1,
   [4629] = 1.1,
   [5047] = 0.91,
   [5048] = 1.1,
   [5327] = 1.1,
   [6373] = 0.83,
   [6375] = 1.33,
   [6376] = 1.1,
   [6825] = 1.21,
   [6826] = 1.46,
   [6920] = 1.21,
   [7763] = 0.51,
   [7857] = 1.1,
   [7970] = 0.75,
   [9017] = 0.83,
   [9419] = 1.61,
   [9794] = 0.91,
   [10543] = 0.75,
   [10579] = 0.51,
   [11096] = 1.46,
   [11293] = 1.33,
   [11460] = 0.91,
   [11997] = 0.83,
   [12432] = 1.33,
   [12449] = 0.68,
   [12990] = 0.56,
   [14152] = 0.68,
   [14368] = 0.68,
   [14525] = 1.1,
   [30244] = 0.83,
   [114157] = 1.1,
   [121735] = 1.1,
}

function V.Scale(display)
   local own = ns.mod.db.global.scales
   return (own and own[display]) or V.SCALE[display] or 1
end

-- Models that reach beyond their tile (wings, tails), by display id: how many times larger a
-- frame they get, to the sides and up; the model keeps its size (the camera moves back by the
-- same factor).  What is set in the model viewer (global.rooms) wins.
V.ROOM = {
   [110] = 2,
   [391] = 2,
   [486] = 2,
   [506] = 2,
   [713] = 2,
   [1912] = 2,
   [1999] = 2,
   [2000] = 1.5,
   [2003] = 2,
   [2023] = 2,
   [2024] = 2.5,
   [2703] = 1.5,
   [2705] = 1.5,
   [2719] = 2.5,
   [3206] = 2.5,
   [3207] = 2.5,
   [4629] = 1.5,
   [5327] = 2,
   [6373] = 3,
   [6375] = 2,
   [6376] = 3,
   [6825] = 1.5,
   [6826] = 1.5,
   [7763] = 2,
   [7857] = 1.5,
   [8389] = 3.5,
   [9794] = 2,
   [10543] = 3,
   [10579] = 2.5,
   [10585] = 1.5,
   [10991] = 1.5,
   [11096] = 2.5,
   [11293] = 2,
   [11460] = 2.5,
   [11997] = 1,
   [12449] = 2,
   [12990] = 3,
   [13109] = 2,
   [14525] = 2,
   [15533] = 1.5,
   [16111] = 2,
   [30244] = 2,
   [121735] = 2.5,
}

function V.Room(display)
   local own = ns.mod.db.global.rooms
   return (own and own[display]) or V.ROOM[display] or 1
end

-- What the player says when attacking, hurt and dying, by race (the race file of UnitRace) and
-- sex (2 male, 3 female): { attack = kit, wound = { kits }, die = kit }, from the sounds
-- Human/Dwarf/... Player Attack, Wound, WoundCrit and Death.  A race or kind missing here
-- sounds like the other sex of the race, then like a human of its sex.
V.PLAYER_SOUND = {
   Human = {
      [2] = { attack = 2941, wound = { 2942, 2943 }, die = 2944 },
      [3] = { attack = 2937, wound = { 2938, 2939 }, die = 2940 },
   },
   Dwarf = {
      [2] = { attack = 2929, wound = { 2930, 2931 }, die = 2932 },
      [3] = { attack = 2925, wound = { 2926, 2927 }, die = 2928 },
   },
   NightElf = {
      [2] = { attack = 2956, wound = { 2957, 2958 }, die = 2959 },
      [3] = { attack = 2933, wound = { 2934, 2935 }, die = 2936 },
   },
   Gnome = {
      [2] = { attack = 3275, wound = { 3276, 3277 }, die = 3278 },
      [3] = { attack = 3269, wound = { 3270, 3271 } },
   },
   Orc = {
      [2] = { attack = 1319, wound = { 1320, 1321 }, die = 1322 },
      [3] = { attack = 2960, wound = 2961, die = 213 },
   },
   Tauren = {
      [2] = { attack = 1353, wound = { 1354, 1355 }, die = 1356 },
      [3] = { die = 229 },
   },
   Troll = {
      [2] = { attack = 3307, wound = { 3308, 3309 }, die = 3310 },
      [3] = { attack = 3301, wound = { 3302, 3303 }, die = 3304 },
   },
   Scourge = {
      [2] = { attack = 1315, wound = { 1316, 1317 }, die = 1318 },
      [3] = { attack = 1361, wound = { 1362, 1363 }, die = 1364 },
   },
}

-- The sound of the player for kind ("attack", "wound" or "die"), see PLAYER_SOUND.
function V.PlayerSound(kind)
   local _, race = UnitRace and UnitRace("player")
   local sex = UnitSex and UnitSex("player") == 3 and 3 or 2
   local other = sex == 3 and 2 or 3
   local own = V.PLAYER_SOUND[race]
   local human = V.PLAYER_SOUND.Human
   return (own and own[sex][kind]) or (own and own[other][kind]) or human[sex][kind]
end

-- How far to turn a model in the model viewer and the zoo, by display id, in radians: to see
-- how wide it is from the side, for its room (the game turns them as it wants).  What is set
-- in the model viewer (global.turns) wins.
V.TURN = {
}

function V.Turn(display)
   local own = ns.mod.db.global.turns
   return (own and own[display]) or V.TURN[display] or 0
end

-- Monsters that go by another name than in the original (design.md, open decision 2).  The
-- id and the rules stay those of the original monster.
V.MONSTER_NAME = {
   [K.LEMMING] = L["rat"],
   [K.YELLOWMOLD] = L["fungal spore"],
   [K.ZILLER] = L["zhevra"],
   [K.XVART] = L["bluegill warrior"],
   [K.GREENURCHIN] = L["phase lasher"],
   [K.PURPLEWORM] = L["Giant Worm"],
   [K.FORVALAKA] = L["black panther"],
   [K.METAMORPH] = L["phantasm"],
   [K.JACKAL] = L["hyena"],
   [K.CENTIPEDE] = L["hive crawler"],
   [K.ANT] = L["silithid harvester"],
   [K.BUGBEAR] = L["hornet"],
   [K.JACULI] = L["cloud serpent"],
   [K.LEPRECHAUN] = L["treasure goblin"],
   [K.QUASIT] = L["imp"],
   [K.NYMPH] = L["sprite"],
   [K.RUSTMONSTER] = L["rust oozeling"],
   [K.CUBE] = L["corrosive ooze"],
   [K.VAMPIRE] = L["vampire bat"],
   [K.SPIRITNAGA] = L["banshee"],
   [K.HELLHOUND] = L["core hound"],
   [K.ELF] = L["blood elf"],
   [K.LAMANOBE] = L["Timbermaw Warrior"],
   [K.OSEQUIP] = L["dire boar"],
   [K.ROTHE] = L["kodo"],
}
for id, name in pairs(V.MONSTER_NAME) do
   ns.MonsterData[id].name = name
end

-- Armour class changed from the original: the higher it is, the easier the monster is to hit.
-- The rats (armour class 0) took 10 to 20 swings early on.
V.MONSTER_AC = {
   [K.LEMMING] = 10,
}
for id, ac in pairs(V.MONSTER_AC) do
   ns.MonsterData[id].armorclass = ac
end

-- The display of a monster; look is the number it was given by chance (Draw: G.look).
function V.MonsterDisplay(id, look)
   local own = ns.mod.db.global.displays
   local display = (own and own[id]) or V.DISPLAY[id]
   if display == nil then return nil end
   local list = Choices(display)
   return list[((look or 1) - 1) % #list + 1]
end

-- All the displays a monster can have, the backup too: the one chosen in the model viewer,
-- or its list.
function V.DisplayList(id)
   local own = ns.mod.db.global.displays
   local display = (own and own[id]) or V.DISPLAY[id]
   if type(display) ~= "table" then return display and { display } or {} end
   local list = { unpack(display) }
   for _, backup in ipairs(display.backup or {}) do list[#list + 1] = backup end
   return list
end

function V.MonsterGlyph(id)
   return ns.Tables.monstglyphs:sub(id + 1, id + 1)
end

function V.ObjectGlyph(id)
   return ns.Tables.objglyphs:sub(id + 1, id + 1)
end

function V.ClassIcon(class)
   return ICONS .. class.icon
end

-- The dungeon ground gets darker and bluer with depth, the volcano redder.
function V.Ground(level)
   if level == 0 then return V.GROUND.town end
   local depth
   if level > K.DBOTTOM then
      depth = (level - K.DBOTTOM - 1) / (K.VBOTTOM - K.DBOTTOM - 1)
      return V.Blend(V.GROUND.volcano, V.GROUND.lava, depth)
   end
   depth = (level - 1) / (K.DBOTTOM - 1)
   return V.Blend(V.GROUND.dungeon, V.GROUND.deep, depth)
end
