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
local _, ns = ...

local mod = LibStub("AceAddon-3.0"):NewAddon("WoWLarn", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "LibMagicUtil-1.0")
LibStub("LibLogger-1.0"):Embed(mod)
ns.mod = mod

----------------------------------------------------------------
-- Saved variable defaults
----------------------------------------------------------------

mod.defaults = {
   profile = {
      scale = 1,
      difficulty = 0,
      minimap = { hide = false },
      view = "flat",  -- "flat" tiles or the "3d" view
      fast = false,  -- skip the delays (naps) between game steps
      window = { point = "CENTER", x = 0, y = 0 },
   },
   char = {},  -- game = the game being played, see Save.lua
   global = {
      scores = { winners = {}, dead = {} },  -- the scoreboards, see Scores.lua
      taxes = {},  -- what each winner owes the LRS
      displays = {},  -- [monster id] = the display chosen in the model viewer
      scales = {},  -- [display id] = the size set in the model viewer (Visuals.Scale)
      rooms = {},  -- [display id] = the room set in the model viewer (Visuals.Room)
      lowers = {},  -- [display id] = how far the model is moved down, set in the model viewer (Visuals.Lower)
      turns = {},  -- [display id] = the turn (radians) set in the model viewer (Visuals.Turn)
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

-- The launcher for the data broker displays (and the minimap button), when the libraries are
-- there.
function mod:SetupLauncher()
   local ldb = LibStub("LibDataBroker-1.1", true)
   if not ldb then return end
   self.launcher = ldb:NewDataObject("WoWLarn", {
      type = "launcher",
      icon = "Interface\\Icons\\INV_Misc_Book_08",
      OnClick = function(_, button)
         if button == "RightButton" then
            self:OpenConfig()
         else
            ns.main:Toggle()
         end
      end,
      OnTooltipShow = function(tooltip)
         tooltip:AddLine("WoWLarn")
         tooltip:AddLine(L["Click to open or close the game."], 1, 1, 1)
         tooltip:AddLine(L["Right-click for the settings."], 1, 1, 1)
      end,
   })
   local icon = LibStub("LibDBIcon-1.0", true)
   if icon then icon:Register("WoWLarn", self.launcher, self.db.profile.minimap) end
end

function mod:UpdateMinimapButton()
   local icon = LibStub("LibDBIcon-1.0", true)
   if not icon then return end
   if self.db.profile.minimap.hide then icon:Hide("WoWLarn") else icon:Show("WoWLarn") end
end

function mod:OnEnable()
   self:SetupLauncher()
   self:RegisterEvent("PLAYER_LOGOUT", function() ns.Save.store() end)
end

function mod:OnDisable()
end

function mod:ApplyProfile()
   ns.main:ApplyScale()
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
   self:info(L["/larn  - show/hide the game window"])
   self:info(L["/larn config  - open settings"])
   self:info(L["/larn view  - flat tiles or the 2.5D view"])
   self:info(L["/larn scores  - show the high scores"])
   self:info(L["/larn sounds  - play every sound effect"])
   self:info(L["/larn reset  - reset the window position"])
end

-- Flat tiles or the 2.5D view.
function mod:ToggleView()
   self.db.profile.view = self.db.profile.view == "3d" and "flat" or "3d"
   ns.ui:Refresh("map")
   if ns.bar.UpdateView then ns.bar:UpdateView() end
end

function mod:ChatCommand(input)
   local cmd = strtrim(input or ""):lower()
   if cmd == "" then
      ns.main:Toggle()
   elseif cmd == "config" then
      self:OpenConfig()
   elseif cmd == "view" or cmd == "3d" then
      self:ToggleView()
   elseif cmd == "sounds" then
      ns.ui:TestSounds()
   elseif cmd == "scores" then
      ns.main:Show()
      ns.scoreboard:Show()
   elseif cmd == "models" then
      ns.modelViewer:Toggle()
   elseif cmd == "zoo" then
      ns.zoo:Toggle()
   elseif cmd == "reset" then
      ns.main:ResetPosition()
   elseif cmd == "help" then
      self:PrintHelp()
--@debug@
   elseif cmd == "new" then
      ns.ui.co = nil
      ns.main:Show()
      if not ns.ui:IsActive() then ns.ui:NewGame() end
   elseif cmd == "mapdebug" then
      ns.map:Debug()
   elseif cmd == "debug" then
      ns.debugPanel:Toggle()
   elseif cmd == "wizard" then
      ns.Debug.toggleWizard()
   elseif cmd == "god" then
      ns.Debug.toggleGod()
--@end-debug@
   else
      self:PrintHelp()
   end
end
