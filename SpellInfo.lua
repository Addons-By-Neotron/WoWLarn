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
-- the tooltips of the spellbook.  The numbers follow the formulas of Spells.lua (C: speldamage()).
-- info(spell) returns the effect text and the short form shown in the list (damage range).
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

-- Missiles lose strength with every tile (see GoDirect).
local function Missile(low, high)
   local fade = 3 + idiv(c[K.HARDGAME], 2)
   return format(L["%s damage; the missile loses %d for every tile it flies"], Range(low, high), fade), Range(low, high)
end

local function Adjacent(low, high)
   return format(L["%s damage to every monster next to you"], Range(low, high)), Range(low, high)
end

local function Turns(low, high, what)
   if low == high then return format(what, low) end
   return format(what, Range(low, high))
end

-- Each entry is a function of the caster's level that returns the effect and, for the
-- spells that do damage, the short form.
local INFO = {
   [K.SP_PROTECTION] = function() return L["+2 armor for 250 turns (stacks the time)"] end,
   [K.SP_MAGIC_MISSILE] = function(lev) return Missile(lev + 4, 3 * lev + 5) end,
   [K.SP_DEXTERITY] = function() return L["+3 dexterity for 400 turns"] end,
   [K.SP_SLEEP] = function() return L["Hits the monster next to you 2-4 times with your weapon"] end,
   [K.SP_CHARM_MONSTER] = function() return format(L["Monsters may be awed for %d turns"], c[K.CHARISMA] * 2) end,
   [K.SP_SONIC_SPEAR] = function(lev) return Missile(16 + lev, 25 + lev) end,
   [K.SP_WEB] = function() return L["Hits the monster next to you 3-5 times with your weapon"] end,
   [K.SP_STRENGTH] = function() return L["+3 strength for 151-250 turns"] end,
   [K.SP_ENLIGHTENMENT] = function() return L["Maps the area around you (32 by 12 tiles)"] end,
   [K.SP_HEALING] = function(lev) return format(L["Heals %d hit points"], 20 + lev * 2), tostring(20 + lev * 2) end,
   [K.SP_CURE_BLINDNESS] = function() return L["Cures blindness"] end,
   [K.SP_CREATE_MONSTER] = function() return L["Creates a monster of this level's kind next to you"] end,
   [K.SP_PHANTASMAL_FORCES] = function(lev)
      return format(L["%s damage to the monster in a direction, if it believes you (needs wisdom)"],
         Range(21 + lev, 40 + lev)), Range(21 + lev, 40 + lev)
   end,
   [K.SP_INVISIBILITY] = function() return L["Invisible for 12 turns (128 more for each amulet of invisibility)"] end,
   [K.SP_FIREBALL] = function(lev) return Missile(26 + lev, 50 + 2 * lev) end,
   [K.SP_COLD] = function(lev) return Missile(21 + lev, 45 + lev) end,
   [K.SP_POLYMORPH] = function() return L["Turns the monster in a direction into a random one"] end,
   [K.SP_CANCELLATION] = function(lev) return format(L["Monsters can't use special abilities for %d turns"], 5 + lev) end,
   [K.SP_HASTE_SELF] = function(lev) return format(L["You move twice as fast for %d turns"], 7 + lev) end,
   [K.SP_CLOUD_KILL] = function() return Adjacent(31, 40) end,
   [K.SP_VAPORIZE_ROCK] = function() return L["Turns the rock around you to air; hurts xorns and trolls (200)"] end,
   [K.SP_DEHYDRATION] = function(lev) return format(L["%d damage to the monster in a direction"], 100 + lev), tostring(100 + lev) end,
   [K.SP_LIGHTNING] = function(lev) return Missile(21 + 2 * lev, 45 + 2 * lev) end,
   [K.SP_DRAIN_LIFE] = function()
      local drain = math.max(0, math.min(c[K.HP] - 1, idiv(c[K.HPMAX], 2)))
      return format(L["%d damage to the monster in a direction; costs you %d hit points"], drain * 2, drain), tostring(drain * 2)
   end,
   [K.SP_INVULNERABILITY] = function() return L["+10 armor for 200 turns; costs 1 intelligence"] end,
   [K.SP_FLOOD] = function(lev) return Adjacent(32 + lev, 32 + lev) end,
   [K.SP_FINGER_OF_DEATH] = function()
      return L["2000 damage to the monster in a direction (needs wisdom)"], "2000"
   end,
   [K.SP_SCARE_MONSTER] = function(lev) return format(L["Monsters won't fight you for %s turns (3 times with the hand of fear)"], Range(1 + lev, 10 + lev)) end,
   [K.SP_HOLD_MONSTER] = function(lev) return format(L["Monsters are frozen for %s turns"], Range(1 + lev, 10 + lev)) end,
   [K.SP_TIME_STOP] = function(lev) return format(L["Time stops for %s turns"], Range(1 + 2 * lev, 20 + 2 * lev)) end,
   [K.SP_TELEPORT_AWAY] = function() return L["Teleports the monster in a direction elsewhere on the level"] end,
   [K.SP_MAGIC_FIRE] = function(lev) return Adjacent(36 + lev, 45 + lev) end,
   [K.SP_MAKE_A_WALL] = function() return L["Builds a wall on an empty tile in a direction"] end,
   [K.SP_SPHERE_OF_ANNIHILATION] = function()
      return L["Makes a sphere that wanders for 12-31 turns and kills what it touches; costs 1 intelligence"]
   end,
   [K.SP_GENOCIDE] = function() return L["Wipes out a kind of monster for good; costs 1 intelligence and the spell is forgotten"] end,
   [K.SP_SUMMON_DEMON] = function()
      return L["A demon hits the monster in a direction for 150, but it may also do nothing, or turn on you"], "150"
   end,
   [K.SP_WALK_THROUGH_WALLS] = function() return Turns(6, 15, L["Walk through walls for %s turns"]) end,
   [K.SP_ALTER_REALITY] = function() return L["Rebuilds the level, keeping what is on it; costs 1 intelligence and the spell is forgotten"] end,
   [K.SP_PERMANENCE] = function() return L["Makes the time-limited spells permanent; costs 1 intelligence and the spell is forgotten"] end,
}

function SpellInfo.risky(spell)
   return RISKY[spell] or false
end

-- The effect text and the short form (or nil) of the spell for the caster as they are now.
function SpellInfo.info(spell)
   local info = INFO[spell]
   if not info then return nil end
   return info(c[K.LEVEL])
end

-- The character level the spell needs (C: speldamage() checks level * 3 + 2 against the spell).
function SpellInfo.minLevel(spell)
   return math.max(0, math.ceil((spell - 3) / 3))
end
