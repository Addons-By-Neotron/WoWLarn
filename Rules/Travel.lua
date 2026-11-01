--[[
**********************************************************************
WoWLarn - Standing on objects (object.c). items, traps, stairs, entrance and shafts so far.
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

-- Walks to a place the player has already found (stairs, shops, altars...), by the shortest
-- way over the ground that is on the map. Not in the C. The walk stops for anything the
-- player should look at: a monster, a hit, a new object coming into view, a trap or any
-- object on the way.
local Travel = {}
ns.Travel = Travel

local c, item, know, mon = G.c, G.item, G.know, G.mon
local MAXX, MAXY = K.MAXX, K.MAXY
local DIROFFX, DIROFFY = ns.Display.DIROFFX, ns.Display.DIROFFY
local STEP_DELAY = 30  -- milliseconds between steps, as for a run
local MAX_ROWS = 26

-- The places on the list, and what the list calls them (the exit from level 1 is a tile, not an object).
local EXIT = -1
local SPOT
local function Spots()
   if SPOT then return SPOT end
   SPOT = {
      [K.OSTAIRSUP] = L["Stairs up"],
      [K.OSTAIRSDOWN] = L["Stairs down"],
      [K.OELEVATORUP] = L["Elevator up"],
      [K.OELEVATORDOWN] = L["Elevator down"],
      [K.OVOLUP] = L["Volcano shaft up"],
      [K.OVOLDOWN] = L["Volcano shaft down"],
      [K.OENTRANCE] = L["Dungeon entrance"],
      [K.OHOME] = L["Home"],
      [K.OSCHOOL] = L["College of Ularn"],
      [K.OBANK] = L["Bank of Ularn"],
      [K.OBANK2] = L["Bank of Ularn"],
      [K.ODNDSTORE] = L["Thrift Shoppe"],
      [K.OTRADEPOST] = L["Trading post"],
      [K.OLRS] = L["Revenue Service"],
      [K.OALTAR] = L["Altar"],
      [K.OFOUNTAIN] = L["Fountain"],
      [K.OTHRONE] = L["Throne"],
      [K.OTHRONE2] = L["Throne"],
      [K.OMIRROR] = L["Mirror"],
      [K.OSTATUE] = L["Statue"],
      [EXIT] = L["Dungeon exit"],
   }
   return SPOT
end

-- What is on the map as a trap. The hidden ones are not: the player has not found them.
local TRAP = {
   [K.OTRAPARROW] = true, [K.ODARTRAP] = true, [K.OTRAPDOOR] = true, [K.OPIT] = true,
   [K.OTELEPORTER] = true,
}
local HIDDEN = {
   [K.OTRAPARROWIV] = true, [K.OIVDARTRAP] = true, [K.OIVTRAPDOOR] = true, [K.OIVTELETRAP] = true,
}

-- The object the player can tell is on a tile; 0 for none (hidden traps count as none).
local function Seen(x, y)
   local id = item[x][y]
   if HIDDEN[id] then return 0 end
   return id
end

-- True if the player knows of a trap or a pit on the tile.
function Travel.knownTrap(x, y)
   return TRAP[item[x][y]] == true
end

local function Remembered(x, y)
   return ns.Display.remembered(x, y)
end

-- True if a monster the player can see is on the tile.
local function SeesMonster(x, y)
   return mon[x][y] ~= 0 and know[x][y] ~= 0 and ns.Display.visibleMonster(x, y) ~= 0
end

-- What a step costs: 1 on open ground. The path is the cheapest, so it goes round whatever costs
-- more when there is a way, and through it when there is not.
local COST = {
   door = 8,     -- a closed door: the question, and it may be stuck
   object = 25,  -- an object: the walk stops on it
   trap = 60,    -- a trap that is known: the walk stops in front of it
}

-- The cheapest ways from the player over the ground on the map (monsters do not count: after
-- magic mapping all of them are on the map, and the walk stops when one is near anyway).
-- Returns the cost to each tile (cost[x][y]), the direction taken to enter it and the number of
-- steps to it.
local function Flood()
   local cost, how, steps = {}, {}, {}
   for x = 1, MAXX do cost[x], how[x], steps[x] = {}, {}, {} end
   local buckets = { [0] = { { G.playerx, G.playery } } }
   cost[G.playerx][G.playery], steps[G.playerx][G.playery] = 0, 0
   local last = 0
   local d = 0
   while d <= last do
      for _, tile in ipairs(buckets[d] or {}) do
         local px, py = tile[1], tile[2]
         if cost[px][py] == d then  -- (not one that was reached more cheaply since)
            for dir = 1, 8 do
               local x, y = px + DIROFFX[dir], py + DIROFFY[dir]
               if x >= 1 and x <= MAXX and y >= 1 and y <= MAXY
                  and Seen(x, y) ~= K.OWALL and Remembered(x, y) then
                  local step = 1
                  local here = Seen(x, y)
                  if TRAP[item[x][y]] then
                     step = step + COST.trap
                  elseif here == K.OCLOSEDDOOR then
                     step = step + COST.door
                  elseif here ~= 0 and here ~= K.OOPENDOOR then
                     step = step + COST.object
                  end
                  local total = d + step
                  if not cost[x][y] or total < cost[x][y] then
                     cost[x][y], how[x][y], steps[x][y] = total, dir, steps[px][py] + 1
                     buckets[total] = buckets[total] or {}
                     table.insert(buckets[total], { x, y })
                     if total > last then last = total end
                  end
               end
            end
         end
      end
      d = d + 1
   end
   return cost, how, steps
end

-- The places on the map the player can walk to, in the order of their names:
-- { x =, y =, id =, name =, steps = }, by name (the order stays put as you walk about)
function Travel.list()
   local cost, _, steps = Flood()
   local names, list = Spots(), {}
   for x = 1, MAXX do
      for y = 1, MAXY do
         local id = Seen(x, y)
         if id == 0 and G.level == 1 and x == 34 and y == MAXY then id = EXIT end  -- (the way out has no object)
         if names[id] and (x ~= G.playerx or y ~= G.playery) and Remembered(x, y) and cost[x][y] then
            local label = names[id]
            local ride = G.elevators[G.level * 10000 + x * 100 + y]  -- (where it took you last time)
            if id == K.OSTAIRSUP and G.level == K.DBOTTOM + 1 then label = label .. " " .. L["(a dead end)"] end  -- (the stairs up on V1 lead nowhere)
            if ride and (id == K.OELEVATORUP or id == K.OELEVATORDOWN) then
               label = label .. " " .. string.format(L["to floor %s"], ns.Tables.levelname[ride + 1])
            end
            list[#list + 1] = { x = x, y = y, id = id, name = names[id], label = label, steps = steps[x][y] }
         end
      end
   end
   table.sort(list, function(a, b)
      if a.name ~= b.name then return a.name < b.name end
      if a.steps ~= b.steps then return a.steps < b.steps end
      if a.x ~= b.x then return a.x < b.x end
      return a.y < b.y
   end)
   for i = #list, MAX_ROWS + 1, -1 do list[i] = nil end
   return list
end

-- The direction of the first step towards a tile, or nil if there is no way.
local function NextStep(tx, ty)
   local cost, how, steps = Flood()
   if not cost[tx][ty] then return nil end
   local x, y = tx, ty
   while steps[x][y] > 1 do
      local dir = how[x][y]
      x, y = x - DIROFFX[dir], y - DIROFFY[dir]
   end
   return how[x][y], x, y
end

-- True if a monster the player can see is within two steps, going round walls: one on the other
-- side of a wall can not get at the player, so it does not count.
local function MonsterNear()
   local reached = { [G.playerx * 100 + G.playery] = true }
   local front = { { G.playerx, G.playery } }
   for _ = 1, 2 do
      local nextFront = {}
      for _, tile in ipairs(front) do
         for dir = 1, 8 do
            local x, y = tile[1] + DIROFFX[dir], tile[2] + DIROFFY[dir]
            if x >= 1 and x <= MAXX and y >= 1 and y <= MAXY and not reached[x * 100 + y]
               and (item[x][y] ~= K.OWALL or c[K.WTW] ~= 0) then
               reached[x * 100 + y] = true
               if SeesMonster(x, y) then return true end
               nextFront[#nextFront + 1] = { x, y }
            end
         end
      end
      front = nextFront
   end
   return false
end

Travel.monsterNear = MonsterNear

-- Walks to the tile, one step at a time, with the monsters moving as in a run. Stops on
-- the first object it steps on (the game then deals with it, as for any step), but goes on
-- through doors.
function Travel.go(tx, ty)
   local ui, Display, Monster = ns.ui, ns.Display, ns.Monster
   local level = G.level
   while G.playerx ~= tx or G.playery ~= ty do
      if MonsterNear() then
         ui:Message(L["You stop: a monster is near."])
         return
      end
      local dir, nx, ny = NextStep(tx, ty)
      if not dir then
         ui:Message(L["You see no way to go on."])
         return
      end
      if TRAP[item[nx][ny]] and (nx ~= tx or ny ~= ty) then  -- (no way round it)
         ui:Message(L["You stop: there is a trap in the way."])
         return
      end
      local fromx, fromy = G.playerx, G.playery
      Display.moveplayer(dir)
      if G.playerx == fromx and G.playery == fromy then  -- (a wall, or a monster that was hit)
         local blocked = mon[fromx + DIROFFX[dir]][fromy + DIROFFY[dir]] ~= 0
         ui:Message(blocked and L["You stop: something is in the way."] or L["You stop: the way is blocked."])
         return
      end
      G.nomove = false  -- the step takes a turn
      if c[K.HASTEMONST] ~= 0 then Monster.movemonst() end
      Monster.movemonst()
      Monster.randMonst()
      ns.Regen.regen()
      if G.dead then return end
      if G.level ~= level then return end  -- (a trap door, or a teleport)
      if G.hitflag then
         ui:Message(L["You stop: you were hit."])
         return
      end
      Display.showcell(G.playerx, G.playery)
      local here = item[G.playerx][G.playery]
      if (here == K.OCLOSEDDOOR and (G.playerx ~= tx or G.playery ~= ty)) or HIDDEN[here] then
         -- a door (the prompt to open it), or a trap nobody knew of: deal with it here, and go on
         local x, y = G.playerx, G.playery
         ns.Object.lookForObject()
         G.lookedHere = G.playerx .. "," .. G.playery .. "," .. G.level
         if G.dead or G.level ~= level then return end
         if G.playerx ~= x or G.playery ~= y then
            ui:Message(here == K.OCLOSEDDOOR and L["You stop: the door is shut."] or L["You stop: you were moved."])
            return
         end
         if G.hitflag then
            ui:Message(L["You stop: you were hit."])
            return
         end
      elseif here ~= 0 and here ~= K.OOPENDOOR then
         if G.playerx ~= tx or G.playery ~= ty then
            ui:Message(L["You stop: there is something here."])
         end
         return
      end
      ui:Nap(STEP_DELAY)
   end
end

-- The command: lists the places found, and walks to the one picked.
function Travel.command()
   local ui, store = ns.ui, ns.store
   local list = Travel.list()
   if #list == 0 then
      ui:Message(L["You know of no place to go to."])
      return
   end
   local rows = {}
   for index, spot in ipairs(list) do
      rows[index] = {
         key = string.char(96 + index), text = spot.label, icon = spot.id,
         price = string.format(L["%d steps"], spot.steps),
      }
   end
   store:Open(L["Go to"], L["Pick a place you have found.  You walk there on the shortest way, and stop for monsters, traps and anything new."], 2)
   store:SetRows(rows)
   ns.prompt:Set(L["Where to? [escape to stay]"])
   local key
   repeat
      key = ui:GetKey()
   until key == ns.ESC or (#key == 1 and list[key:byte() - 96])
   ns.prompt:Clear()
   store:Close()
   ui:Refresh("all")
   if key ~= ns.ESC then
      local spot = list[key:byte() - 96]
      Travel.go(spot.x, spot.y)
   end
end
