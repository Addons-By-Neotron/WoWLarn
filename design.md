# WoWLarn Design

WoWLarn is a port of **Ularn 1.5** (Phil Cordier's 1987 extension of Noah Morgan's Larn) to a World of Warcraft addon. It runs as a self-contained game window in the WoW UI.

- **Game rules:** a faithful port of the maps, monsters, items, spells, formulas and win/lose rules.
- **Presentation:** native WoW, not a terminal. The map uses graphical tiles, monsters use WoW creature portraits and 3D models, and items use WoW icons. There is a side panel with a minimap and stats, and a bottom panel with the message log and control buttons.
- **Reference source:** `/opt/workspace/ularn` (C, about 16k lines, outside this repo). Treat it as the spec for game logic. When behaviour is unclear, read the C.
- **Targets:** same as the `.toc` (Retail and Classic/Forever). Graphics assets (creature display IDs, icons, textures) must exist in **every** target client; see §7.
- **License:** GPLv2, matching Ularn. Credit Phil Cordier, Noah Morgan, Josh Brandt and David Richerby.

---

## 1. The original game in brief

- **Story/goal:** the player's daughter has dianthroritis. Find the **potion of cure dianthroritis** at the bottom of the volcano (V5), bring it home (the `OHOME` tile in town) before `TIMELIMIT` (40000 turns; shown as 400 "mobuls"). Arriving after the deadline loses the game. Score includes gold; the Larn Revenue Service taxes winners.
- **World:** `NLEVELS = 21` levels, each `MAXX × MAXY = 67 × 17`:
  - level 0: town ("H"), fully known, with the buildings
  - levels 1–15: dungeon (`DBOTTOM = 15`)
  - levels 16–20: volcano V1–V5 (`VBOTTOM = 20`)
  - Levels persist once visited (`beenhere[]`, `savelevel`/`getlevel`).
- **Level generation** (`create.c`):
  - A level is either a canned map from `data/Umaps` (21 ASCII maps of 67×17, separated by blank lines) or a recursive-backtracker maze (`makemaze`/`eat`) plus random open rooms, a horizontal corridor, and treasure rooms below level 4.
  - Objects come from `makeobject`; monsters from `fillmonst`/`makemonst`.
  - Levels 11–15 add 1–5 demon lords. Level 15 also has a demon prince guarding the Eye of Larn. V1–V5 add 1–5 demon princes, and V5 has the God of Hellfire guarding the cure potion.
  - There are no stairs from V3 to V4 or V4 to V5; you go down by pit or trapdoor.
- **Player:**
  - Attributes are the `c[0..99]` array (`player.h`): stats, HP, spells, timers for every effect, and "object exists" flags.
  - 26-slot inventory: `iven[]` holds item types, `ivenarg[]` holds the enchantment, potion or scroll id.
  - 8 classes are picked at start (`store.c:pick_char`); in WoWLarn they become WoW classes (§9). Experience thresholds are in `data.c:skill[]`; level titles in `data.c:class[]`.
- **Turn loop** (`main.c:main`, one iteration per player action):
  1. `lookforobject()`: interact with the tile underfoot.
  2. `movemonst()`: twice if monsters are hasted; monsters only move within a window around the player.
  3. Redraw the cell and bottom line.
  4. `parse()`: read the command.
  5. `regen()`: HP/spell regeneration, count down every effect timer, advance `gtime`.
  6. Random monster spawn counter `rmst`.
- **Commands** (`main.c:parse`, `data/Uhelp`): vi-keys movement (`hjklyubn`, capitals run), `.` stay, `w` wield, `W` wear, `T` take off, `r` read, `q` quaff, `d` drop, `c` cast (3-letter code), `C` close door, `e` eat, `i` inventory, `D` discoveries, `^` find traps, `Z` teleport (level ≥ 10), `g` pack weight, `P` tax status, `S` save, `Q` quit, `v` version, `?` help, `^L` redraw.
- **Combat:**
  - Player attacks by moving into a monster (`monster.c:hitmonster`, `hitm`, `fullhit`).
  - Monsters attack in `hitplayer`; special attacks are in `spattack`.
  - Monster stats are in `data.c:monster[]` (65 entries including demons). Difficulty (`tok.c:sethard`) scales them.
- **Magic:**
  - 39 spells (`data.c:spelcode/spelname/speldescript`), cast by 3-letter code. `monster.c:cast`/`speldamage` implement them. `spelweird[][]` is the per-monster resistance table.
  - 24 scrolls and 24 potions are unidentified until used. Spawn odds are in `scprob[]`/`potprob[]`.
- **Town buildings:** DND store, College of Larn (school), Bank of Larn / 5th branch (`obank2`), Trading Post, Larn Revenue Service (`store.c`), home (`object.c:ohome`), and Dealer McDope's Pad (`store.c:opad`; becomes a goblin alchemist, see §13).
- **Dungeon features:** altars, thrones, fountains, statues, mirrors, chests, books, cookies, pits, trapdoors, teleporters, elevators, sphere of annihilation (`sphere.c`), and the unique artifacts listed in `README.spoilers`.
- **Scoreboard:** separate winners and dead lists (`scores.c`). The dead list records inventory.

---

## 2. Source map: C → Lua

Game-logic modules mirror the C files so each one can be ported and checked against its C counterpart. Every ported function keeps its C name (camelCase is fine) and gets a `-- C: file.c:function` comment. All C screen output (`display.c`, `show.c`, `io.c`, the text pages in `store.c`/`help.c`/`scores.c`) is **replaced** by the UI layer (§6). Game code calls a small UI API (§4) instead of drawing.

| C file | Purpose | Lua module |
|---|---|---|
| `header.h`, `player.h`, `itm.h`, `monst.h` | constants, `c[]` indices, object/monster ids | `Constants.lua` |
| `data.c` | monster table, names, spells, probabilities, titles | `Data/Monsters.lua`, `Data/Objects.lua`, `Data/Spells.lua`, `Data/Tables.lua` |
| `data/Umaps` | canned levels | `Data/Maps.lua` (generated) |
| `data/Uhelp`, `data/Ufortune` | help text, fortunes | `Data/Help.lua`, `Data/Fortunes.lua` (generated) |
| (new) | glyph/monster/item → texture, icon, displayID | `Data/Visuals.lua` |
| `create.c` | player creation, level gen, object placement | `Create.lua` |
| `main.c` (`parse`, loop) | turn loop, command dispatch | `Game.lua` |
| `action.c` | wield/wear/drop/read/quaff/eat/run | `Action.lua` |
| `player.c` | stats, exp, hp, inventory, `recalc` | `Player.lua` |
| `monster.c` | combat, spells, monster creation, drops | `Monster.lua`, `Spells.lua` |
| `movem.c` | monster movement AI | `MoveMonst.lua` |
| `object.c`, `moreobj.c` | tile interactions, potions, scrolls, features | `Object.lua` |
| `store.c`, `bill.c` | town building logic, tax letters | `Town.lua` (logic) + `UI/Store.lua` (window) |
| `sphere.c` | spheres of annihilation | `Sphere.lua` |
| `regen.c` | per-turn timers | `Regen.lua` |
| `display.c` | map/status drawing | `UI/MapView.lua`, `UI/SidePanel.lua` (drawing); `Display.lua` (`showcell` visibility, `moveplayer`) |
| `data.c` globals (`c[]`, `item[][]`, `know[][]`, `iven[]`, `level`, `playerx`, ...) | game state | `State.lua` (`ns.G`) |
| `header.h` macros (`rnd`, `rund`) | random numbers, C integer math | `Util.lua` |
| `store.c:pick_char` | class definitions | `Data/Classes.lua` (+ `Create.makePlayer`, `UI/ClassPicker.lua`) |
| `show.c` | inventory and discovery lists | `UI/Inventory.lua`, `UI/Discoveries.lua` |
| `io.c` (`lprintf` etc.) | message output, prompts | `UI/MessageLog.lua`, `UI/Prompt.lua` |
| `tok.c` | keyboard tokens, options, difficulty | `UI/Input.lua`, `sethard` in `Create.lua` |
| `savelev.c` | level/game save | `Save.lua` |
| `scores.c` | scoreboard, death | `Scores.lua` + `UI/Scoreboard.lua` |
| `help.c`, `fortune.c` | help pages, cookies | `UI/Help.lua` |
| `tty.c`, `signal.c`, `nap.c`, `diag.c` | Unix terminal plumbing | **not ported** (`nap` → coroutine sleep; `diag` maybe debug-only) |

`WoWLarn.lua` stays the Ace3 shell: DB, slash commands, show/hide the window. `Options.lua` holds the settings. Game modules live under one shared namespace table (`local _, ns = ...`). Use `ns.c`, `ns.item`, etc. rather than globals. **Game logic modules must not touch frames.** They call `ns.ui:*` only, so the logic can be checked against the C without UI noise.

---

## 3. Data conversion

WoW addons cannot read files at runtime, so all data files become Lua tables.

- `tools/convert-data.py` (not shipped) reads the Ularn sources and writes the generated files, which are committed:
  - done: `Constants.lua` (`ns.K`, from the three headers, with the index shifts applied), `Data/Tables.lua` (experience table, level titles, level names, glyph strings, object names), `Data/Monsters.lua` (the 65 monsters), `Data/Help.lua` (story and help pages), `Data/Maps.lua` (the 21 canned levels; the C only picks the first 20), `Data/Items.lua` (`scprob`, `potprob`, `nlpts`, `nch`, `nplt`, `ndgg`, `nsw`, `nobjtab`)
  - to come: `Data/Fortunes.lua`, and the spell and scroll description tables with their milestones (5 and 6)
  - Modules import the constants they use as locals (`local HP, AC = K.HP, K.AC`), because a file may only have 200 locals.
  - Run `tools/convert-data.py` after changing it; never edit the generated files.
  - `Umaps`: 21 maps × 17 rows × 67 chars, separated by blank lines. Store as an array of 17 strings per map. Decode glyphs to object ids at level creation, as `create.c:cannedlevel` does, using `row:sub(x, x)` with 1-based x.
  - `Uhelp`: pages split on the leading page-count line and form feeds. Strip the `^[[7m` / `^[[m` escapes and turn them into highlight markup. The key list becomes the in-game help and the button tooltips.
- Transcribe the `data.c` tables to Lua by hand or with a script, keeping the column order and comments. **Shift every 0-based table to 1-based** per §5:
  - `monster[]`, `objectname[]`, `scrollname`, `potionname`
  - `spelcode`/`spelname`/`speldescript`/`splev`, `spelweird`
  - `scprob`/`potprob` (their values are scroll/potion ids, so shift them too)
  - `nlpts`/`nch`/`nplt`/`ndgg`/`nsw`, `skill[]`, `class[]`, `levelname[]`, `monstlevel[]`
  - the store's `itm[]` table (`store.c`)
  - `objnamelist`/`monstnamelist` (ASCII glyphs) are kept for decoding `Umaps` and as the fallback renderer only.
- `sethard` changes `monster[]` in place. Keep a pristine copy and build the scaled table per game, so changing difficulty or starting a new game doesn't stack the scaling.
- `tools/` and `design.md` are in the `.pkgmeta` `ignore:` list.

---

## 4. Execution model: coroutine game thread + UI API

The C code blocks for input everywhere: `getcharacter()`, `readnum()`, `getyn()`, `more()`, the store/bank/school loops, `cast()` asking for a spell and then a direction, and `nap(ms)` delays. Rewriting each of these as an explicit UI state machine would change the shape of the code and invite bugs.

**Decision:** the whole game runs inside one Lua coroutine. Input from **either the keyboard or the UI** (buttons, inventory clicks, store rows, map clicks) resumes it.

- The game thread asks for input through `ns.ui` calls that yield until answered:

  | UI call | Replaces (C) | UI shown | Answered by |
  |---|---|---|---|
  | `ui:GetCommand()` | `parse()` / `yylex()` | (none) | key, control button, or map click |
  | `ui:PickItem(prompt, filter)` | `whatitem()` | inventory window opens with valid items highlighted | click a slot, or press its letter; Esc cancels |
  | `ui:PickDirection(prompt)` | `dirsub()` | direction overlay around the player on the map | key or click |
  | `ui:PickSpell()` | `cast()` code entry | spellbook popup | 3-letter code typed, or click |
  | `ui:GetNumber(prompt, max)` | `readnum()`; `*` means all | numeric input dialog | typed number |
  | `ui:YesNo(prompt)` | `getyn()` | confirm dialog | yes/no |
  | `ui:More()` | `more()`, `retcont()` | continue button | click or key |
  | `ui:Store(kind, state)` | the store/bank/school/trading post/LRS loops | store window | row selection |
  | `ui:Message(fmt, ...)` | `lprintf`/`lprcat` to the message area | message log | (no input) |
  | `ui:Refresh(what)` | `bottomline()`, `showcell()`, `draws()` | redraws map, minimap, stats or effects | (no input) |
  | `ui:Nap(ms)` | `nap()` | yields with `C_Timer.After` | timer; disabled by a "fast" option |
  | `ui:Animate(evt)` | (new) | non-blocking model animation (attack, hit, death, spell) | (no input) |

- The UI-side dispatcher keeps track of which request is pending and only resumes the coroutine with an answer of the right type. Other input is ignored or queued, for example a movement key arriving during a YesNo.
- `died()` / `quit()` / save-and-exit end the coroutine by returning, not `os.exit`. The window then shows the scoreboard and offers a new game.
- Errors are caught by checking the result of `coroutine.resume` and passing it to `geterrorhandler()`; the game is then marked "crashed" and restarts on the next key.
- **Never wrap game logic in `pcall`/`xpcall`, and never yield inside a `table.sort` comparator or `string.gsub` callback.** WoW runs Lua 5.1, which cannot yield across them.
- Keys from the keyboard, control buttons, dialog buttons and clicks all go through one input path, `ui:InjectKey(key)`. Higher-level requests (`YesNo`, `GetNumber`, `More`, `PickDirection`) are loops over `ui:GetKey()`, so a button click is just a synthetic key.
- Level generation and maze recursion run inside one resume. `eat()` recursion depth is at most about 600, which is fine for Lua.

---

## 5. Porting rules

These are where most porting bugs will come from. Follow them everywhere.

1. **1-based indexing everywhere.** Every game array starts at 1, so Lua tables stay pure arrays (array part, `#`, `ipairs`, `table.concat`, and `string.sub` on map rows all work).
   - **Coordinates:** C `x ∈ [0, MAXX-1]` → Lua `x ∈ [1, MAXX]`; same for y. Translate **every** bound and literal coordinate: `x < MAXX-1` → `x < MAXX`, `x <= 0` → `x <= 1`, `rnd(MAXX-2)` → `rnd(MAXX-2)+1`, `item[33][MAXY-1]` → `item[34][MAXY]`, and window clamps in `movemonst`. Canned map rows and generated mazes keep the same shape; only the numbers move. Comment non-obvious shifts with `-- C: x-1`.
   - **`c[]` indices:** the constants shift by +1 (`STRENGTH = 1`, `INTELLIGENCE = 2`, … `TMP2 = 99`). Code keeps writing `c[STRENGTH]`. Loops over the six stats (`for i=0;i<6`) become `for i = 1, 6`.
   - **Inventory:** `iven`/`ivenarg` slots are `1..IVENSIZE`. "Nothing wielded/worn", `c[WIELD] = -1` in C, becomes `0`. Every `c[WIELD] > 0` / `>= 0` test must be re-read and translated (C slot 0 is valid; Lua slot 0 means none).
   - **Id enums that are already 1-based stay unchanged:** object ids (`OALTAR = 1`…, `0` = empty tile) and monster ids (`LEMMING = 1`…, `0` = no monster). `monster[0]`, the C dummy entry, is dropped.
   - **Id enums that are 0-based shift by +1:** scrolls (`SENCHANTARM = 1`… `S_MAX = 24`), potions (`PSLEEP = 1`… `P_MAX = 24`), and spells (`pro = 1`… 39). For example, the cure potion is `ivenarg == 22` (C `21`), and the starting potion `rund(6)` becomes `rnd(6)`. Grep for every literal id in the C before porting a function.
   - **Levels:** keep the level number as a **value** (`0` = town … `20` = V5), as C uses it in formulas such as `rmst = 120-(level<<2)`. Per-level storage is indexed `levels[level+1]`, behind the `getlevel`/`savelevel` helpers only.
2. **Integer division:** C `a / b` on ints → `math.floor(a / b)` for non-negative values. For possibly negative operands, C truncates toward zero, so use a `idiv(a, b)` helper that truncates.
3. **Modulo:** C `%` truncates; Lua `%` floors. `rand() % x` is safe (non-negative). Audit any other `%` with possibly negative operands and use a `cmod` helper.
4. **Bit ops:** `&`, `|`, `<<`, `>>` → `bit.band`, `bit.bor`, `bit.lshift`, `bit.rshift` (WoW's `bit` library). Add `bit` to `.luacheckrc`. Example: `(c[HASTESELF]&1)==0`.
5. **Game state:** the C globals live in one table, `ns.G` (`State.lua`). Its arrays are allocated once and reset in place, so modules may cache `G.c`, `G.item` and so on. The 2D grids are `[x][y]`. `mitem[x][y].mon` becomes `G.mon[x][y]` (a monster id); the stolen-item list of `mitem` will be a sparse table when theft arrives with the monsters. A saved level is a snapshot copied in and out (`G.SaveLevel`/`G.GetLevel`).
6. **Named constants:** every `#define` becomes a local or `ns` constant with the same name (`HP`, `OWALL`, `DEMONLORD`, ...), so `c[HP]` reads the same as in the C.
7. **Integer widths:** C `char`/`short` fields clamp or overflow. Port explicit clamps (like those in `sethard`) exactly. Where C silently relied on `char` overflow, note it with a `-- C: char overflow` comment and clamp.
8. **RNG:** keep `rnd(x) = random(1..x)`, `rund(x) = random(0..x-1)`. Use WoW's `math.random` / `fastrandom`. Replayable games aren't a goal.
9. **Messages:** `lprintf` formats → `ui:Message` with `string.format`. Watch for `%d` with non-integers, which errors in Lua; floor first. Drop cursor positioning, padding and screen-clearing; the UI handles layout.
10. **Bugs in the original:** port faithfully by default. Fix only clear crashes or memory-corruption bugs, and mark each fix `-- FIX:` with the reason. Gameplay quirks, such as the odd Slayer damage formula in `hitplayer` (`dam=(int)(1 - (0.1*rnd(5))*dam)`), stay as-is unless noted in §12.
11. **Globals:** none, other than the SavedVariables (`WoWLarnDB`) and the frame names needed for `UISpecialFrames`.

---

## 6. UI layout

One main game frame (movable, resizable, scale setting, position saved in profile) with three regions:

```
+--------------------------------------------------+-------------------+
|                                                  |  MINIMAP          |
|                                                  |  (whole 67x17     |
|              MAP VIEW                            |   level, known    |
|   (tile viewport centered on player,             |   cells only)     |
|    e.g. 23 x 13 tiles @ 32px, scrolls)           +-------------------+
|                                                  |  PORTRAITS        |
|                                                  |  player | target  |
|                                                  |  (3D models)      |
|                                                  +-------------------+
|                                                  |  STATS            |
|                                                  |  HP/spell bars,   |
|                                                  |  STR INT WIS CON  |
|                                                  |  DEX CHA AC WC    |
|                                                  |  Lvl/Exp/title    |
|                                                  |  Gold, Depth, Time|
|                                                  +-------------------+
|                                                  |  EFFECTS (icons)  |
+--------------------------------------------------+-------------------+
|  MESSAGE LOG (ScrollingMessageFrame, ~6 lines,   |  CONTROL BUTTONS  |
|  scrollback, color-coded: combat/loot/system)    |  (icon grid)      |
+--------------------------------------------------+-------------------+
```

### 6.1 Map view (`UI/MapView.lua`)

- **Viewport:** a window onto the level, about 23×13 cells, centered on the player. The view scrolls with the player and clamps at level edges. The whole level (67×17) doesn't fit at a usable cell size, which is why there is a viewport plus a minimap.
- **Two renderers** behind one interface (`MapView:DrawCell`, `:MoveActor`, `:Animate`), chosen in options:
  - **2.5D view (default):** a tilted north-up camera behind and above the player, using WildCraft's techniques (§7.1).
    - The floor is drawn as perspective quads (`SetVertexOffset`).
    - Walls are upright panels or blocks with front and top faces.
    - Monsters and the player are **real WoW creature models** (`PlayerModel`) standing on their cells, facing their move direction, with walk, attack, wound and death animations.
    - Items and features are icons or billboards standing on the floor; artifacts could later use world-object models (`SetModel(fileID)`).
    - Turn-based, so the scene is redrawn only when the state changes. Moves tween smoothly over about 0.15 s.
  - **Flat tiles:** a top-down grid of tile frames (32 px), with creature portraits (`SetPortraitTextureFromCreatureDisplayID`) for monsters. It is cheap, has no model limits, and also serves as the debugging and low-spec mode. The ASCII-glyph fallback (§7) is a variant of this renderer.
- **Layers** (both renderers):
  1. ground: floor or wall, varied per depth (town / dungeon / volcano)
  2. object: feature or item
  3. actors: monsters and player
  4. overlays: direction-pick arrows, spell or projectile effects, "unknown" fog
- **Visibility rules** (ported from `show1cell`/`showcell`):
  - Only `know[x][y]` cells are drawn.
  - Blindness hides everything.
  - Mimics cycle to a random monster's portrait every 10 turns.
  - Invisible stalkers show the floor unless `SEEINVISIBLE`.
  - Demons (≥ `DEMONLORD`) are hidden without the Eye of Larn.
- **Mouse:** hovering a tile shows a GameTooltip with the object or monster name. Clicking an adjacent tile moves or attacks; clicking during `PickDirection` answers it. Click-to-travel is out of scope for now.
- **Projectiles/spells** (`godirect`, `omnidirect`): animate across tiles with `ui:Nap` steps, as the C does with `nap`.

### 6.2 Side panel (`UI/SidePanel.lua`)

- **Minimap:** the whole 67×17 level as 1,139 small colored textures (wall / floor / stairs / store / item / monster / player), known cells only. Clicking it pans the main view; it re-centers on the next move. Shows the depth label ("H", "1"–"15", "V1"–"V5").
- **Portraits:**
  - Player: a `PlayerModel` with `SetUnit("player")`, which shows your own WoW character.
  - Target: a `PlayerModel` with `SetDisplayInfo(displayID)` for the last monster you fought or hovered. It plays attack, wound and death animations (`SetAnimation`) on combat events from `ui:Animate`, and shows the name and an HP estimate.
- **Stats:** HP and spell bars (StatusBar); `STR INT WIS CON DEX CHA`; `AC`, `WC`, level, experience (with a bar to the next `skill[]` threshold), the title from `class[]`, gold, bank, and the time remaining (`TIMELIMIT - gtime` in mobuls).
- **Effects:** icon row for every active `c[]` timer or flag that `botside` shows (protection, haste, invisible, hero, giant strength, blind, confused, and so on). Icons are from `Data/Visuals.lua`; tooltips show the name and remaining turns.

### 6.3 Bottom panel

- **Message log** (`UI/MessageLog.lua`): a `ScrollingMessageFrame` with mouse-wheel scrollback and per-category colors (combat, damage taken, loot, magic, system). Repeated identical messages collapse with a ×N counter.
- **Control buttons** (`UI/ControlBar.lua`): icon buttons with a keybind label and a tooltip (the help text). Each one pushes the same command char as the key.
  - inventory `i`, wield `w`, wear `W`, take off `T`, drop `d`
  - quaff `q`, read `r`, eat `e`, cast `c`
  - close door `C`, find traps `^`, rest `.`, teleport `Z` (shown at level ≥ 10), discoveries `D`
  - help `?`, save & close `S`
  - A disabled state is shown when a command can't be used (no potions, blind, time stop), using the same checks as `parse`.

### 6.4 Dialog windows (all on the same frame strata, closed by Esc)

- **Inventory:** a 26-slot grid of item icons with names and enchantments, wielded/worn markers and pack weight. In `PickItem` mode, valid items are highlighted.
- **Spellbook:** known spells with code, name, description (`speldescript`) and level; click to cast.
- **Discoveries:** identified potions, scrolls and spells (`seemagic`).
- **Store windows:** DND store (item list with icons and prices, sell/buy), bank (deposit/withdraw/appraise gems), school (courses), trading post, LRS (taxes), home (status/win), and the goblin alchemist (Grizzik's, §13).
- **Character creation:** class picker (§9) and name (default: your WoW character name), plus difficulty for a new game.
- **Help, scoreboard, death/win screens:** text panels styled like WoW quest or letter frames. Tax letters (`bill.c`) appear as mail-style letters.

---

## 7. Graphics and WoW assets (`Data/Visuals.lua`)

All asset references are numeric **fileIDs** or display IDs, chosen from content that exists in Classic Era/Forever as well as Retail, and checked on every target client. Each entry has a fallback.

- **Monsters → creature `displayID`:** each of the 65 Ularn monsters maps to a classic-era creature display. Examples:
  - kobold → a Kobold
  - orc → an Orc grunt
  - troll → a Troll
  - white/bronze/green/silver/red dragon → dragon or whelp displays
  - nymph → a Dryad
  - water lord → a Water Elemental
  - demon lords → Doomguard / Infernal / Eredar variants
  - God of Hellfire → Ragnaros
  - The table is curated by hand, with a comment naming the creature.
  - **Tiles:** `SetPortraitTextureFromCreatureDisplayID(texture, displayID)`, present in the Retail, Classic and Vanilla UI sources. These are cheap 2D portraits, cached per displayID.
  - **Side panel:** a full 3D `PlayerModel:SetDisplayInfo(displayID)` with animations.
  - **Fallback:** a creature-family ability icon.
  - **Verify:** portrait rendering cost with about 20 visible monsters, and that portraits render before the creature model is cached client-side. `SetPortraitTexture...` may return blank until the model loads; re-apply on the next refresh.
- **Items → icon fileIDs:** weapons, armor, rings, potions (by identified type; unidentified potions use generic flask icons with per-game random color assignment, as the C randomises names), scrolls, books, gems, gold, artifacts (Eye of Larn, Orb, Lance of Death, Slayer, ...).
- **Features → icons or textures:** altar, throne, fountain, statue, mirror, chest, stairs, elevator, pit, trapdoor, teleporter, doors, store entrances (vendor/bank/trainer style icons), home (hearthstone-like icon).
- **Ground:** tileable floor and wall textures per region: town (grass/cobble), dungeon (stone), volcano (lava rock). Use whole-texture fileIDs that exist in all clients, or simple flat colors with a border as the fallback "classic" style.
- **Player:** on tiles, a class icon or the player's portrait (`SetPortraitTexture(tex, "player")`). In the side panel, the 3D player model.
- **Effects:** spell icons for timers/flags in the effects row and for spell animations on the map (`ui:Animate`).
- **ASCII fallback renderer:** a setting draws the original glyphs (`objnamelist`/`monstnamelist`) on tiles instead of graphics. It is useful for debugging and for comparing against the C.

### 7.1 Lessons from WildCraft (`~/src/WildCraft-1.0.0`)

WildCraft is a pseudo-3D mount-racing addon for Classic Forever (Interface 16001) that draws WoW creature models in a hand-built 3D scene. Its techniques and its hard-won workarounds apply directly here. References are to `WildCraft\WildCraft.lua` unless noted.

- **Perspective quads:** `Texture:SetVertexOffset(corner, dx, dy)` moves each of a texture's 4 corners, so any rectangle can be warped into a trapezoid. The steps are:
  1. Project each cell's 4 ground corners to the screen.
  2. Anchor the texture at the bounding box.
  3. Offset the corners.

  (`fx.TerrainPiece`, about l.5344.) Adjacent quads leave hairline gaps, so **push every corner outward a pixel or so from the quad's center** (`C.PIECE_OVERLAP`). Pool the quads and reuse them by key, without recreating them per frame.
- **Upright panels** (walls, doors, store fronts): split the panel into vertical slices, project both ends of each slice, set its `TexCoord` span, and offset the right-hand corners to the far end's height (`DrawPanel`, about l.5672).
- **Projection:** a single `Project(x, y, z)` → `screenX, below-horizon, scale, depth` function (l.3744) is the only place camera math lives. Draw order is set with `SetFrameLevel(Level(depth))` (l.3785).
- **Creature models:**
  - Use one `PlayerModel` per actor inside a holder frame (`ModelFrame`, about l.12378). Look things up by **display ID first**, `SetDisplayInfo(displayID)`, falling back to `SetCreature(npcID)`. Keep a hand-curated creature→display table with comments (`Roster.lua` `ns.DISPLAYS`, `ns.SetLook`).
  - Display IDs must exist in the oldest target client (Forever's `CreatureDisplayInfo`).
  - Record `GetModelFileID()` in `OnModelLoaded` in the SVs to debug wrong-looking models.
- **Size models by frame size, never `SetModelScale`.** The game forgets model scale at arbitrary moments. Each model needs per-creature tuning: `feet` (vertical offset so feet land on the ground point), `shift`, `pitch` and a size factor. Plan a `Data/Visuals.lua` tune entry per monster, and a debug **model viewer** (`/larn models`, debug-only) to pick displays and tune them in game.
- **Shared depth buffer:** all `PlayerModel`s in a window draw into one depth buffer, so a far model can cut into a near one regardless of frame level.
  - WildCraft's fix (`Seat`, about l.6052): read each model's default camera once, then call `MakeCurrentCameraCustom` + `SetCameraPosition`/`SetCameraTarget` to push the camera back in proportion to the actor's scene depth, and enlarge the frame by the same factor. The picture size is unchanged and the depth order is correct.
  - Cap and ease the distance so big models don't hit the far clip.
  - We need this whenever two actors overlap on screen, which happens with adjacent cells in the tilted view.
- **Animations:**
  - IDs: `stand 0, walk 4, run 5, attack 16, wound/stun 14, jump 38` (`ANIM`, l.384); death is 1 in the standard set.
  - **`OnModelLoaded` resets the animation**, so re-apply the wanted one there. Only call `SetAnimation` when it changes (`SetAnim`, l.5986).
  - Check `HasAnimation` before using one, and fall back otherwise (`fx.Routine`).
  - Animation speed is controlled with `SetPaused` or `SetSequenceTime` (`fx.Pace`).
- **Defensive API use:** every model call is wrapped in `pcall`, and the code checks that a method exists before relying on it (`GetCameraPosition`, `SetViewInsets`, `SetSequenceTime`, `SetLight`, `HasAnimation`), since availability varies by client.
- **Lighting and fog:** `SetLight` and `SetFogColor`/`SetFogNear`/`SetFogFar` on models (about l.9756) can darken or silhouette models. Use them for unlit or remembered cells, blindness, and the volcano's red tint.
- **Media:** WildCraft ships its own textures as `.png` in `Media\`, which works on Forever. Verify PNG on Retail before relying on it; otherwise ship `.tga`/`.blp` or use game fileIDs. Keep bundled art small: WildCraft's map pictures are 10–40 MB each.
- **Model budget:** WildCraft runs about 5 racers plus a crowd plus props as live models. For WoWLarn, cap live models to the actors inside the viewport (typically under 15) and pool `PlayerModel` frames. Far or remembered monsters use portraits.

---

## 8. Input

- **Keyboard:** the game frame uses `EnableKeyboard(true)`. While the window is shown and **focused**, it calls `SetPropagateKeyboardInput(false)`, so game keys don't trigger WoW bindings. Otherwise it propagates.
  - Use `OnChar` for printable characters, which handles shift and layout, and `OnKeyDown` for Esc, Enter, Backspace, arrows, numpad and Ctrl-combos.
  - Arrow keys and numpad map to the 8 directions as well as vi-keys.
- **Focus:** clicking the window focuses it; Esc at the top-level command prompt, or clicking outside (`GLOBAL_MOUSE_DOWN`, where the client has it), releases it. Show focus state visibly on the frame border. Never hold the keyboard while the window is hidden.
- **Combat lockdown:** `SetPropagateKeyboardInput` may be restricted in combat on Retail. Milestone 1 calls it on this non-secure frame without special handling; **verify in combat on each client**, and if it errors, auto-unfocus on `PLAYER_REGEN_DISABLED` and refuse to focus in combat (buttons and mouse keep working).
- **Esc:** closes the topmost dialog or cancels the pending prompt. At the top-level command prompt it unfocuses, then closes the window.
- **Mouse:** control buttons, map clicks (§6.1), inventory and store clicks. Everything playable by keyboard is also playable by mouse.

---

## 9. Classes (and races later)

The 8 Ularn classes are re-themed as WoW classes. **Mechanics are unchanged:** starting stats, HP, known spells and starting kit come from `pick_char`. Only the name, icon and flavor text change.

| Ularn | WoW class | Why | Start (from C) |
|---|---|---|---|
| Ogre | **Warrior** | STR 18 / CON 16, brute | 16 HP, `mle`, 2 random potions |
| Wizard | **Mage** | INT/WIS 16, 2 spells | 8 HP, `mle`+`chm`, treasure-detect potion, 2 scrolls |
| Klingon | **Shaman** | balanced fighter-caster, sonic spear | 14 HP, `ssp`, studded leather, potion |
| Elf | **Priest** | CHA 14, protection spell | 8 HP, `pro`, max 2 spells, leather, scroll |
| Rogue | **Rogue** | DEX 14, stealth | 12 HP, `mle`, leather + dagger, stealth scroll |
| Geek | **Hunter** | all 12, jack of all trades | 10 HP, `pro`+`mle`, leather + dagger |
| Dwarf | **Paladin** | STR/CON 16, spear | 12 HP, `pro`, spear |
| Rambo | **Warlock** ("forbidden pact") | all stats 3, 1 HP, starts with the Lance of Death | 1 HP, Lance of Death |

- Druid (and Death Knight etc. on Retail) are unused for now. They are possible later as new classes with their own stat lines.
- The class picker pre-selects the player's own WoW class (`UnitClass("player")`) when it maps to one.
- **Races (later):** an optional second pick that applies small stat modifiers (e.g. Dwarf +2 CON, Gnome +2 INT, Night Elf +2 DEX), plus the player-model look in the side panel. Not part of the original game, so it is behind an option and noted as a gameplay change.

---

## 10. Persistence

- **SavedVariables:** `WoWLarnDB` (AceDB). The profile holds window and options. **Game state goes in `WoWLarnDB.char`**, so each WoW character has its own game. The **scoreboard goes in `WoWLarnDB.global`**, shared account-wide.
- **What is saved** (mirrors `savelev.c:savegame`):
  - `c[]`, inventory, player position, `level`, `gtime`, known scrolls/potions/spells, the unidentified-potion/scroll appearance mapping, and flags and counters.
  - For every visited level: `item`, `iarg`, `know`, `mitem` (monster + stolen items) and `hitp`.
  - Spheres, `beenhere`, and the per-game monster table (scaled by `sethard`, with renames and genocide flags).
  - Compact encoding: each level's layers as one string or number array per row (`string.char`-packed where values < 256), not 1,139 small tables.
- **When saved:** state lives in the SV table at all times. WoW writes SVs only on logout or `/reload`, so a client crash loses progress since then. Say so in the README.
- **Permadeath:** death or a win clears `char.game` and records the score. `S` closes the window; reopening resumes. There's no save-scum protection beyond that.
- A `version` field allows future migrations.

---

## 11. Localization

- UI chrome (buttons, tooltips, dialog titles, options, slash help) goes through AceLocale. Babelfish generates the non-enUS files.
- **Game text** (monster/item names, messages, store dialogs, help, fortunes) stays **English in the Lua source and data tables** for now, because of the volume. It is collected so it can be localized later. A proportional-font UI removes the 80-column length constraint, so later localization is feasible.

---

## 12. Milestones

Each milestone is playable or testable in game.

1. **Frame + plumbing** (done): main frame with the three regions, coroutine runner, UI API stubs, input/focus, message log, `/larn` to open. Test: echo key presses to the log.
2. **Data + town** (done, flat tile renderer):
   - constants (1-based) and data tables, `Data/Visuals.lua` with fallbacks
   - character creation (§9), level 0 rendered with tiles
   - movement and run, minimap, stats panel, player model
   - still to do from this list: icon names in `Data/Visuals.lua` are placeholders to check in game; tile hover tooltips and click-to-move; the spell, scroll and potion tables (milestones 5 and 6); standing on a building does nothing yet (milestone 8)
3. **Dungeon** (done):
   - `Create.lua`: `makeMaze` (recursive-backtracker `Eat`, open rooms, corridor), `CannedLevel`, `TreasureRoom`/`TRoom`, `makeObject` with all object rules; `Item.lua`: `cgood`, `createItem`, `dropGold`, `something`, `newObject`; `Player.packWeight`, `Player.losehp`, `Player.died` (sets `G.dead`; the game loop ends when it is set, so code after `losehp` must check `G.dead`)
   - `Object.lua`: dungeon entrance, stairs up and down, volcano shafts; `newCaveLevel` keeps visited levels; `ui:Choose` is the "(g) go inside, or (i) ignore it?" prompt
   - depth-themed ground colours in `Visuals.Ground`
   - the monster hooks `Monster.makeMonst` and `Monster.createMonster` are stubs until milestone 4, so levels have no monsters yet; Dealer McDope's pad (`OPAD`) is the goblin alchemist's
   - deviations from the C, all deliberate: `scprob` and `potprob` are rolled one past their end in the C (it reads the next array); the C most likely reads a 0 from the array that follows, so the first entry is used instead. A door in a treasure room may sit in a corner, so tests treat diagonal steps as connected. Canned maps have no level-1 exit; entering the dungeon opens it, as in the C. The `rnd(n)` loop limits in `makeObject` are re-rolled on every pass, as in the C.
   - still to do from this list: pits, trapdoors, elevators and the rest of the features (milestone 7)
4. **Monsters + combat** (done, flat tile renderer):
   - `Monster.lua`: `makeMonst`, `createMonster`, `fillMonst`, `hitmonster`, `hitm`, `hitplayer`, all 16 `spattack` attacks, `dropsomething`; `MoveMonst.lua`: `movemonst`, `movemt` (smart and dumb movement), `mmove`, `teleportMonst`; `Create.setHP` fills a level (demon lords on 11 to 15, demon princes in the volcano); `Player`: experience and level changes, max HP/spell helpers, `stealSomething`, `adjustCValues`, `emptyHanded`; `Item.createGem`
   - `G.monster` is a per-game copy of `ns.MonsterData` (`Monster.init`, called from `makePlayer`), because genocide changes the flags; `G.loot[x * 100 + y]` holds what a monster carries (C: `mitem[][].it`) and is saved with the level
   - monsters are drawn as their ASCII letter in red (tiles and minimap); invisible stalkers, demons without the eye of Larn and the mimic follow `Display.visibleMonster`
   - deliberate carry-overs from the C: a fire-breathing monster still hurts a fire-resistant player (the C `else` only guards the message); the scared-monster branch of `movemt` reads the `tmpitem` left over from an earlier move, as the C does
   - difficulty: `Monster.init` scales the monsters by `c[HARDGAME]` (C: `sethard`); no option sets the difficulty yet, so it is always 0
   - left out on purpose: the spheres of annihilation (`movsphere`, `rmsphere`, the `OANNIHILATION` branch of `mmove`) wait for the spells in milestone 6; `annihilate` and `genmonst` belong to scrolls and spells (5 and 6)
   - still to do from this list: monster icons or portraits on the tiles and the target model with animations (they need the models of milestone 10; the glyphs are the fallback), the death screen and scoreboard (milestone 9)
5. **Items:**
   - `makeobject` and pickup (`lookforobject`)
   - inventory window, `PickItem`, wield/wear/take off, drop
   - all potions and scrolls; gold, gems, chests, books and cookies
   - traps, pits, trapdoors, teleporters and elevators; effects row
6. **Spells:** spellbook, `PickSpell`/`PickDirection`, all 39 spells, `spelweird`, projectile/area animations, spheres of annihilation.
7. **Features + artifacts:** altars, thrones, fountains, statues, mirrors, the brass lamp genie, and all unique artifact effects.
8. **Town buildings:** store windows for DND store, school, bank and 5th branch, trading post, LRS taxes, home, and the goblin alchemist.
9. **Endgame + persistence:** save/resume in SVs, win at home, time limit, scoreboards (winners/dead with inventory), tax letters.
10. **2.5D view:**
    - projection, perspective floor quads, wall panels
    - pooled `PlayerModel` actors with display lookup, per-monster tune, the depth fix (`Seat` technique) and animations
    - move tweens, spell effects, lighting/fog for remembered cells
    - debug model viewer for curating `Data/Visuals.lua`
11. **Options + polish:** difficulty, monster renames, fast mode (no naps), tile size, ASCII fallback renderer, colors, LDB/minimap launcher, races (§9).

---

## 13. Open decisions

1. ~~Dealer McDope's Pad~~ **Decided: goblin alchemist.** `OPAD` becomes **Grizzik's Questionable Elixirs**, a goblin alchemist's shop.
   - Each item becomes a goblin potion with the **same price, same effect code (`object.c`, `regen.c:COKED`) and one-per-game limit (`drug[]`)**.
   - The object ids keep their C names internally (`OSPEED`… `OCOKE`) so the port stays comparable with the C. Only display names and messages change.

   | C item (price) | Effect (from C) | WoWLarn name |
   |---|---|---|
   | Killer Speed (100) | haste self + half damage taken; −2 all stats (min 3) | **Goblin Rocket Fuel** |
   | Groovy Acid (250) | confused, +2 WIS/INT, long awareness *and* aggravate, heals all monsters on level | **Gnomish Mind-Expander** |
   | Monster Hash (500) | monsters hasted, +2 INT/WIS, −2 CON/DEX, half damage, long clumsiness | **Volatile Swamp Brew** |
   | Trippy Shrooms (1000) | monsters hasted, confused, +2 WIS/CHA | **Glowcap Stew** |
   | Cool Coke (5000) | +33 all stats for 10 turns then −34 (`COKED`), +3 CHA, −2 DEX/CON | **Overcharged Fel Tonic** |

   - **Usage:**
     - In C you use these by dropping one and stepping on it, which brings up a snort/eat/smoke prompt.
     - WoWLarn keeps the step-on prompt as **drink / take / ignore**.
     - It also lets you **drink them straight from inventory** (with `q`, or by clicking the item). This is a small UX change; the effects are identical.
     - Unlike real potions they are always identified, as in the original.
   - Messages are rewritten in goblin flavour (e.g. "Time is money, friend!"). The shop window uses an alchemist NPC model and potion icons.
2. ~~Monster display IDs~~ **Decided:**
   - Monsters with an obvious WoW equivalent (kobold, orc, troll, dragons, …) keep their name and get that look.
   - **Monsters that don't translate** (lemming, jaculi, ziller, lama nobe, osequip, rothe, xvart, bitbug, green urchin, …) are **replaced by a WoW creature of similar difficulty**:
     - Use the Ularn monster's `level` (1–20) and its place in `data.c:monster[]` to pick a classic creature from a comparable tier, e.g. low levels → Elwynn/Durotar critters and beasts, mid → Stranglethorn/Badlands, deep → raid-tier demons and elementals.
     - Try to keep the flavour of its special attack, e.g. the theft attackers become a thief-type creature.
     - The creature takes that WoW name. Only the display name and look change; stats, flags, special attack and `spelweird` stay the original monster's.
   - The mapping lives in `Data/Visuals.lua` (name override + displayID + tune) and still needs an in-game curation pass with the model viewer.
3. ~~Wizard mode~~ **Decided: a debug mode that is not shipped.**
   - Port the wizard commands and every `wizard` check in the C:
     - `=` toggle, with no password
     - `#` max experience; `_` debug kit (stats 70, Lance of Death, all spells, potions and scrolls known, map revealed)
     - `@` create item; `Z` teleport to any level 0–20; `A` dump state to the chat/log
     - the side effects: levels revealed, enchantments shown, some penalties skipped, genocided monsters still creatable
   - **Packaging:** all of it sits inside `--@debug@` … `--@end-debug@` blocks, or in a `Debug.lua` that is only listed in the `.toc` between `#@debug@` / `#@end-debug@`. The packager strips it from releases, so wizard mode exists only in the dev checkout.
   - Wizard games never record scores, as in C.
   - Debug-only extras go in the same place: the model viewer (§7.1) and `/larn` debug subcommands (e.g. `/larn level 15`, `/larn spawn <monster>`).
4. ~~Map renderer default~~ **Decided:**
   - The 2.5D model view (§6.1) is the goal, with a **fixed north-up tilted camera**. A rotating camera would make the 8 movement directions confusing.
   - Build the **flat tile renderer first** (milestones 2–5), then add 2.5D as milestone 10. Both sit behind the `MapView` interface.
5. ~~Tile art source~~ **Decided:** use **WoW textures/fileIDs** first, with the flat-color fallback. Revisit a bundled texture set later if WoW art doesn't work well or isn't available on all clients.
