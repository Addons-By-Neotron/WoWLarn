--[[
**********************************************************************
WoWLarn - The action bar: ten slots for spells, potions and scrolls, on the keys 1 to 0.
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

-- The action bar: a slot holds a spell (by its three letters) or a kind of potion or scroll
-- (by object and kind, so it finds the item in the pack by itself).  The key of a slot (1 to 0,
-- while the game waits for a command) or a click does what the keys would: the command
-- (c, q or r) and then the answer, the three letters or the letter of the pack slot.  The
-- digits are the repeat count of the original game when the bar is switched off.  A right
-- click on a slot chooses what it holds.  The slots belong to the character.
local bar = {}
ns.actionBar = bar

local SLOTS, SIZE, SPACING = 10, 34, 3
-- the popup: ROWS lines of COLS choices, each COL_W wide (the icon, the spell's letters in a column CODE_W
-- wide, then the name), and the scroll bar on the right
local ROWS, ROW_H, COLS, COL_W, CODE_W = 16, 18, 2, 175, 26
local POPUP_W = COLS * COL_W + 40
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

function bar:Enabled()
   return ns.mod.db.profile.actionBar ~= false
end

local function Slots()
   local char = ns.mod.db.char
   char.actionbar = char.actionbar or {}
   return char.actionbar
end

-- The pack slots (1..26) that hold this kind of object.
local function Holding(object, arg)
   local found = {}
   for slot = 1, K.IVENSIZE do
      if G.iven[slot] == object and G.ivenarg[slot] == arg then found[#found + 1] = slot end
   end
   return found
end

local function SpellIndex(code)
   for index, spell in ipairs(ns.Tables.spelcode) do
      if spell == code then return index end
   end
end

local function Name(slot)
   if slot.spell then
      local index = SpellIndex(slot.spell)
      return index and ns.Tables.spelname[index] or slot.spell
   end
   return ns.Player.objectName(slot.object, slot.arg)
end

local function Icon(slot)
   if slot.spell then
      return "Interface\\Icons\\" .. (ns.Visuals.SPELL_ICON[slot.spell] or "INV_Misc_Book_08")
   end
   return ns.Visuals.ObjectIcon(slot.object, slot.arg) or FALLBACK_ICON
end

-- The keys that do what a slot holds, or nil and a message if it cannot be done now.
function bar:Keys(number)
   local slot = Slots()[number]
   if not slot then return nil, format(L["Slot %d of the action bar is empty (right-click it to choose)."], number % 10) end
   if slot.spell then
      local index = SpellIndex(slot.spell)
      if not index or G.spelknow[index] == 0 then return nil, L["You don't know that spell."] end
      local keys = { "c" }
      for letter in slot.spell:gmatch(".") do keys[#keys + 1] = letter end
      return keys
   end
   local held = Holding(slot.object, slot.arg)
   if #held == 0 then return nil, format(L["You have no %s."], Name(slot)) end
   return { slot.object == K.OSCROLL and "r" or "q", string.char(96 + held[1]) }
end

function bar:Press(number)
   if not ns.ui:IsReady() then return end
   ns.main:SetFocus(true)
   local keys, message = self:Keys(number)
   if not keys then
      if message then ns.ui:Message(message) end
      return
   end
   for _, key in ipairs(keys) do ns.ui:InjectKey(key) end
end

function bar:Assign(number, slot)
   Slots()[number] = slot
   self:Update()
end

function bar:Update()
   if not self.frame then return end
   self.frame:SetShown(self:Enabled())
   if not self:Enabled() then return end
   for number, button in ipairs(self.buttons) do
      local slot = Slots()[number]
      if slot then
         local usable, count
         if slot.spell then
            local index = SpellIndex(slot.spell)
            usable = index and G.spelknow and G.spelknow[index] ~= 0
         else
            count = #Holding(slot.object, slot.arg)
            usable = count > 0
         end
         ns.Visuals.SetIcon(button.icon, Icon(slot))
         button.icon:SetDesaturated(not usable)
         button.icon:SetAlpha(usable and 1 or 0.5)
         button.count:SetText(count and count > 1 and count or "")
         button.code:SetText(slot.spell or "")
      else
         button.icon:SetTexture(nil)
         button.count:SetText("")
         button.code:SetText("")
      end
   end
end

local function OnEnter(button)
   GameTooltip:SetOwner(button, "ANCHOR_TOP")
   local slot = Slots()[button.number]
   if slot then
      GameTooltip:SetText(Name(slot), 1, 1, 1)
      if slot.spell then
         local index = SpellIndex(slot.spell)
         local effect = index and ns.SpellInfo.info(index)
         if effect then GameTooltip:AddLine(effect, 1, 0.82, 0, true) end
      end
      GameTooltip:AddLine(L["Right-click to choose something else."], 0.7, 0.7, 0.7)
   else
      GameTooltip:SetText(L["Empty slot"], 1, 1, 1)
      GameTooltip:AddLine(L["Right-click to choose a spell, potion or scroll."], 0.7, 0.7, 0.7)
   end
   GameTooltip:Show()
end

-- The popup: what a slot can hold now.  Clear first, then the spells that are known, in the groups of
-- the spell book (a title for each, then the spells with their icons), then the potions and scrolls
-- in the pack.
function bar:Choices()
   local choices = { { text = L["(clear the slot)"] } }
   local T, SI = ns.Tables, ns.SpellInfo
   for number, group in ipairs(SI.GROUPS) do
      local started
      for index = 1, K.SPNUM do
         if SI.group(index) == number and G.spelknow[index] ~= 0 then
            if not started then
               started = true
               choices[#choices + 1] = { header = group.name }
            end
            local code = T.spelcode[index]
            choices[#choices + 1] = { code = code, text = T.spelname[index], slot = { spell = code },
               icon = "Interface\\Icons\\" .. (ns.Visuals.SPELL_ICON[code] or "INV_Misc_Book_08") }
         end
      end
   end
   local seen, started = {}, false
   for pack = 1, K.IVENSIZE do
      local object, arg = G.iven[pack], G.ivenarg[pack]
      if (object == K.OPOTION or object == K.OSCROLL) and not seen[object .. ":" .. arg] then
         seen[object .. ":" .. arg] = true
         if not started then
            started = true
            choices[#choices + 1] = { header = L["Potions and scrolls"] }
         end
         choices[#choices + 1] = { text = ns.Player.objectName(object, arg), slot = { object = object, arg = arg },
            icon = ns.Visuals.ObjectIcon(object, arg) or FALLBACK_ICON }
      end
   end
   return choices
end

-- The choices in lines of the popup: a title on a line of its own, the choices under it COLS to a line
-- (the clear choice too, alone on its line).
local function Lines(choices)
   local lines, line = {}, nil
   for _, choice in ipairs(choices) do
      if choice.header or not choice.slot then
         lines[#lines + 1] = { choice }
         line = nil
      elseif line and #line < COLS then
         line[#line + 1] = choice
      else
         line = { choice }
         lines[#lines + 1] = line
      end
   end
   return lines
end

function bar:UpdatePopup()
   local popup = self.popup
   FauxScrollFrame_Update(popup.scroll, #popup.lines, ROWS, ROW_H)
   local offset = FauxScrollFrame_GetOffset(popup.scroll)
   for row = 1, ROWS do
      local line = popup.lines[offset + row]
      for col = 1, COLS do
         local cell, choice = popup.rows[row][col], line and line[col]
         cell.choice = choice
         cell:SetShown(choice ~= nil)
         if choice then
            local header = choice.header
            cell:SetWidth(header and COLS * COL_W - 4 or COL_W - 4)  -- (a title runs across the columns)
            cell.icon:SetShown(choice.icon ~= nil)
            if choice.icon then ns.Visuals.SetIcon(cell.icon, choice.icon) end
            cell.code:SetText(choice.code or "")
            cell.text:SetText(header and ("|cffffd100" .. header .. "|r") or choice.text)
            cell.text:ClearAllPoints()
            -- the names in a column after the letters (the potions and scrolls have none: the same column)
            cell.text:SetPoint("LEFT", header and 2 or (choice.icon and ROW_H + 4 + CODE_W or 4), 0)
            cell.text:SetPoint("RIGHT", -2, 0)
            cell:EnableMouse(not header)  -- (a title is no choice)
         end
      end
   end
end

function bar:OpenPopup(button)
   if not self.popup then
      -- (on UIParent: in the game window it would be cut off at the window's edges)
      local popup = ns.CreatePanel(UIParent)
      popup:SetFrameStrata("FULLSCREEN_DIALOG")
      popup:SetToplevel(true)
      self.frame:HookScript("OnHide", function() popup:Hide() end)
      popup:SetSize(POPUP_W, ROWS * ROW_H + 40)
      popup:SetClampedToScreen(true)
      popup:EnableMouse(true)
      popup:Hide()
      self.popup = popup
      -- Escape closes it (before the game window, which takes the keys, sees it); the other keys go on
      popup:EnableKeyboard(true)
      popup:SetScript("OnKeyDown", function(p, key)
         p:SetPropagateKeyboardInput(key ~= "ESCAPE")
         if key == "ESCAPE" then p:Hide() end
      end)
      -- and so does a click outside it (a right-click on a slot closes it and opens it again for that slot)
      popup:SetScript("OnShow", function(p) p:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
      popup:SetScript("OnHide", function(p) p:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
      popup:SetScript("OnEvent", function(p)
         local scrollBar = _G["WoWLarnActionBarScrollScrollBar"]  -- (the scroll bar hangs off the right of the popup)
         if not p:IsMouseOver() and not (scrollBar and scrollBar:IsMouseOver()) then p:Hide() end
      end)
      popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      popup.title:SetPoint("TOPLEFT", 10, -10)
      popup.scroll = CreateFrame("ScrollFrame", "WoWLarnActionBarScroll", popup, "FauxScrollFrameTemplate")
      popup.scroll:SetPoint("TOPLEFT", 6, -30)
      popup.scroll:SetSize(POPUP_W - 12, ROWS * ROW_H)
      popup.scroll:SetScript("OnVerticalScroll", function(scroll, offset)
         FauxScrollFrame_OnVerticalScroll(scroll, offset, ROW_H, function() self:UpdatePopup() end)
      end)
      popup.rows = {}
      for row = 1, ROWS do
         popup.rows[row] = {}
         for col = 1, COLS do
            local cell = CreateFrame("Button", nil, popup)
            cell:SetSize(COL_W - 4, ROW_H)
            cell:SetPoint("TOPLEFT", 10 + (col - 1) * COL_W, -30 - (row - 1) * ROW_H)
            cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            cell.icon = cell:CreateTexture(nil, "ARTWORK")
            cell.icon:SetSize(ROW_H - 2, ROW_H - 2)
            cell.icon:SetPoint("LEFT", 2, 0)
            cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            cell.code = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")  -- (gold)
            cell.code:SetPoint("LEFT", ROW_H + 4, 0)
            cell.code:SetWidth(CODE_W)
            cell.code:SetJustifyH("LEFT")
            cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell.text:SetJustifyH("LEFT")
            cell.text:SetWordWrap(false)  -- (a long name is cut short with "...")
            cell:SetScript("OnClick", function(b)
               if not b.choice or b.choice.header then return end
               self:Assign(popup.number, b.choice.slot)
               popup:Hide()
            end)
            popup.rows[row][col] = cell
         end
      end
   end
   local popup = self.popup
   popup.number = button.number
   popup.lines = Lines(self:Choices())
   popup.title:SetText(format(L["Slot %d"], button.number % 10))
   popup:SetScale(button:GetEffectiveScale() / UIParent:GetEffectiveScale())  -- (the size of the game window)
   popup:ClearAllPoints()
   popup:SetPoint("BOTTOM", button, "TOP", 0, 6)
   popup:Show()
   self:UpdatePopup()
end

function bar:Create(parent)
   local frame = CreateFrame("Frame", nil, parent)
   frame:SetSize(SLOTS * (SIZE + SPACING) - SPACING, SIZE)
   frame:SetPoint("BOTTOM", 0, 6)
   -- (the models of the 2.5D view are frames too, and its effects layer is at +1000 of the view)
   frame:SetFrameStrata("DIALOG")
   frame:SetFrameLevel(parent:GetFrameLevel() + 1100)
   self.frame, self.buttons = frame, {}
   for number = 1, SLOTS do
      local button = CreateFrame("Button", nil, frame)
      button:SetSize(SIZE, SIZE)
      button:SetPoint("LEFT", (number - 1) * (SIZE + SPACING), 0)
      button.number = number
      local back = button:CreateTexture(nil, "BACKGROUND")
      back:SetAllPoints()
      back:SetColorTexture(0, 0, 0, 0.55)
      for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
         { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
         local line = button:CreateTexture(nil, "BORDER")
         line:SetColorTexture(0.45, 0.45, 0.5, 1)
         line:SetPoint(edge[1])
         line:SetPoint(edge[2])
         if edge[3] then line:SetHeight(1) else line:SetWidth(1) end
      end
      button.icon = button:CreateTexture(nil, "ARTWORK")
      button.icon:SetPoint("TOPLEFT", 1, -1)
      button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
      button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      button.key = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      button.key:SetPoint("TOPLEFT", 2, -2)
      button.key:SetText(number % 10)
      button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      button.count:SetPoint("BOTTOMRIGHT", -2, 2)
      button.code = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      button.code:SetPoint("BOTTOMLEFT", 2, 2)
      button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      button:SetScript("OnClick", function(b, mouse)
         if mouse == "RightButton" then self:OpenPopup(b) else self:Press(b.number) end
      end)
      button:SetScript("OnEnter", OnEnter)
      button:SetScript("OnLeave", GameTooltip_Hide)
      self.buttons[number] = button
   end
   self:Update()
   return frame
end
