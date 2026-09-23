pkill -f Game.exe; pkill -f wineserver; sleep 3
export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=err+all BOX86_NOBANNER=1
export WINEDLLOVERRIDES="mscoree,mshtml=" XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
export PATH=/opt/wine/wine-9.0-x86/bin:$PATH
cd "$HOME/crossy/Crossy Road/CrossyRoad" || exit 1
timeout 45 box86 /opt/wine/wine-9.0-x86/bin/wine Game.exe -force-opengl -screen-width 480 -screen-height 640 -screen-fullscreen 0 > /tmp/crun.txt 2>&1
echo "rc=$?"
grep -viE 'fixme' /tmp/crun.txt | tail -15
tail -5 "$HOME/crossy/Crossy Road/CrossyRoad/output_log.txt" 2>/dev/null
