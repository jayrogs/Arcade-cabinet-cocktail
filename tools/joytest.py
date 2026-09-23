#!/usr/bin/env python3
"""Does player 2's stick work from player 2's side of the table?

Both players join, then player 1 is left alone while player 2's stick is held UP, DOWN,
LEFT and RIGHT in turn, a few seconds each. Player 2 sits at the far end, so for the game
to suit a face-to-face table, player 2 pushing UP (away from themselves) must send their
character DOWN the screen as player 1 sees it. The film and the times of each hold are
kept, so the moves can be checked frame by frame.

    python3 joytest.py <game> <port> [mame|mame2010]    -> ~/flip_raw/joy/<game>.mkv + .json
"""
import json, os, socket, struct, subprocess, sys, time
sys.path.insert(0, os.path.expanduser("~"))
import fliptest as ft

UP, DOWN, LEFT, RIGHT = 4, 5, 6, 7
OUT = ft.HOME + "/flip_raw/joy"


def run(stem, base, core):
    os.makedirs(OUT, exist_ok=True)
    cfg = "%s/net_%d.cfg" % (OUT, base)
    open(cfg, "w").write(
        'audio_driver = "alsa"\naudio_device = "null"\naudio_sync = "false"\n'
        'video_shader_enable = "false"\nvideo_font_enable = "false"\n'
        'video_vsync = "false"\nvideo_fullscreen = "false"\n'
        'network_remote_enable = "true"\nnetwork_remote_base_port = "%d"\n'
        'network_remote_enable_user_p1 = "true"\nnetwork_remote_enable_user_p2 = "true"\n' % base)
    part, done = "%s/.%s.mkv" % (OUT, stem), "%s/%s.mkv" % (OUT, stem)
    for f in (part, done):
        if os.path.exists(f):
            os.remove(f)
    frames = 30000                       # a safety net; the test ends the game itself
    t0 = time.time()
    game = subprocess.Popen(["retroarch", "-L", core, ft.find(stem), "--appendconfig=" + cfg,
                             "--recordconfig=" + ft.HOME + "/demos_raw/fast.cfg", "-r", part,
                             "--max-frames=%d" % frames], env=ft.ENV,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    def send(user, button, state):
        s.sendto(struct.pack("<iiiiHxx", user, ft.JOYPAD, 0, button, state), ("127.0.0.1", base + user))

    def press(user, button, hold=0.15):
        send(user, button, 1); time.sleep(hold); send(user, button, 0)

    def join(seconds):
        end = time.time() + seconds
        while time.time() < end and game.poll() is None:
            for u in (0, 1):
                press(u, ft.SELECT); time.sleep(0.2)
            press(0, ft.START); time.sleep(0.2)
            press(1, ft.START); time.sleep(0.4)

    # past the game's start-up, then three rounds of: both join, and straight away each
    # player's stick is pushed four ways (player 1 first, as the check on the test itself)
    join(40)
    holds = []
    for rnd in range(3):
        join(6)
        for user in (0, 1):
            for name, b in (("UP", UP), ("DOWN", DOWN), ("LEFT", LEFT), ("RIGHT", RIGHT)):
                if game.poll() is not None:
                    break
                a = time.time() - t0
                send(user, b, 1); time.sleep(1.0); send(user, b, 0)
                holds.append(("P%d %s" % (user + 1, name), a, time.time() - t0, rnd))
                time.sleep(0.4)
    game.terminate()                     # retroarch closes the film properly on this
    game.wait()
    wall = time.time() - t0
    if os.path.exists(part):
        os.replace(part, done)
    json.dump({"wall": wall, "frames": frames, "holds": holds}, open("%s/%s.json" % (OUT, stem), "w"))
    print(stem, "filmed" if os.path.exists(done) else "NOTHING", "%.0f s" % wall, len(holds), "holds")


if __name__ == "__main__":
    core = ft.CORE
    if len(sys.argv) > 3 and sys.argv[3] == "mame":
        core = ft.HOME + "/.config/retroarch/cores/mame2003_plus_libretro.so"
    if len(sys.argv) > 3 and sys.argv[3] == "mame2010":
        core = ft.HOME + "/.config/retroarch/cores/mame2010_libretro.so"
    run(sys.argv[1], int(sys.argv[2]), core)
