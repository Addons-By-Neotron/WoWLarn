--[[
**********************************************************************
WoWLarn - Game loop (milestone 1 stand-in).
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

local Game = {}
ns.Game = Game

local ui = ns.ui

-- Placeholder game: exercises every input request. Replaced by the ported
-- main.c loop in milestone 2.
function Game.Run()
   ui:Log("system", L["Welcome to WoWLarn."])
   ui:Log("system", L["Milestone 1: keys are echoed. Q quit, N number, M more, P pause, D direction, S save and close."])
   while true do
      local command = ui:GetCommand()
      ns.map:SetDebugText(format(L["Last key: %s"], command))
      if command == "Q" then
         if ui:YesNo(L["Really quit?"]) == "y" then
            ui:Log("system", L["Game over. Press any key to start again."])
            return
         end
      elseif command == "N" then
         local amount = ui:GetNumber(L["How many?"], 1000)
         ui:Message(L["Number: %d"], amount)
      elseif command == "M" then
         ui:Message(L["Some text first."])
         ui:More()
         ui:Message(L["And then some more."])
      elseif command == "P" then
         ui:Message(L["Pausing for two seconds..."])
         ui:Nap(2000)
         ui:Message(L["Done."])
      elseif command == "D" then
         local direction = ui:PickDirection(L["Which way?"])
         ui:Message(L["Direction: %s"], tostring(direction))
      elseif command == "S" then
         ns.main:Hide()
      else
         ui:Message(L["Key: %s"], command)
      end
   end
end
