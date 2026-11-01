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
local RACE_H = 190  -- (the race pick below the settings)
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
   frame:SetSize(WIDTH, 90 + #SETTINGS * ROW_H + RACE_H)
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
      local widget = { setting = setting, label = label, desc = desc }
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

   self:CreateRacePick(frame, -44 - #SETTINGS * ROW_H)

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

-- The look of the character: the race to pick (your own, or a model of any other), a man or a
-- woman, and how it looks.  The race only changes the look; the bonuses are for the Races setting.
function options:CreateRacePick(frame, y)
   local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   label:SetPoint("TOPLEFT", 16, y)
   label:SetText(L["Race"])
   local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
   desc:SetWidth(WIDTH - 32 - 170)
   desc:SetJustifyH("LEFT")
   desc:SetText(L["How your character looks, and the race whose bonus the Races setting gives.  Your own race is the one of your WoW character."])

   local preview = CreateFrame("PlayerModel", nil, frame)
   preview:SetSize(130, RACE_H - 20)
   preview:SetPoint("TOPRIGHT", -16, y)
   self.preview = preview

   local pick = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   pick:SetSize(CONTROL_W, 26)
   pick:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
   pick:SetScript("OnClick", function() self:OpenRaces() end)
   self.dropdown = pick

   self.genders = {}
   for index, name in ipairs({ L["Male"], L["Female"] }) do
      local button = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
      button:SetSize(24, 24)
      button:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", (index - 1) * 90, -8)
      local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      text:SetPoint("LEFT", button, "RIGHT", 2, 0)
      text:SetText(name)
      button:SetScript("OnClick", function()
         Profile().gender = index
         self:Update()
         self:UpdateRaces()
      end)
      self.genders[index] = button
   end
end

-- The window to pick the race from: a model of each, its name and what it adds.
local COLS, CELL_W, CELL_H, MODEL_H = 7, 100, 168, 100

function options:CreateRaces()
   -- (on the screen, not on the game window: that has a scale of its own, and holds less)
   local frame = ns.CreatePanel(UIParent, nil, { 0.04, 0.04, 0.06, 0.99 })
   frame:SetFrameStrata("FULLSCREEN_DIALOG")
   frame:SetPoint("CENTER", UIParent, "CENTER")
   frame:EnableMouse(true)
   frame:Hide()
   local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   title:SetPoint("TOP", 0, -12)
   title:SetText(L["Pick a race"])
   local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
   hint:SetText(L["Green and red are what it adds to your stats when the Races setting is on."])
   local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   close:SetSize(100, 24)
   close:SetPoint("BOTTOM", 0, 12)
   close:SetText(L["Close"])
   close:SetScript("OnClick", function() frame:Hide() end)
   self.races = { frame = frame, cells = {}, genders = {} }
   for index, name in ipairs({ L["Male"], L["Female"] }) do  -- (the sex of all the models)
      local button = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
      button:SetSize(24, 24)
      button:SetPoint("TOPLEFT", 16 + (index - 1) * 90, -14)
      local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      text:SetPoint("LEFT", button, "RIGHT", 2, 0)
      text:SetText(name)
      button:SetScript("OnClick", function()
         Profile().gender = index
         self:Update()
         self:UpdateRaces()
      end)
      self.races.genders[index] = button
   end
   return self.races
end

local function RaceCell(self, parent, index)
   local cell = CreateFrame("Button", nil, parent)
   cell:SetSize(CELL_W - 4, CELL_H - 4)
   cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
   cell.selected = cell:CreateTexture(nil, "BACKGROUND")
   cell.selected:SetAllPoints()
   cell.selected:SetColorTexture(0.9, 0.7, 0.1, 0.25)
   cell.model = CreateFrame("PlayerModel", nil, cell)
   cell.model:SetPoint("TOPLEFT", 4, -4)
   cell.model:SetPoint("TOPRIGHT", -4, -4)
   cell.model:SetHeight(MODEL_H)
   cell.name = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   cell.name:SetPoint("TOP", cell.model, "BOTTOM", 0, -4)
   cell.name:SetWidth(CELL_W - 8)
   cell.bonus = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   cell.bonus:SetPoint("TOP", cell.name, "BOTTOM", 0, -3)
   cell.bonus:SetWidth(CELL_W - 8)
   cell:SetScript("OnClick", function(button)
      Profile().raceChoice = button.token
      self.races.frame:Hide()
      self:Update()
   end)
   return cell
end

-- Fills the window with the races of this client, in the sex that is picked.
function options:UpdateRaces()
   local races = self.races
   if not races or not races.frame:IsShown() then return end
   local gender = ns.Create.gender()
   local choice = ns.Create.raceChoice()
   for index, button in ipairs(races.genders) do button:SetChecked(index == gender) end
   local entries = { { false, L["Your own"] } }
   for _, race in ipairs(ns.RaceList) do entries[#entries + 1] = race end
   for index, entry in ipairs(entries) do
      local cell = races.cells[index] or RaceCell(self, races.frame, index)
      races.cells[index] = cell
      local token = entry[1] or nil
      cell.token = token
      cell:ClearAllPoints()
      cell:SetPoint("TOPLEFT", 12 + ((index - 1) % COLS) * CELL_W, -(56 + math.floor((index - 1) / COLS) * CELL_H))
      cell.name:SetText(entry[2])
      local _, bonus
      if token then _, bonus = ns.Create.raceInfo(token) else _, bonus = ns.Create.ownRaceInfo() end
      cell.bonus:SetText(bonus and ns.Create.raceLines(bonus) or "")
      local look = token and ns.RaceModels[token] and ns.RaceModels[token][gender]
      if look then
         cell.model:SetDisplayInfo(look)
      else
         pcall(cell.model.SetUnit, cell.model, "player")
      end
      cell.selected:SetShown(token == choice)
      cell:Show()
   end
   for index = #entries + 1, #races.cells do races.cells[index]:Hide() end
   races.frame:SetSize(COLS * CELL_W + 24, 56 + math.ceil(#entries / COLS) * CELL_H + 50)
   local scale = math.min(1, (UIParent:GetHeight() - 40) / races.frame:GetHeight())
   races.frame:SetScale(scale)
end

function options:OpenRaces()
   local races = self.races or self:CreateRaces()
   races.frame:Show()
   self:UpdateRaces()
end

-- Shows the race pick: the name, the sex and the model.
function options:UpdateRacePick()
   local choice = ns.Create.raceChoice()
   local gender = ns.Create.gender()
   self.dropdown:SetText(choice and ns.RaceNames[choice] or L["Your own"])
   for index, button in ipairs(self.genders) do
      button:SetChecked(index == gender)
      button:SetEnabled(choice ~= nil)
   end
   local look = ns.Create.look(select(3, ns.Create.raceInfo()))
   if look then
      self.preview:SetDisplayInfo(look)
   else
      pcall(self.preview.SetUnit, self.preview, "player")
   end
end

-- Shows the values: "Difficulty: 3".
function options:Update()
   self:UpdateRacePick()
   for _, widget in ipairs(self.widgets) do
      local setting = widget.setting
      local value = Profile()[setting.key]
      if setting.slider then
         value = value or 0
         widget.label:SetText(string.format("%s: %s", setting.name, value == 0 and setting.off or value))
      else
         widget.label:SetText(setting.name)
      end
      if setting.key == "races" then  -- what the bonus is
         local race, bonus = ns.Create.raceInfo()
         widget.desc:SetText(bonus and format(L["Your race, %s, adds %s to the stats of the new game.  Not part of the original game."], race, ns.Create.raceText(bonus))
            or setting.desc)
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
   if self.races then self.races.frame:Hide() end
   self.frame:Hide()
end
