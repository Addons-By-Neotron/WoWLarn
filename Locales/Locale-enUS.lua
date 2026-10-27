--[[
**********************************************************************
WoWLarn - Localization.
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
local isSilent = true
--@debug@
isSilent = false
--@end-debug@

local L = LibStub("AceLocale-3.0"):NewLocale("WoWLarn", "enUS", true, isSilent)

L["General"] = true
L["Profiles"] = true
L["Available commands:"] = true
L["/larn config  - open settings"] = true
