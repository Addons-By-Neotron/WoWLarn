--[[
**********************************************************************
WoWLarn - Standing on objects (object.c). Stairs, entrance and shafts so far.
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
local G = ns.G

local Object = {}
ns.Object = Object

local K = ns.K
local Create = ns.Create
local DBOTTOM, VBOTTOM, MAXX, MAXY = K.DBOTTOM, K.VBOTTOM, K.MAXX, K.MAXY

-- Puts the player on the first tile holding the given object (C: the search loops after
-- changing level).
local function MoveToObject(what)
   for x = 1, MAXX do
      for y = 1, MAXY do
         if G.item[x][y] == what then
            G.playerx, G.playery = x, y
            return
         end
      end
   end
end

-- C: ostairs(dir). dir > 0 is a staircase going up, otherwise one going down.
local function Stairs(dir)
   local ui = ns.ui
   local choice = ui:Choose(dir > 0 and L["Do you (s) stay here or (u) go up?"]
      or L["Do you (s) stay here or (d) go down?"], dir > 0 and "su" or "sd")
   if choice == "s" or choice == "i" then return end
   local level = G.level
   if choice == "u" then
      if dir < 0 then
         ui:Message(L["The stairs don't go up!"])
      elseif level >= 2 and level ~= DBOTTOM + 1 then  -- not on V1
         Create.newCaveLevel(level - 1)
         MoveToObject(K.OSTAIRSDOWN)
         ui:Refresh("all")
      else
         ui:Message(L["The stairs lead to a dead end!"])
      end
   else
      if dir > 0 then
         ui:Message(L["The stairs don't go down!"])
      elseif level ~= 0 and level ~= DBOTTOM and level ~= VBOTTOM then  -- not on the bottom
         Create.newCaveLevel(level + 1)
         MoveToObject(K.OSTAIRSUP)
         ui:Refresh("all")
      else
         ui:Message(L["The stairs lead to a dead end!"])
      end
   end
end

-- C: lookforobject(). Everything you can step on does something; the town buildings and
-- the dungeon features arrive in later milestones.
function Object.lookForObject()
   if G.c[K.TIMESTOP] ~= 0 then return end  -- can't find objects if time is stopped
   local id = G.item[G.playerx][G.playery]
   if id == 0 then return end

   local ui = ns.ui
   ns.Display.showcell(G.playerx, G.playery)
   ui.repcount = 0
   local name = ns.Tables.objectname[id]

   if id == K.OENTRANCE then
      ui:Message(L["You have found %s"], name)
      if ui:Choose(L["Do you (g) go inside, or (i) ignore it?"], "g") == "g" then
         Create.newCaveLevel(1)
         G.playerx, G.playery = 34, MAXY - 1
         G.item[34][MAXY], G.know[34][MAXY], G.mon[34][MAXY] = 0, 0, 0
         ui:Refresh("all")
      end
   elseif id == K.OVOLDOWN then
      ui:Message(L["You have found %s"], name)
      if ui:Choose(L["Do you (c) climb down, or (i) ignore it?"], "c") == "i" then return end
      if G.level ~= 0 then
         ui:Message(L["The shaft only extends 5 feet downward!"])
         return
      end
      if ns.Player.packWeight() > 45 + 3 * (G.c[K.STRENGTH] + G.c[K.STREXTRA]) then
         ui:Message(L["You slip and fall down the shaft."])
         G.lastnum = 275
         ns.Player.losehp(30 + ns.rnd(20))
         if G.dead then return end
      else
         ui:Message(L["You climb down."])
      end
      ui:Nap(3000)
      Create.newCaveLevel(DBOTTOM + 1)  -- down to V1
      G.playerx, G.playery = ns.rnd(MAXX - 2) + 1, ns.rnd(MAXY - 2) + 1
      ns.Player.positionPlayer()
      ui:Refresh("all")
   elseif id == K.OVOLUP then
      ui:Message(L["You have found %s"], name)
      if ui:Choose(L["Do you (c) climb up, or (i) ignore it?"], "c") == "i" then return end
      local c = G.c
      if ns.Player.packWeight() > 40 + 5 * (c[K.DEXTERITY] + c[K.STRENGTH] + c[K.STREXTRA]) then
         ui:Message(L["You slip and fall down the shaft."])
         G.lastnum = 275
         ns.Player.losehp(15 + ns.rnd(20))
         return
      end
      ui:Message(L["You climb up."])
      ui:Nap(3000)
      Create.newCaveLevel(0)
      MoveToObject(K.OVOLDOWN)  -- put the player near the volcano shaft
      ns.Player.positionPlayer()
      ui:Refresh("all")
   elseif id == K.OSTAIRSUP then
      ui:Message(L["There is a circular staircase here."])
      Stairs(1)
   elseif id == K.OSTAIRSDOWN then
      ui:Message(L["There is a circular staircase here."])
      Stairs(-1)
   elseif name then
      ui:Message(L["There is %s here. (Not implemented yet.)"], name)
   end
end
