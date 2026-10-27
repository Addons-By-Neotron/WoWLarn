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
ui.repcount = 0  -- C: yrepcount, a repeat count typed before a command
ui.dirty = {}

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
   self:Flush()
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

-- C: bottomline(), showcell(), draws(). what is "map", "stats" or "all". Redraws are
-- batched and happen when the game thread next waits.
function ui:Refresh(what)
   if what == "all" then
      self.dirty.map, self.dirty.stats, self.dirty.inv = true, true, true
   else
      self.dirty[what] = true
   end
end

function ui:Flush()
   local dirty = self.dirty
   if dirty.map then
      dirty.map = nil
      ns.map:Draw()
      ns.side:UpdateMinimap()
   end
   if dirty.stats then
      dirty.stats = nil
      ns.side:UpdateStats()
   end
   if dirty.inv then
      dirty.inv = nil
      ns.inventory:Update()
   end
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

-- C: yylex(). Returns the command character. Digits typed first set a repeat count, the
-- command then repeats; game code sets ui.repcount = 0 to cancel (a hit, a wall).
-- Esc releases the keyboard.
function ui:GetCommand()
   local G = ns.G
   if G.hit2flag then
      G.hit2flag = false
      self.repcount = 0
      return " "
   end
   if self.repcount > 0 then
      self.repcount = self.repcount - 1
      return self.lastok
   end
   self.repcount = 0

   while true do
      local key = self:GetKey()
      if key == ESC then
         ns.main:SetFocus(false)
      else
         key = ARROW_COMMAND[key] or key
         if #key == 1 then
            if key:match("^%d$") then
               self.repcount = self.repcount * 10 + tonumber(key)
            else
               if self.repcount > 0 then
                  self.repcount = self.repcount - 1
               end
               self.lastok = key
               return key
            end
         end
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

-- C: the "(g) go inside, or (i) ignore it?" prompts. keys is a string of the accepted
-- lowercase letters; "i" and Esc always ignore. Returns the key, "i" for Esc.
function ui:Choose(message, keys)
   ns.prompt:Set(message, nil)
   local answer
   while not answer do
      local key = self:GetKey()
      if key == ESC then
         answer = "i"
      elseif #key == 1 and (key == "i" or keys:find(key, 1, true)) then
         answer = key
      end
   end
   ns.prompt:Clear()
   self:Log("prompt", "%s %s", message, answer)
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

-- C: pick_char(). Returns the chosen entry of classes (keyed by its letter, or Enter for
-- the highlighted one; the arrow keys move the highlight).
function ui:PickClass(classes, selected)
   ns.picker:Show(classes, selected)
   local result
   while not result do
      local key = self:GetKey()
      for index, class in ipairs(classes) do
         if key == class.letter then
            result = class
         end
      end
      if key == "ENTER" then
         result = classes[selected]
      elseif key == "UP" then
         selected = selected > 1 and selected - 1 or #classes
         ns.picker:Select(selected)
      elseif key == "DOWN" then
         selected = selected < #classes and selected + 1 or 1
         ns.picker:Select(selected)
      end
   end
   ns.picker:Hide()
   return result
end

-- Not needed until later milestones; fail loudly if something calls them early.
-- C: whatitem(). Opens the inventory with the valid items marked and waits for a slot.
-- Returns the slot (1..26), "gold" for '.' and "none" for '-' when opts allows them, or
-- nil if the player cancelled.
function ui:PickItem(verb, filter, opts)
   opts = opts or {}
   local extra = (opts.gold and L[", . for gold"] or "") .. (opts.none and L[", - for none"] or "")
   ns.inventory:Open(format(L["What do you want to %s?"], verb), filter)
   ns.prompt:Set(format(L["What do you want to %s? [a-z, * for all%s]"], verb, extra))
   local result
   while result == nil do
      local key = self:GetKey()
      if key == ESC or key == " " or key == "ENTER" then
         result = false
      elseif #key == 1 and key >= "a" and key <= "z" then
         result = key:byte() - 96
      elseif key == "*" then
         ns.inventory:Open(format(L["What do you want to %s?"], verb), nil)
      elseif key == "." and opts.gold then
         result = "gold"
      elseif key == "-" and opts.none then
         result = "none"
      end
   end
   ns.prompt:Clear()
   ns.inventory:Close()
   if result == false then
      self:Log("prompt", L["%s aborted."], verb)
      return nil
   end
   return result
end

-- C: showstr(). Shows the inventory until a key is pressed.
function ui:ShowInventory()
   ns.inventory:Open(L["Inventory"], nil)
   ns.prompt:Set(L["Press any key to close the inventory"])
   self:GetKey()
   ns.prompt:Clear()
   ns.inventory:Close()
end
function ui:PickSpell() error("ui:PickSpell is not implemented yet (milestone 6)") end
function ui:Store() error("ui:Store is not implemented yet (milestone 8)") end
