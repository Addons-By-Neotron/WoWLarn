--[[
**********************************************************************
WoWLarn - Game thread and the UI request API.
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
local L = LibStub("AceLocale-3.0"):GetLocale("WoWLarn")
local _, ns = ...

-- The game logic runs in one coroutine (design.md section 4). Every blocking call
-- below yields until the UI delivers an answer, so ported C code reads like the C.
-- Never wrap game logic in pcall/xpcall: Lua 5.1 cannot yield across them.

local ESC = "ESC"
ns.ESC = ESC

local ui = {}
ns.ui = ui
ui.repcount = 0  -- C: yrepcount, a repeat count typed before a command
ui.dirty = {}

-- C: main.c:parse. Direction numbers match the C (1 south, 2 east, 3 north, 4 west,
-- 5 northeast, 6 northwest, 7 southeast, 8 southwest).
local DIRECTION = {
   j = 1, l = 2, k = 3, h = 4, u = 5, y = 6, n = 7, b = 8,
   DOWN = 1, RIGHT = 2, UP = 3, LEFT = 4,
}
local ARROW_COMMAND = { UP = "k", DOWN = "j", LEFT = "h", RIGHT = "l" }

----------------------------------------------------------------
-- Coroutine plumbing
----------------------------------------------------------------

function ui:IsActive()
   return self.co ~= nil
end

function ui:NewGame()
   ns.scoreboard:Hide()
   self.co = coroutine.create(ns.Game.Run)
   self.wait = nil
   ns.prompt:Clear()
   self:Resume()
end

-- Runs the game until it next waits for input (or ends).
function ui:Resume(...)
   local co = self.co
   if not co or coroutine.status(co) ~= "suspended" then return end
   self.wait = nil
   local ok, err = coroutine.resume(co, ...)
   if not ok then
      self.co = nil
      ns.prompt:Clear()
      self:Log("system", L["The game crashed. Press any key to start over."])
      geterrorhandler()(err)
   elseif coroutine.status(co) == "dead" then
      self.co = nil
      ns.prompt:Clear()
   end
end

-- The only input path: the keyboard, buttons and (later) clicks all end up here.
function ui:InjectKey(key)
   if self.wait == "key" then
      self:Resume(key)
   elseif not self.co then
      self:NewGame()
   end
   -- Otherwise the game is napping: input is dropped.
end

local function Wait(self, kind)
   self:Flush()
   self.wait = kind
   return coroutine.yield()
end

----------------------------------------------------------------
-- Output
----------------------------------------------------------------

function ui:Log(category, fmt, ...)
   ns.log:Add(select("#", ...) > 0 and format(fmt, ...) or fmt, category)
end

-- C: lprintf/lprcat to the message area.
function ui:Message(fmt, ...)
   self:Log("info", fmt, ...)
end

-- Plays one of the sounds of the game; the sound kits are looked up by name, and the game
-- goes quiet if the client does not have one.
-- name = { sound kit name, sound kit id }; change the pair to change the sound (/larn sounds
-- plays them all, one after the other).
local SOUND = {
   levelup = { "LEVELUP", 888 },
   gold = { "LOOT_WINDOW_COIN_SOUND", 120 },
   coin = { "IG_BACKPACK_COIN_OK", 865 },
   pickup = { "PICK_UP_GEMS", 1221 },
   drop = { "PUT_DOWN_GEMS", 1204 },
   door = { "IG_BACKPACK_OPEN", 862 },
   stuck = { "IG_BACKPACK_COIN_CANCEL", 866 },
   potion = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856 },
   scroll = { "IG_SPELLBOOK_OPEN", 829 },
   cast = { "IG_ABILITY_PAGE_TURN", 836 },
   swing = { "IG_CREATURE_NEUTRAL_SELECT", 871 },
   hit = { "IG_ABILITY_ICON_DROP", 838 },
   bite = { "IG_CREATURE_AGGRO_SELECT", 873 },
   hurt = { "IG_PLAYER_INVITE", 880 },
   kill = { "IG_QUEST_LIST_COMPLETE", 878 },
   level = { "IG_QUEST_LIST_OPEN", 875 },
   death = { "GS_CHARACTER_SELECTION_DEL_CHARACTER", 810 },
   win = { "UI_AUTO_QUEST_COMPLETE", 23404 },
}
local SOUND_ORDER = { "levelup", "gold", "coin", "pickup", "drop", "door", "stuck", "potion", "scroll", "cast",
   "swing", "hit", "bite", "hurt", "kill", "level", "death", "win" }

-- A colored glow under the player (2.5D view): spells, potions and scrolls.
local FLASH = {
   cast = { 0.4, 0.7, 1 }, potion = { 0.4, 1, 0.5 }, scroll = { 1, 0.9, 0.4 }, levelup = { 1, 0.85, 0.2 },
}

local function Play(sound)
   if not sound or not PlaySound or ns.mod.db.profile.sound == false then return end
   if type(sound) == "table" then
      if type(sound[1]) == "number" then  -- { sound kit id, ... }: one of them
         PlaySound(sound[math.random(#sound)])
      elseif sound.file then  -- { file = file data id }
         if PlaySoundFile then PlaySoundFile(sound.file, "SFX") end
      else  -- { sound kit name, sound kit id }
         PlaySound((SOUNDKIT and SOUNDKIT[sound[1]]) or sound[2])
      end
   elseif type(sound) == "string" then  -- a sound kit name
      if SOUNDKIT and SOUNDKIT[sound] then PlaySound(SOUNDKIT[sound]) end
   else  -- a sound kit id
      PlaySound(sound)
   end
end

ui.Play = Play  -- (the model viewer tries sound kits)

function ui:Sound(name)
   if FLASH[name] then ns.map3d:Flash(FLASH[name]) end
   Play(name and SOUND[name])
end

-- What the monsters sound like (Visuals.MONSTER_SOUND): kind is "attack", "wound", "die" or
-- "special"; a monster without a sound of its own for it gets the default one.
-- (a human man's attack, wound and death sounds, see Visuals.PLAYER_SOUND)
local HUMAN = ns.Visuals.PLAYER_SOUND.Human[2]
local MONSTER_SOUND_DEFAULT = { attack = HUMAN.attack, wound = HUMAN.wound, die = HUMAN.die, special = HUMAN.attack }
function ui:MonsterSound(kind, monster)
   local own = monster and ns.Visuals.MONSTER_SOUND[monster]
   local sound = own and (own[kind] or (kind == "special" and own.attack))
   if sound then
      Play(sound)
   else
      Play(MONSTER_SOUND_DEFAULT[kind])
   end
end

-- The voice of the player (Visuals.PlayerSound): kind is "attack", "wound" or "die".
function ui:PlayerSound(kind)
   Play(ns.Visuals.PlayerSound(kind))
end

-- /larn sounds: plays every sound with its name.
function ui:TestSounds()
   for index, name in ipairs(SOUND_ORDER) do
      C_Timer.After((index - 1) * 1.2, function()
         ns.mod:info(name)
         self:Sound(name)
      end)
   end
end

-- C: bottomline(), showcell(), draws(). what is "map", "stats" or "all". Redraws are
-- batched and happen when the game thread next waits.
function ui:Refresh(what)
   if what == "all" then
      self.dirty.map, self.dirty.stats, self.dirty.inv = true, true, true
   else
      self.dirty[what] = true
   end
end

function ui:Flush()
   local dirty = self.dirty
   if dirty.map then
      dirty.map = nil
      ns.map:Draw()
      ns.side:UpdateMinimap()
   end
   if dirty.stats then
      dirty.stats = nil
      ns.side:UpdateStats()
   end
   if dirty.inv then
      dirty.inv = nil
      ns.inventory:Update()
   end
end

-- Model animations of the 2.5D view: kind is "hit", "bite", "wound", "die" or "hurt" (see
-- map3d:Animate); x, y the tile involved.
local ANIMATION_SOUND = { hit = "swing", hurt = "hurt" }  -- (the player has a voice: PlayerSound)
local MONSTER_KIND = { bite = "attack", wound = "wound", die = "die", special = "special" }
function ui:Animate(kind, x, y, monster, fromY)
   if MONSTER_KIND[kind] then
      self:MonsterSound(MONSTER_KIND[kind], monster or ns.G.mon[x][y])
   elseif kind == "hit" then
      self:PlayerSound("attack")
   elseif kind == "hurt" then
      self:PlayerSound(ns.G.c[ns.K.HP] <= 0 and "die" or "wound")
   else
      self:Sound(ANIMATION_SOUND[kind])
   end
   if kind == "special" then return end
   ns.map3d:Animate(kind, x, y, monster, fromY)
end

-- C: nap(). Pauses the game thread; "fast" mode skips it.
function ui:Nap(ms)
   if ms <= 0 or ns.mod.db.profile.fast then return end
   local co = self.co
   C_Timer.After(ms / 1000, function()
      if self.co == co and self.wait == "nap" then
         self:Resume()
      end
   end)
   Wait(self, "nap")
end

----------------------------------------------------------------
-- Input requests
----------------------------------------------------------------

function ui:GetKey()
   return Wait(self, "key")
end

-- C: yylex(). Returns the command character. Digits typed first set a repeat count, the
-- command then repeats; game code sets ui.repcount = 0 to cancel (a hit, a wall).
-- Esc releases the keyboard.
function ui:GetCommand()
   local G = ns.G
   if G.hit2flag then
      G.hit2flag = false
      self.repcount = 0
      return " "
   end
   if self.repcount > 0 then
      self.repcount = self.repcount - 1
      return self.lastok
   end
   self.repcount = 0

   while true do
      local key = self:GetKey()
      if key == ESC then
         ns.main:SetFocus(false)
      else
         key = ARROW_COMMAND[key] or key
         if #key == 1 then
            if key:match("^%d$") then
               self.repcount = self.repcount * 10 + tonumber(key)
            else
               if self.repcount > 0 then
                  self.repcount = self.repcount - 1
               end
               self.lastok = key
               return key
            end
         end
      end
   end
end

-- C: getyn(). Returns "y", "n" or ESC (Esc, space and enter all mean ESC).
function ui:YesNo(message)
   ns.prompt:Set(message .. " [y/n]", "yesno")
   local answer
   while not answer do
      local key = self:GetKey()
      if key == "y" or key == "Y" then
         answer = "y"
      elseif key == "n" or key == "N" then
         answer = "n"
      elseif key == ESC or key == " " or key == "ENTER" then
         answer = ESC
      end
   end
   ns.prompt:Clear()
   self:Log("prompt", "%s %s", message, answer == ESC and L["(cancelled)"] or answer)
   return answer
end

-- C: the "(g) go inside, or (i) ignore it?" prompts. keys is a string of the accepted
-- lowercase letters; "i" and Esc always ignore. Returns the key, "i" for Esc.
function ui:Choose(message, keys)
   ns.prompt:Set(message, nil)
   local answer
   while not answer do
      local key = self:GetKey()
      if key == ESC then
         answer = "i"
      elseif #key == 1 and (key == "i" or keys:find(key, 1, true)) then
         answer = key
      end
   end
   ns.prompt:Clear()
   self:Log("prompt", "%s %s", message, answer)
   return answer
end

-- C: more()/retcont().
function ui:More()
   ns.prompt:Set(L["--- press space to continue ---"], "more")
   local key
   repeat key = self:GetKey() until key == " " or key == "ENTER"
   ns.prompt:Clear()
end

-- C: readnum(). '*' means all (max); Esc or space aborts with -1.
function ui:GetNumber(message, max)
   local digits, result = "", nil
   while not result do
      ns.prompt:Set(message .. " " .. digits)
      local key = self:GetKey()
      if key == "*" and digits == "" then
         result = max
      elseif key == "ENTER" then
         result = tonumber(digits) or 0
      elseif key == ESC or key == " " then
         result = -1
      elseif key == "BACKSPACE" then
         digits = digits:sub(1, -2)
      elseif key:match("^%d$") and #digits < 9 then
         digits = digits .. key
      end
   end
   ns.prompt:Clear()
   self:Log("prompt", "%s %s", message, result < 0 and L["(cancelled)"] or tostring(result))
   return result
end

-- C: dirsub()/direction questions. Returns 1..8, or nil if cancelled.
function ui:PickDirection(message)
   ns.prompt:Set(message .. " " .. L["(direction)"])
   local direction
   while not direction do
      local key = self:GetKey()
      direction = DIRECTION[key]
      if not direction and (key == ESC or key == " ") then
         break
      end
   end
   ns.prompt:Clear()
   return direction
end

-- C: pick_char(). Returns the chosen entry of classes (keyed by its letter, or Enter for
-- the highlighted one; the arrow keys move the highlight).
function ui:PickClass(classes, selected)
   ns.picker:Show(classes, selected)
   local result
   while not result do
      local key = self:GetKey()
      for index, class in ipairs(classes) do
         if key == class.letter then
            result = class
         end
      end
      if key == "ENTER" then
         result = classes[selected]
      elseif key == "UP" then
         selected = selected > 1 and selected - 1 or #classes
         ns.picker:Select(selected)
      elseif key == "DOWN" then
         selected = selected < #classes and selected + 1 or 1
         ns.picker:Select(selected)
      end
   end
   ns.picker:Hide()
   return result
end

-- Not needed until later milestones; fail loudly if something calls them early.
-- C: whatitem(). Opens the inventory with the valid items marked and waits for a slot.
-- Returns the slot (1..26), "gold" for '.' and "none" for '-' when opts allows them, or
-- nil if the player cancelled.
function ui:PickItem(verb, filter, opts)
   opts = opts or {}
   local extra = (opts.gold and L[", . for gold"] or "") .. (opts.none and L[", - for none"] or "")
   ns.inventory:Open(format(L["What do you want to %s?"], verb), filter)
   ns.prompt:Set(format(L["What do you want to %s? [a-z, * for all%s]"], verb, extra))
   local result
   while result == nil do
      local key = self:GetKey()
      if key == ESC or key == " " or key == "ENTER" then
         result = false
      elseif #key == 1 and key >= "a" and key <= "z" then
         result = key:byte() - 96
      elseif key == "*" then
         ns.inventory:Open(format(L["What do you want to %s?"], verb), nil)
      elseif key == "." and opts.gold then
         result = "gold"
      elseif key == "-" and opts.none then
         result = "none"
      end
   end
   ns.prompt:Clear()
   ns.inventory:Close()
   if result == false then
      self:Log("prompt", L["%s aborted."], verb)
      return nil
   end
   return result
end

-- C: showstr(). Shows the inventory until a key is pressed.
function ui:ShowInventory()
   ns.inventory:Open(L["Inventory"], nil)
   ns.prompt:Set(L["Press any key to close the inventory"])
   self:GetKey()
   ns.prompt:Clear()
   ns.inventory:Close()
end

-- C: cast() asking for the spell. The spellbook opens beside the prompt; a spell is the
-- three letter code, typed or clicked. Returns the code, or nil if the player cancelled.
function ui:PickSpell(message, all)
   ns.spellbook:Open(all)
   local code = ""
   local cancelled
   while #code < 3 and not cancelled do
      ns.prompt:Set((message or L["Enter your spell:"]) .. " " .. code)
      local key = self:GetKey()
      if key == ESC then
         cancelled = true
      elseif key == "BACKSPACE" then
         code = code:sub(1, -2)
      elseif #key == 1 and key:match("%a") and not (code == "" and key == "D") then
         code = code .. key
      end
   end
   ns.prompt:Clear()
   ns.spellbook:Close()
   if cancelled then return nil end
   return code
end

-- C: the missile of godirect(): shows glyph on a tile for delay milliseconds.
function ui:Missile(x, y, glyph, delay)
   ns.map:SetOverlay(x, y, glyph)
   self:Refresh("map")
   self:Nap(delay)
   ns.map:SetOverlay()
   self:Refresh("map")
end

-- C: seemagic(). Lists the spells, scrolls and potions found so far until a key is pressed.
function ui:ShowDiscoveries()
   ns.spellbook:ShowDiscoveries()
   ns.prompt:Set(L["Press any key to close the list"])
   self:GetKey()
   ns.prompt:Clear()
   ns.spellbook:Close()
end
function ui:Store() error("ui:Store is not implemented yet (milestone 8)") end
