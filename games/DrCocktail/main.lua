-- main.lua : Dr. Cocktail. Head-to-head Dr. Mario for a cocktail table.
-- Layouts: "side" (bottles side by side, player 2's turned to face the far seat),
-- "cocktail" (halves stacked, player 2's turned), "upright" (NES screen, both upright).
local Board = require("board")
local R = require("render")
local sfx = require("sfx")
local AI = require("ai")
local HS = require("hiscore")
local music = require("music")

local CFG = {
  freePlay = true,      -- false = coin switches add credits (1 credit solo, 2 credits versus)
  layout = "side",      -- "side", "cocktail" or "upright"
  screenRotation = 0,   -- 0, 90, 180 or 270 to match how the LCD is mounted in the table
  fullscreen = false,
  roundsToWin = 3,      -- versus is first to this many rounds (NES: three)
  music = true,
  slideFrames = 0,      -- extra frames a landed capsule can still slide. NES = 0.
  spawnDelay = 24,      -- frames between a capsule locking and the next appearing
  garbageMin = 2,       -- matches from one capsule needed to send junk (NES: 2)
  garbageMax = 4,       -- most junk halves one capsule can send (NES: 4)
  fallFrames = 10,      -- frames per row for settling pieces and junk
  demoSeconds = 15,     -- idle time on the title before the attract demo
  swapPads = false,     -- true if player 1's panel drives player 2's bottle
  capsuleSeam = "black",  -- line between a capsule's two halves: "none", "dark" or "black"
  capsuleSeamWidth = 1,   -- 1 = a single pixel line (NES), 2 = both halves draw one
}
do
  local ok, user = pcall(require, "config")
  if ok and type(user) == "table" then
    for k, v in pairs(user) do CFG[k] = v end
  end
end
Board.slideFrames = tonumber(CFG.slideFrames) or 0
Board.spawnDelay = tonumber(CFG.spawnDelay) or 24
Board.garbageMin = tonumber(CFG.garbageMin) or 2
Board.garbageMax = tonumber(CFG.garbageMax) or 4
Board.fallFrames = tonumber(CFG.fallFrames or CFG.garbageFallFrames) or 10

-- The only sounds a computer-controlled bottle makes: the combo sounds when it sends junk
-- at you. Its moves, locks, clears and virus kills stay silent so the cab speaker is yours.
local CPU_SOUNDS = { combo1 = true, combo2 = true }
-- Board events that never play as effects: the music (vs win, game over, stage clear
-- jingles) already marks those moments.
local SILENT_EVENTS = { won = true, dead = true }

-- Keyboard mapping. Player 1: arrows, A / D rotate. Player 2: I J K L, U / O rotate.
-- Override per player in config.lua with keys1 = { ... } / keys2 = { ... } (same field
-- names, LÖVE key constants), e.g. to restore the MAME defaults for a keyboard encoder:
--   keys1 = { b1 = "lctrl", b2 = "lalt" }, keys2 = { up = "r", down = "f", left = "d", right = "g", b1 = "a", b2 = "s" }
local KEYS = {
  { up = "up", down = "down", left = "left", right = "right", b1 = "a", b2 = "d", b3 = "space", b4 = "f", b5 = "g", start = "1", coin = "5" },
  { up = "i", down = "k", left = "j", right = "l", b1 = "u", b2 = "o", b3 = "p", b4 = "y", b5 = "h", start = "2", coin = "6" },
}
for p = 1, 2 do
  local o = CFG["keys" .. p]
  if type(o) == "table" then for k, v in pairs(o) do KEYS[p][k] = v end end
end
local SPEEDS = { "low", "med", "hi" }
local MENU_SFX = "ting"
local MUSIC_ORDER = R.MUSIC_ORDER
local INTRO_FRAMES = 100

local G = {
  state = "title", -- title | demo | setup | intro | play | stageclear | gameover | roundover
  credits = 0,
  t = 0,
  timer = 0,
  mode = nil,
  active = { false, false },
  cpu = { false, false },
  titleSel = 1,
  titlePage = 0,      -- 0 = menu, 1 = high scores
  pageTimer = 0,
  cursor = { 1, 1 },
  musicType = "fever",
  boards = {},
  wins = { 0, 0 },
  settings = { { level = 10, speed = "med" }, { level = 10, speed = "med" } },
  carryScore = 0,
}

-- F10 shows the last sound effect and who caused it, for tracking down stray noises.
local showPads = false
local lastSfx = { name = "", who = "", t = -99 }
local showSounds = false
local function playFrom(who, name)
  lastSfx.name, lastSfx.who, lastSfx.t = name, who, G.t
  sfx.play(name)
end

local LAYOUT
local half, screen, rng
local pressed, gpPressed, padPressed = {}, { {}, {} }, { {}, {} }
local padDirPrev = { {}, {} }   -- last frame's stick direction, per pad
local testMode, shotMode, shotFrames = false, nil, 0
local probeMode = false

-------------------------------------------------------------------------------
-- input
-------------------------------------------------------------------------------
-- Controls from a JAMMA encoder board. These show up as plain USB joysticks, NOT as
-- recognised gamepads, so we read them raw: the hat or the first two axes for the
-- stick, numbered buttons for the rest. The 3H / Xin-Mo dual board needs the Pi told
-- it is TWO pads (usbhid.quirks=0x16c0:0x75e1:0x040 in cmdline.txt) or both players
-- land on one. Press F9 in game to see exactly what your board sends, then set the
-- numbers in config.lua:
--   pad1 = { b1 = 1, b2 = 2, start = 8, coin = 7 }
local PADS = {
  { b1 = 1, b2 = 2, b3 = 3, b4 = 4, b5 = 10, start = 8, coin = 7 },
  { b1 = 1, b2 = 2, b3 = 3, b4 = 4, b5 = 10, start = 8, coin = 7 },
}
for p = 1, 2 do
  local o = CFG["pad" .. p]
  if type(o) == "table" then for k, v in pairs(o) do PADS[p][k] = v end end
end
local AXIS_EDGE = 0.5

-- which physical pad drives player p (the Pi lists them in USB order)
local function padIndex(p)
  return CFG.swapPads and (3 - p) or p
end

local function joystickFor(p)
  return love.joystick.getJoysticks()[padIndex(p)]
end

-- stick direction from a raw joystick: hat first, then the first two axes
local function rawDir(js, dir)
  for h = 1, js:getHatCount() do
    local v = js:getHat(h)
    if v and v ~= "c" and v:find(dir == "left" and "l" or dir == "right" and "r"
                                or dir == "up" and "u" or "d") then return true end
  end
  if js:getAxisCount() >= 2 then
    local x, y = js:getAxis(1), js:getAxis(2)
    if dir == "left" and x < -AXIS_EDGE then return true end
    if dir == "right" and x > AXIS_EDGE then return true end
    if dir == "up" and y < -AXIS_EDGE then return true end
    if dir == "down" and y > AXIS_EDGE then return true end
  end
  return false
end

local function readInput(p, edges)
  local k, pad = KEYS[p], PADS[p]
  local di = padIndex(p)
  local js = joystickFor(p)
  local gamepad = js and js:isGamepad()
  -- stick or d-pad direction from the joystick alone
  local function jsDir(name, gp)
    if not js then return false end
    if gamepad then
      if js:isGamepadDown(gp) then return true end
      local axis, sign = nil, 1
      if name == "left" then axis, sign = "leftx", -1
      elseif name == "right" then axis, sign = "leftx", 1
      elseif name == "up" then axis, sign = "lefty", -1
      elseif name == "down" then axis, sign = "lefty", 1 end
      return axis ~= nil and sign * js:getGamepadAxis(axis) > AXIS_EDGE
    end
    return rawDir(js, name)
  end
  local function held(name, gp)
    return love.keyboard.isDown(k[name]) or jsDir(name, gp)
  end
  local function press(name, gp)
    if not edges then return false end
    if pressed[k[name]] == true then return true end
    if gamepad and gpPressed[di][gp] == true then return true end
    local btn = pad[name]
    if btn and padPressed[di][btn] == true then return true end
    return false
  end
  -- A stick never sends a press event, only a position. Menus need presses, so the
  -- moment a direction becomes held counts as one press, until it is released.
  local function dirPress(name, gp)
    if press(name, gp) then return true end
    if not edges or not js then return false end
    local now = jsDir(name, gp)
    local was = padDirPrev[di][name]
    padDirPrev[di][name] = now
    return now and not was
  end
  return {
    left = held("left", "dpleft"),
    right = held("right", "dpright"),
    down = held("down", "dpdown"),
    rotCW = press("b1", "a"),
    rotCCW = press("b2", "b"),
    back = press("b2", "b"),
    pause = press("b4", "y") or press("b3", "x") or press("b5", "leftshoulder"),
    start = press("start", "start"),
    coin = press("coin", "back"),
    leftP = dirPress("left", "dpleft"),
    rightP = dirPress("right", "dpright"),
    upP = dirPress("up", "dpup"),
    downP = dirPress("down", "dpdown"),
  }
end

local function randomInput(r)
  return {
    left = r:random() < 0.15, right = r:random() < 0.15, down = r:random() < 0.3,
    rotCW = r:random() < 0.08, rotCCW = r:random() < 0.04,
  }
end

function love.keypressed(key)
  pressed[key] = true
  if key == "escape" then love.event.quit() end
  if key == "f11" then love.window.setFullscreen(not love.window.getFullscreen()) end
  if key == "f10" then showSounds = not showSounds end
  if key == "f9" then showPads = not showPads end
end

function love.joystickpressed(js, button)
  for i, j in ipairs(love.joystick.getJoysticks()) do
    if j == js and padPressed[i] then padPressed[i][button] = true end
  end
end

function love.gamepadpressed(js, button)
  for i, j in ipairs(love.joystick.getJoysticks()) do
    if j == js and gpPressed[i] then gpPressed[i][button] = true end
  end
end

-------------------------------------------------------------------------------
-- game flow
-------------------------------------------------------------------------------
local function speedIndex(s)
  for i, v in ipairs(SPEEDS) do if v == s then return i end end
  return 2
end

local function musicIndex(m)
  for i, v in ipairs(MUSIC_ORDER) do if v == m then return i end end
  return 1
end

local function playMusic(slot)
  if CFG.music and not testMode then music.play(slot) end
end

local function stopMusic()
  if not testMode then music.stop() end
end

-- In-game music for the chosen type, or silence for OFF.
local function playGameMusic()
  if G.musicType == "off" then stopMusic() else playMusic(G.musicType) end
end

-- Builds the bottles and shows them for a moment before the first capsule, with the
-- game music starting, the way the NES does.
local function startRound()
  G.boards = {}
  G.ai = nil
  for p = 1, 2 do
    if G.active[p] then
      local s = G.settings[p]
      G.boards[p] = Board.new(s.level, s.speed, rng)
      if G.mode == "solo" then G.boards[p].score = G.carryScore end
      if G.cpu[p] then
        G.ai = G.ai or {}
        G.ai[p] = AI.new(G.boards[p], rng)
      end
    end
  end
  G.state = "intro"
  G.timer = INTRO_FRAMES
  playGameMusic()
end

local function goTitle()
  playMusic("title")
  G.state = "title"
  G.timer = 0
  G.titlePage, G.pageTimer = 0, 0
  G.boards = {}
  G.ai = nil
end

local PAGE_FRAMES = 60 * 7   -- menu and high score pages alternate this often

local DEMO_IDLE_FRAMES = 60 * (tonumber(CFG.demoSeconds) or 15)
local DEMO_MAX_FRAMES = 60 * 60

local function startDemo()
  local r = love.math.newRandomGenerator(os.time())
  local level = r:random(8, 16)
  G.mode = "versus"
  G.active = { true, true }
  G.wins = { 0, 0 }
  G.boards = { Board.new(level, "med", r), Board.new(level, "med", r) }
  G.ai = { AI.new(G.boards[1], r), AI.new(G.boards[2], r) }
  G.state = "demo"
  G.timer = 0
  playMusic("fever")
end

-- choice: 1 = solo, 2 = two players, 3 = player versus the computer
local function beginGame(choice)
  G.mode = (choice == 1) and "solo" or "versus"
  G.active = (choice == 1) and { true, false } or { true, true }
  G.cpu = { false, choice == 3 }
  G.cursor = { 1, 1 }
  G.wins = { 0, 0 }
  G.carryScore = 0
  G.rank = nil
  G.state = "setup"
  playMusic("select")
  playFrom("UI", "start")
end

local function tick(inp)
  for p = 1, 2 do
    if inp[p].coin then
      G.credits = G.credits + 1
      playFrom("UI", "coin")
    end
  end

  local st = G.state
  if st == "title" then
    -- menu and high score pages take turns; any press on the scores page just brings
    -- the menu back, it never starts a game
    G.pageTimer = G.pageTimer + 1
    if G.pageTimer >= PAGE_FRAMES then
      G.pageTimer = 0
      G.titlePage = 1 - G.titlePage
    end
    local anyPress = false
    for p = 1, 2 do
      local i = inp[p]
      if i.start or i.rotCW or i.rotCCW or i.upP or i.downP or i.leftP or i.rightP then anyPress = true end
    end
    if G.titlePage == 1 then
      if anyPress then
        G.titlePage, G.pageTimer = 0, 0
        playFrom("UI", MENU_SFX)
        G.timer = 0
      end
      return
    end
    if anyPress then G.pageTimer = 0 end
    -- the heart is the cursor: up/down from either seat moves it, start confirms
    for p = 1, 2 do
      if inp[p].upP and G.titleSel > 1 then G.titleSel = G.titleSel - 1 playFrom("UI", MENU_SFX) G.timer = 0 end
      if inp[p].downP and G.titleSel < 3 then G.titleSel = G.titleSel + 1 playFrom("UI", MENU_SFX) G.timer = 0 end
    end
    local confirm = false
    for p = 1, 2 do if inp[p].start or inp[p].rotCW then confirm = true end end
    if confirm then
      local need = (G.titleSel == 2) and 2 or 1
      if CFG.freePlay or G.credits >= need then
        if not CFG.freePlay then G.credits = G.credits - need end
        beginGame(G.titleSel)
      end
    else
      G.timer = G.timer + 1
      if G.timer >= DEMO_IDLE_FRAMES then startDemo() end
    end

  elseif st == "demo" then
    -- any start or coin brings the title back
    if inp[1].start or inp[2].start or inp[1].coin or inp[2].coin then
      goTitle()
    else
      G.timer = G.timer + 1
      for p = 1, 2 do G.boards[p]:tick(G.ai[p]:input()) end
      for p = 1, 2 do
        local target = G.boards[3 - p].pendingGarbage
        for _, c in ipairs(G.boards[p]:takeOutgoing()) do target[#target + 1] = c end
        G.boards[p]:drainEvents()
      end
      local b1, b2 = G.boards[1], G.boards[2]
      local over = b1.state == "won" or b1.state == "dead" or b2.state == "won" or b2.state == "dead"
      if over or G.timer >= DEMO_MAX_FRAMES then goTitle() end
    end

  elseif st == "setup" then
    -- NES mode select: up/down picks the row, left/right changes it, start begins.
    -- A computer player takes player 1's level and speed.
    for p = 1, 2 do
      if G.active[p] and not G.cpu[p] then
        local s, i, row = G.settings[p], inp[p], G.cursor[p]
        if i.upP and row > 1 then G.cursor[p] = row - 1 playFrom("UI", MENU_SFX) end
        if i.downP and row < 3 then G.cursor[p] = row + 1 playFrom("UI", MENU_SFX) end
        local d = (i.rightP and 1 or 0) - (i.leftP and 1 or 0)
        if d ~= 0 then
          if row == 1 then s.level = math.max(0, math.min(20, s.level + d))
          elseif row == 2 then s.speed = SPEEDS[math.max(1, math.min(3, speedIndex(s.speed) + d))]
          else G.musicType = MUSIC_ORDER[math.max(1, math.min(3, musicIndex(G.musicType) + d))] end
          playFrom("UI", MENU_SFX)
        end
        if i.back then
          playFrom("UI", MENU_SFX)
          goTitle()
          return
        end
        if i.start or i.rotCW then
          playFrom("UI", "ready")
          if G.cpu[2] then G.settings[2] = { level = G.settings[1].level, speed = G.settings[1].speed } end
          startRound()
          break
        end
      end
    end

  elseif st == "intro" then
    G.timer = G.timer - 1
    if G.timer <= 0 then G.state = "play" end

  elseif st == "paused" then
    local items = pauseItems()
    for p = 1, 2 do
      local i = inp[p]
      if i.upP and G.pauseSel > 1 then G.pauseSel = G.pauseSel - 1 playFrom("UI", MENU_SFX) end
      if i.downP and G.pauseSel < #items then G.pauseSel = G.pauseSel + 1 playFrom("UI", MENU_SFX) end
      if i.pause or i.back then
        G.state = "play"
        playFrom("UI", MENU_SFX)
        return
      end
      if i.start or i.rotCW then
        local pick = G.pauseSel
        playFrom("UI", "ready")
        if pick == 1 then
          G.state = "play"
        elseif pick == 2 then
          G.wins = { 0, 0 }
          G.carryScore = 0
          startRound()
        elseif pick == 3 then
          goTitle()
        else
          love.event.quit(0)
        end
        return
      end
    end

  elseif st == "play" then
    for p = 1, 2 do
      if inp[p].pause and not G.cpu[p] then
        G.state = "paused"
        G.pauseSel = 1
        playFrom("UI", MENU_SFX)
        return
      end
    end
    for p = 1, 2 do
      local b = G.boards[p]
      if b then
        local i = (G.cpu[p] and G.ai and G.ai[p]) and G.ai[p]:input() or inp[p]
        b:tick(i)
      end
    end
    if G.mode == "versus" then
      for p = 1, 2 do
        local target = G.boards[3 - p].pendingGarbage
        for _, c in ipairs(G.boards[p]:takeOutgoing()) do target[#target + 1] = c end
      end
    end
    for p = 1, 2 do
      local b = G.boards[p]
      if b then
        for _, e in ipairs(b:drainEvents()) do
          if not SILENT_EVENTS[e] and (not G.cpu[p] or CPU_SOUNDS[e]) then
            playFrom((G.cpu[p] and "CPU" or ("P" .. p)), e)
          end
        end
      end
    end
    if G.mode == "solo" then
      local b = G.boards[1]
      if b.state == "won" then
        playMusic(G.musicType == "chill" and "chillclear" or "feverclear")
        G.carryScore = b.score
        G.state, G.timer = "stageclear", 200
      elseif b.state == "dead" then
        playMusic("gameover")
        G.rank = HS.add(b.score, b.level)
        G.state, G.timer = "gameover", 260
      end
    else
      local b1, b2 = G.boards[1], G.boards[2]
      local winner
      if b1.state == "won" or b2.state == "dead" then winner = 1
      elseif b2.state == "won" or b1.state == "dead" then winner = 2 end
      if winner then
        G.wins[winner] = G.wins[winner] + 1
        G.roundWinner = winner
        -- a human winning a round gets the vs win music; the computer winning one gets game over
        playMusic(G.cpu[winner] and "gameover" or "matchwin")
        G.state, G.timer = "roundover", 90   -- short guard so a stray press cannot skip it
      end
    end

  elseif st == "stageclear" then
    G.timer = G.timer - 1
    if G.timer <= 0 then
      G.settings[1].level = math.min(20, G.settings[1].level + 1)
      startRound()
    end

  elseif st == "gameover" then
    G.timer = G.timer - 1
    if G.timer <= 0 then goTitle() end

  elseif st == "roundover" then
    -- the winner decides when the next round starts: only their Start counts.
    -- If the computer won, the human's Start stands in for it.
    G.timer = G.timer - 1
    if G.timer <= 0 then
      local decider = G.cpu[G.roundWinner] and (3 - G.roundWinner) or G.roundWinner
      if inp[decider].start or inp[decider].rotCW then
        playFrom("UI", "ready")
        if G.wins[G.roundWinner] >= CFG.roundsToWin then goTitle() else startRound() end
      end
    end
  end
end

-------------------------------------------------------------------------------
-- drawing
-------------------------------------------------------------------------------
local function overlayFor(p, b)
  local st = G.state
  if st == "demo" then
    if math.floor(G.t * 1.5) % 2 == 0 then return "DEMO", CFG.freePlay and "PRESS START" or "INSERT COIN" end
    return nil
  elseif st == "stageclear" then
    return "STAGE CLEAR", ("NEXT LEVEL %d"):format(math.min(20, b.level + 1))
  elseif st == "gameover" then
    return "GAME OVER", G.rank and ("HIGH SCORE #%d"):format(G.rank) or ("SCORE %d"):format(b.score)
  elseif st == "roundover" then
    local won = G.roundWinner == p
    local matchOver = G.wins[G.roundWinner] >= CFG.roundsToWin
    local decider = G.cpu[G.roundWinner] and (3 - G.roundWinner) or G.roundWinner
    local sub
    if p == decider then
      sub = (math.floor(G.t * 2) % 2 == 0) and "PRESS START" or (matchOver and "MATCH OVER" or "FOR NEXT ROUND")
    else
      sub = matchOver and "MATCH LOST" or "WINNER STARTS NEXT"
    end
    return won and "YOU WIN" or "YOU LOSE", sub
  end
  return nil
end

-- What the pause panel offers. It sits on top of the game; the clock stops.
local PAUSE_ITEMS = { "CONTINUE", "PLAY AGAIN", "MAIN MENU", "QUIT" }

local function pauseItems() return PAUSE_ITEMS end

local function selectData()
  return { mode = G.mode, settings = G.settings, cursor = G.cursor, musicType = G.musicType, cpu = G.cpu }
end

-- The NES end-of-round look: bottle emptied, yellow card with the result, the doctor
-- standing in the winner's bottle, and who presses Start written under the card.
local function drawRoundEnd(p, b, bx, by)
  local won = G.roundWinner == p
  local matchOver = G.wins[G.roundWinner] >= CFG.roundsToWin
  local decider = G.cpu[G.roundWinner] and (3 - G.roundWinner) or G.roundWinner
  R.drawBottle(b, bx, by, G.t, false, true)
  local y = R.drawEndCard(bx, by, won and { "YOU", "WON!" } or { "YOU", "LOST!" })
  if p == decider then
    if math.floor(G.t * 2) % 2 == 0 then R.drawBottleLine(bx, y, "PRESS START") end
  else
    R.drawBottleLine(bx, y, matchOver and "MATCH OVER" or "WINNER STARTS", R.PAL.panel)
  end
  if won then R.drawBottleDoctor(bx, by) end
end

-- Draws one player's bottle, info and overlays into the current canvas.
local function drawPlayer(p, region, bx, by, t)
  local b = G.boards[p]
  if not b then
    R.drawMessage(region, "SOLO GAME", ("PLAYER 1  LEVEL %d"):format(G.settings[1].level))
    return
  end
  local extra
  if G.state == "demo" then extra = "DEMO"
  elseif G.mode == "versus" then
    extra = ("ROUNDS %d-%d"):format(G.wins[p], G.wins[3 - p])
    if G.cpu[p] then extra = extra .. "  CPU" end
  end
  if G.state == "roundover" then
    drawRoundEnd(p, b, bx, by)
  else
    R.drawBottle(b, bx, by, t)
  end
  if LAYOUT.perPlayerCanvas then R.drawCocktailInfo(b, p, extra, LAYOUT) else R.drawSideInfo(b, p, bx, extra) end
  if G.state ~= "roundover" then
    local title, sub = overlayFor(p, b)
    if title then R.drawOverlay(region, title, sub) end
  end
end

-- Solo end screens on the same card, inside the bottle.
local function drawSoloEnd(b, bx, by)
  local st = G.state
  if st == "gameover" then
    local y = R.drawEndCard(bx, by, { "GAME", "OVER" })
    R.drawBottleLine(bx, y, G.rank and ("HI SCORE #" .. G.rank) or ("%d"):format(b.score), R.PAL.logoText)
  elseif st == "stageclear" then
    local y = R.drawEndCard(bx, by, { "STAGE", "CLEAR" })
    R.drawBottleLine(bx, y, ("LEVEL %d NEXT"):format(math.min(20, b.level + 1)), R.PAL.panel)
    R.drawBottleDoctor(bx, by)
  end
end

local function scheme()
  if G.state == "title" then return "title" elseif G.state == "setup" then return "select" end
  return "game"
end

-- One full screen's worth for a region: title, select panel, or the play field.
local function drawScreenRegion(region, t)
  if G.state == "title" then
    R.drawTitle(region, G.credits, CFG.freePlay, t, HS.list, G.titleSel, G.titlePage)
  elseif G.state == "setup" then
    R.drawSelect(region, selectData(), t)
  end
end

-- The picture can sit off centre on a monitor fed through a VGA adapter. The lining-up
-- screen writes what it found into ~/screen.conf; both this and the menu read it.
local function readScreenConf()
  local home = os.getenv("HOME")
  if not home then return end
  local f = io.open(home .. "/screen.conf", "r")
  if not f then return end
  for line in f:lines() do
    local k, v = line:match("^(%w+)%s*=%s*(-?%d+)")
    if k and v then CFG[k] = tonumber(v) end
  end
  f:close()
end

function love.draw()
  local g = love.graphics
  local t = G.t
  R.wins, R.roundsToWin = G.wins, CFG.roundsToWin
  local cw, ch = LAYOUT.canvas[1], LAYOUT.canvas[2]
  local menu = G.state == "title" or G.state == "setup"
  local soloSelect = G.mode == "solo" and G.state == "setup"
  local soloGame = G.mode == "solo" and not menu and G.state ~= "demo" and G.boards[1]
  local paused = G.state == "paused"

  if soloSelect or soloGame then
    -- one player: the whole screen, upright for player 1's seat
    local sw, sh = R.screenSize(LAYOUT)
    g.setCanvas(screen)
    if soloSelect then
      R.background(sw, sh, "select")
      R.drawSelect({ 0, 0, sw, sh }, selectData(), t)
    else
      R.background(sw, sh, "title")
      local bx, by = R.drawSolo(G.boards[1], sw, sh, t, HS.list[1] and HS.list[1].score or 0)
      drawSoloEnd(G.boards[1], bx, by)
      if paused then R.drawPause({ 0, 0, sw, sh }, pauseItems(), G.pauseSel or 1) end
    end
    cw, ch = sw, sh
  elseif LAYOUT.perPlayerCanvas then
    for p = 1, 2 do
      g.setCanvas(half[p])
      R.background(cw, ch, scheme())
      if menu then
        drawScreenRegion(LAYOUT.region, t)
      else
        drawPlayer(p, LAYOUT.region, LAYOUT.bottle[1], LAYOUT.bottle[2], t)
        if paused then R.drawPause(LAYOUT.region, pauseItems(), G.pauseSel or 1) end
      end
    end
    g.setCanvas(screen)
    g.clear(0, 0, 0)
    g.setColor(1, 1, 1)
    if LAYOUT.composite == "vertical" then
      g.draw(half[1], 0, ch)                -- player 1: bottom, upright
      g.draw(half[2], cw, ch, math.pi)      -- player 2: top, turned to face them
      g.setColor(R.PAL.glassDark)
      g.rectangle("fill", 0, ch - 1, cw, 2)
    else
      g.draw(half[1], 0, 0)                 -- player 1: left, upright
      g.draw(half[2], cw * 2, ch, math.pi)  -- player 2: right, turned to face them
      g.setColor(R.PAL.glassDark)
      g.rectangle("fill", cw - 1, 0, 2, ch)
    end
    cw, ch = R.screenSize(LAYOUT)
  else
    g.setCanvas(screen)
    R.background(cw, ch, scheme())
    if menu then
      drawScreenRegion(LAYOUT.full, t)
    else
      for p = 1, 2 do
        drawPlayer(p, LAYOUT.regions[p], LAYOUT.bottles[p][1], LAYOUT.bottles[p][2], t)
      end
      if paused then R.drawPause(LAYOUT.full, pauseItems(), G.pauseSel or 1) end
      R.drawCenterPanel(G.boards[1], G.boards[2], t)
    end
  end
  g.setCanvas()

  local ww, wh = g.getDimensions()
  local rw, rh = cw, ch
  if CFG.screenRotation % 180 ~= 0 then rw, rh = rh, rw end
  -- A monitor fed through a VGA adapter often shows a little less than it is sent, and
  -- a little off centre, which eats the edges of the picture. overscan pulls the picture
  -- in by that many screen pixels; nudgeX / nudgeY shift it. All three default to 0.
  local padX = tonumber(CFG.padX) or tonumber(CFG.overscan) or 0
  local padY = tonumber(CFG.padY) or tonumber(CFG.overscan) or 0
  -- the picture is turned before it reaches the glass, so on a quarter turn the
  -- screen's width is the picture's height
  local availW, availH = ww - padX * 2, wh - padY * 2
  local sx, sy
  if CFG.screenRotation % 180 == 0 then
    sx, sy = availW / cw, availH / ch
  else
    sx, sy = availH / cw, availW / ch
  end
  if padX == 0 and padY == 0 then
    local s = math.min(sx, sy)
    if s >= 1 then s = math.floor(s) end
    sx, sy = s, s
  end
  g.clear(0, 0, 0)
  g.setColor(1, 1, 1)
  g.draw(screen, math.floor(ww / 2) + (tonumber(CFG.nudgeX) or 0),
                 math.floor(wh / 2) + (tonumber(CFG.nudgeY) or 0),
                 math.rad(CFG.screenRotation), sx, sy, cw / 2, ch / 2)

  if showPads then
    -- F9: live view of every stick the Pi can see. Hold a control and read its number.
    local sticks = love.joystick.getJoysticks()
    local lines = { ("STICKS FOUND: %d"):format(#sticks) }
    for i, js in ipairs(sticks) do
      lines[#lines + 1] = ("%d: %s%s"):format(i, js:getName(), js:isGamepad() and "  [gamepad]" or "  [raw]")
      local btns = {}
      for b = 1, js:getButtonCount() do if js:isDown(b) then btns[#btns + 1] = tostring(b) end end
      local ax = {}
      for a = 1, math.min(js:getAxisCount(), 4) do
        local v = js:getAxis(a)
        if math.abs(v) > 0.2 then ax[#ax + 1] = ("ax%d=%.1f"):format(a, v) end
      end
      local hats = {}
      for h = 1, js:getHatCount() do
        local v = js:getHat(h)
        if v and v ~= "c" then hats[#hats + 1] = ("hat%d=%s"):format(h, v) end
      end
      lines[#lines + 1] = ("   buttons: %s"):format(#btns > 0 and table.concat(btns, " ") or "-")
      lines[#lines + 1] = ("   stick:   %s"):format((#ax + #hats > 0)
        and (table.concat(ax, " ") .. " " .. table.concat(hats, " ")) or "-")
    end
    if #sticks == 0 then lines[#lines + 1] = "nothing plugged in" end
    g.setColor(0, 0, 0, 0.85)
    g.rectangle("fill", 4, 4, 620, 20 + #lines * 24)
    g.setColor(1, 1, 0.4)
    for i, line in ipairs(lines) do g.print(line, 12, 12 + (i - 1) * 24, 0, 2, 2) end
  end

  if showSounds then
    local age = G.t - lastSfx.t
    local line = (age < 3) and (lastSfx.who .. "  " .. lastSfx.name) or "F10: sound log (nothing yet)"
    g.setColor(0, 0, 0, 0.75)
    g.rectangle("fill", 4, 4, 220, 26)
    g.setColor(age < 0.25 and 1 or 0.7, age < 0.25 and 1 or 0.7, 0.4)
    g.print(line, 10, 10, 0, 2, 2)
  end

  if shotMode then
    shotFrames = shotFrames + 1
    if shotFrames == 2 then
      local name = "shot_" .. CFG.layout .. "_" .. shotMode .. ".png"
      g.captureScreenshot(function(img)
        img:encode("png", name)
        print("screenshot written to " .. love.filesystem.getSaveDirectory() .. "/" .. name)
        love.event.quit()
      end)
    end
  end
end

-------------------------------------------------------------------------------
-- update
-------------------------------------------------------------------------------
local acc = 0
function love.update(dt)
  G.t = G.t + dt
  acc = math.min(acc + dt, 0.25)
  local first = true
  while acc >= 1 / 60 do
    tick({ readInput(1, first), readInput(2, first) })
    first = false
    acc = acc - 1 / 60
  end
  if not first then
    pressed = {}
    gpPressed = { {}, {} }
    padPressed = { {}, {} }
  end
end

-------------------------------------------------------------------------------
-- self test: run with  love . --selftest   (use lovec.exe on Windows to see output)
-------------------------------------------------------------------------------
local function blankBoard()
  local b = Board.new(0, "low", rng)
  for y = 1, Board.H do b.grid[y] = {} end
  b.viruses = 0
  return b
end

local function settle(b)
  local n = 0
  while (b.state == "falling" or b.state == "resolving") and n < 5000 do
    b:tick({})
    n = n + 1
  end
end

local function selftest()
  local fails = 0
  local function check(cond, msg)
    if not cond then
      fails = fails + 1
      print("FAIL: " .. msg)
    else
      print("ok:   " .. msg)
    end
  end

  -- 1. one horizontal match clears the last viruses and wins
  local b = blankBoard()
  for x = 1, 3 do b.grid[16][x] = { color = "red", kind = "virus" } end
  b.viruses = 3
  b.capsule = { x = 4, y = 16, o = 0, a = "red", b = "blue" }
  b.state = "falling"
  settle(b)
  check(b.state == "won", "row of four clears viruses and wins")
  check(b.grid[16][5] and b.grid[16][5].color == "blue" and b.grid[16][5].link == nil, "leftover half loses its link")
  check(select(1, b:validate()), "board valid after clear")

  -- 2. two matches from one capsule send two garbage halves
  b = blankBoard()
  for x = 1, 3 do b.grid[16][x] = { color = "red", kind = "virus" } end
  for y = 13, 15 do b.grid[y][5] = { color = "yellow", kind = "virus" } end
  b.viruses = 6
  b.capsule = { x = 4, y = 16, o = 0, a = "red", b = "yellow" }
  b.state = "falling"
  settle(b)
  local out = b:takeOutgoing()
  check(#out == 2, "double match sends 2 garbage (got " .. #out .. ")")
  check(b.viruses == 0 and b.state == "won", "double match clears all six viruses")

  -- 2b. a cascading chain counts as extra matches and sends junk too
  b = blankBoard()
  for x = 1, 3 do b.grid[16][x] = { color = "red", kind = "virus" } end
  for x = 5, 7 do b.grid[16][x] = { color = "yellow", kind = "virus" } end
  b.viruses = 6
  b.capsule = { x = 4, y = 16, o = 1, a = "yellow", b = "red" }   -- red bottom, yellow on top
  b.state = "falling"
  settle(b)
  out = b:takeOutgoing()
  check(#out == 2 and b.viruses == 0, "chain: red row clears, yellow drops into a second row, 2 junk sent (got " .. #out .. ")")

  -- 3. loose halves fall after a clear, intact pairs fall together, viruses stay
  b = blankBoard()
  b.grid[8][6] = { color = "blue", kind = "half" }
  b.grid[5][2] = { color = "red", kind = "half", link = "right" }
  b.grid[5][3] = { color = "yellow", kind = "half", link = "left" }
  b.grid[10][3] = { color = "blue", kind = "virus" }
  b.viruses = 1
  b.state, b.phase, b.resolveTimer = "resolving", "fall", 0
  settle(b)
  check(b.grid[16][6] and b.grid[16][6].color == "blue", "single half falls to the floor")
  check(b.grid[9][2] and b.grid[9][3] and b.grid[9][2].link == "right", "pair stops on the virus, still linked")
  check(b.grid[10][3] and b.grid[10][3].kind == "virus", "virus does not move")
  check(select(1, b:validate()), "board valid after gravity")

  -- 4. garbage lands and the opponent state machine survives it
  b = blankBoard()
  b.grid[16][1] = { color = "red", kind = "virus" }
  b.viruses = 1
  b.pendingGarbage = { "red", "blue", "yellow" }
  b.state = "spawn"
  b:tick({})
  settle(b)
  local halves = 0
  for y = 1, Board.H do for x = 1, Board.W do
    local c = b.grid[y][x]
    if c and c.kind == "half" then halves = halves + 1 end
  end end
  check(halves == 3, "three garbage halves landed (got " .. halves .. ")")
  check(select(1, b:validate()), "board valid after garbage")
  -- junk rains down at its own slower rate
  b = blankBoard()
  b.grid[16][1] = { color = "red", kind = "virus" }
  b.viruses = 1
  b.pendingGarbage = { "blue" }
  b.state = "spawn"
  local fallFrames = 0
  while b.state ~= "spawn" or fallFrames == 0 do
    b:tick({})
    fallFrames = fallFrames + 1
    if fallFrames > 5000 then break end
  end
  check(fallFrames >= 15 * Board.fallFrames, ("junk takes %d frames to reach the floor (at least %d)"):format(fallFrames, 15 * Board.fallFrames))

  -- 5. spawn blocked = dead
  b = blankBoard()
  b.grid[1][4] = { color = "red", kind = "virus" }
  b.viruses = 1
  b.state = "spawn"
  b:tick({})
  check(b.state == "dead", "blocked spawn ends the game")

  -- 5b. NES timing: gravity, slide window, soft drop, speed-up
  local function freshMed()
    local m = Board.new(0, "med", rng)
    for y = 1, Board.H do m.grid[y] = {} end
    m.viruses = 0
    m.state = "spawn"
    m:tick({})
    return m
  end
  b = freshMed()
  local frames = 0
  while b.capsule.y == 1 and frames < 200 do b:tick({}) frames = frames + 1 end
  check(frames == 20, "MED start: first row takes 20 frames (got " .. frames .. ")")
  b.capsule.y = 16
  b.fallTimer = 0
  for _ = 1, 10 do b:tick({}) end
  b:tick({ left = true })
  check(b.state == "falling" and b.capsule.x == 3, "landed capsule still slides before the next gravity tick")
  local n = 0
  while b.state == "falling" and n < 100 do b:tick({}) n = n + 1 end
  check(b.state == "resolving" and n == 9, "locks exactly at the next gravity tick (got " .. n .. ")")
  b = freshMed()
  b:tick({})                    -- release down once so the new capsule accepts it
  b.capsule.y = 16
  b.frame = 0
  n = 0
  while b.state == "falling" and n < 10 do b:tick({ down = true }) n = n + 1 end
  check(n <= 2, "down alone locks on contact within 2 frames (got " .. n .. ")")
  b = freshMed()
  b:tick({})
  frames = 0
  while b.capsule and b.capsule.y == 1 and frames < 50 do b:tick({ down = true, left = true }) frames = frames + 1 end
  check(frames == 19, "down plus a direction does not soft drop (got " .. frames .. ")")
  b = freshMed()
  b:tick({})
  b.frame = 0
  frames = 0
  while b.capsule and b.capsule.y < 3 and frames < 50 do b:tick({ down = true }) frames = frames + 1 end
  check(frames == 3, "soft drop moves a row every 2 frames: two rows by frame 3 (got " .. frames .. ")")
  -- holding down through a lock must not soft drop the next capsule
  b = freshMed()
  b.grid[16][8] = { color = "red", kind = "virus" }   -- keep the round alive
  b.viruses = 1
  b:tick({})
  b.capsule.y = 16
  b.frame = 0
  b:tick({ down = true })                              -- locks
  n = 0
  while b.state ~= "falling" and n < 200 do b:tick({ down = true }) n = n + 1 end
  check(n >= Board.spawnDelay, "next capsule waits the spawn delay (got " .. n .. " frames)")
  for _ = 1, 10 do b:tick({ down = true }) end
  check(b.capsule and b.capsule.y == 1, "a held down button does not soft drop the new capsule")
  b:tick({})
  b:tick({ down = true })
  b:tick({ down = true })
  check(b.capsule and b.capsule.y >= 2, "released and pressed again, down soft drops")
  b = blankBoard()
  b.capsulesDropped = 7
  b.state = "spawn"
  b:tick({})
  b:tick({})
  b.capsule.y = 16
  b.frame = 0
  b:tick({ down = true })
  local chimed = false
  for _, e in ipairs(b:drainEvents()) do if e == "speedup" then chimed = true end end
  check(chimed and b:framesPerRow() == 38, "speed steps up before the 9th capsule (LOW 40 -> 38 frames)")

  -- 6. fuzz: random versus games keep the boards consistent
  local r = love.math.newRandomGenerator(12345)
  local games, deaths, attacks, virusClears, speedups = 40, 0, 0, 0, 0
  for gi = 1, games do
    local level = r:random(0, 20)
    local a, c = Board.new(level, SPEEDS[r:random(3)], r), Board.new(level, SPEEDS[r:random(3)], r)
    local pair = { a, c }
    for frame = 1, 12000 do
      for i = 1, 2 do
        local bd = pair[i]
        bd:tick(randomInput(r))
        local other = pair[3 - i].pendingGarbage
        for _, col in ipairs(bd:takeOutgoing()) do other[#other + 1] = col attacks = attacks + 1 end
        for _, e in ipairs(bd:drainEvents()) do
          if e == "virus" then virusClears = virusClears + 1 elseif e == "speedup" then speedups = speedups + 1 end
        end
        if frame % 30 == 0 then
          local ok, msg = bd:validate()
          if not ok then
            fails = fails + 1
            print(("FAIL: game %d frame %d board %d: %s"):format(gi, frame, i, msg))
            break
          end
        end
      end
      if a.state == "dead" or c.state == "dead" or a.state == "won" or c.state == "won" then
        deaths = deaths + 1
        break
      end
    end
  end
  print(("fuzz: %d games, %d ended, %d virus clears, %d garbage halves sent, %d speed-ups"):format(games, deaths, virusClears, attacks, speedups))
  check(deaths == games, "every fuzz game reached an ending")
  check(virusClears > 0, "random play cleared at least one virus")
  check(speedups > 0, "speed-up chime fires every ten capsules")

  -- 7. the attract-mode AI actually clears viruses
  local ar = love.math.newRandomGenerator(99)
  local ab = Board.new(6, "low", ar)
  local ai = AI.new(ab, ar)
  local startViruses = ab.viruses
  for _ = 1, 30000 do
    ab:tick(ai:input())
    ab:drainEvents()
    if ab.state == "won" or ab.state == "dead" then break end
  end
  print(("ai: level 6, %d -> %d viruses, state %s"):format(startViruses, ab.viruses, ab.state))
  check(ab.viruses <= startViruses / 2, "AI clears at least half the viruses on level 6")
  check(select(1, ab:validate()), "board valid after AI play")

  -- 8. every screen draws in every layout without error
  for _, layoutName in ipairs({ "cocktail", "side", "upright" }) do
    CFG.layout = layoutName
    LAYOUT = R.LAYOUTS[layoutName]
    R.noBottleSprite = LAYOUT.drawnBottle or false
    half = { love.graphics.newCanvas(LAYOUT.canvas[1], LAYOUT.canvas[2]), love.graphics.newCanvas(LAYOUT.canvas[1], LAYOUT.canvas[2]) }
    screen = love.graphics.newCanvas(R.screenSize(LAYOUT))
    local drew = true
    local dr = love.math.newRandomGenerator(3)
    for _, st in ipairs({ "title", "setup", "intro", "play", "roundover", "gameover", "stageclear", "demo" }) do
      for _, mode in ipairs({ "solo", "versus" }) do
        G.state = st
        G.mode = mode
        G.active = { true, mode == "versus" }
        G.cursor = { 2, 3 }
        G.timer = 100
        G.roundWinner = 1
        G.boards = { Board.new(5, "med", dr), mode == "versus" and Board.new(5, "med", dr) or nil }
        G.ai = { AI.new(G.boards[1], dr), G.boards[2] and AI.new(G.boards[2], dr) or nil }
        local ok, err = pcall(love.draw)
        if not ok then drew = false print("draw error in " .. layoutName .. "/" .. st .. "/" .. mode .. ": " .. tostring(err)) end
      end
    end
    check(drew, "all screens draw in layout " .. layoutName)
  end
  love.graphics.setCanvas()
  goTitle()

  -- 8b. title cursor: down moves the heart, start from the other seat confirms it
  G.titleSel = 1
  tick({ { downP = true }, {} })
  check(G.titleSel == 2, "down moves the title heart to 2 PLAYER GAME")
  tick({ {}, { start = true } })
  check(G.state == "setup" and G.mode == "versus", "start confirms the highlighted option")
  goTitle()

  -- 8b1. Start on the high score page dismisses it instead of starting a game
  G.titlePage, G.titleSel = 1, 2
  tick({ { start = true }, {} })
  check(G.state == "title" and G.titlePage == 0, "start on the high scores page returns to the menu")
  tick({ { start = true }, {} })
  check(G.state == "setup", "the next start on the menu starts the game")
  goTitle()

  -- 8b2. after a round only the winner's Start moves things along
  G.mode, G.active, G.cpu = "versus", { true, true }, { false, false }
  G.wins, G.roundWinner = { 1, 0 }, 1
  G.settings = { { level = 3, speed = "low" }, { level = 3, speed = "low" } }
  G.state, G.timer = "roundover", 0
  tick({ {}, { start = true } })
  check(G.state == "roundover", "loser's start is ignored after a round")
  tick({ { start = true }, {} })
  check(G.state == "intro", "winner's start begins the next round")
  G.cpu = { false, true }
  G.wins, G.roundWinner = { 0, 1 }, 2
  G.state, G.timer = "roundover", 0
  tick({ { start = true }, {} })
  check(G.state == "intro", "when the computer wins, the human's start continues")
  goTitle()

  -- 8c. VS COMPUTER: player 2 is driven by the AI and copies player 1's settings
  G.titleSel = 3
  G.settings[1] = { level = 4, speed = "low" }
  tick({ { start = true }, {} })
  check(G.state == "setup" and G.cpu[2], "third title option starts a computer game")
  tick({ { start = true }, {} })
  check(G.state == "intro" and G.settings[2].level == 4 and G.ai and G.ai[2], "computer copies player 1's level and gets an AI")
  for _ = 1, 100 do tick({ {}, {} }) end
  for _ = 1, 1200 do tick({ {}, {} }) end
  check(G.boards[2].capsulesDropped > 3, "computer player actually plays (" .. G.boards[2].capsulesDropped .. " capsules)")
  goTitle()

  -- 9. all music slots load (external file or built-in) and every effect exists
  local mok, merr = pcall(music.load)
  check(mok, "music loads (" .. tostring(merr) .. ")")
  if mok then
    local parts = {}
    for _, slot in ipairs({ "title", "select", "fever", "chill", "feverclear", "chillclear", "gameover", "matchwin", "victory" }) do
      parts[#parts + 1] = slot .. "=" .. tostring(music.info[slot])
      if not music.tracks[slot] then fails = fails + 1 print("FAIL: missing music slot " .. slot) end
    end
    print("music: " .. table.concat(parts, ", "))
  end
  local missing, ext = {}, {}
  for _, name in ipairs(sfx.NAMES) do
    if not sfx.sounds[name] then missing[#missing + 1] = name end
    if sfx.info[name] then ext[#ext + 1] = name .. "=" .. sfx.info[name] end
  end
  print("sfx files: " .. (#ext > 0 and table.concat(ext, ", ") or "none"))
  check(#missing == 0, "all sound effects present" .. (#missing > 0 and (": missing " .. table.concat(missing, ",")) or ""))
  -- combo sounds: smallest junk combo is combo1, bigger is combo2
  b = blankBoard()
  for x = 1, 3 do b.grid[16][x] = { color = "red", kind = "virus" } end
  for y = 13, 15 do b.grid[y][5] = { color = "yellow", kind = "virus" } end
  b.grid[16][8] = { color = "blue", kind = "virus" }
  b.viruses = 7
  b.capsule = { x = 4, y = 16, o = 0, a = "red", b = "yellow" }
  b.state = "falling"
  settle(b)
  local got = {}
  for _, e in ipairs(b:drainEvents()) do got[e] = true end
  check(got.combo1 and not got.combo2, "two matches from one capsule play combo1")

  print(fails == 0 and "SELFTEST OK" or ("SELFTEST FAILED: " .. fails))
  love.event.quit(fails == 0 and 0 or 1)
end

-------------------------------------------------------------------------------
function love.load(args)
  love.mouse.setVisible(false)
  for _, a in ipairs(args or {}) do
    if a == "--selftest" then testMode = true end
    if a == "--probe" then probeMode = true end
    if a == "--sounds" then showSounds = true end
    if a == "--pads" then showPads = true end
    if a == "--shot" then shotMode = "play" end
    local shotArg = a:match("^%-%-shot=(%w+)$")
    if shotArg then shotMode = shotArg end
    local layoutArg = a:match("^%-%-layout=(%w+)$")
    if layoutArg then CFG.layout = layoutArg end
  end
  readScreenConf()
  LAYOUT = R.LAYOUTS[CFG.layout] or R.LAYOUTS.side
  R.noBottleSprite = LAYOUT.drawnBottle or false
  rng = love.math.newRandomGenerator(os.time())
  R.SEAM = CFG.capsuleSeam or "black"
  R.SEAM_WIDTH = tonumber(CFG.capsuleSeamWidth) or 1
  R.load()
  sfx.load()
  HS.load()
  love.audio.setVolume((testMode or shotMode) and 0 or 1)
  if CFG.music and not testMode then
    music.load()
    playMusic("title")
  end
  local cw, ch = LAYOUT.canvas[1], LAYOUT.canvas[2]
  half = { love.graphics.newCanvas(cw, ch), love.graphics.newCanvas(cw, ch) }
  screen = love.graphics.newCanvas(R.screenSize(LAYOUT))
  for _, c in ipairs({ half[1], half[2], screen }) do c:setFilter("nearest", "nearest") end
  if CFG.fullscreen then
    love.window.setFullscreen(true)
  elseif not testMode then
    -- desktop window at 2x the screen, turned to match screenRotation
    local sw, sh = R.screenSize(LAYOUT)
    local ww, wh = sw * 2, sh * 2
    if CFG.screenRotation % 180 ~= 0 then ww, wh = wh, ww end
    love.window.setMode(ww, wh, { resizable = true, vsync = 1 })
  end

  if testMode then selftest() end
  if probeMode then
    love.audio.setVolume(0)
    music.load()
    require("probe")(G, tick, beginGame, startRound, AI, Board, music, HS, sfx)
    love.event.quit()
  end
  if shotMode == "scores" then
    G.titlePage = 1
  elseif shotMode == "roundover" then
    G.settings = { { level = 5, speed = "low" }, { level = 5, speed = "low" } }
    beginGame(2)
    startRound()
    G.state = "roundover"
    G.wins, G.roundWinner, G.timer = { 1, 0 }, 1, 0
  elseif shotMode == "soloselect" then
    G.settings[1] = { level = 10, speed = "med" }
    beginGame(1)
  elseif shotMode == "solo" or shotMode == "throw" then
    local r = love.math.newRandomGenerator(11)
    G.settings[1] = { level = 8, speed = "med" }
    beginGame(1)
    startRound()
    G.state = "play"
    local ai = AI.new(G.boards[1], r)
    for _ = 1, 900 do
      tick({ ai:input(), {} })
      if G.state ~= "play" then break end
    end
    if shotMode == "throw" then
      -- run on until the doctor is mid-throw
      for _ = 1, 3000 do
        tick({ ai:input(), {} })
        local b = G.boards[1]
        if b.state == "spawn" and b.spawnTimer == math.floor(Board.spawnDelay / 2) then break end
        if G.state ~= "play" then break end
      end
    end
  elseif shotMode == "paused" then
    local r = love.math.newRandomGenerator(7)
    G.settings = { { level = 12, speed = "med" }, { level = 12, speed = "med" } }
    beginGame(2)
    startRound()
    G.state = "play"
    G.ai = { AI.new(G.boards[1], r), AI.new(G.boards[2], r) }
    for _ = 1, 500 do tick({ G.ai[1]:input(), G.ai[2]:input() }) if G.state ~= "play" then break end end
    G.state, G.pauseSel = "paused", 2
  elseif shotMode == "select" then
    G.settings = { { level = 5, speed = "low" }, { level = 5, speed = "med" } }
    beginGame(2)
    G.cursor = { 2, 2 }
  elseif shotMode == "play" then
    local r = love.math.newRandomGenerator(7)
    G.settings = { { level = 12, speed = "med" }, { level = 12, speed = "med" } }
    beginGame(2)
    startRound()
    G.state = "play"
    G.ai = { AI.new(G.boards[1], r), AI.new(G.boards[2], r) }
    for _ = 1, 1500 do
      tick({ G.ai[1]:input(), G.ai[2]:input() })
      if G.state ~= "play" then break end
    end
    G.ai = nil
  end
end
