--[[
**********************************************************************
WoWLarn - The object viewer: choose the 3D model of the objects of the game (debug builds only).
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
local K = ns.K

-- The object viewer (/larn objects): the objects of the game on the left (chests, weapons, rings
-- ...), the model files of ns.ModelList on the right by kind, and the model in the middle.  Use
-- gives the model to the object; Print gives the lines to put in V.OBJECT_MODELS in
-- Data/Visuals.lua.  What is set here lasts until the next reload.  Only listed files are shown:
-- a file data id that is not a model can crash the game.
local viewer = {}
ns.objectViewer = viewer

local ROWS, ROW_H, OBJECT_W, MODEL_W, FILE_W, HEIGHT = 22, 16, 190, 320, 620, 460
local KINDS = { "all", "chest", "door", "rock", "lava", "crystal", "weapon", "loot", "decor" }

-- A list with a filter box and a scroll bar: rows (a pool of buttons), shown (the entries) and
-- text(entry) for what a row says.
local function List(frame, name, x, width, filter, onClick, text)
   local list = { shown = {}, rows = {}, text = text }
   if filter then
      list.filter = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
      list.filter:SetSize(width - 30, 20)
      list.filter:SetPoint("TOPLEFT", x + 6, -32)
      list.filter:SetAutoFocus(false)
      list.filter:SetScript("OnEscapePressed", list.filter.ClearFocus)
   end
   list.scroll = CreateFrame("ScrollFrame", name, frame, "FauxScrollFrameTemplate")
   list.scroll:SetPoint("TOPLEFT", x, -58)
   list.scroll:SetSize(width, ROWS * ROW_H)
   list.scroll:SetScript("OnVerticalScroll", function(scroll, offset)
      FauxScrollFrame_OnVerticalScroll(scroll, offset, ROW_H, function() list:Update() end)
   end)
   for row = 1, ROWS do
      local button = CreateFrame("Button", nil, frame)
      button:SetSize(width - 22, ROW_H)
      button:SetPoint("TOPLEFT", x + 2, -58 - (row - 1) * ROW_H)
      button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      button.text:SetPoint("LEFT", 2, 0)
      button.text:SetJustifyH("LEFT")
      button.text:SetWidth(width - 26)
      button.text:SetWordWrap(false)
      button:SetScript("OnClick", function(b) if b.entry then onClick(b.entry) end end)
      list.rows[row] = button
   end
   function list:Update()
      FauxScrollFrame_Update(self.scroll, #self.shown, ROWS, ROW_H)
      local offset = FauxScrollFrame_GetOffset(self.scroll)
      for row = 1, ROWS do
         local button, entry = self.rows[row], self.shown[offset + row]
         button.entry = entry
         button:SetShown(entry ~= nil)
         if entry then button.text:SetText(self.text(entry)) end
      end
   end
   return list
end

local function ObjectName(entry)
   return entry.text
end

function viewer:Objects()
   local T = ns.Tables
   local objects = {}
   for id = 1, K.MAXOBJ - 1 do
      local name = T.objectname[id]
      if name and name ~= "" then objects[#objects + 1] = { id = id, text = ns.Debug.objectLabel(id, name) } end
   end
   return objects
end

function viewer:UpdateObjects()
   local filter = strlower(self.objects.filter:GetText() or "")
   wipe(self.objects.shown)
   for _, entry in ipairs(self.all) do
      if filter == "" or strfind(strlower(entry.text), filter, 1, true) then
         self.objects.shown[#self.objects.shown + 1] = entry
      end
   end
   self.objects:Update()
end

function viewer:UpdateFiles()
   local filter = strlower(self.files.filter:GetText() or "")
   local kind = KINDS[self.kind]
   wipe(self.files.shown)
   for _, entry in ipairs(ns.ModelList) do
      if (kind == "all" or entry[3] == kind)
         and (filter == "" or strfind(strlower(entry[2]), filter, 1, true) or strfind(tostring(entry[1]), filter, 1, true)) then
         self.files.shown[#self.files.shown + 1] = entry
      end
   end
   self.files:Update()
   self.kindButton:SetText(KINDS[self.kind])
end

-- Shows a model file in the middle.
function viewer:ShowFile(file, path)
   self.file = file
   local display = -file
   self.scale = ns.Visuals.Scale(display)
   self.model:SetModel(file)
   self.model:SetFacing(ns.Visuals.Turn(display))
   ns.map3d.CameraScale(self.model, self.scale)
   self.title:SetText(format("%d  %s", file, path or ""))
end

function viewer:SelectObject(entry)
   self.object = entry
   local file = ns.Visuals.ObjectModel(entry.id)
   self:Update()
   if file then self:ShowFile(file) end
end

function viewer:Update()
   local entry = self.object
   if not entry then self.chosen:SetText("choose an object on the left") return end
   local file = ns.Visuals.ObjectModel(entry.id)
   self.chosen:SetText(format("%s: %s", entry.text, file and tostring(file) or "no model"))
end

function viewer:Use()
   if not (self.object and self.file) then return end
   ns.mod.db.global.objectModels[self.object.id] = self.file
   self:Update()
end

function viewer:Clear()
   if not self.object then return end
   ns.mod.db.global.objectModels[self.object.id] = nil
   self:Update()
end

function viewer:Print()
   local ids = {}
   for id in pairs(ns.mod.db.global.objectModels) do ids[#ids + 1] = id end
   table.sort(ids)
   for _, id in ipairs(ids) do
      ns.mod:Print(format("   [%d] = %d,  -- %s", id, ns.mod.db.global.objectModels[id], ns.Tables.objectname[id] or "?"))
   end
end

-- The model of the file is smaller or bigger, or turned (kept for the display -file, like the
-- monster viewer does).
function viewer:Resize(factor)
   if not self.file then return end
   self.scale = math.floor(self.scale * factor * 100 + 0.5) / 100
   ns.mod.db.global.scales[-self.file] = self.scale
   ns.map3d.CameraScale(self.model, self.scale)
   ns.mod:Print(format("model %d: camera scale %.2f", self.file, self.scale))
end

function viewer:Turn(by)
   if not self.file then return end
   local turn = ns.Visuals.Turn(-self.file) + by
   ns.mod.db.global.turns[-self.file] = turn
   self.model:SetFacing(turn)
end

function viewer:Create()
   local width = OBJECT_W + MODEL_W + FILE_W + 24
   local frame = ns.CreatePanel(UIParent, "WoWLarnObjectViewer")
   frame:SetSize(width, HEIGHT)
   frame:SetPoint("CENTER", 0, 0)
   frame:SetFrameStrata("DIALOG")
   frame:SetMovable(true)
   frame:EnableMouse(true)
   frame:RegisterForDrag("LeftButton")
   frame:SetScript("OnDragStart", frame.StartMoving)
   frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
   frame:Hide()
   tinsert(UISpecialFrames, "WoWLarnObjectViewer")
   self.frame = frame

   self.all = self:Objects()
   self.kind = 1

   local x = 8
   self.objects = List(frame, "WoWLarnObjectViewerObjects", x, OBJECT_W, true, function(entry) self:SelectObject(entry) end, ObjectName)
   self.objects.filter:SetScript("OnTextChanged", function() self:UpdateObjects() end)

   x = x + OBJECT_W + 8
   self.model = CreateFrame("PlayerModel", nil, frame)
   self.model:SetPoint("TOPLEFT", x, -32)
   self.model:SetSize(MODEL_W - 8, 300)
   self.model:SetScript("OnModelLoaded", function(model) model:SetFacing(ns.Visuals.Turn(-(self.file or 0))) end)
   self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   self.title:SetPoint("TOPLEFT", self.model, "BOTTOMLEFT", 0, -6)
   self.title:SetWidth(MODEL_W - 8)
   self.title:SetJustifyH("LEFT")
   self.chosen = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   self.chosen:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -6)

   local function Button(text, w, bx, by, onClick)
      local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
      button:SetSize(w, 22)
      button:SetPoint("BOTTOMLEFT", bx, by)
      button:SetText(text)
      button:SetScript("OnClick", onClick)
      return button
   end
   Button("Smaller", 70, x, 70, function() self:Resize(1.1) end)
   Button("Bigger", 70, x + 74, 70, function() self:Resize(1 / 1.1) end)
   Button("< Turn", 70, x + 148, 70, function() self:Turn(-math.pi / 12) end)
   Button("Turn >", 70, x + 222, 70, function() self:Turn(math.pi / 12) end)
   Button("Use for the object", 150, x, 40, function() self:Use() end)
   Button("Clear", 70, x + 154, 40, function() self:Clear() end)
   Button("Print the choices", 150, x, 10, function() self:Print() end)

   x = x + MODEL_W + 4
   self.files = List(frame, "WoWLarnObjectViewerFiles", x, FILE_W, true, function(entry) self:ShowFile(entry[1], entry[2]) end,
      function(entry) return entry[1] .. " " .. entry[2] end)
   self.files.filter:SetWidth(FILE_W - 90)
   self.files.filter:SetScript("OnTextChanged", function() self:UpdateFiles() end)
   self.kindButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   self.kindButton:SetSize(70, 22)
   self.kindButton:SetPoint("LEFT", self.files.filter, "RIGHT", 6, 0)
   self.kindButton:SetScript("OnClick", function()
      self.kind = self.kind % #KINDS + 1
      self:UpdateFiles()
   end)
   self:UpdateObjects()
   self:UpdateFiles()
   self:Update()
end

function viewer:Toggle()
   if not self.frame then self:Create() end
   self.frame:SetShown(not self.frame:IsShown())
end
