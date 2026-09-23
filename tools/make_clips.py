#!/usr/bin/env python3
"""Turns the cabinet's overnight films into the demo screen's clips. Runs on the PC.

For each game filmed on the cabinet:
  1. brings the film over,
  2. finds its liveliest twenty seconds -- a demo spends a lot of its time on title
     cards and high-score tables, and those are not what makes a cabinet look alive,
  3. stands it the right way up, from the emulator's own record of how the game's
     monitor was mounted,
  4. squeezes it into the one kind of video the shelf can play,
and sends the clips back with a list saying each one's shape.

Uses every core on this PC, busiest films first so the cores stay full to the end.

    python make_clips.py
"""
import concurrent.futures as cf
import json, os, subprocess, sys
import numpy as np
import cab

HERE = os.path.dirname(os.path.abspath(__file__))
LOCAL = os.path.join(os.path.dirname(HERE), "demos")
RAW = os.path.join(LOCAL, "raw")
CLIPS = os.path.join(LOCAL, "clips")
PI_RAW = "/home/jayrogs/demos_raw"
PI_CLIPS = "/home/jayrogs/roms/demos"
LENGTH = 20.0            # seconds in each clip
SKIP_START = 6.0         # never before this: it is the start-up test
LOOK_FPS = 4             # how closely the liveliness is measured
TURN = {0: None, 1: "transpose=2", 3: "transpose=1", 2: "hflip,vflip"}


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                          "-show_entries", "stream=width,height,display_aspect_ratio:format=duration",
                          "-of", "json", path], capture_output=True, text=True).stdout
    j = json.loads(out)
    st = j["streams"][0]
    dar = st.get("display_aspect_ratio", "0:1")
    a, b = (int(x) for x in dar.split(":")) if ":" in dar else (0, 1)
    return st["width"], st["height"], (a / b if a and b else 0), float(j["format"]["duration"])


def liveliest(path, duration):
    """Where the most is moving, for LENGTH seconds, after the start-up test."""
    w, h = 32, 32
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf",
                          "fps=%d,scale=%d:%d,format=gray" % (LOOK_FPS, w, h),
                          "-f", "rawvideo", "-"], capture_output=True).stdout
    frames = np.frombuffer(raw, np.uint8)
    n = len(frames) // (w * h)
    if n < 4:
        return SKIP_START
    frames = frames[: n * w * h].reshape(n, h, w).astype(np.int16)
    # GAMEPLAY MOVES ALL OVER THE SCREEN; a title card or a story page moves in one
    # place, or flashes. So what counts is how many parts of the screen are moving,
    # not how much: the screen is cut into sixteen squares and the busy ones counted.
    diff = np.abs(np.diff(frames, axis=0))
    cells = diff.reshape(n - 1, 4, h // 4, 4, w // 4).mean(axis=(2, 4))
    motion = (cells > 3).sum(axis=(1, 2)).astype(float)
    bright = frames[1:].mean(axis=(1, 2))
    motion[bright < 6] = 0                 # a black screen is not a demo
    # a screen that is nearly one colour -- a notice, a blank page -- is not either
    spread = frames[1:].reshape(n - 1, -1).std(axis=1)
    motion[spread < 12] = 0
    span = int(LENGTH * LOOK_FPS)
    first = int(SKIP_START * LOOK_FPS)
    last = len(motion) - span
    if last <= first:
        return max(0.0, min(SKIP_START, duration - LENGTH))
    sums = np.convolve(motion, np.ones(span), "valid")
    best = first + int(np.argmax(sums[first:last + 1]))
    return best / LOOK_FPS


def mostly_pale(src, duration):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", "%.1f" % (duration / 2), "-i", src,
                          "-frames:v", "1", "-vf", "scale=64:48,format=gray", "-f", "rawvideo", "-"],
                         capture_output=True).stdout
    return len(raw) > 0 and sum(1 for b in raw if b > 150) > 0.6 * len(raw)


def make(item):
    stem, turn = item
    src = os.path.join(RAW, stem + ".mkv")
    dst = os.path.join(CLIPS, stem + ".ogv")
    try:
        w, h, dar, duration = probe(src)
        if (w, h) == (640, 480) and mostly_pale(src, duration):
            # FinalBurn Neo's own notice that the game's files do not match: no demo.
            # MAME draws vector games (Battlezone, Tempest) at 640 x 480 too, so the size
            # alone is not enough: the notice is a pale screen, a vector game a black one
            return stem, {"error": "the game does not start"}
        start = liveliest(src, duration)
        # the chip picture is stored on its side for tall games, but the shape the
        # emulator reports is already the upright one
        if turn in ("transpose=1", "transpose=2"):
            w, h = h, w
        shape = dar if dar else w / h
        vf = [turn] if turn else []
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", "%.2f" % start, "-t", str(LENGTH),
                        "-i", src] + (["-vf", ",".join(vf)] if vf else []) +
                       ["-c:v", "libtheora", "-q:v", "7", "-c:a", "libvorbis", "-q:a", "3",
                        "-ar", "44100", "-ac", "2", dst], check=True)
        return stem, {"w": w, "h": h, "shape": round(shape, 4), "from": start}
    except Exception as ex:
        return stem, {"error": str(ex)[:120]}


def main():
    os.makedirs(RAW, exist_ok=True)
    os.makedirs(CLIPS, exist_ok=True)
    c = cab.connect()
    s = c.open_sftp()
    orient = json.loads(s.open("/home/jayrogs/roms/arcade/orient.json").read())
    have = {f for f in s.listdir(PI_RAW) if f.endswith(".mkv") and not f.startswith(".")}
    fetched = 0
    for f in sorted(have):
        local = os.path.join(RAW, f)
        size = s.stat(PI_RAW + "/" + f).st_size
        if not os.path.exists(local) or os.path.getsize(local) != size:
            s.get(PI_RAW + "/" + f, local)
            fetched += 1
    print("brought over", fetched, "new films of", len(have), flush=True)

    listing = os.path.join(CLIPS, "clips.json")
    known = json.load(open(listing)) if os.path.exists(listing) else {}
    todo = []
    for f in sorted(have, key=lambda f: -os.path.getsize(os.path.join(RAW, f))):
        stem = f[:-4]
        if (stem in known and "error" not in known[stem] and "--again" not in sys.argv
                and os.path.exists(os.path.join(CLIPS, stem + ".ogv"))):
            continue
        todo.append((stem, TURN.get(orient.get(stem, 0))))
    print("cutting", len(todo), "clips on", os.cpu_count(), "cores", flush=True)
    with cf.ProcessPoolExecutor(os.cpu_count()) as ex:
        for stem, info in ex.map(make, todo):
            known[stem] = info
            if "error" in info:
                print("  FAILED", stem, info["error"], flush=True)
    json.dump(known, open(listing, "w"), indent=0, sort_keys=True)

    try:
        s.mkdir(PI_CLIPS)
    except IOError:
        pass
    on_pi = set(s.listdir(PI_CLIPS))
    sent = 0
    for stem, info in known.items():
        if "error" in info:
            continue
        name = stem + ".ogv"
        if name not in on_pi or "--again" in sys.argv:
            s.put(os.path.join(CLIPS, name), PI_CLIPS + "/" + name)
            sent += 1
    good = {k: v for k, v in known.items() if "error" not in v}
    with s.open(PI_CLIPS + "/clips.json", "w") as fh:
        fh.write(json.dumps(good, sort_keys=True).encode())
    # the shelf reads this simpler one: a name and a shape on each line
    with s.open(PI_CLIPS + "/clips.txt", "w") as fh:
        TAB, NL = chr(9), chr(10)
        fh.write("".join(k + TAB + "%.4f" % v["shape"] + NL
                         for k, v in sorted(good.items())).encode())
    s.close()
    c.close()
    print("sent", sent, "clips;", len(good), "on the cabinet in all", flush=True)


if __name__ == "__main__":
    main()
