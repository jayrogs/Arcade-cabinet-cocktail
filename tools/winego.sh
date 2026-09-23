#!/bin/bash
exec >> /tmp/wine.log 2>&1
set -x
echo "=== boot2 $(date)"
export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=-all BOX86_NOBANNER=1
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 DISPLAY=:0
export PATH=/opt/wine/wine-9.0-x86/bin:$PATH
timeout 900 box86 /opt/wine/wine-9.0-x86/bin/wineboot -u
echo "=== wineboot rc=$? $(date)"
ls $WINEPREFIX/drive_c
# unpack the game itself
mkdir -p ~/crossy
cd ~/crossy
unzip -q -o ~/roms/arcade/fbneo/"Crossy Road.zip" 2>/dev/null
ls ~/crossy/"Crossy Road"/CrossyRoad | head
echo "=== unpacked $(date)"
