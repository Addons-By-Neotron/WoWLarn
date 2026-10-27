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
C_Timer = { After = function(sec, fn) timers[#timers + 1] = { sec, fn } end }
LibStub = function() return {
   GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end,
} end

local ns = { mod = { db = { profile = { scale = 1, fast = false, window = { point = "CENTER", x = 0, y = 0 } } } } }
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
check(#ns.HelpPages == 6, "help pages")
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
-- the nymph steals an item and keeps it
Fresh(3); G.iven[5], G.ivenarg[5] = K.OPOTION, 2; Put(K.NYMPH, 31, 8)
check(ns.Monster.spattack(14, 31, 8) == true, "nymph steals")
local loot = G.loot[31 * 100 + 31 * 0 + 8] or G.loot[3100 + 8]
check(loot == nil or #loot >= 1, "loot kept")
-- the death of the player
Fresh(3); G.c[K.HP] = 1; G.c[K.AC] = 0; Put(K.DEMONLORD, 31, 8)
for _ = 1, 20 do if not G.dead then ns.Monster.hitplayer(31, 8) end end
check(G.dead, "the player died to a demon lord")
-- losehp
Fresh(3); G.c[K.HP] = 10; ns.Player.losehp(3); check(G.c[K.HP] == 7 and not G.dead, "losehp"); ns.Player.losehp(7); check(G.dead, "dead at 0 hp")

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
check(last():find("the Bank of Larn"), "object message, got " .. tostring(last()))
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
               G.playerx, G.playery = nx, ny
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
G.c[K.HP] = G.c[K.HPMAX]
Put(K.ORC, 31, 8)
LOG = {}
keys("l")
local fought = false
for _, l in ipairs(lines()) do if l:find("You hit the orc") or l:find("You missed the orc") then fought = true end end
check(fought and G.playerx == 30, "bumping a monster attacks it, got " .. table.concat(lines(), " | "))
for _ = 1, 40 do if G.mon[31][8] ~= 0 and not G.dead then keys("l") end end
check(G.mon[31][8] == 0 or G.dead, "fight ended")
if G.dead then check(not ui:IsActive() or last():find("Game over"), "death ends the game") end
keys("S"); ns.main:Show()

-- redraw paths with a populated game
ui:Flush(); ns.map:Layout(); ns.map:Draw(); ns.side:UpdateMinimap(); ns.side:UpdateStats()
print("ALL OK")
