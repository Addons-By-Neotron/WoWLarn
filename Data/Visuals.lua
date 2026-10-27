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
}

V.GROUND = {
   town = { 0.16, 0.30, 0.12 },
   dungeon = { 0.13, 0.12, 0.11 },
   volcano = { 0.22, 0.08, 0.05 },
   deep = { 0.06, 0.07, 0.13 },
   lava = { 0.38, 0.10, 0.04 },
}
V.WALL = { 0.40, 0.36, 0.33 }
V.GLYPH_COLOR = { 1, 0.9, 0.5 }

local ground = {}
function V.Blend(from, to, t)
   for i = 1, 3 do ground[i] = from[i] + (to[i] - from[i]) * t end
   return ground
end

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
