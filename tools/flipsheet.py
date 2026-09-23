#!/usr/bin/env python3
"""A contact sheet of a play-test film: one frame every few seconds, stood upright."""
import io, json, subprocess, sys
from PIL import Image, ImageDraw
import cab

stem, out = sys.argv[1], sys.argv[2]
every = float(sys.argv[3]) if len(sys.argv) > 3 else 5
folder = sys.argv[4] if len(sys.argv) > 4 else "flip_raw"
c = cab.connect()
orient = json.loads(cab.run(c, "cat ~/roms/arcade/orient.json", 30))
if stem.endswith("_m2010"):
    rot = cab.run(c, "grep -h -o -E 'GAME\w* *\( *[0-9?]+, *%s *,[^)]*ROT[0-9]+' ~/.cache/m2010/*.c | grep -o 'ROT[0-9]*' | head -1" % stem[:-6], 30).strip()
    turn = {"ROT90": "transpose=1", "ROT270": "transpose=2", "ROT180": "hflip,vflip"}.get(rot, "null")
elif stem.endswith("_mame"):
    # MAME stores some tall games turned the other way from FinalBurn Neo, so its
    # films are stood up by MAME's own record of each game
    rots = json.loads(cab.run(c, "cat ~/flip_raw/mame_rot.json 2>/dev/null || echo {}", 30) or "{}")
    rots.update({g: "ROT90" for g in ("pacman", "pacmanf", "mspacman", "mspacmnf", "jrpacman", "jrpacmnf")})
    rots.update({g: "ROT270" for g in ("dkong", "dkongjr", "dkong3")})
    turn = {"ROT90": "transpose=1", "ROT270": "transpose=2", "ROT180": "hflip,vflip"}.get(
        rots.get(stem[:-5], "ROT0"), "null")
else:
    turn = {0: "null", 1: "transpose=2", 3: "transpose=1", 2: "hflip,vflip"}[orient.get(stem, 0)]
cab.run(c, "rm -rf /tmp/fs && mkdir /tmp/fs && ffmpeg -hide_banner -loglevel error -i ~/%s/%s.mkv "
           "-vf 'fps=1/%s,%s' /tmp/fs/%%03d.png" % (folder, stem, every, turn), 300)
s = c.open_sftp()
names = sorted(s.listdir("/tmp/fs"))
frames = [Image.open(io.BytesIO(s.open("/tmp/fs/" + n).read())).convert("RGB") for n in names]
s.close(); c.close()
w, h = frames[0].size
sc = 150.0 / max(w, h)
tw, th = int(w * sc), int(h * sc)
cols = 8
rows = (len(frames) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (tw + 4), rows * (th + 16)), (40, 40, 40))
for k, f in enumerate(frames):
    x, y = (k % cols) * (tw + 4), (k // cols) * (th + 16)
    sheet.paste(f.resize((tw, th)), (x, y))
    ImageDraw.Draw(sheet).text((x + 2, y + th + 2), "%ds" % ((k + 1) * every), fill=(255, 255, 0))
sheet.save(out)
print(len(frames), "frames")
