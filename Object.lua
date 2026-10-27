--[[
**********************************************************************
WoWLarn - Standing on objects (object.c). Only the town so far.
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

-- C: lookforobject(). Everything you can step on does something; the town buildings,
-- stairs and the rest arrive in later milestones.
function Object.lookForObject()
   if G.c[ns.K.TIMESTOP] ~= 0 then return end  -- can't find objects if time is stopped
   local id = G.item[G.playerx][G.playery]
   if id == 0 then return end

   ns.Display.showcell(G.playerx, G.playery)
   ns.ui.repcount = 0
   local name = ns.Tables.objectname[id]
   if name then
      ns.ui:Message(L["There is %s here. (Not implemented yet.)"], name)
   end
end
