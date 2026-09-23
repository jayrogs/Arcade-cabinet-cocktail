#!/usr/bin/env python3
"""Tell every table-capable game that it is in a table.

Each of these games has a switch inside it for "upright or cocktail". Set to cocktail,
the picture turns round for whoever is sitting opposite when it is their turn. This
writes that switch for each game, so nobody has to dig through a menu.
"""
import os

ROOT = os.path.expanduser("~/roms/arcade")
CFGDIR = os.path.expanduser("~/.config/retroarch/config/FinalBurn Neo")
LIST = os.path.join(ROOT, "cocktail2p.txt")

os.makedirs(CFGDIR, exist_ok=True)
games = [g.strip() for g in open(LIST) if g.strip()]
written = 0
for g in games:
    path = os.path.join(CFGDIR, g + ".opt")
    lines = {}
    if os.path.exists(path):
        for line in open(path):
            if "=" in line:
                k, v = line.split("=", 1)
                lines[k.strip()] = v.strip()
    lines['fbneo-dipswitch-%s-Cabinet' % g] = '"Cocktail"'
    with open(path, "w") as f:
        for k in sorted(lines):
            f.write("%s = %s\n" % (k, lines[k]))
    written += 1
print("told %d games they are in a table" % written)
print("example:", os.path.join(CFGDIR, games[0] + ".opt"))
print(open(os.path.join(CFGDIR, games[0] + ".opt")).read().strip())
