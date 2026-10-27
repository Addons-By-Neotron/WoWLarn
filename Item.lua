--[[
**********************************************************************
WoWLarn - Item creation (monster.c: cgood, createitem, something, newobject).
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
local rnd, rund, idiv = ns.rnd, ns.rund, ns.idiv

local Item = {}
ns.Item = Item

local I = ns.ItemTables
local c, item, iarg, know, mon = G.c, G.item, G.iarg, G.know, G.mon
local DIROFFX, DIROFFY = ns.Display.DIROFFX, ns.Display.DIROFFY

local MAXX, MAXY, VBOTTOM = K.MAXX, K.MAXY, K.VBOTTOM

-- C: scprob[rund(82)] and potprob[rund(42)] roll one past the end of their tables. The C
-- reads the first byte of the next array in data.c, a zero, which is the first scroll or
-- potion here.
local function Pick(tab, count)
   return tab[rund(count) + 1] or tab[1]
end

-- The armor and weapon tables are also rolled past their end in places; the C reads a zero.
local function PickOrZero(tab, count)
   return tab[rund(count) + 1] or 0
end

function Item.newScroll() return Pick(I.scprob, 82) end
function Item.newPotion() return Pick(I.potprob, 42) end
function Item.newDagger() return PickOrZero(I.ndgg, 13) end
function Item.newLeather() return PickOrZero(I.nlpts, c[K.HARDGAME] ~= 0 and 10 or 13) end
function Item.newChain() return PickOrZero(I.nch, 11) end
function Item.newPlate() return PickOrZero(I.nplt, c[K.HARDGAME] ~= 0 and 3 or 11) end
function Item.newSword() return PickOrZero(I.nsw, c[K.HARDGAME] ~= 0 and 6 or 14) end

-- C: cgood(). True if the tile is inside the level, is not a wall or closed door, and is
-- free of an item and/or a monster as asked. The exit from level 1 is never good.
function Item.cgood(x, y, wantNoItem, wantNoMonster)
   if y >= 1 and y <= MAXY and x >= 1 and x <= MAXX then
      if item[x][y] ~= K.OWALL and item[x][y] ~= K.OCLOSEDDOOR then
         if not wantNoItem or item[x][y] == 0 then
            if not wantNoMonster or mon[x][y] == 0 then
               if G.level ~= 1 or x ~= 34 or y ~= MAXY then
                  return true
               end
            end
         end
      end
   end
   return false
end

local cgood = Item.cgood

-- C: createitem(). Places an item on a free tile next to (x, y); gold is added to a pile.
function Item.createItem(x, y, it, arg)
   if it >= K.MAXOBJ then return end  -- no such object

   local k = rnd(8)
   for _ = 1, 8 do
      if k > 8 then k = 1 end  -- wraparound the diroff arrays
      x = x + DIROFFX[k]
      y = y + DIROFFY[k]
      k = k + 1
      if it ~= K.OMAXGOLD and it ~= K.OGOLDPILE then
         if cgood(x, y, true, false) then
            item[x][y] = it
            know[x][y] = 0
            iarg[x][y] = arg
            return
         end
      else
         local here = (x >= 1 and x <= MAXX and y >= 1 and y <= MAXY) and item[x][y] or 0
         if here == K.OGOLDPILE or here == K.ODGOLD or here == K.OMAXGOLD or here == K.OKGOLD then
            -- The C switch falls through from the smaller piles to the larger ones.
            local stage = here
            if stage == K.OGOLDPILE then
               if iarg[x][y] + arg < 32767 then
                  iarg[x][y] = iarg[x][y] + arg
                  return
               end
               stage = K.ODGOLD
            end
            if stage == K.ODGOLD then
               if 10 * iarg[x][y] + arg < 327670 then
                  iarg[x][y] = idiv(10 * iarg[x][y] + arg, 10)
                  item[x][y] = K.ODGOLD
                  return
               end
               stage = K.OMAXGOLD
            end
            if stage == K.OMAXGOLD then
               if 100 * iarg[x][y] + arg < 3276700 then
                  iarg[x][y] = idiv(100 * iarg[x][y] + arg, 100)
                  item[x][y] = K.OMAXGOLD
                  return
               end
               stage = K.OKGOLD
            end
            if 1000 * iarg[x][y] + arg <= 32767000 then
               iarg[x][y] = idiv(1000 * iarg[x][y] + arg, 1000)
               item[x][y] = K.OKGOLD
            else
               iarg[x][y] = 32767
            end
            return
         elseif cgood(x, y, true, false) then
            item[x][y] = it
            know[x][y] = 0
            if it == K.OMAXGOLD then
               iarg[x][y] = idiv(arg, 100)
            else
               iarg[x][y] = arg
            end
            return
         end
      end
   end
end

-- C: dropgold(). Drops gold around the player.
function Item.dropGold(amount)
   if amount > 250 then
      Item.createItem(G.playerx, G.playery, K.OMAXGOLD, amount)
   else
      Item.createItem(G.playerx, G.playery, K.OGOLDPILE, amount)
   end
end

-- C: newobject(). Returns the object id and its argument for a random object found on
-- cave level lev. Id 0 means nothing was made.
function Item.newObject(lev)
   if G.level < 0 or G.level > VBOTTOM then return 0, 0 end

   local tmp = 32
   if lev > 6 then
      tmp = 37
   elseif lev > 4 then
      tmp = 35
   end
   tmp = rnd(tmp)
   local id = I.nobjtab[tmp]  -- the object type
   local arg = 0
   if tmp <= 4 then
      arg = Item.newScroll()
   elseif tmp <= 8 then
      arg = Item.newPotion()
   elseif tmp <= 12 then
      arg = rnd((lev + 1) * 10) + lev * 10 + 10
   elseif tmp <= 16 then
      arg = lev
   elseif tmp <= 19 then
      arg = Item.newDagger()
      if arg == 0 then return 0, 0 end
   elseif tmp <= 22 then
      arg = Item.newLeather()
      if arg == 0 then return 0, 0 end
   elseif tmp == 23 or tmp == 32 or tmp == 35 then
      arg = rund(idiv(lev, 3) + 1)
   elseif tmp == 24 or tmp == 26 then
      arg = rnd(idiv(lev, 4) + 1)
   elseif tmp == 25 then
      arg = rund(idiv(lev, 4) + 1)
   elseif tmp == 27 then
      arg = rnd(idiv(lev, 2) + 1)
   elseif tmp == 28 then
      arg = rund(idiv(lev, 3) + 1)
      if arg == 0 then return 0, 0 end
   elseif tmp == 29 or tmp == 31 then
      arg = rund(idiv(lev, 2) + 1)
      if arg == 0 then return 0, 0 end
   elseif tmp == 30 or tmp == 33 then
      arg = rund(idiv(lev, 2) + 1)
   elseif tmp == 34 then
      arg = Item.newChain()
   elseif tmp == 36 then
      arg = Item.newPlate()
   elseif tmp == 37 then
      arg = Item.newSword()
   end
   return id, arg
end

-- C: something(). Creates a random item around (x, y); possibly more than one.
function Item.something(x, y, lev)
   if lev < 0 or lev > VBOTTOM then return end
   if rnd(101) < 8 then
      Item.something(x, y, lev)
   end
   local id, arg = Item.newObject(lev)
   Item.createItem(x, y, id, arg)
end

-- C: creategem(). A gem on a square near the player.
function Item.createGem()
   local id, j
   local roll = rnd(4)
   if roll == 1 then
      id, j = K.ODIAMOND, 50
   elseif roll == 2 then
      id, j = K.ORUBY, 40
   elseif roll == 3 then
      id, j = K.OEMERALD, 30
   else
      id, j = K.OSAPPHIRE, 20
   end
   Item.createItem(G.playerx, G.playery, id, rnd(j) + idiv(j, 10))
end
