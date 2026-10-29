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
local SHADOW = "Interface\\AddOns\\WoWLarn\\Media\\Shadow"
local FLOOR = { 0.28, 0.27, 0.25, 1 }

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
   self.zoom, self.looks, self.flat = 1, {}, false

   -- the models hang on one layer, in the same pool the map uses
   self.layer = CreateFrame("Frame", nil, frame)
   self.layer:SetPoint("TOPLEFT", 8, -8)
   self.layer:SetPoint("BOTTOMRIGHT", -8, 36)
   self.layer.quads, self.layer.icons, self.layer.glyphs, self.layer.models = {}, {}, {}, {}
   self.layer.usedQuads, self.layer.usedIcons, self.layer.usedGlyphs, self.layer.usedModels = 0, 0, 0, 0

   self.cells = {}
   for id = 0, K.LUCIFER do  -- (0: the player, for the size to compare with)
      local cell = CreateFrame("Button", nil, self.layer)
      cell:SetSize(CELL_W, CELL_H)
      cell:SetPoint("TOPLEFT", (id % COLUMNS) * CELL_W, -math.floor(id / COLUMNS) * CELL_H)
      cell.floor = cell:CreateTexture(nil, "BACKGROUND")
      cell.floor:SetColorTexture(FLOOR[1], FLOOR[2], FLOOR[3], 1)
      cell.shadow = cell:CreateTexture(nil, "BORDER")
      cell.shadow:SetTexture(SHADOW)
      cell.shadow:SetVertexColor(0, 0, 0, 0.6)
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
   self.modeButton = Button("2.5D", 50, 82, function()
      self.flat = not self.flat
      self.modeButton:SetText(self.flat and "2.5D" or L["Flat"])
      self:Update()
   end)
   self.modeButton:SetText(L["Flat"])
   self.zoomButton = Button("x1", 40, 136, function()
      local index = 1
      for i, zoom in ipairs(ZOOMS) do if zoom == self.zoom then index = i end end
      self.zoom = ZOOMS[index % #ZOOMS + 1]
      self.zoomButton:SetText("x" .. self.zoom)
      self:Update()
   end)
   Button(L["Close"], 50, 180, function() frame:Hide() end)
   frame:SetScript("OnShow", function() self:Update() end)
end

-- Draws every monster, in the 2.5D view of the map or flat; the models are placed afresh, so
-- a new look shows at once.
function zoo:Update()
   local V, map3d = ns.Visuals, ns.map3d
   local layer = self.layer
   map3d.Begin(layer)
   -- larger, but not larger than the screen
   self.frame:SetScale(math.min(self.zoom, UIParent:GetWidth() / self.frame:GetWidth(), UIParent:GetHeight() / self.frame:GetHeight()))
   local width = TILE_W
   for id, cell in pairs(self.cells) do
      local look = id == 0 and "player" or V.MonsterDisplay(id, self.looks[id] or 1)
      local turn = look ~= "player" and look and V.Turn(look) or 0  -- (to see how wide it is from the side)
      local column, row = id % COLUMNS, math.floor(id / COLUMNS)
      local x, y = column * CELL_W + CELL_W / 2, (row + 1) * CELL_H - 16  -- (the bottom of the tile)
      cell.floor:SetShown(self.flat)
      cell.shadow:SetShown(self.flat and look ~= nil and ns.mod.db.profile.shadows ~= false)
      if self.flat then
         cell.floor:ClearAllPoints()
         cell.floor:SetSize(width, width * 0.5)
         cell.floor:SetPoint("BOTTOM", 0, 16)
         cell.shadow:ClearAllPoints()
         cell.shadow:SetSize(width * 0.84, width * 0.42)
         cell.shadow:SetPoint("BOTTOM", 0, 16 + width * 0.04)
         if look then map3d.Model(layer, look, x, y - width * 0.25, width * (id == 0 and 1.2 or 1), turn) end
      elseif look then
         map3d.DrawTile(layer, look, x, y - width * 0.25, 1, FLOOR, turn)
      end
   end
   map3d.Finish(layer)
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
