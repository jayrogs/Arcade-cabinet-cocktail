#!/bin/bash
exec >> /tmp/wine.log 2>&1
set -x
echo "=== wine libs $(date)"
PW="${PIPW:?set PIPW to the Pi's sudo password}"
run() { echo "$PW" | sudo -S "$@"; }
run apt-get install -y libfreetype6:armhf libpng16-16t64:armhf libfontconfig1:armhf \
  libxext6:armhf libxrender1:armhf libxcursor1:armhf libxi6:armhf libxrandr2:armhf \
  libxinerama1:armhf libxcomposite1:armhf libxfixes3:armhf libgnutls30t64:armhf \
  libpulse0:armhf libopenal1:armhf libglu1-mesa:armhf libgl1-mesa-dri:armhf \
  libvulkan1:armhf libxxf86vm6:armhf
echo "=== wine libs done $(date)"
