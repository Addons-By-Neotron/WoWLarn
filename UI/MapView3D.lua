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
local _, ns = ...
local K = ns.K
local G = ns.G
local V = ns.Visuals

-- The 2.5D view: the same map seen from behind and above the player, with the floor and the
-- walls drawn as perspective quads (design.md 7.1).  It draws into the frame of the flat
-- map (UI/MapView.lua), which switches between the two.
--
-- Space: a tile is TILE units wide.  x grows to the east and y to the south; the camera is
-- CAMERA_BACK units south of the player and CAMERA_HEIGHT above the floor, looking north,
-- so "ahead" is how far north of the camera something is.
local map3d = {}
ns.map3d = map3d

local TILE, WALL_HEIGHT = 64, 64
local CAMERA_BACK, CAMERA_HEIGHT, FOCAL = 380, 300, 330
local PLAYER_AT = 0.62  -- how far down the view the player stands
local NEAR_ROWS, FAR_ROWS, SIDE_COLUMNS = 4, 13, 14
local ROWS = NEAR_ROWS + FAR_ROWS + 1
local MIN_AHEAD = 24
local SEE_THROUGH = 0.3  -- how solid a wall in front of the player is
local FOG_REACH = 1700  -- ahead at which things are at their darkest
local floor, max, min = math.floor, math.max, math.min
local MAXX, MAXY = K.MAXX, K.MAXY

local FLOOR, WALL, ACTOR = 0, 1, 2  -- the layers of a row, back to front

----------------------------------------------------------------
-- Pools of pieces
----------------------------------------------------------------

-- A layer of a row: a frame over the whole view with a pool of quads, icons and glyphs.
local function NewLayer(view, level)
   local frame = CreateFrame("Frame", nil, view)
   frame:SetAllPoints(view)
   frame:SetFrameLevel(level)
   frame.quads, frame.icons, frame.glyphs = {}, {}, {}
   frame.usedQuads, frame.usedIcons, frame.usedGlyphs = 0, 0, 0
   return frame
end

local function Begin(layer)
   layer.usedQuads, layer.usedIcons, layer.usedGlyphs = 0, 0, 0
end

local function Finish(layer)
   for index = layer.usedQuads + 1, #layer.quads do layer.quads[index]:Hide() end
   for index = layer.usedIcons + 1, #layer.icons do layer.icons[index]:Hide() end
   for index = layer.usedGlyphs + 1, #layer.glyphs do layer.glyphs[index]:Hide() end
end

-- A four-cornered piece of the view, corners in order around it (top left, top right, bottom
-- right, bottom left), in view coordinates with y growing downwards.
local function Quad(layer, color, ax, ay, bx, by, cx, cy, dx, dy)
   layer.usedQuads = layer.usedQuads + 1
   local quad = layer.quads[layer.usedQuads]
   if not quad then
      quad = layer:CreateTexture(nil, "ARTWORK")
      quad:SetPoint("TOPLEFT", layer, "TOPLEFT", 0, 0)
      quad:SetSize(1, 1)
      layer.quads[layer.usedQuads] = quad
   end
   quad:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
   quad:SetVertexOffset(1, ax, -ay)
   quad:SetVertexOffset(2, dx, 1 - dy)
   quad:SetVertexOffset(3, bx - 1, -by)
   quad:SetVertexOffset(4, cx - 1, 1 - cy)
   quad:Show()
end

-- A picture standing on the floor at (x, y) in the view, width pixels wide.
local function Icon(layer, texture, x, y, width, height)
   layer.usedIcons = layer.usedIcons + 1
   local icon = layer.icons[layer.usedIcons]
   if not icon then
      icon = layer:CreateTexture(nil, "OVERLAY")
      icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      layer.icons[layer.usedIcons] = icon
   end
   icon:SetTexture(texture)
   icon:ClearAllPoints()
   icon:SetPoint("BOTTOM", layer, "TOPLEFT", x, -y)
   icon:SetSize(width, height)
   icon:Show()
end

local function Glyph(layer, text, color, x, y, size)
   layer.usedGlyphs = layer.usedGlyphs + 1
   local glyph = layer.glyphs[layer.usedGlyphs]
   if not glyph then
      glyph = layer:CreateFontString(nil, "OVERLAY")
      layer.glyphs[layer.usedGlyphs] = glyph
   end
   glyph:SetFont("Fonts\\FRIZQT__.TTF", max(6, floor(size)), "OUTLINE")
   glyph:SetText(text)
   glyph:SetTextColor(color[1], color[2], color[3])
   glyph:ClearAllPoints()
   glyph:SetPoint("BOTTOM", layer, "TOPLEFT", x, -y)
   glyph:Show()
end

----------------------------------------------------------------
-- The camera
----------------------------------------------------------------

local camera = {}

-- Where a point appears in the view: x, y (down), the scale of one unit there and how far
-- ahead it is.  Nil if it is too close to the camera or behind it.
local function Project(wx, wy, wz)
   local ahead = camera.y - wy
   if ahead < MIN_AHEAD then return nil end
   local scale = FOCAL / ahead
   return camera.centerX + (wx - camera.x) * scale, camera.horizon + (CAMERA_HEIGHT - wz) * scale, scale, ahead
end

-- Things far away are darker.
local function Shade(color, ahead, factor, alpha)
   local fog = 1 - 0.55 * min(1, ahead / FOG_REACH)
   fog = fog * (factor or 1)
   return { color[1] * fog, color[2] * fog, color[3] * fog, alpha }
end

----------------------------------------------------------------
-- Drawing
----------------------------------------------------------------

function map3d:Create(view)
   self.view = view
   self.layers = {}
   local base = view:GetFrameLevel() + 1
   for row = 1, ROWS do
      self.layers[row] = {
         [FLOOR] = NewLayer(view, base + (row - 1) * 3 + FLOOR),
         [WALL] = NewLayer(view, base + (row - 1) * 3 + WALL),
         [ACTOR] = NewLayer(view, base + (row - 1) * 3 + ACTOR),
      }
   end
   self:Hide()
end

function map3d:Hide()
   for _, layers in ipairs(self.layers or {}) do
      for _, layer in pairs(layers) do layer:Hide() end
   end
   self.shown = false
end

local function IsWall(x, y)
   return x >= 1 and x <= MAXX and y >= 1 and y <= MAXY and G.know[x][y] ~= 0 and G.item[x][y] == K.OWALL
end

-- The floor tile (x, y), and what stands on it.
local function DrawTile(layers, x, y, ground)
   local x0, x1, y0, y1 = (x - 1) * TILE, x * TILE, (y - 1) * TILE, y * TILE
   local ax, ay, _, aheadFar = Project(x0, y0, 0)
   local bx, by = Project(x1, y0, 0)
   local cx, cy, _, aheadNear = Project(x1, y1, 0)
   local dx, dy = Project(x0, y1, 0)
   if not (ax and bx and cx and dx) then return end
   local ahead = (aheadFar + aheadNear) / 2

   if IsWall(x, y) then
      local color = V.WALL
      local wh = WALL_HEIGHT
      -- a wall between the camera and the player lets the player show through
      local alpha = (y > G.playery and math.abs(x - G.playerx) <= 1) and SEE_THROUGH or 1
      local tx0, ty0 = Project(x0, y0, wh)
      local tx1, ty1 = Project(x1, y0, wh)
      local tx2, ty2 = Project(x1, y1, wh)
      local tx3, ty3 = Project(x0, y1, wh)
      if tx0 and tx1 and tx2 and tx3 then
         Quad(layers[WALL], Shade(color, ahead, 1, alpha), tx0, ty0, tx1, ty1, tx2, ty2, tx3, ty3)
         if not IsWall(x, y + 1) then  -- the face towards the camera
            Quad(layers[WALL], Shade(color, ahead, 0.72, alpha), tx3, ty3, tx2, ty2, cx, cy, dx, dy)
         end
         if camera.x > x1 and not IsWall(x + 1, y) then  -- the east face
            Quad(layers[WALL], Shade(color, ahead, 0.55, alpha), tx1, ty1, tx2, ty2, cx, cy, bx, by)
         elseif camera.x < x0 and not IsWall(x - 1, y) then  -- the west face
            Quad(layers[WALL], Shade(color, ahead, 0.55, alpha), tx0, ty0, tx3, ty3, dx, dy, ax, ay)
         end
      end
      return
   end

   local checker = ((x + y) % 2 == 0) and 1 or 0.93
   Quad(layers[FLOOR], Shade(ground, ahead, checker), ax, ay, bx, by, cx, cy, dx, dy)

   -- what stands on the floor, in the middle of the tile
   local mx, my, scale = Project((x - 0.5) * TILE, (y - 0.5) * TILE, 0)
   if not mx then return end
   local monster = ns.Display.visibleMonster(x, y)
   local object = G.item[x][y]
   if x == G.playerx and y == G.playery then
      local size = TILE * 0.9 * scale
      Icon(layers[ACTOR], V.ClassIcon(G.class), mx, my + size * 0.15, size, size)
   elseif monster ~= 0 then
      Glyph(layers[ACTOR], V.MonsterGlyph(monster), V.MONSTER_COLOR, mx, my + TILE * 0.1 * scale, TILE * 0.9 * scale)
   elseif object ~= 0 then
      local icon = V.ObjectIcon(object)
      local size = TILE * 0.6 * scale
      if icon then
         Icon(layers[ACTOR], icon, mx, my + size * 0.1, size, size)
      else
         Glyph(layers[ACTOR], V.ObjectGlyph(object), V.GLYPH_COLOR, mx, my + size * 0.1, size)
      end
   end
end

function map3d:Draw()
   if not self.layers or not G.class then return end
   self.shown = true
   local view = self.view
   local width, height = view:GetWidth(), view:GetHeight()
   camera.centerX = width / 2
   camera.horizon = height * PLAYER_AT - CAMERA_HEIGHT * FOCAL / CAMERA_BACK
   camera.x = (G.playerx - 0.5) * TILE
   camera.y = (G.playery - 0.5) * TILE + CAMERA_BACK
   local ground = V.Ground(G.level)

   for row = 1, ROWS do
      for _, layer in pairs(self.layers[row]) do
         layer:Show()
         Begin(layer)
      end
   end
   -- Row 1 is the farthest (north), the last row the nearest.
   for row = 1, ROWS do
      local y = G.playery - FAR_ROWS + (row - 1)
      if y >= 1 and y <= MAXY then
         local layers = self.layers[row]
         for x = max(1, G.playerx - SIDE_COLUMNS), min(MAXX, G.playerx + SIDE_COLUMNS) do
            if G.know[x][y] ~= 0 then DrawTile(layers, x, y, ground) end
         end
      end
   end
   for row = 1, ROWS do
      for _, layer in pairs(self.layers[row]) do Finish(layer) end
   end
end
