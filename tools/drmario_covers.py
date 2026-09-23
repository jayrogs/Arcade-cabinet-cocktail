#!/usr/bin/env python3
"""Dr Mario covers for the shelf, built from the game's own sprites. Four looks; each is
saved as menuart/drmario_<letter>.png, and a sheet of all four goes to simcheck.

    python drmario_covers.py
"""
import os
from PIL import Image, ImageDraw

SPR = r"C:\Users\jayru\Desktop\CabMenu\games\DrCocktail\sprites"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "menuart")
W, H = 118, 150                      # the shelf's box, exactly: it draws a cover this size
                                     # pixel for pixel (then the whole screen is blown up 3x)

def keyed(s):
    """Near-black pixels become see-through: some sprites sit on a black ground."""
    px = s.load()
    for y in range(s.height):
        for x in range(s.width):
            r, g, b, a = px[x, y]
            if r < 8 and g < 8 and b < 8:
                px[x, y] = (0, 0, 0, 0)
    return s

def sprite(name, crop=None, scale=1):
    s = Image.open(os.path.join(SPR, name)).convert("RGBA")
    if name.startswith(("title_", "half_", "virus_")):     # the ones drawn on a black ground
        s = keyed(s)
    if crop:
        s = s.crop(crop)
    if scale != 1:
        s = s.resize((s.width * scale, s.height * scale), Image.NEAREST)
    return s

def doctor(pose=0, scale=1):
    return sprite("doctor.png", (pose * 40, 0, pose * 40 + 40, 40), scale)

def virus(colour, scale=1, frame=0):
    return sprite("title_virus.png", None, scale) if colour == "big" else \
           sprite("virus_%s.png" % colour, (frame * 8, 0, frame * 8 + 8, 8), scale)

def bigvirus(which, scale=1):
    # title_virus.png holds the two big viruses side by side (31 wide each)
    s = sprite("title_virus.png")
    half = s.width // 2
    return s.crop((which * half, 0, (which + 1) * half, s.height)).resize(
        (half * scale, s.height * scale), Image.NEAREST)

def pill(a, b, scale=1):
    # a horizontal pill from two halves; the half sprites hold six 8x8 frames
    l = sprite("half_%s.png" % a, (16, 0, 24, 8), scale)     # frame 2: the left end
    r = sprite("half_%s.png" % b, (24, 0, 32, 8), scale)     # frame 3: the right end
    p = Image.new("RGBA", (16 * scale, 8 * scale))
    p.alpha_composite(l, (0, 0)); p.alpha_composite(r, (8 * scale, 0))
    return p

def checker(img, c1, c2, cell=16):
    d = ImageDraw.Draw(img)
    for y in range(0, H, cell):
        for x in range(0, W, cell):
            d.rectangle((x, y, x + cell - 1, y + cell - 1), fill=c1 if (x // cell + y // cell) % 2 else c2)

def frame(img, colour, width=6):
    d = ImageDraw.Draw(img)
    for i in range(width):
        d.rectangle((i, i, W - 1 - i, H - 1 - i), outline=colour)

def centre(img, s, y):
    img.alpha_composite(s, ((W - s.width) // 2, y))

def cover_a():
    """The doctor, big, over a deep blue; logo on top, the three viruses at his feet."""
    img = Image.new("RGBA", (W, H), (16, 32, 96, 255))
    checker(img, (16, 32, 96), (20, 40, 112), 6)
    frame(img, (238, 70, 110), 2)
    centre(img, sprite("logo_half.png", None, 1), 4)           # the pill logo, 112 x 40
    centre(img, doctor(0, 2), 48)                              # 80 x 80
    for i, c in enumerate(("red", "yellow", "blue")):
        v = virus(c, 2)
        bx0, by0, bx1, by1 = v.getbbox()
        cx, cy = W // 4 * (i + 1), 138
        img.alpha_composite(v, (cx - (bx0 + bx1) // 2, cy - (by0 + by1) // 2))
    return img

def cover_b():
    """Bottle in the middle with pills and viruses inside, the doctor peering over it."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    checker(img, (0, 0, 0), (14, 14, 22), 16)
    frame(img, (60, 190, 230), 5)
    b = sprite("bottle_game.png", None, 1)          # 80 x 176
    bx, by = (W - b.width) // 2, 150
    img.alpha_composite(b, (bx, by))
    inside = [("red", "blue", 20, 60), ("yellow", "red", 36, 84), ("blue", "yellow", 12, 108),
              ("red", "red", 44, 132)]
    for a, c, x, y in inside:
        img.alpha_composite(pill(a, c, 2), (bx + x, by + y))
    for i, c in enumerate(("red", "yellow", "blue", "red", "blue")):
        img.alpha_composite(virus(c, 2), (bx + 12 + (i % 3) * 24, by + 40 + (i // 3) * 20))
    img.alpha_composite(doctor(2, 3), (W // 2 - 60 - 40, 20))
    centre(img, sprite("logo_small.png", None, 2), 8) if False else None
    img.alpha_composite(sprite("logo_half.png", None, 1), (W - 112 - 14, 24))
    return img

def cover_c():
    """Poster: the two big viruses on red, the doctor between them, logo across the bottom."""
    img = Image.new("RGBA", (W, H), (176, 24, 48, 255))
    checker(img, (176, 24, 48), (190, 34, 60), 16)
    frame(img, (255, 214, 90), 5)
    img.alpha_composite(bigvirus(0, 3), (12, 60))
    img.alpha_composite(bigvirus(1, 3), (W - 12 - 93, 60))
    centre(img, doctor(3, 4), 130)
    centre(img, sprite("logo.png", None, 1), H - 80 - 20)
    return img

def cover_d():
    """Clean: white ground, pill logo, the doctor, a row of pills as the strip."""
    img = Image.new("RGBA", (W, H), (240, 240, 236, 255))
    frame(img, (26, 87, 174), 6)
    centre(img, sprite("logo.png", None, 1), 22)
    centre(img, doctor(1, 4), 118)
    row = [("red", "blue"), ("yellow", "red"), ("blue", "yellow"), ("red", "yellow")]
    for i, (a, c) in enumerate(row):
        img.alpha_composite(pill(a, c, 3), (24 + i * 54, 300))
    return img

if __name__ == "__main__":
    covers = {"a": cover_a(), "b": cover_b(), "c": cover_c(), "d": cover_d()}
    os.makedirs(OUT, exist_ok=True)
    for k, im in covers.items():
        im.save(os.path.join(OUT, "drmario_%s.png" % k))
    covers = {"a": covers["a"]}
    sheet = Image.new("RGB", (4 * (W + 24) + 24, H + 48), (40, 40, 44))
    d = ImageDraw.Draw(sheet)
    for i, (k, im) in enumerate(covers.items()):
        sheet.paste(im, (24 + i * (W + 24), 36))
        d.text((24 + i * (W + 24), 12), "OPTION " + k.upper(), fill=(255, 255, 255))
    sheet.save(os.path.join(os.path.dirname(HERE), "simcheck", "drmario_options.png"))
    print("drawn")
