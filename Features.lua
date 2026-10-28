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
local rnd, rund, idiv = ns.rnd, ns.rund, ns.idiv

-- The things you find in the dungeon that you can use: altars, thrones, fountains and the
-- brass lamp (C: moreobj.c and the cases of lookforobject()).
local Features = {}
ns.Features = Features

local c = G.c

local function Msg(fmt, ...)
   ns.ui:Message(fmt, ...)
end

-- C: forget(). Destroys the object at the player's location.
local function Forget()
   G.item[G.playerx][G.playery] = 0
   G.know[G.playerx][G.playery] = 0
end

local function CreateMonster(id)
   ns.Monster.createMonster(id)
end

-- C: ohear(). The altar gives a +3 protection.
local function Hear()
   Msg(L["You have been heard!"])
   if c[K.ALTPRO] == 0 then c[K.MOREDEFENSES] = c[K.MOREDEFENSES] + 5 end
   c[K.ALTPRO] = c[K.ALTPRO] + 800  -- protection field
   ns.ui:Refresh("stats")
end

-- C: oaltar().
function Features.altar()
   local ui = ns.ui
   local Player = ns.Player
   while true do
      local choice = ui:Choose(L["Do you (p) pray, (d) desecrate, or (i) ignore it?"], "pd")
      if choice == "p" then
         -- (the C will not let Esc out of this question; here it goes back to the first one)
         local how = ui:Choose(L["Do you (m) give money or (j) just pray?"], "mj")
         if how == "j" then
            local p = rund(100)
            if p < 12 then
               CreateMonster(ns.Monster.makeMonst(G.level + 2))
            elseif p < 17 then
               Player.enchantWeapon(K.ENCH_ALTAR)
            elseif p < 22 then
               Player.enchantArmor(K.ENCH_ALTAR)
            elseif p < 27 then
               Hear()
            else
               Msg(L["Nothing happens."])
            end
            return
         elseif how == "m" then
            local gold = ui:GetNumber(L["How much do you donate?"], c[K.GOLD])
            if gold >= 0 then
               if c[K.GOLD] < gold then
                  Msg(L["You don't have that much!"])
                  ui:Nap(1001)
               elseif gold < idiv(c[K.GOLD], 10) and rnd(60) < 30 and not G.wizard then
                  Msg(L["Cheapskate! The Gods are insulted by such a tiny offering!"])
                  Forget()
                  CreateMonster(K.DEMONPRINCE)
                  c[K.AGGRAVATE] = c[K.AGGRAVATE] + 1500
                  return
               else
                  c[K.GOLD] = c[K.GOLD] - gold
                  if gold < idiv(c[K.GOLD] + gold, 10) or (gold < rnd(50) and not G.wizard) then
                     CreateMonster(ns.Monster.makeMonst(G.level + 2))
                     c[K.AGGRAVATE] = c[K.AGGRAVATE] + 500
                     ui:Refresh("stats")
                     return
                  end
                  local p = rund(16)
                  if p < 4 then
                     Msg(L["Thank you."])
                  elseif p < 6 then
                     Player.enchantArmor(K.ENCH_ALTAR)
                     Player.enchantArmor(K.ENCH_ALTAR)
                  elseif p < 8 then
                     Player.enchantWeapon(K.ENCH_ALTAR)
                     Player.enchantWeapon(K.ENCH_ALTAR)
                  else
                     Hear()
                  end
                  ui:Refresh("stats")
                  return
               end
            end
         end
      elseif choice == "d" then
         if rnd(100) < 60 then
            CreateMonster(ns.Monster.makeMonst(G.level + 3) + 8)
            c[K.AGGRAVATE] = c[K.AGGRAVATE] + 2500
         elseif rnd(100) < 5 then
            Player.raiseLevel()
         elseif rnd(101) < 30 then
            Msg(L["The altar crumbles into a pile of dust before your eyes."])
            Forget()  -- remember to destroy the altar
         else
            Msg(L["Nothing happens."])
         end
         return
      else  -- ignore
         if rnd(100) < 30 then
            CreateMonster(ns.Monster.makeMonst(G.level + 2))
            c[K.AGGRAVATE] = c[K.AGGRAVATE] + rnd(450)
         else
            Msg(L["Nothing happens."])
         end
         return
      end
   end
end

local function Teleported()
   Msg(L["Zaaaappp!  You've been teleported!"])
   ns.ui:Nap(3000)
   ns.Magic.teleport(0)
end

-- C: othrone(). arg is 1 for a throne whose gnome king has been found.
function Features.throne(arg)
   local x, y = G.playerx, G.playery
   local choice = ns.ui:Choose(L["Do you (p) pry off jewels, (s) sit down, or (i) ignore it?"], "ps")
   if choice == "p" then
      local k = rnd(101)
      if k < 25 then
         local i = 0
         while i < rnd(4) do  -- the C re-rolls the limit on every pass
            ns.Item.createGem()  -- gems pop off the throne
            i = i + 1
         end
         G.item[x][y], G.know[x][y] = K.ODEADTHRONE, 0
      elseif k < 40 and arg == 0 then
         CreateMonster(K.GNOMEKING)
         G.item[x][y], G.know[x][y] = K.OTHRONE2, 0
      else
         Msg(L["Nothing happens."])
      end
   elseif choice == "s" then
      local k = rnd(101)
      if k < 30 and arg == 0 then
         CreateMonster(K.GNOMEKING)
         G.item[x][y], G.know[x][y] = K.OTHRONE2, 0
      elseif k < 35 then
         Teleported()
      else
         Msg(L["Nothing happens."])
      end
   end
end

-- C: odeadthrone().
function Features.deadThrone()
   local choice = ns.ui:Choose(L["Do you (s) sit down, or (i) ignore it?"], "s")
   if choice == "s" then
      local k = rnd(101)
      if k < 5 then
         ns.Player.raiseLevel()
      elseif k < 25 then
         Teleported()
      else
         Msg(L["Nothing happens."])
      end
   end
end

-- C: fch(). Raises or lowers an attribute by one.
local function ChangeAttribute(how, index, name)
   if how < 0 then
      if c[index] > 3 then
         Msg(L["%s went down by one!"], name)
         c[index] = c[index] - 1
      else
         Msg(L["%s remained unchanged!"], name)
      end
   else
      Msg(L["%s went up by one!"], name)
      c[index] = c[index] + 1
   end
   ns.ui:Refresh("stats")
end

-- C: fntchange(). Raises (how > 0) or lowers (how < 0) something of the character.
local ATTRIBUTE = {
   { K.STRENGTH, L["Your strength"] }, { K.INTELLIGENCE, L["Your intelligence"] },
   { K.WISDOM, L["Your wisdom"] }, { K.CONSTITUTION, L["Your constitution"] },
   { K.DEXTERITY, L["Your dexterity"] }, { K.CHARISMA, L["Your charm"] },
}

local function FountainChange(how)
   local Player = ns.Player
   local roll = rnd(9)
   if roll <= 6 then
      ChangeAttribute(how, ATTRIBUTE[roll][1], ATTRIBUTE[roll][2])
   elseif roll == 7 then
      local j = rnd(G.level + 1)
      if how < 0 then
         Msg(j == 1 and L["You lose %d hit point!"] or L["You lose %d hit points!"], j)
         Player.loseMaxHP(j)
      else
         Msg(j == 1 and L["You gain %d hit point!"] or L["You gain %d hit points!"], j)
         Player.raiseMaxHP(j)
      end
   elseif roll == 8 then
      local j = rnd(G.level + 1)
      if how > 0 then
         Msg(L["You just gained %d mana!"], j)
         Player.raiseMaxSpells(j)
      else
         Msg(L["You just lost %d mana!"], j)
         Player.loseMaxSpells(j)
      end
   else
      local j = 5 * rnd((G.level + 1) * (G.level + 1))
      if how < 0 then
         Msg(j == 1 and L["You just lost %d experience point!"] or L["You just lost %d experience points!"], j)
         Player.loseExperience(j)
      else
         Msg(j == 1 and L["You just gained %d experience point!"] or L["You just gained %d experience points!"], j)
         Player.raiseExperience(j)
      end
   end
   ns.ui:Refresh("stats")
end

-- C: ofountain().
function Features.fountain()
   local ui = ns.ui
   local choice = ui:Choose(L["Do you (d) drink, (w) wash yourself, or (i) ignore it?"], "dw")
   if choice == "d" then
      if rnd(1501) < 4 then
         Msg(L["OH MY GOD!! You have caught the *dreadful sleep*!"])
         ui:Nap(3000)
         ns.Player.died(280)
         return
      end
      local x = rnd(100)
      if x == 1 then
         ns.Player.raiseLevel()
      elseif x < 11 then
         x = rnd(G.level * 4 + 2)
         Msg(x == 1 and L["Bleah! The water tasted like stale gatorade!  You lose %d hit point!"]
            or L["Bleah! The water tasted like stale gatorade!  You lose %d hit points!"], x)
         G.lastnum = 273
         ns.Player.losehp(x)
         if G.dead then return end
      elseif x < 14 then
         c[K.HALFDAM] = c[K.HALFDAM] + 200 + rnd(200)
         Msg(L["The water makes you vomit."])
      elseif x < 17 then
         ns.Magic.quaffPotion(K.PGIANTSTR)
      elseif x < 45 then
         Msg(L["Nothing seems to have happened."])
      elseif rnd(3) ~= 2 then
         FountainChange(1)  -- change the character upward
      else
         FountainChange(-1)  -- change the character downward
      end
      if rnd(12) < 3 then
         Msg(L["The fountains bubbling slowly quietens."])
         -- dead fountain
         G.item[G.playerx][G.playery], G.know[G.playerx][G.playery] = K.ODEADFOUNTAIN, 0
      end
   elseif choice == "w" then
      if rnd(100) < 11 then
         local x = rnd(G.level * 4 + 2)
         Msg(x == 1 and L["The water burns like acid!  You lose %d hit point!"]
            or L["The water burns like acid!  You lose %d hit points!"], x)
         G.lastnum = 273
         ns.Player.losehp(x)
      elseif rnd(100) < 29 then
         Msg(L["You are now clean."])
      elseif rnd(100) < 31 then
         Msg(L["This water needs soap -- the dirt didn't come off."])
      elseif rnd(100) < 34 then
         CreateMonster(K.WATERLORD)
      else
         Msg(L["Nothing seems to have happened."])
      end
   end
end

-- C: the OBRASSLAMP case of lookforobject(). A genie may grant a spell.
function Features.lamp()
   local ui = ns.ui
   Msg(L["You find a brass lamp."])
   local choice = ui:Choose(L["Do you want to (r) rub it, (t) take it, or (i) ignore it?"], "rt")
   if choice == "r" then
      local roll = rnd(100)
      if roll > 90 then
         Msg(L["The magic genie was very upset at being disturbed!"])
         G.lastnum = 286
         ns.Player.losehp(idiv(c[K.HP], 2) + 1)
         if G.dead then return end
      -- higher level, better chance of spell
      elseif rnd(100) + idiv(c[K.LEVEL], 2) > 80 then
         Msg(L["A magic genie appears!"])
         local code = ui:PickSpell(L["What spell would you like?"], true)
         if not code then
            Msg(L["aborted."])
            return
         end
         local T = ns.Tables
         for i = 1, K.SPNUM do
            if T.spelcode[i] == code then
               G.spelknow[i] = 1
               Msg(L["Spell \"%s\":  %s"], T.spelcode[i], T.spelname[i])
               Msg("%s", T.speldescript[i])
               Msg(L["The genie prefers not to be disturbed again."])
               Forget()
               ui:Refresh("stats")
               return
            end
         end
         Msg(L["The genie has never heard of such a spell!"])
         Msg(L["The genie prefers not to be disturbed again."])
         Forget()
         ui:Refresh("stats")
         return
      else
         Msg(L["Nothing happened."])
      end
      if rnd(100) < 15 then
         Msg(L["The genie prefers not to be disturbed again!"])
         Forget()
         c[K.LAMP] = 0  -- chance of finding the lamp again
      end
      ui:Refresh("stats")
   elseif choice == "t" then
      if ns.Player.take(K.OBRASSLAMP, 0) then Forget() end
   end
end
