#!/usr/bin/env python3
"""Which table games can really turn the picture round for player 2, read from the
emulator's own source. Runs on the cabinet.

A table game asks its hardware to flip the screen when the player opposite takes a
turn. Each game's code in the emulator notes that request in a flip setting, but a
note is not a flip: the drawing code has to act on it. So for each game this looks at
its own code file for flip settings, and asks whether anything ever READS one --
beyond setting it, clearing it at switch-on, or saving it.

    python3 flipsource.py        writes arcade/flipsupport.json
"""
import json, os, re

SRC = os.path.expanduser("~/.cache/fbneo-src/src/burn/drv")
ROOT = os.path.expanduser("~/roms/arcade")
DRIVER = re.compile(r"struct\s+BurnDriver\w*\s+\w+\s*=\s*\{(.*?)\n\};", re.S)
FIRST = re.compile(r'^\s*"([A-Za-z0-9_\-]+)"')
FLIPVAR = re.compile(r"\b(\w*flip\w*)\b", re.I)
# the emulator's own drawing helpers take a flip as they draw: using one is reading it
HELPERS = ("BurnTransferFlip", "GenericTilemapSetFlip", "TMAP_FLIP", "flipscreen_x",
           "GenericTilesSetClipRaw")

where = {}
for dirpath, _, files in os.walk(SRC):
    for fn in files:
        if not fn.endswith((".cpp", ".c")):
            continue
        path = os.path.join(dirpath, fn)
        text = open(path, encoding="utf-8", errors="replace").read()
        for m in DRIVER.finditer(text):
            f = FIRST.search(m.group(1))
            if f:
                where[f.group(1)] = path

# Only a WHOLE-SCREEN flip counts. Every sprite has its own mirror bits too (flipx,
# flipy, TILE_FLIPYX), and those have nothing to do with turning the picture round
# for the player opposite -- counting them made 1942 look fine when it is not.
SCREENFLIP = re.compile(r"\b(\w*(?:flip_?screen|screen_?flip|flipscr)\w*)\b", re.I)

def clean(code):
    code = re.sub(r"/\*.*?\*/", " ", code, flags=re.S)
    code = re.sub(r"//[^\n]*", " ", code)
    return re.sub(r'"(\\.|[^"\\])*"', '""', code)

every = {}
for dirpath, _, files in os.walk(SRC):
    for fn in files:
        if fn.endswith((".cpp", ".c", ".h")):
            p = os.path.join(dirpath, fn)
            every[p] = clean(open(p, encoding="utf-8", errors="replace").read())

def reads_of(name, texts):
    found = []
    pat = re.compile(r"\b%s\b" % re.escape(name))
    for text in texts:
        for line in text.splitlines():
            if not pat.search(line):
                continue
            s = line.strip()
            if re.match(r"^(extern\s+)?(static\s+)?(UINT8|UINT16|UINT32|INT32|INT8|int|bool|char)\b", s):
                continue                                  # a declaration
            if re.match(r"^\*?\s*%s\s*(\[[^\]]*\])?\s*[|&^]?=[^=]" % re.escape(name), s):
                continue                                  # being set, directly or by pointer
            if re.search(r"%s\s*=[^=]" % re.escape(name), s) and not re.search(
                    r"(if|while|\?|return).*%s" % re.escape(name), s):
                continue                                  # set in the middle of a line
            if "SCAN_VAR" in s or "memset" in s:
                continue                                  # being saved or cleared
            found.append(s[:90])
    return found

cache = {}
def verdict(path):
    if path in cache:
        return cache[path]
    code = every[path]
    # a name followed by "(" is a function that writes the setting, not the setting
    names = {n for n in SCREENFLIP.findall(code)
             if not re.search(r"%s\s*\(" % re.escape(n), code)}
    if not names:
        cache[path] = (None, [], [])
        return cache[path]
    reads = []
    for n in names:
        local = re.search(r"^\s*static\s+\w+\s+[^;]*\b%s\b" % re.escape(n), code, re.M)
        reads += reads_of(n, [code] if local else list(every.values()))
    cache[path] = (bool(reads), reads[:3], sorted(names))
    return cache[path]

games = [g.strip() for g in open(ROOT + "/cocktail2p.txt") if g.strip()]
out = {}
for g in games:
    path = where.get(g)
    if not path:
        out[g] = {"flips": None, "why": "not found in the emulator"}
        continue
    ok, reads, names = verdict(path)
    out[g] = {"flips": ok, "file": os.path.basename(path), "evidence": reads[:3], "names": names}
json.dump(out, open(ROOT + "/flipsupport.json", "w"), indent=1, sort_keys=True)
yes = sorted(g for g, v in out.items() if v["flips"])
no = sorted(g for g, v in out.items() if v["flips"] is False)
unk = sorted(g for g, v in out.items() if v["flips"] is None)
print("table games:", len(out), "| can flip:", len(yes), "| cannot:", len(no), "| unknown:", len(unk))
print("CANNOT FLIP:", " ".join(no))
print("NO SCREEN FLIP SETTING AT ALL:", " ".join(unk))
for g in ("1942", "aurail", "pacman", "mspacman", "galaga", "jrpacman", "dkong", "bombjack", "armorcar"):
    if g in out:
        print(" ", g, out[g]["flips"], out[g].get("file"), out[g].get("evidence", [])[:1])
