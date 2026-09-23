exec >> /tmp/fps_try.log 2>&1
export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=-all BOX86_NOBANNER=1
export WINEDLLOVERRIDES="mscoree,mshtml="
export XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0 WAYLAND_DISPLAY=wayland-0
export PATH=/opt/wine/wine-9.0-x86/bin:$PATH
# box86 runs code faster when it may keep bigger blocks and skip strict flag checks
export BOX86_DYNAREC_BIGBLOCK=3 BOX86_DYNAREC_SAFEFLAGS=0 BOX86_DYNAREC_FASTNAN=1 \
       BOX86_DYNAREC_FASTROUND=1 BOX86_DYNAREC_STRONGMEM=0 BOX86_DYNAREC_CALLRET=1
curl -s -m5 "http://127.0.0.1:8080/quality?level=high" >/dev/null   # capture at 25 a second
cd "$HOME/crossy/Crossy Road/CrossyRoad" || exit 1
run() {
  local name="$1"; shift
  pkill -f Game.exe; sleep 3
  box86 /opt/wine/wine-9.0-x86/bin/wine Game.exe -force-opengl "$@" >/dev/null 2>&1 &
  sleep 55
  ( for i in $(seq 1 24); do wtype " "; wtype -k Up; sleep 0.4; done ) >/dev/null 2>&1 &
  timeout 40 ffmpeg -v error -rtsp_transport tcp -i rtsp://127.0.0.1:8554/cab -t 8 -c copy -y /tmp/t_$name.mkv
  echo "=== $name done $(date)"
}
run tuned480 -screen-width 480 -screen-height 640 -screen-fullscreen 0
run tuned360 -screen-width 360 -screen-height 480 -screen-fullscreen 0
echo "=== tune done"
