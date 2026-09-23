#!/bin/bash
# The cabinet. Shows the menu, runs whatever it picks, then shows the menu again.
#   ROTATION: turn the picture to match how the monitor is mounted.
#             normal / 90 / 180 / 270  -- change this one line at the cab.
#   MODE:     the monitor shows all of 1024x768 and only the middle of 1280x1024.
ROTATION=90
MODE=1024x768
LOG=/tmp/cab.log

exec 9>/tmp/cab.lock
flock -n 9 || { echo "$(date) already running" >> $LOG; exit 0; }
# its own pid, so it can be stopped without a pattern match that would catch the
# shell asking for the kill (that mistake has cost two evenings already)
echo $$ > /tmp/cab.pid
trap 'rm -f /tmp/cab.pid' EXIT

export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=wayland-0

# wait for the screen: launching into a blanked display leaves the window nowhere
for i in $(seq 1 30); do
  wlr-randr 2>/dev/null | grep -q "Enabled: yes" && break
  sleep 1
done
OUT=$(wlr-randr 2>/dev/null | awk '/^[A-Z]/{print $1; exit}')
[ -n "$OUT" ] && wlr-randr --output "$OUT" --mode "$MODE" --transform "$ROTATION" 2>/dev/null
wlopm --on '*' 2>/dev/null
sleep 2

rm -f /tmp/cab_stop
while true; do
  rm -f /tmp/cab_launch
  love /home/jayrogs/cabmenu.love >> $LOG 2>&1
  rc=$?
  if [ -f /tmp/cab_launch ]; then
    echo "$(date) running: $(cat /tmp/cab_launch)" >> $LOG
    t0=$(date +%s)
    sh /tmp/cab_launch >> $LOG 2>&1
    echo "$(date) game finished rc=$? after $(( $(date +%s) - t0 ))s" >> $LOG
    # a game that quits inside five seconds never really started: an arcade file
    # built for the other emulator looks exactly like this. Try the other one.
    if [ $(( $(date +%s) - t0 )) -lt 5 ] && [ -f /tmp/cab_launch2 ]; then
      echo "$(date) second try: $(cat /tmp/cab_launch2)" >> $LOG
      t1=$(date +%s)
      sh /tmp/cab_launch2 >> $LOG 2>&1
      echo "$(date) second try finished after $(( $(date +%s) - t1 ))s" >> $LOG
      if [ $(( $(date +%s) - t1 )) -lt 5 ]; then
        echo "that game would not start - wrong files for this emulator" > /tmp/cab_message
      fi
    elif [ $(( $(date +%s) - t0 )) -lt 5 ]; then
      echo "that game would not start" > /tmp/cab_message
    fi
    rm -f /tmp/cab_launch /tmp/cab_launch2
    sleep 1
  else
    echo "$(date) menu exited rc=$rc" >> $LOG
    # Only a deliberate stop ends this. Judging it by the exit number meant that
    # killing the shelf for any reason at all took the whole cabinet dark.
    [ -f /tmp/cab_stop ] && break
    sleep 2                    # crashed: come back
  fi
done
