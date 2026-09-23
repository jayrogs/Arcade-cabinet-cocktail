#!/usr/bin/env python3
"""Reads the table-game test films and says, for each game, whether the screen turned
round for player 2. Runs on the PC, on every core.

How it tells: when a table game hands over to the player opposite, the whole picture
turns upside down. So a flipped moment looks like an EARLIER moment of the same game
turned round -- the maze, the score line, the playfield all land where they were,
only the other way up. A game that never flips has no such pair of moments.

It also makes one strip of pictures per game, so every answer can be checked by eye.

    python flipcheck.py
"""
import concurrent.futures as cf
import json, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw
import cab

HERE = os.path.dirname(os.path.abspath(__file__))
LOCAL = os.path.join(os.path.dirname(HERE), "fliptest")
TURN = {0: None, 1: "transpose=2", 3: "transpose=1", 2: "hflip,vflip"}
FPS = 2
W, H = 36, 48


def frames(path, turn):
    vf = ",".join([x for x in (turn, "fps=%d" % FPS, "scale=%d:%d" % (W, H), "format=gray") if x])
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf", vf, "-f", "rawvideo", "-"],
                         capture_output=True).stdout
    a = np.frombuffer(raw, np.uint8)
    n = len(a) // (W * H)
    return a[: n * W * H].reshape(n, H, W).astype(np.float32)


def judge(item):
    stem, path, turn, strip = item
    f = frames(path, turn)
    if len(f) < 10:
        return stem, {"verdict": "NO FILM"}
    bright = f.mean(axis=(1, 2))
    live = bright > 10
    flat = f.reshape(len(f), -1)
    rot = f[:, ::-1, ::-1].reshape(len(f), -1)
    hits = []
    for j in range(len(f)):
        if not live[j]:
            continue
        # a picture that looks the same either way up proves nothing
        if np.abs(flat[j] - rot[j]).mean() < 12:
            continue
        earlier = [i for i in range(0, j - 2 * FPS) if live[i]]
        if not earlier:
            continue
        d0 = np.abs(flat[earlier] - flat[j]).mean(axis=1).min()
        d180 = np.abs(flat[earlier] - rot[j]).mean(axis=1).min()
        if d180 < 0.55 * d0 and d180 < 18:
            hits.append(j / FPS)
    moved = float(np.abs(np.diff(flat[live], axis=0)).mean()) if live.sum() > 2 else 0.0
    if len(hits) >= 3:
        verdict = "FLIPS"
    elif live.sum() < 0.3 * len(f):
        verdict = "MOSTLY BLACK"
    else:
        verdict = "NO FLIP SEEN"
    # the strip: twelve moments across the film, upright
    vf = ",".join([x for x in (turn, "fps=1/7.5", "scale=-2:120") if x])
    tmp = strip + ".d"
    os.makedirs(tmp, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-vf", vf, os.path.join(tmp, "%02d.png")])
    pics = [Image.open(os.path.join(tmp, n)).convert("RGB") for n in sorted(os.listdir(tmp))][:12]
    if pics:
        pw = pics[0].width
        im = Image.new("RGB", (190 + 12 * (pw + 3), 124), (30, 30, 34))
        d = ImageDraw.Draw(im)
        colour = {"FLIPS": (120, 230, 140), "NO FLIP SEEN": (240, 200, 90)}.get(verdict, (255, 110, 110))
        d.text((6, 40), stem, fill=(255, 255, 255))
        d.text((6, 60), verdict, fill=colour)
        for k, p in enumerate(pics):
            im.paste(p, (190 + k * (pw + 3), 2))
        im.save(strip)
    for n in os.listdir(tmp):
        os.remove(os.path.join(tmp, n))
    os.rmdir(tmp)
    return stem, {"verdict": verdict, "flip_at": hits[:3], "movement": round(moved, 1)}


def main():
    os.makedirs(LOCAL, exist_ok=True)
    c = cab.connect()
    s = c.open_sftp()
    orient = json.loads(s.open("/home/jayrogs/roms/arcade/orient.json").read())
    names = [f for f in s.listdir("/home/jayrogs/flip_raw") if f.endswith(".mkv") and not f.startswith(".")]
    failed = [f[:-7] for f in s.listdir("/home/jayrogs/flip_raw") if f.endswith(".failed")]
    for f in names:
        local = os.path.join(LOCAL, f)
        size = s.stat("/home/jayrogs/flip_raw/" + f).st_size
        if not os.path.exists(local) or os.path.getsize(local) != size:
            s.get("/home/jayrogs/flip_raw/" + f, local)
    try:
        rots = json.loads(s.open("/home/jayrogs/flip_raw/mame_rot.json").read())
    except IOError:
        rots = {}
    s.close(); c.close()
    rots.update({g: "ROT90" for g in ("pacman", "pacmanf", "mspacman", "mspacmnf", "jrpacman", "jrpacmnf")})
    rots.update({g: "ROT270" for g in ("dkong", "dkongjr", "dkong3")})
    MAMETURN = {"ROT90": "transpose=1", "ROT270": "transpose=2", "ROT180": "hflip,vflip"}
    m2010 = {"milliped": "ROT270"}          # the MAME 2010 games; only Millipede is tall

    mamecur = {"bnj": "ROT270", "nibbler": "ROT90", "fshark": "ROT270"}   # the current-MAME games

    def turn_for(stem):
        if stem.endswith("_mamecur"):
            return MAMETURN.get(mamecur.get(stem[:-8], "ROT0"))
        if stem.endswith("_m2010"):
            return MAMETURN.get(m2010.get(stem[:-6], "ROT0"))
        if stem.endswith("_mame"):        # MAME's films are stood up by MAME's own record
            return MAMETURN.get(rots.get(stem[:-5], "ROT0"))
        return TURN.get(orient.get(stem, 0))
    todo = [(f[:-4], os.path.join(LOCAL, f), turn_for(f[:-4]),
             os.path.join(LOCAL, f[:-4] + ".png")) for f in sorted(names)]
    results = {}
    with cf.ProcessPoolExecutor(os.cpu_count()) as ex:
        for stem, r in ex.map(judge, todo):
            results[stem] = r
    for stem in failed:
        results[stem] = {"verdict": "WOULD NOT RUN"}
    json.dump(results, open(os.path.join(LOCAL, "results.json"), "w"), indent=1, sort_keys=True)
    counts = {}
    for r in results.values():
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    print(counts)
    for stem in sorted(results):
        print("  %-12s %s" % (stem, results[stem]["verdict"]))


if __name__ == "__main__":
    main()
