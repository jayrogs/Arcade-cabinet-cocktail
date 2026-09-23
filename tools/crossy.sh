#!/bin/bash
exec 2>>/tmp/crossy_trace.txt
set -x
# Runs the real Crossy Road arcade software on this Pi.
#   box86           turns its x86 instructions into ARM ones
#   wine            answers the Windows calls it makes
#   crossy_keys.py  taps out the keys it listens for when a cabinet button is pressed
#
# The game runs in the FOREGROUND and nothing here watches or tidies up while it plays:
# earlier versions looked for it by name, guessed wrong, and killed it mid-game.
# Everything sits inside one block that the shell reads whole before running it: a shell
# reads a plain script as it goes, so replacing this file while a game was running made the
# old copy carry on partway through the new one and start the game a second time.
{
  export WINEPREFIX=$HOME/.wine-crossy
  export WINEDEBUG=-all
  export BOX86_NOBANNER=1
  export WINEDLLOVERRIDES="mscoree,mshtml="
  export XDG_RUNTIME_DIR=/run/user/1000
  export DISPLAY=:0
  export PATH=/opt/wine/wine-9.0-x86/bin:/usr/local/bin:/usr/bin:/bin
  # box86 is left on its safe settings: the fast ones (bigblock, no safe flags, weak
  # memory order) made the game quit the moment it started
  BOX86=/usr/local/bin/box86
  WINE=/opt/wine/wine-9.0-x86/bin/wine
  LOG=/tmp/crossy.log

  pkill -f 'Game.exe' 2>/dev/null
  /opt/wine/wine-9.0-x86/bin/wineserver -k 2>/dev/null
  pkill -f wineserver 2>/dev/null
  sleep 3

  setsid /usr/bin/python3 "$HOME/crossy_keys.py" >> $LOG 2>&1 &
  KEYS=$!

  # Wine asks about .NET at every start. The game does not need it, so that one window is
  # closed by name a few seconds in, never the game's own window. The game's window is left
  # exactly as Unity made it: stretching it or asking for full screen makes Unity quit.
  # (It is asked for the screen's own size, 768x1024, and a desktop rule removes its
  # title bar: see labwc_rc.xml.)
  ( for i in $(seq 1 25); do
      sleep 3
      W=$(DISPLAY=:0 xdotool search --name "Wine Mono" 2>/dev/null | head -1)
      [ -n "$W" ] && DISPLAY=:0 xdotool windowclose "$W" 2>/dev/null
    done ) &

  # The game shows nothing but black for a minute or more while it loads, so a loading
  # screen sits on top (a desktop rule keeps it above) until the game's log says the first
  # scene is up. Two minutes and a half at most, whatever happens.
  L0=$(wc -l < $LOG)
  WAYLAND_DISPLAY=wayland-0 SDL_VIDEO_WAYLAND_WMCLASS=crossyload love "$HOME/crossyload.love" >/dev/null 2>&1 &
  SPLASH=$!
  ( for i in $(seq 1 150); do
      sleep 1
      tail -n +"$L0" $LOG | grep -q "Hidden/NFAA" && { sleep 3; break; }
    done
    kill $SPLASH 2>/dev/null
    # with no title bar the game fills the screen, but the desktop places it 10 pixels
    # down: slide it to the top. Moving is safe; RESIZING it makes Unity quit.
    G=$(DISPLAY=:0 xdotool search --name "CrossyRoad" 2>/dev/null | head -1)
    [ -n "$G" ] && DISPLAY=:0 xdotool windowmove "$G" 0 0 2>/dev/null ) &

  cd "$HOME/crossy/Crossy Road/CrossyRoad" || exit 1
  echo "=== $(date) starting" >> $LOG
  # NOT -force-opengl: in that mode the window stays black. Wine's own Direct3D path is
  # what actually draws this game, so that is what is used.
  "$BOX86" "$WINE" Game.exe -screen-width ${CROSSY_W:-768} -screen-height ${CROSSY_H:-1024} -screen-fullscreen 0 >> $LOG 2>&1
  echo "=== $(date) finished" >> $LOG
  kill $KEYS $SPLASH 2>/dev/null
  # Wine leaves its helpers (services, explorer) running after the game: clear them so
  # they do not pile up game after game
  /opt/wine/wine-9.0-x86/bin/wineserver -k 2>/dev/null
  exit 0
}
