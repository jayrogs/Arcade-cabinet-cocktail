#!/bin/bash
set -x
exec >> /tmp/box86.log 2>&1
echo "=== retry $(date)"
PW="${PIPW:?set PIPW to the Pi's sudo password}"
run() { echo "$PW" | sudo -S "$@"; }
printf 'deb [signed-by=/usr/share/keyrings/box86-debs-archive-keyring.gpg] https://ryanfortner.github.io/box86-debs/debian ./\n' > /tmp/box86.list
run install -m644 /tmp/box86.list /etc/apt/sources.list.d/box86.list
cat /etc/apt/sources.list.d/box86.list
run apt-get update
run apt-get install -y box86-rpi4arm64
box86 --version
echo "=== done $(date)"
