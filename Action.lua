--[[
**********************************************************************
WoWLarn - Inventory commands (action.c and parts of main.c).
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

local Action = {}
ns.Action = Action

local c, iven, ivenarg = G.c, G.iven, G.ivenarg
local item = G.item

local function Msg(fmt, ...)
   ns.ui:Message(fmt, ...)
end

local function Set(...)
   local set = {}
   for _, id in ipairs({ ... }) do set[id] = true end
   return set
end

-- What each command lists as valid (C: whatitem). Any slot can still be picked.
local WIELD = Set(K.OSWORDofSLASHING, K.OHAMMER, K.OSWORD, K.O2SWORD, K.OSPEAR, K.ODAGGER, K.OBATTLEAXE,
   K.OLONGSWORD, K.OFLAIL, K.OSLAYER, K.OLANCE, K.OVORPAL,
   K.OPSTAFF)  -- (not in the C list, though the table gives it a weapon class; a staff is a weapon)
local ARMOR = Set(K.OPLATE, K.OCHAIN, K.OLEATHER, K.ORING, K.OSTUDLEATHER, K.OSPLINT, K.OPLATEARMOR,
   K.OSSPLATE, K.OELVENCHAIN)
local WEAR = Set(K.OPLATE, K.OCHAIN, K.OLEATHER, K.ORING, K.OSTUDLEATHER, K.OSPLINT, K.OPLATEARMOR,
   K.OSSPLATE, K.OSHIELD, K.OELVENCHAIN)
local READ = Set(K.OSCROLL, K.OBOOK)

local function Has(set)
   return function(id) return set[id] end
end
local function Is(what)
   return function(id) return id == what end
end
local function Any(id)
   return id ~= 0
end

local function DontHave(slot)
   Msg(L["You don't have item %s!"], string.char(96 + slot))
end

local function CantWield(slot)
   Msg(L["You can't wield item %s!"], string.char(96 + slot))
end

-- " +2" or " -1" after the name of the thing just worn or wielded.
local function Enchantment(arg)
   if arg > 0 then return " +" .. arg end
   if arg < 0 then return " " .. arg end
   return ""
end

-- A weapon, armor or shield picked up while the slot is empty is put on at once (not in the
-- C).  Only if it adds something, and if the other hand is free for the two-handed sword.
function Action.autoEquip(slot)
   local id, arg = iven[slot], ivenarg[slot]
   local name = ns.StripArticle(ns.Tables.objectname[id] or "?")
   if WIELD[id] and c[K.WIELD] == 0 then
      if id == K.O2SWORD and c[K.SHIELD] ~= 0 then return end
      if (ns.Player.WEAPON_WC[id] or 0) + arg <= 0 then return end
      c[K.WIELD] = slot
      c[K.LANCEDEATH] = id == K.OLANCE and 1 or 0
      Msg(L["You automatically wield your %s%s."], name, Enchantment(arg))
   elseif ARMOR[id] and c[K.WEAR] == 0 then
      if (ns.Player.ARMOR_AC[id] or 0) + arg <= 0 then return end
      c[K.WEAR] = slot
      Msg(L["You automatically put on your %s%s."], name, Enchantment(arg))
   elseif id == K.OSHIELD and c[K.SHIELD] == 0 then
      if c[K.WIELD] > 0 and iven[c[K.WIELD]] == K.O2SWORD then return end
      if 2 + arg <= 0 then return end
      c[K.SHIELD] = slot
      Msg(L["You automatically put on your shield%s."], Enchantment(arg))
   else
      return
   end
   ns.Player.recalc()
   ns.ui:Refresh("all")
end

-- C: wield().
function Action.wield()
   local slot = ns.ui:PickItem(L["wield"], Has(WIELD), { none = true, only = true, empty = L["You have nothing to wield."] })
   if not slot then return end
   if slot == "none" then
      c[K.WIELD] = 0
      Msg(L["You unwield your weapon."])
   elseif iven[slot] == 0 then
      DontHave(slot)
   elseif iven[slot] == K.OPOTION or iven[slot] == K.OSCROLL then
      CantWield(slot)
   elseif c[K.SHIELD] ~= 0 and iven[slot] == K.O2SWORD then
      Msg(L["But one arm is busy with your shield!"])
   elseif slot == c[K.WEAR] or slot == c[K.SHIELD] then
      Msg(slot == c[K.WEAR] and L["You can't wield your armor while you're wearing it!"]
         or L["You can't wield your shield while you're wearing it!"])
   else
      c[K.WIELD] = slot
      Msg(L["You wield %s%s."], ns.Tables.objectname[iven[slot]], Enchantment(ivenarg[slot]))
      c[K.LANCEDEATH] = iven[slot] == K.OLANCE and 1 or 0
   end
   ns.Player.recalc()
   ns.ui:Refresh("all")
end

-- C: wear().
function Action.wear()
   local slot = ns.ui:PickItem(L["wear"], Has(WEAR), { only = true, empty = L["You have nothing to wear."] })
   if not slot then return end
   local id = iven[slot]
   if id == 0 then
      DontHave(slot)
   elseif ARMOR[id] then
      if c[K.WEAR] ~= 0 then
         Msg(L["You are already wearing some armor."])
         return
      end
      c[K.WEAR] = slot
      if c[K.WIELD] == slot then c[K.WIELD] = 0 end
      Msg(L["You put on your %s%s."], ns.Tables.objectname[id], Enchantment(ivenarg[slot]))
   elseif id == K.OSHIELD then
      if c[K.SHIELD] ~= 0 then
         Msg(L["You are already wearing a shield."])
         return
      end
      if c[K.WIELD] > 0 and iven[c[K.WIELD]] == K.O2SWORD then
         Msg(L["Your hands are busy with the two handed sword!"])
         return
      end
      c[K.SHIELD] = slot
      if c[K.WIELD] == slot then c[K.WIELD] = 0 end
      Msg(L["You put on your shield%s."], Enchantment(ivenarg[slot]))
   else
      Msg(L["You can't wear that!"])
      return
   end
   ns.Player.recalc()
   ns.ui:Refresh("all")
end

-- What kind of thing the equipment window wants taken off ("armor" or "shield"), for the
-- next 'T'.
Action.takeOffWhat = nil

-- True if the object can be wielded / worn as armor / worn as a shield (for the equipment window).
function Action.isWeapon(id) return WIELD[id] or false end
function Action.isArmor(id) return ARMOR[id] or false end
function Action.isShield(id) return id == K.OSHIELD end

-- C: the 'T' command.
function Action.takeOff()
   local what = Action.takeOffWhat
   Action.takeOffWhat = nil
   if what == "armor" and c[K.WEAR] ~= 0 then
      c[K.WEAR] = 0
      Msg(L["Your armor is off."])
   elseif c[K.SHIELD] ~= 0 then
      c[K.SHIELD] = 0
      Msg(L["Your shield is off."])
   elseif c[K.WEAR] ~= 0 then
      c[K.WEAR] = 0
      Msg(L["Your armor is off."])
   else
      Msg(L["You aren't wearing anything."])
      return
   end
   ns.Player.recalc()
   ns.ui:Refresh("all")
end

-- C: dropobj(). Drops an item, or some gold.
function Action.drop()
   local ui = ns.ui
   local slot = ui:PickItem(L["drop"], Any, { gold = true })
   if not slot then return end
   if slot ~= "gold" then
      ns.Player.dropObject(slot)
      return
   end

   local here = item[G.playerx][G.playery]
   local pit = here == K.OPIT
   if here ~= 0 and not pit then
      Msg(L["There's something here already!"])
      return
   end
   local amt = ui:GetNumber(L["How much gold do you drop?"], c[K.GOLD])
   if amt <= 0 then return end
   if amt > c[K.GOLD] then
      Msg(L["You don't have that much!"])
      return
   end
   local arg
   if amt <= 32767 then
      item[G.playerx][G.playery] = K.OGOLDPILE
      arg = amt
   elseif amt <= 327670 then
      item[G.playerx][G.playery] = K.ODGOLD
      arg = ns.idiv(amt, 10)
      amt = 10 * arg
   elseif amt <= 3276700 then
      item[G.playerx][G.playery] = K.OMAXGOLD
      arg = ns.idiv(amt, 100)
      amt = 100 * arg
   elseif amt <= 32767000 then
      item[G.playerx][G.playery] = K.OKGOLD
      arg = ns.idiv(amt, 1000)
      amt = 1000 * arg
   else
      item[G.playerx][G.playery] = K.OKGOLD
      arg, amt = 32767, 32767000
   end
   c[K.GOLD] = c[K.GOLD] - amt
   Msg(amt == 1 and L["You drop %d gold piece."] or L["You drop %d gold pieces."], amt)
   if pit then
      item[G.playerx][G.playery] = K.OPIT
      Msg(L["The gold disappears down the pit."])
   else
      G.iarg[G.playerx][G.playery] = arg
   end
   G.know[G.playerx][G.playery] = 0
   G.dropflag = true
   ui:Refresh("all")
end

-- C: readscr(). Reads a scroll or a book from the pack.
function Action.read()
   local slot = ns.ui:PickItem(L["read"], Has(READ), { only = true, empty = L["You have no scrolls or books to read."] })
   if not slot then return end
   local id = iven[slot]
   if id == K.OSCROLL then
      ns.Magic.readScroll(ivenarg[slot])
      iven[slot] = 0
   elseif id == K.OBOOK then
      ns.Magic.readBook(ivenarg[slot])
      iven[slot] = 0
   elseif id == 0 then
      DontHave(slot)
   else
      Msg(L["There's nothing on it to read."])
   end
   ns.ui:Refresh("all")
end

-- C: quaff().
function Action.quaff()
   local slot = ns.ui:PickItem(L["quaff"], function(id) return id == K.OPOTION or ns.Object.isElixir(id) end,
      { only = true, empty = L["You have no potions to drink."] })
   if not slot then return end
   local id = iven[slot]
   if ns.Object.isElixir(id) then
      iven[slot], ivenarg[slot] = 0, 0
      ns.Object.drinkElixir(id)
   elseif id == K.OPOTION then
      local arg = ivenarg[slot]
      iven[slot] = 0
      ns.Magic.quaffPotion(arg)
   elseif id == 0 then
      DontHave(slot)
   else
      Msg(L["You wouldn't want to quaff that, would you?"])
   end
   ns.ui:Refresh("all")
end

-- The message of a fortune cookie (C: fortune()).
function Action.fortune()
   local list = ns.Fortunes
   return list[ns.rnd(#list)]
end

-- C: eatcookie().
function Action.eat()
   local slot = ns.ui:PickItem(L["eat"], Is(K.OCOOKIE), { only = true, empty = L["You have no cookies to eat."] })
   if not slot then return end
   local id = iven[slot]
   if id == K.OCOOKIE then
      Msg(L["The cookie was delicious."])
      iven[slot] = 0
      if c[K.BLINDCOUNT] == 0 then
         Msg(L["Inside you find a scrap of paper that says:"])
         Msg("%s", Action.fortune())
      end
   elseif id == 0 then
      DontHave(slot)
   else
      Msg(L["You can't eat that!"])
   end
   ns.ui:Refresh("all")
end

-- C: closedoor().
function Action.closeDoor()
   if c[K.TIMESTOP] ~= 0 then return end
   ns.Display.showcell(G.playerx, G.playery)
   ns.ui.repcount = 0
   if item[G.playerx][G.playery] ~= K.OOPENDOOR then
      Msg(L["There is no open door here."])
      return
   end
   Msg(L["The door closes."])
   item[G.playerx][G.playery] = K.OCLOSEDDOOR
   G.know[G.playerx][G.playery] = 0
   G.iarg[G.playerx][G.playery] = 0
   G.dropflag = true  -- so we won't be asked to open it
   ns.ui:Refresh("all")
end

-- C: the '^' command. Names the traps next to the player.
local TRAPS = Set(K.OTRAPDOOR, K.ODARTRAP, K.OTRAPARROW, K.OTELEPORTER, K.OELEVATORUP, K.OELEVATORDOWN)
function Action.findTraps()
   local found = 0
   for y = math.max(1, G.playery - 1), math.min(K.MAXY, G.playery + 1) do
      for x = math.max(1, G.playerx - 1), math.min(K.MAXX, G.playerx + 1) do
         if TRAPS[item[x][y]] then
            Msg(L["It's %s"], ns.Tables.objectname[item[x][y]])
            found = found + 1
         end
      end
   end
   if found == 0 then
      Msg(L["No traps are visible."])
   end
end

-- C: the 'Z' command.
function Action.teleport()
   if G.wizard then
      local t = ns.ui:GetNumber(L["Which level do you wish to teleport to?"], 20)
      if t > 20 or t < 0 then
         Msg(L["Sorry!"])
         return
      end
      G.playerx, G.playery = ns.rnd(K.MAXX - 2) + 1, ns.rnd(K.MAXY - 2) + 1
      ns.Create.newCaveLevel(t)
      ns.Player.positionPlayer()
      ns.ui:Refresh("all")
   elseif c[K.LEVEL] > 9 then
      ns.Magic.teleport(true)
   else
      Msg(L["You don't know how to teleport yet."])
   end
end

-- The 'I' command (not in the original): puts the pack in order -- what is worn or wielded,
-- then what works while carried, then the rest, then the things to use up -- and the empty
-- slots last. The slots of the worn things move along.
local CONSUMABLE = Set(K.OPOTION, K.OSCROLL, K.OBOOK, K.OCOOKIE)
function Action.sortPack()
   local c, iven, ivenarg = G.c, G.iven, G.ivenarg
   local function group(slot)
      if iven[slot] == 0 then return 5 end
      if slot == c[K.WIELD] or slot == c[K.WEAR] or slot == c[K.SHIELD] then return 1 end
      if ns.Equipment.isPassive(iven[slot]) then return 2 end
      if CONSUMABLE[iven[slot]] then return 4 end
      return 3
   end
   local order = {}
   for slot = 1, K.IVENSIZE do order[slot] = slot end
   table.sort(order, function(a, b)
      local ga, gb = group(a), group(b)
      if ga ~= gb then return ga < gb end
      if iven[a] ~= iven[b] then return iven[a] < iven[b] end
      if ivenarg[a] ~= ivenarg[b] then return ivenarg[a] > ivenarg[b] end
      return a < b
   end)
   local items, args, where = {}, {}, {}
   for new, old in ipairs(order) do
      items[new], args[new], where[old] = iven[old], ivenarg[old], new
   end
   for slot = 1, K.IVENSIZE do iven[slot], ivenarg[slot] = items[slot], args[slot] end
   for _, key in ipairs({ K.WIELD, K.WEAR, K.SHIELD }) do
      if c[key] ~= 0 then c[key] = where[c[key]] end
   end
   Msg(L["You sort your pack."])
   ns.ui:Refresh("all")
end

-- C: the 'g' command.
function Action.packWeight()
   local pounds = ns.Player.packWeight()
   Msg(pounds == 1 and L["The stuff you are carrying presently weighs %d pound."]
      or L["The stuff you are carrying presently weighs %d pounds."], pounds)
end
