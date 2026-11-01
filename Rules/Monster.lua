--[[
**********************************************************************
WoWLarn - Monsters: creation, combat and special attacks (monster.c).
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
local rnd, rund, idiv = ns.rnd, ns.rund, ns.idiv

local Monster = {}
ns.Monster = Monster


local c, iven, ivenarg = G.c, G.iven, G.ivenarg
local item, iarg, know, mon, hitp, stealth = G.item, G.iarg, G.know, G.mon, G.hitp, G.stealth

local MAXX, MAXY = K.MAXX, K.MAXY
local DEMONLORD, DEMONPRINCE, LUCIFER = K.DEMONLORD, K.DEMONPRINCE, K.LUCIFER
local MAXMONST, DBOTTOM = K.MAXMONST, K.DBOTTOM
local FL_GENOCIDED, FL_HEAD, FL_NOBEHEAD = K.FL_GENOCIDED, K.FL_HEAD, K.FL_NOBEHEAD

-- Flags are small powers of two; Lua 5.1 has no bit operators.
local function HasFlag(flags, bit)
   return flags % (bit * 2) >= bit
end

Monster.hasFlag = HasFlag

local function Trunc(x)
   return x >= 0 and math.floor(x) or -math.floor(-x)
end

local function Msg(fmt, ...)
   ns.ui:Message(fmt, ...)
end

-- The monster table of this game (C: monster[]). It is a copy because genocide changes it.
function Monster.init()
   local copy = {
      [0] = { name = "", level = 0, armorclass = 0, damage = 0, attack = 0, intelligence = 0,
         gold = 0, hitpoints = 0, experience = 0, flags = 0 },
   }
   for id, data in pairs(ns.MonsterData) do
      local row = {}
      for key, value in pairs(data) do row[key] = value end
      copy[id] = row
   end
   G.monster = copy

   -- C: sethard(). Scales the monsters by the difficulty; nothing changes at 0.
   local k = c[K.HARDGAME]
   if k ~= 0 then
      for id = 0, MAXMONST + 8 do
         local row = copy[id]
         row.hitpoints = math.min(idiv((6 + k) * row.hitpoints + 1, 6), 32767)
         row.damage = math.min(idiv((6 + k) * row.damage + 1, 5), 127)
         row.gold = math.min(idiv(10 * row.gold, 10 + k), 32767)
         row.armorclass = math.max(row.armorclass - k, -127)
         row.experience = math.max(idiv(7 * row.experience, 7 + k) + 1, 1)
      end
   end
end

-- C: makemonst(lev). A random monster id for the given cave level.
function Monster.makeMonst(lev)
   local monster, ml = G.monster, ns.Tables.monstlevel
   if lev < 1 then lev = 1 end
   if lev > 12 then lev = 12 end

   local tmp = K.WATERLORD
   if lev < 5 then
      while tmp == K.WATERLORD do
         local x = ml[lev]
         tmp = rnd(x ~= 0 and x or 1)
      end
   else
      while tmp == K.WATERLORD do
         local x = ml[lev] - ml[lev - 3]
         tmp = rnd(x ~= 0 and x or 1) + ml[lev - 3]
      end
   end

   while HasFlag(monster[tmp].flags, FL_GENOCIDED) and tmp < MAXMONST do
      tmp = tmp + 1  -- genocided?
   end

   if G.level <= DBOTTOM and rnd(100) < 10 and not Monster.lemmingsEnough() then
      tmp = K.LEMMING
   end
   return tmp
end

-- C: createmonster(). Puts a monster on a free tile next to the player.
function Monster.createMonster(id)
   local monster = G.monster
   if id < 1 or id > MAXMONST + 8 then
      Msg(L["can't createmonst(%d)"], id)
      return
   end
   while HasFlag(monster[id].flags, FL_GENOCIDED) and id < MAXMONST do
      id = id + 1
   end
   local DIROFFX, DIROFFY = ns.Display.DIROFFX, ns.Display.DIROFFY
   local k = rnd(8)  -- choose a direction, then try all
   for _ = 1, 8 do
      if k > 8 then k = 1 end
      local x, y = G.playerx + DIROFFX[k], G.playery + DIROFFY[k]
      k = k + 1
      if ns.Item.cgood(x, y, false, true) then
         mon[x][y] = id
         hitp[x][y] = monster[id].hitpoints
         stealth[x][y], know[x][y] = 0, 0
         if id == K.ROTHE or id == K.POLTERGEIST or id == K.VAMPIRE then
            stealth[x][y] = 1
         end
         return
      end
   end
end

-- C: fillmonst(). Puts a monster on a random free tile. Returns 0, or -1 if it failed.
function Monster.fillMonst(what)
   for _ = 1, 10 do  -- max # of creation attempts
      local x, y = rnd(MAXX - 2) + 1, rnd(MAXY - 2) + 1
      if item[x][y] == 0 and mon[x][y] == 0 and (G.playerx ~= x or G.playery ~= y) then
         mon[x][y] = what
         know[x][y] = 0
         hitp[x][y] = G.monster[what].hitpoints
         return 0
      end
   end
   return -1
end

-- C: the rmst counter in main(): fillmonst(makemonst(level)).
function Monster.spawnRandom()
   Monster.fillMonst(Monster.makeMonst(G.level))
end

-- C: randmonst(). Called after every step of a run.
function Monster.randMonst()
   if c[K.TIMESTOP] ~= 0 then return end
   G.rmst = G.rmst - 1
   if G.rmst <= 0 then
      G.rmst = 120 - G.level * 4
      Monster.fillMonst(Monster.makeMonst(G.level))
   end
end

-- C: ifblind(). Sets the name used in the messages ("monster" if blind).
local function IfBlind(x, y)
   local name
   if c[K.BLINDCOUNT] ~= 0 then
      G.lastnum = 279
      name = L["monster"]
   else
      G.lastnum = mon[x][y]
      name = G.monster[G.lastnum].name
   end
   G.lastmonst = name
end

Monster.ifBlind = IfBlind

-- C: fullhit(). Damage against a monster of a number of full hits.
local function FullHit(xx)
   if xx < 0 or xx > 20 then return 0 end
   if c[K.LANCEDEATH] ~= 0 then return 10000 end
   local i = xx * (idiv(c[K.WCLASS], 2) + c[K.STRENGTH] + c[K.STREXTRA] - c[K.HARDGAME] - 12 + c[K.MOREDAM])
   return i >= 1 and i or xx
end
Monster.fullHit = FullHit

-- C: dropsomething(). Some monsters leave an object behind.
local DROPS = {
   [K.ORC] = true, [K.NYMPH] = true, [K.ELF] = true, [K.TROGLODYTE] = true, [K.TROLL] = true,
   [K.ROTHE] = true, [K.VIOLETFUNGI] = true, [K.PLATINUMDRAGON] = true, [K.GNOMEKING] = true,
   [K.REDDRAGON] = true,
}

local function DropSomething(x, y, monst)
   if DROPS[monst] then
      ns.Item.something(x, y, G.level)
   elseif monst == K.LEPRECHAUN then
      if rnd(101) >= 75 then ns.Item.createGem() end
      if rnd(5) == 1 then DropSomething(x, y, K.LEPRECHAUN) end
   end
end

-- FIX: not in the C. Lemmings multiply when hit, when they move and when monsters are made,
-- which fills a level with them.  There are never more than MAX_LEMMINGS on a level.
local MAX_LEMMINGS = 12
function Monster.lemmingsEnough()
   local count = 0
   for x = 1, K.MAXX do
      local column = mon[x]
      for y = 1, K.MAXY do
         if column[y] == K.LEMMING then
            count = count + 1
            if count >= MAX_LEMMINGS then return true end
         end
      end
   end
   return false
end

-- C: hitm(). Damages the monster at (x, y); returns the hit points it absorbed. The damage
-- done is reported with hitmsg (a format of the monster name and the damage) if given.
function Monster.hitm(x, y, amt, hitmsg)
   local monster = G.monster
   local monst = mon[x][y]
   local amt2 = amt  -- save the initial damage so we can return it

   if c[K.HALFDAM] ~= 0 then  -- half damage curse
      amt = math.floor(amt / 2)
   end
   if amt <= 0 then
      amt, amt2 = 1, 1
   end

   G.lasthx, G.lasthy = x, y
   stealth[x][y] = 1  -- hitting a monster breaks the stealth condition
   c[K.HOLDMONST] = 0  -- ... and the hold monster spell

   if c[K.SLAYING] ~= 0 then  -- a dragon and orb(s) of dragon slaying
      if monst == K.WHITEDRAGON or monst == K.REDDRAGON or monst == K.GREENDRAGON
         or monst == K.BRONZEDRAGON or monst == K.PLATINUMDRAGON or monst == K.SILVERDRAGON then
         amt = amt * 3
         ns.ItemInfo.discover(K.OORBOFDRAGON, G.lastmonst)
      end
   end

   local wielded = c[K.WIELD] > 0 and iven[c[K.WIELD]] or 0
   -- Deal with Vorpy.
   if wielded == K.OVORPAL and rnd(20) == 1 and HasFlag(monster[monst].flags, FL_HEAD)
      and not HasFlag(monster[monst].flags, FL_NOBEHEAD) then
      Msg(L["The Vorpal Blade beheads the %s!"], G.lastmonst)
      amt = hitp[x][y]
      ns.ItemInfo.discover(K.OVORPAL)
   end

   -- invincible monster fix
   if hitp[x][y] > monster[monst].hitpoints then
      hitp[x][y] = monster[monst].hitpoints
   end

   if monst >= DEMONLORD then
      if c[K.LANCEDEATH] ~= 0 then amt = 300 end
      if wielded == K.OSLAYER then
         amt = 10000
         ns.ItemInfo.discover(K.OSLAYER, G.lastmonst)
      end
   end

   local hpoints = hitp[x][y]
   Msg(hitmsg or L["The %s takes %d damage."], G.lastmonst, amt)
   if hpoints <= amt then
      ns.ui:Animate("die", x, y, monst)
      Msg(L["The %s died!"], G.lastmonst)
      Msg(L["You gained %d exp."], monster[monst].experience)
      ns.Bestiary.kill(monst)
      ns.Player.raiseExperience(monster[monst].experience)
      mon[x][y], know[x][y] = 0, 0  -- C: disappear(x, y)

      local key = x * 100 + y
      local loot = G.loot[key]
      if loot and #loot > 0 then
         for _, entry in ipairs(loot) do
            ns.Item.createItem(x, y, entry[1], entry[2])
         end
         G.loot[key] = nil
         local gold = monster[monst].gold
         if gold > 0 then ns.Item.dropGold(rnd(gold) + gold) end
      else
         local gold = monster[monst].gold
         if gold > 0 then ns.Item.dropGold(rnd(gold) + gold) end
         DropSomething(x, y, monst)
      end
      ns.Display.showcell(G.playerx, G.playery)
      ns.ui:Refresh("all")
      hitp[x][y] = 0
      return hpoints
   end
   hitp[x][y] = hpoints - amt
   ns.ui:Animate("wound", x, y)
   return amt2
end

-- Weapons that are dulled by the rust monster, the disenchantress and the cube.
local DULLABLE = {
   [K.OSLAYER] = true, [K.ODAGGER] = true, [K.OSPEAR] = true, [K.OFLAIL] = true, [K.OBATTLEAXE] = true,
   [K.OLONGSWORD] = true, [K.O2SWORD] = true, [K.OLANCE] = true, [K.OHAMMER] = true,
   [K.OVORPAL] = true, [K.OBELT] = true,
}

-- C: hitmonster(). The player attacks the monster at (x, y).
function Monster.hitmonster(x, y)
   if c[K.TIMESTOP] ~= 0 then return end  -- not if time stopped
   local monst = mon[x][y]
   if monst == 0 then return end

   G.hit3flag = true
   IfBlind(x, y)
   ns.ui:Animate("hit", x, y)

   local tmp = G.monster[monst].armorclass + c[K.LEVEL] + c[K.DEXTERITY]
      + idiv(c[K.WCLASS], 4) - 12 - c[K.HARDGAME]

   ns.Bestiary.swing(monst)
   local flag, damag = false, 0
   -- need at least a random chance to hit
   if rnd(20) < tmp or rnd(71) < 5 then
      flag = true
      damag = FullHit(1)
      if damag < 9999 then
         damag = rnd(damag) + 1
      end
   else
      Msg(L["You missed the %s."], G.lastmonst)
   end

   -- If the monster was hit, deal with weapon dulling.
   local wield = c[K.WIELD]
   if flag and (monst == K.RUSTMONSTER or monst == K.DISENCHANTRESS or monst == K.CUBE) and wield > 0 then
      if (ivenarg[wield] > -10 and DULLABLE[iven[wield]]) or ivenarg[wield] > 0 then
         Msg(L["Your weapon is dulled by the %s."], G.lastmonst)
         ns.Bestiary.special(monst, ns.Bestiary.DULLS)
         ivenarg[wield] = ivenarg[wield] - 1
         ns.Player.recalc()
      elseif ivenarg[wield] > -10 then  -- (already at +0, and not a weapon that dulls any further)
         if iven[wield] == K.OSWORDofSLASHING then ns.ItemInfo.notice(K.OSWORDofSLASHING, G.lastmonst) end
      elseif ivenarg[wield] <= -10 then
         Msg(L["Your weapon disintegrates!"])
         ns.Bestiary.special(monst, ns.Bestiary.DULLS)
         ns.Player.adjustCValues(iven[wield], ivenarg[wield])  -- FIX: not in the C. What it did to the stats goes with it.
         iven[wield], ivenarg[wield] = 0, 0
         c[K.WIELD] = 0
         ns.Player.recalc()
         flag = false  -- didn't hit after all
      end
   end

   if flag then
      Monster.hitm(x, y, damag, L["You hit the %s for %d damage."])
      if c[K.LANCEDEATH] ~= 0 then ns.ItemInfo.discover(K.OLANCE) end
      if monst >= DEMONLORD and c[K.LANCEDEATH] ~= 0 and hitp[x][y] ~= 0 then
         Msg(L["Your lance of death tickles the %s!"], G.lastmonst)
      end
   end
   if monst == K.METAMORPH and hitp[x][y] < 25 and hitp[x][y] > 0 then
      mon[x][y] = K.BRONZEDRAGON + rund(9)
      ns.Bestiary.special(monst, ns.Bestiary.METAMORPHS)
   end
   if mon[x][y] == K.LEMMING and rnd(100) <= 40 and not Monster.lemmingsEnough() then
      Monster.createMonster(K.LEMMING)
      ns.Bestiary.special(K.LEMMING, ns.Bestiary.MULTIPLIES)
   end
   ns.ui:Refresh("all")
end

-- C: checkloss().
local function CheckLoss(x)
   if x > 0 then
      ns.Player.losehp(x)
   end
end

-- Armor that the rust monster eats: { item, lowest enchantment }.
local RUSTARM = {
   { K.OSTUDLEATHER, -2 }, { K.ORING, -4 }, { K.OCHAIN, -5 },
   { K.OSPLINT, -6 }, { K.OPLATE, -8 }, { K.OPLATEARMOR, -9 },
}

-- The special attacks picked by the spirit naga.
local SPSEL = { 1, 2, 3, 5, 6, 8, 9, 11, 13, 14 }

-- C: spattack(). Special attack number x by the monster at (xx, yy). Returns true if the
-- caller must redraw that tile and stop (the monster stole something).
function Monster.spattack(x, xx, yy)
   local monster, ui, Player = G.monster, ns.ui, ns.Player
   local monst = mon[xx][yy]

   -- cancellation only works 5% of the time for the demon prince and god
   if c[K.CANCELLATION] ~= 0 then
      if monst >= DEMONPRINCE then
         if rnd(100) >= 95 then return false end
      else
         return false
      end
   end

   -- the staff of power cancels demon lords, wraiths and vampires 75% of the time;
   -- Lucifer is unaffected
   if monst ~= LUCIFER then
      if monst >= DEMONLORD or monst == K.WRAITH or monst == K.VAMPIRE then
         for i = 1, K.IVENSIZE do
            if iven[i] == K.OPSTAFF and rnd(100) < 75 then
               ns.ItemInfo.notice(K.OPSTAFF, G.lastmonst)
               return false
            end
         end
      end
   end
   -- with the cube of undead control, wraiths and vampires do nothing
   if monst == K.WRAITH or monst == K.VAMPIRE then
      if c[K.CUBEofUNDEAD] ~= 0 or c[K.UNDEADPRO] ~= 0 then
         if c[K.CUBEofUNDEAD] ~= 0 then ns.ItemInfo.notice(K.OCUBEofUNDEAD, G.lastmonst) end
         return false
      end
   end

   local name = G.lastmonst
   local message, damage
   ns.Bestiary.special(monst, x)

   if x == 1 then  -- rust your armor, j is true once rusting has occurred
      local j = false
      local m = c[K.WEAR]
      local k = m
      local shield = c[K.SHIELD]
      if shield ~= 0 then
         ivenarg[shield] = ivenarg[shield] - 1
         if ivenarg[shield] < -1 then
            ivenarg[shield] = -1
         else
            j = true
         end
      end
      if not j and k ~= 0 then
         m = iven[k]
         for _, entry in ipairs(RUSTARM) do  -- find his armor in the table
            if m == entry[1] then
               ivenarg[k] = ivenarg[k] - 1
               if ivenarg[k] < entry[2] then
                  ivenarg[k] = entry[2]
               else
                  j = true
               end
               break
            end
         end
      end
      if not j then  -- rusting did not occur
         if m == K.OLEATHER then
            message = L["The %s hit you -- you are lucky you have leather on."]
         elseif m == K.OSSPLATE then
            message = L["The %s hit you -- you are fortunate to have stainless steel armor!"]
         elseif m == K.OELVENCHAIN then
            ns.ItemInfo.discover(K.OELVENCHAIN, G.lastmonst)
            message = L["The %s hit you -- you are very lucky to have such strong elven chain!"]
         end
      else
         message = L["The %s hit you -- your armor feels weaker."]
         Player.recalc()
      end

   elseif x == 2 or x == 3 then  -- breath of fire
      damage = x == 2 and rnd(15) + 8 - c[K.AC] or rnd(20) + 25 - c[K.AC]
      -- As in the C, the damage is taken even when fire resistant, and then nothing is said.
      if c[K.FIRERESISTANCE] == 0 then
         Msg(L["The %s breathes fire at you!"], name)
      end
      CheckLoss(damage)
      return false

   elseif x == 4 then
      -- A curse that wears off, not the permanent loss of the original (too harsh at level 2):
      -- each sting takes a point more, and the time runs from the first (the counter of the
      -- time is DRAINSTRENGTH, and INFEEBLEMENT counts the points).
      if c[K.STRENGTH] + c[K.STREXTRA] > 3 then
         message = L["The %s stung you!  A curse makes you weaker."]
         if c[K.DRAINSTRENGTH] == 0 then c[K.DRAINSTRENGTH] = 150 + rnd(100) end
         c[K.INFEEBLEMENT] = c[K.INFEEBLEMENT] + 1
         c[K.STREXTRA] = c[K.STREXTRA] - 1
      else
         message = L["The %s stung you!"]
      end

   elseif x == 5 then
      Msg(L["The %s blasts you with his cold breath."], name)
      CheckLoss(rnd(15) + 18 - c[K.AC])
      return false

   elseif x == 6 then
      Msg(L["The %s drains you of your life energy!"], name)
      Player.loseLevel()
      if monst == DEMONPRINCE then
         Player.loseMaxSpells(1)
      end
      if monst == LUCIFER then
         Player.loseLevel()
         Player.loseMaxSpells(2)
         for i = K.STRENGTH, K.STRENGTH + 5 do  -- C: c[0..5], the six abilities
            local old = c[i]
            c[i] = old - 1
            if old < 3 then c[i] = 3 end
         end
      end
      return false

   elseif x == 7 then
      Msg(L["The %s got you with a gusher!"], name)
      CheckLoss(rnd(15) + 25 - c[K.AC])
      return false

   elseif x == 8 then
      if c[K.NOTHEFT] ~= 0 then  -- he has a device of no theft
         ns.ItemInfo.discover(K.ONOTHEFT, G.lastmonst)
         return false
      end
      if c[K.GOLD] ~= 0 then
         message = L["The %s hit you.  Your purse feels lighter."]
         if c[K.GOLD] > 32767 then
            c[K.GOLD] = idiv(c[K.GOLD], 2)
         else
            c[K.GOLD] = c[K.GOLD] - rnd(1 + idiv(c[K.GOLD], 2))
         end
         if c[K.GOLD] < 0 then c[K.GOLD] = 0 end
      else
         message = L["The %s couldn't find any gold to steal."]
      end
      Msg(message, name)
      mon[xx][yy], know[xx][yy] = 0, 0  -- the leprechaun vanishes
      ui:Refresh("stats")
      return true

   elseif x == 9 then  -- disenchant
      local i = rund(K.IVENSIZE) + 1
      local m = iven[i]  -- randomly select an item
      if m > 0 and ivenarg[i] > 0 and m ~= K.OSCROLL and m ~= K.OPOTION then
         local was = ivenarg[i]
         ivenarg[i] = ivenarg[i] - 3
         if ivenarg[i] < 0 then ivenarg[i] = 0 end
         -- FIX: not in the C, where a disenchanted ring kept all it had given, and took back only
         -- what was left of it: the rest was a permanent gain.  The ring takes its loss now.
         local lost = was - ivenarg[i]
         if m == K.ODEXRING then
            c[K.DEXTERITY] = c[K.DEXTERITY] - lost
         elseif m == K.OSTRRING then
            c[K.STREXTRA] = c[K.STREXTRA] - lost
         elseif m == K.OCLEVERRING then
            c[K.INTELLIGENCE] = c[K.INTELLIGENCE] - lost
         end
         Msg(L["The %s hits you with a spell of disenchantment!"], name)
         Player.recalc()
         ui:Refresh("stats")
         return false
      end

   elseif x == 10 then
      Msg(L["The %s hit you with its barbed tail."], name)
      CheckLoss(rnd(25) - c[K.AC])
      return false

   elseif x == 11 then
      if G.wizard then return false end
      message = L["The %s has confused you."]
      c[K.CONFUSE] = c[K.CONFUSE] + 10 + rnd(10)

   elseif x == 12 then  -- performs any number of other special attacks
      return Monster.spattack(SPSEL[rund(10) + 1], xx, yy)

   elseif x == 13 then
      Msg(L["The %s flattens you with it's psionics!"], name)
      CheckLoss(rnd(15) + 30 - c[K.AC])
      return false

   elseif x == 14 then
      if c[K.NOTHEFT] ~= 0 then  -- he has a device of no theft
         ns.ItemInfo.discover(K.ONOTHEFT, G.lastmonst)
         return false
      end
      if Player.emptyHanded() then
         message = L["The %s couldn't find anything to steal."]
      else
         Msg(L["The %s picks your pocket and takes:"], name)
         if not Player.stealSomething(xx, yy) then
            Msg(L["  nothing"])
         end
         Monster.teleportMonst(xx, yy, mon[xx][yy])
         ui:Refresh("all")
         return true
      end

   elseif x == 15 then
      Msg(L["The %s bit you!"], name)
      CheckLoss(rnd(10) + 5 - c[K.AC])
      return false

   elseif x == 16 then
      Msg(L["The %s bit you!"], name)
      CheckLoss(rnd(15) + 10 - c[K.AC])
      return false
   end

   if message then
      Msg(message, name)
      ui:Refresh("stats")
   end
   return false
end

-- C: hitplayer(). The monster at (x, y) attacks the player.
function Monster.hitplayer(x, y)
   if G.dead then return end  -- the C exits when the player dies
   local monster = G.monster
   local mster = mon[x][y]
   G.lastnum = mster

   if know[x][y] == 0 then
      know[x][y] = 1
      ns.ui:Refresh("map")
   end

   local bias = c[K.HARDGAME] + 1
   G.hitflag, G.hit2flag, G.hit3flag = true, true, true
   ns.ui.repcount = 0
   -- (what Display.visibleMonster hides)
   if (mster == K.INVISIBLESTALKER and c[K.SEEINVISIBLE] == 0)
      or (mster >= K.DEMONLORD and mster <= K.LUCIFER and c[K.EYEOFLARN] == 0) then
      ns.ui:Unseen()
   end
   IfBlind(x, y)
   local name = G.lastmonst

   if mster == K.LEMMING then return end
   ns.ui:Animate("bite", x, y)

   if mster < DEMONLORD and c[K.INVISIBILITY] ~= 0 and rnd(33) < 20 then
      Msg(L["The %s misses wildly!"], name)
      return
   end

   if mster < DEMONLORD and mster ~= K.PLATINUMDRAGON and c[K.CHARMCOUNT] ~= 0 then
      if rnd(30) + 5 * monster[mster].level - c[K.CHARISMA] < 30 then
         Msg(L["The %s is awestruck by your magnificence!"], name)
         return
      end
   end

   local dam = monster[mster].damage
   dam = dam + rnd(dam < 1 and 1 or dam) + monster[mster].level

   local wielded = c[K.WIELD] > 0 and iven[c[K.WIELD]] or 0
   -- demon lords, princes and the god of hellfire do less damage to the wielder of Slayer
   if mster >= DEMONLORD and wielded == K.OSLAYER then
      dam = Trunc(1 - (0.1 * rnd(5)) * dam)
   end

   -- the spirit naga's and poltergeist's damage is halved with the scarab of negate spirit
   if c[K.NEGATESPIRIT] ~= 0 or c[K.SPIRITPRO] ~= 0 then
      if mster == K.POLTERGEIST or mster == K.SPIRITNAGA then
         dam = Trunc(dam / 2)
         if c[K.NEGATESPIRIT] ~= 0 then ns.ItemInfo.discover(K.OSPIRITSCARAB, G.lastmonst) end
      end
   end

   -- halved for the undead with the cube of undead control
   if c[K.CUBEofUNDEAD] ~= 0 or c[K.UNDEADPRO] ~= 0 then
      if mster == K.VAMPIRE or mster == K.WRAITH or mster == K.ZOMBIE then
         dam = Trunc(dam / 2)
         if c[K.CUBEofUNDEAD] ~= 0 then ns.ItemInfo.notice(K.OCUBEofUNDEAD, G.lastmonst) end
      end
   end

   local hit = false
   local ac = c[K.AC]
   if monster[mster].attack > 0 then
      if dam + bias + 8 > ac or rnd(ac > 0 and ac or 1) == 1 then
         ns.ui:Animate("special", x, y, mster)
         if Monster.spattack(monster[mster].attack, x, y) then
            return
         end
         hit = true
         bias = bias - 2
      end
   end

   if dam + bias > ac or rnd(ac > 0 and ac or 1) == 1 then
      hit = true
      dam = dam - ac
      if dam < 0 then dam = 0 end
      ns.Bestiary.hit(mster, dam, ac)
      Msg(L["The %s hit you for %d damage."], name, dam)
      if dam > 0 then
         ns.Player.losehp(dam, true)
      end
   end

   if not hit then
      Msg(L["The %s missed."], name)
   end
end

-- C: annihilate(). Kills the monsters around the player (not the demons) and gives the
-- experience, but no dropped objects.
function Monster.annihilate()
   local k = 0
   for x = G.playerx - 1, G.playerx + 1 do
      for y = G.playery - 1, G.playery + 1 do
         if x >= 1 and x <= MAXX and y >= 1 and y <= MAXY and mon[x][y] ~= 0 then
            local id = mon[x][y]
            if id < DEMONLORD then
               k = k + G.monster[id].experience
               mon[x][y], know[x][y] = 0, 0
            else
               Msg(L["The %s barely escapes being annihilated!"], G.monster[id].name)
               hitp[x][y] = math.floor(hitp[x][y] / 2) + 1  -- lose half the hit points
            end
         end
      end
   end
   if k > 0 then
      Msg(L["You hear loud screams of agony!"])
      ns.Player.raiseExperience(k)
   end
end
