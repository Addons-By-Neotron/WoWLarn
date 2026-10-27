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

L["Available commands:"] = true
L["/larn  - show/hide the game window"] = true
L["/larn config  - open settings"] = true
L["/larn reset  - reset the window position"] = true
L["General"] = true
L["Window scale"] = true
L["Fast mode"] = true
L["Skip the short pauses between game steps, such as spell animations."] = true
L["Profiles"] = true
L["The game crashed. Press any key to start over."] = true
L["(cancelled)"] = true
L["--- press space to continue ---"] = true
L["(direction)"] = true
L["The blindness lifts."] = true
L["You regain your senses."] = true
L["You now feel better."] = true
L["Your vision returns to normal."] = true
L["The hysteria of itching forces you to remove your armor!"] = true
L["The irritation subsides."] = true
L["You now feel less awkward."] = true
L["There is %s here. (Not implemented yet.)"] = true
L["Do you really want to quit?"] = true
L["Game over. Press any key to start again."] = true
L["WoWLarn - a port of Ularn 1.5 (the Addiction of Ularn)."] = true
L["That command is not implemented yet."] = true
L["You set out as %s."] = true
L["HP"] = true
L["STR"] = true
L["INT"] = true
L["WIS"] = true
L["CON"] = true
L["DEX"] = true
L["CHA"] = true
L["Originally: %s"] = true
L["Choose your class"] = true
L["Click a class, or press its letter. Enter takes the highlighted one."] = true
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
L["Keyboard captured - Esc to release"] = true
L["Click the window to use the keyboard"] = true
L["No"] = true
L["Yes"] = true
L["Continue"] = true
L["Map"] = true
L["Portraits"] = true
L["Stats"] = true
L["Effects"] = true
L["Depth: %s"] = true
L["Spells"] = true
L["Exp"] = true
L["AC"] = true
L["WC"] = true
L["Level"] = true
L["Gold"] = true
L["%d mobuls left"] = true
