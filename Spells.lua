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

-- The player's spells (C: cast(), speldamage() and the direction routines of monster.c).
-- Spells are numbered 1..39 here (C: 0..38), and the spell numbers of the C switch below
-- are shifted by one. The C asks for a direction with dirsub(), which cannot be cancelled;
-- here Escape cancels, and the spell point stays spent.
local Spells = {}
ns.Spells = Spells

local c, iven, ivenarg = G.c, G.iven, G.ivenarg
local item, iarg, know, mon, hitp = G.item, G.iarg, G.know, G.mon, G.hitp
local MAXX, MAXY, VBOTTOM = K.MAXX, K.MAXY, K.VBOTTOM
local SPNUM = K.SPNUM

local function Msg(fmt, ...)
   ns.ui:Message(fmt, ...)
end

-- C: isconfuse(). True if the player is confused.
local function IsConfused()
   if c[K.CONFUSE] ~= 0 then
      Msg(L["You can't aim your magic!"])
      return true
   end
   return false
end

-- C: nospell(). True (with a message) if the spell can't affect the monster.
local function NoSpell(spnum, monst)
   if spnum > SPNUM or spnum < 1 or monst > K.MAXMONST + 8 or monst < 1 then return false end
   local reaction = ns.Tables.spelweird[monst][spnum]
   if reaction == 0 then return false end
   Msg(ns.Tables.spelmes[reaction], G.monster[monst].name)
   return true
end
Spells.noSpell = NoSpell

-- C: loseint(). The price of the big spells.
local function LoseInt()
   c[K.INTELLIGENCE] = c[K.INTELLIGENCE] - 1
   if c[K.INTELLIGENCE] < 3 then c[K.INTELLIGENCE] = 3 end
end

-- C: dirsub(). Asks for a direction; returns the target tile and the direction, or nil.
local function DirSub()
   local dir = ns.ui:PickDirection(L["In what direction?"])
   if not dir then
      Msg(L["aborted."])
      return nil
   end
   local x, y = ns.vxy(G.playerx + ns.Display.DIROFFX[dir], G.playery + ns.Display.DIROFFY[dir])
   return x, y, dir
end

-- Remembers who was hit, so that the right message is shown (C: ifblind()).
local function IfBlind(x, y)
   ns.Monster.ifBlind(x, y)
end

-- C: direct(). Asks for a direction and hits the monster there. str takes the monster name
-- and then arg.
local function Direct(spnum, dam, str, arg)
   if spnum < 1 or spnum > SPNUM then return end
   if IsConfused() then return end
   local x, y = DirSub()
   if not x then return end
   local m = mon[x][y]
   if item[x][y] == K.OMIRROR then
      if spnum == 4 or spnum == 7 then  -- sleep and web
         if spnum == 4 then
            Msg(L["You fall asleep!"])
         else
            Msg(L["You get stuck in your own web!"])
         end
         for _ = 1, arg + 2 do
            ns.Game.parse2()
            ns.ui:Nap(1000)
            if G.dead then return end
         end
         return
      end
      G.lastnum = 278
      if str ~= "" then Msg(str, L["spell caster (that's you)"], arg) end
      ns.Player.losehp(dam)
      return
   end
   if m == 0 then
      Msg(L["There wasn't anything there!"])
      return
   end
   IfBlind(x, y)
   if NoSpell(spnum, m) then
      G.lasthx, G.lasthy = x, y
      return
   end
   if str ~= "" then Msg(str, G.lastmonst, arg) end
   ns.Monster.hitm(x, y, dam)
end
Spells.direct = Direct

-- C: godirect(). A missile that keeps on going in the direction until its power is spent.
-- cshow is the glyph drawn on the way, delay the milliseconds spent on each tile.
local function GoDirect(spnum, dam, str, delay, cshow)
   local monster = G.monster
   local ui = ns.ui
   if spnum < 1 or spnum > SPNUM then return end
   if IsConfused() then return end

   local tx, ty = DirSub()
   if not tx then return end
   local dx, dy = tx - G.playerx, ty - G.playery
   local x, y = G.playerx, G.playery

   while dam > 0 do
      x, y = x + dx, y + dy
      if x > MAXX or y > MAXY or x < 1 or y < 1 then break end  -- out of bounds
      -- if the energy hits the player
      if x == G.playerx and y == G.playery then
         Msg(L["You are hit by your own magic!"])
         G.lastnum = 278
         ns.Player.losehp(dam)
         return
      end
      -- if not blind show the effect
      if c[K.BLINDCOUNT] == 0 then
         ui:Missile(x, y, cshow, delay)
      end
      local m = mon[x][y]
      if m ~= 0 then  -- is there a monster there?
         IfBlind(x, y)
         -- cannot cast a missile spell at lucifer!!
         if m == K.LUCIFER or (m >= K.DEMONLORD and rnd(100) < 10) then
            dx, dy = -dx, -dy
            Msg(L["The %s returns your puny missile!"], monster[m].name)
         else
            if NoSpell(spnum, m) then
               G.lasthx, G.lasthy = x, y
               return
            end
            Msg(str, G.lastmonst)
            dam = dam - ns.Monster.hitm(x, y, dam)
            ui:Refresh("map")
            ui:Nap(1000)
            if G.dead then return end
            x, y = x - dx, y - dy
         end
      else
         local it = item[x][y]
         local broke = false  -- the tile changed, so it is drawn again
         if it == K.OWALL then
            Msg(str, L["wall"])
            -- can't break a wall below V2, nor the border of the level
            if dam >= 50 + c[K.HARDGAME] and G.level < VBOTTOM - 2
               and x < MAXX and y < MAXY and x > 1 and y > 1 then
               Msg(L["The wall crumbles."])
               item[x][y] = 0
               broke = true
            end
            dam = 0
         elseif it == K.OCLOSEDDOOR then
            Msg(str, L["door"])
            if dam >= 40 then
               Msg(L["The door is blasted apart."])
               item[x][y] = 0
               broke = true
            end
            dam = 0
         elseif it == K.OSTATUE then
            Msg(str, L["statue"])
            if dam > 44 and not (c[K.HARDGAME] > 3 and rnd(60) < 30) then
               Msg(L["The statue crumbles."])
               item[x][y] = K.OBOOK
               iarg[x][y] = G.level
               broke = true
            end
            dam = 0
         elseif it == K.OTHRONE then
            Msg(str, L["throne"])
            if dam > 33 then
               mon[x][y] = K.GNOMEKING
               hitp[x][y] = monster[K.GNOMEKING].hitpoints
               item[x][y] = K.OTHRONE2
               broke = true
            end
            dam = 0
         elseif it == K.OMIRROR then
            dx, dy = -dx, -dy
         end
         if broke then
            know[x][y] = 0
            ui:Refresh("map")
         end
      end
      dam = dam - (3 + idiv(c[K.HARDGAME], 2))
   end
end
Spells.godirect = GoDirect

-- C: omnidirect(). Hits every monster next to the player.
local function OmniDirect(spnum, dam, str)
   if spnum < 1 or spnum > SPNUM then return end
   for x = G.playerx - 1, G.playerx + 1 do
      for y = G.playery - 1, G.playery + 1 do
         if x >= 1 and x <= MAXX and y >= 1 and y <= MAXY then
            local m = mon[x][y]
            if m ~= 0 then
               if not NoSpell(spnum, m) then
                  IfBlind(x, y)
                  Msg(str, G.lastmonst)
                  ns.Monster.hitm(x, y, dam)
                  ns.ui:Nap(800)
                  if G.dead then return end
               else
                  G.lasthx, G.lasthy = x, y
               end
            end
         end
      end
   end
end

-- C: tdirect(). Teleports a monster away.
local function TDirect(spnum)
   if spnum < 1 or spnum > SPNUM then return end
   if IsConfused() then return end
   local x, y = DirSub()
   if not x then return end
   local m = mon[x][y]
   if m == 0 then
      Msg(L["There wasn't anything there!"])
      return
   end
   IfBlind(x, y)
   if NoSpell(spnum, m) then
      G.lasthx, G.lasthy = x, y
      return
   end
   ns.Monster.teleportMonst(x, y, m)
   ns.ui:Refresh("map")
end

-- C: makewall().
local function MakeWall(spnum)
   if spnum < 1 or spnum > SPNUM then return end
   if IsConfused() then return end
   local x, y = DirSub()
   if not x then return end
   if item[x][y] == K.OWALL then  -- can't make anything on walls
      Msg(L["There's a wall there already!"])
   elseif item[x][y] ~= 0 then
      Msg(L["There's something there already!"])
   elseif mon[x][y] ~= 0 then
      Msg(L["There's a monster there!"])
   elseif G.level == 1 and x == 34 and y == MAXY then
      Msg(L["You can't make a wall there!"])
   else
      item[x][y] = K.OWALL
      know[x][y] = 1
      ns.ui:Refresh("map")
   end
end

-- C: dirpoly(). Polymorphs a monster.
local function DirPoly(spnum)
   if spnum < 1 or spnum > SPNUM then return end
   if IsConfused() then return end  -- if he is confused, he can't aim his magic
   local x, y = DirSub()
   if not x then return end
   if mon[x][y] == 0 then
      Msg(L["There wasn't anything there!"])
      return
   end
   IfBlind(x, y)
   if NoSpell(spnum, mon[x][y]) then
      G.lasthx, G.lasthy = x, y
      return
   end
   local m
   repeat
      m = rnd(K.MAXMONST + 7)
   until not ns.Monster.hasFlag(G.monster[m].flags, K.FL_GENOCIDED)
   mon[x][y] = m
   hitp[x][y] = G.monster[m].hitpoints
   ns.ui:Refresh("map")  -- show the new monster
end

-- C: genmonst(). Wipes a kind of monster out of the game.
local function GenMonst()
   local ui = ns.ui
   ui:Message(L["Genocide which monster?"])
   local key
   repeat
      key = ui:GetKey()
   until key == " " or (#key == 1 and key:match("%a"))
   local glyphs = ns.Tables.monstglyphs
   for j = 0, K.MAXMONST - 1 do  -- search for the monster type
      if glyphs:sub(j + 1, j + 1) == key then  -- have we found it?
         local monster = G.monster[j]
         if not ns.Monster.hasFlag(monster.flags, K.FL_GENOCIDED) or G.wizard then
            if not ns.Monster.hasFlag(monster.flags, K.FL_GENOCIDED) then
               monster.flags = monster.flags + K.FL_GENOCIDED  -- genocided from the game
            end
            Msg(L["There will be no more %ss."], monster.name)
            -- now wipe out the monsters on this level
            ns.Create.newCaveLevel(G.level)
            ui:Refresh("all")
            return
         end
      end
   end
   Msg(L["You sense failure!"])
end

-- C: the vaporize rock spell.
local function Vaporize()
   local xh, yh = math.min(G.playerx + 1, MAXX - 1), math.min(G.playery + 1, MAXY - 1)
   for i = math.max(G.playerx - 1, 2), xh do
      for j = math.max(G.playery - 1, 2), yh do
         local it = item[i][j]
         if it == K.OWALL then
            -- can't vaporize below V2
            if G.level < VBOTTOM - 2 then
               item[i][j], know[i][j] = 0, 0
            end
         elseif it == K.OSTATUE then
            if not (c[K.HARDGAME] > 3 and rnd(60) < 30) then
               item[i][j] = K.OBOOK
               iarg[i][j] = G.level
               know[i][j] = 0
            end
         elseif it == K.OTHRONE then
            mon[i][j] = K.GNOMEKING
            know[i][j] = 0
            item[i][j] = K.OTHRONE2
            hitp[i][j] = G.monster[K.GNOMEKING].hitpoints
         elseif it == K.OALTAR then
            mon[i][j] = K.DEMONPRINCE
            know[i][j] = 0
            hitp[i][j] = G.monster[K.DEMONPRINCE].hitpoints
            for _ = 1, 4 do ns.Monster.createMonster(K.DEMONPRINCE) end
         end
         local m = mon[i][j]
         if m == K.XORN or m == K.TROLL then  -- these take damage from vaporize rock
            IfBlind(i, j)
            ns.Monster.hitm(i, j, 200)
         end
      end
   end
   ns.ui:Refresh("map")
end

-- C: the alter reality spell. Rebuilds the level, keeping its objects and monsters.
local function AlterReality()
   local saved = {}  -- {type 0 object / 1 monster, id, arg}
   for j = 1, MAXY do
      for i = 1, MAXX do
         local xl = item[i][j]
         if xl ~= 0 and xl ~= K.OWALL and xl ~= K.OANNIHILATION then
            saved[#saved + 1] = { 0, xl, iarg[i][j] }
         end
         if mon[i][j] ~= 0 then
            saved[#saved + 1] = { 1, mon[i][j], hitp[i][j] }
         end
         item[i][j] = K.OWALL
         mon[i][j] = 0
         know[i][j] = G.wizard and 1 or 0
      end
   end
   ns.Create.eat(2, 2)
   if G.level == 1 then item[34][MAXY] = 0 end
   local row = rnd(MAXY - 2)  -- C: rnd(MAXY - 2) on 0-based rows, so row + 1 here
   for i = 2, MAXX - 1 do
      item[i][row + 1] = 0
   end
   -- put the objects back in the level
   for index = #saved, 1, -1 do
      local entry = saved[index]
      local trys, i, j = 100, 2, 2
      if entry[1] == 0 then
         while true do
            trys = trys - 1
            if not (trys > 0 and item[i][j] ~= 0) then break end
            i, j = rnd(MAXX - 1) + 1, rnd(MAXY - 1) + 1
         end
         if trys ~= 0 then
            item[i][j] = entry[2]
            iarg[i][j] = entry[3]
         end
      else  -- put the monsters back in
         while true do
            trys = trys - 1
            if not (trys > 0 and (item[i][j] == K.OWALL or mon[i][j] ~= 0)) then break end
            i, j = rnd(MAXX - 1) + 1, rnd(MAXY - 1) + 1
         end
         if trys ~= 0 then
            mon[i][j] = entry[2]
            hitp[i][j] = entry[3]
         end
      end
   end
   LoseInt()
   if not G.wizard then G.spelknow[38] = 0 end
   ns.Player.positionPlayer()
   ns.ui:Refresh("all")
end

-- C: speldamage(). Performs the spell the player cast; x is the spell number.
function Spells.speldamage(x)
   local ui = ns.ui
   if x > SPNUM then return end  -- no such spell

   if c[K.TIMESTOP] ~= 0 then  -- not if time stopped
      Msg(L["It didn't seem to work."])
      return
   end
   if rnd(23) == 7 or rnd(18) > c[K.INTELLIGENCE] then
      Msg(L["It didn't work!"])
      return
   end
   local clev = c[K.LEVEL]
   if clev * 3 + 2 < x - 1 then
      Msg(L["Nothing happens. You seem inexperienced."])
      return
   end

   -- ----- LEVEL 1 SPELLS -----
   if x == 1 then  -- protection
      if c[K.PROTECTIONTIME] == 0 then c[K.MOREDEFENSES] = c[K.MOREDEFENSES] + 2 end  -- protection field +2
      c[K.PROTECTIONTIME] = c[K.PROTECTIONTIME] + 250

   elseif x == 2 then  -- magic missile
      local i = rnd((clev + 1) * 2) + clev + 3
      GoDirect(x, i, clev >= 2 and L["Your missiles hit the %s."] or L["Your missile hit the %s."], 100, "+")

   elseif x == 3 then  -- dexterity
      if c[K.DEXCOUNT] == 0 then c[K.DEXTERITY] = c[K.DEXTERITY] + 3 end
      c[K.DEXCOUNT] = c[K.DEXCOUNT] + 400

   elseif x == 4 then  -- sleep
      local i = rnd(3) + 1
      Direct(x, ns.Monster.fullHit(i), L["While the %s slept, you smashed it %d times."], i)

   elseif x == 5 then  -- charm monster
      c[K.CHARMCOUNT] = c[K.CHARMCOUNT] + c[K.CHARISMA] * 2

   elseif x == 6 then  -- sonic spear
      GoDirect(x, rnd(10) + 15 + clev, L["The sound damages the %s."], 70, "@")

   -- ----- LEVEL 2 SPELLS -----
   elseif x == 7 then  -- web
      local i = rnd(3) + 2
      Direct(x, ns.Monster.fullHit(i), L["While the %s is entangled, you hit it %d times."], i)

   elseif x == 8 then  -- strength
      if c[K.STRCOUNT] == 0 then c[K.STREXTRA] = c[K.STREXTRA] + 3 end
      c[K.STRCOUNT] = c[K.STRCOUNT] + 150 + rnd(100)

   elseif x == 9 then  -- enlightenment
      local xl, yl = ns.vxy(G.playerx - 15, G.playery - 5)
      local xh, yh = ns.vxy(G.playerx + 16, G.playery + 6)
      for i = yl, yh do
         for j = xl, xh do
            know[j][i] = 1
         end
      end
      ui:Refresh("map")

   elseif x == 10 then  -- healing
      ns.Player.raiseHP(20 + clev * 2)

   elseif x == 11 then  -- cure blindness
      c[K.BLINDCOUNT] = 0

   elseif x == 12 then  -- create monster
      ns.Monster.createMonster(ns.Monster.makeMonst(G.level + 1) + 8)

   elseif x == 13 then  -- phantasmal forces
      if rnd(11) + 7 <= c[K.WISDOM] then
         Direct(x, rnd(20) + 20 + clev, L["The %s believed!"], 0)
      else
         Msg(L["It didn't believe the illusions!"])
      end

   elseif x == 14 then  -- invisibility; the amulet of invisibility adds more time
      local j = 0
      for i = 1, K.IVENSIZE do
         if iven[i] == K.OAMULET then j = j + 1 + ivenarg[i] end
      end
      c[K.INVISIBILITY] = c[K.INVISIBILITY] + j * 128 + 12

   -- ----- LEVEL 3 SPELLS -----
   elseif x == 15 then  -- fireball
      GoDirect(x, rnd(25 + clev) + 25 + clev, L["The fireball hits the %s."], 40, "*")

   elseif x == 16 then  -- cold
      GoDirect(x, rnd(25) + 20 + clev, L["The cone of cold strikes the %s."], 60, "O")

   elseif x == 17 then  -- polymorph
      DirPoly(x)

   elseif x == 18 then  -- cancellation
      c[K.CANCELLATION] = c[K.CANCELLATION] + 5 + clev

   elseif x == 19 then  -- haste self
      c[K.HASTESELF] = c[K.HASTESELF] + 7 + clev

   elseif x == 20 then  -- cloud kill
      OmniDirect(x, 30 + rnd(10), L["The %s gasps for air!"])

   elseif x == 21 then  -- vaporize rock
      Vaporize()

   -- ----- LEVEL 4 SPELLS -----
   elseif x == 22 then  -- dehydration
      Direct(x, 100 + clev, L["The %s shrivels up."], 0)

   elseif x == 23 then  -- lightning
      GoDirect(x, rnd(25) + 20 + clev * 2, L["A lightning bolt hits the %s."], 1, "~")

   elseif x == 24 then  -- drain life
      local i = math.min(c[K.HP] - 1, idiv(c[K.HPMAX], 2))
      Direct(x, i + i, "", 0)
      c[K.HP] = c[K.HP] - i

   elseif x == 25 then  -- globe of invulnerability
      if c[K.GLOBE] == 0 then c[K.MOREDEFENSES] = c[K.MOREDEFENSES] + 10 end
      c[K.GLOBE] = c[K.GLOBE] + 200
      LoseInt()

   elseif x == 26 then  -- flood
      OmniDirect(x, 32 + clev, L["The %s struggles for air in your flood!"])

   elseif x == 27 then  -- finger of death
      if rnd(151) == 63 then
         Msg(L["Your heart stopped!"])
         ui:Nap(4000)
         ns.Player.died(270)
         return
      end
      if c[K.WISDOM] > rnd(10) + 10 then
         Direct(x, 2000, L["The %s's heart stopped."], 0)
      else
         Msg(L["It didn't work."])
      end

   -- ----- LEVEL 5 SPELLS -----
   elseif x == 28 then  -- scare monster
      c[K.SCAREMONST] = c[K.SCAREMONST] + rnd(10) + clev
      -- if the player has the hand of fear it lasts longer
      for i = 1, K.IVENSIZE do
         if iven[i] == K.OHANDofFEAR then
            c[K.SCAREMONST] = c[K.SCAREMONST] * 3
            break
         end
      end

   elseif x == 29 then  -- hold monster
      c[K.HOLDMONST] = c[K.HOLDMONST] + rnd(10) + clev

   elseif x == 30 then  -- time stop
      c[K.TIMESTOP] = c[K.TIMESTOP] + rnd(20) + clev * 2

   elseif x == 31 then  -- teleport away
      TDirect(x)

   elseif x == 32 then  -- magic fire
      OmniDirect(x, 35 + rnd(10) + clev, L["The %s cringes from the flame."])

   -- ----- LEVEL 6 SPELLS -----
   elseif x == 33 then  -- make wall
      MakeWall(x)

   elseif x == 34 then  -- sphere of annihilation
      if rnd(23) == 5 and not G.wizard then
         Msg(L["You have been enveloped by the zone of nothingness!"])
         ui:Nap(4000)
         ns.Player.died(258)
         return
      end
      LoseInt()
      local xl, yl, dir = DirSub()  -- get the direction of the sphere
      if xl then
         ns.Sphere.newsphere(xl, yl, dir, rnd(20) + 11)  -- make a sphere
      end

   elseif x == 35 then  -- genocide
      GenMonst()
      G.spelknow[35] = 0
      LoseInt()

   elseif x == 36 then  -- summon demon
      if rnd(100) > 30 then
         Direct(x - 1, 150, L["The demon strikes at the %s."], 0)
         return
      end
      if rnd(100) > 15 then
         Msg(L["Nothing seems to have happened."])
         return
      end
      Msg(L["The demon turned on you and then vanished!"])
      G.lastnum = 277
      ns.Player.losehp(rnd(40) + 30)  -- must say killed by a demon

   elseif x == 37 then  -- walk through walls
      c[K.WTW] = c[K.WTW] + rnd(10) + 5

   elseif x == 38 then  -- alter reality
      AlterReality()

   elseif x == 39 then  -- permanence
      ns.Magic.adjustTime(-99999)
      G.spelknow[39] = 0  -- forget
      LoseInt()
   end
end

-- C: cast(). Asks for the three letter code of a spell and casts it.
function Spells.cast()
   local ui = ns.ui
   if c[K.SPELLS] <= 0 then
      Msg(L["You don't have any spells!"])
      return
   end
   local T = ns.Tables
   local found
   repeat
      local code = ui:PickSpell()
      if not code then
         Msg(L["aborted."])
         return
      end
      c[K.SPELLS] = c[K.SPELLS] - 1
      -- (the C searches in order)
      for i = 1, SPNUM do
         if T.spelcode[i] == code and G.spelknow[i] ~= 0 then
            Msg(L["Casting %s (%s)."], code, T.spelname[i])
            Spells.speldamage(i)
            found = true
            break
         end
      end
      ui:Refresh("all")
   until found or G.dead
end
