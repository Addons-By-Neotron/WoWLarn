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
local G = ns.G
local format = string.format

-- The spellbook (the spells you know, shown while casting; C: the list of cast()) and the
-- list of discoveries (C: seemagic()). Clicking a spell answers the pending request with
-- its three letters.
local spellbook = {}
ns.spellbook = spellbook

local COLUMNS = 3
local COLUMN_W, ROW_H = 220, 22
local HEADER_H, LINE_H = 26, 14

function spellbook:Create(parent)
   local frame = ns.CreatePanel(parent)
   frame:SetFrameStrata("DIALOG")
   frame:SetFrameLevel(parent:GetFrameLevel() + 1220)
   frame:SetWidth(COLUMNS * COLUMN_W + 16)
   frame:SetPoint("CENTER")
   frame:EnableMouse(true)
   frame:Hide()
   self.frame = frame

   self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   self.title:SetPoint("TOPLEFT", 8, -6)

   self.buttons = {}
   for index = 1, K.SPNUM do
      local button = CreateFrame("Button", nil, frame)
      button:SetSize(COLUMN_W - 4, ROW_H - 2)
      button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      button.text:SetPoint("LEFT", 4, 0)
      button.text:SetPoint("RIGHT", -2, 0)
      button.text:SetJustifyH("LEFT")
      button.index = index
      button:SetScript("OnClick", function(self)
         ns.main:SetFocus(true)
         local code = ns.Tables.spelcode[self.index]
         for letter in code:gmatch(".") do
            ns.ui:InjectKey(letter)
         end
      end)
      button:SetScript("OnEnter", function(self)
         GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
         local SI = ns.SpellInfo
         GameTooltip:SetText(ns.Tables.spelname[self.index], 1, 1, 1)
         GameTooltip:AddDoubleLine(L["1 Mana"], SI.kind(self.index) or "", 1, 1, 1, 1, 1, 1)
         GameTooltip:AddLine(L["Instant"], 1, 1, 1)
         local effect = SI.info(self.index)
         if effect then GameTooltip:AddLine(effect, 1, 0.82, 0, true) end
         if SI.risky(self.index) then GameTooltip:AddLine(L["Risky: it can backfire!"], 1, 0.3, 0.3, true) end
         if SI.minLevel(self.index) > ns.G.c[K.LEVEL] then
            GameTooltip:AddLine(L["Might not work at your level"], 1, 0.5, 0, true)
         end
         GameTooltip:Show()
      end)
      button:SetScript("OnLeave", GameTooltip_Hide)
      button:Hide()
      self.buttons[index] = button
   end

   -- The three columns of text of the list of discoveries.
   self.columns = {}
   for column = 1, COLUMNS do
      local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      text:SetPoint("TOPLEFT", 8 + (column - 1) * COLUMN_W, -HEADER_H)
      text:SetJustifyH("LEFT")
      text:SetJustifyV("TOP")
      text:SetWidth(COLUMN_W - 8)
      text:SetHeight(300)  -- (a text that does not wrap shows only its first line)
      text:Hide()
      self.columns[column] = text
   end
   return frame
end

function spellbook:IsShown()
   return self.frame and self.frame:IsShown()
end

function spellbook:Close()
   if self.frame then self.frame:Hide() end
end

-- Shows the spells that are known (all of them if all is set, as for the genie), to pick
-- one by clicking it.
function spellbook:Open(all)
   if not self.frame then return end
   local T = ns.Tables
   self.title:SetText(all and L["All spells"] or L["Your spells"])
   for _, text in ipairs(self.columns) do text:Hide() end
   local shown = 0
   for index, button in ipairs(self.buttons) do
      if all or G.spelknow[index] ~= 0 then
         button:ClearAllPoints()
         button:SetPoint("TOPLEFT", 8 + (shown % COLUMNS) * COLUMN_W, -(HEADER_H + math.floor(shown / COLUMNS) * ROW_H))
         local _, short = ns.SpellInfo.info(index)
         button.text:SetText("|cffffd100" .. T.spelcode[index] .. "|r  " .. T.spelname[index]
            .. (short and ("  |cff66ff66" .. short .. "|r") or "") .. (ns.SpellInfo.risky(index) and "  |cffff4d4d!|r" or ""))
         button:Show()
         shown = shown + 1
      else
         button:Hide()
      end
   end
   self.frame:SetHeight(HEADER_H + math.max(1, math.ceil(shown / COLUMNS)) * ROW_H + 8)
   self.frame:Show()
end

-- C: seemagic(). The spells, scrolls and potions found so far.
function spellbook:ShowDiscoveries()
   if not self.frame then return end
   local T = ns.Tables
   self.title:SetText(L["Discoveries"])
   for _, button in ipairs(self.buttons) do button:Hide() end

   local lines = { {}, {}, {} }
   local function Add(title, names)
      if #names == 0 then return end
      local row = #lines[1] + 1
      lines[1][row], lines[2][row], lines[3][row] = "|cffffd100" .. title .. "|r", "", ""
      for i, name in ipairs(names) do
         local column = (i - 1) % COLUMNS + 1
         local line = row + math.floor((i - 1) / COLUMNS) + 1
         for c = 1, COLUMNS do lines[c][line] = lines[c][line] or "" end
         lines[column][line] = name
      end
      local last = row + math.ceil(#names / COLUMNS) + 1
      for c = 1, COLUMNS do lines[c][last] = "" end
   end

   local spells, scrolls, potions = {}, {}, {}
   for i = 1, K.SPNUM do
      if G.spelknow[i] ~= 0 then spells[#spells + 1] = T.spelcode[i] .. "  " .. T.spelname[i] end
   end
   for i = 1, K.MAXSCROLL do
      if G.scrollknown[i] ~= 0 and T.scrollname[i] ~= "" then scrolls[#scrolls + 1] = T.scrollname[i] end
   end
   for i = 1, K.MAXPOTION do
      if G.potionknown[i] ~= 0 and T.potionname[i] ~= "" then potions[#potions + 1] = T.potionname[i] end
   end
   Add(L["Spells discovered"], spells)
   Add(L["Scrolls found"], scrolls)
   Add(L["Potions found"], potions)

   for column, text in ipairs(self.columns) do
      text:SetText(table.concat(lines[column], "\n"))
      text:Show()
   end
   self.frame:SetHeight(HEADER_H + math.max(1, #lines[1]) * LINE_H + 8)
   self.frame:Show()
end
