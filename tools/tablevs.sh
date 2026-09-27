#!/bin/bash
# FACE TO FACE split games: the game runs as usual, and tableflip.py (beside it) turns player
# 2's half round only while player 2 is playing. RetroArch listens for tableflip's command on
# 127.0.0.1:55355 only while one of these games is running (tablevs.cfg).
#     sh tablevs.sh retroarch -L <core> <game> -f
#     sh tablevs.sh naomi <name>        (a NAOMI game, through naomi.sh)
{
  CFG=/home/jayrogs/.config/retroarch/tablevs.cfg
  python3 /home/jayrogs/tableflip.py >> /tmp/cab.log 2>&1 &
  W=$!
  if [ "$1" = naomi ]; then
    APPEND_CFG=$CFG sh /home/jayrogs/naomi.sh "$2"
  else
    # plain sh (the launcher runs this with sh): no ${@:2}, which sh cannot read
    PROG=$1
    shift
    "$PROG" --appendconfig="$CFG" "$@"
  fi
  kill $W 2>/dev/null
  exit 0
}
