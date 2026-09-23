#!/usr/bin/env python3
"""Turns cabinet buttons into the keys the Crossy Road arcade software expects.

That game only listens to a keyboard: C is player 1's coin, V is player 2's coin, the
space bar is player 1's jump and the up arrow is player 2's jump, and O opens its test
menu. The cabinet's panels and the phone page are joysticks, so this listens to them and
presses the right keys straight into the game's window.

    python3 crossy_keys.py            (runs until stopped)
"""
import os, select, subprocess, sys, threading, time
from evdev import InputDevice, ecodes as e, list_devices

ENV = dict(os.environ, DISPLAY=":0", XDG_RUNTIME_DIR="/run/user/1000")
COIN_HOLD = 0.35         # a shorter coin press is not counted: 0.1 s was ignored, 0.35 s worked

WEB1, WEB2 = "Cab Web Panel", "Cab Web Panel 2"


def players():
    """Which device belongs to which player: the phone pads by name, then the real
    panels in the order the Pi lists them."""
    out, real = [], []          # (device, player) pairs: a device cannot be a key
    for path in sorted(list_devices()):
        try:
            dev = InputDevice(path)
        except OSError:
            continue
        caps = dev.capabilities()
        if e.EV_KEY not in caps:
            dev.close(); continue
        if dev.name == WEB1:
            out.append((dev, 1))
        elif dev.name == WEB2:
            out.append((dev, 2))
        elif e.EV_ABS in caps or e.BTN_TRIGGER in caps.get(e.EV_KEY, []):
            real.append(dev)
        else:
            dev.close()
    for i, dev in enumerate(real[:2]):
        out.append((dev, i + 1))
    return out


def main():
    # Keys go in through xdotool, into the game's own X window. wtype (a Wayland typing
    # tool) was tried first and the game closed the moment it typed anything.
    def key(action, name):
        subprocess.run(["xdotool", action, name], env=ENV,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def coin_in(name):
        key("keydown", name); time.sleep(COIN_HOLD); key("keyup", name)

    pairs = players()
    byfd = {d.fd: (d, p) for d, p in pairs}
    print("listening to:", ", ".join("%s -> P%d" % (d.name, p) for d, p in pairs), flush=True)
    coin = {1: "c", 2: "v"}
    jump = {1: "space", 2: "Up"}
    stick_down = {}
    while True:
        r, _, _ = select.select(list(byfd), [], [], 1.0)
        for fd in r:
            dev, p = byfd[fd]
            try:
                for ev in dev.read():
                    if ev.type == e.EV_KEY and ev.value in (0, 1):
                        # the coin button puts a credit in; every other button jumps, held
                        # for as long as the button is
                        if ev.code in (e.BTN_BASE2, e.BTN_SELECT, e.BTN_BASE3):
                            if ev.value == 1:
                                threading.Thread(target=coin_in, args=(coin[p],), daemon=True).start()
                        else:
                            key("keydown" if ev.value == 1 else "keyup", jump[p])
                    elif ev.type == e.EV_ABS and ev.code == e.ABS_Y:
                        # pushing the stick away from you also jumps, once per push
                        away = ev.value < -16000 if p == 1 else ev.value > 16000
                        if away != stick_down.get(p, False):
                            stick_down[p] = away
                            key("keydown" if away else "keyup", jump[p])
            except OSError:
                pass


if __name__ == "__main__":
    main()
