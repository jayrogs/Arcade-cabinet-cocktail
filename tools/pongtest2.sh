export XDG_RUNTIME_DIR=/run/user/1000
echo "shelf only:"
timeout 12 ffmpeg -hide_banner -f pulse -i @DEFAULT_MONITOR@ -t 5 -af volumedetect -f null - 2>&1 | grep -E "mean_volume|max_volume"
export WAYLAND_DISPLAY=wayland-1
(timeout 40 love ~/pong.love >/dev/null 2>&1 &)
sleep 9
echo "shelf + pong:"
timeout 12 ffmpeg -hide_banner -f pulse -i @DEFAULT_MONITOR@ -t 5 -af volumedetect -f null - 2>&1 | grep -E "mean_volume|max_volume"
