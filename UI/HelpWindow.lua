--[[
**********************************************************************
WoWLarn - The help window (the ? key).
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

-- The help: the commands as a table, then the sections of text, in a window over the game that
-- scrolls. Enter, space or Esc close it; the up and down arrows scroll (so does the wheel).
local help = {}
ns.helpWindow = help

local WIDTH, HEIGHT, MARGIN = 700, 560, 16
local KEY_W, ROW_H, COLUMNS = 110, 20, 2

function help:Create(parent)
   local frame = ns.CreatePanel(parent, nil, { 0.04, 0.04, 0.06, 0.97 })
   frame:SetFrameLevel(parent:GetFrameLevel() + 1260)
   frame:SetSize(WIDTH, HEIGHT)
   frame:SetPoint("CENTER")
   frame:EnableMouse(true)
   frame:Hide()
   self.frame = frame

   local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   title:SetPoint("TOPLEFT", MARGIN, -12)
   title:SetText(L["Help"])
   local ok = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   ok:SetSize(90, 22)
   ok:SetPoint("BOTTOM", 0, 10)
   ok:SetText(L["OK"])
   ok:SetScript("OnClick", function()
      ns.main:SetFocus(true)
      ns.ui:InjectKey("ENTER")
   end)

   local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
   scroll:SetPoint("TOPLEFT", MARGIN, -44)
   scroll:SetPoint("BOTTOMRIGHT", -MARGIN - 22, 42)
   local content = CreateFrame("Frame", nil, scroll)
   content:SetSize(WIDTH - 2 * MARGIN - 26, 10)
   scroll:SetScrollChild(content)
   self.scroll, self.content = scroll, content
   self.strings = {}  -- (the lines of text, kept to be used again)
   self.used = 0
   return frame
end

-- A line of text in the content, to be placed by the caller.
function help:Text(font)
   self.used = self.used + 1
   local text = self.strings[self.used]
   if not text then
      text = self.content:CreateFontString(nil, "OVERLAY", font)
      text:SetJustifyH("LEFT")
      text:SetJustifyV("TOP")
      self.strings[self.used] = text
   end
   text:SetFontObject(font)
   text:ClearAllPoints()
   text:Show()
   return text
end

function help:Fill()
   for _, text in ipairs(self.strings) do text:Hide() end
   self.used = 0
   local content = self.content
   local width = content:GetWidth()
   local y = 0
   for _, section in ipairs(ns.HelpSections) do
      local heading = self:Text("GameFontNormalLarge")
      heading:SetPoint("TOPLEFT", 0, -y)
      heading:SetText(section.title)
      y = y + heading:GetStringHeight() + 6
      if section.commands then
         local rows = math.ceil(#section.commands / COLUMNS)
         local columnWidth = width / COLUMNS
         for index, command in ipairs(section.commands) do
            local column = math.floor((index - 1) / rows)
            local row = (index - 1) % rows
            local keys = self:Text("GameFontNormal")
            keys:SetPoint("TOPLEFT", column * columnWidth, -(y + row * ROW_H))
            keys:SetWidth(KEY_W)
            keys:SetText(command[1])
            local what = self:Text("GameFontHighlight")
            what:SetPoint("TOPLEFT", column * columnWidth + KEY_W + 6, -(y + row * ROW_H))
            what:SetWidth(columnWidth - KEY_W - 14)
            what:SetText(command[2])
         end
         y = y + rows * ROW_H + 8
      end
      if section.text then
         local body = self:Text("GameFontHighlight")
         body:SetPoint("TOPLEFT", 0, -y)
         body:SetWidth(width)
         body:SetSpacing(2)
         body:SetText(section.text)
         y = y + body:GetStringHeight() + 6
      end
      y = y + 14
   end
   content:SetHeight(y)
end

function help:Show()
   self:Fill()
   self.scroll:SetVerticalScroll(0)
   self.frame:Show()
end

function help:Hide()
   self.frame:Hide()
end

-- The arrow keys scroll.
function help:Scroll(delta)
   local scroll = self.scroll
   local top = math.max(0, math.min(scroll:GetVerticalScroll() + delta, scroll:GetVerticalScrollRange()))
   scroll:SetVerticalScroll(top)
end

-- Shows the help and waits until it is closed.
function help:Run()
   local ui = ns.ui
   self:Show()
   ns.prompt:Set(L["Press space, enter or escape to close the window"])
   local key
   repeat
      key = ui:GetKey()
      if key == "UP" then
         self:Scroll(-60)
      elseif key == "DOWN" then
         self:Scroll(60)
      end
   until key == ns.ESC or key == " " or key == "ENTER"
   ns.prompt:Clear()
   self:Hide()
   ui:Refresh("all")
end
