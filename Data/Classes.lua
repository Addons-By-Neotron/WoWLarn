--[[
**********************************************************************
WoWLarn - Character classes.
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

-- The eight Ularn classes as WoW classes (design.md section 9). The numbers are the
-- original ones from store.c:pick_char; only names and flavor changed. The letter is
-- the key used to pick the class in the original.
-- stats: strength, intelligence, wisdom, constitution, dexterity, charisma.
-- spells: spell numbers (1-based: pro 1, mle 2, dex 3, sle 4, chm 5, ssp 6).
-- kit: starting inventory in slot order. arg = "potion" or "scroll" picks a random
-- one of the first six. wear/wield are kit positions (nil = nothing).
ns.Classes = {
   { letter = "a", token = "WARRIOR", icon = "ClassIcon_Warrior", original = "Ogre",
     hp = 16, stats = { 18, 4, 6, 16, 6, 4 }, spells = { 2 }, spellmax = 1, spellcount = 1,
     kit = { { K.OPOTION, "random" }, { K.OPOTION, "random" } } },
   { letter = "b", token = "MAGE", icon = "ClassIcon_Mage", original = "Wizard",
     hp = 8, stats = { 8, 16, 16, 6, 6, 8 }, spells = { 2, 5 }, spellmax = 2, spellcount = 2,
     kit = { { K.OPOTION, K.PTREASURE }, { K.OSCROLL, "random" }, { K.OSCROLL, "random" } } },
   { letter = "c", token = "SHAMAN", icon = "ClassIcon_Shaman", original = "Klingon",
     hp = 14, stats = { 14, 12, 4, 12, 8, 3 }, spells = { 6 }, spellmax = 1, spellcount = 1,
     kit = { { K.OSTUDLEATHER, 0 }, { K.OPOTION, "random" } }, wear = 1 },
   { letter = "d", token = "PRIEST", icon = "ClassIcon_Priest", original = "Elf",
     hp = 8, stats = { 8, 14, 12, 8, 8, 14 }, spells = { 1 }, spellmax = 2, spellcount = 1,
     kit = { { K.OLEATHER, 0 }, { K.OSCROLL, "random" } }, wear = 1 },
   { letter = "e", token = "ROGUE", icon = "ClassIcon_Rogue", original = "Rogue",
     hp = 12, stats = { 8, 12, 8, 10, 14, 6 }, spells = { 2 }, spellmax = 1, spellcount = 1,
     kit = { { K.OLEATHER, 0 }, { K.ODAGGER, 0 }, { K.OSCROLL, K.SSTEALTH } }, wear = 1, wield = 2 },
   { letter = "f", token = "HUNTER", icon = "ClassIcon_Hunter", original = "Geek",
     hp = 10, stats = { 12, 12, 12, 12, 12, 12 }, spells = { 1, 2 }, spellmax = 1, spellcount = 1,
     kit = { { K.OLEATHER, 0 }, { K.ODAGGER, 0 } }, wear = 1, wield = 2 },
   { letter = "g", token = "PALADIN", icon = "ClassIcon_Paladin", original = "Dwarf",
     hp = 12, stats = { 16, 6, 8, 16, 4, 4 }, spells = { 1 }, spellmax = 1, spellcount = 1,
     kit = { { K.OSPEAR, 0 } }, wield = 1 },
   { letter = "h", token = "WARLOCK", icon = "ClassIcon_Warlock", original = "Rambo",
     hp = 1, stats = { 3, 3, 3, 3, 3, 3 }, spells = {}, spellmax = 0, spellcount = 0,
     kit = { { K.OLANCE, 0 } }, wield = 1, lanceofdeath = true },
}
