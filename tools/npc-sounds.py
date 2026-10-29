#!/usr/bin/env python3
"""Prints the sounds of a classic NPC from wowhead: python3 tools/npc-sounds.py 1120

The first number of a line is the sound kit id, which can go in Data/Visuals.lua (V.MONSTER_SOUND)
and plays with PlaySound; the file data ids after it play with PlaySoundFile."""
import json, re, subprocess, sys

page = subprocess.run(["curl", "-sL", "-m", "30", "-A", "Mozilla/5.0",
                       f"https://www.wowhead.com/classic/npc={sys.argv[1]}"],
                      capture_output=True, text=True).stdout
match = re.search(r"id: 'sounds'.*?data:(\[.*?\])\}\);", page, re.S)
if not match:
    sys.exit("no sounds on the page")
for sound in json.loads(match.group(1)):
    files = ", ".join(str(f["id"]) for f in sound["files"])
    print(f'{sound["id"]:>7}  {sound["activity"]:<18} {sound["name"]}  files: {files}')
