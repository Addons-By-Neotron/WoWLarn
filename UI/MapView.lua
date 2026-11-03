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
local L = LibStub("AceLocale-3.0"):GetLocale("WoWLarn")
]]
local _, ns = ...
local K = ns.K
local G = ns.G
local V = ns.Visuals

local map = {}
ns.map = map

local DEFAULT_TILE = 32
local TILE = DEFAULT_TILE  -- (the setting Tile size, see map:Layout)
local floor, max, min = math.floor, math.max, math.min
local MAXX, MAXY = K.MAXX, K.MAXY

local function Fill(texture, color)
   if texture.SetColorTexture then
      texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
   else
      texture:SetTexture(color[1], color[2], color[3], color[4] or 1)
   end
   texture:SetTexCoord(0, 1, 0, 1)
   texture:SetVertexColor(1, 1, 1, 1)
end

-- A tile of a texture (see Visuals Texture): the file data id, the part of it, tinted; the flat
-- colour if there is none.
local function FillTexture(texture, id, _, tint, color)
   if not id then return Fill(texture, color) end
   texture:SetTexture(id)
   texture:SetTexCoord(0, 1, 0, 1)
   texture:SetVertexColor(tint[1], tint[2], tint[3], 1)
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
   ns.map3d:Create(frame)
   frame:SetScript("OnSizeChanged", function() self:Layout() end)
   self:EnableTooltips(frame)
   return frame
end

-- Builds the grid of tiles that fits the frame.
-- The tile under the cursor, or nil.  x, y are in pixels from the top left of the map.
function map:TileAt(sx, sy)
   if self:Is3D() then return ns.map3d:TileAt(sx, sy) end
   if not self.camX or not self.cols then return nil end
   local col = floor((sx - self.offsetX) / TILE) + 1
   local row = floor((sy - self.offsetY) / TILE) + 1
   if col < 1 or row < 1 or col > self.cols or row > self.rows then return nil end
   return self.camX + col - 1, self.camY + row - 1
end

-- Fills the tooltip for what is on the tile (x, y); false if there is nothing to tell.
function map:Describe(x, y)
   if x < 1 or y < 1 or x > MAXX or y > MAXY or G.know[x][y] == 0 then return false end
   if x == G.playerx and y == G.playery then
      GameTooltip:SetText(G.name or L["You"], 1, 1, 1)
      GameTooltip:Show()
      return true
   end
   local monster = ns.Display.visibleMonster(x, y)
   if monster ~= 0 then
      GameTooltip:SetText(G.monster[monster].name, 1, 0.3, 0.3)
      GameTooltip:Show()
      return true
   end
   local object = G.item[x][y]
   if object == 0 or object == K.OWALL then return false end
   if G.named[x][y] == object then  -- (looked at or dropped: what it is, as the pack would name it)
      ns.ItemInfo.tooltip(object, G.iarg[x][y])
      return true
   end
   GameTooltip:SetText(ns.ItemInfo.groundName(object), 1, 1, 1)
   GameTooltip:Show()
   return true
end

-- Shows the tooltip of the tile the cursor is over, while the map itself is under it.
function map:EnableTooltips(frame)
   frame:EnableMouse(true)
   local since, shown = 0, nil
   frame:SetScript("OnUpdate", function(_, elapsed)
      since = since + elapsed
      if since < 0.05 then return end
      since = 0
      local focus = GetMouseFoci and GetMouseFoci()[1] or GetMouseFocus and GetMouseFocus()
      local x, y
      if focus == frame and G.class then
         local scale = frame:GetEffectiveScale()
         local cx, cy = GetCursorPosition()
         x, y = self:TileAt(cx / scale - frame:GetLeft(), frame:GetTop() - cy / scale)
      end
      local key = x and (x * 100 + y .. ":" .. G.level)
      if key == shown then return end
      shown = key
      if not x then
         GameTooltip:Hide()
         return
      end
      GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
      if not self:Describe(x, y) then GameTooltip:Hide() end
   end)
   frame:SetScript("OnLeave", function() shown = nil; GameTooltip:Hide() end)
end

function map:Layout()
   TILE = ns.mod.db.profile.tileSize or DEFAULT_TILE
   local width, height = self.frame:GetWidth(), self.frame:GetHeight()
   local cols, rows = floor(width / TILE), floor(height / TILE)
   if cols < 1 or rows < 1 then return end
   local offsetX, offsetY = floor((width - cols * TILE) / 2), floor((height - rows * TILE) / 2)
   for row = 1, rows do
      self.cells[row] = self.cells[row] or {}
      for col = 1, cols do
         local cell = self.cells[row][col] or NewCell(self.frame)
         self.cells[row][col] = cell
         cell.bg:SetSize(TILE, TILE)
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
   self.offsetX, self.offsetY = offsetX, offsetY
   self.flatHidden = false  -- (the cells were shown again above)
   self:Draw()
end

local function DrawTile(cell, x, y, ground)
   if x > MAXX or y > MAXY or not ns.Display.remembered(x, y) then
      Fill(cell.bg, { 0, 0, 0, 1 })
      HideCell(cell)
      return
   end
   local object = G.item[x][y]
   if object == K.OWALL then
      if V.WallVariant(G.level, x, y) then  -- (lava)
         local id, uv = V.Texture(G.level, "lava", x, y)
         FillTexture(cell.bg, id, uv, { 1, 1, 1 }, V.GROUND.lava)
      else
         local id, uv = V.Texture(G.level, "wall", x, y)
         FillTexture(cell.bg, id, uv, V.Tint(G.level), V.WALL)
      end
      HideCell(cell)
      return
   end
   -- (a plain floor in the flat view: the texture hides the lines between the tiles and what lies on them)
   FillTexture(cell.bg, nil, nil, V.Tint(G.level), ground)
   cell.actor:Hide()
   if G.know[x][y] == 0 and not (x == G.playerx and y == G.playery) then  -- (not in sight)
      HideCell(cell)
      return
   end
   local monster = ns.Display.visibleMonster(x, y)
   if monster ~= 0 then
      -- (what lies under the monster stays, as a picture)
      local under, picture = nil, false
      if object ~= 0 and not ns.mod.db.profile.ascii then under, picture = V.ObjectPicture(object, G.iarg[x][y], G.named[x][y] == object) end
      if under then
         cell.icon:SetTexture(under)
         cell.icon:SetBlendMode((picture or ns.mod.db.profile.opaqueIcons) and "BLEND" or "ADD")
         cell.icon:Show()
      else
         cell.icon:Hide()
      end
      if ns.map3d.MonsterModel(x, y) then  -- (drawn as a model, see map:Draw)
         cell.glyph:Hide()
         return
      end
      cell.glyph:SetText(V.MonsterGlyph(monster))
      cell.glyph:SetTextColor(unpack(V.MONSTER_COLOR))
      cell.glyph:Show()
      return
   end
   cell.glyph:SetTextColor(unpack(V.GLYPH_COLOR))
   local icon, picture = nil, false
   if object ~= 0 and not ns.mod.db.profile.ascii then icon, picture = V.ObjectPicture(object, G.iarg[x][y], G.named[x][y] == object) end
   if icon then
      cell.icon:SetTexture(icon)
      cell.icon:SetBlendMode((picture or ns.mod.db.profile.opaqueIcons) and "BLEND" or "ADD")  -- (add: the black of the icon is left out)
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

-- C: the missile shown by godirect(). Call without arguments to remove it.
function map:SetOverlay(x, y, glyph, color)
   self.overlays = x and { { x = x, y = y, glyph = glyph, color = color } } or nil
end

-- Several at once: a list of { x, y, glyph, color } (the area spells).  Call without arguments to
-- remove them.
function map:SetOverlays(list)
   self.overlays = list
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
-- True if the 2.5D view is the one to show (a setting).
function map:Is3D()
   return ns.mod.db.profile.view == "3d" and G.level ~= 0  -- (the town is always flat)
end

-- Shows or hides the flat tiles.
local function ShowFlat(self, shown)
   for _, cells in pairs(self.cells) do
      for col, cell in pairs(cells) do
         if shown then
            cell.bg:Show()
         else
            cell.bg:Hide()
            HideCell(cell)
         end
      end
   end
end

function map:Draw()
   if not self.cols or not G.class then return end
   if self:Is3D() then
      if not self.flatHidden then
         ShowFlat(self, false)
         self.flatHidden = true
      end
      if self.modelLayer then self.modelLayer:Hide() end
      ns.map3d:Draw()
      return
   end
   if self.flatHidden then
      self.flatHidden = false
      ns.map3d:Hide()
      ShowFlat(self, true)
   end
   local cols, rows = self.cols, self.rows
   local camX = max(1, min(G.playerx - floor(cols / 2), MAXX - cols + 1))
   local camY = max(1, min(G.playery - floor(rows / 2), MAXY - rows + 1))
   self.camX, self.camY = camX, camY
   local ground = V.Ground(G.level)
   if not self.modelLayer then  -- the models of monsters and the player stand on this
      self.modelLayer = CreateFrame("Frame", nil, self.frame)
      self.modelLayer:SetAllPoints()
      self.modelLayer.models = {}
   end
   local frame = self.modelLayer
   frame:Show()
   ns.map3d.BeginModels(frame)
   for row = 1, rows do
      for col = 1, cols do
         local x, y = camX + col - 1, camY + row - 1
         DrawTile(self.cells[row][col], x, y, ground)
         if x <= MAXX and y <= MAXY and G.know[x][y] ~= 0 and (x ~= G.playerx or y ~= G.playery) then
            local display, facing, anim = ns.map3d.MonsterModel(x, y)
            if display then
               ns.map3d.Model(frame, display, self.offsetX + (col - 0.5) * TILE,
                  self.offsetY + row * TILE - TILE * 0.05, TILE * 0.9, facing, anim)
            end
         end
      end
   end
   -- What spells do on the way, above the models (the effects of the 2.5D view).
   ns.map3d:BeginEffects(self.modelLayer:GetFrameLevel() + 30)
   for _, effect in ipairs(self.overlays or {}) do
      local col, row = effect.x - camX + 1, effect.y - camY + 1
      if self.cells[row] and self.cells[row][col] then
         ns.map3d:Effect(self.offsetX + (col - 0.5) * TILE, self.offsetY + (row - 0.5) * TILE, TILE * 0.9,
            effect.glyph, effect.color or V.MISSILE_COLOR)
      end
   end
   ns.map3d:EndEffects()
   -- The player.
   local col, row = G.playerx - camX + 1, G.playery - camY + 1
   local cell = self.cells[row] and self.cells[row][col]
   if cell and G.class then
      if ns.mod.db.profile.ascii then  -- the original @
         cell.glyph:SetText("@")
         cell.glyph:SetTextColor(unpack(V.PLAYER_COLOR))
         cell.glyph:Show()
         cell.icon:Hide()
      elseif ns.mod.db.profile.models ~= false then  -- the model of the player
         local facing, anim = ns.map3d.PlayerModel()
         cell.actor:Hide()
         cell.glyph:Hide()
         local look = ns.Create.gameLook()
         ns.map3d.playerLook = look
         ns.map3d.Model(frame, look or "player", self.offsetX + (col - 0.5) * TILE,
            self.offsetY + row * TILE - TILE * 0.05, TILE * 0.9, facing, anim)
      else
         cell.actor:SetTexture(V.ClassIcon(G.class))
         cell.actor:Show()
         cell.glyph:Hide()
      end
   end
   ns.map3d.EndModels(frame)
end
