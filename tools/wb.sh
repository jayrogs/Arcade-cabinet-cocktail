exec >> /tmp/wb.log 2>&1
set -x
export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=-all XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
pkill -f wineserver; sleep 2
timeout 900 /usr/local/bin/box86 /opt/wine/wine-9.0-x86/bin/wine wineboot -u
echo "wineboot rc=$?"
ls $WINEPREFIX/drive_c/windows/mono 2>/dev/null
pkill -f wineserver
echo "=== wb done $(date)"
