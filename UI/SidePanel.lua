--[[
**********************************************************************
WoWLarn - Side panel: minimap, portraits, stats and effects.
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

local side = {}
ns.side = side

local GAP = 4
local MINIMAP_H, PORTRAIT_H, STATS_H = 120, 100, 170

local function Section(parent, height, title)
   local panel = ns.CreatePanel(parent)
   panel:SetHeight(height)
   local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   label:SetPoint("TOPLEFT", 4, -3)
   label:SetText(title)
   return panel
end

function side:Create(parent)
   local frame = CreateFrame("Frame", nil, parent)

   local minimap = Section(frame, MINIMAP_H, L["Map"])
   minimap:SetPoint("TOPLEFT")
   minimap:SetPoint("TOPRIGHT")

   local portraits = Section(frame, PORTRAIT_H, L["Portraits"])
   portraits:SetPoint("TOPLEFT", minimap, "BOTTOMLEFT", 0, -GAP)
   portraits:SetPoint("TOPRIGHT", minimap, "BOTTOMRIGHT", 0, -GAP)
   local player = CreateFrame("PlayerModel", nil, portraits)
   player:SetPoint("TOPLEFT", 4, -16)
   player:SetPoint("BOTTOMRIGHT", portraits, "BOTTOM", -2, 4)
   pcall(player.SetUnit, player, "player")
   pcall(player.SetPortraitZoom, player, 0.8)
   self.player = player
   self.target = CreateFrame("PlayerModel", nil, portraits)
   self.target:SetPoint("TOPLEFT", portraits, "TOP", 2, -16)
   self.target:SetPoint("BOTTOMRIGHT", -4, 4)

   local stats = Section(frame, STATS_H, L["Stats"])
   stats:SetPoint("TOPLEFT", portraits, "BOTTOMLEFT", 0, -GAP)
   stats:SetPoint("TOPRIGHT", portraits, "BOTTOMRIGHT", 0, -GAP)
   local text = stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   text:SetPoint("TOPLEFT", 6, -18)
   text:SetJustifyH("LEFT")
   text:SetSpacing(2)
   text:SetText("HP: --\nSpells: --\nSTR -- INT -- WIS --\nCON -- DEX -- CHA --\nAC -- WC --\nLevel --  Exp --\nGold --  Depth --\nTime --")
   self.statsText = text

   local effects = Section(frame, 40, L["Effects"])
   effects:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -GAP)
   effects:SetPoint("BOTTOMRIGHT")

   self.frame = frame
   return frame
end
