-- board.lua : Dr. Mario rules for one bottle. Pure logic, no drawing.
-- Grid is grid[y][x], x = 1..8 left to right, y = 1..16 top to bottom.
-- A cell is nil or { color = "red"|"yellow"|"blue", kind = "virus"|"half", link = nil|"left"|"right"|"up"|"down" }
local Board = {}
Board.__index = Board

local W, H = 8, 16
Board.W, Board.H = W, H
Board.COLORS = { "red", "yellow", "blue" }
local COLORS = Board.COLORS

-- NES gravity table (NTSC), frames per row, indexed by speed = base + fine.
-- Base is LOW 15 / MED 25 / HI 31. Fine starts at 0, goes up by one just before the
-- 9th capsule and every 10 capsules after that, capped at 49. Level does not change
-- gravity on the NES, only the virus count. Source: wiki.drmar.io Mechanics (NES).
local SPEED_TABLE = {
  70, 68, 66, 64, 62, 60, 58, 56, 54, 52, 50, 48, 46, 44, 42, 40, 38, 36, 34, 32,
  30, 28, 26, 24, 22, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 10, 9, 9, 8,
  8, 7, 7, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5, 5,
  4, 4, 4, 4, 4, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1,
}
local SPEED_START = { low = 15, med = 25, hi = 31 }
local FINE_MAX = 49
-- NES DAS: move on press, again after 16 frames, then every 6.
local DAS_DELAY, DAS_REPEAT = 16, 6
-- Extra frames a landed capsule may still slide before locking. The NES has none: it
-- locks the frame a downward move fails, and the slide window is simply the time until
-- the next gravity tick. main.lua sets this from config for people who want more.
Board.slideFrames = 0
-- Frames between a capsule locking (and any clears settling) and the next one appearing.
Board.spawnDelay = 24
local FLASH_FRAMES = 16
-- Junk: clearing garbageMin or more matches from one capsule (chains included) sends
-- that many junk halves to the other bottle, capped at garbageMax. NES is 2 and 4.
Board.garbageMin = 2
Board.garbageMax = 4
-- Frames per row for anything falling through the bottle after a lock: pieces
-- settling after a clear and junk raining down from the top.
Board.fallFrames = 10

local function virusCount(level) return math.min((level + 1) * 4, 84) end

-- Viruses only spawn in the bottom rows; higher levels fill higher.
local function virusTopRow(level)
  if level <= 14 then return 7
  elseif level <= 16 then return 6
  elseif level <= 18 then return 5
  else return 4 end
end

function Board.new(level, speed, rng)
  local b = setmetatable({}, Board)
  b.level, b.speed, b.rng = level, speed, rng
  b.grid = {}
  for y = 1, H do b.grid[y] = {} end
  b.viruses, b.capsulesDropped, b.score = 0, 0, 0
  b.state = "spawn" -- spawn | falling | resolving | dead | won
  b.phase = "clear"
  b.capsule = nil
  b.nextPair = b:randomPair()
  b.fallTimer, b.resolveTimer = 0, 0
  b.frame, b.slideTimer, b.spawnTimer = 0, 0, 0
  b.downLatch = false
  b.heldDir, b.heldFrames = nil, 0
  b.pendingGarbage, b.outgoing = {}, {}
  b.lockColors = {}
  b.flash = nil
  b.events = {}
  b.lensHit = { red = 0, yellow = 0, blue = 0 } -- frames left of the lens virus's hop
  b:placeViruses()
  return b
end

function Board:emit(e) self.events[#self.events + 1] = e end
function Board:drainEvents() local e = self.events self.events = {} return e end
function Board:takeOutgoing() local o = self.outgoing self.outgoing = {} return o end

function Board:get(x, y)
  if x < 1 or x > W or y < 1 or y > H then return nil end
  return self.grid[y][x]
end

-- Empty and inside the bottle. y = 0 counts as free: that is the neck above the spawn point.
function Board:free(x, y)
  if x < 1 or x > W or y > H then return false end
  if y < 1 then return true end
  return self.grid[y][x] == nil
end

function Board:randomPair()
  return { COLORS[self.rng:random(3)], COLORS[self.rng:random(3)] }
end

-- NES rule: a virus never has the same colour two cells away in a straight line.
function Board:placeViruses()
  local want, top = virusCount(self.level), virusTopRow(self.level)
  local placed, tries = 0, 0
  while placed < want and tries < 20000 do
    tries = tries + 1
    local x, y = self.rng:random(W), self.rng:random(top, H)
    if not self.grid[y][x] then
      local start = self.rng:random(3)
      for i = 0, 2 do
        local c = COLORS[(start + i - 1) % 3 + 1]
        local ok = true
        for _, d in ipairs({ { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do
          local n = self:get(x + d[1], y + d[2])
          if n and n.color == c then ok = false end
        end
        if ok then
          self.grid[y][x] = { color = c, kind = "virus" }
          placed = placed + 1
          break
        end
      end
    end
  end
  self.viruses = placed
end

-- Capsule: anchor (x, y) is the bottom-left cell. o = orientation 0..3, clockwise.
-- Returns the two cells as {x, y, color}. First is the anchor.
function Board.capsuleCells(c)
  local x, y = c.x, c.y
  if c.o == 0 then return { x, y, c.a }, { x + 1, y, c.b }
  elseif c.o == 1 then return { x, y, c.b }, { x, y - 1, c.a }
  elseif c.o == 2 then return { x, y, c.b }, { x + 1, y, c.a }
  else return { x, y, c.a }, { x, y - 1, c.b } end
end

function Board:capsuleFits(c)
  local p, q = Board.capsuleCells(c)
  return self:free(p[1], p[2]) and self:free(q[1], q[2])
end

function Board:spawn()
  local c = { x = 4, y = 1, o = 0, a = self.nextPair[1], b = self.nextPair[2] }
  if not self:capsuleFits(c) then
    self.state = "dead"
    self:emit("dead")
    return
  end
  self.capsule = c
  self.nextPair = self:randomPair()
  self.fallTimer = 0
  self.slideTimer = 0
  -- a held down button does nothing to a new capsule until it is released and pressed again
  self.downLatch = true
  self.state = "falling"
end

function Board:fineSpeed()
  return math.min(FINE_MAX, math.floor((self.capsulesDropped + 2) / 10))
end

function Board:tryMove(dx, dy)
  local c = self.capsule
  local t = { x = c.x + dx, y = c.y + dy, o = c.o, a = c.a, b = c.b }
  if self:capsuleFits(t) then
    c.x, c.y = t.x, t.y
    return true
  end
  return false
end

function Board:tryRotate(dir)
  local c = self.capsule
  local t = { x = c.x, y = c.y, o = (c.o + dir) % 4, a = c.a, b = c.b }
  if self:capsuleFits(t) then
    c.o = t.o
    self:emit("rotate")
    return true
  end
  -- Wall kick: turning flat against the right wall shifts the capsule left.
  if t.o % 2 == 0 then
    t.x = c.x - 1
    if self:capsuleFits(t) then
      c.x, c.o = t.x, t.o
      self:emit("rotate")
      return true
    end
  end
  return false
end

function Board:framesPerRow()
  local idx = math.min(SPEED_START[self.speed] + self:fineSpeed(), #SPEED_TABLE - 1)
  return SPEED_TABLE[idx + 1]
end

function Board:lock()
  local c = self.capsule
  local p, q = Board.capsuleCells(c)
  if p[2] < 1 or q[2] < 1 then
    self.state = "dead"
    self:emit("dead")
    return
  end
  local vertical = c.o % 2 == 1
  self.grid[p[2]][p[1]] = { color = p[3], kind = "half", link = vertical and "up" or "right" }
  self.grid[q[2]][q[1]] = { color = q[3], kind = "half", link = vertical and "down" or "left" }
  self.capsule = nil
  self.capsulesDropped = self.capsulesDropped + 1
  self.lockColors = {}
  self.state, self.phase, self.resolveTimer = "resolving", "clear", 0
  self:emit("lock")
  -- the chime plays when the fine speed steps up: before the 9th, 19th, 29th... capsule
  if (self.capsulesDropped + 2) % 10 == 0 and self:fineSpeed() <= FINE_MAX then self:emit("speedup") end
end

-- Downward step. Locks the frame it fails, like the NES, unless slideFrames grants more.
function Board:stepDown()
  if self:tryMove(0, 1) then
    self.fallTimer = 0
    self.slideTimer = 0
    return true
  end
  if self.slideTimer < Board.slideFrames then
    self.slideTimer = self.slideTimer + 1
    self.fallTimer = 0
    return false
  end
  self:lock()
  return false
end

-- Which virus colours are still in the bottle (drives the magnifier).
function Board:virusColors()
  local present = {}
  for y = 1, H do
    for x = 1, W do
      local c = self.grid[y][x]
      if c and c.kind == "virus" then present[c.color] = true end
    end
  end
  return present
end

-- NES order each frame: vertical movement, then left/right with DAS, then rotation.
function Board:tickFalling(inp)
  self.frame = self.frame + 1

  -- Soft drop only counts when down is pressed on its own. Down plus a direction
  -- cancels it, so a capsule can be slid along the floor without locking.
  if not inp.down then self.downLatch = false end
  local soft = inp.down and not self.downLatch and not inp.left and not inp.right
  if soft then
    if self.frame % 2 == 1 then
      self:stepDown()
    end
  else
    self.fallTimer = self.fallTimer + 1
    if self.fallTimer >= self:framesPerRow() then
      self:stepDown()
    end
  end
  if self.state ~= "falling" then return end

  local dir
  if inp.left and not inp.right then dir = -1 elseif inp.right and not inp.left then dir = 1 end
  if dir then
    local moved
    if dir ~= self.heldDir then
      self.heldDir, self.heldFrames = dir, 0
      moved = self:tryMove(dir, 0)
      if moved then self:emit("move") else self.heldFrames = DAS_DELAY - 1 end
    else
      self.heldFrames = self.heldFrames + 1
      if self.heldFrames >= DAS_DELAY and (self.heldFrames - DAS_DELAY) % DAS_REPEAT == 0 then
        moved = self:tryMove(dir, 0)
        if moved then self:emit("move") else self.heldFrames = DAS_DELAY - 1 end
      end
    end
  else
    self.heldDir = nil
  end

  if inp.rotCW then self:tryRotate(1) end
  if inp.rotCCW then self:tryRotate(-1) end
end

-- Every straight run of four or more same-coloured cells, rows then columns.
function Board:findRuns()
  local runs = {}
  local function scan(cells)
    local i = 1
    while i <= #cells do
      local c = self.grid[cells[i][2]][cells[i][1]]
      local j = i
      if c then
        while j + 1 <= #cells do
          local n = self.grid[cells[j + 1][2]][cells[j + 1][1]]
          if n and n.color == c.color then j = j + 1 else break end
        end
        if j - i + 1 >= 4 then
          local run = { color = c.color }
          for k = i, j do run[#run + 1] = cells[k] end
          runs[#runs + 1] = run
        end
      end
      i = j + 1
    end
  end
  for y = 1, H do
    local row = {}
    for x = 1, W do row[x] = { x, y } end
    scan(row)
  end
  for x = 1, W do
    local col = {}
    for y = 1, H do col[y] = { x, y } end
    scan(col)
  end
  return runs
end

function Board:clearRuns(runs)
  local flash, virusesCleared = {}, 0
  for _, run in ipairs(runs) do
    self.lockColors[#self.lockColors + 1] = run.color
    for _, cell in ipairs(run) do
      local x, y = cell[1], cell[2]
      local c = self.grid[y][x]
      if c then
        if c.kind == "virus" then
          self.viruses = self.viruses - 1
          virusesCleared = virusesCleared + 1
          self.lensHit[c.color] = 30
        elseif c.link then
          local px, py = x, y
          if c.link == "right" then px = x + 1
          elseif c.link == "left" then px = x - 1
          elseif c.link == "up" then py = y - 1
          else py = y + 1 end
          local partner = self:get(px, py)
          if partner then partner.link = nil end
        end
        self.grid[y][x] = nil
        flash[#flash + 1] = { x, y, c.color }
      end
    end
  end
  local mult = ({ low = 1, med = 2, hi = 3 })[self.speed]
  for i = 1, virusesCleared do
    self.score = self.score + 100 * mult * (2 ^ (i - 1))
  end
  self.flash = flash
  self:emit(virusesCleared > 0 and "virus" or "clear")
end

-- One row of gravity for loose halves and intact pairs. Viruses never move.
-- Bottom-up so a piece is never moved twice in one step.
function Board:gravityStep()
  local moved = false
  local g = self.grid
  for y = H - 1, 1, -1 do
    for x = 1, W do
      local c = g[y][x]
      if c and c.kind == "half" then
        if c.link == nil then
          if g[y + 1][x] == nil then
            g[y + 1][x], g[y][x] = c, nil
            moved = true
          end
        elseif c.link == "right" then
          if g[y + 1][x] == nil and g[y + 1][x + 1] == nil then
            g[y + 1][x], g[y + 1][x + 1] = c, g[y][x + 1]
            g[y][x], g[y][x + 1] = nil, nil
            moved = true
          end
        elseif c.link == "up" then
          if g[y + 1][x] == nil and y > 1 then
            g[y + 1][x], g[y][x] = c, g[y - 1][x]
            g[y - 1][x] = nil
            moved = true
          end
        end
      end
    end
  end
  return moved
end

function Board:tickResolving()
  if self.resolveTimer > 0 then
    self.resolveTimer = self.resolveTimer - 1
    return
  end
  if self.phase == "clear" then
    local runs = self:findRuns()
    if #runs > 0 then
      self:clearRuns(runs)
      self.phase, self.resolveTimer = "fall", FLASH_FRAMES
    else
      self:finishResolve()
    end
  else
    self.flash = nil
    if self:gravityStep() then
      self.resolveTimer = Board.fallFrames
    else
      self.garbageFalling = false
      self.phase = "clear"
    end
  end
end

-- Two or more matches from one capsule send that many garbage halves to the opponent.
function Board:finishResolve()
  local n = #self.lockColors
  if n >= Board.garbageMin then
    for i = 1, math.min(n, Board.garbageMax) do self.outgoing[#self.outgoing + 1] = self.lockColors[i] end
    -- combo1: the smallest junk-sending combo. combo2: anything bigger.
    self:emit(n > Board.garbageMin and "combo2" or "combo1")
  end
  self.lockColors = {}
  if self.viruses <= 0 then
    self.state = "won"
    self:emit("won")
  else
    self.state = "spawn"
    self.spawnTimer = Board.spawnDelay
  end
end

function Board:dropGarbage()
  local cols = {}
  for x = 1, W do cols[x] = x end
  for i = W, 2, -1 do
    local j = self.rng:random(i)
    cols[i], cols[j] = cols[j], cols[i]
  end
  for i, color in ipairs(self.pendingGarbage) do
    if i > Board.garbageMax then break end
    local x = cols[i]
    if self.grid[1][x] == nil then
      self.grid[1][x] = { color = color, kind = "half" }
    end
  end
  self.pendingGarbage = {}
  self.lockColors = {}
  self.garbageFalling = true
  self.state, self.phase, self.resolveTimer = "resolving", "fall", 0
  self:emit("garbage")
end

-- One 60 Hz step. inp = { left, right, down (held), rotCW, rotCCW (pressed this frame) }
function Board:tick(inp)
  for color, n in pairs(self.lensHit) do
    if n > 0 then self.lensHit[color] = n - 1 end
  end
  if self.state == "spawn" then
    if self.spawnTimer > 0 then
      self.spawnTimer = self.spawnTimer - 1
    elseif #self.pendingGarbage > 0 then
      self:dropGarbage()
    else
      self:spawn()
    end
  elseif self.state == "falling" then
    self:tickFalling(inp)
  elseif self.state == "resolving" then
    self:tickResolving()
  end
end

-- Consistency check used by the self test.
function Board:validate()
  local viruses = 0
  for y = 1, H do
    for x = 1, W do
      local c = self.grid[y][x]
      if c then
        if c.kind == "virus" then
          viruses = viruses + 1
        elseif c.link then
          local px, py, back = x, y, nil
          if c.link == "right" then px, back = x + 1, "left"
          elseif c.link == "left" then px, back = x - 1, "right"
          elseif c.link == "up" then py, back = y - 1, "down"
          else py, back = y + 1, "up" end
          local p = self:get(px, py)
          if not p or p.kind ~= "half" or p.link ~= back then
            return false, ("broken link at %d,%d"):format(x, y)
          end
        end
      end
    end
  end
  if viruses ~= self.viruses then
    return false, ("virus count %d vs %d"):format(viruses, self.viruses)
  end
  return true
end

return Board
