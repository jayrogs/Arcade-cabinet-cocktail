#!/usr/bin/env python3
"""Which games can flip the screen for the player sitting opposite.

A real cocktail table has a switch inside that tells the game it is a table, not an
upright: the picture then turns round for player two's turn. That switch lives in the
emulator's own description of each game, so this reads it straight from the source.
"""
import os, re, subprocess, sys, tarfile, urllib.request

ROOT = os.path.expanduser("~/roms/arcade")
SRC = os.path.expanduser("~/.cache/fbneo-src")
TARBALL = "https://codeload.github.com/libretro/FBNeo/tar.gz/refs/heads/master"
OUT = os.path.join(ROOT, "cocktail.txt")

def source_tree():
    marker = os.path.join(SRC, "done")
    if os.path.exists(marker):
        return SRC
    os.makedirs(SRC, exist_ok=True)
    tgz = os.path.join(SRC, "fbneo.tar.gz")
    if not os.path.exists(tgz) or os.path.getsize(tgz) < 10_000_000:
        print("fetching the emulator's source (this is the slow bit)...", flush=True)
        req = urllib.request.Request(TARBALL, headers={"User-Agent": "cab/1.0"})
        with urllib.request.urlopen(req, timeout=600) as r, open(tgz, "wb") as f:
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
    print("unpacking just the game descriptions...", flush=True)
    with tarfile.open(tgz) as tf:
        for m in tf:
            if "/src/burn/drv/" in m.name and m.name.endswith((".cpp", ".c", ".h")):
                m.name = m.name.split("/", 1)[1]
                tf.extract(m, SRC)
    open(marker, "w").write("ok\n")
    return SRC

DRIVER = re.compile(
    r"struct\s+BurnDriver\w*\s+\w+\s*=\s*\{(.*?)\n\};", re.S)
NAME = re.compile(r'"\s*([A-Za-z0-9_\-]+)\s*"')
# the table is called XxxDIPList and the game refers to XxxDIPInfo; a macro joins
# the two, so both are matched on the Xxx part
DIPREF = re.compile(r"\b(\w+)DIPInfo\b")
TABLE = re.compile(r"BurnDIPInfo\s+(\w+)DIPList\s*\[\s*\]\s*=\s*\{(.*?)\n\};", re.S)

def main():
    tree = source_tree()
    cocktail_tables, cocktail_games, all_games = set(), set(), set()
    for dirpath, _, files in os.walk(tree):
        for fn in files:
            if not fn.endswith((".cpp", ".c")):
                continue
            path = os.path.join(dirpath, fn)
            try:
                text = open(path, encoding="utf-8", errors="replace").read()
            except Exception:
                continue
            if "BurnDriver" not in text:
                continue
            here = set()
            for m in TABLE.finditer(text):
                if "cocktail" in m.group(2).lower():
                    here.add(m.group(1))
            cocktail_tables |= here
            for m in DRIVER.finditer(text):
                body = m.group(1)
                n = NAME.search(body)
                if not n:
                    continue
                short = n.group(1)
                all_games.add(short)
                for ref in DIPREF.findall(body):
                    if ref in here:
                        cocktail_games.add(short)
                        break

    have = []
    for dirpath, dirnames, files in os.walk(ROOT):
        if os.path.basename(dirpath) in ("media", "boxart", "samples"):
            continue
        for f in files:
            if f.lower().endswith(".zip"):
                have.append(f[:-4])
    have = sorted(set(have))

    mine = [g for g in have if g in cocktail_games]
    with open(OUT, "w") as f:
        f.write("\n".join(mine) + "\n")
    print("games the emulator describes: %d" % len(all_games))
    print("of those, ones with a cocktail switch: %d" % len(cocktail_games))
    print("on this machine: %d of %d" % (len(mine), len(have)))
    print("wrote", OUT)
    print("first few:", ", ".join(mine[:12]))

main()
