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
}
V.WALL = { 0.40, 0.36, 0.33 }
V.GLYPH_COLOR = { 1, 0.9, 0.5 }

function V.ObjectIcon(id)
   local visual = V.object[id]
   return visual and visual.icon and (ICONS .. visual.icon)
end

function V.ObjectGlyph(id)
   return ns.Tables.objglyphs:sub(id + 1, id + 1)
end

function V.ClassIcon(class)
   return ICONS .. class.icon
end

function V.Ground(level)
   if level == 0 then return V.GROUND.town end
   if level > K.DBOTTOM then return V.GROUND.volcano end
   return V.GROUND.dungeon
end
