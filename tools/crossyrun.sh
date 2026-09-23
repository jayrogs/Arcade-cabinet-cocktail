#!/bin/bash
exec >> /tmp/crossy_run.log 2>&1
set -x
export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=-all BOX86_NOBANNER=1
export XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
export PATH=/opt/wine/wine-9.0-x86/bin:$PATH
cd ~/crossy/"Crossy Road"/CrossyRoad
echo "=== launch $(date)"
timeout 180 box86 /opt/wine/wine-9.0-x86/bin/wine Game.exe -screen-width 720 -screen-height 1000 -screen-fullscreen 0
echo "=== game exited rc=$? $(date)"
