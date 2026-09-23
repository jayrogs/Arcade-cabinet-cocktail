exec >> /tmp/mono.log 2>&1
set -x
export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=-all XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
pkill -f 'wine' ; pkill -f Game.exe; sleep 5
rm -rf $WINEPREFIX
echo "=== fresh prefix, installing mono $(date)"
timeout 3000 /usr/local/bin/box86 /opt/wine/wine-9.0-x86/bin/wine wineboot -u
echo "wineboot rc=$? $(date)"
ls $WINEPREFIX/drive_c/windows/mono 2>/dev/null || echo "NO MONO FOLDER"
pkill -f wine
echo "=== mono install done $(date)"
