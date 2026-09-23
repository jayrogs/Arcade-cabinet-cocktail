#!/bin/bash
# Sets up the stack that can run a 32-bit Windows game on this ARM Pi:
# box86 turns x86 instructions into ARM ones, and Wine makes Windows calls work on Linux.
set -x
exec >> /tmp/box86.log 2>&1
echo "=== started $(date)"
PW="${PIPW:?set PIPW to the Pi's sudo password}"
run() { echo "$PW" | sudo -S "$@"; }
run dpkg --add-architecture armhf
curl -fsSL https://ryanfortner.github.io/box86-debs/KEY.gpg | gpg --dearmour -o /tmp/box86.gpg
run install -m644 /tmp/box86.gpg /usr/share/keyrings/box86-debs-archive-keyring.gpg
curl -fsSL https://ryanfortner.github.io/box86-debs/box86.list | run tee /etc/apt/sources.list.d/box86.list
run apt-get update
run apt-get install -y box86-rpi4arm64
box86 --version
echo "=== box86 done $(date)"
