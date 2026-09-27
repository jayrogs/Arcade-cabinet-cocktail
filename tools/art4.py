#!/usr/bin/env python3
"""Fourth pass at the arcade pictures: real box art, not operators' adverts.

art3.py put each game's flyer on the shelf, and many flyers turned out to be adverts for
arcade operators (often in Japanese), not covers. This gives each game, in order:
  1. the box of a home release with exactly the same title (US first, then world, Europe,
     Japan), from the libretro thumbnail archive's console sets
  2. otherwise its arcade title screen (the logo, no advert)
The picture it replaces is kept in media/flyers/.

    python3 art4.py              count what would change, touch nothing, list a sample
    python3 art4.py --go         fetch and replace
    python3 art4.py --go --only 1942,pang3     just these games
"""
import os, re, sys, urllib.parse, urllib.request, xml.etree.ElementTree as ET

ROOT = os.path.expanduser("~/roms/arcade")
CACHE = os.path.expanduser("~/.cache/fbneo")
BASE = "https://thumbnails.libretro.com/"
# the home machines an arcade game was most often brought to, best first
SYSTEMS = ["SNK - Neo Geo CD", "Sega - Saturn", "Sony - PlayStation", "Sega - Dreamcast",
           "Sega - Mega Drive - Genesis", "Nintendo - Super Nintendo Entertainment System",
           "NEC - PC Engine - TurboGrafx 16", "NEC - PC Engine CD - TurboGrafx-CD",
           "Sega - Mega-CD - Sega CD", "Sega - 32X", "Nintendo - Nintendo Entertainment System",
           "Sega - Master System - Mark III", "Atari - 7800", "Atari - 2600",
           "Nintendo - Game Boy Advance"]
REGIONS = ["usa", "world", "europe", "japan"]
# when each machine came out: the home version nearest the arcade game's own year is the one
# that was its real port (Centipede on the 2600, not the 1999 PlayStation remake)
YEAR = {"SNK - Neo Geo CD": 1994, "Sega - Saturn": 1994, "Sony - PlayStation": 1994,
        "Sega - Dreamcast": 1998, "Sega - Mega Drive - Genesis": 1988,
        "Nintendo - Super Nintendo Entertainment System": 1990,
        "NEC - PC Engine - TurboGrafx 16": 1987, "NEC - PC Engine CD - TurboGrafx-CD": 1988,
        "Sega - Mega-CD - Sega CD": 1991, "Sega - 32X": 1994,
        "Nintendo - Nintendo Entertainment System": 1983, "Sega - Master System - Mark III": 1985,
        "Atari - 7800": 1986, "Atari - 2600": 1977, "Nintendo - Game Boy Advance": 2001}
# releases that seldom have a real box of their own
ODD = re.compile(r"beta|proto|sample|aftermarket|e-reader|virtual console|mini\)|switch online|"
                 r"collection|archives|possible|demo|sega channel|unl\)|pirate|hack", re.I)
# arcade games whose home namesakes are different games: they get their title screen
DIFFERENT = {"asterix", "batman", "superman", "hook", "starwars", "gaiden", "rambo3", "godzilla",
             "krull", "airwolf", "robocop2", "drgnbstr", "tmnt2pj"}
# chosen by hand
CHOSEN = {"atetris": ("Nintendo - Nintendo Entertainment System", "Tetris (USA) (Tengen) (Unl)"),
          "atetrisc": ("Nintendo - Nintendo Entertainment System", "Tetris (USA) (Tengen) (Unl)")}


def fetch(url, timeout=90):
    req = urllib.request.Request(url, headers={"User-Agent": "cab/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def listing(system, kind="Named_Boxarts"):
    path = os.path.join(CACHE, "list_%s_%s.txt" % (re.sub(r"\W+", "_", system), kind))
    if os.path.exists(path):
        return open(path, encoding="utf-8").read().splitlines()
    try:
        html = fetch(BASE + urllib.parse.quote(system) + "/" + kind + "/").decode("utf-8", "replace")
    except Exception as ex:
        print("  no list for", system, kind, ex)
        return []
    names = [urllib.parse.unquote(h)[:-4] for h in re.findall(r'href="([^"/]+\.png)"', html)]
    open(path, "w", encoding="utf-8").write("\n".join(names))
    return names


def key(title):
    """a title reduced to letters and digits, so small differences in writing it match"""
    t = title.lower()
    t = re.sub(r"\([^)]*\)|\[[^\]]*\]", " ", t)
    t = re.sub(r"^(.*), the\b", r"the \1", t.strip())
    t = t.replace("&", " and ").replace("_", " ")
    t = re.sub(r"^the\s+", "", t.strip())
    return re.sub(r"[^a-z0-9]+", "", t)


def region(name):
    n = name.lower()
    for i, r in enumerate(REGIONS):
        if "(" + r in n or ", " + r in n:
            return i
    return len(REGIONS)


def dat_names():
    """each game's full title, and its year where the list gives one"""
    out, years = {}, {}
    for i in (0, 1):
        path = os.path.join(CACHE, "names%d.dat" % i)
        if os.path.exists(path):
            for ev, el in ET.iterparse(path, events=("end",)):
                if el.tag in ("game", "machine"):
                    n, d = el.get("name"), el.findtext("description")
                    if n and d:
                        out[n] = d
                        y = (el.findtext("year") or "")[:4]
                        if y.isdigit():
                            years[n] = int(y)
                    el.clear()
    # the cabinet's own names for the games not in FinalBurn Neo's list
    for f in [os.path.join(ROOT, "names.txt")] + [os.path.join(ROOT, d, "names.txt") for d in os.listdir(ROOT)]:
        if os.path.exists(f):
            for line in open(f, encoding="utf-8", errors="replace"):
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2 and parts[0] not in out:
                    out[parts[0]] = parts[1]
    return out, years


def main():
    go = "--go" in sys.argv
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
    dat, years = dat_names()
    boxes = {}                                    # title key -> [(system rank, region, system, name)]
    for rank, system in enumerate(SYSTEMS):
        for n in listing(system):
            boxes.setdefault(key(n), []).append((rank, region(n), system, n))
    titles = {}
    for n in listing("FBNeo - Arcade Games", "Named_Titles"):
        titles.setdefault(key(n), n)
    games = []
    for dirpath, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in ("media", "boxart", "samples", "flyers", "titles")]
        for f in files:
            if f.lower().endswith(".zip") and (only is None or f[:-4] in only):
                games.append((dirpath, f[:-4]))
    n_box = n_title = n_none = 0
    sample = []
    for dirpath, stem in sorted(games):
        desc = dat.get(stem, stem)
        k = key(desc)
        # also the title without a subtitle after ":" or " - " ("Tetris - The Absolute ...")
        k2 = key(re.split(r":| - ", re.sub(r"\([^)]*\)", "", desc))[0])
        # a box only on the exact title: without its subtitle, "Mega Man - The Power Battle"
        # would take the NES Mega Man's box. The title screens are the arcade game's own.
        hit = None if stem in DIFFERENT else boxes.get(k)
        neogeo = os.path.basename(dirpath) == "neogeo"
        if hit:
            hit = [h for h in hit if neogeo or h[2] != "SNK - Neo Geo CD"] or None
        if stem in CHOSEN:
            hit = [(0, 0, CHOSEN[stem][0], CHOSEN[stem][1])]
        url = None
        if hit:
            year = years.get(stem, 1990)
            # a normal release, then the machine nearest the arcade year, then the region
            rank, reg, system, name = sorted(hit, key=lambda h: (bool(ODD.search(h[3])),
                                             abs(YEAR[h[2]] - year) // 4, h[1], h[0]))[0]
            if re.search(r"proto|beta|sample", name, re.I):
                hit = None                   # never sold, so never had a box: the title screen
        if hit:
            url = BASE + urllib.parse.quote(system) + "/Named_Boxarts/" + urllib.parse.quote(name) + ".png"
            what = "box   %s: %s" % (system.split(" - ")[-1], name)
            n_box += 1
        else:
            t = titles.get(k) or titles.get(k2)
            if t:
                url = BASE + "FBNeo%20-%20Arcade%20Games/Named_Titles/" + urllib.parse.quote(t) + ".png"
                what = "title %s" % t
                n_title += 1
            else:
                what = "nothing found, kept"
                n_none += 1
        line = "  %-10s %-40s -> %s" % (stem, desc[:40], what)
        if not go:
            if hit and len(sample) < 400:
                sample.append(line)
            continue
        if not url:
            continue
        try:
            data = fetch(url)
        except Exception as ex:
            print("  %-10s failed: %s" % (stem, ex), flush=True)
            continue
        if len(data) < 2000:
            continue
        media = os.path.join(dirpath, "media")
        os.makedirs(os.path.join(media, "flyers"), exist_ok=True)
        art = os.path.join(media, stem + ".png")
        keep = os.path.join(media, "flyers", stem + ".png")
        if os.path.exists(art) and not os.path.exists(keep):
            os.replace(art, keep)
        open(art, "wb").write(data)
        print(line, flush=True)
    if not go:
        print("\n".join(sample))
    print("%d games: %d get a home-release box, %d get the arcade title screen, %d nothing found"
          % (len(games), n_box, n_title, n_none))


main()
