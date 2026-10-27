--[[
**********************************************************************
WoWLarn - Configuration options.
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
local mod = LibStub("AceAddon-3.0"):GetAddon("WoWLarn")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfig = LibStub("AceConfig-3.0")

local APP_NAME = "WoWLarn"

local options

local function Get(info)
   return mod.db.profile[info[#info]]
end

local function Set(info, value)
   mod.db.profile[info[#info]] = value
end

local function BuildOptions()
   options = {
      general = {
         type = "group",
         name = L["General"],
         get = Get,
         set = Set,
         args = {
            scale = {
               type = "range",
               name = L["Window scale"],
               order = 10,
               min = 0.5, max = 2, step = 0.05, isPercent = true,
               set = function(_, value)
                  mod.db.profile.scale = value
                  ns.main:ApplyScale()
               end,
            },
            fast = {
               type = "toggle",
               name = L["Fast mode"],
               desc = L["Skip the short pauses between game steps, such as spell animations."],
               order = 20,
               width = "full",
            },
         },
      },
   }
   options.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(mod.db)
end

function mod:OptReg(optname, tbl, dispname)
   if dispname then
      optname = APP_NAME .. optname
      AceConfig:RegisterOptionsTable(optname, tbl)
      return AceConfigDialog:AddToBlizOptions(optname, dispname, APP_NAME)
   else
      AceConfig:RegisterOptionsTable(optname, tbl)
      return AceConfigDialog:AddToBlizOptions(optname, APP_NAME)
   end
end

function mod:SetupOptions()
   BuildOptions()
   self.optionsMain = self:OptReg(APP_NAME, options.general)
   self.optionsEnd = self:OptReg(": Profiles", options.profiles, L["Profiles"])
end

function mod:NotifyOptionsChanged()
   AceConfigRegistry:NotifyChange(APP_NAME)
end
