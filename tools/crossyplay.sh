#!/bin/bash
exec >> /tmp/crossy_run.log 2>&1
set -x
export XDG_RUNTIME_DIR=/run/user/1000
setsid nohup python3 ~/crossy_keys.py > /tmp/crossy_keys.log 2>&1 < /dev/null &
sleep 3
curl -s -m5 "http://127.0.0.1:8080/press?b=8" >/dev/null     # coin, player 1
sleep 4
WAYLAND_DISPLAY=wayland-0 grim /tmp/cr_coin.png
for i in 1 2 3 4 5 6; do curl -s -m5 "http://127.0.0.1:8080/press?b=1" >/dev/null; sleep 0.8; done
WAYLAND_DISPLAY=wayland-0 grim /tmp/cr_play.png
echo "=== play shots $(date)"
