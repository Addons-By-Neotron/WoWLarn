--[[
**********************************************************************
WoWLarn - Monster movement (movem.c).
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
local rnd = ns.rnd

local Monster = ns.Monster

local c, iven = G.c, G.iven
local item, iarg, know, mon, hitp, stealth = G.item, G.iarg, G.know, G.mon, G.hitp, G.stealth
local DIROFFX, DIROFFY = ns.Display.DIROFFX, ns.Display.DIROFFY

local MAXX, MAXY = K.MAXX, K.MAXY
local DEMONLORD = K.DEMONLORD

-- Per-tile "already moved this turn" flags, and the proximity map of the smart monsters.
-- The map has a border of 127 (walls) so the ripple can look one tile past the level.
local moved, screen = {}, {}
for x = 0, MAXX + 1 do
   moved[x], screen[x] = {}, {}
   for y = 0, MAXY + 1 do
      moved[x][y], screen[x][y] = 0, 127
   end
end

-- The window of the level where monsters move, set by movemonst and used by movemt.
local tmp1, tmp2, tmp3, tmp4, distance = 0, 0, 0, 0, 0
local w1, w1x, w1y = {}, {}, {}
local tmpitem = 0

local function Clamp(v, low, high)
   return math.max(low, math.min(high, v))
end

-- C: teleportmonst(). Moves a monster, and what it carries, to a random free tile.
function Monster.teleportMonst(xx, yy, monst)
   for _ = 1, 10 do  -- max # of creation attempts
      local x, y = rnd(MAXX - 2) + 1, rnd(MAXY - 2) + 1
      if item[x][y] == 0 and mon[x][y] == 0 and (G.playerx ~= x or G.playery ~= y) then
         mon[x][y] = monst
         mon[xx][yy] = 0
         know[x][y] = 1
         know[xx][yy] = 0
         hitp[x][y] = G.monster[monst].hitpoints
         hitp[xx][yy] = 0
         G.loot[x * 100 + y] = G.loot[xx * 100 + yy]
         G.loot[xx * 100 + yy] = nil
         return
      end
   end
end

-- C: mmove(). Moves the monster from (aa, bb) to (cc, dd), or attacks the player there.
local function MMove(aa, bb, cc, dd)
   local monster = G.monster
   local ui = ns.ui
   if cc == G.playerx and dd == G.playery then
      Monster.hitplayer(aa, bb)
      moved[aa][bb] = 1
      return
   end

   local it = item[cc][dd]
   -- these monsters do not move onto pits or trapdoors
   if it == K.OPIT or it == K.OTRAPDOOR then
      local m = mon[aa][bb]
      local flies = m == K.SPIRITNAGA or m == K.PLATINUMDRAGON or m == K.WRAITH or m == K.VAMPIRE
         or m == K.SILVERDRAGON or m == K.POLTERGEIST or (m >= DEMONLORD and m <= K.LUCIFER)
      if not flies then
         mon[aa][bb] = 0  -- fell in a pit or trapdoor
         hitp[aa][bb] = 0
         ui:Refresh("map")
         return
      end
   end

   -- whatever the monster carries goes with it
   G.loot[cc * 100 + dd] = G.loot[aa * 100 + bb]
   G.loot[aa * 100 + bb] = nil

   local tmp = mon[aa][bb]
   mon[cc][dd] = tmp
   if it == K.OANNIHILATION then
      -- demons dispel spheres
      if tmp >= DEMONLORD then
         local talismans = 0
         for x = 1, K.IVENSIZE do
            if G.iven[x] == K.OSPHTALISMAN then talismans = talismans + 1 end
         end
         if talismans == 0 or (talismans ~= 0 and tmp == K.LUCIFER and rnd(10) > 7) then
            ui:Message(L["The %s dispels the sphere!"], monster[tmp].name)
            ns.Sphere.rmsphere(cc, dd)  -- delete the sphere
         else
            it, tmp = 0, 0
            mon[cc][dd] = 0  -- monster dead
         end
      else
         it, tmp = 0, 0
         mon[cc][dd] = 0  -- monster dead
      end
   end

   stealth[cc][dd] = 1
   local flag = 0

   -- set hit points
   hitp[cc][dd] = hitp[aa][bb]
   G.look[cc][dd] = G.look[aa][bb]  -- it keeps its look
   if hitp[cc][dd] < 0 then hitp[cc][dd] = 1 end

   if tmp == K.LEMMING then
      -- 2% chance moving a lemming creates a new lemming in the old spot
      if rnd(100) <= 2 and not Monster.lemmingsEnough() then
         mon[aa][bb] = K.LEMMING
         know[aa][bb] = 1
      else
         mon[aa][bb] = 0
      end
   else
      mon[aa][bb] = 0  -- no monster in the old coordinates
   end

   moved[cc][dd] = 1

   if tmp == K.LEPRECHAUN then  -- the leprechaun takes gold and gems
      if it == K.OGOLDPILE or it == K.OMAXGOLD or it == K.OKGOLD or it == K.ODGOLD
         or it == K.ODIAMOND or it == K.ORUBY or it == K.OEMERALD or it == K.OSAPPHIRE then
         local key = cc * 100 + dd
         local loot = G.loot[key]
         if not loot then
            loot = {}
            G.loot[key] = loot
         end
         if #loot < 6 then
            loot[#loot + 1] = { item[cc][dd], iarg[cc][dd] }
         end
         item[cc][dd], iarg[cc][dd] = 0, 0
      end
   end

   if tmp == K.TROLL then  -- a troll regenerates
      if G.gtime % 2 == 0 and monster[tmp].hitpoints > hitp[cc][dd] then
         hitp[cc][dd] = hitp[cc][dd] + 1
      end
   end

   local who
   if it == K.OTRAPARROW then  -- an arrow hits the monster
      who = L["An arrow"]
      hitp[cc][dd] = hitp[cc][dd] - (rnd(10) + G.level)
      if hitp[cc][dd] <= 0 then
         mon[cc][dd] = 0
         flag = 2
      else
         flag = 1
      end
   end

   if it == K.ODARTRAP then  -- a dart hits the monster
      who = L["A dart"]
      hitp[cc][dd] = hitp[cc][dd] - rnd(6)
      if hitp[cc][dd] <= 0 then
         mon[cc][dd] = 0
         flag = 2
      else
         flag = 1
      end
   end

   if tmp < DEMONLORD and it == K.OTELEPORTER then  -- the monster hits a teleport trap
      flag = 3
      Monster.teleportMonst(cc, dd, mon[cc][dd])
   end

   if tmp < DEMONLORD and (it == K.OELEVATORUP or it == K.OELEVATORDOWN) then
      mon[cc][dd] = 0
      flag = 4
   end

   if c[K.BLINDCOUNT] ~= 0 then return end  -- if blind don't show where the monsters are

   if know[cc][dd] ~= 0 and flag ~= 0 then
      local name = monster[tmp].name
      if flag == 1 then
         ui:Message(L["%s hits the %s."], who, name)
      elseif flag == 2 then
         ui:Message(L["%s hits and kills the %s."], who, name)
      elseif flag == 3 then
         ui:Message(L["The %s gets teleported."], name)
      elseif flag == 4 then
         ui:Message(L["The %s is carried away by an elevator!"], name)
      end
   end

   if tmp >= DEMONLORD and tmp <= K.LUCIFER and c[K.EYEOFLARN] == 0 then
      return
   end
   if know[aa][bb] ~= 0 or know[cc][dd] ~= 0 then
      ui:Refresh("map")
   end
end

-- C: movemt(). Works out where the monster at (i, j) moves.
local function MoveMT(i, j)
   local monst = mon[i][j]
   local monster = G.monster

   if monst == K.TROGLODYTE or monst == K.HOBGOBLIN or monst == K.METAMORPH or monst == K.XVART
      or monst == K.INVISIBLESTALKER or monst == K.ICELIZARD then  -- half speed monsters
      if G.gtime % 2 == 1 then return end
   end

   -- choose the destination randomly if scared
   local tmp = 0
   for x = 1, K.IVENSIZE do
      if iven[x] == K.OHANDofFEAR then
         tmp = 1
         break
      end
   end
   if c[K.SCAREMONST] ~= 0 then
      if tmp == 1 then tmp = 2 end
   elseif tmp == 1 and rnd(10) > 4 then
      tmp = 0
   end

   if monst > DEMONLORD or monst == K.PLATINUMDRAGON then
      if tmp == 1 then
         tmp = 0
      else
         tmp = rnd(10) > 5 and 1 or 0
      end
   end

   if tmp ~= 0 then
      local xl = Clamp(i + rnd(3) - 2, 1, MAXX)
      local yl = Clamp(j + rnd(3) - 2, 1, MAXY)
      local here = item[xl][yl]
      if here ~= K.OWALL and mon[xl][yl] == 0 then
         if mon[i][j] ~= K.VAMPIRE or tmpitem ~= K.OMIRROR then
            if here ~= K.OCLOSEDDOOR then
               MMove(i, j, xl, yl)
            end
         end
      end
      return
   end

   -- intelligent movement here -- first set up the screen array
   if monster[monst].intelligence > 10 - c[K.HARDGAME] then  -- a smart monster
      local xl, yl = Clamp(tmp3 - 2, 1, MAXX), Clamp(tmp1 - 2, 1, MAXY)
      local xh, yh = Clamp(tmp4 + 2, 1, MAXX), Clamp(tmp2 + 2, 1, MAXY)
      for k = yl, yh - 1 do
         for m = xl, xh - 1 do
            if G.level == 1 and m == 34 and k == MAXY then
               screen[m][k] = 127
            elseif monst >= K.DEMONPRINCE then
               screen[m][k] = 0
            else
               local it = item[m][k]
               if it == K.OWALL or it == K.OELEVATORUP or it == K.OELEVATORDOWN or it == K.OPIT
                  or it == K.OTRAPARROW or it == K.ODARTRAP or it == K.OCLOSEDDOOR
                  or it == K.OTRAPDOOR or it == K.OTELEPORTER
                  or (it == K.OMIRROR and mon[m][k] == K.VAMPIRE) then
                  screen[m][k] = 127
               else
                  screen[m][k] = 0
               end
            end
         end
      end
      screen[G.playerx][G.playery] = 1

      -- now perform the proximity ripple from the player to the monster
      xl, yl = Clamp(tmp3 - 1, 1, MAXX), Clamp(tmp1 - 1, 1, MAXY)
      xh, yh = Clamp(tmp4 + 1, 1, MAXX), Clamp(tmp2 + 1, 1, MAXY)

      local found = false
      tmp = 1
      while tmp < distance and not found do  -- only up to `distance` squares away
         for k = yl, yh - 1 do
            for m = xl, xh - 1 do
               if screen[m][k] == tmp then  -- found proximity n, advance it
                  for z = 1, 8 do  -- go around in a circle
                     local xtmp, ytmp = m + DIROFFX[z], k + DIROFFY[z]
                     if screen[xtmp][ytmp] == 0 then
                        screen[xtmp][ytmp] = tmp + 1
                     end
                     if xtmp == i and ytmp == j then
                        found = true
                        break
                     end
                  end
               end
               if found then break end
            end
            if found then break end
         end
         if not found then tmp = tmp + 1 end
      end

      if tmp < distance then  -- did find connectivity
         -- now select the lowest value around the monster
         for z = 1, 8 do
            local x2, y2 = i + DIROFFX[z], j + DIROFFY[z]
            if screen[x2] and screen[x2][y2] == tmp and mon[x2][y2] == 0 then
               w1x[0], w1y[0] = x2, y2
               MMove(i, j, x2, y2)
               return
            end
         end
      end
   end

   -- dumb monsters move here
   local xl, yl, xh, yh = i - 1, j - 1, i + 2, j + 2
   if i < G.playerx then
      xl = xl + 1
   elseif i > G.playerx then
      xh = xh - 1
   end
   if j < G.playery then
      yl = yl + 1
   elseif j > G.playery then
      yh = yh - 1
   end

   for k = 0, 8 do
      w1[k] = 10000
   end

   -- for each square compute the distance to the player
   for k = xl, xh - 1 do
      for m = yl, yh - 1 do
         if k >= 1 and k <= MAXX and m >= 1 and m <= MAXY
            and not (k == 34 and m == MAXY and G.level == 1) then
            local index = k - i + 4 + 3 * (m - j)
            tmpitem = item[k][m]
            if tmpitem ~= K.OWALL or (k == G.playerx and m == G.playery) then
               if mon[k][m] == 0 then  -- no monster already there
                  if mon[i][j] ~= K.VAMPIRE or tmpitem ~= K.OMIRROR then  -- vampires keep away from mirrors
                     if tmpitem ~= K.OCLOSEDDOOR then  -- and monsters from closed doors
                        w1[index] = (G.playerx - k) ^ 2 + (G.playery - m) ^ 2
                        w1x[index] = k
                        w1y[index] = m
                     end
                  end
               end
            end
         end
      end
   end

   tmp = 0
   for k = 1, 8 do
      if w1[tmp] > w1[k] then
         tmp = k
      end
   end

   if w1[tmp] < 10000 then
      if i ~= w1x[tmp] or j ~= w1y[tmp] then
         MMove(i, j, w1x[tmp], w1y[tmp])
      end
   end
end

-- C: movemonst(). Moves the monsters toward the player.
function Monster.movemonst()
   if c[K.TIMESTOP] ~= 0 then return end  -- no action if time is stopped
   if c[K.HASTESELF] ~= 0 and c[K.HASTESELF] % 2 == 0 then return end
   if #G.spheres > 0 then ns.Sphere.movsphere() end  -- move the spheres of annihilation
   if c[K.HOLDMONST] ~= 0 then return end  -- no action if monsters are held

   -- determine the window of monsters to move; the C works with 0-based coordinates
   if c[K.AGGRAVATE] ~= 0 then
      tmp1, tmp2 = G.playery - 5, G.playery + 6
      tmp3, tmp4 = G.playerx - 10, G.playerx + 11
      distance = 40  -- depth of intelligent monster movement
   else
      tmp1, tmp2 = G.playery - 3, G.playery + 4
      tmp3, tmp4 = G.playerx - 5, G.playerx + 6
      distance = 17
   end

   if G.level == 0 then  -- outside, monsters can move in the perimeter
      tmp1, tmp2 = math.max(tmp1, 1), math.min(tmp2, MAXY + 1)
      tmp3, tmp4 = math.max(tmp3, 1), math.min(tmp4, MAXX + 1)
   else  -- in a dungeon the perimeter is a wall
      tmp1, tmp2 = math.max(tmp1, 2), math.min(tmp2, MAXY)
      tmp3, tmp4 = math.max(tmp3, 2), math.min(tmp4, MAXX)
   end

   for j = tmp1, tmp2 - 1 do  -- now reset the monster moved flags
      for i = tmp3, tmp4 - 1 do
         moved[i][j] = 0
      end
   end
   moved[G.lasthx][G.lasthy] = 0

   if c[K.AGGRAVATE] ~= 0 or c[K.STEALTH] == 0 then  -- who gets moved?
      for j = tmp1, tmp2 - 1 do  -- look through all locations in the window
         for i = tmp3, tmp4 - 1 do
            if mon[i][j] ~= 0 and moved[i][j] == 0 then
               MoveMT(i, j)
            end
         end
      end
   else  -- stealthy and not aggravated: only the awake monsters move
      for j = tmp1, tmp2 - 1 do
         for i = tmp3, tmp4 - 1 do
            if mon[i][j] ~= 0 and moved[i][j] == 0 and stealth[i][j] ~= 0 then
               MoveMT(i, j)
            end
         end
      end
   end

   -- now move the monster last hit by the player, if not already moved
   if mon[G.lasthx][G.lasthy] ~= 0 and moved[G.lasthx][G.lasthy] == 0 then
      MoveMT(G.lasthx, G.lasthy)
      G.lasthx, G.lasthy = w1x[0] or G.lasthx, w1y[0] or G.lasthy
   end
end
