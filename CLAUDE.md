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
  jack); the sink volume is boosted to 180% so the amp can be turned down. Replacement
  (Apple adapter or a DAC HAT) still to do.
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
- **Pong's music** was rewritten (`games/Pong/music.lua`): 16-bar game tune and 8-bar
  title tune, band-limited pulses, triangle bass, drums, looped echo.
- **Fan:** official Pi 5 Active Cooler fitted and tested (off below 50°C, spins up above).
- **Backup:** `Documents\CabBackup` on Jay's PC, made by `tools/cab_backup.py` hourly
  when the cabinet is on.
- Project moved to a second Claude account; this file replaces the old chat history.
  Cloud sessions can't reach the Pi or the PC; run Claude Code on the PC.
- **Reaching the Pi:** `tools/cab.py` / `tools/pi.py` log in with the PC's SSH key, no
  password. Claude does not use the Pi's password. Passwordless `sudo` is allowed only for
  `reboot`, `poweroff` and `systemctl restart cabweb` (`/etc/sudoers.d/cabinet`); anything
  else needing `sudo` is for Jay to run.

## Moving to the Pi 5

1. **Power:** the cabinet supply is 5V 16A with a 12V terminal next to it. Tape over
   the 12V one. Set 5V to 5.1V with a multimeter and check it at the cut end of the
   cable before plugging in. Use a short USB-C cable rated for 5A, and ideally a 5A inline
   fuse on the red wire.
2. **`config.txt`** on the card's boot drive (`/boot/firmware/config.txt`):
   - `usb_max_current_enable=1`, because a wired supply can't tell the Pi 5 it has 5A
   - `kernel=kernel8.img`, because the Pi 5's default kernel uses 16K memory pages and
     box86 (Crossy Road through Wine) only runs with 4K
3. **Sound:** the Pi 5 has **no headphone jack**. The Pi 4's jack was the cabinet's sound.
   Ordered: an onn USB-C to 3.5mm adapter (it has a sound chip, since it works with the
   iPad Pro and Pixel phones) plus a USB-A male to USB-C female adapter, into a normal
   USB port (not the Pi 5's power port). Reviews mention hiss; the Apple USB-C adapter is
   the quieter fallback. Until it arrives there's no sound unless the screen plays sound
   over HDMI.
   - The scripts that record the cabinet's sound (`feed.sh`, `tools/cabweb.py`,
     `tools/pongtest*.sh`) now use `@DEFAULT_MONITOR@`, whatever output is the default,
     instead of the Pi 4 jack's name. Games already play through the default output.
   - If sound goes to HDMI instead of the adapter, make the adapter the default:
     `wpctl status`, then `wpctl set-default <id>`.
4. **Check after first boot:** the controls (`tools/joytest.py`), sound, Crossy Road
   (box86/Wine), Monkey Ball (Flycast), and the frame rates (`tools/fps.sh`).
   Use a fan: the Pi 5 runs hotter.

## Rules learned the hard way

- `retroarch.cfg` on the Pi is read-only on purpose.
- Never `pkill -f` a name that also appears in the same command line.
- Write for Jay in plain words. The code comments explain *why* in everyday language;
  match that.
