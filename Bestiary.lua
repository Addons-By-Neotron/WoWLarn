--[[
WoWLarn - the bestiary: the monsters seen so far, what they do and roughly how tough they are.
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

-- The bestiary: every monster the player has seen, in any game, with the level it was first
-- met on, the special attacks seen so far and rough figures for its hit points and damage.
-- It is kept in the saved variables (global.bestiary) and so builds up over the games.
-- [monster id] = { level = first dungeon level, kills = number killed, specials = { [attack] = true },
--    hurt = true once it has damaged the player, blocked = the highest armor class it did nothing against }
local Bestiary = {}
ns.Bestiary = Bestiary

local session = {}
local function Entries()
   return ns.mod and ns.mod.db and ns.mod.db.global.bestiary or session
end

-- What a special attack is called, by the number of the C (spattack).
local SPECIAL = {
   [1] = L["Corrodes armor"],
   [2] = L["Breathes fire"],
   [3] = L["Breathes fire"],
   [4] = L["Curses your strength"],
   [5] = L["Breathes cold"],
   [6] = L["Drains your levels"],
   [7] = L["Drenches you with a gusher"],
   [8] = L["Steals gold"],
   [9] = L["Disenchants your gear"],
   [10] = L["Hits with a barbed tail"],
   [11] = L["Confuses you"],
   [12] = L["Casts spells"],
   [13] = L["Blasts you with psionics"],
   [14] = L["Steals your things"],
   [15] = L["Bites hard"],
   [16] = L["Steals your gear"],
}

-- A game that has had cheats on does not add to it.
local function Counts()
   return not (G.wizard or G.cheated)
end

function Bestiary.entry(id)
   return Entries()[id]
end

-- A monster is in view.
function Bestiary.see(id)
   local entries = Entries()
   if entries[id] or not Counts() or not G.level then return end
   entries[id] = { level = G.level, kills = 0, specials = {} }
end

-- A special attack of the monster has happened.
function Bestiary.special(id, attack)
   local entry = Entries()[id]
   if entry and Counts() and attack and SPECIAL[attack] then entry.specials[attack] = true end
end

-- The monster has hit the player, for damage (after the armor class ac took its share).  Its
-- damage is only known to the bestiary once it has hurt: before that, all it knows is that the
-- armor stopped it, so it did less than that.
function Bestiary.hit(id, damage, ac)
   local entry = Entries()[id]
   if not entry or not Counts() then return end
   if damage > 0 then
      entry.hurt = true
   else
      entry.blocked = math.max(entry.blocked or 0, ac)
   end
end

function Bestiary.kill(id)
   local entry = Entries()[id]
   if entry and Counts() then entry.kills = entry.kills + 1 end
end

-- The special attacks seen, as a list of names; and whether the monster has others to find.
function Bestiary.specials(id)
   local entry, names, listed = Entries()[id], {}, {}
   for attack in pairs(entry and entry.specials or {}) do
      if not listed[SPECIAL[attack]] then  -- (two attacks can have the same name)
         listed[SPECIAL[attack]] = true
         names[#names + 1] = SPECIAL[attack]
      end
   end
   table.sort(names)
   local data = ns.MonsterData[id]
   return names, data.attack > 0 and #names == 0
end

-- The monsters seen, from the weakest.
function Bestiary.list()
   local list = {}
   for id in pairs(Entries()) do
      if ns.MonsterData[id] then list[#list + 1] = id end
   end
   table.sort(list)
   return list
end

function Bestiary.count()
   return #Bestiary.list()
end

-- The monster as it is in this game (the difficulty changes it), or as it is by default.
local function Stats(id)
   return (G.monster and G.monster[id]) or ns.MonsterData[id]
end

-- A range around a value, not exact: the more of its kind have been killed, the closer it
-- is.  The range is moved a little, by the monster, so the middle of it gives nothing away.
local function Estimate(value, id, kills)
   if value <= 0 then return 0, 0 end
   local spread = math.max(0.1, 0.5 - 0.05 * kills)
   local shift = ((id * 7919) % 100 / 100 - 0.5) * spread
   local low, high = value * (1 - spread + shift), value * (1 + spread + shift)
   local step = high >= 100 and 10 or high >= 20 and 5 or 1
   low = math.max(1, math.floor(low / step) * step)
   high = math.max(low, math.ceil(high / step) * step)
   return low, high
end

-- About how many hit points the monster has: low, high.
function Bestiary.health(id)
   local entry = Entries()[id]
   return Estimate(Stats(id).hitpoints, id, entry and entry.kills or 0)
end

-- About how much one hit does to the player with the armor class worn now (the damage of
-- Monster.hitplayer, less the armor class): low, high; 0, 0 if it can not hurt.  What the
-- special attacks do is not in it.
function Bestiary.damage(id, ac)
   local data = Stats(id)
   local low = math.max(0, data.damage + 1 + data.level - ac)
   local high = math.max(0, data.damage + math.max(data.damage, 1) + data.level - ac)
   if high == 0 then return 0, 0 end
   local entry = Entries()[id]
   local kills = entry and entry.kills or 0
   local lowest = Estimate(math.max(low, 1), id, kills)
   local _, highest = Estimate(high, id, kills)
   return low == 0 and 0 or lowest, highest
end
