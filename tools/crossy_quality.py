"""Crossy Road's graphics settings, changed in its own data file (Game_Data/mainData).

The game has one quality level, "Good". Measured on the cabinet with the game's own frame
count (2026-09-23, demo mode, 45 s each):

    as shipped                                  15.7 frames a second
    vsync off                                   15.5   (kept anyway: it only ever waits)
    vsync off, edge smoothing (2x) off          24.8   <- what the cabinet runs
    ... and angled-texture sharpening off       25.0   (no gain, so it stays on)

Shadows are untouched. Only single bytes change, at offsets read from the file with UnityPy,
so nothing else in the file moves.

    python crossy_quality.py <mainData> <out>       writes the edited copy
"""
import sys

VSYNC, ANTIALIAS = 124484, 124476       # offsets inside this build's mainData

src, out = sys.argv[1], sys.argv[2]
b = bytearray(open(src, "rb").read())
assert b[VSYNC] in (0, 1) and b[ANTIALIAS] in (0, 2), "not the mainData these offsets were read from"
b[VSYNC] = 0
b[ANTIALIAS] = 0
open(out, "wb").write(b)
print("written", out)
