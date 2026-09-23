exec >> /tmp/crossy.log 2>&1
set -x
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DISPLAY=:0
wtype c; sleep 2; wtype c; sleep 3
WAYLAND_DISPLAY=wayland-0 grim /tmp/k1.png
xdotool search --class -- "." 2>/dev/null | head -5
W=$(xdotool search --name "Game" | head -1)
echo "window=$W"
xdotool windowactivate $W 2>&1 | head -2
xdotool key --window $W c 2>&1 | head -2
sleep 3
WAYLAND_DISPLAY=wayland-0 grim /tmp/k2.png
echo "=== keytest2 done"
