export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0
( for i in $(seq 1 16); do wtype " "; wtype -k Up; sleep 0.5; done ) >/dev/null 2>&1 &
S=$(date +%s.%N)
for i in $(seq 1 60); do grim -t ppm - 2>/dev/null | md5sum | cut -c1-8; done > /tmp/hashes.txt
E=$(date +%s.%N)
echo "grabs: $(wc -l < /tmp/hashes.txt)  distinct: $(sort -u /tmp/hashes.txt | wc -l)  seconds: $(echo "$E - $S" | bc)"
