# The cabinet menu

What the arcade table shows when you switch it on. It lists everything on the machine,
you pick with the stick, and it starts. When the game finishes the menu comes back.

## Adding games

On any PC on the same network, open `\192.168.1.175\games` (log in as **jayrogs**).
Drop files into the folder for their machine:

| Folder | Machine | What the files look like |
|---|---|---|
| arcade | Arcade (FBNeo) | `sf2.zip`, `dkong.zip` |
| mame | Arcade (MAME 2003) | `.zip` |
| nes, snes, genesis, sms, gg, 32x | The consoles | `.nes .sfc .md .sms .gg .32x` |
| gb, gba, lynx, vb, wonderswan | Handhelds | `.gb .gbc .gba .lnx .vb .ws` |
| psx, dreamcast, tg16 | Disc machines | `.chd .cue .gdi` |
| atari2600, atari7800, c64, msx, o2em | The old ones | `.a26 .a78 .d64 .rom .bin` |
| love | LOVE games | `.love` |

Then pick **SEARCH AGAIN** in the menu. Some machines need a BIOS file: those go in
`\192.168.1.175\bios`.

## At the cabinet

| Doing | Button |
|---|---|
| Move | The stick, up and down |
| Open / start | Button 1, or Start |
| Go back | Button 2 |
| Leave a game | Hold **Coin** and press **Start** |
| Switch the table off | The last line of the menu |

## The pieces

- `main.lua` the menu itself, drawn at 256x320 and scaled whole so it stays sharp
- `systems.lua` one line per machine: its folder, its name, and which emulator plays it
- `cab.sh` what the cabinet runs at switch-on: shows the menu, runs what it picks, repeats
- `font.png` the same lettering as Dr Cocktail

Games run through RetroArch with the emulator cores in
`/home/jayrogs/.config/retroarch/cores`. To add a machine, put a core there and add a
line to `systems.lua`.
