import os, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import cab
from PIL import Image
c = cab.connect()
print("on:", c.cab_host, "|", cab.run(c, "pgrep -a love || pgrep -a retroarch || echo NOTHING RUNNING"))
cab.run(c, "grim /tmp/shot.png")
out = os.environ["TEMP"] + r"\picab"
s = c.open_sftp(); s.get("/tmp/shot.png", out + r"\pi_shot.png"); s.close()
c.close()
im = Image.open(out + r"\pi_shot.png").convert("RGB")
im.resize((im.width * 2 // 3, im.height * 2 // 3), Image.NEAREST).save(out + r"\pi_shot_small.png")
print("captured", im.size)
