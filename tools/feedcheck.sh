export XDG_RUNTIME_DIR=/run/user/1000
timeout 30 ffmpeg -v error -rtsp_transport tcp -i rtsp://127.0.0.1:8554/cab -t 10 -c copy -y /tmp/fc.mkv &
sleep 6
echo "--- while the feed runs:"
top -b -n1 -o %CPU | sed -n '7,12p' | cut -c1-80
pgrep -af '[w]f-recorder' | cut -c1-150
wait
ls -la /tmp/fc.mkv
