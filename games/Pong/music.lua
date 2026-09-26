-- music.lua : the tunes, built by the game itself rather than loaded from files.
--
-- French house, the Daft Punk way: four-on-the-floor kick, claps on two and four, a swung
-- hi-hat and the open "tss" on every off-beat; a syncopated octave-bouncing bass with
-- ghost notes; disco seventh-chord stabs on the off-beats through a filter that opens and
-- closes across the loop; and a gliding, wah-wah "talk box" lead with a funky hook. The
-- whole mix pumps with the kick. The title tune is the same groove filtered down, the
-- way their records build.
--
-- Everything is one loop. The echo and the reverb run round the loop twice and keep the
-- second time, so the tail of the end is already sounding at the start: no seam.
--
-- Building takes a second or two on the Pi, so the finished tune is kept as a .wav in the
-- game's save folder and loaded from there next time (VERSION changes when a tune does).

local M = {}

local RATE = 22050
local VERSION = 3
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

-- seventh chords, voiced for the stabs, and the bass root
local CHORDS = {
  Am7 = { "A3", "C4", "E4", "G4", root = "A1" },
  D9 = { "F#3", "A3", "C4", "E4", root = "D2" },
  Fmaj7 = { "F3", "A3", "C4", "E4", root = "F1" },
  G = { "G3", "B3", "D4", "F#4", root = "G1" },
  Em7 = { "E3", "G3", "B3", "D4", root = "E2" },
  E7 = { "E3", "G#3", "B3", "D4", root = "E2" },
}

-- The bass, one bar of sixteenths: semitones above the root (false = silent), how hard,
-- and how many sixteenths it lasts. The octave jumps and ghost notes are the funk.
local BASS = {
  { 0, 1, 2 }, false, false, { 12, 0.7, 1 },
  false, { 0, 0.85, 1 }, { 0, 0.35, 1 }, false,
  { 7, 0.9, 2 }, false, { 10, 0.75, 1 }, false,
  { 12, 0.9, 1 }, false, { 0, 0.7, 1 }, { 7, 0.45, 1 },
}

local HOOK = [[
  R:.5 E5:.25 G5:.25 R:.25 A5:.5 G5:.25 E5:.5 R:.5 G5:.5 A5:.5
  F#5:.75 E5:.25 R:.5 D5:.5 E5:1 R:1
  R:.5 E5:.25 G5:.25 R:.25 A5:.5 G5:.25 C6:.5 R:.5 B5:.5 A5:.5
  F#5:.75 A5:.25 R:.5 F#5:.5 E5:1.5 R:.5
  C6:1 A5:.5 G5:.5 F5:.5 E5:.5 R:1
  D5:.5 E5:.5 F#5:.5 G5:.5 A5:1 B5:1
  C6:.75 B5:.25 A5:.5 E5:.5 G5:1 R:1
  G#5:1 B5:1 D6:.5 B5:.5 G#5:1
]]

local TUNES = {
  play = {
    bpm = 122, full = true,
    chords = { "Am7", "D9", "Am7", "D9", "Fmaj7", "G", "Am7", "E7",
               "Am7", "D9", "Am7", "D9", "Fmaj7", "G", "Em7", "E7" },
    melody = HOOK .. [[
      A5:.25 R:.25 A5:.25 G5:.25 R:.5 E5:.5 G5:.25 R:.25 A5:.5 R:1
      F#5:.25 R:.25 F#5:.25 E5:.25 R:.5 D5:.5 E5:1.5 R:.5
      A5:.25 R:.25 A5:.25 G5:.25 R:.5 E5:.5 G5:.25 R:.25 C6:.5 R:1
      B5:.5 A5:.5 F#5:.5 E5:.5 D5:1 R:1
      A5:1.5 G5:.5 F5:1 E5:1
      D5:.5 F#5:.5 A5:.5 B5:.5 D6:2
      B5:.75 A5:.25 G5:.5 E5:.5 D5:1 E5:1
      G#5:.5 B5:.5 D6:.5 E6:.5 D6:1 B5:1
    ]],
  },
  title = {
    bpm = 118, full = false,
    chords = { "Am7", "D9", "Am7", "D9", "Fmaj7", "G", "Am7", "E7" },
    melody = HOOK,
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


-- a handclap: three quick bursts of noise then a tail, the way a room of hands sounds
local function clap(buf, n, t, vol)
  local i0 = math.floor(t * RATE)
  local last, bp = 0, 0
  local len = math.floor(0.22 * RATE)
  for k = 0, len - 1 do
    local s = k / RATE
    local r = rng:random() * 2 - 1
    local hp = r - last; last = r
    bp = bp + 0.35 * (hp - bp)
    local env
    if s < 0.03 then env = math.exp(-((s % 0.01) * 300))     -- the three bursts
    else env = math.exp(-(s - 0.03) * 18) end
    local i = (i0 + k) % n + 1
    buf[i] = buf[i] + bp * env * vol
  end
end

-- The "talk box" lead: one voice that glides from note to note, with a wah on every note
-- (the filter jumps open and settles), two detuned saws and a square an octave down.
local function talkbox(buf, n, notes, beat, vol)
  local t = 0
  local f, phase = 0, { 0, 0.3, 0.6 }
  local y1, y2 = 0, 0
  for idx, m in ipairs(notes) do
    local dur = m[2] * beat
    local target = freq(m[1])
    local i0 = math.floor(t * RATE)
    local len = math.floor(dur * RATE)
    local nextRest = not notes[idx + 1] or notes[idx + 1][1] == "R"
    if target > 0 then
      if f == 0 then f = target end
      local rel = nextRest and math.floor(0.04 * RATE) or 0
      for k = 0, len - 1 do
        f = f + (target - f) * 0.004                      -- the glide
        local vib = 1 + (k > RATE * 0.18 and 0.005 * math.sin(k / RATE * TAU * 5.5) or 0)
        local s = 0
        for v = 1, 3 do
          local ff = f * vib * (v == 1 and 1.004 or (v == 2 and 0.996 or 0.5))
          local dt = ff / RATE
          local p = phase[v]
          s = s + (v == 3 and sq(p, dt, 0.5) * 0.5 or saw(p, dt))
          p = p + dt; if p >= 1 then p = p - 1 end
          phase[v] = p
        end
        local ks = k / RATE
        local fc = 650 + 2600 * (1 - math.exp(-ks / 0.025)) * math.exp(-ks / 0.22)
        local a = 1 - math.exp(-TAU * fc / RATE)
        y1 = y1 + a * (s - y1)
        y2 = y2 + a * (y1 - y2)
        local env = math.min(1, k / (0.006 * RATE))
        if rel > 0 and k > len - rel then env = env * (len - k) / rel end
        local i = (i0 + k) % n + 1
        buf[i] = buf[i] + y2 * env * vol
      end
    else
      f = 0
    end
    t = t + dur
  end
end

-- ------------------------------------------------------------------ one tune
local function build(spec)
  local beat = 60 / spec.bpm
  local six = beat / 4
  local bars = #spec.chords
  local n = math.floor(bars * 4 * beat * RATE)
  local pumped, bass, dry, lead, send = buffer(n), buffer(n), buffer(n), buffer(n), buffer(n)
  local full = spec.full
  local SWING = 0.2                                 -- the late second sixteenth: the shuffle

  local function at(bar, step)                       -- time of a sixteenth, swung
    local t = bar * 4 * beat + step * six
    if step % 2 == 1 then t = t + SWING * six end
    return t
  end

  for bar = 0, bars - 1 do
    local ch = CHORDS[spec.chords[bar + 1]]
    -- the filter over the stabs opens and closes across the loop (the filter-house sweep)
    local sweep = 0.5 - 0.5 * math.cos(TAU * bar / bars)
    local stabCut = full and (700 + 2800 * sweep) or (350 + 700 * sweep)

    -- disco stabs on the off-beats, and a push on the last sixteenth of every other bar
    local stabs = { { 2, 1 }, { 6, 0.8 }, { 10, 1 }, { 14, 0.8 } }
    if bar % 2 == 1 then stabs[#stabs + 1] = { 15, 0.6 } end
    for _, st in ipairs(stabs) do
      for _, nm in ipairs(ch) do
        synth(pumped, n, at(bar, st[1]), six * 1.4, freq(nm), {
          wave = "saw", voices = 3, detune = 12, vol = 0.07 * st[2],
          cut = stabCut * 1.6, cutEnd = stabCut, sweep = 0.06, release = 0.04,
        })
      end
    end

    -- the bass
    local root = freq(ch.root)
    for step = 0, 15 do
      local b = BASS[step + 1]
      if b then
        local f = root * SEMITONE ^ b[1]
        synth(bass, n, at(bar, step), six * b[3] * 0.85, f, {
          wave = "saw", voices = 2, detune = 5, vol = 0.36 * b[2],
          cut = full and 1900 or 900, cutEnd = 300, sweep = 0.07, release = 0.02 })
        synth(bass, n, at(bar, step), six * b[3] * 0.85, f,            -- a clean sub under it
              { wave = "sine", vol = 0.22 * b[2], release = 0.02 })
      end
    end

    -- drums
    for b = 0, 3 do drum(dry, n, bar * 4 * beat + b * beat, "kick", full and 1 or 0.7) end
    if full then
      clap(send, n, at(bar, 4), 0.55)
      clap(send, n, at(bar, 12), 0.55)
      if bar % 4 == 3 then clap(send, n, at(bar, 15), 0.3) end        -- a flam into the next
    end
    for step = 0, 15 do
      if step % 4 == 2 then
        drum(dry, n, at(bar, step), "open", full and 0.12 or 0.07)    -- the "tss"
      elseif full then
        drum(dry, n, at(bar, step), "hat", step % 2 == 1 and 0.07 or 0.045)
      end
    end
  end

  -- the lead
  talkbox(lead, n, parseMelody(spec.melody), beat, full and 0.2 or 0.09)

  -- everything but the kick and hats pumps with the kick
  local per = math.floor(beat * RATE)
  for i = 1, n do
    local since = ((i - 1) % per) / RATE
    pumped[i] = pumped[i] * (1 - 0.55 * math.exp(-since * 10))
    bass[i] = bass[i] * (1 - 0.3 * math.exp(-since * 14))
    lead[i] = lead[i] * (1 - 0.25 * math.exp(-since * 10))
  end

  -- a short echo on the lead, a little room on everything that is not the low end
  echo(lead, send, n, math.floor(beat * 0.75 * RATE), 2, 0.22)
  local wet = buffer(n)
  for i = 1, n do wet[i] = send[i] + lead[i] * 0.35 + pumped[i] * 0.3 end
  local room = reverb(wet, n, 0.8, 0.45)

  local mix = buffer(n)
  for i = 1, n do
    mix[i] = pumped[i] + bass[i] + dry[i] + send[i] + lead[i] + room[i] * 0.3
  end
  -- level it: a gentle squash so the loud moments stay round, then the peak at 0.85
  local peak = 0
  for i = 1, n do
    local v = mix[i] * 1.3
    v = v / (1 + math.abs(v) * 0.3)
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
local playing, playingName = nil, nil

-- ------------------------------------------------------------------ your own music
-- Any .mp3 / .ogg / .wav dropped into roms/music/pong on the cabinet (\\cabinet\games\
-- music\pong from a PC) plays instead of the tunes built here: a name with "title" in it
-- on the title screen, anything else during games (one picked at random each game).
-- LOVE's own filesystem cannot see outside the game, so a file is read as bytes.
local FOLDER = (os.getenv("HOME") or ".") .. "/roms/music/pong"
local found, streams = nil, {}

local function ownFiles()
  if found then return found end
  found = { title = {}, play = {} }
  local pipe = io.popen("find '" .. FOLDER .. "' -maxdepth 1 -type f 2>/dev/null")
  if pipe then
    for path in pipe:lines() do
      local lower = path:lower()
      if lower:match("%.mp3$") or lower:match("%.ogg$") or lower:match("%.wav$") then
        local name = lower:match("[^/]+$")
        local list = name:find("title") and found.title or found.play
        list[#list + 1] = path
      end
    end
    pipe:close()
  end
  table.sort(found.title); table.sort(found.play)
  return found
end

local function streamFor(path)
  if streams[path] == nil then
    streams[path] = false
    local f = io.open(path, "rb")
    if f then
      local bytes = f:read("*a")
      f:close()
      local ok, src = pcall(function()
        return love.audio.newSource(love.filesystem.newFileData(bytes, path:match("[^/]+$")), "stream")
      end)
      if ok and src then
        src:setLooping(true)
        streams[path] = src
      end
    end
  end
  return streams[path] or nil
end

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
  if playingName == name and playing and playing:isPlaying() then return end
  M.stop()
  local list = ownFiles()[name]
  local s
  if list and #list > 0 then
    local path = list[love.math.random(#list)]
    s = streamFor(path)
    print(s and ("pong music: " .. path) or ("pong music: could not play " .. path))
    io.stdout:flush()
  end
  s = s or M.load(name)                         -- no file of your own: the built-in tune
  s:setVolume(volume or 0.5)
  s:seek(0)
  s:play()
  playing, playingName = s, name
end

function M.stop()
  if playing then playing:stop() end
  playing, playingName = nil, nil
end

function M.duck(v)              -- quieten under a win jingle, say
  if playing then playing:setVolume(v) end
end

return M
