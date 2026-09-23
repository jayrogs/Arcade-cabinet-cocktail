#!/usr/bin/env python3
"""Second pass at the pictures, for the games the first pass could not name.

The archive files every picture under the game's full title, which does not always
match the emulator's wording. This fetches the archive's own index and matches on the
title with the region and version bits taken off.
"""
import json, os, re, sys, urllib.parse, urllib.request, xml.etree.ElementTree as ET

ROOT = os.path.expanduser("~/roms/arcade")
CACHE = os.path.expanduser("~/.cache/fbneo")
BASE = "https://thumbnails.libretro.com/FBNeo%20-%20Arcade%20Games"
TREE = ("https://api.github.com/repos/libretro-thumbnails/"
        "FBNeo_-_Arcade_Games/git/trees/master?recursive=1")
KINDS = ["Named_Titles", "Named_Snaps", "Named_Boxarts"]

def fetch(url, timeout=120):
    req = urllib.request.Request(url, headers={"User-Agent": "cab/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()

def index():
    path = os.path.join(CACHE, "thumbs.json")
    if not os.path.exists(path) or os.path.getsize(path) < 100000:
        os.makedirs(CACHE, exist_ok=True)
        with open(path, "wb") as f:
            f.write(fetch(TREE, timeout=300))
    data = json.load(open(path))
    by_kind = {k: {} for k in KINDS}
    for node in data.get("tree", []):
        p = node.get("path", "")
        for k in KINDS:
            if p.startswith(k + "/") and p.endswith(".png"):
                name = p[len(k) + 1:-4]
                by_kind[k][name] = p
    return by_kind

def simple(s):
    s = s.lower()
    s = re.sub(r"\([^)]*\)", " ", s)
    s = re.sub(r"\[[^\]]*\]", " ", s)
    s = re.sub(r"[^a-z0-9]+", "", s)
    return s

def names_from_dats():
    out = {}
    for i in (0, 1):
        path = os.path.join(CACHE, "names%d.dat" % i)
        if not os.path.exists(path):
            continue
        for ev, el in ET.iterparse(path, events=("end",)):
            if el.tag in ("game", "machine"):
                n, d = el.get("name"), el.findtext("description")
                if n and d:
                    out[n] = d
                el.clear()
    return out

def main():
    by_kind = index()
    lookup = {k: {simple(n): n for n in v} for k, v in by_kind.items()}
    dat = names_from_dats()

    missing = []
    for dirpath, dirs, files in os.walk(ROOT):
        if os.path.basename(dirpath) in ("media", "boxart", "samples"):
            continue
        for f in files:
            if f.lower().endswith(".zip"):
                stem = f[:-4]
                art = os.path.join(dirpath, "media", stem + ".png")
                if not (os.path.exists(art) and os.path.getsize(art) > 0):
                    missing.append((dirpath, stem))

    print("looking for %d pictures" % len(missing), flush=True)
    got = 0
    for dirpath, stem in sorted(missing):
        want = simple(dat.get(stem, stem))
        found = None
        for k in KINDS:
            name = lookup[k].get(want)
            if not name:
                # a title that starts the same way will do
                for key, n in lookup[k].items():
                    if want and (key.startswith(want) or want.startswith(key)) and abs(len(key) - len(want)) < 12:
                        name = n
                        break
            if name:
                url = "%s/%s/%s.png" % (BASE, k, urllib.parse.quote(name))
                try:
                    data = fetch(url, timeout=60)
                except Exception:
                    continue
                if data and len(data) > 500:
                    os.makedirs(os.path.join(dirpath, "media"), exist_ok=True)
                    with open(os.path.join(dirpath, "media", stem + ".png"), "wb") as fh:
                        fh.write(data)
                    print("  %-12s <- %s" % (stem, name), flush=True)
                    got += 1
                    found = True
                    break
        if not found:
            print("  %-12s no picture anywhere" % stem, flush=True)
    print("found %d of %d" % (got, len(missing)))

main()
