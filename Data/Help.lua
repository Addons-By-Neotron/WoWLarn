-- The help texts. Page 1 is the story shown at the start of a game, page 2 the commands (the ?
-- key); the rest explain the special cases. Written by hand, based on the Ularn help file.

local _, ns = ...

local H = "|cffffd100"  -- headings
local R = "|r"

ns.HelpPages = {
   [[
    Welcome to the game of Ularn.  At this moment, you face a great problem.
Your daughter has contracted a strange disease and none of your home remedies
seems to have any effect.  You sense that she is in mortal danger and you must
try to save her.  Time ago you heard of a land of great danger and opportunity.
Perhaps here is the solution you need.

    It has been said that there once was a great magician who called himself
Polinneaus.  Many years ago, after having many miraculous successes, Polinneaus
retired to the caverns of Ularn, where he devoted most of his time to the
creation of magic.   Rumors have it that one day Polinneaus set out to dispel
an attacking army in a forest some distance to the north.  It is believed that
there he met his demise.

    The caverns of Ularn, it is thought, must be magnificent in design
and contain much magic and treasure.  One option you have is to undertake a
journey into these caverns.


    Good Luck!  (You're going to need it.)]],
   H.."Commands"..R..[=[

h j k l  move left, down, up, right          y u b n  move diagonally
H J K L Y U B N  run in that direction (or shift and an arrow key)     .  stay here
,  use what is here (stairs, altars, fountains...)
c  cast a spell        r  read a scroll        q  quaff a potion
e  eat a cookie        w  wield a weapon       W  wear armor
T  take off armor      d  drop an item         i  look in your pack
D  discoveries         ^  find traps           C  close a door
Z  teleport            g  your pack weight     P  your tax status
t  go to a place you found     B  the bestiary (button)
v  version             S  save and close       Q  quit the game
?  this help

The buttons at the bottom of the window do the same with the mouse.
Click the window to capture the keyboard, Esc releases it.  Hover over the
map, your stats, your effects and your items for tooltips.

Press t (or the map button) to go to a stairway, shop, altar and so on that you
have found.  You walk the shortest way, and stop at monsters, objects and traps.]=],
   H.."Special notes"..R..[=[

When dropping gold, if you type '*' as the amount, all your gold gets dropped.
In general, typing '*' means all of what you are interested in.  This is true
when visiting the bank, or when contributing at altars.

In the stores, the trading post, the school and the home, Esc gets you out, or
click Leave.  The Thrift Shoppe has several pages: space or > turns to the next,
< to the previous.

When casting a spell, type 'D' as the first letter to see the spells you know,
then type the three letter code of the spell, or click the spell.  Typing 'D'
at any other time shows all the spells you know, and the potions and scrolls
you have identified so far.

What is on a tile (stairs, altars, doors, items) comes up when you step on it.
Press ',' to bring it up again.

Going to a place: t lists the stairs, elevators, shops, altars, fountains and so
on that you have found, by name, with the steps to each.  The walk goes round
walls, traps and objects, through doors (you get the usual question), and stops
when a monster is near, when you are hit, or when you step on an object.  It
always says why it stopped.

The action bar at the bottom of the map holds ten slots for spells, potions
and scrolls, on the keys 1 to 0.  Right-click a slot to choose what it holds,
click it (or press its key) to use it.

The bestiary (the B button) lists the monsters you have met, and what you have
seen them do.  Items show what you have learned about them when you hover over
them; a power is only described once you have seen it work.

The classes are the Ularn ones, with WoW names.  The Glass Cannon starts with
1 hit point and the Lance of Death: it kills almost anything, until something
touches it.

A monster that is hit by an unseen attacker (an invisible stalker, a demon
lord without the Eye of Larn) stops your running for a moment.  Settings has
an optional elevator limit, to keep an express elevator from taking you many
levels at once.]=],
   H.."The high scores"..R..[=[

There are two lists, one for winners and one for characters that died, shared
by all your characters.  Each game gets its own entry, best score first, and
only the top ten of each list are kept.  When a character dies, its pack is
stored with the score, so you can hover over an entry to see what it carried.
The difficulty of the game is noted too.  Type /larn scores to see the lists.]=],
   H.."About"..R..[=[

WoWLarn is a port of Ularn 1.5 to World of Warcraft.

Ularn was written in 1987 by Phil Cordier at UC Santa Cruz, based on Larn by
Noah Morgan, and updated in 2001 by Josh Brandt and David Richerby.]=],
}
