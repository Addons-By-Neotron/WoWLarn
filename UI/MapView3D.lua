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
-- CAMERA_BACK units south of the player and CAMERA_HEIGHT above the floor (CAMERA_DISTANCE
-- away whatever the angle), pitched down at the player, so "ahead" is the distance along the
-- line of sight.
local map3d = {}
ns.map3d = map3d

local TILE, WALL_HEIGHT = 64, 64
local WALL_INSET = 12  -- how much thinner a wall is than its tile, on the sides facing open floor
local CAMERA_DISTANCE = 640  -- from the camera to the player, whatever the angle
local TILE_PIXELS = 55  -- how wide the tile of the player is on the screen
local CAMERA_BACK, CAMERA_HEIGHT, FOCAL  -- from the camera angle, see map3d:Draw
local SIN, COS = 0, 1  -- of the angle
local PLAYER_AT = 0.62  -- how far down the view the player stands
local NEAR_ROWS, FAR_ROWS, SIDE_COLUMNS = 4, 13, 14
local ROWS = NEAR_ROWS + FAR_ROWS + 1
local MIN_AHEAD = 24
local SEE_THROUGH = 0.3  -- how solid a wall in front of the player is
local FOG_REACH = 1700  -- ahead at which things are at their darkest
local floor, max, min = math.floor, math.max, math.min
local MAXX, MAXY = K.MAXX, K.MAXY

local FACING = 0  -- the facing at which a model looks towards the camera (south)
local TURN = 1  -- 1 if a larger facing turns a model from south to east, -1 if the other way
-- how far to turn from south, for the directions of the game (south, east, north, west, then
-- northeast, northwest, southeast, southwest)
local TURN_TO = {
   0, math.pi / 2, math.pi, math.pi * 1.5, math.pi * 0.75, math.pi * 1.25, math.pi * 0.25, math.pi * 1.75,
}
-- the direction that goes from one tile towards another, as a number of the game
local DIRECTION = {
   [0] = { [1] = 1, [0] = 1, [-1] = 3 },
   [1] = { [0] = 2, [-1] = 5, [1] = 7 },
   [-1] = { [0] = 4, [-1] = 6, [1] = 8 },
}
local function Facing(dir)
   return FACING + TURN * (TURN_TO[dir] or 0)
end
local function Sign(value) return value > 0 and 1 or value < 0 and -1 or 0 end
local MODEL_ASPECT = 1.7  -- how much taller than wide a model is drawn
local MODEL_ROOM = 2  -- (see Model)
local ANIM = { stand = 0, death = 1, walk = 4, wound = 14, attack = 16 }  -- model animations
local TWEEN = 0.16  -- seconds a step takes
local MONSTER_TWEEN = 0.22
local FLOOR, WALL, ACTOR = 0, 1, 2  -- the layers of a row, back to front

----------------------------------------------------------------
-- Pools of pieces
----------------------------------------------------------------

-- A layer of a row: a frame over the whole view with a pool of quads, icons and glyphs.
local function NewLayer(view, level)
   local frame = CreateFrame("Frame", nil, view)
   frame:SetAllPoints(view)
   frame:SetFrameLevel(level)
   frame.quads, frame.icons, frame.glyphs, frame.models = {}, {}, {}, {}
   frame.usedQuads, frame.usedIcons, frame.usedGlyphs, frame.usedModels = 0, 0, 0, 0
   return frame
end

local function Begin(layer)
   layer.usedQuads, layer.usedIcons, layer.usedGlyphs, layer.usedModels = 0, 0, 0, 0
end

local function Finish(layer)
   for index = layer.usedQuads + 1, #layer.quads do layer.quads[index]:Hide() end
   for index = layer.usedIcons + 1, #layer.icons do layer.icons[index]:Hide() end
   for index = layer.usedGlyphs + 1, #layer.glyphs do layer.glyphs[index]:Hide() end
   for index = layer.usedModels + 1, #layer.models do layer.models[index]:Hide() end
end

-- A four-cornered piece of the view, corners in order around it (top left, top right, bottom
-- right, bottom left), in view coordinates with y growing downwards.
local function Quad(layer, color, ax, ay, bx, by, cx, cy, dx, dy, texture)
   layer.usedQuads = layer.usedQuads + 1
   local quad = layer.quads[layer.usedQuads]
   if not quad then
      quad = layer:CreateTexture(nil, "ARTWORK")
      quad:SetPoint("TOPLEFT", layer, "TOPLEFT", 0, 0)
      quad:SetSize(1, 1)
      layer.quads[layer.usedQuads] = quad
   end
   if texture then
      quad:SetTexture(texture)
      quad:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
   else
      quad:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
      quad:SetVertexColor(1, 1, 1, 1)
   end
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

-- A creature standing on the floor at (x, y) in the view: a model of the unit ("player") or of
-- a display, width pixels wide and about twice as tall.
local function Model(layer, look, x, y, width, facing, anim)
   layer.usedModels = layer.usedModels + 1
   local models, used = layer.models, layer.usedModels
   -- keep a model that is playing its animation (a dying one) on its own frame: when the
   -- pool shifts, setting another look on it would restart it
   if anim == ANIM.death and not (models[used] and models[used].look == look and models[used].anim == anim) then
      for index = used + 1, #models do
         if models[index].look == look and models[index].anim == anim then
            models[used], models[index] = models[index], models[used]
            break
         end
      end
   end
   local frame = models[used]
   if not frame then
      frame = CreateFrame("Frame", nil, layer)
      frame.model = CreateFrame("PlayerModel", nil, frame)
      frame.model:SetAllPoints()
      frame.model:SetScript("OnModelLoaded", function(self)
         self:SetFacing(frame.facing or FACING)
         if frame.anim and self.SetAnimation then self:SetAnimation(frame.anim) end  -- (loading resets it)
         if self.SetModelScale then self:SetModelScale(1 / MODEL_ROOM) end  -- (and this)
      end)
      layer.models[layer.usedModels] = frame
   end
   if frame.look ~= look then  -- (setting the look again would restart it)
      frame.look = look
      if look == "player" then
         frame.model:SetUnit("player")
      else
         frame.model:SetDisplayInfo(look)
      end
      frame.facing, frame.anim = nil, nil
   end
   anim = anim or ANIM.stand
   if frame.anim ~= anim then
      frame.anim = anim
      if frame.model.SetAnimation then frame.model:SetAnimation(anim) end
   end
   if frame.facing ~= facing then
      frame.facing = facing
      frame.model:SetFacing(facing)
   end
   -- a model is clipped to its frame and a dying one lies down wider than it stands, so
   -- every model gets a frame MODEL_ROOM times larger around the same centre, and is scaled
   -- down by the same factor to look the same size (always, so nothing changes when it dies)
   local k = MODEL_ROOM
   y = y + (V.LOWER[look] or 0) * width
   frame:ClearAllPoints()
   frame:SetPoint("CENTER", layer, "TOPLEFT", x, -(y - width * MODEL_ASPECT / 2))
   frame:SetSize(width * k, width * k * MODEL_ASPECT)
   if frame.model.SetModelScale and not frame.scaled then
      frame.scaled = true
      frame.model:SetModelScale(1 / k)
   end
   frame:Show()
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
   local back, up = camera.y - wy, wz - CAMERA_HEIGHT
   local ahead = back * COS - up * SIN  -- along the line of sight
   if ahead < MIN_AHEAD then return nil end
   local scale = FOCAL / ahead
   return camera.centerX + (wx - camera.x) * scale, camera.centerY - (back * SIN + up * COS) * scale, scale, ahead
end

-- Things far away are darker.
local function Shade(color, ahead, factor, alpha)
   local fog = 1 - 0.55 * min(1, ahead / FOG_REACH)
   fog = fog * (factor or 1)
   return { color[1] * fog, color[2] * fog, color[3] * fog, alpha }
end

-- A round shadow on the floor around the world point (wx, wy).
local SHADOW = "Interface\\AddOns\\WoWLarn\\Media\\Shadow"  -- (a soft round fade)
local SHADOW_COLOR = { 0, 0, 0, 0.6 }
local SHADOW_LIFT = TILE * 0.2  -- how far up the screen the shadow sits, to be under the feet
local function Shadow(layer, wx, wy, radius)
   if ns.mod.db.profile.shadows == false then return end
   local _, _, scale = Project(wx, wy, 0)
   if not scale then return end
   local lift = SHADOW_LIFT * scale  -- (the feet are a little above the bottom of a model)
   local ax, ay = Project(wx - radius, wy - radius, 0)
   local bx, by = Project(wx + radius, wy - radius, 0)
   local cx, cy = Project(wx + radius, wy + radius, 0)
   local dx, dy = Project(wx - radius, wy + radius, 0)
   if ax and bx and cx and dx then
      Quad(layer, SHADOW_COLOR, ax, ay - lift, bx, by - lift, cx, cy - lift, dx, dy - lift, SHADOW)
   end
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
   return x >= 1 and x <= MAXX and y >= 1 and y <= MAXY and ns.Display.remembered(x, y) and G.item[x][y] == K.OWALL
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
      -- a wall is thinner than its tile on the sides that face open floor, so what stands
      -- next to it does not overlap it
      local west = IsWall(x - 1, y) and 0 or WALL_INSET
      local east = IsWall(x + 1, y) and 0 or WALL_INSET
      local north = IsWall(x, y - 1) and 0 or WALL_INSET
      local south = IsWall(x, y + 1) and 0 or WALL_INSET
      local wx0, wx1, wy0, wy1 = x0 + west, x1 - east, y0 + north, y1 - south
      if west + east + north + south > 0 then  -- the ground around it
         Quad(layers[FLOOR], Shade(ground, ahead, 0.5), ax, ay, bx, by, cx, cy, dx, dy)
      end
      local fax, fay = Project(wx0, wy0, 0)
      local fbx, fby = Project(wx1, wy0, 0)
      local fcx, fcy = Project(wx1, wy1, 0)
      local fdx, fdy = Project(wx0, wy1, 0)
      local tx0, ty0 = Project(wx0, wy0, wh)
      local tx1, ty1 = Project(wx1, wy0, wh)
      local tx2, ty2 = Project(wx1, wy1, wh)
      local tx3, ty3 = Project(wx0, wy1, wh)
      if tx0 and tx1 and tx2 and tx3 and fcx and fdx and fax and fbx then
         Quad(layers[WALL], Shade(color, ahead, 1, alpha), tx0, ty0, tx1, ty1, tx2, ty2, tx3, ty3)
         if not IsWall(x, y + 1) then  -- the face towards the camera
            Quad(layers[WALL], Shade(color, ahead, 0.72, alpha), tx3, ty3, tx2, ty2, fcx, fcy, fdx, fdy)
         end
         if camera.x > wx1 and not IsWall(x + 1, y) then  -- the east face
            Quad(layers[WALL], Shade(color, ahead, 0.55, alpha), tx1, ty1, tx2, ty2, fcx, fcy, fbx, fby)
         elseif camera.x < wx0 and not IsWall(x - 1, y) then  -- the west face
            Quad(layers[WALL], Shade(color, ahead, 0.55, alpha), tx0, ty0, tx3, ty3, fdx, fdy, fax, fay)
         end
      end
      return
   end

   local checker = ((x + y) % 2 == 0) and 1 or 0.93
   Quad(layers[FLOOR], Shade(ground, ahead, checker), ax, ay, bx, by, cx, cy, dx, dy)

   if G.know[x][y] == 0 and not (x == G.playerx and y == G.playery) then return end  -- (not in sight)

   -- what stands on the floor, in the middle of the tile
   local mx, my, scale = Project((x - 0.5) * TILE, (y - 0.5) * TILE, 0)
   if not mx then return end
   local monster = ns.Display.visibleMonster(x, y)
   local object = G.item[x][y]
   local models = ns.mod.db.profile.models ~= false and not ns.mod.db.profile.ascii
   if x == G.playerx and y == G.playery then
      return  -- (drawn at its own, possibly moving, position)
   elseif monster ~= 0 then
      local look = G.look[x][y]
      if look == 0 then
         look = ns.rnd(1000)
         G.look[x][y] = look
      end
      local display = models and V.MonsterDisplay(monster, look)
      if display then
         -- monsters face the player they are after
         local toward = DIRECTION[Sign(G.playerx - x)][Sign(G.playery - y)]
         local entry = map3d.anims[x * 100 + y]
         local anim = entry and entry.expires > GetTime() and entry.anim or nil
         -- a monster that just moved glides from the tile it came from
         local wx, wy = (x - 0.5) * TILE, (y - 0.5) * TILE
         local move = map3d.moves[x * 100 + y]
         if move then
            local f = (GetTime() - move.t0) / MONSTER_TWEEN
            if f >= 1 then
               map3d.moves[x * 100 + y] = nil
            else
               map3d.tweening = true
               wx, wy = wx + (move.fromX - x) * TILE * (1 - f), wy + (move.fromY - y) * TILE * (1 - f)
               anim = anim or ANIM.walk
               local sx, sy, sscale = Project(wx, wy, 0)
               if sx then mx, my, scale = sx, sy, sscale end
            end
         end
         Shadow(layers[ACTOR], wx, wy, TILE * 0.42)
         Model(layers[ACTOR], display, mx, my + TILE * 0.05 * scale, TILE * 0.9 * scale, Facing(toward), anim)
      else
         Glyph(layers[ACTOR], V.MonsterGlyph(monster), V.MONSTER_COLOR, mx, my + TILE * 0.1 * scale, TILE * 0.9 * scale)
      end
   elseif map3d.ghosts[x * 100 + y] and map3d.ghosts[x * 100 + y].expires > GetTime() then
      local ghost = map3d.ghosts[x * 100 + y]
      Shadow(layers[ACTOR], (x - 0.5) * TILE, (y - 0.5) * TILE, TILE * 0.42)
      Model(layers[ACTOR], ghost.display, mx, my + TILE * 0.05 * scale, TILE * 0.9 * scale, ghost.facing, ANIM.death)
   elseif object ~= 0 then
      local icon = not ns.mod.db.profile.ascii and V.ObjectIcon(object)
      local size = TILE * 0.6 * scale
      if icon then
         Icon(layers[ACTOR], icon, mx, my + size * 0.1, size, size)
      else
         Glyph(layers[ACTOR], V.ObjectGlyph(object), V.GLYPH_COLOR, mx, my + size * 0.1, size)
      end
   end
end

map3d.anims, map3d.ghosts, map3d.moves = {}, {}, {}  -- by tile (x * 100 + y): what a monster there is doing
map3d.playerAnim = nil  -- { anim, expires }

-- For the flat view, which draws the same models: what to draw for the monster on (x, y), or
-- nil if it has no model (or models are off): its display, the facing and the animation.
function map3d.MonsterModel(x, y)
   local monster = ns.Display.visibleMonster(x, y)
   if monster == 0 or ns.mod.db.profile.models == false or ns.mod.db.profile.ascii then return nil end
   local look = G.look[x][y]
   if look == 0 then
      look = ns.rnd(1000)
      G.look[x][y] = look
   end
   local display = V.MonsterDisplay(monster, look)
   if not display then return nil end
   local entry = map3d.anims[x * 100 + y]
   return display, Facing(DIRECTION[Sign(G.playerx - x)][Sign(G.playery - y)]),
      entry and entry.expires > GetTime() and entry.anim or nil
end

-- The facing and the animation of the player model.
function map3d.PlayerModel()
   local entry = map3d.playerAnim
   return Facing(G.facing), entry and entry.expires > GetTime() and entry.anim or nil
end
map3d.Model = Model

local function Redraw()
   if map3d.shown then ns.map:Draw() end
end

-- Something happens on the tile (x, y), for a while: "hit" (the player attacks it), "bite" (the
-- monster there attacks), "wound", "die" (the monster is gone from the map by now) and
-- "hurt" (the player is wounded).
function map3d:Animate(kind, x, y, monster, fromY)
   local now, key = GetTime(), x and x * 100 + y
   if kind == "move" then  -- a monster stepped from (monster, fromY) to (x, y)
      self.moves[key] = { fromX = monster, fromY = fromY, t0 = now }
      C_Timer.After(MONSTER_TWEEN + 0.05, Redraw)
      return
   end
   local duration = 0.7
   if x and kind ~= "hurt" then  -- the player turns towards what it fights
      local dir = DIRECTION[Sign(x - G.playerx)][Sign(y - G.playery)]
      if dir and (kind == "hit" or kind == "bite") then G.facing = dir end
   end
   if kind == "hit" then
      self.playerAnim = { anim = ANIM.attack, expires = now + duration }
   elseif kind == "hurt" then
      self.playerAnim = { anim = ANIM.wound, expires = now + duration }
   elseif kind == "bite" then
      self.anims[key] = { anim = ANIM.attack, expires = now + duration }
   elseif kind == "wound" then
      self.anims[key] = { anim = ANIM.wound, expires = now + duration }
   elseif kind == "die" then
      duration = 2.6
      local look = G.look[x][y]
      local display = look ~= 0 and monster and V.MonsterDisplay(monster, look)
      if display then
         self.ghosts[key] = { display = display, expires = now + duration,
            facing = Facing(DIRECTION[Sign(G.playerx - x)][Sign(G.playery - y)]) }
      end
   end
   C_Timer.After(duration + 0.05, Redraw)  -- back to standing
end

-- A glow under the player for a moment: color is { r, g, b }.
function map3d:Flash(color)
   self.flash = { color = color, expires = GetTime() + 0.6 }
   Redraw()
   C_Timer.After(0.65, Redraw)
end

-- Where the player is drawn: it glides to the tile it moved to.
-- The tile under the cursor (pixels from the top left of the view): the floor it points at, or
-- the tile of a monster or an object standing there.
function map3d:TileAt(sx, sy)
   if not camera.centerX then return nil end
   local u, v = (sx - camera.centerX) / FOCAL, (camera.centerY - sy) / FOCAL
   local function Floor(z)
      local slope = SIN - v * COS
      if slope <= 0.01 then return nil end
      local t = (CAMERA_HEIGHT - z) / slope
      local back = t * (COS + v * SIN)
      return floor((camera.x + u * t) / TILE) + 1, floor((camera.y - back) / TILE) + 1
   end
   local x, y = Floor(TILE * 0.6)  -- (the middle of a standing thing)
   if x and x >= 1 and y >= 1 and x <= MAXX and y <= MAXY and G.know[x][y] ~= 0
      and (ns.Display.visibleMonster(x, y) ~= 0 or (G.item[x][y] ~= 0 and G.item[x][y] ~= K.OWALL)) then
      return x, y
   end
   return Floor(0)
end

-- Redraws a few times a second while something glides.
function map3d:EnsureDriver()
   self.driver = self.driver or CreateFrame("Frame")  -- (the view has its own OnUpdate)
   if self.driver:GetScript("OnUpdate") then return end
   local since = 0
   self.driver:SetScript("OnUpdate", function(driver, elapsed)
      since = since + elapsed
      if since < 0.03 then return end
      since = 0
      Redraw()
      if not map3d.t0 and not map3d.tweening then driver:SetScript("OnUpdate", nil) end
   end)
end

function map3d:Position()
   local px, py = G.playerx, G.playery
   if self.level ~= G.level or not self.toX or max(math.abs(px - self.toX), math.abs(py - self.toY)) > 1 then
      self.level, self.t0 = G.level, nil
      self.toX, self.toY = px, py
      return px, py, false
   end
   local now = GetTime()
   local curX, curY = self.toX, self.toY
   if self.t0 then
      local f = min(1, (now - self.t0) / TWEEN)
      curX, curY = self.fromX + (self.toX - self.fromX) * f, self.fromY + (self.toY - self.fromY) * f
   end
   if px ~= self.toX or py ~= self.toY then
      self.fromX, self.fromY, self.t0 = curX, curY, now
      self.toX, self.toY = px, py
      curX, curY = self.fromX, self.fromY
   end
   if self.t0 and now - self.t0 >= TWEEN then self.t0 = nil end
   if self.t0 then
      return curX, curY, true
   end
   return self.toX, self.toY, false
end

function map3d:Draw()
   if not self.layers or not G.class then return end
   self.shown = true
   local view = self.view
   local width, height = view:GetWidth(), view:GetHeight()
   -- the camera angle (degrees above the floor): steeper looks more like the flat map
   local angle = ns.mod.db.profile.cameraAngle or 55
   SIN, COS = math.sin(math.rad(angle)), math.cos(math.rad(angle))
   CAMERA_BACK, CAMERA_HEIGHT = CAMERA_DISTANCE * COS, CAMERA_DISTANCE * SIN
   FOCAL = CAMERA_DISTANCE * TILE_PIXELS / TILE
   camera.centerX = width / 2
   camera.centerY = height * PLAYER_AT
   self.tweening = false
   local posX, posY, walking = self:Position()
   camera.x = (posX - 0.5) * TILE
   camera.y = (posY - 0.5) * TILE + CAMERA_BACK
   local roundX, roundY = floor(posX + 0.5), floor(posY + 0.5)
   local ground = V.Ground(G.level)

   for row = 1, ROWS do
      for _, layer in pairs(self.layers[row]) do
         layer:Show()
         Begin(layer)
      end
   end
   -- Row 1 is the farthest (north), the last row the nearest.
   for row = 1, ROWS do
      local y = roundY - FAR_ROWS + (row - 1)
      if y >= 1 and y <= MAXY then
         local layers = self.layers[row]
         for x = max(1, roundX - SIDE_COLUMNS), min(MAXX, roundX + SIDE_COLUMNS) do
            if ns.Display.remembered(x, y) then DrawTile(layers, x, y, ground) end
         end
      end
   end
   -- the missile of a spell on its way: a glow on the floor and the glyph above it
   local overlay = ns.map.overlay
   if overlay then
      local row = overlay.y - (roundY - FAR_ROWS) + 1
      local layer = self.layers[row] and self.layers[row][ACTOR]
      if layer and overlay.x >= 1 and overlay.x <= MAXX and overlay.y >= 1 and overlay.y <= MAXY then
         local wx, wy = (overlay.x - 0.5) * TILE, (overlay.y - 0.5) * TILE
         local mx, my, scale = Project(wx, wy, TILE * 0.35)
         if mx then
            local ax, ay = Project(wx - TILE * 0.6, wy - TILE * 0.6, 0)
            local bx, by = Project(wx + TILE * 0.6, wy - TILE * 0.6, 0)
            local cx, cy = Project(wx + TILE * 0.6, wy + TILE * 0.6, 0)
            local dx, dy = Project(wx - TILE * 0.6, wy + TILE * 0.6, 0)
            if ax and bx and cx and dx then
               local color = V.MISSILE_COLOR
               Quad(layer, { color[1], color[2], color[3], 0.9 }, ax, ay, bx, by, cx, cy, dx, dy, SHADOW)
            end
            Glyph(layer, overlay.glyph, V.MISSILE_COLOR, mx, my, TILE * 1.1 * scale)
         end
      end
   end
   -- the player, in the row of the nearest tile
   do
      local layer = self.layers[FAR_ROWS + 1][ACTOR]
      local mx, my, scale = Project((posX - 0.5) * TILE, (posY - 0.5) * TILE, 0)
      if mx then
         local size = TILE * 0.9 * scale
         local models = ns.mod.db.profile.models ~= false and not ns.mod.db.profile.ascii
         if models then
            local entry = self.playerAnim
            local anim = entry and entry.expires > GetTime() and entry.anim or (walking and ANIM.walk or ANIM.stand)
            Shadow(layer, (posX - 0.5) * TILE, (posY - 0.5) * TILE, TILE * 0.42)
            local flash = self.flash
            if flash and flash.expires > GetTime() then  -- (fades out)
               local fade = (flash.expires - GetTime()) / 0.6
               local wx, wy, radius = (posX - 0.5) * TILE, (posY - 0.5) * TILE, TILE * (1.3 - 0.4 * fade)
               local ax, ay = Project(wx - radius, wy - radius, 0)
               local bx, by = Project(wx + radius, wy - radius, 0)
               local cx, cy = Project(wx + radius, wy + radius, 0)
               local dx, dy = Project(wx - radius, wy + radius, 0)
               if ax and bx and cx and dx then
                  local color = flash.color
                  Quad(layer, { color[1], color[2], color[3], 0.9 * fade }, ax, ay, bx, by, cx, cy, dx, dy, SHADOW)
               end
            end
            Model(layer, "player", mx, my + size * 0.1, size * 1.1, Facing(G.facing), anim)
         elseif ns.mod.db.profile.ascii then  -- the original @
            Glyph(layer, "@", V.PLAYER_COLOR, mx, my + size * 0.1, size)
         else
            Icon(layer, V.ClassIcon(G.class), mx, my + size * 0.15, size, size)
         end
      end
   end
   if self.t0 or self.tweening then self:EnsureDriver() end
   for row = 1, ROWS do
      for _, layer in pairs(self.layers[row]) do Finish(layer) end
   end
end
