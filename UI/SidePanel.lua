--[[
**********************************************************************
WoWLarn - Side panel: minimap, portraits, stats and effects.
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
local L = LibStub("AceLocale-3.0"):GetLocale("WoWLarn")
local _, ns = ...
local K = ns.K
local G = ns.G
local V = ns.Visuals

local side = {}
ns.side = side

local GAP = 4
local CELL = 3  -- minimap pixels per tile
local EFFECT_SIZE, EFFECT_COLUMNS = 24, 8
local STAT_W, STAT_H = 68, 15
local MINIMAP_H, PORTRAIT_H, STATS_H = K.MAXY * CELL + 22, 112, 196

local function Section(parent, height, title)
   local panel = ns.CreatePanel(parent)
   panel:SetHeight(height)
   local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   label:SetPoint("TOPLEFT", 4, -3)
   label:SetText(title)
   return panel
end

local function Fill(texture, r, g, b, a)
   if texture.SetColorTexture then
      texture:SetColorTexture(r, g, b, a)
   else
      texture:SetTexture(r, g, b, a)
   end
end

-- A status bar with a label drawn on top of it.
local function Bar(parent, r, g, b)
   local bar = CreateFrame("StatusBar", nil, parent)
   bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
   bar:SetStatusBarColor(r, g, b)
   bar:SetHeight(14)
   bar:SetMinMaxValues(0, 1)
   bar:SetValue(0)
   local background = bar:CreateTexture(nil, "BACKGROUND")
   background:SetAllPoints()
   Fill(background, 0, 0, 0, 0.6)
   bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   bar.text:SetPoint("CENTER")
   return bar
end

-- What is shown under the bars, and what each thing does (from the way the game uses it).
local function C(index) return G.c[index] end
local function Strength() return C(K.STRENGTH) + C(K.STREXTRA) end
local function Number(label, value) return format("%s %d", label, value) end
local STAT_CELLS = {
   { text = function() return Number(L["STR"], Strength()) end, title = function() return L["Strength"] end,
     tip = L["Strength adds to the damage of every hit you make, together with your weapon class."] },
   { text = function() return Number(L["INT"], C(K.INTELLIGENCE)) end, title = function() return L["Intelligence"] end,
     tip = L["Intelligence makes spells work: a spell can fail unless a roll of 1 to 18 is at most your intelligence."] },
   { text = function() return Number(L["WIS"], C(K.WISDOM)) end, title = function() return L["Wisdom"] end,
     tip = L["Wisdom decides whether the strongest spells, like phantasmal forces and finger of death, take hold."] },
   { text = function() return Number(L["CON"], C(K.CONSTITUTION)) end, title = function() return L["Constitution"] end,
     tip = L["Constitution decides how many hit points you gain with each level."] },
   { text = function() return Number(L["DEX"], C(K.DEXTERITY)) end, title = function() return L["Dexterity"] end,
     tip = L["Dexterity helps you hit monsters, and keeps you out of pits and trap doors."] },
   { text = function() return Number(L["CHA"], C(K.CHARISMA)) end, title = function() return L["Charisma"] end,
     tip = L["Charisma can awe a monster so that it does not attack, and makes the charm monster spell last longer."] },
   { text = function() return Number(L["AC"], C(K.AC)) end, title = function() return L["Armor class"] end,
     tip = L["The higher your armor class, the less damage monsters do to you, and the more often they miss."],
     extra = function() return table.concat(ns.Equipment.summary(), "\n", 1, 1) end },
   { text = function() return Number(L["WC"], C(K.WCLASS)) end, title = function() return L["Weapon class"] end,
     tip = L["Your weapon class adds to your chance to hit and to the damage you do."],
     extra = function() return table.concat(ns.Equipment.summary(), "\n", 2, 2) end },
   { text = function() return Number(L["Level"], C(K.LEVEL)) end, title = function() return L["Level"] end,
     tip = L["Your level goes up with experience.  Each level gives hit points and spell points, and opens a pack slot every second level."] },
   { text = function() return Number(L["Gold"], C(K.GOLD)) end, title = function() return L["Gold"] end,
     tip = L["Gold buys things in the town.  The bank keeps it safe, and what you have when the game ends is your score."],
     extra = function() return format(L["In the bank: %d"], C(K.BANKACCOUNT)) end },
   { wide = true, text = function() return format(L["%d mobuls left"], math.floor((K.TIMELIMIT - G.gtime) / 100)) end,
     title = function() return L["Time left"] end,
     tip = L["Your daughter's illness will not wait.  Bring the potion of cure dianthroritis home before the time runs out."] },
}

function side:Create(parent)
   local frame = CreateFrame("Frame", nil, parent)

   local minimap = Section(frame, MINIMAP_H, L["Map"])
   minimap:SetPoint("TOPLEFT")
   minimap:SetPoint("TOPRIGHT")
   self.depth = minimap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   self.depth:SetPoint("TOPRIGHT", -4, -3)
   -- One small texture per tile, drawn from the known part of the level.
   self.tiles = {}
   local holder = CreateFrame("Frame", nil, minimap)
   holder:SetSize(K.MAXX * CELL, K.MAXY * CELL)
   holder:SetPoint("BOTTOM", 0, 4)
   for x = 1, K.MAXX do
      self.tiles[x] = {}
      for y = 1, K.MAXY do
         local tile = holder:CreateTexture(nil, "ARTWORK")
         tile:SetSize(CELL, CELL)
         tile:SetPoint("TOPLEFT", (x - 1) * CELL, -(y - 1) * CELL)
         self.tiles[x][y] = tile
      end
   end
   self.minimapKey = {}

   local portraits = Section(frame, PORTRAIT_H, L["Portraits"])
   portraits:SetPoint("TOPLEFT", minimap, "BOTTOMLEFT", 0, -GAP)
   portraits:SetPoint("TOPRIGHT", minimap, "BOTTOMRIGHT", 0, -GAP)
   local player = CreateFrame("PlayerModel", nil, portraits)
   player:SetPoint("TOPLEFT", 4, -16)
   player:SetPoint("BOTTOMRIGHT", portraits, "BOTTOM", -2, 4)
   pcall(player.SetUnit, player, "player")
   pcall(player.SetPortraitZoom, player, 0.8)
   self.player = player
   self.target = CreateFrame("PlayerModel", nil, portraits)
   self.target:SetPoint("TOPLEFT", portraits, "TOP", 2, -16)
   self.target:SetPoint("BOTTOMRIGHT", -4, 4)

   local stats = Section(frame, STATS_H, L["Stats"])
   stats:SetPoint("TOPLEFT", portraits, "BOTTOMLEFT", 0, -GAP)
   stats:SetPoint("TOPRIGHT", portraits, "BOTTOMRIGHT", 0, -GAP)
   self.title = stats:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   self.title:SetPoint("TOPLEFT", 6, -16)
   self.title:SetPoint("RIGHT", -6, 0)
   self.title:SetJustifyH("LEFT")
   self.hp = Bar(stats, 0.75, 0.15, 0.15)
   self.hp:SetPoint("TOPLEFT", 6, -34)
   self.hp:SetPoint("TOPRIGHT", -6, -34)
   self.spells = Bar(stats, 0.2, 0.35, 0.85)
   self.spells:SetPoint("TOPLEFT", self.hp, "BOTTOMLEFT", 0, -3)
   self.spells:SetPoint("TOPRIGHT", self.hp, "BOTTOMRIGHT", 0, -3)
   self.exp = Bar(stats, 0.75, 0.6, 0.1)
   self.exp:SetPoint("TOPLEFT", self.spells, "BOTTOMLEFT", 0, -3)
   self.exp:SetPoint("TOPRIGHT", self.spells, "BOTTOMRIGHT", 0, -3)
   -- the numbers under the bars: a cell for each, so each can explain itself
   self.cells = {}
   for index, cell in ipairs(STAT_CELLS) do
      local frame = CreateFrame("Frame", nil, stats)
      local column, row = (index - 1) % 3, math.floor((index - 1) / 3)
      frame:SetSize(cell.wide and STAT_W * 2 or STAT_W, STAT_H)
      frame:SetPoint("TOPLEFT", self.exp, "BOTTOMLEFT", column * STAT_W, -6 - row * STAT_H)
      frame:EnableMouse(true)
      frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      frame.text:SetPoint("LEFT")
      frame.text:SetJustifyH("LEFT")
      frame.cell = cell
      frame:SetScript("OnEnter", function(self)
         GameTooltip:SetOwner(self, "ANCHOR_LEFT")
         GameTooltip:SetText(self.cell.title(), 1, 1, 1)
         GameTooltip:AddLine(self.cell.tip, nil, nil, nil, true)
         if self.cell.extra then
            local extra = self.cell.extra()
            if extra then GameTooltip:AddLine(extra, 0.6, 0.9, 0.6, true) end
         end
         GameTooltip:Show()
      end)
      frame:SetScript("OnLeave", GameTooltip_Hide)
      self.cells[index] = frame
   end

   local effects = Section(frame, 40, L["Effects"])
   effects:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -GAP)
   effects:SetPoint("BOTTOMRIGHT")
   -- One icon per effect in V.EFFECTS, shown while its counter is running.
   self.effectIcons = {}
   for index, effect in ipairs(V.EFFECTS) do
      local button = CreateFrame("Frame", nil, effects)
      button:SetSize(EFFECT_SIZE, EFFECT_SIZE)
      button.texture = button:CreateTexture(nil, "ARTWORK")
      button.texture:SetAllPoints()
      button.texture:SetTexture("Interface\\Icons\\" .. effect[3])
      button.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      button.effect = effect
      button:EnableMouse(true)
      button:SetScript("OnEnter", function(self)
         GameTooltip:SetOwner(self, "ANCHOR_TOP")
         GameTooltip:SetText(self.effect[2])
         local turns = G.c[self.effect[1]]
         if turns > 1 then
            GameTooltip:AddLine(format(L["%d turns left"], turns), 0.7, 0.7, 0.7)
         end
         GameTooltip:Show()
      end)
      button:SetScript("OnLeave", GameTooltip_Hide)
      button:Hide()
      self.effectIcons[index] = button
   end
   self.effectsFrame = effects

   self.frame = frame
   return frame
end

-- C: botside(). Lays out the icons of the effects that are running.
function side:UpdateEffects()
   if not self.effectIcons then return end
   local shown = 0
   for index, button in ipairs(self.effectIcons) do
      local on = G.c[button.effect[1]] ~= 0
      button:SetShown(on)
      if on then
         button:ClearAllPoints()
         button:SetPoint("TOPLEFT", self.effectsFrame, "TOPLEFT", 6 + (shown % EFFECT_COLUMNS) * (EFFECT_SIZE + 2),
            -16 - math.floor(shown / EFFECT_COLUMNS) * (EFFECT_SIZE + 2))
         shown = shown + 1
      end
   end
end

-- C: bot_linex() and botside().
function side:UpdateStats()
   local c = G.c
   if not self.cells or c[K.LEVEL] == 0 then return end
   local level = c[K.LEVEL]
   local T = ns.Tables
   self.title:SetText(format("%s - %s", G.name, T.class[level]))
   self.depth:SetText(format(L["Depth: %s"], T.levelname[G.level + 1]))

   self.hp:SetMinMaxValues(0, math.max(1, c[K.HPMAX]))
   self.hp:SetValue(c[K.HP])
   self.hp.text:SetText(format("%s %d / %d", L["HP"], c[K.HP], c[K.HPMAX]))
   self.spells:SetMinMaxValues(0, math.max(1, c[K.SPELLMAX]))
   self.spells:SetValue(c[K.SPELLS])
   self.spells.text:SetText(format("%s %d / %d", L["Spells"], c[K.SPELLS], c[K.SPELLMAX]))
   -- skill[level] in the C is T.skill[level + 1]: the experience for the next level.
   local low, high = T.skill[level], T.skill[level + 1] or T.skill[level]
   self.exp:SetMinMaxValues(low, math.max(low + 1, high))
   self.exp:SetValue(c[K.EXPERIENCE])
   self.exp.text:SetText(format("%s %d / %d", L["Exp"], c[K.EXPERIENCE], high))

   self:UpdateEffects()

   for _, frame in ipairs(self.cells) do
      frame.text:SetText(frame.cell.text())
   end
end

-- Minimap colors: [kind] = { r, g, b }.
local MINIMAP = {
   wall = { 0.5, 0.5, 0.55 }, monster = { 1, 0.2, 0.2 }, object = { 1, 0.82, 0 }, player = { 0.3, 1, 0.3 },
}

function side:UpdateMinimap()
   if not self.tiles or G.c[K.LEVEL] == 0 then return end
   local ground = V.Ground(G.level)
   local keys = self.minimapKey
   for x = 1, K.MAXX do
      local column, known, items = self.tiles[x], G.know[x], G.item[x]
      keys[x] = keys[x] or {}
      for y = 1, K.MAXY do
         local kind
         if x == G.playerx and y == G.playery then
            kind = "player"
         elseif known[y] == 0 then
            kind = "unknown"
         elseif ns.Display.visibleMonster(x, y) ~= 0 then
            kind = "monster"
         elseif items[y] == K.OWALL then
            kind = "wall"
         elseif items[y] ~= 0 then
            kind = "object"
         else
            kind = "floor"
         end
         if keys[x][y] ~= kind then
            keys[x][y] = kind
            local tile = column[y]
            if kind == "unknown" then
               Fill(tile, 0, 0, 0, 0.5)
            elseif kind == "floor" then
               Fill(tile, ground[1] * 1.6, ground[2] * 1.6, ground[3] * 1.6, 1)
            else
               local color = MINIMAP[kind]
               Fill(tile, color[1], color[2], color[3], 1)
            end
         end
      end
   end
end
