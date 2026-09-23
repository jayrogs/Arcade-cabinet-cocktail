-- music.lua : the tunes, built by the game itself rather than loaded from files.
--
-- Three voices, the way an old machine would do it: a bass, a bubbling arpeggio and a
-- hi-hat. Each tune is one loop, made once when the game starts and then played round and
-- round. Everything is written in beats, so changing the speed changes the whole tune.

local M = {}

local RATE = 16000          -- plenty for square waves, and quick to build
local SEMITONE = 2 ^ (1 / 12)

-- note names to frequency, A4 = 440
local STEPS = { C = -9, D = -7, E = -5, F = -4, G = -2, A = 0, B = 2 }
local function freq(name)
  local letter, sharp, octave = name:match("^([A-G])(#?)(%d)$")
  if not letter then return 0 end
  local n = STEPS[letter] + (sharp == "#" and 1 or 0) + (tonumber(octave) - 4) * 12
  return 440 * SEMITONE ^ n
end

-- one voice's sound at a moment: square, soft square, or noise
local function wave(kind, phase, seed)
  if kind == "noise" then
    -- a repeatable rattle, so the loop joins itself cleanly
    return (((seed * 1103515245 + 12345) % 65536) / 32768) - 1
  end
  local s = phase % 1
  if kind == "square" then return s < 0.5 and 1 or -1 end
  if kind == "pulse" then return s < 0.25 and 1 or -1 end        -- thinner, reedier
  return math.sin(phase * 2 * math.pi)
end

-- add one note to the buffer
local function put(buf, n, start, length, f, kind, vol, decay)
  local i0 = math.floor(start * RATE)
  local i1 = math.min(n, math.floor((start + length) * RATE))
  local phase = 0
  local step = f / RATE
  for i = i0, i1 - 1 do
    local age = (i - i0) / math.max(1, i1 - i0)
    local env
    if decay == "pluck" then env = (1 - age) ^ 2
    elseif decay == "hit" then env = math.max(0, 1 - age * 4)
    else env = math.min(1, (1 - age) * 3) * math.min(1, age * 40) end
    phase = phase + step
    buf[i + 1] = (buf[i + 1] or 0) + wave(kind, phase, i) * env * vol
  end
end

-- A tune is: bars of chords, a bass note per beat, and an arpeggio riding on top.
local TUNES = {
  play = {
    bpm = 138,
    chords = {                        -- four bars, each: bass note then three notes to climb
      { "A2", { "A3", "C4", "E4" } },
      { "F2", { "F3", "A3", "C4" } },
      { "G2", { "G3", "B3", "D4" } },
      { "E2", { "E3", "G3", "B3" } },
    },
    hats = true, lead = true,
  },
  title = {
    bpm = 104,
    chords = {
      { "A2", { "A3", "C4", "E4" } },
      { "E2", { "E3", "G3", "B3" } },
      { "F2", { "F3", "A3", "C4" } },
      { "G2", { "G3", "B3", "D4" } },
    },
    hats = false, lead = false,
  },
}

local function build(spec)
  local beat = 60 / spec.bpm
  local bars = #spec.chords
  local length = bars * 4 * beat                 -- four beats to the bar
  local n = math.floor(length * RATE)
  local buf = {}
  for bar = 0, bars - 1 do
    local chord = spec.chords[bar + 1]
    local bass, notes = freq(chord[1]), chord[2]
    local t0 = bar * 4 * beat
    -- the bass, on every beat, with an extra push on the off-beat
    for b = 0, 3 do
      put(buf, n, t0 + b * beat, beat * 0.45, bass, "square", 0.22, "hit")
      put(buf, n, t0 + (b + 0.5) * beat, beat * 0.22, bass, "square", 0.12, "hit")
    end
    -- the arpeggio: sixteenths climbing the chord and back down
    local order = { 1, 2, 3, 2 }
    for s = 0, 15 do
      local f = freq(notes[order[(s % 4) + 1]])
      put(buf, n, t0 + s * beat / 4, beat / 4 * 0.9, f, "pulse", 0.075, "pluck")
    end
    -- a slow melody note over each bar, an octave up
    if spec.lead then
      put(buf, n, t0 + beat * 0.5, beat * 1.4, freq(notes[3]) * 2, "square", 0.085, "soft")
      put(buf, n, t0 + beat * 2.5, beat * 1.2, freq(notes[2]) * 2, "square", 0.07, "soft")
    end
    if spec.hats then
      for s = 0, 7 do
        put(buf, n, t0 + (s + 0.5) * beat / 2, 0.035, 0, "noise", s % 2 == 0 and 0.05 or 0.09, "hit")
      end
    end
  end
  local sd = love.sound.newSoundData(n, RATE, 16, 1)
  for i = 0, n - 1 do
    local v = buf[i + 1] or 0
    if v > 1 then v = 1 elseif v < -1 then v = -1 end
    sd:setSample(i, v)
  end
  local src = love.audio.newSource(sd, "static")
  src:setLooping(true)
  return src, sd
end

local made, raw = {}, {}
local playing = nil

function M.load(name)
  if not made[name] then made[name], raw[name] = build(TUNES[name]) end
  return made[name]
end

function M.data(name)            -- the samples themselves, for the self test
  M.load(name)
  return raw[name]
end

function M.play(name, volume)
  if playing == made[name] and playing and playing:isPlaying() then return end
  M.stop()
  local s = M.load(name)
  s:setVolume(volume or 0.5)
  s:seek(0)
  s:play()
  playing = s
end

function M.stop()
  if playing then playing:stop() end
  playing = nil
end

function M.duck(v)              -- quieten under a win jingle, say
  if playing then playing:setVolume(v) end
end

return M
