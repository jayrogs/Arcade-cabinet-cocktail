#!/usr/bin/env python3
"""Play-tests a table game: puts two coins in, starts a TWO player game, then lets both
players lose their lives with nobody touching anything, while filming it all.

The presses go to the game over the emulator's own network gamepad, so no real or
made-up panel is involved and nothing else on the cabinet can see them. It runs on the
invisible second screen.

    python3 fliptest.py galaga [port]      films /home/jayrogs/flip_raw/galaga.mkv
"""
import os, socket, struct, subprocess, sys, time

HOME = os.path.expanduser("~")
CORE = HOME + "/.config/retroarch/cores/fbneo_libretro.so"
OUT = HOME + "/flip_raw"
FRAMES = 5400                   # about ninety seconds of the game
ENV = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1")
JOYPAD, B, SELECT, START = 1, 0, 2, 3

def find(stem):
    for dirpath, _, files in os.walk(HOME + "/roms/arcade"):
        if os.path.basename(dirpath) in ("media", "boxart", "samples"):
            continue
        if stem + ".zip" in files:
            return os.path.join(dirpath, stem + ".zip")

def main(stem, base, core=CORE, name=None):
    os.makedirs(OUT, exist_ok=True)
    cfg = "%s/net_%d.cfg" % (OUT, base)
    open(cfg, "w").write(
        'audio_driver = "alsa"\naudio_device = "null"\naudio_sync = "false"\n'
        'video_shader_enable = "false"\nvideo_font_enable = "false"\n'
        'video_vsync = "false"\nvideo_fullscreen = "false"\n'
        'network_remote_enable = "true"\nnetwork_remote_base_port = "%d"\n'
        'network_remote_enable_user_p1 = "true"\nnetwork_remote_enable_user_p2 = "true"\n'
        % base)
    rec = HOME + "/demos_raw/fast.cfg"
    name = name or stem
    part = "%s/.%s.mkv" % (OUT, name)
    done = "%s/%s.mkv" % (OUT, name)
    for f in (part, done):
        if os.path.exists(f):
            os.remove(f)
    game = subprocess.Popen(["retroarch", "-L", core, find(stem), "--appendconfig=" + cfg,
                             "--recordconfig=" + rec, "-r", part, "--max-frames=%d" % FRAMES],
                            env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    def press(user, button, hold=0.25):
        for state in (1, 0):
            # port, device, index, id, state -- the emulator's own layout, padded to 20
            s.sendto(struct.pack("<iiiiHxx", user, JOYPAD, 0, button, state),
                     ("127.0.0.1", base + user))
            if state:
                time.sleep(hold)

    # The game's own start-up test lasts a different time in every game, and the game
    # runs faster than real time here, so there is no right moment to press. Instead a
    # coin goes in and player 2's start is pressed every second, all the way through:
    # a two player game starts the moment the game will take one, and again after each
    # game over. Nobody plays, so both players lose their lives, turn about.
    # a game that freezes would keep this waiting for ever, so it gets five minutes
    deadline = time.time() + 300
    sim = os.environ.get("SIM") == "1"   # both at once: player 1 starts, player 2 joins
    while game.poll() is None:
        if sim:
            press(0, SELECT, 0.15); time.sleep(0.25)
            press(0, START, 0.15); time.sleep(0.4)
        if time.time() > deadline:
            game.kill()
            game.wait()
            if os.path.exists(part):
                os.remove(part)
            raise RuntimeError("froze")
        press(0, SELECT, 0.15)
        time.sleep(0.25)
        press(1, START, 0.15)
        time.sleep(0.6)
    if os.path.exists(part):
        os.replace(part, done)
        print("filmed", done, os.path.getsize(done) // 1024, "KB")
    else:
        print("NOTHING FILMED for", stem)

def everything():
    """Every table game on the list, one after another, skipping ones already filmed."""
    names = [g.strip() for g in open(HOME + "/roms/arcade/cocktail2p.txt") if g.strip()]
    # the well-known ones first, so a short night still covers the games that get played
    try:
        first = [g.strip() for g in open(OUT + "/priority.txt") if g.strip()]
        names = [g for g in first if g in names] + [g for g in names if g not in first]
    except OSError:
        pass
    same = {"mspacmnf", "pacmanf", "jrpacmnf"}      # identical to their originals
    log = open(OUT + "/log.txt", "a")
    for g in names:
        if g in same or os.path.exists("%s/%s.failed" % (OUT, g)) or (os.path.exists("%s/%s.mkv" % (OUT, g))
                         and os.path.getsize("%s/%s.mkv" % (OUT, g)) > 100000):
            continue
        t0 = time.time()
        why = ""
        try:
            main(g, 55400)
            ok = os.path.exists("%s/%s.mkv" % (OUT, g))
        except Exception as ex:
            ok, why = False, str(ex)
        if not ok:
            open(OUT + "/" + g + ".failed", "w").write(why or "no film")
        log.write(time.strftime("%H:%M:%S ") + ("filmed   " if ok else "FAILED   ") +
                  "%-12s %4.0f s" % (g, time.time() - t0) + chr(10))
        log.flush()
    log.write(time.strftime("%H:%M:%S ") + "FINISHED" + chr(10))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--all":
        everything()
    else:
        core = CORE
        tail = ""
        if len(sys.argv) > 3 and sys.argv[3] == "mame":
            core, tail = HOME + "/.config/retroarch/cores/mame2003_plus_libretro.so", "_mame"
        if len(sys.argv) > 3 and sys.argv[3] == "mame2010":
            core, tail = HOME + "/.config/retroarch/cores/mame2010_libretro.so", "_m2010"
        main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 55400, core,
             sys.argv[1] + tail)
