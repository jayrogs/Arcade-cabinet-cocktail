#!/usr/bin/env python3
"""Pull the frames filmed into /tmp/boot on the cabinet and lay them out, with times."""
import io, sys
from PIL import Image, ImageDraw
import cab

out = sys.argv[1]
c = cab.connect()
s = c.open_sftp()
times = s.open('/tmp/boot/times').read().decode().split()
t = {times[i]: float(times[i + 1]) for i in range(0, len(times), 2)}
names = sorted(x for x in s.listdir('/tmp/boot') if x.endswith('.png'))
cols = 8
rows = (len(names) + cols - 1) // cols
sheet = Image.new('RGB', (cols * 120, rows * 175), (40, 40, 40))
for k, n in enumerate(names):
    im = Image.open(io.BytesIO(s.open('/tmp/boot/' + n).read())).convert('RGB').resize((115, 153))
    x, y = (k % cols) * 120, (k // cols) * 175
    sheet.paste(im, (x, y))
    ImageDraw.Draw(sheet).text((x + 2, y + 156), '%.1fs' % t[n[:-4]], fill=(255, 255, 0))
sheet.save(out)
s.close(); c.close()
print(len(names), 'frames')
