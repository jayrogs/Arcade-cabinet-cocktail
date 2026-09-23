exec >> /tmp/crossy.log 2>&1
set -x
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0
wtype c; sleep 1; wtype v; sleep 6          # both players in
( for i in $(seq 1 24); do wtype " "; wtype -k Up; sleep 0.45; done ) &
sleep 2
timeout 14 wf-recorder -y -D -r 60 -c libx264 -p preset=ultrafast -p crf=20 -f /tmp/smooth.mkv
echo "=== recorded $(date)"
