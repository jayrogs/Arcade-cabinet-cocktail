#!/bin/bash
exec >> /tmp/wine.log 2>&1
set -x
PW="${PIPW:?set PIPW to the Pi's sudo password}"
run() { echo "$PW" | sudo -S "$@"; }
for p in libfreetype6 libpng16-16t64 libfontconfig1 libxext6 libxrender1 libxcursor1 \
         libxi6 libxrandr2 libxinerama1 libxcomposite1 libxfixes3 libgnutls30t64 \
         libpulse0 libopenal1 libglu1-mesa libgl1-mesa-dri libvulkan1 libxxf86vm1; do
  run apt-get install -y "$p:armhf" || echo "SKIPPED $p"
done
echo "=== wine libs2 done $(date)"
