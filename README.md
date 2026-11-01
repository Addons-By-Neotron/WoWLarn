# WoWLarn

A graphical World of Warcraft port of **Ularn 1.5**, the classic roguelike (Ularn was created by
Phil Cordier, based on Larn by Noah Morgan, and maintained by Josh Brandt and David Richerby).
The rules, maps, monsters, items and store prices follow the original C source, so the game plays
like Ularn. What changes is how it looks: WoW classes, models, icons, sounds and tooltips.

Works on Retail and Classic.

## Playing

- `/larn` opens the game window. Click the window to capture the keyboard, `Esc` releases it.
- Keys are the Ularn keys: `hjklyubn` move (capital letters run), `c` cast, `r` read, `q` quaff,
  `w` wield, `W` wear, `d` drop, `i` inventory, `e` eat, `D` discoveries, `,` use what is here,
  `.` rest, `t` go to a place, `S` save and close, `?` help. The button bar at the bottom of the
  window does the same with the mouse. `?` and the story at the start of a game open in a window
  over the map.
- The action bar has ten slots for spells, potions and scrolls, on the keys `1` to `0`.
  Right-click a slot to choose what it holds.
- `t` lists the places you have found (stairs, elevators, shops, altars, fountains, the way out)
  and walks you to the one you pick, by the shortest way. It goes through doors, and stops for
  monsters, hits, traps and objects, always saying why.
- The bestiary (`B`) lists the monsters you have met and what you have seen them do. Items
  describe their powers once you have seen them work.
- What is on a tile (stairs, altars, doors, items) comes up when you step on it.
  Press `,` to bring it up again.
- Hover over the map, the stats, the effects and the items for tooltips.
- Your game is saved with your character, and resumed the next time you open the window.
  WoW writes saved variables when you log out or `/reload`, so a crash loses what happened since.
- One life: dying ends the game and enters your score. The high scores are shared by all your
  characters (`/larn scores`).

## The 2.5D view

`/larn view` switches between flat tiles and a 2.5D view from behind the player, with the
character, monsters and animations drawn as WoW models. Options let you change the camera angle,
turn shadows, models and sounds off, or draw monsters as the original letters.

## Differences from the original

Deliberate changes are marked `FIX:` in the code. The main ones: the lemming cap, what is on a
tile only comes up when you step on it, every game gets its own place on the scoreboard, the log
says how much experience a kill gave and when a metamorph changes shape, and a new character
knows the potions and scrolls it starts with. Optional settings (all off by default): Races (a few
stat points from your character's race) and an elevator limit (the most levels an express
elevator can take you).

The eight classes keep the Ularn stats. Note they are not balanced: the Hunter is the best all
rounder, and the Glass Cannon (the WoW warlock) starts with 1 hit point and the Lance of Death.

## Commands

- `/larn` - show or hide the game window
- `/larn config` - open the settings
- `/larn view` - flat tiles or 2.5D
- `/larn scores` - show the high scores
- `/larn sounds` - play every sound effect, with its name
- `/larn models` - model viewer for choosing monster looks
- `/larn reset` - reset the window position

## License

GPL v2, see `LICENSE`.
