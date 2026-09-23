exec >> /tmp/mono.log 2>&1
set -x
pkill -f Game.exe; pkill -f wineserver; sleep 3
mkdir -p /opt/wine/wine-9.0-x86/share/wine/mono
cd /opt/wine/wine-9.0-x86/share/wine/mono
curl -fL --retry 3 -o mono.tar.xz https://dl.winehq.org/wine/wine-mono/9.0.0/wine-mono-9.0.0-x86.tar.xz
ls -la mono.tar.xz
tar xf mono.tar.xz && rm -f mono.tar.xz
ls
echo "=== mono2 done $(date)"
