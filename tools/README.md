# Reaching the cabinet

The cabinet is a Raspberry Pi called **picade**. It answers on two addresses and the
scripts here try both, so they work at home or from anywhere:

| Where | Address |
|---|---|
| On Jay's network | `192.168.1.175` (fixed, it will not move) |
| Anywhere | `arcade-cab` / `100.73.167.50` (over Tailscale) |

From another machine you need three things: Tailscale signed in to the same account,
`pip install paramiko pillow`, and the Pi's password in the `PIPW` environment variable.

## The scripts

| | |
|---|---|
| `cab.py` | finds the cabinet and runs commands on it; the others use it |
| `pi.py "command"` | run one command on the cabinet and print what it says |
| `grab.py` | photograph the cabinet's screen into `pi_shot.png` |
| `shots_cab.py a,b` | have the menu render its own screens and fetch them |
| `deploy3.py` | send a new build of the game and restart the cabinet |
| `art.py` | fetch a picture for every arcade game (runs **on** the Pi) |

## What lives where on the Pi

| | |
|---|---|
| `~/cab.sh` | what runs at switch-on: the menu, then whatever it picks, then the menu again |
| `~/cabmenu.love` | the menu |
| `~/drcocktail.love` | Dr. Mario Cocktail Edition |
| `~/cabalign.love` | the screen lining-up tool |
| `~/roms/...` | the games, shared as `\192.168.1.175\games` |
| `~/.config/retroarch/` | the emulators; `retroarch.cfg` is read-only on purpose |
| `~/screen.conf` | how the picture sits on the glass |

Stop it with `kill $(cat /tmp/cab.pid)`, start it with
`setsid nohup /home/jayrogs/cab.sh < /dev/null > /dev/null 2>&1 &`.
Never `pkill -f` a name that also appears in the same command line: it kills the shell
asking for it.
