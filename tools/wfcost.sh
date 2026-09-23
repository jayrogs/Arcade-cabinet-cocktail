export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0
cost() {
  local name="$1"; shift
  pkill -x wf-recorder; sleep 2
  wf-recorder -y -D -r 20 "$@" -f /tmp/w_$name.mkv >/dev/null 2>&1 &
  sleep 6
  echo "$name: $(top -b -n1 -o %CPU | grep wf-reco | head -1 | awk '{print $9}')% cpu"
  sleep 2
  pkill -x wf-recorder; sleep 2
}
cost turn_scale -x yuv420p -F transpose=1,scale=576:768 -c h264_v4l2m2m -p b=800k
cost scale_only -x yuv420p -F scale=768:576 -c h264_v4l2m2m -p b=800k
cost plain -x yuv420p -c h264_v4l2m2m -p b=800k
cost plain_nofmt -c h264_v4l2m2m -p b=800k
