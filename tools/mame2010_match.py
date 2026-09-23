#!/usr/bin/env python3
"""Which MAME 2010 game is this zip, really? By chip fingerprints, not by name.

His arcade set was made for FinalBurn Neo, and MAME sometimes files the same board
under a different name -- his Missile Command has revision 3 of one chip, which MAME
calls "missile2", not "missile". So each zip's chips are fingerprinted and matched
against every game MAME knows, including the chips MAME borrows from a parent game.

    python3 mame_match.py missile tron ...     prints the MAME name each zip matches
"""
import glob, json, os, re, sys, zipfile

SRC = glob.glob(os.path.expanduser("~/.cache/m2010/*/src/mame/drivers"))[0]
ROOT = os.path.expanduser("~/roms/arcade")
BLOCK = re.compile(r"ROM_START\(\s*(\w+)\s*\)(.*?)ROM_END", re.S)
LOAD = re.compile(r'ROM_\w*\(\s*"([^"]+)"\s*,[^,]*,\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*CRC\(\s*([0-9a-fA-F]{8})\s*\)')
GAME = re.compile(r"^\s*GAME\w*\s*\(\s*[\d?]+\s*,\s*(\w+)\s*,\s*(\w+)\s*,", re.M)


def load_mame():
    sets, parent = {}, {}
    for path in glob.glob(SRC + "/*.c"):
        text = open(path, encoding="latin-1").read()
        text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
        for m in BLOCK.finditer(text):
            body = m.group(2)
            if "NO_DUMP" in body:
                body = "\n".join(l for l in body.splitlines() if "NO_DUMP" not in l)
            sets[m.group(1)] = {(c.lower(), int(sz, 0)) for _, sz, c in LOAD.findall(body)}
        for m in GAME.finditer(text):
            if m.group(2) != "0":
                parent[m.group(1)] = m.group(2)
    return sets, parent


def zip_chips(path):
    with zipfile.ZipFile(path) as z:
        return {("%08x" % i.CRC, i.file_size) for i in z.infolist()}


def find(stem):
    for dirpath, _, files in os.walk(ROOT):
        if os.path.basename(dirpath) in ("media", "boxart", "samples", "mamesets"):
            continue
        if stem + ".zip" in files:
            return os.path.join(dirpath, stem + ".zip")


def match(stem, sets, parent):
    have = zip_chips(find(stem))
    # a game borrows the chips it shares with its parent, so the parent's zip counts too
    best = []
    for name, need in sets.items():
        if not need:
            continue
        if need <= have:
            best.append((name == stem, len(need), name))
    best.sort(reverse=True)
    return [b[2] for b in best[:3]]


if __name__ == "__main__":
    sets, parent = load_mame()
    out = {}
    for stem in sys.argv[1:]:
        try:
            out[stem] = {"matches": match(stem, sets, parent), "parent_of_match": None}
            if out[stem]["matches"]:
                out[stem]["parent_of_match"] = parent.get(out[stem]["matches"][0])
        except Exception as ex:
            out[stem] = {"error": str(ex)[:80]}
    print(json.dumps(out, indent=1))
