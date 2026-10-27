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

-- Explains what the things you carry do. In Ularn rings, belts and the artifacts work as
-- long as they are in the pack, and there is no limit on how many of them add up, so the
-- inventory shows which items are in effect and what they come to.
local Equipment = {}
ns.Equipment = Equipment

local c, iven, ivenarg = G.c, G.iven, G.ivenarg
local format = string.format

-- What an item does. Each entry gives the short text for the row and the lines of the
-- tooltip; arg is the enchantment of the item.
local EFFECTS = {
   [K.OPROTRING] = function(arg) return format(L["+%d armor class"], arg + 1) end,
   [K.ODAMRING] = function(arg) return format(L["+%d weapon class"], arg + 1) end,
   [K.OBELT] = function(arg) return format(L["+%d weapon class"], arg * 2 + 2) end,
   [K.OREGENRING] = function(arg) return format(L["+%d regeneration"], arg + 1) end,
   [K.ORINGOFEXTRA] = function(arg) return format(L["+%d regeneration"], 5 * (arg + 1)) end,
   [K.OENERGYRING] = function(arg) return format(L["+%d spell energy"], arg + 1) end,
   [K.ODEXRING] = function(arg) return format(L["+%d dexterity"], arg + 1) end,
   [K.OSTRRING] = function(arg) return format(L["+%d strength"], arg + 1) end,
   [K.OCLEVERRING] = function(arg) return format(L["+%d intelligence"], arg + 1) end,
   [K.OHAMMER] = function() return L["+10 strength and dexterity, -10 intelligence"] end,
   [K.OSWORDofSLASHING] = function() return L["+5 dexterity"] end,
   [K.OSLAYER] = function() return L["+10 intelligence"] end,
   [K.OPSTAFF] = function() return L["+10 wisdom"] end,
   [K.OORB] = function() return L["Expanded awareness"] end,
   [K.OORBOFDRAGON] = function() return L["Protects against dragons"] end,
   [K.OSPIRITSCARAB] = function() return L["Protects against spirits"] end,
   [K.OCUBEofUNDEAD] = function() return L["Protects against the undead"] end,
   [K.ONOTHEFT] = function() return L["Thieves cannot steal from you"] end,
   [K.OAMULET] = function() return L["Strengthens invisibility"] end,
   [K.OHANDofFEAR] = function() return L["Monsters run in fear"] end,
   [K.OSPHTALISMAN] = function() return L["Protects against spheres of annihilation"] end,
   [K.OWWAND] = function() return L["You float over pits"] end,
   [K.OLARNEYE] = function() return L["You see the demon lords"] end,
}
-- The ones whose effect the status line can say in a few words.
local SHORT = {
   [K.OPROTRING] = true, [K.ODAMRING] = true, [K.OBELT] = true, [K.OREGENRING] = true,
   [K.ORINGOFEXTRA] = true, [K.OENERGYRING] = true, [K.ODEXRING] = true, [K.OSTRRING] = true,
   [K.OCLEVERRING] = true, [K.OSWORDofSLASHING] = true,
}

-- The effect text of a passive item, or nil.
function Equipment.effect(id, arg)
   return EFFECTS[id] and EFFECTS[id](arg)
end

-- True if the item does something just by being carried.
function Equipment.isPassive(id)
   return EFFECTS[id] ~= nil
end

-- What the worn armor, shield or wielded weapon adds (C: recalc()).
local function WornBonus(slot)
   local id, arg = iven[slot], ivenarg[slot]
   if c[K.WEAR] == slot or c[K.SHIELD] == slot then
      local base = ns.Player.ARMOR_AC[id]
      if base then return format(L["+%d armor class"], base + arg) end
   elseif c[K.WIELD] == slot then
      local base = ns.Player.WEAPON_WC[id]
      if base then return format(L["+%d weapon class"], base + arg) end
   end
end

-- A few words for the row of the inventory: what the slot adds right now.
function Equipment.short(slot)
   local id, arg = iven[slot], ivenarg[slot]
   if id == 0 then return nil end
   if SHORT[id] then return EFFECTS[id](arg) end
   if EFFECTS[id] then return L["in effect"] end
   return WornBonus(slot)
end

-- What a slot adds right now because it is worn or wielded (the rest is in ItemInfo).
function Equipment.lines(slot)
   local id, arg = iven[slot], ivenarg[slot]
   local lines = {}
   local worn = WornBonus(slot)
   if worn then lines[#lines + 1] = worn end
   return lines
end

-- The totals of everything carried and worn, in lines of the form "armor class 14 (...)".
function Equipment.summary()
   local armor, shield, rings, damage, belts = 0, 0, 0, 0, 0
   local strength, dexterity, intelligence, wisdom = 0, 0, 0, 0
   local wear, shieldSlot, wield = c[K.WEAR], c[K.SHIELD], c[K.WIELD]
   if wear > 0 then armor = (ns.Player.ARMOR_AC[iven[wear]] or 0) + ivenarg[wear] end
   if shieldSlot > 0 and iven[shieldSlot] == K.OSHIELD then shield = 2 + ivenarg[shieldSlot] end
   local weapon = 0
   if wield > 0 then weapon = (ns.Player.WEAPON_WC[iven[wield]] or 0) + ivenarg[wield] end
   local artifacts, seen = {}, {}
   for i = 1, K.IVENSIZE do
      local id, arg = iven[i], ivenarg[i]
      if id == K.OPROTRING then
         rings = rings + arg + 1
      elseif id == K.ODAMRING then
         damage = damage + arg + 1
      elseif id == K.OBELT then
         belts = belts + arg * 2 + 2
      elseif id == K.OSTRRING then
         strength = strength + arg + 1
      elseif id == K.ODEXRING then
         dexterity = dexterity + arg + 1
      elseif id == K.OCLEVERRING then
         intelligence = intelligence + arg + 1
      elseif id == K.OHAMMER then
         strength, dexterity, intelligence = strength + 10, dexterity + 10, intelligence - 10
      elseif id == K.OSWORDofSLASHING then
         dexterity = dexterity + 5
      elseif id == K.OSLAYER then
         intelligence = intelligence + 10
      elseif id == K.OPSTAFF then
         wisdom = wisdom + 10
      end
      if EFFECTS[id] and not SHORT[id] and id ~= K.OHAMMER and id ~= K.OSLAYER and id ~= K.OPSTAFF and not seen[id] then
         seen[id] = true
         artifacts[#artifacts + 1] = ns.Tables.objectname[id]
      end
   end

   local lines = {}
   lines[#lines + 1] = format(L["Armor class %d: armor %d, shield %d, rings %d, spells %d"],
      c[K.AC], armor, shield, rings, c[K.MOREDEFENSES])
   lines[#lines + 1] = format(L["Weapon class %d: weapon %d, rings %d, belts %d, other %d"],
      c[K.WCLASS], weapon, damage, belts, c[K.MOREDAM])
   lines[#lines + 1] = format(L["Regeneration %d, spell energy %d"], c[K.REGEN], c[K.ENERGY])
   local stats = {}
   for _, entry in ipairs({ { strength, L["strength"] }, { dexterity, L["dexterity"] },
      { intelligence, L["intelligence"] }, { wisdom, L["wisdom"] } }) do
      if entry[1] ~= 0 then stats[#stats + 1] = format("%+d %s", entry[1], entry[2]) end
   end
   if #stats > 0 then lines[#lines + 1] = L["From items:"] .. " " .. table.concat(stats, ", ") end
   if #artifacts > 0 then lines[#lines + 1] = L["Artifacts:"] .. " " .. table.concat(artifacts, ", ") end
   return lines
end
