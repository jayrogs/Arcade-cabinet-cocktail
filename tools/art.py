#!/usr/bin/env python3
"""Fetch a picture for every arcade game on the cabinet.

The files are named the short way (1941.zip) but the picture archive is named the long
way ("1941 - Counter Attack (World)"), so the emulator's own name list is used to join
the two. Title screens first, then a gameplay shot, then the cabinet flyer.
"""
import os, re, sys, urllib.parse, urllib.request, xml.etree.ElementTree as ET

ROOT = os.path.expanduser("~/roms/arcade")
DAT = "/tmp/fbneo.dat"
BASE = "https://thumbnails.libretro.com/FBNeo%20-%20Arcade%20Games"
KINDS = ["Named_Titles", "Named_Snaps", "Named_Boxarts"]
DAT_URLS = [
    "https://raw.githubusercontent.com/libretro/FBNeo/master/dats/"
    "FinalBurn%20Neo%20%28ClrMame%20Pro%20XML%2C%20Arcade%20only%29.dat",
    "https://raw.githubusercontent.com/libretro/FBNeo/master/dats/"
    "FinalBurn%20Neo%20%28ClrMame%20Pro%20XML%2C%20Neogeo%20only%29.dat",
]

def fetch(url, path=None, timeout=40):
    req = urllib.request.Request(url, headers={"User-Agent": "cab/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
    if path:
        with open(path, "wb") as f:
            f.write(data)
    return data

def load_names():
    names = {}
    for i, url in enumerate(DAT_URLS):
        path = "%s.%d" % (DAT, i)
        if not os.path.exists(path) or os.path.getsize(path) < 50000:
            print("fetching name list %d..." % i, flush=True)
            fetch(url, path, timeout=120)
        for ev, el in ET.iterparse(path, events=("end",)):
            if el.tag in ("game", "machine"):
                n, d = el.get("name"), el.findtext("description")
                if n and d:
                    names[n] = d
                el.clear()
    return names

# the archive swaps these characters for an underscore
BAD = re.compile(r"[&*/:`<>?\\|\"]")
def thumb_name(desc):
    return urllib.parse.quote(BAD.sub("_", desc))

def main():
    names = load_names()
    print("names known:", len(names), flush=True)
    todo = []
    for dirpath, dirnames, files in os.walk(ROOT):
        if os.path.basename(dirpath) in ("media", "boxart", "samples"):
            continue
        for f in files:
            if f.lower().endswith(".zip"):
                todo.append((dirpath, f[:-4]))
    print("games:", len(todo), flush=True)
    got = miss = skip = 0
    for dirpath, stem in sorted(todo):
        media = os.path.join(dirpath, "media")
        out = os.path.join(media, stem + ".png")
        if os.path.exists(out) and os.path.getsize(out) > 0:
            skip += 1
            continue
        desc = names.get(stem)
        if not desc:
            miss += 1
            continue
        os.makedirs(media, exist_ok=True)
        for kind in KINDS:
            url = "%s/%s/%s.png" % (BASE, kind, thumb_name(desc))
            try:
                data = fetch(url)
            except Exception:
                continue
            if data and len(data) > 500:
                with open(out, "wb") as fh:
                    fh.write(data)
                got += 1
                break
        else:
            miss += 1
        if (got + miss) % 25 == 0:
            print("got %d, none for %d, already had %d" % (got, miss, skip), flush=True)
    print("DONE got %d, none for %d, already had %d" % (got, miss, skip), flush=True)

main()
