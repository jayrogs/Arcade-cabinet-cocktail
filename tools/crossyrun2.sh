#!/bin/bash
exec >> /tmp/crossy_run.log 2>&1
set -x
pkill -f Game.exe; pkill -f wineserver; sleep 2
export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=-all BOX86_NOBANNER=1
export WINEDLLOVERRIDES="mscoree,mshtml="
export XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
export PATH=/opt/wine/wine-9.0-x86/bin:$PATH
cd ~/crossy/"Crossy Road"/CrossyRoad
echo "=== launch2 $(date)"
timeout 600 box86 /opt/wine/wine-9.0-x86/bin/wine Game.exe -screen-width 700 -screen-height 980 &
sleep 90
XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 grim /tmp/cr2.png
sleep 40
XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 grim /tmp/cr3.png
echo "=== shots taken $(date)"
