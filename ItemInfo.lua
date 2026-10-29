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
local format = string.format

-- How items look in the text, in the way of the WoW item links: [name] in the colour of
-- its quality, and a tooltip that says what it does. The quality comes from what the
-- item is worth.
local ItemInfo = {}
ns.ItemInfo = ItemInfo

local QUALITY = {
   { name = L["Poor"], color = "9d9d9d" },
   { name = L["Common"], color = "ffffff" },
   { name = L["Uncommon"], color = "1eff00" },
   { name = L["Rare"], color = "0070dd" },
   { name = L["Epic"], color = "a335ee" },
   { name = L["Legendary"], color = "ff8000" },
}
local POOR, COMMON, UNCOMMON, RARE, EPIC, LEGENDARY = 1, 2, 3, 4, 5, 6

-- Items that are not in the store, by what they are worth in gold.
local WORTH = {
   [K.OCHEST] = 590, [K.OURN] = 100, [K.OBRASSLAMP] = 500,
}
local ALWAYS = {
   [K.OLARNEYE] = LEGENDARY, [K.OCOOKIE] = POOR, [K.OLANCE] = EPIC, [K.OVORPAL] = EPIC,
   [K.OSLAYER] = EPIC, [K.OHAMMER] = EPIC, [K.OSPHTALISMAN] = EPIC,
}
-- Special weapons: never worth less than this, whatever their enchantment.
local AT_LEAST = { [K.OSWORDofSLASHING] = RARE }
local GEMS = { [K.ODIAMOND] = true, [K.ORUBY] = true, [K.OEMERALD] = true, [K.OSAPPHIRE] = true }
local ENCHANTABLE = {}
for id in pairs(ns.Player.ARMOR_AC) do ENCHANTABLE[id] = true end
for id in pairs(ns.Player.WEAPON_WC) do ENCHANTABLE[id] = true end

-- What the item is worth in gold (the DND store price, 10 gold to the store's unit).
local function Worth(id, arg)
   if GEMS[id] then return arg * 100 end
   for _, entry in ipairs(ns.ItemTables.dnd) do
      if entry[3] == id and ((id ~= K.OPOTION and id ~= K.OSCROLL) or entry[4] == arg) then
         return entry[1] * 10
      end
   end
   return WORTH[id] or 0
end

-- Returns the quality (POOR..LEGENDARY) of an item.
function ItemInfo.quality(id, arg)
   if ALWAYS[id] then return ALWAYS[id] end
   if (id == K.OPOTION and G.potionknown[arg] == 0) or (id == K.OSCROLL and G.scrollknown[arg] == 0) then
      return COMMON  -- (do not give away what it is)
   end
   if GEMS[id] and not G.gemsSold[id] then
      return COMMON  -- (a gem is only known for what it is worth once the bank has bought one of its kind)
   end
   if ENCHANTABLE[id] then  -- armor and weapons go by their enchantment
      local quality = arg < 0 and POOR or arg == 0 and COMMON or arg < 5 and UNCOMMON or RARE
      if AT_LEAST[id] then  -- (a special weapon is a grade better: rare, epic from +5)
         quality = quality >= RARE and EPIC or math.max(quality, AT_LEAST[id])
      end
      return quality
   end
   local worth = Worth(id, arg)
   local quality = worth < 500 and COMMON or worth < 2000 and UNCOMMON or worth < 8000 and RARE or EPIC
   return quality
end

function ItemInfo.color(id, arg)
   return QUALITY[ItemInfo.quality(id, arg)].color
end

-- The text of an item as shown in messages: a link that the message log gives a tooltip.
function ItemInfo.link(id, arg)
   return format("|cff%s|Hwowlarn:%d:%d|h[%s]|h|r", ItemInfo.color(id, arg), id, arg, ns.Player.objectName(id, arg))
end

local POTION = {
   L["Puts you to sleep for a while."], L["Heals a few hit points and cures blindness."],
   L["Raises your level by one."], L["Raises all of your attributes."],
   L["Raises your wisdom."], L["Raises your strength."], L["Raises your charisma."],
   L["Makes you dizzy and unsteady."], L["Raises your intelligence."],
   L["Shows the gold on this level."], L["Shows the monsters on this level."],
   L["Makes you forget some of the map."], L["Tastes like water."],
   L["Blinds you for a while."], L["Confuses you for a while."], L["Makes you a hero for a while."],
   L["Raises your constitution."], L["Gives you giant strength for a while."],
   L["Protects you from fire for a while."], L["Shows the treasure on this level."],
   L["Heals all of your hit points."], L["The cure for your daughter's illness!  Take it home."],
   L["Poison.  It hurts you and may weaken you."], L["Lets you see invisible monsters for a while."],
}
local SCROLL = {
   L["Enchants the armor you wear."], L["Enchants the weapon you wield."],
   L["Lights up and maps the area around you."], L["Blank paper."],
   L["Creates a monster next to you."], L["Creates an object next to you."],
   L["Makes monsters on this level come after you."], L["Moves time ahead, a great deal."],
   L["Teleports you somewhere on this level."], L["Lets you see through the walls for a while."],
   L["Makes the monsters on this level move quickly."], L["Heals the monsters on this level."],
   L["Protects you from spirits for a while."], L["Protects you from the undead for a while."],
   L["Makes monsters less likely to notice you for a while."], L["Maps the level."],
   L["Holds the monsters near you for a while."], L["Perfects the gems you carry."],
   L["Makes your spells last longer."], L["Identifies what an item is."],
   L["Removes curses."], L["Annihilates the monsters around you, and maybe you."],
   L["Blasts the walls and monsters around you."], L["Protects you from dying once."],
}

local MISC = {
   [K.OCOOKIE] = L["Contains a fortune."],
   [K.OBOOK] = L["Read it to learn a spell."],
   [K.OCHEST] = L["Open it to see what is inside.  Heavy."],
   [K.OBRASSLAMP] = L["Rub it, and a genie may appear."],
   [K.OURN] = L["Perhaps something is inside."],
   [K.OLARNEYE] = L["The Eye of Larn.  The bank pays a fortune for it."],
}

-- The special powers of some weapons are found out by seeing them work, once, for all the
-- games (the discoveries are kept with the account).  Until then the tooltip only hints at them.
local POWER = {
   [K.OVORPAL] = L["It can behead the monsters that have a head."],
   [K.OLANCE] = L["It slays what it hits, but is less effective against demons."],
   [K.OSLAYER] = L["It slays demon lords and princes, and they hurt you less."],
   [K.OHANDofFEAR] = L["Monsters sometimes run in fear.  The scare monster spell needs it."],
   [K.ONOTHEFT] = L["Thieves can't steal from you."],
   [K.OSPHTALISMAN] = L["Spheres of annihilation can't harm you."],
   [K.OORBOFDRAGON] = L["Your blows hurt dragons much more."],
   [K.OSPIRITSCARAB] = L["Ghostly monsters hurt you less."],
   [K.OCUBEofUNDEAD] = L["The undead hurt you less, and some will not attack at all."],
   [K.OAMULET] = L["Your invisibility lasts longer."],
   [K.OLARNEYE] = L["Demon lords can't hide from you."],
   [K.OWWAND] = L["You float over pits and trap doors."],
}

-- True if the object has a power that is found out by seeing it work.
function ItemInfo.hasPower(id)
   return POWER[id] ~= nil
end

local session = {}
local function Discoveries()
   return ns.mod and ns.mod.db and ns.mod.db.global.discovered or session
end

function ItemInfo.isDiscovered(id)
   return Discoveries()[id] or false
end

-- Called when the power of an object has just shown itself.
function ItemInfo.discover(id)
   if not POWER[id] or Discoveries()[id] then return end
   Discoveries()[id] = true
   ns.ui:Message(L["You have found out what %s can do!"], ns.Tables.objectname[id])
end

-- The lines of a tooltip: what the item is and does. Returns a list of strings.
function ItemInfo.lines(id, arg)
   local lines = {}
   local quality = QUALITY[ItemInfo.quality(id, arg)]
   lines[#lines + 1] = format("|cff%s%s|r", quality.color, quality.name)
   local armor, weapon = ns.Player.ARMOR_AC[id], ns.Player.WEAPON_WC[id]
   if armor then lines[#lines + 1] = format(L["Armor class %d"], armor + arg) end
   if weapon then lines[#lines + 1] = format(L["Weapon class %d"], weapon + arg) end
   if id == K.OPOTION or id == K.OSCROLL then
      local known = id == K.OPOTION and G.potionknown[arg] or G.scrollknown[arg]
      if known ~= 0 then
         lines[#lines + 1] = (id == K.OPOTION and POTION or SCROLL)[arg]
      else
         lines[#lines + 1] = L["You don't know what it does yet."]
      end
   end
   local effect = not POWER[id] and ns.Equipment.effect(id, arg)
   if effect then
      lines[#lines + 1] = effect
      lines[#lines + 1] = L["Works as long as you carry it."]
   end
   if MISC[id] then lines[#lines + 1] = MISC[id] end
   if POWER[id] and ItemInfo.isDiscovered(id) then lines[#lines + 1] = POWER[id] end
   return lines
end

-- Fills a GameTooltip for an item.
function ItemInfo.tooltip(id, arg)
   GameTooltip:SetText(ns.Player.objectName(id, arg), 1, 1, 1)
   for _, line in ipairs(ItemInfo.lines(id, arg)) do
      GameTooltip:AddLine(line, 1, 1, 1, true)
   end
   GameTooltip:Show()
end

-- What an object on the floor is called when the cursor is over it: only the kind of thing,
-- not what it is (that is for the one who picks it up).
local KIND = {
   [K.OPROTRING] = L["Ring"], [K.ODAMRING] = L["Ring"], [K.OREGENRING] = L["Ring"], [K.ORINGOFEXTRA] = L["Ring"],
   [K.OENERGYRING] = L["Ring"], [K.ODEXRING] = L["Ring"], [K.OSTRRING] = L["Ring"], [K.OCLEVERRING] = L["Ring"],
   [K.OBELT] = L["Belt"], [K.OAMULET] = L["Amulet"], [K.OORB] = L["Orb"], [K.OORBOFDRAGON] = L["Orb"],
   [K.OSPIRITSCARAB] = L["Scarab"], [K.OCUBEofUNDEAD] = L["Cube"], [K.ONOTHEFT] = L["Device"],
   [K.OWWAND] = L["Wand"], [K.OPSTAFF] = L["Staff"], [K.OSCROLL] = L["Scroll"], [K.OPOTION] = L["Potion"],
   [K.OBOOK] = L["Book"], [K.OSWORDofSLASHING] = L["Sword"], [K.OSWORD] = L["Sword"], [K.OSLAYER] = L["Sword"],
   [K.OVORPAL] = L["Sword"], [K.OLANCE] = L["Lance"], [K.OHAMMER] = L["Hammer"],
}

function ItemInfo.groundName(id)
   return KIND[id] or ns.Tables.objectname[id] or "?"
end
