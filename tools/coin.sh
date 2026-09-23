exec >> /tmp/crossy.log 2>&1
set -x
kill 117425 2>/dev/null
export XDG_RUNTIME_DIR=/run/user/1000
curl -s -m5 "http://127.0.0.1:8080/press?b=8" >/dev/null
sleep 3
WAYLAND_DISPLAY=wayland-0 grim /tmp/c1.png
curl -s -m5 "http://127.0.0.1:8080/press?b=8" >/dev/null
sleep 4
WAYLAND_DISPLAY=wayland-0 grim /tmp/c2.png
echo "=== coin test done"
