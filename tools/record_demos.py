#!/usr/bin/env python3
"""Films every arcade game's own demo, for the shelf's demo screen.

Each game is started with no coin in, which is when a real arcade machine plays its
demo to attract people, and about seventy seconds of it are filmed with sound. It all
happens on an invisible second screen, so the real one is never touched, and it runs
faster than real time.

It can be stopped and started again: games already filmed are skipped.

    python3 record_demos.py            films everything not yet filmed
"""
import sys, os, subprocess, sys, time, concurrent.futures as cf

HOME = os.path.expanduser("~")
ROOT = HOME + "/roms/arcade"
OUT = HOME + "/demos_raw"
CORE = HOME + "/.config/retroarch/cores/fbneo_libretro.so"
CORES = HOME + "/.config/retroarch/cores/"


def core_for(stem):
    """The emulator the shelf uses for this game: MAME for the ones on its MAME lists
    (a line is "game" or "game mamename", the second with a copy under that name)."""
    for listfile, core, folder in (("use_mamecur.txt", "mame", None),
                                   ("use_mame2010.txt", "mame2010", "mamesets2010"),
                                   ("use_mame.txt", "mame2003_plus", "mamesets")):
        try:
            for line in open(ROOT + "/" + listfile):
                parts = line.split()
                if parts and parts[0] == stem:
                    path = None
                    if len(parts) > 1 and folder:
                        path = ROOT + "/" + folder + "/" + parts[1] + ".zip"
                    return CORES + core + "_libretro.so", path
        except OSError:
            pass
    return CORE, None
CFG = OUT + "/headless.cfg"
# the cheapest squeeze there is: the films are cut down and squeezed again later
FAST = OUT + "/fast.cfg"
LOG = OUT + "/log.txt"
FRAMES = 3600           # about sixty seconds of the game
WORKERS = 1             # the Pi runs short of power under load, so gently
# the sped-up versions look exactly like the originals, so they share their films
SAME_AS = {"mspacmnf": "mspacman", "pacmanf": "pacman", "jrpacmnf": "jrpacman"}

HEADLESS = """audio_driver = "alsa"
audio_device = "null"
audio_enable = "true"
audio_sync = "false"
audio_mute_enable = "false"
video_shader_enable = "false"
video_font_enable = "false"
video_vsync = "false"
video_fullscreen = "false"
"""

FASTREC = """vcodec = libx264
acodec = aac
pix_fmt = yuv420p
format = matroska
threads = 1
video_preset = ultrafast
video_crf = 20
"""

ENV = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1")


def log(msg):
    with open(LOG, "a") as f:
        f.write(time.strftime("%H:%M:%S ") + msg + "\n")


def screen_up():
    """The invisible screen: a second copy of the desktop that shows nothing anywhere."""
    if os.path.exists("/run/user/1000/wayland-1"):
        return
    cfg = OUT + "/labwc"
    os.makedirs(cfg, exist_ok=True)
    open(cfg + "/autostart", "w").close()          # nothing starts on it by itself
    subprocess.Popen(["labwc", "-C", cfg], env=dict(
        ENV, WLR_BACKENDS="headless", WLR_LIBINPUT_NO_DEVICES="1", WLR_RENDERER="gles2"),
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    time.sleep(3)


def games():
    found = {}
    for dirpath, dirnames, files in os.walk(ROOT):
        if os.path.basename(dirpath) in ("media", "boxart", "samples", "mamesets", "mamesets2010"):
            continue
        for f in files:
            if f.lower().endswith(".zip"):
                stem = f[:-4]
                if stem not in SAME_AS:
                    found[stem] = os.path.join(dirpath, f)
    # the tall games and the table games first: they are the ones this cabinet is for,
    # so if the night runs out, the demo has the best of them
    first = set()
    for name in ("tall.txt", "cocktail2p.txt"):
        try:
            first |= {g.strip() for g in open(ROOT + "/" + name) if g.strip()}
        except OSError:
            pass
    try:                      # games taken off the shelf get no demo either
        for g in open(ROOT + "/hide.txt"):
            found.pop(g.strip(), None)
    except OSError:
        pass
    return sorted(found.items(), key=lambda kv: (kv[0] not in first, kv[0]))


def film(item, rec=None):
    stem, path = item
    done = "%s/%s.mkv" % (OUT, stem)
    if os.path.exists(done) and os.path.getsize(done) > 100000:
        return "had"
    part = "%s/.%s.mkv" % (OUT, stem)
    if os.path.exists(part):
        os.remove(part)
    t0 = time.time()
    try:
        core, other = core_for(stem)
        subprocess.run(["nice", "-n", "10", "retroarch", "-L", core, other or path,
                        "--appendconfig=" + CFG, "--recordconfig=" + (rec or FAST), "-r", part, "--max-frames=%d" % FRAMES],
                       env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       timeout=300)
    except subprocess.TimeoutExpired:
        log("TOO SLOW  %s" % stem)
    if os.path.exists(part) and os.path.getsize(part) > 100000:
        os.replace(part, done)
        log("filmed    %-12s %5.0f s  %6d KB" % (stem, time.time() - t0, os.path.getsize(done) // 1024))
        return "filmed"
    if os.path.exists(part):
        os.remove(part)
    # a picture with an odd height (Missile Command is 231 tall) is refused by the usual
    # recorder settings; the 4:4:4 settings take any size
    if not os.environ.get("RETRY"):
        alt = OUT + "/fast444.cfg"
        if os.path.exists(alt):
            os.environ["RETRY"] = "1"
            try:
                return film(item, rec=alt)
            finally:
                del os.environ["RETRY"]
    log("would not film %s" % stem)
    return "failed"


def main():
    os.makedirs(OUT, exist_ok=True)
    open(CFG, "w").write(HEADLESS)
    open(FAST, "w").write(FASTREC)
    screen_up()
    todo = games()
    log("starting: %d games" % len(todo))
    counts = {}
    if len(sys.argv) > 1:                # only the games named
        todo = [kv for kv in todo if kv[0] in sys.argv[1:]]
        for stem, _ in todo:
            for f in (OUT + "/" + stem + ".mkv",):
                if os.path.exists(f):
                    os.remove(f)
    with cf.ThreadPoolExecutor(WORKERS) as ex:
        for r in ex.map(film, todo):
            counts[r] = counts.get(r, 0) + 1
    log("FINISHED %s" % counts)


if __name__ == "__main__":
    main()
