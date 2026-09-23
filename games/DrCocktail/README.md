# Dr. Cocktail

Head-to-head Dr. Mario for a cocktail arcade table, drawn in the style of the NES original:
8-pixel cells, purple checkerboard, glass bottles, the magnifier with the three viruses.

Three layouts, picked with `layout = "..."` in `config.lua`:

The cab is a cocktail table with a 5:4 monitor mounted sideways, so from either seat the
screen is a 4:5 portrait between the two players. The layouts are cut for exactly that:

- **side** (the default): two tall strips. Player 1's bottle in the left strip with the level,
  score and win tally stacked above and below it; player 2's strip on the right turned 180
  degrees so it reads upright from the far end. 256x320, exactly 4x into 1024x1280.
- **cocktail**: the same portrait, but the halves stacked along the table instead, player 1's
  at the near end and player 2's flipped at the far end.
- **upright**: the NES two-player screen with both bottles the right way up, for a desktop
  or a table where both players sit on the same side.

Set `screenRotation` in `config.lua` (0, 90, 180 or 270) until the picture stands the right
way for player 1's seat.

Written in Lua for [LÖVE](https://love2d.org) 11.x. No asset files: the font and every sprite
are built from pixel strings at startup, and the sound effects are synthesised.

## Music and sound

Music slots match the NES: **title**, **select** (mode select screen), **fever** and
**chill** (in-game, per the MUSIC TYPE choice; the attract demo uses fever), **feverclear**
and **chillclear** (stage clear jingles), **gameover** (bottle overflowed, or the computer
won the round) and **matchwin** (a human wins a versus round, against the computer or in
two-player; a file with "vs", "versus" or "match" in its name lands here). Game music is
replaced by the jingle the moment a round ends.

Every slot has a built-in chiptune. To replace one, drop a `.ogg`, `.mp3` or `.wav` into the
`music/` folder. A file named exactly after the slot (`fever.mp3`) wins; otherwise the filename
is matched on words, so "Dr. Mario Music (NES) - Fever.mp3" lands in the fever slot and a
file with "select" or "mode" in the name becomes the mode select music. The full list is in
`music/PUT MUSIC HERE.txt`.

Sound effects work the same way: drop a file into `sfx/` named after the effect (`virus.wav`,
`rotate.ogg`...), or with the key word in its name (`combo-sound.mp3` is **combo1**, the
smallest junk-throwing combo; `combo-sound-2.mp3` is **combo2**, three or more matches at
once). The full list of names is in `sfx/PUT SOUNDS HERE.txt`. Anything you do not supply
keeps its synthesised NES-style default.

## Sprites

The viruses, the doctor and the title logo are drawn in code, but PNG files in `sprites/`
override them: `virus_red.png` and friends for the 8x8 in-bottle viruses, `lens_red.png`
and friends for the big lens viruses, `doctor.png` for the doctor (four poses: idle, holding,
throwing, arms out), `logo.png` and `logo_half.png` for the title capsule, and
`title_doctor.png` / `title_virus.png` for the menu pill icons, and `half_red.png` /
`half_yellow.png` / `half_blue.png` for the capsule halves, a 48x8 strip in the sprite sheet's
order: top, bottom, left, right, loose single, cleared ring. `logo_small.png` is the small
logo on the one-player screen. `font.png` replaces the typeface: an ImageFont strip of 8x8
cells separated by magenta columns, in the order
`ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,-:<>!?/'#@` (the game's own glyphs are the NES ones;
B, J, K, Q, Z and the punctuation never appear in the original and are drawn to match).
A file wider than it is tall is read as animation frames side by side. Transparent
background. See `sprites/PUT SPRITES HERE.txt`.

## Run on the desktop

Double-click `Play Dr Cocktail.bat` in this folder. Or from a terminal:

```
"C:\Program Files\LOVE\love.exe" .
```

`Esc` quits, `F11` toggles fullscreen, `F10` shows the last sound effect and which
board caused it (P1, P2, CPU or UI) for tracking down a stray noise. Leave the title screen alone for fifteen seconds and
the attract-mode demo starts: two computer players go head to head until someone presses start.

Two people can play on one keyboard:

| Action        | Player 1     | Player 2 |
|---------------|--------------|----------|
| Move          | ← →          | J / L    |
| Soft drop     | ↓            | K        |
| Rotate CW     | A            | U        |
| Rotate CCW    | D            | O        |
| Pause         | F            | Y        |
| Start         | 1            | 2        |
| Coin          | 5            | 6        |

Both maps can be changed in `config.lua` with `keys1 = { ... }` and `keys2 = { ... }` using
the field names up, down, left, right, b1, b2, b3, start, coin and LÖVE key names. A keyboard
encoder such as a J-PAC sends the MAME defaults (player 1 Left Ctrl / Left Alt, player 2
R F D G with A / S), which is what to put there if the cab ends up wired that way.

USB gamepads also work: pad 1 drives player 1, pad 2 drives player 2 (A / B rotate,
Start, Back = coin).

## Playing

The flow is the NES one: title screen, mode select, then the game. The attract demo starts
after fifteen idle seconds on the title (`demoSeconds`); any Start or coin ends it.

- **Title**: up/down moves the heart between 1 PLAYER GAME, 2 PLAYER GAME and VS COMPUTER,
  Start (or button 1) from either seat confirms. A two-player game takes two credits when
  coins are on; the others take one.
- **VS COMPUTER**: player 2's bottle is played by the computer, using player 1's level and
  speed. Handy on the cab when nobody else is around, and for testing junk attacks.
- **Mode select**: up/down moves between VIRUS LEVEL, SPEED and MUSIC TYPE, left/right
  changes the value. In versus each player has their own level and speed marker, 1P above
  the bar and 2P below. Music type (FEVER / CHILL / OFF) is shared. **Start** begins.
- The bottles then appear with the viruses in place and the music starts; the first capsule
  drops a moment later.
- Solo: clear every virus to hear the stage-clear jingle and advance a level. Overflow the
  neck and it is game over.
- Versus: clear your bottle or outlast your opponent to take the round, with the victory
  jingle. First to three rounds wins. After a round the screen waits: only the **winner's**
  Start begins the next round (or returns to the title once the match is decided). If the
  computer won, the human's Start stands in for it.
- **Going back**: button 2 on the mode select returns to the title screen, so picking
  the wrong number of players costs nothing.
- **Pause**: button 4 during a game (button 3 on a three-button panel) stops the clock and
  offers CONTINUE, PLAY AGAIN, MAIN MENU and QUIT. Quit closes the game, which on the
  cabinet brings its menu back. Either seat can open it; button 2 or the pause button
  again closes it.
- **Junk**: every match a single capsule causes counts, including chains where a clear drops
  pieces into a second clear. Two or more matches send that many junk halves into the
  opponent's bottle, in the colours of the matches, capped at four. `garbageMin` and
  `garbageMax` in `config.lua` change the threshold and the cap.
- The drop speed steps up just before the 9th capsule and every 10 after, marked by the
  five-note chime.

## Capsule feel

The timing follows the NES disassembly notes at wiki.drmar.io:

- Gravity comes from the 81-entry NES table. LOW starts at 40 frames per row, MED at 20,
  HI at 14, and the virus level does not change it.
- A capsule locks the frame a downward move fails. There is no separate grace timer; the
  window to slide a landed capsule is the time until the next gravity tick, which is the
  whole 20 frames on MED if you are not soft dropping. `slideFrames` in `config.lua` adds
  extra frames on top if you want more than the original.
- Soft drop moves a row every 2 frames and only while down is pressed **on its own**.
  Down plus left or right cancels the soft drop, so you can slide a capsule along the
  floor with the stick held diagonally without it locking.
- Down must be **released and pressed again for each capsule**. Holding it through a lock
  does nothing to the next pill until you let go, so you cannot machine-gun pills by
  leaning on the stick.
- After a capsule locks and any clears settle there is a short pause (`spawnDelay`, 24
  frames by default) before the next capsule appears.
- Left/right moves on press, again after 16 frames, then every 6.
- Anything falling after a lock, pieces settling after a clear and incoming junk, drops one
  row every 10 frames (`fallFrames`).
- Rotating against a wall on the right kicks the capsule one column left.

## Cabinet setup

1. Copy `config.example.lua` to `config.lua`. Set `freePlay = false` for coin operation,
   `fullscreen = true`, and `screenRotation` to 0, 90, 180 or 270 until player 1's half of
   the screen sits at the seat wired as player 1.
2. On RetroPie, install the `love` package from optional packages and drop this folder in
   `~/RetroPie/roms/love/drcocktail/` (or zip the contents as `drcocktail.love`). It shows up
   in the LÖVE system of the front-end. On Batocera, put the `.love` file in `roms/love`.
3. A dual JAMMA encoder such as the RetroArcade.us / 3H board (USB id 16c0:75e1) reports two
   joysticks, but Linux merges them into one unless told otherwise. Add
   `usbhid.quirks=0x16c0:0x75e1:0x040` to the end of `/boot/firmware/cmdline.txt` and reboot;
   `js0` becomes player 1 and `js1` player 2. If the panels come out crossed, set
   `swapPads = true` in `config.lua`. Press F9 in game to see what each pad sends.

## Tests

```
"C:\Program Files\LOVE\lovec.exe" . --selftest
```

Runs scripted rule checks (matching, gravity, garbage, game over) plus forty fuzzed versus
games that verify board consistency every half second. `--shot` plays a simulated versus
game and writes `shot.png` to the LÖVE save directory.

## Files

- `board.lua`   game rules for one bottle, no rendering. Gravity uses the NES speed table.
- `render.lua`  draws one player's half of the table, title and high score pages
- `main.lua`    input, game flow, cocktail split screen, attract demo, self test
- `ai.lua`      computer player for the attract demo
- `hiscore.lua` top five solo scores, saved in the LÖVE save directory
- `music.lua`   original chiptune loop rendered at startup (`music = false` in config to mute)
- `sfx.lua`     square-wave sound effects
- `conf.lua`    LÖVE window settings

## Not yet done

Hand-drawn sprites and initials entry on the high score table. The rules engine is isolated in
`board.lua` so both are front-end work.

Dev: "lovec . --probe" runs probe.lua, a scripted computer game that reports combos and junk.
