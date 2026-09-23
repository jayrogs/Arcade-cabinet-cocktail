#!/bin/bash
exec >> /tmp/wine.log 2>&1
set -x
echo "=== first run $(date)"
export WINEPREFIX=$HOME/.wine-crossy
export WINEDEBUG=-all
export BOX86_NOBANNER=1
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-1
export PATH=/opt/wine/wine-9.0-x86/bin:$PATH
timeout 300 box86 /opt/wine/wine-9.0-x86/bin/wine --version
timeout 600 box86 /opt/wine/wine-9.0-x86/bin/wineboot -u
echo "=== wineboot rc=$? $(date)"
ls $WINEPREFIX/drive_c 2>/dev/null
