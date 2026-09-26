-- Flappy Bird : a flapping game for a cocktail table, played a turn each.
--
-- One player flies at a time and gets the WHOLE screen. When it is player 2's turn the
-- whole picture turns round to face their seat, the way a cocktail table is meant to
-- work. Three turns each, both flying the same pipes, and the totals decide it.
--
-- Any button flaps.
--
-- Keys, for a keyboard: player 1 space or up, player 2 M or right shift. 1 and 2 start.

local g = love.graphics
local L = require("look")
local music = require("music")

local VIEW_W, VIEW_H = 256, 340            -- the whole screen: one player has it all
local W, H = VIEW_W, VIEW_H
local TURNS = 3                            -- turns each in a two player game
local GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,-:<>!?/'#@"
local WEB1, WEB2 = "Cab Web Panel", "Cab Web Panel 2"

-- how the game feels: these are the numbers worth arguing about
local GRAVITY = 420
local FLAP = -142
local SPEED = 62                           -- how fast the world comes at you
local GAP = 54                             -- the hole between the pipes
local PIPE_EVERY = 92                      -- how far apart they stand
local GROUND_Y = VIEW_H - 30

local font, screen
local pressed, jsPressed = {}, {}

-- ------------------------------------------------------------------ sound
local sfx = {}
local function tone(freq, secs, kind, vol)
  local rate = 22050
  local n = math.floor(rate * secs)
  local sd = love.sound.newSoundData(n, rate, 16, 1)
  for i = 0, n - 1 do
    local t = i / rate
    local env = 1 - i / n
    local v
    if kind == "flap" then
      local f = freq * (1 + 1.2 * (i / n))
      v = math.sin(2 * math.pi * f * t) * 0.6 + (love.math.random() * 2 - 1) * 0.4
      env = env * env
    elseif kind == "point" then
      local f = freq * (i < n / 2 and 1 or 1.5)
      v = (math.sin(2 * math.pi * f * t) > 0) and 1 or -1
    elseif kind == "hit" then
      local a = (math.sin(2 * math.pi * freq * t) > 0) and 1 or -1
      v = a * 0.5 + math.sin(2 * math.pi * freq * 0.5 * t) * 0.4 +
          ((i < n * 0.2) and (love.math.random() * 2 - 1) * 0.7 or 0)
      env = env * env
    elseif kind == "fall" then
      local f = freq * (1 - 0.7 * (i / n))
      v = (math.sin(2 * math.pi * f * t) > 0) and 1 or -1
    else
      v = math.sin(2 * math.pi * freq * t)
    end
    sd:setSample(i, math.max(-1, math.min(1, v * env * (vol or 0.5))))
  end
  return love.audio.newSource(sd, "static")
end

local function makeSounds()
  sfx.flap = tone(210, 0.09, "flap", 0.30)
  sfx.point = tone(720, 0.13, "point", 0.35)
  sfx.hit = tone(120, 0.26, "hit", 0.6)
  sfx.fall = tone(340, 0.45, "fall", 0.4)
  sfx.menu = tone(520, 0.06, "point", 0.25)
  sfx.coin = tone(1320, 0.1, "point", 0.22)            -- EXTRAS: a bright ping
  sfx.shield = tone(440, 0.3, "flap", 0.4)             -- a rising whoosh
  sfx.pop = tone(260, 0.22, "hit", 0.45)               -- the shield bursting
end

local function play(name)
  local s = sfx[name]
  if s then s:stop(); s:play() end
end

-- ------------------------------------------------------------------ input
local KEYS = {
  { flap = { "space", "up", "z", "lctrl" }, start = { "1" } },
  { flap = { "m", "rshift", "down" }, start = { "2" } },
}

local function padsFor(p)
  local out, real = {}, {}
  for _, js in ipairs(love.joystick.getJoysticks()) do
    local name = js:getName()
    if name == WEB1 then
      if p == 1 then out[#out + 1] = js end
    elseif name == WEB2 then
      if p == 2 then out[#out + 1] = js end
    else
      real[#real + 1] = js
    end
  end
  if real[p] then out[#out + 1] = real[p] end
  return out
end

local shoved = {}          -- stick shoves this frame, by joystick object

-- buttonsOnly: leave the stick out (on the title the stick changes EXTRAS instead)
local function flapPressed(p, buttonsOnly)
  for _, k in ipairs(KEYS[p].flap) do if pressed[k] then return true end end
  for _, k in ipairs(KEYS[p].start) do if pressed[k] then return true end end
  for _, js in ipairs(padsFor(p)) do
    if jsPressed[js] or (shoved[js] and not buttonsOnly) then return true end
  end
  return false
end

local function stickShoved(p)
  if pressed[p == 1 and "left" or "j"] or pressed[p == 1 and "right" or "l"] then return true end
  for _, js in ipairs(padsFor(p)) do
    if shoved[js] then return true end
  end
  return false
end

function love.joystickpressed(js, b) jsPressed[js] = b end

-- The stick counts too: shoved any way, it flaps, once per shove. The cabinet's panels
-- report the stick as two axes (not a hat), so both are watched.
local stick = {}
function love.joystickaxis(js, axis, v)
  if axis > 2 then return end
  local s = stick[js] or { 0, 0, out = false }
  stick[js] = s
  s[axis] = v
  local far = math.max(math.abs(s[1]), math.abs(s[2]))
  if far > 0.5 and not s.out then
    s.out = true
    shoved[js] = true
  elseif far < 0.3 then
    s.out = false
  end
end
function love.joystickhat(js, h, v)
  if v ~= "c" then shoved[js] = true end
end
function love.keypressed(k)
  if k == "escape" then love.event.quit() end
  pressed[k] = true
end

-- ------------------------------------------------------------------ the world
-- Both players fly the same pipes: the row is worked out from the game's seed, so each
-- half shows the very same holes in the very same places.
local S = {
  state = "title",          -- title | choose | ready | play | crashed | between | over
  t = 0, idle = 0, seed = 1,
  scroll = 0, run = 0,
  players = 1, turn = 1, round = 1,
  totals = { 0, 0 }, bestRun = { 0, 0 },
  bird = nil, best = 0,
  shake = 0, flash = 0, timer = 0,
  extras = true,            -- coins, shields and drifting pipes (the stick on the title)
  pops = {},                -- "+1" and the like, floating up and fading
}

-- a number 0..1 for pipe n, from the seed alone; salt picks a different one per use
local function hash(n, salt)
  local x = math.sin(n * 12.9898 * salt + S.seed * 78.233) * 43758.5453
  return x - math.floor(x)
end

-- EXTRAS: some gaps drift up and down from the sixth pipe on; how far (0 = still)
local function driftAmp(n)
  if not S.extras or n < 6 then return 0 end
  local r = hash(n, 9.1)
  if r > 0.45 then return 0 end
  return 6 + (r / 0.45) * 6
end

-- The nth pipe's hole, from the seed alone, so every turn flies the same run. Each hole is
-- placed from the one before: between two pipes there is only about 0.8 s, which is about
-- 60 px of climbing flapping flat out, and big drops are just as tight (a flap on the way
-- out of a pipe eats the time needed to fall). Holes drawn anywhere at random asked for
-- climbs of up to 186 px. Checked with FLAP_TEST=fair: a simple auto-pilot now gets through
-- 37 of 40 courses to pipe 60; on the old holes it crashed on all 40 by the fourth pipe.
local CLIMB, DROP = 50, 55
local tops = {}
local function gapFor(n)
  if tops.seed ~= S.seed or tops.extras ~= S.extras then
    tops = { seed = S.seed, extras = S.extras }
  end
  if tops[n] then return tops[n] end
  local lo, hi = 34, GROUND_Y - GAP - 36
  local top = lo + hash(n, 1) * (hi - lo)
  if n > 1 then
    local prev = gapFor(n - 1)
    local wobble = driftAmp(n) + driftAmp(n - 1)       -- a drifting hole needs slack
    top = math.max(prev - (CLIMB - wobble), math.min(prev + (DROP - wobble), top))
  end
  tops[n] = top
  return top
end

-- EXTRAS. All of it comes from the seed too, so both players meet the same coins,
-- shields and drifting pipes in the same places.
local function itemFor(n)
  if not S.extras or n < 2 then return nil end
  local r = hash(n, 3.7)
  if n >= 4 and r < 0.09 then return "shield" end      -- rare: survive one crash
  if r < 0.6 then return "coin" end                    -- a bonus point in the gap
  return nil
end

-- from the sixth pipe on, some gaps drift up and down while you fly at them: gently, so a
-- hole never closes on a bird already inside it (it used to move up to 40 px)
local function driftFor(n)
  local amp = driftAmp(n)
  if amp == 0 then return 0 end
  return math.sin(S.run / SPEED * 1.3 + n * 1.3) * amp
end

local function newBird(p)
  return {
    p = p, x = 62, y = VIEW_H * 0.42, vy = 0,
    tilt = 0, flap = 1, flapT = 0,
    alive = true, score = 0, feathers = {}, landed = false, passed = {},
    got = {}, coins = 0, shield = false, safe = 0,
  }
end

local function beginTurn()
  S.scroll = 0
  S.run = 0
  S.bird = newBird(S.turn)
  S.pops = {}
  S.state = "ready"
  S.timer = 0
end

local function startGame(players, who)
  S.seed = math.floor(love.math.random() * 100000) + 1
  S.players = players
  S.turn = (players == 1) and who or 1
  S.round = 1
  S.totals = { 0, 0 }
  S.bestRun = { 0, 0 }
  music.stop()
  beginTurn()
end

local function feathers(b, n, colour)
  for _ = 1, n do
    b.feathers[#b.feathers + 1] = {
      x = b.x, y = b.y, a = love.math.random() * 6.28,
      vx = -20 - love.math.random() * 40, vy = -30 + love.math.random() * 60,
      spin = (love.math.random() - 0.5) * 8,
      life = 0.4 + love.math.random() * 0.4, c = colour,
    }
  end
end

-- Pipes are placed by how far this turn has flown (S.run), which only counts once the
-- bird is actually flying, and the first one starts just off the right edge. Placed by
-- the scenery's scroll instead, they came through the bird while it waited to start.
local PIPE_START = VIEW_W + 20
local function pipesNear(run)
  local out = {}
  local first = math.max(1, math.floor((run - PIPE_START - L.PIPE_W) / PIPE_EVERY) + 1)
  for n = first, first + math.ceil(VIEW_W / PIPE_EVERY) + 2 do
    local top = math.max(18, math.min(GROUND_Y - GAP - 18, gapFor(n) + driftFor(n)))
    out[#out + 1] = { n = n, x = PIPE_START + (n - 1) * PIPE_EVERY - run, top = top,
                      item = itemFor(n) }
  end
  return out
end

local function hits(b, pipes)
  if b.y + 5 >= GROUND_Y then return "ground" end
  if b.y - 5 < 0 then b.y = 5; b.vy = 0 end
  for _, pipe in ipairs(pipes) do
    if b.x + 6 > pipe.x - 3 and b.x - 6 < pipe.x + L.PIPE_W + 3 then
      if b.y - 5 < pipe.top or b.y + 5 > pipe.top + GAP then return "pipe" end
    end
  end
  return nil
end

local function anyFlap()
  -- whoever is flying now; on your own, either seat works
  return flapPressed(S.turn) or (S.players == 1 and flapPressed(3 - S.turn))
end

local function updateFeathers(b, dt)
  for i = #b.feathers, 1, -1 do
    local f = b.feathers[i]
    f.life = f.life - dt
    f.x = f.x + f.vx * dt; f.y = f.y + f.vy * dt
    f.vy = f.vy + 120 * dt; f.a = f.a + f.spin * dt
    if f.life <= 0 then table.remove(b.feathers, i) end
  end
end

local function endTurn()
  local b = S.bird
  S.totals[S.turn] = S.totals[S.turn] + b.score
  if b.score > S.bestRun[S.turn] then S.bestRun[S.turn] = b.score end
  if b.score > S.best then
    S.best = b.score
    love.filesystem.write("best.txt", tostring(S.best))
  end
  if S.players == 1 then
    S.state = "over"
  else
    if S.turn == 2 then S.round = S.round + 1 end
    if S.round > TURNS then
      S.state = "over"
    else
      S.turn = 3 - S.turn
      S.state = "between"
    end
  end
  S.timer = 0
end

-- ------------------------------------------------------------------ update
local function step(dt)
  dt = math.min(dt, 1 / 30)
  S.t = S.t + dt
  S.shake = math.max(0, S.shake - dt)
  S.flash = math.max(0, S.flash - dt)
  S.timer = S.timer + dt
  for i = #S.pops, 1, -1 do
    local pp = S.pops[i]
    pp.t = pp.t + dt
    pp.y = pp.y - 18 * dt
    if pp.t > 0.9 then table.remove(S.pops, i) end
  end

  if S.state == "title" then
    S.idle = S.idle + dt
    S.scroll = S.scroll + SPEED * 0.35 * dt
    for p = 1, 2 do
      -- the stick switches EXTRAS on and off; a button starts
      if stickShoved(p) then
        S.extras = not S.extras
        love.filesystem.write("extras.txt", S.extras and "on" or "off")
        play("menu")
      end
      if flapPressed(p, true) then
        play("menu")
        S.chooser = p
        S.waitT = 0
        S.state = "choose"
        return
      end
    end
  elseif S.state == "choose" then
    -- a few seconds for the other seat to join; otherwise it is a game on your own
    S.waitT = (S.waitT or 0) + dt
    S.scroll = S.scroll + SPEED * 0.35 * dt
    if flapPressed(3 - S.chooser) then play("menu"); startGame(2, S.chooser); return end
    if S.waitT > 0.4 and flapPressed(S.chooser) then startGame(1, S.chooser); return end
    if S.waitT > 4 then startGame(1, S.chooser); return end
  elseif S.state == "ready" then
    S.scroll = S.scroll + SPEED * dt
    S.bird.y = VIEW_H * 0.42 + math.sin(S.t * 5) * 4
    if S.timer > 0.4 and anyFlap() then S.state = "play" end
  elseif S.state == "play" then
    S.scroll = S.scroll + SPEED * dt
    S.run = S.run + SPEED * dt
    local b = S.bird
    local pipes = pipesNear(S.run)
    updateFeathers(b, dt)
    if anyFlap() then
      b.vy = FLAP
      b.flapT = 0.18
      play("flap")
      feathers(b, 2, { 1, 1, 1 })
    end
    b.vy = b.vy + GRAVITY * dt
    b.y = b.y + b.vy * dt
    b.flapT = math.max(0, b.flapT - dt)
    b.flap = b.flapT > 0.09 and 1 or (b.flapT > 0 and 2 or 3)
    local want = math.max(-0.5, math.min(1.2, b.vy / 260))
    b.tilt = b.tilt + (want - b.tilt) * math.min(1, dt * 9)
    for _, pipe in ipairs(pipes) do
      if pipe.x + L.PIPE_W < b.x and not b.passed[pipe.n] then
        b.passed[pipe.n] = true
        b.score = b.score + 1
        play("point")
      end
      -- EXTRAS: the coin or shield sitting in the middle of the gap
      if pipe.item and not b.got[pipe.n] then
        local ix, iy = pipe.x + L.PIPE_W / 2, pipe.top + GAP / 2
        if math.abs(b.x - ix) < 10 and math.abs(b.y - iy) < 11 then
          b.got[pipe.n] = true
          if pipe.item == "coin" then
            b.score = b.score + 1
            b.coins = b.coins + 1
            play("coin")
            S.pops[#S.pops + 1] = { x = ix, y = iy, t = 0, text = "+1", c = { 1, 0.88, 0.25 } }
          else
            b.shield = true
            play("shield")
            S.pops[#S.pops + 1] = { x = ix, y = iy, t = 0, text = "SHIELD", c = { 0.5, 0.95, 1 } }
          end
        end
      end
    end
    b.safe = math.max(0, b.safe - dt)
    local hit = hits(b, pipes)
    if hit and b.safe > 0 then
      -- just saved by a shield: pipes pass through for a moment, the ground bounces
      if hit == "ground" then b.y = GROUND_Y - 6; b.vy = FLAP end
      hit = nil
    elseif hit and b.shield then
      b.shield = false
      b.safe = 1.0
      b.vy = FLAP
      S.shake = 0.12
      play("pop")
      feathers(b, 10, { 0.5, 0.95, 1 })
      S.pops[#S.pops + 1] = { x = b.x, y = b.y - 8, t = 0, text = "SAVED!", c = { 0.5, 0.95, 1 } }
      if hit == "ground" then b.y = GROUND_Y - 6 end
      hit = nil
    end
    if hit then
      b.alive = false
      S.shake = 0.25
      S.flash = 0.25
      feathers(b, 12, { 1, 0.95, 0.75 })
      play("hit"); play("fall")
      S.state = "crashed"
      S.timer = 0
    end
  elseif S.state == "crashed" then
    local b = S.bird
    updateFeathers(b, dt)
    if not b.landed then
      b.vy = b.vy + GRAVITY * 1.2 * dt
      b.y = b.y + b.vy * dt
      b.tilt = math.min(1.4, b.tilt + 4 * dt)
      if b.y + 5 >= GROUND_Y then b.y = GROUND_Y - 5; b.landed = true end
    end
    if S.timer > 1.6 then endTurn() end
  elseif S.state == "between" then
    -- the picture has turned to the other seat; they press when they are ready
    if S.timer > 0.8 and (flapPressed(S.turn) or S.timer > 8) then beginTurn() end
  elseif S.state == "over" then
    if S.timer > 1.5 then
      for p = 1, 2 do
        if flapPressed(p) then startGame(S.players, p); return end
      end
    end
    if S.timer > 14 then
      S.state = "title"; S.idle = 0
      music.play("title", 0.4)
    end
  end
  pressed, jsPressed, shoved = {}, {}, {}
end

-- the presses are used up every frame, however step() ended (several ways return early)
function love.update(dt)
  step(dt)
  pressed, jsPressed, shoved = {}, {}, {}
end

-- ------------------------------------------------------------------ drawing
local function text(s, x, y, colour, scale)
  scale = scale or 1
  g.setColor(colour or { 1, 1, 1 })
  g.print(s, math.floor(x - font:getWidth(s) * scale / 2), math.floor(y), 0, scale, scale)
end

local function shadowText(s, x, y, colour, scale)
  text(s, x + 1, y + 1, { 0, 0, 0, 0.55 }, scale)
  text(s, x, y, colour, scale)
end

local function panel(x, y, w, h)
  g.setColor(0, 0, 0, 0.35)
  g.rectangle("fill", x + 2, y + 3, w, h, 4, 4)
  g.setColor(0.99, 0.96, 0.86)
  g.rectangle("fill", x, y, w, h, 4, 4)
  g.setColor(0.80, 0.72, 0.55)
  g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  g.setColor(1, 1, 1, 0.65)
  g.rectangle("fill", x + 2, y + 2, w - 4, 2, 2, 2)
end

local BIRD_COLOURS = { { 0.98, 0.84, 0.20 }, { 0.95, 0.52, 0.30 } }
local WHO = { "PLAYER 1", "PLAYER 2" }

local function medalFor(score)
  if score >= 40 then return "ruby" elseif score >= 25 then return "gold"
  elseif score >= 12 then return "silver" elseif score >= 5 then return "bronze" end
end

local function drawWorld()
  local score = S.bird and S.bird.score or 0
  local sky, night = L.skyFor(score)
  L.sky(sky)
  L.sun(sky, night, S.t)
  L.clouds(S.scroll, night)
  L.city(S.scroll, night)
  local playing = S.state ~= "title" and S.state ~= "choose"
  if playing then
    for _, pipe in ipairs(pipesNear(S.run)) do
      L.pipe(pipe.x, pipe.top, GAP, night)
      -- EXTRAS: a coin or a shield bubble in the middle of the gap, until it is taken
      if pipe.item and S.bird and not S.bird.got[pipe.n] and S.state ~= "between" then
        local ix, iy = pipe.x + L.PIPE_W / 2, pipe.top + GAP / 2 + math.sin(S.t * 3 + pipe.n) * 2
        if pipe.item == "coin" then
          local w = math.max(1.5, math.abs(math.cos(S.t * 4 + pipe.n)) * 7)   -- spinning
          g.setColor(1, 0.85, 0.3, 0.25)
          g.circle("fill", ix, iy, 10)                                          -- a glow
          g.setColor(0.55, 0.35, 0.05)
          g.ellipse("fill", ix + 1, iy + 1, w, 7)
          g.setColor(1, 0.82, 0.2)
          g.ellipse("fill", ix, iy, w, 7)
          g.setColor(1, 0.97, 0.7)
          g.rectangle("fill", ix - math.min(2, w - 1), iy - 4, 1.5, 4)
        else
          local r = 7 + math.sin(S.t * 5) * 0.8
          g.setColor(0.5, 0.95, 1, 0.25)
          g.circle("fill", ix, iy, r + 3)                                      -- a glow
          g.setColor(0.3, 0.8, 1, 0.55)
          g.circle("fill", ix, iy, r)
          g.setColor(0.85, 1, 1)
          g.circle("line", ix, iy, r)
          g.setColor(1, 1, 1)
          g.rectangle("fill", ix - 4, iy - 4, 2, 2)
        end
      end
    end
  end
  L.ground(S.scroll, night)
  if S.bird and playing and S.state ~= "between" then
    local b = S.bird
    for _, f in ipairs(b.feathers) do L.feather(f) end
    -- just saved by a shield: the bird blinks while it cannot be hurt
    if b.safe <= 0 or math.floor(S.t * 12) % 2 == 0 then
      L.bird(b.x, b.y, b.tilt, b.flap, BIRD_COLOURS[S.turn], not b.alive)
    end
    if b.shield and b.alive then
      g.setColor(0.5, 0.95, 1, 0.18 + 0.08 * math.sin(S.t * 6))
      g.circle("fill", b.x, b.y, 11)
      g.setColor(0.6, 1, 1, 0.8)
      g.circle("line", b.x, b.y, 11)
    end
  end
  for _, pp in ipairs(S.pops) do
    -- outlined all round, like the score, so it reads against sky and pipes alike
    local a = 1 - math.max(0, pp.t - 0.5) / 0.4
    local x, y = math.floor(pp.x - (font:getWidth(pp.text) - 1) / 2), math.floor(pp.y)
    g.setColor(0.1, 0.08, 0.15, 0.85 * a)
    for dx = -1, 1 do for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then g.print(pp.text, x + dx, y + dy) end
    end end
    g.setColor(pp.c[1], pp.c[2], pp.c[3], a)
    g.print(pp.text, x, y)
  end
end

local function drawFront()
  local mid = VIEW_W / 2
  if S.state == "title" or S.state == "choose" then
    panel(mid - 84, 66, 168, 84)
    shadowText("FLAPPY", mid, 72, { 0.95, 0.72, 0.15 }, 3)
    shadowText("BIRD", mid, 98, { 0.95, 0.72, 0.15 }, 2)
    text("A TURN EACH", mid, 120, { 0.35, 0.32, 0.28 })
    text("BEST  " .. S.best, mid, 132, { 0.45, 0.42, 0.36 })
    L.bird(mid, 170 + math.sin(S.t * 4) * 6, math.sin(S.t * 4) * 0.25,
           (math.floor(S.t * 8) % 3) + 1, BIRD_COLOURS[1])
    if S.state == "choose" then
      panel(mid - 104, 200, 208, 44)
      text("STARTING ON YOUR OWN", mid, 206, { 0.35, 0.32, 0.28 })
      text("OTHER SEAT PRESS TO JOIN", mid, 218, { 0.55, 0.35, 0.20 })
      text(string.format("%d", math.max(0, math.ceil(4 - (S.waitT or 0)))), mid, 230, { 0.35, 0.32, 0.28 })
    else
      -- EXTRAS on or off, changed with the stick
      panel(mid - 96, 204, 192, 30)
      local on = S.extras
      text("< EXTRAS " .. (on and "ON" or "OFF") .. " >", mid, 209, on and { 0.2, 0.55, 0.25 } or { 0.55, 0.35, 0.2 })
      text(on and "COINS SHIELDS DRIFTING" or "THE CLASSIC GAME", mid, 221, { 0.45, 0.42, 0.36 })
      if math.floor(S.t * 2) % 2 == 0 then
        shadowText("PRESS A BUTTON", mid, 252, { 1, 1, 1 })
      end
    end
  elseif S.state == "ready" then
    shadowText(WHO[S.turn], mid, 60, { 1, 1, 1 }, 2)
    if S.players == 2 then
      shadowText("TURN " .. S.round .. " OF " .. TURNS, mid, 84, { 1, 1, 1 })
    end
    if math.floor(S.t * 2) % 2 == 0 then
      shadowText("PRESS TO FLY", mid, 106, { 1, 1, 1 })
    end
  elseif S.state == "play" or S.state == "crashed" then
    shadowText(tostring(S.bird.score), mid, 24, { 1, 1, 1 }, 3)
    if S.players == 2 then
      shadowText(WHO[S.turn] .. "   TURN " .. S.round, mid, VIEW_H - 24, { 1, 1, 1 })
    end
  elseif S.state == "between" then
    panel(mid - 80, 112, 160, 76)
    text(WHO[S.turn], mid, 118, { 0.25, 0.22, 0.20 }, 2)
    text("YOUR TURN", mid, 140, { 0.45, 0.42, 0.36 })
    text("TURN " .. S.round .. " OF " .. TURNS, mid, 152, { 0.45, 0.42, 0.36 })
    text("P1  " .. S.totals[1] .. "    P2  " .. S.totals[2], mid, 166, { 0.35, 0.32, 0.28 })
    if S.timer > 0.8 and math.floor(S.t * 2) % 2 == 0 then
      shadowText("PRESS WHEN READY", mid, 200, { 1, 1, 1 })
    end
  elseif S.state == "over" then
    if S.players == 1 then
      panel(mid - 90, 112, 180, 78)
      text("GAME OVER", mid, 118, { 0.85, 0.35, 0.20 }, 2)
      local m = medalFor(S.bestRun[S.turn])
      if m then L.medal(m, mid - 60, 156) end
      text("SCORE", mid + 8, 142, { 0.45, 0.42, 0.36 })
      text(tostring(S.bestRun[S.turn]), mid + 8, 152, { 0.25, 0.22, 0.20 }, 2)
      text("BEST " .. S.best, mid + 8, 172, { 0.45, 0.42, 0.36 })
    else
      panel(mid - 82, 96, 164, 106)
      text("FINAL SCORE", mid, 102, { 0.35, 0.32, 0.28 })
      text("PLAYER 1", mid, 120, { 0.45, 0.42, 0.36 })
      text(tostring(S.totals[1]), mid, 130, { 0.25, 0.22, 0.20 }, 2)
      text("PLAYER 2", mid, 154, { 0.45, 0.42, 0.36 })
      text(tostring(S.totals[2]), mid, 164, { 0.25, 0.22, 0.20 }, 2)
      local word = (S.totals[1] > S.totals[2]) and "PLAYER 1 WINS"
                or (S.totals[2] > S.totals[1]) and "PLAYER 2 WINS" or "A DRAW"
      text(word, mid, 188, { 0.85, 0.35, 0.20 })
    end
    if S.timer > 1.5 and math.floor(S.t * 2) % 2 == 0 then
      shadowText("PRESS TO PLAY AGAIN", mid, 218, { 1, 1, 1 })
    end
  end
end

function love.draw()
  g.setCanvas(screen)
  g.clear(0, 0, 0)
  -- On player 2's turn the whole picture is turned round to face their seat. A game on
  -- your own never turns: you sit where you started.
  local flip = (S.players == 2) and (S.turn == 2)
               and S.state ~= "title" and S.state ~= "choose"
  g.push()
  if flip then
    g.translate(VIEW_W, VIEW_H)
    g.rotate(math.pi)
  end
  drawWorld()
  drawFront()
  g.pop()
  if S.flash > 0 then
    g.setColor(1, 1, 1, S.flash * 0.5)
    g.rectangle("fill", 0, 0, W, H)
  end
  g.setCanvas()
  g.clear(0, 0, 0)
  local sw, sh = g.getDimensions()
  local s = math.max(1, math.floor(math.min(sw / W, sh / H)))
  local ox = math.floor((sw - W * s) / 2)
  local oy = math.floor((sh - H * s) / 2)
  if S.shake > 0 then
    ox = ox + love.math.random(-2, 2) * s
    oy = oy + love.math.random(-2, 2) * s
  end
  g.setColor(1, 1, 1)
  g.draw(screen, ox, oy, 0, s, s)
end

function love.load()
  g.setDefaultFilter("nearest", "nearest")
  font = g.newImageFont("font.png", GLYPHS)
  font:setFilter("nearest", "nearest")
  g.setFont(font)
  screen = g.newCanvas(W, H)
  screen:setFilter("nearest", "nearest")
  L.setup(VIEW_W, VIEW_H)
  makeSounds()
  S.best = tonumber(love.filesystem.read("best.txt") or "0") or 0
  S.extras = (love.filesystem.read("extras.txt") or "on") ~= "off"
  music.play("title", 0.4)
  if not os.getenv("FLAP_WINDOW") then love.window.setFullscreen(true, "desktop") end
  love.mouse.setVisible(false)
  -- a picture of one screen, for checking how everything looks:
  --   FLAP_SHOT=title | titleoff | choose | ready | play | shield | saved | crashed |
  --             between | ready2 | over1 | over2
  local shot = os.getenv("FLAP_SHOT")
  if shot then
    love.audio.setVolume(0)
    S.seed = 4242
    S.extras = shot ~= "titleoff"
    local function flying(players, turn, run, score)
      startGame(players, 1)
      S.seed = 4242
      S.turn = turn
      S.state = "play"
      S.run, S.scroll = run, run
      local b = S.bird
      b.p = turn
      b.score = score
      for _, pipe in ipairs(pipesNear(S.run)) do        -- sit the bird in the next hole
        if pipe.x + L.PIPE_W + 9 > b.x then b.y = pipe.top + GAP / 2; break end
      end
      b.vy, b.tilt = -40, -0.2
      return b
    end
    if shot == "choose" then S.state, S.chooser, S.waitT = "choose", 1, 1.2
    elseif shot == "ready" then startGame(1, 1)
    elseif shot == "ready2" then startGame(2, 1); S.turn = 2; beginTurn(); S.round = 2
    elseif shot == "play" then flying(1, 1, 420, 7)
    elseif shot == "shield" then flying(1, 1, 600, 12).shield = true
    elseif shot == "saved" then
      local b = flying(1, 1, 600, 12)
      b.safe = 0.6
      S.pops = { { x = b.x, y = b.y - 14, t = 0.2, text = "SAVED!", c = { 0.5, 0.95, 1 } } }
    elseif shot == "crashed" then
      local b = flying(1, 1, 420, 7)
      b.alive, S.state, b.tilt = false, "crashed", 1.2
    elseif shot == "between" then
      startGame(2, 1); S.totals = { 14, 0 }; S.turn = 2; S.state = "between"; S.timer = 2
    elseif shot == "over1" then
      startGame(1, 1); S.bestRun = { 23, 0 }; S.best = 31; S.state = "over"; S.timer = 3
    elseif shot == "over2" then
      startGame(2, 1); S.totals = { 42, 37 }; S.state = "over"; S.timer = 3
    end
    S.freeze = true
    S.shots = { 0.12 }
    return
  end
  if os.getenv("FLAP_TEST") == "fair" then
    -- is every course flyable? A careful auto-pilot flies 40 courses (EXTRAS on) to pipe
    -- 60 each; it reports where it crashed and the biggest climb it was asked for
    love.audio.setVolume(0)
    local crashes, worst, lines = 0, 0, {}
    for run = 1, 40 do
      S.extras = true
      startGame(1, 1)
      S.state = "play"
      local b = S.bird
      local steps = 0
      while S.state == "play" and b.score < 60 + b.coins and steps < 60 * 400 do
        steps = steps + 1
        -- aim at the hole it is in or coming to, flap to hold the middle of it
        local aim = VIEW_H * 0.45
        for _, pipe in ipairs(pipesNear(S.run)) do
          if pipe.x + L.PIPE_W + 9 > b.x then aim = pipe.top + GAP * 0.5; break end
        end
        if b.y > aim + 6 and b.vy > 0 then pressed["space"] = true end
        love.update(1 / 60)
      end
      for n = 2, 60 do worst = math.max(worst, gapFor(n - 1) - gapFor(n)) end
      if S.state ~= "play" then
        crashes = crashes + 1
        lines[#lines + 1] = ("  course %d: crashed at pipe %d"):format(run, b.score - b.coins + 1)
      end
    end
    lines[#lines + 1] = ("%d of 40 courses crashed; the biggest climb asked for was %d px")
      :format(crashes, math.floor(worst + 0.5))
    print(table.concat(lines, "\n"))
    love.event.quit()
    return
  end
  if os.getenv("FLAP_TEST") then
    S.shots = { 2, 6, 11, 17, 24 }
    startGame(2, 1)
    S.auto = true
  end
end

local realUpdate = love.update
function love.update(dt)
  -- the self test flies for itself, so the pictures show a real game
  if S.auto then
    -- press for whoever is flying: player 1's key does nothing on player 2's turn
    local flapKey = (S.players == 2 and S.turn == 2) and "m" or "space"
    if S.state == "play" and S.bird then
      local b = S.bird
      local aim = VIEW_H * 0.45
      for _, pipe in ipairs(pipesNear(S.run)) do
        if pipe.x + L.PIPE_W > b.x - 10 then aim = pipe.top + GAP * 0.5; break end
      end
      if b.y > aim + 4 and b.vy > -40 then pressed[flapKey] = true end
    elseif S.state == "ready" or S.state == "between" or S.state == "over" then
      pressed[flapKey] = true
    end
  end
  if S.freeze then
    S.t = S.t + dt               -- a screen held still for its picture (FLAP_SHOT)
  else
    realUpdate(dt)
  end
  if S.shots then
    S.shotT = (S.shotT or 0) + dt
    if S.shots[1] and S.shotT >= S.shots[1] then
      table.remove(S.shots, 1)
      local name = os.getenv("FLAP_SHOT") and ("shot_" .. os.getenv("FLAP_SHOT"))
                   or ("flap" .. math.floor(S.shotT))
      g.captureScreenshot(name .. ".png")
    end
    if #S.shots == 0 then love.event.quit() end
  end
end
