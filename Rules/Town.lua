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
local rnd, idiv = ns.rnd, ns.idiv

-- The town buildings (C: store.c and ohome() of object.c). Each one opens the store window
-- (UI/Store.lua) and runs its own loop of keys, in the style of the C. The window only
-- shows things; clicking a row injects its letter.
local Town = {}
ns.Town = Town

local c, iven, ivenarg = G.c, G.iven, G.ivenarg
local ESC = ns.ESC
local format = string.format

local function Letter(index)
   return string.char(96 + index)
end

local function Gold(amount)
   return format(amount == 1 and L["%d gold piece"] or L["%d gold pieces"], amount)
end

-- Says something in the message log and on the last line of the window.
local function Say(fmt, ...)
   local text = select("#", ...) > 0 and format(fmt, ...) or fmt
   ns.ui:Message("%s", text)
   ns.store:SetNote(text)
end

local function Leave()
   ns.prompt:Clear()
   ns.store:Close()
   ns.ui:Refresh("all")
end

-- The Ularn Revenue Service does not serve tax evaders. Shows why and waits for Esc.
local function Frozen(title, text)
   ns.store:Open(title, text, 0)
   ns.prompt:Set(L["Press escape to leave"])
   local key
   repeat key = ns.ui:GetKey() until key == ESC
   Leave()
end

-- The gold line of the window, and where the C kept the "You have N gold pieces".
local function ShowGold()
   ns.store:SetStatus(format(L["You have %s."], Gold(c[K.GOLD])))
   ns.ui:Refresh("stats")
end

local function NoGold()
   Say(L["You don't have enough gold to pay for that!"])
   ns.ui:Nap(2200)
end

----------------------------------------------------------------
-- The DND store
----------------------------------------------------------------

-- The quantities left of each thing (C: itm[].qty), kept for the whole game.
local function Stock()
   if not G.stock then
      G.stock = {}
      for index, entry in ipairs(ns.ItemTables.dnd) do G.stock[index] = entry[5] end
   end
   return G.stock
end

local function StockName(entry)
   local T = ns.Tables
   if entry[3] == K.OPOTION then
      return format(L["potion of %s"], T.potionname[entry[4]])
   elseif entry[3] == K.OSCROLL then
      return format(L["scroll of %s"], T.scrollname[entry[4]])
   end
   return ns.StripArticle(T.objectname[entry[3]])
end

local function StockRows(page)
   local rows, stock = {}, Stock()
   for index = page * K.IVENSIZE + 1, math.min((page + 1) * K.IVENSIZE, K.DNDSIZE) do
      if stock[index] > 0 then
         local entry = ns.ItemTables.dnd[index]
         rows[#rows + 1] = {
            key = Letter((index - 1) % K.IVENSIZE + 1), text = StockName(entry),
            price = format("%6d", entry[1] * 10), icon = entry[3], arg = entry[4],
         }
      end
   end
   return rows
end

local function Buy(index)
   local stock = Stock()
   local entry = ns.ItemTables.dnd[index]
   if not entry or stock[index] <= 0 then
      Say(L["Sorry, but we are out of that item."])
      ns.ui:Nap(2200)
   elseif ns.Player.pocketFull() then
      Say(L["You can't carry anything more!"])
      ns.ui:Nap(2200)
   elseif c[K.GOLD] < entry[1] * 10 then
      NoGold()
   else
      if entry[2] == "potion" then
         G.potionknown[entry[4]] = 1
      elseif entry[2] == "scroll" then
         G.scrollknown[entry[4]] = 1
      end
      c[K.GOLD] = c[K.GOLD] - entry[1] * 10
      ns.ui:Sound("coin")
      stock[index] = stock[index] - 1
      ns.Player.take(entry[3], entry[4])
      ns.ui:Nap(1001)
   end
end

-- C: dndstore().
function Town.dndStore()
   local title = L["Ularn Thrift Shoppe"]
   if G.taxes > 0 then
      Frozen(title, format(L["The Ularn Revenue Service has ordered us to not do business with tax evaders.\n\nThey have also told us that you owe %d gp in back taxes and, as we must comply with the law, we cannot serve you at this time.  So Sorry."], G.taxes))
      return
   end
   local store, ui = ns.store, ns.ui
   store:Open(title, L["Welcome to the Ularn Thrift Shoppe.  We stock many items explorers find useful in their adventures.  Feel free to browse to your heart's content.  Also be advised that if you break 'em, you pay for 'em."], 2)
   local page = 0
   local pages = math.ceil(K.DNDSIZE / K.IVENSIZE)
   while true do
      store:SetRows(StockRows(page))
      store:SetPages(page + 1, pages)
      ShowGold()
      ns.prompt:Set(L["Enter your transaction [space for more, escape to leave]"])
      local key = ui:GetKey()
      if key == ESC then
         break
      elseif key == " " or key == ">" then
         page = (page + 1) % pages
         store:SetNote("")
      elseif key == "<" then
         page = (page - 1) % pages
         store:SetNote("")
      elseif #key == 1 and key >= "a" and key <= "z" then
         Buy(page * K.IVENSIZE + key:byte() - 96)
      end
   end
   Leave()
end

----------------------------------------------------------------
-- The College of Ularn
----------------------------------------------------------------

local COURSES = {
   { L["Fighter's Training I"], 10 }, { L["Fighter's Training II"], 15 },
   { L["Introduction to Wizardry"], 10 }, { L["Applied Wizardry"], 20 },
   { L["Behavioral Psychology"], 10 }, { L["Faith for Today"], 10 },
   { L["Contemporary Dance"], 10 }, { L["History of Ularn"], 5 },
}
local COURSE_COST = 250

local function CourseRows()
   local rows = {}
   for index, course in ipairs(COURSES) do
      if not G.course[index] then
         rows[#rows + 1] = { key = Letter(index), text = course[1], price = format(L["%d mobuls"], course[2]) }
      end
   end
   return rows
end

-- What each course does; returns false (and says why) if the prerequisite is missing.
local function Teach(index)
   local STR, CON, INT, WIS, CHA, DEX = K.STRENGTH, K.CONSTITUTION, K.INTELLIGENCE, K.WISDOM, K.CHARISMA, K.DEXTERITY
   if index == 1 then
      c[STR], c[CON] = c[STR] + 2, c[CON] + 1
      Say(L["You feel stronger!"])
   elseif index == 2 then
      if not G.course[1] then
         Say(L["Sorry but this class has a prerequisite of Fighter's Training I"])
         return false
      end
      Say(L["You feel much stronger!"])
      c[STR], c[CON] = c[STR] + 2, c[CON] + 2
   elseif index == 3 then
      c[INT] = c[INT] + 2
      Say(L["The task before you now seems more attainable!"])
   elseif index == 4 then
      if not G.course[3] then
         Say(L["Sorry but this class has a prerequisite of Introduction to Wizardry"])
         return false
      end
      Say(L["The task before you now seems very attainable!"])
      c[INT] = c[INT] + 2
   elseif index == 5 then
      c[CHA] = c[CHA] + 3
      Say(L["You now feel like a born leader!"])
   elseif index == 6 then
      c[WIS] = c[WIS] + 2
      Say(L["You now feel more confident that you can find the potion in time!"])
   elseif index == 7 then
      c[DEX] = c[DEX] + 3
      Say(L["You feel like dancing!"])
   else
      c[INT] = c[INT] + 1
      Say(L["Wow! e = mc^2!"])
   end
   return true
end

-- C: oschool().
function Town.school()
   local store, ui = ns.store, ns.ui
   store:Open(L["The College of Ularn"], L["The College of Ularn offers the exciting opportunity of higher education to all inhabitants of the caves.  Here is the class schedule.  All courses cost 250 gold pieces."], 1)
   while true do
      store:SetRows(CourseRows())
      ShowGold()
      ns.prompt:Set(L["What is your choice? [escape to leave]"])
      local key = ui:GetKey()
      if key == ESC then
         break
      elseif #key == 1 and key >= "a" and key <= "h" then
         local index = key:byte() - 96
         if c[K.GOLD] < COURSE_COST then
            NoGold()
         elseif G.course[index] then
            Say(L["Sorry but that class is filled."])
            ui:Nap(1000)
         else
            c[K.GOLD] = c[K.GOLD] - COURSE_COST
            ns.ui:Sound("coin")
            if Teach(index) then
               local used = COURSES[index][2] * 100
               G.gtime = G.gtime + used
               G.course[index] = true  -- remember that he has taken that course
               c[K.HP] = c[K.HPMAX]  -- he regenerated
               c[K.SPELLS] = c[K.SPELLMAX]
               if c[K.BLINDCOUNT] ~= 0 then c[K.BLINDCOUNT] = 1 end  -- cure blindness too
               if c[K.CONFUSE] ~= 0 then c[K.CONFUSE] = 1 end  -- end confusion
               ns.Magic.adjustTime(used)
            else
               c[K.GOLD] = c[K.GOLD] + COURSE_COST
               ns.ui:Sound("coin")
            end
            ui:Refresh("stats")
            ui:Nap(1000)
         end
      end
   end
   Leave()
end

----------------------------------------------------------------
-- The bank
----------------------------------------------------------------

local BANK_LIMIT = 1000000
local GEMS = { [K.OLARNEYE] = true, [K.ODIAMOND] = true, [K.OEMERALD] = true, [K.ORUBY] = true, [K.OSAPPHIRE] = true }

-- C: ointerest(). Interest on the account for the time since the last visit.
local function Interest()
   if c[K.BANKACCOUNT] < 0 then
      c[K.BANKACCOUNT] = 0
   elseif c[K.BANKACCOUNT] > 0 and c[K.BANKACCOUNT] < BANK_LIMIT then
      local mobuls = idiv(G.gtime - G.lastBank, 100)
      while mobuls > 0 and c[K.BANKACCOUNT] < BANK_LIMIT do
         mobuls = mobuls - 1
         c[K.BANKACCOUNT] = c[K.BANKACCOUNT] + idiv(c[K.BANKACCOUNT], 877)  -- about 10% a year
      end
   end
   G.lastBank = idiv(G.gtime, 100) * 100
end

local function EyeValue()
   return math.max(50000, 250000 - idiv(G.gtime * 7, 100) * 100)
end

-- The gems in the pack and what the bank gives for them.
local function GemValue(slot)
   if iven[slot] == K.OLARNEYE then return EyeValue() end
   if GEMS[iven[slot]] then return ivenarg[slot] * 100 end
   return 0
end

-- The Eye of Larn is worth what the bank says after it has appraised it (Appraise), not before.
local function GemRows(eyeKnown)
   local rows = {}
   for slot = 1, K.IVENSIZE do
      if GEMS[iven[slot]] then
         local price = (iven[slot] == K.OLARNEYE and not eyeKnown) and "?" or format("%6d", GemValue(slot))
         rows[#rows + 1] = { key = Letter(slot), text = ns.Player.itemName(slot),
            price = price, icon = iven[slot], arg = ivenarg[slot] }
      end
   end
   return rows
end

local function SellGem(slot)
   if iven[slot] == K.OLARNEYE then c[K.EYEOFLARN] = 0 end
   G.gemsSold[iven[slot]] = true
   c[K.GOLD] = c[K.GOLD] + GemValue(slot)
   ns.ui:Sound("coin")
   iven[slot], ivenarg[slot] = 0, 0
end

-- C: appraise(). The bank offers to buy the Eye of Larn.
local function Appraise(slot)
   local ui = ns.ui
   Say(L["I see you have %s.  I must commend you.  I didn't think you could get it."], ns.Tables.objectname[K.OLARNEYE])
   if ui:YesNo(L["Shall I appraise it for you?"]) ~= "y" then return end
   Say(L["Just one moment please..."])
   ui:Nap(1000)
   local amount = EyeValue()
   Say(L["This is an excellent stone.  It is worth %d gold pieces to us."], amount)
   if ui:YesNo(L["Would you like to sell it?"]) == "y" then
      SellGem(slot)
   else
      Say(L["It is, of course, your privilege to keep the stone."])
   end
   return true
end

-- C: obank(), obank2(), banktitle() and obanksub().
function Town.bank(branch)
   local store, ui = ns.store, ns.ui
   local title = branch and L["Welcome to the 8th-level branch office of the First National Bank of Ularn."]
      or L["Welcome to the First National Bank of Ularn."]
   if G.taxes > 0 then
      Frozen(title, format(L["The Ularn Revenue Service has ordered that your account be frozen until all levied taxes have been paid.  They have also told us that you owe %d gp in taxes and we must comply with them. We cannot serve you at this time.  Sorry.\n\nWe suggest you go to the LRS office and pay your taxes."], G.taxes))
      return
   end
   store:Open(title, L["We buy gemstones at the appraisals shown below."], 1)
   Interest()  -- credit any needed interest
   if G.level == 8 then c[K.TELEFLAG] = 0 end

   local eyeKnown = false  -- (set once the bank has appraised the Eye of Larn)
   local function Show()
      store:SetRows(GemRows(eyeKnown))
      local text = format(L["You have %s in the bank."], Gold(c[K.BANKACCOUNT])) .. "   "
         .. format(L["You have %s."], Gold(c[K.GOLD]))
      if c[K.BANKACCOUNT] + c[K.GOLD] >= 500000 then
         text = text .. "\n" .. L["Note:  Only deposits under 1,000,000gp can earn interest."]
      end
      store:SetStatus(text)
      ui:Refresh("stats")
   end

   for slot = 1, K.IVENSIZE do
      if iven[slot] == K.OLARNEYE then
         Show()
         eyeKnown = Appraise(slot) or false
         break
      end
   end
   while true do
      Show()
      ns.prompt:Set(L["Your wish? [(d) deposit, (w) withdraw, (s) sell a stone, or escape]"])
      local key = ui:GetKey()
      if key == ESC then
         break
      elseif key == "d" then
         local amount = ui:GetNumber(L["Deposit how much?"], c[K.GOLD])
         if amount > c[K.GOLD] then
            Say(L["You don't have that much."])
            ui:Nap(2000)
         elseif amount > 0 then
            c[K.GOLD] = c[K.GOLD] - amount
            ns.ui:Sound("coin")
            c[K.BANKACCOUNT] = c[K.BANKACCOUNT] + amount
         end
      elseif key == "w" then
         local amount = ui:GetNumber(L["Withdraw how much?"], c[K.BANKACCOUNT])
         if amount > c[K.BANKACCOUNT] then
            Say(L["You don't have that much in the bank!"])
            ui:Nap(2000)
         elseif amount > 0 then
            c[K.GOLD] = c[K.GOLD] + amount
            ns.ui:Sound("coin")
            c[K.BANKACCOUNT] = c[K.BANKACCOUNT] - amount
         end
      elseif key == "s" then
         ns.prompt:Set(L["Which stone would you like to sell? [a-z, * for all]"])
         local choice
         repeat choice = ui:GetKey() until choice == ESC or choice == "*" or (#choice == 1 and choice >= "a" and choice <= "z")
         if choice == "*" then
            for slot = 1, K.IVENSIZE do
               if GEMS[iven[slot]] then SellGem(slot) end
            end
         elseif choice ~= ESC then
            local slot = choice:byte() - 96
            if GEMS[iven[slot]] then
               SellGem(slot)
            else
               Say(L["Item %s is not a gemstone!"], choice)
               ui:Nap(2000)
            end
         end
         ui:Refresh("inv")
      end
   end
   Leave()
end

----------------------------------------------------------------
-- The trading post
----------------------------------------------------------------

-- C: the price the trading post pays; nil if it does not buy the item.
local function TradeValue(slot)
   local id, arg = iven[slot], ivenarg[slot]
   local dnd = ns.ItemTables.dnd
   for j = 1, K.DNDSIZE do
      if dnd[j][3] == id or GEMS[id] and id ~= K.OLARNEYE then
         if GEMS[id] then
            return 20 * arg
         elseif id == K.OSCROLL or id == K.OPOTION then
            -- (the C indexes the store with the number of the scroll or potion, which
            -- is off for the potions that are not in the store)
            local entry = dnd[j + arg - 1]
            return entry and 2 * entry[1]
         end
         local value = dnd[j][1]
         if arg >= 0 then value = value * 2 end
         local count = arg
         while count > 0 do
            count = count - 1
            value = idiv(14 * (67 + value), 10)
            if value >= 500000 then break end
         end
         return value
      end
   end
end

-- C: otradepost().
function Town.tradingPost()
   local store, ui = ns.store, ns.ui
   store:Open(L["The Ularn Trading Post"], L["Welcome to the Ularn Trading Post.  We buy items that explorers no longer find useful.  Since the condition of the items you bring in is not certain, and we incur great expense in reconditioning the items, we usually pay only 20% of their value were they to be new.  If the items are badly damaged, we will pay only 10% of their new value."], 0)
   while true do
      ShowGold()
      local slot = ui:PickItem(L["sell"])
      if not slot then break end
      local id, arg = iven[slot], ivenarg[slot]
      if id == K.OSCROLL and G.scrollknown[arg] == 0 or id == K.OPOTION and G.potionknown[arg] == 0 then
         Say(L["Sorry, we can't accept unidentified objects."])
      elseif id == K.OLANCE and G.ramboflag then
         Say(L["You don't *really* want to sell that, now do you?"])
      elseif id == 0 then
         Say(L["You don't have item %s!"], Letter(slot))
      else
         local value = TradeValue(slot)
         if not value then
            Say(L["So sorry but we are not authorized to accept that item."])
         else
            local name = ns.Player.itemName(slot)
            if ui:YesNo(format(L["%s is worth %s to us.  Do you want to sell it?"], name, Gold(value))) == "y" then
               c[K.GOLD] = c[K.GOLD] + value
               ns.ui:Sound("coin")
               if GEMS[id] then G.gemsSold[id] = true end
               if c[K.WEAR] == slot then c[K.WEAR] = 0 end
               if c[K.WIELD] == slot then c[K.WIELD] = 0 end
               if c[K.SHIELD] == slot then c[K.SHIELD] = 0 end
               ns.Player.adjustCValues(id, arg)
               iven[slot], ivenarg[slot] = 0, 0
               Say(L["Sold %s for %s."], name, Gold(value))
               ui:Refresh("inv")
            else
               Say(L["No thanks."])
            end
         end
      end
   end
   ns.Player.recalc()
   Leave()
end

----------------------------------------------------------------
-- The Larn Revenue Service
----------------------------------------------------------------

-- C: paytaxes(). Pays up to x gold of the taxes; returns what was paid.
local function PayTaxes(x)
   if x <= 0 then return 0 end
   return ns.Scores.payTaxes(x)
end

-- C: olrs().
function Town.lrs()
   local store, ui = ns.store, ns.ui
   local function Show()
      local owe = G.taxes > 0 and format(L["You presently owe %d gp in taxes."], G.taxes) or L["You do not owe us any taxes."]
      local have = c[K.GOLD] > 0 and format(L["You have %d gp."], c[K.GOLD]) or L["You have no gold pieces."]
      store:Open(L["The Ularn Revenue Service"], L["Welcome to the Ularn Revenue Service district office.  How can we help you?"] .. "\n\n" .. owe .. "\n\n" .. have, 0)
   end
   Show()
   while true do
      ns.prompt:Set(L["Your wish? [(p) pay taxes, or escape]"])
      local key = ui:GetKey()
      if key == ESC then
         break
      elseif key == "p" then
         local amount = ui:GetNumber(L["Pay how much?"], c[K.GOLD])
         if amount > c[K.GOLD] then
            ui:Message(L["You don't have that much."])
         elseif amount > 0 then
            c[K.GOLD] = c[K.GOLD] - PayTaxes(amount)
            ns.ui:Sound("coin")
         end
         Show()
         ui:Refresh("stats")
      end
   end
   Leave()
end

----------------------------------------------------------------
-- Home
----------------------------------------------------------------

-- C: ohome(). Hands over the potion of cure dianthroritis, if you have it.
function Town.home()
   local store, ui = ns.store, ns.ui
   local spouse = G.sex == 1 and L["wife"] or L["husband"]
   local title = format(L["Welcome home %s."], G.name)

   for slot = 1, K.IVENSIZE do
      -- remove the potion of cure dianthroritis from the pack
      if iven[slot] == K.OPOTION and ivenarg[slot] == K.PCUREDIANTH then
         iven[slot], ivenarg[slot] = 0, 0
         local text = L["Congratulations.  You found the potion of cure dianthroritis!\n\nFrankly, No one thought you could do it.  Boy!  Did you surprise them!"]
         store:Open(title, text, 0)
         ui:Nap(1000)
         if G.gtime > K.TIMELIMIT then
            store:SetIntro(text .. "\n\n" .. format(L["However... the doctor has the sad duty to inform you that your daughter has died! You didn't make it in time.  In your agony, you kill the doctor, your %s and yourself!  Too bad..."], spouse))
            ui:Nap(5000)
            Leave()
            ns.Player.died(269)
         else
            text = text .. "\n\n" .. L["The doctor is now administering the potion and, in a few moments, your daughter should be well on her way to recovery."]
            store:SetIntro(text)
            ui:Nap(6000)
            for _ = 1, 3 do
               text = text .. "."
               store:SetIntro(text)
               ui:Nap(1000)
            end
            store:SetIntro(text .. "\n\n" .. L["It's working!  The doctor thinks that your daughter will recover in a few days.  Congratulations!"])
            ui:Nap(5000)
            Leave()
            ns.Player.died(263)
         end
         return
      end
   end

   store:Open(title, "", 0)
   if G.gtime > K.TIMELIMIT then
      store:SetIntro(format(L["The doctor has the sad duty to inform you that your daughter has died! You didn't make it in time.  In your agony, you kill the doctor, your %s and yourself!  Too bad..."], spouse))
      ui:Nap(5000)
      Leave()
      ns.Player.died(269)
      return
   end
   store:SetIntro(L["Latest word from the doctor is not good."] .. "\n\n"
      .. format(L["The diagnosis is confirmed as dianthroritis.  He guesses that your daughter has only %d mobuls left in this world.  It's up to you, %s, to find the only hope for your daughter, the very rare potion of cure dianthroritis.  It is rumored that only deep in the depths of the caves can this potion be found."],
         idiv(K.TIMELIMIT - G.gtime + 99, 100), G.name))
   ns.prompt:Set(L["Press escape to leave"])
   local key
   repeat key = ui:GetKey() until key == ESC or key == "ENTER"
   Leave()
end

----------------------------------------------------------------
-- Grizzik's Questionable Elixirs (C: Dealer McDope's pad)
----------------------------------------------------------------

local ELIXIRS = {
   { L["Goblin Rocket Fuel"], 100, K.OSPEED }, { L["Gnomish Mind-Expander"], 250, K.OACID },
   { L["Volatile Swamp Brew"], 500, K.OHASH }, { L["Glowcap Stew"], 1000, K.OSHROOMS },
   { L["Overcharged Fel Tonic"], 5000, K.OCOKE },
}
for _, elixir in ipairs(ELIXIRS) do
   ns.Tables.objectname[elixir[3]] = elixir[1]  -- (the C ids stay, only the names change)
end

local function ElixirRows()
   local rows = {}
   for index, elixir in ipairs(ELIXIRS) do
      if not G.drug[index] then
         rows[#rows + 1] = { key = Letter(index), text = elixir[1], price = format(L["%d gold"], elixir[2]), icon = elixir[3] }
      end
   end
   return rows
end

-- C: snag(). Puts the elixir in the first free slot.
local function Snag(id)
   for slot = 1, ns.Player.pocketLimit() do
      if iven[slot] == 0 then
         iven[slot], ivenarg[slot] = id, 0
         Say(L["Ok, here ya go: %s"], ns.Player.itemName(slot))
         ns.ui:Refresh("inv")
         return true
      end
   end
   Say(L["Hey, you can't carry any more."])
   return false
end

-- C: opad().
function Town.pad()
   local store, ui = ns.store, ns.ui
   store:Open(L["Grizzik's Questionable Elixirs"], L["Psst, friend!  Grizzik's got the finest elixirs this side of the Barrens.  One of each, no refunds, and don't ask what's in 'em.  Time is money!"], 1)
   while true do
      store:SetRows(ElixirRows())
      ShowGold()
      ns.prompt:Set(L["So, whaddya want? [escape to leave]"])
      local key = ui:GetKey()
      if key == ESC then
         break
      elseif #key == 1 and key >= "a" and key <= "e" then
         local index = key:byte() - 96
         local elixir = ELIXIRS[index]
         if G.drug[index] then
            Say(L["Grizzik ain't got no more of that, friend!"])
            ui:Nap(2200)
         elseif c[K.GOLD] < elixir[2] then
            Say(L["No gold, no elixir, friend!  Time is money!"])
            ui:Nap(1200)
         else
            if Snag(elixir[3]) then
               c[K.GOLD] = c[K.GOLD] - elixir[2]
               ns.ui:Sound("coin")
               G.drug[index] = true  -- remember that he has snagged that one
            end
            ui:Nap(1000)
         end
      end
   end
   Leave()
end
