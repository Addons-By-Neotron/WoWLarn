--[[
**********************************************************************
WoWLarn - Map view: the flat tile renderer.
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
local _, ns = ...
local K = ns.K
local G = ns.G
local V = ns.Visuals

local map = {}
ns.map = map

local TILE = 32
local floor, max, min = math.floor, math.max, math.min
local MAXX, MAXY = K.MAXX, K.MAXY

local function Fill(texture, color)
   if texture.SetColorTexture then
      texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
   else
      texture:SetTexture(color[1], color[2], color[3], color[4] or 1)
   end
end

local function NewCell(frame)
   local cell = {}
   cell.bg = frame:CreateTexture(nil, "BORDER")
   cell.bg:SetSize(TILE, TILE)
   cell.icon = frame:CreateTexture(nil, "ARTWORK")
   cell.icon:SetPoint("TOPLEFT", cell.bg, "TOPLEFT", 3, -3)
   cell.icon:SetPoint("BOTTOMRIGHT", cell.bg, "BOTTOMRIGHT", -3, 3)
   cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
   cell.glyph = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   cell.glyph:SetPoint("CENTER", cell.bg, "CENTER")
   cell.actor = frame:CreateTexture(nil, "OVERLAY")
   cell.actor:SetPoint("TOPLEFT", cell.bg, "TOPLEFT", 2, -2)
   cell.actor:SetPoint("BOTTOMRIGHT", cell.bg, "BOTTOMRIGHT", -2, 2)
   cell.actor:SetTexCoord(0.07, 0.93, 0.07, 0.93)
   return cell
end

local function HideCell(cell)
   cell.icon:Hide()
   cell.glyph:Hide()
   cell.actor:Hide()
end

function map:Create(parent)
   local frame = ns.CreatePanel(parent, nil, { 0, 0, 0, 1 })
   if frame.SetClipsChildren then frame:SetClipsChildren(true) end
   self.frame = frame
   self.cells = {}
   frame:SetScript("OnSizeChanged", function() self:Layout() end)
   return frame
end

-- Builds the grid of tiles that fits the frame.
function map:Layout()
   local width, height = self.frame:GetWidth(), self.frame:GetHeight()
   local cols, rows = floor(width / TILE), floor(height / TILE)
   if cols < 1 or rows < 1 then return end
   local offsetX, offsetY = floor((width - cols * TILE) / 2), floor((height - rows * TILE) / 2)
   for row = 1, rows do
      self.cells[row] = self.cells[row] or {}
      for col = 1, cols do
         local cell = self.cells[row][col] or NewCell(self.frame)
         self.cells[row][col] = cell
         cell.bg:ClearAllPoints()
         cell.bg:SetPoint("TOPLEFT", self.frame, "TOPLEFT", offsetX + (col - 1) * TILE, -(offsetY + (row - 1) * TILE))
         cell.bg:Show()
      end
   end
   -- Hide cells left over from a larger size.
   for row, cells in pairs(self.cells) do
      for col, cell in pairs(cells) do
         if row > rows or col > cols then
            cell.bg:Hide()
            HideCell(cell)
         end
      end
   end
   self.cols, self.rows = cols, rows
   self:Draw()
end

local function DrawTile(cell, x, y, ground)
   if x > MAXX or y > MAXY or G.know[x][y] == 0 then
      Fill(cell.bg, { 0, 0, 0, 1 })
      HideCell(cell)
      return
   end
   local object = G.item[x][y]
   if object == K.OWALL then
      Fill(cell.bg, V.WALL)
      HideCell(cell)
      return
   end
   Fill(cell.bg, ground)
   cell.actor:Hide()
   local monster = ns.Display.visibleMonster(x, y)
   if monster ~= 0 then
      cell.icon:Hide()
      cell.glyph:SetText(V.MonsterGlyph(monster))
      cell.glyph:SetTextColor(unpack(V.MONSTER_COLOR))
      cell.glyph:Show()
      return
   end
   cell.glyph:SetTextColor(unpack(V.GLYPH_COLOR))
   local icon = object ~= 0 and V.ObjectIcon(object)
   if icon then
      cell.icon:SetTexture(icon)
      cell.icon:Show()
      cell.glyph:Hide()
   elseif object ~= 0 then
      cell.icon:Hide()
      cell.glyph:SetText(V.ObjectGlyph(object))
      cell.glyph:Show()
   else
      cell.icon:Hide()
      cell.glyph:Hide()
   end
end

--@debug@
-- Prints what the map would draw, to find out why tiles are missing.
function map:Debug()
   local known, walls, shown = 0, 0, 0
   for x = 1, MAXX do
      for y = 1, MAXY do
         if G.know[x][y] ~= 0 then
            known = known + 1
            if G.item[x][y] == K.OWALL then walls = walls + 1 end
         end
      end
   end
   for _, cells in pairs(self.cells) do
      for _, cell in pairs(cells) do
         if cell.bg:IsShown() then shown = shown + 1 end
      end
   end
   print(format("mapdebug: level %d player %d,%d cols %s rows %s cells shown %d known %d walls %d OWALL %s wall color %s",
      G.level, G.playerx, G.playery, tostring(self.cols), tostring(self.rows), shown, known, walls,
      tostring(K.OWALL), tostring(V.WALL and V.WALL[1])))
   local camX = max(1, min(G.playerx - floor(self.cols / 2), MAXX - self.cols + 1))
   local camY = max(1, min(G.playery - floor(self.rows / 2), MAXY - self.rows + 1))
   print(format("mapdebug: camera %d,%d frame %dx%d visible %s", camX, camY, self.frame:GetWidth(), self.frame:GetHeight(),
      tostring(self.frame:IsVisible())))
   local listed = 0
   for row = 1, self.rows do
      for col = 1, self.cols do
         local x, y = camX + col - 1, camY + row - 1
         if x <= MAXX and y <= MAXY and G.know[x][y] ~= 0 and listed < 6 then
            listed = listed + 1
            local cell = self.cells[row][col]
            print(format("  tile %d,%d item %d cell %d,%d bg shown %s visible %s left %s top %s", x, y, G.item[x][y], col, row,
               tostring(cell.bg:IsShown()), tostring(cell.bg:IsVisible()), tostring(cell.bg:GetLeft()), tostring(cell.bg:GetTop())))
         end
      end
   end
   local ok, err = pcall(self.Draw, self)
   print("mapdebug: Draw " .. (ok and "ok" or tostring(err)))
end
--@end-debug@

-- Draws the part of the level around the player.
function map:Draw()
   if not self.cols or not G.class then return end
   local cols, rows = self.cols, self.rows
   local camX = max(1, min(G.playerx - floor(cols / 2), MAXX - cols + 1))
   local camY = max(1, min(G.playery - floor(rows / 2), MAXY - rows + 1))
   local ground = V.Ground(G.level)
   for row = 1, rows do
      for col = 1, cols do
         DrawTile(self.cells[row][col], camX + col - 1, camY + row - 1, ground)
      end
   end
   -- The player.
   local col, row = G.playerx - camX + 1, G.playery - camY + 1
   local cell = self.cells[row] and self.cells[row][col]
   if cell and G.class then
      cell.actor:SetTexture(V.ClassIcon(G.class))
      cell.actor:Show()
      cell.glyph:Hide()
   end
end
