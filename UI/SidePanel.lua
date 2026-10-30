--[[
**********************************************************************
WoWLarn - Side panel: minimap, character sheet and effects.
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
local STAT_W, STAT_H, HEADING_H = 114, 14, 20
local SLOT_SIZE = 26
local MINIMAP_H, SHEET_H = K.MAXY * CELL + 22, 328
local MODEL_TOP, MODEL_H = 26, 84

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

-- The character sheet under the bars, in the way of the WoW one: a gold label and a white value,
-- in two columns with headings.  Each row explains itself in a tooltip.  A value in green is
-- raised by a spell that is running.
local function C(index) return G.c[index] end
local function Strength() return C(K.STRENGTH) + C(K.STREXTRA) end
local GREEN, RED = { 0.1, 1, 0.1 }, { 1, 0.3, 0.3 }
local STAT_COLUMNS = {
   {
      { heading = L["Attributes"] },
      { stat = "STR", label = L["Strength"], value = Strength,
        tip = L["Strength makes your hits stronger."] },
      { stat = "INT", label = L["Intelligence"], value = function() return C(K.INTELLIGENCE) end,
        tip = L["Intelligence makes your spells more likely to work."] },
      { stat = "WIS", label = L["Wisdom"], value = function() return C(K.WISDOM) end,
        tip = L["Wisdom makes your strongest spells, like phantasmal forces and finger of death, more likely to work."] },
      { stat = "CON", label = L["Constitution"], value = function() return C(K.CONSTITUTION) end,
        tip = L["Constitution gives you more hit points when you gain a level."] },
      { stat = "DEX", label = L["Dexterity"], value = function() return C(K.DEXTERITY) end,
        tip = L["Dexterity helps you hit monsters, and helps you avoid pits and trap doors."] },
      { stat = "CHA", label = L["Charisma"], value = function() return C(K.CHARISMA) end,
        tip = L["Charisma makes monsters more likely to be awed by you and not attack, and makes charm monster last longer."] },
   },
   {
      { heading = L["Combat"] },
      { label = L["Armor class"], value = function() return C(K.AC) end,
        tip = L["A better armor class makes monsters miss more often and hurt you less."],
        extra = function() return table.concat(ns.Equipment.summary(), "\n", 1, 1) end },
      { label = L["Weapon class"], value = function() return C(K.WCLASS) end,
        tip = L["A better weapon class makes you hit more often and harder."],
        extra = function() return table.concat(ns.Equipment.summary(), "\n", 2, 2) end },
      { label = L["Health regen"], value = function() return format("%d / %d", C(K.REGEN), (ns.Equipment.regenTurns())) end,
        tip = L["Hit points you regain, and the number of turns between."],
        extra = function() return format(L["%d every %d turns.  Rings of regeneration add to it."], C(K.REGEN), (ns.Equipment.regenTurns())) end },
      { label = L["Mana regen"], value = function() return format("1 / %d", select(2, ns.Equipment.regenTurns())) end,
        tip = L["One point of mana comes back every so many turns."],
        extra = function() return format(L["1 every %d turns.  Rings of energy make it quicker."], select(2, ns.Equipment.regenTurns())) end },
      { heading = L["General"] },
      { label = L["Level"], value = function() return C(K.LEVEL) end,
        tip = L["Your level goes up with experience.  Each level gives you more hit points and mana, and a new pack slot every second level."] },
      { label = L["Gold"], value = function() return C(K.GOLD) end,
        tip = L["Gold buys things in the town.  The bank keeps it safe, and what you have when the game ends is your score."],
        extra = function() return format(L["In the bank: %d"], C(K.BANKACCOUNT)) end },
      { label = L["Time"], value = function() return format(L["%d mobuls"], math.floor((K.TIMELIMIT - G.gtime) / 100)) end,
        tip = L["Your daughter's illness will not wait.  Bring the potion of cure dianthroritis home before the time runs out."] },
   },
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

   -- One character sheet: the name, the model with the slots of the equipment beside it, the
   -- bars and the numbers.
   local stats = Section(frame, SHEET_H, "")
   stats:SetPoint("TOPLEFT", minimap, "BOTTOMLEFT", 0, -GAP)
   stats:SetPoint("TOPRIGHT", minimap, "BOTTOMRIGHT", 0, -GAP)
   self.title = stats:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   self.title:SetPoint("TOPLEFT", 6, -6)
   self.title:SetPoint("RIGHT", -6, 0)
   self.title:SetJustifyH("LEFT")
   local player = CreateFrame("PlayerModel", nil, stats)
   player:SetPoint("TOPLEFT", 4 + SLOT_SIZE + 4, -MODEL_TOP)
   player:SetPoint("TOPRIGHT", -4, -MODEL_TOP)
   player:SetHeight(MODEL_H)
   pcall(player.SetUnit, player, "player")
   pcall(player.SetPortraitZoom, player, 0.8)
   self.player = player
   self:CreateSlots(stats)
   self.hp = Bar(stats, 0.75, 0.15, 0.15)
   self.hp:SetPoint("TOPLEFT", 6, -(MODEL_TOP + MODEL_H + 6))
   self.hp:SetPoint("TOPRIGHT", -6, -(MODEL_TOP + MODEL_H + 6))
   self.spells = Bar(stats, 0.2, 0.35, 0.85)
   self.spells:SetPoint("TOPLEFT", self.hp, "BOTTOMLEFT", 0, -3)
   self.spells:SetPoint("TOPRIGHT", self.hp, "BOTTOMRIGHT", 0, -3)
   -- what the bars mean, and how fast they fill
   local function Tooltip(bar, title, lines)
      bar:EnableMouse(true)
      bar:SetScript("OnEnter", function(self)
         GameTooltip:SetOwner(self, "ANCHOR_LEFT")
         GameTooltip:SetText(title, 1, 1, 1)
         for _, line in ipairs(lines()) do GameTooltip:AddLine(line, nil, nil, nil, true) end
         GameTooltip:Show()
      end)
      bar:SetScript("OnLeave", GameTooltip_Hide)
   end
   Tooltip(self.hp, L["Health"], function()
      local c = G.c
      return {
         L["The hit points you have.  At zero you die."],
         format(L["You regain %d every %d turns."], c[K.REGEN], math.max(1, 22 + c[K.HARDGAME] * 2 - c[K.LEVEL])),
         L["Rings of health regeneration make you regain more each time."],
      }
   end)
   Tooltip(self.spells, L["Mana"], function()
      local c = G.c
      return {
         L["Casting a spell uses one point of mana."],
         format(L["You regain 1 every %d turns."], math.max(1, 100 + 4 * (c[K.HARDGAME] - c[K.LEVEL] - c[K.ENERGY]))),
         format(L["Rings of mana regeneration make it come back faster.  Mana regeneration: %d."], c[K.ENERGY]),
      }
   end)
   self.exp = Bar(stats, 0.75, 0.6, 0.1)
   self.exp:SetPoint("TOPLEFT", self.spells, "BOTTOMLEFT", 0, -3)
   self.exp:SetPoint("TOPRIGHT", self.spells, "BOTTOMRIGHT", 0, -3)
   -- the sheet under the bars: a row for each, so each can explain itself
   self.cells = {}
   for column, rows in ipairs(STAT_COLUMNS) do
      local y = 6
      for _, cell in ipairs(rows) do
         local frame = CreateFrame("Frame", nil, stats)
         if cell.heading then
            if y > 6 then y = y + 6 end  -- (a gap above a heading that is not the first)
            frame:SetSize(STAT_W, HEADING_H)
         else
            frame:SetSize(STAT_W, STAT_H)
         end
         frame:SetPoint("TOPLEFT", self.exp, "BOTTOMLEFT", (column - 1) * (STAT_W + 4), -y)
         y = y + (cell.heading and HEADING_H or STAT_H)
         if cell.heading then
            frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            frame.label:SetPoint("BOTTOMLEFT", 2, 3)
            frame.label:SetText(cell.heading)
            local line = frame:CreateTexture(nil, "ARTWORK")
            line:SetPoint("BOTTOMLEFT", 0, 0)
            line:SetPoint("BOTTOMRIGHT", 0, 0)
            line:SetHeight(1)
            Fill(line, 1, 0.82, 0, 0.5)
            frame.cell = false
         else
            frame:EnableMouse(true)
            frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            frame.label:SetPoint("LEFT", 6, 0)
            frame.label:SetText(cell.label)
            frame.label:SetTextColor(0.8, 0.8, 0.8)
            frame.value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            frame.value:SetPoint("RIGHT", -2, 0)
            frame.value:SetJustifyH("RIGHT")
            frame.cell = cell
            frame:SetScript("OnEnter", function(self)
               GameTooltip:SetOwner(self, "ANCHOR_LEFT")
               GameTooltip:SetText(self.cell.label, 1, 1, 1)
               GameTooltip:AddLine(self.cell.tip, nil, nil, nil, true)
               if self.cell.stat then
                  local total, base, mods = ns.Equipment.statBreakdown(self.cell.stat)
                  GameTooltip:AddDoubleLine(L["Base"], base, 1, 1, 1, 1, 1, 1)
                  for _, mod in ipairs(mods) do
                     local good = mod[2] > 0
                     GameTooltip:AddDoubleLine(mod[1], format("%+d", mod[2]), 0.8, 0.8, 0.8,
                        good and 0.1 or 1, good and 1 or 0.3, good and 0.1 or 0.3)
                  end
                  if #mods > 0 then GameTooltip:AddDoubleLine(L["Total"], total, 1, 0.82, 0, 1, 0.82, 0) end
               end
               if self.cell.extra then
                  local extra = self.cell.extra()
                  if extra then GameTooltip:AddLine(extra, 0.6, 0.9, 0.6, true) end
               end
               GameTooltip:Show()
            end)
            frame:SetScript("OnLeave", GameTooltip_Hide)
         end
         self.cells[#self.cells + 1] = frame
      end
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
         local curse = V.CURSE[self.effect[1]]
         GameTooltip:SetText(self.effect[2], curse and 1 or 0.3, curse and 0.3 or 1, 0.3)
         GameTooltip:AddLine(curse and L["Curse"] or L["Boon"], curse and 1 or 0.3, curse and 0.3 or 1, 0.3)
         local turns = G.c[self.effect[1]]
         if turns > 1 then
            GameTooltip:AddLine(format(L["%d turns left"], turns), 0.7, 0.7, 0.7)
         end
         if curse then
            GameTooltip:AddLine(L["A scroll of remove curse or a potion of instant healing lifts it."], 0.9, 0.9, 0.9, true)
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

-- The slots of the character sheet: weapon, armor and shield.  A click opens the list of what
-- in the pack fits (UI/EquipMenu.lua); the tooltip says what is there and how it counts.
local SLOTS = {
   { kind = "weapon", empty = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand", worn = function() return G.c[K.WIELD] end },
   { kind = "armor", empty = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest", worn = function() return G.c[K.WEAR] end },
   { kind = "shield", empty = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand", worn = function() return G.c[K.SHIELD] end },
}

function side:CreateSlots(parent)
   self.slots = {}
   for index, slot in ipairs(SLOTS) do
      local button = CreateFrame("Button", nil, parent)
      button:SetSize(SLOT_SIZE, SLOT_SIZE)
      button:SetPoint("TOPLEFT", 4, -MODEL_TOP - (index - 1) * (SLOT_SIZE + 3))
      button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      button.icon = button:CreateTexture(nil, "ARTWORK")
      button.icon:SetAllPoints()
      button.border = button:CreateTexture(nil, "OVERLAY")
      button.border:SetAllPoints()
      Fill(button.border, 0, 0, 0, 0)
      button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      button.count:SetPoint("BOTTOMRIGHT", -2, 2)
      button.slot = slot
      button:SetScript("OnClick", function(b) ns.equipMenu:Open(b.slot.kind, b) end)
      button:SetScript("OnEnter", function(b)
         GameTooltip:SetOwner(b, "ANCHOR_LEFT")
         local worn = b.slot.worn()
         if worn ~= 0 and G.iven[worn] ~= 0 then
            ns.ItemInfo.tooltip(G.iven[worn], G.ivenarg[worn])
         else
            GameTooltip:SetText(ns.equipMenu.KINDS[b.slot.kind].title, 1, 1, 1)
            GameTooltip:AddLine(L["Nothing equipped."], 0.7, 0.7, 0.7)
         end
         GameTooltip:AddLine(L["Click to change."], 0.5, 0.8, 1)
         GameTooltip:Show()
      end)
      button:SetScript("OnLeave", GameTooltip_Hide)
      self.slots[index] = button
   end
end

function side:UpdateSlots()
   if not self.slots then return end
   for _, button in ipairs(self.slots) do
      local worn = button.slot.worn()
      local id = worn ~= 0 and G.iven[worn] or 0
      local icon = id ~= 0 and V.ObjectIcon(id)
      if icon then
         button.icon:SetTexture(icon)
         button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
         local arg = G.ivenarg[worn]
         button.count:SetText(arg ~= 0 and format("%+d", arg) or "")
      else
         button.icon:SetTexture(button.slot.empty)
         button.icon:SetTexCoord(0, 1, 0, 1)
         button.count:SetText("")
      end
   end
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
   self.spells.text:SetText(format("%s %d / %d", L["Mana"], c[K.SPELLS], c[K.SPELLMAX]))
   -- skill[level] in the C is T.skill[level + 1]: the experience for the next level.
   local low, high = T.skill[level], T.skill[level + 1] or T.skill[level]
   self.exp:SetMinMaxValues(low, math.max(low + 1, high))
   self.exp:SetValue(c[K.EXPERIENCE])
   self.exp.text:SetText(format("%s %d / %d", L["Exp"], c[K.EXPERIENCE], high))

   self:UpdateEffects()
   self:UpdateSlots()

   for _, frame in ipairs(self.cells) do
      if frame.cell then
         frame.value:SetText(frame.cell.value())
         local color = { 1, 1, 1 }
         if frame.cell.stat then  -- (green: raised by what you carry or a spell, red: lowered)
            local total, base = ns.Equipment.statBreakdown(frame.cell.stat)
            if total > base then color = GREEN elseif total < base then color = RED end
         end
         frame.value:SetTextColor(color[1], color[2], color[3])
      end
   end
end

-- Minimap colors: [kind] = { r, g, b }.
local MINIMAP = {
   stairsup = { 1, 0.5, 0.05 }, stairsdown = { 0.85, 0.35, 1 },
   elevatorup = { 1, 0.75, 0.4 }, elevatordown = { 1, 0.6, 0.85 },
   wall = { 0.62, 0.62, 0.68 }, monster = { 1, 0.2, 0.2 }, object = { 1, 0.82, 0 }, player = { 0.35, 0.85, 1 },
}

-- The ways between the levels have colors of their own.
local STAIRS = {
   [K.OSTAIRSUP] = "stairsup", [K.OSTAIRSDOWN] = "stairsdown",
   [K.OELEVATORUP] = "elevatorup", [K.OELEVATORDOWN] = "elevatordown",
}

function side:UpdateMinimap()
   if not self.tiles or G.c[K.LEVEL] == 0 then return end
   local ground = V.Ground(G.level)
   local keys = self.minimapKey
   if self.minimapLevel ~= G.level then  -- another level: paint everything again
      self.minimapLevel = G.level
      for x = 1, K.MAXX do keys[x] = nil end
   end
   for x = 1, K.MAXX do
      local column, known, items = self.tiles[x], G.know[x], G.item[x]
      keys[x] = keys[x] or {}
      for y = 1, K.MAXY do
         local kind
         if x == G.playerx and y == G.playery then
            kind = "player"
         elseif not ns.Display.remembered(x, y) then
            kind = "unknown"
         elseif items[y] == K.OWALL then
            kind = "wall"
         elseif known[y] == 0 then
            kind = "floor"
         elseif ns.Display.visibleMonster(x, y) ~= 0 then
            kind = "monster"
         elseif items[y] == K.OWALL then
            kind = "wall"
         elseif STAIRS[items[y]] then
            kind = STAIRS[items[y]]
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
               Fill(tile, ground[1] * 0.7, ground[2] * 0.7, ground[3] * 0.7, 1)
            else
               local color = MINIMAP[kind]
               Fill(tile, color[1], color[2], color[3], 1)
            end
         end
      end
   end
end
