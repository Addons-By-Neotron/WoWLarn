--[[
**********************************************************************
WoWLarn - Random numbers and C integer arithmetic.
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

local random, floor = math.random, math.floor

-- C: rnd(x) is 1..x, rund(x) is 0..x-1 (header.h).
function ns.rnd(x)
   return random(x)
end

function ns.rund(x)
   return random(0, x - 1)
end

-- C: vxy(). Keeps a coordinate on the level (the C runs 0..MAXX-1, here 1..MAXX).
function ns.vxy(x, y)
   local K = ns.K
   return math.max(1, math.min(K.MAXX, x)), math.max(1, math.min(K.MAXY, y))
end

-- C integer division truncates toward zero.
function ns.idiv(a, b)
   local quotient = a / b
   if quotient >= 0 then return floor(quotient) end
   return -floor(-quotient)
end

-- C remainder takes the sign of the dividend.
function ns.cmod(a, b)
   return a - b * ns.idiv(a, b)
end
