--[[
**********************************************************************
WoWLarn - The debug panel: buttons for wizard mode, god mode and friends (debug builds only).
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

-- The debug panel (/larn debug, or the Debug button in the title bar): wizard mode, god mode
-- and what they give, as buttons.  Anything that gives an advantage turns wizard mode on,
-- which keeps the game off the scoreboard.
local panel = {}
ns.debugPanel = panel

local WIDTH, BUTTON_H, GAP = 190, 24, 4

local function Wizard()
   if not G.wizard then ns.Debug.toggleWizard() end
end

-- Runs a key in the game (it asks questions); the game has to be waiting for a command.
local function Key(key)
   Wizard()
   if ns.ui.InjectKey then ns.ui:InjectKey(key) end
end

-- The item list: every object (potions and scrolls by kind), filtered by what is typed.  A
-- click puts the object next to the player; the number is its argument (enchantment, gold).
local ROWS, ROW_H, LIST_W = 16, 18, 260
local entries

local function Entries()
   if entries then return entries end
   local T = ns.Tables
   entries = {}
   for id = 1, K.MAXOBJ - 1 do
      local name = T.objectname[id]
      if name and name ~= "" then
         if id == K.OPOTION then
            for arg = 0, K.MAXPOTION - 1 do
               local kind = T.potionname[arg]
               if kind and kind ~= "" then entries[#entries + 1] = { id = id, arg = arg, text = name .. " of " .. kind } end
            end
         elseif id == K.OSCROLL then
            for arg = 0, K.MAXSCROLL - 1 do
               local kind = T.scrollname[arg]
               if kind and kind ~= "" then entries[#entries + 1] = { id = id, arg = arg, text = name .. " of " .. kind } end
            end
         else
            entries[#entries + 1] = { id = id, text = ns.Debug.objectLabel(id, name) }
         end
      end
   end
   return entries
end

function panel:UpdateList()
   local list = self.list
   local shown = self.shown
   wipe(shown)
   local filter = strlower(list.filter:GetText() or "")
   for _, entry in ipairs(Entries()) do
      if filter == "" or strfind(strlower(entry.text), filter, 1, true) then shown[#shown + 1] = entry end
   end
   FauxScrollFrame_Update(list.scroll, #shown, ROWS, ROW_H)
   local offset = FauxScrollFrame_GetOffset(list.scroll)
   for row = 1, ROWS do
      local button, entry = list.rows[row], shown[offset + row]
      button.entry = entry
      button:SetShown(entry ~= nil)
      if entry then button.text:SetText(entry.text) end
   end
end

function panel:CreateList()
   local list = ns.CreatePanel(UIParent, "WoWLarnItemList")
   list:SetSize(LIST_W + 36, 62 + ROWS * ROW_H)
   list:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 4, 0)
   list:SetFrameStrata("FULLSCREEN_DIALOG")
   list:SetToplevel(true)
   list:EnableMouse(true)
   list:Hide()
   self.list, self.shown = list, {}

   local filter = CreateFrame("EditBox", nil, list, "InputBoxTemplate")
   filter:SetSize(LIST_W - 70, 20)
   filter:SetPoint("TOPLEFT", 14, -8)
   filter:SetAutoFocus(false)
   filter:SetScript("OnTextChanged", function() self:UpdateList() end)
   filter:SetScript("OnEscapePressed", filter.ClearFocus)
   list.filter = filter
   local arg = CreateFrame("EditBox", nil, list, "InputBoxTemplate")
   arg:SetSize(44, 20)
   arg:SetPoint("LEFT", filter, "RIGHT", 10, 0)
   arg:SetAutoFocus(false)
   arg:SetNumeric(true)
   arg:SetText("0")
   arg:SetScript("OnEscapePressed", arg.ClearFocus)
   list.arg = arg
   local hint = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   hint:SetPoint("TOPLEFT", filter, "BOTTOMLEFT", -6, -2)
   hint:SetText("type to filter, number = enchantment / gold; click to create")

   list.scroll = CreateFrame("ScrollFrame", "WoWLarnItemListScroll", list, "FauxScrollFrameTemplate")
   list.scroll:SetPoint("TOPLEFT", 8, -50)
   list.scroll:SetPoint("BOTTOMRIGHT", -28, 8)
   list.scroll:SetScript("OnVerticalScroll", function(scroll, offset)
      FauxScrollFrame_OnVerticalScroll(scroll, offset, ROW_H, function() self:UpdateList() end)
   end)
   list.rows = {}
   for row = 1, ROWS do
      local button = CreateFrame("Button", nil, list)
      button:SetSize(LIST_W, ROW_H)
      button:SetPoint("TOPLEFT", 10, -50 - (row - 1) * ROW_H)
      button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      button.text:SetPoint("LEFT", 2, 0)
      button:SetScript("OnClick", function(b)
         local entry = b.entry
         if not entry then return end
         Wizard()
         ns.Debug.makeItem(entry.id, entry.arg or tonumber(list.arg:GetText()) or 0)
      end)
      list.rows[row] = button
   end
end

function panel:ToggleList()
   if not self.list then self:CreateList() end
   self.list:SetShown(not self.list:IsShown())
   self:UpdateList()
end

function panel:Create()
   local frame = ns.CreatePanel(UIParent, "WoWLarnDebugPanel")
   frame:SetPoint("CENTER", -300, 0)
   frame:SetFrameStrata("FULLSCREEN_DIALOG")
   frame:SetToplevel(true)
   frame:SetMovable(true)
   frame:EnableMouse(true)
   frame:RegisterForDrag("LeftButton")
   frame:SetScript("OnDragStart", frame.StartMoving)
   frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
   frame:Hide()
   tinsert(UISpecialFrames, "WoWLarnDebugPanel")
   self.frame = frame
   frame:SetScript("OnHide", function() if self.list then self.list:Hide() end end)

   local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   title:SetPoint("TOP", 0, -8)
   title:SetText("WoWLarn debug")

   local buttons = {}
   local function Button(text, onClick)
      local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
      button:SetSize(WIDTH - 16, BUTTON_H)
      button:SetPoint("TOP", 0, -26 - #buttons * (BUTTON_H + GAP))
      button:SetText(text)
      button:SetScript("OnClick", function() onClick() self:Update() end)
      buttons[#buttons + 1] = button
      return button
   end
   self.wizard = Button("Wizard mode", ns.Debug.toggleWizard)
   self.god = Button("God mode", ns.Debug.toggleGod)
   Button("Debug kit (stats 70, all known)", function() Wizard() ns.Debug.kit() end)
   Button("Maximum experience", function() Wizard() ns.Debug.maxExperience() end)
   Button("Reveal the map", function() Wizard() ns.Debug.reveal() end)
   Button("Create an item (list)", function() self:ToggleList() end)
   Button("Teleport to a level...", function() Key("Z") end)
   Button("Dump the state", ns.Debug.dump)
   Button("New game (gives this one up)", ns.Debug.newGame)
   Button("Object model viewer", function() ns.objectViewer:Toggle() end)
   Button("Texture browser", function() ns.textureBrowser:Toggle() end)
   Button("Flat / 2.5D view", function() ns.mod:ToggleView() end)
   frame:SetSize(WIDTH, 34 + #buttons * (BUTTON_H + GAP))
end

function panel:Update()
   if not self.frame then return end
   self.wizard:SetText("Wizard mode: " .. (G.wizard and "ON" or "off"))
   self.god:SetText("God mode: " .. (G.god and "ON" or "off"))
end

function panel:Toggle()
   if not self.frame then self:Create() end
   self.frame:SetShown(not self.frame:IsShown())
   self:Update()
end
