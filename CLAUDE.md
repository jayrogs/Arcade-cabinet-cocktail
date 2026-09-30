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
- **CarnEvil** (Midway Seattle, 1998) runs in full MAME (about 75% speed in play) from `roms/mame/carnevil.zip`
  (must contain `486_carnevil.u96`, which MAME needs since 0.226; the first upload lacked it) plus
  `roms/mame/carnevil/carnevil.chd`. Same stick aiming as House of the Dead; `table/carnevil.cfg` shows only P1's crosshair and
  slows it (keydelta 3). It runs ~44 fps in play (75%), not full speed: one busy thread.
  **Its guns had to be calibrated** in the game's own service menu or shots never land: done
  Sept 28 (both guns; the game's marker sat inside the crosshair). Saved in its nvram; a copy
  is in `~/table_cfg/carnevil_nvram/` - if shots stop landing, copy it back to
  `saves/MAME/mame/nvram/carnevil/`. To recalibrate: start it with RetroArch's F2 save-state
  hotkey off, F2 = service, `=`/`-` move, F2 select, then GUN CALIBRATION.
- **House of the Dead 2** (Sept 30): `roms/naomi/hotd2.zip` + `hod2bios.zip` (also copied to
  `system/dc/`), in MODERN ARCADE and FAVES, started by `~/hotd2.sh` (tools/). Flycast aims its gun
  from an *analog* stick, absolutely (stick position = screen position), so with the on/off sticks
  the crosshair could only sit in the middle or at an edge. `tools/gunstick.py` makes a pretend
  controller "Cab Gun Stick" whose analog stick is the crosshair: holding the real stick glides it
  (slow at first, then fast), player 1's buttons pass through. It writes its RetroArch controller
  number to `/tmp/gunstick_pad.cfg`, which hotd2.sh appends. Autoconfig: `table/Cab Gun Stick.cfg`;
  `table/hotd2.cfg` binds button 2 to reload; `table/hotd2.opt` (config/Flycast/) turns the crosshair
  on at 200%. cabside.py ignores the pretend controller (its coin button looked like a phone pad's
  side button and restarted the game). Tested with a fake panel: shots land on the crosshair,
  reload works. A mouse-driven gun (RETRO_DEVICE_LIGHTGUN) never got coordinates here: dead end.
  The phone page's arcade upload is where Jay put hod2bios.zip; it was moved to roms/naomi.
- **Phone page uploads** take up to 16 GB (2 GB must stay free); it's at http://192.168.1.50:8080.
- **Overclocked to 2.8 GHz** (`arm_freq=2800` in `[pi5]` of config.txt, Sept 28; backup
  config.txt.bak-oc). Needed the supply raised: ~5.25V idle at the Pi, 4.99V under full load, no
  undervoltage. At 5.05V idle it dipped to 4.68V and throttled. Stress-tested at 70°C max.
- **Main shelf reorganised (Sept 30)**, 14 boxes -> 9, in this order: FAVES (first since Sept 30, Jay's ask; was FAVOURITES/STARS), RETRO ARCADE (the arcade
  folder), MODERN ARCADE (was NEW ARCADE; `newArcade` in the code; its own launchers + every game of a machine marked `inNew` in systems.lua,
  i.e. Dreamcast, which has no box of its own), 2P VERSUS (was FACE TO FACE), 2P TAKE TURNS (was
  TWO PLAYER: the cocktail-flip list), EXTRAS (Dr Mario, Pong, Flappy Bird, Crossy Road; `extras`
  in main.lua), any other machine with games, PLAYED LATELY, SETTING UP (the to-test
  list is now inside it), TURN OFF. Deploy: swap main.lua / systems.lua inside `~/cabmenu.love`
  (a zip) and kill the menu's `love`; cab.sh restarts it. Box pictures: `tools/menuart.py` CARDS.
- **Any game can be starred (Sept 30):** boxes with their own launcher carry a `key`
  (`extra/drmario`, `modern/crzytaxi`, `versus/atetris`...; `specials()` in main.lua), stored in
  `~/cab_state.txt` beside the folder games' `arcade/<name>` keys; PLAYED LATELY uses them too.
  Jay's FAVES list, set by hand that day: Dr Mario, the versus Tetrises (Tetris, Sega Tetris,
  TGM2 Plus, Tetris Plus 2), versus Puzzle Bobble 2, the three sped-up Pac-Mans, Crazy Taxi,
  CarnEvil, House of the Dead 1 (he asked for 2: add it once hod2bios.zip arrives and it works).
  The old stars (Claude's picks, which annoyed him) are in `~/cab_state.txt.bak-faves`.
- **Menu (Sept 28):** no MAME shelf any more (systems.lua); the 3D-era arcade games (Crazy Taxi,
  Monkey Ball, Sega Tetris, House of the Dead, CarnEvil, Area 51) are in a **NEW ARCADE** box
  (`newArcade` in main.lua). Area 51 (`roms/mame/area51.zip` + `area51/*.chd`) runs ~90% speed via
  mamegun.sh, P1 crosshair only (`table/area51.cfg`). **Gun calibrated Sept 28** (service F2 ->
  shoot GUN TEST, right START (key 2) -> CALIBRATE: crosshair on the centre +, hold trigger till DONE;
  right START again = tracking screen, whose red + is where the game aims). Before: shots ~15px low.
  After: dead centre, 8-14px toward the middle near the side edges (the game's own scaling; still
  inside the ring). Saved in nvram; copy in `~/table_cfg/area51_nvram/` (pre-calibration copy in
  `area51_nvram_before/`). Leaving a test screen = hold left START.
- **Dreamcast** shelf: Flycast with the real BIOS (`system/dc/dc_boot.bin`, `dc_flash.bin`).
  Crazy Taxi 2 (converted .cue/.bin -> .chd with chdman, now installed) has its controls in
  `config/Flycast/Crazy Taxi 2 (USA).cfg` (copy in `table/`): stick steers, 1 gas, 2 brake,
  3 = A (menus / hop), 4 = B. Tested driving at full speed. Phone page uploads Dreamcast games.
- **Flycast sound (Sept 30), after Jay said Crazy Taxi 2 and House of the Dead 2 sounded bad and
  Crazy Taxi 1 clear.** Measured by recording the output (`pw-record -P stream.capture.sink=true`;
  the sink monitor is after the volume, and "180%" is really x5.8, +15 dB): no dropouts in any of
  them, but CT2 had 48% and HOTD2 58% of their energy below 150 Hz (CT1 15%), which the small
  speakers can't play. Now `flycast.cfg` (copy: `flycast.cfg` in the repo root) runs every Flycast game
  through `filters/cab/CabClear.dsp` (`table/CabClear.dsp`: a 120 Hz high-pass; iir.so copied
  beside it) at -3 dB (CT1 clipped a little at 0); Dreamcast is -8 dB
  (`config/Flycast/dreamcast.cfg`, a content-dir override; it clipped 2% at 0), HOTD2 -1 dB
  (hotd2.cfg). Re-recorded: no clipping, peaks 2-4 dB under the limit, CT1 and CT2 equally loud
  in the mids. Jay may swap the adapter for an Apple USB-C one; if the buzz goes, the 180% boost
  can come down and these cuts with it.
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
