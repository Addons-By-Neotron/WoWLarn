--[[
**********************************************************************
WoWLarn - Standing on objects (object.c). items, traps, stairs, entrance and shafts so far.
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

-- C: nearbymonst(). True if a monster is next to the player.
local function NearbyMonster()
   for x = G.playerx - 1, G.playerx + 1 do
      for y = G.playery - 1, G.playery + 1 do
         if x >= 1 and x <= MAXX and y >= 1 and y <= MAXY and G.mon[x][y] ~= 0 then
            return true
         end
      end
   end
   return false
end
Object.nearbyMonster = NearbyMonster

-- C: forget(). Destroys the object at the player's location.
local function Forget()
   G.item[G.playerx][G.playery] = 0
   G.know[G.playerx][G.playery] = 0
end

local function Msg(fmt, ...)
   ns.ui:Message(fmt, ...)
end

-- C: finditem(). Says what was found and asks if the player wants to take it.
local NO_ARG = {
   [K.ODIAMOND] = true, [K.ORUBY] = true, [K.OEMERALD] = true, [K.OSAPPHIRE] = true, [K.OSPIRITSCARAB] = true,
   [K.OORBOFDRAGON] = true, [K.OORB] = true, [K.OHANDofFEAR] = true, [K.OWWAND] = true,
   [K.OCUBEofUNDEAD] = true, [K.ONOTHEFT] = true,
}
local function FindItem(itm)
   local arg = G.iarg[G.playerx][G.playery]
   Msg(L["You find %s%s"], ns.Article(ns.Tables.objectname[itm]), ns.ItemInfo.link(itm, NO_ARG[itm] and 0 or arg))
   if ns.ui:Choose(L["Do you want to (t) take it, or (i) ignore it?"], "t") == "t" then
      if ns.Player.take(itm, arg) then Forget() end
   end
end

-- C: ogold(). Picks up gold; the piles are worth 10, 100 or 1000 times their argument.
local function PickUpGold(kind)
   ns.ui:Sound("gold")
   local amount = G.iarg[G.playerx][G.playery]
   if kind == K.ODGOLD then
      amount = amount * 10
   elseif kind == K.OMAXGOLD then
      amount = amount * 100
   elseif kind == K.OKGOLD then
      amount = amount * 1000
   end
   Msg(amount == 1 and L["You find %d gold piece."] or L["You find %d gold pieces."], amount)
   G.c[K.GOLD] = G.c[K.GOLD] + amount
   Forget()
   ns.ui:Refresh("stats")
end

-- Drugs: eat, snort or smoke it, take it, or ignore it.
local function Drug(link, useKey, id, effect)
   local ui = ns.ui
   Msg(L["You find a vial of %s."], link)
   local choice = ui:Choose(L["Do you want to (d) drink it, (t) take it, or (i) ignore it?"], useKey .. "t")
   if choice == useKey then
      effect()
      Forget()
      ui:Refresh("all")
   elseif choice == "t" then
      if ns.Player.take(id, 0) then Forget() end
   end
end

local function AtLeast3(index, amount)
   local c = G.c
   c[index] = c[index] - amount
   if c[index] < 3 then c[index] = 3 end
end

-- The effects of the elixirs of the goblin alchemist (drunk where found or from the pack).
local c = G.c
local ELIXIR = {
   [K.OSPEED] = function()
      Msg(L["Everything around you seems to slow down!"])
      c[K.HASTESELF] = c[K.HASTESELF] + 200 + c[K.LEVEL]
      c[K.HALFDAM] = c[K.HALFDAM] + 300 + ns.rnd(200)
      AtLeast3(K.INTELLIGENCE, 2)
      AtLeast3(K.WISDOM, 2)
      AtLeast3(K.CONSTITUTION, 2)
      AtLeast3(K.DEXTERITY, 2)
      AtLeast3(K.STRENGTH, 2)
   end,
   [K.OSHROOMS] = function()
      Msg(L["The world turns glowy and strange..."])
      c[K.HASTEMONST] = c[K.HASTEMONST] + ns.rnd(75) + 25
      c[K.CONFUSE] = c[K.CONFUSE] + 30 + ns.rnd(10)
      c[K.WISDOM] = c[K.WISDOM] + 2
      c[K.CHARISMA] = c[K.CHARISMA] + 2
   end,
   [K.OACID] = function()
      Msg(L["Your mind expands, and the room starts to spin!"])
      c[K.CONFUSE] = c[K.CONFUSE] + 30 + ns.rnd(10)
      c[K.WISDOM] = c[K.WISDOM] + 2
      c[K.INTELLIGENCE] = c[K.INTELLIGENCE] + 2
      c[K.AWARENESS] = c[K.AWARENESS] + 1500
      c[K.AGGRAVATE] = c[K.AGGRAVATE] + 1500
      for mx = 1, MAXX do  -- heal the monsters
         for my = 1, MAXY do
            if G.mon[mx][my] ~= 0 then G.hitp[mx][my] = G.monster[G.mon[mx][my]].hitpoints end
         end
      end
   end,
   [K.OHASH] = function()
      Msg(L["The brew hits hard.  You feel strong, and very sluggish..."])
      c[K.HASTEMONST] = c[K.HASTEMONST] + ns.rnd(75) + 25
      c[K.INTELLIGENCE] = c[K.INTELLIGENCE] + 2
      c[K.WISDOM] = c[K.WISDOM] + 2
      AtLeast3(K.CONSTITUTION, 2)
      AtLeast3(K.DEXTERITY, 2)
      c[K.HALFDAM] = c[K.HALFDAM] + 300 + ns.rnd(200)
      c[K.CLUMSINESS] = c[K.CLUMSINESS] + ns.rnd(1800) + 200
      G.drugClumsy = true  -- (so that dropping the weapon is known for what it comes from)
   end,
   [K.OCOKE] = function()
      Msg(L["Fel energy surges through you!  Your nose begins to bleed!"])
      AtLeast3(K.DEXTERITY, 2)
      AtLeast3(K.CONSTITUTION, 2)
      c[K.CHARISMA] = c[K.CHARISMA] + 3
      for i = K.STRENGTH, K.STRENGTH + 5 do c[i] = c[i] + 33 end
      c[K.COKED] = c[K.COKED] + 10
   end,
}

-- Drinking one finds out what it does (ItemInfo.discover).
for id, effect in pairs(ELIXIR) do
   ELIXIR[id] = function()
      effect()
      ns.ItemInfo.discover(id)
   end
end

function Object.isElixir(id)
   return ELIXIR[id] ~= nil
end

-- Drinks the elixir id from the pack; returns false if it is not one.
function Object.drinkElixir(id)
   if not ELIXIR[id] then return false end
   ELIXIR[id]()
   return true
end

-- C: opit().
local function Pit()
   local c = G.c
   if ns.rnd(101) > 81 then return end
   if ns.rnd(70) > 9 * c[K.DEXTERITY] - ns.Player.packWeight() or ns.rnd(101) < 5 then
      for i = 1, K.IVENSIZE do
         if G.iven[i] == K.OWWAND then
            Msg(L["You float right over the pit."])
            ns.ItemInfo.discover(K.OWWAND)
            return
         end
      end
      if G.level == DBOTTOM or G.level == VBOTTOM then
         Msg(L["You fell into a pit leading straight to HELL!"])
         ns.ui:Nap(3000)
         ns.Player.died(262)
         return
      end
      local damage
      if ns.rnd(101) < 20 then
         damage = 0
         Msg(L["You fell into a pit!  A poor monster cushions your fall!"])
      else
         damage = ns.rnd(G.level * 3 + 3)
         if damage > c[K.HP] then damage = c[K.HP] end
         Msg(damage == 1 and L["You fell into a pit!  You suffer %d hit point damage."]
            or L["You fell into a pit!  You suffer %d hit points damage."], damage)
         G.lastnum = 261
      end
      ns.Player.losehp(damage)
      if G.dead then return end
      ns.ui:Nap(2000)
      Create.newCaveLevel(G.level + 1)
      ns.ui:Refresh("all")
   end
end

-- C: oelevator(). dir 1 goes up, -1 goes down.
local function Elevator(dir)
   local ui = ns.ui
   if dir == 1 then
      if G.level == 0 then
         Msg(L["Unfortunately, it is out of order."])
         return
      end
      G.playerx, G.playery = ns.rnd(MAXX - 2) + 1, ns.rnd(MAXY - 2) + 1
      ui:Nap(2000)
      Create.newCaveLevel(ns.rund(G.level))
   else
      if G.level == DBOTTOM or G.level == VBOTTOM then
         ui:Nap(2000)
         Msg(L["And it leads straight to HELL!"])
         ui:Nap(3000)
         ns.Player.died(287)
         return
      end
      G.playerx, G.playery = ns.rnd(MAXX - 2) + 1, ns.rnd(MAXY - 2) + 1
      ui:Nap(2000)
      Create.newCaveLevel(G.level + ns.rnd(math.max(DBOTTOM - G.level, 1)))
   end
   ns.Player.positionPlayer()
   ui:Refresh("all")
end

-- C: ochest().
local function Chest()
   local ui, c = ns.ui, G.c
   local x, y = G.playerx, G.playery
   local choice = ui:Choose(L["Do you (t) take it, (o) try to open it, or (i) ignore it?"], "to")
   if choice == "o" then
      if ns.rnd(101) < 40 then
         Msg(L["The chest explodes as you open it."])
         local damage = ns.rnd(10)
         if damage > c[K.HP] then damage = c[K.HP] end
         G.lastnum = 281  -- in case he dies
         Msg(damage == 1 and L["You suffer %d hit point damage!"] or L["You suffer %d hit points damage!"], damage)
         if damage > 0 then ns.Player.losehp(damage) end
         if G.dead then return end
         local roll = ns.rnd(10)
         if roll == 1 then
            c[K.ITCHING] = c[K.ITCHING] + ns.rnd(1000) + 100
            Msg(L["You feel an irritation spread over your skin!"])
         elseif roll == 2 then
            c[K.CLUMSINESS] = c[K.CLUMSINESS] + ns.rnd(1600) + 200
            Msg(L["You begin to lose hand-eye co-ordination!"])
         elseif roll == 3 then
            c[K.HALFDAM] = c[K.HALFDAM] + ns.rnd(1600) + 200
            Msg(L["You suddenly feel sick and BARF all over your shoes!"])
         end
         local level = G.iarg[x][y]
         G.item[x][y], G.know[x][y] = 0, 0
         if ns.rnd(100) < 69 then ns.Item.createGem() end  -- gems from the chest
         ns.Item.dropGold(ns.rnd(110 * level + 200))
         -- the C re-rolls the limit on every pass
         local i = 0
         while i < ns.rnd(4) do
            ns.Item.something(x, y, level + 2)
            i = i + 1
         end
      else
         Msg(L["The lock holds firm and the chest stays shut."])
      end
   elseif choice == "t" then
      if ns.Player.take(K.OCHEST, G.iarg[x][y]) then Forget() end
   end
end

-- Objects that arrive later: the town buildings (milestone 8).
local LATER = {}
for _, id in ipairs({ K.OSCHOOL, K.OBANK, K.OBANK2, K.ODNDSTORE, K.OTRADEPOST, K.OHOME, K.OPAD, K.OLRS }) do
   LATER[id] = true
end

local BUILDING = {
   [K.OSCHOOL] = { found = L["You have found the College of Ularn."], key = "g", enter = function() ns.Town.school() end },
   [K.OBANK] = { found = L["You have found the bank of Ularn."], key = "g", enter = function() ns.Town.bank(false) end },
   [K.OBANK2] = { found = L["You have found a branch office of the bank of Ularn."], key = "g", enter = function() ns.Town.bank(true) end },
   [K.ODNDSTORE] = { found = L["There is a DND store here."], key = "g", enter = function() ns.Town.dndStore() end },
   [K.OTRADEPOST] = { found = L["You have found the Ularn trading Post."], key = "g", enter = function() ns.Town.tradingPost() end },
   [K.OHOME] = { found = L["You have found your way home."], key = "g", enter = function() ns.Town.home() end },
   [K.OPAD] = { found = L["You have found Grizzik's Questionable Elixirs!"], key = "c", enter = function() ns.Town.pad() end },
   [K.OLRS] = { found = L["There is an LRS office here."], key = "g", enter = function() ns.Town.lrs() end },
}
for _, building in pairs(BUILDING) do
   building.prompt = building.key == "c" and L["Do you (c) check it out, or (i) ignore it?"] or L["Do you (g) go inside, or (i) stay here?"]
end

-- C: lookforobject(). Everything you can step on does something.
function Object.lookForObject()
   local c = G.c
   if c[K.TIMESTOP] ~= 0 then return end  -- can't find objects if time is stopped
   local x, y = G.playerx, G.playery
   local id = G.item[x][y]
   if id == 0 then return end

   local ui = ns.ui
   ns.Display.showcell(x, y)
   ui.repcount = 0
   G.named[x][y] = id  -- (looked at: the mouse over it tells what it is)
   local name = ns.Tables.objectname[id]

   if id == K.OGOLDPILE or id == K.OMAXGOLD or id == K.OKGOLD or id == K.ODGOLD then
      PickUpGold(id)

   elseif id == K.OPOTION then
      local arg = G.iarg[x][y]
      local T = ns.Tables
      if G.potionknown[arg] ~= 0 then
         Msg(L["You find a magic potion of %s."], T.potionname[arg])
      else
         Msg(L["You find a magic potion."])
      end
      local choice = ui:Choose(L["Do you (d) drink it, (t) take it, or (i) ignore it?"], "dt")
      if choice == "d" then
         Forget()  -- destroy the potion
         ns.Magic.quaffPotion(arg)
      elseif choice == "t" then
         if ns.Player.take(K.OPOTION, arg) then Forget() end
      end

   elseif id == K.OSCROLL then
      local arg = G.iarg[x][y]
      local T = ns.Tables
      if G.scrollknown[arg] ~= 0 then
         Msg(L["You find a magic scroll of %s."], T.scrollname[arg])
      else
         Msg(L["You find a magic scroll."])
      end
      local choice
      if c[K.BLINDCOUNT] == 0 then
         choice = ui:Choose(L["Do you (r) read it, (t) take it, or (i) ignore it?"], "rt")
      else
         choice = ui:Choose(L["Do you (t) take it, or (i) ignore it?"], "t")
      end
      if choice == "r" then
         Forget()  -- destroy it
         ns.Magic.readScroll(arg)
      elseif choice == "t" then
         if ns.Player.take(K.OSCROLL, arg) then Forget() end
      end

   elseif id == K.OBOOK then
      Msg(L["You find a book."])
      local arg = G.iarg[x][y]
      local choice
      if c[K.BLINDCOUNT] == 0 then
         choice = ui:Choose(L["Do you (r) read it, (t) take it, or (i) ignore it?"], "rt")
      else
         choice = ui:Choose(L["Do you (t) take it, or (i) ignore it?"], "t")
      end
      if choice == "r" then
         ns.Magic.readBook(arg)
         Forget()  -- no more book
      elseif choice == "t" then
         if ns.Player.take(K.OBOOK, arg) then Forget() end
      end

   elseif id == K.OCOOKIE then
      Msg(L["You find a fortune cookie."])
      local choice = ui:Choose(L["Do you (e) eat it, (t) take it, or (i) ignore it?"], "et")
      if choice == "e" then
         Msg(L["The cookie tasted good."])
         Forget()  -- no more cookie
         if c[K.BLINDCOUNT] == 0 then
            Msg(L["A message inside the cookie reads:"])
            Msg("%s", ns.Action.fortune())
         end
      elseif choice == "t" then
         if ns.Player.take(K.OCOOKIE, 0) then Forget() end
      end

   elseif id == K.OORB or id == K.OWWAND or id == K.OHANDofFEAR then
      if NearbyMonster() then return end
      FindItem(id)

   elseif id == K.OPIT then
      Msg(L["You're standing at the top of a pit."])
      Pit()

   elseif id == K.OSTAIRSUP then
      Msg(L["There is a circular staircase here."])
      Stairs(1)

   elseif id == K.OSTAIRSDOWN then
      Msg(L["There is a circular staircase here."])
      Stairs(-1)

   elseif id == K.OELEVATORUP then
      Msg(L["You have found an express elevator going up."])
      Elevator(1)

   elseif id == K.OELEVATORDOWN then
      Msg(L["You have found an express elevator going down."])
      Elevator(-1)

   elseif id == K.OCHEST then
      Msg(L["There is a chest here."])
      Chest()

   elseif id == K.OIVTELETRAP or id == K.OTELEPORTER then
      if id == K.OIVTELETRAP then
         if ns.rnd(11) < 6 then return end
         G.item[x][y] = K.OTELEPORTER
         G.know[x][y] = 1
      end
      Msg(L["Zaaaappp!  You've been teleported!"])
      ui:Nap(3000)
      ns.Magic.teleport(false)

   elseif id == K.OOPENDOOR then
      Msg(L["There is an open door here."])

   elseif id == K.OCLOSEDDOOR then
      if G.dropflag then return end
      Msg(L["You find %s"], name)
      if ui:Choose(L["Do you (o) try to open it, or (i) ignore it?"], "o") ~= "o" then
         G.playerx, G.playery = G.lastpx, G.lastpy
         return
      end
      if ns.rnd(11) < 7 then
         local trap = G.iarg[x][y]
         -- (the C says nothing when the door does not open)
         Msg(L["The door is stuck and won't open."])
         ui:Sound("stuck")
         if trap == 6 then
            Msg(L["Your struggle makes a loud noise!"])
            c[K.AGGRAVATE] = c[K.AGGRAVATE] + ns.rnd(400)
         elseif trap == 7 or trap == 8 then
            Msg(L["You are jolted by an electric shock!"])
            G.lastnum = 274
            ns.Player.losehp(ns.rnd(20))
            if G.dead then return end
         elseif trap == 9 then
            Msg(L["You suddenly feel weaker!"])
            if c[K.STRENGTH] > 3 then c[K.STRENGTH] = c[K.STRENGTH] - 1 end
         end
         G.playerx, G.playery = G.lastpx, G.lastpy
      else
         Msg(L["The door opens."])
         ui:Sound("door")
         Forget()
         G.item[x][y] = K.OOPENDOOR
      end
      ui:Refresh("all")

   elseif id == K.OTRAPARROWIV or id == K.OTRAPARROW then
      if id == K.OTRAPARROWIV then
         if ns.rnd(17) < 13 then return end
         G.item[x][y] = K.OTRAPARROW
         G.know[x][y] = 0
      end
      Msg(L["You are hit by an arrow!"])
      G.lastnum = 259
      ns.Player.losehp(ns.rnd(10) + G.level)

   elseif id == K.OIVDARTRAP or id == K.ODARTRAP then
      if id == K.OIVDARTRAP then
         if ns.rnd(17) < 13 then return end
         G.item[x][y] = K.ODARTRAP
         G.know[x][y] = 0
      end
      Msg(L["You are hit by a dart!"])
      G.lastnum = 260
      ns.Player.losehp(ns.rnd(5))
      if G.dead then return end
      c[K.STRENGTH] = c[K.STRENGTH] - 1
      if c[K.STRENGTH] < 3 then c[K.STRENGTH] = 3 end
      ui:Refresh("stats")

   elseif id == K.OIVTRAPDOOR or id == K.OTRAPDOOR then
      if id == K.OIVTRAPDOOR then
         if ns.rnd(17) < 13 then return end
         G.item[x][y] = K.OTRAPDOOR
         G.know[x][y] = 1
      end
      G.lastnum = 272  -- a trap door
      for i = 1, K.IVENSIZE do
         if G.iven[i] == K.OWWAND then
            Msg(L["You escape a trap door."])
            ns.ItemInfo.discover(K.OWWAND)
            return
         end
      end
      if G.level == DBOTTOM or G.level == VBOTTOM then
         Msg(L["You fall through a trap door leading straight to HELL!"])
         ui:Nap(3000)
         ns.Player.died(271)
         return
      end
      Msg(L["You fall through a trap door!"])
      ns.Player.losehp(ns.rnd(5 + G.level))
      if G.dead then return end
      ui:Nap(2000)
      Create.newCaveLevel(G.level + 1)
      ui:Refresh("all")

   elseif id == K.OENTRANCE then
      Msg(L["You have found %s"], name)
      if ui:Choose(L["Do you (g) go inside, or (i) ignore it?"], "g") == "g" then
         Create.newCaveLevel(1)
         G.playerx, G.playery = 34, MAXY - 1
         G.item[34][MAXY], G.know[34][MAXY], G.mon[34][MAXY] = 0, 0, 0
         ui:Refresh("all")
      end

   elseif id == K.OVOLDOWN then
      Msg(L["You have found %s"], name)
      if ui:Choose(L["Do you (c) climb down, or (i) ignore it?"], "c") == "i" then return end
      if G.level ~= 0 then
         Msg(L["The shaft only extends 5 feet downward!"])
         return
      end
      if ns.Player.packWeight() > 45 + 3 * (c[K.STRENGTH] + c[K.STREXTRA]) then
         Msg(L["You slip and fall down the shaft."])
         G.lastnum = 275
         ns.Player.losehp(30 + ns.rnd(20))
         if G.dead then return end
      else
         Msg(L["You climb down."])
      end
      ui:Nap(3000)
      Create.newCaveLevel(DBOTTOM + 1)  -- down to V1
      G.playerx, G.playery = ns.rnd(MAXX - 2) + 1, ns.rnd(MAXY - 2) + 1
      ns.Player.positionPlayer()
      ui:Refresh("all")

   elseif id == K.OVOLUP then
      Msg(L["You have found %s"], name)
      if ui:Choose(L["Do you (c) climb up, or (i) ignore it?"], "c") == "i" then return end
      if ns.Player.packWeight() > 40 + 5 * (c[K.DEXTERITY] + c[K.STRENGTH] + c[K.STREXTRA]) then
         Msg(L["You slip and fall down the shaft."])
         G.lastnum = 275
         ns.Player.losehp(15 + ns.rnd(20))
         return
      end
      Msg(L["You climb up."])
      ui:Nap(3000)
      Create.newCaveLevel(0)
      MoveToObject(K.OVOLDOWN)  -- put the player near the volcano shaft
      ns.Player.positionPlayer()
      ui:Refresh("all")

   elseif id == K.OSPEED then
      Drug(ns.ItemInfo.link(id, 0), "d", id, ELIXIR[id])

   elseif id == K.OSHROOMS then
      Drug(ns.ItemInfo.link(id, 0), "d", id, ELIXIR[id])

   elseif id == K.OACID then
      Drug(ns.ItemInfo.link(id, 0), "d", id, ELIXIR[id])

   elseif id == K.OHASH then
      Drug(ns.ItemInfo.link(id, 0), "d", id, ELIXIR[id])

   elseif id == K.OCOKE then
      Drug(ns.ItemInfo.link(id, 0), "d", id, ELIXIR[id])

   elseif id == K.OWALL then
      return

   elseif id == K.OANNIHILATION then
      for i = 1, K.IVENSIZE do
         if G.iven[i] == K.OSPHTALISMAN then
            Msg(L["The Talisman of the Sphere protects you from annihilation!"])
            return
         end
      end
      ns.Player.died(283)  -- annihilated by a sphere of annihilation

   elseif id == K.OALTAR then
      if NearbyMonster() then return end
      Msg(L["There is a holy altar here."])
      ns.Features.altar()

   elseif id == K.OTHRONE or id == K.OTHRONE2 then
      if NearbyMonster() then return end
      Msg(L["There is %s here."], name)
      ns.Features.throne(id == K.OTHRONE2 and 1 or 0)

   elseif id == K.ODEADTHRONE then
      Msg(L["There is %s here."], name)
      ns.Features.deadThrone()

   elseif id == K.OBRASSLAMP then
      ns.Features.lamp()

   elseif id == K.OFOUNTAIN then
      if NearbyMonster() then return end
      Msg(L["There is a fountain here."])
      ns.Features.fountain()

   elseif id == K.OSTATUE then  -- nothing happens when you move on a statue
      if NearbyMonster() then return end
      Msg(L["You stand before a statue."])

   elseif id == K.OMIRROR then  -- nothing happens when you move on a mirror
      if NearbyMonster() then return end
      Msg(L["There is a mirror here."])

   elseif id == K.ODEADFOUNTAIN then
      if NearbyMonster() then return end
      Msg(L["There is a dead fountain here."])

   elseif LATER[id] then
      if NearbyMonster() then return end
      local building = BUILDING[id]
      Msg(building.found)
      if ui:Choose(building.prompt, building.key) == building.key then
         building.enter(id)
      end

   else
      FindItem(id)
   end
end
