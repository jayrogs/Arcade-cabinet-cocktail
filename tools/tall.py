#!/usr/bin/env python3
"""Which of the arcade games are TALL -- made for a screen mounted the way this one is.

Read from the emulator's own description of each game, the same place the two-player
table list came from. Run on the cabinet:  python3 tall.py
"""
import os, re

SRC = os.path.expanduser("~/.cache/fbneo-src")
ROOT = os.path.expanduser("~/roms/arcade")
DRIVER = re.compile(r"struct\s+BurnDriver\w*\s+\w+\s*=\s*\{(.*?)\n\};", re.S)
FIRST = re.compile(r'^\s*"([A-Za-z0-9_\-]+)"\s*,\s*(NULL|"[^"]*")', re.S)

tall, wide, parent_of = set(), set(), {}
for dirpath, _, files in os.walk(SRC):
    for fn in files:
        if not fn.endswith((".cpp", ".c")):
            continue
        text = open(os.path.join(dirpath, fn), encoding="utf-8", errors="replace").read()
        for m in DRIVER.finditer(text):
            body = m.group(1)
            f = FIRST.search(body)
            if not f:
                continue
            name = f.group(1)
            parent_of[name] = None if f.group(2) == "NULL" else f.group(2).strip('"')
            (tall if "BDF_ORIENTATION_VERTICAL" in body else wide).add(name)

have = set()
for dirpath, _, files in os.walk(ROOT):
    if os.path.basename(dirpath) in ("media", "boxart", "samples"):
        continue
    for f in files:
        if f.lower().endswith((".zip", ".7z")):
            have.add(f.rsplit(".", 1)[0])

mine_tall = sorted(g for g in have if g in tall)
mine_wide = sorted(g for g in have if g in wide)
originals_tall = {g for g in tall if parent_of.get(g) is None}
missing = sorted(originals_tall - have)
print("games on the cabinet:            %d" % len(have))
print("  tall, fill the screen:         %d" % len(mine_tall))
print("  wide, show as a band:          %d" % len(mine_wide))
print("  the emulator does not know:    %d" % (len(have) - len(mine_tall) - len(mine_wide)))
print("tall games that exist (originals, not copies): %d" % len(originals_tall))
print("  of those, on the cabinet:      %d" % len(originals_tall & have))
print("  of those, NOT on the cabinet:  %d" % len(missing))
with open(os.path.join(ROOT, "tall.txt"), "w") as f:
    f.write("\n".join(mine_tall) + "\n")
with open(os.path.join(ROOT, "tall_missing.txt"), "w") as f:
    f.write("\n".join(missing) + "\n")
