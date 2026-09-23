PW="${PIPW:?set PIPW to the Pi's sudo password}"
run() { echo "$PW" | sudo -S "$@"; }
cat > /tmp/cabperf.service <<'UNIT'
[Unit]
Description=Let the Pi run at full speed for the cabinet
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > $c; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
run install -m644 /tmp/cabperf.service /etc/systemd/system/cabperf.service
run systemctl daemon-reload
run systemctl enable --now cabperf.service
systemctl is-enabled cabperf.service
