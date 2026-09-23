-- Cabinet settings. Change screenRotation at the table until player 1's strip
-- is at player 1's seat, then leave it alone.
return {
  layout = "side",       -- two tall strips, player 2's turned to the far end
  screenRotation = 0,    -- 0 / 90 / 180 / 270
  fullscreen = true,
  freePlay = true,       -- set false to make the coin switches charge credits
  music = true,
  overscan = 0,            -- pull the picture in this many screen pixels, for a monitor
                           -- that cuts the edges off (try the monitor's AUTO button first)
  nudgeX = 0,              -- shift the picture right (+) or left (-) by this many pixels
  nudgeY = 0,              -- shift it down (+) or up (-)
}
