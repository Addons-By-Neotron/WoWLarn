--[[
**********************************************************************
WoWLarn - Player attributes and inventory helpers (player.c).
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
local G = ns.G

local Player = {}
ns.Player = Player

local c, iven, ivenarg = G.c, G.iven, G.ivenarg
local item, mon = G.item, G.mon

local MAXX, MAXY, IVENSIZE = K.MAXX, K.MAXY, K.IVENSIZE
local AC, WCLASS, MOREDEFENSES, MOREDAM = K.AC, K.WCLASS, K.MOREDEFENSES, K.MOREDAM
local WEAR, SHIELD, WIELD = K.WEAR, K.SHIELD, K.WIELD
local REGEN, ENERGY = K.REGEN, K.ENERGY

-- Armor class bonus before the enchantment (C: the switch in recalc).
local ARMOR_AC = {
   [K.OSHIELD] = 2, [K.OLEATHER] = 2, [K.OSTUDLEATHER] = 3, [K.ORING] = 5, [K.OCHAIN] = 6,
   [K.OSPLINT] = 7, [K.OPLATE] = 9, [K.OPLATEARMOR] = 10, [K.OSSPLATE] = 12, [K.OELVENCHAIN] = 15,
}

-- Weapon class before the enchantment. Anything not listed has weapon class 0.
local WEAPON_WC = {
   [K.ODAGGER] = 3, [K.OBELT] = 7, [K.OSHIELD] = 8, [K.OPSTAFF] = 10, [K.OSPEAR] = 10,
   [K.OFLAIL] = 14, [K.OBATTLEAXE] = 17, [K.OLANCE] = 20, [K.OLONGSWORD] = 22, [K.OVORPAL] = 22,
   [K.O2SWORD] = 26, [K.OSWORDofSLASHING] = 30, [K.OSLAYER] = 30, [K.OSWORD] = 32, [K.OHAMMER] = 35,
}

-- C: recalc(). Armor class, weapon class and the ring-based regeneration values.
function Player.recalc()
   c[AC] = c[MOREDEFENSES]
   if c[WEAR] > 0 then
      local bonus = ARMOR_AC[iven[c[WEAR]]]
      if bonus then c[AC] = c[AC] + bonus + ivenarg[c[WEAR]] end
   end
   if c[SHIELD] > 0 and iven[c[SHIELD]] == K.OSHIELD then
      c[AC] = c[AC] + 2 + ivenarg[c[SHIELD]]
   end

   if c[WIELD] <= 0 then
      c[WCLASS] = 0
   else
      local base = WEAPON_WC[iven[c[WIELD]]]
      c[WCLASS] = base and (base + ivenarg[c[WIELD]]) or 0
   end
   c[WCLASS] = c[WCLASS] + c[MOREDAM]

   c[REGEN] = 1
   c[ENERGY] = 0
   for i = 1, IVENSIZE do
      local kind, arg = iven[i], ivenarg[i]
      if kind == K.OPROTRING then
         c[AC] = c[AC] + arg + 1
      elseif kind == K.ODAMRING then
         c[WCLASS] = c[WCLASS] + arg + 1
      elseif kind == K.OBELT then
         c[WCLASS] = c[WCLASS] + arg * 2 + 2
      elseif kind == K.OREGENRING then
         c[REGEN] = c[REGEN] + arg + 1
      elseif kind == K.ORINGOFEXTRA then
         c[REGEN] = c[REGEN] + 5 * (arg + 1)
      elseif kind == K.OENERGYRING then
         c[ENERGY] = c[ENERGY] + arg + 1
      end
   end
end

-- C: positionplayer(). Moves the player to the next free tile.
function Player.positionPlayer()
   local try = 2
   while (item[G.playerx][G.playery] ~= 0 or mon[G.playerx][G.playery] ~= 0) and try > 0 do
      G.playerx = G.playerx + 1
      if G.playerx >= MAXX then
         G.playerx = 2
         G.playery = G.playery + 1
         if G.playery >= MAXY then
            G.playery = 2
            try = try - 1
         end
      end
   end
   if try == 0 then
      ns.ui:Message("Failure in positionplayer")
   end
end

-- C: drop_object(). Arrives with the inventory in milestone 5.
function Player.dropObject(slot)
   error("Player.dropObject is not implemented yet (milestone 5)")
end
