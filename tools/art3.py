#!/usr/bin/env python3
"""Third pass at the pictures: the real flyer or box art first, wherever there is one.

The first two passes took the title screen first, which is only the arcade board's own
picture (about 300 pixels across) and looks rough blown up on the shelf. This asks the
same archive for the flyer first, then a title screen only for games that have no
picture at all. The picture it replaces is kept in media/titles/ so nothing is lost.

    python3 art3.py            count what would change, touch nothing
    python3 art3.py --go       fetch and replace
"""
import json, os, re, sys, urllib.parse, urllib.request, xml.etree.ElementTree as ET

ROOT = os.path.expanduser("~/roms/arcade")
CACHE = os.path.expanduser("~/.cache/fbneo")
BASE = "https://thumbnails.libretro.com/FBNeo%20-%20Arcade%20Games"
TREE = ("https://api.github.com/repos/libretro-thumbnails/"
        "FBNeo_-_Arcade_Games/git/trees/master?recursive=1")
BOX = "Named_Boxarts"
TITLE = "Named_Titles"
SMALL = 400          # a picture narrower and shorter than this is worth replacing

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
    by_kind = {BOX: {}, TITLE: {}}
    for node in data.get("tree", []):
        p = node.get("path", "")
        for k in by_kind:
            if p.startswith(k + "/") and p.endswith(".png"):
                by_kind[k][p[len(k) + 1:-4]] = p
    return by_kind

def simple(s):
    s = s.lower()
    s = re.sub(r"\([^)]*\)", " ", s)
    s = re.sub(r"\[[^\]]*\]", " ", s)
    return re.sub(r"[^a-z0-9]+", "", s)

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

def find(lookup, want):
    name = lookup.get(want)
    if name:
        return name
    # a title that starts the same way will do (regions and versions differ)
    for key, n in lookup.items():
        if want and (key.startswith(want) or want.startswith(key)) and abs(len(key) - len(want)) < 12:
            return n
    return None

def size_of(path):
    try:
        from PIL import Image
        return Image.open(path).size
    except Exception:
        return (0, 0)

def main():
    go = "--go" in sys.argv
    by_kind = index()
    lookup = {k: {simple(n): n for n in v} for k, v in by_kind.items()}
    dat = names_from_dats()
    games = []
    for dirpath, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in ("media", "boxart", "samples")]
        for f in files:
            if f.lower().endswith(".zip"):
                games.append((dirpath, f[:-4]))
    better = same = none = 0
    for dirpath, stem in sorted(games):
        art = os.path.join(dirpath, "media", stem + ".png")
        w, h = size_of(art)
        if max(w, h) >= SMALL:
            same += 1
            continue
        name = find(lookup[BOX], simple(dat.get(stem, stem)))
        if not name:
            none += 1
            continue
        better += 1
        if not go:
            print("  %-12s would get %s" % (stem, name), flush=True)
            continue
        try:
            data = fetch("%s/%s/%s.png" % (BASE, BOX, urllib.parse.quote(name)), timeout=60)
        except Exception as ex:
            print("  %-12s failed: %s" % (stem, ex), flush=True)
            continue
        if not data or len(data) < 2000:
            continue
        keep = os.path.join(dirpath, "media", "titles")
        os.makedirs(keep, exist_ok=True)
        if os.path.exists(art):
            os.replace(art, os.path.join(keep, stem + ".png"))
        with open(art, "wb") as fh:
            fh.write(data)
        print("  %-12s <- %s" % (stem, name), flush=True)
    print("%d games: %d get a flyer, %d already sharp, %d have no flyer (keep the title screen)"
          % (len(games), better, same, none))

main()
