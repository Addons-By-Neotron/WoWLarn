--[[
**********************************************************************
WoWLarn - The window for placing the model of the player (debug builds only).
**********************************************************************
This file is part of WoWLarn, a World of Warcraft addon.

WoWLarn is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, version 2 of the
License.

WoWLarn is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with WoWLarn. If
not, see <http://www.gnu.org/licenses/>.
**********************************************************************
]]
local _, ns = ...

-- The form tuner (/larn form, or the debug panel): the player model of the form you are in (a
-- druid's, a mount) with its size and place, by model file id (Visuals.Form).  The values last
-- until the next reload; Print gives the line to put in V.FORM.
local tuner = {}
ns.formTuner = tuner

local WIDTH, ROW_H = 300, 28
-- key, label, step, default
local ROWS = {
   { "scale", "Scale (above 1: smaller)", 0.1, 1 },
   { "shift", "Shift sideways (tiles)", 0.05, 0 },
   { "lower", "Lower", 0.05, 0 },
   { "room", "Room (frame size)", 0.5, 2 },
}

function tuner:Current()
   local file = ns.map3d.playerFile
   if not file then return nil end
   local now = ns.Visuals.Form(file) or {}
   return file, now
end

function tuner:Change(key, by)
   local file, now = self:Current()
   if not file then return end
   local row
   for _, entry in ipairs(ROWS) do if entry[1] == key then row = entry end end
   local forms = ns.mod.db.global.forms
   forms[file] = { scale = now.scale, shift = now.shift, lower = now.lower, room = now.room }
   local value = (now[key] or row[4]) + by
   forms[file][key] = math.floor(value * 100 + 0.5) / 100
   ns.ui:RefreshNow("map")
   self:Update()
end

function tuner:Reset()
   local file = ns.map3d.playerFile
   if file then ns.mod.db.global.forms[file] = nil end
   ns.ui:RefreshNow("map")
   self:Update()
end

function tuner:Line()
   local file, now = self:Current()
   if not file then return nil end
   return format("   [%d] = { scale = %s, shift = %s, lower = %s, room = %s },  -- the model of the player", file,
      tostring(now.scale or 1), tostring(now.shift or 0), tostring(now.lower or 0), tostring(now.room or 2))
end

function tuner:Print()
   local line = self:Line()
   ns.mod:Print(line or "form: no player model yet")
end

function tuner:Update()
   if not self.frame or not self.frame:IsShown() then return end
   local file, now = self:Current()
   self.title:SetText(file and format("Model %d", file) or "No player model yet (start the game)")
   for _, row in ipairs(self.rows) do
      row.value:SetText(file and tostring(now and now[row.key] or row.default) or "-")
   end
end

function tuner:Create()
   local frame = ns.CreatePanel(UIParent, "WoWLarnFormTuner")
   frame:SetSize(WIDTH, 80 + #ROWS * ROW_H + 30)
   frame:SetPoint("CENTER", 300, 0)
   frame:SetFrameStrata("FULLSCREEN_DIALOG")
   frame:SetToplevel(true)
   frame:SetMovable(true)
   frame:EnableMouse(true)
   frame:RegisterForDrag("LeftButton")
   frame:SetScript("OnDragStart", frame.StartMoving)
   frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
   frame:Hide()
   tinsert(UISpecialFrames, "WoWLarnFormTuner")
   self.frame = frame

   local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   heading:SetPoint("TOP", 0, -8)
   heading:SetText("Player model place")
   self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   self.title:SetPoint("TOP", heading, "BOTTOM", 0, -4)

   self.rows = {}
   for index, entry in ipairs(ROWS) do
      local key, label, step, default = unpack(entry)
      local y = -50 - (index - 1) * ROW_H
      local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      text:SetPoint("TOPLEFT", 12, y - 6)
      text:SetText(label)
      local more = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
      more:SetSize(24, 22)
      more:SetPoint("TOPRIGHT", -10, y)
      more:SetText("+")
      more:SetScript("OnClick", function() self:Change(key, step) end)
      local value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      value:SetPoint("RIGHT", more, "LEFT", -4, 0)
      value:SetWidth(44)
      local less = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
      less:SetSize(24, 22)
      less:SetPoint("RIGHT", value, "LEFT", -4, 0)
      less:SetText("-")
      less:SetScript("OnClick", function() self:Change(key, -step) end)
      self.rows[index] = { key = key, default = default, value = value }
   end

   local print = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   print:SetSize(120, 22)
   print:SetPoint("BOTTOMLEFT", 10, 10)
   print:SetText("Print the line")
   print:SetScript("OnClick", function() self:Print() end)
   local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   reset:SetSize(80, 22)
   reset:SetPoint("LEFT", print, "RIGHT", 6, 0)
   reset:SetText("Reset")
   reset:SetScript("OnClick", function() self:Reset() end)
   frame:SetScript("OnShow", function() self:Update() end)
end

function tuner:Toggle()
   if not self.frame then self:Create() end
   self.frame:SetShown(not self.frame:IsShown())
end
