--[[
**********************************************************************
WoWLarn - Game-side display logic: visibility and player movement (display.c).
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
local L = LibStub("AceLocale-3.0"):GetLocale("WoWLarn")
local _, ns = ...
local K = ns.K
local G = ns.G
local rund = ns.rund

local Display = {}
ns.Display = Display

local c, item, know, mon = G.c, G.item, G.know, G.mon
local MAXX, MAXY = K.MAXX, K.MAXY

-- C: diroffx/diroffy. Direction 0 is "stay", 1 south, 2 east, 3 north, 4 west,
-- 5 northeast, 6 northwest, 7 southeast, 8 southwest. (y grows downward.)
local DIROFFX = { [0] = 0, 0, 1, 0, -1, 1, -1, 1, -1 }
local DIROFFY = { [0] = 0, 1, 0, -1, 0, -1, -1, 1, 1 }
Display.DIROFFX, Display.DIROFFY = DIROFFX, DIROFFY

-- C: the monster shown on a tile. Invisible stalkers and demons (without the eye of Larn)
-- are not seen, and a mimic looks like another monster that changes now and then.
function Display.visibleMonster(x, y)
   local id = mon[x][y]
   if id == 0 then return 0 end
   if id == K.MIMIC then
      if G.gtime % 10 == 0 or not G.mimicmonst then
         repeat G.mimicmonst = ns.rnd(K.MAXMONST) until G.mimicmonst ~= K.INVISIBLESTALKER
      end
      return G.mimicmonst
   elseif id == K.INVISIBLESTALKER and c[K.SEEINVISIBLE] == 0 then
      return 0
   elseif id >= K.DEMONLORD and id <= K.LUCIFER then
      if c[K.EYEOFLARN] == 0 then return 0 end
      ns.ItemInfo.discover(K.OLARNEYE)
   end
   return id
end

-- True if the ground of the tile is on the map: it is known now, or was. A tile that is not
-- known now (a monster came or went) shows the ground only.
function Display.remembered(x, y)
   if know[x][y] ~= 0 then
      G.seen[x][y] = 1
      return true
   end
   return G.seen[x][y] ~= 0
end

-- C: showcell(). Marks the tiles around the player as seen.
function Display.showcell(x, y)
   local radius = 1
   if c[K.AWARENESS] ~= 0 then radius = 3 end
   if c[K.BLINDCOUNT] ~= 0 then radius = 0 end  -- blind: only the tile you stand on

   for j = math.max(1, y - radius), math.min(MAXY, y + radius) do
      for m = math.max(1, x - radius), math.min(MAXX, x + radius) do
         if know[m][j] == 0 then
            know[m][j] = 1
         end
      end
   end
   ns.ui:Refresh("map")
end

-- C: moveplayer(). Returns 1 if the player moved onto an empty tile (a run may go on),
-- otherwise 0. Walking into a monster attacks it.
function Display.moveplayer(dir)
   local ui = ns.ui
   if c[K.CONFUSE] ~= 0 and c[K.LEVEL] < ns.rnd(30) then
      dir = rund(9)  -- if confused any direction
   end

   if dir >= 1 then G.facing = dir end  -- the way the model of the player looks
   local k = G.playerx + DIROFFX[dir]
   local m = G.playery + DIROFFY[dir]
   if k < 1 or k > MAXX or m < 1 or m > MAXY then
      G.nomove = true
      ui.repcount = 0
      return 0
   end

   local object, monster = item[k][m], mon[k][m]

   if object == K.OWALL and c[K.WTW] == 0 then  -- hit a wall
      G.nomove = true
      ui.repcount = 0
      return 0
   end

   if k == 34 and m == MAXY and G.level == 1 then  -- the exit from the dungeon
      ns.Create.newCaveLevel(0)
      for x = 1, MAXX do
         for y = 1, MAXY do
            if item[x][y] == K.OENTRANCE then
               G.playerx, G.playery = x, y
               ns.Player.positionPlayer()
               ui:Refresh("all")
               return 0
            end
         end
      end
   end

   if monster > 0 then  -- hit a monster
      ns.Monster.hitmonster(k, m)
      ui.repcount = 0
      return 0
   end

   G.lastpx, G.lastpy = G.playerx, G.playery
   G.playerx, G.playery = k, m

   if object ~= 0 and object ~= K.OTRAPARROWIV and object ~= K.OIVTELETRAP
      and object ~= K.OIVDARTRAP and object ~= K.OIVTRAPDOOR then
      ui.repcount = 0
      return 0
   end
   return 1
end
