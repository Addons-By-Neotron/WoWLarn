--[[
**********************************************************************
WoWLarn - Monster movement (movem.c). Arrives in milestone 4.
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

local Monster = {}
ns.Monster = Monster

-- C: movemonst(). No monsters exist yet.
function Monster.movemonst()
end

-- C: randmonst(). Random monster creation arrives with the monsters.
function Monster.randmonst()
end

-- C: hitmonster(). Combat arrives in milestone 4.
function Monster.hitmonster(x, y)
   error("Monster.hitmonster is not implemented yet (milestone 4)")
end

-- C: the rmst counter in main(): fillmonst(makemonst(level)).
function Monster.spawnRandom()
end
