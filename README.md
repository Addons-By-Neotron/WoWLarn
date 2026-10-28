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
  `.` rest, `S` save and close, `?` help. The button bar at the bottom of the window does the same
  with the mouse.
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
tile only comes up when you step on it, every game gets its own place on the scoreboard, and the
optional Races setting (a few stat points from your character's race).

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
