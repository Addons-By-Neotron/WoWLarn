--[[
**********************************************************************
WoWLarn - Class picker shown at the start of a game.
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
local V = ns.Visuals

local picker = {}
ns.picker = picker

local ROW_H, WIDTH = 40, 520

local function ClassName(token)
   local names = LOCALIZED_CLASS_NAMES_MALE
   return names and names[token] or token
end

local function Summary(class)
   local s = class.stats
   return format("%s %d  %s %d  %s %d  %s %d  %s %d  %s %d  %s %d", L["HP"], class.hp,
      L["STR"], s[1], L["INT"], s[2], L["WIS"], s[3], L["CON"], s[4], L["DEX"], s[5], L["CHA"], s[6])
end

local function ShowTooltip(row)
   local class = row.class
   GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
   GameTooltip:SetText(ClassName(class.token))
   for _, entry in ipairs(class.kit) do
      GameTooltip:AddLine(ns.Tables.objectname[entry[1]] or "?", 1, 1, 1)
   end
   GameTooltip:Show()
end

function picker:Create(parent)
   local frame = ns.CreatePanel(parent, nil, { 0.04, 0.04, 0.06, 0.97 })
   frame:SetFrameLevel(parent:GetFrameLevel() + 120)
   frame:SetSize(WIDTH, 60 + #ns.Classes * ROW_H)
   frame:SetPoint("CENTER")
   frame:EnableMouse(true)
   frame:Hide()
   local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   title:SetPoint("TOP", 0, -12)
   title:SetText(L["Choose your class"])
   local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
   hint:SetText(L["Click a class, or press its letter. Enter takes the highlighted one."])

   self.rows = {}
   for index, class in ipairs(ns.Classes) do
      local row = CreateFrame("Button", nil, frame)
      row:SetHeight(ROW_H - 4)
      row:SetPoint("TOPLEFT", 10, -50 - (index - 1) * ROW_H)
      row:SetPoint("TOPRIGHT", -10, -50 - (index - 1) * ROW_H)
      row.class = class
      row.highlight = row:CreateTexture(nil, "BACKGROUND")
      row.highlight:SetAllPoints()
      row.highlight:SetColorTexture(1, 0.82, 0, 0.18)
      row.highlight:Hide()
      local icon = row:CreateTexture(nil, "ARTWORK")
      icon:SetSize(32, 32)
      icon:SetPoint("LEFT", 4, 0)
      icon:SetTexture(V.ClassIcon(class))
      local letter = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      letter:SetPoint("LEFT", icon, "RIGHT", 8, 0)
      letter:SetText(class.letter .. ")")
      local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      name:SetPoint("LEFT", letter, "RIGHT", 6, 6)
      name:SetText(ClassName(class.token))
      local detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
      detail:SetText(Summary(class))
      row:SetScript("OnClick", function() ns.ui:InjectKey(class.letter) end)
      row:SetScript("OnEnter", ShowTooltip)
      row:SetScript("OnLeave", GameTooltip_Hide)
      self.rows[index] = row
   end
   self.frame = frame
   return frame
end

function picker:Select(index)
   for i, row in ipairs(self.rows) do
      row.highlight:SetShown(i == index)
   end
end

function picker:Show(classes, selected)
   self:Select(selected)
   self.frame:Show()
end

function picker:Hide()
   self.frame:Hide()
end
