#!/usr/bin/env python3
"""Turns player 2's half round only while player 2 is playing (the FACE TO FACE split games).

Started beside RetroArch by tablevs.sh. The game starts as it is drawn; the moment player 2
presses start, RetroArch is told (a network command) to use tablesplit_live.glsl, so player
2's half faces their seat. Once player 2 has done nothing for QUIET seconds (the match is
over, or they have gone), it goes back to plain.glsl. After player 2 has joined once, any
button or stick from them turns it round again straight away: between rounds the game can
sit on its game-over and continue screens long enough to go quiet, and the next round then
began unflipped until player 2 happened to press start. Before this, the split was on from the
start and the title and one-player screens looked cut in half.

Player 2 is the second half of the real panel and the phone page's second pad.
"""
import os, select, socket, sys, time
from evdev import InputDevice, ecodes as e, list_devices

QUIET = 45                      # seconds of nothing from player 2 before the flip goes off
PORT = 55355
SH = "/home/jayrogs/.config/retroarch/shaders/"
FLIP, PLAIN = SH + "tablesplit_live.glslp", SH + "plain.glslp"


def player2():
    real, out = [], []
    # in number order: event12 must come after event5, which plain sorting gets wrong
    for path in sorted(list_devices(), key=lambda p: int(''.join(c for c in p if c.isdigit()) or 0)):
        try:
            d = InputDevice(path)
        except OSError:
            continue
        if d.name.startswith("3H Dual Arcade"):
            real.append(d)
        elif d.name == "Cab Web Panel 2":
            out.append(d)
        else:
            d.close()
    if len(real) >= 2:
        out.append(real[1])
    return out


def tell(preset):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.sendto(("SET_SHADER " + preset).encode(), ("127.0.0.1", PORT))
    s.close()
    print("tableflip:", os.path.basename(preset), flush=True)


def main():
    devs = player2()
    if not devs:
        print("tableflip: no player 2 controls found", flush=True)
        return
    flipped, joined, last = False, False, 0.0
    while True:
        r, _, _ = select.select(devs, [], [], 1.0)
        now = time.time()
        for d in r:
            try:
                for ev in d.read():
                    moved = (ev.type == e.EV_KEY and ev.value == 1) or \
                            (ev.type == e.EV_ABS and ev.value != 0)
                    if moved:
                        last = now
                    start = ev.type == e.EV_KEY and ev.value == 1 and ev.code == e.BTN_BASE2
                    if not flipped and (start or (moved and joined)):
                        tell(FLIP)
                        flipped = joined = True
            except OSError:
                pass
        if flipped and now - last > QUIET:
            tell(PLAIN)
            flipped = False


if __name__ == "__main__":
    main()
