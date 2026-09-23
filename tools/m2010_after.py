#!/usr/bin/env python3
"""After the MAME 2010 queue: every game it could not start is matched by its chips to the
name MAME 2010 knows it by, copied under that name into arcade/mamesets2010, and run again."""
import json, os, re, shutil, subprocess, time
HOME = os.path.expanduser("~")
LOG = HOME + "/flip_raw/m2010_log.txt"
while subprocess.run(["pgrep", "-f", "[m]ame2010_table.py --all 1942"], stdout=subprocess.DEVNULL).returncode == 0:
    time.sleep(30)
failed = sorted({l.split()[3] for l in open(LOG) if l.split()[1:3] == ["NOT", "RUN"]})
out = subprocess.run(["python3", HOME + "/mame2010_match.py"] + failed, capture_output=True, text=True).stdout
matches = json.loads(out)
todo, names = [], {}
for g, m in matches.items():
    real = (m.get("matches") or [None])[0]
    if real and real != g:
        src = subprocess.run(["find", HOME + "/roms/arcade", "-name", g + ".zip", "-not", "-path", "*mamesets*"],
                             capture_output=True, text=True).stdout.split()
        if src:
            shutil.copy(src[0], HOME + "/roms/arcade/mamesets2010/%s.zip" % real)
            todo.append(real); names[real] = g
json.dump(names, open(HOME + "/flip_raw/m2010_renamed.json", "w"))
with open(LOG, "a") as f:
    f.write(time.strftime("%H:%M:%S ") + "RENAMED  " + " ".join("%s=%s" % (names[r], r) for r in todo) + chr(10))
subprocess.run(["python3", HOME + "/mame2010_table.py", "--all"] + todo, env=dict(os.environ, MT_PORT="57000"))
