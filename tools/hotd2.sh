#!/bin/bash
# The House of the Dead 2 (NAOMI): naomi.sh as for the other NAOMI games (it adds
# ~/.config/retroarch/hotd2.cfg by itself), with gunstick.py beside it: a pretend controller
# whose analog stick is the crosshair, moved by the real stick. gunstick.py writes down which
# controller number it got (/tmp/gunstick_pad.cfg), and RetroArch is told that is player 1.
# Needs roms/naomi/hotd2.zip and hod2bios.zip.
{
  PAD=/tmp/gunstick_pad.cfg
  rm -f $PAD
  python3 /home/jayrogs/gunstick.py >> /tmp/cab.log 2>&1 &
  W=$!
  # RetroArch must find the pretend controller already there
  for i in 1 2 3 4 5 6 7 8 9 10; do [ -f $PAD ] && break; sleep 0.5; done
  APPEND_CFG="${APPEND_CFG:+$APPEND_CFG|}$PAD" sh /home/jayrogs/naomi.sh hotd2 "$@"
  kill $W 2>/dev/null
  exit 0
}
