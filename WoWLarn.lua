--[[
**********************************************************************
WoWLarn - Addon setup, events and slash commands.
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

local mod = LibStub("AceAddon-3.0"):NewAddon("WoWLarn", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "LibMagicUtil-1.0")
LibStub("LibLogger-1.0"):Embed(mod)

----------------------------------------------------------------
-- Saved variable defaults
----------------------------------------------------------------

mod.defaults = {
   profile = {
   },
}

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function mod:OnInitialize()
   self.db = LibStub("AceDB-3.0"):New("WoWLarnDB", self.defaults, "Default")
   self.db.RegisterCallback(self, "OnProfileChanged", "ApplyProfile")
   self.db.RegisterCallback(self, "OnProfileCopied", "ApplyProfile")
   self.db.RegisterCallback(self, "OnProfileReset", "ApplyProfile")

   self:SetupOptions()
   self:RegisterChatCommand("larn", "ChatCommand")
   self:RegisterChatCommand("wowlarn", "ChatCommand")
end

function mod:OnEnable()
end

function mod:OnDisable()
end

function mod:ApplyProfile()
   self:NotifyOptionsChanged()
end

----------------------------------------------------------------
-- Slash command
----------------------------------------------------------------

function mod:OpenConfig()
   self:InterfaceOptionsFrame_OpenToCategory(self.optionsEnd)
   self:InterfaceOptionsFrame_OpenToCategory(self.optionsMain)
end

function mod:PrintHelp()
   self:info(L["Available commands:"])
   self:info(L["/larn config  - open settings"])
end

function mod:ChatCommand(input)
   local cmd = strtrim(input or ""):lower()
   if cmd == "config" then
      self:OpenConfig()
   else
      self:PrintHelp()
   end
end
