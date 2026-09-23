#!/usr/bin/env python3
"""Write out the real title of every arcade game on the machine.

The files are named the short way (mspacman.zip) but the emulator's own name list has
"Ms. Pac-Man"; this puts the two together in one file the menu reads.
"""
import os, re, urllib.request, xml.etree.ElementTree as ET

ROOT = os.path.expanduser("~/roms/arcade")
OUT = os.path.join(ROOT, "names.txt")
CACHE = os.path.expanduser("~/.cache/fbneo")
URLS = [
    "https://raw.githubusercontent.com/libretro/FBNeo/master/dats/"
    "FinalBurn%20Neo%20%28ClrMame%20Pro%20XML%2C%20Arcade%20only%29.dat",
    "https://raw.githubusercontent.com/libretro/FBNeo/master/dats/"
    "FinalBurn%20Neo%20%28ClrMame%20Pro%20XML%2C%20Neogeo%20only%29.dat",
]

def dat_files():
    os.makedirs(CACHE, exist_ok=True)
    out = []
    for i, url in enumerate(URLS):
        path = os.path.join(CACHE, "names%d.dat" % i)
        if not os.path.exists(path) or os.path.getsize(path) < 50000:
            print("fetching name list %d..." % i, flush=True)
            req = urllib.request.Request(url, headers={"User-Agent": "cab/1.0"})
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
            with open(path, "wb") as f:
                f.write(data)
        out.append(path)
    return out

DATS = dat_files()
# the menu's lettering has these and nothing else
KEEP = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,-:<>!?/'#@")

def tidy(desc):
    # "1941: Counter Attack (World)" -> "1941: COUNTER ATTACK"
    desc = re.sub(r"\s*\([^)]*\)", "", desc)
    desc = re.sub(r"\s*\[[^\]]*\]", "", desc)
    desc = desc.replace("&", " AND ").replace("_", " ")
    desc = desc.upper()
    desc = "".join(ch if ch in KEEP else " " for ch in desc)
    return re.sub(r"\s+", " ", desc).strip()

names = {}
for path in DATS:
    if not os.path.exists(path):
        continue
    for ev, el in ET.iterparse(path, events=("end",)):
        if el.tag in ("game", "machine"):
            n, d = el.get("name"), el.findtext("description")
            if n and d:
                names[n] = d
            el.clear()

have = []
for dirpath, dirnames, files in os.walk(ROOT):
    if os.path.basename(dirpath) in ("media", "boxart", "samples"):
        continue
    for f in files:
        if f.lower().endswith(".zip"):
            have.append(f[:-4])

lines, known = [], 0
for stem in sorted(set(have)):
    d = names.get(stem)
    if d:
        pretty = tidy(d)
        if pretty:
            lines.append("%s\t%s" % (stem, pretty))
            known += 1
with open(OUT, "w") as f:
    f.write("\n".join(lines) + "\n")
print("games on the machine: %d, real titles for %d" % (len(set(have)), known))
print("wrote", OUT)
for line in lines[:6]:
    print("  ", line)
