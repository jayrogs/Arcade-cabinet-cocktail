#!/bin/bash
# Starts a Sega NAOMI game with the same Flycast as Monkey Ball and Crazy Taxi:
#     sh naomi.sh sgtetris [more retroarch options, e.g. --set-shader ...]
# plays ~/roms/naomi/sgtetris.zip with flycast.cfg and naomi.cfg, plus
# ~/.config/retroarch/<name>.cfg if there is one (a game's own controls).
#
# A start that locks up (black screen, processor almost idle after 15 s) is closed and
# tried again, up to three times, as monkeyball.sh does.
{
  NAME=$1
  shift                                         # anything after the name goes to retroarch
  R=/home/jayrogs/.config/retroarch
  CFG="$R/flycast.cfg|$R/naomi.cfg"
  [ -f "$R/$NAME.cfg" ] && CFG="$CFG|$R/$NAME.cfg"
  for try in 1 2 3; do
    retroarch --appendconfig="$CFG" "$@" \
      -L "$R/cores/flycast_libretro.so" "/home/jayrogs/roms/naomi/$NAME.zip" -f &
    RA=$!
    sleep 15
    kill -0 $RA 2>/dev/null || exit 0          # closed already: nothing to watch
    busy=$(ps -o pcpu= -p $RA | tr -d ' ' | cut -d. -f1)
    if [ "${busy:-0}" -ge 15 ]; then
      wait $RA
      exit 0
    fi
    echo "$(date) $NAME froze while starting (processor ${busy}%), try $try" >> /tmp/cab.log
    kill -9 $RA 2>/dev/null
    wait $RA 2>/dev/null
    sleep 2
  done
  exit 1
}
