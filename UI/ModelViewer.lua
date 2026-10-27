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
local L = LibStub("AceLocale-3.0"):GetLocale("WoWLarn")
local _, ns = ...
local K = ns.K

-- The model viewer (/larn models): steps through creature displays so one can be chosen for
-- each monster of the game.  The choice is kept in the saved variables (global.displays) and
-- shows in the 2.5D view straight away.
local viewer = {}
ns.modelViewer = viewer

local WIDTH, MODEL_H = 340, 300

function viewer:Create()
   local frame = ns.CreatePanel(UIParent, "WoWLarnModelViewer")
   frame:SetSize(WIDTH, MODEL_H + 150)
   frame:SetPoint("CENTER", 300, 0)
   frame:SetFrameStrata("DIALOG")
   frame:SetMovable(true)
   frame:EnableMouse(true)
   frame:RegisterForDrag("LeftButton")
   frame:SetScript("OnDragStart", frame.StartMoving)
   frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
   frame:Hide()
   tinsert(UISpecialFrames, "WoWLarnModelViewer")
   self.frame = frame

   self.model = CreateFrame("PlayerModel", nil, frame)
   self.model:SetPoint("TOPLEFT", 8, -8)
   self.model:SetSize(WIDTH - 16, MODEL_H)
   self.model:SetScript("OnModelLoaded", function(model) model:SetFacing(math.pi * 1.5) end)

   self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   self.title:SetPoint("TOPLEFT", self.model, "BOTTOMLEFT", 0, -6)
   self.state = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   self.state:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)

   local function Button(text, width, x, y, onClick)
      local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
      button:SetSize(width, 22)
      button:SetPoint("BOTTOMLEFT", x, y)
      button:SetText(text)
      button:SetScript("OnClick", onClick)
      return button
   end
   Button("-100", 44, 8, 40, function() self:Step(-100) end)
   Button("-10", 36, 54, 40, function() self:Step(-10) end)
   Button("-1", 30, 92, 40, function() self:Step(-1) end)
   self.edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
   self.edit:SetSize(60, 22)
   self.edit:SetPoint("BOTTOMLEFT", 130, 40)
   self.edit:SetAutoFocus(false)
   self.edit:SetNumeric(true)
   self.edit:SetScript("OnEnterPressed", function(edit)
      self:Show(tonumber(edit:GetText()) or self.display)
      edit:ClearFocus()
   end)
   Button("+1", 30, 196, 40, function() self:Step(1) end)
   Button("+10", 36, 230, 40, function() self:Step(10) end)
   Button("+100", 44, 268, 40, function() self:Step(100) end)
   Button(L["< Monster"], 80, 8, 10, function() self:Pick(-1) end)
   Button(L["Monster >"], 80, 92, 10, function() self:Pick(1) end)
   Button(L["Use"], 60, 180, 10, function() self:Assign(self.display) end)
   Button(L["Clear"], 60, 244, 10, function() self:Assign(nil) end)

   self.monster, self.display = 1, 1
   return frame
end

local function Name(id)
   local data = ns.MonsterData[id]
   return data and data.name or "?"
end

-- Shows a display in the viewer.
function viewer:Show(display)
   self.display = math.max(1, display)
   self.model:SetDisplayInfo(self.display)
   self.model:SetFacing(math.pi * 1.5)
   self.edit:SetText(tostring(self.display))
   self:Update()
end

function viewer:Step(by)
   self:Show(self.display + by)
end

function viewer:Update()
   local id = self.monster
   local assigned = ns.Visuals.MonsterDisplay(id)
   self.title:SetText(format("%d  %s", id, Name(id)))
   self.state:SetText(assigned and format(L["Shown as display %d"], assigned) or L["Shown as a letter"])
end

-- Goes to another monster, showing its display if it has one.
function viewer:Pick(by)
   self.monster = (self.monster - 1 + by) % K.MAXMONST + 1
   local assigned = ns.Visuals.MonsterDisplay(self.monster)
   if assigned then self:Show(assigned) else self:Update() end
end

-- Chooses the display shown for the monster (nil: none).
function viewer:Assign(display)
   ns.mod.db.global.displays[self.monster] = display
   self:Update()
   ns.ui:Refresh("map")
end

function viewer:Toggle()
   if not self.frame then self:Create() end
   if self.frame:IsShown() then
      self.frame:Hide()
   else
      self.frame:Show()
      self:Show(self.display)
   end
end
