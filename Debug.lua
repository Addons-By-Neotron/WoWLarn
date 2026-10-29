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
   Log("wizard mode %s%s", G.wizard and "on" or "off", G.wizard and " (this game will not be scored)" or "")
   ns.ui:Refresh("all")
   if ns.debugPanel.Update then ns.debugPanel:Update() end
end

function Debug.toggleGod()
   G.god = not G.god
   if G.god then G.wizard = true end  -- (no score for a game that cannot be lost)
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
   ns.Item.createItem(G.playerx, G.playery, id, arg)
   Log("created %s (%d, %d)", ns.Tables.objectname[id] or "?", id, arg)
   ui:Refresh("all")
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
