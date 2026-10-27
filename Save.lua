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
local _, ns = ...
local K = ns.K
local G = ns.G

-- Saving and resuming the game (C: savelev.c, savegame/restoregame). The game lives in G
-- all the time; this copies it into WoWLarnDB.char.game when the player logs out or hides
-- the window, and back when a new session starts. WoW only writes the saved variables when
-- the player logs out or reloads, so a crash loses what happened since then.
local Save = {}
ns.Save = Save

local VERSION = 1
local MAXX, MAXY = K.MAXX, K.MAXY
local GRIDS = { "item", "iarg", "know", "hitp", "mon", "stealth" }
-- The plain values of G (numbers, strings, booleans) that are part of a game.
local SCALARS = {
   "level", "playerx", "playery", "lastpx", "lastpy", "lasthx", "lasthy", "gtime", "wizard", "lastnum",
   "lastmonst", "facing", "rmst", "name", "sex", "lastBank", "ramboflag",
}
-- The tables of G that are copied as they are.
local TABLES = {
   "c", "cbak", "iven", "ivenarg", "spelknow", "scrollknown", "potionknown", "visited", "spheres",
   "stock", "course", "drug", "monster", "gemsSold",
}

local function Copy(value)
   if type(value) ~= "table" then return value end
   local copy = {}
   for key, entry in pairs(value) do copy[key] = Copy(entry) end
   return copy
end

-- A grid as one string per column: "12,0,4,...".
local function PackGrid(grid)
   local columns = {}
   for x = 1, MAXX do
      columns[x] = table.concat(grid[x], ",", 1, MAXY)
   end
   return columns
end

local function UnpackGrid(columns, grid)
   for x = 1, MAXX do
      local y = 0
      for number in columns[x]:gmatch("-?%d+") do
         y = y + 1
         grid[x][y] = tonumber(number)
      end
   end
end

local function PackLevel(level)
   local packed = { loot = Copy(level.loot) }
   for _, name in ipairs(GRIDS) do packed[name] = PackGrid(level[name]) end
   return packed
end

-- Makes the table that is stored: everything in G that makes up the game.
function Save.pack()
   G.SaveLevel()  -- the level being played goes into G.levels too
   local data = { version = VERSION, class = G.class and G.class.letter }
   for _, name in ipairs(SCALARS) do data[name] = G[name] end
   for _, name in ipairs(TABLES) do data[name] = Copy(G[name]) end
   data.levels = {}
   for index, level in pairs(G.levels) do data.levels[index] = PackLevel(level) end
   return data
end

-- Puts a stored game back into G. Returns false if it can not be used.
function Save.unpack(data)
   if type(data) ~= "table" or data.version ~= VERSION or not data.class then return false end
   local class
   for _, entry in ipairs(ns.Classes) do
      if entry.letter == data.class then class = entry end
   end
   if not class then return false end

   G.Reset()
   G.class = class
   for _, name in ipairs(SCALARS) do G[name] = data[name] end
   for _, name in ipairs({ "c", "cbak", "iven", "ivenarg", "spelknow", "scrollknown", "potionknown" }) do
      for index, value in pairs(data[name]) do G[name][index] = value end
   end
   for _, name in ipairs({ "visited", "spheres", "stock", "course", "drug", "monster", "gemsSold" }) do
      G[name] = Copy(data[name])
   end
   G.gemsSold = G.gemsSold or {}  -- (saves from before this was kept)
   G.levels = {}
   for index, packed in pairs(data.levels) do
      local level = { loot = Copy(packed.loot) }
      for _, name in ipairs(GRIDS) do
         level[name] = {}
         for x = 1, MAXX do level[name][x] = {} end
         UnpackGrid(packed[name], level[name])
      end
      G.levels[index] = level
   end
   G.GetLevel()
   return true
end

local function Char()
   return ns.mod.db.char
end

-- Stores the game in the saved variables. Does nothing if there is no game being played.
function Save.store()
   if not G.class or G.dead or not ns.ui:IsActive() then return end
   Char().game = Save.pack()
end

function Save.clear()
   Char().game = nil
end

function Save.exists()
   return Char().game ~= nil
end

-- Loads the stored game; returns true if there was one.
function Save.load()
   local data = Char().game
   if not data then return false end
   if Save.unpack(data) then return true end
   Char().game = nil  -- (made by another version: it can not be used)
   return false
end
