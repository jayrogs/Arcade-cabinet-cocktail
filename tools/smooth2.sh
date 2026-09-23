exec >> /tmp/crossy.log 2>&1
set -x
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0
( for i in $(seq 1 20); do wtype " "; wtype -k Up; sleep 0.5; done ) &
timeout 12 wf-recorder -y -D -r 30 -c h264_v4l2m2m -p b=4000k -f /tmp/smooth2.mkv
echo "=== recorded2 $(date)"
vcgencmd measure_clock arm; vcgencmd get_throttled
