#!/usr/bin/env python3
"""Work out which of the games on the machine two people can play at once.

NPlayers (nplayers.arcadebelgium.be) says, for every arcade game, how many people can
play and whether they play together or take turns. "Together" is the list worth having
on a cocktail table.
"""
import os, re, subprocess, urllib.request, zipfile, io

ROOT = os.path.expanduser("~/roms/arcade")
CACHE = os.path.expanduser("~/.cache/nplayers")
URL = "https://nplayers.arcadebelgium.be/files/nplayers0278.zip"
OUT_SIM = os.path.join(ROOT, "together.txt")
OUT_ALL = os.path.join(ROOT, "players.txt")

def ini_text():
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, "nplayers.ini")
    if not os.path.exists(path) or os.path.getsize(path) < 100000:
        req = urllib.request.Request(URL, headers={"User-Agent": "cab/1.0"})
        with urllib.request.urlopen(req, timeout=120) as r:
            z = zipfile.ZipFile(io.BytesIO(r.read()))
        with open(path, "wb") as f:
            f.write(z.read("nplayers.ini"))
    return open(path, encoding="utf-8", errors="replace").read()

counts = {}
for line in ini_text().splitlines():
    if "=" in line and not line.startswith(";"):
        name, kind = line.split("=", 1)
        counts[name.strip()] = kind.strip()

have = []
for dirpath, dirnames, files in os.walk(ROOT):
    if os.path.basename(dirpath) in ("media", "boxart", "samples"):
        continue
    for f in files:
        if f.lower().endswith(".zip"):
            have.append(f[:-4])
have = sorted(set(have))

together, everything, unknown = [], [], []
for stem in have:
    kind = counts.get(stem)
    if not kind:
        unknown.append(stem)
        continue
    everything.append("%s\t%s" % (stem, kind))
    m = re.match(r"(\d)P", kind)
    if m and int(m.group(1)) >= 2 and "sim" in kind.lower():
        together.append(stem)

with open(OUT_SIM, "w") as f:
    f.write("\n".join(together) + "\n")
with open(OUT_ALL, "w") as f:
    f.write("\n".join(everything) + "\n")

print("games on the machine: %d" % len(have))
print("two or more play at once: %d" % len(together))
print("not in the list at all: %d" % len(unknown))
print("first few:", ", ".join(together[:10]))
