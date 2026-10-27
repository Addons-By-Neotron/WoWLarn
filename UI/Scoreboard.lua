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

-- The scoreboards (C: showscores(), showallscores()): the winners and the dead, with the
-- inventory of the dead as the tooltip of their line. It is a window of its own, because
-- it is shown when the game is over.
local scoreboard = {}
ns.scoreboard = scoreboard

local ROW_H, ROW_W = 16, 540
local HEADER_H = 54

function scoreboard:Create(parent)
   local frame = ns.CreatePanel(parent, nil, { 0.04, 0.04, 0.06, 0.97 })
   frame:SetFrameStrata("DIALOG")
   frame:SetFrameLevel(parent:GetFrameLevel() + 150)
   frame:SetSize(ROW_W + 16, HEADER_H + K.SCORESIZE * ROW_H + 12)
   frame:SetPoint("CENTER")
   frame:EnableMouse(true)
   frame:Hide()
   self.frame = frame

   local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   title:SetPoint("TOP", 0, -10)
   title:SetText(L["U L A R N    S C O R E S"])

   self.tabs = {}
   for index, tab in ipairs({ { "winners", L["Winners"] }, { "dead", L["The dead"] } }) do
      local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
      button:SetSize(90, 20)
      button:SetPoint("TOPLEFT", 8 + (index - 1) * 94, -28)
      button:SetText(tab[2])
      button:SetScript("OnClick", function() self:Select(tab[1]) end)
      self.tabs[tab[1]] = button
   end
   local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
   close:SetPoint("TOPRIGHT", 2, 2)

   self.rows = {}
   for index = 1, K.SCORESIZE do
      local row = CreateFrame("Button", nil, frame)
      row:SetSize(ROW_W, ROW_H)
      row:SetPoint("TOPLEFT", 8, -(HEADER_H + (index - 1) * ROW_H))
      row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.text:SetPoint("LEFT", 2, 0)
      row.text:SetPoint("RIGHT", -2, 0)
      row.text:SetJustifyH("LEFT")
      row.text:SetWordWrap(false)
      row:SetScript("OnEnter", function(self)
         local entry = self.entry
         if not entry or not entry.inventory then return end
         GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
         GameTooltip:SetText(entry.who)
         for _, item in ipairs(entry.inventory) do
            if item[1] ~= 0 then
               GameTooltip:AddLine(ns.Tables.objectname[item[1]] .. (item[2] ~= 0 and (" " .. item[2]) or ""), 1, 1, 1)
            end
         end
         GameTooltip:Show()
      end)
      row:SetScript("OnLeave", GameTooltip_Hide)
      self.rows[index] = row
   end
   return frame
end

local function Line(kind, rank, entry, highlight)
   local text
   if kind == "winners" then
      text = format(L["%2d) %9d  %s (%s), %d mobuls, difficulty %d"], rank, entry.score, entry.who, entry.class, entry.time, entry.hardlev)
   else
      text = format("%2d) %9d  %s (%s), %s", rank, entry.score, entry.who, entry.class,
         ns.Scores.deathLine(entry.what, entry.level, entry.sex))
   end
   return highlight and ("|cffffd100" .. text .. "|r") or text
end

function scoreboard:Select(kind)
   self.kind = kind
   local list = kind == "winners" and ns.Scores.winners() or ns.Scores.dead()
   for index, row in ipairs(self.rows) do
      local entry = list[index]
      row.entry = entry
      if entry then
         row.text:SetText(Line(kind, index, entry, entry == self.highlight))
         row:Show()
      else
         row:Hide()
      end
   end
   for name, button in pairs(self.tabs) do
      button:SetEnabled(name ~= kind)
   end
end

-- Shows the list the entry is in (or the winners), marking the entry.
function scoreboard:Show(entry)
   if not self.frame then return end
   self.highlight = entry
   self:Select(entry and entry.what ~= ns.Scores.WIN and "dead" or "winners")
   self.frame:Show()
end

function scoreboard:Hide()
   if self.frame then self.frame:Hide() end
end
