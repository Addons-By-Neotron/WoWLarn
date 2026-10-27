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
