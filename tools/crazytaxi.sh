#!/bin/bash
# Starts Crazy Taxi (Sega NAOMI, 1999), played by the same Flycast as Monkey Ball.
#
# Like Monkey Ball, a start can now and then lock up (a black screen with the processor
# almost idle), so a start still idle after 15 seconds is closed and tried again, up to
# three times. Its saved memory is kept (high scores carry over); if a start ever boots
# black every time, remove saves/Flycast/reicast/crzytaxi.zip.nvmem as monkeyball.sh does.
#
# crazytaxi.cfg gives the stick to the steering and buttons 1 / 2 to the pedals.
{
  R=/home/jayrogs/.config/retroarch
  for try in 1 2 3; do
    retroarch --appendconfig="$R/flycast.cfg|$R/crazytaxi.cfg" \
      -L "$R/cores/flycast_libretro.so" /home/jayrogs/roms/naomi/crzytaxi.zip -f &
    RA=$!
    sleep 15
    kill -0 $RA 2>/dev/null || exit 0          # closed already: nothing to watch
    busy=$(ps -o pcpu= -p $RA | tr -d ' ' | cut -d. -f1)
    if [ "${busy:-0}" -ge 15 ]; then
      wait $RA
      exit 0
    fi
    echo "$(date) Crazy Taxi froze while starting (processor ${busy}%), try $try" >> /tmp/cab.log
    kill -9 $RA 2>/dev/null
    wait $RA 2>/dev/null
    sleep 2
  done
  exit 1
}
