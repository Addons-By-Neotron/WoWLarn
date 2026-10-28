--[[
**********************************************************************
WoWLarn - The game loop and command dispatch (main.c).
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

local Game = {}
ns.Game = Game

local ui = ns.ui
local c = G.c
local Display, Monster, Regen = ns.Display, ns.Monster, ns.Regen

local RUN_DELAY = 30  -- milliseconds between the steps of a run

-- C: parse2(). The monsters and the clock move on without the player acting.
function Game.parse2()
   if c[K.HASTEMONST] ~= 0 then Monster.movemonst() end
   Monster.movemonst()
   Monster.randMonst()
   ns.Regen.regen()
end

-- C: main.c:parse(). Movement keys; the capital letter runs.
local MOVE = { j = 1, l = 2, k = 3, h = 4, u = 5, y = 6, n = 7, b = 8 }
local RUN = { J = 1, L = 2, K = 3, H = 4, U = 5, Y = 6, N = 7, B = 8 }

-- C: run().
local function Run(dir)
   local moved = 1
   while moved ~= 0 do
      moved = Display.moveplayer(dir)
      if moved > 0 then
         if c[K.HASTEMONST] ~= 0 then Monster.movemonst() end
         Monster.movemonst()
         Monster.randMonst()
         Regen.regen()
      end
      if G.hitflag or G.dead then moved = 0 end
      if moved ~= 0 then
         Display.showcell(G.playerx, G.playery)
         ui:Nap(RUN_DELAY)
      end
   end
end

-- Logs a page of text one line at a time.
local function LogPage(page)
   for line in (page .. "\n"):gmatch("(.-)\n") do
      ui:Log("system", "%s", line)
   end
end

-- C: parse(). Gets and executes one command. Returns true if the game is over.
local function Parse()
   local key = ui:GetCommand()

   if MOVE[key] then
      Display.moveplayer(MOVE[key])
   elseif RUN[key] then
      Run(RUN[key])
   elseif key == "." then  -- stay here
      if ui.repcount > 0 then G.viewflag = true end
   elseif key == " " then
      ui.repcount = 0
      G.nomove = true
   elseif key == "S" then  -- the game stays where it is while the window is closed
      ui.repcount = 0
      G.nomove = true
      ns.main:Hide()
   elseif key == "Q" then
      ui.repcount = 0
      G.nomove = true
      if ui:YesNo(L["Do you really want to quit?"]) == "y" then
         G.dead = ns.Scores.QUIT
         return true
      end
   elseif key == "w" then
      ui.repcount = 0
      ns.Action.wield()
   elseif key == "W" then
      ui.repcount = 0
      ns.Action.wear()
   elseif key == "T" then
      ui.repcount = 0
      ns.Action.takeOff()
   elseif key == "r" then
      ui.repcount = 0
      if c[K.BLINDCOUNT] ~= 0 then
         ui:Message(L["You can't read anything when you're blind!"])
      elseif c[K.TIMESTOP] == 0 then
         ns.Action.read()
      end
   elseif key == "q" then
      ui.repcount = 0
      if c[K.TIMESTOP] == 0 then ns.Action.quaff() end
   elseif key == "d" then
      ui.repcount = 0
      if c[K.TIMESTOP] == 0 then ns.Action.drop() end
   elseif key == "e" then
      ui.repcount = 0
      if c[K.TIMESTOP] == 0 then ns.Action.eat() end
   elseif key == "C" then
      ui.repcount = 0
      ns.Action.closeDoor()
   elseif key == "c" then
      ui.repcount = 0
      ns.Spells.cast()
   elseif key == "D" then
      ui.repcount = 0
      G.nomove = true
      ui:ShowDiscoveries()
   elseif key == "i" then
      ui.repcount = 0
      G.nomove = true
      ui:ShowInventory()
   elseif key == "g" then
      ui.repcount = 0
      G.nomove = true
      ns.Action.packWeight()
   elseif key == "^" then
      ui.repcount = 0
      ns.Action.findTraps()
   elseif key == "Z" then
      ui.repcount = 0
      ns.Action.teleport()
   elseif key == "v" then
      ui.repcount = 0
      G.nomove = true
      ui:Message(L["WoWLarn - a port of Ularn 1.5 (the Addiction of Ularn)."])
   elseif key == "?" then
      ui.repcount = 0
      G.nomove = true
      LogPage(ns.HelpPages[2])
   else
      ui.repcount = 0
      G.nomove = true
      ui:Message(L["That command is not implemented yet."])
   end
   return false
end

-- C: welcome().
local function Welcome()
   LogPage(ns.HelpPages[1])
   ui:More()
end

local function DefaultClass()
   local _, token = UnitClass("player")
   for index, class in ipairs(ns.Classes) do
      if class.token == token then return index end
   end
   return 1
end

-- C: died(), once the game is over: keeps the score and shows how it ended.
local function Finish()
   local cause = G.dead
   if type(cause) ~= "number" then cause = 284 end
   ns.Save.clear()  -- (one life)
   local entry = ns.Scores.record(cause)
   ui:Sound(cause == ns.Scores.WIN and "win" or cause ~= ns.Scores.QUIT and "death" or nil)
   ui:Log("damage", "%s %s", G.name, ns.Scores.deathLine(cause))
   ui:Log("system", L["Score: %d   Difficulty: %d"], c[K.GOLD], c[K.HARDGAME])
   if entry then ns.scoreboard:Show(entry) end
   if entry and cause == ns.Scores.WIN then
      for _, letter in ipairs(ns.Scores.letters()) do
         ui:Log("system", "|cffffd100%s|r - %s", letter[1], letter[2])
         ui:Log("system", "%s", letter[3])
      end
   end
   ui:Log("system", L["Game over. Press any key to start again."])
end

function Game.Run()
   G.Reset()
   G.name = UnitName("player")
   G.sex = UnitSex("player") == 3 and 0 or 1  -- C: 1 is a man, 0 a woman
   G.taxes = ns.Scores.taxes()  -- what the LRS wants from an earlier win

   if ns.Save.load() then
      ui:Refresh("all")
      ui:Log("system", L["Welcome back.  Your game goes on where you left it."])
   else
      local class = ui:PickClass(ns.Classes, DefaultClass())
      ns.Create.makePlayer(class)
      ns.Create.newCaveLevel(0)
      ui:Refresh("all")
      Welcome()
      ui:Log("system", L["You set out as %s."], LOCALIZED_CLASS_NAMES_MALE[class.token] or class.token)
      if G.race then ui:Log("system", L["Your %s blood adds to your abilities."], G.race) end
   end

   while true do
      if not G.dropflag then
         ns.Object.lookForObject()  -- see if there is an object here
         if G.dead then break end
      else
         G.dropflag = false  -- don't show what was just dropped
      end
      if not G.hitflag then
         if c[K.HASTEMONST] ~= 0 then Monster.movemonst() end
         Monster.movemonst()
      end
      if G.dead then break end
      if not G.viewflag then
         Display.showcell(G.playerx, G.playery)
      else
         G.viewflag = false
      end
      G.hitflag, G.hit3flag = false, false
      G.nomove = true
      ui:Refresh("all")

      while G.nomove do  -- get commands and make moves
         G.nomove = false
         if Parse() then
            Finish()
            return
         end
         if G.dead then break end
      end

      if G.dead then break end
      Regen.regen()
      if c[K.TIMESTOP] == 0 then
         G.rmst = G.rmst - 1
         if G.rmst <= 0 then
            G.rmst = 120 - G.level * 4
            Monster.spawnRandom()
         end
      end
   end
   Finish()
end
