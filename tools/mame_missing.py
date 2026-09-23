#!/usr/bin/env python3
"""For a game none of the emulators flips: the nearest set each MAME knows, and what his
zip is missing for it. So he knows exactly which files to look for.

    python3 mame_missing.py missile tapper ...        (SRC=m2010 for MAME 2010)
"""
import glob, os, re, sys, zipfile
import mame_match as mm

which = os.environ.get("SRC", "m2k3")
mm.SRC = (glob.glob(os.path.expanduser("~/.cache/%s/*/src/mame/drivers" % which))
          + glob.glob(os.path.expanduser("~/.cache/%s/*/src/drivers" % which)))[0]
LOAD2 = re.compile(r'ROM\w*\(\s*"([^"]+)"\s*,[^,]*,\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*CRC\(\s*([0-9a-fA-F]{8})\s*\)')

def sets_named():
    out, parent = {}, {}
    for path in glob.glob(mm.SRC + "/*.c"):
        text = re.sub(r"/\*.*?\*/", " ", open(path, encoding="latin-1").read(), flags=re.S)
        for m in mm.BLOCK.finditer(text):
            body = "\n".join(l for l in m.group(2).splitlines() if "NO_DUMP" not in l)
            out[m.group(1)] = [(n, c.lower(), int(sz, 0)) for n, sz, c in LOAD2.findall(body)]
        for m in mm.GAME.finditer(text):
            if m.group(2) != "0": parent[m.group(1)] = m.group(2)
    return out, parent

sets, parent = sets_named()
for stem in sys.argv[1:]:
    have = mm.zip_chips(mm.find(stem))
    havecrc = {c for c, _ in have}
    best = []
    for name, need in sets.items():
        if not need: continue
        fam = name == stem or parent.get(name) == stem or parent.get(stem) == name or name.startswith(stem[:4])
        if not fam: continue
        got = [n for n, c, s in need if (c, s) in have]
        miss = [n for n, c, s in need if (c, s) not in have]
        best.append((len(got) / len(need), name, got, miss))
    best.sort(reverse=True)
    if not best:
        print("%-9s no set with that name in this MAME" % stem); continue
    share, name, got, miss = best[0]
    print("%-9s nearest '%s': has %d of %d files, missing: %s" % (stem, name, len(got), len(got) + len(miss), " ".join(miss) or "nothing"))
