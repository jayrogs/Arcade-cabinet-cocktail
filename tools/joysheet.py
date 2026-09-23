#!/usr/bin/env python3
"""Before and after each of player 2's stick pushes, from the player 1 seat.

    python joysheet.py jackal [mame]      -> ../seats/<game>_joy.png
"""
import json, os, sys
from PIL import Image, ImageChops, ImageDraw, ImageFont
import cab
from seatsheet import OUT, TURN, fit, grab, length

game = sys.argv[1]
rnd = int(sys.argv[2]) if len(sys.argv) > 2 else 0
c = cab.connect()
s = c.open_sftp()
os.makedirs(os.path.join(OUT, "films"), exist_ok=True)
film = os.path.join(OUT, "films", game + "_joy.mkv")
if rnd == 0 or not os.path.exists(film): s.get("/home/jayrogs/flip_raw/joy/%s.mkv" % game, film)
info = json.loads(s.open("/home/jayrogs/flip_raw/joy/%s.json" % game).read())
orient = json.loads(cab.run(c, "cat ~/roms/arcade/orient.json", 30))
names = dict(l.split("\t", 1) for l in cab.run(c, "cat ~/roms/arcade/names.txt", 30).splitlines() if "\t" in l)
c.close()
turn = TURN[orient.get(game, 0)]
scale = length(film) / info["wall"]               # film seconds per real second
rnd = int(sys.argv[2]) if len(sys.argv) > 2 else 0
holds = [h for h in info["holds"] if h[3] == rnd]
try:
    big = ImageFont.truetype("arialbd.ttf", 22); lab = ImageFont.truetype("arialbd.ttf", 16)
except OSError:
    big = lab = ImageFont.load_default()
SW, SH, N = 216, 288, 4                          # four frames through each push
pad = 12
W = pad + N * (SW + pad)
H = 46 + len(holds) * (SH + 38)
im = Image.new("RGB", (W, H), (28, 28, 34))
dr = ImageDraw.Draw(im)
dr.text((pad, 10), names.get(game, game).strip() + "  -  each stick, seen from the player 1 seat",
        fill=(255, 220, 90), font=big)
for r, (name, a, b, _) in enumerate(holds):
    y = 46 + r * (SH + 38)
    dr.text((pad, y + 6), "%s HOLDS %s  (start of the push -> 1 s later)" % tuple(name.replace("P", "PLAYER ").split(" ", 1) if False else ("PLAYER " + name[1], name[3:])),
            fill=(200, 230, 255), font=lab)
    for k in range(N):
        t = (a + (b - a) * k / (N - 1)) * scale
        fr = fit(grab(film, turn, t)).resize((SW, SH), Image.NEAREST)
        im.paste(fr, (pad + k * (SW + pad), y + 30))
im.save(os.path.join(OUT, "%s_joy%d.png" % (game, rnd)))
print("drew", game, "scale %.2f" % scale)
