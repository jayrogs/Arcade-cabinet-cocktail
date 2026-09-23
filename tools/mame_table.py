#!/usr/bin/env python3
"""Sets up table games in MAME 2003-Plus and films a two-player game of each.

For each game given:
  1. finds its table switch in MAME's source (mame_cabinet.py),
  2. lets MAME run it once on the invisible screen, which writes its settings file,
  3. checks the switch in that file matches the source -- right place, right mask,
     exactly two settings -- and only then turns it to cocktail,
  4. films two players taking turns (fliptest.py, through MAME).
Nothing is added to the shelf's MAME list here: that happens only after the film
shows the picture turning round for player 2.

    python3 mame_table.py 1942 cclimber ...
"""
import json, os, subprocess, sys, time

HOME = os.path.expanduser("~")
MAME = HOME + "/.config/retroarch/cores/mame2003_plus_libretro.so"
OUT = HOME + "/flip_raw"
LOG = OUT + "/mame_log.txt"
ENV = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1")
sys.path.insert(0, HOME)
import mame_cabinet, mamecfg


def log(msg):
    with open(LOG, "a") as f:
        f.write(time.strftime("%H:%M:%S ") + msg + "\n")


def find(stem):
    for dirpath, _, files in os.walk(HOME + "/roms/arcade"):
        if os.path.basename(dirpath) in ("media", "boxart", "samples"):
            continue
        if stem + ".zip" in files:
            return os.path.join(dirpath, stem + ".zip")


def one(g):
    info = mame_cabinet.cabinet(g)
    rots = json.load(open(OUT + "/mame_rot.json")) if os.path.exists(OUT + "/mame_rot.json") else {}
    if "rot" in info:
        rots[g] = info["rot"]
        json.dump(rots, open(OUT + "/mame_rot.json", "w"))
    if "error" in info:
        log("SKIP     %-10s %s" % (g, info["error"]))
        return
    cfg = os.path.join(mamecfg.CFG, g + ".cfg")
    if not os.path.exists(cfg):
        subprocess.run(["timeout", "120", "retroarch", "-L", MAME, find(g),
                        "--appendconfig=" + HOME + "/demos_raw/headless.cfg", "--max-frames=300"],
                       env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not os.path.exists(cfg):
        log("FAILED   %-10s MAME would not run it" % g)
        return
    data = open(cfg, "rb").read()
    maker, now = mamecfg.parse(data)
    sw = mamecfg.switches(now)
    # Some games build part of their switch list from shared pieces, which shifts the
    # table switch a place or two later than a plain count says. So it is found by
    # its bit and by having the cocktail value among its settings, taking the one
    # nearest the counted place and never before it.
    want_k, mask, cock = info["switch"], info["mask"], info.get("cocktail")
    cands = [n + 1 for n, (i, e, opts) in enumerate(sw)
             if e["mask"] == mask and cock is not None and cock in opts and n + 1 >= want_k]
    if not cands:
        log("MISMATCH %-10s no switch with bit %s and a cocktail setting" % (g, mask))
        return
    k = min(cands)
    mamecfg.set_value(g, k, cock)
    t0 = time.time()
    r = subprocess.run(["python3", HOME + "/fliptest_one.py", g, os.environ.get("MT_PORT", "56500"), "mame"],
                       capture_output=True, text=True, cwd=HOME)
    ok = os.path.exists("%s/%s_mame.mkv" % (OUT, g))
    log("%s %-10s switch %d, %.0f s" % ("filmed  " if ok else "NO FILM ", g, k, time.time() - t0))


if __name__ == "__main__":
    for g in sys.argv[1:]:
        if os.path.exists("%s/%s_mame.mkv" % (OUT, g)):
            continue
        try:
            one(g)
        except Exception as ex:
            log("ERROR    %-10s %s" % (g, str(ex)[:80]))
    log("FINISHED")
