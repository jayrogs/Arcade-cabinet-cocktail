-- Pong for a cocktail table. One player at each end of the screen, facing each other;
-- nothing ever has to turn round, because the table itself is the court.
--
-- The screen is drawn at 192 x 256 and blown up by a whole number, so every pixel is the
-- same size (the cabinet's 768 x 1024 is exactly four times). Player 1 sits at the bottom,
-- player 2 at the top: player 2's stick is mirrored (their left is our right) and their
-- words and score are drawn upside down, facing them.
--
-- Keys, for a keyboard: player 1 left/right (or A / D), Z for the power shot, 1 to start;
-- player 2 J / L, M for the power shot, 2 to start. Escape quits.

local g = love.graphics
local music = require("music")
local W, H = 192, 256
local GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,-:<>!?/'#@"

-- the cabinet: which USB pad is which player, by name. The made-up phone pads are named
-- "Cab Web Panel" (player 1) and "Cab Web Panel 2" (player 2); anything else is the real
-- control panel, in the order the Pi lists it.
local WEB1, WEB2 = "Cab Web Panel", "Cab Web Panel 2"
local AXIS_EDGE = 0.5
local START_BUTTON = 8   -- the panel's Player 1 / Player 2 button, as LÖVE numbers it

local CFG = {
  toWin = 7,           -- points to win: 5, 7 or 11
  cpu = 2,             -- machine level 1..3 when one person plays
  mirrorP2 = true,     -- player 2's stick reads from their seat, not ours
  demoAfter = 20,      -- seconds idle on the title before the machine plays itself
}

-- ---------------------------------------------------------------- sounds, made here
local sfx = {}
local function tone(freq, secs, kind, vol)
  local rate = 22050
  local n = math.floor(rate * secs)
  local sd = love.sound.newSoundData(n, rate, 16, 1)
  for i = 0, n - 1 do
    local t = i / rate
    local env = 1 - i / n         -- every sound fades out over its own length
    local v
    if kind == "square" then
      v = (math.sin(2 * math.pi * freq * t) > 0) and 1 or -1
    elseif kind == "thud" then
      -- the note, its octave under it for weight, and a scrape of noise at the very start
      local a = (math.sin(2 * math.pi * freq * t) > 0) and 1 or -1
      local b = math.sin(2 * math.pi * freq * 0.5 * t)
      local knock = (i < n * 0.06) and (love.math.random() * 2 - 1) * 0.7 or 0
      v = a * 0.55 + b * 0.45 + knock
      env = env * env                      -- falls away quickly, like a hit
    elseif kind == "boom" then
      -- the power shot: the same knock, but the pitch drops as it goes
      local f = freq * (1 + 0.8 * (1 - i / n))
      local a = (math.sin(2 * math.pi * f * t) > 0) and 1 or -1
      v = a * 0.7 + math.sin(2 * math.pi * f * 0.5 * t) * 0.5
      env = env * env
    elseif kind == "slide" then       -- falls in pitch: the score sound
      v = math.sin(2 * math.pi * (freq * (1 - 0.6 * i / n)) * t)
    elseif kind == "noise" then
      v = (love.math.random() * 2 - 1)
    else
      v = math.sin(2 * math.pi * freq * t)
    end
    sd:setSample(i, v * env * (vol or 0.5))
  end
  return love.audio.newSource(sd, "static"), sd
end

local function makeSounds()
  -- low and thick: a bright little beep sounds tinny on a cabinet speaker, so each hit
  -- is a deep square wave with a touch of noise on the front, like a real knock
  sfx.paddle = tone(150, 0.11, "thud", 0.55)
  sfx.wall = tone(110, 0.09, "thud", 0.4)
  sfx.power = tone(90, 0.22, "boom", 0.6)
  sfx.score = tone(180, 0.45, "slide", 0.5)
  sfx.menu = tone(330, 0.05, "square", 0.25)
  sfx.win = {}
  for i, f in ipairs({ 523, 659, 784, 1047 }) do sfx.win[i] = tone(f, 0.16, "square", 0.35) end
end

local function play(name)
  local s = sfx[name]
  if s then s:stop(); s:play() end
end

-- ---------------------------------------------------------------- the game
local S = {
  state = "title",         -- title | play | point | over | demo
  t = 0, idle = 0,
  sel = 1,                 -- title cursor: 1 START, 2 mode, 3 machine level, 4 points
  mode = 2,                -- what START begins: 2 players, or 1 against the machine
  players = 2,
  human = { true, true },
  score = { 0, 0 },
  serveTo = 1,
  pad = { { x = W / 2, vx = 0, w = 28, cool = 0, boost = 0 },
          { x = W / 2, vx = 0, w = 28, cool = 0, boost = 0 } },
  ball = { x = W / 2, y = H / 2, vx = 0, vy = 0, speed = 0, trail = {} },
  rally = 0, bestRally = 0,
  shake = 0, flash = 0, timer = 0,
  sparks = {},
  winner = nil,
  msg = nil,
}
local PAD_H = 4
local PAD_Y = { H - 12, 8 }         -- player 1 at the bottom, player 2 at the top
local BALL = 4
local SPEED0, SPEED_UP, SPEED_MAX = 110, 1.07, 380
local POWER = 1.45
local COOLDOWN = 2.5

local font, screen, scaleNow

-- ---------------------------------------------------------------- input
local pressed = {}       -- keyboard presses this frame
local jsPressed = {}     -- joystick presses this frame, by joystick object
local KEYS = {
  { left = { "left", "a" }, right = { "right", "d" }, up = { "up", "w" }, down = { "down", "s" },
    fire = { "z", "lctrl" }, start = { "1" } },
  { left = { "j" }, right = { "l" }, up = { "i" }, down = { "k" }, fire = { "m", "rctrl" }, start = { "2" } },
}

local function padsFor(p)
  -- every pad that should drive player p
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

local function rawAxis(js, vertical)
  -- -1 .. 1 sideways (or up and down), from the hat or the first two axes
  local lo, hi, axis = "l", "r", 1
  if vertical then lo, hi, axis = "u", "d", 2 end
  for h = 1, js:getHatCount() do
    local v = js:getHat(h)
    if v and v:find(lo) then return -1 end
    if v and v:find(hi) then return 1 end
  end
  if js:getAxisCount() >= axis then
    local x = js:getAxis(axis)
    if x < -AXIS_EDGE then return -1 end
    if x > AXIS_EDGE then return 1 end
  end
  return 0
end

local function keyDown(list)
  for _, k in ipairs(list) do if love.keyboard.isDown(k) then return true end end
  return false
end

local function keyPressed(list)
  for _, k in ipairs(list) do if pressed[k] then return true end end
  return false
end

-- sideways -1..1 for player p, from their own seat
local function steer(p)
  local v = 0
  if keyDown(KEYS[p].left) then v = -1 elseif keyDown(KEYS[p].right) then v = 1 end
  for _, js in ipairs(padsFor(p)) do
    local a = rawAxis(js)
    if a ~= 0 then v = a end
  end
  if p == 2 and CFG.mirrorP2 then v = -v end
  return v
end

-- up and down, from the player's own seat (player 2's up is our down): for the menu
local function updown(p)
  local v = 0
  if keyDown(KEYS[p].up) then v = -1 elseif keyDown(KEYS[p].down) then v = 1 end
  for _, js in ipairs(padsFor(p)) do
    local a = rawAxis(js, true)
    if a ~= 0 then v = a end
  end
  if p == 2 and CFG.mirrorP2 then v = -v end
  return v
end

local function anyButtonDown(p)
  if keyDown(KEYS[p].fire) then return true end
  for _, js in ipairs(padsFor(p)) do
    for b = 1, js:getButtonCount() do if js:isDown(b) then return true end end
  end
  return false
end

local function anyButtonPressed(p)
  if keyPressed(KEYS[p].fire) or keyPressed(KEYS[p].start) then return true end
  for _, js in ipairs(padsFor(p)) do
    if jsPressed[js] then return true end
  end
  return false
end

local function anyInput()
  for p = 1, 2 do
    if anyButtonPressed(p) or steer(p) ~= 0 then return true end
  end
  return false
end

function love.keypressed(k) pressed[k] = true end
function love.joystickpressed(js, b) jsPressed[js] = b end

-- ---------------------------------------------------------------- play
local function spark(x, y, n, colour)
  for i = 1, n do
    local a = love.math.random() * math.pi * 2
    local sp = 20 + love.math.random() * 60
    S.sparks[#S.sparks + 1] = { x = x, y = y, vx = math.cos(a) * sp, vy = math.sin(a) * sp,
                                life = 0.25 + love.math.random() * 0.25, c = colour }
  end
end

local function serve()
  local b = S.ball
  b.x, b.y = W / 2, H / 2
  b.speed = SPEED0
  local dir = (S.serveTo == 1) and 1 or -1            -- toward the player who receives
  local a = (love.math.random() * 0.8 - 0.4)          -- a bit sideways, never flat
  b.vx = math.sin(a) * b.speed
  b.vy = math.cos(a) * b.speed * dir
  b.trail = {}
  S.rally = 0
end

local function newGame(players, whoStarted)
  music.play("play", 0.4)
  S.players = players
  if players == 2 then
    S.human = { true, true }
  else
    S.human = { whoStarted == 1, whoStarted == 2 }
  end
  S.score = { 0, 0 }
  S.winner = nil
  for p = 1, 2 do S.pad[p].x = W / 2; S.pad[p].cool = 0; S.pad[p].boost = 0 end
  S.serveTo = love.math.random(2)
  S.bestRally = 0
  S.state = "point"
  S.timer = 1.0
  S.msg = nil
  serve()
end

-- How well the machine plays. It used to know exactly where every ball would land at
-- every level, differing only in speed, so even EASY hit nearly everything.
--   predict  works out where the ball will cross its line (else chases where it is now)
--   miss     its aim is off by up to this much each time the ball comes (paddle half-width
--            is 14, so beyond that it can miss outright)
--   react    seconds before it starts moving to a ball coming its way
--   speed    how fast its paddle moves (a person's moves at 150)
--   power    chance of a power shot on each return
local MACHINE = {                      -- measured against a stand-in person (PONG_TEST=difficulty):
  { predict = true, miss = 18, react = 0.28, speed = 105, power = 0 },     -- EASY:   you win ~85-90%
  { predict = true, miss = 16, react = 0.22, speed = 125, power = 0.05 },  -- NORMAL: ~55%, a fair match
  { predict = true, miss = 15, react = 0.16, speed = 145, power = 0.1 },   -- HARD:   ~20%
}
local DEMO_MACHINE = { predict = true, miss = 4, react = 0.1, speed = 170, power = 0.25 }

local function landing(p)
  -- where the ball will cross player p's line, folded back off the walls
  local b = S.ball
  local dist = math.abs(PAD_Y[p] - b.y)
  local tx = b.x + b.vx * (dist / math.max(1, math.abs(b.vy)))
  while tx < 0 or tx > W do
    if tx < 0 then tx = -tx else tx = 2 * W - tx end
  end
  return tx
end

local function machineFor()
  return S.state == "demo" and DEMO_MACHINE or MACHINE[CFG.cpu]
end

local function cpuSteer(p, dt)
  local b, pad, m = S.ball, S.pad[p], machineFor()
  local coming = (p == 1 and b.vy > 0) or (p == 2 and b.vy < 0)
  if coming and not pad.tracking then
    -- a new ball on its way: a fresh mistake, and a moment before it reacts
    pad.tracking = true
    pad.err = (love.math.random() * 2 - 1) * m.miss
    pad.wait = m.react
  elseif not coming then
    pad.tracking = false
  end
  local target = pad.target or W / 2
  if coming then
    pad.wait = (pad.wait or 0) - dt
    if pad.wait <= 0 then
      target = (m.predict and landing(p) or b.x + BALL / 2) + pad.err
    end
  else
    target = W / 2                                     -- drift back to the middle
  end
  pad.target = target
  local d = target - pad.x
  local v = 0
  if math.abs(d) > 2 then v = (d > 0) and 1 or -1 end
  return v, m.speed
end

local function movePads(dt)
  for p = 1, 2 do
    local pad = S.pad[p]
    local v, maxv
    if S.human[p] and S.state ~= "demo" then
      v, maxv = steer(p), 150
      if S.testBot then v = S.testBot(p, dt) end    -- the difficulty test's stand-in player
    else
      v, maxv = cpuSteer(p, dt)
    end
    local before = pad.x
    pad.x = math.max(pad.w / 2 + 2, math.min(W - pad.w / 2 - 2, pad.x + v * maxv * dt))
    pad.vx = (pad.x - before) / math.max(dt, 1e-4)
    pad.cool = math.max(0, pad.cool - dt)
    pad.boost = math.max(0, pad.boost - dt)
  end
end

local function hitPaddle(p)
  local b, pad = S.ball, S.pad[p]
  local off = (b.x - pad.x) / (pad.w / 2)             -- -1 .. 1 across the paddle
  off = math.max(-1, math.min(1, off))
  b.speed = math.min(SPEED_MAX, b.speed * SPEED_UP)
  local powered = false
  if pad.cool <= 0 and ((S.human[p] and S.state ~= "demo" and anyButtonDown(p))
                        or ((not S.human[p] or S.state == "demo") and love.math.random() < machineFor().power)) then
    powered = true
    pad.cool = COOLDOWN
    pad.boost = 0.4
  end
  local speed = b.speed * (powered and POWER or 1)
  local angle = off * 0.9 + (pad.vx / 150) * 0.25      -- where it hit, plus a little spin
  angle = math.max(-1.1, math.min(1.1, angle))
  b.vx = math.sin(angle) * speed
  b.vy = math.cos(angle) * speed * ((p == 1) and -1 or 1)
  b.y = (p == 1) and (PAD_Y[1] - BALL) or (PAD_Y[2] + PAD_H)
  S.rally = S.rally + 1
  if S.rally > S.bestRally then S.bestRally = S.rally end
  spark(b.x + BALL / 2, b.y + BALL / 2, powered and 14 or 6, powered and { 1, 0.9, 0.3 } or { 1, 1, 1 })
  play(powered and "power" or "paddle")
  if powered then S.shake = 0.15 end
end

local function pointFor(p)
  S.score[p] = S.score[p] + 1
  S.serveTo = 3 - p                                     -- the one who lost it receives
  S.shake = 0.3
  S.flash = 0.25
  spark(S.ball.x + BALL / 2, S.ball.y + BALL / 2, 20, { 1, 0.4, 0.4 })
  play("score")
  if S.score[p] >= CFG.toWin then
    S.state = "over"
    S.winner = p
    S.timer = 6
    music.duck(0.15)
    for i, s in ipairs(sfx.win) do
      s:stop(); s:play()   -- plays as a chord; good enough for a tiny speaker
    end
  else
    S.state = (S.state == "demo") and "demo" or "point"
    S.timer = 1.1
    serve()
    if S.state == "demo" then S.timer = 1.1 end
  end
end

local function moveBall(dt)
  local b = S.ball
  -- small steps so a fast ball never skips through a paddle
  local steps = math.max(1, math.ceil(math.abs(b.vy) * dt / 2))
  local sdt = dt / steps
  for _ = 1, steps do
    b.x = b.x + b.vx * sdt
    b.y = b.y + b.vy * sdt
    if b.x <= 0 then b.x = 0; b.vx = math.abs(b.vx); play("wall"); spark(b.x, b.y + 2, 3, { 0.7, 0.8, 1 })
    elseif b.x + BALL >= W then b.x = W - BALL; b.vx = -math.abs(b.vx); play("wall"); spark(b.x + BALL, b.y + 2, 3, { 0.7, 0.8, 1 }) end
    -- player 1's paddle, at the bottom
    local p1 = S.pad[1]
    if b.vy > 0 and b.y + BALL >= PAD_Y[1] and b.y + BALL <= PAD_Y[1] + PAD_H + 2
       and b.x + BALL >= p1.x - p1.w / 2 and b.x <= p1.x + p1.w / 2 then
      hitPaddle(1)
    end
    local p2 = S.pad[2]
    if b.vy < 0 and b.y <= PAD_Y[2] + PAD_H and b.y >= PAD_Y[2] - 2
       and b.x + BALL >= p2.x - p2.w / 2 and b.x <= p2.x + p2.w / 2 then
      hitPaddle(2)
    end
    if b.y > H + 8 then pointFor(2); return end
    if b.y < -8 - BALL then pointFor(1); return end
  end
  table.insert(b.trail, 1, { b.x, b.y })
  if #b.trail > 10 then table.remove(b.trail) end
end

local function updateSparks(dt)
  for i = #S.sparks, 1, -1 do
    local s = S.sparks[i]
    s.life = s.life - dt
    s.x = s.x + s.vx * dt; s.y = s.y + s.vy * dt
    s.vx = s.vx * 0.9; s.vy = s.vy * 0.9
    if s.life <= 0 then table.remove(S.sparks, i) end
  end
end

-- ---------------------------------------------------------------- title
local OPTIONS = 4
-- The title is a big START button with the settings under it. A button on START begins
-- the game; a button on a setting changes it. The cabinet's own Start buttons (and 1 / 2
-- on a keyboard) begin the game from anywhere on the list.
local function startGame(p)
  play("menu")
  newGame(S.mode, p)
end

local function startPressed(p)
  if keyPressed(KEYS[p].start) then return true end
  for _, js in ipairs(padsFor(p)) do
    if jsPressed[js] == START_BUTTON then return true end
  end
  return false
end

local function titleAct(p)
  if S.sel == 1 then startGame(p)
  elseif S.sel == 2 then S.mode = 3 - S.mode; play("menu")
  elseif S.sel == 3 then CFG.cpu = CFG.cpu % 3 + 1; play("menu")
  elseif S.sel == 4 then
    CFG.toWin = ({ [5] = 7, [7] = 11, [11] = 5 })[CFG.toWin] or 7
    play("menu")
  end
end

local function updateTitle(dt)
  S.idle = S.idle + dt
  S.held = S.held or { false, false }
  for p = 1, 2 do
    -- down or right steps the cursor on; the stick has to come back to the middle
    -- before it counts again, so one push is one step
    local v = updown(p)
    if v == 0 then v = steer(p) end
    if v ~= 0 and not S.held[p] then
      S.held[p] = true
      S.sel = ((S.sel - 1 + v) % OPTIONS) + 1
      play("menu")
    elseif v == 0 then
      S.held[p] = false
    end
    if startPressed(p) then startGame(p) return end
    if anyButtonPressed(p) then titleAct(p) end
    if S.state ~= "title" then return end
  end
  if S.idle > CFG.demoAfter then
    S.state = "demo"
    music.play("play", 0.35)
    S.human = { false, false }
    S.score = { 0, 0 }
    S.serveTo = 1
    S.winner = nil
    S.timer = 0.5
    serve()
  end
end

-- ---------------------------------------------------------------- update
function love.update(dt)
  dt = math.min(dt, 1 / 30)
  S.t = S.t + dt
  S.shake = math.max(0, S.shake - dt)
  S.flash = math.max(0, S.flash - dt)
  updateSparks(dt)
  if S.state == "title" then
    updateTitle(dt)
  elseif S.state == "point" then
    movePads(dt)
    S.timer = S.timer - dt
    if S.timer <= 0 then S.state = "play" end
  elseif S.state == "play" then
    movePads(dt)
    moveBall(dt)
  elseif S.state == "over" then
    S.timer = S.timer - dt
    if S.timer <= 0 or anyInput() then
      S.state = "title"; S.idle = 0
      music.play("title", 0.45)
    end
  elseif S.state == "demo" then
    if anyInput() then
      S.state = "title"; S.idle = 0; S.score = { 0, 0 }
      music.play("title", 0.45)
      return
    end
    movePads(dt)
    if S.timer > 0 then
      S.timer = S.timer - dt
    else
      moveBall(dt)
    end
    if S.winner then
      S.winner = nil; S.score = { 0, 0 }; S.state = "demo"; S.timer = 1; serve()
    end
  end
  pressed = {}
  jsPressed = {}
end

-- ---------------------------------------------------------------- draw
local function text(s, x, y, colour, flip, scale)
  -- x, y is the centre; flip draws it upside down, for the player at the far end
  scale = scale or 1
  -- the font counts a blank column after every letter, the last one too: leave that one
  -- out, or everything sits a pixel off centre (two at double size)
  local w = (font:getWidth(s) - 1) * scale
  g.setColor(colour or { 1, 1, 1 })
  if flip then
    g.print(s, x + w / 2, y + 4 * scale, math.pi, scale, scale)
  else
    g.print(s, x - w / 2, y - 4 * scale, 0, scale, scale)
  end
end

local function both(s, y1, y2, colour, scale)
  -- the same words at each end, each facing its player
  text(s, W / 2, y1, colour, false, scale)
  text(s, W / 2, y2, colour, true, scale)
end

local function ballColour()
  local h = (S.ball.speed - SPEED0) / (SPEED_MAX - SPEED0)
  return { 1, 1 - 0.55 * h, 1 - 0.9 * h }
end

local function drawCourt()
  g.setColor(0.18, 0.18, 0.26)
  for y = 6, H - 6, 8 do g.rectangle("fill", W / 2 - 1, y, 2, 4) end
  g.setColor(0.28, 0.28, 0.4)
  g.rectangle("fill", 0, 0, 1, H); g.rectangle("fill", W - 1, 0, 1, H)
end

local function drawScores()
  local c1 = S.human[1] and { 0.55, 0.85, 1 } or { 0.7, 0.7, 0.75 }
  local c2 = S.human[2] and { 1, 0.7, 0.55 } or { 0.7, 0.7, 0.75 }
  text(tostring(S.score[1]), W / 2 - 40, H - 40, c1, false, 2)
  text(tostring(S.score[2]), W / 2 + 40, 40, c2, true, 2)
  -- the power-shot bar beside each score: full means it is ready
  for p = 1, 2 do
    local pad = S.pad[p]
    local frac = 1 - pad.cool / COOLDOWN
    local x = (p == 1) and (W / 2 - 52) or (W / 2 + 28)
    local y = (p == 1) and (H - 30) or 26
    g.setColor(0.2, 0.2, 0.28)
    g.rectangle("fill", x, y, 24, 2)
    g.setColor(frac >= 1 and { 1, 0.9, 0.3 } or { 0.5, 0.5, 0.6 })
    g.rectangle("fill", x, y, 24 * frac, 2)
  end
  if S.rally >= 5 then
    local c = { 0.5, 0.5, 0.6, math.min(1, (S.rally - 4) / 6) }
    both(S.rally .. " HITS", H / 2 + 20, H / 2 - 20, c)
  end
end

local function drawPlay()
  drawCourt()
  drawScores()
  local b = S.ball
  -- the trail, then the ball
  for i, t in ipairs(b.trail) do
    local a = (1 - i / #b.trail) * 0.5
    local c = ballColour()
    g.setColor(c[1], c[2], c[3], a)
    g.rectangle("fill", t[1], t[2], BALL, BALL)
  end
  if S.state ~= "point" or math.floor(S.t * 10) % 2 == 0 then
    g.setColor(ballColour())
    g.rectangle("fill", b.x, b.y, BALL, BALL)
  end
  for p = 1, 2 do
    local pad = S.pad[p]
    local c = (p == 1) and { 0.55, 0.85, 1 } or { 1, 0.7, 0.55 }
    if pad.boost > 0 then c = { 1, 0.95, 0.5 } end
    g.setColor(c)
    g.rectangle("fill", pad.x - pad.w / 2, PAD_Y[p], pad.w, PAD_H)
  end
  for _, s in ipairs(S.sparks) do
    g.setColor(s.c[1], s.c[2], s.c[3], math.min(1, s.life * 4))
    g.rectangle("fill", s.x, s.y, 1, 1)
  end
  if S.state == "point" and S.score[1] + S.score[2] > 0 then
    -- who just scored, in their own colour, said to both ends
    local last = 3 - S.serveTo
    both("POINT " .. (last == 1 and "BLUE" or "ORANGE"), H / 2 + 40, H / 2 - 40,
         last == 1 and { 0.55, 0.85, 1 } or { 1, 0.7, 0.55 })
  end
  if S.state == "over" and S.winner then
    local win = S.winner
    local c = win == 1 and { 0.55, 0.85, 1 } or { 1, 0.7, 0.55 }
    local who = win == 1 and "BLUE" or "ORANGE"
    if math.floor(S.t * 3) % 2 == 0 then
      both(who .. " WINS!", H / 2 + 40, H / 2 - 40, c, 1)
    end
    if S.bestRally >= 3 then both("BEST RALLY " .. S.bestRally, H / 2 + 56, H / 2 - 56, { 0.6, 0.6, 0.7 }) end
  end
  if S.state == "demo" then
    if math.floor(S.t * 2) % 2 == 0 then
      both("DEMO", H / 2 + 34, H / 2 - 34, { 1, 0.8, 0.2 })
    end
  end
end

local function drawTitle()
  drawCourt()
  -- a ball bounces about behind the title for life
  local bx = W / 2 + math.sin(S.t * 1.3) * 70
  local by = H / 2 + math.cos(S.t * 0.9) * 90
  g.setColor(0.25, 0.25, 0.35)
  g.rectangle("fill", bx, by, BALL, BALL)
  local settings = {
    "MODE: " .. (S.mode == 2 and "2 PLAYERS" or "VS MACHINE"),
    "MACHINE: " .. ({ "EASY", "NORMAL", "HARD" })[CFG.cpu],
    "FIRST TO " .. CFG.toWin,
  }
  local glow = 0.5 + 0.5 * math.sin(S.t * 5)
  -- each end is laid out for player 1 at the bottom; player 2's is the same turned round
  -- (y measured from their edge instead of ours)
  for end_ = 1, 2 do
    local flip = end_ == 2
    local function Y(fromEdge) return flip and fromEdge or (H - fromEdge) end
    text("PONG", W / 2, Y(100), { 1, 1, 1 }, flip, 2)

    -- the START button: a small framed box, lit and pulsing while it is the one chosen
    local on = S.sel == 1
    local bw, bh = 56, 15
    local bx, by = W / 2 - bw / 2, Y(70) - bh / 2
    if on then
      g.setColor(0.2, 0.8, 1, 0.1 * glow + 0.05)       -- a soft glow round it
      g.rectangle("fill", bx - 3, by - 3, bw + 6, bh + 6, 4, 4)
      g.setColor(0.1, 0.45 + 0.2 * glow, 0.6 + 0.2 * glow)
    else
      g.setColor(0.08, 0.1, 0.16)
    end
    g.rectangle("fill", bx, by, bw, bh, 3, 3)
    g.setColor(on and { 0.6, 1, 1 } or { 0.35, 0.4, 0.55 })
    g.rectangle("line", bx + 0.5, by + 0.5, bw - 1, bh - 1, 3, 3)
    text("START", W / 2, Y(70), on and { 1, 1, 1 } or { 0.55, 0.6, 0.7 }, flip)

    -- the settings under it, with room to breathe
    for i, s in ipairs(settings) do
      local here = S.sel == i + 1
      local c = here and { 1, 0.9, 0.3 } or { 0.5, 0.5, 0.6 }
      -- the words are centred on their own; the marker sits just before them (a "> "
      -- or blank in front pushed every line off centre)
      text(s, W / 2, Y(46 - (i - 1) * 12), c, flip)
      if here then
        local half = font:getWidth(s) / 2 + 7
        text(">", flip and (W / 2 + half) or (W / 2 - half), Y(46 - (i - 1) * 12), c, flip)
      end
    end
  end
  -- the middle of the court is left to the ball bouncing about
end

function love.draw()
  g.setCanvas(screen)
  g.clear(0.03, 0.03, 0.05)
  if S.flash > 0 then
    g.setColor(1, 1, 1, S.flash * 0.4)
    g.rectangle("fill", 0, 0, W, H)
  end
  if S.state == "title" then drawTitle() else drawPlay() end
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
  love.graphics.setDefaultFilter("nearest", "nearest")
  font = g.newImageFont("font.png", GLYPHS)
  font:setFilter("nearest", "nearest")
  g.setFont(font)
  screen = g.newCanvas(W, H)
  screen:setFilter("nearest", "nearest")
  makeSounds()
  music.load("play")            -- built now, so the first game does not stutter
  music.play("title", 0.45)
  if not os.getenv("PONG_WINDOW") then
    love.window.setFullscreen(true, "desktop")
  end
  love.mouse.setVisible(false)
  -- a self test: the machine plays itself and pictures are saved, then it quits
  if os.getenv("PONG_TEST") == "audio" then
    local A = require("audiotest")
    local made = {}
    local _, sd
    _, sd = tone(150, 0.11, "thud", 0.55); A.stats("paddle", sd)
    _, sd = tone(110, 0.09, "thud", 0.4);  A.stats("wall", sd)
    _, sd = tone(90, 0.22, "boom", 0.6);   A.stats("power", sd)
    _, sd = tone(180, 0.45, "slide", 0.5); A.stats("score", sd)
    for _, k in ipairs({ "title", "play" }) do A.stats(k, music.data(k)) end
    love.filesystem.write("audio.txt", table.concat(A.out, string.char(10)))
    love.event.quit()
    return
  end
  if os.getenv("PONG_TEST") == "difficulty" then
    -- each machine level against a stand-in person (reads the ball, but a fifth of a second
    -- late and up to 16 pixels off, missing about one ball in ten), for three hours of play each; prints who won the points
    love.audio.setVolume(0)
    local bot = {}
    S.testBot = function(p, dt)
      local b, pad = S.ball, S.pad[p]
      local coming = (p == 1 and b.vy > 0) or (p == 2 and b.vy < 0)
      if coming and not bot.tracking then
        bot.tracking, bot.wait, bot.err = true, 0.22, (love.math.random() * 2 - 1) * 16
      elseif not coming then
        bot.tracking = false
      end
      local target = W / 2
      if coming then
        bot.wait = bot.wait - dt
        target = bot.wait <= 0 and (landing(p) + bot.err) or pad.x
      end
      local d = target - pad.x
      return math.abs(d) > 2 and ((d > 0) and 1 or -1) or 0
    end
    local lines = {}
    for level = 1, 3 do
      CFG.cpu = level
      local won = { 0, 0 }
      newGame(1, 1)
      local last = { 0, 0 }
      for _ = 1, 60 * 60 * 180 do
        love.update(1 / 60)
        for p = 1, 2 do
          if S.score[p] > last[p] then won[p] = won[p] + (S.score[p] - last[p]) end
        end
        last = { S.score[1], S.score[2] }
        if S.state == "over" or S.state == "title" then newGame(1, 1); last = { 0, 0 } end
      end
      lines[#lines + 1] = ("%-6s you win %3d%% of points (%d to %d)"):format(
        ({ "EASY", "NORMAL", "HARD" })[level], math.floor(100 * won[1] / math.max(1, won[1] + won[2]) + 0.5),
        won[1], won[2])
      print(lines[#lines])
    end
    love.filesystem.write("difficulty.txt", table.concat(lines, string.char(10)))
    love.event.quit()
    return
  end
  if os.getenv("PONG_TEST") == "title" then
    S.test = { 1, 2 }
  elseif os.getenv("PONG_TEST") then
    S.state = "demo"; S.human = { false, false }; S.timer = 0.3; serve()
    S.test = { 2, 6, 10, 14 }
  end
end

local testT = 0
local realUpdate = love.update
function love.update(dt)
  realUpdate(dt)
  if S.test then
    testT = testT + dt
    if S.test[1] and testT >= S.test[1] then
      table.remove(S.test, 1)
      love.graphics.captureScreenshot("shot" .. math.floor(testT) .. ".png")
    end
    if #S.test == 0 then love.event.quit() end
  end
end

function love.keypressed(k)
  if k == "escape" then love.event.quit() end
  pressed[k] = true
end
