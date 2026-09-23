-- Flap : a flapping game for a cocktail table, played a turn each.
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

local function flapPressed(p)
  for _, k in ipairs(KEYS[p].flap) do if pressed[k] then return true end end
  for _, k in ipairs(KEYS[p].start) do if pressed[k] then return true end end
  for _, js in ipairs(padsFor(p)) do
    if jsPressed[js] then return true end
    -- the stick counts too: shoved any way, it flaps
    for h = 1, js:getHatCount() do
      local v = js:getHat(h)
      if v and v ~= "c" and not (js.lastHat == v) then js.lastHat = v; return true end
    end
  end
  return false
end

function love.joystickpressed(js, b) jsPressed[js] = b end
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
  scroll = 0,
  players = 1, turn = 1, round = 1,
  totals = { 0, 0 }, bestRun = { 0, 0 },
  bird = nil, best = 0,
  shake = 0, flash = 0, timer = 0,
}

local function gapFor(n)
  -- the nth pipe's hole, from the seed alone, so every turn flies the same run
  local x = math.sin(n * 12.9898 + S.seed * 78.233) * 43758.5453
  local r = x - math.floor(x)
  return 34 + r * (GROUND_Y - GAP - 70)
end

local function newBird(p)
  return {
    p = p, x = 62, y = VIEW_H * 0.42, vy = 0,
    tilt = 0, flap = 1, flapT = 0,
    alive = true, score = 0, feathers = {}, landed = false, passed = {},
  }
end

local function beginTurn()
  S.scroll = 0
  S.bird = newBird(S.turn)
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

local function pipesNear(scroll)
  local out = {}
  local first = math.floor((scroll - 40) / PIPE_EVERY)
  for n = first, first + math.ceil(VIEW_W / PIPE_EVERY) + 2 do
    if n >= 1 then
      out[#out + 1] = { n = n, x = n * PIPE_EVERY - scroll, top = gapFor(n) }
    end
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
function love.update(dt)
  dt = math.min(dt, 1 / 30)
  S.t = S.t + dt
  S.shake = math.max(0, S.shake - dt)
  S.flash = math.max(0, S.flash - dt)
  S.timer = S.timer + dt

  if S.state == "title" then
    S.idle = S.idle + dt
    S.scroll = S.scroll + SPEED * 0.35 * dt
    for p = 1, 2 do
      if flapPressed(p) then
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
    local b = S.bird
    local pipes = pipesNear(S.scroll)
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
    end
    if hits(b, pipes) then
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
  pressed, jsPressed = {}, {}
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
    for _, pipe in ipairs(pipesNear(S.scroll)) do
      L.pipe(pipe.x, pipe.top, GAP, night)
    end
  end
  L.ground(S.scroll, night)
  if S.bird and playing and S.state ~= "between" then
    for _, f in ipairs(S.bird.feathers) do L.feather(f) end
    L.bird(S.bird.x, S.bird.y, S.bird.tilt, S.bird.flap, BIRD_COLOURS[S.turn], not S.bird.alive)
  end
end

local function drawFront()
  local mid = VIEW_W / 2
  if S.state == "title" or S.state == "choose" then
    panel(mid - 70, 78, 140, 64)
    shadowText("FLAP", mid, 84, { 0.95, 0.72, 0.15 }, 3)
    text("A TURN EACH", mid, 112, { 0.35, 0.32, 0.28 })
    text("BEST  " .. S.best, mid, 124, { 0.45, 0.42, 0.36 })
    L.bird(mid, 170 + math.sin(S.t * 4) * 6, math.sin(S.t * 4) * 0.25,
           (math.floor(S.t * 8) % 3) + 1, BIRD_COLOURS[1])
    if S.state == "choose" then
      panel(mid - 80, 200, 160, 44)
      text("STARTING ON YOUR OWN", mid, 206, { 0.35, 0.32, 0.28 })
      text("OTHER SEAT PRESS TO JOIN", mid, 218, { 0.55, 0.35, 0.20 })
      text(string.format("%d", math.max(0, math.ceil(4 - (S.waitT or 0)))), mid, 230, { 0.35, 0.32, 0.28 })
    elseif math.floor(S.t * 2) % 2 == 0 then
      shadowText("PRESS A BUTTON", mid, 252, { 1, 1, 1 })
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
      panel(mid - 78, 112, 156, 78)
      text("GAME OVER", mid, 118, { 0.85, 0.35, 0.20 }, 2)
      local m = medalFor(S.bestRun[S.turn])
      if m then L.medal(m, mid - 52, 156) end
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
  music.play("title", 0.4)
  if not os.getenv("FLAP_WINDOW") then love.window.setFullscreen(true, "desktop") end
  love.mouse.setVisible(false)
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
    if S.state == "play" and S.bird then
      local b = S.bird
      local aim = VIEW_H * 0.45
      for _, pipe in ipairs(pipesNear(S.scroll)) do
        if pipe.x + L.PIPE_W > b.x - 10 then aim = pipe.top + GAP * 0.5; break end
      end
      if b.y > aim + 4 and b.vy > -40 then pressed["space"] = true end
    elseif S.state == "ready" or S.state == "between" or S.state == "over" then
      pressed["space"] = true
    end
  end
  realUpdate(dt)
  if S.shots then
    S.shotT = (S.shotT or 0) + dt
    if S.shots[1] and S.shotT >= S.shots[1] then
      table.remove(S.shots, 1)
      g.captureScreenshot("flap" .. math.floor(S.shotT) .. ".png")
    end
    if #S.shots == 0 then love.event.quit() end
  end
end
