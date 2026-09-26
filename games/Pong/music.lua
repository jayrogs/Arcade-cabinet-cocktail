-- music.lua : the tunes, built by the game itself rather than loaded from files.
--
-- Written like an NES tune: a lead with a little vibrato and an echo, a triangle bass,
-- a quiet arpeggio for sparkle, and drums (kick, snare, hats). Each tune is one loop,
-- made once when the game starts and then played round and round; the echo wraps round
-- the end of the loop so it joins itself without a seam.
--
-- The square waves are smoothed at their edges (polyBLEP) and every note fades in and
-- out over a few milliseconds: the old version's raw edges and hard starts were what
-- made it buzz and click.

local M = {}

local RATE = 22050
local SEMITONE = 2 ^ (1 / 12)

-- note names to frequency, A4 = 440. "R" is a rest.
local STEPS = { C = -9, D = -7, E = -5, F = -4, G = -2, A = 0, B = 2 }
local function freq(name)
  local letter, sharp, octave = name:match("^([A-G])(#?)(%d)$")
  if not letter then return 0 end
  local n = STEPS[letter] + (sharp == "#" and 1 or 0) + (tonumber(octave) - 4) * 12
  return 440 * SEMITONE ^ n
end

local CHORDS = {
  Am = { "A", "C", "E" }, F = { "F", "A", "C" }, C = { "C", "E", "G" }, G = { "G", "B", "D" },
  E = { "E", "G#", "B" }, Em = { "E", "G", "B" }, Dm = { "D", "F", "A" },
}
local ROOT = { Am = "A2", F = "F2", C = "C3", G = "G2", E = "E2", Em = "E2", Dm = "D2" }

-- the tunes: a chord per bar, and the melody as "note:beats" (four beats to a bar)
local TUNES = {
  play = {
    bpm = 138, drums = "full", lead = "pulse",
    chords = { "Am", "F", "C", "G", "Am", "F", "G", "E",
               "F", "G", "Em", "Am", "Dm", "G", "C", "E" },
    melody = [[
      A4:.5 C5:.5 E5:1 D5:.5 C5:.5 D5:.5 E5:.5
      F5:1 E5:.5 D5:.5 C5:1 A4:1
      G4:.5 C5:.5 E5:1 G5:1 E5:1
      D5:1.5 B4:.5 G4:1 R:1
      A4:.5 C5:.5 E5:1 A5:1 G5:.5 E5:.5
      F5:.5 G5:.5 A5:1 G5:.5 F5:.5 E5:1
      D5:.5 E5:.5 F5:1 E5:.5 D5:.5 B4:1
      G#4:1 B4:1 E5:2
      C5:.5 F5:.5 A5:1.5 G5:.5 F5:1
      B4:.5 D5:.5 G5:1.5 F5:.5 E5:1
      E5:.5 G5:.5 B5:1 A5:.5 G5:.5 E5:1
      A5:1.5 E5:.5 C5:1 A4:1
      D5:.5 F5:.5 A5:1 F5:.5 D5:.5 F5:1
      G5:1 F5:.5 E5:.5 D5:1 B4:1
      C5:.5 E5:.5 G5:1 C6:1.5 B5:.5
      B5:1 G#5:1 E5:1 B4:1
    ]],
  },
  title = {
    bpm = 96, drums = "soft", lead = "triangle",
    chords = { "Am", "F", "C", "G", "Am", "F", "G", "E" },
    melody = [[
      E5:2 C5:1 A4:1
      F5:1.5 E5:.5 C5:2
      G5:2 E5:1 C5:1
      D5:3 R:1
      E5:1 A5:1 G5:1 E5:1
      F5:2 A5:1 F5:1
      G5:1 F5:1 D5:1 B4:1
      E5:3 R:1
    ]],
  },
}

-- ------------------------------------------------------------------ the voices
-- polyBLEP: rounds off the jump in a square wave so it does not alias into a buzz
local function blep(t, dt)
  if t < dt then t = t / dt; return t + t - t * t - 1
  elseif t > 1 - dt then t = (t - 1) / dt; return t * t + t + t + 1 end
  return 0
end

local function pulse(phase, dt, duty)
  local v = (phase < duty) and 1 or -1
  v = v + blep(phase, dt) - blep((phase - duty) % 1, dt)
  return v - (2 * duty - 1)                  -- keep it centred
end

local function triangle(phase)
  return 4 * math.abs(phase - 0.5) - 1
end

-- one note into a buffer. Everything wraps round the end, so the loop is seamless.
-- opts: kind ("pulse" / "triangle"), duty, vol, attack, release, vibrato
local function note(buf, n, t, dur, f, o)
  if f <= 0 then return end
  local i0 = math.floor(t * RATE)
  local len = math.floor(dur * RATE)
  local att = math.max(1, math.floor((o.attack or 0.006) * RATE))
  local rel = math.max(1, math.floor((o.release or 0.03) * RATE))
  local decay = o.decay or 0              -- how fast it fades while held (per second)
  local phase, dt = 0, f / RATE
  for k = 0, len - 1 do
    local env = 1
    if k < att then env = k / att end
    if k > len - rel then env = env * (len - k) / rel end
    if decay > 0 then env = env * math.exp(-decay * k / RATE) end
    local df = dt
    if o.vibrato and k > RATE * 0.18 then
      df = dt * (1 + 0.006 * math.sin(k / RATE * 2 * math.pi * 5.5))
    end
    phase = (phase + df) % 1
    local v
    if o.kind == "triangle" then v = triangle(phase) else v = pulse(phase, df, o.duty or 0.5) end
    local i = (i0 + k) % n + 1
    buf[i] = buf[i] + v * env * o.vol
  end
end

-- drums. The noise is repeatable, so every build of the tune is the same.
local noiseGen = love.math.newRandomGenerator(1985)
local function drum(buf, n, t, kind, vol)
  local i0 = math.floor(t * RATE)
  local last = 0
  if kind == "kick" then
    local len, phase = math.floor(0.22 * RATE), 0
    for k = 0, len - 1 do
      local s = k / RATE
      phase = phase + (45 + 115 * math.exp(-s * 32)) / RATE
      local i = (i0 + k) % n + 1
      buf[i] = buf[i] + math.sin(phase * 2 * math.pi) * math.exp(-s * 11) * vol
    end
  elseif kind == "snare" then
    local len, phase = math.floor(0.18 * RATE), 0
    for k = 0, len - 1 do
      local s = k / RATE
      local r = noiseGen:random() * 2 - 1
      local hp = r - last; last = r              -- brighter noise
      phase = phase + 185 / RATE
      local i = (i0 + k) % n + 1
      buf[i] = buf[i] + (hp * 0.45 * math.exp(-s * 16) +
                         math.sin(phase * 2 * math.pi) * 0.55 * math.exp(-s * 30)) * vol
    end
  else                                           -- "hat" and "open"
    local len = math.floor((kind == "open" and 0.2 or 0.05) * RATE)
    local fade = kind == "open" and 14 or 70
    for k = 0, len - 1 do
      local r = noiseGen:random() * 2 - 1
      local hp = r - last; last = r
      local i = (i0 + k) % n + 1
      buf[i] = buf[i] + hp * math.exp(-k / RATE * fade) * vol
    end
  end
end

local function parseMelody(text)
  local out = {}
  for name, beats in text:gmatch("(%S+):([%d%.]+)") do
    out[#out + 1] = { name, tonumber(beats) }
  end
  return out
end

-- ------------------------------------------------------------------ one tune
local function build(spec)
  local beat = 60 / spec.bpm
  local bars = #spec.chords
  local n = math.floor(bars * 4 * beat * RATE)
  local mix, lead = {}, {}
  for i = 1, n do mix[i] = 0; lead[i] = 0 end
  local soft = spec.drums == "soft"

  for bar = 0, bars - 1 do
    local name = spec.chords[bar + 1]
    local chord, t0 = CHORDS[name], bar * 4 * beat
    -- triangle bass: the root in eighths, jumping up the octave on the off-beats
    local root = freq(ROOT[name])
    for e = 0, 7 do
      local f = (e % 2 == 1 and not soft) and root * 2 or root
      if soft and e % 2 == 1 then f = 0 end
      note(mix, n, t0 + e * beat / 2, beat / 2 * (soft and 1.8 or 0.85), f,
           { kind = "triangle", vol = 0.42, release = 0.02 })
    end
    -- the sparkle: a thin pulse climbing the chord in sixteenths (eighths on the title)
    local steps = soft and 8 or 16
    local order = { 1, 2, 3, 2 }
    for s = 0, steps - 1 do
      local nm = chord[order[s % 4 + 1]] .. "4"
      note(mix, n, t0 + s * 4 * beat / steps, 4 * beat / steps * 0.8, freq(nm),
           { kind = "pulse", duty = 0.125, vol = soft and 0.07 or 0.06, decay = 9, release = 0.01 })
    end
    -- drums
    if spec.drums == "full" then
      local fill = (bar % 8 == 7)
      drum(mix, n, t0, "kick", 0.75)
      drum(mix, n, t0 + 2 * beat, "kick", 0.75)
      drum(mix, n, t0 + 2.5 * beat, "kick", 0.45)
      drum(mix, n, t0 + beat, "snare", 0.42)
      if fill then
        for s = 0, 3 do drum(mix, n, t0 + (3 + s / 4) * beat, "snare", 0.25 + s * 0.06) end
      else
        drum(mix, n, t0 + 3 * beat, "snare", 0.42)
      end
      for e = 0, 7 do
        drum(mix, n, t0 + e * beat / 2, (e == 7 and not fill) and "open" or "hat", e % 2 == 1 and 0.16 or 0.1)
      end
    else
      for e = 0, 3 do drum(mix, n, t0 + (e + 0.5) * beat, "hat", 0.06) end
    end
  end

  -- the melody, with vibrato on the longer notes
  local t = 0
  for _, m in ipairs(parseMelody(spec.melody)) do
    local dur = m[2] * beat
    if m[1] ~= "R" then
      note(lead, n, t, dur * 0.92, freq(m[1]), {
        kind = spec.lead, duty = 0.25, vol = spec.lead == "triangle" and 0.5 or 0.28,
        vibrato = m[2] >= 1, decay = spec.lead == "triangle" and 0.8 or 1.6,
      })
    end
    t = t + dur
  end
  -- an echo a dotted eighth behind (two repeats), round the loop
  local d = math.floor(beat * 0.75 * RATE)
  for i = 1, n do
    local v = lead[i]
    if v ~= 0 then
      mix[i] = mix[i] + v
      local j = (i - 1 + d) % n + 1
      mix[j] = mix[j] + v * 0.28
      j = (i - 1 + 2 * d) % n + 1
      mix[j] = mix[j] + v * 0.1
    end
  end

  -- level it: the loudest moment at 0.85, nothing clipped
  local peak = 0
  for i = 1, n do local a = math.abs(mix[i]); if a > peak then peak = a end end
  local gain = peak > 0 and 0.85 / peak or 1
  local sd = love.sound.newSoundData(n, RATE, 16, 1)
  for i = 0, n - 1 do sd:setSample(i, mix[i + 1] * gain) end
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
