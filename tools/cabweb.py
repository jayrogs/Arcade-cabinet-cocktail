#!/usr/bin/env python3
"""The cabinet, on a web page.

Shows what is on the cabinet's screen and sends button presses back, so the table can
be used and tested from anywhere. The presses go through a made-up joystick that looks
to the games exactly like the real panel.
"""
import http.server, io, os, socket, socketserver, subprocess, threading, time
import urllib.parse, urllib.request

PORT = 8080

# The screen recorder is a child of this program. If it is left behind when this stops,
# systemd waits a minute and a half for it and a restart looks like a hang -- which it
# did once. So it is stopped on the way out, every way out.
import atexit, signal

def _tidy(*_a):
    subprocess.run(["pkill", "-x", "wf-recorder"], check=False)

atexit.register(_tidy)
for _sig in (signal.SIGTERM, signal.SIGINT):
    signal.signal(_sig, lambda *_a: (_tidy(), os._exit(0)))
SCALE = os.environ.get("CAB_SCALE", "0.75")
QUALITY = os.environ.get("CAB_QUALITY", "45")
ENV = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-0")

# --- the made-up panel ------------------------------------------------------
pad = pad2 = None
try:
    from evdev import UInput, ecodes as e, AbsInfo
    caps = {
        e.EV_KEY: [e.BTN_TRIGGER, e.BTN_THUMB, e.BTN_THUMB2, e.BTN_TOP,
                   e.BTN_TOP2, e.BTN_PINKIE, e.BTN_BASE, e.BTN_BASE2,
                   e.BTN_BASE3, e.BTN_BASE4],
        e.EV_ABS: [
            (e.ABS_X, AbsInfo(value=0, min=-32767, max=32767, fuzz=0, flat=0, resolution=0)),
            (e.ABS_Y, AbsInfo(value=0, min=-32767, max=32767, fuzz=0, flat=0, resolution=0)),
        ],
    }
    pad = UInput(caps, name="Cab Web Panel", vendor=0x16c0, product=0x75e2)
    # a second one for player 2's start and coin, made after the first so it is player 2
    time.sleep(0.5)
    pad2 = UInput(caps, name="Cab Web Panel 2", vendor=0x16c0, product=0x75e3)
    time.sleep(0.5)
except Exception as ex:                     # no uinput: the page still shows the screen
    print("no made-up panel:", ex, flush=True)

BUTTONS = {}
if pad:
    from evdev import ecodes as e
    BUTTONS = {
        1: e.BTN_TRIGGER, 2: e.BTN_THUMB, 3: e.BTN_THUMB2, 4: e.BTN_TOP,
        5: e.BTN_TOP2, 6: e.BTN_PINKIE, 7: e.BTN_BASE, 8: e.BTN_BASE2,
        9: e.BTN_BASE3, 10: e.BTN_BASE4,
    }

def tap(button, ms=90, player=1):
    """A press. Held longer when asked, which is how the page asks for the shelf."""
    dev = pad2 if player == 2 else pad
    if not dev or button not in BUTTONS:
        return
    from evdev import ecodes as e
    dev.write(e.EV_KEY, BUTTONS[button], 1)
    dev.syn()
    time.sleep(max(0.02, min(ms, 3000) / 1000.0))
    dev.write(e.EV_KEY, BUTTONS[button], 0)
    dev.syn()

def push(direction):
    if not pad:
        return
    from evdev import ecodes as e
    x, y = {"left": (-32767, 0), "right": (32767, 0),
            "up": (0, -32767), "down": (0, 32767)}.get(direction, (0, 0))
    pad.write(e.EV_ABS, e.ABS_X, x)
    pad.write(e.EV_ABS, e.ABS_Y, y)
    pad.syn()
    time.sleep(0.12)
    pad.write(e.EV_ABS, e.ABS_X, 0)
    pad.write(e.EV_ABS, e.ABS_Y, 0)
    pad.syn()

# --- the screen -------------------------------------------------------------
# Grabbing the screen costs about a third of a second, so it happens all the time in
# the background and whoever asks gets the newest one immediately. This build of grim
# has no jpeg of its own, so it hands over a raw picture and Pillow squeezes it.
from PIL import Image

_latest = [b"", 0.0]
_wake = threading.Condition()
_watchers = [0]

def grab_once():
    p = subprocess.run(["grim", "-s", SCALE, "-t", "ppm", "-"],
                       capture_output=True, env=ENV, timeout=10)
    if not p.stdout:
        raise RuntimeError(p.stderr.decode(errors="replace")[:200] or "no picture")
    img = Image.open(io.BytesIO(p.stdout)).convert("RGB")
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=int(QUALITY))
    return buf.getvalue()

# A screen recorder keeps a picture coming about nine times a second; grabbing single
# snapshots managed three. It writes into a pipe and this reads whole pictures out of
# it. The picture arrives sideways, because the cabinet's screen is turned, so the
# recorder is told to turn it back.
FIFO = "/tmp/cabfifo"
# The recorder hands over plain uncompressed pictures and the squeezing is done here,
# because its own compression ignored every quality setting and sent 50KB a picture --
# far too much to push down a phone line.
SHOT_W, SHOT_H = 480, 640
# three sizes to choose from on the page: a picture of this cabinet is mostly
# checkerboard, which is the hardest thing there is to squeeze, so a phone on a slow
# line wants the small one
LEVELS = {
    "low":    ((336, 448), 25, 5),
    "medium": ((400, 533), 35, 8),
    "high":   ((480, 640), 45, 10),
}
level = ["medium"]

# Real video, not a run of still pictures. The Pi's own video chip does the squeezing,
# the video server hands it to the browser, and it only runs while someone is watching.
# A cabinet screen barely changes from moment to moment, which is exactly what video is
# good at, so this is both smaller and far quicker than sending pictures.
VIDEO = {
    "low":    ("12", "500k", ""),
    "medium": ("20", "1200k", ""),
    "high":   ("25", "2500k", ""),
}
ORDER = ["high", "medium", "low"]
preferred = ["medium"]       # what was picked in the settings; a struggling phone only
                             # steps down from it for the visit, never for good
QUALITY_FILE = "/home/jayrogs/stream/quality.conf"

# THE PI CAN ONLY RECORD ITS SCREEN ONCE AT A TIME. There are two ways of watching
# here -- live video, and the old run of still pictures -- and each one needs its own
# recorder, so the two must never run together. Whichever the browser asks for wins,
# and the other one steps aside. Without this the page falls back to pictures, the
# pictures then block the video from ever starting, and it can never get back.
video_until = [0.0]          # live video has the screen until this moment

WATCH_FLAG = "/tmp/cab_watching"

def video_wanted():
    return time.time() < video_until[0]


def mark_watching(on):
    """A file the shelf looks at: while somebody is watching from a phone, the shelf
    stops playing its demo films. Decoding those costs about half a core, which is the
    difference between a smooth picture and a slide show."""
    try:
        if on:
            with open(WATCH_FLAG, "w") as f:
                f.write(str(int(time.time())))
        elif os.path.exists(WATCH_FLAG):
            os.remove(WATCH_FLAG)
    except OSError:
        pass

def _recorder_pids(fifo):
    return _pids(fifo, program="wf-recorder")

# Getting out of a game, and starting the cabinet over. The launcher shows the shelf,
# runs whatever it picks, then shows the shelf again -- so stopping the game IS the way
# back to the shelf, and stopping the shelf is the way to restart it.
#
# Everything here finds what to stop by its own process number. Never by a name pattern:
# a pattern also matches the command asking for the kill, and that mistake has taken the
# whole cabinet down twice.
SHELF = "cabmenu.love"
DRMARIO = "drcocktail.love"
LAUNCHER_PID = "/tmp/cab.pid"

def _comm(pid):
    # the name of the program itself, not the words on its command line
    try:
        with open("/proc/%d/comm" % pid) as f:
            return f.read().strip()
    except Exception:
        return ""

def _pids(pattern, program=None):
    # A command line search alone is a trap: it also matches the shell that is asking
    # for the kill, which has taken this cabinet down twice. So every match must also
    # BE the program we mean, checked by its own name.
    try:
        out = subprocess.run(["pgrep", "-f", pattern], capture_output=True, text=True)
        found = [int(x) for x in out.stdout.split() if x.strip().isdigit()]
    except Exception:
        return []
    mine = {os.getpid(), os.getppid()}
    return [p for p in found
            if p not in mine and (program is None or _comm(p) == program)]

def _stop(pids, hard_after=4):
    for pid in pids:
        try:
            os.kill(pid, 15)
        except Exception:
            pass
    if not pids:
        return 0
    for _ in range(hard_after * 4):
        time.sleep(0.25)
        if not any(_alive(pid) for pid in pids):
            return len(pids)
    for pid in pids:
        try:
            os.kill(pid, 9)
        except Exception:
            pass
    return len(pids)

def _alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except Exception:
        return False

def _playing():
    """Whatever the launcher has put on top of the shelf.

    Not just games: the button setup and the screen sizing are the same kind of thing,
    and getting stuck in one of those with no way back was the whole reason this exists.
    So it is anything running EXCEPT the shelf itself.
    """
    found = []
    try:
        out = subprocess.run(["pgrep", "-x", "retroarch"], capture_output=True, text=True)
        found += [int(x) for x in out.stdout.split() if x.strip().isdigit()]
    except Exception:
        pass
    try:
        # Crossy Road runs under Wine and shows up as "Game.exe": stopping it ends the
        # launcher's run the same way closing the emulator does
        out = subprocess.run(["pgrep", "-f", r"^Game\.exe "], capture_output=True, text=True)
        found += [int(x) for x in out.stdout.split() if x.strip().isdigit()]
    except Exception:
        pass
    try:
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
            if SHELF not in words:            # the shelf stays; everything else goes
                found.append(pid)
    except Exception:
        pass
    return found

def restart(what):
    if what == "game":
        n = _stop(sorted(set(_playing())))
        return "back to the shelf" if n else "nothing was playing"
    if what == "shelf":
        _stop(sorted(set(_playing())))
        _stop(_pids(SHELF, program="love"))
        return "the shelf is starting again"
    if what == "all":
        try:
            launcher = int(open(LAUNCHER_PID).read().strip())
        except Exception:
            launcher = 0
        if launcher:
            _stop([launcher])
        _stop(sorted(set(_playing())))
        _stop(_pids(SHELF, program="love"))
        time.sleep(1)
        env = dict(os.environ)
        env["XDG_RUNTIME_DIR"] = "/run/user/1000"
        env["WAYLAND_DISPLAY"] = "wayland-0"
        subprocess.Popen(["/home/jayrogs/cab.sh"], env=env, start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
        return "the whole cabinet is starting again"
    return "not a thing I can restart"

def set_video_quality(name):
    fps, rate, scale = VIDEO.get(name, VIDEO["medium"])
    with open(QUALITY_FILE, "w") as f:
        f.write(("FPS=%s\nBITRATE=%s" + chr(10) + "SCALE=%s\n") % (fps, rate, scale))
    # stop the video feed only, never the picture one; the video server starts a
    # fresh feed as soon as the browser asks again, which it does a moment later
    _stop(_recorder_pids("/tmp/cabvid"))
SHOT_BYTES = SHOT_W * SHOT_H * 3
RECORD = ["wf-recorder", "-c", "rawvideo", "-m", "rawvideo", "-x", "rgb24", "-r", "10",
          "-F", "transpose=1,scale=%d:%d" % (SHOT_W, SHOT_H), "-f", FIFO]
IDLE_STOP = 25          # seconds with nobody watching before the recorder rests

def recorder():
    while True:
        # nothing is recorded while nobody has the page open: a game should never
        # lose speed to a window nobody is looking through
        # never while the live video feed has the screen: the Pi records once at a time
        while (_watchers[0] == 0 or video_wanted()
               or _recorder_pids("/tmp/cabvid")):
            time.sleep(0.5)
        try:
            if os.path.exists(FIFO):
                os.unlink(FIFO)
            if not video_wanted():
                mark_watching(False)
            os.mkfifo(FIFO)
        except Exception:
            pass
        # Nothing else may be writing into this pipe. Two recorders at once interleave
        # their pictures, and every picture after that comes out shifted sideways.
        _stop(_recorder_pids(FIFO))
        proc = subprocess.Popen(RECORD, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, env=ENV)
        try:
            with open(FIFO, "rb") as f:
                quiet = time.time()
                while proc.poll() is None:
                    if video_wanted() or _recorder_pids("/tmp/cabvid"):
                        break
                    if _watchers[0] == 0:
                        if time.time() - quiet > IDLE_STOP:
                            break
                    else:
                        quiet = time.time()
                    raw = f.read(SHOT_BYTES)
                    if not raw or len(raw) < SHOT_BYTES:
                        break
                    size, quality, rate = LEVELS.get(level[0], LEVELS["medium"])
                    now = time.time()
                    if now - _latest[1] < 1.0 / rate:
                        continue              # keep to the chosen rate
                    img = Image.frombytes("RGB", (SHOT_W, SHOT_H), raw)
                    if size != (SHOT_W, SHOT_H):
                        img = img.resize(size, Image.BILINEAR)
                    buf = io.BytesIO()
                    img.save(buf, "JPEG", quality=quality, optimize=False)
                    with _wake:
                        _latest[0], _latest[1] = buf.getvalue(), time.time()
                        _wake.notify_all()
        except Exception:
            pass
        finally:
            try:
                proc.kill()
                proc.wait(timeout=3)      # collect it, so no husk is left behind
            except Exception:
                pass
        time.sleep(1)

def grabber():
    # a spare pair of hands: if the recorder is not delivering, fall back to snapshots
    while True:
        time.sleep(0.5)
        if time.time() - _latest[1] < 2:
            continue
        if _watchers[0] == 0:
            continue
        try:
            data = grab_once()
        except Exception:
            continue
        with _wake:
            _latest[0], _latest[1] = data, time.time()
            _wake.notify_all()

def frame(wait_for_new=False, since=0.0):
    with _wake:
        if wait_for_new:
            _wake.wait(timeout=2.0)
        return _latest[0], _latest[1]

threading.Thread(target=recorder, daemon=True).start()
threading.Thread(target=grabber, daemon=True).start()

# --- the sound ---------------------------------------------------------------
# Listens in on what the cabinet is playing and sends it out as a stream the page can
# play. The source is the monitor of whichever output the cabinet plays through (headphone
# jack, USB sound card or HDMI), so it hears the menu music and the games exactly as the
# cabinet does.
SOURCE = "@DEFAULT_MONITOR@"

def audio_stream():
    return subprocess.Popen(
        ["ffmpeg", "-loglevel", "quiet",
         "-f", "pulse", "-i", SOURCE,
         "-ac", "2", "-ar", "44100",
         "-c:a", "libmp3lame", "-b:a", "96k", "-f", "mp3", "-"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=ENV)

PAGE = """<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#0d0d0f">
<title>The cabinet</title>
<style>
 *{box-sizing:border-box}
 [hidden]{display:none !important}   /* hidden means hidden, whatever else is said below */
 body{background:#0d0d0f;color:#e9e9ee;margin:0;
      font:15px/1.45 -apple-system,system-ui,"Segoe UI",Roboto,sans-serif;
      padding:10px 12px calc(18px + env(safe-area-inset-bottom,0px));
      display:flex;flex-direction:column;align-items:center;gap:12px;
      -webkit-user-select:none;user-select:none}

 /* the cabinet screen: it is a tall screen, so keep it tall */
 /* The cabinet screen is mounted sideways, and the picture is now sent exactly as it
    lies rather than being turned by the Pi -- turning it there cost most of a core.
    The phone turns it instead, which costs nothing: the video is laid out as wide as
    the box is tall, then rotated a quarter turn into place. */
 #v{position:absolute;width:133.333%;height:75%;object-fit:contain;
    transform:rotate(90deg);transform-origin:center center}
 .screen{position:relative;height:min(46vh,540px);aspect-ratio:3/4;background:#000;overflow:hidden;
         border:1px solid #2b2b33;border-radius:12px;display:flex;
         align-items:center;justify-content:center}
 .screen video,.screen img{width:100%;height:100%;object-fit:contain;display:block;
                           image-rendering:pixelated}
 .bar{width:100%;max-width:430px;display:flex;align-items:center;gap:10px;
      justify-content:space-between;font-size:12px;color:#8b8b97;min-height:20px}
 .bar b{font-weight:500;color:#8b8b97}

 button{font:inherit;color:#e9e9ee;background:#1b1b21;border:1px solid #32323c;
        border-radius:13px;touch-action:manipulation;-webkit-tap-highlight-color:transparent}
 button:active{filter:brightness(1.5)}

 /* the stick and the fire buttons, side by side, where thumbs actually are */
 .pads{width:100%;max-width:430px;display:flex;align-items:center;
       justify-content:space-between;gap:10px}
 .dpad{display:grid;grid-template-columns:repeat(3,58px);grid-template-rows:repeat(3,58px);gap:6px}
 .dpad button{font-size:19px;color:#c9c9d6}
 .u{grid-area:1/2}.l{grid-area:2/1}.r{grid-area:2/3}.dn{grid-area:3/2}
 .fires{display:grid;grid-template-columns:repeat(2,66px);gap:10px}
 .fire{width:66px;height:66px;border-radius:50%;font-size:19px;font-weight:600;
       background:#2c1119;border-color:#5d2130;color:#ffc9d4}
 .fire.one{background:#8d1f31;border-color:#c13;color:#fff}

 /* the two that matter most */
 .main{width:100%;max-width:430px;display:flex;gap:10px}
 .main button{flex:1;padding:15px 2px;font-weight:600;font-size:13px;letter-spacing:.2px}
 .coin{background:#33280e;border-color:#6d5620;color:#ffe6a6}
 .start{background:#2a1430;border-color:#5c2f66;color:#f0c5ff}
 .side{background:#171b2a;border-color:#2f3a5c;color:#c5d3ff}
 .snd{background:#16241c;border-color:#2c5c41;color:#bff0d4}
 .snd.off{background:#1b1b21;border-color:#32323c;color:#8b8b97}

 .more{width:100%;max-width:430px;padding:13px;color:#9b9ba7;background:#141418;
       border-color:#26262e;font-size:14px}
 #extra{width:100%;max-width:430px;display:flex;flex-direction:column;gap:10px}
 #extra[hidden]{display:none}
 .group{background:#131317;border:1px solid #25252d;border-radius:13px;padding:11px}
 .group h4{margin:0 0 9px;font-size:11px;font-weight:600;color:#7d7d8a;
           letter-spacing:.09em;text-transform:uppercase}
 .row{display:flex;gap:8px;flex-wrap:wrap}
 .row button{flex:1 1 auto;min-width:92px;padding:13px 10px;font-size:14px}
 button.on{background:#1d3a2a;border-color:#3d7a57;color:#d4ffe5}
 .danger{background:#2a1316;border-color:#5b2a2f;color:#ffd0d0}
 select{font:inherit;color:#e9e9ee;background:#1b1b21;border:1px solid #32323c;
        border-radius:13px;padding:12px 10px;flex:1 1 auto;min-width:120px}
 small{color:#75757f;font-size:12px;text-align:center;max-width:430px;line-height:1.5}
</style>

<div class=screen><video id=v autoplay playsinline muted></video><img id=s hidden></div>
<div class=bar><b id=how>starting the video...</b><button class=more style="width:auto;padding:5px 11px;font-size:12px" onclick="full()">Full screen</button></div>

<div class=pads>
 <div class=dpad>
  <button class=u>&#9650;</button>
  <button class=l>&#9664;</button>
  <button class=r>&#9654;</button>
  <button class=dn>&#9660;</button>
 </div>
 <div class=fires>
  <button class="fire one" data-b=1>1</button>
  <button class=fire data-b=2>2</button>
  <button class=fire data-b=3>3</button>
  <button class=fire data-b=4>4</button>
 </div>
</div>

<div class="main">
 <button class=coin onclick="b(8)">COIN</button>
 <button class=start onclick="b(9)">1P START</button>
 <button class=start onclick="b2(9)">2P START</button>
 <button class=side id=sidebtn>SIDE</button>
 <button class="snd off" id=snd onclick="sound()">SOUND OFF</button>
</div>

<button class=more onclick="toggle()">Settings and restarting</button>
<div id=extra hidden>
 <div class=group>
  <h4>Picture</h4>
  <div class=row>
   <button data-q=low>Save data</button>
   <button data-q=medium class=on>Normal</button>
   <button data-q=high>Best</button>
   <button id=mode onclick="pictures()">Still pictures</button>
  </div>
 </div>
 <div class=group id=addgame>
  <h4>Add a game</h4>
  <div class=row>
   <select id=upto>
    <option value=arcade>Arcade</option><option value=nes>Nintendo</option>
    <option value=snes>Super Nintendo</option><option value=genesis>Mega Drive</option>
    <option value=sms>Master System</option><option value=gg>Game Gear</option>
    <option value=gb>Game Boy</option><option value=gba>Game Boy Advance</option>
    <option value=tg16>TurboGrafx</option><option value=atari2600>Atari 2600</option>
    <option value=atari7800>Atari 7800</option><option value=lynx>Lynx</option>
    <option value=psx>PlayStation</option><option value=mame>MAME</option>
    <option value=music>Menu music</option>
   </select>
   <button onclick="document.getElementById('upfile').click()">Choose the file</button>
   <input id=upfile type=file hidden onchange="upload(this)">
  </div>
  <small id=upsaid style="display:block;margin-top:8px;text-align:left">The file goes in exactly as it is. Do not unzip it.</small>
 </div>
 <div class=group>
  <h4>Restarting</h4>
  <div class=row>
   <button onclick="go('game')">Back to the shelf</button>
   <button onclick="go('shelf')">Restart the shelf</button>
   <button class=danger id=allbtn onclick="go('all')">Restart everything</button>
  </div>
 </div>
</div>
<small>Tap SIDE to play the same game again. Hold it to come back to the shelf.
The side button on the cabinet does the same.<br>
SOUND is what the cabinet is playing, and it comes down with the picture.</small>

<script>
const img = document.getElementById('s');
const vid = document.getElementById('v');
// THE SOUND HAS ITS OWN PLAYER. Tied to the picture it came out silent (the picture's
// timing held it back); on its own it plays. The picture itself always stays muted.
const snd = new Audio();
let soundOn = location.search.includes('loud');   // 'loud' is a test switch
const how = document.getElementById('how');
const mode = document.getElementById('mode');
let pc = null, onPictures = false, watchdog = null;
let tries = 0;            // fresh attempts since the video last worked
let chosen = false;       // true when YOU asked for still pictures, not a failure

// ---- the picture ----------------------------------------------------------
// Live video. The browser asks for a stream, the cabinet answers, and after that the
// pictures travel straight between the two with nothing in the middle.
async function video(){
  stopVideo();
  onPictures = false;
  img.removeAttribute('src');      // let go of the picture stream
  mode.textContent = 'Still pictures';
  mode.onclick = () => pictures();
  how.textContent = 'starting the video...';
  try {
    // A phone that is not on the house network needs help finding a way in. These
    // only help the two ends find each other; the pictures still travel directly.
    pc = new RTCPeerConnection({iceServers: [
      {urls: 'stun:stun.l.google.com:19302'},
      {urls: 'stun:stun.cloudflare.com:3478'}
    ]});
    pc.addTransceiver('video', {direction: 'recvonly'});
    pc.addTransceiver('audio', {direction: 'recvonly'});
    pc.ontrack = ev => {
      if (ev.track.kind === 'audio') {
        snd.srcObject = new MediaStream([ev.track]);
        if (soundOn) snd.play().catch(err => {
          // a phone may want a fresh tap before it plays sound; the button then says so
          if (err && err.name === 'NotAllowedError') { soundOn = false; showSound(); }
        });
      } else {
        vid.srcObject = new MediaStream([ev.track]);
        vid.muted = true;
        vid.play().catch(() => {});
      }
    };
    // the moment a real picture lands, stop worrying
    vid.onplaying = vid.onloadeddata = () => {
      if (vid.videoWidth) { clearTimeout(watchdog); tries = 0; how.textContent = 'live video'; }
    };
    const mine = pc;      // so an old connection's dying words are not mistaken for this one
    pc.onconnectionstatechange = () => {
      if (pc !== mine) return;
      if (mine.connectionState === 'connected' && !vid.videoWidth)
        how.textContent = 'connected, waiting for the picture...';
      if (mine.connectionState === 'failed') {
        // try again before settling for still pictures: a phone freezes a tab it is
        // not showing, and the connection dies of that, not of anything being wrong
        if (tries < 2) { tries++; how.textContent = 'reconnecting...'; setTimeout(video, 700); }
        else smaller('the video would not connect');
      }
    };
    await pc.setLocalDescription(await pc.createOffer());
    await new Promise(done => {
      if (pc.iceGatheringState === 'complete') return done();
      const t = setTimeout(done, 2500);
      pc.addEventListener('icegatheringstatechange', () => {
        if (pc.iceGatheringState === 'complete') { clearTimeout(t); done(); }
      });
    });
    const res = await fetch('/whep', {method: 'POST',
      headers: {'Content-Type': 'application/sdp'}, body: pc.localDescription.sdp});
    if (!res.ok) throw new Error('refused');
    await pc.setRemoteDescription({type: 'answer', sdp: await res.text()});
    vid.hidden = false; img.hidden = true;
    how.textContent = 'waiting for the picture...';
    // The cabinet has to start recording itself before anything can arrive, which
    // takes 10-25 seconds. Giving up too soon threw away a video that was working.
    clearTimeout(watchdog);
    watchdog = setTimeout(() => {
      if (!onPictures && !vid.videoWidth) smaller('the video never started');
    }, 45000);   // the feed can take 20 s or more to start while the Pi is busy
  } catch (e) {
    smaller('the video would not start');
  }
}

// When the video struggles, make the video SMALLER and try again: a smaller picture at
// fewer frames gets through a weak connection. Still pictures are only the last resort,
// once the smallest video has failed too -- and even then the video is tried again
// every half minute, so a connection that recovers gets its video back by itself.
let retryVideo = null;
async function smaller(why){
  let now = 'bottom';
  try { now = await (await fetch('/quality?step=down')).text(); } catch (e) {}
  if (now === 'bottom') {
    pictures(why);
    clearTimeout(retryVideo);
    retryVideo = setTimeout(() => { if (onPictures && !chosen) { tries = 0; video(); } }, 30000);
    return;
  }
  showLevel(now);
  tries = 0;
  how.textContent = why + ' - trying a smaller video...';
  setTimeout(video, 900);
}
function showLevel(name){
  document.querySelectorAll('[data-q]').forEach(o => o.classList.toggle('on', o.dataset.q === name));
}
// a fresh visit starts from the level picked in the settings, not from wherever the
// last bad connection left it
fetch('/quality?step=reset').then(r => r.text()).then(showLevel).catch(() => {});

// Is the cabinet's sound really arriving? Asked of the connection itself every two
// seconds, so the page can say which end is silent instead of leaving it to guesswork.
let lastEnergy = 0, lastPackets = 0;
setInterval(async () => {
  if (!pc || onPictures) return;
  let got = null;
  (await pc.getStats()).forEach(r => { if (r.type === 'inbound-rtp' && r.kind === 'audio') got = r; });
  const packets = got ? got.packetsReceived : 0, energy = got ? (got.totalAudioEnergy || 0) : 0;
  const arriving = packets > lastPackets, loud = energy > lastEnergy + 1e-7;
  how.dataset.sound = packets + ' packets, energy ' + energy.toFixed(5);
  // the sound is only measured while it is playing, so "silent" means something only then
  if (vid.videoWidth) how.textContent = 'live video - ' + (!arriving ? 'NO SOUND ARRIVING from the cabinet'
    : !soundOn ? 'sound ready (tap SOUND OFF to hear it)'
    : loud ? 'sound playing' : 'sound on, but the cabinet is quiet right now');
  // tell the cabinet too, so a silent phone can be looked into from the other end
  fetch('/soundreport?packets=' + packets + '&energy=' + energy.toFixed(5) + '&soundOn=' + soundOn + '&sndPaused=' + snd.paused +
        '&volume=' + vid.volume + '&paused=' + vid.paused + '&w=' + vid.videoWidth + '&state=' + pc.connectionState +
        '&tracks=' + (snd.srcObject ? snd.srcObject.getAudioTracks().map(a => a.readyState + (a.enabled ? '' : '-disabled') + (a.muted ? '-muted' : '')).join('+') : 'none')).catch(() => {});
  lastPackets = packets; lastEnergy = energy;
}, 2000);

function stopVideo(){
  clearTimeout(watchdog);
  if (pc) { try { pc.close(); } catch (e) {} pc = null; }
  vid.srcObject = null;
  snd.pause(); snd.srcObject = null;
}

// the old way, kept as a safety net: a run of still pictures
function pictures(why){
  stopVideo();
  onPictures = true;
  chosen = !why;          // no reason given means the button was pressed on purpose
  vid.hidden = true; img.hidden = false;
  img.src = '/stream?' + Date.now();
  how.textContent = why ? why + ' - still pictures instead' : 'still pictures';
  mode.textContent = 'Live video';
  mode.onclick = () => video();
}
img.onerror = () => { if (onPictures) setTimeout(() => { img.src = '/stream?' + Date.now(); }, 800); };

// Leaving the tab lets go of the video, so the cabinet is not recording for nobody.
// Coming back picks it straight up again -- unless still pictures were YOUR choice.
document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    if (!onPictures) stopVideo();
    return;
  }
  if (!chosen) { tries = 0; video(); }
});

function full(){
  const el = onPictures ? img : vid;
  if (el.requestFullscreen) el.requestFullscreen().catch(() => {});
  else if (el.webkitEnterFullscreen) el.webkitEnterFullscreen();
}

// ---- the panel ------------------------------------------------------------
function b(n, ms){ fetch('/press?b=' + n + (ms ? '&ms=' + ms : '')); }
function b2(n){ fetch('/press?p=2&b=' + n); }     // player 2's controller
function d(w){ fetch('/push?d=' + w); }

// a button held down keeps going, the way a real one does
function repeats(el, fire){
  let timer = null;
  const go = ev => { ev.preventDefault(); fire(); clearInterval(timer);
                     timer = setInterval(fire, 170); };
  const stop = () => { clearInterval(timer); timer = null; };
  el.addEventListener('pointerdown', go);
  el.addEventListener('pointerup', stop);
  el.addEventListener('pointerleave', stop);
  el.addEventListener('pointercancel', stop);
}
repeats(document.querySelector('.u'), () => d('up'));
repeats(document.querySelector('.dn'), () => d('down'));
repeats(document.querySelector('.l'), () => d('left'));
repeats(document.querySelector('.r'), () => d('right'));
document.querySelectorAll('.fire').forEach(el => {
  el.addEventListener('pointerdown', ev => { ev.preventDefault(); b(el.dataset.b); });
});

// SIDE: a tap plays the same game again, holding it brings the shelf back, exactly
// like the button on the side of the cabinet
const sidebtn = document.getElementById('sidebtn');
let sideAt = 0, sideDone = false, sideTimer = null;
sidebtn.addEventListener('pointerdown', ev => {
  ev.preventDefault();
  sideAt = Date.now(); sideDone = false;
  sideTimer = setTimeout(() => { sideDone = true; b(10, 1200); sidebtn.textContent = 'SHELF'; }, 700);
});
function sideUp(){
  clearTimeout(sideTimer);
  if (sideAt && !sideDone) b(10);
  sideAt = 0;
  setTimeout(() => { sidebtn.textContent = 'SIDE'; }, 500);
}
sidebtn.addEventListener('pointerup', sideUp);
sidebtn.addEventListener('pointerleave', sideUp);

// ---- the rest -------------------------------------------------------------
// Adding a game. It must check the cabinet's answer and say NOT SAVED in red when it
// fails: a page that says "saved" while nothing was saved is worse than no page.
function upload(input){
  const f = input.files[0];
  const said = document.getElementById('upsaid');
  if (!f) return;
  const to = document.getElementById('upto').value;
  const x = new XMLHttpRequest();
  x.open('POST', '/upload?to=' + encodeURIComponent(to) + '&name=' + encodeURIComponent(f.name));
  x.upload.onprogress = e => {
    if (e.lengthComputable) said.textContent = 'sending ' + f.name + ' ... ' +
      Math.round(100 * e.loaded / e.total) + '%';
  };
  const bad = why => { said.style.color = '#ff6b6b'; said.textContent = 'NOT SAVED - ' + why; };
  x.onload = () => {
    if (x.status === 200) { said.style.color = '#7ddc9a'; said.textContent = x.responseText; }
    else bad(x.responseText || ('the cabinet said ' + x.status));
  };
  x.onerror = () => bad('the cabinet did not answer');
  said.style.color = '#c9c9d6';
  said.textContent = 'sending ' + f.name + ' ...';
  x.send(f);
  input.value = '';
}

function toggle(){
  const x = document.getElementById('extra');
  x.hidden = !x.hidden;
}

document.querySelectorAll('[data-q]').forEach(el => {
  el.onclick = () => {
    document.querySelectorAll('[data-q]').forEach(o => o.classList.remove('on'));
    el.classList.add('on');
    fetch('/quality?level=' + el.dataset.q).then(() => {
      if (onPictures) img.src = '/stream?' + Date.now(); else setTimeout(video, 700);
    });
  };
});

// The sound comes down inside the video itself, so it stays with the picture. The
// video starts silent because a browser will not play sound until it is asked to.
function sound(){
  soundOn = !soundOn;
  snd.volume = 1;
  if (soundOn) snd.play().catch(() => {}); else snd.pause();
  showSound();
}
// the button always says what is really happening
function showSound(){
  const btn = document.getElementById('snd');
  btn.textContent = soundOn ? 'SOUND ON' : 'SOUND OFF';
  btn.classList.toggle('off', !soundOn);
}
showSound();


// Restarting. The big one asks twice, because a stray tap should not take the
// cabinet down in the middle of a game.
let armed = null;
function go(what){
  const btn = document.getElementById('allbtn');
  if (what === 'all' && armed !== 'all') {
    armed = 'all';
    btn.textContent = 'Tap again to be sure';
    setTimeout(() => { armed = null; btn.textContent = 'Restart everything'; }, 5000);
    return;
  }
  armed = null;
  btn.textContent = 'Restart everything';
  how.textContent = 'working...';
  fetch('/restart?what=' + what).then(r => r.text()).then(t => {
    how.textContent = t;
    setTimeout(() => { if (!onPictures) video(); else img.src = '/stream?' + Date.now(); }, 4000);
  }).catch(() => { how.textContent = 'the cabinet did not answer'; });
}

addEventListener('keydown', ev => {
  const k = {ArrowUp:'up',ArrowDown:'down',ArrowLeft:'left',ArrowRight:'right'}[ev.key];
  if (k) { d(k); ev.preventDefault(); return; }
  const n = {z:1,x:2,c:3,v:4,Enter:8,' ':1}[ev.key];
  if (n) { b(n); ev.preventDefault(); }
});
// ?pictures on the address starts in still pictures, which is how that view gets checked
if (location.search.indexOf('pictures') >= 0) pictures(); else video();
if (location.search.indexOf('settings') >= 0) { toggle(); const t = document.getElementById(location.hash.slice(1)); if (t) t.scrollIntoView(); }   // opens the settings, for checking them
</script>
"""

# --- adding a game from the page ---------------------------------------------
# Pick a file on a phone, and it lands in the right folder on the cabinet. The name is
# checked hard, because a name is the one thing here a stranger's file gets to choose:
# no folders in it, nothing but plain characters, and only the kinds of file a game is.
import re
ROMS = "/home/jayrogs/roms"
WHERE = {                       # what the page offers -> the folder it means
    "arcade": "arcade/fbneo", "mame": "mame", "nes": "nes", "snes": "snes",
    "genesis": "genesis", "sms": "sms", "gg": "gg", "gb": "gb", "gba": "gba",
    "tg16": "tg16", "atari2600": "atari2600", "atari7800": "atari7800",
    "lynx": "lynx", "psx": "psx", "music": "music",
}
KINDS = (".zip", ".7z", ".nes", ".sfc", ".smc", ".md", ".gen", ".bin", ".sms", ".gg",
         ".gb", ".gbc", ".gba", ".pce", ".a26", ".a78", ".lnx", ".chd", ".cue",
         ".mp3", ".ogg", ".wav")
BIGGEST = 800 * 1024 * 1024
GOODNAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._()\[\]!&+,'-]{0,120}$")

def take_upload(handler, query):
    to = query.get("to", ["arcade"])[0]
    name = os.path.basename(query.get("name", [""])[0].replace("\\", "/"))
    if to not in WHERE:
        return 400, "that is not a machine I know"
    if not GOODNAME.match(name) or ".." in name:
        return 400, "that file name has characters I will not accept"
    if not name.lower().endswith(KINDS):
        return 400, "that is not a kind of file a game comes as"
    size = int(handler.headers.get("Content-Length", 0))
    if size <= 0 or size > BIGGEST:
        return 400, "the file is empty or too big"
    folder = os.path.join(ROMS, WHERE[to])
    os.makedirs(folder, exist_ok=True)
    part = os.path.join(folder, "." + name + ".part")
    left = size
    with open(part, "wb") as f:
        while left > 0:
            chunk = handler.rfile.read(min(left, 1 << 16))
            if not chunk:
                break
            f.write(chunk)
            left -= len(chunk)
    if left:
        os.remove(part)
        return 400, "the upload stopped part way; nothing was kept"
    os.replace(part, os.path.join(folder, name))
    # let the shelf look again, but never pull it out from under a game in progress
    if not _playing():
        _stop(_pids(SHELF, program="love"))
        return 200, "saved %s (%d KB) - the shelf is looking again" % (name, size // 1024)
    return 200, "saved %s (%d KB) - use SEARCH AGAIN when the game is over" % (name, size // 1024)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send_bytes(self, data, ctype):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        path = urllib.parse.urlparse(self.path)
        if path.path == "/upload":
            try:
                code, said = take_upload(self, urllib.parse.parse_qs(path.query))
            except Exception as ex:
                code, said = 500, "that did not work: " + str(ex)[:80]
            body = said.encode()
            self.send_response(code)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path.path != "/whep":
            self.send_error(404)
            return
        try:
            n = int(self.headers.get("Content-Length", 0))
            offer = self.rfile.read(n)
            video_until[0] = time.time() + 120
            mark_watching(True)
            _stop(_recorder_pids("/tmp/cabfifo"))
            time.sleep(0.5)
            req = urllib.request.Request("http://127.0.0.1:8889/cab/whep", data=offer,
                                         headers={"Content-Type": "application/sdp"})
            with urllib.request.urlopen(req, timeout=20) as r:
                answer = r.read()
            self.send_response(201)
            self.send_header("Content-Type", "application/sdp")
            self.send_header("Content-Length", str(len(answer)))
            self.end_headers()
            self.wfile.write(answer)
        except Exception as ex:
            self.send_error(503, str(ex)[:120])

    def do_GET(self):
        path = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(path.query)
        if path.path == "/":
            self.send_bytes(PAGE.encode(), "text/html; charset=utf-8")
        elif path.path == "/frame.jpg":
            _watchers[0] += 1
            try:
                data, when = frame(wait_for_new=True)
                if not data:
                    data = grab_once()
                self.send_bytes(data, "image/jpeg")
            except Exception:
                self.send_error(503)
            finally:
                _watchers[0] -= 1
        elif path.path == "/stream":
            video_until[0] = 0.0          # pictures asked for: give the screen back
            mark_watching(False)
            _watchers[0] += 1
            try:
                self.connection.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 24576)
                self.connection.settimeout(8)
            except Exception:
                pass
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=cab")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            last = 0.0
            try:
                while True:
                    data, when = frame(wait_for_new=True)
                    if not data or when == last:
                        continue
                    last = when
                    if video_wanted():
                        break
                    self.wfile.write(b"--cab\r\nContent-Type: image/jpeg\r\n"
                                     b"Content-Length: " + str(len(data)).encode() + b"\r\n\r\n")
                    self.wfile.write(data)
                    self.wfile.write(b"\r\n")
            except Exception:
                pass
            finally:
                _watchers[0] -= 1
        elif path.path == "/press":
            # a request that does not make sense presses NOTHING: falling back to button
            # 1 once opened a game on the real screen from a typo
            try:
                tap(int(q.get("b", ["0"])[0]), int(q.get("ms", ["90"])[0]), int(q.get("p", ["1"])[0]))
            except ValueError:
                pass
            self.send_bytes(b"ok", "text/plain")
        elif path.path == "/push":
            push(q.get("d", ["left"])[0])
            self.send_bytes(b"ok", "text/plain")
        elif path.path == "/soundreport":
            with open("/tmp/cab_soundreport.txt", "a") as f:
                f.write("%s %s %s" % (time.strftime("%H:%M:%S"), self.client_address[0], path.query) + chr(10))
            self.send_bytes(b"ok", "text/plain")
        elif path.path == "/audio.mp3":
            proc = audio_stream()
            self.send_response(200)
            self.send_header("Content-Type", "audio/mpeg")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            try:
                while True:
                    chunk = proc.stdout.read(4096)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
            except Exception:
                pass
            finally:
                proc.kill()
        elif path.path == "/quality":
            want = q.get("level", [""])[0]
            step = q.get("step", [""])[0]
            if want in LEVELS:
                preferred[0] = want
            elif step == "down":            # the video is struggling: one size smaller
                at = ORDER.index(level[0])
                want = ORDER[at + 1] if at + 1 < len(ORDER) else "bottom"
            elif step == "reset":           # a fresh visit starts from the chosen level
                want = preferred[0] if preferred[0] != level[0] else ""
            if want == "bottom":
                self.send_bytes(b"bottom", "text/plain")
                return
            if want in LEVELS:
                level[0] = want
                try:
                    set_video_quality(want)
                except Exception:
                    pass
            self.send_bytes(level[0].encode(), "text/plain")
        elif path.path == "/restart":
            what = q.get("what", ["game"])[0]
            try:
                said = restart(what)
            except Exception as ex:
                said = "that did not work: " + str(ex)[:80]
            self.send_bytes(said.encode(), "text/plain")
        elif path.path == "/what":
            out = subprocess.run(["pgrep", "-a", "love"], capture_output=True).stdout
            out += subprocess.run(["pgrep", "-a", "retroarch"], capture_output=True).stdout
            self.send_bytes(out or b"nothing running", "text/plain")
        else:
            self.send_error(404)

class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

print("the cabinet is on http://0.0.0.0:%d" % PORT, flush=True)
Server(("0.0.0.0", PORT), Handler).serve_forever()
