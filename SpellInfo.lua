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
local format = string.format
local idiv = ns.idiv

-- What each spell does for the caster as they are now (level, intelligence, wisdom...), for
-- the tooltips of the spellbook, in the way of the WoW spell tooltips.  The numbers follow the
-- formulas of Spells.lua (C: speldamage()).  info(spell) returns the description and the short
-- form shown in the list (damage range); kind(spell) says how the spell reaches its target.
local SpellInfo = {}
ns.SpellInfo = SpellInfo

local c = G.c

-- Spells that can backfire (not what the risks are, only that they might).
local RISKY = {
   [K.SP_DRAIN_LIFE] = true, [K.SP_FINGER_OF_DEATH] = true, [K.SP_SPHERE_OF_ANNIHILATION] = true,
   [K.SP_SUMMON_DEMON] = true,
}

local function Range(low, high)
   return format("%d-%d", low, high)
end

-- How a spell reaches what it works on (the right hand side of the tooltip).
local SELF, LINE, AROUND, NEXT, LEVEL = L["Self"], L["In a line"], L["Around you"], L["Next to you"], L["Whole level"]
local KIND = {
   [K.SP_PROTECTION] = SELF, [K.SP_MAGIC_MISSILE] = LINE, [K.SP_DEXTERITY] = SELF, [K.SP_SLEEP] = NEXT,
   [K.SP_CHARM_MONSTER] = SELF, [K.SP_SONIC_SPEAR] = LINE, [K.SP_WEB] = NEXT, [K.SP_STRENGTH] = SELF,
   [K.SP_ENLIGHTENMENT] = AROUND, [K.SP_HEALING] = SELF, [K.SP_CURE_BLINDNESS] = SELF,
   [K.SP_CREATE_MONSTER] = AROUND, [K.SP_PHANTASMAL_FORCES] = NEXT, [K.SP_INVISIBILITY] = SELF,
   [K.SP_FIREBALL] = LINE, [K.SP_COLD] = LINE, [K.SP_POLYMORPH] = NEXT, [K.SP_CANCELLATION] = SELF,
   [K.SP_HASTE_SELF] = SELF, [K.SP_CLOUD_KILL] = AROUND, [K.SP_VAPORIZE_ROCK] = AROUND,
   [K.SP_DEHYDRATION] = NEXT, [K.SP_LIGHTNING] = LINE, [K.SP_DRAIN_LIFE] = NEXT, [K.SP_INVULNERABILITY] = SELF,
   [K.SP_FLOOD] = AROUND, [K.SP_FINGER_OF_DEATH] = NEXT, [K.SP_SCARE_MONSTER] = SELF, [K.SP_HOLD_MONSTER] = SELF,
   [K.SP_TIME_STOP] = SELF, [K.SP_TELEPORT_AWAY] = NEXT, [K.SP_MAGIC_FIRE] = AROUND, [K.SP_MAKE_A_WALL] = NEXT,
   [K.SP_SPHERE_OF_ANNIHILATION] = NEXT, [K.SP_GENOCIDE] = LEVEL, [K.SP_SUMMON_DEMON] = NEXT,
   [K.SP_WALK_THROUGH_WALLS] = SELF, [K.SP_ALTER_REALITY] = LEVEL, [K.SP_PERMANENCE] = SELF,
}

-- Spells whose damage or healing is the same every time (it only grows with your level).
local FIXED = {
   [K.SP_HEALING] = true, [K.SP_DEHYDRATION] = true, [K.SP_DRAIN_LIFE] = true, [K.SP_FLOOD] = true,
   [K.SP_FINGER_OF_DEATH] = true, [K.SP_SUMMON_DEMON] = true,
}

-- Missiles lose strength with every tile (see GoDirect).
local function Missile(what, low, high)
   local fade = 3 + idiv(c[K.HARDGAME], 2)
   return format(what, Range(low, high), fade), Range(low, high)
end

local function Around(low, high)
   return format(L["Hurts every monster next to you for %s damage."], Range(low, high)), Range(low, high)
end

-- Each entry is a function of the caster's level that returns the description and, for the
-- spells that do damage, the short form.
local INFO = {
   [K.SP_PROTECTION] = function() return L["Raises your armor by 2 for 250 turns.  Casting it again adds to the time."] end,
   [K.SP_MAGIC_MISSILE] = function(lev)
      return Missile(L["Hurls a magic missile in a straight line, causing %s damage to the monsters in its way.  It loses %d damage for every tile it flies."], lev + 4, 3 * lev + 5)
   end,
   [K.SP_DEXTERITY] = function() return L["Adds 3 to your dexterity for 400 turns."] end,
   [K.SP_SLEEP] = function() return L["Puts the monster to sleep, if it works.  A sleeping monster takes 2-4 free weapon hits."] end,
   [K.SP_CHARM_MONSTER] = function() return format(L["Monsters may be awed by you and not attack, for %d turns."], c[K.CHARISMA] * 2) end,
   [K.SP_SONIC_SPEAR] = function(lev)
      return Missile(L["Hurls a sonic spear in a straight line, causing %s damage to the monsters in its way.  It loses %d damage for every tile it flies."], 16 + lev, 25 + lev)
   end,
   [K.SP_WEB] = function() return L["Entangles the monster, if it works.  A trapped monster takes 3-5 free weapon hits."] end,
   [K.SP_STRENGTH] = function() return L["Adds 3 to your strength for 151-250 turns."] end,
   [K.SP_ENLIGHTENMENT] = function() return L["Maps the area around you, 32 tiles wide and 12 high."] end,
   [K.SP_HEALING] = function(lev) return format(L["Heals you for %d hit points."], 20 + lev * 2), tostring(20 + lev * 2) end,
   [K.SP_CURE_BLINDNESS] = function() return L["Cures your blindness."] end,
   [K.SP_CREATE_MONSTER] = function() return L["Creates a monster next to you, one of those of the level you are on."] end,
   [K.SP_PHANTASMAL_FORCES] = function(lev)
      return format(L["Conjures an illusion that causes %s damage to the monster if it believes it.  Needs wisdom."],
         Range(21 + lev, 40 + lev)), Range(21 + lev, 40 + lev)
   end,
   [K.SP_INVISIBILITY] = function() return L["Makes you invisible for 12 turns, 128 more for each amulet of invisibility."] end,
   [K.SP_FIREBALL] = function(lev)
      return Missile(L["Hurls a fireball in a straight line, causing %s fire damage to the monsters in its way.  It loses %d damage for every tile it flies."], 26 + lev, 50 + 2 * lev)
   end,
   [K.SP_COLD] = function(lev)
      return Missile(L["Sends a blast of cold in a straight line, causing %s frost damage to the monsters in its way.  It loses %d damage for every tile it flies."], 21 + lev, 45 + lev)
   end,
   [K.SP_POLYMORPH] = function() return L["Changes the monster into a random one."] end,
   [K.SP_CANCELLATION] = function(lev) return format(L["Monsters can't use their special abilities for %d turns."], 5 + lev) end,
   [K.SP_HASTE_SELF] = function(lev) return format(L["You act twice as often for %d turns."], 7 + lev) end,
   [K.SP_CLOUD_KILL] = function() return Around(31, 40) end,
   [K.SP_VAPORIZE_ROCK] = function() return L["Turns the rock around you into air.  Xorns and trolls take 200 damage."] end,
   [K.SP_DEHYDRATION] = function(lev) return format(L["Dries up the monster for %d damage."], 100 + lev), tostring(100 + lev) end,
   [K.SP_LIGHTNING] = function(lev)
      return Missile(L["Shoots a bolt of lightning in a straight line, causing %s damage to the monsters in its way.  It loses %d damage for every tile it flies."], 21 + 2 * lev, 45 + 2 * lev)
   end,
   [K.SP_DRAIN_LIFE] = function()
      local drain = math.max(0, math.min(c[K.HP] - 1, idiv(c[K.HPMAX], 2)))
      return format(L["Costs you %d hit points to deal %d damage to the monster."], drain, drain * 2), tostring(drain * 2)
   end,
   [K.SP_INVULNERABILITY] = function() return L["Raises your armor by 10 for 200 turns.  Costs 1 intelligence."] end,
   [K.SP_FLOOD] = function(lev)
      return format(L["Floods the area, hurting every monster next to you for %d damage."], 32 + lev), tostring(32 + lev)
   end,
   [K.SP_FINGER_OF_DEATH] = function() return L["Kills the monster outright, if it works.  Needs wisdom."], "2000" end,
   [K.SP_SCARE_MONSTER] = function(lev) return format(L["Monsters won't fight you for %s turns, three times as long with the hand of fear."], Range(1 + lev, 10 + lev)) end,
   [K.SP_HOLD_MONSTER] = function(lev) return format(L["Freezes every monster for %s turns."], Range(1 + lev, 10 + lev)) end,
   [K.SP_TIME_STOP] = function(lev) return format(L["Stops time for %s turns.  You can still move."], Range(1 + 2 * lev, 20 + 2 * lev)) end,
   [K.SP_TELEPORT_AWAY] = function() return L["Sends the monster to somewhere else on the level."] end,
   [K.SP_MAGIC_FIRE] = function(lev) return Around(36 + lev, 45 + lev) end,
   [K.SP_MAKE_A_WALL] = function() return L["Builds a wall on an empty tile."] end,
   [K.SP_SPHERE_OF_ANNIHILATION] = function()
      return L["Makes a sphere that wanders on its own for 12-31 turns and kills whatever it touches.  Costs 1 intelligence."]
   end,
   [K.SP_GENOCIDE] = function() return L["Wipes out a kind of monster for good.  Costs 1 intelligence, and the spell is forgotten."] end,
   [K.SP_SUMMON_DEMON] = function()
      return L["Calls a demon to strike the monster for 150 damage.  It may also do nothing, or turn on you."], "150"
   end,
   [K.SP_WALK_THROUGH_WALLS] = function() return format(L["You can walk through walls for %s turns."], Range(6, 15)) end,
   [K.SP_ALTER_REALITY] = function() return L["Bends the world into a new shape.  Whatever is in it comes along, but nothing stays where it was.  Costs 1 intelligence, and the spell is forgotten."] end,
   [K.SP_PERMANENCE] = function() return L["Makes the spells with a time limit permanent.  Costs 1 intelligence, and the spell is forgotten."] end,
}

function SpellInfo.risky(spell)
   return RISKY[spell] or false
end

-- How the spell reaches its target: "Self", "In a line", "Around you", "Next to you"...
function SpellInfo.kind(spell)
   return KIND[spell]
end

-- True if the damage or healing is the same every time.
function SpellInfo.fixed(spell)
   return FIXED[spell] or false
end

-- The description and the short form (or nil) of the spell for the caster as they are now.
function SpellInfo.info(spell)
   local info = INFO[spell]
   if not info then return nil end
   return info(c[K.LEVEL])
end

-- The character level the spell needs (C: speldamage() checks level * 3 + 2 against the spell).
function SpellInfo.minLevel(spell)
   return math.max(0, math.ceil((spell - 3) / 3))
end
