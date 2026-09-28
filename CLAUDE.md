# Arcade cabinet: notes for Claude

A cocktail arcade table run by a Raspberry Pi called **picade**. `README.md` covers the
menu and adding games; `tools/README.md` covers reaching the Pi, the scripts, and what
lives where on it. Read both first.

## Where things stand (Sept 2026)

- **Now running on a Raspberry Pi 5** (Sept 25). The Pi 4 died after being wired to 12V;
  the memory card survived and went straight in. Checked after a full reboot: power
  ~5.05V with no throttling, the 3H controls board, the USB-C sound adapter as the default
  output, menu, phone page and video feed all fine. Idled ~55°C without a fan; with the
  Active Cooler it idles ~49°C. The onn USB-C sound adapter buzzes (worse than the Pi 4's
  jack). The HDMI-to-VGA converter has no audio socket, so the adapter stays. Workaround
  Jay is happy with: the sink volume is boosted to 180% (`wpctl set-volume
  @DEFAULT_AUDIO_SINK@ 1.8`) and the amp's dial turned down, which buries the buzz. Keep
  it there; an Apple USB-C adapter or a DAC HAT would be the real fix if ever wanted.
- **Deployed on the Pi 5:** the Dr Mario pause fix, the sound change below, and Crossy
  Road's "player 1 button 3 jumps player 2" (`tools/crossy_keys.py`, not yet played).
- **The menu froze on a black DEMO screen** on the Pi 5 (Sept 25; cause not yet known,
  the video decoder thread was stuck waiting on a lock). `cab.sh` now has a watchdog: the
  menu touches `/tmp/cab_alive` every 2s and a menu silent for 30s is restarted, with a
  gdb trace saved as `/tmp/menu_freeze_*.txt` first. Read those traces to find the real
  cause (`/tmp` is cleared on reboot, so check before restarting the Pi).
- **Buttons (Sept 25, tested):** the 3H board sends buttons 1-4 as 0-3, Player 1/2 start
  as 7 (each half), player 1's side button as 9 (BTN_BASE4) and player 2's side button as
  8 (BTN_BASE3; rewired from the service pin, which the board ignores, to P2 coin).
  - Arcade games: `autoconfig/udev/3H Dual Arcade 3H Dual Arcade.cfg` on the Pi maps
    b/a/y/x = 0/1/2/3, start = 7, select (coin) = 9. **P1 side button = coin.**
  - Per-emulator overrides in `~/.config/retroarch/config/<core>/<core>.cfg` (FBNeo, MAME,
    MAME 2003-Plus, MAME 2010, Flycast) turn off RetroArch's start+select quit combo and
    its quit-on-button-9, so neither can end a game.
  - **P2 side button:** tap = same game again, hold = back to the shelf (`cabside.py`,
    with `cab.sh` acting on `/tmp/cab_again`). The phone pads keep their own button 10.
  - The menu's "SET UP THE BUTTONS" tool rewrites that autoconfig file from whatever is
    pressed; a careless run is what broke it before. Don't run it without updating it.
- **Arcade pictures are flyers** (Sept 25): `tools/art3.py --go` fetched libretro's
  Named_Boxarts (max 512px wide) for 540 games; the title screens they replaced are in
  each set's `media/titles/`. The menu draws at `DETAIL` x its 256x320 layout (3x on the
  cabinet) so pictures keep their detail; before, they were squashed to 256x320 first.
- **Pong's music** plays files from `~/roms/music/pong` (the `games` share, `music\pong`, from a PC):
  a name containing "title" on the title screen, anything else in games (random each game).
  In there now: two CC-BY loops by Tomasz Kucza and CC0 "Starlight City" (see its
  CREDITS.txt). With the folder empty, the built-in French-house tunes in
  `games/Pong/music.lua` play instead (built once, cached as .wav in the save folder).
  Claude won't download commercial soundtracks (Tetris etc.); Jay can drop his own in.
- **Crazy Taxi** (NAOMI, `roms/naomi/crzytaxi.zip`) has its own shelf entry, launched by
  `~/crazytaxi.sh` (copy in `tools/`, retries a start that hangs, like Monkey Ball) with
  `~/.config/retroarch/crazytaxi.cfg` (copy in `tools/`): stick steers, button 1 gas, button 2
  brake, button 3 drive gear, button 4 reverse (not the stick: steering hard flipped the gear). The game's own
  buttons 3-4 (RetroArch Y/X) are moved off the panel: Crazy Taxi freezes if it gets one.
- **FACE TO FACE** shelf box (`FACE` list / `faceGames()` in `main.lua`): games set up for
  players at opposite ends. "split" games (Puzzle Bobble 2, Puyo Puyo 2, Magical Drop II/III,
  Twinkle Star Sprites, Atari Tetris) run with `tablesplit.glsl` (repo root; on the Pi in
  `~/.config/retroarch/shaders/`): the curtain plus the right-hand field turned half round,
  versus only. "court" games (Windjammers) run from `~/roms_table/` (symlinks to the game and
  neogeo.zip), whose RetroArch content-dir files (`table/roms_table.cfg` -> config/FinalBurn
  Neo/, `table/roms_table.rmp` -> config/remaps/FinalBurn Neo/) turn the picture a quarter and
  each player's stick with it. Box pictures: `~/menuart/face_<stem>.png`, copied from media.
  Windjammers' stick directions were derived, not proven in play: if one is backwards, swap it
  in roms_table.rmp.
- **NAOMI games** other than Monkey Ball start with `~/naomi.sh <name>` (copy in `tools/`):
  flycast.cfg + `naomi.cfg` (moves the NAOMI's button 4 off the panel; it froze Crazy Taxi) +
  `<name>.cfg` if present. Sega Tetris is on the shelf this way.
- Uploads that were in the wrong place were moved to `~/uploads_set_aside/` (a duplicate
  Puzzle Bobble 2, and the Windows PC Crazy Taxi), not deleted.
- **The screen runs at 60 Hz** (`MODE=1024x768@60.004002Hz` in `cab.sh`). A bare 1024x768 gave
  75 Hz, and Flycast (audio sync off, so paced by the screen) ran Crazy Taxi / Monkey Ball 25%
  too fast; other games judder at 75. Check with `wlr-randr | grep current`.
- **The House of the Dead** (Model 2) runs in full MAME (`mame_libretro`, ~95% speed) from
  `roms/mame/hotdo.zip` (the original release, so named `hotdo`). The stick moves each
  player's crosshair: MAME `saves/MAME/mame/cfg/default.cfg` (copy: `table/mame_default.cfg`)
  binds P1/P2_LIGHTGUN_X/Y increment/decrement to JOYCODE_1/2_HAT1*; `hotdo.cfg`
  (`table/hotdo.cfg`) turns the crosshairs on. Button 1 fires; firing at the very edge
  reloads. P1's crosshair is blue, P2's red. Tested with one fake pad per player (two fake
  pads at once confused RetroArch's port assignment, not the game).
- **Fan:** official Pi 5 Active Cooler fitted and tested (off below 50°C, spins up above).
- **Backup:** `Documents\CabBackup` on Jay's PC, made by `tools/cab_backup.py` hourly
  when the cabinet is on.
- Project moved to a second Claude account; this file replaces the old chat history.
  Cloud sessions can't reach the Pi or the PC; run Claude Code on the PC.
- **Reaching the Pi:** `tools/cab.py` / `tools/pi.py` log in with the PC's SSH key, no
  password; they find the Pi by name (`picade.local`) or Tailscale (`100.73.167.50`), because
  its Wi-Fi address used to change on restart. Since Sept 27 it is fixed at 192.168.1.50
  (NetworkManager connection `cab-wifi`, manual; below the AT&T gateway's .64-.253 pool). Claude never types the Pi's password. Since Sept 27
  Jay has made `sudo` password-free for his user (`/etc/sudoers.d/cabinet-all`, his choice,
  to let Claude do boot and system changes); delete that file to undo it.
- **Start-up is silent:** `cmdline.txt` has `console=tty3 loglevel=3 systemd.show_status=false`
  (plus `logo.nologo`, no `splash`); the EEPROM has `DISABLE_HDMI=1` and
  `NET_INSTALL_AT_POWER_ON=0`. The screen stays black until the menu.
- `retroarch.cfg` on the Pi is read-only on purpose.
- Never `pkill -f` a name that also appears in the same command line.
- Write for Jay in plain words. The code comments explain *why* in everyday language;
  match that.
