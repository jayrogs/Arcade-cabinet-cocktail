-- music.lua : music slots matching the NES flow. Each slot has a built-in chiptune and can
-- be replaced by dropping a file into music/ (ogg, mp3 or wav). Exact names win
-- (fever.mp3), otherwise the filename is matched on key words, so a file called
-- "Dr. Mario Music (NES) - Fever.mp3" lands in the fever slot by itself.
--
--   title       title screen and high score page                       (loops)
--   select      mode select screen                                     (loops)
--   fever       in-game music, "FEVER" choice, also the attract demo   (loops)
--   chill       in-game music, "CHILL" choice                          (loops)
--   feverclear  stage clear jingle when playing with Fever
--   chillclear  stage clear jingle when playing with Chill
--   gameover    bottle overflowed
--   victory     versus round won
local M = {}
local RATE = 22050

--   matchwin    a human wins a versus round (plays once, the winner presses Start)
--   victory     spare short jingle, unused unless you route a file to it
local SLOTS = { "title", "select", "fever", "chill", "feverclear", "chillclear", "gameover", "matchwin", "victory" }
local LOOPS = { title = true, select = true, fever = true, chill = true }

-- filename must contain every word in `all` and none of the words in `none`
local HINTS = {
  title = { { all = { "title" } } },
  select = { { all = { "select" } }, { all = { "mode" } }, { all = { "menu" } } },
  fever = { { all = { "fever" }, none = { "clear" } } },
  chill = { { all = { "chill" }, none = { "clear" } } },
  feverclear = { { all = { "fever", "clear" } } },
  chillclear = { { all = { "chill", "clear" } } },
  gameover = { { all = { "game over" } }, { all = { "gameover" } }, { all = { "game_over" } } },
  matchwin = { { all = { "vs" } }, { all = { "versus" } }, { all = { "match" } } },
  victory = { { all = { "victory" }, none = { "vs", "versus", "match" } }, { all = { "round" } } },
}

local NAMES = { C = 0, ["C#"] = 1, D = 2, ["D#"] = 3, E = 4, F = 5, ["F#"] = 6, G = 7, ["G#"] = 8, A = 9, ["A#"] = 10, B = 11 }
local function freq(note)
  local name, oct = note:match("^([A-G]#?)(%d)$")
  local midi = (tonumber(oct) + 1) * 12 + NAMES[name]
  return 440 * 2 ^ ((midi - 69) / 12)
end

-- Built-in tunes. Lead in eighth notes, bass in quarters. "-" holds, "." rests.
local TUNES = {
  title = {
    bpm = 96, leadVol = 0.13, bassVol = 0.10, hat = false,
    lead = {
      "E4", "-", "A4", "-", "C5", "-", "B4", "-", "A4", "-", "E4", "-", "G4", "-", "-", ".",
      "D4", "-", "F4", "-", "A4", "-", "G4", "-", "E4", "-", "-", "-", "-", "-", "-", ".",
      "C4", "-", "E4", "-", "G4", "-", "A4", "-", "G4", "-", "E4", "-", "D4", "-", "-", ".",
      "F4", "-", "A4", "-", "C5", "-", "B4", "-", "A4", "-", "-", "-", "-", "-", "-", ".",
    },
    bass = {
      "A2", "A2", "E2", "E2", "C3", "C3", "G2", "G2", "D2", "D2", "F2", "F2", "E2", "E2", "E2", "E2",
      "C3", "C3", "G2", "G2", "A2", "A2", "D2", "D2", "F2", "F2", "G2", "G2", "A2", "A2", "A2", "A2",
    },
  },
  select = {
    bpm = 120, leadVol = 0.14, bassVol = 0.11, hat = true,
    lead = {
      "C5", "-", "G4", "-", "E4", "-", "G4", "-", "C5", "-", "E5", "-", "D5", "-", "-", ".",
      "B4", "-", "G4", "-", "D4", "-", "G4", "-", "B4", "-", "D5", "-", "C5", "-", "-", ".",
    },
    bass = { "C3", "C3", "G2", "G2", "C3", "C3", "E2", "E2", "G2", "G2", "D2", "D2", "G2", "G2", "C3", "C3" },
  },
  fever = {
    bpm = 140, leadVol = 0.16, bassVol = 0.12, hat = true,
    lead = {
      "A4", "C5", "E5", "C5", "A4", "B4", "C5", "B4", "A4", "G4", "E4", "G4", "A4", "-", "C5", ".",
      "D5", "C5", "B4", "C5", "D5", "E5", "F5", "E5", "D5", "B4", "G4", "B4", "D5", "-", "-", ".",
      "E5", "D5", "C5", "D5", "E5", "G5", "E5", "D5", "C5", "B4", "A4", "B4", "C5", "-", "E5", ".",
      "F5", "E5", "D5", "E5", "F5", "E5", "D5", "C5", "B4", "C5", "B4", "G4", "A4", "-", "-", ".",
    },
    bass = {
      "A2", "A2", "E2", "E2", "A2", "A2", "G2", "G2", "F2", "F2", "C3", "C3", "G2", "G2", "G2", "G2",
      "C3", "C3", "G2", "G2", "A2", "A2", "E2", "E2", "F2", "F2", "D3", "D3", "E2", "E2", "E2", "E2",
    },
  },
  chill = {
    bpm = 100, leadVol = 0.13, bassVol = 0.11, hat = false,
    lead = {
      "E5", "-", "-", "D5", "C5", "-", "D5", "-", "E5", "-", "-", "-", "-", "-", "-", ".",
      "D5", "-", "-", "C5", "B4", "-", "C5", "-", "D5", "-", "-", "-", "-", "-", "-", ".",
      "C5", "-", "-", "B4", "A4", "-", "B4", "-", "C5", "-", "D5", "-", "E5", "-", "-", ".",
      "B4", "-", "C5", "-", "D5", "-", "B4", "-", "A4", "-", "-", "-", "-", "-", "-", ".",
    },
    bass = {
      "A2", "A2", "E2", "E2", "A2", "A2", "E2", "E2", "G2", "G2", "D2", "D2", "G2", "G2", "D2", "D2",
      "F2", "F2", "C3", "C3", "F2", "F2", "C3", "C3", "E2", "E2", "E2", "E2", "A2", "A2", "A2", "A2",
    },
  },
  feverclear = {
    bpm = 160, leadVol = 0.16, bassVol = 0.12, hat = false,
    lead = { "C5", "E5", "G5", "C6", "-", "G5", "C6", "-", "-", "-", "-", "-", ".", ".", ".", "." },
    bass = { "C3", "C3", "G2", "C3", "C3", "C3", ".", "." },
  },
  chillclear = {
    bpm = 120, leadVol = 0.14, bassVol = 0.11, hat = false,
    lead = { "E5", "-", "C5", "-", "G5", "-", "-", "-", "E5", "-", "-", "-", ".", ".", ".", "." },
    bass = { "C3", "C3", "C3", "C3", "C3", "C3", ".", "." },
  },
  gameover = {
    bpm = 90, leadVol = 0.15, bassVol = 0.11, hat = false,
    lead = { "E4", "-", "D4", "-", "C4", "-", "B3", "-", "A3", "-", "-", "-", "-", "-", ".", "." },
    bass = { "A2", "A2", "E2", "A2", "A2", "A2", ".", "." },
  },
  victory = {
    bpm = 150, leadVol = 0.16, bassVol = 0.12, hat = false,
    lead = { "G4", "C5", "E5", "G5", "-", "E5", "G5", "-", "-", "-", "-", "-", ".", ".", ".", "." },
    bass = { "C3", "C3", "G2", "C3", "C3", "C3", ".", "." },
  },
  matchwin = {
    bpm = 150, leadVol = 0.16, bassVol = 0.12, hat = true,
    lead = {
      "C5", "E5", "G5", "C6", "-", "G5", "C6", "-", "A5", "-", "G5", "-", "E5", "-", "-", ".",
      "F5", "A5", "C6", "F6", "-", "C6", "F6", "-", "G5", "-", "-", "-", "C6", "-", "-", ".",
    },
    bass = { "C3", "C3", "G2", "G2", "A2", "A2", "E2", "E2", "F2", "F2", "C3", "C3", "G2", "G2", "C3", "C3" },
  },
}

local function expand(notes)
  local seq, cur, age = {}, nil, 0
  for _, nt in ipairs(notes) do
    if nt == "." then cur = nil
    elseif nt ~= "-" then cur = freq(nt) age = 0 end
    seq[#seq + 1] = { f = cur, start = age }
    age = age + 1
  end
  return seq
end

local function render(tune)
  local sixteenth = 60 / tune.bpm / 4
  local leadLen, bassLen = 2 * sixteenth, 4 * sixteenth
  local leadSeq, bassSeq = expand(tune.lead), expand(tune.bass)
  local n = math.floor(#tune.lead * leadLen * RATE)
  local sd = love.sound.newSoundData(n, RATE, 16, 1)
  local rng = love.math.newRandomGenerator(1)
  local leadPhase, bassPhase = 0, 0
  for i = 0, n - 1 do
    local t = i / RATE
    local s = 0
    local ln = leadSeq[math.floor(t / leadLen) % #leadSeq + 1]
    if ln.f then
      local inNote = (t % leadLen) + ln.start * leadLen
      local env = math.max(0, 1 - inNote * (tune.hat and 2.2 or 0.9))
      leadPhase = leadPhase + ln.f / RATE
      s = s + ((leadPhase % 1) < 0.5 and 1 or -1) * tune.leadVol * env
    end
    local bn = bassSeq[math.floor(t / bassLen) % #bassSeq + 1]
    if bn.f then
      local env = math.max(0, 1 - (t % bassLen) * 1.4)
      bassPhase = bassPhase + bn.f / RATE
      s = s + ((bassPhase % 1) < 0.25 and 1 or -1) * tune.bassVol * env
    end
    if tune.hat then
      local eighth = t % leadLen
      if math.floor(t / leadLen) % 2 == 1 and eighth < 0.03 then
        s = s + (rng:random() * 2 - 1) * 0.08 * (1 - eighth / 0.03)
      end
    end
    sd:setSample(i, math.max(-1, math.min(1, s)))
  end
  return love.audio.newSource(sd)
end

local AUDIO_EXT = { ogg = true, mp3 = true, wav = true }

local function matches(file, rule)
  local f = file:lower():gsub("%.%w+$", "")
  for _, w in ipairs(rule.all) do if not f:find(w, 1, true) then return false end end
  for _, w in ipairs(rule.none or {}) do if f:find(w, 1, true) then return false end end
  return true
end

local function externalTrack(slot, candidates, used)
  local function pick(f)
    local ok, src = pcall(love.audio.newSource, "music/" .. f, "stream")
    if ok then used[f] = true return src, f end
    return nil
  end
  for _, f in ipairs(candidates) do
    if not used[f] and f:lower():match("^" .. slot .. "%.") then return pick(f) end
  end
  for _, rule in ipairs(HINTS[slot] or {}) do
    for _, f in ipairs(candidates) do
      if not used[f] and matches(f, rule) then return pick(f) end
    end
  end
  return nil
end

function M.load()
  M.tracks, M.info = {}, {}
  local candidates, used = {}, {}
  if love.filesystem.getInfo("music", "directory") then
    for _, f in ipairs(love.filesystem.getDirectoryItems("music")) do
      local ext = f:lower():match("%.(%w+)$")
      if ext and AUDIO_EXT[ext] then candidates[#candidates + 1] = f end
    end
    table.sort(candidates)
  end
  for _, slot in ipairs(SLOTS) do
    local src, file = externalTrack(slot, candidates, used)
    if src then
      src:setVolume(0.8)
      M.info[slot] = file
    else
      src = render(TUNES[slot])
      src:setVolume(0.6)
      M.info[slot] = "built-in"
    end
    src:setLooping(LOOPS[slot] or false)
    M.tracks[slot] = src
  end
  M.current = nil
end

-- Switches to a slot. Re-requesting the looping slot already playing is a no-op;
-- jingles always restart.
function M.play(slot)
  if not M.tracks then return end
  if M.current == slot and LOOPS[slot] and M.tracks[slot]:isPlaying() then return end
  M.stop()
  local src = M.tracks[slot]
  if src then
    src:play()
    M.current = slot
  end
end

function M.stop()
  if M.tracks and M.current then M.tracks[M.current]:stop() end
  M.current = nil
end

return M
