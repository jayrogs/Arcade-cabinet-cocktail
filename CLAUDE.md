# Arcade cabinet: notes for Claude

A cocktail arcade table run by a Raspberry Pi called **picade**. `README.md` covers the
menu and adding games; `tools/README.md` covers reaching the Pi, the scripts, and what
lives where on it. Read both first.

## Where things stand (Sept 2026)

- **The Pi 4 is dead.** It was wired to 12V by accident, smoked, and now the supply just
  flashes and clicks. Replacing it with a **Raspberry Pi 5**.
- **The memory card probably survived.** Not checked yet. If it's fine it goes straight
  into the new Pi.
- **Backup:** `Documents\CabBackup` on Jay's PC, made the night before (after the Monkey
  Ball, Crossy Road and Dr Mario skill work). Made by `tools/cab_backup.py`.
- **Not yet on the cabinet:** the Dr Mario pause fix (commit b583362) and the sound
  change below. Deploy both once the new Pi is up.
- Project moved to a second Claude account; this file replaces the old chat history.
  Cloud sessions can't reach the Pi or the PC. Deploys, screenshots and the card check
  need Claude Code running on the PC (Tailscale + `PIPW` set).

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
