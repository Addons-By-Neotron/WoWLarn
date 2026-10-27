--[[
**********************************************************************
WoWLarn - Player and level creation (create.c).
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
local rnd = ns.rnd

local Create = {}
ns.Create = Create

local c, iven, ivenarg, spelknow = G.c, G.iven, G.ivenarg, G.spelknow
local item, iarg, know, mon = G.item, G.iarg, G.know, G.mon

local MAXX, MAXY = K.MAXX, K.MAXY

-- C: makeplayer() and pick_char(). class is an entry of ns.Classes.
function Create.makePlayer(class)
   c[K.LEVEL] = 1
   c[K.REGENCOUNTER] = 16
   c[K.ECOUNTER] = 96  -- start regeneration correctly
   c[K.SHIELD], c[K.WEAR], c[K.WIELD] = 0, 0, 0  -- 0 is nothing (C: -1)

   for i = 1, 6 do
      c[K.STRENGTH + i - 1] = class.stats[i]
   end
   c[K.HPMAX], c[K.HP] = class.hp, class.hp
   c[K.SPELLMAX], c[K.SPELLS] = class.spellmax, class.spellcount
   for _, spell in ipairs(class.spells) do
      spelknow[spell] = 1
   end
   for slot, entry in ipairs(class.kit) do
      iven[slot] = entry[1]
      ivenarg[slot] = entry[2] == "random" and rnd(6) or entry[2]
   end
   c[K.WEAR] = class.wear or 0
   c[K.WIELD] = class.wield or 0
   if class.lanceofdeath then
      c[K.LANCEDEATH] = 1
   end

   G.class = class
   G.playerx = rnd(MAXX - 2) + 1
   G.playery = rnd(MAXY - 2) + 1
   G.gtime = 0
   ns.Player.recalc()
end

-- C: fillroom(). Puts an object on a random free tile.
function Create.fillRoom(what, arg)
   local x, y = rnd(MAXX - 2) + 1, rnd(MAXY - 2) + 1
   while item[x][y] ~= 0 do
      x = x + rnd(3) - 2
      y = y + rnd(3) - 2
      if x > MAXX - 1 then x = 2 end
      if x < 2 then x = MAXX - 1 end
      if y > MAXY - 1 then y = 2 end
      if y < 2 then y = MAXY - 1 end
   end
   item[x][y] = what
   iarg[x][y] = arg
end

-- C: makemaze(). Dungeon levels come in milestone 3; the town is an empty field.
function Create.makeMaze(lev)
   if lev > 0 then
      error("Dungeon levels are not implemented yet (milestone 3)")
   end
   -- item[][] is already clear.
end

-- C: makeobject(). Only the town so far.
function Create.makeObject(lev)
   if lev == 0 then
      Create.fillRoom(K.OENTRANCE, 0)  -- entrance to the dungeon
      Create.fillRoom(K.ODNDSTORE, 0)
      Create.fillRoom(K.OSCHOOL, 0)    -- college of Larn
      Create.fillRoom(K.OBANK, 0)      -- 1st national bank of Larn
      Create.fillRoom(K.OVOLDOWN, 0)   -- volcano shaft to the temple
      Create.fillRoom(K.OHOME, 0)      -- the player's home and family
      Create.fillRoom(K.OTRADEPOST, 0)
      Create.fillRoom(K.OLRS, 0)       -- Larn Revenue Service
      return
   end
   error("Dungeon levels are not implemented yet (milestone 3)")
end

-- C: sethp(). Monsters arrive in milestone 4; the town has none.
function Create.setHP(flag)
   if flag then
      G.FillStealth(0)
   end
   if G.level == 0 then
      c[K.TELEFLAG] = 0
      return
   end
end

-- C: newcavelevel(). Must be called whenever the player changes level.
function Create.newCaveLevel(x)
   if G.Visited(G.level) then
      G.SaveLevel()
   end
   G.level = x
   if G.Visited(x) then
      G.GetLevel()
      Create.setHP(false)
      return
   end
   G.ClearLevel()
   Create.makeMaze(x)
   Create.makeObject(x)
   G.SetVisited(x)
   Create.setHP(true)
   if G.wizard or x == 0 then
      G.FillKnow(1)
   end
end
