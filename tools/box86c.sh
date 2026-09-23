#!/bin/bash
set -x
exec >> /tmp/box86.log 2>&1
echo "=== libs $(date)"
PW="${PIPW:?set PIPW to the Pi's sudo password}"
run() { echo "$PW" | sudo -S "$@"; }
run apt-get install -y libc6:armhf libstdc++6:armhf zlib1g:armhf libgl1:armhf libx11-6:armhf libasound2t64:armhf
box86 --version
echo "=== libs done $(date)"
