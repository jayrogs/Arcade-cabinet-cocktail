exec >> /tmp/prefix.log 2>&1
set -x
export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=-all XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
pkill -f Game.exe; /opt/wine/wine-9.0-x86/bin/wineserver -k; sleep 4
# with mono out of the way, building the folder takes minutes instead of hours; the
# question it asks at start-up is closed by the launcher anyway
mv /opt/wine/wine-9.0-x86/share/wine/mono /opt/wine/mono-parked 2>/dev/null
rm -rf $WINEPREFIX
timeout 900 /usr/local/bin/box86 /opt/wine/wine-9.0-x86/bin/wine wineboot -u
echo "wineboot rc=$? $(date)"
ls $WINEPREFIX/drive_c/windows/system32/kernel32.dll && echo PREFIX_OK
/opt/wine/wine-9.0-x86/bin/wineserver -k
echo "=== prefix done $(date)"
