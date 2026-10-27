--[[
**********************************************************************
WoWLarn - Map view region.
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

local map = {}
ns.map = map

function map:Create(parent)
   local frame = ns.CreatePanel(parent)
   local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
   text:SetPoint("CENTER", 0, 20)
   text:SetText(L["Map view"])
   local debug = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   debug:SetPoint("TOP", text, "BOTTOM", 0, -12)
   self.debug = debug
   self.frame = frame
   return frame
end

function map:SetDebugText(message)
   if self.debug then self.debug:SetText(message or "") end
end
