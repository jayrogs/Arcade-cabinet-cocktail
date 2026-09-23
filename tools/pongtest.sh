luac -p /tmp/pong_main.lua && cp /tmp/pong.love ~/pong.love && echo INSTALLED
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-1
(timeout 30 love ~/pong.love >/dev/null 2>&1 &)
sleep 8
timeout 12 ffmpeg -hide_banner -f pulse -i alsa_output.platform-fe00b840.mailbox.stereo-fallback.monitor -t 6 -af volumedetect -f null - 2>&1 | grep -E "mean_volume|max_volume"
