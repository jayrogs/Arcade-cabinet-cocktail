#!/usr/bin/env python3
"""Which way up each arcade game's picture is, from the emulator's own records.

The recordings come out as the chips drew them: a tall game lies on its side. Each
game carries flags saying how its monitor was mounted, and this turns those into the
turn needed to stand the recording upright:

    0  as it is         1  a quarter turn clockwise
    2  upside down      3  a quarter turn anticlockwise
"""
import os, re, json

SRC = os.path.expanduser("~/.cache/fbneo-src")
DRIVER = re.compile(r"struct\s+BurnDriver\w*\s+\w+\s*=\s*\{(.*?)\n\};", re.S)
FIRST = re.compile(r'^\s*"([A-Za-z0-9_\-]+)"')
out = {}
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
            vert = "BDF_ORIENTATION_VERTICAL" in body
            flip = "BDF_ORIENTATION_FLIPPED" in body
            out[f.group(1)] = (1 if not flip else 3) if vert else (2 if flip else 0)
json.dump(out, open(os.path.expanduser("~/roms/arcade/orient.json"), "w"))
from collections import Counter
print(len(out), "games;", dict(Counter(out.values())))
for g in ("galaga", "pacman", "jrpacman", "1942", "dkong", "sf2", "kof94", "ddonpach"):
    print(" ", g, out.get(g))
