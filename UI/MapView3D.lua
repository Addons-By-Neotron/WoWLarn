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
local NEAR_ROWS, FAR_ROWS, SIDE_COLUMNS = 4, 13, 14  -- (at a zoom of FULL_ZOOM or more: farther out there are more)
local ROWS = NEAR_ROWS + FAR_ROWS + 1
local FULL_ZOOM = 0.8
local MIN_AHEAD = 24
local SEE_THROUGH = 0.3  -- how solid a wall in front of the player is
local STEEP = math.sin(math.rad(50)) - 1e-9  -- from this angle up the camera looks over the walls
local FOG_REACH = 1700  -- ahead at which things are at their darkest
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
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
local SETTLE = 3  -- seconds a model gets its camera scale set again after loading
local PLAYER_ROOM = 2  -- how much larger a frame the player model gets, to the sides and up: a shapeshifted druid is wider than a tile
local FEET_DOWN = 0.13  -- of the width of a model: how far its feet are brought down the screen (towards the viewer), off the point they stood on
local MODEL_ROOM = 1  -- (see Model; above 1 the models are scaled down in larger frames, which proved unreliable)
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

-- The models are pooled too, but a creature gets the frame that already shows its look when
-- there is one, wherever it is in the pool: a model that is given another look is loaded again
-- (it blinks), and one that is hidden and shown again starts over.  A frame that is not taken in
-- a pass (pool.pass is the number of the pass) is hidden at its end.
-- The layers of the rows of the view share one pool (layer.shared): the creatures change rows as
-- the player moves, and a frame that keeps its parent, with only its level changed, keeps its
-- model.
local function BeginModels(layer)
   local pool = layer.models
   pool.pass = (type(pool.pass) == "number" and pool.pass or 0) + 1
end

local function EndModels(layer)
   local pool = layer.models
   for _, frame in ipairs(pool) do
      if frame.modelDraw ~= pool.pass then frame:Hide() end
   end
end
map3d.BeginModels, map3d.EndModels = BeginModels, EndModels

local function Begin(layer)
   layer.usedQuads, layer.usedIcons, layer.usedGlyphs, layer.usedModels = 0, 0, 0, 0
   if not layer.shared then BeginModels(layer) end
end

local function Finish(layer)
   for index = layer.usedQuads + 1, #layer.quads do layer.quads[index]:Hide() end
   for index = layer.usedIcons + 1, #layer.icons do layer.icons[index]:Hide() end
   for index = layer.usedGlyphs + 1, #layer.glyphs do layer.glyphs[index]:Hide() end
   if not layer.shared then EndModels(layer) end
end

-- A four-cornered piece of the view, corners in order around it (top left, top right, bottom
-- right, bottom left), in view coordinates with y growing downwards.
-- texture: a path (the soft round shadows and glows, blended), or a file data id of a piece of
-- terrain (opaque), with uv = { left, right, top, bottom } the part of it to show.  The quads are
-- pooled and reused: what it was last used for is set again every time.
-- Debug view (/larn surfaces): each kind of surface is drawn as a solid colour of its own.  The caller
-- says what kind it is making by setting surface before the call.
local SURFACE_COLORS = {
   floor = { 0.45, 0.45, 0.45 }, lava = { 0.5, 0.05, 0.05 }, shadow = { 0, 0, 0 },
   ["wall top"] = { 1, 1, 0.2 }, ["wall front"] = { 0.9, 0.15, 0.15 }, ["wall side"] = { 1, 0.55, 0.1 },
   ["wall strip"] = { 1, 0.45, 0.75 }, picture = { 1, 0, 1 },
   ["door leaf"] = { 0.2, 0.8, 0.2 }, ["lintel face"] = { 0.2, 0.4, 1 }, ["lintel top"] = { 0.2, 0.9, 0.9 },
   ["door jamb"] = { 0.7, 0.3, 1 }, ["pillar face"] = { 0.6, 0.4, 0.2 }, ["pillar top"] = { 0.7, 1, 0.2 },
}
local surface  -- the kind of the next quad (see SURFACE_COLORS)
local function Quad(layer, color, ax, ay, bx, by, cx, cy, dx, dy, texture, uv, level)
   layer.usedQuads = layer.usedQuads + 1
   local quad = layer.quads[layer.usedQuads]
   if not quad then
      quad = layer:CreateTexture(nil, "ARTWORK")
      quad:SetPoint("TOPLEFT", layer, "TOPLEFT", 0, 0)
      quad:SetSize(1, 1)
      layer.quads[layer.usedQuads] = quad
   end
   local sub = level or (type(texture) == "string" and 1 or 0)  -- (the shadows and glows over the floor, whatever the order the quads were made in)
   local debugColor = map3d.surfaces and SURFACE_COLORS[surface]
   if debugColor and surface ~= "shadow" then
      texture, color = nil, { debugColor[1], debugColor[2], debugColor[3], color[4] or 1 }
   end
   if quad.sub ~= sub then
      quad.sub = sub
      quad:SetDrawLayer("ARTWORK", sub)
   end
   local blend = (type(texture) == "number") and "DISABLE" or "BLEND"
   if quad.blend ~= blend then
      quad.blend = blend
      quad:SetBlendMode(blend)
   end
   if texture then
      if quad.texture ~= texture then
         quad.texture = texture
         -- (the pictures are 256 pixels and shown at a fraction of that: mipmaps keep them sharp)
         quad:SetTexture(texture, nil, nil, (type(texture) == "string" and level and level >= 2) and "TRILINEAR" or nil)
      end
      local l, r, t, b = 0, 1, 0, 1
      if uv then l, r, t, b = uv[1], uv[2], uv[3], uv[4] end
      if quad.l ~= l or quad.r ~= r or quad.t ~= t or quad.b ~= b then
         quad.l, quad.r, quad.t, quad.b = l, r, t, b
         quad:SetTexCoord(l, r, t, b)
      end
      quad:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
   else
      quad.texture = nil
      quad:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
      quad:SetVertexColor(1, 1, 1, 1)
   end
   quad:SetVertexOffset(1, ax, -ay)
   quad:SetVertexOffset(2, dx, 1 - dy)
   quad:SetVertexOffset(3, bx - 1, -by)
   quad:SetVertexOffset(4, cx - 1, 1 - cy)
   surface = nil
   quad:Show()
end

-- A picture standing on the floor at (x, y) in the view, width pixels wide.
local function Icon(layer, texture, x, y, width, height, picture)
   layer.usedIcons = layer.usedIcons + 1
   local icon = layer.icons[layer.usedIcons]
   if not icon then
      icon = layer:CreateTexture(nil, "OVERLAY")
      layer.icons[layer.usedIcons] = icon
   end
   V.SetIcon(icon, texture)
   -- (a picture is transparent already and shown whole; an icon is cut at the edges, and added: its black is left out)
   if picture then icon:SetTexCoord(0, 1, 0, 1) else icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
   icon:SetBlendMode((picture or ns.mod.db.profile.opaqueIcons) and "BLEND" or "ADD")
   icon:ClearAllPoints()
   icon:SetPoint("BOTTOM", layer, "TOPLEFT", x, -y)
   icon:SetSize(width, height)
   icon:Show()
end

-- Sets how far the camera stands from a model.  The client ignores a value equal to the last one,
-- even when the model has been loaded again since, so it is set to another value first.
local function CameraScale(model, scale)
   if not model.SetCamDistanceScale then return end
   model:SetCamDistanceScale(scale * 1.001)
   model:SetCamDistanceScale(scale)
end

map3d.CameraScale = CameraScale

-- True if the look is the player's: "player", or the model of the race picked for the game.
local function Own(look)
   return look == "player" or (look ~= nil and look == map3d.playerLook)
end

-- A creature standing on the floor at (x, y) in the view: a model of the unit ("player") or of
-- a display, width pixels wide and about twice as tall.
-- owner: a table that keeps its own frame (a dying monster), so the shifting of the pool of
-- frames never sets another look on it, which would restart its animation.
-- Raises the camera of a model so that it looks down on it as far as the camera of the view looks down on
-- the floor (by map3d.tilt: 1 as far, 0 not at all).  It is the camera that moves, not the model: a model
-- turned about its own axis would lean a different way for each way it faces.  The camera set up by the
-- client (fitted to the model, and as far back as the scale says) is made a custom one, which can be moved,
-- and kept (model.cam: where it was, the target, and the scale it was for); it is turned about the target at
-- the same distance.  A model that is loaded again starts over (OnModelLoaded).
local function SetTilt(model, scale)
   model.tiltDone, model.tiltAngle = map3d.tilt, ns.mod.db.profile.cameraAngle
   if not (model.GetCameraPosition and model.GetCameraTarget and model.SetCameraPosition and model.MakeCurrentCameraCustom) then return end
   local cam = model.cam
   if not cam then
      if map3d.tilt == 0 then return end  -- (nothing to change, and nothing kept)
      model:MakeCurrentCameraCustom()
      local cx, cy, cz = model:GetCameraPosition()
      local tx, ty, tz = model:GetCameraTarget()
      if not (cx and tx) then return end
      cam = { cx, cy, cz, tx, ty, tz, scale }
      model.cam = cam
   end
   local ratio = scale / cam[7]  -- (another scale since: the camera is further or nearer to the target)
   local tx, ty, tz = cam[4], cam[5], cam[6]
   local vx, vy, vz = (cam[1] - tx) * ratio, (cam[2] - ty) * ratio, (cam[3] - tz) * ratio
   local flat = math.sqrt(vx * vx + vy * vy)
   local r = math.sqrt(flat * flat + vz * vz)
   if flat < 1e-6 or r < 1e-6 then return end
   local hx, hy = vx / flat, vy / flat  -- (the way from the target to the camera, level)
   local before = math.atan2(vz, flat)
   local elevation = before + math.rad(ns.mod.db.profile.cameraAngle or 55) * map3d.tilt
   elevation = math.min(elevation, math.rad(89))
   local sin0, cos0, sinE, cosE = math.sin(before), math.cos(before), math.sin(elevation), math.cos(elevation)
   -- The target is the middle of the model, and a model is as tall as it is: seen from above its feet come up
   -- towards the middle, further for a tall one.  So the target is moved along the up of the camera until
   -- the feet (the origin of the model) are where they were on the screen, and each creature stands on its tile.
   local shift = -((sin0 - sinE) * (tx * hx + ty * hy) + (cosE - cos0) * tz)
   tx, ty, tz = tx - shift * sinE * hx, ty - shift * sinE * hy, tz + shift * cosE
   model:SetCameraTarget(tx, ty, tz)
   model:SetCameraPosition(tx + r * cosE * hx, ty + r * cosE * hy, tz + r * sinE)
end

-- The camera of a model: as far back as scale says (while it settles), then raised (see SetTilt).
local function ApplyCamera(model, scale, settling)
   if settling or not model.cam and not model.settled then
      CameraScale(model, scale)
   end
   if not settling then
      model.settled = true
      SetTilt(model, scale)
   end
end

local function Model(layer, look, x, y, width, facing, anim, owner)
   local frame = owner and owner.frame
   if not frame and not owner then
      local spare
      local pool = layer.models
      for _, candidate in ipairs(pool) do
         if candidate.modelDraw ~= pool.pass then
            if candidate.look == look then frame = candidate break end
            spare = spare or candidate
         end
      end
      frame = frame or spare
   end
   if not frame then
      -- (an owned frame hangs on the view: changing its parent, or hiding it, restarts it)
      frame = CreateFrame("Frame", nil, (owner or layer.shared) and layer:GetParent() or layer)
      frame.model = CreateFrame("PlayerModel", nil, frame)
      frame.model:SetAllPoints()
      frame.model:SetScript("OnModelLoaded", function(self)
         self:SetFacing(frame.facing or FACING)
         if frame.anim and self.SetAnimation then self:SetAnimation(frame.anim) end  -- (loading resets it)
         if MODEL_ROOM ~= 1 and self.SetModelScale then self:SetModelScale(1 / MODEL_ROOM) end  -- (and this)
         self.cam, self.settled = nil, false  -- (the camera starts over)
         ApplyCamera(self, frame.scale or 1, true)  -- (and this)
         self.settleUntil = GetTime() + SETTLE  -- (the client sets up the camera of a model after it has loaded)
      end)
      frame.model:SetScript("OnUpdate", function(self)
         if self.settleUntil and self.settleUntil > GetTime() then
            ApplyCamera(self, frame.scale or 1, true)
         elseif self.tiltDone ~= map3d.tilt or self.tiltAngle ~= ns.mod.db.profile.cameraAngle then
            self.tiltAngle = ns.mod.db.profile.cameraAngle
            ApplyCamera(self, frame.scale or 1)  -- (the setting or the angle of the view changed)
         end
      end)
      if owner then
         owner.frame = frame
      else
         layer.models[#layer.models + 1] = frame
      end
   end
   if not owner then frame.modelDraw = layer.models.pass end
   if layer.shared and not owner then  -- (above the row it stands in)
      local level = layer:GetFrameLevel() + 1
      if frame.level ~= level then
         frame.level = level
         frame:SetFrameLevel(level)
      end
   end
   if owner then  -- (follows its tile from row to row)
      owner.drawn = map3d.drawn
      if frame.level ~= layer:GetFrameLevel() + 1 then
         frame.level = layer:GetFrameLevel() + 1
         frame:SetFrameLevel(frame.level)
      end
   end
   if frame.look ~= look then  -- (setting the look again would restart it)
      frame.look = look
      if look == "player" then
         frame.model:ClearModel()  -- (as the character sheets do: a model that is loaded keeps its form)
         frame.model:SetUnit("player", false, true)  -- (as you are, not in a form: a druid's bear or bird does not fit a tile)
      elseif look < 0 then  -- (a model file data id, negated)
         frame.model:SetModel(-look)
      else
         if Own(look) then frame.model:ClearModel() end  -- (the frame may have held the unit)
         frame.model:SetDisplayInfo(look)
      end
      frame.facing, frame.anim = nil, nil
      frame.model.settleUntil = GetTime() + SETTLE
   end
   anim = anim or ANIM.stand
   if frame.anim ~= anim then
      frame.anim = anim
      if frame.model.SetAnimation then frame.model:SetAnimation(anim) end
   end
   facing = facing or FACING
   if frame.facing ~= facing then
      frame.facing = facing
      frame.model:SetFacing(facing)
   end
   -- a model is clipped to its frame and a dying one lies down wider than it stands, so
   -- every model gets a frame MODEL_ROOM times larger around the same centre, and is scaled
   -- down by the same factor to look the same size (always, so nothing changes when it dies)
   local k = MODEL_ROOM
   local room = not Own(look) and V.Room(look) or PLAYER_ROOM
   local own = look == "player" and V.PlayerScale() or 1  -- (a short race: the model is smaller, so the feet are brought down again)
   y = y + (not Own(look) and V.Lower(look) or (1 - 1 / own) / 2 * MODEL_ASPECT * 0.9) * width + FEET_DOWN * width
   frame:ClearAllPoints()
   frame:SetPoint("CENTER", layer, "TOPLEFT", x, -(y - width * MODEL_ASPECT / 2))
   frame:SetSize(width * k * room, width * k * room * MODEL_ASPECT)
   -- (every time: the client resets the scale when it reloads or restarts the model)
   if k ~= 1 and frame.model.SetModelScale then frame.model:SetModelScale(1 / k) end
   -- (after the size: the client sets up the camera again when a frame is resized)
   local scale = not Own(look) and V.Scale(look) * V.Room(look) or own * PLAYER_ROOM  -- (a larger frame, the camera further back)
   if frame.scale ~= scale then
      frame.scale = scale
      if frame.model.cam then
         ApplyCamera(frame.model, scale)
      else
         CameraScale(frame.model, scale)
      end
      frame.model.settleUntil = GetTime() + SETTLE
   end
   frame:Show()
end

map3d.tilt = 0  -- how much of the camera angle the models lean by (1: as much as the camera looks down; debug: /larn tilt)
map3d.Model = Model  -- (the monster zoo draws with it)
map3d.MODEL_ASPECT = MODEL_ASPECT
map3d.Begin, map3d.Finish = Begin, Finish

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

-- Things far away are darker: the colour is multiplied by 1 at the camera, down to 0.45 at
-- FOG_REACH and beyond (the "Distance fog" option turns this off; factor still applies).
local function Shade(color, ahead, factor, alpha)
   local fog = ns.mod.db.profile.fog == false and 1 or 1 - 0.55 * min(1, ahead / FOG_REACH)
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
      surface = "shadow"
      Quad(layer, SHADOW_COLOR, ax, ay - lift, bx, by - lift, cx, cy - lift, dx, dy - lift, SHADOW)
   end
end

-- A picture floating in the middle of a tile, a little above the floor, always flat to the
-- screen (it keeps its shape whatever the camera angle), with a shadow below.
local PICTURE_LIFT = 0.1  -- of a tile, how far above the floor it floats
local BOB, BOB_SPEED = 0.035, 2.2  -- of a tile, how far it bobs up and down, and how fast (radians per second)
local WHITE = { 1, 1, 1, 1 }  -- (pictures are not darkened by the distance fog)
-- still: stands on the floor and does not bob (furniture, see V.STANDING)
local function PictureQuad(layer, texture, tileX, tileY, size, ahead, still, ax, ay)
   local wx, wy = (tileX - 0.5) * TILE, (tileY - 0.5) * TILE
   local bob = 0
   if not still then
      map3d.bobbing = true  -- (the view is drawn again and again while one is in sight)
      bob = BOB * math.sin(GetTime() * BOB_SPEED + tileX * 7 + tileY * 13)  -- (each at its own point of the swing)
   end
   -- The bottom edge of the picture stands at the point of the floor (lifted, if it floats).  The
   -- picture is flat to the screen, so its height is added on the screen: put up in the world
   -- as a height, it would be foreshortened by the angle of the camera and the picture would
   -- slide over the floor when the angle is changed.
   local sx, sy, scale = Project(wx, wy, (still and 0 or PICTURE_LIFT) * TILE)
   if not sx then return end
   local uv = V.Flipbook(texture)
   if uv then map3d.bobbing = true end  -- (a flipbook turns: the view is drawn again and again)
   local half = size * TILE * scale / 2
   sy = sy - half - bob * TILE * scale  -- (on the screen, not in the world: straight above, a height would hardly show)
   -- (no shadow: the soft one under a floating picture lay over its lower part; and the picture
   -- is on a sublevel above any shadow, whatever the order the quads were made in)
   -- (ax, ay: the point of the picture, as a part of its width from the left and of its height
   -- from the bottom, that goes on the floor point; by default the middle of the bottom edge)
   sx = sx + (0.5 - (ax or 0.5)) * 2 * half
   sy = sy + (ay or 0) * 2 * half
   surface = "picture"
   Quad(layer, WHITE, sx - half, sy - half, sx + half, sy - half, sx + half, sy + half, sx - half, sy + half, texture, uv, 2)
end

-- A tile with a creature (a display, or "player") on it, as the map draws them, for the
-- monster zoo: the centre of the tile is at (sx, sy) in the view of layer, zoom times larger.
function map3d.DrawTile(layer, look, sx, sy, zoom, floorColor, facing)
   local angle = ns.mod.db.profile.cameraAngle or 55
   SIN, COS = math.sin(math.rad(angle)), math.cos(math.rad(angle))
   CAMERA_BACK, CAMERA_HEIGHT = CAMERA_DISTANCE * COS, CAMERA_DISTANCE * SIN
   FOCAL = CAMERA_DISTANCE * TILE_PIXELS * zoom / TILE
   camera.centerX, camera.centerY, camera.x, camera.y = sx, sy, 0, CAMERA_BACK
   local half = TILE / 2
   local ax, ay = Project(-half, -half, 0)
   local bx, by = Project(half, -half, 0)
   local cx, cy = Project(half, half, 0)
   local dx, dy = Project(-half, half, 0)
   if ax and bx and cx and dx then Quad(layer, floorColor, ax, ay, bx, by, cx, cy, dx, dy) end
   Shadow(layer, 0, 0, TILE * 0.42)
   local mx, my, scale = Project(0, 0, 0)
   local width = (look == "player" and TILE * 1.1 or TILE * 0.9) * scale
   Model(layer, look, mx, my + TILE * (look == "player" and 0.1 or 0.05) * scale, width, facing or FACING)
end

----------------------------------------------------------------
-- Drawing
----------------------------------------------------------------

function map3d:Create(view)
   self.view = view
   -- the mouse wheel zooms (shift: tilts the camera), or sizes the tiles of the flat view
   view:EnableMouseWheel(true)
   view:SetScript("OnMouseWheel", function(_, delta)
      local profile = ns.mod.db.profile
      if not ns.map:Is3D() then
         profile.tileSize = max(24, min(48, (profile.tileSize or 32) + delta * 4))
         ns.map:Layout()
      elseif IsShiftKeyDown() then
         profile.cameraAngle = max(30, min(80, (profile.cameraAngle or 55) + delta * 5))
         ns.ui:RefreshNow("map")
      else
         profile.zoom3d = max(0.5, min(1.5, floor(((profile.zoom3d or 1) + delta * 0.1) * 20 + 0.5) / 20))
         ns.ui:RefreshNow("map")
      end
   end)
   self.layers = {}
   self.sharedLayer = { models = {} }  -- (the pool of the models of all the rows)
   -- the effects of spells go above everything, models too (a model is a frame of its own, and
   -- what is drawn in a layer is under it)
   self.effects = NewLayer(view, view:GetFrameLevel() + 1000)
   self:Hide()
end

-- The layers of the rows there are to draw.
function map3d:EnsureLayers(rows)
   local view = self.view
   local base = view:GetFrameLevel() + 1
   for row = #self.layers + 1, rows do
      self.layers[row] = {
         [FLOOR] = NewLayer(view, base + (row - 1) * 3 + FLOOR),
         [WALL] = NewLayer(view, base + (row - 1) * 3 + WALL),
         [ACTOR] = NewLayer(view, base + (row - 1) * 3 + ACTOR),
      }
      local actor = self.layers[row][ACTOR]
      actor.models, actor.shared = self.sharedLayer.models, true
      end
end

-- Zoomed out, more tiles fit in the view.
function map3d:SetReach(zoom)
   local more = max(1, FULL_ZOOM / zoom)
   NEAR_ROWS, FAR_ROWS, SIDE_COLUMNS = ceil(4 * more), ceil(13 * more), ceil(14 * more)
   ROWS = NEAR_ROWS + FAR_ROWS + 1
   self:EnsureLayers(ROWS)
end

-- Effects: BeginEffects(level), Effect() for each, EndEffects().  (sx, sy) is the middle of the
-- tile in the view, size how many pixels wide.
function map3d:BeginEffects(level)
   local layer = self.effects
   layer:SetFrameLevel(level)
   layer:Show()
   Begin(layer)
end

function map3d:Effect(sx, sy, size, glyph, color)
   local layer = self.effects
   local half = size * 0.65
   Quad(layer, { color[1], color[2], color[3], 0.5 }, sx - half, sy - half, sx + half, sy - half, sx + half, sy + half, sx - half, sy + half,
      "Interface\\AddOns\\WoWLarn\\Media\\Shadow")
   Glyph(layer, glyph, color, sx, sy + size * 0.4, size)
end

function map3d:EndEffects()
   Finish(self.effects)
end

function map3d:Hide()
   for _, layers in ipairs(self.layers or {}) do
      for _, layer in pairs(layers) do layer:Hide() end
   end
   if self.effects then self.effects:Hide() end
   -- (the models hang on the view, not on the layers: the town is drawn flat, with its own models)
   if self.sharedLayer then
      for _, frame in ipairs(self.sharedLayer.models) do frame:Hide() end
   end
   for _, ghost in pairs(self.ghosts) do
      if ghost.frame then ghost.frame:Hide() end
   end
   self.shown = false
end

-- Forgets what the models were doing, for a new game.
function map3d:Reset()
   self.anims, self.ghosts, self.moves, self.playerAnim = {}, {}, {}, nil
   self:Hide()
end

local function IsWall(x, y)
   return x >= 1 and x <= MAXX and y >= 1 and y <= MAXY and ns.Display.remembered(x, y) and G.item[x][y] == K.OWALL
end

-- A wall that is drawn as a block: not one of those that are lava in the volcano (which are
-- flat, and walls only for the game).
local function IsBlock(x, y)
   return IsWall(x, y) and not V.WallVariant(G.level, x, y)
end

local TINT_WHITE = { 1, 1, 1 }
local TINT = { 1, 1, 1 }  -- what the textures of this level are tinted by, set when drawing

-- The part of the tile of a wall block that the block fills: a block is thinner than its tile on
-- the sides that face open floor, see DrawTile.  West, east, north and south edges, in world units.
local function Extent(x, y)
   return (x - 1) * TILE + (IsBlock(x - 1, y) and 0 or WALL_INSET), x * TILE - (IsBlock(x + 1, y) and 0 or WALL_INSET),
      (y - 1) * TILE + (IsBlock(x, y - 1) and 0 or WALL_INSET), y * TILE - (IsBlock(x, y + 1) and 0 or WALL_INSET)
end

-- An upright strip of a wall from the ground point (ax, ay) to (bx, by), height h, the part
-- from..to of the tile along it (0 to 1) of the texture.  For the faces of a block that a
-- neighbouring block is set back from: they are not drawn whole, as the neighbour hides them
-- where it is as wide as the tile.
local function FaceStrip(layer, color, ahead, factor, alpha, texture, uv, ax, ay, bx, by, h, from, to)
   local gax, gay = Project(ax, ay, 0)
   local gbx, gby = Project(bx, by, 0)
   local tax, tay = Project(ax, ay, h)
   local tbx, tby = Project(bx, by, h)
   if not (gax and gbx and tax and tbx) then return end
   if uv then uv = { uv[1] + (uv[2] - uv[1]) * from, uv[1] + (uv[2] - uv[1]) * to, uv[3], uv[4] } end
   surface = "wall strip"
   Quad(layer, Shade(color, ahead, factor, alpha), tax, tay, tbx, tby, gbx, gby, gax, gay, texture, uv)
end

-- A flat object (V.FLAT) laid on the floor of its tile, in the perspective of the floor.
local function DrawFlat(layers, x, y, object)
   local flat = V.FLAT[object]
   local cx, cy, half = (x - 0.5) * TILE, (y - 0.5) * TILE, flat.size * TILE / 2
   local ax, ay = Project(cx - half, cy - half, 0)
   local bx, by = Project(cx + half, cy - half, 0)
   local dx, dy = Project(cx + half, cy + half, 0)
   local ex, ey = Project(cx - half, cy + half, 0)
   if not (ax and bx and dx and ex) then return end
   surface = "picture"
   Quad(layers[FLOOR], WHITE, ax, ay, bx, by, dx, dy, ex, ey, V.ObjectIcon(object), flat.box, 2)
end

-- A door, built like the walls from quads: the leaves (the picture of the door) stand in the middle of
-- the opening between the two wall blocks beside it, and over them a lintel closes the opening up to
-- the wall height (its face towards the camera and its top, of the wall texture).  The sides of the
-- opening are the faces of the wall blocks.  It runs across the tile (east to west) or, in a wall that
-- runs north to south, along it, and keeps the way it faces (G.doorway) when the walls are gone.
local LEAF_HEIGHT = WALL_HEIGHT * 0.8  -- the opening, under the lintel
local DOOR_WIDTH = WALL_HEIGHT * 0.8  -- of the opening that holds the leaves: as wide as high (the leaves picture is a square); the rest of the 88 of the wall's opening is stone beside the door
local LINTEL_THICK = 0.5  -- of the thickness of the wall
local function DrawDoor(layers, x, y, ahead, object)
   if G.doorway[x][y] == 0 then  -- (worked out from the walls once: they can be blasted away)
      local sides = IsBlock(x, y - 1) and IsBlock(x, y + 1) and not (IsBlock(x - 1, y) and IsBlock(x + 1, y))
      G.doorway[x][y] = sides and 2 or 1
   end
   local sideways = G.doorway[x][y] == 2
   local x0, y0 = (x - 1) * TILE, (y - 1) * TILE
   -- a is along the wall: the opening, between the faces of the blocks beside it; c across it: the thickness of the wall
   local a0, a1 = (sideways and y0 or x0) - WALL_INSET, (sideways and y0 or x0) + TILE + WALL_INSET
   local cm = (sideways and x0 or y0) + TILE / 2
   local wall = TILE / 2 - WALL_INSET  -- half the thickness of the wall
   local th = wall * LINTEL_THICK  -- (the lintel is thinner)
   local e0, e1 = a0, a1  -- the whole opening of the wall
   local gap = a1 - a0
   local p0, p1 = a0 + (gap - DOOR_WIDTH) / 2, a1 - (gap - DOOR_WIDTH) / 2  -- the opening for the leaves
   a0, a1 = p0, p1
   local function Point(a, c, z)
      if sideways then return Project(c, a, z) end
      return Project(a, c, z)
   end
   -- the face towards the camera: south, or east or west
   local near = (sideways and camera.x < cm) and cm - th or cm + th
   local far = near == cm + th and cm - th or cm + th
   -- a quad from four corners, each { a, c, z }, in order round it from the top left
   local function Piece(kind, color, texture, uv, level, p1, p2, p3, p4)
      local ax, ay = Point(p1[1], p1[2], p1[3])
      local bx, by = Point(p2[1], p2[2], p2[3])
      local cx, cy = Point(p3[1], p3[2], p3[3])
      local dx, dy = Point(p4[1], p4[2], p4[3])
      if ax and bx and cx and dx then
         surface = kind
         Quad(layers[WALL], color, ax, ay, bx, by, cx, cy, dx, dy, texture, uv, level)
      end
   end
   local alpha = (SIN < STEEP and y > G.playery and math.abs(x - G.playerx) <= 1) and SEE_THROUGH or 1
   local picture = V.DoorPicture(object, G.level, x, y, true)
   local color = Shade(TINT_WHITE, ahead, sideways and 0.7 or 0.9, alpha)
   -- the leaves, edge to edge (an open door: they are swung back against the sides, and between them it is clear)
   Piece("door leaf", color, picture, nil, 2, { a0, cm, LEAF_HEIGHT }, { a1, cm, LEAF_HEIGHT }, { a1, cm, 0 }, { a0, cm, 0 })
   -- the rest, back to front by sublevel (the order of quads within one sublevel is not fixed): the part of
   -- the sides of the opening behind the lintel (2 leaves, 3 this), the lintel (4 its top, 5 its face), the part of
   -- the sides in front of its face (6) and the stone beside it (7)
   local wallTexture, wallUV = V.Texture(G.level, "wall", x, y)
   local wallColor = wallTexture and TINT or V.WALL
   Piece("lintel face", Shade(wallColor, ahead, sideways and 0.55 or 0.72, alpha), wallTexture, wallUV, 5,
      { a0, near, WALL_HEIGHT }, { a1, near, WALL_HEIGHT }, { a1, near, LEAF_HEIGHT }, { a0, near, LEAF_HEIGHT })
   Piece("lintel top", Shade(wallColor, ahead, 1, alpha), wallTexture, wallUV, 4,
      { a0, far, WALL_HEIGHT }, { a1, far, WALL_HEIGHT }, { a1, near, WALL_HEIGHT }, { a0, near, WALL_HEIGHT })
   -- the stone between the opening and the wall blocks: as thick as the wall and as high
   local front = (near == cm + th) and cm + wall or cm - wall
   local back = (front == cm + wall) and cm - wall or cm + wall
   -- the sides of the narrowed opening, from the front of the stone to the leaves: the one the camera sees
   local along = sideways and camera.y or camera.x  -- the camera along the wall, and across it
   local across = sideways and camera.x or camera.y
   local jambColor = Shade(wallColor, ahead, sideways and 0.72 or 0.55, alpha)
   -- Which jamb the camera sees: the one at the far end.  Seen mostly from across the wall (a door in a
   -- wall that runs east to west, seen from the south) it is at the side: the part in front of the face
   -- of the lintel is in front of it, the part behind is behind it.  Seen mostly along the wall (the far end
   -- of a door in a wall that runs north to south) the whole of it is behind the lintel and the leaves.
   local fromAcross = math.abs(across - cm) > math.abs(along - (a0 + a1) / 2)
   for _, edge in ipairs({ a0, a1 }) do
      if (edge == a0 and along > a0) or (edge == a1 and along < a1) then
         if fromAcross then
            Piece("door jamb", jambColor, wallTexture, wallUV, 3,
               { edge, near, LEAF_HEIGHT }, { edge, cm, LEAF_HEIGHT }, { edge, cm, 0 }, { edge, near, 0 })
            Piece("door jamb", jambColor, wallTexture, wallUV, 6,
               { edge, front, WALL_HEIGHT }, { edge, near, WALL_HEIGHT }, { edge, near, 0 }, { edge, front, 0 })
         else
            Piece("door jamb", jambColor, wallTexture, wallUV, 1,
               { edge, front, WALL_HEIGHT }, { edge, cm, WALL_HEIGHT }, { edge, cm, 0 }, { edge, front, 0 })
         end
      end
   end
   for _, side in ipairs({ { e0, a0 }, { a1, e1 } }) do
      local from, to = side[1], side[2]
      Piece("pillar face", Shade(wallColor, ahead, sideways and 0.55 or 0.72, alpha), wallTexture, wallUV, 7,
         { from, front, WALL_HEIGHT }, { to, front, WALL_HEIGHT }, { to, front, 0 }, { from, front, 0 })
      Piece("pillar top", Shade(wallColor, ahead, 1, alpha), wallTexture, wallUV, 7,
         { from, back, WALL_HEIGHT }, { to, back, WALL_HEIGHT }, { to, front, WALL_HEIGHT }, { from, front, WALL_HEIGHT })
   end
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
      if V.WallVariant(G.level, x, y) then  -- lava: flat, and bright whatever the distance
         local tex, uv = V.Texture(G.level, "lava", x, y)
         if tex then
            surface = "lava"
            Quad(layers[FLOOR], Shade({ 1, 0.9, 0.8 }, ahead * 0.4, 1), ax, ay, bx, by, cx, cy, dx, dy, tex, uv)
         else
            surface = "lava"
            Quad(layers[FLOOR], Shade(V.GROUND.lava, ahead * 0.4, 1.4), ax, ay, bx, by, cx, cy, dx, dy)
         end
         return
      end
      local color = V.WALL
      local wh = WALL_HEIGHT
      -- a wall between the camera and the player lets the player show through, unless the
      -- camera is steep enough to look over it
      local alpha = (SIN < STEEP and y > G.playery and math.abs(x - G.playerx) <= 1) and SEE_THROUGH or 1
      -- textured, unless it lets the player show through (opaque textures ignore the alpha)
      local wallTexture, wallUV
      if alpha == 1 then wallTexture, wallUV = V.Texture(G.level, "wall", x, y) end
      if wallTexture then color = TINT end
      -- a wall is thinner than its tile on the sides that face open floor, so what stands
      -- next to it does not overlap it
      local west = IsBlock(x - 1, y) and 0 or WALL_INSET
      local east = IsBlock(x + 1, y) and 0 or WALL_INSET
      local north = IsBlock(x, y - 1) and 0 or WALL_INSET
      local south = IsBlock(x, y + 1) and 0 or WALL_INSET
      local wx0, wx1, wy0, wy1 = x0 + west, x1 - east, y0 + north, y1 - south
      if west + east + north + south > 0 then  -- the ground around it
         local floorTexture, floorUV = V.Texture(G.level, "floor", x, y)
         if floorTexture then
            surface = "floor"
            Quad(layers[FLOOR], Shade(TINT, ahead, 0.5), ax, ay, bx, by, cx, cy, dx, dy, floorTexture, floorUV)
         else
            surface = "floor"
            Quad(layers[FLOOR], Shade(ground, ahead, 0.5), ax, ay, bx, by, cx, cy, dx, dy)
         end
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
         surface = "wall top"
         Quad(layers[WALL], Shade(color, ahead, 1, alpha), tx0, ty0, tx1, ty1, tx2, ty2, tx3, ty3, wallTexture, wallUV)
         if not IsBlock(x, y + 1) then  -- the face towards the camera
            surface = "wall front"
            Quad(layers[WALL], Shade(color, ahead, 0.72, alpha), tx3, ty3, tx2, ty2, fcx, fcy, fdx, fdy, wallTexture, wallUV)
         end
         if camera.x > wx1 and not IsBlock(x + 1, y) then  -- the east face
            surface = "wall side"
            Quad(layers[WALL], Shade(color, ahead, 0.55, alpha), tx1, ty1, tx2, ty2, fcx, fcy, fbx, fby, wallTexture, wallUV)
         elseif camera.x < wx0 and not IsBlock(x - 1, y) then  -- the west face
            surface = "wall side"
            Quad(layers[WALL], Shade(color, ahead, 0.55, alpha), tx0, ty0, tx3, ty3, fdx, fdy, fax, fay, wallTexture, wallUV)
         end
         -- Where a neighbouring block is set back from the tile (it has open floor on that side),
         -- the face of this block that it would hide is bare for the width of the set-back:
         -- at the corners of the walls.
         local layer = layers[WALL]
         if IsBlock(x, y + 1) then
            local sx0, sx1 = Extent(x, y + 1)
            if sx0 > wx0 then
               local to = min(sx0, wx1)
               FaceStrip(layer, color, ahead, 0.72, alpha, wallTexture, wallUV, wx0, wy1, to, wy1, wh, (wx0 - x0) / TILE, (to - x0) / TILE)
            end
            if sx1 < wx1 then
               local from = max(sx1, wx0)
               FaceStrip(layer, color, ahead, 0.72, alpha, wallTexture, wallUV, from, wy1, wx1, wy1, wh, (from - x0) / TILE, (wx1 - x0) / TILE)
            end
         end
         local side, edge
         if camera.x > wx1 and IsBlock(x + 1, y) then side, edge = x + 1, wx1
         elseif camera.x < wx0 and IsBlock(x - 1, y) then side, edge = x - 1, wx0 end
         if side then
            local _, _, ny0, ny1 = Extent(side, y)
            if ny0 > wy0 then
               local to = min(ny0, wy1)
               FaceStrip(layer, color, ahead, 0.55, alpha, wallTexture, wallUV, edge, wy0, edge, to, wh, (wy0 - y0) / TILE, (to - y0) / TILE)
            end
            if ny1 < wy1 then
               local from = max(ny1, wy0)
               FaceStrip(layer, color, ahead, 0.55, alpha, wallTexture, wallUV, edge, from, edge, wy1, wh, (from - y0) / TILE, (wy1 - y0) / TILE)
            end
         end
      end
      return
   end

   local checker = ((x + y) % 2 == 0) and 1 or 0.93
   local floorTexture, floorUV = V.Texture(G.level, "floor", x, y)
   if floorTexture then
      surface = "floor"
      Quad(layers[FLOOR], Shade(TINT, ahead, checker), ax, ay, bx, by, cx, cy, dx, dy, floorTexture, floorUV)
   else
      surface = "floor"
      Quad(layers[FLOOR], Shade(ground, ahead, checker), ax, ay, bx, by, cx, cy, dx, dy)
   end

   -- a door is part of the wall: it shows wherever the wall does
   local door = G.item[x][y]
   if V.IsDoor(door) and not ns.mod.db.profile.ascii and ns.Display.remembered(x, y) then
      DrawDoor(layers, x, y, ahead, door)
   end

   if G.know[x][y] == 0 and not (x == G.playerx and y == G.playery) then return end  -- (not in sight)

   -- what stands on the floor, in the middle of the tile
   local mx, my, scale = Project((x - 0.5) * TILE, (y - 0.5) * TILE, 0)
   if not mx then return end
   local monster = ns.Display.visibleMonster(x, y)
   local object = G.item[x][y]
   local models = ns.mod.db.profile.models ~= false and not ns.mod.db.profile.ascii
   if V.IsDoor(object) and not ns.mod.db.profile.ascii then object = 0 end  -- (drawn above)
   if V.FLAT[object] and not ns.mod.db.profile.ascii and G.know[x][y] ~= 0 then
      DrawFlat(layers, x, y, object)
      object = 0
   end
   local ghost = map3d.ghosts[x * 100 + y]
   if ghost and monster == 0 and ghost.expires > GetTime() and ghost.level == G.level and models then  -- (the corpse stays under the player)
      Shadow(layers[ACTOR], (x - 0.5) * TILE, (y - 0.5) * TILE, TILE * 0.42)
      Model(layers[ACTOR], ghost.display, mx, my + TILE * 0.05 * scale, TILE * 0.9 * scale, ghost.facing, ANIM.death, ghost)
   else
      ghost = nil
   end
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
         -- monsters face the player they are after, and the way they go while they walk
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
               toward = DIRECTION[Sign(x - move.fromX)][Sign(y - move.fromY)] or toward  -- (walks forwards)
               local sx, sy, sscale = Project(wx, wy, 0)
               if sx then mx, my, scale = sx, sy, sscale end
            end
         end
         if object ~= 0 then  -- (what lies under the monster stays, a little smaller)
            local under, picture
            if not ns.mod.db.profile.ascii then under, picture = V.ObjectPicture(object, G.iarg[x][y], G.named[x][y] == object, ns.mod.db.profile.cameraAngle or 55) end
            if under then
               if picture then
                  PictureQuad(layers[ACTOR], under, x, y, (V.STANDING[object] or 0.75) * 2 / 3, ahead, V.STANDING[object], V.Anchor(object, ns.mod.db.profile.cameraAngle or 55))
               else
                  local size = TILE * 0.5 * scale
                  Icon(layers[ACTOR], under, mx, my + size * 0.1, size, size)
               end
            end
         end
         Shadow(layers[ACTOR], wx, wy, TILE * 0.42)
         Model(layers[ACTOR], display, mx, my + TILE * 0.05 * scale, TILE * 0.9 * scale, Facing(toward), anim)
      else
         Glyph(layers[ACTOR], V.MonsterGlyph(monster), V.MONSTER_COLOR, mx, my + TILE * 0.1 * scale, TILE * 0.9 * scale)
      end
   elseif ghost then
      -- (drawn above)
   elseif object ~= 0 then
      local icon, picture
      if not ns.mod.db.profile.ascii then icon, picture = V.ObjectPicture(object, G.iarg[x][y], G.named[x][y] == object, ns.mod.db.profile.cameraAngle or 55) end
      local size = TILE * 0.6 * scale
      if icon and picture then
         PictureQuad(layers[ACTOR], icon, x, y, V.STANDING[object] or 0.75, ahead, V.STANDING[object], V.Anchor(object, ns.mod.db.profile.cameraAngle or 55))
      elseif icon then
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
   return Facing(G.facing), (G.c[K.HP] <= 0 and ANIM.death) or entry and entry.expires > GetTime() and entry.anim or nil
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
      duration = 5
      local look = G.look[x][y]
      local display = look ~= 0 and monster and V.MonsterDisplay(monster, look)
      if display then
         self.ghosts[key] = { display = display, expires = now + duration, level = G.level,
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
      local interval = (map3d.t0 or map3d.tweening) and 0.03 or 0.06  -- (a bob needs fewer frames than a step)
      if since < interval then return end
      since = 0
      Redraw()
      if not map3d.t0 and not map3d.tweening and not map3d.bobbing then driver:SetScript("OnUpdate", nil) end
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

-- Rows are stacked far to near, by how far they are from the spot on the floor under the
-- camera: the tops of walls lean away from that spot, so past it (a steep camera) the rows
-- farthest down the view are the farthest away and go at the back.
function map3d:StackRows(roundY)
   local order = self.order or {}
   self.order = order
   for row = 1, ROWS do
      order[row] = row
      local y = roundY - FAR_ROWS + (row - 1)
      self.distance = self.distance or {}
      self.distance[row] = math.abs((y - 0.5) * TILE - camera.y)
   end
   local distance = self.distance
   table.sort(order, function(a, b)
      if distance[a] ~= distance[b] then return distance[a] > distance[b] end
      return a < b
   end)
   -- (all the floors at the back: a floor is flat on the ground, so nothing standing on the
   -- floor of another row is ever behind it; the walls and what stands on the floor, by row)
   local base = self.view:GetFrameLevel() + 1
   for rank, row in ipairs(order) do
      for kind, layer in pairs(self.layers[row]) do
         local level
         if kind == FLOOR then
            level = base + (rank - 1)
         else
            -- (the models of a row are a level above its walls; and they go by the row, not the rank: a
            -- creature that stands further down the view is nearer to the viewer and hides one behind it,
            -- also past the spot under the camera, where the walls are stacked the other way round)
            level = base + ROWS + ((kind == ACTOR and row or rank) - 1) * 3 + (kind == ACTOR and 1 or 0)
         end
         if layer:GetFrameLevel() ~= level then layer:SetFrameLevel(level) end
      end
   end
end

-- /larn mapdebug: the model frames that are shown, and the levels they are drawn at (higher is in front).
function map3d:DebugModels()
   print(format("models: player at %d,%d, %d rows (%d far), player row %d", G.playerx, G.playery, ROWS, FAR_ROWS, FAR_ROWS + 1))
   for _, frame in ipairs(self.sharedLayer.models) do
      if frame:IsShown() then
         print(format("  look %s level %s (frame %d, model %d) centre y %s", tostring(frame.look), tostring(frame.level),
            frame:GetFrameLevel(), frame.model:GetFrameLevel(), tostring(frame:GetCenter() and select(2, frame:GetCenter()))))
         local m = frame.model
         local cx, cy, cz = m:GetCameraPosition()
         local tx, ty, tz = m:GetCameraTarget()
         local cam = m.cam
         print(format("     frame %.0fx%.0f scale %s  camera now %.2f %.2f %.2f target %.2f %.2f %.2f  kept %s", frame:GetWidth(), frame:GetHeight(),
            tostring(frame.scale), cx or 0, cy or 0, cz or 0, tx or 0, ty or 0, tz or 0,
            cam and format("%.2f %.2f %.2f target %.2f %.2f %.2f scale %s", cam[1], cam[2], cam[3], cam[4], cam[5], cam[6], tostring(cam[7])) or "no"))
      end
   end
   for row = FAR_ROWS, FAR_ROWS + 3 do
      local layers = self.layers[row]
      if layers then print(format("  row %d: walls %d actors %d", row, layers[WALL]:GetFrameLevel(), layers[ACTOR]:GetFrameLevel())) end
   end
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
   FOCAL = CAMERA_DISTANCE * TILE_PIXELS * (ns.mod.db.profile.zoom3d or 1) / TILE
   camera.centerX = width / 2
   camera.centerY = height * PLAYER_AT
   self.tweening, self.bobbing = false, false
   self.drawn = (self.drawn or 0) + 1
   local posX, posY, walking = self:Position()
   camera.x = (posX - 0.5) * TILE
   camera.y = (posY - 0.5) * TILE + CAMERA_BACK
   local roundX, roundY = floor(posX + 0.5), floor(posY + 0.5)
   local ground = V.Ground(G.level)
   TINT = V.Tint(G.level)
   self:SetReach(ns.mod.db.profile.zoom3d or 1)
   self:StackRows(roundY)

   BeginModels(self.sharedLayer)
   for row = 1, #self.layers do
      for _, layer in pairs(self.layers[row]) do
         layer:SetShown(row <= ROWS)
         if row <= ROWS then Begin(layer) end
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
   -- what spells do on the way: a glow and a glyph, above the models
   self:BeginEffects(view:GetFrameLevel() + 1 + ROWS * 4 + 8)  -- (above the floors, then the walls and models of every row)
   for _, effect in ipairs(ns.map.overlays or {}) do
      local mx, my, scale = Project((effect.x - 0.5) * TILE, (effect.y - 0.5) * TILE, TILE * 0.35)
      if mx and effect.x >= 1 and effect.x <= MAXX and effect.y >= 1 and effect.y <= MAXY then
         self:Effect(mx, my, TILE * 1.1 * scale, effect.glyph, effect.color or V.MISSILE_COLOR)
      end
   end
   self:EndEffects()
   -- the player, in the row of the nearest tile
   do
      local layer = self.layers[FAR_ROWS + 1][ACTOR]
      local mx, my, scale = Project((posX - 0.5) * TILE, (posY - 0.5) * TILE, 0)
      if mx then
         local size = TILE * 0.9 * scale
         local models = ns.mod.db.profile.models ~= false and not ns.mod.db.profile.ascii
         if models then
            local entry = self.playerAnim
            local anim = (G.c[K.HP] <= 0 and ANIM.death) or entry and entry.expires > GetTime() and entry.anim or (walking and ANIM.walk or ANIM.stand)
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
            local look = ns.Create.gameLook()
            map3d.playerLook = look
            Model(layer, look or "player", mx, my + size * 0.1, size * 1.1, Facing(G.facing), anim)
         elseif ns.mod.db.profile.ascii then  -- the original @
            Glyph(layer, "@", V.PLAYER_COLOR, mx, my + size * 0.1, size)
         else
            Icon(layer, V.ClassIcon(G.class), mx, my + size * 0.15, size, size)
         end
      end
   end
   if self.t0 or self.tweening or self.bobbing then self:EnsureDriver() end
   for key, ghost in pairs(self.ghosts) do  -- (hiding a model restarts it: only those not drawn)
      if ghost.drawn ~= self.drawn then
         if ghost.frame then ghost.frame:Hide() end
         if ghost.expires <= GetTime() or ghost.level ~= G.level then self.ghosts[key] = nil end  -- (a corpse stays on its level)
      end
   end
   for row = 1, ROWS do
      for _, layer in pairs(self.layers[row]) do Finish(layer) end
   end
   EndModels(self.sharedLayer)
end
