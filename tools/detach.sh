export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=-all XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
cd "$HOME/crossy/Crossy Road/CrossyRoad" || exit 1
pkill -f Game.exe; /opt/wine/wine-9.0-x86/bin/wineserver -k; sleep 4
echo "--- detached, stdin from terminal"
setsid sh -c '/usr/local/bin/box86 /opt/wine/wine-9.0-x86/bin/wine Game.exe -screen-width 700 -screen-height 980 -screen-fullscreen 0 > /tmp/d1.log 2>&1' &
sleep 45
echo "alive=$(ps -eo args --no-headers | grep -ci '[G]ame.exe')"
tail -3 /tmp/d1.log | cut -c1-100
pkill -f Game.exe; /opt/wine/wine-9.0-x86/bin/wineserver -k; sleep 4
echo "--- detached, stdin from /dev/null"
setsid sh -c '/usr/local/bin/box86 /opt/wine/wine-9.0-x86/bin/wine Game.exe -screen-width 700 -screen-height 980 -screen-fullscreen 0 > /tmp/d2.log 2>&1' < /dev/null &
sleep 45
echo "alive=$(ps -eo args --no-headers | grep -ci '[G]ame.exe')"
tail -3 /tmp/d2.log | cut -c1-100
