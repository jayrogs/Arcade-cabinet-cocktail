export XDG_RUNTIME_DIR=/run/user/1000
curl -s -m5 "http://127.0.0.1:8080/quality?level=medium" >/dev/null
sleep 2
timeout 35 ffmpeg -v error -rtsp_transport tcp -i rtsp://127.0.0.1:8554/cab -t 10 -c copy -y /tmp/fc2.mkv &
sleep 7
top -b -n1 -o %CPU | grep -E 'wf-reco|ffmpeg' | head -2 | awk '{print $12, $9"% cpu"}'
wait
ls -la /tmp/fc2.mkv
