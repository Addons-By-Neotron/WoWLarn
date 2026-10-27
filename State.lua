--[[
**********************************************************************
WoWLarn - Game state (the C globals).
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
local MAXX, MAXY = K.MAXX, K.MAXY

-- All of the game state lives in this one table. The arrays are allocated once and
-- reset in place, so modules may keep local references to G.c, G.item and so on.
-- Coordinates are 1-based (x 1..MAXX, y 1..MAXY); arrays are indexed [x][y].
-- Level numbers are values 0..20; per-level storage is indexed [level + 1].
local G = {}
ns.G = G

local LEVEL_GRIDS = { "item", "iarg", "know", "hitp", "mon", "stealth" }

local function Grid()
   local grid = {}
   for x = 1, MAXX do
      local column = {}
      for y = 1, MAXY do column[y] = 0 end
      grid[x] = column
   end
   return grid
end

local function FillGrid(grid, value)
   for x = 1, MAXX do
      local column = grid[x]
      for y = 1, MAXY do column[y] = value end
   end
end

local function CopyGrid(from, to)
   for x = 1, MAXX do
      local source, target = from[x], to[x]
      for y = 1, MAXY do target[y] = source[y] end
   end
end

local function CopyLoot(from)
   local to = {}
   for key, list in pairs(from or {}) do
      local copy = {}
      for i, entry in ipairs(list) do copy[i] = { entry[1], entry[2] } end
      to[key] = copy
   end
   return to
end

local function FillArray(array, count, value)
   for i = 1, count do array[i] = value end
end

G.c = {}            -- character attributes, indexed by the constants in player.h
G.cbak = {}
G.iven = {}         -- inventory item types, 1..IVENSIZE (0 = empty slot)
G.ivenarg = {}      -- inventory item arguments
G.spelknow = {}     -- 1..SPNUM
G.scrollknown = {}  -- 1..MAXSCROLL
G.potionknown = {}  -- 1..MAXPOTION
G.loot = {}         -- items carried by the monsters, [x * 100 + y] = { { id, arg }, ... } (C: mitem[][].it)
G.levels = {}       -- saved levels, [level + 1]
G.visited = {}      -- [level + 1] = true once a level has been made
for _, name in ipairs(LEVEL_GRIDS) do
   G[name] = Grid()
end
-- item[x][y]    object on the tile        iarg[x][y]  its argument
-- know[x][y]    nonzero once seen         hitp[x][y]  monster hit points
-- mon[x][y]     monster id (C: mitem[x][y].mon)
-- stealth[x][y] nonzero if the monster there is awake

function G.Reset()
   FillArray(G.c, 100, 0)
   FillArray(G.cbak, 100, 0)
   FillArray(G.iven, K.IVENSIZE, 0)
   FillArray(G.ivenarg, K.IVENSIZE, 0)
   FillArray(G.spelknow, K.SPNUM, 0)
   G.spheres = {}  -- the spheres of annihilation of every level, newest first
   FillArray(G.scrollknown, K.MAXSCROLL, 0)
   FillArray(G.potionknown, K.MAXPOTION, 0)
   G.potionknown[K.PINSTHEAL] = 1  -- the only potion known from the start
   for _, name in ipairs(LEVEL_GRIDS) do
      FillGrid(G[name], 0)
   end
   G.levels, G.visited = {}, {}
   G.loot = {}
   G.monster = nil      -- per-game copy of ns.MonsterData, made by Monster.init
   G.lastmonst = ""     -- name of the monster last hit (C: lastmonst)
   G.lasthx, G.lasthy = 1, 1  -- where the player last hit a monster
   G.level = 0
   G.playerx, G.playery = 1, 1
   G.lastpx, G.lastpy = 1, 1
   G.gtime = 0
   G.wizard = false
   G.dead = false       -- set by Player.died
   G.lastnum = 0        -- cause of the last damage, for the scoreboard
   G.hitflag, G.hit2flag, G.hit3flag = false, false, false
   G.nomove, G.dropflag, G.viewflag = false, false, false
   G.rmst = 80          -- random monster creation counter
   G.name, G.sex, G.class = "", 1, nil
   G.gemsSold = {}  -- the gem kinds that have been sold (their worth is not shown before)
   G.stock, G.course, G.drug = nil, {}, {}  -- DND stock, school courses and elixirs bought
   G.taxes, G.lastBank, G.ramboflag = 0, 0, false
end

function G.Visited(level)
   return G.visited[level + 1] == true
end

function G.SetVisited(level)
   G.visited[level + 1] = true
end

-- C: savelevel(). Copies the live level into storage.
function G.SaveLevel()
   local saved = G.levels[G.level + 1]
   if not saved then
      saved = {}
      for _, name in ipairs(LEVEL_GRIDS) do saved[name] = Grid() end
      G.levels[G.level + 1] = saved
   end
   for _, name in ipairs(LEVEL_GRIDS) do
      CopyGrid(G[name], saved[name])
   end
   saved.loot = CopyLoot(G.loot)
end

-- C: getlevel(). Copies a stored level back into the live arrays.
function G.GetLevel()
   local saved = G.levels[G.level + 1]
   for _, name in ipairs(LEVEL_GRIDS) do
      CopyGrid(saved[name], G[name])
   end
   G.loot = CopyLoot(saved.loot)
end

function G.ClearLevel()
   for _, name in ipairs(LEVEL_GRIDS) do
      FillGrid(G[name], 0)
   end
   G.loot = {}
end

function G.FillKnow(value)
   FillGrid(G.know, value)
end

function G.FillStealth(value)
   FillGrid(G.stealth, value)
end

G.Reset()
