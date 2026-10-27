--[[
**********************************************************************
WoWLarn - Shared widget helpers.
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
local _, ns = ...

local BORDER = { 0.35, 0.35, 0.4, 1 }
local BACKGROUND = { 0.04, 0.04, 0.06, 0.92 }

ns.COLOR_BORDER = BORDER
ns.COLOR_FOCUS = { 1, 0.82, 0, 1 }

-- A flat dark panel with a one pixel border.
function ns.CreatePanel(parent, name, background)
   local panel = CreateFrame("Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
   if panel.SetBackdrop then
      panel:SetBackdrop({
         bgFile = "Interface\\Buttons\\WHITE8X8",
         edgeFile = "Interface\\Buttons\\WHITE8X8",
         edgeSize = 1,
      })
      panel:SetBackdropColor(unpack(background or BACKGROUND))
      panel:SetBackdropBorderColor(unpack(BORDER))
   end
   return panel
end
