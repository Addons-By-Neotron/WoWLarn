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
local L = LibStub("AceLocale-3.0"):GetLocale("WoWLarn")
local _, ns = ...
local K = ns.K
local G = ns.G
local V = ns.Visuals

-- The window of the town buildings: a title, a few lines of text, a list of lettered rows
-- (goods with prices, courses, gems) and two lines at the bottom for the gold and the last
-- thing that happened. The game code (Town.lua) fills it in and waits for keys; clicking a
-- row injects its letter, just like the inventory.
local store = {}
ns.store = store

local COLUMNS, ROWS = 2, 13
local ROW_H, ROW_W = 24, 270
local HEADER_H, INTRO_H, TEXT_H, FOOTER_H = 24, 54, 250, 76

function store:Create(parent)
   local frame = ns.CreatePanel(parent)
   frame:SetFrameStrata("DIALOG")
   frame:SetFrameLevel(parent:GetFrameLevel() + 1200)  -- (above the action bar; the inventory opens above it; the 2.5D view uses the 60 levels above the map)
   frame:SetWidth(COLUMNS * ROW_W + 16)
   frame:SetPoint("CENTER")
   frame:EnableMouse(true)
   frame:Hide()
   self.frame = frame

   self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   self.title:SetPoint("TOPLEFT", 8, -6)

   self.intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   self.intro:SetPoint("TOPLEFT", 8, -HEADER_H)
   self.intro:SetWidth(COLUMNS * ROW_W)
   self.intro:SetJustifyH("LEFT")
   self.intro:SetJustifyV("TOP")

   -- the buttons along the bottom: the pages of a long list on the left ("<" and ">" are the keys
   -- the game code listens for), then what can be done here (the game code says what and which
   -- key each sends), and Leave (the same as Esc) on the right
   local function Key(key)
      ns.main:SetFocus(true)
      ns.ui:InjectKey(key)
   end
   local leave = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   leave:SetSize(80, 22)
   leave:SetPoint("BOTTOMRIGHT", -8, 8)
   leave:SetText(L["Leave"])
   leave:SetScript("OnClick", function() Key(ns.ESC) end)
   self.leave = leave
   self.pager = CreateFrame("Frame", nil, frame)
   self.pager:SetSize(120, 22)
   self.pager:SetPoint("BOTTOMLEFT", 8, 8)
   self.pager:Hide()
   local previous = CreateFrame("Button", nil, self.pager, "UIPanelButtonTemplate")
   previous:SetSize(24, 22)
   previous:SetPoint("LEFT")
   previous:SetText("<")
   previous:SetScript("OnClick", function() Key("<") end)
   local following = CreateFrame("Button", nil, self.pager, "UIPanelButtonTemplate")
   following:SetSize(24, 22)
   following:SetPoint("RIGHT")
   following:SetText(">")
   following:SetScript("OnClick", function() Key(">") end)
   self.actions = {}
   for index = 1, 4 do
      local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
      button:SetSize(100, 22)
      button:SetPoint("RIGHT", index == 1 and leave or self.actions[index - 1], "LEFT", -6, 0)
      button:SetScript("OnClick", function(self) Key(self.key) end)
      button:Hide()
      self.actions[index] = button
   end
   self.pageText = self.pager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   self.pageText:SetPoint("LEFT", previous, "RIGHT")
   self.pageText:SetPoint("RIGHT", following, "LEFT")

   self.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   self.status:SetPoint("BOTTOMLEFT", 8, 54)
   self.status:SetPoint("BOTTOMRIGHT", -8, 54)
   self.status:SetJustifyH("LEFT")
   self.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   self.note:SetPoint("BOTTOMLEFT", 8, 34)
   self.note:SetPoint("BOTTOMRIGHT", -8, 34)
   self.note:SetJustifyH("LEFT")

   -- the question before a sale: a small window over the list, answered with y and n
   local confirm = ns.CreatePanel(frame)
   confirm:SetSize(340, 96)
   confirm:SetPoint("CENTER")
   confirm:SetFrameLevel(frame:GetFrameLevel() + 40)
   confirm:EnableMouse(true)
   confirm:Hide()
   self.confirm = confirm
   self.confirmText = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   self.confirmText:SetPoint("TOPLEFT", 10, -10)
   self.confirmText:SetPoint("TOPRIGHT", -10, -10)
   self.confirmText:SetHeight(48)
   self.confirmText:SetJustifyH("CENTER")
   self.confirmText:SetJustifyV("TOP")
   local no = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate")
   no:SetSize(90, 22)
   no:SetPoint("BOTTOM", 50, 10)
   no:SetText(L["No"])
   no:SetScript("OnClick", function() Key("n") end)
   local yes = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate")
   yes:SetSize(90, 22)
   yes:SetPoint("BOTTOM", -50, 10)
   yes:SetText(L["Yes"])
   yes:SetScript("OnClick", function() Key("y") end)

   -- how much gold: a slider from 0 to the most there is, or type the number
   local amount = ns.CreatePanel(frame)
   amount:SetSize(380, 130)
   amount:SetPoint("CENTER")
   amount:SetFrameLevel(frame:GetFrameLevel() + 40)
   amount:EnableMouse(true)
   amount:Hide()
   self.amount = amount
   self.amountText = amount:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   self.amountText:SetPoint("TOP", 0, -10)
   self.amountValueText = amount:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   self.amountValueText:SetPoint("TOP", 0, -32)
   local slider = CreateFrame("Slider", nil, amount, "OptionsSliderTemplate")
   slider:SetSize(320, 16)
   slider:SetPoint("TOP", 0, -64)
   slider:SetObeyStepOnDrag(true)
   slider:SetValueStep(1)
   slider:SetScript("OnValueChanged", function(_, value)
      if self.settingAmount then return end
      self.typing = false
      self:ShowAmount(math.floor(value + 0.5))
   end)
   self.amountSlider = slider
   self.amountMin = amount:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   self.amountMin:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
   self.amountMin:SetText("0")
   self.amountMax = amount:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   self.amountMax:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
   local function AmountButton(label, key, x)
      local button = CreateFrame("Button", nil, amount, "UIPanelButtonTemplate")
      button:SetSize(90, 22)
      button:SetPoint("BOTTOM", x, 10)
      button:SetText(label)
      button:SetScript("OnClick", function() Key(key) end)
   end
   AmountButton(L["OK"], "ENTER", -100)
   AmountButton(L["All"], "*", 0)
   AmountButton(L["Cancel"], ns.ESC, 100)

   self.rows = {}
   for index = 1, COLUMNS * ROWS do
      local button = CreateFrame("Button", nil, frame)
      button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      button.selected = button:CreateTexture(nil, "BACKGROUND")
      button.selected:SetAllPoints()
      button.selected:SetColorTexture(1, 0.82, 0, 0.2)
      button.selected:Hide()
      button.icon = button:CreateTexture(nil, "ARTWORK")
      button.icon:SetSize(ROW_H - 6, ROW_H - 6)
      button.icon:SetPoint("LEFT", 2, 0)
      button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      button.price = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      button.price:SetPoint("RIGHT", -4, 0)
      button.price:SetJustifyH("RIGHT")
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      button.text:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
      button.text:SetPoint("RIGHT", button.price, "LEFT", -4, 0)
      button.text:SetJustifyH("LEFT")
      button.text:SetWordWrap(false)
      button:SetScript("OnClick", function(self)
         if not self.key then return end
         ns.main:SetFocus(true)
         ns.ui:InjectKey(self.key)
      end)
      button:SetScript("OnEnter", function(self)
         if self.id then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            ns.ItemInfo.tooltip(self.id, self.arg)
         elseif self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
         end
      end)
      button:SetScript("OnLeave", GameTooltip_Hide)
      button:Hide()
      self.rows[index] = button
   end
   return frame
end

function store:IsShown()
   return self.frame and self.frame:IsShown()
end

function store:Close()
   if self.frame then self.frame:Hide() end
end

-- Starts a new screen. columns is 1 (default) or 2 for a list of rows, 0 for a screen of text.
function store:Open(title, intro, columns)
   if not self.frame then return end
   self.columns = columns or 1
   self.introHeight = self.columns == 0 and TEXT_H or INTRO_H
   self.intro:SetFontObject(self.columns == 0 and "GameFontHighlight" or "GameFontHighlightSmall")
   self.title:SetText(title)
   self:SetActions()
   self.confirm:Hide()
   self.amount:Hide()
   self.leave:SetText(self.columns == 0 and L["OK"] or L["Leave"])
   self.intro:SetText(intro or "")
   self.status:SetText("")
   self.note:SetText("")
   self:SetPages()
   self:SetRows({})
   self.frame:Show()
end

-- Shows the page buttons ("Page 2 / 3"), or hides them when there is only one page.
function store:SetPages(page, pages)
   if not self.frame then return end
   self.pager:SetShown(pages ~= nil and pages > 1)
   if pages then self.pageText:SetText(format(L["Page %d / %d"], page, pages)) end
end

-- rows: { key = "a", send = the key a click sends (default: key), selected = true to highlight it, text = "...", price = "...", icon = object id, arg = its argument (the
-- tooltip of an item), dim = true, tip = "..." }
-- Rows fill the first column top to bottom, then the second.
function store:SetRows(rows)
   if not self.frame then return end
   local perColumn = self.columns == 1 and ROWS or math.ceil(#rows / 2)
   local width = self.columns == 1 and COLUMNS * ROW_W or ROW_W
   for index, button in ipairs(self.rows) do
      local row = rows[index]
      if row then
         local column = math.floor((index - 1) / perColumn)
         button:SetSize(width - 4, ROW_H - 2)
         button:ClearAllPoints()
         button:SetPoint("TOPLEFT", 8 + column * ROW_W, -(HEADER_H + self.introHeight + ((index - 1) % perColumn) * ROW_H))
         button.key, button.tip, button.id, button.arg = row.send or row.key, row.tip, row.icon, row.arg or 0
         button.selected:SetShown(row.selected == true)
         local icon = row.icon and V.ObjectIcon(row.icon)
         if icon then
            button.icon:SetTexture(icon)
            button.icon:Show()
         else
            button.icon:Hide()
         end
         local color = row.dim and "|cff777777" or "|cffffffff"
         button.text:SetText(color .. row.key .. ")|r " .. color .. row.text .. "|r")
         button.price:SetText(row.price or "")
         button:Show()
      else
         button:Hide()
      end
   end
   local count = math.min(#rows, ROWS * COLUMNS)
   local lines = self.columns == 1 and count or math.min(perColumn, ROWS)
   if self.columns == 0 then
      self.frame:SetHeight(HEADER_H + math.max(TEXT_H, self.intro:GetStringHeight() + 8) + FOOTER_H + 8)
   else
      self.frame:SetHeight(HEADER_H + INTRO_H + math.max(lines, 1) * ROW_H + FOOTER_H + 8)
   end
end

-- The buttons next to Leave, the first one nearest to it: { { label, key }, ... } with the key that
-- clicking it sends. No list hides them all.
function store:SetActions(list)
   if not self.frame then return end
   list = list or {}
   for index, button in ipairs(self.actions) do
      local action = list[index]
      if action then
         button.key = action[2]
         button:SetText(action[1])
      end
      button:SetShown(action ~= nil)
   end
end

-- Asks to confirm a sale in a small window; answered with the y and n keys (or the buttons).
-- Returns "y", "n" or Esc.
function store:Confirm(text)
   local ui = ns.ui
   if not self.frame then return ui:YesNo(text) end
   self.confirmText:SetText(text)
   self.confirm:Show()
   local answer
   while not answer do
      local key = ui:GetKey()
      if key == "y" or key == "Y" then
         answer = "y"
      elseif key == "n" or key == "N" then
         answer = "n"
      elseif key == ns.ESC or key == " " or key == "ENTER" then
         answer = ns.ESC
      end
   end
   self.confirm:Hide()
   return answer
end

function store:ShowAmount(value)
   self.amountSet = value
   self.amountValueText:SetText(value)
   self.settingAmount = true
   self.amountSlider:SetValue(value)
   self.settingAmount = false
end

-- Asks for a number from 0 to max in a small window: drag the slider, type digits, or press
-- * (all). Returns the number, or -1 if cancelled (as ui:GetNumber).
function store:Amount(text, max)
   local ui = ns.ui
   if not self.frame then return ui:GetNumber(text, max) end
   self.amountText:SetText(text)
   self.amountSlider:SetMinMaxValues(0, math.max(max, 1))
   self.amountMax:SetText(max)
   self.typing = false
   self:ShowAmount(0)
   self.amount:Show()
   local result
   while not result do
      local key = ui:GetKey()
      if key == "*" then
         self.typing = false
         self:ShowAmount(max)
      elseif key == "ENTER" then
         result = self.amountSet
      elseif key == ns.ESC or key == " " then
         result = -1
      elseif key == "BACKSPACE" then
         self:ShowAmount(math.floor(self.amountSet / 10))
      elseif key:match("^%d$") then
         local value = self.typing and self.amountSet * 10 + tonumber(key) or tonumber(key)
         self.typing = true
         self:ShowAmount(math.min(value, max))
      end
   end
   self.amount:Hide()
   return result
end

function store:SetIntro(text)
   if self.frame then self.intro:SetText(text or "") end
end

function store:SetStatus(text)
   if self.frame then self.status:SetText(text or "") end
end

function store:SetNote(text)
   if self.frame then self.note:SetText(text or "") end
end
