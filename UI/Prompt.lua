--[[
**********************************************************************
WoWLarn - Prompt strip above the message log.
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

local prompt = {}
ns.prompt = prompt

local HEIGHT = 24

local function MakeButton(parent, label, key)
   local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
   button:SetSize(70, 20)
   button:SetText(label)
   button:SetScript("OnClick", function()
      ns.main:SetFocus(true)
      ns.ui:InjectKey(key)
   end)
   button:Hide()
   return button
end

function prompt:Create(parent)
   local frame = CreateFrame("Frame", nil, parent)
   frame:SetHeight(HEIGHT)
   local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   text:SetPoint("LEFT", 4, 0)
   text:SetJustifyH("LEFT")
   self.text = text
   self.no = MakeButton(frame, L["No"], "n")
   self.no:SetPoint("RIGHT", -2, 0)
   self.yes = MakeButton(frame, L["Yes"], "y")
   self.yes:SetPoint("RIGHT", self.no, "LEFT", -4, 0)
   self.more = MakeButton(frame, L["Continue"], " ")
   self.more:SetPoint("RIGHT", -2, 0)
   text:SetPoint("RIGHT", self.yes, "LEFT", -4, 0)
   self.frame = frame
   return frame
end

-- mode: nil for plain text, "yesno" or "more" for the matching buttons.
function prompt:Set(message, mode)
   if not self.frame then return end
   self.text:SetText(message or "")
   self.yes:SetShown(mode == "yesno")
   self.no:SetShown(mode == "yesno")
   self.more:SetShown(mode == "more")
end

function prompt:Clear()
   self:Set("")
end
