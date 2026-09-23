#!/bin/bash
set -x
exec >> /tmp/wine.log 2>&1
echo "=== wine $(date)"
cd /opt 2>/dev/null || cd ~
PW="${PIPW:?set PIPW to the Pi's sudo password}"
run() { echo "$PW" | sudo -S "$@"; }
run mkdir -p /opt/wine
run chown jayrogs /opt/wine
cd /opt/wine
# a plain 32-bit Wine build: box86 runs it, and it runs the Windows game
URL=https://github.com/Kron4ek/Wine-Builds/releases/download/9.0/wine-9.0-x86.tar.xz
curl -fL --retry 3 -o wine.tar.xz "$URL"
ls -la wine.tar.xz
tar xf wine.tar.xz
ls
echo "=== wine unpacked $(date)"
