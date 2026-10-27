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
L["/larn  - show/hide the game window"] = true
L["/larn config  - open settings"] = true
L["/larn reset  - reset the window position"] = true
L["Window scale"] = true
L["Fast mode"] = true
L["Skip the short pauses between game steps, such as spell animations."] = true
L["Yes"] = true
L["No"] = true
L["Continue"] = true
L["Map"] = true
L["Portraits"] = true
L["Stats"] = true
L["Effects"] = true
L["Map view"] = true
L["Keyboard captured - Esc to release"] = true
L["Click the window to use the keyboard"] = true
L["Inventory"] = true
L["Wield weapon"] = true
L["Wear armor"] = true
L["Take off armor"] = true
L["Drop item"] = true
L["Quaff potion"] = true
L["Read scroll"] = true
L["Eat cookie"] = true
L["Cast spell"] = true
L["Close door"] = true
L["Find traps"] = true
L["Rest"] = true
L["Teleport"] = true
L["Discoveries"] = true
L["Help"] = true
L["Save and close"] = true
L["Key: %s"] = true
L["(cancelled)"] = true
L["--- press space to continue ---"] = true
L["(direction)"] = true
L["The game crashed. Press any key to start over."] = true
L["Welcome to WoWLarn."] = true
L["Milestone 1: keys are echoed. Q quit, N number, M more, P pause, D direction, S save and close."] = true
L["Last key: %s"] = true
L["Really quit?"] = true
L["Game over. Press any key to start again."] = true
L["How many?"] = true
L["Number: %d"] = true
L["Some text first."] = true
L["And then some more."] = true
L["Pausing for two seconds..."] = true
L["Done."] = true
L["Which way?"] = true
L["Direction: %s"] = true
