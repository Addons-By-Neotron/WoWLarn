--[[
**********************************************************************
WoWLarn - a port of Ularn 1.5 to World of Warcraft
**********************************************************************
This file is part of WoWLarn, a World of Warcraft addon.

WoWLarn is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, version 2 of the
License.

WoWLarn is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with WoWLarn. If
not, see <http://www.gnu.org/licenses/>.
**********************************************************************
]]
local L = LibStub("AceLocale-3.0"):GetLocale("WoWLarn")
local _, ns = ...
local K = ns.K
local G = ns.G
local rnd, idiv = ns.rnd, ns.idiv

-- The spheres of annihilation (C: sphere.c). G.spheres holds {x, y, lev, dir, lifetime}
-- for every sphere of every level, newest first; c[SPHCAST] counts them.
local Sphere = {}
ns.Sphere = Sphere

local c, iven = G.c, G.iven
local item, know, mon, hitp = G.item, G.know, G.mon, G.hitp
local MAXX, MAXY = K.MAXX, K.MAXY

local function Msg(fmt, ...)
   ns.ui:Message(fmt, ...)
end

local function HasTalisman()
   for i = 1, K.IVENSIZE do
      if iven[i] == K.OSPHTALISMAN then return true end
   end
   return false
end

-- C: rmsphere(). Deletes the sphere of this level that is at (x, y).
function Sphere.rmsphere(x, y)
   local spheres = G.spheres
   for index, sp in ipairs(spheres) do
      if sp.lev == G.level and sp.x == x and sp.y == y then
         item[x][y], mon[x][y] = 0, 0
         know[x][y] = 1
         ns.ui:Refresh("map")  -- show the now missing sphere
         c[K.SPHCAST] = c[K.SPHCAST] - 1
         table.remove(spheres, index)
         break
      end
   end
end

-- C: sphboom(). The blast of a detonating sphere.
function Sphere.sphboom(x, y)
   if c[K.HOLDMONST] ~= 0 then c[K.HOLDMONST] = 1 end
   if c[K.CANCELLATION] ~= 0 then c[K.CANCELLATION] = 1 end
   -- the C runs 1..MAXX-2 here, which is 2..MAXX-1
   for j = math.max(2, x - 2), math.min(x + 2, MAXX - 1) do
      for i = math.max(2, y - 2), math.min(y + 2, MAXY - 1) do
         item[j][i], mon[j][i] = 0, 0
         ns.ui:Refresh("map")
         if HasTalisman() then return end  -- (the C checks this after the first tile)
         if G.playerx == j and G.playery == i then
            Msg(L["You were too close to the sphere!"])
            ns.ui:Nap(3000)
            ns.Player.died(283)  -- player killed in explosion
            return
         end
      end
   end
end

-- C: newsphere(). Makes a sphere at (x, y) that moves in direction dir (0..8) for life turns.
function Sphere.newsphere(x, y, dir, life)
   local monster = G.monster
   if dir >= 9 then dir = 0 end  -- no movement if direction not found
   if G.level == 0 then
      x, y = ns.vxy(x, y)  -- don't go out of bounds
   else
      x, y = math.max(2, math.min(MAXX - 1, x)), math.max(2, math.min(MAXY - 1, y))
   end

   local function boom()
      Sphere.sphboom(x, y)  -- blow up stuff around the sphere
      Sphere.rmsphere(x, y)  -- remove any spheres that are here
   end

   if not HasTalisman() then
      -- demons dispel spheres
      local m = mon[x][y]
      if m >= K.DEMONLORD then
         local hp = hitp[x][y]
         know[x][y] = 1
         ns.ui:Refresh("map")  -- show the demon (ha ha)
         Msg(L["The %s dispels the sphere!"], monster[m].name)
         Sphere.rmsphere(x, y)  -- remove any spheres that are here
         mon[x][y] = m
         hitp[x][y] = hp
         know[x][y] = 0
      end

      -- the disenchantress cancels spheres
      if m == K.DISENCHANTRESS then
         Msg(L["The %s cancels the sphere!"], monster[m].name)
         boom()
      end

      -- cancellation cancels spheres
      if c[K.CANCELLATION] ~= 0 then
         Msg(L["As the cancellation takes effect, you hear a great earth shaking blast!"])
         boom()
      end

      -- collision of sphere and player!
      if G.playerx == x and G.playery == y then
         Msg(L["You have been enveloped by the zone of nothingness!"])
         Sphere.rmsphere(x, y)  -- remove any spheres that are here
         ns.ui:Nap(4000)
         ns.Player.died(258)
         return
      end
   end

   -- collision of spheres detonates spheres
   if item[x][y] == K.OANNIHILATION then
      Msg(L["Two spheres of annihilation collide! You hear a great earth-shaking blast!"])
      Sphere.rmsphere(x, y)
      boom()
   end
   if G.dead then return end

   item[x][y] = K.OANNIHILATION
   mon[x][y] = 0
   know[x][y] = 1
   ns.ui:Refresh("map")  -- show the new sphere
   table.insert(G.spheres, 1, { x = x, y = y, lev = G.level, dir = dir, lifetime = life })
   c[K.SPHCAST] = c[K.SPHCAST] + 1
end

-- C: movsphere(). Moves the spheres of this level. They eat anything in their way, except
-- for upper level demons, who can dispel them.
function Sphere.movsphere()
   local DIROFFX, DIROFFY = ns.Display.DIROFFX, ns.Display.DIROFFY
   -- first duplicate the list, as moving a sphere changes it
   local copy = {}
   for _, sp in ipairs(G.spheres) do
      if sp.lev == G.level then
         copy[#copy + 1] = { x = sp.x, y = sp.y, dir = sp.dir, lifetime = sp.lifetime }
      end
   end

   for _, sp in ipairs(copy) do
      local x, y = sp.x, sp.y
      if item[x][y] == K.OANNIHILATION then  -- (otherwise it is not really there)
         sp.lifetime = sp.lifetime - 1
         if sp.lifetime < 0 then  -- has the sphere run out of gas?
            Sphere.rmsphere(x, y)
         else
            -- time to move the sphere
            local roll = rnd(math.max(7, idiv(c[K.INTELLIGENCE], 2)))
            if roll == 1 or roll == 2 then  -- change direction to a random one
               sp.dir = rnd(8)
            end
            local dir, len = sp.dir, sp.lifetime
            Sphere.rmsphere(x, y)
            Sphere.newsphere(x + DIROFFX[dir], y + DIROFFY[dir], dir, len)
            if G.dead then return end
         end
      end
   end
end
