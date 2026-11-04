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
                  ns.ui:RefreshNow("map")
               end,
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
            sound = {
               type = "toggle",
               name = L["Sound effects"],
               desc = L["Play sounds for fights, pick-ups, doors and more."],
               order = 16.7,
               get = function() return mod.db.profile.sound ~= false end,
               set = function(_, value) mod.db.profile.sound = value end,
            },
            shadows = {
               type = "toggle",
               name = L["Shadows"],
               desc = L["Draw a shadow under the player and monsters in the 2.5D view."],
               order = 16.8,
               get = function() return mod.db.profile.shadows ~= false end,
               set = function(_, value)
                  mod.db.profile.shadows = value
                  ns.ui:RefreshNow("map")
               end,
            },
            fog = {
               type = "toggle",
               name = L["Distance fog"],
               desc = L["Darken things the further they are from the camera in the 2.5D view."],
               order = 16.9,
               get = function() return mod.db.profile.fog ~= false end,
               set = function(_, value)
                  mod.db.profile.fog = value
                  ns.ui:RefreshNow("map")
               end,
            },
            textures = {
               type = "toggle",
               name = L["Textured ground"],
               desc = L["Draw the floors and walls with textures (and lava in the volcano) instead of flat colours."],
               order = 17.1,
               get = function() return mod.db.profile.textures ~= false end,
               set = function(_, value)
                  mod.db.profile.textures = value
                  ns.ui:RefreshNow("map")
               end,
            },
            actionBar = {
               type = "toggle",
               name = L["Action bar"],
               desc = L["Ten slots for spells, potions and scrolls on the keys 1 to 0 (right-click a slot to choose).  Without it, the digits set a repeat count, as in the original game."],
               order = 17.2,
               get = function() return mod.db.profile.actionBar ~= false end,
               set = function(_, value)
                  mod.db.profile.actionBar = value
                  ns.actionBar:Update()
               end,
            },
            ascii = {
               type = "toggle",
               name = L["Classic letters"],
               desc = L["Draw monsters and things as the original letters instead of pictures."],
               order = 17,
               set = function(_, value)
                  mod.db.profile.ascii = value
                  ns.ui:RefreshNow("map")
               end,
            },
            warnings = {
               type = "toggle",
               name = L["Warnings"],
               desc = L["Show a window when a door shocks you, and when your hit points fall to a quarter or less.  It has to be answered, so a key held down does not carry on through it."],
               order = 17.6,
               get = function() return mod.db.profile.warnings ~= false end,
            },
            scoreItems = {
               type = "toggle",
               name = L["Score counts what you carry"],
               desc = L["The score is your gold and bank balance, as in the original.  On, what the bank and the trading post would pay for the items in your pack counts too.  It applies to every game from now on."],
               order = 17.5,
               get = function() return mod.db.global.scoreItems end,
               set = function(_, value) mod.db.global.scoreItems = value end,
            },
            opaqueIcons = {
               type = "toggle",
               name = L["Square icons"],
               desc = L["Keep the black squares around the icons on the map.  Off, the black is left out so the icons sit on the floor."],
               order = 17.2,
               set = function(_, value)
                  mod.db.profile.opaqueIcons = value
                  ns.ui:RefreshNow("map")
               end,
            },
            cameraAngle = {
               type = "range",
               name = L["Camera angle"],
               desc = L["How high the camera is in the 2.5D view.  Steeper looks more like the flat map."],
               order = 16.5,
               min = 30, max = 80, step = 5,
               get = function() return mod.db.profile.cameraAngle or 55 end,
               set = function(_, value)
                  mod.db.profile.cameraAngle = value
                  ns.ui:RefreshNow("map")
               end,
            },
            zoom3d = {
               type = "range",
               name = L["Zoom"],
               desc = L["How close the camera is in the 2.5D view.  Lower shows more of the map."],
               order = 16.6,
               min = 0.5, max = 1.5, step = 0.05,
               get = function() return mod.db.profile.zoom3d or 1 end,
               set = function(_, value)
                  mod.db.profile.zoom3d = value
                  ns.ui:RefreshNow("map")
               end,
            },
            models = {
               type = "toggle",
               name = L["Creature models"],
               desc = L["Show your character and the monsters as 3D models in the 2.5D view."],
               order = 18,
               get = function() return mod.db.profile.models ~= false end,
               set = function(_, value)
                  mod.db.profile.models = value
                  ns.ui:RefreshNow("map")
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
