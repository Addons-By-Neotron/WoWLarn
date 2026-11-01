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
local HEADER_H, INTRO_H, TEXT_H, FOOTER_H = 24, 54, 250, 44

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

   -- leave the building (the same as Esc) and page through a long list ("<" and ">" are the
   -- keys the game code listens for)
   local function Key(key)
      ns.main:SetFocus(true)
      ns.ui:InjectKey(key)
   end
   local leave = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   leave:SetSize(70, 20)
   leave:SetPoint("TOPRIGHT", -6, -4)
   leave:SetText(L["Leave"])
   leave:SetScript("OnClick", function() Key(ns.ESC) end)
   self.leave = leave
   self.pager = CreateFrame("Frame", nil, frame)
   self.pager:SetSize(120, 20)
   self.pager:SetPoint("RIGHT", leave, "LEFT", -8, 0)
   self.pager:Hide()
   local previous = CreateFrame("Button", nil, self.pager, "UIPanelButtonTemplate")
   previous:SetSize(24, 20)
   previous:SetPoint("LEFT")
   previous:SetText("<")
   previous:SetScript("OnClick", function() Key("<") end)
   local following = CreateFrame("Button", nil, self.pager, "UIPanelButtonTemplate")
   following:SetSize(24, 20)
   following:SetPoint("RIGHT")
   following:SetText(">")
   following:SetScript("OnClick", function() Key(">") end)
   self.pageText = self.pager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   self.pageText:SetPoint("LEFT", previous, "RIGHT")
   self.pageText:SetPoint("RIGHT", following, "LEFT")

   self.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   self.status:SetPoint("BOTTOMLEFT", 8, 26)
   self.status:SetPoint("BOTTOMRIGHT", -8, 26)
   self.status:SetJustifyH("LEFT")
   self.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   self.note:SetPoint("BOTTOMLEFT", 8, 6)
   self.note:SetPoint("BOTTOMRIGHT", -8, 6)
   self.note:SetJustifyH("LEFT")

   self.rows = {}
   for index = 1, COLUMNS * ROWS do
      local button = CreateFrame("Button", nil, frame)
      button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
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

-- rows: { key = "a", text = "...", price = "...", icon = object id, arg = its argument (the
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
         button.key, button.tip, button.id, button.arg = row.key, row.tip, row.icon, row.arg or 0
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

function store:SetIntro(text)
   if self.frame then self.intro:SetText(text or "") end
end

function store:SetStatus(text)
   if self.frame then self.status:SetText(text or "") end
end

function store:SetNote(text)
   if self.frame then self.note:SetText(text or "") end
end
