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
      discovered = {},  -- [object id] = true: items whose special power the player has seen at work (ItemInfo.discover)
      bestiary = {},  -- [monster id] = { level, kills, specials }: what has been seen of each monster (Bestiary.lua)
      displays = {},  -- [monster id] = the display chosen in the model viewer
      scales = {},  -- [display id] = the size set in the model viewer (Visuals.Scale)
      rooms = {},  -- [display id] = the room set in the model viewer (Visuals.Room)
      lowers = {},  -- [display id] = how far the model is moved down, set in the model viewer (Visuals.Lower)
      textures = {},  -- [level .. slot] = file data id: set with the texture browser (debug builds), until the next reload
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

   -- What the model viewer set lasts until the next reload: the game starts from the tables in
   -- Data/Visuals.lua (see Visuals Own).
   for _, key in ipairs({ "displays", "scales", "rooms", "lowers", "turns", "textures" }) do
      wipe(self.db.global[key])
   end

   self:SetupOptions()
   self:RegisterChatCommand("larn", "ChatCommand")
   self:RegisterChatCommand("wowlarn", "ChatCommand")
end

--@debug@
-- /larn tex floor|wall|lava <id | + | ->: sets the texture of the slot for this level until the
-- next reload; + and - take the next and the previous file data id.  The texture browser
-- (/larn debug, Textures) is easier.
function mod:TryTexture(cmd)
   local slot, what = cmd:match("^tex%s+(%a+)%s*(%S*)")
   local V = ns.Visuals
   local level = ns.G.level or 1
   if slot ~= "floor" and slot ~= "wall" and slot ~= "lava" then
      self:Print("/larn tex floor|wall|lava <id|+|->   (level now: " .. level .. ")")
      return
   end
   local id = V.Texture(level, slot) or 127718
   if what == "+" then id = id + 1 elseif what == "-" then id = id - 1 elseif tonumber(what) then id = tonumber(what) end
   self.db.global.textures[level .. slot] = id
   self:Print(format("level %d %s: %d", level, slot, id))
   ns.ui:RefreshNow("map")
end
--@end-debug@

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
--@debug@
   self:info("Debug build:")
   self:info("/larn debug  - the debug panel")
   self:info("/larn wizard  - wizard mode on or off")
   self:info("/larn god  - god mode on or off")
   self:info("/larn new  - give this game up and start another")
   self:info("/larn models  - the model viewer (choose the look of the monsters)")
   self:info("/larn zoo  - all the monsters in one place")
   self:info("/larn mapdebug  - what the map is drawing")
   self:info("/larn tex floor|wall|lava <id|+|->  - try textures for this level")
--@end-debug@
end

-- Flat tiles or the 2.5D view.
function mod:ToggleView()
   self.db.profile.view = self.db.profile.view == "3d" and "flat" or "3d"
   ns.ui:RefreshNow("map")
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
   elseif cmd:match("^tex") then
      self:TryTexture(cmd)
   elseif cmd == "new" then
      ns.Debug.newGame()
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
