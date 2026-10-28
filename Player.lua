--[[
**********************************************************************
WoWLarn - Player attributes and inventory helpers (player.c).
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

local Player = {}
ns.Player = Player

local c, iven, ivenarg = G.c, G.iven, G.ivenarg
local item, mon = G.item, G.mon

local MAXX, MAXY, IVENSIZE = K.MAXX, K.MAXY, K.IVENSIZE
local AC, WCLASS, MOREDEFENSES, MOREDAM = K.AC, K.WCLASS, K.MOREDEFENSES, K.MOREDAM
local WEAR, SHIELD, WIELD = K.WEAR, K.SHIELD, K.WIELD
local REGEN, ENERGY = K.REGEN, K.ENERGY

-- Armor class bonus before the enchantment (C: the switch in recalc).
local ARMOR_AC = {
   [K.OSHIELD] = 2, [K.OLEATHER] = 2, [K.OSTUDLEATHER] = 3, [K.ORING] = 5, [K.OCHAIN] = 6,
   [K.OSPLINT] = 7, [K.OPLATE] = 9, [K.OPLATEARMOR] = 10, [K.OSSPLATE] = 12, [K.OELVENCHAIN] = 15,
}
Player.ARMOR_AC = ARMOR_AC  -- (Equipment.lua explains the totals)

-- Weapon class before the enchantment. Anything not listed has weapon class 0.
local WEAPON_WC = {
   [K.ODAGGER] = 3, [K.OBELT] = 7, [K.OSHIELD] = 8, [K.OPSTAFF] = 10, [K.OSPEAR] = 10,
   [K.OFLAIL] = 14, [K.OBATTLEAXE] = 17, [K.OLANCE] = 20, [K.OLONGSWORD] = 22, [K.OVORPAL] = 22,
   [K.O2SWORD] = 26, [K.OSWORDofSLASHING] = 30, [K.OSLAYER] = 30, [K.OSWORD] = 32, [K.OHAMMER] = 35,
}
Player.WEAPON_WC = WEAPON_WC

-- C: recalc(). Armor class, weapon class and the ring-based regeneration values.
function Player.recalc()
   c[AC] = c[MOREDEFENSES]
   if c[WEAR] > 0 then
      local bonus = ARMOR_AC[iven[c[WEAR]]]
      if bonus then c[AC] = c[AC] + bonus + ivenarg[c[WEAR]] end
   end
   if c[SHIELD] > 0 and iven[c[SHIELD]] == K.OSHIELD then
      c[AC] = c[AC] + 2 + ivenarg[c[SHIELD]]
   end

   if c[WIELD] <= 0 then
      c[WCLASS] = 0
   else
      local base = WEAPON_WC[iven[c[WIELD]]]
      c[WCLASS] = base and (base + ivenarg[c[WIELD]]) or 0
   end
   c[WCLASS] = c[WCLASS] + c[MOREDAM]

   c[REGEN] = 1
   c[ENERGY] = 0
   for i = 1, IVENSIZE do
      local kind, arg = iven[i], ivenarg[i]
      if kind == K.OPROTRING then
         c[AC] = c[AC] + arg + 1
      elseif kind == K.ODAMRING then
         c[WCLASS] = c[WCLASS] + arg + 1
      elseif kind == K.OBELT then
         c[WCLASS] = c[WCLASS] + arg * 2 + 2
      elseif kind == K.OREGENRING then
         c[REGEN] = c[REGEN] + arg + 1
      elseif kind == K.ORINGOFEXTRA then
         c[REGEN] = c[REGEN] + 5 * (arg + 1)
      elseif kind == K.OENERGYRING then
         c[ENERGY] = c[ENERGY] + arg + 1
      end
   end
end

-- C: positionplayer(). Moves the player to the next free tile.
function Player.positionPlayer()
   local try = 2
   while (item[G.playerx][G.playery] ~= 0 or mon[G.playerx][G.playery] ~= 0) and try > 0 do
      G.playerx = G.playerx + 1
      if G.playerx >= MAXX then
         G.playerx = 2
         G.playery = G.playery + 1
         if G.playery >= MAXY then
            G.playery = 2
            try = try - 1
         end
      end
   end
   if try == 0 then
      ns.ui:Message("Failure in positionplayer")
   end
end

-- C: packweight(). The number of pounds the player is carrying.
local WEIGHT = {
   [K.OSSPLATE] = 40, [K.OPLATEARMOR] = 40, [K.OPLATE] = 35, [K.OHAMMER] = 30, [K.OSPLINT] = 26,
   [K.OCHAIN] = 23, [K.OBATTLEAXE] = 23, [K.O2SWORD] = 23,
   [K.OLONGSWORD] = 20, [K.OPSTAFF] = 20, [K.OSWORD] = 20, [K.ORING] = 20, [K.OFLAIL] = 20,
   [K.OELVENCHAIN] = 15, [K.OSWORDofSLASHING] = 15, [K.OLANCE] = 15, [K.OSLAYER] = 15,
   [K.OSTUDLEATHER] = 15, [K.OLEATHER] = 8, [K.OSPEAR] = 8,
   [K.OORBOFDRAGON] = 4, [K.OORB] = 4, [K.OBELT] = 4, [K.OSHIELD] = 7,
}

function Player.packWeight()
   local k = ns.idiv(c[K.GOLD], 1000)
   local last = IVENSIZE
   while last > 0 and iven[last] == 0 do
      last = last - 1
   end
   for i = 1, last do
      local id = iven[i]
      if id == K.OCHEST then
         k = k + 30 + ivenarg[i]
      elseif id ~= 0 then
         k = k + (WEIGHT[id] or 1)
      end
   end
   return k
end

-- C: losehp(). Removes hit points; kills the player at zero. Callers must check G.dead
-- afterwards, since nothing stops the game code the way the C exit() in died() does.
function Player.losehp(x, quiet)
   if G.dead then return end
   if not quiet and x > 0 then ns.ui:Message(L["You lose %d hit points."], x) end
   c[K.HP] = c[K.HP] - x
   if x > 0 then ns.ui:Animate("hurt") end
   if c[K.HP] <= 0 then
      ns.ui:Message(L["Alas, you have died."])
      ns.ui:Nap(3000)
      Player.died(G.lastnum)
   end
   ns.ui:Refresh("stats")
end

-- C: raisehp(), raisemhp(), losemhp(), raisespells(), raisemspells(), losemspells().
function Player.raiseHP(x)
   c[K.HP] = math.min(c[K.HP] + x, c[K.HPMAX])
end

function Player.raiseMaxHP(x)
   c[K.HPMAX] = c[K.HPMAX] + x
   c[K.HP] = c[K.HP] + x
end

function Player.loseMaxHP(x)
   c[K.HP] = math.max(c[K.HP] - x, 1)
   c[K.HPMAX] = math.max(c[K.HPMAX] - x, 1)
end

function Player.raiseSpells(x)
   c[K.SPELLS] = math.min(c[K.SPELLS] + x, c[K.SPELLMAX])
end

function Player.raiseMaxSpells(x)
   c[K.SPELLMAX] = c[K.SPELLMAX] + x
   c[K.SPELLS] = c[K.SPELLS] + x
end

function Player.loseMaxSpells(x)
   c[K.SPELLMAX] = math.max(c[K.SPELLMAX] - x, 0)
   c[K.SPELLS] = math.max(c[K.SPELLS] - x, 0)
end

-- C: raiseexperience(). skill[c[LEVEL]] in C is T.skill[level + 1] here.
function Player.raiseExperience(x)
   local ui, skill = ns.ui, ns.Tables.skill
   local old, oldHP, oldSpells, oldPack = c[K.LEVEL], c[K.HPMAX], c[K.SPELLMAX], Player.pocketLimit()
   c[K.EXPERIENCE] = c[K.EXPERIENCE] + x
   while c[K.EXPERIENCE] >= skill[c[K.LEVEL] + 1] and c[K.LEVEL] < K.MAXPLEVEL do
      local tmp = ns.idiv(c[K.CONSTITUTION] - c[K.HARDGAME], 2)
      c[K.LEVEL] = c[K.LEVEL] + 1
      Player.raiseMaxHP(ns.rnd(3) + ns.rnd(tmp > 0 and tmp or 1))
      Player.raiseMaxSpells(ns.rund(3))
      if c[K.LEVEL] < 7 - c[K.HARDGAME] then
         Player.raiseMaxHP(ns.idiv(c[K.CONSTITUTION], 4))
      end
   end
   if c[K.LEVEL] ~= old then
      ui:Message(L["Welcome to level %d!"], c[K.LEVEL])
      local gains = { format(L["%d hit points"], c[K.HPMAX] - oldHP) }
      if c[K.SPELLMAX] > oldSpells then gains[#gains + 1] = format(L["%d mana"], c[K.SPELLMAX] - oldSpells) end
      if Player.pocketLimit() > oldPack then gains[#gains + 1] = L["a new pack slot"] end
      ui:Message(L["You gain %s."], table.concat(gains, ", "))
      ui:Sound("levelup")
      local level = c[K.LEVEL]
      if level == 94 then  -- earth guardian
         c[K.WTW] = 99999
      elseif level == 95 then  -- air guardian
         c[K.INVISIBILITY] = 99999
      elseif level == 96 then  -- fire guardian
         c[K.FIRERESISTANCE] = 99999
      elseif level == 97 then  -- water guardian
         c[K.CANCELLATION] = 99999
      elseif level == 98 then  -- time guardian
         c[K.HASTESELF] = 99999
      elseif level == 99 then  -- ethereal guardian
         c[K.STEALTH] = 99999
         c[K.SPIRITPRO] = 99999
      elseif level == 100 then
         ui:Message(L["You are now The Creator!"])
         G.FillKnow(1)
         for i = 1, K.SPNUM do G.spelknow[i] = 1 end
         for i = 1, K.MAXSCROLL do G.scrollknown[i] = 1 end
         for i = 1, K.MAXPOTION do G.potionknown[i] = 1 end
      end
   end
   ui:Refresh("stats")
end

-- C: loseexperience() and loselevel().
function Player.loseExperience(x)
   local ui, skill = ns.ui, ns.Tables.skill
   local old = c[K.LEVEL]
   c[K.EXPERIENCE] = math.max(c[K.EXPERIENCE] - x, 0)
   while c[K.EXPERIENCE] < skill[c[K.LEVEL]] do
      c[K.LEVEL] = c[K.LEVEL] - 1
      if c[K.LEVEL] <= 1 then c[K.LEVEL] = 1 end
      local tmp = ns.idiv(c[K.CONSTITUTION] - c[K.HARDGAME], 2)
      Player.loseMaxHP(ns.rnd(tmp > 0 and tmp or 1))
      if c[K.LEVEL] < 7 - c[K.HARDGAME] then
         Player.loseMaxHP(ns.idiv(c[K.CONSTITUTION], 4))
      end
      Player.loseMaxSpells(ns.rund(3))
   end
   if old ~= c[K.LEVEL] then
      ui:Message(L["You went down to level %d!"], c[K.LEVEL])
   end
   ui:Refresh("stats")
end

function Player.loseLevel()
   if c[K.LEVEL] > 1 then
      Player.loseExperience(c[K.EXPERIENCE] - ns.Tables.skill[c[K.LEVEL]] + 1)
   end
end

-- C: emptyhanded(). True if the player carries nothing but what is worn or wielded.
function Player.emptyHanded()
   for i = 1, IVENSIZE do
      if iven[i] ~= 0 and i ~= c[K.WIELD] and i ~= c[K.WEAR] and i ~= c[K.SHIELD] then
         return false
      end
   end
   return true
end

-- C: adjustcvalues(). Takes back what an object gave while it was carried.
function Player.adjustCValues(id, arg)
   local flag = false
   if id == K.ODEXRING then
      c[K.DEXTERITY] = c[K.DEXTERITY] - (arg + 1)
      flag = true
   elseif id == K.OSTRRING then
      c[K.STREXTRA] = c[K.STREXTRA] - (arg + 1)
      flag = true
   elseif id == K.OCLEVERRING then
      c[K.INTELLIGENCE] = c[K.INTELLIGENCE] - (arg + 1)
      flag = true
   elseif id == K.OHAMMER then
      c[K.DEXTERITY] = c[K.DEXTERITY] - 10
      c[K.STREXTRA] = c[K.STREXTRA] - 10
      c[K.INTELLIGENCE] = c[K.TMP2]
      flag = true
   elseif id == K.OORB then
      c[K.ORB] = c[K.ORB] - 1
      c[K.AWARENESS] = c[K.AWARENESS] - 1
   elseif id == K.OSWORDofSLASHING then
      c[K.DEXTERITY] = c[K.DEXTERITY] - 5
      flag = true
   elseif id == K.OSLAYER then
      c[K.INTELLIGENCE] = c[K.INTELLIGENCE] - 10
      flag = true
   elseif id == K.OPSTAFF then
      c[K.WISDOM] = c[K.WISDOM] - 10
      flag = true
   elseif id == K.OORBOFDRAGON then
      c[K.SLAYING] = c[K.SLAYING] - 1
      return
   elseif id == K.OSPIRITSCARAB then
      c[K.NEGATESPIRIT] = c[K.NEGATESPIRIT] - 1
      return
   elseif id == K.OCUBEofUNDEAD then
      c[K.CUBEofUNDEAD] = c[K.CUBEofUNDEAD] - 1
      return
   elseif id == K.ONOTHEFT then
      c[K.NOTHEFT] = c[K.NOTHEFT] - 1
      return
   elseif id == K.OLANCE then
      c[K.LANCEDEATH] = 0
      return
   elseif id == K.OLARNEYE then
      c[K.EYEOFLARN] = 0
      if c[K.BLINDCOUNT] == 0 then
         ns.ui:Message(L["Your sight fades for a moment..."])
         ns.ui:Nap(2000)
         ns.ui:Message(L["Your sight returns but everything looks dull and faded."])
      end
      return
   elseif id == K.OPOTION or id == K.OSCROLL then
      return
   else
      flag = true
   end
   if flag then ns.ui:Refresh("stats") end

   for i = K.STRENGTH, K.STRENGTH + 5 do
      if c[i] < 3 then c[i] = 3 end
   end
end

-- C: stealsomething(). A monster takes an item from the player's pockets; it is kept in
-- the monster's loot. Returns true if something was stolen.
function Player.stealSomething(x, y)
   local key = x * 100 + y
   local loot = G.loot[key]
   if loot and #loot >= 6 then return false end  -- max of 6 stolen items per monster
   for _ = 1, 100 do
      local i = ns.rund(IVENSIZE) + 1
      if iven[i] ~= 0 and c[K.WEAR] ~= i and c[K.WIELD] ~= i and c[K.SHIELD] ~= i then
         ns.ui:Message("  %s", ns.Tables.objectname[iven[i]] or "?")
         Player.adjustCValues(iven[i], ivenarg[i])
         if not loot then
            loot = {}
            G.loot[key] = loot
         end
         loot[#loot + 1] = { iven[i], ivenarg[i] }
         iven[i], ivenarg[i] = 0, 0
         ns.ui:Refresh("stats")
         return true
      end
   end
   return false
end

-- C: died(). The full scoreboard and tombstone arrive in milestone 9.
-- C: died(). Ends the game, unless life protection saves the player (the only case where it
-- returns normally). Callers must check G.dead afterwards.
function Player.died(cause)
   if c[K.LIFEPROT] > 0 and ns.Scores.canBeSaved(cause) then
      c[K.LIFEPROT] = c[K.LIFEPROT] - 1
      c[K.HP] = 1
      c[K.CONSTITUTION] = c[K.CONSTITUTION] - 1
      ns.ui:Message(L["You feel wiiieeeeerrrrrd all over!"])
      ns.ui:Nap(4000)
      ns.ui:Refresh("stats")
      return
   end
   G.dead = cause or true
end

-- Objects whose argument is not shown in their name (C: show3).
local PLAIN = {
   [K.OLARNEYE] = true, [K.OBOOK] = true, [K.OSPIRITSCARAB] = true, [K.ODIAMOND] = true, [K.ORUBY] = true,
   [K.OCUBEofUNDEAD] = true, [K.OEMERALD] = true, [K.OCHEST] = true, [K.OCOOKIE] = true,
   [K.OSAPPHIRE] = true, [K.OORB] = true, [K.OHANDofFEAR] = true, [K.OBRASSLAMP] = true,
   [K.OURN] = true, [K.OWWAND] = true, [K.OSPHTALISMAN] = true, [K.ONOTHEFT] = true,
}

-- The name of an inventory slot as shown in the inventory (C: show3 without the letter).
-- Potions and scrolls only show what they are once the player has found out.
function Player.objectName(id, arg)
   local T = ns.Tables
   local name = T.objectname[id] or "?"
   if id == K.OPOTION then
      local kind = T.potionname[arg]
      if kind and kind ~= "" and G.potionknown[arg] ~= 0 then name = name .. " of " .. kind end
   elseif id == K.OSCROLL then
      local kind = T.scrollname[arg]
      if kind and kind ~= "" and G.scrollknown[arg] ~= 0 then name = name .. " of " .. kind end
   elseif not PLAIN[id] then
      if arg > 0 or G.wizard then
         name = name .. " +" .. arg
      elseif arg < 0 then
         name = name .. " " .. arg
      end
   end
   return name
end

function Player.itemName(slot)
   local name = Player.objectName(iven[slot], ivenarg[slot])
   if c[K.WIELD] == slot then name = name .. L[" (weapon in hand)"] end
   if c[K.WEAR] == slot or c[K.SHIELD] == slot then name = name .. L[" (being worn)"] end
   return name
end

-- C: pocketfull(). True if the player can't carry one more thing.
-- How many inventory slots can be used at this level (the C: 15 + level / 2, at most 26).
function Player.pocketLimit()
   return math.min(15 + ns.idiv(c[K.LEVEL], 2), IVENSIZE)
end

function Player.pocketFull()
   local limit = Player.pocketLimit()
   for i = 1, limit do
      if iven[i] == 0 then return false end
   end
   return true
end

-- C: take(). Puts something in the inventory; returns true on success (C: 0).
function Player.take(itm, arg)
   local ui = ns.ui
   local limit = math.min(15 + ns.idiv(c[K.LEVEL], 2), IVENSIZE)
   for i = 1, limit do
      if iven[i] == 0 then
         iven[i], ivenarg[i] = itm, arg
         ui:Sound("pickup")
         local stats, eyeflag = false, false
         if itm == K.OPROTRING or itm == K.ODAMRING or itm == K.OBELT then
            stats = true
         elseif itm == K.ODEXRING then
            c[K.DEXTERITY] = c[K.DEXTERITY] + arg + 1
            stats = true
         elseif itm == K.OSTRRING then
            c[K.STREXTRA] = c[K.STREXTRA] + arg + 1
            stats = true
         elseif itm == K.OCLEVERRING then
            c[K.INTELLIGENCE] = c[K.INTELLIGENCE] + arg + 1
            stats = true
         elseif itm == K.OHAMMER then
            c[K.DEXTERITY] = c[K.DEXTERITY] + 10
            c[K.STREXTRA] = c[K.STREXTRA] + 10
            c[K.TMP2] = c[K.INTELLIGENCE]
            c[K.INTELLIGENCE] = (c[K.TMP2] - 10 <= 0) and 1 or c[K.TMP2] - 10
            stats = true
         elseif itm == K.OORB then
            c[K.ORB] = c[K.ORB] + 1
            c[K.AWARENESS] = c[K.AWARENESS] + 1
         elseif itm == K.OORBOFDRAGON then
            c[K.SLAYING] = c[K.SLAYING] + 1
         elseif itm == K.OSPIRITSCARAB then
            c[K.NEGATESPIRIT] = c[K.NEGATESPIRIT] + 1
         elseif itm == K.OCUBEofUNDEAD then
            c[K.CUBEofUNDEAD] = c[K.CUBEofUNDEAD] + 1
         elseif itm == K.ONOTHEFT then
            c[K.NOTHEFT] = c[K.NOTHEFT] + 1
         elseif itm == K.OSWORDofSLASHING then
            c[K.DEXTERITY] = c[K.DEXTERITY] + 5
            stats = true
         elseif itm == K.OSLAYER then
            c[K.INTELLIGENCE] = c[K.INTELLIGENCE] + 10
         elseif itm == K.OPSTAFF then
            c[K.WISDOM] = c[K.WISDOM] + 10
         elseif itm == K.OLARNEYE then
            c[K.EYEOFLARN] = 1
            eyeflag = true
         end

         ui:Message(L["You pick up: %s"], ns.ItemInfo.link(itm, arg))
         ui:Refresh("inv")
         if stats then Player.recalc() end
         ui:Refresh("stats")
         if c[K.BLINDCOUNT] == 0 and eyeflag then
            ui:Message(L["Your sight fades for a moment..."])
            ui:Nap(2000)
            ui:Message(L["Your sight returns, and everything looks crystal-clear!"])
            ui:Refresh("all")
         end
         return true
      end
   end
   ui:Message(L["You can't carry anything else."])
   local limit = Player.pocketLimit()
   if limit < IVENSIZE then
      ui:Message(L["Your pack holds %d items at your level (%d at most); more slots open as you level."], limit, IVENSIZE)
   end
   return false
end

-- C: drop_object(). Drops inventory slot k on the player's tile. Returns true if something
-- was in the way (C: 1).
function Player.dropObject(k)
   local ui = ns.ui
   if k < 1 or k > IVENSIZE then return false end
   local itm = iven[k]
   if itm == 0 then
      ui:Message(L["You don't have item %s!"], string.char(96 + k))
      return true
   end
   local pitflag = false
   local here = item[G.playerx][G.playery]
   if here == K.OPIT then
      pitflag = true
   elseif here ~= 0 then
      ui:Message(L["There's something here already."])
      return true
   end
   if G.playery == MAXY and G.playerx == 34 then return true end  -- not in the entrance

   ui:Sound("drop")
   if not pitflag then
      item[G.playerx][G.playery] = itm
      G.iarg[G.playerx][G.playery] = ivenarg[k]
   end
   if c[K.WIELD] == k then c[K.WIELD] = 0 end
   if c[K.WEAR] == k then c[K.WEAR] = 0 end
   if c[K.SHIELD] == k then c[K.SHIELD] = 0 end
   Player.adjustCValues(itm, ivenarg[k])
   ui:Message(L["You drop: %s"], ns.ItemInfo.link(iven[k], ivenarg[k]))
   if pitflag then
      ui:Message(L["It disappears down the pit."])
   end
   G.know[G.playerx][G.playery] = 0
   iven[k] = 0
   G.dropflag = true  -- so we won't be asked to pick it up right away
   Player.recalc()
   ui:Refresh("all")
   return false
end

-- C: raiselevel().
function Player.raiseLevel()
   if c[K.LEVEL] < K.MAXPLEVEL then
      Player.raiseExperience(ns.Tables.skill[c[K.LEVEL] + 1] - c[K.EXPERIENCE])
   end
end

-- C: enchantarmor(). how is K.ENCH_SCROLL or K.ENCH_ALTAR.
function Player.enchantArmor(how)
   local ui = ns.ui
   -- bomb out if we're not wearing anything
   if c[K.WEAR] == 0 and c[K.SHIELD] == 0 then
      ui:Message(L["You feel a sense of loss."])
      return
   end
   -- choose what to enchant
   local which = ns.rund(100) < 50 and K.SHIELD or K.WEAR
   if c[which] == 0 then
      which = which == K.SHIELD and K.WEAR or K.SHIELD
   end
   -- enchant it and check for destruction at +10
   local slot = c[which]
   ivenarg[slot] = ivenarg[slot] + 1
   if ivenarg[slot] >= 10 then
      if how == K.ENCH_ALTAR then
         ivenarg[slot] = ivenarg[slot] - 1
         ui:Message(L["Your %s glows briefly."], ns.Tables.objectname[iven[slot]])
         return
      elseif ns.rnd(10) <= 9 then
         ui:Message(L["Your %s vibrates violently and crumbles into dust!"], ns.Tables.objectname[iven[slot]])
         iven[slot], ivenarg[slot] = 0, 0
         c[which] = 0
         Player.recalc()
         ui:Refresh("all")
         return
      end
   end
   ui:Message(L["Your %s glows for a moment."], ns.Tables.objectname[iven[slot]])
   Player.recalc()
   ui:Refresh("all")
end

-- C: enchweapon().
function Player.enchantWeapon(how)
   local ui = ns.ui
   local slot = c[K.WIELD]
   if slot == 0 then
      ui:Message(L["You feel depressed."])
      return
   end
   local tmp = iven[slot]
   if tmp ~= K.OSCROLL and tmp ~= K.OPOTION then
      ivenarg[slot] = ivenarg[slot] + 1
      if tmp == K.OCLEVERRING then
         c[K.INTELLIGENCE] = c[K.INTELLIGENCE] + 1
      elseif tmp == K.OSTRRING then
         c[K.STREXTRA] = c[K.STREXTRA] + 1
      elseif tmp == K.ODEXRING then
         c[K.DEXTERITY] = c[K.DEXTERITY] + 1
      end
      if ivenarg[slot] >= 10 and ns.rnd(10) <= 9 then
         if how == K.ENCH_ALTAR then
            ivenarg[slot] = ivenarg[slot] - 1
            ui:Message(L["Your weapon glows a little."])
         else
            ui:Message(L["Your weapon vibrates violently and crumbles into dust!"])
            iven[slot], ivenarg[slot] = 0, 0
            c[K.WIELD] = 0
         end
      else
         ui:Message(L["Your weapon glows for a moment."])
      end
      Player.recalc()
      ui:Refresh("all")
   end
end
