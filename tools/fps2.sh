export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0
( for i in $(seq 1 30); do wtype " "; wtype -k Up; sleep 0.4; done ) >/dev/null 2>&1 &
timeout 45 ffmpeg -v error -rtsp_transport tcp -i rtsp://127.0.0.1:8554/cab -t 10 -c copy -y /tmp/feed.mkv
ls -la /tmp/feed.mkv
