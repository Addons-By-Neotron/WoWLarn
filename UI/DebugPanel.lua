--[[
**********************************************************************
WoWLarn - The debug panel: buttons for wizard mode, god mode and friends (debug builds only).
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
local _, ns = ...
local G = ns.G

-- The debug panel (/larn debug, or the Debug button in the title bar): wizard mode, god mode
-- and what they give, as buttons.  Anything that gives an advantage turns wizard mode on,
-- which keeps the game off the scoreboard.
local panel = {}
ns.debugPanel = panel

local WIDTH, BUTTON_H, GAP = 190, 24, 4

local function Wizard()
   if not G.wizard then ns.Debug.toggleWizard() end
end

-- Runs a key in the game (it asks questions); the game has to be waiting for a command.
local function Key(key)
   Wizard()
   if ns.ui.InjectKey then ns.ui:InjectKey(key) end
end

function panel:Create()
   local frame = ns.CreatePanel(UIParent, "WoWLarnDebugPanel")
   frame:SetPoint("CENTER", -300, 0)
   frame:SetFrameStrata("DIALOG")
   frame:SetMovable(true)
   frame:EnableMouse(true)
   frame:RegisterForDrag("LeftButton")
   frame:SetScript("OnDragStart", frame.StartMoving)
   frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
   frame:Hide()
   tinsert(UISpecialFrames, "WoWLarnDebugPanel")
   self.frame = frame

   local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   title:SetPoint("TOP", 0, -8)
   title:SetText("WoWLarn debug")

   local buttons = {}
   local function Button(text, onClick)
      local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
      button:SetSize(WIDTH - 16, BUTTON_H)
      button:SetPoint("TOP", 0, -26 - #buttons * (BUTTON_H + GAP))
      button:SetText(text)
      button:SetScript("OnClick", function() onClick() self:Update() end)
      buttons[#buttons + 1] = button
      return button
   end
   self.wizard = Button("Wizard mode", ns.Debug.toggleWizard)
   self.god = Button("God mode", ns.Debug.toggleGod)
   Button("Debug kit (stats 70, all known)", function() Wizard() ns.Debug.kit() end)
   Button("Maximum experience", function() Wizard() ns.Debug.maxExperience() end)
   Button("Reveal the map", function() Wizard() ns.Debug.reveal() end)
   Button("Create an item...", function() Key("@") end)
   Button("Teleport to a level...", function() Key("Z") end)
   Button("Dump the state", ns.Debug.dump)
   Button("Flat / 2.5D view", function() ns.mod:ToggleView() end)
   frame:SetSize(WIDTH, 34 + #buttons * (BUTTON_H + GAP))
end

function panel:Update()
   if not self.frame then return end
   self.wizard:SetText("Wizard mode: " .. (G.wizard and "ON" or "off"))
   self.god:SetText("God mode: " .. (G.god and "ON" or "off"))
end

function panel:Toggle()
   if not self.frame then self:Create() end
   self.frame:SetShown(not self.frame:IsShown())
   self:Update()
end
