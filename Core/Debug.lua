--[[
**********************************************************************
WoWLarn - Wizard mode and god mode (debug builds only: the packager strips this file).
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
local _, ns = ...
local K = ns.K
local G = ns.G
local c = G.c

-- Wizard mode (main.c: the '=' command and every `wizard` check) and a god mode that cannot
-- die.  Wizard games never record scores.  The keys:
--   =  wizard mode on or off        _  the debug kit        #  maximum experience
--   @  create an item               A  dump the state       Z  teleport to any level
local Debug = {}
ns.Debug = Debug

local function Log(format, ...)
   ns.ui:Log("system", "|cffff8040[debug]|r " .. format, ...)
end

function Debug.toggleWizard()
   G.wizard = not G.wizard
   if G.wizard then G.cheated = true end  -- (turning it off again does not make the game count)
   Log("wizard mode %s%s", G.wizard and "on" or "off", G.cheated and " (this game will not be scored)" or "")
   ns.ui:Refresh("all")
   if ns.debugPanel.Update then ns.debugPanel:Update() end
end

function Debug.toggleGod()
   G.god = not G.god
   if G.god then G.wizard, G.cheated = true, true end  -- (no score for a game that cannot be lost)
   Log("god mode %s%s", G.god and "on" or "off", G.god and " (wizard mode too: this game will not be scored)" or "")
   if G.god then c[K.HP] = c[K.HPMAX] end
   ns.ui:Refresh("all")
   if ns.debugPanel.Update then ns.debugPanel:Update() end
end

-- Maps, spells, potions and scrolls known, strong, with the Lance of Death.
function Debug.kit()
   for i = K.STRENGTH, K.STRENGTH + 5 do c[i] = 70 end
   c[K.HPMAX] = math.max(c[K.HPMAX], 1000)
   c[K.HP] = c[K.HPMAX]
   c[K.SPELLMAX] = math.max(c[K.SPELLMAX], 200)
   c[K.SPELLS] = c[K.SPELLMAX]
   for spell = 1, K.SPNUM do G.spelknow[spell] = 1 end
   for potion = 1, K.MAXPOTION do G.potionknown[potion] = 1 end
   for scroll = 1, K.MAXSCROLL do G.scrollknown[scroll] = 1 end
   G.FillKnow(1)
   if not ns.Player.take(K.OLANCE, 0) then Log("no room for the Lance of Death") end
   ns.Player.recalc()
   ns.Player.normalize()
   G.statSnap = nil  -- (no need to report it)
   Log("debug kit: stats 70, spells and potions and scrolls known, map revealed")
   ns.ui:Refresh("all")
end

function Debug.reveal()
   G.FillKnow(1)
   Log("map revealed")
   ns.ui:Refresh("all")
end

function Debug.maxExperience()
   local top = ns.Tables.skill[K.MAXPLEVEL]
   if c[K.EXPERIENCE] < top then ns.Player.raiseExperience(top - c[K.EXPERIENCE]) end
   Log("level %d", c[K.LEVEL])
   ns.ui:Refresh("all")
end

-- Asks for an object number and its argument, and puts the object next to the player.  Runs
-- in the game, since it asks.
function Debug.createItem()
   local ui = ns.ui
   local id = ui:GetNumber(format("Create which object (1-%d)?", K.MAXOBJ - 1), K.MAXOBJ - 1)
   if id < 1 or id >= K.MAXOBJ then return end
   local arg = ui:GetNumber("Its argument (enchantment, potion or scroll kind)?", 100)
   if arg < 0 then return end
   Debug.makeItem(id, arg)
end

-- Puts an object next to the player.
-- The four gold ids are one pile at different scales (the argument is multiplied).
local GOLD_SCALE = { [K.OGOLDPILE] = 1, [K.ODGOLD] = 10, [K.OMAXGOLD] = 100, [K.OKGOLD] = 1000 }

function Debug.objectLabel(id, name)
   local scale = GOLD_SCALE[id]
   if scale then return ("%s (x%d)"):format(name, scale) end
   return name
end

function Debug.makeItem(id, arg)
   ns.Item.createItem(G.playerx, G.playery, id, arg)
   Log("created %s (%d, %d)", ns.Tables.objectname[id] or "?", id, arg)
   ns.ui:RefreshNow("all")
end

-- Empties the level the player is on (monsters, objects, the walls inside) and shows all of it,
-- to look at things without anything in the way.  The wall round the edge stays.
function Debug.clearLevel()
   G.ClearLevel()
   for x = 1, K.MAXX do
      for y = 1, K.MAXY do
         if x == 1 or x == K.MAXX or y == 1 or y == K.MAXY then G.item[x][y] = K.OWALL end
         G.know[x][y], G.seen[x][y] = 1, 1
      end
   end
   G.playerx, G.playery = 2, 2
   Log("level %d cleared", G.level)
end

-- Clears the level and lays out every kind of object on it in rows, a tile apart (potions and
-- scrolls once for each kind).  level: goes there first (1 is a dungeon, 16 the volcano).
function Debug.showcase(level)
   if level and level ~= G.level then
      ns.Create.newCaveLevel(level)
   end
   Debug.clearLevel()
   local x, y, count = 3, 3, 0
   local function put(id, arg)
      G.item[x][y], G.iarg[x][y] = id, arg or 0
      count = count + 1
      x = x + 2
      if x > K.MAXX - 2 then x, y = 3, y + 2 end
   end
   for id = 1, K.MAXOBJ - 1 do
      if id == K.OPOTION then
         for kind = 1, K.MAXPOTION do put(id, kind) end
      elseif id == K.OSCROLL then
         for kind = 1, K.MAXSCROLL do put(id, kind) end
      elseif id ~= K.OWALL and ns.Tables.objectname[id] and y <= K.MAXY - 2 then
         put(id, GOLD_SCALE[id] and 100 or 0)
      end
   end
   ns.Player.positionPlayer()
   Log("%d objects laid out on level %d", count, G.level)
   ns.ui:Refresh("all")
end

-- Throws the game away, with no score and no saved game left, and starts a new one (a game in
-- god mode can neither be lost nor, until now, be given up).
function Debug.newGame()
   ns.Save.clear()
   ns.ui.co = nil
   ns.ui.wait = nil
   ns.inventory:Close()
   ns.spellbook:Close()
   ns.main:Show()
   ns.ui:NewGame()
   Log("a new game")
end

function Debug.dump()
   Log("level %d at %d,%d  turn %d  hp %d/%d  level %d  experience %d", G.level, G.playerx, G.playery, G.gtime,
      c[K.HP], c[K.HPMAX], c[K.LEVEL], c[K.EXPERIENCE])
   Log("stats %d %d %d %d %d %d  gold %d  wizard %s  god %s", c[K.STRENGTH], c[K.INTELLIGENCE], c[K.WISDOM],
      c[K.CONSTITUTION], c[K.DEXTERITY], c[K.CHARISMA], c[K.GOLD], tostring(G.wizard), tostring(G.god))
   local monsters = 0
   for x = 1, K.MAXX do
      for y = 1, K.MAXY do
         if G.mon[x][y] ~= 0 then monsters = monsters + 1 end
      end
   end
   Log("%d monsters on this level", monsters)
end

-- The wizard keys of the game (Game.lua).
function Debug.key(key)
   if key == "=" then
      Debug.toggleWizard()
   elseif not G.wizard then
      Log("wizard mode is off (= turns it on)")
   elseif key == "_" then
      Debug.kit()
   elseif key == "#" then
      Debug.maxExperience()
   elseif key == "@" then
      Debug.createItem()
   elseif key == "A" then
      Debug.dump()
   end
end
