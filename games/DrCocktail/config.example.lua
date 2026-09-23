-- Copy this file to config.lua to override defaults. Missing keys keep their defaults.
return {
  freePlay = false,        -- cab: coin switches add credits. Desktop: true.
  layout = "side",         -- "side": bottles side by side, P2's flipped for the far seat (landscape)
                           -- "cocktail": halves stacked, P2's flipped (portrait)
                           -- "upright": NES screen, both bottles the right way up
  screenRotation = 90,     -- 0 / 90 / 180 / 270 until the picture matches how the LCD is mounted
  fullscreen = true,
  roundsToWin = 3,         -- versus is first to this many rounds (NES: three)
  music = true,            -- built-in tunes, or files dropped in the music/ folder
  -- keys1 = { b1 = "lctrl", b2 = "lalt" },   -- MAME-style rotate buttons for a keyboard encoder
  -- keys2 = { up = "r", down = "f", left = "d", right = "g", b1 = "a", b2 = "s" },
  spawnDelay = 24,         -- frames between a capsule locking and the next one appearing
  garbageMin = 2,          -- matches from one capsule needed to send junk (NES: 2)
  garbageMax = 4,          -- most junk halves one capsule can send (NES: 4)
  fallFrames = 10,         -- frames per row for pieces settling after a clear and for junk
  demoSeconds = 15,        -- idle seconds on the title before the attract demo
  swapPads = false,        -- true if player 1's panel drives player 2's bottle
  slideFrames = 0,         -- extra frames a landed capsule may still slide before locking.
                           -- 0 is the NES: it locks the frame a drop fails; the slide window
                           -- is the gap until the next gravity tick (20 frames on MED).
  overscan = 0,            -- pull the picture in this many screen pixels, for a monitor
                           -- that cuts the edges off (try the monitor's AUTO button first)
  nudgeX = 0,              -- shift the picture right (+) or left (-) by this many pixels
  nudgeY = 0,              -- shift it down (+) or up (-)
}
