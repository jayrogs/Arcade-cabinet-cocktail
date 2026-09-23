#!/usr/bin/env python3
"""What each seat at the table sees, for the both-at-once games.

The cabinet's screen is turned 90 degrees, so a game fills a tall picture that reads
upright from player 1's end. For three moments of two-player play this draws the
picture as seen from player 1's end, from player 2's end (turned half round), and from a
seat on the long side (turned a quarter), so it can be judged by eye.

    python seatsheet.py chinagat ddragon2 ...      writes ../seats/<game>.png
"""
import json, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont
import cab

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "seats")
SCREEN = (384, 512)                      # the tall screen, half size
TURN = {0: None, 1: "transpose=2", 3: "transpose=1", 2: "hflip,vflip"}


def fit(img):
    """The game as retroarch puts it on the tall screen: as big as fits, black around it."""
    w, h = img.size
    sc = min(SCREEN[0] / w, SCREEN[1] / h)
    g = img.resize((int(w * sc), int(h * sc)), Image.NEAREST)
    s = Image.new("RGB", SCREEN, (0, 0, 0))
    s.paste(g, ((SCREEN[0] - g.width) // 2, (SCREEN[1] - g.height) // 2))
    return s


def grab(path, turn, t):
    vf = ",".join(x for x in (turn, "format=rgb24") if x)
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", "%.2f" % t, "-i", path, "-frames:v", "1",
                          "-vf", vf, "-f", "image2pipe", "-vcodec", "png", "-"], capture_output=True).stdout
    import io
    return Image.open(io.BytesIO(raw)).convert("RGB")


def length(path):
    return float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                 "-of", "csv=p=0", path], capture_output=True, text=True).stdout)


def sheet(game, path, turn, title):
    """The real screen at three moments, as seen from player 1's seat."""
    d = length(path)
    moments = [d * f for f in (0.45, 0.65, 0.85)]
    pad = 16
    try:
        big = ImageFont.truetype("arialbd.ttf", 24)
    except OSError:
        big = ImageFont.load_default()
    W = pad + len(moments) * (SCREEN[0] + pad)
    H = 50 + SCREEN[1] + pad
    im = Image.new("RGB", (W, H), (28, 28, 34))
    ImageDraw.Draw(im).text((pad, 12), title, fill=(255, 220, 90), font=big)
    for c, t in enumerate(moments):
        im.paste(fit(grab(path, turn, t)), (pad + c * (SCREEN[0] + pad), 50))
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, game + ".png"))


if __name__ == "__main__":
    c = cab.connect()
    orient = json.loads(cab.run(c, "cat ~/roms/arcade/orient.json", 30))
    names = dict(l.split("\t", 1) for l in cab.run(c, "cat ~/roms/arcade/names.txt", 30).splitlines() if "\t" in l)
    s = c.open_sftp()
    os.makedirs(os.path.join(OUT, "films"), exist_ok=True)
    for arg in sys.argv[1:]:
        game, _, remote = arg.partition("=")            # game or game=path/on/pi.mkv
        remote = remote or "/home/jayrogs/flip_raw/sim/%s.mkv" % game
        local = os.path.join(OUT, "films", os.path.basename(remote))
        if not os.path.exists(local): s.get(remote, local)
        sheet(game, local, TURN[orient.get(game, 0)], names.get(game, game).strip())
        print("drew", game)
    c.close()
