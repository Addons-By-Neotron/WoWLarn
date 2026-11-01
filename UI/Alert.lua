--[[
**********************************************************************
WoWLarn - A warning that has to be answered, so a held key does not carry on through it.
**********************************************************************
Copyright (C) 2026 NeoTron

**********************************************************************
]]
local L = LibStub("AceLocale-3.0"):GetLocale("WoWLarn")
local _, ns = ...

local alert = {}
ns.alert = alert

local WIDTH, HEIGHT = 380, 130

function alert:Create(parent)
   local frame = ns.CreatePanel(parent, nil, { 0.12, 0.02, 0.02, 0.97 })
   frame:SetFrameStrata("FULLSCREEN_DIALOG")
   frame:SetSize(WIDTH, HEIGHT)
   frame:SetPoint("CENTER")
   frame:EnableMouse(true)
   frame:Hide()
   self.frame = frame

   local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   title:SetPoint("TOP", 0, -12)
   title:SetTextColor(1, 0.3, 0.3)
   title:SetText(L["Warning"])

   self.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   self.text:SetPoint("TOPLEFT", 16, -40)
   self.text:SetPoint("TOPRIGHT", -16, -40)
   self.text:SetJustifyH("CENTER")
   self.text:SetWordWrap(true)

   local ok = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   ok:SetSize(90, 24)
   ok:SetPoint("BOTTOM", 0, 12)
   ok:SetText(L["OK"])
   ok:SetScript("OnClick", function() ns.ui:InjectKey("ENTER") end)
   return frame
end

function alert:Show(text)
   self.text:SetText(text)
   self.frame:Show()
end

function alert:Hide()
   if self.frame then self.frame:Hide() end
end
