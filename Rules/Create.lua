--[[
**********************************************************************
WoWLarn - Player and level creation (create.c).
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
local _, ns = ...
local K = ns.K
local G = ns.G
local rnd, rund, idiv = ns.rnd, ns.rund, ns.idiv

local Create = {}
ns.Create = Create

local c, iven, ivenarg, spelknow = G.c, G.iven, G.ivenarg, G.spelknow
local item, iarg, know, mon = G.item, G.iarg, G.know, G.mon

local MAXX, MAXY = K.MAXX, K.MAXY
local DBOTTOM, VBOTTOM = K.DBOTTOM, K.VBOTTOM
local hitp = G.hitp

-- C: makeplayer() and pick_char(). class is an entry of ns.Classes.
-- Optional (the Races setting, not in Ularn): the race of the WoW character adds to the stats.
-- { strength, intelligence, wisdom, constitution, dexterity, charisma }
local RACES = {
   Human = { 0, 0, 1, 0, 0, 2 }, Dwarf = { 1, 0, 0, 2, 0, 0 }, NightElf = { 0, 0, 1, 0, 2, 0 },
   Gnome = { 0, 2, 0, 0, 1, 0 }, Draenei = { 0, 0, 2, 0, 0, 1 }, Worgen = { 1, 0, 0, 0, 2, 0 },
   Pandaren = { 0, 0, 1, 2, 0, 0 }, Orc = { 2, 0, 0, 1, 0, 0 }, Scourge = { 0, 1, 1, 1, 0, 0 },
   Tauren = { 2, 0, 0, 1, 0, 0 }, Troll = { 0, 0, 0, 2, 1, 0 }, BloodElf = { 0, 2, 0, 0, 0, 1 },
   Goblin = { 0, 2, 0, 0, 0, 1 },
}

-- The allied races count as the race they come from.
local KIN = {
   VoidElf = "BloodElf", Nightborne = "BloodElf", LightforgedDraenei = "Draenei", DarkIronDwarf = "Dwarf",
   EarthenDwarf = "Dwarf", KulTiran = "Human", Mechagnome = "Gnome", MagharOrc = "Orc",
   HighmountainTauren = "Tauren", ZandalariTroll = "Troll", Vulpera = "Goblin",
}
RACES.Dracthyr = { 1, 1, 0, 1, 0, 0 }
RACES.Haranir = { 0, 0, 1, 0, 2, 0 }

-- Adds the bonuses of the race of the player; returns its name, or nil.
local function ApplyRace()
   if not ns.mod.db.profile.races or not UnitRace then return nil end
   local name, token = UnitRace("player")
   local bonus = RACES[token] or RACES[KIN[token]]
   if not bonus then return nil end
   for i = 1, 6 do c[K.STRENGTH + i - 1] = c[K.STRENGTH + i - 1] + bonus[i] end
   return name
end

function Create.makePlayer(class)
   c[K.HARDGAME] = ns.mod.db.profile.difficulty or 0  -- (the setting at the start of the game)
   c[K.LEVEL] = 1
   c[K.REGENCOUNTER] = 16
   c[K.ECOUNTER] = 96  -- start regeneration correctly
   c[K.SHIELD], c[K.WEAR], c[K.WIELD] = 0, 0, 0  -- 0 is nothing (C: -1)

   for i = 1, 6 do
      c[K.STRENGTH + i - 1] = class.stats[i]
   end
   G.race = ApplyRace()
   c[K.HPMAX], c[K.HP] = class.hp, class.hp
   c[K.SPELLMAX], c[K.SPELLS] = class.spellmax, class.spellcount
   for _, spell in ipairs(class.spells) do
      spelknow[spell] = 1
   end
   for slot, entry in ipairs(class.kit) do
      iven[slot] = entry[1]
      ivenarg[slot] = entry[2] == "random" and rnd(6) or entry[2]
   end
   c[K.WEAR] = class.wear or 0
   c[K.WIELD] = class.wield or 0
   if class.lanceofdeath then
      c[K.LANCEDEATH] = 1
      G.ramboflag = true
   end

   G.class = class
   ns.Monster.init()
   G.playerx = rnd(MAXX - 2) + 1
   G.playery = rnd(MAXY - 2) + 1
   G.gtime = 0
   ns.Player.recalc()
end

-- C: fillroom(). Puts an object on a random free tile.
function Create.fillRoom(what, arg)
   local x, y = rnd(MAXX - 2) + 1, rnd(MAXY - 2) + 1
   while item[x][y] ~= 0 do
      x = x + rnd(3) - 2
      y = y + rnd(3) - 2
      if x > MAXX - 1 then x = 2 end
      if x < 2 then x = MAXX - 1 end
      if y > MAXY - 1 then y = 2 end
      if y < 2 then y = MAXY - 1 end
   end
   item[x][y] = what
   iarg[x][y] = arg
end

-- C: fillmroom(). Puts n objects of one kind into the level.
local function FillMRoom(n, what, arg)
   for _ = 1, n do
      Create.fillRoom(what, arg)
   end
end

-- C: froom(). A 1 in 151 style chance (n of them) of one object.
local function FRoom(n, what, arg)
   if rnd(151) < n then
      Create.fillRoom(what, arg)
   end
end

-- Hit points of a freshly made monster (C: monster[mon].hitpoints).
local function MonsterHP(id)
   return G.monster[id].hitpoints
end

-- C: eat(). Digs the maze out of solid wall with a recursive backtracker. The C works on
-- 0-based coordinates: the borders are x <= 2, x >= MAXX-3 there, one more here.
local function Eat(xx, yy)
   local dir = rnd(4)
   local try = 2
   while try > 0 do
      if dir == 1 then  -- west
         if xx > 3 and item[xx - 1][yy] == K.OWALL and item[xx - 2][yy] == K.OWALL then
            item[xx - 1][yy], item[xx - 2][yy] = 0, 0
            Eat(xx - 2, yy)
         end
      elseif dir == 2 then  -- east
         if xx < MAXX - 2 and item[xx + 1][yy] == K.OWALL and item[xx + 2][yy] == K.OWALL then
            item[xx + 1][yy], item[xx + 2][yy] = 0, 0
            Eat(xx + 2, yy)
         end
      elseif dir == 3 then  -- south (smaller y)
         if yy > 3 and item[xx][yy - 1] == K.OWALL and item[xx][yy - 2] == K.OWALL then
            item[xx][yy - 1], item[xx][yy - 2] = 0, 0
            Eat(xx, yy - 2)
         end
      else  -- north (larger y)
         if yy < MAXY - 2 and item[xx][yy + 1] == K.OWALL and item[xx][yy + 2] == K.OWALL then
            item[xx][yy + 1], item[xx][yy + 2] = 0, 0
            Eat(xx, yy + 2)
         end
      end
      dir = dir + 1
      if dir > 4 then
         dir = 1
         try = try - 1
      end
   end
end

Create.eat = Eat

-- C: cannedlevel(). Reads a level from the map data about half of the time (always on the
-- bottom levels). Returns true if it made the level.
local function CannedLevel(lev)
   if lev ~= DBOTTOM and lev ~= VBOTTOM then
      if rnd(100) < 50 then return false end
   end

   local map = ns.Maps[rund(20) + 1]
   for y = 1, MAXY do
      local row = map[y]
      for x = 1, MAXX do
         local it, arg, mit, marg = 0, 0, 0, 0
         local ch = row:sub(x, x)
         if ch == "#" then
            it = K.OWALL
         elseif ch == "D" then
            it = K.OCLOSEDDOOR
            arg = rnd(30)
         elseif ch == "~" then
            if lev == DBOTTOM then
               it = K.OLARNEYE
               mit = K.DEMONPRINCE
               marg = MonsterHP(mit)
            end
         elseif ch == "!" then
            if lev == VBOTTOM then
               it = K.OPOTION
               arg = K.PCUREDIANTH
               mit = K.LUCIFER
               marg = MonsterHP(mit)
            end
         elseif ch == "." then
            if lev > DBOTTOM - 5 then
               mit = ns.Monster.makeMonst(lev + 1)
               marg = MonsterHP(mit)
            end
         elseif ch == "-" then
            it, arg = ns.Item.newObject(lev + 1)
         end
         item[x][y] = it
         iarg[x][y] = arg
         mon[x][y] = mit
         hitp[x][y] = marg
         know[x][y] = G.wizard and 1 or 0
      end
   end
   return true
end

-- C: troom(). Makes a treasure room of any size with its upper left corner at (tx, ty), in
-- 0-based C coordinates. The room is filled with objects and monsters.
local function TRoom(lv, xsize, ysize, tx, ty, glyph)
   for j = ty - 1, ty + ysize do  -- clear out space for the room
      for i = tx - 1, tx + xsize do
         item[i + 1][j + 1] = 0
      end
   end
   for j = ty, ty + ysize - 1 do  -- now put in the walls
      for i = tx, tx + xsize - 1 do
         item[i + 1][j + 1] = K.OWALL
         mon[i + 1][j + 1] = 0
      end
   end
   for j = ty + 1, ty + ysize - 2 do  -- now clear out the interior
      for i = tx + 1, tx + xsize - 2 do
         item[i + 1][j + 1] = 0
      end
   end
   -- locate the door on the treasure room
   local i, j
   if rnd(2) == 1 then  -- on horizontal walls
      i = tx + rund(xsize)
      j = ty + (ysize - 1) * rund(2)
   else  -- on vertical walls
      i = tx + (xsize - 1) * rund(2)
      j = ty + rund(ysize)
   end
   item[i + 1][j + 1] = K.OCLOSEDDOOR
   iarg[i + 1][j + 1] = glyph

   -- createmonster() and something() work around the player, so the player is moved.
   local bupx, bupy = G.playerx, G.playery
   G.playery = ty + idiv(ysize, 2) + 1
   local hard = c[K.HARDGAME] >= 3
   G.playerx = tx + 1 + 1
   while G.playerx <= tx + xsize - 2 + 1 do
      local count = rnd(hard and 4 or 6)
      for _ = 0, count do
         ns.Item.something(G.playerx, G.playery, lv + 2)
         ns.Monster.createMonster(ns.Monster.makeMonst(hard and lv + 4 or lv + 2))
      end
      G.playerx = G.playerx + 2
   end
   G.playerx, G.playery = bupx, bupy
end

-- C: treasureroom(). Level 10's treasure room has the eye in it and demon lords; level V5
-- has the potion of cure dianthroritis and the demon prince.
local function TreasureRoom(lv)
   local tx = 1 + rnd(10)
   while tx < MAXX - 10 do
      if lv == DBOTTOM or lv == VBOTTOM or rnd(10) <= 2 then
         local xsize = rnd(6) + 3
         local ysize = rnd(3) + 3
         local ty = rnd(MAXY - 9) + 1  -- upper left corner of the room
         if lv == DBOTTOM or lv == VBOTTOM then
            tx = tx + rnd(MAXX - 24)
            TRoom(lv, xsize, ysize, tx, ty, rnd(3) + 6)
         else
            TRoom(lv, xsize, ysize, tx, ty, rnd(9))
         end
      end
      tx = tx + 10
   end
end

-- C: makemaze(). Only the walls and open spaces are made here; the town is an empty field.
function Create.makeMaze(lev)
   if lev > 0 and CannedLevel(lev) then return end

   local fill = lev == 0 and 0 or K.OWALL
   for y = 1, MAXY do
      for x = 1, MAXX do
         item[x][y] = fill
      end
   end
   if lev == 0 then return end

   Eat(2, 2)

   if lev == 1 then
      item[34][MAXY] = 0  -- exit from the dungeon
   end

   -- Now for the open spaces, not on the bottom levels. These use the 0-based C coordinates.
   if lev ~= DBOTTOM and lev ~= VBOTTOM then
      for _ = 1, rnd(3) + 3 do
         local my = rnd(11) + 2
         local myl = my - rnd(2)
         local myh = my + rnd(2)
         local mxl, mxh, z
         if lev <= DBOTTOM then  -- in the dungeon
            local mx = rnd(44) + 5
            mxl = mx - rnd(4)
            mxh = mx + rnd(12) + 3
            z = 0
         else  -- in the volcano
            local mx = rnd(60) + 3
            mxl = mx - rnd(2)
            mxh = mx + rnd(2)
            z = ns.Monster.makeMonst(lev)
         end
         for i = mxl, mxh - 1 do
            for j = myl, myh - 1 do
               item[i + 1][j + 1] = 0
               mon[i + 1][j + 1] = z
               if z ~= 0 then hitp[i + 1][j + 1] = MonsterHP(z) end
            end
         end
      end
      local my = rnd(MAXY - 2)  -- a corridor all the way across
      for x = 2, MAXX - 1 do
         item[x][my + 1] = 0
      end
   end

   -- no treasure rooms above level 5
   if lev > 4 then
      TreasureRoom(lev)
   end
end

-- C: makeobject(). The objects of a level; the town gets its buildings.
function Create.makeObject(j)
   local fillRoom = Create.fillRoom
   if j == 0 then
      fillRoom(K.OENTRANCE, 0)  -- entrance to the dungeon
      fillRoom(K.ODNDSTORE, 0)
      fillRoom(K.OSCHOOL, 0)    -- college of Larn
      fillRoom(K.OBANK, 0)      -- 1st national bank of Larn
      fillRoom(K.OVOLDOWN, 0)   -- volcano shaft to the temple
      fillRoom(K.OHOME, 0)      -- the player's home and family
      fillRoom(K.OTRADEPOST, 0)
      fillRoom(K.OLRS, 0)       -- Larn Revenue Service
      return
   end
   if j == DBOTTOM + 1 then  -- V1
      fillRoom(K.OVOLUP, 0)  -- volcano shaft up from the temple
   end

   -- The fixed stairs and the random elevators. Stairs down only on V1 and V2.
   if j > 0 and j ~= DBOTTOM and j < VBOTTOM - 2 then
      fillRoom(K.OSTAIRSDOWN, 0)
   end
   if j > 1 and j ~= DBOTTOM then
      fillRoom(K.OSTAIRSUP, 0)
   end

   -- > 3, not on V1 or V5 or 15
   if j > 3 and j ~= DBOTTOM + 1 and j ~= VBOTTOM and j ~= DBOTTOM then
      if c[K.ELVUP] == 0 and rnd(100) > 85 then
         fillRoom(K.OELEVATORUP, 0)
         c[K.ELVUP] = c[K.ELVUP] + 1
      end
   end

   -- < lev 10, or 15 or V5
   if j > 0 and (j <= DBOTTOM - 5 or j == DBOTTOM or j == VBOTTOM) then
      if c[K.ELVDOWN] == 0 and rnd(100) > 85 then
         fillRoom(K.OELEVATORDOWN, 0)
         c[K.ELVDOWN] = c[K.ELVDOWN] + 1
      end
   end

   -- The random objects in the maze.
   FillMRoom(rund(3), K.OBOOK, j)
   FillMRoom(rund(3), K.OCOOKIE, 0)
   FillMRoom(rund(3), K.OALTAR, 0)
   FillMRoom(rund(3), K.OSTATUE, 0)
   FillMRoom(rund(3), K.OFOUNTAIN, 0)
   FillMRoom(rund(2), K.OTHRONE, 0)
   FillMRoom(rund(2), K.OMIRROR, 0)

   -- Be sure to have pits and trapdoors on V3, V4 and V5, because there are no stairs there.
   if j >= VBOTTOM - 2 then
      fillRoom(K.OPIT, 0)
   end
   FillMRoom(rund(3), K.OPIT, 0)

   if j >= VBOTTOM - 2 then
      fillRoom(K.OIVTRAPDOOR, 0)
   end
   FillMRoom(rund(2), K.OIVTRAPDOOR, 0)
   FillMRoom(rund(2), K.OTRAPARROWIV, 0)
   FillMRoom(rnd(3) - 2, K.OIVTELETRAP, 0)
   FillMRoom(rnd(3) - 2, K.OIVDARTRAP, 0)

   if j == 1 then
      FillMRoom(1, K.OCHEST, j)
   else
      FillMRoom(rund(2), K.OCHEST, j)
   end

   if j <= DBOTTOM then
      FillMRoom(rund(2), K.ODIAMOND, rnd(10 * j + 1) + 10)
      FillMRoom(rund(2), K.ORUBY, rnd(6 * j + 1) + 6)
      FillMRoom(rund(2), K.OEMERALD, rnd(4 * j + 1) + 4)
      FillMRoom(rund(2), K.OSAPPHIRE, rnd(3 * j + 1) + 2)
   end

   -- The C re-rolls the limit on every pass of these loops.
   local i = 0
   while i < rnd(4) + 3 do
      fillRoom(K.OPOTION, ns.Item.newPotion())
      i = i + 1
   end
   i = 0
   while i < rnd(5) + 3 do
      fillRoom(K.OSCROLL, ns.Item.newScroll())
      i = i + 1
   end
   i = 0
   while i < rnd(12) + 11 do
      fillRoom(K.OGOLDPILE, 12 * rnd(j + 1) + (j * 8) + 10)
      i = i + 1
   end

   if j == 8 then
      fillRoom(K.OBANK2, 0)  -- branch office of the bank
   end

   if c[K.PAD] == 0 and j >= 4 and rnd(100) > 75 then
      fillRoom(K.OPAD, 0)  -- the goblin alchemist's pad (C: Dealer McDope)
      c[K.PAD] = c[K.PAD] + 1
   end

   FRoom(2, K.ORING, 0)
   FRoom(1, K.OSTUDLEATHER, 0)
   FRoom(3, K.OSPLINT, 0)
   FRoom(5, K.OSHIELD, rund(3))
   FRoom(2, K.OBATTLEAXE, rund(3))
   FRoom(5, K.OLONGSWORD, rund(3))
   FRoom(5, K.OFLAIL, rund(3))
   FRoom(7, K.OSPEAR, rnd(5))
   FRoom(4, K.OREGENRING, rund(3))
   FRoom(1, K.OPROTRING, rund(3))
   FRoom(2, K.OSTRRING, rund(5))
   FRoom(2, K.ORINGOFEXTRA, 0)

   -- At most one of the unique artifacts per level, each once per game.
   local unique = {
      { K.LAMP, K.OBRASSLAMP }, { K.WAND, K.OWWAND }, { K.DRAGSLAY, K.OORBOFDRAGON },
      { K.NEGATE, K.OSPIRITSCARAB }, { K.CUBEUNDEAD, K.OCUBEofUNDEAD }, { K.DEVICE, K.ONOTHEFT },
      { K.TALISMAN, K.OSPHTALISMAN }, { K.HAND, K.OHANDofFEAR }, { K.ORB, K.OORB },
      { K.ELVEN, K.OELVENCHAIN },
   }
   for _, entry in ipairs(unique) do
      local flag, object = entry[1], entry[2]
      if c[flag] == 0 and rnd(120) < 8 then
         fillRoom(object, 0)
         c[flag] = c[flag] + 1
         break
      end
   end

   if c[K.SLASH] == 0 and rnd(120) < 8 then  -- sword of slashing
      fillRoom(K.OSWORDofSLASHING, 0)
      c[K.SLASH] = c[K.SLASH] + 1
   end

   if c[K.BESSMANN] == 0 and rnd(120) < 8 then  -- Bessman's flailing hammer
      fillRoom(K.OHAMMER, 0)
      c[K.BESSMANN] = c[K.BESSMANN] + 1
   end

   if j >= 10 and j <= VBOTTOM and c[K.SLAY] == 0 then  -- Slayer
      if rnd(100) > 85 - (j - 10) then
         fillRoom(K.OSLAYER, 0)
         c[K.SLAY] = c[K.SLAY] + 1
      end
   end

   if c[K.VORPAL] == 0 and rnd(120) < 8 then  -- the Vorpal Blade
      fillRoom(K.OVORPAL, 0)
      c[K.VORPAL] = c[K.VORPAL] + 1
   end

   if c[K.STAFF] == 0 and j >= 8 and j <= 20 then  -- staff of power
      if rnd(100) > 85 - (j - 10) then
         fillRoom(K.OPSTAFF, 0)
         c[K.STAFF] = c[K.STAFF] + 1
      end
   end

   -- We don't get these if the difficulty level is >= 3.
   if c[K.HARDGAME] < 3 or rnd(4) == 3 then
      if j > 3 then
         FRoom(3, K.OSWORD, rund(6))  -- sunsword
         FRoom(5, K.O2SWORD, rnd(6))  -- a two handed sword
         FRoom(3, K.OBELT, rund(7))  -- belt of striking
         FRoom(3, K.OENERGYRING, rund(6))
         FRoom(4, K.OPLATE, rund(8))
      end
   end
end

-- C: sethp(). Creates the set of monsters for a level. Must be done when entering a new
-- level: with flag the old monsters are wiped out, otherwise they are left there.
function Create.setHP(flag)
   local level = G.level
   if flag then
      G.FillStealth(0)
   end
   if level == 0 then
      c[K.TELEFLAG] = 0
      return
   end

   local count
   if flag then
      count = rnd(12) + 2 + idiv(level, 2)
   else
      count = idiv(level, 2) + 1
   end
   for _ = 1, count do
      ns.Monster.fillMonst(ns.Monster.makeMonst(level))
   end

   -- Levels 11 to 15 get 1 to 5 demon lords, the volcano levels 1 to 5 demon princes.
   if level >= DBOTTOM - 4 and level <= DBOTTOM then
      local j = 1
      while j <= level - 10 do
         if ns.Monster.fillMonst(K.DEMONLORD + rund(7)) == -1 then
            j = j - 1
         end
         j = j + 1
      end
   end
   if level > DBOTTOM then
      local j = 1
      while j <= level - DBOTTOM do
         if ns.Monster.fillMonst(K.DEMONPRINCE) == -1 then
            j = j - 1
         end
         j = j + 1
      end
   end
   ns.Player.positionPlayer()
end

-- C: newcavelevel(). Must be called whenever the player changes level.
-- C: checkgen(). Wipes out the monsters that were genocided.
function Create.checkGen()
   local monster = G.monster
   for y = 1, MAXY do
      for x = 1, MAXX do
         if ns.Monster.hasFlag(monster[mon[x][y]].flags, K.FL_GENOCIDED) then
            mon[x][y] = 0  -- no more monster
         end
      end
   end
end

function Create.newCaveLevel(x)
   if G.Visited(G.level) then
      G.SaveLevel()
   end
   if G.gtime and G.gtime > 0 then ns.ui:Sound("level") end
   G.level = x
   if G.Visited(x) then
      G.GetLevel()
      Create.setHP(false)
      Create.checkGen()
      return
   end
   G.ClearLevel()
   Create.makeMaze(x)
   Create.makeObject(x)
   G.SetVisited(x)
   Create.setHP(true)
   if G.wizard or x == 0 then
      G.FillKnow(1)
   end
   Create.checkGen()  -- wipe out any genocided monsters
end
