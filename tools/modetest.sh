exec >> /tmp/modetest.log 2>&1
set -x
export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=-all BOX86_NOBANNER=1
export WINEDLLOVERRIDES="mscoree,mshtml=" XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
export BOX86_DYNAREC_BIGBLOCK=3 BOX86_DYNAREC_SAFEFLAGS=0
cd "$HOME/crossy/Crossy Road/CrossyRoad" || exit 1
shot() { XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 grim "$1"; }
try() {
  local name="$1"; shift
  pkill -f 'C:.*Game.exe'; pkill -f wineserver; sleep 4
  /usr/local/bin/box86 /opt/wine/wine-9.0-x86/bin/wine Game.exe "$@" >/dev/null 2>&1 &
  sleep 85
  W=$(DISPLAY=:0 xdotool search --name "Wine Mono" 2>/dev/null | head -1)
  [ -n "$W" ] && DISPLAY=:0 xdotool windowclose "$W" 2>/dev/null
  sleep 10
  shot /tmp/mode_$name.png
  echo "=== $name shot $(date)"
}
try opengl -force-opengl -screen-width 480 -screen-height 640 -screen-fullscreen 0
try default -screen-width 480 -screen-height 640 -screen-fullscreen 0
pkill -f 'C:.*Game.exe'; pkill -f wineserver
echo "=== modes done"
