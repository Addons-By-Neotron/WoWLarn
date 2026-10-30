--[[
**********************************************************************
WoWLarn - The texture browser: pick the floor, wall and lava textures of a level (debug builds only).
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
local G = ns.G
local K = ns.K

-- The texture browser (the Textures button of the debug panel): the terrain textures of
-- ns.TextureList, filtered by what is typed, with a preview.  The buttons set the texture of the
-- floor, the wall or the lava of this level (or of every level of its region), until the next
-- reload; Print gives the lines to put in V.LEVEL_TEXTURES in Data/Visuals.lua.
local browser = {}
ns.textureBrowser = browser

local ROWS, ROW_H, LIST_W, PREVIEW = 20, 16, 330, 160

function browser:Entries()
   local filter = strlower(self.filter:GetText() or "")
   local shown = self.shown
   wipe(shown)
   for _, entry in ipairs(ns.TextureList) do
      if filter == "" or strfind(strlower(entry[2]), filter, 1, true) or strfind(tostring(entry[1]), filter, 1, true) then
         shown[#shown + 1] = entry
      end
   end
end

function browser:UpdateList()
   self:Entries()
   local shown = self.shown
   FauxScrollFrame_Update(self.scroll, #shown, ROWS, ROW_H)
   local offset = FauxScrollFrame_GetOffset(self.scroll)
   for row = 1, ROWS do
      local button, entry = self.rows[row], shown[offset + row]
      button.entry = entry
      button:SetShown(entry ~= nil)
      if entry then
         button.text:SetText(entry[1] .. " " .. entry[2]:gsub("^.-/textures/", ""):gsub("%.blp$", ""))
         button.text:SetTextColor(entry[1] == self.selected and 1 or 0.8, entry[1] == self.selected and 0.82 or 0.8, entry[1] == self.selected and 0 or 0.8)
      end
   end
   self.count:SetText(#shown .. " textures")
end

function browser:Select(id)
   self.selected = id
   self.preview:SetTexture(id)
   self.id:SetText(tostring(id))
   self:UpdateList()
end

-- The levels a button changes: this one, or all of its region.
function browser:Levels()
   local level = G.level or 1
   if not self.region:GetChecked() then return { level } end
   local V = ns.Visuals
   local region, levels = V.Region(level), {}
   for l = 0, K.MAXLEVEL do
      if V.Region(l) == region then levels[#levels + 1] = l end
   end
   return levels
end

function browser:Apply(slot)
   local id = self.selected or tonumber(self.id:GetText())
   if not id then return end
   for _, level in ipairs(self:Levels()) do
      ns.mod.db.global.textures[level .. slot] = id
   end
   ns.mod:Print(format("%s %d, level %d: %s", slot, id, G.level or 1, self.region:GetChecked() and "(all of its region)" or ""))
   ns.ui:RefreshNow("map")
   self:UpdateLevel()
end

function browser:UpdateLevel()
   local V = ns.Visuals
   local level = G.level or 1
   self.level:SetText(format("Level %d (%s): floor %s, wall %s, lava %s", level, V.Region(level),
      tostring(V.Texture(level, "floor")), tostring(V.Texture(level, "wall")), tostring(V.Texture(level, "lava"))))
end

-- The lines for Data/Visuals.lua, of the levels set here.
function browser:Print()
   local levels = {}
   for key, id in pairs(ns.mod.db.global.textures) do
      local level, slot = key:match("^(%d+)(%a+)$")
      if level then
         level = tonumber(level)
         levels[level] = levels[level] or {}
         levels[level][slot] = id
      end
   end
   local keys = {}
   for level in pairs(levels) do keys[#keys + 1] = level end
   table.sort(keys)
   for _, level in ipairs(keys) do
      local parts = {}
      for _, slot in ipairs({ "floor", "wall", "lava" }) do
         if levels[level][slot] then parts[#parts + 1] = slot .. " = " .. levels[level][slot] end
      end
      ns.mod:Print(format("   [%d] = { %s },", level, table.concat(parts, ", ")))
   end
end

function browser:Create()
   local frame = ns.CreatePanel(UIParent, "WoWLarnTextureBrowser")
   frame:SetSize(LIST_W + PREVIEW + 70, 112 + ROWS * ROW_H)
   frame:SetPoint("CENTER", 100, 0)
   frame:SetFrameStrata("FULLSCREEN_DIALOG")
   frame:SetToplevel(true)
   frame:SetMovable(true)
   frame:EnableMouse(true)
   frame:RegisterForDrag("LeftButton")
   frame:SetScript("OnDragStart", frame.StartMoving)
   frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
   frame:SetScript("OnShow", function() self:UpdateLevel() end)
   frame:Hide()
   tinsert(UISpecialFrames, "WoWLarnTextureBrowser")
   self.frame, self.shown = frame, {}

   local level = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   level:SetPoint("TOPLEFT", 14, -10)
   self.level = level

   local filter = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
   filter:SetSize(LIST_W - 80, 20)
   filter:SetPoint("TOPLEFT", 20, -32)
   filter:SetAutoFocus(false)
   filter:SetScript("OnTextChanged", function() self:UpdateList() end)
   filter:SetScript("OnEscapePressed", filter.ClearFocus)
   self.filter = filter
   self.count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   self.count:SetPoint("LEFT", filter, "RIGHT", 8, 0)

   self.scroll = CreateFrame("ScrollFrame", "WoWLarnTextureScroll", frame, "FauxScrollFrameTemplate")
   self.scroll:SetPoint("TOPLEFT", 8, -58)
   self.scroll:SetPoint("BOTTOMLEFT", 8, 8)
   self.scroll:SetWidth(LIST_W + 10)
   self.scroll:SetScript("OnVerticalScroll", function(scroll, offset)
      FauxScrollFrame_OnVerticalScroll(scroll, offset, ROW_H, function() self:UpdateList() end)
   end)
   self.rows = {}
   for row = 1, ROWS do
      local button = CreateFrame("Button", nil, frame)
      button:SetSize(LIST_W, ROW_H)
      button:SetPoint("TOPLEFT", 10, -58 - (row - 1) * ROW_H)
      button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      button.text:SetPoint("LEFT", 2, 0)
      button.text:SetJustifyH("LEFT")
      button:SetScript("OnClick", function(b) if b.entry then self:Select(b.entry[1]) end end)
      self.rows[row] = button
   end

   local x = LIST_W + 40
   local preview = frame:CreateTexture(nil, "ARTWORK")
   preview:SetSize(PREVIEW, PREVIEW)
   preview:SetPoint("TOPLEFT", x, -58)
   self.preview = preview
   local id = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
   id:SetSize(PREVIEW - 10, 20)
   id:SetPoint("TOPLEFT", x + 6, -58 - PREVIEW - 8)
   id:SetAutoFocus(false)
   id:SetScript("OnEnterPressed", function(box)
      box:ClearFocus()
      if tonumber(box:GetText()) then self:Select(tonumber(box:GetText())) end
   end)
   id:SetScript("OnEscapePressed", id.ClearFocus)
   self.id = id

   local function Button(text, y, onClick)
      local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
      button:SetSize(PREVIEW, 22)
      button:SetPoint("TOPLEFT", x, y)
      button:SetText(text)
      button:SetScript("OnClick", onClick)
      return button
   end
   local y = -58 - PREVIEW - 40
   Button("Use as floor", y, function() self:Apply("floor") end)
   Button("Use as wall", y - 26, function() self:Apply("wall") end)
   Button("Use as lava", y - 52, function() self:Apply("lava") end)
   self.region = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
   self.region:SetPoint("TOPLEFT", x - 4, y - 80)
   local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   label:SetPoint("LEFT", self.region, "RIGHT", 0, 0)
   label:SetText("all levels of this region")
   Button("Print the choices", y - 110, function() self:Print() end)
   Button("Close", y - 136, function() frame:Hide() end)
end

function browser:Toggle()
   if not self.frame then self:Create() self:UpdateList() end
   self.frame:SetShown(not self.frame:IsShown())
end
