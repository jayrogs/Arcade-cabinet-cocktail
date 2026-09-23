-- ai.lua : a simple computer player used for the attract-mode demo.
-- For each new capsule it scores every (column, orientation) landing spot and then
-- feeds the board left/right/rotate/down inputs to get there.
local Board = require("board")
local AI = {}
AI.__index = AI

function AI.new(board, rng)
  return setmetatable({ board = board, rng = rng, target = nil, cooldown = 0 }, AI)
end

-- Where would this capsule come to rest if dropped straight down from here?
local function dropRow(b, c)
  local t = { x = c.x, y = c.y, o = c.o, a = c.a, b = c.b }
  while true do
    t.y = t.y + 1
    if not b:capsuleFits(t) then return t.y - 1 end
  end
end

local function colorAt(b, x, y)
  local c = b:get(x, y)
  return c and c.color
end

-- Higher is better. Rewards touching same colours, completed runs, and staying low.
local function scorePlacement(b, c)
  local p, q = Board.capsuleCells(c)
  local cells = { p, q }
  local score = 0
  for _, cell in ipairs(cells) do
    local x, y, col = cell[1], cell[2], cell[3]
    if y < 1 then return -1e9 end
    -- run length through this cell in both axes, counting the other half too
    for _, axis in ipairs({ { 1, 0 }, { 0, 1 } }) do
      local n = 1
      for dir = -1, 1, 2 do
        local k = 1
        while true do
          local nx, ny = x + axis[1] * dir * k, y + axis[2] * dir * k
          local other = (nx == p[1] and ny == p[2]) and p[3] or ((nx == q[1] and ny == q[2]) and q[3] or nil)
          local cc = other or colorAt(b, nx, ny)
          if cc == col then n = n + 1 k = k + 1 else break end
        end
      end
      if n >= 4 then score = score + 1000
      elseif n == 3 then score = score + 60
      elseif n == 2 then score = score + 15 end
    end
    -- a virus of the same colour directly below is what we want
    local below = b:get(x, y + 1)
    if below and below.color ~= col then score = score - 25 end
    if below and below.color == col and below.kind == "virus" then score = score + 30 end
    score = score + y * 4                      -- lower is better
  end
  -- discourage burying viruses under wrong colours
  return score
end

function AI:chooseTarget()
  local b = self.board
  local c = b.capsule
  local best, bestScore = nil, -math.huge
  for o = 0, 3 do
    for x = 1, Board.W do
      local t = { x = x, y = c.y, o = o, a = c.a, b = c.b }
      if b:capsuleFits(t) then
        t.y = dropRow(b, t)
        local s = scorePlacement(b, t) + self.rng:random() * 5
        if s > bestScore then best, bestScore = { x = x, o = o }, s end
      end
    end
  end
  self.target = best
end

-- Returns an input table for this frame.
function AI:input()
  local b = self.board
  local inp = { left = false, right = false, down = false, rotCW = false, rotCCW = false }
  if b.state ~= "falling" or not b.capsule then
    self.target = nil
    return inp
  end
  if not self.target then self:chooseTarget() end
  local c, t = b.capsule, self.target
  if not t then return inp end
  self.cooldown = self.cooldown - 1
  if self.cooldown > 0 then return inp end
  if c.o ~= t.o then
    inp.rotCW = true
    self.cooldown = 6
  elseif c.x < t.x then
    inp.right = true
    self.cooldown = 5
  elseif c.x > t.x then
    inp.left = true
    self.cooldown = 5
  else
    inp.down = true
  end
  return inp
end

return AI
