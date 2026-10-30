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
local ROWS, ROW_H, POPUP_W = 16, 18, 270
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
         button.icon:SetTexture(Icon(slot))
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

-- The popup: what a slot can hold now.  Clear first, then the spells that are known, then the
-- potions and scrolls in the pack.
function bar:Choices()
   local choices = { { text = L["(clear the slot)"] } }
   local T = ns.Tables
   for index = 1, K.SPNUM do
      if G.spelknow[index] ~= 0 then
         choices[#choices + 1] = { text = "|cffffd100" .. T.spelcode[index] .. "|r  " .. T.spelname[index], slot = { spell = T.spelcode[index] } }
      end
   end
   local seen = {}
   for pack = 1, K.IVENSIZE do
      local object, arg = G.iven[pack], G.ivenarg[pack]
      if (object == K.OPOTION or object == K.OSCROLL) and not seen[object .. ":" .. arg] then
         seen[object .. ":" .. arg] = true
         choices[#choices + 1] = { text = ns.Player.objectName(object, arg), slot = { object = object, arg = arg } }
      end
   end
   return choices
end

function bar:UpdatePopup()
   local popup = self.popup
   FauxScrollFrame_Update(popup.scroll, #popup.choices, ROWS, ROW_H)
   local offset = FauxScrollFrame_GetOffset(popup.scroll)
   for row = 1, ROWS do
      local button, choice = popup.rows[row], popup.choices[offset + row]
      button.choice = choice
      button:SetShown(choice ~= nil)
      if choice then button.text:SetText(choice.text) end
   end
end

function bar:OpenPopup(button)
   if not self.popup then
      local popup = ns.CreatePanel(self.frame)
      popup:SetFrameStrata("DIALOG")
      popup:SetSize(POPUP_W, ROWS * ROW_H + 40)
      popup:EnableMouse(true)
      popup:Hide()
      self.popup = popup
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
         local choiceButton = CreateFrame("Button", nil, popup)
         choiceButton:SetSize(POPUP_W - 36, ROW_H)
         choiceButton:SetPoint("TOPLEFT", 10, -30 - (row - 1) * ROW_H)
         choiceButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
         choiceButton.text = choiceButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
         choiceButton.text:SetPoint("LEFT", 2, 0)
         choiceButton.text:SetJustifyH("LEFT")
         choiceButton:SetScript("OnClick", function(b)
            if not b.choice then return end
            self:Assign(popup.number, b.choice.slot)
            popup:Hide()
         end)
         popup.rows[row] = choiceButton
      end
   end
   local popup = self.popup
   popup.number = button.number
   popup.choices = self:Choices()
   popup.title:SetText(format(L["Slot %d"], button.number % 10))
   popup:ClearAllPoints()
   popup:SetPoint("BOTTOM", button, "TOP", 0, 6)
   popup:Show()
   self:UpdatePopup()
end

function bar:Create(parent)
   local frame = CreateFrame("Frame", nil, parent)
   frame:SetSize(SLOTS * (SIZE + SPACING) - SPACING, SIZE)
   frame:SetPoint("BOTTOM", 0, 6)
   frame:SetFrameLevel(parent:GetFrameLevel() + 60)
   self.frame, self.buttons = frame, {}
   for number = 1, SLOTS do
      local button = CreateFrame("Button", nil, frame)
      button:SetSize(SIZE, SIZE)
      button:SetPoint("LEFT", (number - 1) * (SIZE + SPACING), 0)
      button.number = number
      local back = button:CreateTexture(nil, "BACKGROUND")
      back:SetAllPoints()
      back:SetColorTexture(0, 0, 0, 0.55)
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
