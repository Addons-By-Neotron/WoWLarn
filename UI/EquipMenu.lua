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
local format = string.format

-- The equipment window: a click on the weapon, armor or shield slot of the character sheet
-- lists what in the pack fits, with what it would do to your armor class or weapon class.
-- A choice is done the way the keys do it (w, W, T), so it takes a turn like they do.
local equip = {}
ns.equipMenu = equip

local ROW_H, ROW_W, PAD = 24, 250, 6

local function Letter(slot)
   return string.char(96 + slot)
end

-- The kinds of slot: what fits, which key puts it on, and how to take it off.
local KINDS = {
   weapon = { title = L["Weapon"], fits = function(id) return ns.Action.isWeapon(id) end,
      worn = function() return G.c[K.WIELD] end },
   armor = { title = L["Armor"], fits = function(id) return ns.Action.isArmor(id) end,
      worn = function() return G.c[K.WEAR] end },
   shield = { title = L["Shield"], fits = function(id) return ns.Action.isShield(id) end,
      worn = function() return G.c[K.SHIELD] end },
}
equip.KINDS = KINDS

-- Does what the choice does, through the keys of the game.
local function Choose(kind, slot)
   local ui = ns.ui
   if not ui:IsReady() then
      ui:Message(L["You can't change your equipment right now."])
      return
   end
   ns.main:SetFocus(true)
   if kind == "weapon" then
      ui:InjectKey("w")
      ui:InjectKey(slot > 0 and Letter(slot) or "-")
   else
      local worn = KINDS[kind].worn()
      if slot == worn then return end
      if worn ~= 0 then  -- (the game wears one at a time)
         ns.Action.takeOffWhat = kind
         ui:InjectKey("T")
      end
      if slot > 0 then
         ui:InjectKey("W")
         ui:InjectKey(Letter(slot))
      end
   end
end

function equip:Create()
   local catcher = CreateFrame("Button", nil, UIParent)
   catcher:SetAllPoints(UIParent)
   catcher:SetFrameStrata("FULLSCREEN_DIALOG")
   catcher:RegisterForClicks("AnyUp")
   catcher:SetScript("OnClick", function() self:Close() end)
   catcher:Hide()
   self.catcher = catcher

   local frame = ns.CreatePanel(catcher, nil, { 0.05, 0.05, 0.08, 0.98 })
   frame:SetFrameStrata("FULLSCREEN_DIALOG")
   frame:SetFrameLevel(catcher:GetFrameLevel() + 10)
   frame:EnableMouse(true)
   self.frame = frame
   self.rows = {}
end

local function Row(self, index)
   local row = self.rows[index]
   if row then return row end
   row = CreateFrame("Button", nil, self.frame)
   row:SetSize(ROW_W - 2 * PAD, ROW_H)
   row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
   row.icon = row:CreateTexture(nil, "ARTWORK")
   row.icon:SetSize(ROW_H - 4, ROW_H - 4)
   row.icon:SetPoint("LEFT", 2, 0)
   row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
   row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
   row.text:SetPoint("RIGHT", -2, 0)
   row.text:SetJustifyH("LEFT")
   row.text:SetWordWrap(false)
   row:SetScript("OnEnter", function(r) equip:Tooltip(r) end)
   row:SetScript("OnLeave", GameTooltip_Hide)
   row:SetScript("OnClick", function(r)
      equip:Close()
      Choose(r.kind, r.slot)
   end)
   self.rows[index] = row
   return row
end

-- The tooltip of a row: the item, and what the choice does to the class.
function equip:Tooltip(row)
   GameTooltip:SetOwner(row, "ANCHOR_LEFT")
   if row.slot == 0 then
      GameTooltip:SetText(row.kind == "weapon" and L["Unwield"] or L["Take off"], 1, 1, 1)
   else
      ns.ItemInfo.tooltip(G.iven[row.slot], G.ivenarg[row.slot])
   end
   local label, now, after, warning = ns.Equipment.preview(row.kind, row.slot)
   if after ~= now then
      local better = after > now
      GameTooltip:AddLine(format("%s %d > %d (%+d)", label, now, after, after - now),
         better and 0.3 or 1, better and 1 or 0.3, 0.3)
   else
      GameTooltip:AddLine(format(L["%s stays %d"], label, now), 0.7, 0.7, 0.7)
   end
   if warning then GameTooltip:AddLine(warning, 1, 0.5, 0, true) end
   GameTooltip:Show()
end

-- Opens the list for a kind of slot ("weapon", "armor" or "shield"), next to the button.
function equip:Open(kind, anchor)
   if not self.frame then self:Create() end
   local info = KINDS[kind]
   local worn = info.worn()
   local count = 0
   local function Add(slot, text, icon)
      count = count + 1
      local row = Row(self, count)
      row.kind, row.slot = kind, slot
      row.text:SetText(text)
      if icon then
         V.SetIcon(row.icon, icon)
         row.icon:Show()
      else
         row.icon:Hide()
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", PAD, -(22 + (count - 1) * ROW_H))
      row:Show()
   end
   if worn ~= 0 then
      Add(0, "|cffffd100" .. (kind == "weapon" and L["Unwield"] or L["Take off"]) .. "|r")
   end
   for slot = 1, K.IVENSIZE do
      local id = G.iven[slot]
      if id ~= 0 and info.fits(id) then
         local name = "|cff" .. ns.ItemInfo.color(id, G.ivenarg[slot]) .. ns.Player.itemName(slot) .. "|r"
         Add(slot, Letter(slot) .. ") " .. name, V.ObjectIcon(id))
      end
   end
   if count == 0 then
      Add(0, "|cff777777" .. L["Nothing in your pack fits."] .. "|r")
   end
   for index, row in ipairs(self.rows) do
      row:SetShown(index <= count)
      row:SetEnabled(not (count == 1 and row.kind == kind and row.slot == 0 and worn == 0))
   end
   self.title = self.title or self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   self.title:SetPoint("TOPLEFT", PAD + 2, -6)
   self.title:SetText(info.title)
   self.frame:SetSize(ROW_W, 28 + count * ROW_H)
   self.frame:ClearAllPoints()
   self.frame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
   self.catcher:Show()
end

function equip:Close()
   if self.catcher then self.catcher:Hide() end
   GameTooltip:Hide()
end
