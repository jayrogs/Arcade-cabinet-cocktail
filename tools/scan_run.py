#!/usr/bin/env python3
"""Does every arcade game actually start? A quick look at each, on the invisible screen.

Each game runs for about two seconds and one picture is taken at the end. FinalBurn
Neo shows its own 640x480 notice when a game's files do not match this version of it
-- and it does not quit, so the shelf's fallback to MAME never happens and whoever
picked the game is left looking at the notice. Those games are then tried in
MAME 2003-Plus the same way.

    python3 scan_run.py            writes arcade/runs.json
"""
import glob, json, os, shutil, struct, subprocess, sys, time

HOME = os.path.expanduser("~")
ROOT = HOME + "/roms/arcade"
CORES = HOME + "/.config/retroarch/cores/"
ENV = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1")
OUT = ROOT + "/runs.json"
TMP = "/tmp/scan"


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def look(core, path, frames):
    shutil.rmtree(TMP, ignore_errors=True)
    os.makedirs(TMP)
    cfg = TMP + "/look.cfg"
    open(cfg, "w").write('audio_driver = "alsa"\naudio_device = "null"\nvideo_shader_enable = "false"\n'
                         'video_font_enable = "false"\nvideo_vsync = "false"\nvideo_fullscreen = "false"\n'
                         'screenshot_directory = "%s"\nsavestate_thumbnail_enable = "false"\n' % TMP)
    try:
        subprocess.run(["timeout", "90", "retroarch", "-L", CORES + core + "_libretro.so", path,
                        "--appendconfig=" + cfg, "--max-frames=%d" % frames, "--max-frames-ss"],
                       env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    shots = glob.glob(TMP + "/*.png")
    if not shots:
        return None
    # FinalBurn Neo's notice: a pale page under a blue title bar
    from PIL import Image
    im = Image.open(shots[0]).convert("RGB")
    small = im.resize((32, 24))
    px = list(small.getdata())
    pale = sum(1 for r, g, b in px if r > 200 and g > 200 and b > 200) / len(px)
    top = [small.getpixel((x, 0)) for x in range(32)]
    blue = sum(1 for r, g, b in top if b > 150 and r < 80) / 32
    # the bar is THIN: a few rows down it is already the pale page. A pale sky with
    # blue above it (After Burner II) fooled a looser test.
    below = [small.getpixel((x, 3)) for x in range(32)]
    page = sum(1 for r, g, b in below if r > 200 and g > 200 and b > 200) / 32
    shutil.copy(shots[0], "/tmp/scan_last_%s.png" % core)
    return "notice" if (pale > 0.8 and blue > 0.5 and page > 0.8) else "picture"


def main():
    results = json.load(open(OUT)) if os.path.exists(OUT) else {}
    games = []
    for dirpath, _, files in os.walk(ROOT):
        if os.path.basename(dirpath) in ("media", "boxart", "samples"):
            continue
        games += [(f[:-4], os.path.join(dirpath, f)) for f in files if f.endswith(".zip")]
    again = "--recheck" in sys.argv
    for stem, path in sorted(games):
        if stem in results and not (again and results[stem].get("fbneo") != "runs"):
            continue
        seen = look("fbneo", path, 150)
        if seen == "picture":
            results[stem] = {"fbneo": "runs"}
        else:
            r = {"fbneo": "files do not match" if seen == "notice" else "no picture"}
            m = look("mame2003_plus", path, 600)
            r["mame"] = "runs" if m == "picture" else ("no picture" if m is None else "notice")
            results[stem] = r
        json.dump(results, open(OUT, "w"), indent=0, sort_keys=True)
    bad = {k: v for k, v in results.items() if v.get("fbneo") != "runs"}
    print(len(results), "games looked at;", len(bad), "do not start in FinalBurn Neo")
    for k in sorted(bad):
        print("  %-12s %s" % (k, bad[k]))


if __name__ == "__main__":
    main()
