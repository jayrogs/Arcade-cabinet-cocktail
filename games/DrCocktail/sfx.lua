-- sfx.lua : sound effects. Built-in ones are synthesised NES-style at startup.
-- Drop a file into the sfx/ folder to replace one. A file named exactly after the effect
-- wins (virus.wav); otherwise the filename is matched on words, so "combo-sound.mp3" is
-- combo1 and "combo-sound-2.mp3" is combo2. Names:
--   move     capsule steps sideways
--   rotate   capsule turns
--   lock     capsule lands
--   clear    four in a row, capsule pieces only
--   virus    four in a row that took out a virus
--   combo1   the smallest combo that throws junk (two matches from one capsule)
--   combo2   a bigger combo (three or more matches)
--   garbage  junk dropped into your bottle
--   dead     bottle overflowed
--   won      last virus cleared
--   coin     credit added
--   start    game started
--   ready    player readied up / menu confirm
--   speedup  five-note chime when the drop speed steps up (every ten capsules)
--   ting     menu cursor moved or an option changed
local sfx = {}
local RATE = 22050

local NAMES = { "move", "rotate", "lock", "clear", "virus", "combo1", "combo2", "garbage", "dead", "won",
                "coin", "start", "ready", "speedup", "cursor", "ting" }
sfx.NAMES = NAMES

-- filename must contain every word in `all` and none in `none`
local HINTS = {
  combo1 = { { all = { "combo" }, none = { "2", "3", "4" } } },
  combo2 = { { all = { "combo", "2" } }, { all = { "combo", "3" } }, { all = { "combo", "big" } } },
  virus = { { all = { "virus" } } },
  garbage = { { all = { "garbage" } }, { all = { "junk" } } },
  speedup = { { all = { "speed" } } },
  ting = { { all = { "ting" } }, { all = { "menu" } }, { all = { "cursor" } } },
}

-- One note. wave: "square" | "pulse" | "tri" | "noise". f2 sweeps pitch to f2 over the note.
local function note(wave, f, dur, vol, f2)
  local n = math.floor(RATE * dur)
  local out = {}
  local phase = 0
  local rng = love.math.newRandomGenerator(7)
  for i = 0, n - 1 do
    local k = i / n
    local fr = f2 and (f + (f2 - f) * k) or f
    phase = phase + fr / RATE
    local p = phase % 1
    local v
    if wave == "square" then v = p < 0.5 and 1 or -1
    elseif wave == "pulse" then v = p < 0.25 and 1 or -1
    elseif wave == "tri" then v = 4 * math.abs(p - 0.5) - 1
    else v = rng:random() * 2 - 1 end
    out[#out + 1] = v * vol * (1 - k)
  end
  return out
end

-- Joins notes back to back into one Source.
local function seq(...)
  local parts = { ... }
  local total = 0
  for _, p in ipairs(parts) do total = total + #p end
  local sd = love.sound.newSoundData(total, RATE, 16, 1)
  local i = 0
  for _, p in ipairs(parts) do
    for _, v in ipairs(p) do
      sd:setSample(i, math.max(-1, math.min(1, v)))
      i = i + 1
    end
  end
  return love.audio.newSource(sd)
end

local function builtin()
  return {
    move = seq(note("square", 220, 0.025, 0.18)),
    rotate = seq(note("square", 660, 0.04, 0.18, 990)),
    lock = seq(note("tri", 160, 0.06, 0.3)),
    clear = seq(note("square", 660, 0.05, 0.2), note("square", 880, 0.05, 0.2), note("square", 1100, 0.07, 0.2)),
    virus = seq(note("square", 1320, 0.05, 0.22), note("square", 990, 0.05, 0.22), note("square", 660, 0.05, 0.22),
                note("square", 1320, 0.05, 0.22), note("square", 990, 0.05, 0.22), note("square", 660, 0.09, 0.22)),
    combo1 = seq(note("pulse", 400, 0.2, 0.25, 1800)),
    combo2 = seq(note("pulse", 400, 0.12, 0.25, 1800), note("pulse", 600, 0.12, 0.25, 2400), note("pulse", 800, 0.2, 0.25, 3200)),
    garbage = seq(note("pulse", 140, 0.12, 0.3, 90), note("noise", 0, 0.1, 0.2)),
    dead = seq(note("square", 440, 0.15, 0.25, 330), note("square", 330, 0.15, 0.25, 220), note("square", 220, 0.5, 0.25, 55)),
    won = seq(note("square", 523, 0.09, 0.25), note("square", 659, 0.09, 0.25), note("square", 784, 0.09, 0.25),
              note("square", 1047, 0.25, 0.25)),
    coin = seq(note("square", 988, 0.06, 0.25), note("square", 1319, 0.12, 0.25)),
    start = seq(note("square", 784, 0.08, 0.25), note("square", 1047, 0.14, 0.25)),
    ready = seq(note("square", 880, 0.05, 0.2), note("square", 1175, 0.08, 0.2)),
    speedup = seq(note("square", 784, 0.06, 0.2), note("square", 988, 0.06, 0.2), note("square", 1175, 0.06, 0.2),
                  note("square", 1319, 0.06, 0.2), note("square", 1568, 0.12, 0.2)),
    cursor = seq(note("square", 440, 0.03, 0.15)),
    ting = seq(note("square", 2093, 0.02, 0.22), note("square", 2637, 0.09, 0.2)),
  }
end

local AUDIO_EXT = { wav = true, ogg = true, mp3 = true }

local function matches(file, rule)
  local f = file:lower():gsub("%.%w+$", "")   -- drop the extension so ".mp3" is not a "3"
  for _, w in ipairs(rule.all) do if not f:find(w, 1, true) then return false end end
  for _, w in ipairs(rule.none or {}) do if f:find(w, 1, true) then return false end end
  return true
end

local function external(name, candidates, used)
  local function pick(f)
    local ok, src = pcall(love.audio.newSource, "sfx/" .. f, "static")
    if ok then used[f] = true return src, f end
    return nil
  end
  for _, f in ipairs(candidates) do
    if not used[f] and f:lower():match("^" .. name .. "%.") then return pick(f) end
  end
  for _, rule in ipairs(HINTS[name] or {}) do
    for _, f in ipairs(candidates) do
      if not used[f] and matches(f, rule) then return pick(f) end
    end
  end
  return nil
end

function sfx.load()
  sfx.sounds = builtin()
  sfx.info = {}
  local candidates, used = {}, {}
  if love.filesystem.getInfo("sfx", "directory") then
    for _, f in ipairs(love.filesystem.getDirectoryItems("sfx")) do
      local ext = f:lower():match("%.(%w+)$")
      if ext and AUDIO_EXT[ext] then candidates[#candidates + 1] = f end
    end
    table.sort(candidates)
  end
  for _, name in ipairs(NAMES) do
    local src, file = external(name, candidates, used)
    if src then
      sfx.sounds[name] = src
      sfx.info[name] = file
    end
  end
end

function sfx.play(name)
  local s = sfx.sounds and sfx.sounds[name]
  if s then
    s:stop()
    s:play()
  end
end

return sfx
