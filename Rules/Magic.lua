--[[
**********************************************************************
WoWLarn - Potions, scrolls, books and teleporting (object.c).
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

local Magic = {}
ns.Magic = Magic

local c, iven, ivenarg = G.c, G.iven, G.ivenarg
local item, know, mon, hitp = G.item, G.know, G.mon, G.hitp

local MAXX, MAXY, DBOTTOM, VBOTTOM = K.MAXX, K.MAXY, K.DBOTTOM, K.VBOTTOM

-- The curses that a scroll of remove curse (or instant healing) lifts.
local CURSE = {
   K.BLINDCOUNT, K.CONFUSE, K.AGGRAVATE, K.HASTEMONST, K.ITCHING,
   K.LAUGHING, K.DRAINSTRENGTH, K.CLUMSINESS, K.HALFDAM,
}
-- What the spell extension scroll doubles.
local EXTEN = {
   K.PROTECTIONTIME, K.DEXCOUNT, K.STRCOUNT, K.CHARMCOUNT, K.INVISIBILITY, K.CANCELLATION,
   K.HASTESELF, K.GLOBE, K.SCAREMONST, K.HOLDMONST, K.TIMESTOP,
}
-- Everything that counts down, for time warps and the school.
local TIME_CHANGE = {
   K.HASTESELF, K.HERO, K.ALTPRO, K.PROTECTIONTIME, K.DEXCOUNT,
   K.STRCOUNT, K.GIANTSTR, K.CHARMCOUNT, K.INVISIBILITY, K.CANCELLATION,
   K.HASTESELF, K.AGGRAVATE, K.SCAREMONST, K.STEALTH, K.AWARENESS, K.HOLDMONST, K.HASTEMONST,
   K.FIRERESISTANCE, K.GLOBE, K.SPIRITPRO, K.UNDEADPRO, K.HALFDAM, K.SEEINVISIBLE,
   K.ITCHING, K.CLUMSINESS, K.WTW, K.DRAINSTRENGTH,
}

local function Msg(fmt, ...)
   ns.ui:Message(fmt, ...)
end

-- C: removecurse().
function Magic.removeCurse()
   for _, index in ipairs(CURSE) do
      if c[index] ~= 0 then c[index] = 1 end
   end
end

-- C: adjusttime(). Moves every timer forward (or back) by tim turns.
function Magic.adjustTime(tim)
   for _, index in ipairs(TIME_CHANGE) do
      if c[index] ~= 0 then
         if c[index] < tim + 1 then
            c[index] = 1
         else
            c[index] = c[index] - tim
         end
      end
   end
   ns.Regen.regen()
end

-- C: oteleport(). err is true for an uncontrolled teleport, which can end in a rock.
function Magic.teleport(err)
   if err and rnd(151) < 3 then
      ns.Player.died(264)  -- stuck in a rock
      return
   end
   if not G.wizard then c[K.TELEFLAG] = 1 end  -- show ?? on the bottom line

   local level, tmp = G.level, 0
   if level == 0 then
      tmp = 0
   elseif level <= DBOTTOM then  -- in the dungeon
      tmp = rnd(5) + level - 3
      if tmp > DBOTTOM then tmp = DBOTTOM end
      if tmp < 0 then tmp = 0 end
   else  -- in the volcano
      tmp = rnd(4) + level - 2
      if tmp >= VBOTTOM then tmp = VBOTTOM end
      if tmp < DBOTTOM + 1 then tmp = 0 end  -- back to the surface
   end
   G.playerx, G.playery = rnd(MAXX - 2) + 1, rnd(MAXY - 2) + 1
   if level ~= tmp then
      ns.Create.newCaveLevel(tmp)
   end
   ns.Player.positionPlayer()
   ns.ui:Refresh("all")
end

-- C: readbook(). Teaches a spell depending on the level of the book.
function Magic.readBook(arg)
   local T = ns.Tables
   local i
   if arg <= 3 then
      local tmp = T.splev[arg + 1]
      i = rund(tmp ~= 0 and tmp or 1)
   else
      if arg >= 21 then arg = 20 end  -- # entries in splev = 21
      local tmp = T.splev[arg + 1] - 9
      i = rnd(tmp ~= 0 and tmp or 1) + 9
   end
   local spell = i + 1  -- spell ids are shifted
   if arg >= 3 and G.spelknow[K.SP_MONSTER_LORE] == 0 and rnd(8) == 1 then spell = K.SP_MONSTER_LORE end  -- (not in the original: any book may teach it)
   G.spelknow[spell] = 1
   Msg(L["Spell \"%s\":  %s"], T.spelcode[spell], T.spelname[spell])
   Msg("%s.", T.speldescript[spell])
   if rnd(10) == 4 then
      Msg(L["You feel clever!"])
      c[K.INTELLIGENCE] = c[K.INTELLIGENCE] + 1
      ns.ui:Refresh("stats")
   end
end

-- C: quaffpotion(). The effect of drinking potion number pot.
function Magic.quaffPotion(pot)
   local ui = ns.ui
   if pot < 1 or pot > K.MAXPOTION then return end  -- check for within bounds

   G.potionknown[pot] = 1
   Msg(L["You drink a potion of %s."], ns.Tables.potionname[pot])
   ui:Sound("potion")

   if pot == K.PSLEEP then
      Msg(L["You fall asleep..."])
      local i = rnd(11) - idiv(c[K.CONSTITUTION], 4) + 2
      i = i - 1
      while i > 0 do
         ns.Game.parse2()
         if G.dead then return end
         ui:Nap(1000)
         i = i - 1
      end
      Msg(L[".. you wake up."])
      return

   elseif pot == K.PHEALING then
      Msg(L["You feel better."])
      if c[K.HP] == c[K.HPMAX] then
         ns.Player.raiseMaxHP(1)
      else
         c[K.HP] = c[K.HP] + rnd(20) + 20 + c[K.LEVEL]
         if c[K.HP] > c[K.HPMAX] then c[K.HP] = c[K.HPMAX] end
      end

   elseif pot == K.PRAISELEVEL then
      Msg(L["You feel much more skillful!"])
      ns.Player.raiseLevel()
      ns.Player.raiseMaxHP(1)
      return

   elseif pot == K.PINCABILITY then
      Msg(L["You feel strange for a moment."])
      local index = K.STRENGTH + rund(6)
      c[index] = c[index] + 1

   elseif pot == K.PWISDOM then
      Msg(L["You feel more self-confident!"])
      c[K.WISDOM] = c[K.WISDOM] + rnd(2)

   elseif pot == K.PSTRENGTH then
      Msg(L["Wow!  You feel great!"])
      if c[K.STRENGTH] < 12 then
         c[K.STRENGTH] = 12
      else
         c[K.STRENGTH] = c[K.STRENGTH] + 1
      end

   elseif pot == K.PCHARISMA then
      Msg(L["You feel charismatic!"])
      c[K.CHARISMA] = c[K.CHARISMA] + 1

   elseif pot == K.PDIZZINESS then
      Msg(L["You become dizzy!"])
      c[K.STRENGTH] = c[K.STRENGTH] - 1
      if c[K.STRENGTH] < 3 then c[K.STRENGTH] = 3 end

   elseif pot == K.PLEARNING then
      Msg(L["You feel clever!"])
      c[K.INTELLIGENCE] = c[K.INTELLIGENCE] + 1

   elseif pot == K.PGOLDDET then
      Msg(L["You feel greedy..."])
      ui:Nap(2000)
      for x = 1, MAXX do
         for y = 1, MAXY do
            if item[x][y] == K.OGOLDPILE or item[x][y] == K.OMAXGOLD then
               know[x][y] = 1
            end
         end
      end
      ui:Refresh("all")
      return

   elseif pot == K.PMONSTDET then
      for x = 1, MAXX do
         for y = 1, MAXY do
            if mon[x][y] ~= 0 then know[x][y] = 1 end
         end
      end
      ui:Refresh("all")
      return

   elseif pot == K.PFORGETFUL then
      Msg(L["You stagger for a moment..."])
      G.FillKnow(0)
      ui:Nap(2000)
      ui:Refresh("all")
      return

   elseif pot == K.PWATER then
      return

   elseif pot == K.PBLINDNESS then
      Msg(L["You can't see anything!"])
      c[K.BLINDCOUNT] = c[K.BLINDCOUNT] + 500  -- dang, that's a long time
      ui:Refresh("all")
      return

   elseif pot == K.PCONFUSION then
      Msg(L["You feel confused."])
      c[K.CONFUSE] = c[K.CONFUSE] + 20 + rnd(9)
      return

   elseif pot == K.PHEROISM then
      Msg(L["WOW!  You feel fantastic!"])
      if c[K.HERO] == 0 then
         for i = K.STRENGTH, K.STRENGTH + 5 do c[i] = c[i] + 11 end
      end
      c[K.HERO] = c[K.HERO] + 250

   elseif pot == K.PSTURDINESS then
      Msg(L["You feel healthier!"])
      c[K.CONSTITUTION] = c[K.CONSTITUTION] + 1

   elseif pot == K.PGIANTSTR then
      Msg(L["You now have incredible bulging muscles!"])
      if c[K.GIANTSTR] == 0 then c[K.STREXTRA] = c[K.STREXTRA] + 21 end
      c[K.GIANTSTR] = c[K.GIANTSTR] + 700

   elseif pot == K.PFIRERESIST then
      Msg(L["You feel a chill run up your spine!"])
      c[K.FIRERESISTANCE] = c[K.FIRERESISTANCE] + 1000

   elseif pot == K.PTREASURE then
      Msg(L["You feel greedy..."])
      ui:Nap(2000)
      for x = 1, MAXX do
         for y = 1, MAXY do
            local k = item[x][y]
            if k == K.ODIAMOND or k == K.ORUBY or k == K.OEMERALD or k == K.OMAXGOLD
               or k == K.OSAPPHIRE or k == K.OLARNEYE or k == K.OGOLDPILE then
               know[x][y] = 1
            end
         end
      end
      ui:Refresh("all")
      return

   elseif pot == K.PINSTHEAL then
      c[K.HP] = c[K.HPMAX]
      Magic.removeCurse()

   elseif pot == K.PCUREDIANTH then
      Msg(L["You don't seem to be affected."])
      return

   elseif pot == K.PPOISON then
      Msg(L["You feel a sickness engulf you!"])
      c[K.HALFDAM] = c[K.HALFDAM] + 200 + rnd(200)
      return

   elseif pot == K.PSEEINVIS then
      Msg(L["You feel your vision sharpen."])
      c[K.SEEINVISIBLE] = c[K.SEEINVISIBLE] + rnd(1000) + 400
      return
   end
   ns.Player.recalc()
   ui:Refresh("stats")  -- show new stats
end

-- C: read_scroll(). The effect of reading scroll number typ.
function Magic.readScroll(typ)
   local ui = ns.ui
   if typ < 1 or typ > K.MAXSCROLL then return end  -- be sure we are within bounds
   G.scrollknown[typ] = 1
   Msg(L["You read a scroll of %s."], ns.Tables.scrollname[typ])
   ui:Sound("scroll")

   if typ == K.SENCHANTARM then
      ns.Player.enchantArmor(K.ENCH_SCROLL)

   elseif typ == K.SENCHANTWEAP then
      ns.Player.enchantWeapon(K.ENCH_SCROLL)

   elseif typ == K.SENLIGHTEN then
      local yh, xh = math.min(G.playery + 7, MAXY), math.min(G.playerx + 25, MAXX)
      local yl, xl = math.max(G.playery - 7, 1), math.max(G.playerx - 25, 1)
      for y = yl, yh do
         for x = xl, xh do
            know[x][y] = 1
         end
      end
      ui:Nap(2000)
      ui:Refresh("all")

   elseif typ == K.SCREATEMONST then
      ns.Monster.createMonster(ns.Monster.makeMonst(G.level + 1))

   elseif typ == K.SCREATEITEM then
      ns.Item.something(G.playerx, G.playery, G.level)

   elseif typ == K.SAGGMONST then
      c[K.AGGRAVATE] = c[K.AGGRAVATE] + 800

   elseif typ == K.STIMEWARP then
      -- As in the C, this is slightly wrong if gtime is small and we can't go back far enough.
      local i = idiv(rnd(1000) - 850, 100)
      if i == 0 then i = 1 end
      G.gtime = G.gtime + 100 * i
      if G.gtime < 0 then G.gtime = 0 end
      local count = i < 0 and -i or i
      if i < 0 then
         Msg(count == 1 and L["You go backward in time by %d mobul"] or L["You go backward in time by %d mobuls"], count)
      else
         Msg(count == 1 and L["You go forward in time by %d mobul"] or L["You go forward in time by %d mobuls"], count)
      end
      Magic.adjustTime(i * 100)

   elseif typ == K.STELEPORT then
      Magic.teleport(false)

   elseif typ == K.SAWARENESS then
      c[K.AWARENESS] = c[K.AWARENESS] + 1800

   elseif typ == K.SHASTEMONST then
      c[K.HASTEMONST] = c[K.HASTEMONST] + rnd(55) + 12
      Msg(L["You feel nervous."])

   elseif typ == K.SMONSTHEAL then
      for x = 1, MAXX do
         for y = 1, MAXY do
            if mon[x][y] ~= 0 then hitp[x][y] = G.monster[mon[x][y]].hitpoints end
         end
      end
      Msg(L["You feel uneasy."])

   elseif typ == K.SSPIRITPROT then
      c[K.SPIRITPRO] = c[K.SPIRITPRO] + 300 + rnd(200)

   elseif typ == K.SUNDEADPROT then
      c[K.UNDEADPRO] = c[K.UNDEADPRO] + 300 + rnd(200)

   elseif typ == K.SSTEALTH then
      c[K.STEALTH] = c[K.STEALTH] + 250 + rnd(250)

   elseif typ == K.SMAGICMAP then
      G.FillKnow(1)
      ui:Nap(2000)

   elseif typ == K.SHOLDMONST then
      c[K.HOLDMONST] = c[K.HOLDMONST] + 30

   elseif typ == K.SGEMPERFECT then
      for i = 1, K.IVENSIZE do
         local id = iven[i]
         if id == K.ODIAMOND or id == K.ORUBY or id == K.OEMERALD or id == K.OSAPPHIRE then
            local j = ivenarg[i] * 2
            if j <= 0 and ivenarg[i] ~= 0 then j = 2550 end
            ivenarg[i] = j
         end
      end

   elseif typ == K.SSPELLEXT then
      for _, index in ipairs(EXTEN) do
         c[index] = c[index] * 2
      end

   elseif typ == K.SIDENTIFY then
      for i = 1, K.IVENSIZE do
         if iven[i] == K.OPOTION then G.potionknown[ivenarg[i]] = 1 end
         if iven[i] == K.OSCROLL then G.scrollknown[ivenarg[i]] = 1 end
      end

   elseif typ == K.SREMCURSE then
      Magic.removeCurse()

   elseif typ == K.SANNIHILATE then
      ns.Monster.annihilate()

   elseif typ == K.SPULVERIZE then
      ns.Spells.godirect(K.SP_LIGHTNING, 150, L["The ray hits the %s."], 0, " ")

   elseif typ == K.SLIFEPROT then
      c[K.LIFEPROT] = c[K.LIFEPROT] + 1
   end
   ui:Refresh("all")
end
