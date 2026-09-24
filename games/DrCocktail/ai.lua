-- ai.lua : the computer player, used for VS COMPUTER and the attract-mode demo.
-- For each new capsule it scores every (column, orientation) landing spot and then
-- feeds the board left/right/rotate/down inputs to get there.
--
-- How good it is comes from its skill (the virus level and speed are player 1's either
-- way, so a skill only changes the computer itself):
--   easy        slow hands, often picks a poor spot, never hurries a capsule down
--   normal      how the computer has always played
--   hard        quick hands, and it plans for the next capsule as well as this one
--   impossible  as fast as the controls allow, planning the same way
local Board = require("board")
local AI = {}
AI.__index = AI

AI.SKILLS = { "easy", "normal", "hard", "impossible" }
local SKILL = {
  --          frames between presses   extra noise in its judgement   chance of a blunder   hurries down   looks one capsule ahead
  easy       = { rotate = 16, move = 13, noise = 60,  blunder = 0.25, drop = false, ahead = false },
  normal     = { rotate = 6,  move = 5,  noise = 5,   blunder = 0,    drop = true,  ahead = false },
  hard       = { rotate = 4,  move = 4,  noise = 0.5, blunder = 0,    drop = true,  ahead = true },
  impossible = { rotate = 2,  move = 2,  noise = 0,   blunder = 0,    drop = true,  ahead = true },
}

function AI.new(board, rng, skill)
  local s = SKILL[skill or "normal"] or SKILL.normal
  return setmetatable({ board = board, rng = rng, target = nil, cooldown = 0, skill = s }, AI)
end

-- A board with a few extra cells laid on top, so a placement can be tried without
-- touching the real one.
local Trial = {}
Trial.__index = Trial
Trial.capsuleFits = Board.capsuleFits
function Trial.new(base, cells)
  local extra = {}
  for _, cell in ipairs(cells) do extra[cell[1] + cell[2] * 100] = { color = cell[3], kind = "capsule" } end
  return setmetatable({ base = base, extra = extra }, Trial)
end
function Trial:get(x, y)
  return self.extra[x + y * 100] or self.base:get(x, y)
end
function Trial:free(x, y)
  if x < 1 or x > Board.W or y > Board.H then return false end
  if y < 1 then return true end
  return self:get(x, y) == nil
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
  return score
end

-- Every spot a capsule with colours a, b can come to rest on this board, with its score.
local function landings(b, spawn, a, bcol)
  local out = {}
  for o = 0, 3 do
    for x = 1, Board.W do
      local t = { x = x, y = spawn.y, o = o, a = a, b = bcol }
      if b:capsuleFits(t) then
        t.y = dropRow(b, t)
        out[#out + 1] = { x = x, o = o, t = t, score = scorePlacement(b, t) }
      end
    end
  end
  return out
end

function AI:chooseTarget()
  local b, s = self.board, self.skill
  local c = b.capsule
  local spots = landings(b, c, c.a, c.b)
  if #spots == 0 then self.target = nil return end
  if s.blunder > 0 and self.rng:random() < s.blunder then
    local pick = spots[self.rng:random(#spots)]
    self.target = { x = pick.x, o = pick.o }
    return
  end
  local best, bestScore = nil, -math.huge
  for _, spot in ipairs(spots) do
    local score = spot.score
    if s.ahead and b.nextPair and score > -1e8 then
      -- lay this capsule down, then see how well the next one could go
      local p, q = Board.capsuleCells(spot.t)
      local after = Trial.new(b, { p, q })
      local nextBest = -1e9
      for _, n in ipairs(landings(after, c, b.nextPair[1], b.nextPair[2])) do
        if n.score > nextBest then nextBest = n.score end
      end
      score = score + 0.6 * nextBest
    end
    score = score + self.rng:random() * s.noise
    if score > bestScore then best, bestScore = { x = spot.x, o = spot.o }, score end
  end
  self.target = best
end

-- Returns an input table for this frame.
function AI:input()
  local b, s = self.board, self.skill
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
    self.cooldown = s.rotate
  elseif c.x < t.x then
    inp.right = true
    self.cooldown = s.move
  elseif c.x > t.x then
    inp.left = true
    self.cooldown = s.move
  elseif s.drop then
    inp.down = true
  end
  return inp
end

return AI
