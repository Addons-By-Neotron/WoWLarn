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

-- The monster zoo (/larn zoo): every monster on a tile of its own, drawn the way the map draws
-- it, to see which models do not fit.  Re-draw picks other looks; a click on a monster opens it
-- in the model viewer, where its size can be set.
local zoo = {}
ns.zoo = zoo

local COLUMNS, TILE_W, CELL_W, CELL_H = 13, 50, 64, 118
local ZOOMS = { 1, 1.5, 2 }

function zoo:Create()
   local V = ns.Visuals
   local rows = math.ceil((K.LUCIFER + 1) / COLUMNS)
   local frame = ns.CreatePanel(UIParent, "WoWLarnZoo")
   frame:SetSize(COLUMNS * CELL_W + 16, rows * CELL_H + 44)
   frame:SetPoint("CENTER")
   frame:SetFrameStrata("DIALOG")
   frame:SetMovable(true)
   frame:EnableMouse(true)
   frame:RegisterForDrag("LeftButton")
   frame:SetScript("OnDragStart", frame.StartMoving)
   frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
   frame:Hide()
   tinsert(UISpecialFrames, "WoWLarnZoo")
   self.frame = frame
   self.zoom, self.looks = 1, {}

   -- the models hang on one layer, in the same pool the map uses
   self.layer = CreateFrame("Frame", nil, frame)
   self.layer:SetPoint("TOPLEFT", 8, -8)
   self.layer:SetPoint("BOTTOMRIGHT", -8, 36)
   self.layer.models, self.layer.usedModels = {}, 0

   self.cells = {}
   for id = 0, K.LUCIFER do  -- (0: the player, for the size to compare with)
      local cell = CreateFrame("Button", nil, self.layer)
      cell:SetSize(CELL_W, CELL_H)
      cell:SetPoint("TOPLEFT", (id % COLUMNS) * CELL_W, -math.floor(id / COLUMNS) * CELL_H)
      cell.floor = cell:CreateTexture(nil, "BACKGROUND")
      cell.floor:SetColorTexture(0.25, 0.25, 0.28, 0.9)
      cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      cell.label:SetPoint("BOTTOM", 0, 2)
      cell.label:SetWidth(CELL_W - 2)
      cell.label:SetWordWrap(false)
      cell.label:SetText(id == 0 and L["you"] or (id .. " " .. ns.MonsterData[id].name))
      cell:SetScript("OnClick", function() if id > 0 then self:Open(id) end end)
      self.cells[id] = cell
   end

   local function Button(text, width, x, onClick)
      local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
      button:SetSize(width, 22)
      button:SetPoint("BOTTOMLEFT", x, 8)
      button:SetText(text)
      button:SetScript("OnClick", onClick)
      return button
   end
   Button(L["Re-draw"], 70, 8, function() self:Redraw() end)
   self.zoomButton = Button("x1", 40, 82, function()
      local index = 1
      for i, zoom in ipairs(ZOOMS) do if zoom == self.zoom then index = i end end
      self.zoom = ZOOMS[index % #ZOOMS + 1]
      self.zoomButton:SetText("x" .. self.zoom)
      self:Update()
   end)
   Button(L["Close"], 50, 126, function() frame:Hide() end)
   frame:SetScript("OnShow", function() self:Update() end)
end

-- Draws every monster; the models are placed afresh, so a new look shows at once.
function zoo:Update()
   local V, map3d = ns.Visuals, ns.map3d
   local layer = self.layer
   layer.usedModels = 0
   local width = TILE_W * self.zoom
   for id, cell in pairs(self.cells) do
      cell.floor:ClearAllPoints()
      cell.floor:SetSize(width, width * 0.5)
      cell.floor:SetPoint("BOTTOM", 0, 16)
      local look = id == 0 and "player" or V.MonsterDisplay(id, self.looks[id] or 1)
      if look then
         local x, y = (id % COLUMNS) * CELL_W + CELL_W / 2, (math.floor(id / COLUMNS) + 1) * CELL_H - 16 - width * 0.25
         map3d.Model(layer, look, x, y, width * (id == 0 and 1.2 or 1), 0)
      end
   end
   for index = layer.usedModels + 1, #layer.models do layer.models[index]:Hide() end
end

-- Other looks for the monsters that have several.
function zoo:Redraw()
   for id = 1, K.LUCIFER do self.looks[id] = math.random(1, 1000) end
   self:Update()
end

function zoo:Open(id)
   local viewer = ns.modelViewer
   if not (viewer.frame and viewer.frame:IsShown()) then viewer:Toggle() end
   viewer:Select(id)
end

function zoo:Toggle()
   if not self.frame then self:Create() end
   self.frame:SetShown(not self.frame:IsShown())
end
