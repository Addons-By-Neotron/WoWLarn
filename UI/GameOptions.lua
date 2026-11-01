--[[
**********************************************************************
WoWLarn - The settings of a new game: difficulty and the optional changes.
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

-- Shown at the start of a new game, before the class is picked. What is chosen here is kept
-- as the settings of the next new game too (ns.mod.db.profile); a game keeps the ones it
-- was started with (G.rules, the difficulty in c[K.HARDGAME]).
local options = {}
ns.gameOptions = options

local WIDTH, ROW_H = 560, 76
local CONTROL_W = 190  -- (what is kept free at the right for the slider or the check box)

-- The settings: key in the profile, what it is, how the value reads.
local SETTINGS = {
   { key = "difficulty", slider = true, min = 0, max = 6,
     name = L["Difficulty"],
     desc = L["How hard the game is.  Monsters are tougher and the dungeon is meaner."] },
   { key = "toughWeapons", name = L["Tough weapons"],
     desc = L["Weapons resist being dulled by the rust monster and its kin: the better the weapon and the more plus it has, the better.  The Lance of Death is never dulled."] },
   { key = "elevatorLimit", slider = true, min = 0, max = 14, off = L["off"],
     name = L["Elevator limit"],
     desc = L["The most levels an express elevator can take you, up or down.  Off leaves it to chance, as in the original: a ride from level 3 can end on level 15."] },
   { key = "races", name = L["Races"],
     desc = L["Your character's race adds a few points to the stats of the new game.  Not part of the original game."] },
}

local function Profile()
   return ns.mod.db.profile
end

function options:Create(parent)
   local frame = ns.CreatePanel(parent, nil, { 0.04, 0.04, 0.06, 0.97 })
   frame:SetFrameLevel(parent:GetFrameLevel() + 1220)
   frame:SetSize(WIDTH, 90 + #SETTINGS * ROW_H)
   frame:SetPoint("CENTER")
   frame:EnableMouse(true)
   frame:Hide()
   local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   title:SetPoint("TOP", 0, -12)
   title:SetText(L["A new game"])
   local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
   hint:SetText(L["Choose how hard it gets, then press Start (or Enter)."])

   self.widgets = {}
   for index, setting in ipairs(SETTINGS) do
      local y = -44 - (index - 1) * ROW_H
      local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      label:SetPoint("TOPLEFT", 16, y)
      local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
      desc:SetWidth(WIDTH - 32 - CONTROL_W)
      desc:SetJustifyH("LEFT")
      desc:SetText(setting.desc)
      local widget = { setting = setting, label = label }
      if setting.slider then
         local slider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
         slider:SetSize(CONTROL_W - 30, 16)
         slider:SetPoint("TOPRIGHT", -26, y - 6)
         for _, name in ipairs({ "Low", "High", "Text" }) do  -- (the template's own labels)
            local label = slider[name]
            if type(label) == "table" then label:Hide() end
         end
         slider:SetMinMaxValues(setting.min, setting.max)
         slider:SetObeyStepOnDrag(true)
         slider:SetValueStep(1)
         slider:SetScript("OnValueChanged", function(_, value)
            if self.loading then return end
            Profile()[setting.key] = math.floor(value + 0.5)
            self:Update()
         end)
         widget.slider = slider
      else
         local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
         check:SetSize(24, 24)
         check:SetPoint("TOPRIGHT", -26 - (CONTROL_W - 54) / 2, y - 2)
         check:SetScript("OnClick", function(button)
            Profile()[setting.key] = button:GetChecked() and true or false
            self:Update()
         end)
         widget.check = check
      end
      self.widgets[index] = widget
   end

   local start = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   start:SetSize(110, 24)
   start:SetPoint("BOTTOM", 0, 12)
   start:SetText(L["Start"])
   start:SetScript("OnClick", function()
      ns.main:SetFocus(true)
      ns.ui:InjectKey("ENTER")
   end)
   self.frame = frame
   return frame
end

-- Shows the values: "Difficulty: 3".
function options:Update()
   for _, widget in ipairs(self.widgets) do
      local setting = widget.setting
      local value = Profile()[setting.key]
      if setting.slider then
         value = value or 0
         widget.label:SetText(string.format("%s: %s", setting.name, value == 0 and setting.off or value))
      else
         widget.label:SetText(setting.name)
      end
   end
end

function options:Show()
   self.loading = true
   for _, widget in ipairs(self.widgets) do
      local value = Profile()[widget.setting.key]
      if widget.slider then
         widget.slider:SetValue(value or 0)
      else
         widget.check:SetChecked(value and true or false)
      end
   end
   self.loading = false
   self:Update()
   self.frame:Show()
end

function options:Hide()
   self.frame:Hide()
end
