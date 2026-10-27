--[[
**********************************************************************
WoWLarn - Message log.
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

local log = {}
ns.log = log

local CATEGORY_COLOR = {
   info = { 0.9, 0.9, 0.9 },
   system = { 1, 0.82, 0 },
   combat = { 1, 0.45, 0.4 },
   damage = { 1, 0.2, 0.2 },
   loot = { 0.4, 0.9, 0.4 },
   magic = { 0.5, 0.7, 1 },
   prompt = { 0.7, 0.7, 0.7 },
}

local function Colorize(text, category)
   local c = CATEGORY_COLOR[category] or CATEGORY_COLOR.info
   local color = format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
   -- an item link ends its own colour, so carry on with the colour of the message after it
   return color .. text:gsub("|r", "|r" .. color) .. "|r"
end

function log:Create(parent)
   local frame = CreateFrame("ScrollingMessageFrame", nil, parent)
   frame:SetFontObject(ChatFontNormal or GameFontNormal)
   frame:SetJustifyH("LEFT")
   frame:SetMaxLines(1000)
   frame:SetFading(false)
   frame:SetInsertMode("BOTTOM")
   frame:EnableMouseWheel(true)
   frame:SetScript("OnMouseWheel", function(self, delta)
      if IsShiftKeyDown() then
         if delta > 0 then self:PageUp() else self:PageDown() end
      elseif delta > 0 then
         self:ScrollUp()
      else
         self:ScrollDown()
      end
   end)
   -- [Item] links: the tooltip says what it is
   frame:SetHyperlinksEnabled(true)
   frame:SetScript("OnHyperlinkEnter", function(self, link)
      local id, arg = link:match("^wowlarn:(%-?%d+):(%-?%d+)$")
      if not id then return end
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      ns.ItemInfo.tooltip(tonumber(id), tonumber(arg))
   end)
   frame:SetScript("OnHyperlinkLeave", GameTooltip_Hide)
   self.frame = frame
   -- Anything logged before the window existed.
   for _, entry in ipairs(self.backlog or {}) do
      frame:AddMessage(entry)
   end
   self.backlog = nil
   return frame
end

function log:Add(text, category)
   local line = Colorize(text, category)
   if self.frame then
      self.frame:AddMessage(line)
   else
      self.backlog = self.backlog or {}
      self.backlog[#self.backlog + 1] = line
   end
end

function log:PageUp()
   if self.frame then self.frame:PageUp() end
end

function log:PageDown()
   if self.frame then self.frame:PageDown() end
end
