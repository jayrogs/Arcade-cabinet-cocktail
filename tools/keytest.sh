exec >> /tmp/crossy_run.log 2>&1
set -x
PW="${PIPW:?set PIPW to the Pi's sudo password}"
echo "$PW" | sudo -S apt-get install -y wtype xdotool 2>&1 | tail -2
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DISPLAY=:0
which wtype xdotool
wtype c 2>&1 | head -2
sleep 3
grim /tmp/cr_key1.png
xdotool key c 2>&1 | head -2
sleep 3
grim /tmp/cr_key2.png
echo "=== key test done"
