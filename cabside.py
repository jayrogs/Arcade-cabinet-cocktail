#!/usr/bin/env python3
"""The side button, while a game is playing.

    tap it            the same game starts over
    hold it           the shelf comes back

Nothing else touches it: while the shelf is showing, this stays out of the way, because
the shelf uses that button itself.

It listens to the panel directly rather than asking the emulator, so it works in every
game without any per-game setting, and it keeps listening for the panel to be plugged
back in.
"""
import os, select, subprocess, sys, time

try:
    import evdev
    from evdev import ecodes as e
except Exception as ex:
    print("no way to read the panel:", ex, flush=True)
    raise SystemExit(1)

SIDE = e.BTN_BASE4          # the tenth button on the panel, which is the side one
HOLD = 0.7                  # held this long counts as a hold, not a tap
AGAIN = "/tmp/cab_again"    # the note the launcher looks for: play that game again
RESCAN = 3.0                # how often to look for a panel being plugged in


SHELF = "cabmenu.love"

def _on_top():
    """Whatever the launcher has put over the shelf: a game, the button setup, anything.

    The shelf itself is the one thing that does not count, because the shelf uses this
    button for its own purposes.
    """
    found = []
    try:
        out = subprocess.run(["pgrep", "-x", "retroarch"], capture_output=True, text=True)
        found += [int(x) for x in out.stdout.split() if x.strip().isdigit()]
        # Crossy Road runs under Wine and shows up as "Game.exe": stopping it ends the
        # launcher's run the same way closing the emulator does
        out = subprocess.run(["pgrep", "-f", r"^Game\.exe "], capture_output=True, text=True)
        found += [int(x) for x in out.stdout.split() if x.strip().isdigit()]
        out = subprocess.run(["pgrep", "-x", "love"], capture_output=True, text=True)
        for x in out.stdout.split():
            if not x.strip().isdigit():
                continue
            pid = int(x)
            try:
                with open("/proc/%d/cmdline" % pid, "rb") as f:
                    words = f.read().decode(errors="replace")
            except Exception:
                continue
            if SHELF not in words:
                found.append(pid)
    except Exception:
        pass
    return found

def playing():
    return bool(_on_top())


def stop_game():
    for pid in _on_top():
        try:
            os.kill(pid, 15)
        except Exception:
            pass


def again():
    """Leave the note, then stop the game: the launcher starts the same one again."""
    try:
        open(AGAIN, "w").close()
    except Exception:
        pass
    stop_game()
    print("tap: the same game again", flush=True)


def shelf():
    """No note, so the launcher goes back to the shelf."""
    try:
        os.remove(AGAIN)
    except Exception:
        pass
    stop_game()
    print("hold: back to the shelf", flush=True)


def panels():
    """Every device that actually has that side button on it."""
    found = []
    for path in evdev.list_devices():
        try:
            d = evdev.InputDevice(path)
            keys = d.capabilities().get(e.EV_KEY, [])
            if SIDE in keys:
                found.append(d)
            else:
                d.close()
        except Exception:
            pass
    return found


def main():
    devices = {}
    down_at = None
    fired = False
    last_scan = 0.0
    while True:
        now = time.time()
        if now - last_scan > RESCAN:
            last_scan = now
            fresh = panels()
            names = {d.path for d in fresh}
            for path in list(devices):
                if path not in names:
                    try:
                        devices.pop(path).close()
                    except Exception:
                        pass
            for d in fresh:
                if d.path in devices:
                    d.close()
                else:
                    devices[d.path] = d
                    print("watching", d.path, d.name, flush=True)

        if not devices:
            time.sleep(0.5)
            continue

        # a short wait, so a hold can be noticed while the button is still down
        ready, _, _ = select.select(list(devices.values()), [], [], 0.05)
        for d in ready:
            try:
                for ev in d.read():
                    if ev.type != e.EV_KEY or ev.code != SIDE:
                        continue
                    if ev.value == 1:               # pressed
                        down_at = time.time()
                        fired = False
                    elif ev.value == 0:             # let go
                        if down_at and not fired and playing():
                            again()
                        down_at = None
                        fired = False
            except OSError:
                try:
                    devices.pop(d.path).close()
                except Exception:
                    pass
                last_scan = 0.0

        if down_at and not fired and time.time() - down_at >= HOLD:
            fired = True
            if playing():
                shelf()


if __name__ == "__main__":
    main()
