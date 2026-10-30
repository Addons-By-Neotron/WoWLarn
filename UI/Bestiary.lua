--[[
WoWLarn - the bestiary window.
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
local G = ns.G
local format = string.format

-- The bestiary window (the B button of the bar): the monsters seen so far in a list, and for
-- the one chosen its model, the level it was first met on, a rough idea of how tough it is and
-- the special attacks seen (see Bestiary.lua).
local window = {}
ns.bestiaryWindow = window

local LIST_W, ROW_H, ROWS = 190, 18, 26
local DETAIL_W, MODEL_H = 330, 240
local MODEL_ROOM = 1.7  -- the models are made for a frame a tile wide: farther away in this larger one

function window:Create()
   local frame = ns.CreatePanel(UIParent, "WoWLarnBestiary", { 0.04, 0.04, 0.06, 0.97 })
   frame:SetSize(LIST_W + DETAIL_W + 40, 40 + ROWS * ROW_H)
   frame:SetPoint("CENTER", 120, 0)
   frame:SetFrameStrata("FULLSCREEN_DIALOG")  -- (above the main window, whose many layers are all in DIALOG)
   frame:SetToplevel(true)
   frame:SetMovable(true)
   frame:EnableMouse(true)
   frame:RegisterForDrag("LeftButton")
   frame:SetScript("OnDragStart", frame.StartMoving)
   frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
   frame:Hide()
   tinsert(UISpecialFrames, "WoWLarnBestiary")
   self.frame = frame

   self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   self.title:SetPoint("TOPLEFT", 12, -10)

   local scroll = CreateFrame("ScrollFrame", "WoWLarnBestiaryScroll", frame, "FauxScrollFrameTemplate")
   scroll:SetPoint("TOPLEFT", 8, -32)
   scroll:SetSize(LIST_W, ROWS * ROW_H)
   scroll:SetScript("OnVerticalScroll", function(s, offset)
      FauxScrollFrame_OnVerticalScroll(s, offset, ROW_H, function() self:UpdateList() end)
   end)
   self.scroll = scroll
   self.rows = {}
   for row = 1, ROWS do
      local button = CreateFrame("Button", nil, frame)
      button:SetSize(LIST_W - 4, ROW_H)
      button:SetPoint("TOPLEFT", 10, -32 - (row - 1) * ROW_H)
      button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      button.text:SetPoint("LEFT", 2, 0)
      button:SetScript("OnClick", function(b)
         if b.id then self:Select(b.id) end
      end)
      self.rows[row] = button
   end

   local model = CreateFrame("PlayerModel", nil, frame)
   model:SetPoint("TOPLEFT", LIST_W + 30, -32)
   model:SetSize(DETAIL_W, MODEL_H)
   model:SetScript("OnModelLoaded", function(m) m:SetFacing(self.turn or 0) ns.map3d.CameraScale(m, (self.scale or 1) * MODEL_ROOM) end)
   self.model = model

   self.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   self.name:SetPoint("TOPLEFT", model, "BOTTOMLEFT", 0, -6)
   self.details = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   self.details:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -8)
   self.details:SetWidth(DETAIL_W)
   self.details:SetJustifyH("LEFT")
   self.details:SetSpacing(3)

   frame:SetScript("OnShow", function() self:Update() end)
end

function window:UpdateList()
   local list = ns.Bestiary.list()
   FauxScrollFrame_Update(self.scroll, #list, ROWS, ROW_H)
   local offset = FauxScrollFrame_GetOffset(self.scroll)
   for row, button in ipairs(self.rows) do
      local id = list[offset + row]
      button.id = id
      button:SetShown(id ~= nil)
      if id then
         local name = ns.TitleCase(ns.MonsterData[id].name)
         button.text:SetText((id == self.selected and "|cffffd100" or "") .. name)
      end
   end
end

-- A range of numbers as text.
local function Range(low, high)
   return low == high and tostring(low) or format("%d-%d", low, high)
end

function window:Select(id)
   self.selected = id
   local data, entry = ns.MonsterData[id], ns.Bestiary.entry(id)
   local V = ns.Visuals
   local display = V.MonsterDisplay(id, 1)
   if display then
      self.turn, self.scale = V.Turn(display), V.Scale(display)
      if display < 0 then self.model:SetModel(-display) else self.model:SetDisplayInfo(display) end
      self.model:SetFacing(self.turn)
      ns.map3d.CameraScale(self.model, self.scale * MODEL_ROOM)
      self.model:Show()
   else
      self.model:Hide()
   end
   self.name:SetText(ns.TitleCase(data.name))

   local lines = {}
   lines[#lines + 1] = format(L["First met on level %d"], entry.level)
   if entry.kills > 0 then lines[#lines + 1] = format(L["Killed: %d"], entry.kills) end
   local low, high = ns.Bestiary.health(id)
   lines[#lines + 1] = format(L["Health: about %s"], Range(low, high))
   local nlow, nhigh = ns.Bestiary.damage(id, 0)
   lines[#lines + 1] = format(L["Damage: about %s per hit without armor"], Range(nlow, nhigh))
   local ac = G.c and G.c[K.AC] or 0
   if ac > 0 then
      local alow, ahigh = ns.Bestiary.damage(id, ac)
      if ahigh == 0 then
         lines[#lines + 1] = L["Your armor stops it (unless it has tricks)"]
      else
         lines[#lines + 1] = format(L["With your armor: about %s"], Range(alow, ahigh))
      end
   end
   local specials, hidden = ns.Bestiary.specials(id)
   if #specials > 0 then
      lines[#lines + 1] = "|cffffd100" .. L["Special attacks"] .. "|r"
      for _, name in ipairs(specials) do lines[#lines + 1] = "  " .. name end
   end
   if hidden or (#specials > 0 and data.attack == 12) then
      lines[#lines + 1] = "|cff999999" .. L["It may have tricks you have yet to see."] .. "|r"
   end
   self.details:SetText(table.concat(lines, "\n"))
   self:UpdateList()
end

function window:Update()
   local list = ns.Bestiary.list()
   self.title:SetText(format(L["Bestiary: %d of %d monsters seen"], #list, K.MAXMONST + 8))
   if self.selected and not ns.Bestiary.entry(self.selected) then self.selected = nil end
   if not self.selected and list[1] then self.selected = list[1] end
   if self.selected then
      self:Select(self.selected)
   else
      self.name:SetText("")
      self.details:SetText(L["No monsters seen yet."])
      self.model:Hide()
      self:UpdateList()
   end
end

function window:Toggle()
   if not self.frame then self:Create() end
   self.frame:SetShown(not self.frame:IsShown())
end
