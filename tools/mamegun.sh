#!/bin/bash
# Starts a light-gun game in full MAME:  sh mamegun.sh hotdo
# MAME writes its settings back when a game closes, so a change made while the game was running
# was lost (player 2's crosshair came back on). The game's settings (~/table_cfg/<name>.cfg:
# only player 1's crosshair shown) are put back before every start.
{
  NAME=$1
  CFG=/home/jayrogs/.config/retroarch/saves/MAME/mame/cfg
  [ -f "/home/jayrogs/table_cfg/$NAME.cfg" ] && cp "/home/jayrogs/table_cfg/$NAME.cfg" "$CFG/$NAME.cfg"
  exec retroarch -L /home/jayrogs/.config/retroarch/cores/mame_libretro.so "/home/jayrogs/roms/mame/$NAME.zip" -f
}
