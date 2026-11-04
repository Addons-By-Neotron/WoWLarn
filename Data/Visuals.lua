--[[
**********************************************************************
WoWLarn - Object visuals.
**********************************************************************
Copyright (C) 2026 NeoTron

This file is part of WoWLarn, a World of Warcraft Addon

WoWLarn is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 2 of the License.

WoWLarn is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with WoWLarn.  If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0.html>.

**********************************************************************
]]
local _, ns = ...
local K = ns.K
local L = LibStub("AceLocale-3.0"):GetLocale("WoWLarn")

-- How things are drawn. Every object id has an ASCII glyph (Tables.objglyphs); icons are
-- optional. The icon names are placeholders: they are checked in game and curated later.
local V = {}
ns.Visuals = V

local ICONS = "Interface\\Icons\\"
local IMAGES = "Interface\\AddOns\\WoWLarn\\Media\\Weapons\\"  -- the pictures of the map (transparent, see tools/rotate-images.py)

V.object = {
   [K.OENTRANCE] = { icon = "INV_Misc_Map_01" },
   [K.ODNDSTORE] = { icon = "INV_Sword_04" },
   [K.OSCHOOL] = { icon = "INV_Misc_Book_09" },
   [K.OBANK] = { icon = "INV_Misc_Coin_01" },
   [K.OVOLDOWN] = { icon = "Spell_Fire_SelfDestruct" },
   [K.OHOME] = { icon = "INV_Misc_Key_03" },
   [K.OTRADEPOST] = { icon = "INV_Misc_Bag_08" },
   [K.OLRS] = { icon = "INV_Misc_Note_01" },
   -- items (placeholders)
   [K.OPOTION] = { icon = "INV_Potion_54" },
   [K.OSCROLL] = { icon = "INV_Scroll_03" },
   [K.OBOOK] = { icon = "INV_Misc_Book_09" },
   [K.OCOOKIE] = { icon = "INV_Misc_Food_15" },
   [K.OGOLDPILE] = { icon = "INV_Misc_Coin_01" },
   [K.ODGOLD] = { icon = "INV_Misc_Coin_01" },
   [K.OMAXGOLD] = { icon = "INV_Misc_Coin_01" },
   [K.OKGOLD] = { icon = "INV_Misc_Coin_01" },
   [K.ODIAMOND] = { icon = "INV_Misc_Gem_Diamond_01" },
   [K.ORUBY] = { icon = "INV_Misc_Gem_Ruby_01" },
   [K.OEMERALD] = { icon = "INV_Misc_Gem_Emerald_01" },
   [K.OSAPPHIRE] = { icon = "INV_Misc_Gem_Sapphire_01" },
   [K.OCHEST] = { icon = "INV_Box_01" },
   -- weapons and armor: icons of WoW items of the same sort (from wowhead)
   [K.ODAGGER] = { icon = 135641, image = "dagger" },       -- Worn Dagger
   [K.OSPEAR] = { icon = 135127, image = "spear" },
   [K.OFLAIL] = { icon = 133476, image = "flail" },                     -- Flail
   [K.OBATTLEAXE] = { icon = 132407, image = "battleaxe" },          -- Battle Axe
   [K.OLONGSWORD] = { icon = 135328, image = "longsword" },                -- Longsword
   [K.O2SWORD] = { icon = 135326, image = "2hs" },                   -- Claymore
   [K.OSWORD] = { icon = "INV_Sword_22", image = "sunsword" },                    -- Teebu's Blazing Longsword (the sunsword)
   [K.OSWORDofSLASHING] = { icon = 135346, image = "slash" },          -- Thrash Blade
   [K.OSLAYER] = { icon = 135359, image = "slayer" },                   -- Demonslayer
   [K.OVORPAL] = { icon = 135291, image = "vorpal" },                   -- Dazzling Longsword
   [K.OHAMMER] = { icon = 133066, image = "hammer" },                  -- Maul
   [K.OLANCE] = { icon = 135131, image = "lanceofdeath" },                    -- Dragonslayer's Lance
   [K.OPSTAFF] = { icon = 135157, image = "staffofpower" },                   -- Staff of Jordan
   [K.OBELT] = { icon = "INV_Belt_09" },                      -- Belt of Might
   [K.OLEATHER] = { icon = "INV_Chest_Leather_01" },
   [K.OSTUDLEATHER] = { icon = "INV_Chest_Leather_02" },      -- Bone-studded Leather
   [K.ORING] = { icon = "INV_Chest_Chain_04" },               -- Striker's Ringmail
   [K.OCHAIN] = { icon = "INV_Chest_Chain" },                 -- Chainmail Armor
   [K.OSPLINT] = { icon = "INV_Chest_Plate01" },
   [K.OPLATE] = { icon = "INV_Chest_Plate10" },               -- Heavy Mithril Breastplate
   [K.OPLATEARMOR] = { icon = "INV_Chest_Plate10" },
   [K.OSSPLATE] = { icon = "INV_Chest_Plate10" },
   [K.OELVENCHAIN] = { icon = "INV_Chest_Chain_11" },         -- Earthfury Ringmail
   [K.OSHIELD] = { icon = "INV_Shield_04" },
}

V.GROUND = {
   town = { 0.16, 0.30, 0.12 },
   dungeon = { 0.26, 0.23, 0.20 },
   volcano = { 0.34, 0.15, 0.10 },
   deep = { 0.15, 0.16, 0.24 },
   lava = { 0.50, 0.17, 0.07 },
}
V.WALL = { 0.52, 0.48, 0.43 }
V.GLYPH_COLOR = { 1, 0.9, 0.5 }
V.MISSILE_COLOR = { 0.6, 0.85, 1 }

local ground = {}
function V.Blend(from, to, t)
   for i = 1, 3 do ground[i] = from[i] + (to[i] - from[i]) * t end
   return ground
end

-- The status effects shown in the effects row: the 17 of the C bottom line (botside) and a
-- few more that the C only showed through the stats. The icons are placeholders to curate.
V.EFFECTS = {
   { K.STEALTH, L["Stealth"], "Ability_Stealth" },
   { K.UNDEADPRO, L["Undead protection"], "Spell_Holy_PrayerOfSpirit" },
   { K.SPIRITPRO, L["Spirit protection"], "Spell_Holy_DivineSpirit" },
   { K.CHARMCOUNT, L["Charm"], "Spell_Shadow_Charm" },
   { K.TIMESTOP, L["Time stop"], "Spell_Frost_Stun" },
   { K.HOLDMONST, L["Hold monsters"], "Spell_Nature_Slow" },
   { K.GIANTSTR, L["Giant strength"], "Spell_Nature_Strength" },
   { K.FIRERESISTANCE, L["Fire resistance"], "Spell_Fire_FireArmor" },
   { K.DEXCOUNT, L["Dexterity"], "Spell_Nature_Invisibilty" },
   { K.STRCOUNT, L["Strength"], "Spell_Nature_Strength" },
   { K.SCAREMONST, L["Scare monsters"], "Spell_Shadow_PsychicScream" },
   { K.HASTESELF, L["Haste"], "Spell_Nature_Bloodlust" },
   { K.CANCELLATION, L["Cancellation"], "Spell_Holy_DispelMagic" },
   { K.INVISIBILITY, L["Invisible"], "Ability_Vanish" },
   { K.ALTPRO, L["Protection 3"], "Spell_Holy_PowerWordShield" },
   { K.PROTECTIONTIME, L["Protection 2"], "Spell_Holy_SealOfProtection" },
   { K.WTW, L["Walk through walls"], "Spell_Arcane_Blink" },
   { K.BLINDCOUNT, L["Blind"], "Spell_Shadow_MindSteal" },
   { K.CONFUSE, L["Confused"], "Spell_Shadow_MindBomb" },
   { K.HERO, L["Hero"], "Ability_Warrior_BattleShout" },
   { K.SEEINVISIBLE, L["See invisible"], "Spell_Holy_Heal" },
   { K.AWARENESS, L["Awareness"], "Spell_Holy_MindVision" },
   { K.AGGRAVATE, L["Aggravated"], "Ability_Warrior_Rampage" },
   { K.HALFDAM, L["Half damage"], "Spell_Shadow_CurseOfMannoroth" },
   { K.ITCHING, L["Itching"], "Spell_Nature_NullifyDisease" },
   { K.CLUMSINESS, L["Clumsy"], "Spell_Shadow_CurseOfTounges" },
   { K.HASTEMONST, L["Monsters hasted"], "Spell_Nature_Bloodlust" },
}

-- The effects that hurt rather than help: the ones in the effects row that a scroll of
-- remove curse lifts (Magic.lua, CURSE).
V.CURSE = {
   [K.BLINDCOUNT] = true, [K.CONFUSE] = true, [K.AGGRAVATE] = true, [K.HASTEMONST] = true,
   [K.ITCHING] = true, [K.CLUMSINESS] = true, [K.HALFDAM] = true,
}

-- The pictures of the potions (Media/Potions, by potion id).  An unknown potion is drawn as the
-- generic one (index 0); a known one as itself, also on the floor.
local POTIONS = "Interface\\AddOns\\WoWLarn\\Media\\Potions\\"
local POTION_FILE = {
   [0] = "potion_00_generic", "potion_01_sleep", "potion_02_healing", "potion_03_raise_level",
   "potion_04_increase_ability", "potion_05_wisdom", "potion_06_strength", "potion_07_raise_charisma",
   "potion_08_weakness", "potion_09_learning", "potion_10_gold_detection", "potion_11_monster_detection",
   "potion_12_forgetfulness", "potion_13_water", "potion_14_blindness", "potion_15_confusion",
   "potion_16_heroism", "potion_17_sturdiness", "potion_18_giant_strength", "potion_19_fire_resistance",
   "potion_20_treasure_finding", "potion_21_instant_healing", "potion_22_cure_dianthroritis",
   "potion_23_poison", "potion_24_see_invisible",
}
-- The picture of a scroll: the rolled one until it is known, then the open one.  On the map
-- (opened = false) a scroll still lies rolled until the player has stepped on it (or dropped it).
local SCROLLS = "Interface\\AddOns\\WoWLarn\\Media\\Scrolls\\"
function V.ScrollPicture(arg, opened)
   local known = opened ~= false and arg and arg > 0 and ns.G.scrollknown[arg] ~= 0
   return SCROLLS .. (known and "scroll_01_open_icon.png" or "scroll_00_generic_icon.png")
end

-- The pictures of the gems (Media/Gems).
local GEMS = "Interface\\AddOns\\WoWLarn\\Media\\Gems\\"
local GEM_FILE = {
   [K.ODIAMOND] = "gem_50_diamond_icon.png", [K.ORUBY] = "gem_51_ruby_icon.png",
   [K.OEMERALD] = "gem_52_emerald_icon.png", [K.OSAPPHIRE] = "gem_53_sapphire_icon.png",
}

-- The pictures of the rings (Media/Rings).  Rings are never unidentified in Larn, so each shows
-- its own; the generic one is for a ring that has no picture.
local RINGS = "Interface\\AddOns\\WoWLarn\\Media\\Rings\\"
local RING_FILE = {
   [K.ORINGOFEXTRA] = "ring_01_extra_regeneration", [K.OREGENRING] = "ring_02_regeneration",
   [K.OPROTRING] = "ring_03_protection", [K.OSEQUIP] = "ring_04_energy", [K.ODEXRING] = "ring_05_dexterity",
   [K.OSTRRING] = "ring_06_strength", [K.OCLEVERRING] = "ring_07_cleverness", [K.ODAMRING] = "ring_08_increase_damage",
}
function V.RingPicture(id)
   return RINGS .. (RING_FILE[id] or "ring_00_generic") .. "_icon.png"
end

-- Other objects with a picture of their own (Media/Misc).
local MISC = "Interface\\AddOns\\WoWLarn\\Media\\Misc\\"
local MISC_FILE = { [K.OBOOK] = "misc_00_spell_tome_icon.png" }  -- the spell book

-- Doors (Media/Doors): three looks, wood, stone and iron, closed and open.  Each door keeps its own,
-- picked by a hash of the level and the place of the door.
local DOORS = "Interface\\AddOns\\WoWLarn\\Media\\Doors\\"
local DOOR_KIND = { "wood", "stone", "iron" }
function V.IsDoor(id) return id == K.OCLOSEDDOOR or id == K.OOPENDOOR end
-- The head-on picture of a door: with the stone frame round it for the 2D map, or (leaves) only the
-- leaves, edge to edge, for the 3D view, which builds the frame of the wall's own stone.
function V.DoorPicture(id, level, x, y, leaves)
   local hash = (((level or 0) * 131 + (x or 0)) * 257 + (y or 0)) * 2654435761 % 4294967296
   local kind = DOOR_KIND[math.floor(hash / 65536) % #DOOR_KIND + 1]
   return DOORS .. (id == K.OOPENDOOR and "door_19_" .. kind .. "_open" or "door_20_" .. kind) .. (leaves and "_leaves" or "") .. "_icon.png"
end

-- Objects rendered from several camera angles (30 to 80 degrees in steps of 5): in its folder,
-- <name>_<angle>_icon.png for the 3D view, and <name>_icon.png for the 2D map (no angle).
local MEDIA = "Interface\\AddOns\\WoWLarn\\Media\\"
local ANGLED = {
   -- thrones (a gnome king was found: the same look; the jewels pried off: the massive one)
   [K.OTHRONE] = "Throne\\misc_02_throne", [K.OTHRONE2] = "Throne\\misc_02_throne",
   [K.ODEADTHRONE] = "Throne\\misc_79_massive_throne",
   -- stairs
   [K.OSTAIRSUP] = "Stairs\\stairs_05_stairs_up", [K.OSTAIRSDOWN] = "Stairs\\stairs_13_stairs_down",
   -- piles of gold, by the size of the pile (small to huge: ids 18, 72, 70, 71)
   [K.OGOLDPILE] = "Gold\\gold_18_small", [K.ODGOLD] = "Gold\\gold_72_medium",
   [K.OMAXGOLD] = "Gold\\gold_70_large", [K.OKGOLD] = "Gold\\gold_71_huge",
   -- fountains (the dead one is dry)
   [K.OFOUNTAIN] = "Fountain\\fountain_07_fountain", [K.ODEADFOUNTAIN] = "Fountain\\fountain_17_dead_fountain",
   -- elevators
   [K.OELEVATORUP] = "Elevator\\elevator_06_elevator_up", [K.OELEVATORDOWN] = "Elevator\\elevator_14_elevator_down",
   -- volcano shafts
   [K.OVOLDOWN] = "Volcano\\volcano_55_volcano_down", [K.OVOLUP] = "Volcano\\volcano_56_volcano_up",
   -- the magic mirror
   [K.OMIRROR] = "Mirror\\mirror_11_mirror",
   -- pits and trap doors (the invisible trap door looks the same once it shows)
   [K.OPIT] = "Traps\\trap_04_pit", [K.OTRAPDOOR] = "Traps\\trap_75_trapdoor", [K.OIVTRAPDOOR] = "Traps\\trap_75_trapdoor",
}
-- The picture of an angled object without the folder path and the "_icon.png": the plain one
-- for the 2D map (no angle), else the one that fits the camera angle.
local function AngledName(id, angle)
   if not angle then return ANGLED[id] end
   angle = math.max(30, math.min(80, math.floor(angle / 5 + 0.5) * 5))
   return ANGLED[id] .. "_" .. angle
end
local function AngledPicture(id, angle)
   return MEDIA .. AngledName(id, angle) .. "_icon.png"
end

-- Flat objects that stand on the middle of their tile by the middle of what the picture shows,
-- not by the bottom edge of the frame (the pictures are not centred in their frame, and the
-- thrones are meant to rest on the bottom).  See Data/Anchors.lua, from tools/gen-anchors.py.
local CENTERED = { [K.OSTAIRSDOWN] = true, [K.OSTAIRSUP] = true, [K.OPIT] = true, [K.OTRAPDOOR] = true, [K.OIVTRAPDOOR] = true,
   [K.OFOUNTAIN] = true, [K.ODEADFOUNTAIN] = true,
   [K.OELEVATORUP] = true, [K.OELEVATORDOWN] = true,
   [K.OVOLUP] = true, [K.OVOLDOWN] = true }  -- (the stairs up: by the middle of their round base)

-- Where the middle of what the picture of this object shows is in its frame: its distance from
-- the left as a part of the width, and from the bottom as a part of the height.  Nil for an
-- object that is placed by the bottom edge.
function V.Anchor(id, angle)
   if not CENTERED[id] then return nil end
   local anchor = ns.Anchors and ns.Anchors[AngledName(id, angle)]
   if anchor then return anchor[1], anchor[2] end
end

-- Pictures of things that stand on the floor rather than float over it (they do not bob in the
-- 3D view): the size of each as a part of a tile
-- (it can be more than 1: the picture stands on the floor and reaches up over the tiles behind).
V.STANDING = {
   [K.OTHRONE] = 1.45, [K.OTHRONE2] = 1.45, [K.ODEADTHRONE] = 1.45,
   [K.OSTAIRSUP] = 1.4, [K.OSTAIRSDOWN] = 1.4,  -- (the picture is about 0.65 of its frame wide: about a tile)
   [K.OGOLDPILE] = 0.75, [K.ODGOLD] = 0.75, [K.OMAXGOLD] = 0.75, [K.OKGOLD] = 0.75,  -- (lie on the floor)
   [K.OFOUNTAIN] = 1.2, [K.ODEADFOUNTAIN] = 1.2,  -- (about 0.83 of the frame wide)
   [K.OELEVATORUP] = 1.8, [K.OELEVATORDOWN] = 1.9,  -- (about 0.5 of the frame wide)
   [K.OVOLUP] = 1.2, [K.OVOLDOWN] = 1.5,  -- (0.83 and 0.65 of the frame wide)
   [K.OMIRROR] = 1.45,  -- (a tall thing like the thrones)
   [K.OPIT] = 1.4, [K.OTRAPDOOR] = 1.6, [K.OIVTRAPDOOR] = 1.6,  -- (holes in the floor: 0.7 and 0.55 of the frame wide)
}

-- Objects that lie flat in the floor: in the 3D view their top-down picture (the one without an angle)
-- is laid on the floor like a tile, so it has the perspective of the floor and does not skew
-- as the camera moves.  size: of a tile; box: the part of the picture that shows the object
-- (left, right, top, bottom, as parts of the picture).
V.FLAT = {
   [K.OTRAPDOOR] = { size = 0.85, box = { 59 / 256, 197 / 256, 111 / 256, 249 / 256 } },
   [K.OIVTRAPDOOR] = { size = 0.85, box = { 59 / 256, 197 / 256, 111 / 256, 249 / 256 } },
}

function V.PotionPicture(arg)
   local known = arg and arg > 0 and ns.G.potionknown[arg] ~= 0 and POTION_FILE[arg]
   return POTIONS .. (known or POTION_FILE[0]) .. "_icon.png"
end

-- The icon of a spell by its three letters (for the action bar); the others get a book.
V.SPELL_ICON = {
   pro = "Spell_Holy_PowerWordShield", mle = "Spell_Nature_StarFall", sle = "Spell_Nature_Sleep",
   chm = "Spell_Shadow_Charm", web = "Ability_Ensnare", hel = "Spell_Holy_Heal", inv = "Spell_Magic_LesserInvisibility",
   bal = "Spell_Fire_FlameBolt", cld = "Spell_Frost_FrostNova", has = "Spell_Nature_Bloodlust",
   lit = "Spell_Nature_Lightning", drl = "Spell_Shadow_LifeDrain02", ply = "Spell_Nature_Polymorph",
   hld = "Spell_Frost_ChainsOfIce", tel = "Spell_Arcane_Blink", mfi = "Spell_Fire_Immolation",
   sph = "Spell_Shadow_ShadowWordDominate", sum = "Spell_Shadow_SummonVoidWalker", fgr = "Spell_Holy_Excorcism",
   cbl = "Spell_Holy_RemoveCurse", enl = "Spell_Holy_MindVision", stp = "Spell_Frost_Stun", sca = "Spell_Shadow_PsychicScream",
   lor = "INV_Misc_Book_09",
   ssp = "INV_Spear_05", cre = "Spell_Shadow_SummonImp", pha = "Spell_Shadow_GatherShadows",
   can = "Spell_Holy_DispelMagic", ckl = "Spell_Nature_CorrosiveBreath", vpr = "Spell_Nature_EarthShock",
   dry = "INV_Drink_05", glo = "Spell_Holy_DivineIntervention", flo = "Spell_Frost_SummonWaterElemental",
   gen = "Spell_Shadow_DeathCoil", wtw = "Spell_Shadow_Teleport", alt = "Spell_Arcane_Arcane04",
   per = "Spell_Holy_Aspiration", mkw = "Spell_Nature_EarthBindTotem"
}
-- The spells that put an effect on you have the icon of that effect.
for spell, counter in pairs({ pro = K.PROTECTIONTIME, dex = K.DEXCOUNT, str = K.STRCOUNT }) do
   for _, effect in ipairs(V.EFFECTS) do
      if effect[1] == counter then V.SPELL_ICON[spell] = effect[3] end
   end
end

-- Sets the texture of an icon.  The pictures of the addon are large and shown small, so they
-- get mipmaps (trilinear); the icons of the game are left as they are.
function V.SetIcon(texture, path)
   local ours = type(path) == "string" and path:find("WoWLarn", 1, true)
   texture:SetTexture(path, nil, nil, ours and "TRILINEAR" or nil)
end

function V.ObjectIcon(id, arg)
   if V.IsDoor(id) then return V.DoorPicture(id) end
   if id == K.OPOTION then return V.PotionPicture(arg) end
   if id == K.OSCROLL then return V.ScrollPicture(arg) end
   if GEM_FILE[id] then return GEMS .. GEM_FILE[id] end
   if MISC_FILE[id] then return MISC .. MISC_FILE[id] end
   if ANGLED[id] then return AngledPicture(id) end
   if RING_FILE[id] then return V.RingPicture(id) end
   local visual = V.object[id]
   local icon = visual and visual.icon
   if type(icon) == "number" then return icon end  -- (a file data id)
   return icon and (ICONS .. icon)
end

-- What the map draws for an object: its own picture if it has one (true as the second value:
-- it has its own transparency, and is not cut at the edges like an icon), else its icon.
function V.ObjectPicture(id, arg, opened, angle, x, y)
   if V.IsDoor(id) then return V.DoorPicture(id, ns.G.level, x, y), true end
   if ANGLED[id] then return AngledPicture(id, angle), true end
   if id == K.OPOTION then return V.PotionPicture(arg), true end
   if id == K.OSCROLL then return V.ScrollPicture(arg, opened), true end
   if GEM_FILE[id] then return GEMS .. GEM_FILE[id], true end
   if MISC_FILE[id] then return MISC .. MISC_FILE[id], true end
   if RING_FILE[id] then return V.RingPicture(id), true end
   local visual = V.object[id]
   if visual and visual.image then return IMAGES .. visual.image .. ".png", true end
   return V.ObjectIcon(id, arg), false
end

-- Monsters are drawn as their ASCII letter until they get icons and models (milestone 10).
V.MONSTER_COLOR = { 1, 0.35, 0.3 }
V.PLAYER_COLOR = { 0.3, 1, 0.3 }

-- A list of displays from single numbers and { first, last } ranges.
local function Displays(...)
   local list = {}
   for _, part in ipairs({ ... }) do
      if type(part) == "table" then
         for display = part[1], part[2] do list[#list + 1] = display end
      else
         list[#list + 1] = part
      end
   end
   return list
end

-- Whether the client has a display (some are only in the newer clients).  A display is
-- tried on a model that is never shown; the answer is kept.  One that is not known at once
-- is tried again when its model has loaded, and the map is drawn again then.
-- A display the client does not know is shown as a placeholder model (it has a model file id
-- too), so the file of a display that cannot exist is learned first and counts as "not there".
local usable, probe, missing = {}, nil, nil
local NO_SUCH_DISPLAY = 99999999
local function Has(model)
   local file = model.GetModelFileID and model:GetModelFileID()
   return file ~= nil and file ~= 0 and file ~= missing
end
local function Usable(display)
   if usable[display] ~= nil then return usable[display] end
   if not probe then
      probe = CreateFrame("PlayerModel", nil, UIParent)
      probe:SetSize(8, 8)
      probe:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 100, -100)  -- (off screen)
      probe:SetScript("OnModelLoaded", function(model)
         if model.display == NO_SUCH_DISPLAY then
            missing = model.GetModelFileID and model:GetModelFileID()
         elseif model.display and not usable[model.display] and Has(model) then
            usable[model.display] = true
            ns.ui:Refresh("map")
         end
      end)
      probe.display = NO_SUCH_DISPLAY
      probe:SetDisplayInfo(NO_SUCH_DISPLAY)
      missing = probe.GetModelFileID and probe:GetModelFileID()
   end
   probe.display = display
   if display < 0 then probe:SetModel(-display) else probe:SetDisplayInfo(display) end
   -- (until the placeholder is known, the answer waits for OnModelLoaded)
   usable[display] = (not probe.GetModelFileID) or (missing ~= nil and Has(probe))
   return usable[display]
end

-- Displays to try in turn: { first choices..., backup = { used if none of those is there } }.
local function Prefer(first, backup)
   first.backup = backup
   return first
end

-- The list of displays a monster is shown as: its first choices that the client has, else
-- the backup.
local function Choices(display)
   if type(display) ~= "table" then return { display } end
   if not display.backup then return display end
   local list = {}
   for _, id in ipairs(display) do
      if Usable(id) then list[#list + 1] = id end
   end
   if #list == 0 then return display.backup end
   return list
end

-- The creature display each monster is shown as in the 2.5D view.  V.DISPLAY is the list that
-- goes with the addon; what the player picked in the model viewer (/larn models) is kept in
-- the saved variables and wins.
-- A monster has a display or a list of displays, one of which each monster gets by chance.
V.DISPLAY = {
   -- [monster id] = displayID, or a list of them
   [K.LEMMING] = Displays(1141, 1418),  -- (Rat and Dig Rat)
   [K.JACKAL] = Displays({ 10902, 10903 }, 1536, 2710, 2712, 2713, 2714, 1535, 12966),  -- (the hyena)
   [K.CENTIPEDE] = 15533,
   [K.ANT] = 11096,
   [K.ASSASSINBUG] = 7511,
   [K.BUGBEAR] = 11088,
   [K.JACULI] = Displays(2705, 2703, 10991),
   -- (the demon lords, I to VII: the felguards, the doomguard, a dreadlord)
   [K.DEMONLORD] = 5048,
   [K.DEMONLORD + 1] = 5047,
   [K.DEMONLORD + 2] = 9017,
   [K.DEMONLORD + 3] = 7970,
   [K.DEMONLORD + 4] = 14152,
   [K.DEMONLORD + 5] = Displays(1912, 4426),
   [K.DEMONLORD + 6] = 10543,
   [K.DEMONPRINCE] = 12449,  -- (Lord Kazzak)
   [K.LUCIFER] = 12990,  -- (Echo of Archimonde)
   [K.ELF] = 7874,  -- (Blood Elf Defender)
   [K.SILVERDRAGON] = 6373,  -- (a teal drake)
   [K.GREENDRAGON] = 6375,
   [K.REDDRAGON] = 6376,  -- (Flamescale Drake)
   [K.PLATINUMDRAGON] = 11460,  -- (Azuregos)
   [K.BRONZEDRAGON] = 2719,  -- (Anachronos)
   [K.WHITEDRAGON] = 10585,  -- (a cobalt whelp)
   [K.WATERLORD] = 110,  -- (Baron Aquanis)
   [K.EYE] = 2421,  -- (Eye of Kilrogg)
   [K.LEPRECHAUN] = Prefer({ 61712, 51994 }, { 7109, 7197, 7202, 7203, 7228, 7230, 7234 }),  -- (the treasure goblin, else Venture Co. goblins)
   [K.QUASIT] = 4449,  -- (an imp)
   [K.NYMPH] = Displays(12432, 1825),
   [K.RUSTMONSTER] = Displays(7763, 15436),
   [K.CUBE] = Displays(11141, 4754, 767, 1306, 11137, 1146, 11140, 11139, 682, 11138, 2569, 358, 1145, 2028),
   [K.YETI] = Displays(3206, 10579, 3207),
   [K.ZOMBIE] = Displays({ 10970, 10979 }),
   [K.WRAITH] = Displays(14368, 146),
   [K.POLTERGEIST] = 10728,
   [K.SPIRITNAGA] = 8782,
   [K.VAMPIRE] = 8808,
   [K.VORTEX] = Displays(14525, 5327),
   [K.HELLHOUND] = Displays(11997, 12168),
   [K.CENTAUR] = Displays(9447),
   [K.TROLL] = Displays(5608, 5626, 5605, 5610, 5612, 5607, 5613, 10249, 11442, 3986, 3999, 6487, 6489, 3993, 1157, 6485),
   [K.GREENURCHIN] = 13109,  -- (Phase Lasher)
   [K.XVART] = Displays(506, 391, 486, 11293),  -- (Bluegill and Saltscale murlocs)
   [K.PURPLEWORM] = Displays(7549, 13009),  -- (Murk Worm and Rock Worm)
   [K.MIMIC] = Displays(7763, 15436),  -- (the oozeling: only for its death, it looks like another monster before that, see Display.visibleMonster)
   [K.METAMORPH] = Displays(4629, 7857, 14703),  -- (Haunting Phantasm and the two wraiths)
   [K.FORVALAKA] = Displays(633, 11452),  -- (Shadowmaw panthers)
   [K.ZILLER] = Displays(6087, 2187, 6086, 1531),  -- (Zhevra Runner, Charger, Courser and Tamed Zhevra)
   [K.ICELIZARD] = 8797,  -- (Cold Eye Basilisk)
   [K.UMBERHULK] = 12156,  -- (Hive'Regal Burrower)
   [K.YELLOWMOLD] = 16111,  -- (the Spore, Loatheb)
   [K.VIOLETFUNGI] = Prefer({ 8389 }, { 121735 }),  -- (the Rotting Behemoth, else the Dread Fungus)
   [K.DISENCHANTRESS] = 1937,  -- (Anaya Dawnrunner)
   [K.INVISIBLESTALKER] = 4870,  -- (Restless Shade)
   [K.ROTHE] = Displays(1230, 1308, 1232, 2767, 10914, 1453, 179),  -- (kodos)
   [K.OSEQUIP] = Displays(381, 389, 1208),  -- (boars)
   [K.LAMANOBE] = Displays(6825, 6826, 936, 2000, 1999, 2003),  -- (the Timbermaw furbolgs)
   [K.XORN] = Displays(2169, 2170, 2075),  -- (the stone spirits)
   [K.SHAMBLINGMOUND] = Displays(2023, 713, 2024),  -- (the fen creeper, dweller and lord)
   [K.GNOMEKING] = 7006,  -- (High Tinker Mekkatorque)
   [K.GNOME] = Displays({ 6920, 6931 }),
   [K.KOBOLD] = Displays({ 114157, 114160 }, { 114709, 114718 }),
   [K.HOBGOBLIN] = Displays(30244, { 30261, 30267 }),
   [K.ORC] = Displays({ 9794, 9805 }),
   [K.SNAKE] = Displays(1206, 1986, 2954, 2955, 2957, 4268, 8173, 6303),
   [K.TROGLODYTE] = Displays(160, 606, 611, 721, 722, 723, 726, 730, 763, 764, 1194, 11166, 11609, 11610),
}

-- The sounds of the monsters, by monster id; any of attack, wound, die and special may be
-- left out (the default sound is played, a special attack falls back to the attack sound).
-- A sound is a sound kit name ("LEVELUP"), a sound kit id (888), a list of kit ids (one is
-- played, { 1, 2, 3 }) or { file = file data id }.
V.MONSTER_SOUND = {
   [K.HOBGOBLIN] = { attack = 397, wound = 398, die = 400, special = 396 },  -- (Dunemaul Ogre)
   [K.NYMPH] = { attack = { 6339, 6340, 6341 }, wound = { 6343, 6344, 6345 }, die = { 6346, 6347, 6348 }, special = 6342 },  -- (the wisp voice)
   -- (the demon lords: the doomguard voice, or the dreadlord voice for the felguards)
   [K.DEMONLORD] = { attack = 1091, wound = 1092, die = 1094, special = 1095 },
   [K.DEMONLORD + 1] = { attack = 1098, wound = 1099, die = 1101, special = 1102 },
   [K.DEMONLORD + 2] = { attack = 1091, wound = 1092, die = 1094, special = 1095 },
   [K.DEMONLORD + 3] = { attack = 1098, wound = 1099, die = 1101, special = 1102 },
   [K.DEMONLORD + 4] = { attack = 1098, wound = 1099, die = 1101, special = 1102 },
   [K.DEMONLORD + 5] = { attack = 1098, wound = 1099, die = 1101, special = 1102 },
   [K.DEMONLORD + 6] = { attack = 1091, wound = 1092, die = 1094, special = 1095 },
   [K.LUCIFER] = { attack = 1091, wound = 1092, die = 1094, special = 1095 },  -- (Echo of Archimonde)
   [K.DEMONPRINCE] = { attack = 8092, wound = 8093, die = 8095, special = 8096 },  -- (Lord Kazzak)
   [K.ELF] = { attack = 1307, wound = 1308, die = 1310 },  -- (Blood Elf Defender)
   [K.SILVERDRAGON] = { attack = 4060, wound = 4061, die = 4063, special = 4065 },  -- (Flamescale Drake)
   [K.GREENDRAGON] = { attack = 4060, wound = 4061, die = 4063, special = 4065 },  -- (Flamescale Drake)
   [K.REDDRAGON] = { attack = 4060, wound = 4061, die = 4063, special = 4065 },  -- (Flamescale Drake)
   [K.PLATINUMDRAGON] = { attack = 3520, wound = 3521, die = 3523, special = 3525 },  -- (Azuregos)
   [K.BRONZEDRAGON] = { attack = 3520, wound = 3521, die = 3523, special = 3525 },  -- (Anachronos)
   [K.WHITEDRAGON] = { attack = 429, wound = 430, die = 432, special = 428 },  -- (Cobalt Whelp)
   [K.WATERLORD] = { attack = 1403, wound = 1404, die = 1406, special = 1408 },  -- (Baron Aquanis)
   [K.EYE] = { attack = 8697, wound = 8698, die = 8700, special = { 8580, 8581, 8582, 8583, 8584, 8585, 8586, 8587 } },  -- (C'Thun)
   [K.QUASIT] = { attack = 766, wound = 767, die = 769, special = 770 },  -- (Vicious Grell)
   [K.INVISIBLESTALKER] = { attack = 3419, wound = 3420, die = 3422, special = 3424 },  -- (Restless Shade)
   [K.GREENURCHIN] = { attack = 5045, wound = 5046, die = 5048, special = 5050 },  -- (Phase Lasher)
   [K.XVART] = { attack = 417, wound = 418, die = 420, special = 416 },  -- (Bluegill Warrior)
   [K.PURPLEWORM] = { attack = 5038, wound = 5039, die = 5041, special = 5043 },  -- (Murk Worm)
   [K.MIMIC] = { attack = 721, wound = 722, die = 723, special = 724 },  -- (the ooze sounds, as the cube)
   [K.METAMORPH] = { attack = 3419, wound = 3420, die = 3422, special = 3424 },  -- (Haunting Phantasm)
   [K.FORVALAKA] = { attack = 643, wound = 644, die = 646 },  -- (Shadowmaw Panther)
   [K.ZILLER] = { attack = 725, wound = 726, die = 728, special = 729 },  -- (Zhevra Runner)
   [K.ICELIZARD] = { attack = 565, wound = 567, die = 569, special = 570 },  -- (Cold Eye Basilisk)
   [K.UMBERHULK] = { attack = 1225, wound = 1226, die = 1228, special = 1230 },  -- (Hive'Regal Burrower)
   [K.YELLOWMOLD] = { attack = 8742, wound = 8743, die = 8745 },  -- (the Spore)
   [K.VIOLETFUNGI] = { attack = 456, wound = 459, die = 458, special = 462 },  -- (the Rotting Behemoth)
   [K.DISENCHANTRESS] = { attack = 2933, wound = 2934, die = 2936, special = 23291 },  -- (Anaya Dawnrunner; the reforging sound for disenchanting)
   [K.ROTHE] = { attack = 772, wound = 773, die = 775, special = 771 },  -- (the kodo voice)
   [K.OSEQUIP] = { attack = 380, wound = 381, die = 383, special = 379 },  -- (the boar voice)
   [K.LAMANOBE] = { attack = 355, wound = 358, die = 357, special = 356 },  -- (the furbolg voice)
   [K.XORN] = { attack = 736, wound = 737, die = 738, special = 739 },  -- (the earth elemental voice)
   [K.SHAMBLINGMOUND] = { attack = 456, wound = 459, die = 458, special = 462 },  -- (the bog beast voice)
   [K.GNOMEKING] = { attack = 3275, wound = 3276, die = 3278, special = 7226 },  -- (High Tinker Mekkatorque)
   [K.GNOME] = { attack = 3275, wound = 3276, die = 3278 },  -- (Addled Leper)
   [K.TROLL] = { attack = 3307, wound = 3308, die = 3310 },  -- (a Frostmane troll; tools/npc-sounds.py)
-- (the sounds of one NPC of each kind: attack, injury, death, aggro; tools/npc-sounds.py)
   [K.LEMMING] = { wound = 1379, die = 1380 },  -- (Rat; it has no attack sound, so that is the default bite)
   [K.JACKAL] = { attack = 2506, wound = 2507, die = 2509, special = 2511 },  -- (Bonepaw Hyena)
   [K.SNAKE] = { attack = 4494, wound = 4495, die = 4497, special = 4499 },  -- (Razzashi Cobra)
   [K.KOBOLD] = { attack = 312, wound = 315, die = 314, special = 694 },  -- (Kobold Laborer)
   [K.ORC] = { attack = 1319, wound = 1320, die = 1322 },  -- (Blackrock Grunt)
   [K.CENTIPEDE] = { attack = 715, wound = 716, die = 718, special = 719 },  -- (Vekniss Hive Crawler)
   [K.JACULI] = { attack = 586, wound = 587, die = 589, special = 590 },  -- (Cloud Serpent)
   [K.TROGLODYTE] = { attack = 655, wound = 656, die = 658, special = 659 },  -- (Stonesplinter Skullthumper)
   [K.ANT] = { attack = 715, wound = 716, die = 718, special = 719 },  -- (Silithid Harvester)
   [K.LEPRECHAUN] = { attack = 1409, wound = 1410, die = 1413, special = 1415 },  -- (Venture Co. Operator)
   [K.RUSTMONSTER] = { attack = 721, wound = 722, die = 723, special = 724 },  -- (Oozeling)
   [K.ZOMBIE] = { attack = 1468, wound = 1469, die = 1471, special = 1473 },  -- (Blighted Zombie)
   [K.ASSASSINBUG] = { attack = 715, wound = 716, die = 718, special = 719 },  -- (Beetle)
   [K.BUGBEAR] = { attack = 715, wound = 716, die = 718, special = 719 },  -- (Hive'Zora Wasp)
   [K.HELLHOUND] = { attack = 6814, wound = 6815, die = 6817, special = 6819 },  -- (Core Hound)
   [K.CENTAUR] = { attack = 1040, wound = 1041, die = 1043, special = 1044 },  -- (Galak Centaur)
   [K.YETI] = { attack = 1239, wound = 1240, die = 1242, special = 1243 },  -- (Cave Yeti)
   [K.CUBE] = { attack = 721, wound = 722, die = 723, special = 724 },  -- (Glutinous Ooze)
   [K.VORTEX] = { attack = 3784, wound = 3785, die = 3787, special = 3789 },  -- (Dust Devil)
   [K.WRAITH] = { attack = 3419, wound = 3420, die = 3422, special = 3424 },  -- (Eldreth Wraith)
   [K.VAMPIRE] = { attack = 3364, wound = 3365, die = 3367, special = 3369 },  -- (Vampiric Duskbat)
   [K.POLTERGEIST] = { attack = 1167, wound = 1169, die = 1171, special = 1173 },  -- (Shrieking Banshee)
   [K.SPIRITNAGA] = { attack = 1167, wound = 1169, die = 1171, special = 1173 },  -- (Wailing Banshee)
   -- [K.SNAKE] = { attack = "...", wound = 0, die = { file = 0 } },
}

-- What is set in the model viewer takes effect at once and lasts until the next reload: the
-- values are cleared when the addon loads, so the game starts from the tables in this file
-- (the values are put there by hand).
local function Own(name)
   return ns.mod.db.global[name]
end

V.LOWER = {
   [110] = -0.1,
   [160] = 0.18,
   [358] = 0.34,
   [391] = 0.34,
   [486] = 0.34,
   [506] = 0.34,
   [606] = 0.18,
   [611] = 0.18,
   [633] = 0.32,
   [682] = 0.34,
   [721] = 0.18,
   [722] = 0.18,
   [723] = 0.18,
   [726] = 0.18,
   [730] = 0.18,
   [763] = 0.18,
   [764] = 0.18,
   [767] = 0.34,
   [936] = 0.2,
   [1141] = 0.02,
   [1145] = 0.34,
   [1146] = 0.34,
   [1157] = 0.04,
   [1194] = 0.18,
   [1206] = 0.52,  -- snake
   [1306] = 0.34,
   [1535] = 0.12,
   [1536] = 0.12,
   [1937] = -0.12,
   [1986] = 0.52,
   [1999] = 0.2,
   [2000] = 0.2,
   [2003] = 0.2,
   [2028] = 0.34,
   [2569] = 0.34,
   [2710] = 0.12,
   [2712] = 0.12,
   [2713] = 0.12,
   [2714] = 0.12,
   [2954] = 0.52,
   [2955] = 0.52,
   [2957] = 0.52,
   [3206] = -0.12,
   [3986] = 0.04,
   [3993] = 0.04,
   [3999] = 0.04,
   [4268] = 0.52,
   [4449] = 0.22,
   [4629] = -0.14,
   [4754] = 0.34,
   [5047] = 0.12,
   [5048] = 0.22,
   [5605] = 0.04,
   [5607] = 0.04,
   [5608] = 0.04,
   [5610] = 0.04,
   [5612] = 0.04,
   [5613] = 0.04,
   [5626] = 0.04,
   [6303] = 0.52,
   [6373] = -0.1,
   [6375] = -0.08,
   [6376] = -0.06,
   [6485] = 0.04,
   [6487] = 0.04,
   [6489] = 0.04,
   [6825] = 0.2,
   [6826] = 0.2,
   [6920] = 0.16,
   [6921] = 0.16,
   [6922] = 0.16,
   [6923] = 0.16,
   [6924] = 0.16,
   [6925] = 0.16,
   [6926] = 0.16,
   [6927] = 0.16,
   [6928] = 0.16,
   [6929] = 0.16,
   [6930] = 0.16,
   [6931] = 0.16,
   [7006] = 0.08,
   [7511] = 0.4,
   [7763] = 0.2,
   [7857] = -0.14,
   [7970] = -0.08,
   [8173] = 0.52,
   [8389] = 0.18,
   [8797] = 0.32,
   [9447] = 0.2,
   [10249] = 0.04,
   [10543] = -0.08,
   [10585] = -0.1,
   [10902] = 0.12,
   [10903] = 0.12,
   [10970] = 0.02,
   [10971] = 0.02,
   [10972] = 0.02,
   [10973] = 0.02,
   [10974] = 0.02,
   [10975] = 0.02,
   [10976] = 0.02,
   [10977] = 0.02,
   [10978] = 0.02,
   [10979] = 0.02,
   [11088] = 0.08,
   [11096] = 0.16,
   [11137] = 0.34,
   [11138] = 0.34,
   [11139] = 0.34,
   [11140] = 0.34,
   [11141] = 0.34,
   [11166] = 0.18,
   [11293] = 0.34,
   [11442] = 0.04,
   [11452] = 0.32,
   [11609] = 0.18,
   [11610] = 0.18,
   [11997] = 0.24,
   [12156] = 0.38,
   [12168] = 0.24,
   [12449] = -0.02,
   [12966] = 0.12,
   [12990] = -0.18,
   [14525] = -0.12,
   [14703] = -0.14,
   [15436] = 0.2,
   [15533] = 0.3,
   [30244] = -0.1,
   [30261] = -0.1,
   [30262] = -0.1,
   [30263] = -0.1,
   [30264] = -0.1,
   [30265] = -0.1,
   [30266] = -0.1,
   [30267] = -0.1,
   [114157] = 0.14,
   [114158] = 0.14,
   [114159] = 0.14,
   [114160] = 0.14,
   [114709] = 0.14,
   [114710] = 0.14,
   [114711] = 0.14,
   [114712] = 0.14,
   [114713] = 0.14,
   [114714] = 0.14,
   [114715] = 0.14,
   [114716] = 0.14,
   [114717] = 0.14,
   [114718] = 0.14,
   [121735] = 0.18,
}

-- (what is set in the model viewer wins until the next reload, see Own)
function V.Lower(display)
   local own = Own("lowers")
   return (own and own[display]) or V.LOWER[display] or 0
end

-- Models that are too big or too small for their tile, by display id: how far the camera
-- stands from the model, 1 is the usual; above 1 shrinks the model.  What is set in the model
-- viewer (global.scales) wins.
V.SCALE = {
   [110] = 0.83,
   [146] = 0.68,
   [391] = 1.33,
   [486] = 1.33,
   [506] = 1.33,
   [713] = 1.1,
   [936] = 1.61,
   [1141] = 0.83,
   [1937] = 0.68,
   [1999] = 1.61,
   [2000] = 1.61,
   [2003] = 1.61,
   [2023] = 1.1,
   [2024] = 1.1,
   [2719] = 0.91,
   [3206] = 0.51,
   [3207] = 0.51,
   [4449] = 1.1,
   [4629] = 1.1,
   [5047] = 0.91,
   [5048] = 1.1,
   [5327] = 1.1,
   [6373] = 0.91,
   [6375] = 1.33,
   [6825] = 1.61,
   [6826] = 1.61,
   [6920] = 1.21,
   [6921] = 1.21,
   [6922] = 1.21,
   [6923] = 1.21,
   [6924] = 1.21,
   [6925] = 1.21,
   [6926] = 1.21,
   [6927] = 1.21,
   [6928] = 1.21,
   [6929] = 1.21,
   [6930] = 1.21,
   [6931] = 1.21,
   [7763] = 0.51,
   [7857] = 1.1,
   [7970] = 0.75,
   [8389] = 1.61,
   [9017] = 0.83,
   [9419] = 1.61,
   [9447] = 0.62,
   [9794] = 0.91,
   [10543] = 0.75,
   [10579] = 0.51,
   [10970] = 1.46,
   [10971] = 1.46,
   [10972] = 1.46,
   [10973] = 1.46,
   [10974] = 1.46,
   [10975] = 1.46,
   [10976] = 1.46,
   [10977] = 1.46,
   [10978] = 1.46,
   [10979] = 1.46,
   [11096] = 1.46,
   [11293] = 1.33,
   [11460] = 0.91,
   [11997] = 0.83,
   [12168] = 0.83,
   [12432] = 1.33,
   [12449] = 0.68,
   [12990] = 0.68,
   [14152] = 0.68,
   [14368] = 0.68,
   [14525] = 1.1,
   [14703] = 1.1,
   [15436] = 0.51,
   [15533] = 1.1,
   [30244] = 0.83,
   [30261] = 0.83,
   [30262] = 0.83,
   [30263] = 0.83,
   [30264] = 0.83,
   [30265] = 0.83,
   [30266] = 0.83,
   [30267] = 0.83,
   [114157] = 1.1,
   [114158] = 1.1,
   [114159] = 1.1,
   [114160] = 1.1,
   [114709] = 1.1,
   [114710] = 1.1,
   [114711] = 1.1,
   [114712] = 1.1,
   [114713] = 1.1,
   [114714] = 1.1,
   [114715] = 1.1,
   [114716] = 1.1,
   [114717] = 1.1,
   [114718] = 1.1,
   [121735] = 1.61,
}

function V.Scale(display)
   local own = Own("scales")
   return (own and own[display]) or V.SCALE[display] or 1
end

-- Models that reach beyond their tile (wings, tails), by display id: how many times larger a
-- frame they get, to the sides and up; the model keeps its size (the camera moves back by the
-- same factor).  What is set in the model viewer wins until the next reload (see Own).
V.ROOM = {
   [2024] = 2.5,
   [2703] = 1.5,
   [2705] = 1.5,
   [2719] = 2.5,
   [3206] = 2.5,
   [3207] = 2.5,
   [6373] = 3,
   [6376] = 3,
   [8389] = 2.5,
   [10543] = 3,
   [10579] = 2.5,
   [10991] = 1.5,
   [11096] = 2.5,
   [11460] = 2.5,
   [12990] = 3,
   [15533] = 2.5,
   [16111] = 3,
   [121735] = 2.5,
}

-- Every model gets at least this much room, so wings and tails fit by default.
V.MIN_ROOM = 2

function V.Room(display)
   local own = Own("rooms")
   return math.max(V.MIN_ROOM, (own and own[display]) or V.ROOM[display] or 1)
end

-- What the player says when attacking, hurt and dying, by race (the race file of UnitRace) and
-- sex (2 male, 3 female): { attack = kit, wound = { kits }, die = kit }, from the sounds
-- Human/Dwarf/... Player Attack, Wound, WoundCrit and Death.  A race or kind missing here
-- sounds like the other sex of the race, then like a human of its sex.
V.PLAYER_SOUND = {
   Human = {
      [2] = { attack = 2941, wound = { 2942, 2943 }, die = 2944 },
      [3] = { attack = 2937, wound = { 2938, 2939 }, die = 2940 },
   },
   Dwarf = {
      [2] = { attack = 2929, wound = { 2930, 2931 }, die = 2932 },
      [3] = { attack = 2925, wound = { 2926, 2927 }, die = 2928 },
   },
   NightElf = {
      [2] = { attack = 2956, wound = { 2957, 2958 }, die = 2959 },
      [3] = { attack = 2933, wound = { 2934, 2935 }, die = 2936 },
   },
   Gnome = {
      [2] = { attack = 3275, wound = { 3276, 3277 }, die = 3278 },
      [3] = { attack = 3269, wound = { 3270, 3271 } },
   },
   Orc = {
      [2] = { attack = 1319, wound = { 1320, 1321 }, die = 1322 },
      [3] = { attack = 2960, wound = 2961, die = 213 },
   },
   Tauren = {
      [2] = { attack = 1353, wound = { 1354, 1355 }, die = 1356 },
      [3] = { die = 229 },
   },
   Troll = {
      [2] = { attack = 3307, wound = { 3308, 3309 }, die = 3310 },
      [3] = { attack = 3301, wound = { 3302, 3303 }, die = 3304 },
   },
   Scourge = {
      [2] = { attack = 1315, wound = { 1316, 1317 }, die = 1318 },
      [3] = { attack = 1361, wound = { 1362, 1363 }, die = 1364 },
   },
}

-- The sound of the player for kind ("attack", "wound" or "die"), see PLAYER_SOUND.
function V.PlayerSound(kind)
   local _, race = UnitRace and UnitRace("player")
   local sex = UnitSex and UnitSex("player") == 3 and 3 or 2
   local other = sex == 3 and 2 or 3
   local own = V.PLAYER_SOUND[race]
   local human = V.PLAYER_SOUND.Human
   return (own and own[sex][kind]) or (own and own[other][kind]) or human[sex][kind]
end

-- How far to turn a model in the model viewer and the zoo, by display id, in radians: to see
-- how wide it is from the side, for its room (the game turns them as it wants).  What is set
-- in the model viewer wins until the next reload (see Own).
V.TURN = {
   [110] = 5.235,
   [633] = 2.096,
   [1937] = 6.278,
   [6087] = 0.262,
   [6303] = 4.973,
   [11452] = 2.096,
   [12156] = 4.187,
   [15533] = 6.278,
}

function V.Turn(display)
   local own = Own("turns")
   return (own and own[display]) or V.TURN[display] or 0
end

-- Monsters that go by another name than in the original (design.md, open decision 2).  The
-- id and the rules stay those of the original monster.
V.MONSTER_NAME = {
   [K.LEMMING] = L["rat"],
   [K.GNOME] = L["leper gnome"],
   [K.YELLOWMOLD] = L["fungal spore"],
   [K.ZILLER] = L["zhevra"],
   [K.XVART] = L["bluegill warrior"],
   [K.GREENURCHIN] = L["phase lasher"],
   [K.PURPLEWORM] = L["Giant Worm"],
   [K.FORVALAKA] = L["black panther"],
   [K.METAMORPH] = L["phantasm"],
   [K.JACKAL] = L["hyena"],
   [K.CENTIPEDE] = L["hive crawler"],
   [K.ANT] = L["silithid harvester"],
   [K.BUGBEAR] = L["hornet"],
   [K.JACULI] = L["cloud serpent"],
   [K.LEPRECHAUN] = L["treasure goblin"],
   [K.QUASIT] = L["imp"],
   [K.NYMPH] = L["sprite"],
   [K.RUSTMONSTER] = L["rust oozeling"],
   [K.CUBE] = L["corrosive ooze"],
   [K.VAMPIRE] = L["vampire bat"],
   [K.SPIRITNAGA] = L["banshee"],
   [K.HELLHOUND] = L["core hound"],
   [K.ELF] = L["blood elf"],
   [K.LAMANOBE] = L["Timbermaw Warrior"],
   [K.OSEQUIP] = L["dire boar"],
   [K.ROTHE] = L["kodo"],
   [K.WHITEDRAGON] = L["azure whelp"],  -- (a whelp, not a dragon)
   [K.SILVERDRAGON] = L["silver drake"],  -- (drake models)
   [K.GREENDRAGON] = L["green drake"],
   [K.REDDRAGON] = L["red drake"],
}
for id, name in pairs(V.MONSTER_NAME) do
   ns.MonsterData[id].name = name
end
for _, data in pairs(ns.MonsterData) do
   data.name = ns.TitleCase(data.name)
end

-- Armour class changed from the original: the higher it is, the easier the monster is to hit.
-- The rats (armour class 0) took 10 to 20 swings early on.
V.MONSTER_AC = {
   [K.LEMMING] = 6,
}
for id, ac in pairs(V.MONSTER_AC) do
   ns.MonsterData[id].armorclass = ac
end

-- How far the camera stands from the model of the player, by race (the client fits any model
-- to the frame, so the short races look as tall as the tall ones): above 1 shrinks the model.
V.RACE_SCALE = {
   Gnome = 1.45, Mechagnome = 1.45, Goblin = 1.35, Vulpera = 1.5, Dwarf = 1.15, DarkIronDwarf = 1.15,
   EarthenDwarf = 1.15, Pandaren = 0.95, Orc = 0.97, MagharOrc = 0.97, Troll = 0.95, ZandalariTroll = 0.9,
   Draenei = 0.92, LightforgedDraenei = 0.92, Tauren = 0.85, HighmountainTauren = 0.85, Worgen = 0.95,
   KulTiran = 0.95, Dracthyr = 0.95,
}
function V.PlayerScale()
   local token = UnitRace and select(2, UnitRace("player"))
   return V.RACE_SCALE[token] or 1
end

-- The display of a monster; look is the number it was given by chance (Draw: G.look).
function V.MonsterDisplay(id, look)
   local own = Own("displays")
   local display = (own and own[id]) or V.DISPLAY[id]
   if display == nil then return nil end
   local list = Choices(display)
   return list[((look or 1) - 1) % #list + 1]
end

-- All the displays a monster can have, the backup too: the one chosen in the model viewer,
-- or its list.
function V.DisplayList(id)
   local own = Own("displays")
   local display = (own and own[id]) or V.DISPLAY[id]
   if type(display) ~= "table" then return display and { display } or {} end
   local list = { unpack(display) }
   for _, backup in ipairs(display.backup or {}) do list[#list + 1] = backup end
   return list
end

function V.MonsterGlyph(id)
   return ns.Tables.monstglyphs:sub(id + 1, id + 1)
end

function V.ObjectGlyph(id)
   return ns.Tables.objglyphs:sub(id + 1, id + 1)
end

function V.ClassIcon(class)
   return ICONS .. class.icon
end

-- Textures of the ground, walls and lava: file data ids, by region and slot.  A tile takes one of
-- the list by chance (the same one every time).  They are picked from the dungeon and tileset
-- textures of the game (checked by the listfile, not by eye: /larn tex, in debug builds, steps
-- through the neighbours of an id to find better ones).  With "Textured ground" off, and in ASCII
-- mode, the flat colours above are drawn.
-- One floor and one wall texture for each level (several would look messy): the region's, unless
-- the level has its own in V.LEVEL_TEXTURES[level] = { floor =, wall =, lava = }.
V.TEXTURES = {
   town = { floor = 127725, wall = 127095 },  -- (cobblestone, grey stone)
   dungeon = { floor = 127718, wall = 128406 },  -- (stone floor, rock wall)
   volcano = { floor = 127717, wall = 128402, lava = 186942 },  -- (rock floor, lava rock, lava)
}
V.LEVEL_TEXTURES = {
}

-- The region a level is in: "town", "dungeon" or "volcano".
function V.Region(level)
   if level == 0 then return "town" end
   return level > K.DBOTTOM and "volcano" or "dungeon"
end

local function Hash(x, y, salt)
   local h = (x * 73856093 + y * 19349663 + salt * 83492791) % 2147483647
   h = (h * 1103515245 + 12345) % 2147483647
   return h / 2147483647
end
V.Hash = Hash

-- The texture of a level for a slot ("floor", "wall" or "lava"): a file data id, or nil if there is
-- none (or the setting is off).
function V.Texture(level, slot)
   local profile = ns.mod.db.profile
   if profile.textures == false or profile.ascii then return nil end
   local own = ns.mod.db.global.textures
   local mine = V.LEVEL_TEXTURES[level]
   return (own and own[level .. slot]) or (mine and mine[slot]) or V.TEXTURES[V.Region(level)][slot]
end

-- Some of the walls of the volcano are lava instead (nothing changes in the game: it is still a
-- wall, and keeps the walker out).  The same every time, in clumps; never on the border of the
-- level.  Returns "lava" or nil.
function V.WallVariant(level, x, y)
   if V.Region(level) ~= "volcano" then return nil end
   if x <= 2 or y <= 2 or x >= K.MAXX - 1 or y >= K.MAXY - 1 then return nil end
   local clump = Hash(math.floor(x / 3), math.floor(y / 3), level + 11)
   if clump < 0.28 and Hash(x, y, level + 5) < 0.85 then return "lava" end
   return nil
end

-- What a texture is tinted by, to match the colour of the ground of the level (the textures are
-- bright, and the ground colours are dark and different in each region).
function V.Tint(level)
   local g = V.Ground(level)
   local top = math.max(g[1], g[2], g[3], 0.01)
   return { g[1] / top * 0.9, g[2] / top * 0.9, g[3] / top * 0.9 }
end

-- The dungeon ground gets darker and bluer with depth, the volcano redder.
function V.Ground(level)
   if level == 0 then return V.GROUND.town end
   local depth
   if level > K.DBOTTOM then
      depth = (level - K.DBOTTOM - 1) / (K.VBOTTOM - K.DBOTTOM - 1)
      return V.Blend(V.GROUND.volcano, V.GROUND.lava, depth)
   end
   depth = (level - 1) / (K.DBOTTOM - 1)
   return V.Blend(V.GROUND.dungeon, V.GROUND.deep, depth)
end
