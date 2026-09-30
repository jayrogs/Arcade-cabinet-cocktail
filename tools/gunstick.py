#!/usr/bin/env python3
"""The stick aims the gun in NAOMI gun games (The House of the Dead 2).

Started beside the game by hotd2.sh. Flycast can aim its gun with a stick, but only an
analog one: the crosshair sits wherever the stick is held, so the middle of the stick is the
middle of the screen. The table's sticks are on/off, and with those the crosshair can only
be in the middle or jammed against an edge.

So this makes a pretend controller, "Cab Gun Stick", whose analog stick is the crosshair's
place on the screen. Holding the real stick glides it that way, letting go leaves it where it
is. A tap nudges it slowly, for picking a head; held, it speeds up, for crossing the screen.
Player 1's buttons are passed straight through, so the pretend controller is a whole player 1
(hotd2.sh tells RetroArch to use it; its buttons are in autoconfig/udev/Cab Gun Stick.cfg).

Player 1's half of the panel and the phone page's first pad both drive it.
"""
import os, select, time
from evdev import InputDevice, UInput, ecodes as e, list_devices, AbsInfo

SLOW, FAST = 0.55, 2.4          # crosshair speed, in half-screens a second: at first, and held
RAMP = 0.5                      # seconds of holding to get from one to the other
TICK = 1 / 120.0
FULL = 32767
BUTTONS = [e.BTN_TRIGGER, e.BTN_THUMB, e.BTN_THUMB2, e.BTN_TOP, e.BTN_TOP2, e.BTN_PINKIE,
           e.BTN_BASE, e.BTN_BASE2, e.BTN_BASE3, e.BTN_BASE4]


def player1():
    panel, out = [], []
    # in number order: event12 must come after event5, which plain sorting gets wrong
    for path in sorted(list_devices(), key=lambda p: int(''.join(c for c in p if c.isdigit()) or 0)):
        try:
            d = InputDevice(path)
        except OSError:
            continue
        if d.name.startswith("3H Dual Arcade"):
            panel.append(d)
        elif d.name == "Cab Web Panel":
            out.append(d)
        else:
            d.close()
    # the panel is two controllers, player 1's first; the second is player 2's half
    return out + [d for i, d in enumerate(panel) if i != 1]


def main():
    devs = player1()
    if not devs:
        print("gunstick: no player 1 controls found", flush=True)
        return
    # where each stick's middle is, and how far it has to go to count as pushed
    span = {}
    for d in devs:
        for code, info in d.capabilities().get(e.EV_ABS, []):
            if code in (e.ABS_X, e.ABS_Y):
                mid = (info.min + info.max) / 2.0
                span[(d.path, code)] = (mid, max((info.max - info.min) / 4.0, 0.5))
    pad = UInput({e.EV_KEY: BUTTONS,
                  e.EV_ABS: [(e.ABS_X, AbsInfo(0, -FULL, FULL, 0, 0, 0)),
                             (e.ABS_Y, AbsInfo(0, -FULL, FULL, 0, 0, 0))]},
                 name="Cab Gun Stick", vendor=0x16c0, product=0x75e9)
    # RetroArch numbers controllers in the order they appeared; say which number this one is,
    # for hotd2.sh to hand to RetroArch as player 1
    time.sleep(0.4)
    mine = int(''.join(c for c in pad.device.path if c.isdigit()))
    others = []
    for block in open("/proc/bus/input/devices").read().split(chr(10) * 2):
        words = block.partition("Handlers=")[2].splitlines()[:1]
        words = words[0].split() if words else []
        if any(w.startswith("js") for w in words):
            others += [int(w[5:]) for w in words if w.startswith("event")]
    with open("/tmp/gunstick_pad.cfg", "w") as f:
        f.write('input_player1_joypad_index = "%d"' % sorted(others).index(mine) + chr(10))
    push = {}                   # (device, axis) -> -1, 0 or 1
    held, pos, sent = [0.0, 0.0], [0.0, 0.0], [0, 0]
    parent, checked, last = os.getppid(), time.time(), time.time()
    print("gunstick: aiming with %d sticks" % len(devs), flush=True)
    while devs:
        now = time.time()
        if now - checked > 2:
            checked = now
            # the launcher has gone: stop (a helper left behind once ate most of the Pi)
            if os.getppid() != parent:
                break
        r, _, _ = select.select(devs, [], [], TICK)
        for d in r:
            try:
                for ev in d.read():
                    key = (d.path, ev.code)
                    if ev.type == e.EV_ABS and key in span:
                        mid, far = span[key]
                        push[key] = (ev.value > mid + far) - (ev.value < mid - far)
                    elif ev.type == e.EV_KEY and ev.code in BUTTONS and ev.value in (0, 1):
                        pad.write(e.EV_KEY, ev.code, ev.value)
            except OSError:
                devs.remove(d)  # unplugged
        now = time.time()
        dt, last = min(now - last, 0.05), now
        for i, code in enumerate((e.ABS_X, e.ABS_Y)):
            way = sum(v for (path, c), v in push.items() if c == code)
            way = (way > 0) - (way < 0)
            if way == 0:
                held[i] = 0.0
            else:
                held[i] += dt
                speed = SLOW + (FAST - SLOW) * min(held[i] / RAMP, 1.0)
                pos[i] = max(-1.0, min(1.0, pos[i] + way * speed * dt))
            value = int(pos[i] * FULL)
            if value != sent[i]:
                sent[i] = value
                pad.write(e.EV_ABS, code, value)
        pad.syn()
    pad.close()


if __name__ == "__main__":
    main()
