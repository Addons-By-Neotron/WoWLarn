--[[
**********************************************************************
WoWLarn - Inventory window (show.c).
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
local K = ns.K
local G = ns.G
local V = ns.Visuals

-- A 26 slot grid over the map: two columns of 13. In pick mode the valid items stand out;
-- clicking a slot or pressing its letter answers the pending request.
local inventory = {}
ns.inventory = inventory

local COLUMNS, ROWS = 2, 13
local ROW_H, ROW_W = 26, 270
local HEADER_H, FOOTER_H = 24, 24

local function Letter(slot)
   return string.char(96 + slot)
end

function inventory:Create(parent)
   local frame = ns.CreatePanel(parent)
   frame:SetFrameStrata("DIALOG")
   frame:SetFrameLevel(parent:GetFrameLevel() + 20)
   frame:SetSize(COLUMNS * ROW_W + 16, ROWS * ROW_H + HEADER_H + FOOTER_H + 8)
   frame:SetPoint("CENTER")
   frame:EnableMouse(true)
   frame:Hide()
   self.frame = frame

   self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   self.title:SetPoint("TOPLEFT", 8, -6)
   self.weight = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   self.weight:SetPoint("BOTTOMLEFT", 8, 6)

   self.rows = {}
   for slot = 1, K.IVENSIZE do
      local column = math.floor((slot - 1) / ROWS)
      local row = (slot - 1) % ROWS
      local button = CreateFrame("Button", nil, frame)
      button:SetSize(ROW_W - 4, ROW_H - 2)
      button:SetPoint("TOPLEFT", 8 + column * ROW_W, -(HEADER_H + row * ROW_H))
      button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      button.icon = button:CreateTexture(nil, "ARTWORK")
      button.icon:SetSize(ROW_H - 6, ROW_H - 6)
      button.icon:SetPoint("LEFT", 2, 0)
      button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      button.text:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
      button.text:SetPoint("RIGHT", -2, 0)
      button.text:SetJustifyH("LEFT")
      button.slot = slot
      button:SetScript("OnClick", function()
         ns.main:SetFocus(true)
         ns.ui:InjectKey(Letter(slot))
      end)
      self.rows[slot] = button
   end
   return frame
end

-- filter is nil to show everything, or a function(id) that says which items are valid.
function inventory:Open(title, filter)
   if not self.frame then return end
   self.filter = filter
   self.title:SetText(title or L["Inventory"])
   self.frame:Show()
   self:Update()
end

function inventory:Close()
   if self.frame then self.frame:Hide() end
   self.filter = nil
end

function inventory:IsShown()
   return self.frame and self.frame:IsShown()
end

function inventory:Update()
   if not self.frame or not self.frame:IsShown() then return end
   local filter = self.filter
   local limit = ns.Player.pocketLimit()
   local used = 0
   for slot, button in ipairs(self.rows) do
      local id = G.iven[slot]
      if id ~= 0 then used = used + 1 end
      if slot > limit and id == 0 then
         -- a slot that opens up with the level: say when
         button.icon:Hide()
         button.text:SetText(format("|cff555555%s) %s|r", Letter(slot), format(L["locked until level %d"], (slot - 15) * 2)))
      elseif id == 0 then
         button.icon:Hide()
         button.text:SetText("|cff777777" .. Letter(slot) .. ")|r")
      else
         local icon = V.ObjectIcon(id)
         if icon then
            button.icon:SetTexture(icon)
            button.icon:Show()
         else
            button.icon:Hide()
         end
         local valid = not filter or filter(id)
         local color = valid and "|cffffffff" or "|cff777777"
         button.text:SetText(color .. Letter(slot) .. ")|r " .. color .. ns.Player.itemName(slot) .. "|r")
      end
   end
   local pounds = ns.Player.packWeight()
   self.weight:SetText(format(L["Items %d of %d"], used, limit) .. "   "
      .. format(pounds == 1 and L["Carrying %d pound"] or L["Carrying %d pounds"], pounds))
end
