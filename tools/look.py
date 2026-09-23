#!/usr/bin/env python3
"""Look at the cabinet screen, and optionally press something first.

Every press is followed by a picture, so nothing is ever pressed blind: that is how
the cabinet got switched off by accident once.

    python look.py out.png                   just look
    python look.py out.png right             press right, then look
    python look.py out.png press:1           press button 1, then look
"""
import io, sys, time
from PIL import Image
import cab

out = sys.argv[1]
action = sys.argv[2] if len(sys.argv) > 2 else None
c = cab.connect()
if action:
    if action.startswith("press:"):
        url = "http://127.0.0.1:8080/press?b=" + action.split(":", 1)[1]
    else:
        url = "http://127.0.0.1:8080/push?d=" + action
    cab.run(c, 'curl -s -m 5 "%s" >/dev/null; sleep 1.5' % url, 30)
i, o, e = c.exec_command("XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 grim -t ppm -")
Image.open(io.BytesIO(o.read())).convert("RGB").resize((300, 400)).save(out)
c.close()
print("saved", out)
