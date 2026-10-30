--[[
**********************************************************************
WoWLarn - Per-turn regeneration and effect timers (regen.c).
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

local Regen = {}
ns.Regen = Regen

local c, iven = G.c, G.iven

-- C: regen(). Called once after each player action.
function Regen.regen()
   local ui = ns.ui
   local flag = false

   if c[K.TIMESTOP] ~= 0 then  -- for the stop time spell
      c[K.TIMESTOP] = c[K.TIMESTOP] - 1
      if c[K.TIMESTOP] <= 0 then ui:Refresh("stats") end
      return
   end

   if c[K.STRENGTH] < 3 then
      c[K.STRENGTH] = 3
      flag = true
   end
   if c[K.HASTESELF] == 0 then
      G.gtime = G.gtime + 1
   end

   if c[K.HP] ~= c[K.HPMAX] then  -- regenerate hit points
      local counter = c[K.REGENCOUNTER]
      c[K.REGENCOUNTER] = counter - 1
      if counter <= 0 then
         c[K.REGENCOUNTER] = 22 + c[K.HARDGAME] * 2 - c[K.LEVEL]
         c[K.HP] = math.min(c[K.HP] + c[K.REGEN], c[K.HPMAX])
         ui:Refresh("stats")
      end
   end

   if c[K.SPELLS] < c[K.SPELLMAX] then  -- regenerate spells
      local counter = c[K.ECOUNTER]
      c[K.ECOUNTER] = counter - 1
      if counter <= 0 then
         c[K.ECOUNTER] = 100 + 4 * (c[K.HARDGAME] - c[K.LEVEL] - c[K.ENERGY])
         c[K.SPELLS] = c[K.SPELLS] + 1
         ui:Refresh("stats")
      end
   end

   -- Timers that only matter while running down. count(index) decrements and
   -- returns true when it just expired.
   local function expired(index)
      if c[index] == 0 then return false end
      c[index] = c[index] - 1
      return c[index] <= 0
   end

   if expired(K.HERO) then
      for i = 1, 6 do c[i] = c[i] - 10 end
      flag = true
   end
   if expired(K.COKED) then
      ns.ItemInfo.discoverAfter(K.OCOKE, L["The fel tonic wears off, and you crash hard!"])
      for i = 1, 6 do c[i] = c[i] - 34 end
      flag = true
   end
   if expired(K.ALTPRO) then
      c[K.MOREDEFENSES] = c[K.MOREDEFENSES] - 3
      flag = true
   end
   if expired(K.PROTECTIONTIME) then
      c[K.MOREDEFENSES] = c[K.MOREDEFENSES] - 2
      flag = true
   end
   if expired(K.DEXCOUNT) then
      c[K.DEXTERITY] = math.max(c[K.DEXTERITY] - 3, 3)
      flag = true
   end
   if expired(K.STRCOUNT) then
      c[K.STREXTRA] = c[K.STREXTRA] - 3
      flag = true
   end
   if expired(K.DRAINSTRENGTH) then
      c[K.STREXTRA] = c[K.STREXTRA] + ns.Monster.CURSE_STRENGTH
      ui:Message(L["The curse on your strength lifts."])
      flag = true
   end
   if expired(K.BLINDCOUNT) then
      ui:Message(L["The blindness lifts."])
   end
   if expired(K.CONFUSE) then
      ui:Message(L["You regain your senses."])
   end
   if expired(K.GIANTSTR) then
      c[K.STREXTRA] = c[K.STREXTRA] - 20
      flag = true
   end
   if expired(K.CHARMCOUNT) then flag = true end
   if expired(K.INVISIBILITY) then flag = true end
   if expired(K.CANCELLATION) then flag = true end
   if expired(K.WTW) then flag = true end
   if expired(K.HASTESELF) then flag = true end
   if c[K.AGGRAVATE] ~= 0 then c[K.AGGRAVATE] = c[K.AGGRAVATE] - 1 end
   if expired(K.SCAREMONST) then flag = true end
   if expired(K.STEALTH) then flag = true end
   if c[K.AWARENESS] ~= 0 and c[K.ORB] ~= 2 then
      c[K.AWARENESS] = c[K.AWARENESS] - 1
   end
   if expired(K.HOLDMONST) then flag = true end
   if c[K.HASTEMONST] ~= 0 then c[K.HASTEMONST] = c[K.HASTEMONST] - 1 end
   if expired(K.FIRERESISTANCE) then flag = true end
   if expired(K.GLOBE) then
      c[K.MOREDEFENSES] = c[K.MOREDEFENSES] - 10
      flag = true
   end
   if expired(K.SPIRITPRO) then flag = true end
   if expired(K.UNDEADPRO) then flag = true end
   if expired(K.HALFDAM) then
      ui:Message(L["You now feel better."])
   end

   if c[K.SEEINVISIBLE] ~= 0 then
      local amulet = false
      for i = 1, K.IVENSIZE do
         if iven[i] == K.OAMULET then
            amulet = true
            break
         end
      end
      -- (The C also changes the invisible stalker's glyph back; drawing handles that here.)
      if not amulet and expired(K.SEEINVISIBLE) then
         ui:Message(L["Your vision returns to normal."])
      end
   end

   if c[K.ITCHING] ~= 0 then
      if c[K.ITCHING] > 1 and (c[K.WEAR] ~= 0 or c[K.SHIELD] ~= 0) and rnd(100) < 50 then
         c[K.WEAR], c[K.SHIELD] = 0, 0
         ui:Message(L["The hysteria of itching forces you to remove your armor!"])
         ns.Player.recalc()
         flag = true
      end
      if expired(K.ITCHING) then
         ui:Message(L["The irritation subsides."])
      end
   end

   if c[K.CLUMSINESS] ~= 0 then
      if c[K.WIELD] ~= 0 and c[K.CLUMSINESS] > 1 and G.item[G.playerx][G.playery] == 0 and rnd(100) < 33 then
         ns.Player.dropObject(c[K.WIELD])  -- drop your weapon
         if G.drugClumsy then ns.ItemInfo.discoverAfter(K.OHASH, L["Your hands are so clumsy from the brew that the weapon slips away!"]) end
      end
      if expired(K.CLUMSINESS) then
         ui:Message(L["You now feel less awkward."])
         G.drugClumsy = nil
      end
   end

   if flag then
      ns.Player.recalc()
      ui:Refresh("stats")
   end
end
