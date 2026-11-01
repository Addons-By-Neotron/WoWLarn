-- The help texts: the story shown at the start of a game (ns.HelpPages[1]) and the sections of
-- the help window, the ? key (ns.HelpSections; UI/HelpWindow.lua). Written by hand, based on the
-- Ularn help file.

local _, ns = ...

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
}

-- Each section: a title, a table of commands { keys, what it does } and/or text (paragraphs
-- are separated by an empty line; the window wraps them).
ns.HelpSections = {
   { title = "Commands",
     commands = {
        { "h j k l", "Move left, down, up, right" },
        { "y u b n", "Move diagonally" },
        { "H J K L Y U B N", "Run (shift and an arrow key runs too)" },
        { ".", "Rest here" },
        { ",", "Use what is here: stairs, altars, fountains..." },
        { "t", "Go to a place you have found" },
        { "c", "Cast a spell" },
        { "r", "Read a scroll" },
        { "q", "Quaff a potion" },
        { "e", "Eat a cookie" },
        { "w", "Wield a weapon" },
        { "W", "Wear armor" },
        { "T", "Take off armor" },
        { "d", "Drop an item" },
        { "C", "Close a door" },
        { "^", "Find traps" },
        { "Z", "Teleport" },
        { "i", "Look in your pack" },
        { "I", "Sort your pack" },
        { "D", "Discoveries" },
        { "g", "Your pack weight" },
        { "V", "Flat tiles or the 2.5D view" },
        { "v", "Version" },
        { "S", "Close the window" },
        { "Q", "Quit the game" },
        { "?", "This help" },
     },
     text = "The buttons below the map do the same with the mouse.  Click the window to capture the keyboard, Esc releases it.  Hover over the map, your stats, your effects and your items for tooltips." },
   { title = "Going places",
     text = "Press t (or its button) for a list of the stairs, elevators, shops, altars, fountains and so on that you have found, by name, with the steps to each.  Pick one and you walk there by the shortest way, round walls, traps and objects, and through doors (you get the usual question).\n\nThe walk stops when a monster is near, when you are hit, or when you step on an object, and it always says why.  Stepping on the place you picked does what it always does: stairs, shops, altars and the rest." },
   { title = "The action bar",
     text = "The bar at the bottom of the map holds ten slots for spells, potions and scrolls, on the keys 1 to 0.  Right-click a slot to choose what it holds, click it or press its key to use it." },
   { title = "Special notes",
     text = "When dropping gold, if you type '*' as the amount, all your gold gets dropped.  In general, typing '*' means all of what you are interested in.  This is true when visiting the bank, or when contributing at altars.\n\nIn the stores, the trading post, the school and the home, Esc gets you out, or click Leave.  The Thrift Shoppe has several pages: space or > turns to the next, < to the previous.\n\nWhen casting a spell, type 'D' as the first letter to see the spells you know, then type the three letter code of the spell, or click the spell.  Typing 'D' at any other time shows all the spells you know, and the potions and scrolls you have identified so far.\n\nWhat is on a tile (stairs, altars, doors, items) comes up when you step on it.  Press ',' to bring it up again.\n\nA potion or scroll you can identify offers (x) destroy it, to clear the bad ones off the floor.\n\nA run stops when a way opens to the side (a crossing, a door, the mouth of a room), in front of a known trap or pit, and when a monster you can see is close, so you have time to react.  A monster that hits you without being seen (an invisible stalker, a demon lord without the Eye of Larn) stops it too." },
   { title = "Learning about things",
     text = "The bestiary (the B button) lists the monsters you have met, and what you have seen them do.  Items show what you have learned about them when you hover over them; a power is only described once you have seen it work." },
   { title = "Classes and settings",
     text = "The classes are the Ularn ones, with WoW names.  The Glass Cannon starts with 1 hit point and the Lance of Death: it kills almost anything, until something touches it.\n\nA new game starts with a settings window: the difficulty, and some optional changes (all off by default): tough weapons, which resist being dulled the better they are (the Lance of Death never dulls), a limit on how far an express elevator can take you, and a few stat points from your character's race.  A game keeps the settings it was started with." },
   { title = "The high scores",
     text = "There are two lists, one for winners and one for characters that died, shared by all your characters.  Each game gets its own entry, best score first, and only the top ten of each list are kept.  When a character dies, its pack is stored with the score, so you can hover over an entry to see what it carried.  The difficulty of the game is noted too.  Type /larn scores to see the lists." },
   { title = "About",
     text = "WoWLarn is a port of Ularn 1.5 to World of Warcraft.\n\nUlarn was written in 1987 by Phil Cordier at UC Santa Cruz, based on Larn by Noah Morgan, and updated in 2001 by Josh Brandt and David Richerby." },
}
