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

-- redraw paths with a populated game
ui:Flush(); ns.map:Layout(); ns.map:Draw(); ns.side:UpdateMinimap(); ns.side:UpdateStats()
print("ALL OK")
