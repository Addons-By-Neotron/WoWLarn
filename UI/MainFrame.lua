--[[
**********************************************************************
WoWLarn - Main window, layout, focus and keyboard capture.
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

local main = {}
ns.main = main

local FRAME_NAME = "WoWLarnFrame"
local WIDTH, HEIGHT = 976, 712
local TITLE_H, SIDE_W, BOTTOM_H, PAD = 22, 240, 170, 6

-- WoW key names the game needs; printable characters arrive through OnChar.
local KEYMAP = {
   ESCAPE = ns.ESC, ENTER = "ENTER", BACKSPACE = "BACKSPACE",
   UP = "UP", DOWN = "DOWN", LEFT = "LEFT", RIGHT = "RIGHT",
}

local ARROWS = { UP = true, DOWN = true, LEFT = true, RIGHT = true }

local function SavePosition(frame)
   local point, _, _, x, y = frame:GetPoint()
   local window = ns.mod.db.profile.window
   window.point, window.x, window.y = point, x, y
end

local function ApplyPosition(frame)
   local window = ns.mod.db.profile.window
   frame:ClearAllPoints()
   frame:SetPoint(window.point, UIParent, window.point, window.x, window.y)
end

function main:Create()
   if self.frame then return self.frame end
   local frame = ns.CreatePanel(UIParent, FRAME_NAME)
   frame:SetSize(WIDTH, HEIGHT)
   frame:SetFrameStrata("DIALOG")
   frame:SetClampedToScreen(true)
   frame:SetMovable(true)
   frame:EnableMouse(true)
   frame:Hide()
   self.frame = frame
   self:ApplyScale()
   ApplyPosition(frame)
   tinsert(UISpecialFrames, FRAME_NAME)

   -- Title bar: drag handle, focus hint and close button.
   local title = CreateFrame("Frame", nil, frame)
   title:SetPoint("TOPLEFT")
   title:SetPoint("TOPRIGHT")
   title:SetHeight(TITLE_H)
   title:EnableMouse(true)
   title:RegisterForDrag("LeftButton")
   title:SetScript("OnDragStart", function() frame:StartMoving() end)
   title:SetScript("OnDragStop", function()
      frame:StopMovingOrSizing()
      SavePosition(frame)
   end)
   title:SetScript("OnMouseDown", function() self:SetFocus(true) end)
   local name = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   name:SetPoint("LEFT", 8, 0)
   name:SetText("WoWLarn")
   self.hint = title:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   self.hint:SetPoint("CENTER")
   local close = CreateFrame("Button", nil, title, "UIPanelCloseButton")
   close:SetPoint("RIGHT", 2, 0)
   close:SetScript("OnClick", function() self:Hide() end)
--@debug@
   local debug = CreateFrame("Button", nil, title, "UIPanelButtonTemplate")
   debug:SetSize(54, 18)
   debug:SetPoint("RIGHT", close, "LEFT", -2, 0)
   debug:SetText("Debug")
   debug:SetScript("OnClick", function() ns.debugPanel:Toggle() end)
--@end-debug@

   -- Regions.
   local map = ns.map:Create(frame)
   map:SetPoint("TOPLEFT", PAD, -(TITLE_H + PAD))
   map:SetPoint("BOTTOMRIGHT", -(SIDE_W + 2 * PAD), BOTTOM_H + 2 * PAD)

   ns.picker:Create(map)
   ns.alert:Create(map)
   ns.gameOptions:Create(map)
   ns.actionBar:Create(map)
   ns.inventory:Create(map)
   ns.spellbook:Create(map)
   ns.store:Create(map)
   ns.scoreboard:Create(frame)
   ns.helpWindow:Create(frame)

   local side = ns.side:Create(frame)
   side:SetWidth(SIDE_W)
   side:SetPoint("TOPRIGHT", -PAD, -(TITLE_H + PAD))
   side:SetPoint("BOTTOMRIGHT", -PAD, BOTTOM_H + 2 * PAD)

   local bottom = ns.CreatePanel(frame)
   bottom:SetHeight(BOTTOM_H)
   bottom:SetPoint("BOTTOMLEFT", PAD, PAD)
   bottom:SetPoint("BOTTOMRIGHT", -PAD, PAD)

   local bar = ns.bar:Create(bottom)
   bar:SetPoint("RIGHT", -PAD, 0)

   local prompt = ns.prompt:Create(bottom)
   prompt:SetPoint("BOTTOMLEFT", PAD, PAD)
   prompt:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -PAD, 0)

   local logFrame = ns.log:Create(bottom)
   logFrame:SetPoint("TOPLEFT", PAD, -PAD)
   logFrame:SetPoint("BOTTOMRIGHT", prompt, "TOPRIGHT", 0, 2)

   -- Keyboard: captured only while focused.
   frame:SetScript("OnMouseDown", function() self:SetFocus(true) end)
   frame:SetScript("OnKeyDown", function(_, key) self:OnKeyDown(key) end)
   frame:SetScript("OnChar", function(_, char)
      if self.focused then ns.ui:InjectKey(char) end
   end)
   frame:SetScript("OnShow", function() self:OnShow() end)
   frame:SetScript("OnHide", function()
      self:SetFocus(false)
      ns.Save.store()
   end)
   -- Clicking anywhere outside releases the keyboard (event is missing on some clients).
   frame:SetScript("OnEvent", function()
      if self.focused and not ((frame.IsMouseOver and frame:IsMouseOver()) or (MouseIsOver and MouseIsOver(frame))) then
         self:SetFocus(false)
      end
   end)
   pcall(frame.RegisterEvent, frame, "GLOBAL_MOUSE_DOWN")

   self:SetFocus(false)
   return frame
end

function main:OnShow()
   if not ns.ui:IsActive() then
      ns.ui:NewGame()
   end
end

function main:OnKeyDown(key)
   local frame = self.frame
   if not self.focused then
      frame:SetPropagateKeyboardInput(true)
      return
   end
   frame:SetPropagateKeyboardInput(false)
   if key == "PAGEUP" then
      ns.log:PageUp()
   elseif key == "PAGEDOWN" then
      ns.log:PageDown()
   elseif KEYMAP[key] then
      local name = KEYMAP[key]
      if IsShiftKeyDown() and ARROWS[name] then name = "SHIFT-" .. name end  -- run
      ns.ui:InjectKey(name)
   end
end

function main:SetFocus(on)
   local frame = self.frame
   if not frame then return end
   on = on and frame:IsShown() or false
   self.focused = on
   frame:EnableKeyboard(on)
   if frame.SetBackdropBorderColor then
      frame:SetBackdropBorderColor(unpack(on and ns.COLOR_FOCUS or ns.COLOR_BORDER))
   end
   self.hint:SetText(on and L["Keyboard captured - Esc to release"] or L["Click the window to use the keyboard"])
end

function main:ApplyScale()
   if self.frame then
      -- never larger than the screen, whatever the setting
      local frame = self.frame
      local scale = ns.mod.db.profile.scale
      local w, h = frame:GetWidth(), frame:GetHeight()
      if w and w > 0 and h and h > 0 then
         scale = math.min(scale, UIParent:GetWidth() * 0.98 / w, UIParent:GetHeight() * 0.98 / h)
      end
      frame:SetScale(scale)
   end
end

function main:ResetPosition()
   local window = ns.mod.db.profile.window
   window.point, window.x, window.y = "CENTER", 0, 0
   if self.frame then ApplyPosition(self.frame) end
end

function main:Show()
   self:Create():Show()
   self:ApplyScale()
   self:SetFocus(true)
end

function main:Hide()
   if self.frame then self.frame:Hide() end
end

function main:Toggle()
   if self.frame and self.frame:IsShown() then
      self:Hide()
   else
      self:Show()
   end
end
