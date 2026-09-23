#!/usr/bin/env python3
"""Draws the box covers for the cabinet's own shelf.

The games get real box art from the picture archive. The shelf's own boxes -- Dr Mario,
two player, favourites, each machine, the setting-up ones -- had nothing but a coloured
rectangle, so they are drawn here instead: one small picture each, in the same chunky
style as everything else on the screen.

Everything is drawn on a tiny canvas and then blown up with no smoothing, so the pixels
stay square and hard-edged, which is the whole point.

    python tools/menuart.py            draws them into menuart/
"""
import os, sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "menuart")
DRSPRITES = r"C:\Users\jayru\Desktop\CabMenu\games\DrCocktail\sprites"

W, H = 64, 90               # the little canvas
BIG = 4                     # how much it is blown up
FONT = os.path.join(ROOT, "font.png")
GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,-:<>!?/'#@"


# ---------------------------------------------------------------- the lettering
def load_font():
    im = Image.open(FONT).convert("RGBA")
    sep = im.getpixel((0, 0))
    px = im.load()
    out, x, w = {}, 0, im.size[0]
    inside, start, n = False, 0, 0
    for i in range(w):
        is_sep = px[i, 0] == sep
        if not is_sep and not inside:
            inside, start = True, i
        elif is_sep and inside:
            inside = False
            if n < len(GLYPHS):
                out[GLYPHS[n]] = im.crop((start, 0, i, 8))
            n += 1
    return out

GLYPH = load_font()


def text(img, s, cx, y, colour):
    """Writes in the cabinet's own lettering, centred on cx."""
    s = s.upper()
    wide = sum(8 for ch in s if ch in GLYPH)
    x = int(cx - wide / 2)
    for ch in s:
        g = GLYPH.get(ch)
        if not g:
            x += 8
            continue
        tinted = Image.new("RGBA", g.size, colour + (255,))
        tinted.putalpha(g.split()[3])
        img.alpha_composite(tinted, (x, y))
        x += 8


# ---------------------------------------------------------------- helpers
def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


def box(d, xy, fill=None, outline=None):
    d.rectangle(xy, fill=fill, outline=outline)


# ---------------------------------------------------------------- the pictures
def icon_cabinet(d, c, bright):
    """An upright arcade machine, seen face on."""
    body, dark = shade(c, 0.85), shade(c, 0.45)
    box(d, (16, 22, 47, 70), fill=body, outline=shade(c, 1.4))
    box(d, (18, 24, 45, 31), fill=(250, 226, 96))          # the marquee, lit up
    box(d, (20, 26, 43, 29), fill=shade(c, 1.2))
    box(d, (19, 34, 44, 50), fill=(12, 12, 24), outline=(90, 90, 120))
    for i in range(3):                                      # something on the screen
        box(d, (23 + i * 7, 40 + (i % 2) * 4, 26 + i * 7, 43 + (i % 2) * 4),
            fill=(120, 240, 140) if i % 2 else (250, 120, 120))
    box(d, (18, 53, 45, 60), fill=dark)                     # the control panel
    box(d, (22, 55, 25, 58), fill=(240, 240, 250))          # the stick
    for i in range(3):
        box(d, (29 + i * 4, 55, 31 + i * 4, 57), fill=(250, 100, 110))
    box(d, (27, 63, 36, 67), fill=(70, 70, 90))             # the coin door
    box(d, (30, 64, 33, 66), fill=(250, 226, 96))
    box(d, (16, 70, 21, 74), fill=dark)
    box(d, (42, 70, 47, 74), fill=dark)


def icon_table(d, c, bright):
    """Two sticks facing each other across a table: the cocktail cabinet."""
    box(d, (12, 30, 51, 62), fill=shade(c, 0.6), outline=shade(c, 1.4))
    box(d, (16, 34, 47, 58), fill=(12, 12, 24), outline=(80, 80, 110))
    for i in range(4):
        box(d, (20 + i * 7, 40, 24 + i * 7, 46), fill=(240, 200, 90) if i % 2 else (120, 220, 250))
    # the near player
    box(d, (26, 64, 28, 70), fill=(200, 200, 215))
    d.ellipse((24, 68, 30, 74), fill=(240, 90, 90))
    for i in range(2):
        d.ellipse((33 + i * 7, 68, 38 + i * 7, 73), fill=(250, 210, 90))
    # the far player, upside down, the way they sit
    box(d, (35, 22, 37, 28), fill=(200, 200, 215))
    d.ellipse((33, 18, 39, 24), fill=(120, 160, 250))
    for i in range(2):
        d.ellipse((20 + i * 7, 19, 25 + i * 7, 24), fill=(140, 230, 160))


def icon_star(d, c, bright):
    pts = [(32, 20), (38, 38), (57, 38), (42, 49), (48, 68),
           (32, 56), (16, 68), (22, 49), (7, 38), (26, 38)]
    d.polygon(pts, fill=(250, 214, 80), outline=(255, 250, 200))
    d.polygon([(32, 28), (36, 40), (48, 40), (38, 47), (42, 59),
               (32, 52), (22, 59), (26, 47), (16, 40), (28, 40)], fill=(255, 238, 150))


def icon_clock(d, c, bright):
    d.ellipse((14, 26, 50, 62), fill=(30, 34, 44), outline=shade(c, 1.6), width=2)
    d.ellipse((19, 31, 45, 57), outline=shade(c, 1.2))
    box(d, (31, 34, 33, 45), fill=(250, 240, 200))          # the long hand
    box(d, (32, 43, 41, 45), fill=(250, 200, 120))          # the short one
    for a in (0, 1, 2, 3):
        x = 31 + [0, 15, 0, -15][a]
        y = 43 + [-15, 0, 15, 0][a]
        box(d, (x, y, x + 2, y + 2), fill=(230, 230, 240))


def _pad(d, x, y, w, h, c, radius=3):
    d.rounded_rectangle((x, y, x + w, y + h), radius=radius,
                        fill=shade(c, 0.9), outline=shade(c, 1.5))


def icon_nespad(d, c, bright):
    _pad(d, 10, 33, 44, 22, (150, 140, 135), radius=2)
    box(d, (15, 38, 27, 50), fill=(40, 40, 46))
    box(d, (19, 38, 23, 50), fill=(20, 20, 24))
    box(d, (15, 42, 27, 46), fill=(20, 20, 24))
    box(d, (31, 43, 37, 46), fill=(70, 70, 80))
    box(d, (31, 47, 37, 50), fill=(70, 70, 80))
    d.ellipse((41, 42, 46, 47), fill=(200, 40, 50))
    d.ellipse((47, 42, 52, 47), fill=(200, 40, 50))


def icon_snespad(d, c, bright):
    _pad(d, 8, 34, 48, 20, (170, 170, 180), radius=8)
    box(d, (14, 39, 24, 49), fill=(60, 60, 70))
    box(d, (17, 39, 21, 49), fill=(35, 35, 42))
    box(d, (14, 42, 24, 46), fill=(35, 35, 42))
    for (dx, dy, col) in ((44, 41, (120, 160, 240)), (48, 45, (240, 200, 90)),
                          (40, 45, (120, 220, 140)), (44, 49, (230, 110, 120))):
        d.ellipse((dx, dy, dx + 4, dy + 4), fill=col)


def icon_mdpad(d, c, bright):
    _pad(d, 9, 34, 46, 21, (60, 62, 72), radius=9)
    box(d, (15, 39, 25, 49), fill=(35, 35, 42))
    box(d, (18, 39, 22, 49), fill=(20, 20, 26))
    box(d, (15, 42, 25, 46), fill=(20, 20, 26))
    for i in range(3):
        d.ellipse((36 + i * 6, 42, 41 + i * 6, 47), fill=(180, 60, 60))


def icon_gameboy(d, c, bright):
    d.rounded_rectangle((20, 18, 44, 72), radius=4, fill=(170, 172, 150),
                        outline=(120, 122, 105))
    box(d, (24, 23, 40, 40), fill=(60, 78, 44), outline=(80, 82, 70))
    box(d, (26, 26, 38, 37), fill=(140, 168, 80))
    box(d, (24, 46, 30, 52), fill=(50, 50, 56))
    box(d, (26, 44, 28, 54), fill=(50, 50, 56))
    d.ellipse((34, 47, 38, 51), fill=(160, 50, 90))
    d.ellipse((38, 44, 42, 48), fill=(160, 50, 90))
    for i in range(4):
        box(d, (27 + i * 3, 60, 28 + i * 3, 66), fill=(120, 122, 105))


def icon_psxpad(d, c, bright):
    _pad(d, 8, 32, 48, 18, (140, 142, 150), radius=6)
    d.rounded_rectangle((11, 44, 23, 62), radius=4, fill=(140, 142, 150))
    d.rounded_rectangle((41, 44, 53, 62), radius=4, fill=(140, 142, 150))
    box(d, (16, 36, 24, 44), fill=(60, 60, 68))
    box(d, (19, 36, 21, 44), fill=(40, 40, 48))
    box(d, (16, 39, 24, 41), fill=(40, 40, 48))
    for (dx, dy) in ((44, 36), (48, 40), (40, 40), (44, 44)):
        d.ellipse((dx, dy, dx + 4, dy + 4), fill=(90, 90, 100))


def icon_cart(d, c, bright):
    """A plain cartridge, for a machine without a picture of its own."""
    box(d, (16, 24, 47, 62), fill=shade(c, 0.9), outline=shade(c, 1.5))
    box(d, (20, 28, 43, 44), fill=(235, 232, 220))
    box(d, (22, 31, 41, 34), fill=shade(c, 1.2))
    box(d, (22, 36, 37, 38), fill=(170, 170, 180))
    box(d, (22, 40, 33, 42), fill=(170, 170, 180))
    box(d, (20, 50, 43, 60), fill=shade(c, 0.5))
    for i in range(7):
        box(d, (22 + i * 3, 52, 23 + i * 3, 58), fill=(200, 190, 120))


def icon_tools(d, c, bright):
    box(d, (14, 28, 50, 60), fill=(34, 36, 44), outline=shade(c, 1.4))
    for i in range(3):
        y = 34 + i * 8
        box(d, (19, y, 45, y + 2), fill=(70, 74, 88))
        knob = 21 + i * 9
        box(d, (knob, y - 2, knob + 4, y + 4), fill=(230, 190, 90) if i == 1 else (150, 200, 230))


def icon_power(d, c, bright):
    d.ellipse((17, 27, 47, 57), outline=(240, 120, 120), width=4)
    box(d, (26, 22, 38, 40), fill=(20, 20, 26))
    box(d, (30, 22, 34, 40), fill=(240, 120, 120))


def icon_magnifier(d, c, bright):
    d.ellipse((16, 22, 44, 50), outline=(220, 224, 235), width=3)
    d.ellipse((20, 26, 40, 46), fill=(60, 120, 170, 255))
    d.line((41, 47, 52, 62), fill=(220, 224, 235), width=5)


def icon_button(d, c, bright):
    d.ellipse((18, 28, 46, 56), fill=(90, 20, 28), outline=(40, 10, 14))
    d.ellipse((21, 25, 43, 47), fill=(230, 60, 74), outline=(255, 160, 160))
    d.ellipse((26, 29, 36, 36), fill=(255, 150, 160))


def icon_screen(d, c, bright):
    box(d, (12, 26, 51, 58), fill=(16, 16, 26), outline=(180, 184, 200))
    for i in range(4):
        box(d, (14 + i, 28 + i, 16 + i, 30 + i), fill=(240, 200, 90))
        box(d, (47 - i, 54 - i, 49 - i, 56 - i), fill=(240, 200, 90))
    box(d, (30, 30, 33, 54), fill=(60, 64, 80))
    box(d, (14, 41, 49, 43), fill=(60, 64, 80))
    box(d, (24, 62, 39, 66), fill=(120, 124, 140))


def icon_drmario(d, c, bright, img=None):
    """Built from the game's own pictures: the name, a pill and the three bugs."""
    pass        # handled separately, because it pastes real sprites


ICONS = {
    "cabinet": icon_cabinet, "table": icon_table, "star": icon_star, "clock": icon_clock,
    "nespad": icon_nespad, "snespad": icon_snespad, "mdpad": icon_mdpad,
    "gameboy": icon_gameboy, "psxpad": icon_psxpad, "cart": icon_cart,
    "tools": icon_tools, "power": icon_power, "magnifier": icon_magnifier,
    "button": icon_button, "screen": icon_screen,
}


# ---------------------------------------------------------------- the card itself
def card(name, short, colour, icon):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    # the box itself: a dark face, a bright edge and a spine down the left
    box(d, (0, 0, W - 1, H - 1), fill=shade(colour, 0.22), outline=shade(colour, 1.5))
    box(d, (1, 1, 5, H - 2), fill=shade(colour, 0.7))
    box(d, (6, 1, W - 2, H - 2), fill=shade(colour, 0.28))
    # a checker wash, like the shelf behind it
    for y in range(8, H - 12, 4):
        for x in range(8, W - 4, 4):
            if (x // 4 + y // 4) % 2 == 0:
                box(d, (x, y, x + 1, y + 1), fill=shade(colour, 0.38))
    # the band across the top with the short name
    box(d, (7, 4, W - 3, 14), fill=(0, 0, 0))
    text(img, short[:6], (W + 4) / 2, 5, (255, 255, 255))
    d = ImageDraw.Draw(img)
    ICONS[icon](d, colour, shade(colour, 1.6))
    # a sheen, and a bright strip along the bottom like the shelf boxes have
    sheen = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).polygon([(7, 1), (34, 1), (7, 40)], fill=(255, 255, 255, 26))
    img.alpha_composite(sheen)
    ImageDraw.Draw(img).rectangle((7, H - 9, W - 3, H - 7), fill=shade(colour, 1.3))
    return img.resize((W * BIG, H * BIG), Image.NEAREST)


def drmario_card():
    """The Dr Mario box, made from the game's own pictures."""
    colour = (26, 87, 174)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    box(d, (0, 0, W - 1, H - 1), fill=shade(colour, 0.22), outline=shade(colour, 1.5))
    box(d, (1, 1, 5, H - 2), fill=shade(colour, 0.7))
    box(d, (6, 1, W - 2, H - 2), fill=(20, 28, 64))
    for y in range(18, H - 14, 4):
        for x in range(8, W - 4, 4):
            if (x // 4 + y // 4) % 2 == 0:
                box(d, (x, y, x + 1, y + 1), fill=(30, 42, 92))
    box(d, (7, 4, W - 3, 14), fill=(0, 0, 0))
    text(img, "MARIO", (W + 4) / 2, 5, (255, 255, 255))

    def paste(fname, x, y, crop=None, scale=1):
        p = os.path.join(DRSPRITES, fname)
        if not os.path.exists(p):
            return
        s = Image.open(p).convert("RGBA")
        if crop:
            s = s.crop(crop)
        if scale != 1:
            s = s.resize((max(1, int(s.width * scale)), max(1, int(s.height * scale))),
                         Image.NEAREST)
        img.alpha_composite(s, (x, y))

    paste("logo_small.png", 2, 20, scale=0.65)          # the name, as the game draws it
    for i, v in enumerate(("virus_red.png", "virus_yellow.png", "virus_blue.png")):
        paste(v, 12 + i * 14, 42, crop=(0, 0, 8, 8))
    for i, hf in enumerate(("half_red.png", "half_blue.png")):
        paste(hf, 20 + i * 8, 58, crop=(0, 0, 8, 8))
    for i, hf in enumerate(("half_yellow.png", "half_red.png")):
        paste(hf, 28 + i * 8, 66, crop=(0, 0, 8, 8))
    ImageDraw.Draw(img).rectangle((7, H - 9, W - 3, H - 7), fill=shade(colour, 1.3))
    return img.resize((W * BIG, H * BIG), Image.NEAREST)


CARDS = [
    ("twoplayer",  "2P",       (26, 112, 87),  "table"),
    ("favourites", "STARS",    (184, 133, 15), "star"),
    ("recent",     "AGAIN",    (41, 112, 102), "clock"),
    ("arcade",     "ARCADE",   (204, 28, 46),  "cabinet"),
    ("mame",       "MAME",     (158, 26, 87),  "cabinet"),
    ("nes",        "NES",      (140, 33, 36),  "nespad"),
    ("snes",       "SNES",     (89, 71, 153),  "snespad"),
    ("genesis",    "MEGA",     (26, 71, 158),  "mdpad"),
    ("sms",        "SMS",      (33, 92, 117),  "cart"),
    ("gg",         "GG",       (41, 107, 82),  "gameboy"),
    ("32x",        "32X",      (51, 51, 140),  "cart"),
    ("gb",         "GB",       (92, 107, 51),  "gameboy"),
    ("gba",        "GBA",      (82, 56, 133),  "gameboy"),
    ("psx",        "PSX",      (61, 61, 71),   "psxpad"),
    ("tg16",       "TG16",     (184, 92, 15),  "cart"),
    ("atari2600",  "2600",     (140, 82, 26),  "cart"),
    ("atari7800",  "7800",     (115, 66, 26),  "cart"),
    ("lynx",       "LYNX",     (128, 102, 20), "gameboy"),
    ("c64",        "C64",      (71, 87, 61),   "cart"),
    ("msx",        "MSX",      (46, 87, 102),  "cart"),
    ("vb",         "VB",       (148, 20, 26),  "cart"),
    ("wonderswan", "WS",       (77, 77, 92),   "gameboy"),
    ("o2em",       "O2",       (102, 46, 102), "cart"),
    ("dreamcast",  "DC",       (184, 107, 26), "psxpad"),
    ("love",       "LOVE",     (191, 51, 107), "cart"),
    ("settings",   "SETUP",    (70, 66, 46),   "tools"),
    ("off",        "OFF",      (120, 26, 31),  "power"),
    ("search",     "LOOK",     (61, 66, 82),   "magnifier"),
    ("buttontest", "TEST",     (46, 71, 77),   "button"),
    ("panel",      "PANEL",    (77, 66, 46),   "cart"),
    ("screen",     "SCREEN",   (56, 77, 92),   "screen"),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    made = 0
    for name, short, colour, icon in CARDS:
        card(name, short, colour, icon).save(os.path.join(OUT, name + ".png"))
        made += 1
    drmario_card().save(os.path.join(OUT, "drmario.png"))
    made += 1
    print("drew %d covers into %s" % (made, OUT))


if __name__ == "__main__":
    main()
