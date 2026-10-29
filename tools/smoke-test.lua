-- Headless smoke test: loads the addon files with stand-ins for the WoW API and plays
-- through the game thread. Usage: luajit tools/smoke-test.lua   (run from the addon folder)
local root = arg[1] or "."

local proxy
proxy = setmetatable({}, { __index = function() return function() return proxy end end })
LOG = {}
local function newframe(kind)
   return setmetatable({ kind = kind, scripts = {} }, {
      __index = function(t, k)
         if k == "SetScript" then return function(self, n, fn) self.scripts[n] = fn end end
         if k == "IsShown" then return function(self) return self.shown end end
         if k == "Show" then return function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end end
         if k == "Hide" then return function(self) self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end end
         if k == "SetShown" then return function(self, v) self.shown = v end end
         if k == "AddMessage" then return function(self, m) LOG[#LOG + 1] = m end end
         if k == "GetPoint" then return function() return "CENTER", nil, nil, 0, 0 end end
         if k == "GetFrameLevel" then return function() return 1 end end
         if k == "GetWidth" then return function() return 704 end end
         if k == "GetHeight" then return function() return 448 end end
         if k == "CreateFontString" or k == "CreateTexture" then return function() return newframe("child") end end
         return function() return proxy end
      end,
   })
end
CreateFrame = function(kind) return newframe(kind) end
UIParent = newframe("ui")
UISpecialFrames = {}
BackdropTemplateMixin = true
tinsert = table.insert
format = string.format
unpack = unpack or table.unpack
GameTooltip, GameTooltip_Hide, ChatFontNormal = proxy, function() end, {}
IsShiftKeyDown = function() return false end
LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", WARRIOR = "Warrior" }
UnitClass = function() return "Mage", "MAGE" end
UnitName = function() return "Tester" end
UnitSex = function() return 2 end
geterrorhandler = function() return function(e) print("ERRHANDLER: " .. tostring(e)) end end
local timers = {}
GetTime = function() return 0 end
C_Timer = { After = function(sec, fn) timers[#timers + 1] = { sec, fn } end }
LibStub = function() return {
   GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end,
} end

local ns = { mod = { db = { profile = { scale = 1, fast = false, window = { point = "CENTER", x = 0, y = 0 } }, char = {}, global = { scores = { winners = {}, dead = {} }, taxes = {} } } } }
local toc = io.open(root .. "/WoWLarn.toc"):read("*a")
for file in toc:gmatch("\n([%w_\\/]+%.lua)") do
   if file ~= "WoWLarn.lua" and file ~= "Options.lua" then
      assert(loadfile(root .. "/" .. file:gsub("\\", "/")))("WoWLarn", ns)
   end
end

local K, G, ui = ns.K, ns.G, ns.ui
local function strip(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function lines() local out = {} for i, l in ipairs(LOG) do out[i] = strip(l) end return out end
local function last() local l = lines() return l[#l] end
local function check(cond, msg) if not cond then print("FAIL: " .. msg); os.exit(1) end end
local function keys(s) for ch in s:gmatch(".") do ui:InjectKey(ch) end end

---------------------------------------------------------------- data
check(#ns.MonsterData == 65, "65 monsters, got " .. #ns.MonsterData)
check(K.PTREASURE == 20 and K.STRENGTH == 1 and K.OENTRANCE == 54, "shifted constants")
check(ns.Tables.objectname[K.ODNDSTORE] == "the DND store", "object names")
check(ns.Tables.class[1] == "novice explorer", "class titles")
check(#ns.HelpPages == 5, "help pages")
-- Lua 5.1 (unlike LuaJIT and 5.4) rejects a nested opening bracket inside a long string.
do
   local source = io.open(root .. "/Data/Help.lua"):read("*a")
   local position = 1
   while true do
      local from, to, equals = source:find("%[(=*)%[\n", position)
      if not from then break end
      local closer = "]" .. equals .. "]"
      local stop = source:find(closer, to, true)
      check(stop, "unterminated long string")
      check(not source:sub(to, stop):find("[" .. equals .. "[", 1, true), "nested long string bracket in Help.lua")
      position = stop + #closer
   end
end

---------------------------------------------------------------- input requests (own coroutine)
ns.main:Create()
local results = {}
ui.co = coroutine.create(function()
   results.yn = ui:YesNo("Sure?")
   results.num = ui:GetNumber("How many?", 500)
   ui:More()
   results.dir = ui:PickDirection("Which way?")
   results.star = ui:GetNumber("All?", 500)
   results.abort = ui:GetNumber("Abort?", 500)
   results.done = true
end)
ui:Resume()
keys("y"); check(results.yn == "y", "yes")
keys("12"); ui:InjectKey("BACKSPACE"); keys("7"); ui:InjectKey("ENTER"); check(results.num == 17, "number 17")
keys("x"); check(not results.dir, "more ignores x"); keys(" ")
ui:InjectKey("LEFT"); check(results.dir == 4, "arrow direction")
keys("*"); check(results.star == 500, "star = max")
ui:InjectKey("ESC"); check(results.abort == -1 and results.done, "abort = -1")

---------------------------------------------------------------- classes
local expect = {
   a = { hp = 16, ac = 0, wc = 0 }, b = { hp = 8, ac = 0, wc = 0 }, c = { hp = 14, ac = 3, wc = 0 },
   d = { hp = 8, ac = 2, wc = 0 }, e = { hp = 12, ac = 2, wc = 3 }, f = { hp = 10, ac = 2, wc = 3 },
   g = { hp = 12, ac = 0, wc = 10 }, h = { hp = 1, ac = 0, wc = 20 },
}
for _, class in ipairs(ns.Classes) do
   G.Reset()
   ns.Create.makePlayer(class)
   local e = expect[class.letter]
   check(G.c[K.HP] == e.hp and G.c[K.HPMAX] == e.hp, class.letter .. " hp")
   check(G.c[K.AC] == e.ac, class.letter .. " ac " .. G.c[K.AC])
   check(G.c[K.WCLASS] == e.wc, class.letter .. " wc " .. G.c[K.WCLASS])
   for slot = 1, #class.kit do check(G.iven[slot] == class.kit[slot][1], class.letter .. " kit") end
   check(G.playerx >= 2 and G.playerx <= K.MAXX - 1 and G.playery >= 2 and G.playery <= K.MAXY - 1, "start position")
end
G.Reset(); ns.Create.makePlayer(ns.Classes[2])
check(G.ivenarg[1] == K.PTREASURE and G.spelknow[2] == 1 and G.spelknow[5] == 1 and G.c[K.SPELLMAX] == 2, "mage kit")
G.Reset(); ns.Create.makePlayer(ns.Classes[8])
ns.mod.db.profile.races = true; UnitRace = function() return "Dwarf", "Dwarf" end
G.Reset(); ns.Create.makePlayer(ns.Classes[8]); check(G.race == "Dwarf" and G.c[K.CONSTITUTION] == ns.Classes[8].stats[4] + 2, "race bonus")
ns.mod.db.profile.races = nil; UnitRace = nil; G.Reset(); ns.Create.makePlayer(ns.Classes[8])
check(G.c[K.LANCEDEATH] == 1 and G.c[K.WIELD] == 1, "rambo")

---------------------------------------------------------------- town
G.Reset(); ns.Create.makePlayer(ns.Classes[1]); ns.Create.newCaveLevel(0)
local function buildings()
   local list = {}
   for x = 1, K.MAXX do for y = 1, K.MAXY do if G.item[x][y] ~= 0 then list[#list + 1] = x .. "," .. y .. "=" .. G.item[x][y] end end end
   return table.concat(list, " "), #list
end
local before, count = buildings()
check(count == 8, "eight buildings, got " .. count)
check(G.know[1][1] == 1 and G.know[K.MAXX][K.MAXY] == 1, "town fully known")
ns.Create.newCaveLevel(0)
check(buildings() == before, "level survives a save and restore")

---------------------------------------------------------------- dungeon levels
check(#ns.Maps >= 20 and #ns.Maps[1] == 17 and #ns.Maps[1][1] == 67, "maps loaded")
check(#ns.ItemTables.scprob == 81 and #ns.ItemTables.potprob == 41 and #ns.ItemTables.nobjtab == 37, "item tables")
math.randomseed(12345)
local function count(what)
   local n = 0
   for x = 1, K.MAXX do for y = 1, K.MAXY do if G.item[x][y] == what then n = n + 1 end end end
   return n
end
-- Floods from the first tile holding `from` through everything but walls (doors open,
-- diagonal steps allowed: a treasure room's door may sit in a corner).
local function reaches(from, to)
   local seen, queue, head = {}, {}, 1
   for x = 1, K.MAXX do for y = 1, K.MAXY do
      if G.item[x][y] == from and #queue == 0 then queue[1] = { x, y }; seen[x * 100 + y] = true end
   end end
   while queue[head] do
      local x, y = queue[head][1], queue[head][2]
      head = head + 1
      if G.item[x][y] == to then return true end
      for d = 1, 8 do
         local nx, ny = x + ns.Display.DIROFFX[d], y + ns.Display.DIROFFY[d]
         if nx >= 1 and nx <= K.MAXX and ny >= 1 and ny <= K.MAXY and not seen[nx * 100 + ny]
            and G.item[nx][ny] ~= K.OWALL then
            seen[nx * 100 + ny] = true
            queue[#queue + 1] = { nx, ny }
         end
      end
   end
   return false
end
local unreachable, total = 0, 0
for trial = 1, 8 do
   for lev = 1, 20 do
      G.Reset(); ns.Create.makePlayer(ns.Classes[1]); ns.Create.newCaveLevel(0)
      ns.Create.newCaveLevel(lev)
      local tag = "level " .. lev .. " trial " .. trial
      check(G.level == lev and G.Visited(lev), tag .. " made")
      check(count(K.OSTAIRSUP) == ((lev > 1 and lev ~= K.DBOTTOM) and 1 or 0), tag .. " stairs up " .. count(K.OSTAIRSUP))
      check(count(K.OSTAIRSDOWN) == ((lev ~= K.DBOTTOM and lev < K.VBOTTOM - 2) and 1 or 0), tag .. " stairs down")
      check(count(K.OVOLUP) == (lev == K.DBOTTOM + 1 and 1 or 0), tag .. " volcano shaft")
      for x = 1, K.MAXX do
         -- Canned maps have no exit on level 1; entering the dungeon opens it (as in the C).
         local exit = lev == 1 and x == 34
         check(G.item[x][1] == K.OWALL and (exit or G.item[x][K.MAXY] == K.OWALL), tag .. " wall row at x=" .. x)
      end
      for y = 1, K.MAXY do check(G.item[1][y] == K.OWALL and G.item[K.MAXX][y] == K.OWALL, tag .. " wall column") end
      if lev ~= K.DBOTTOM and lev + 1 <= 15 and lev > 1 and count(K.OSTAIRSUP) == 1 and count(K.OSTAIRSDOWN) == 1 then
         total = total + 1
         if not reaches(K.OSTAIRSUP, K.OSTAIRSDOWN) then unreachable = unreachable + 1 end
      end
   end
end
print(("stairs unreachable: %d of %d"):format(unreachable, total))
check(unreachable == 0, "stairs are connected")

-- a fresh level is unexplored: nothing is known until the player looks around
G.Reset(); ns.Create.makePlayer(ns.Classes[1]); ns.Create.newCaveLevel(0); ns.Create.newCaveLevel(5)
check(count(0) >= 0, "count helper")
do
   local known = 0
   for x = 1, K.MAXX do for y = 1, K.MAXY do known = known + G.know[x][y] end end
   check(known == 0, "fresh dungeon level is unknown, " .. known .. " tiles known")
   ns.Display.showcell(G.playerx, G.playery)
   for x = 1, K.MAXX do for y = 1, K.MAXY do known = known + G.know[x][y] end end
   check(known > 0 and known <= 9, "showcell reveals the neighbourhood, " .. known)
end

-- visited levels are restored as they were
G.Reset(); ns.Create.makePlayer(ns.Classes[1]); ns.Create.newCaveLevel(0); ns.Create.newCaveLevel(3)
G.item[2][2] = K.OALTAR; G.iarg[2][2] = 77
local snapshot = 0
for x = 1, K.MAXX do for y = 1, K.MAXY do snapshot = snapshot + G.item[x][y] * (x + y) end end
ns.Create.newCaveLevel(4); ns.Create.newCaveLevel(3)
local after = 0
for x = 1, K.MAXX do for y = 1, K.MAXY do after = after + G.item[x][y] * (x + y) end end
check(after == snapshot and G.item[2][2] == K.OALTAR and G.iarg[2][2] == 77, "level 3 restored")

-- createitem and gold
G.Reset(); ns.Create.makePlayer(ns.Classes[1]); ns.Create.newCaveLevel(0)
for x = 1, K.MAXX do for y = 1, K.MAXY do G.item[x][y] = 0 end end
G.playerx, G.playery = 30, 8
ns.Item.dropGold(100)
local piles = 0
for x = 29, 31 do for y = 7, 9 do if G.item[x][y] == K.OGOLDPILE then piles = piles + 1 end end end
check(piles == 1, "gold pile dropped")
for _ = 1, 50 do local id, arg = ns.Item.newObject(12); check(id >= 0 and arg >= 0, "newobject") end
check(ns.Player.packWeight() >= 0, "pack weight")

---------------------------------------------------------------- monsters and combat
ns.mod.db.profile.fast = true  -- no pauses: this part of the test runs outside the game thread
local function Fresh(level)
   G.Reset(); ns.Create.makePlayer(ns.Classes[1]); ns.Create.newCaveLevel(0); ns.Create.newCaveLevel(level)
   for x = 1, K.MAXX do for y = 1, K.MAXY do
      G.item[x][y], G.mon[x][y], G.hitp[x][y], G.stealth[x][y] = 0, 0, 0, 0
      G.know[x][y] = 1
   end end
   G.loot = {}
   G.playerx, G.playery = 30, 8
   LOG = {}
end
local function Monsters()
   local n = 0
   for x = 1, K.MAXX do for y = 1, K.MAXY do if G.mon[x][y] ~= 0 then n = n + 1 end end end
   return n
end
local function Put(id, x, y) G.mon[x][y] = id; G.hitp[x][y] = G.monster[id].hitpoints; G.stealth[x][y] = 1 end

-- levels come with monsters (and demon lords / princes on the deep ones)
for _, lev in ipairs({ 1, 5, 11, 15, 16, 20 }) do
   G.Reset(); ns.Create.makePlayer(ns.Classes[1]); ns.Create.newCaveLevel(0); ns.Create.newCaveLevel(lev)
   local n, lords, princes = 0, 0, 0
   for x = 1, K.MAXX do for y = 1, K.MAXY do
      local m = G.mon[x][y]
      if m ~= 0 then
         n = n + 1
         check(G.hitp[x][y] == G.monster[m].hitpoints and m <= 65, "monster hit points on level " .. lev)
         if m >= K.DEMONLORD and m < K.DEMONPRINCE then lords = lords + 1 end
         if m == K.DEMONPRINCE then princes = princes + 1 end
      end
   end end
   check(n >= 3, "level " .. lev .. " has monsters, got " .. n)
   if lev >= 11 and lev <= 15 then check(lords >= lev - 10, "demon lords on " .. lev) end
   if lev > 15 then check(princes >= lev - 15, "demon princes on " .. lev) end
end
-- makemonst honours the tier and genocide
Fresh(3)
for _ = 1, 200 do local m = ns.Monster.makeMonst(1); check(m >= 1 and m <= ns.Tables.monstlevel[1] + 1 or m == K.LEMMING, "tier 1 monster " .. m) end
G.monster[K.KOBOLD].flags = K.FL_GENOCIDED
for _ = 1, 200 do check(ns.Monster.makeMonst(1) ~= K.KOBOLD, "genocided monsters are skipped") end

-- a monster walks to the player and attacks
Fresh(3); G.c[K.AC] = 0; G.c[K.HP] = 1000; G.c[K.HPMAX] = 1000
Put(K.ORC, 35, 8)
for _ = 1, 20 do
   ns.Monster.movemonst(); G.gtime = G.gtime + 1
   if G.hitflag then break end
end
check(G.hitflag and (G.c[K.HP] < 1000 or (last() or ""):find("missed")), "orc reached and attacked the player")
check(G.mon[35][8] == 0, "orc left its spot")
-- a smart monster finds its way around a wall
Fresh(3); G.c[K.HP] = 1000; G.c[K.HPMAX] = 1000
for y = 3, 13 do G.item[33][y] = y == 11 and 0 or K.OWALL end  -- one gap, inside the window
Put(K.ELF, 35, 9)  -- smart: finds the way round the wall
local ox, oy = 35, 9
for _ = 1, 30 do ns.Monster.movemonst(); G.gtime = G.gtime + 1 end
local found = false
for x = 1, K.MAXX do for y = 1, K.MAXY do if G.mon[x][y] == K.ELF then found = true; ox, oy = x, y end end end
check(found and math.max(math.abs(ox - 30), math.abs(oy - 8)) <= 1 or G.hitflag, "elf closed in around the wall: " .. ox .. "," .. oy)

-- the player kills a monster: experience, gold and drops
Fresh(3)
G.c[K.STRENGTH] = 30; G.c[K.DEXTERITY] = 30
Put(K.ORC, 31, 8); G.hitp[31][8] = 1
local xp = G.c[K.EXPERIENCE]
ns.Monster.hitmonster(31, 8)
for _ = 1, 20 do if G.mon[31][8] ~= 0 then ns.Monster.hitmonster(31, 8) end end
check(G.mon[31][8] == 0, "orc died")
check(G.c[K.EXPERIENCE] > xp, "experience gained")
check(G.hit3flag, "hit flag set")
local drops = 0
for x = 28, 33 do for y = 6, 10 do if G.item[x][y] ~= 0 then drops = drops + 1 end end end
check(drops >= 1, "the orc left gold or an item")
-- experience raises the level
Fresh(3)
local lvl = G.c[K.LEVEL]
ns.Player.raiseExperience(ns.Tables.skill[lvl + 1])
check(G.c[K.LEVEL] == lvl + 1 and G.c[K.HPMAX] > 16, "level up")
ns.Player.loseLevel()
check(G.c[K.LEVEL] == lvl, "level drained")

-- every special attack runs
for attack = 1, 16 do
   Fresh(3)
   G.c[K.HP] = 5000; G.c[K.HPMAX] = 5000; G.c[K.GOLD] = 1000; G.c[K.WEAR] = 1
   G.iven[1], G.ivenarg[1], G.iven[3], G.ivenarg[3] = K.OLEATHER, 1, K.ODAGGER, 2
   Put(K.LEPRECHAUN, 31, 8); G.lastmonst = "thing"
   ns.Monster.spattack(attack, 31, 8)
end
check(not G.dead, "special attacks at full health do not kill")
-- the leprechaun steals gold and vanishes
Fresh(3); G.c[K.GOLD] = 1000; Put(K.LEPRECHAUN, 31, 8)
check(ns.Monster.spattack(8, 31, 8) == true and G.mon[31][8] == 0 and G.c[K.GOLD] < 1000, "gold stolen")
-- the nymph steals an item, keeps it through a save, and drops it when she dies
Fresh(3)
for i = 1, K.IVENSIZE do G.iven[i], G.ivenarg[i] = 0, 0 end
G.c[K.WIELD], G.c[K.WEAR], G.c[K.SHIELD] = 0, 0, 0
G.iven[5], G.ivenarg[5] = K.OPOTION, 2; Put(K.NYMPH, 31, 8)
local function FindNymph()
   for x = 1, K.MAXX do for y = 1, K.MAXY do
      if G.mon[x][y] == K.NYMPH then return x, y end
   end end
end
local function HasPotion()
   for _, list in pairs(G.loot) do
      for _, entry in ipairs(list) do if entry[1] == K.OPOTION then return true end end
   end
   return false
end
-- stealing may fail now and then (100 random picks); try again like a determined nymph
for _ = 1, 10 do
   if not HasPotion() then
      local nx, ny = FindNymph()
      ns.Monster.spattack(14, nx, ny)
   end
end
check(HasPotion() and G.iven[5] == 0, "the potion is in the nymph's loot")
G.SaveLevel(); G.loot = {}; G.GetLevel()
check(HasPotion(), "loot survives a level save")
local nx, ny = FindNymph()
G.hitp[nx][ny] = 1
G.c[K.EXPERIENCE] = 0
ns.Monster.hitm(nx, ny, 50)
check(G.mon[nx][ny] == 0 and next(G.loot) == nil, "dead nymph gives up her loot")
local potions = 0
for x = 1, K.MAXX do for y = 1, K.MAXY do if G.item[x][y] == K.OPOTION then potions = potions + 1 end end end
check(potions >= 1, "the stolen potion is on the floor")
-- difficulty scaling (C: sethard)
G.Reset(); G.c[K.HARDGAME] = 2; ns.Monster.init()
check(G.monster[K.ORC].hitpoints > ns.MonsterData[K.ORC].hitpoints, "harder game, tougher monsters")
G.Reset(); ns.Monster.init()
check(G.monster[K.ORC].hitpoints == ns.MonsterData[K.ORC].hitpoints, "normal game leaves monsters alone")
-- the death of the player
Fresh(3); G.c[K.HP] = 1; G.c[K.AC] = 0; Put(K.DEMONLORD, 31, 8)
for _ = 1, 20 do if not G.dead then ns.Monster.hitplayer(31, 8) end end
check(G.dead, "the player died to a demon lord")
-- a death stops the turn: one death message however many monsters are adjacent
Fresh(3); G.c[K.HP] = 1; G.c[K.AC] = 0; G.c[K.STEALTH] = 0
Put(K.ELF, 31, 8); Put(K.ELF, 31, 9); Put(K.ELF, 29, 8)
for _ = 1, 5 do if not G.dead then ns.Monster.movemonst(); G.gtime = G.gtime + 1 end end
local alas = 0
for _, l in ipairs(lines()) do if l:find("Alas") then alas = alas + 1 end end
check(G.dead and alas == 1, "one death message, got " .. alas)
-- losehp
Fresh(3); G.c[K.HP] = 10; ns.Player.losehp(3); check(G.c[K.HP] == 7 and not G.dead, "losehp"); ns.Player.losehp(7); check(G.dead, "dead at 0 hp")

---------------------------------------------------------------- items
check(ns.Tables.potionname[K.PHEALING] == "healing" and ns.Tables.scrollname[K.SENCHANTARM] == "enchant armor", "names")
check(ns.Tables.spelcode[1] == "pro" and ns.Tables.spelname[39] == "permanence" and #ns.Fortunes > 30, "spell and fortune data")
Fresh(3)
for i = 1, K.IVENSIZE do G.iven[i], G.ivenarg[i] = 0, 0 end
G.c[K.WIELD], G.c[K.WEAR], G.c[K.SHIELD] = 0, 0, 0
G.c[K.LEVEL] = 1
check(G.potionknown[K.PINSTHEAL] == 1 and G.potionknown[K.PHEALING] == 0, "initial potion knowledge")
-- the pack holds 15 + level/2 things
local taken = 0
for _ = 1, 30 do if ns.Player.take(K.OPOTION, K.PHEALING) then taken = taken + 1 end end
check(taken == 15, "pack limit at level 1, got " .. taken)
check(ns.Player.pocketFull(), "pocket full")
for i = 1, K.IVENSIZE do G.iven[i], G.ivenarg[i] = 0, 0 end
-- rings and the hammer change the stats while carried
G.c[K.DEXTERITY] = 10
ns.Player.take(K.ODEXRING, 2)
check(G.c[K.DEXTERITY] == 13, "ring of dexterity")
check(ns.Player.dropObject(1) == false and G.item[G.playerx][G.playery] == K.ODEXRING and G.c[K.DEXTERITY] == 10, "drop gives it back")
-- Bessman's hammer: +10 strength and dexterity, -10 intelligence, given back as they were taken
G.item[G.playerx][G.playery], G.iarg[G.playerx][G.playery] = 0, 0
G.c[K.INTELLIGENCE] = 12
ns.Player.take(K.OHAMMER, 0)
check(G.c[K.INTELLIGENCE] == 2, "the hammer takes 10 intelligence")
G.c[K.INTELLIGENCE] = G.c[K.INTELLIGENCE] + 2  -- (something raises it meanwhile)
ns.Player.dropObject(1)
check(G.c[K.INTELLIGENCE] == 14, "dropping the hammer gives back 10, got " .. G.c[K.INTELLIGENCE])
G.item[G.playerx][G.playery], G.iarg[G.playerx][G.playery] = 0, 0
check(ns.Player.dropObject(2) == false or true, "dropping nothing is fine")
check(G.dropflag, "dropflag set")
-- item names
G.iven[1], G.ivenarg[1] = K.OPOTION, K.PHEALING
check(ns.Player.itemName(1) == "magic potion" or ns.Player.itemName(1):find("potion"), "unknown potion name: " .. ns.Player.itemName(1))
G.potionknown[K.PHEALING] = 1
check(ns.Player.itemName(1):find("of healing"), "known potion name")
G.iven[2], G.ivenarg[2] = K.OLONGSWORD, 2; G.c[K.WIELD] = 2
check(ns.Player.itemName(2):find("%+2") and ns.Player.itemName(2):find("weapon in hand"), "weapon name: " .. ns.Player.itemName(2))
-- enchanting
ns.Player.recalc()
local wc = G.c[K.WCLASS]
ns.Player.enchantWeapon(K.ENCH_SCROLL)
check(G.ivenarg[2] == 3 and G.c[K.WCLASS] == wc + 1, "weapon enchanted")
G.ivenarg[2] = 9
ns.Player.enchantWeapon(K.ENCH_ALTAR)
check(G.ivenarg[2] == 9 and G.iven[2] == K.OLONGSWORD, "an altar does not destroy")
for _ = 1, 50 do if G.iven[2] ~= 0 then G.ivenarg[2] = 9; ns.Player.enchantWeapon(K.ENCH_SCROLL) end end
check(G.iven[2] == 0 and G.c[K.WIELD] == 0, "a +10 weapon crumbles")
G.c[K.WEAR] = 0; G.c[K.SHIELD] = 0
ns.Player.enchantArmor(K.ENCH_SCROLL)
check((last() or ""):find("sense of loss"), "no armor to enchant")
G.iven[3], G.ivenarg[3] = K.OLEATHER, 0; G.c[K.WEAR] = 3; ns.Player.recalc()
local ac = G.c[K.AC]
ns.Player.enchantArmor(K.ENCH_SCROLL)
check(G.ivenarg[3] == 1 and G.c[K.AC] == ac + 1, "armor enchanted")

-- every potion
for pot = 1, 24 do
   Fresh(3); G.c[K.HP] = 20; G.c[K.HPMAX] = 40
   ns.Monster.fillMonst(1)
   ns.Magic.quaffPotion(pot)
   check(G.potionknown[pot] == 1, "potion " .. pot .. " becomes known")
   check(not G.dead, "potion " .. pot .. " does not kill")
end
Fresh(3); G.c[K.HP] = 20; G.c[K.HPMAX] = 40; ns.Magic.quaffPotion(K.PINSTHEAL); check(G.c[K.HP] == 40, "instant healing")
Fresh(3); G.c[K.STRENGTH] = 10; ns.Magic.quaffPotion(K.PSTRENGTH); check(G.c[K.STRENGTH] == 12, "strength potion")
Fresh(3); local l0 = G.c[K.LEVEL]; ns.Magic.quaffPotion(K.PRAISELEVEL); check(G.c[K.LEVEL] == l0 + 1, "raise level potion")
Fresh(3); ns.Magic.quaffPotion(K.PHEROISM); local str = G.c[K.STRENGTH]; ns.Magic.quaffPotion(K.PHEROISM)
check(G.c[K.HERO] == 500 and G.c[K.STRENGTH] == str, "hero bonus only once")
Fresh(3); ns.Magic.quaffPotion(K.PFORGETFUL)
local known = 0
for x = 1, K.MAXX do for y = 1, K.MAXY do known = known + G.know[x][y] end end
check(known == 0, "forgetfulness forgets the map")
Fresh(3); G.c[K.AWARENESS] = 0
-- every scroll
for typ = 1, 24 do
   if typ ~= K.SPULVERIZE then
      Fresh(3); G.iven[1], G.ivenarg[1] = K.OLEATHER, 0; G.c[K.WEAR] = 1
      ns.Monster.fillMonst(1)
      ns.Magic.readScroll(typ)
      check(G.scrollknown[typ] == 1 and not G.dead, "scroll " .. typ)
   end
end
Fresh(3); for x = 1, K.MAXX do for y = 1, K.MAXY do G.know[x][y] = 0 end end
ns.Magic.readScroll(K.SMAGICMAP)
check(G.know[1][1] == 1 and G.know[K.MAXX][K.MAXY] == 1, "magic mapping")
Fresh(3); G.c[K.HP] = 5; G.c[K.HALFDAM] = 300; G.c[K.CONFUSE] = 40
ns.Magic.readScroll(K.SREMCURSE)
check(G.c[K.HALFDAM] == 1 and G.c[K.CONFUSE] == 1, "remove curse")
Fresh(3); G.gtime = 5000; G.c[K.HERO] = 500
ns.Magic.readScroll(K.STIMEWARP)
check(G.gtime ~= 5000, "time warp moves the clock")
Fresh(3); Put(K.ORC, 31, 8); Put(K.ORC, 29, 7); Put(K.DEMONLORD, 30, 9)
ns.Magic.readScroll(K.SANNIHILATE)
check(G.mon[31][8] == 0 and G.mon[29][7] == 0 and G.mon[30][9] == K.DEMONLORD, "annihilation spares the demon")
-- books teach a spell
Fresh(3); G.spelknow[1] = 0; ns.Magic.readBook(0)
check(G.spelknow[1] == 1, "a level 0 book teaches protection")
-- teleport
Fresh(3); ns.Magic.teleport(false)
check(G.c[K.TELEFLAG] == 1 and G.level >= 0 and G.level <= K.DBOTTOM, "teleport stays on the right levels")
-- pack weight changes with what you carry
Fresh(3); for i = 1, K.IVENSIZE do G.iven[i], G.ivenarg[i] = 0, 0 end
G.c[K.GOLD] = 0
local w0 = ns.Player.packWeight()
G.iven[1] = K.OPLATE
check(ns.Player.packWeight() == w0 + 35, "plate weighs 35")
-- the inventory window runs with everything in it
ns.inventory:Open("test", function(id) return id == K.OPLATE end); ns.inventory:Update(); ns.inventory:Close()

---------------------------------------------------------------- the game
ui.co = nil
ui:NewGame()
check(ui.wait == "key" and ns.picker.frame.shown, "class picker waits")
ui:InjectKey("UP"); ui:InjectKey("ENTER")  -- Mage is the default (index 2); Up goes to 1
check(G.class and G.class.token == "WARRIOR", "picked via arrows and enter")
check(ui.wait == "key", "welcome asks for more")
local story = false
for _, l in ipairs(lines()) do if l:find("Welcome to the game of Ularn") then story = true end end
check(story, "story shown")
keys(" ")
check(last():find("You set out as Warrior"), "set out message, got " .. tostring(last()))

ns.mod.db.profile.fast = true
for x = 1, K.MAXX do for y = 1, K.MAXY do G.item[x][y] = 0 end end  -- clear the field for movement tests
G.playerx, G.playery = 10, 8
local t0 = G.gtime
keys("3l"); check(G.playerx == 13 and G.playery == 8, "repeat count: x=" .. G.playerx)
check(G.gtime == t0 + 3, "three turns passed, got " .. (G.gtime - t0))
keys("k"); check(G.playery == 7, "north")
keys("b"); check(G.playerx == 12 and G.playery == 8, "southwest")
t0 = G.gtime
keys("H"); check(G.playerx == 1, "run west ends at the edge, x=" .. G.playerx)
check(G.gtime == t0 + 11, "run took 11 turns, got " .. (G.gtime - t0))
t0 = G.gtime
keys("h"); check(G.playerx == 1 and G.gtime == t0, "wall of the map costs no turn")
ui:InjectKey("UP"); check(G.playery == 7, "arrow keys move")
G.item[5][7] = K.OBANK
keys("L"); check(G.playerx == 5, "run stops on an object, x=" .. G.playerx)
check(last():find("the bank of Ularn"), "object message, got " .. tostring(last()))
keys("i"); G.item[5][7] = 0  -- stay outside
keys("S"); check(not ns.main.frame.shown, "S closes the window")
ns.main:Show(); keys("."); keys("?"); check(last():find("help") or #LOG > 20, "help logged")
keys("x"); check(last():find("not implemented"), "unknown command")
ui:InjectKey("ESC"); check(not ns.main.focused, "Esc releases the keyboard")
keys("Q"); keys("n"); check(ui:IsActive(), "quit declined")
keys("Q"); keys("y"); check(not ui:IsActive(), "quit ends the game")
keys("a"); check(ui:IsActive() and ns.picker.frame.shown, "any key starts a new game")

-- stairs, entrance and shaft in a real game
ns.picker.frame.shown = true
ui:InjectKey("ENTER"); keys(" ")
check(G.class and ui.wait == "key", "new game ready")
local function Neighbour(what)
   -- puts the player beside the object and returns the direction key that steps onto it
   for x = 1, K.MAXX do for y = 1, K.MAXY do
      if G.item[x][y] == what then
         for key, dir in pairs({ j = 1, l = 2, k = 3, h = 4 }) do
            local nx, ny = x - ns.Display.DIROFFX[dir], y - ns.Display.DIROFFY[dir]
            if nx >= 1 and nx <= K.MAXX and ny >= 1 and ny <= K.MAXY and G.item[nx][ny] ~= K.OWALL then
               G.item[nx][ny] = 0; G.mon[nx][ny] = 0
               G.playerx, G.playery = nx, ny; G.lookedHere = nil
               return key
            end
         end
      end
   end end
   error("object not found: " .. what)
end
local key = Neighbour(K.OENTRANCE)
keys(key); check(last():find("You have found") and ui.wait == "key", "entrance prompt, got " .. tostring(last()))
keys("g"); check(G.level == 1 and G.playerx == 34 and G.playery == K.MAXY - 1, "entered the dungeon at " .. G.playerx .. "," .. G.playery)
keys("j"); check(G.level == 0 and G.item[G.playerx][G.playery] ~= K.OENTRANCE or G.level == 0, "left the dungeon")
check(G.level == 0, "exit from level 1 leads to town")
key = Neighbour(K.OVOLDOWN)
keys(key); keys("c"); check(G.level == K.DBOTTOM + 1 and count(K.OVOLUP) == 1, "down the volcano shaft to " .. G.level)
ns.Create.newCaveLevel(2)
key = Neighbour(K.OSTAIRSUP)
keys(key); check(last():find("circular staircase") and ui.wait == "key", "stairs prompt, got " .. tostring(last()))
keys("u"); check(G.level == 1 and G.item[G.playerx][G.playery] == K.OSTAIRSDOWN, "up the stairs")
key = Neighbour(K.OSTAIRSDOWN)
keys(key); keys("d"); check(G.level == 2 and G.item[G.playerx][G.playery] == K.OSTAIRSUP, "down the stairs")
-- fighting in the game thread: walking into a monster attacks it, and it fights back
ns.Create.newCaveLevel(3)
for x = 1, K.MAXX do for y = 1, K.MAXY do G.item[x][y], G.mon[x][y] = 0, 0 end end
G.playerx, G.playery = 30, 8
G.c[K.HP], G.c[K.HPMAX] = 10000, 10000  -- this fight must not end the game
Put(K.ORC, 31, 8)
LOG = {}
keys("l")
local fought = false
for _, l in ipairs(lines()) do if l:find("You hit the orc") or l:find("You missed the orc") then fought = true end end
check(fought and G.playerx == 30, "bumping a monster attacks it, got " .. table.concat(lines(), " | "))
for _ = 1, 40 do if G.mon[31][8] ~= 0 and not G.dead then keys("l") end end
check(G.mon[31][8] == 0 or G.dead, "fight ended")
if G.dead then check(not ui:IsActive() or last():find("Game over"), "death ends the game") end

-- items in the game thread
ns.Create.newCaveLevel(3)
local function Clear()
   for x = 1, K.MAXX do for y = 1, K.MAXY do G.item[x][y], G.mon[x][y] = 0, 0 end end
   G.playerx, G.playery = 30, 8
   G.c[K.HP] = G.c[K.HPMAX]
   for i = 1, K.IVENSIZE do G.iven[i], G.ivenarg[i] = 0, 0 end
   G.c[K.WIELD], G.c[K.WEAR], G.c[K.SHIELD] = 0, 0, 0
   G.dropflag = false
   G.lookedHere = nil
   LOG = {}
end
Clear()
G.iven[1], G.ivenarg[1] = K.ODAGGER, 1
G.iven[2], G.ivenarg[2] = K.OLEATHER, 0
G.iven[3], G.ivenarg[3] = K.OPOTION, K.PHEALING
G.iven[4], G.ivenarg[4] = K.OSCROLL, K.SBLANK
G.iven[5], G.ivenarg[5] = K.OCOOKIE, 0
G.iven[6], G.ivenarg[6] = K.OSHIELD, 0
G.iven[7], G.ivenarg[7] = K.O2SWORD, 0
keys("w"); check(ui.wait == "key", "wield asks for an item")
keys("a"); check(G.c[K.WIELD] == 1, "wielded the dagger: " .. table.concat({ unpack(lines(), math.max(1, #lines() - 4)) }, " | ")); check(G.c[K.WCLASS] == 4, "dagger wc " .. G.c[K.WCLASS] .. " moredam " .. G.c[K.MOREDAM] .. " iven " .. G.iven[1] .. " arg " .. G.ivenarg[1])
keys("w"); keys("-"); check(G.c[K.WIELD] == 0, "unwield with -")
keys("W"); keys("b"); check(G.c[K.WEAR] == 2 and G.c[K.AC] == 2, "wore the leather armor")
keys("W"); keys("b"); check((last() or ""):find("already wearing"), "only one armor")
keys("W"); keys("f"); check(G.c[K.SHIELD] == 6, "wore the shield")
keys("w"); keys("g"); check(G.c[K.WIELD] == 0 and (last() or ""):find("busy with your shield"), "two-hander needs both hands")
keys("T"); check(G.c[K.SHIELD] == 0 and (last() or ""):find("shield is off"), "take off the shield first")
keys("T"); check(G.c[K.WEAR] == 0, "then the armor")
keys("T"); check((last() or ""):find("aren't wearing"), "nothing to take off")
G.c[K.HP] = 1; G.c[K.HPMAX] = 100
keys("q"); keys("a"); check(G.c[K.HP] == 1, "can't quaff a dagger")
keys("q"); keys("c"); check(G.c[K.HP] > 1 and G.iven[3] == 0 and G.potionknown[K.PHEALING] == 1, "quaffed the potion")
keys("r"); keys("d"); check(G.iven[4] == 0 and G.scrollknown[K.SBLANK] == 1, "read the scroll")
keys("e"); keys("e"); check(G.iven[5] == 0, "ate the cookie")
keys("q"); ui:InjectKey("ESC"); check(ui.wait == "key" and (last() or ""):find("aborted"), "Esc cancels")
G.iven[5], G.ivenarg[5] = K.OHASH, 0; local wisdom = G.c[K.WISDOM]; keys("q"); keys("e"); check(G.iven[5] == 0 and G.c[K.WISDOM] == wisdom + 2, "drank the elixir from the pack")
keys("i"); check(ui.wait == "key", "inventory waits for a key"); keys(" ")
keys("g"); check((last() or ""):find("weighs"), "pack weight")
-- dropping an item and gold
G.c[K.GOLD] = 500
keys("d"); keys("a"); check(G.item[30][8] == K.ODAGGER and G.iven[1] == 0, "dropped the dagger")
G.item[30][8] = 0
keys("d"); keys("."); keys("2"); keys("0"); ui:InjectKey("ENTER")
check(G.c[K.GOLD] == 480 and G.item[30][8] == K.OGOLDPILE and G.iarg[30][8] == 20, "dropped 20 gold")
-- walking onto things
local function Step(object, arg, key)
   Clear(); G.item[31][8] = object; G.iarg[31][8] = arg
   keys(key or "l")
end
G.c[K.GOLD] = 0
Step(K.OGOLDPILE, 77); check(G.c[K.GOLD] == 77 and G.item[31][8] == 0, "picked up gold")
Step(K.OPOTION, K.PSTRENGTH); check(ui.wait == "key", "potion asks")
keys("t"); check(G.iven[1] == K.OPOTION and G.item[31][8] == 0, "took the potion")
Step(K.OSCROLL, K.SBLANK); keys("i"); check(G.item[31][8] == K.OSCROLL and G.iven[1] == 0, "ignored the scroll")
Step(K.OCOOKIE, 0); keys("e"); check(G.item[31][8] == 0 and table.concat(lines(), "|"):find("tasted good"), "ate a cookie from the floor")
Step(K.OLONGSWORD, 2); keys("t"); check(G.iven[1] == K.OLONGSWORD and G.ivenarg[1] == 2, "took a sword")
Step(K.OBOOK, 0); keys("r"); local s = 0; for i = 1, K.SPNUM do s = s + G.spelknow[i] end
check(s >= 1 and G.item[31][8] == 0, "read a book")
Step(K.ODIAMOND, 25); keys("t"); check(G.iven[1] == K.ODIAMOND, "took a diamond")
Step(K.OWALL, 0); check(G.playerx == 30, "wall blocks")
-- traps
Step(K.OTRAPARROW, 0); check(G.c[K.HP] < G.c[K.HPMAX], "arrow trap hurts")
Step(K.ODARTRAP, 0); check(G.c[K.HP] < G.c[K.HPMAX], "dart trap hurts")
Clear(); G.item[31][8] = K.OTELEPORTER; local lv = G.level; keys("l"); check(G.c[K.TELEFLAG] == 1, "teleporter")
ns.Create.newCaveLevel(3); Clear(); G.item[31][8] = K.OTRAPDOOR; keys("l"); check(G.level == 4, "trap door falls to the next level: " .. G.level)
ns.Create.newCaveLevel(5); Clear(); G.item[31][8] = K.OELEVATORUP; keys("l"); check(G.level >= 0 and G.level <= 4, "elevator up: " .. G.level)
ns.Create.newCaveLevel(3); Clear(); G.item[31][8] = K.OCLOSEDDOOR; G.iarg[31][8] = 3; G.lastpx, G.lastpy = 30, 8
keys("l"); check(ui.wait == "key", "door asks"); keys("o")
check(G.item[31][8] == K.OOPENDOOR or G.playerx == 30, "door opened or held")
if G.item[31][8] == K.OOPENDOOR then keys("C"); check(true) end
Clear(); G.item[30][8] = K.OOPENDOOR; keys("C"); check(G.item[30][8] == K.OCLOSEDDOOR, "closed the door")
Clear(); G.item[31][8] = K.OTRAPDOOR; keys("^"); check((last() or ""):find("trapdoor"), "found the trap door: " .. tostring(last()) .. " wait=" .. tostring(ui.wait))
-- a chest
Clear(); G.item[31][8] = K.OCHEST; G.iarg[31][8] = 2; keys("l"); check(ui.wait == "key", "chest asks")
keys("t"); check(G.iven[1] == K.OCHEST, "took the chest")
Clear(); G.item[31][8] = K.OCHEST; G.iarg[31][8] = 2; keys("l"); keys("o")
check(G.item[31][8] ~= K.OCHEST or (last() or ""):find("lock holds"), "opened the chest")
-- spells, cast in the live game thread
do
   local savedc, savedspells = {}, {}
   for i = 1, 100 do savedc[i] = G.c[i] end
   for i = 1, K.SPNUM do savedspells[i] = G.spelknow[i] end
   local oldfast = ns.mod.db.profile.fast
   ns.mod.db.profile.fast = true
   local T = ns.Tables
   local function Code(name)
      for i = 1, K.SPNUM do if T.spelname[i] == name then return T.spelcode[i], i end end
      error("no spell " .. name)
   end
   local function Arena()
      ns.Create.newCaveLevel(3); Clear()
      for i = 1, K.SPNUM do G.spelknow[i] = 1 end
      G.c[K.INTELLIGENCE], G.c[K.WISDOM], G.c[K.CHARISMA], G.c[K.LEVEL] = 25, 25, 25, 40
      G.c[K.HP], G.c[K.HPMAX] = 5000, 5000
      G.c[K.CONFUSE], G.c[K.BLINDCOUNT], G.c[K.TIMESTOP], G.c[K.HOLDMONST], G.c[K.CANCELLATION] = 0, 0, 0, 0, 0
   end
   local function Cast(name, dir)
      local code = Code(name)
      for _ = 1, 40 do
         G.c[K.SPELLS] = 50; LOG = {}
         keys("c"); keys(code)
         if dir and debug.traceback(ui.co):find("PickDirection") then keys(dir) end
         local text = table.concat(lines(), "|")
         check(not debug.traceback(ui.co):find("FindItem"), "stuck on an item after casting " .. name .. " at " .. G.playerx .. "," .. G.playery .. " item " .. G.item[G.playerx][G.playery] .. ": " .. text)
         if not (text:find("didn't work") or text:find("Nothing happens") or text:find("lock holds")) then return text end
         if ui.wait == "key" then ui:InjectKey("ESC") end
      end
      error("the spell " .. name .. " never worked")
   end
   local function Monster(x, y, id)
      G.monster[id].hitpoints = 100000  -- (hitm clamps to the table)
      G.mon[x][y], G.hitp[x][y] = id, 100000
   end

   Arena(); keys("c"); check(ui.wait == "key" and ns.spellbook:IsShown(), "casting shows the spellbook")
   ui:InjectKey("ESC"); check(last():find("aborted") and not ns.spellbook:IsShown(), "Esc aborts casting")
   G.c[K.SPELLS] = 0; LOG = {};keys("c"); check(last():find("any mana"), "no spells left")
   G.c[K.SPELLS] = 5; keys("c"); keys("zzz"); check(ui.wait == "key" and G.c[K.SPELLS] == 4, "an unknown code costs a spell and asks again")
   ui:InjectKey("ESC")
   ns.spellbook:ShowDiscoveries(); ns.spellbook:Open(); ns.spellbook:Close()

   Arena(); LOG = {}; check(ns.Spells.noSpell(select(2, Code("invisibility")), K.GNOME) and last():find("infravision"), "a gnome sees through invisibility")
   check(not ns.Spells.noSpell(select(2, Code("fireball")), K.GNOME), "a gnome burns")
   -- buffs
   Arena(); Cast("protection"); check(G.c[K.PROTECTIONTIME] >= 240 and G.c[K.MOREDEFENSES] >= 2, "protection")
   Arena(); Cast("dexterity"); check(G.c[K.DEXCOUNT] >= 390, "dexterity")
   Arena(); Cast("strength"); check(G.c[K.STRCOUNT] >= 140 and G.c[K.STREXTRA] >= 3, "strength")
   Arena(); Cast("charm monster"); check(G.c[K.CHARMCOUNT] >= 40, "charm")
   Arena(); Cast("invisibility"); check(G.c[K.INVISIBILITY] >= 10, "invisibility")
   Arena(); Cast("cancellation"); check(G.c[K.CANCELLATION] >= 5, "cancellation")
   Arena(); Cast("haste self"); check(G.c[K.HASTESELF] >= 7, "haste self")
   Arena(); Cast("walk through walls"); check(G.c[K.WTW] >= 5, "walk through walls")
   Arena(); Cast("hold monster"); check(G.c[K.HOLDMONST] >= 1, "hold monster")
   Arena(); Cast("scare monster"); check(G.c[K.SCAREMONST] >= 1, "scare monster")
   Arena(); Cast("invulnerability"); check(G.c[K.GLOBE] >= 190 and G.c[K.INTELLIGENCE] == 24, "globe costs intelligence")
   Arena(); Cast("time stop"); check(G.c[K.TIMESTOP] >= 1, "time stop"); G.c[K.TIMESTOP] = 0
   Arena(); G.c[K.HP] = 10; Cast("healing"); check(G.c[K.HP] > 10, "healing")
   Arena(); G.c[K.BLINDCOUNT] = 50; Cast("cure blindness"); check(G.c[K.BLINDCOUNT] == 0, "cure blindness")
   Arena(); for x = 1, K.MAXX do for y = 1, K.MAXY do G.know[x][y] = 0 end end
   Cast("enlightenment"); check(G.know[30][8] == 1 and G.know[40][12] == 1, "enlightenment maps the area")

   -- directed spells
   Arena(); Monster(33, 8, K.ORC); Cast("magic missile", "l"); check(G.hitp[33][8] < 100000, "magic missile hits")
   Arena(); Monster(33, 8, K.ORC); Cast("sonic spear", "l"); check(G.hitp[33][8] < 100000, "sonic spear hits")
   Arena(); Monster(33, 8, K.ORC); Cast("fireball", "l"); check(G.hitp[33][8] < 100000, "fireball hits")
   Arena(); Monster(33, 8, K.ORC); Cast("cold", "l"); check(G.hitp[33][8] < 100000, "cone of cold hits")
   Arena(); Monster(33, 8, K.ORC); Cast("lightning", "l"); check(G.hitp[33][8] < 100000, "lightning hits")
   Arena(); Monster(31, 8, K.ORC); Cast("sleep", "l"); check(G.hitp[31][8] < 100000, "sleep smashes")
   Arena(); Monster(31, 8, K.ORC); Cast("web", "l"); check(G.hitp[31][8] < 100000, "web smashes")
   Arena(); Monster(31, 8, K.ORC); Cast("phantasmal forces", "l"); check(G.hitp[31][8] < 100000, "phantasmal forces")
   Arena(); Monster(31, 8, K.ORC); local t_ = Cast("dehydration", "l");  check(G.hitp[31][8] < 100000, "dehydration")
   Arena(); Monster(31, 8, K.ORC); Cast("drain life", "l"); check(G.hitp[31][8] < 100000, "drain life")
   Arena(); Monster(31, 8, K.ORC); Cast("finger of death", "l")
   Arena(); Monster(31, 8, K.ORC); Cast("summon demon", "l")
   Arena(); Monster(31, 8, K.ORC); Cast("teleport away", "l"); check(G.mon[31][8] == 0, "teleport away moves it")
   Arena(); Monster(31, 8, K.ORC); Cast("polymorph", "l"); check(G.mon[31][8] ~= 0, "polymorph")
   Arena(); Cast("magic missile", "l"); check(table.concat(lines(), "|"):find("anything there") == nil, "a missile flies on")
   Arena(); Cast("sleep", "l"); check(table.concat(lines(), "|"):find("anything there"), "nothing to sleep")
   Arena(); G.c[K.CONFUSE] = 20; Monster(33, 8, K.ORC); Cast("fireball", "l"); check(G.hitp[33][8] == 100000, "confused: no aim")
   Arena(); G.item[33][8] = K.OWALL; Cast("fireball", "l"); check(G.item[33][8] == 0, "a fireball breaks a wall")
   Arena(); G.item[33][8] = K.OCLOSEDDOOR; Cast("fireball", "l"); check(G.item[33][8] == 0, "a fireball blasts a door")
   Arena(); G.item[33][8] = K.OSTATUE; Cast("fireball", "l"); check(G.item[33][8] == K.OBOOK, "a fireball breaks a statue")
   Arena(); G.item[33][8] = K.OTHRONE; Cast("fireball", "l"); check(G.item[33][8] == K.OTHRONE2, "a fireball breaks the throne")
   Arena(); G.item[32][8] = K.OMIRROR; G.c[K.HP] = 5000; Cast("fireball", "l"); check(G.c[K.HP] < 5000, "a mirror reflects the fireball")
   Arena(); G.item[31][8] = K.OMIRROR; Cast("dehydration", "l"); check(G.c[K.HP] < 5000, "a mirror reflects a direct spell")
   Arena(); Cast("make a wall", "l"); check(G.item[31][8] == K.OWALL, "make a wall")
   Arena(); Cast("make a wall", "l"); Cast("make a wall", "l"); check(table.concat(lines(), "|"):find("wall there already"), "no wall on a wall")

   -- area spells
   for _, name in ipairs({ "cloud kill", "flood", "magic fire" }) do
      Arena(); Monster(31, 8, K.ORC); Cast(name); check(G.hitp[31][8] < 100000, name .. " hits the neighbours")
   end
   Arena(); G.item[31][8] = K.OWALL; G.item[29][9] = K.OSTATUE; Cast("vaporize rock")
   check(G.item[31][8] == 0 and G.item[29][9] == K.OBOOK, "vaporize rock")
   Arena(); G.item[31][8] = K.OALTAR; Cast("vaporize rock"); check(G.mon[31][8] == K.DEMONPRINCE, "an altar summons a demon prince")
   Arena(); Monster(31, 8, K.XORN); Cast("vaporize rock"); check(G.hitp[31][8] < 100000 or G.mon[31][8] == 0, "a xorn is hurt")

   -- create monster, alter reality, genocide, permanence
   Arena(); local before = 0; for x = 1, K.MAXX do for y = 1, K.MAXY do if G.mon[x][y] ~= 0 then before = before + 1 end end end
   Cast("create monster"); local after = 0; for x = 1, K.MAXX do for y = 1, K.MAXY do if G.mon[x][y] ~= 0 then after = after + 1 end end end
   check(after == before + 1, "create monster")
   Arena(); G.item[40][8] = K.OBOOK; G.iarg[40][8] = 3
   local objects = 0; for x = 1, K.MAXX do for y = 1, K.MAXY do if G.item[x][y] ~= 0 and G.item[x][y] ~= K.OWALL then objects = objects + 1 end end end
   Cast("alter reality"); local objects2 = 0; for x = 1, K.MAXX do for y = 1, K.MAXY do if G.item[x][y] ~= 0 and G.item[x][y] ~= K.OWALL then objects2 = objects2 + 1 end end end
   check(objects2 <= objects and objects2 >= objects - 4 and G.spelknow[select(2, Code("alter reality"))] == 0, "alter reality keeps the objects: " .. objects .. " " .. objects2)
   local reachable = G.item[G.playerx][G.playery] == 0 and G.mon[G.playerx][G.playery] == 0
   check(reachable, "alter reality puts the player on a free tile")
   Arena()
   local glyph = T.monstglyphs:sub(K.ORC + 1, K.ORC + 1)
   local gid; for j = 0, K.MAXMONST - 1 do if T.monstglyphs:sub(j + 1, j + 1) == glyph then gid = j break end end
   G.monster[gid].hitpoints = 100
   Monster(40, 8, gid); G.mon[40][8], G.hitp[40][8] = gid, 100
   G.mon[42][8], G.hitp[42][8] = gid, 100
   G.item[44][9], G.iarg[44][9] = K.OBOOK, 3
   for _ = 1, 40 do
      G.c[K.SPELLS] = 50; LOG = {}
      keys("c"); keys(Code("genocide"))
      if (last() or ""):find("Genocide which") then keys(glyph) end
      if G.monster[gid].flags >= K.FL_GENOCIDED and ns.Monster.hasFlag(G.monster[gid].flags, K.FL_GENOCIDED) then break end
   end
   check(ns.Monster.hasFlag(G.monster[gid].flags, K.FL_GENOCIDED), "genocide marks the monster")
   local left = 0; for x = 1, K.MAXX do for y = 1, K.MAXY do if G.mon[x][y] == gid then left = left + 1 end end end
   check(left == 0 and G.item[44][9] == K.OBOOK, "genocide wipes the monsters out and keeps the level")
   check(G.spelknow[select(2, Code("genocide"))] == 0, "genocide is used up")
   ns.Monster.init()
   Arena(); Cast("permanence"); check(G.spelknow[select(2, Code("permanence"))] == 0, "permanence is used up")

   -- spheres of annihilation
   Arena(); G.wizard = true; Cast("sphere of annihilation", "l"); G.wizard = false  -- (1 in 23 casts kills the caster)
   check(#G.spheres == 1 and G.c[K.SPHCAST] == 1 and G.item[G.spheres[1].x][G.spheres[1].y] == K.OANNIHILATION, "a sphere is made")
   for _ = 1, 6 do ns.Sphere.movsphere() end
   check(#G.spheres == 1, "the sphere moves on")
   local found = 0; for x = 1, K.MAXX do for y = 1, K.MAXY do if G.item[x][y] == K.OANNIHILATION then found = found + 1 end end end
   check(found == 1, "one sphere on the level, found " .. found)
   for _, sp in ipairs({ unpack(G.spheres) }) do ns.Sphere.rmsphere(sp.x, sp.y) end
   check(#G.spheres == 0 and G.c[K.SPHCAST] == 0, "spheres removed")
   Arena(); for x = 38, 42 do for y = 6, 10 do G.item[x][y] = K.OPOTION end end
   G.item[37][8], G.item[43][8] = K.OPOTION, K.OPOTION
   ns.Sphere.sphboom(40, 8)
   local cleared = true; for x = 38, 42 do for y = 6, 10 do if G.item[x][y] ~= 0 then cleared = false end end end
   check(cleared and G.item[37][8] == K.OPOTION and G.item[43][8] == K.OPOTION, "the blast clears a 5x5 area")
   Arena(); ns.Sphere.newsphere(35, 8, 2, 20); ns.Sphere.newsphere(35, 8, 2, 20)
   check(#G.spheres == 1 and G.c[K.SPHCAST] == 1 and G.item[35][8] == K.OANNIHILATION, "two spheres collide and a new one remains")
   Arena(); G.spheres = {}; G.c[K.SPHCAST] = 0; G.c[K.CANCELLATION] = 5; ns.Sphere.newsphere(36, 8, 2, 20)
   check(G.c[K.CANCELLATION] == 1, "cancellation sets off the sphere")
   Arena(); G.spheres = {}; G.c[K.SPHCAST] = 0; Monster(36, 8, K.DEMONLORD); LOG = {}; ns.Sphere.newsphere(36, 8, 2, 20)
   check(table.concat(lines(), "|"):find("dispels"), "a demon dispels the sphere")
   Arena(); G.spheres = {}; G.c[K.SPHCAST] = 0
   ns.Sphere.newsphere(G.playerx, G.playery, 2, 20); check(G.dead == 258, "enveloped by a sphere"); G.dead = nil
   local ate
   for _ = 1, 10 do
      Arena(); G.spheres = {}; G.c[K.SPHCAST] = 0
      ns.Sphere.newsphere(33, 8, 0, 50); Monster(34, 8, K.ORC)
      for _ = 1, 3 do ns.Monster.movemonst() end
      local orcs = 0; for x = 1, K.MAXX do for y = 1, K.MAXY do if G.mon[x][y] == K.ORC then orcs = orcs + 1 end end end
      if orcs == 0 and #G.spheres == 1 then ate = true break end
      G.spheres = {}; G.c[K.SPHCAST] = 0
   end
   check(ate, "a monster that walks into a sphere is annihilated")
   local dispelled
   for _ = 1, 10 do
      Arena(); G.spheres = {}; G.c[K.SPHCAST] = 0; LOG = {}
      ns.Sphere.newsphere(33, 8, 0, 50); Monster(34, 8, K.DEMONLORD)
      for _ = 1, 3 do ns.Monster.movemonst() end
      if table.concat(lines(), "|"):find("dispels") and G.spheres[1] == nil then dispelled = true break end
      G.spheres = {}; G.c[K.SPHCAST] = 0
   end
   check(dispelled, "a demon walking into a sphere dispels it")
   -- the scroll of pulverization
   Arena(); G.item[33][8] = K.OWALL; G.iven[1], G.ivenarg[1] = K.OSCROLL, K.SPULVERIZE
   keys("r"); keys("a"); keys("l"); check(G.item[33][8] == 0, "pulverization breaks the wall")
   -- discoveries
   G.scrollknown[K.SBLANK] = 1; keys("D"); check(ui.wait == "key" and ns.spellbook:IsShown(), "discoveries"); keys(" ")
   ns.mod.db.profile.fast = oldfast
   Arena(); Clear()
   for i = 1, 100 do G.c[i] = savedc[i] end
   for i = 1, K.SPNUM do G.spelknow[i] = savedspells[i] end
   ns.Monster.init()
end
-- altars, thrones, fountains, the brass lamp and the objects that do nothing
do
   local oldfast = ns.mod.db.profile.fast
   ns.mod.db.profile.fast = true
   local function Idle() return ui:IsActive() and debug.traceback(ui.co):find("GetCommand") end
   local function Run(sequence)
      for _, token in ipairs(sequence) do ui:InjectKey(token) end
      for _ = 1, 3 do if not Idle() then ui:InjectKey("ESC") end end
   end
   local function Visit(object, arg, sequence)
      ns.Create.newCaveLevel(3); Clear()
      G.c[K.HP], G.c[K.HPMAX], G.c[K.GOLD], G.c[K.LEVEL] = 5000, 5000, 1000, 60
      G.item[31][8], G.iarg[31][8] = object, arg or 0
      keys("l")
      Run(sequence)
      check(Idle() and not G.dead, "back at the command prompt after " .. object .. " " .. table.concat(sequence, ","))
   end
   local altar = { { "p", "j" }, { "p", "m", "1", "0", "0", "ENTER" }, { "p", "m", "5", "ENTER" }, { "p", "m", "ENTER" },
      { "p", "m", "ESC", "i" }, { "p", "m", "9", "9", "9", "9", "ENTER", "i" }, { "d" }, { "i" } }
   for i = 1, 160 do Visit(K.OALTAR, 0, altar[i % #altar + 1]) end
   local thrones = { { "p" }, { "s" }, { "i" } }
   for i = 1, 90 do Visit(i % 2 == 0 and K.OTHRONE or K.OTHRONE2, 0, thrones[i % 3 + 1]) end
   for i = 1, 30 do Visit(K.ODEADTHRONE, 0, i % 2 == 0 and { "s" } or { "i" }) end
   local fountain = { { "d" }, { "w" }, { "i" } }
   for i = 1, 60 do Visit(K.OFOUNTAIN, 0, fountain[i % 3 + 1]) end
   -- the lamp: a genie may teach the spell asked for
   for i = 1, K.SPNUM do G.spelknow[i] = 0 end
   local learned
   for i = 1, 80 do
      ns.Create.newCaveLevel(3); Clear()
      G.c[K.HP], G.c[K.HPMAX], G.c[K.LEVEL] = 5000, 5000, 60
      G.item[31][8] = K.OBRASSLAMP
      keys("l"); keys("r")
      if debug.traceback(ui.co):find("PickSpell") then
         check(ns.spellbook:IsShown(), "the genie shows all the spells")
         keys("bal")
      end
      for _ = 1, 3 do if not Idle() then ui:InjectKey("ESC") end end
      check(Idle() and not G.dead, "back at the command prompt after the lamp")
      if G.spelknow[K.SP_FIREBALL] == 1 then learned = true break end
   end
   check(learned, "a genie taught fireball")
   Visit(K.OBRASSLAMP, 0, { "t" }); check(G.iven[1] == K.OBRASSLAMP, "took the lamp")
   Visit(K.OSTATUE, 0, {}); check(table.concat(lines(), "|"):find("statue"), "a statue")
   Visit(K.OMIRROR, 0, {}); check(table.concat(lines(), "|"):find("mirror"), "a mirror")
   Visit(K.ODEADFOUNTAIN, 0, {}); check(table.concat(lines(), "|"):find("dead fountain"), "a dead fountain")
   -- the altar blesses
   local blessed
   for _ = 1, 200 do
      Visit(K.OALTAR, 0, { "p", "j" })
      if G.c[K.ALTPRO] > 0 then blessed = true break end
   end
   check(blessed, "an altar gave protection")
   ns.mod.db.profile.fast = oldfast
end
-- dying of a dart
Clear(); G.c[K.HP] = 1; G.item[31][8] = K.OTRAPARROW; keys("l")
check(not ui:IsActive() or G.dead, "an arrow ends the game at 1 hp ")
keys("S"); ns.main:Show()
-- a new game, and death by one's own fireball in the live thread
keys("a"); keys(" "); check(ui:IsActive() and ui.wait == "key", "a new game starts")
do
   local oldfast = ns.mod.db.profile.fast
   ns.mod.db.profile.fast = true
   ns.Create.newCaveLevel(3); Clear()
   for i = 1, K.SPNUM do G.spelknow[i] = 1 end
   G.c[K.INTELLIGENCE], G.c[K.LEVEL], G.c[K.HP], G.c[K.HPMAX] = 25, 40, 1, 5000
   G.item[32][8] = K.OMIRROR
   for _ = 1, 40 do
      if G.dead or not ui:IsActive() then break end
      G.c[K.SPELLS] = 50; keys("c"); keys("bal"); if debug.traceback(ui.co):find("PickDirection") then keys("l") end
   end
   check(G.dead or not ui:IsActive(), "your own fireball can kill you")
   ns.mod.db.profile.fast = oldfast
end

-- redraw paths with a populated game
ui:Flush(); ns.map:Layout(); ns.map:Draw(); ns.side:UpdateMinimap(); ns.side:UpdateStats()
G.c[K.HASTESELF] = 5; ns.side:UpdateStats()
for _, b in ipairs(ns.side.effectIcons) do if b.effect[1] == K.HASTESELF then check(b.scripts and b.scripts.OnEnter, "effect tooltip"); b.scripts.OnEnter(b) end end
 G.c[K.HASTESELF] = 0; ns.side:UpdateStats()
G.Reset(); ns.Create.makePlayer(ns.Classes[1]); ns.Create.newCaveLevel(0); ns.Create.newCaveLevel(3); ns.Display.showcell(G.playerx,G.playery); ns.map:Layout(); ns.map:Draw()
-- equipment summary: stacked rings all count
do
   G.Reset(); ns.Create.makePlayer(ns.Classes[1])
   for _ = 1, 3 do ns.Player.take(K.OPROTRING, 2) end
   ns.Player.take(K.OREGENRING, 0)
   ns.Player.recalc()
   local sum = table.concat(ns.Equipment.summary(), "\n")
   check(sum:find("rings 9"), "summary counts three protection rings: " .. sum)
   check(sum:find("Health regeneration 2"), "summary regen: " .. sum)
   local slot
   for i = 1, K.IVENSIZE do if G.iven[i] == K.OPROTRING then slot = i break end end
   check(ns.Equipment.short(slot) == "+3 armor class", "ring tag")
   ns.Player.take(K.OORB, 0); ns.Player.take(K.OSPIRITSCARAB, 0)
   check(table.concat(ns.Equipment.summary(), "\n"):find("Artifacts:"), "artifact line")
   ns.inventory:Open(); ns.inventory:Update()
   ns.inventory:Close()
end
-- death, life protection, scoreboards
do
   G.Reset(); ns.Create.makePlayer(ns.Classes[1]); ns.Create.newCaveLevel(0)
   G.name = "Tester"
   G.c[K.LIFEPROT] = 1; G.c[K.HP] = 0
   ns.Player.died(5)
   check(not G.dead and G.c[K.HP] == 1 and G.c[K.LIFEPROT] == 0, "life protection saves")
   ns.Player.died(263)
   check(G.dead == 263, "a win is not saved")
   G.dead = false
   G.c[K.LIFEPROT] = 1
   ns.Player.died(256)
   check(G.dead == 256, "quitting is not saved")
   G.c[K.GOLD] = 1000; G.c[K.BANKACCOUNT] = 500
   local entry = ns.Scores.record(5)
   check(entry and entry.score == 1500 and #ns.Scores.dead() >= 1, "death scored with the bank")
   check(ns.Scores.deathLine(5):find("killed by"), ns.Scores.deathLine(5))
   G.c[K.GOLD] = 2000
   entry = ns.Scores.record(ns.Scores.WIN)
   check(#ns.Scores.dead() >= 1 and #ns.Scores.winners() == 1, "a win keeps the deaths")
   check(ns.Scores.taxes() == 100, "tax on a win: " .. ns.Scores.taxes())
   check(ns.Scores.payTaxes(60) == 60 and ns.Scores.taxes() == 40, "paying taxes")
   check(#ns.Scores.letters() == 6 and ns.Scores.letters()[1][3]:find("2000 gold"), "letters")
   ns.scoreboard:Show(entry)
end
-- save and resume
do
   G.Reset(); ns.Create.makePlayer(ns.Classes[1]); ns.Create.newCaveLevel(0); ns.Create.newCaveLevel(3)
   G.c[K.GOLD] = 777; G.gtime = 4242; G.course[2] = true; G.spheres[1] = { x = 3, y = 4, lev = 3, dir = 2, lifetime = 9 }
   G.iarg[10][5] = 1234; G.item[10][5] = K.OGOLDPILE; G.loot[1105] = { { K.ODAGGER, 2 } }
   local items = 0
   for x = 1, K.MAXX do for y = 1, K.MAXY do if G.item[x][y] ~= 0 then items = items + 1 end end end
   check(G.monster[K.LEMMING].name == "rat", "a new game has rats")
   local monsters = G.monster[K.KOBOLD].hitpoints
   ns.ui.co = {}  -- (pretend a game is going on)
   ns.Save.store()
   ns.ui.co = nil
   check(ns.Save.exists(), "game stored")
   G.Reset()
   check(G.c[K.GOLD] == 0, "reset")
   check(ns.Save.load(), "game loaded")
   check(G.c[K.GOLD] == 777 and G.gtime == 4242 and G.level == 3 and G.course[2], "scalars and tables back")
   check(G.iarg[10][5] == 1234 and G.item[10][5] == K.OGOLDPILE and G.loot[1105][1][2] == 2, "level contents back")
   local after = 0
   for x = 1, K.MAXX do for y = 1, K.MAXY do if G.item[x][y] ~= 0 then after = after + 1 end end end
   check(after == items, "same items on the level: " .. after .. " vs " .. items)
   check(G.monster[K.LEMMING].name == "rat", "lemmings are rats: " .. G.monster[K.LEMMING].name)
   check(G.levels[1] and G.visited[1] and G.spheres[1].lifetime == 9 and G.monster[K.KOBOLD].hitpoints == monsters, "levels, spheres, monsters")
   ns.Save.clear()
   check(not ns.Save.exists(), "save cleared")
end
for _, cell in ipairs(ns.side.cells) do
   if cell.scripts and cell.scripts.OnEnter then cell.scripts.OnEnter(cell) end
end
-- level up message
do
   G.Reset(); ns.Create.makePlayer(ns.Classes[1])
   ns.Player.raiseExperience(ns.Tables.skill[2] + 1)
   check(last and tostring(last()):find("You gain"), "level up gains: " .. tostring(last and last()))
end
-- the 2.5D view
do
   G.Reset(); ns.Create.makePlayer(ns.Classes[1]); ns.Create.newCaveLevel(2)
   ns.Display.showcell(G.playerx, G.playery)
   for x = 1, K.MAXX do for y = 1, K.MAXY do G.know[x][y] = 1 end end
   ns.mod.db.profile.view = "3d"
   ns.map:Layout(); ns.map:Draw()
   check(ns.map3d.shown, "3d view drawn")
   ns.mod.db.profile.ascii = true; ns.map:Draw(); ns.mod.db.profile.ascii = nil
   do local x, y = ns.map3d:TileAt(300, 300); check(x == nil or type(x) == "number", "3d tile at cursor"); ns.map:Describe(G.playerx, G.playery) end
   ns.mod.db.profile.view = "flat"
   ns.map:Draw()
   check(not ns.map3d.shown, "flat view again")
end
print("ALL OK")
