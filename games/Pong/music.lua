-- music.lua : the tunes, built by the game itself rather than loaded from files.
--
-- Synthwave, the Tron sound: a saw bass rolling in sixteenths that ducks under every kick,
-- wide detuned pads, a glassy arpeggio in an echo, and a lead with the bounce of an old
-- puzzle-game tune (quarter, two eighths, quarter...), all in D minor and all sent into a
-- big reverb for the space. The title tune is the slow, floating version with no drums.
--
-- Everything is one loop. The echo and the reverb run round the loop twice and keep the
-- second time, so the tail of the end is already sounding at the start: no seam.
--
-- Building takes a second or two on the Pi, so the finished tune is kept as a .wav in the
-- game's save folder and loaded from there next time (VERSION changes when a tune does).

local M = {}

local RATE = 22050
local VERSION = 2
local SEMITONE = 2 ^ (1 / 12)
local TAU = 2 * math.pi

-- note names to frequency, A4 = 440. "R" is a rest.
local STEPS = { C = -9, D = -7, E = -5, F = -4, G = -2, A = 0, B = 2 }
local function freq(name)
  local letter, sharp, octave = name:match("^([A-G])(#?)(%d)$")
  if not letter then return 0 end
  local n = STEPS[letter] + (sharp == "#" and 1 or 0) + (tonumber(octave) - 4) * 12
  return 440 * SEMITONE ^ n
end

-- chords: the notes, and the bass root
local CHORDS = {
  Dm = { "D", "F", "A", root = "D2" }, ["A#"] = { "A#", "D", "F", root = "A#1" },
  F = { "F", "A", "C", root = "F2" }, C = { "C", "E", "G", root = "C2" },
  Gm = { "G", "A#", "D", root = "G1" }, A = { "A", "C#", "E", root = "A1" },
}

local TUNES = {
  play = {
    bpm = 118, drums = true,
    chords = { "Dm", "A#", "F", "C", "Dm", "A#", "C", "A",
               "Gm", "A#", "Dm", "A", "Gm", "A#", "C", "A" },
    melody = [[
      D5:1 A4:.5 D5:.5 F5:1 E5:.5 D5:.5
      C5:1 A#4:.5 C5:.5 D5:1 F5:1
      A5:1 G5:.5 F5:.5 C5:1 F5:.5 G5:.5
      E5:1.5 D5:.5 C5:1 R:1
      D5:.5 F5:.5 A5:1 D6:1 C6:.5 A5:.5
      A#5:1 A5:.5 G5:.5 F5:1 D5:1
      E5:.5 F5:.5 G5:1 E5:.5 C5:.5 G4:1
      A4:1 C#5:1 E5:1 A5:1
      G5:1.5 A#5:.5 A5:1 G5:1
      F5:1.5 G5:.5 F5:1 D5:1
      A5:.5 G5:.5 F5:.5 E5:.5 D5:1 A4:1
      C#5:1 E5:1 A5:2
      A#5:.5 A5:.5 G5:1 D5:.5 G5:.5 A#5:1
      A5:.5 G5:.5 F5:1 A#4:.5 D5:.5 F5:1
      G5:1 E5:.5 C5:.5 E5:1 G5:1
      A5:1.5 G5:.5 E5:1 C#5:1
    ]],
  },
  title = {
    bpm = 88, drums = false,
    chords = { "Dm", "A#", "F", "C", "Dm", "A#", "Gm", "A" },
    melody = [[
      A5:3 F5:1
      D5:2 F5:2
      C6:2 A5:1 F5:1
      G5:4
      F5:1 A5:1 D6:2
      C6:1.5 A#5:.5 A5:2
      G5:2 A#5:1 D6:1
      C#6:2 E5:2
    ]],
  },
}

-- ------------------------------------------------------------------ oscillators
-- polyBLEP rounds off the jump in a saw or square so it does not alias into a buzz
local function blep(t, dt)
  if t < dt then t = t / dt; return t + t - t * t - 1
  elseif t > 1 - dt then t = (t - 1) / dt; return t * t + t + t + 1 end
  return 0
end
local function saw(p, dt) return 2 * p - 1 - blep(p, dt) end
local function sq(p, dt, duty)
  local v = (p < duty) and 1 or -1
  return v + blep(p, dt) - blep((p - duty) % 1, dt) - (2 * duty - 1)
end

local function buffer(n)
  local b = {}
  for i = 1, n do b[i] = 0 end
  return b
end

-- One synth note into a buffer, wrapping round the loop.
--   o.wave: "saw" / "square" / "tri" / "sine"; o.voices + o.detune (cents) for a wide
--   sound; o.cut / o.cutEnd: a low-pass filter sweeping from cut to cutEnd (Hz) over
--   o.sweep seconds; o.attack / o.release / o.decay shape the volume.
local function synth(buf, n, t, dur, f, o)
  if f <= 0 then return end
  local i0 = math.floor(t * RATE)
  local len = math.floor(dur * RATE)
  local att = math.max(1, math.floor((o.attack or 0.005) * RATE))
  local rel = math.max(1, math.floor((o.release or 0.05) * RATE))
  local voices, det = o.voices or 1, o.detune or 0
  local phases, steps = {}, {}
  for v = 1, voices do
    local c = voices == 1 and 0 or det * ((v - 1) / (voices - 1) * 2 - 1)
    phases[v] = (v * 0.37) % 1
    steps[v] = f * 2 ^ (c / 1200) / RATE
  end
  local cut, cutEnd, sweep = o.cut or 8000, o.cutEnd or o.cut or 8000, o.sweep or 0.2
  local y1, y2 = 0, 0                          -- two poles: a steeper, smoother filter
  local vol = o.vol / voices
  for k = 0, len + rel - 1 do
    local env = 1
    if k < att then env = k / att end
    if o.decay then env = env * math.exp(-o.decay * k / RATE) end
    if k >= len then env = env * (1 - (k - len) / rel) end
    local vib = 1
    if o.vibrato and k > RATE * 0.2 then vib = 1 + 0.004 * math.sin(k / RATE * TAU * 5.2) end
    local s = 0
    for v = 1, voices do
      local p, dt = phases[v], steps[v] * vib
      if o.wave == "saw" then s = s + saw(p, dt)
      elseif o.wave == "square" then s = s + sq(p, dt, o.duty or 0.5)
      elseif o.wave == "tri" then s = s + (4 * math.abs(p - 0.5) - 1)
      else s = s + math.sin(p * TAU) end
      p = p + dt
      if p >= 1 then p = p - 1 end
      phases[v] = p
    end
    local fc = cutEnd + (cut - cutEnd) * math.exp(-k / RATE / sweep)
    local a = 1 - math.exp(-TAU * fc / RATE)
    y1 = y1 + a * (s - y1)
    y2 = y2 + a * (y1 - y2)
    local i = (i0 + k) % n + 1
    buf[i] = buf[i] + y2 * env * vol
  end
end

-- drums. The noise is seeded, so every build is the same.
local rng = love.math.newRandomGenerator(2010)
local function drum(buf, n, t, kind, vol)
  local i0 = math.floor(t * RATE)
  local last, lp = 0, 0
  if kind == "kick" then
    local len, ph = math.floor(0.35 * RATE), 0
    for k = 0, len - 1 do
      local s = k / RATE
      ph = ph + (42 + 130 * math.exp(-s * 28)) / RATE
      local click = k < 60 and (1 - k / 60) * 0.4 or 0
      local i = (i0 + k) % n + 1
      buf[i] = buf[i] + (math.sin(ph * TAU) * math.exp(-s * 7) + click) * vol
    end
  elseif kind == "snare" then
    local len, ph = math.floor(0.3 * RATE), 0
    for k = 0, len - 1 do
      local s = k / RATE
      local r = rng:random() * 2 - 1
      local hp = r - last; last = r
      lp = lp + 0.5 * (hp - lp)                  -- a band of noise, not a hiss
      ph = ph + 200 / RATE
      local i = (i0 + k) % n + 1
      buf[i] = buf[i] + (lp * 0.9 * math.exp(-s * 11) +
                         math.sin(ph * TAU) * 0.5 * math.exp(-s * 35)) * vol
    end
  else                                           -- "hat" / "open"
    local len = math.floor((kind == "open" and 0.22 or 0.045) * RATE)
    local fade = kind == "open" and 13 or 75
    for k = 0, len - 1 do
      local r = rng:random() * 2 - 1
      local hp = r - last; last = r
      local i = (i0 + k) % n + 1
      buf[i] = buf[i] + hp * math.exp(-k / RATE * fade) * vol
    end
  end
end

-- ------------------------------------------------------------------ effects
-- an echo: taps behind, round the loop
local function echo(src, dst, n, gap, taps, fb)
  local g = 1
  for tap = 1, taps do
    g = g * fb
    local d = gap * tap
    for i = 1, n do
      local v = src[i]
      if v ~= 0 then
        local j = (i - 1 + d) % n + 1
        dst[j] = dst[j] + v * g
      end
    end
  end
end

-- a big room (Schroeder: four combs into two all-passes), run round the loop twice so
-- the end's tail rings into the start
local function reverb(src, n, size, damp)
  local combs = { 1557, 1617, 1491, 1422 }
  local out = buffer(n)
  for _, len in ipairs(combs) do
    len = math.floor(len * size)
    local line, pos, store = {}, 1, 0
    for i = 1, len do line[i] = 0 end
    for pass = 1, 2 do
      for i = 1, n do
        local y = line[pos]
        store = y * (1 - damp) + store * damp
        line[pos] = src[i] + store * 0.84
        pos = pos + 1; if pos > len then pos = 1 end
        if pass == 2 then out[i] = out[i] + y * 0.25 end
      end
    end
  end
  for _, len in ipairs({ 225, 556 }) do
    local line, pos = {}, 1
    for i = 1, len do line[i] = 0 end
    for pass = 1, 2 do
      for i = 1, n do
        local b = line[pos]
        local x = out[i]
        local y = b - 0.5 * x
        line[pos] = x + 0.5 * b
        pos = pos + 1; if pos > len then pos = 1 end
        if pass == 2 then out[i] = y end
      end
    end
  end
  return out
end

local function parseMelody(text)
  local out = {}
  for name, beats in text:gmatch("(%S+):([%d%.]+)") do out[#out + 1] = { name, tonumber(beats) } end
  return out
end

-- ------------------------------------------------------------------ one tune
local function build(spec)
  local beat = 60 / spec.bpm
  local bars = #spec.chords
  local n = math.floor(bars * 4 * beat * RATE)
  local ducked, dry, send, lead = buffer(n), buffer(n), buffer(n), buffer(n)
  local drums = spec.drums

  for bar = 0, bars - 1 do
    local ch = CHORDS[spec.chords[bar + 1]]
    local t0 = bar * 4 * beat
    -- pads: every chord note, three detuned saws each, softly filtered, swelling in
    for _, name in ipairs({ ch[1] .. "3", ch[2] .. "4", ch[3] .. "4", ch[1] .. "4" }) do
      synth(ducked, n, t0, 4 * beat, freq(name), {
        wave = "saw", voices = 3, detune = 14, vol = drums and 0.055 or 0.07,
        attack = drums and 0.25 or 0.9, release = drums and 0.3 or 1.2,
        cut = drums and 1500 or 1100,
      })
    end
    -- bass
    local root = freq(ch.root)
    if drums then
      -- the Tron roll: sixteenths, the octave on every other one, each a short pluck
      for s = 0, 15 do
        local f = (s % 2 == 1) and root * 2 or root
        synth(ducked, n, t0 + s * beat / 4, beat / 4 * 0.8, f, {
          wave = "saw", voices = 2, detune = 6, vol = 0.34,
          cut = 2200, cutEnd = 380, sweep = 0.05, release = 0.015,
        })
      end
    else
      synth(ducked, n, t0, 4 * beat, root, { wave = "tri", vol = 0.3, attack = 0.4, release = 0.8 })
    end
    -- the arpeggio: up through the chord across two octaves, glassy, into the echo
    local arp = { ch[1] .. "5", ch[2] .. "5", ch[3] .. "5", ch[1] .. "6", ch[3] .. "5", ch[2] .. "5" }
    local steps = drums and 16 or 8
    for s = 0, steps - 1 do
      local nm = arp[s % #arp + 1]
      if nm:match("^%a#?6$") and not drums then nm = nm:gsub("6$", "5") end
      synth(send, n, t0 + s * 4 * beat / steps, 4 * beat / steps * 0.7, freq(nm), {
        wave = "square", duty = 0.25, vol = drums and 0.05 or 0.06,
        decay = 14, cut = 3500, release = 0.02,
      })
    end
    -- drums: four on the floor, snare on two and four, sixteenth hats
    if drums then
      for b = 0, 3 do drum(dry, n, t0 + b * beat, "kick", 0.95) end
      local fill = bar % 8 == 7
      drum(send, n, t0 + beat, "snare", 0.5)
      if fill then
        for s = 0, 3 do drum(send, n, t0 + (3 + s / 4) * beat, "snare", 0.28 + s * 0.08) end
      else
        drum(send, n, t0 + 3 * beat, "snare", 0.5)
      end
      for s = 0, 15 do
        local kind = (s % 4 == 2) and "open" or "hat"
        drum(dry, n, t0 + s * beat / 4, kind, s % 4 == 2 and 0.09 or (s % 2 == 0 and 0.05 or 0.08))
      end
    end
  end

  -- the lead: two detuned saws an octave apart would be too much; one bright square and
  -- one soft saw together, with vibrato on the long notes
  local t = 0
  for _, m in ipairs(parseMelody(spec.melody)) do
    local dur = m[2] * beat
    local f = freq(m[1])
    if f > 0 then
      synth(lead, n, t, dur * 0.9, f, {
        wave = "saw", voices = 2, detune = 9, vol = drums and 0.2 or 0.16,
        cut = drums and 4200 or 2600, cutEnd = drums and 2400 or 1800, sweep = 0.3,
        attack = drums and 0.01 or 0.06, release = 0.12, vibrato = m[2] >= 1,
      })
      synth(lead, n, t, dur * 0.9, f * 2, {
        wave = "square", duty = 0.5, vol = drums and 0.045 or 0.03,
        cut = 3000, attack = 0.01, release = 0.1, vibrato = m[2] >= 1,
      })
    end
    t = t + dur
  end

  -- the pumping: pads and bass duck under every kick and swell back
  if drums then
    local per = math.floor(beat * RATE)
    for i = 1, n do
      local since = ((i - 1) % per) / RATE
      ducked[i] = ducked[i] * (1 - 0.7 * math.exp(-since * 9))
    end
  end

  -- echo on the lead and the arpeggio (a dotted eighth), then everything wet into the room
  local gap = math.floor(beat * 0.75 * RATE)
  echo(lead, send, n, gap, 3, drums and 0.32 or 0.4)
  local wet = buffer(n)
  for i = 1, n do wet[i] = send[i] + lead[i] * 0.6 + ducked[i] * 0.35 end
  local room = reverb(wet, n, drums and 1.0 or 1.3, 0.35)

  local mix = buffer(n)
  local roomAmt = drums and 0.55 or 0.9
  for i = 1, n do
    mix[i] = ducked[i] + dry[i] + send[i] + lead[i] + room[i] * roomAmt
  end
  -- level it: a gentle squash so the loud moments stay round, then the peak at 0.85
  local peak = 0
  for i = 1, n do
    local v = mix[i] * 1.4
    v = v / (1 + math.abs(v) * 0.35)
    mix[i] = v
    local a = math.abs(v); if a > peak then peak = a end
  end
  local gain = peak > 0 and 0.85 / peak or 1
  local sd = love.sound.newSoundData(n, RATE, 16, 1)
  for i = 0, n - 1 do sd:setSample(i, mix[i + 1] * gain) end
  return sd
end

-- ------------------------------------------------------------------ keeping a copy
local function u32(v)
  return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256,
                     math.floor(v / 16777216) % 256)
end
local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end

local function cached(name)
  local file = ("music_%s_v%d.wav"):format(name, VERSION)
  if love.filesystem.getInfo(file) then
    local ok, sd = pcall(love.sound.newSoundData, file)
    if ok and sd then return sd end
  end
  local sd = build(TUNES[name])
  local body = sd:getString()                  -- 16-bit mono, the same bytes a .wav holds
  pcall(love.filesystem.write, file,
        "RIFF" .. u32(36 + #body) .. "WAVEfmt " .. u32(16) .. u16(1) .. u16(1) ..
        u32(RATE) .. u32(RATE * 2) .. u16(2) .. u16(16) .. "data" .. u32(#body) .. body)
  return sd
end

local made, raw = {}, {}
local playing = nil

function M.load(name)
  if not made[name] then
    raw[name] = cached(name)
    made[name] = love.audio.newSource(raw[name], "static")
    made[name]:setLooping(true)
  end
  return made[name]
end

function M.data(name)            -- the samples themselves, for the self test
  M.load(name)
  return raw[name]
end

-- for listening away from the game: build without the saved copy
function M.build(name) return build(TUNES[name]) end

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
