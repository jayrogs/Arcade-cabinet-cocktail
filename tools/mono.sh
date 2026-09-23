exec >> /tmp/mono.log 2>&1
set -x
export WINEPREFIX=$HOME/.wine-crossy WINEDEBUG=-all XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
pkill -f Game.exe; pkill -f wineserver; sleep 3
mkdir -p /opt/wine/mono && cd /opt/wine/mono
curl -fL --retry 3 -o mono.msi https://dl.winehq.org/wine/wine-mono/9.0.0/wine-mono-9.0.0-x86.msi
ls -la mono.msi
timeout 900 /usr/local/bin/box86 /opt/wine/wine-9.0-x86/bin/wine msiexec /i /opt/wine/mono/mono.msi /qn
echo "install rc=$?"
ls $WINEPREFIX/drive_c/windows/mono 2>/dev/null
pkill -f wineserver
echo "=== mono done $(date)"
