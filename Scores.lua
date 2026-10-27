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
local idiv = ns.idiv
local format = string.format

-- The scoreboards (C: scores.c). There are two lists, the winners and the dead, shared by
-- all characters of the account (WoWLarnDB.global). Each character has at most one entry
-- in each list, and a winner's earlier deaths are removed. The taxes a winner owes are
-- kept per character too.
local Scores = {}
ns.Scores = Scores

local c, iven, ivenarg = G.c, G.iven, G.ivenarg

-- C: whydead[]; the death cause is 256 plus the index.
local WHYDEAD = {
   [0] = L["quit"], L["suspended"], L["self - annihilated"], L["shot by an arrow"], L["hit by a dart"],
   L["fell into a pit"], L["fell into a pit to HELL"], L["a winner"], L["trapped in solid rock"],
   L["killed by a missing save file"], L["killed by an old save file"],
   L["caught by the greedy cheater checker trap"], L["killed by a protected save file"],
   L["killed his family and committed suicide"], L["erased by a wayward finger"],
   L["fell through a trap door to HELL"], L["fell through a trap door"], L["drank some poisonous water"],
   L["fried by an electric shock"], L["slipped in a volcano shaft"],
   L["killed by a stupid act of frustration"], L["attacked by a revolting demon"], L["hit by his own magic"],
   L["demolished by an unseen attacker"], L["fell into the dreadful sleep"], L["killed by an exploding chest"],
   L["died of internal complications"], L["annihilated by a sphere"], L["died a post mortem death"],
   L["wasted by a malloc() failure"], L["wasted by a pissed off genie"], L["took an elevator straight to HELL"],
}
local QUIT, WIN, QUICKQUIT = 256, 263, 300
Scores.QUIT, Scores.WIN, Scores.QUICKQUIT = QUIT, WIN, QUICKQUIT

-- The deaths that life protection can not undo.
local UNSAVABLE = {}
for _, cause in ipairs({ 256, 257, 262, 263, 265, 266, 267, 268, 269, 271, 282, 284, 285, 286, 300 }) do
   UNSAVABLE[cause] = true
end
function Scores.canBeSaved(cause)
   return not UNSAVABLE[cause]
end

local function Board()
   local global = ns.mod.db.global
   global.scores = global.scores or { winners = {}, dead = {} }
   global.taxes = global.taxes or {}
   return global.scores
end

-- Who the player is on the scoreboard: the character and realm.
function Scores.key()
   return G.name .. "-" .. (GetRealmName and GetRealmName() or "")
end

function Scores.taxes()
   return Board() and ns.mod.db.global.taxes[Scores.key()] or 0
end

function Scores.payTaxes(amount)
   local taxes = ns.mod.db.global.taxes
   local key = Scores.key()
   local paid = math.min(amount, taxes[key] or 0)
   taxes[key] = (taxes[key] or 0) - paid
   G.taxes = taxes[key]
   return paid
end

-- The line that says how the player ended (C: diedsub).
function Scores.deathLine(cause, level, sex)
   level, sex = level or G.level, sex or G.sex
   local text
   if type(cause) ~= "number" then cause = 284 end
   if cause < 256 then
      local name = ns.MonsterData[cause].name
      text = format(name:find("^[aeiou]") and L["killed by an %s"] or L["killed by a %s"], name)
   else
      local index = cause - 256
      if sex == 0 and index == 13 then
         text = L["killed her family and committed suicide"]
      elseif sex == 0 and index == 22 then
         text = L["hit by her own magic"]
      else
         text = WHYDEAD[index] or WHYDEAD[28]
      end
   end
   if cause ~= WIN then
      text = text .. " " .. format(L["on %s"], ns.Tables.levelname[level + 1])
   end
   return text
end

local function Sort(list)
   table.sort(list, function(a, b) return a.score > b.score end)
   for index = #list, ns.K.SCORESIZE + 1, -1 do list[index] = nil end
end

local function Find(list, key)
   for index, entry in ipairs(list) do
      if entry.key == key then return index, entry end
   end
end

-- C: newscore(), new1sub() and new2sub().
local function Enter(list, entry, replaceIf)
   local index, old = Find(list, entry.key)
   if old then
      if entry.score >= old.score or entry.hardlev > old.hardlev then list[index] = entry end
   elseif #list < K.SCORESIZE then
      list[#list + 1] = entry
   else
      Sort(list)
      local last = list[#list]
      if entry.score >= last.score or entry.hardlev > last.hardlev then list[#list] = entry end
   end
   Sort(list)
end

-- C: died(), the part that keeps the score. Returns the entry that was entered, or nil
-- (wizards and quick quits don't score).
function Scores.record(cause)
   if type(cause) ~= "number" then cause = 284 end
   c[K.GOLD] = c[K.GOLD] + c[K.BANKACCOUNT]
   c[K.BANKACCOUNT] = 0
   if G.wizard or cause == QUICKQUIT then return nil end

   local board = Board()
   local score = c[K.GOLD]
   local entry = {
      key = Scores.key(), who = G.name, class = G.class and (LOCALIZED_CLASS_NAMES_MALE[G.class.token] or G.class.token) or "?", score = score,
      hardlev = c[K.HARDGAME], level = G.level, what = cause, time = idiv(G.gtime, 100),
      sex = G.sex, date = date and date("%Y-%m-%d") or "",
   }
   if cause == WIN then
      -- a winner loses the non-winning scores, and owes taxes
      local dead = board.dead
      for index = #dead, 1, -1 do
         if dead[index].key == entry.key then table.remove(dead, index) end
      end
      local taxes = math.floor(G.taxes + score * K.TAXRATE)
      ns.mod.db.global.taxes[entry.key] = (ns.mod.db.global.taxes[entry.key] or 0) + taxes
      G.taxes = ns.mod.db.global.taxes[entry.key]
      entry.score = score + 100000 * c[K.HARDGAME]  -- bonus for winning
      Enter(board.winners, entry)
   else
      entry.inventory = {}
      for slot = 1, K.IVENSIZE do
         entry.inventory[slot] = { iven[slot], ivenarg[slot] }
      end
      Enter(board.dead, entry)
   end
   return entry
end

function Scores.winners()
   return Board().winners
end

function Scores.dead()
   return Board().dead
end
