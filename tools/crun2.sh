exec > /tmp/crun2.txt 2>&1
set -x
export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=err+all BOX86_NOBANNER=1
export WINEDLLOVERRIDES="mscoree,mshtml=" XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
export BOX86_DYNAREC_BIGBLOCK=3 BOX86_DYNAREC_SAFEFLAGS=0
pkill -f Game.exe; pkill -f wineserver; sleep 4
cd "$HOME/crossy/Crossy Road/CrossyRoad" || exit 1
timeout 200 /usr/local/bin/box86 /opt/wine/wine-9.0-x86/bin/wine Game.exe -force-opengl -screen-width 480 -screen-height 640 -screen-fullscreen 0
echo "EXIT rc=$?"
