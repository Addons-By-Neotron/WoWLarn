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
-- all characters of the account (WoWLarnDB.global), the best games first. The taxes a winner owes are
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

-- C: newscore(), new1sub() and new2sub(). FIX: the C keeps one entry per player; here every
-- game gets its own, as a player usually has just the one character.
local function Enter(list, entry)
   list[#list + 1] = entry
   Sort(list)
end

-- C: died(), the part that keeps the score. Returns the entry that was entered, or nil
-- (wizards and quick quits don't score).
function Scores.record(cause)
   if type(cause) ~= "number" then cause = 284 end
   c[K.GOLD] = c[K.GOLD] + c[K.BANKACCOUNT]
   c[K.BANKACCOUNT] = 0
   if G.wizard or G.cheated or cause == QUICKQUIT then return nil end  -- (G.cheated: wizard mode was on once)

   local board = Board()
   local score = c[K.GOLD]
   if ns.mod.db.global.scoreItems then score = score + ns.Town.carriedValue() end  -- FIX: not in the C. An option: what you carry counts
   local entry = {
      key = Scores.key(), who = G.name, class = G.class and ns.ClassName(G.class) or "?", score = score,
      hardlev = c[K.HARDGAME], level = G.level, what = cause, time = idiv(G.gtime, 100),
      sex = G.sex, date = date and date("%Y-%m-%d") or "",
   }
   if cause == WIN then
      -- a winner owes taxes
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

-- C: bill.c. The letters a winner gets: { sender, subject, text }. The tax bill comes first.
function Scores.letters()
   local gold, taxes, woman = c[K.GOLD], G.taxes, G.sex == 0
   return {
      { L["Ularn Revenue Service"], L["undeclared income"], format(
         L["We heard you survived the caverns of Ularn.  Let me be the first to congratulate you on your success.  It is quite a feat.  It must also have been very profitable for you.  The Dungeon Master has informed us that you brought %d gold pieces back with you from your journey.  As the county of Ularn is in dire need of funds, we have spared no time in preparing your tax bill.  You owe %d gold pieces as of this notice, and is due within 5 days.  Failure to pay will mean penalties.  Once again, congratulations.  We look forward to your future successful expeditions."],
         gold, taxes) },
      { L["His Majesty King Wilfred"], L["a noble deed"], format(
         L["I have heard of your magnificent feat and I, King Wilfred, hereby declare this day to be a national holiday.  Furthermore, three days hence, ye be invited to the castle to receive the honour of %s of the Realm.  Upon thy name shall it be written...  Bravery and courage be yours.  May you live in happiness for evermore..."],
         woman and L["Lady"] or L["Knight"]) },
      { L["Count Endelford"], woman and L["You Bitch!"] or L["You Bastard!"], format(
         L["I heard (from sources) of your journey.  Congratulations!  You %s!  With several attempts I have yet to endure the caves, and you, a nobody, make the journey!  From this time onward, be warned: upon our meeting you shall pay the price!"],
         woman and L["Bitch"] or L["Bastard"]) },
      { L["Duke of Ularnty"], L["High Praise"],
         L["With a certainty, a hero I declare to be amongst us!  A nod of favour I send to thee.  Methinks Count Endelford this day of right breaths fire as of dragon of whom ye are slayer.  I yearn to behold his anger and jealously.  Should ye choose to unleash some of thy wealth upon those who be unfortunate, I, Duke Mainair, shall equal thy gift also."] },
      { L["St. Mary's Children's Home"], L["these poor children"], format(
         L["News of your great conquest has spread to all of Ularndom.  Might I have a moment of a great %s's time?  We here at St. Mary's Children's Home are very poor and many children are starving.  Disease is widespread and very often fatal without good food.  Could you possibly find it in your heart to help us in our plight?  Whatever you could give would help much.  (your gift is tax-deductible)"],
         woman and L["woman"] or L["man"]) },
      { L["National Dianthroritis Society of Ularn"], L["hope"],
         L["Congratulations on your successful expedition.  We are sure much courage and determination was needed on your quest.  There are many though, that could never hope to undertake such a journey due to an enfeebling disease -- dianthroritis.  We at the National Dianthroritis Society of Ularn wish to appeal to your philanthropy in order to save many good people -- possibly even yourself or a loved one a few years from now.  Much work needs to be done in researching this dreaded disease and you can help today.  Could you please see it in your heart to give generously?  Your continued good health can be your everlasting reward."] },
   }
end
