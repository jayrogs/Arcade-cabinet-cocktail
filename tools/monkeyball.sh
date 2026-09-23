#!/bin/bash
# Starts Monkey Ball (Sega NAOMI, played by Flycast built for OpenGL ES).
#
# Flycast's threaded rendering is what makes it smooth (26-45 frames a second without it),
# but now and then it locks up while starting: a black screen with the processor almost
# idle. A healthy start runs the processor hard straight away, so a start that is still
# idle after 15 seconds is closed and tried again, up to three times.
#
# The game's saved memory is removed first: written while the game is being closed, that
# copy boots to a black screen next time (the cost: high scores do not carry over).
{
  R=/home/jayrogs/.config/retroarch
  for try in 1 2 3; do
    rm -f "$R/saves/Flycast/reicast/monkeyba.zip.nvmem"
    retroarch --appendconfig="$R/flycast.cfg|$R/monkeyball.cfg" \
      -L "$R/cores/flycast_libretro.so" /home/jayrogs/roms/naomi/monkeyba.zip -f &
    RA=$!
    sleep 15
    kill -0 $RA 2>/dev/null || exit 0          # closed already: nothing to watch
    busy=$(ps -o pcpu= -p $RA | tr -d ' ' | cut -d. -f1)
    if [ "${busy:-0}" -ge 15 ]; then
      wait $RA
      exit 0
    fi
    echo "$(date) Monkey Ball froze while starting (processor ${busy}%), try $try" >> /tmp/cab.log
    kill -9 $RA 2>/dev/null
    wait $RA 2>/dev/null
    sleep 2
  done
  exit 1
}
