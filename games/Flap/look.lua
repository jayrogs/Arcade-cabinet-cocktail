-- look.lua : everything that is drawn. Kept apart from the rules so the game can be
-- made prettier without touching how it plays.
--
-- The sky is painted in bands rather than one flat colour, the city behind drifts slower
-- than the ground in front, and every pipe is drawn with a lit edge and a shadowed one so
-- it reads as a solid thing rather than a green rectangle.

local g = love.graphics
local L = {}

local W, H            -- one player's half, in the small drawing size

function L.setup(w, h)
  W, H = w, h
end

-- ------------------------------------------------------------------ colours
local function mix(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function shade(c, f)
  return { math.min(1, c[1] * f), math.min(1, c[2] * f), math.min(1, c[3] * f) }
end

-- a day that turns towards evening the further you get
local SKIES = {
  { top = { 0.31, 0.71, 0.93 }, low = { 0.67, 0.89, 0.97 } },   -- morning
  { top = { 0.20, 0.55, 0.88 }, low = { 0.62, 0.84, 0.96 } },   -- noon
  { top = { 0.36, 0.40, 0.78 }, low = { 0.98, 0.70, 0.45 } },   -- evening
  { top = { 0.10, 0.13, 0.35 }, low = { 0.44, 0.28, 0.52 } },   -- night
}

function L.skyFor(score)
  local step = math.min(#SKIES - 1, math.floor(score / 10))
  local into = math.min(1, (score % 10) / 10)
  local a, b = SKIES[step + 1], SKIES[math.min(#SKIES, step + 2)]
  return { top = mix(a.top, b.top, into), low = mix(a.low, b.low, into) }, step >= 2
end

-- ------------------------------------------------------------------ the world behind
function L.sky(sky)
  -- painted in bands: cheap, and it gives the picture depth a flat fill never has
  local bands = 22
  for i = 0, bands - 1 do
    local t = i / (bands - 1)
    g.setColor(mix(sky.top, sky.low, t))
    g.rectangle("fill", 0, H * t - 1, W, H / bands + 2)
  end
end

function L.sun(sky, night, t)
  if night then
    g.setColor(0.98, 0.98, 0.92)
    g.circle("fill", W - 42, 30, 9)
    g.setColor(sky.top[1], sky.top[2], sky.top[3])
    g.circle("fill", W - 46, 27, 8)              -- a bite out of it makes a moon
    g.setColor(1, 1, 1, 0.75)
    for i = 1, 14 do
      local x = (i * 37 + 11) % W
      local y = (i * 23) % (H * 0.5)
      g.rectangle("fill", x, y, 1, 1)
    end
  else
    g.setColor(1, 0.95, 0.7, 0.30)
    g.circle("fill", W - 44, 28, 16)
    g.setColor(1, 0.97, 0.78)
    g.circle("fill", W - 44, 28, 10)
  end
end

function L.clouds(x, night)
  -- two layers, the far one paler and slower: that is what makes it feel deep
  for layer = 1, 2 do
    local speed = layer == 1 and 0.25 or 0.5
    local y0 = layer == 1 and 24 or 44
    local a = layer == 1 and 0.35 or 0.6
    g.setColor(1, 1, 1, night and a * 0.35 or a)
    local span = 104
    local shift = (x * speed) % span
    for k = -1, math.ceil(W / span) + 1 do
      local cx = k * span - shift + (layer == 1 and 0 or 46)
      local cy = y0 + (k % 3) * 7
      g.ellipse("fill", cx, cy, 15, 6)
      g.ellipse("fill", cx + 11, cy + 2, 11, 5)
      g.ellipse("fill", cx - 10, cy + 3, 9, 4)
    end
  end
end

function L.city(x, night)
  -- a skyline sitting on the horizon, drifting slowly
  local base = H - 30
  local span = 132
  local shift = (x * 0.35) % span
  for k = -1, math.ceil(W / span) + 1 do
    local ox = k * span - shift
    local seed = k * 7919
    for i = 0, 7 do
      local bw = 10 + (seed + i * 31) % 9
      local bh = 14 + (seed + i * 17) % 26
      local bx = ox + i * 16
      g.setColor(night and { 0.13, 0.15, 0.30 } or { 0.44, 0.60, 0.66 })
      g.rectangle("fill", bx, base - bh, bw, bh)
      g.setColor(night and { 0.17, 0.19, 0.36 } or { 0.52, 0.68, 0.73 })
      g.rectangle("fill", bx, base - bh, bw, 2)
      -- lit windows after dark
      if night then
        for wy = base - bh + 4, base - 4, 5 do
          for wx = bx + 2, bx + bw - 3, 4 do
            if (wx * 13 + wy * 7 + seed) % 5 < 2 then
              g.setColor(1, 0.86, 0.45, 0.85)
              g.rectangle("fill", wx, wy, 2, 2)
            end
          end
        end
      end
    end
  end
  -- a line of trees in front of the city, darker again
  local tspan = 46
  local tshift = (x * 0.6) % tspan
  for k = -1, math.ceil(W / tspan) + 1 do
    local tx = k * tspan - tshift
    g.setColor(night and { 0.10, 0.20, 0.16 } or { 0.20, 0.52, 0.28 })
    g.ellipse("fill", tx, base + 2, 13, 9)
    g.ellipse("fill", tx + 14, base + 3, 10, 7)
  end
end

-- ------------------------------------------------------------------ the ground
function L.ground(x, night)
  local top = H - 22
  g.setColor(night and { 0.18, 0.40, 0.22 } or { 0.42, 0.78, 0.31 })
  g.rectangle("fill", 0, top, W, 6)
  g.setColor(night and { 0.13, 0.30, 0.17 } or { 0.32, 0.64, 0.24 })
  local span = 12
  local shift = x % span
  for k = -1, math.ceil(W / span) + 1 do
    g.rectangle("fill", k * span - shift, top + 4, 6, 2)
  end
  g.setColor(night and { 0.32, 0.26, 0.17 } or { 0.85, 0.74, 0.47 })
  g.rectangle("fill", 0, top + 6, W, H - top - 6)
  g.setColor(night and { 0.26, 0.21, 0.14 } or { 0.74, 0.62, 0.37 })
  local dspan = 18
  local dshift = (x * 1.0) % dspan
  for k = -1, math.ceil(W / dspan) + 1 do
    g.rectangle("fill", k * dspan - dshift, top + 9, 9, 2)
  end
end

-- ------------------------------------------------------------------ the pipes
local PIPE_W = 26

function L.pipe(px, gapY, gapH, night)
  local body = night and { 0.20, 0.52, 0.26 } or { 0.36, 0.76, 0.30 }
  local dark = shade(body, 0.62)
  local light = shade(body, 1.22)
  local lip = 6

  local function tube(y, h, capAtBottom)
    -- the tube, with a lit strip down the left and a shadowed one down the right
    g.setColor(body)
    g.rectangle("fill", px, y, PIPE_W, h)
    g.setColor(light)
    g.rectangle("fill", px + 3, y, 5, h)
    g.setColor(dark)
    g.rectangle("fill", px + PIPE_W - 7, y, 7, h)
    g.setColor(0, 0, 0, 0.18)
    g.rectangle("fill", px + PIPE_W - 2, y, 2, h)
    -- the mouth, wider than the tube, with its own shading
    local cy = capAtBottom and y or (y + h - lip * 2)
    g.setColor(body)
    g.rectangle("fill", px - 3, cy, PIPE_W + 6, lip * 2)
    g.setColor(light)
    g.rectangle("fill", px, cy, 5, lip * 2)
    g.setColor(dark)
    g.rectangle("fill", px + PIPE_W - 4, cy, 7, lip * 2)
    g.setColor(0, 0, 0, 0.22)
    g.rectangle("fill", px - 3, cy + lip * 2 - 2, PIPE_W + 6, 2)
    g.setColor(1, 1, 1, 0.16)
    g.rectangle("fill", px - 3, cy, PIPE_W + 6, 1)
  end

  -- a soft edge of shadow where each pipe meets the sky, rather than a slab of grey
  g.setColor(0, 0, 0, 0.09)
  g.rectangle("fill", px + PIPE_W, 0, 5, gapY)
  g.rectangle("fill", px + PIPE_W, gapY + gapH, 5, H)
  tube(0, gapY, false)
  tube(gapY + gapH, H - (gapY + gapH), true)
end

L.PIPE_W = PIPE_W

-- ------------------------------------------------------------------ the bird
function L.bird(x, y, tilt, flap, colour, dead)
  local body = colour or { 0.98, 0.84, 0.20 }
  g.push()
  g.translate(x, y)
  g.rotate(tilt)
  -- a soft shadow under it, so it sits in the world
  g.setColor(0, 0, 0, 0.13)
  g.ellipse("fill", 1, 7, 8, 2)
  g.setColor(shade(body, 0.72))
  g.rectangle("fill", -7, -5, 14, 11, 4, 4)          -- the outline, a darker body behind
  g.setColor(body)
  g.rectangle("fill", -6, -4, 12, 9, 3, 3)
  g.setColor(shade(body, 1.18))
  g.rectangle("fill", -5, -4, 8, 3, 2, 2)            -- light along the top
  -- the wing: three positions, so it looks like it beats rather than slides
  local wy = ({ -1, 2, 4 })[flap] or 1
  g.setColor(shade(body, 0.55))
  g.rectangle("fill", -5, wy - 1, 8, 4, 2, 2)
  g.setColor(shade(body, 0.85))
  g.rectangle("fill", -4, wy - 1, 6, 2, 1, 1)
  -- the face
  g.setColor(1, 1, 1)
  g.rectangle("fill", 1, -4, 5, 5, 2, 2)
  g.setColor(0.08, 0.08, 0.10)
  if dead then
    g.rectangle("fill", 2, -3, 3, 1)                 -- eyes shut
  else
    g.rectangle("fill", 3, -3, 2, 3)
  end
  g.setColor(0.98, 0.55, 0.12)
  g.rectangle("fill", 5, -1, 5, 3, 1, 1)             -- beak
  g.setColor(0.86, 0.42, 0.08)
  g.rectangle("fill", 5, 0, 5, 2, 1, 1)
  g.pop()
end

-- ------------------------------------------------------------------ bits and pieces
function L.feather(p)
  g.setColor(p.c[1], p.c[2], p.c[3], math.min(1, p.life * 3))
  g.push()
  g.translate(p.x, p.y)
  g.rotate(p.a)
  g.rectangle("fill", -1.5, -1, 3, 2)
  g.pop()
end

function L.medal(kind, x, y)
  local rim = ({ bronze = { 0.80, 0.50, 0.28 }, silver = { 0.78, 0.80, 0.85 },
                 gold = { 0.95, 0.80, 0.25 }, ruby = { 0.85, 0.25, 0.35 } })[kind]
  if not rim then return end
  g.setColor(shade(rim, 0.6))
  g.circle("fill", x, y, 9)
  g.setColor(rim)
  g.circle("fill", x, y, 7.5)
  g.setColor(shade(rim, 1.25))
  g.arc("fill", x, y, 7.5, math.pi * 1.1, math.pi * 1.6)
  g.setColor(1, 1, 1, 0.45)
  g.circle("fill", x - 2.5, y - 2.5, 2)
end

L.mix, L.shade = mix, shade
return L
