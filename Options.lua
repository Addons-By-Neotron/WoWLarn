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
            view = {
               type = "select",
               name = L["Map view"],
               desc = L["The flat tiles, or the 2.5D view from behind the player."],
               order = 15,
               values = { flat = L["Flat tiles"], ["3d"] = L["2.5D"] },
               set = function(_, value)
                  mod.db.profile.view = value
                  ns.ui:Refresh("map")
               end,
            },
            difficulty = {
               type = "range",
               name = L["Difficulty"],
               desc = L["How hard the game is.  Monsters are tougher and the dungeon is meaner.  It applies to games you start from now on."],
               order = 12,
               min = 0, max = 6, step = 1,
            },
            tileSize = {
               type = "range",
               name = L["Tile size"],
               desc = L["The size of a tile in the flat view."],
               order = 16,
               min = 24, max = 48, step = 4,
               get = function() return mod.db.profile.tileSize or 32 end,
               set = function(_, value)
                  mod.db.profile.tileSize = value
                  ns.map:Layout()
               end,
            },
            ascii = {
               type = "toggle",
               name = L["Classic letters"],
               desc = L["Draw monsters and things as the original letters instead of pictures."],
               order = 17,
               set = function(_, value)
                  mod.db.profile.ascii = value
                  ns.ui:Refresh("map")
               end,
            },
            minimap = {
               type = "toggle",
               name = L["Minimap button"],
               desc = L["Show a button on the minimap."],
               order = 30,
               get = function() return not mod.db.profile.minimap.hide end,
               set = function(_, value)
                  mod.db.profile.minimap.hide = not value
                  mod:UpdateMinimapButton()
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
