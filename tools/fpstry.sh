exec >> /tmp/fps_try.log 2>&1
export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=-all BOX86_NOBANNER=1
export WINEDLLOVERRIDES="mscoree,mshtml="
export XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0 WAYLAND_DISPLAY=wayland-0
export PATH=/opt/wine/wine-9.0-x86/bin:$PATH
cd "$HOME/crossy/Crossy Road/CrossyRoad" || exit 1
try() {
  local name="$1"; shift
  pkill -f Game.exe; sleep 3
  box86 /opt/wine/wine-9.0-x86/bin/wine Game.exe "$@" >/dev/null 2>&1 &
  sleep 55
  ( for i in $(seq 1 20); do wtype " "; wtype -k Up; sleep 0.4; done ) >/dev/null 2>&1 &
  timeout 40 ffmpeg -v error -rtsp_transport tcp -i rtsp://127.0.0.1:8554/cab -t 8 -c copy -y /tmp/f_$name.mkv
  echo "=== $name done $(date)"
}
try d3d11 -screen-width 480 -screen-height 640 -screen-fullscreen 0
try opengl -force-opengl -screen-width 480 -screen-height 640 -screen-fullscreen 0
try d3d9 -force-d3d9 -screen-width 480 -screen-height 640 -screen-fullscreen 0
echo "=== all done"
