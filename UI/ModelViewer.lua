--[[
**********************************************************************
WoWLarn - a port of Ularn 1.5 to World of Warcraft
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
local L = LibStub("AceLocale-3.0"):GetLocale("WoWLarn")
local _, ns = ...
local K = ns.K

-- The model viewer (/larn models): steps through creature displays so one can be chosen for
-- each monster of the game.  What is set here shows in the 2.5D view straight away and lasts
-- until the next reload (the saved values are cleared when the addon loads, so the game starts
-- from Data/Visuals.lua); the values are put in Data/Visuals.lua by hand.
local viewer = {}
ns.modelViewer = viewer

local WIDTH, MODEL_H, LIST_W, ROW_H = 340, 300, 190, 18

local function Name(id)
   local data = ns.MonsterData[id]
   return data and data.name or "?"
end

function viewer:Create()
   local frame = ns.CreatePanel(UIParent, "WoWLarnModelViewer")
   frame:SetSize(WIDTH + LIST_W, MODEL_H + 210)
   frame:SetPoint("CENTER", 300, 0)
   frame:SetFrameStrata("DIALOG")
   frame:SetMovable(true)
   frame:EnableMouse(true)
   frame:RegisterForDrag("LeftButton")
   frame:SetScript("OnDragStart", frame.StartMoving)
   frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
   frame:Hide()
   tinsert(UISpecialFrames, "WoWLarnModelViewer")
   self.frame = frame

   self.model = CreateFrame("PlayerModel", nil, frame)
   self.model:SetPoint("TOPLEFT", 8, -8)
   self.model:SetSize(WIDTH - 16, MODEL_H)
   self.model:SetScript("OnModelLoaded", function(model) model:SetFacing(0) end)

   self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   self.title:SetPoint("TOPLEFT", self.model, "BOTTOMLEFT", 0, -6)
   self.state = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   self.state:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)

   local function Button(text, width, x, y, onClick)
      local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
      button:SetSize(width, 22)
      button:SetPoint("BOTTOMLEFT", x, y)
      button:SetText(text)
      button:SetScript("OnClick", onClick)
      return button
   end
   Button("-100", 44, 8, 40, function() self:Step(-100) end)
   Button("-10", 36, 54, 40, function() self:Step(-10) end)
   Button("-1", 30, 92, 40, function() self:Step(-1) end)
   self.edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
   self.edit:SetSize(70, 22)
   self.edit:SetPoint("BOTTOMLEFT", 130, 40)
   self.edit:SetAutoFocus(false)
   self.edit:SetScript("OnEnterPressed", function(edit)
      self:Show(tonumber(edit:GetText()) or self.display)
      edit:ClearFocus()
   end)
   Button("+1", 30, 196, 40, function() self:Step(1) end)
   Button("+10", 36, 230, 40, function() self:Step(10) end)
   Button("+100", 44, 268, 40, function() self:Step(100) end)
   Button(L["< Monster"], 66, 8, 10, function() self:Pick(-1) end)
   Button(L["Monster >"], 66, 78, 10, function() self:Pick(1) end)
   Button(L["< Look"], 52, 148, 10, function() self:Look(-1) end)
   Button(L["Look >"], 52, 204, 10, function() self:Look(1) end)
   Button(L["Use"], 34, 260, 10, function() self:Assign(self.display) end)
   Button(L["Clear"], 40, 298, 10, function() self:Assign(nil) end)
   Button(L["Smaller"], 60, 8, 100, function() self:Resize(1.1) end)
   Button(L["Bigger"], 52, 72, 100, function() self:Resize(1 / 1.1) end)
   Button(L["Narrower"], 70, 130, 100, function() self:Room(-0.5) end)
   Button(L["Wider"], 52, 204, 100, function() self:Room(0.5) end)
   Button(L["Sync all"], 70, 260, 100, function() self:Sync() end)
   Button(L["< Turn"], 56, 8, 130, function() self:Turn(-math.pi / 12) end)
   Button(L["Turn >"], 56, 68, 130, function() self:Turn(math.pi / 12) end)
   Button(L["Up"], 40, 130, 130, function() self:Lower(-0.02) end)
   Button(L["Down"], 48, 174, 130, function() self:Lower(0.02) end)

   -- the sounds of the monster (its own, else the default ones), and any sound kit
   local sounds = { { "attack", L["Attack"] }, { "wound", L["Wound"] }, { "die", L["Die"] }, { "special", L["Special"] } }
   for index, sound in ipairs(sounds) do
      Button(sound[2], 56, 8 + (index - 1) * 60, 70, function() ns.ui:MonsterSound(sound[1], self.monster) end)
   end
   self.kit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
   self.kit:SetSize(52, 22)
   self.kit:SetPoint("BOTTOMLEFT", 256, 70)
   self.kit:SetAutoFocus(false)
   self.kit:SetNumeric(true)
   local function PlayKit()
      local kit = tonumber(self.kit:GetText())
      if kit then ns.ui.Play(kit) end
   end
   self.kit:SetScript("OnEnterPressed", function(edit) PlayKit() edit:ClearFocus() end)
   Button(L["Play"], 30, 312, 70, PlayKit)

   -- the monsters, those with a model first marked in green
   local scroll = CreateFrame("ScrollFrame", "WoWLarnModelViewerList", frame, "UIPanelScrollFrameTemplate")
   scroll:SetPoint("TOPLEFT", WIDTH, -8)
   scroll:SetPoint("BOTTOMRIGHT", -28, 40)
   local content = CreateFrame("Frame", nil, scroll)
   content:SetSize(LIST_W - 36, 1)
   scroll:SetScrollChild(content)
   self.content, self.rows = content, {}
   self.onlyModels = true
   self.filter = Button(L["With models"], LIST_W - 16, WIDTH, 10, function()
      self.onlyModels = not self.onlyModels
      self:UpdateList()
   end)
   self.filter:ClearAllPoints()
   self.filter:SetPoint("BOTTOMRIGHT", -8, 10)
   self.filter:SetWidth(LIST_W - 20)

   self.monster, self.display, self.variant = 1, 1, 1
   return frame
end

-- The list of monsters on the right: all of them, or those with a model.
function viewer:UpdateList()
   local V = ns.Visuals
   self.filter:SetText(self.onlyModels and L["With models"] or L["All monsters"])
   local shown = 0
   for id = 1, K.LUCIFER do
      local count = #V.DisplayList(id)
      if count > 0 or not self.onlyModels then
         shown = shown + 1
         local row = self.rows[shown]
         if not row then
            row = CreateFrame("Button", nil, self.content)
            row:SetSize(LIST_W - 36, ROW_H)
            row:SetPoint("TOPLEFT", 0, -(shown - 1) * ROW_H)
            row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 2, 0)
            row.text:SetPoint("RIGHT", -2, 0)
            row.text:SetJustifyH("LEFT")
            row:SetScript("OnClick", function(button) self:Select(button.monster) end)
            self.rows[shown] = row
         end
         row.monster = id
         local color = id == self.monster and "|cffffd200" or count > 0 and "|cff40ff40" or "|cff888888"
         row.text:SetText(format("%s%d  %s%s|r", color, id, Name(id), count > 1 and format(" (%d)", count) or ""))
         row:Show()
      end
   end
   for index = shown + 1, #self.rows do self.rows[index]:Hide() end
   self.content:SetHeight(max(1, shown * ROW_H))
end

-- Shows a display in the viewer.
function viewer:Show(display)
   if display < 0 then  -- (a model file, not a creature: only the ones the game uses, the others can crash the client)
      local known
      for _, id in ipairs(ns.Visuals.MIMIC_CHEST) do
         if id == display then known = true end
      end
      if not known then
         ns.mod:Print(L["Only a positive display can be tried."])
         return
      end
   end
   self.display = display < 0 and display or math.max(1, display)
   self.scale = ns.Visuals.Scale(self.display)
   if self.display < 0 then
      self.model:SetModel(-self.display)  -- (a model file data id, negated)
   else
      self.model:SetDisplayInfo(self.display)
   end
   self.model:SetFacing(ns.Visuals.Turn(self.display))
   ns.map3d.CameraScale(self.model, self.scale)
   self.edit:SetText(tostring(self.display))
   self:Update()
   self:ShowInZoo()
end

-- Makes the model of this display smaller (factor above 1) or bigger, in the viewer and in
-- the game; the size is kept in the saved variables and shown, so it can be put in V.SCALE.
function viewer:Resize(factor)
   self.scale = math.floor(self.scale * factor * 100 + 0.5) / 100
   ns.mod.db.global.scales[self.display] = self.scale
   ns.map3d.CameraScale(self.model, self.scale)
   ns.mod:Print(format("display %d: camera scale %.2f", self.display, self.scale))
   self:Refresh()
end

-- Shows a changed size or room at once: on the map and in the zoo.
function viewer:Refresh()
   self:Update()
   if ns.ui.Refresh then ns.ui:Refresh("map") end
   self:ShowInZoo()
end

-- The zoo shows the look that is shown here.
function viewer:ShowInZoo()
   local zoo = ns.zoo
   if zoo.frame and zoo.frame:IsShown() then
      for index, display in ipairs(ns.Visuals.DisplayList(self.monster)) do
         if display == self.display then zoo.looks[self.monster] = index end
      end
      zoo:Update()
   end
end

-- Gives the frame of this display more room (wings, tails), or less; kept in the saved
-- variables and shown, to be put in V.ROOM.
function viewer:Room(by)
   local room = math.max(1, ns.Visuals.Room(self.display) + by)
   ns.mod.db.global.rooms[self.display] = room
   ns.mod:Print(format("display %d: room %.1f", self.display, room))
   self:Refresh()
end

-- Turns the display in the viewer and the zoo (not in the game), 15 degrees at a time; kept in
-- the saved variables.
function viewer:Turn(by)
   local turn = (ns.Visuals.Turn(self.display) + by) % (2 * math.pi)
   turn = math.floor(turn * 1000 + 0.5) / 1000
   if turn >= 2 * math.pi - 0.001 then turn = 0 end
   ns.mod.db.global.turns[self.display] = turn
   self.model:SetFacing(turn)
   ns.mod:Print(format("display %d: turn %.0f degrees (%.3f)", self.display, math.deg(turn), turn))
   self:Refresh()
end

-- Moves the model of this display up or down against its shadow (as a fraction of its width,
-- positive is down); kept in the saved variables and shown, to be put in V.LOWER.
function viewer:Lower(by)
   local lower = math.floor((ns.Visuals.Lower(self.display) + by) * 1000 + 0.5) / 1000
   ns.mod.db.global.lowers[self.display] = lower
   ns.mod:Print(format("display %d: lower %.3f", self.display, lower))
   self:Refresh()
end

-- Gives every look of this monster the size, room, turn and height of the one shown.
function viewer:Sync()
   local global = ns.mod.db.global
   local scale, room, turn = ns.Visuals.Scale(self.display), ns.Visuals.Room(self.display), ns.Visuals.Turn(self.display)
   local lower = ns.Visuals.Lower(self.display)
   local list = ns.Visuals.DisplayList(self.monster)
   for _, display in ipairs(list) do
      global.scales[display], global.rooms[display], global.turns[display] = scale, room, turn
      global.lowers[display] = lower
   end
   ns.mod:Print(format("%d looks: camera scale %.2f, room %.1f, turn %.0f degrees", #list, scale, room, math.deg(turn)))
   self:Refresh()
end

function viewer:Step(by)
   if self.display < 0 then return end
   self:Show(self.display + by)
end

function viewer:Update()
   local id = self.monster
   local list = ns.Visuals.DisplayList(id)
   local assigned = ns.Visuals.MonsterDisplay(id)
   self.title:SetText(format("%d  %s", id, Name(id)))
   local state = assigned and format(L["Shown as display %d"], assigned) or L["Shown as a letter"]
   if #list > 1 then state = state .. format(L["  (%d looks)"], #list) end
   self.state:SetText(state)
   self:UpdateList()
end

-- Selects a monster, showing its first look if it has one.
function viewer:Select(id)
   self.monster, self.variant = id, 1
   local list = ns.Visuals.DisplayList(id)
   if list[1] then self:Show(list[1]) else self:Update() end
end

-- Goes to another monster.
function viewer:Pick(by)
   self:Select((self.monster - 1 + by) % K.LUCIFER + 1)
end

-- Steps through the looks of the monster.
function viewer:Look(by)
   local list = ns.Visuals.DisplayList(self.monster)
   if #list == 0 then return end
   self.variant = (self.variant - 1 + by) % #list + 1
   self:Show(list[self.variant])
end

-- Chooses the display shown for the monster (nil: none).
function viewer:Assign(display)
   ns.mod.db.global.displays[self.monster] = display
   self.variant = 1
   self:Update()
   ns.ui:Refresh("map")
end

function viewer:Toggle()
   if not self.frame then self:Create() end
   if self.frame:IsShown() then
      self.frame:Hide()
   else
      self.frame:Show()
      self:Select(self.monster)
   end
end
