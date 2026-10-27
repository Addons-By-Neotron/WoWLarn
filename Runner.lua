--[[
**********************************************************************
WoWLarn - Game thread and the UI request API.
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

-- The game logic runs in one coroutine (design.md section 4). Every blocking call
-- below yields until the UI delivers an answer, so ported C code reads like the C.
-- Never wrap game logic in pcall/xpcall: Lua 5.1 cannot yield across them.

local ESC = "ESC"
ns.ESC = ESC

local ui = {}
ns.ui = ui

-- C: main.c:parse. Direction numbers match the C (1 south, 2 east, 3 north, 4 west,
-- 5 northeast, 6 northwest, 7 southeast, 8 southwest).
local DIRECTION = {
   j = 1, l = 2, k = 3, h = 4, u = 5, y = 6, n = 7, b = 8,
   DOWN = 1, RIGHT = 2, UP = 3, LEFT = 4,
}
local ARROW_COMMAND = { UP = "k", DOWN = "j", LEFT = "h", RIGHT = "l" }

----------------------------------------------------------------
-- Coroutine plumbing
----------------------------------------------------------------

function ui:IsActive()
   return self.co ~= nil
end

function ui:NewGame()
   self.co = coroutine.create(ns.Game.Run)
   self.wait = nil
   ns.prompt:Clear()
   self:Resume()
end

-- Runs the game until it next waits for input (or ends).
function ui:Resume(...)
   local co = self.co
   if not co or coroutine.status(co) ~= "suspended" then return end
   self.wait = nil
   local ok, err = coroutine.resume(co, ...)
   if not ok then
      self.co = nil
      ns.prompt:Clear()
      self:Log("system", L["The game crashed. Press any key to start over."])
      geterrorhandler()(err)
   elseif coroutine.status(co) == "dead" then
      self.co = nil
      ns.prompt:Clear()
   end
end

-- The only input path: the keyboard, buttons and (later) clicks all end up here.
function ui:InjectKey(key)
   if self.wait == "key" then
      self:Resume(key)
   elseif not self.co then
      self:NewGame()
   end
   -- Otherwise the game is napping: input is dropped.
end

local function Wait(self, kind)
   self.wait = kind
   return coroutine.yield()
end

----------------------------------------------------------------
-- Output
----------------------------------------------------------------

function ui:Log(category, fmt, ...)
   ns.log:Add(select("#", ...) > 0 and format(fmt, ...) or fmt, category)
end

-- C: lprintf/lprcat to the message area.
function ui:Message(fmt, ...)
   self:Log("info", fmt, ...)
end

-- C: bottomline(), showcell(), draws(). Nothing to redraw until the map exists.
function ui:Refresh(what)
end

-- C: model animations for attacks, wounds, spells (milestone 4+).
function ui:Animate(event)
end

-- C: nap(). Pauses the game thread; "fast" mode skips it.
function ui:Nap(ms)
   if ms <= 0 or ns.mod.db.profile.fast then return end
   local co = self.co
   C_Timer.After(ms / 1000, function()
      if self.co == co and self.wait == "nap" then
         self:Resume()
      end
   end)
   Wait(self, "nap")
end

----------------------------------------------------------------
-- Input requests
----------------------------------------------------------------

function ui:GetKey()
   return Wait(self, "key")
end

-- C: yylex()/parse(). Returns the command character; Esc releases the keyboard.
function ui:GetCommand()
   while true do
      local key = self:GetKey()
      if key == ESC then
         ns.main:SetFocus(false)
      elseif ARROW_COMMAND[key] then
         return ARROW_COMMAND[key]
      elseif #key == 1 then
         return key
      end
   end
end

-- C: getyn(). Returns "y", "n" or ESC (Esc, space and enter all mean ESC).
function ui:YesNo(message)
   ns.prompt:Set(message .. " [y/n]", "yesno")
   local answer
   while not answer do
      local key = self:GetKey()
      if key == "y" or key == "Y" then
         answer = "y"
      elseif key == "n" or key == "N" then
         answer = "n"
      elseif key == ESC or key == " " or key == "ENTER" then
         answer = ESC
      end
   end
   ns.prompt:Clear()
   self:Log("prompt", "%s %s", message, answer == ESC and L["(cancelled)"] or answer)
   return answer
end

-- C: more()/retcont().
function ui:More()
   ns.prompt:Set(L["--- press space to continue ---"], "more")
   local key
   repeat key = self:GetKey() until key == " " or key == "ENTER"
   ns.prompt:Clear()
end

-- C: readnum(). '*' means all (max); Esc or space aborts with -1.
function ui:GetNumber(message, max)
   local digits, result = "", nil
   while not result do
      ns.prompt:Set(message .. " " .. digits)
      local key = self:GetKey()
      if key == "*" and digits == "" then
         result = max
      elseif key == "ENTER" then
         result = tonumber(digits) or 0
      elseif key == ESC or key == " " then
         result = -1
      elseif key == "BACKSPACE" then
         digits = digits:sub(1, -2)
      elseif key:match("^%d$") and #digits < 9 then
         digits = digits .. key
      end
   end
   ns.prompt:Clear()
   self:Log("prompt", "%s %s", message, result < 0 and L["(cancelled)"] or tostring(result))
   return result
end

-- C: dirsub()/direction questions. Returns 1..8, or nil if cancelled.
function ui:PickDirection(message)
   ns.prompt:Set(message .. " " .. L["(direction)"])
   local direction
   while not direction do
      local key = self:GetKey()
      direction = DIRECTION[key]
      if not direction and (key == ESC or key == " ") then
         break
      end
   end
   ns.prompt:Clear()
   return direction
end

-- Not needed until later milestones; fail loudly if something calls them early.
function ui:PickItem() error("ui:PickItem is not implemented yet (milestone 5)") end
function ui:PickSpell() error("ui:PickSpell is not implemented yet (milestone 6)") end
function ui:Store() error("ui:Store is not implemented yet (milestone 8)") end
