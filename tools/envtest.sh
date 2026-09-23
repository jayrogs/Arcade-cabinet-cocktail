cd "$HOME/crossy/Crossy Road/CrossyRoad" || exit 9
export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=-all BOX86_NOBANNER=1
export WINEDLLOVERRIDES="mscoree,mshtml=" XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
export PATH=/opt/wine/wine-9.0-x86/bin:/usr/local/bin:/usr/bin:/bin
run() {
  local label="$1"; shift
  ( "$@" /usr/local/bin/box86 /opt/wine/wine-9.0-x86/bin/wine Game.exe -screen-fullscreen 0 \
      -screen-width 400 -screen-height 520 > /tmp/env_$label.txt 2>&1 & )
  sleep 25
  local n=$(ps -eo args --no-headers | grep -ci "[G]ame.exe")
  echo "$label alive=$n  $(tail -1 /tmp/env_$label.txt | cut -c1-70)"
  pkill -f Game.exe; /opt/wine/wine-9.0-x86/bin/wineserver -k 2>/dev/null; sleep 3
}
run withall env
run bare env -i HOME=$HOME PATH=/opt/wine/wine-9.0-x86/bin:/usr/local/bin:/usr/bin:/bin WINEPREFIX=$HOME/.wine-crossy DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 WINEDEBUG=-all
run bareuser env -i HOME=$HOME USER=jayrogs LOGNAME=jayrogs PATH=/opt/wine/wine-9.0-x86/bin:/usr/local/bin:/usr/bin:/bin WINEPREFIX=$HOME/.wine-crossy DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 WINEDEBUG=-all
