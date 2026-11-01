--[[
**********************************************************************
WoWLarn - Control buttons.
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

local bar = {}
ns.bar = bar

local BUTTON_SIZE, SPACING, COLUMNS = 36, 4, 9

-- key is the command character the game receives (main.c:parse).
-- The icons are placeholders until Data/Visuals.lua curates them.
local COMMANDS = {
   { key = "i", name = L["Inventory"], icon = "INV_Misc_Bag_08" },
   { key = "I", name = L["Sort inventory"], icon = "INV_Misc_Note_02" },
   { key = "d", name = L["Drop item"], icon = "INV_Misc_Coin_01" },
   { key = "q", name = L["Quaff potion"], icon = "INV_Potion_54" },
   { key = "r", name = L["Read scroll"], icon = "INV_Scroll_03" },
   { key = "e", name = L["Eat cookie"], icon = "INV_Misc_Food_15" },
   { key = "c", name = L["Cast spell"], icon = "Spell_Fire_FlameBolt" },
   { key = "C", name = L["Close door"], icon = "INV_Misc_Key_03" },
   { key = "^", name = L["Find traps"], icon = "Ability_Rogue_FindWeakness" },
   { key = ".", name = L["Rest"], icon = "Spell_Nature_Sleep" },
   { key = "t", name = L["Go to"], icon = "INV_Misc_Map_01" },
   { key = "Z", name = L["Teleport"], icon = "Spell_Arcane_Blink" },
   { key = "D", name = L["Discoveries"], icon = "INV_Misc_Book_08" },
   { key = "?", name = L["Help"], icon = "INV_Misc_QuestionMark" },
   { key = "S", name = L["Save and close"], icon = "INV_Misc_Note_01" },
   { key = "B", name = L["Bestiary"], icon = "INV_Misc_Head_Dragon_01", bestiary = true },
   { key = "V", name = L["Flat tiles or the 2.5D view"], icon = "INV_Misc_Spyglass_02", view = true },
}

local function OnEnter(self)
   GameTooltip:SetOwner(self, "ANCHOR_TOP")
   GameTooltip:SetText(self.command.name)
   GameTooltip:AddLine(format(L["Key: %s"], self.command.key), 0.7, 0.7, 0.7)
   GameTooltip:Show()
end

local function OnClick(self)
   ns.main:SetFocus(true)
   if self.command.bestiary then  -- (works without a game)
      ns.bestiaryWindow:Toggle()
      return
   end
   if self.command.view then  -- (works without a game)
      ns.mod:ToggleView()
      return
   end
   ns.ui:InjectKey(self.command.key)
end

function bar:Create(parent)
   local frame = CreateFrame("Frame", nil, parent)
   frame:SetSize(COLUMNS * (BUTTON_SIZE + SPACING) - SPACING, 2 * (BUTTON_SIZE + SPACING) - SPACING)
   self.buttons = {}
   for index, command in ipairs(COMMANDS) do
      local button = CreateFrame("Button", nil, frame)
      button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
      local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
      button:SetPoint("TOPLEFT", column * (BUTTON_SIZE + SPACING), -row * (BUTTON_SIZE + SPACING))
      button:SetNormalTexture("Interface\\Icons\\" .. command.icon)
      button:GetNormalTexture():SetTexCoord(0.07, 0.93, 0.07, 0.93)
      button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      local label = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      label:SetPoint("BOTTOMRIGHT", -2, 2)
      label:SetText(command.view and (ns.mod.db.profile.view == "3d" and "3D" or "2D") or command.key)
      button.label = label
      button.command = command
      button:SetScript("OnEnter", OnEnter)
      button:SetScript("OnLeave", GameTooltip_Hide)
      button:SetScript("OnClick", OnClick)
      self.buttons[command.key] = button
   end
   self.frame = frame
   return frame
end

-- The view button shows which view is on.
function bar:UpdateView()
   local button = self.buttons and self.buttons.V
   if button then button.label:SetText(ns.mod.db.profile.view == "3d" and "3D" or "2D") end
end
