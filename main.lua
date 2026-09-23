-- Arcade cabinet menu. Starts with the cab, shows what is on the machine as a shelf of
-- boxes, and hands the chosen game to the wrapper script to run. Drawn at 256x320 and
-- scaled whole, so it matches Dr Mario Cocktail Edition and stays sharp on the cocktail
-- table's sideways monitor.
local SYSTEMS = require("systems")

local W, H = 256, 320
local CELL = 8
local HOME = os.getenv("HOME") or "."
local ROOT = HOME .. "/roms"
local LAUNCH_FILE = "/tmp/cab_launch"
local SECOND_FILE = "/tmp/cab_launch2"   -- the other arcade emulator, tried if the first fails
local MESSAGE_FILE = "/tmp/cab_message"  -- what the wrapper wants to tell us
local CORE_DIR = HOME .. "/.config/retroarch/cores"

local PAD_X, PAD_Y, NUDGE_X, NUDGE_Y = 0, 0, 0, 0

-- The picture can sit off centre on a monitor fed through a VGA adapter. The lining-up
-- screen writes what it found into ~/screen.conf.
local function readScreenConf()
  local home = os.getenv("HOME")
  if not home then return end
  local f = io.open(home .. "/screen.conf", "r")
  if not f then return end
  for line in f:lines() do
    local k, v = line:match("^(%w+)%s*=%s*(-?%d+)")
    if k == "nudgeX" then NUDGE_X = tonumber(v) end
    if k == "nudgeY" then NUDGE_Y = tonumber(v) end
    if k == "padX" then PAD_X = tonumber(v) end
    if k == "padY" then PAD_Y = tonumber(v) end
    if k == "overscan" then PAD_X, PAD_Y = tonumber(v), tonumber(v) end
  end
  f:close()
end

local GLYPH_ORDER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,-:<>!?/'#@"

local PAL = {
  bg1 = { 57 / 255, 0, 165 / 255 },
  bg2 = { 0, 0, 0 },
  panel = { 165 / 255, 231 / 255, 1.0 },
  edge = { 0, 239 / 255, 222 / 255 },
  white = { 1, 1, 1 },
  black = { 0, 0, 0 },
  pink = { 248 / 255, 48 / 255, 88 / 255 },
  orange = { 248 / 255, 160 / 255, 48 / 255 },
  yellow = { 189 / 255, 189 / 255, 0 },
  grey = { 0.55, 0.55, 0.62 },
}

local g = love.graphics
local font, screen, bg
local state = "systems"       -- "systems" | "games" | "launching"
local menu, cursor, title, sub
local catalogue = {}
local groupOf                 -- which system and folder the game list came from
local t, scroll = 0, 1
-- left alone, the cabinet starts showing off: a picture of a game at a time, big,
-- until somebody touches it
local ATTRACT_AFTER = 45      -- seconds of nobody touching it
-- while somebody watches from a phone, the demo films are left alone: decoding them
-- costs about half of one of this Pi's cores, and the picture being sent needs it more
local WATCH_FLAG = "/tmp/cab_watching"
local function someoneWatching()
  local f = io.open(WATCH_FLAG, "r")
  if not f then return false end
  f:close()
  return true
end
local HOLD = 6                -- seconds a still picture stays up
local CLIP_HOLD = 19.2         -- seconds a filmed clip stays up (each clip is 20)
local FADE_TIME = 0.6          -- the fade in and out between clips
local idle, attract, shown, shownAt, fade = 0, false, nil, 0, 0
-- the letter picker: a grid of first letters over a long shelf
local picker, pickerAt, pickerLetters = false, 1, {}
local message, messageTimer
local art = {}                -- cache: key -> image or false
local titles = {}             -- short file name -> the game's real title
local favourites = {}         -- the ones starred, by system and file name
local recent = {}             -- what was played last, newest first
local totest = {}             -- games to try at the real table (arcade/totest.txt)
local together = {}           -- the ones two people can play at once
local cocktail = {}           -- the ones that turn round for the far seat
local useMame = {}            -- the ones that must start in MAME, not FinalBurn Neo
local useMame2010 = {}        -- the ones only MAME 2010 runs and turns round properly
local useMameCur = {}         -- the ones that need the current MAME (newer file versions)
local tunes, tune, tuneIndex  -- the music, and which one is playing
local blip, thunk             -- the noises the shelf makes
local shotMode, shotFrames

-------------------------------------------------------------------------------
-- reading the disk
-------------------------------------------------------------------------------
local function shellQuote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local function fileExists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

-- files the emulator needs but nobody plays
local BIOS = {
  neogeo = true, pgm = true, skns = true, decocass = true, cvs = true, isgsm = true,
  nmk004 = true, midssio = true, bubsys = true, neocdz = true, ym2608 = true,
  coleco = true, msx = true, spectrum = true, channelf = true, fdsbios = true,
  naomi = true, naomi2 = true, awbios = true,
}

local function listFiles(dir, extList, shortName)
  local want = {}
  for e in extList:gmatch("%S+") do want[e] = true end
  local out = {}
  local pipe = io.popen("find " .. shellQuote(dir) .. " -maxdepth 2 -type f 2>/dev/null")
  if not pipe then return out end
  for line in pipe:lines() do
    local ext = line:match("%.([%w]+)$")
    local folder = line:match("/([^/]+)/[^/]+$")
    -- media/ and boxart/ hold the pictures, samples are sound for the emulator
    -- mamesets holds copies under the names MAME knows them by; they are not extra games
    local skipFolder = folder == "media" or folder == "boxart" or folder == "samples"
                       or folder == "mamesets" or folder == "mamesets2010"
    if ext and want[ext:lower()] and not skipFolder then
      local base = line:match("([^/\\]+)$") or line
      local stem = base:gsub("%.[%w]+$", "")
      if not BIOS[stem:lower()] then
        local group = (folder and folder ~= dir:match("([^/]+)$")) and folder or nil
        local key = (dir:match("([^/]+)$") or "") .. "/" .. stem
        out[#out + 1] = {
          label = titles[key] or stem:gsub("[_%.]", " "):upper(), path = line, stem = stem,
          dir = dir, group = group, short = shortName,
        }
      end
    end
  end
  pipe:close()
  table.sort(out, function(a, b) return a.label < b.label end)
  return out
end

-------------------------------------------------------------------------------
-- what the cabinet remembers between switch-ons
-------------------------------------------------------------------------------
local STATE = HOME .. "/cab_state.txt"

local function gameCount(n)
  return (n == 1) and "1 GAME" or ("%d GAMES"):format(n)
end

local function gameKey(game)
  return (game.dir:match("([^/]+)$") or "") .. "/" .. game.stem
end

local function readState()
  favourites, recent = {}, {}
  local f = io.open(STATE, "r")
  if not f then return end
  for line in f:lines() do
    local kind, key = line:match("^(%a+)\t(.+)$")
    if kind == "star" then favourites[key] = true
    elseif kind == "played" then recent[#recent + 1] = key end
  end
  f:close()
end

local function writeState()
  local f = io.open(STATE, "w")
  if not f then return end
  for key in pairs(favourites) do f:write("star\t" .. key .. "\n") end
  for i, key in ipairs(recent) do
    if i <= 20 then f:write("played\t" .. key .. "\n") end
  end
  f:close()
end

local function notePlayed(game)
  if not game then return end
  local key = gameKey(game)
  for i, k in ipairs(recent) do
    if k == key then table.remove(recent, i) break end
  end
  table.insert(recent, 1, key)
  while #recent > 20 do table.remove(recent) end
  writeState()
end

-------------------------------------------------------------------------------
-- sound
-------------------------------------------------------------------------------
-- Music comes from roms/music, which is the same share the games live on, so a tune
-- can be dropped in from any PC. LOVE's own filesystem cannot see outside the game,
-- so the file is read as bytes and handed to the sound system.
local function loadTune(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local ok, src = pcall(function()
    local ext = path:match("%.([%w]+)$") or "mp3"
    return love.audio.newSource(love.filesystem.newFileData(data, "tune." .. ext), "stream")
  end)
  return ok and src or nil
end

local function findTunes()
  tunes = {}
  local pipe = io.popen("find " .. shellQuote(HOME .. "/roms/music") ..
                        " -maxdepth 1 -type f 2>/dev/null")
  if pipe then
    for line in pipe:lines() do
      if line:match("%.[Mm][Pp]3$") or line:match("%.[Oo][Gg][Gg]$") or line:match("%.[Ww][Aa][Vv]$") then
        tunes[#tunes + 1] = line
      end
    end
    pipe:close()
  end
  table.sort(tunes)
end

local function playNextTune()
  if not tunes or #tunes == 0 then return end
  if tune then tune:stop() end
  tuneIndex = (tuneIndex or 0) % #tunes + 1
  tune = loadTune(tunes[tuneIndex])
  if tune then
    tune:setVolume(0.55)
    tune:play()
  end
end

-- two short noises, made here rather than carried as files: a soft blip for moving
-- along the shelf and a fatter thunk for choosing
local function makeNoise(freq, seconds, kind)
  local rate = 44100
  local n = math.floor(rate * seconds)
  local data = love.sound.newSoundData(n, rate, 16, 1)
  for i = 0, n - 1 do
    local t = i / rate
    local fade = 1 - (i / n)
    local v
    if kind == "square" then
      v = (math.sin(t * freq * 2 * math.pi) > 0) and 0.22 or -0.22
    else
      v = math.sin(t * freq * 2 * math.pi) * 0.3
    end
    data:setSample(i, v * fade * fade)
  end
  return love.audio.newSource(data, "static")
end

local function sound(src)
  if src then src:stop() src:play() end
end

-- names.txt, written by names.py on the Pi: the short file name and the real title,
-- one pair per line. Without it the file name is used, which reads like MSPACMAN.
-- together.txt, written by twoplayer.py: one short file name per line, the games two
-- people can play at the same time rather than taking turns
local function readList(file, into)
  for _, s in ipairs(SYSTEMS) do
    local f = io.open(ROOT .. "/" .. s.dir .. "/" .. file, "r")
    if f then
      for line in f:lines() do
        local stem = line:match("^%s*(%S+)%s*$")
        if stem then into[s.dir .. "/" .. stem] = true end
      end
      f:close()
    end
  end
end

local function readTogether()
  together, cocktail = {}, {}
  readList("together.txt", together)
  -- cocktail2p.txt: the ones with a table switch AND room for two
  readList("cocktail2p.txt", cocktail)
  -- totest.txt: games nobody is sure about yet, to be tried at the real table
  totest = {}
  readList("totest.txt", totest)
  -- use_mame.txt: table games that FinalBurn Neo will not turn round for player 2 --
  -- it keeps them upright on purpose -- but MAME does. Pac-Man is the one that matters.
  -- a line is "game" or "game mamename": the second when MAME knows these very chips
  -- under another name, and has a copy by that name in arcade/mamesets
  -- use_mame2010.txt works the same way, with its renamed copies in arcade/mamesets2010
  local function readNamed(file)
    local into = {}
    for _, sys in ipairs(SYSTEMS) do
      local f = io.open(ROOT .. "/" .. sys.dir .. "/" .. file, "r")
      if f then
        for line in f:lines() do
          local stem, other = line:match("^%s*(%S+)%s*(%S*)%s*$")
          if stem then into[sys.dir .. "/" .. stem] = (other ~= "" and other) or true end
        end
        f:close()
      end
    end
    return into
  end
  useMame2010 = readNamed("use_mame2010.txt")
  useMameCur = readNamed("use_mamecur.txt")
  useMame = readNamed("use_mame.txt")
end

local function readTitles()
  titles = {}
  for _, s in ipairs(SYSTEMS) do
    local f = io.open(ROOT .. "/" .. s.dir .. "/names.txt", "r")
    if f then
      for line in f:lines() do
        local short, pretty = line:match("^(%S+)	(.+)$")
        if short and pretty then titles[s.dir .. "/" .. short] = pretty end
      end
      f:close()
    end
  end
end

-- The demo's films: each game's own demo, filmed overnight and cut to its liveliest
-- twenty seconds. They live in roms/demos, with a list of each one's shape. The shelf
-- can only open a video from inside its own folder, so that folder is linked in there.
local clips = {}
local clipBag = {}
local function readClips()
  clips = {}
  local f = io.open(ROOT .. "/demos/clips.txt", "r")
  if not f then return end
  for line in f:lines() do
    local stem, shape = line:match("^(%S+)\t([%d%.]+)")
    if stem then clips[stem] = tonumber(shape) end
  end
  f:close()
  love.filesystem.setSymlinksEnabled(true)
  local save = love.filesystem.getSaveDirectory()
  os.execute("mkdir -p " .. shellQuote(save) .. " && ln -sfn " ..
             shellQuote(ROOT .. "/demos") .. " " .. shellQuote(save .. "/demos"))
  clipBag = {}
end

local function scan()
  readTitles()
  readClips()
  readTogether()
  catalogue = {}
  for _, s in ipairs(SYSTEMS) do
    catalogue[s.dir] = listFiles(ROOT .. "/" .. s.dir, s.ext, s.short)
    -- hide.txt: files that are not games (a system's own start-up file) or that start
    -- in neither emulator, so picking them would only show an error
    local hide = {}
    readList("hide.txt", hide)
    local kept = {}
    for _, game in ipairs(catalogue[s.dir]) do
      if not hide[gameKey(game)] then kept[#kept + 1] = game end
    end
    catalogue[s.dir] = kept
  end
end

-- The shelf's own boxes -- Dr Mario, two player, each machine, the setting-up ones --
-- have covers drawn for them, in menuart/. Games get their real box art instead.
local pics = {}
local function loadPic(name)
  if pics[name] ~= nil then return pics[name] or nil end
  pics[name] = false
  local f = io.open(HOME .. "/menuart/" .. name .. ".png", "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local ok, img = pcall(function()
    local fd = love.filesystem.newFileData(data, name .. ".png")
    return g.newImage(love.image.newImageData(fd))
  end)
  if ok and img then
    img:setFilter("nearest", "nearest")     -- square pixels, not a smeared photo
    pics[name] = img
    return img
  end
  return nil
end

-- a picture for a game: roms/<system>/media/<same name>.png (or .jpg, or boxart/)
local function loadArt(game)
  local key = game.dir .. "/" .. game.stem
  if art[key] ~= nil then return art[key] or nil end
  art[key] = false
  -- the picture sits in a media folder beside the game itself, whatever depth that is
  local base = game.path:match("^(.*)/[^/]+$") or ROOT
  for _, folder in ipairs({ "media", "boxart" }) do
    for _, ext in ipairs({ "png", "jpg", "jpeg" }) do
      local path = ("%s/%s/%s.%s"):format(base, folder, game.stem, ext)
      local f = io.open(path, "rb")
      if f then
        local data = f:read("*a")
        f:close()
        local ok, img = pcall(function()
          local fd = love.filesystem.newFileData(data, game.stem .. "." .. ext)
          return g.newImage(love.image.newImageData(fd))
        end)
        if ok and img then
          img:setFilter("linear", "linear")
          art[key] = img
          return img
        end
      end
    end
  end
  return nil
end

-------------------------------------------------------------------------------
-- menus
-------------------------------------------------------------------------------
-- every game on the machine, from every system, as one lookup
local function allGames()
  local byKey = {}
  for _, sys in ipairs(SYSTEMS) do
    for _, game in ipairs(catalogue[sys.dir] or {}) do
      byKey[gameKey(game)] = { game = game, sys = sys }
    end
  end
  return byKey
end

local function countPicked()
  local byKey, stars, plays = allGames(), 0, 0
  for key in pairs(favourites) do if byKey[key] then stars = stars + 1 end end
  for _, key in ipairs(recent) do if byKey[key] then plays = plays + 1 end end
  return stars, plays
end

local function buildSystems()
  menu, cursor, title, sub = {}, 1, "ARCADE CABINET", nil
  -- THE MACHINES COME FIRST, and the arcade is the first of them: it is the main thing
  -- this cabinet is for, so it is what the shelf opens on.
  for _, s in ipairs(SYSTEMS) do
    local games = catalogue[s.dir] or {}
    if #games > 0 then
      menu[#menu + 1] = {
        label = s.name, short = s.short, tag = gameCount(#games),
        color = s.color, sys = s, pic = s.dir,
      }
    end
  end
  local drc = HOME .. "/drcocktail.love"
  if fileExists(drc) then
    menu[#menu + 1] = {
      label = "DR. MARIO COCKTAIL EDITION", short = "DR MARIO", tag = "2 PLAYER",
      color = { 0.10, 0.34, 0.68 }, run = "love " .. shellQuote(drc), pic = "drmario",
    }
  end
  local pong = HOME .. "/pong.love"
  if fileExists(pong) then
    menu[#menu + 1] = {
      label = "PONG", short = "PONG", tag = "1 OR 2 PLAYERS",
      color = { 0.12, 0.30, 0.40 }, run = "love " .. shellQuote(pong), pic = "pong",
    }
  end
  local flap = HOME .. "/flap.love"
  if fileExists(flap) then
    menu[#menu + 1] = {
      label = "FLAP", short = "FLAP", tag = "1 OR 2 PLAYERS",
      color = { 0.24, 0.62, 0.88 }, run = "love " .. shellQuote(flap), pic = "flap",
    }
  end
  -- the real Crossy Road arcade software, run through box86 and wine
  local crossy = HOME .. "/crossy.sh"
  if fileExists(crossy) then
    menu[#menu + 1] = {
      label = "CROSSY ROAD", short = "CROSSY", tag = "2 PLAYERS   THE REAL ONE",
      color = { 0.24, 0.62, 0.90 }, run = "sh " .. shellQuote(crossy), pic = "crossy",
    }
  end
  -- Monkey Ball, Sega's 2001 arcade game, played by Flycast (the NAOMI board it ran on)
  local monkey = ROOT .. "/naomi/monkeyba.zip"
  if fileExists(monkey) then
    menu[#menu + 1] = {
      label = "MONKEY BALL", short = "MONKEY", tag = "SEGA ARCADE 2001",
      color = { 0.93, 0.55, 0.12 }, pic = "monkeyball",
      run = "retroarch --appendconfig=" .. shellQuote(HOME .. "/.config/retroarch/flycast.cfg") ..
            " -L " .. shellQuote(CORE_DIR .. "/flycast_libretro.so") .. " " .. shellQuote(monkey) .. " -f",
    }
  end
  local cockCount = 0
  for _, sys in ipairs(SYSTEMS) do
    for _, game in ipairs(catalogue[sys.dir] or {}) do
      if cocktail[gameKey(game)] then cockCount = cockCount + 1 end
    end
  end
  if cockCount > 0 then
    menu[#menu + 1] = { label = "TWO PLAYER", short = "2P", tag = gameCount(cockCount),
                        color = { 0.10, 0.44, 0.34 }, picked = "cocktail", pic = "twoplayer" }
  end

  local stars, plays = countPicked()
  if stars > 0 then
    menu[#menu + 1] = { label = "FAVOURITES", short = "STARS", tag = gameCount(stars),
                        color = { 0.72, 0.52, 0.06 }, picked = "star", pic = "favourites" }
  end
  if plays > 0 then
    menu[#menu + 1] = { label = "PLAYED LATELY", short = "AGAIN", tag = gameCount(plays),
                        color = { 0.16, 0.44, 0.40 }, picked = "recent", pic = "recent" }
  end
  local testCount = 0
  for key in pairs(allGames()) do if totest[key] then testCount = testCount + 1 end end
  if testCount > 0 then
    menu[#menu + 1] = { label = "TO TEST AT THE TABLE", short = "TEST", tag = gameCount(testCount),
                        color = { 0.50, 0.20, 0.44 }, picked = "totest", pic = "twoplayer" }
  end
  -- everything that is not a game lives behind one box, at the very end, so the shelf
  -- itself is games and nothing else
  menu[#menu + 1] = { label = "SETTING UP", short = "SETUP", tag = "BUTTONS, SCREEN, SEARCH",
                      color = { 0.28, 0.26, 0.18 }, tools = true, pic = "settings" }
  menu[#menu + 1] = { label = "TURN OFF", short = "OFF", tag = "SHUT THE TABLE DOWN",
                      color = { 0.30, 0.10, 0.12 }, power = true, pic = "off" }
  state = "systems"
  scroll = cursor
end

local buildGames
local buildPicked              -- the favourites and recently played shelves
local buildTools               -- the setting-up shelf, behind its own box

-- one box per folder the games arrived in (cps1, neogeo, ...), when there is more
-- than one; picking a folder shows what is in it
local function buildGroups(s)
  local games = catalogue[s.dir] or {}
  local names, seen, loose = {}, {}, 0
  for _, game in ipairs(games) do
    if game.group then
      if not seen[game.group] then seen[game.group] = 0 names[#names + 1] = game.group end
      seen[game.group] = seen[game.group] + 1
    else
      loose = loose + 1
    end
  end
  if #names < 2 then return false end
  table.sort(names)
  menu, cursor, title, sub = {}, 1, s.name, gameCount(#games)
  if loose > 0 then
    menu[#menu + 1] = { label = "EVERYTHING ELSE", short = s.short, tag = gameCount(loose),
                        color = s.color, sys = s, group = false }
  end
  for _, n in ipairs(names) do
    menu[#menu + 1] = { label = n:gsub("[_%-]", " "):upper(), short = s.short,
                        tag = gameCount(seen[n]), color = s.color, sys = s, group = n }
  end
  menu[#menu + 1] = { label = "ALL OF THEM", short = s.short, tag = gameCount(#games),
                      color = s.color, sys = s, group = "*" }
  state = "groups"
  scroll = cursor
  return true
end

-- one box on a game shelf, whichever shelf it is
local function gameEntry(game, s)
  local run, other
  if s.core then
    local core, path = s.core, game.path
    local mame = useMame[gameKey(game)]
    local m2010 = useMame2010[gameKey(game)]
    if core == "fbneo" and useMameCur[gameKey(game)] then
      core = "mame"
    elseif core == "fbneo" and m2010 then
      core = "mame2010"
      if type(m2010) == "string" then path = ROOT .. "/" .. s.dir .. "/mamesets2010/" .. m2010 .. ".zip" end
    elseif core == "fbneo" and mame then
      core = "mame2003_plus"
      if type(mame) == "string" then path = ROOT .. "/" .. s.dir .. "/mamesets/" .. mame .. ".zip" end
    end
    -- Flycast (Dreamcast and NAOMI) needs its own settings: this RetroArch is built for
    -- OpenGL ES, which Flycast cannot draw with, so it uses Vulkan; and the usual sound
    -- output crashes when a NAOMI game changes its sound speed, so it uses PipeWire's own
    local extra = ""
    if core == "flycast" then extra = " --appendconfig=" .. shellQuote(HOME .. "/.config/retroarch/flycast.cfg") end
    run = "retroarch" .. extra .. " -L " .. shellQuote(CORE_DIR .. "/" .. core .. "_libretro.so") ..
          " " .. shellQuote(path) .. " -f"
    if core == "fbneo" then other = "mame2003_plus"
    elseif core == "mame2003_plus" or core == "mame2010" or core == "mame" then other = "fbneo" end
  else
    run = "love " .. shellQuote(game.path)
  end
  local run2
  if other then
    run2 = "retroarch -L " .. shellQuote(CORE_DIR .. "/" .. other .. "_libretro.so") ..
           " " .. shellQuote(game.path) .. " -f"
  end
  return { label = game.label, short = s.short, color = s.color,
           game = game, run = run, run2 = run2 }
end

function buildTools()
  menu, cursor = {}, 1
  title, sub = "SETTING UP", nil
  menu[#menu + 1] = { label = "SEARCH AGAIN", short = "LOOK", tag = "FOR NEW GAMES",
                      color = { 0.24, 0.26, 0.32 }, rescan = true, pic = "search" }
  menu[#menu + 1] = { label = "WHAT DOES THIS BUTTON DO", short = "TEST", tag = "PRESS AND SEE",
                      color = { 0.18, 0.28, 0.30 }, pic = "buttontest",
                      run = "love " .. shellQuote(HOME .. "/cabbuttons.love") .. " --watch" }
  menu[#menu + 1] = { label = "SET UP THE BUTTONS", short = "PANEL", tag = "FOR THE ARCADE GAMES",
                      color = { 0.30, 0.26, 0.18 }, pic = "panel",
                      run = "love " .. shellQuote(HOME .. "/cabbuttons.love") }
  menu[#menu + 1] = { label = "LINE UP THE PICTURE", short = "SCREEN", tag = "IF THE EDGES ARE CUT OFF",
                      color = { 0.22, 0.30, 0.36 }, pic = "screen",
                      run = "love " .. shellQuote(HOME .. "/cabalign.love") }
  sub = "BUTTON 2 GOES BACK"
  state = "games"
  groupOf = nil
  scroll = cursor
end

function buildPicked(which)
  local byKey = allGames()
  menu, cursor = {}, 1
  -- the header has the count beside it, so the long name stays on the box
  title = (which == "star") and "FAVOURITES"
       or (which == "together") and "TWO PLAYER"
       or (which == "cocktail") and "TWO PLAYER"
       or (which == "totest") and "TO TEST AT THE TABLE"
       or "PLAYED LATELY"
  local keys = {}
  if which == "star" then
    for key in pairs(favourites) do keys[#keys + 1] = key end
    table.sort(keys)
  elseif which == "together" or which == "cocktail" or which == "totest" then
    local from = (which == "cocktail") and cocktail or (which == "totest") and totest or together
    for key in pairs(byKey) do
      if from[key] then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
      return (byKey[a].game.label or a) < (byKey[b].game.label or b)
    end)
  else
    keys = recent
  end
  for _, key in ipairs(keys) do
    local hit = byKey[key]
    if hit then menu[#menu + 1] = gameEntry(hit.game, hit.sys) end
  end
  sub = gameCount(#menu)
  if #menu == 0 then
    menu[1] = { label = "NOTHING HERE YET", short = "-", color = { 0.3, 0.3, 0.3 } }
  end
  state = "games"
  groupOf = nil
  scroll = cursor
end

function buildGames(s, group)
  local all = catalogue[s.dir] or {}
  local games = {}
  for _, game in ipairs(all) do
    if group == "*" or group == nil or game.group == group
       or (group == false and not game.group) then
      games[#games + 1] = game
    end
  end
  menu, cursor = {}, 1
  title = group and group ~= "*" and group ~= false and group:gsub("[_%-]", " "):upper() or s.name
  sub = gameCount(#games)
  for _, game in ipairs(games) do
    menu[#menu + 1] = gameEntry(game, s)
  end
  state = "games"
  groupOf = { sys = s, group = group }
  scroll = cursor
end

local function launch(cmd, second)
  local f = io.open(LAUNCH_FILE, "w")
  if not f then
    message, messageTimer = "COULD NOT START THAT ONE", 3
    return
  end
  f:write(cmd .. "\n")
  f:close()
  if tune then tune:stop() end
  os.remove(SECOND_FILE)
  if second then
    local f2 = io.open(SECOND_FILE, "w")
    if f2 then f2:write(second .. "\n") f2:close() end
  end
  state = "launching"
  love.timer.sleep(0.2)
  love.event.quit(0)
end

local powerArmed              -- true once TURN OFF has been pressed once

local function choose()
  local item = menu[cursor]
  if not item then return end
  sound(thunk)
  if item.rescan then
    scan()
    buildSystems()
    message, messageTimer = "LOOKED AGAIN", 2
  elseif item.power then
    -- ASKS TWICE, ALWAYS. One press used to shut the whole table down, and one stray
    -- press did exactly that with nobody in the room to switch it back on.
    if not powerArmed then
      powerArmed = true
      message, messageTimer = "PRESS AGAIN TO TURN THE TABLE OFF", 4
      return
    end
    powerArmed = nil
    local f = io.open(LAUNCH_FILE, "w")
    if f then f:write("sudo poweroff\n") f:close() end
    love.event.quit(0)
  elseif item.tools then
    buildTools()
  elseif item.picked then
    buildPicked(item.picked)
  elseif item.sys then
    buildGames(item.sys)
  elseif item.run then
    notePlayed(item.game)
    launch(item.run, item.run2)
  end
end

local function back()
  sound(thunk)
  if state == "games" or state == "groups" then buildSystems() end
end

-- button 3 stars a game, or takes the star off
local function toggleStar()
  local item = menu[cursor]
  if not item or not item.game then return end
  local key = gameKey(item.game)
  favourites[key] = (not favourites[key]) or nil
  writeState()
  sound(thunk)
  message, messageTimer = favourites[key] and "ADDED TO FAVOURITES" or "TAKEN OUT OF FAVOURITES", 2
end

-- the same game, started on the other arcade emulator
local function chooseOther()
  local item = menu[cursor]
  if item and item.run2 then
    launch(item.run2, item.run)
  elseif item then
    message, messageTimer = "ONLY ARCADE GAMES HAVE A SECOND ONE", 3
  end
end

local function move(d)
  if #menu == 0 then return end
  idle = 0
  sound(blip)
  powerArmed = nil            -- moving away forgets that TURN OFF was pressed
  cursor = cursor + d
  if cursor < 1 then cursor = #menu elseif cursor > #menu then cursor = 1 end
  -- a wrap should not send the shelf flying the whole way across
  if math.abs(cursor - scroll) > #menu / 2 then scroll = cursor end
end

-- which first letters this shelf actually has, in order
local function buildLetters()
  pickerLetters = {}
  local seen = {}
  for i = 1, #menu do
    local ch = menu[i].label:sub(1, 1):upper()
    if not seen[ch] then
      seen[ch] = i
      pickerLetters[#pickerLetters + 1] = { ch = ch, at = i }
    end
  end
  pickerAt = 1
  for i, l in ipairs(pickerLetters) do
    if l.at <= cursor then pickerAt = i end
  end
end

local function letterOf(i)
  local item = menu[i]
  return item and item.label:sub(1, 1):upper() or ""
end

-- jump to where the next letter starts, for a shelf hundreds of boxes long
local function jumpLetter(d)
  if #menu < 2 then return end
  sound(blip)
  local here = letterOf(cursor)
  local i = cursor
  for _ = 1, #menu do
    i = i + d
    if i < 1 then i = #menu elseif i > #menu then i = 1 end
    if letterOf(i) ~= here then break end
  end
  if d < 0 then
    -- going back should land on the FIRST of that letter, not the last
    local letter = letterOf(i)
    while letterOf(i - 1) == letter and i > 1 do i = i - 1 end
  end
  cursor = i
  scroll = cursor
end

-------------------------------------------------------------------------------
-- input: the cab's two sticks and a keyboard for the bench
-------------------------------------------------------------------------------
local KEYS = {
  prev = { "up", "left", "w", "a", "i", "j" },
  next = { "down", "right", "s", "d", "k", "l" },
  ok = { "return", "space", "1", "2", "z", "u" },
  back = { "escape", "backspace", "x", "o" },
  alt = { "tab", "c", "p" },
  alt2 = { "f", "j" },
}
local PAD = { ok = { 1, 8 }, back = { 2, 7 }, alt = { 3 }, alt2 = { 4 } }
local held = {}
local repeatTimer, repeatDir, repeatCount = 0, 0, 0

local function keyDown(list)
  for _, k in ipairs(list) do if love.keyboard.isDown(k) then return true end end
  return false
end

local function padDir()
  local dx, dy = 0, 0
  for _, js in ipairs(love.joystick.getJoysticks()) do
    local x = js:getAxisCount() >= 1 and js:getAxis(1) or 0
    local y = js:getAxisCount() >= 2 and js:getAxis(2) or 0
    if js:isGamepad() then
      if js:isGamepadDown("dpleft") then x = -1 elseif js:isGamepadDown("dpright") then x = 1 end
      if js:isGamepadDown("dpup") then y = -1 elseif js:isGamepadDown("dpdown") then y = 1 end
    end
    if x < -0.5 then dx = -1 elseif x > 0.5 then dx = 1 end
    if y < -0.5 then dy = -1 elseif y > 0.5 then dy = 1 end
  end
  if love.keyboard.isDown("left") then dx = -1 end
  if love.keyboard.isDown("right") then dx = 1 end
  if love.keyboard.isDown("up") then dy = -1 end
  if love.keyboard.isDown("down") then dy = 1 end
  return dx, dy
end

local function padPressed(which)
  local hit = false
  for _, js in ipairs(love.joystick.getJoysticks()) do
    for _, b in ipairs(PAD[which]) do
      local id = tostring(js) .. which .. b
      local down = b <= js:getButtonCount() and js:isDown(b)
      if down then
        if not held[id] then held[id] = true hit = true end
      else
        held[id] = nil
      end
    end
  end
  return hit
end

-------------------------------------------------------------------------------
-- showing off
-------------------------------------------------------------------------------
-- a game with a picture, chosen at random from everything on the machine
-- A shuffled deck of every game that has a film. Each is shown once before any comes
-- round again, so it always feels fresh, and a new shuffle never starts with the one
-- that was just on.
local lastClip
local function nextClip()
  if #clipBag == 0 then
    for _, sys in ipairs(SYSTEMS) do
      for _, game in ipairs(catalogue[sys.dir] or {}) do
        if clips[game.stem] then clipBag[#clipBag + 1] = { game = game, sys = sys } end
      end
    end
    for i = #clipBag, 2, -1 do
      local j = love.math.random(i)
      clipBag[i], clipBag[j] = clipBag[j], clipBag[i]
    end
    if #clipBag > 1 and clipBag[#clipBag].game.stem == lastClip then
      clipBag[1], clipBag[#clipBag] = clipBag[#clipBag], clipBag[1]
    end
  end
  local hit = table.remove(clipBag)
  if hit then lastClip = hit.game.stem end
  return hit
end

local function dropVideo(item)
  if item and item.video then
    pcall(function() item.video:pause(); item.video:release() end)
    item.video = nil
  end
end

local function pickShowpiece()
  for _ = 1, 5 do
    local hit = next(clips) and nextClip()
    if not hit then break end
    local ok, v = pcall(g.newVideo, "demos/" .. hit.game.stem .. ".ogv", { audio = false })
    if ok and v then
      v:setFilter("nearest", "nearest")      -- square pixels, like the real thing
      v:play()
      hit.video = v
      return hit
    end
  end
  local pool = {}
  for _, sys in ipairs(SYSTEMS) do
    for _, game in ipairs(catalogue[sys.dir] or {}) do
      pool[#pool + 1] = { game = game, sys = sys }
    end
  end
  if #pool == 0 then return nil end
  for _ = 1, 30 do
    local hit = pool[love.math.random(#pool)]
    if loadArt(hit.game) then return hit end
  end
  return nil
end

local function stopShowingOff()
  dropVideo(shown)
  attract, shown, fade = false, nil, 0
  idle = 0
end

-------------------------------------------------------------------------------
-- drawing
-------------------------------------------------------------------------------
local function text(str, x, y, color)
  g.setColor(color or PAL.white)
  g.print(str, math.floor(x), math.floor(y))
end

local function textCenter(str, y, color, cx)
  text(str, math.floor((cx or W / 2) - font:getWidth(str) / 2), y, color)
end

-- break a title into lines that fit a box
local function wrap(str, width)
  local lines, cur = {}, nil
  for word in str:gmatch("%S+") do
    local try = cur and (cur .. " " .. word) or word
    if cur and font:getWidth(try) > width then
      lines[#lines + 1] = cur
      cur = word
    else
      cur = try
    end
  end
  if cur then lines[#lines + 1] = cur end
  return lines
end

local function checker()
  local canvas = g.newCanvas(W, H)
  canvas:setFilter("nearest", "nearest")
  g.setCanvas(canvas)
  for y = 0, H - 1, CELL do
    for x = 0, W - 1, CELL do
      g.setColor(((x + y) / CELL) % 2 == 0 and PAL.bg1 or PAL.bg2)
      g.rectangle("fill", x, y, CELL, CELL)
    end
  end
  g.setCanvas()
  return canvas
end

local BOX_W, BOX_H = 118, 150      -- the box on the front of the shelf
local SHELF_Y = 146                -- its middle
local STEP = 96                    -- how far apart the boxes sit

-- One box: the game's own picture if it has one, else a made-up cover in its
-- machine's colour with the name across it.
local function drawBox(item, cx, cy, scale, focus)
  local w, h = BOX_W * scale, BOX_H * scale
  local x, y = cx - w / 2, cy - h / 2
  local dim = 0.58 + 0.42 * focus
  local txt = 0.45 + 0.55 * focus

  -- a glow behind the one you are on
  if focus > 0.3 then
    local c = item.color or { 0.3, 0.3, 0.3 }
    for i = 6, 1, -1 do
      g.setColor(c[1], c[2], c[3], 0.05 * focus)
      g.rectangle("fill", x - i * 2, y - i * 2, w + i * 4, h + i * 4, 6, 6)
    end
  end
  g.setColor(0, 0, 0, 0.55)
  g.rectangle("fill", x + 3, y + 4, w, h, 3, 3)

  local img = (item.game and loadArt(item.game)) or (item.pic and loadPic(item.pic))
  if img then
    g.setColor(0, 0, 0)
    g.rectangle("fill", x - 2, y - 2, w + 4, h + 4, 3, 3)
    g.setColor(dim, dim, dim)
    local iw, ih = img:getDimensions()
    local s = math.min(w / iw, h / ih)
    g.draw(img, cx - iw * s / 2, cy - ih * s / 2, 0, s, s)
  else
    local c = item.color or { 0.3, 0.3, 0.3 }
    g.setColor(0, 0, 0)
    g.rectangle("fill", x - 2, y - 2, w + 4, h + 4, 3, 3)
    g.setColor(c[1] * dim, c[2] * dim, c[3] * dim)
    g.rectangle("fill", x, y, w, h, 2, 2)
    -- spine down the left, like a box standing on a shelf
    g.setColor(c[1] * dim * 0.5, c[2] * dim * 0.5, c[3] * dim * 0.5)
    g.rectangle("fill", x, y, 7 * scale, h, 2, 2)
    -- band across the top carrying the machine's name
    g.setColor(0, 0, 0, 0.5)
    g.rectangle("fill", x + 9 * scale, y + 7 * scale, w - 15 * scale, 12 * scale)
    textCenter(item.short or "", y + 9 * scale, { 1, 1, 1, txt }, cx + 3 * scale)
    -- only the box at the front carries its name; on the ones at the edge it would
    -- run off the screen and into the arrow
    if focus > 0.45 then
      local lines = wrap(item.label, w - 24 * scale)
      local ly = cy - (#lines * 11) / 2 + 4
      for i, line in ipairs(lines) do
        textCenter(line, ly + (i - 1) * 11, { 1, 1, 1, (focus - 0.45) / 0.55 }, cx + 3 * scale)
      end
    end
    -- a sheen across the top, like light on a shrink-wrapped box
    g.setColor(1, 1, 1, 0.10)
    g.polygon("fill", x + 8 * scale, y, x + w * 0.62, y, x + 8 * scale, y + h * 0.55)
    g.setColor(0, 0, 0, 0.16)
    g.polygon("fill", x + w, y + h * 0.30, x + w, y + h, x + 10 * scale, y + h)
    g.setColor(1, 1, 1, 0.14 * dim)
    g.rectangle("fill", x + 9 * scale, y + h - 13 * scale, w - 15 * scale, 3 * scale)
  end

  local c = item.color or { 0.3, 0.3, 0.3 }
  for i = 1, 7 do
    local a = 0.22 * focus * (1 - i / 8)
    local inset = i * 2
    g.setColor(c[1], c[2], c[3], a)
    g.rectangle("fill", x + inset, y + h + 2 + i, w - inset * 2, 1)
  end

  -- on this table a game is only a two-player game if the picture turns round for the
  -- far seat, so that is what the mark means
  if item.game and focus > 0.5 and cocktail[gameKey(item.game)] then
    g.setColor(0.25, 0.9, 0.5, 0.95)
    g.rectangle("fill", x + 6, y + h - 12 * scale, 26, 9, 2, 2)
    g.setColor(0, 0, 0)
    g.print("2P", math.floor(x + 11), math.floor(y + h - 12 * scale + 1))
  end

  if item.game and favourites[gameKey(item.game)] then
    g.setColor(1, 0.82, 0.1)
    local sx, sy, r = x + w - 10, y + 12, 7 * scale
    for i = 0, 4 do
      local a1 = -math.pi / 2 + i * (2 * math.pi / 5)
      local a2 = a1 + 2 * math.pi / 5
      g.polygon("fill", sx, sy,
                sx + math.cos(a1) * r, sy + math.sin(a1) * r,
                sx + math.cos(a2) * r, sy + math.sin(a2) * r)
    end
  end

  if focus > 0.9 then
    g.setColor(PAL.orange)
    g.rectangle("line", x - 2.5, y - 2.5, w + 5, h + 5, 4, 4)
    g.setColor(PAL.white)
    g.rectangle("line", x - 0.5, y - 0.5, w + 1, h + 1, 3, 3)
  end
end

function love.load(args)
  love.mouse.setVisible(false)
  font = g.newImageFont("font.png", GLYPH_ORDER)
  font:setFilter("nearest", "nearest")
  g.setFont(font)
  g.setLineStyle("rough")
  screen = g.newCanvas(W, H)
  screen:setFilter("nearest", "nearest")
  readScreenConf()
  readState()
  findTunes()
  blip = makeNoise(660, 0.05, "square")
  thunk = makeNoise(180, 0.12, "sine")
  blip:setVolume(0.35)
  thunk:setVolume(0.5)
  playNextTune()
  bg = checker()
  scan()
  buildSystems()
  -- anything the wrapper wants to say about the game that just ran
  local m = io.open(MESSAGE_FILE, "r")
  if m then
    message = (m:read("*l") or ""):upper()
    m:close()
    os.remove(MESSAGE_FILE)
    if message ~= "" then messageTimer = 6 end
  end
  for _, a in ipairs(args or {}) do
    local v = a:match("^%-%-shot=(.+)$")
    if v or a == "--shot" then
      shotMode = v or "systems"
      for i, item in ipairs(menu) do
        if item.sys and item.sys.dir == shotMode then cursor = i buildGames(item.sys) break end
      end
    end
  end
end

local function drawShelf()
  local top = SHELF_Y - BOX_H / 2 - 14
  local bandH = BOX_H + 30
  for i = 0, bandH - 1 do
    g.setColor(0, 0, 0, 0.25 + 0.45 * (i / bandH))
    g.rectangle("fill", 0, top + i, W, 1)
  end
  g.setColor(PAL.edge[1], PAL.edge[2], PAL.edge[3], 0.30)
  g.rectangle("fill", 0, top, W, 1)
  g.setColor(PAL.edge[1], PAL.edge[2], PAL.edge[3], 0.55)
  g.rectangle("fill", 0, top + bandH - 2, W, 2)

  -- the ones either side first, so the front box sits over them
  for pass = 1, 2 do
    for i = math.floor(scroll) - 2, math.ceil(scroll) + 2 do
      local item = menu[i]
      if item then
        local d = i - scroll
        local focus = 1 - math.min(1, math.abs(d))
        local isFront = math.abs(d) < 0.5
        if (pass == 1) ~= isFront then
          local cx = W / 2 + d * STEP
          if cx > -90 and cx < W + 90 then
            drawBox(item, cx, SHELF_Y - 6 * focus, 0.60 + 0.40 * focus, focus)
          end
        end
      end
    end
  end

  if #menu > 1 then
    local a = 0.45 + 0.45 * math.abs(math.sin(t * 3))
    g.setColor(PAL.orange[1], PAL.orange[2], PAL.orange[3], a)
    g.polygon("fill", 6, SHELF_Y, 16, SHELF_Y - 8, 16, SHELF_Y + 8)
    g.polygon("fill", W - 6, SHELF_Y, W - 16, SHELF_Y - 8, W - 16, SHELF_Y + 8)
  end
end

function love.draw()
  g.setCanvas(screen)
  g.clear(0, 0, 0)
  g.setColor(1, 1, 1)
  g.draw(bg, 0, 0)

  local headH = sub and 30 or 22
  g.setColor(PAL.black)
  g.rectangle("fill", 8, 8, W - 16, headH, 6, 6)
  g.setColor(PAL.pink)
  g.rectangle("line", 8.5, 8.5, W - 17, headH - 1, 6, 6)
  textCenter(title, 14, PAL.yellow)
  if sub then textCenter(sub, 26, PAL.panel) end
  if #menu > 1 then
    local count = ("%d/%d"):format(cursor, #menu)
    text(count, W - 14 - font:getWidth(count), 14, PAL.grey)
  end

  drawShelf()

  local item = menu[cursor]
  if item then
    local lines = wrap(item.label, W - 40)
    local barH = 8 + #lines * 11
    local by = SHELF_Y + BOX_H / 2 + 18
    g.setColor(PAL.black)
    g.rectangle("fill", 12, by, W - 24, barH, 4, 4)
    g.setColor(PAL.pink)
    g.rectangle("fill", 12, by, W - 24, 2, 1, 1)
    for i, line in ipairs(lines) do
      textCenter(line, by + 5 + (i - 1) * 11, PAL.white)
    end
    local tag = item.tag or ""
    if tag == "" and state == "games" and #menu > 20 then
      tag = ("%d OF %d"):format(cursor, #menu)
    end
    if tag ~= "" then textCenter(tag, by + barH + 5, PAL.yellow) end
    -- a dot per game, so a long shelf still shows where you are
    local n = math.min(#menu, 21)
    if n > 1 then
      local first = math.max(1, math.min(cursor - math.floor(n / 2), #menu - n + 1))
      local dy = by + barH + (tag ~= "" and 18 or 8)
      for i = 0, n - 1 do
        local on = (first + i) == cursor
        g.setColor(on and PAL.orange or { 1, 1, 1, 0.28 })
        g.rectangle("fill", W / 2 - (n * 6) / 2 + i * 6 + 1, dy, on and 4 or 3, on and 4 or 3, 1, 1)
      end
    end
  end

  local hint, hint2 = "BUTTON 1 OPEN", nil
  if state == "groups" then hint = "BUTTON 1 OPEN    BUTTON 2 BACK" end
  if state == "games" then
    hint = "1 PLAY   2 BACK   3 FAVOURITE"
    if #menu > 20 then hint2 = "UP-DOWN A LETTER   4 ALPHABET" end
  end
  if (messageTimer or 0) > 0 and message then hint, hint2 = message, nil end
  textCenter(hint, H - 13, (messageTimer or 0) > 0 and PAL.orange or PAL.panel)
  if hint2 then textCenter(hint2, H - 25, PAL.grey) end

  -- nothing on the machine yet: say where to put things
  if state == "systems" and #menu <= 3 then
    g.setColor(0, 0, 0, 0.82)
    g.rectangle("fill", 12, H - 74, W - 24, 48, 4, 4)
    g.setColor(PAL.edge)
    g.rectangle("line", 12.5, H - 73.5, W - 25, 47, 4, 4)
    textCenter("ON YOUR PC OPEN", H - 70, PAL.panel)
    textCenter("//192.168.1.175/GAMES", H - 58, PAL.white)
    textCenter("DROP GAMES IN, THEN", H - 44, PAL.panel)
    textCenter("PICK SEARCH AGAIN", H - 34, PAL.panel)
  end

  if state == "launching" then
    g.setColor(0, 0, 0, 0.8)
    g.rectangle("fill", 0, 0, W, H)
    textCenter("STARTING...", H / 2 - 4, PAL.white)
  end

  if picker then
    local cols = 7
    local rows = math.ceil(#pickerLetters / cols)
    local cw, ch = 30, 26
    local pw2, ph2 = cols * cw + 12, rows * ch + 34
    local px2 = math.floor((W - pw2) / 2)
    local py2 = math.floor((H - ph2) / 2)
    g.setColor(0, 0, 0, 0.85)
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(PAL.white)
    g.rectangle("fill", px2 - 1, py2 - 1, pw2 + 2, ph2 + 2, 9, 9)
    g.setColor(PAL.black)
    g.rectangle("fill", px2, py2, pw2, ph2, 8, 8)
    textCenter("JUMP TO", py2 + 6, PAL.yellow)
    for i, l in ipairs(pickerLetters) do
      local cx2 = px2 + 6 + ((i - 1) % cols) * cw
      local cy2 = py2 + 22 + math.floor((i - 1) / cols) * ch
      if i == pickerAt then
        g.setColor(PAL.pink)
        g.rectangle("fill", cx2, cy2, cw - 2, ch - 3, 3, 3)
      end
      text(l.ch, cx2 + math.floor((cw - 2 - font:getWidth(l.ch)) / 2), cy2 + 6,
           i == pickerAt and PAL.white or PAL.panel)
    end
    textCenter("1 JUMP    2 BACK", py2 + ph2 - 12, PAL.grey)
  end

  if attract then
    -- solid black: at 92% the shelf's own heading showed through, under the DEMO badge
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", 0, 0, W, H)
    local vid = shown and shown.video
    local img = (not vid) and shown and loadArt(shown.game)
    if vid or img then
      local iw, ih
      if vid then
        -- the film is stored at the chips' own size; its true shape comes from the list
        ih = vid:getHeight()
        iw = ih * (clips[shown.game.stem] or (vid:getWidth() / ih))
      else
        iw, ih = img:getDimensions()
      end
      local sc = math.min((W - 24) / iw, (H - 90) / ih)
      g.setColor(1, 1, 1, fade)
      if vid then
        g.draw(vid, W / 2 - iw * sc / 2, (H - 40) / 2 - ih * sc / 2, 0,
               sc * iw / vid:getWidth(), sc * ih / vid:getHeight())
      else
        g.draw(img, W / 2 - iw * sc / 2, (H - 40) / 2 - ih * sc / 2, 0, sc, sc)
      end
      -- a frame round it, like a picture on a wall
      g.setColor(1, 1, 1, fade * 0.5)
      g.rectangle("line", W / 2 - iw * sc / 2 - 2.5, (H - 40) / 2 - ih * sc / 2 - 2.5,
                  iw * sc + 5, ih * sc + 5)
      local name = shown.game.label
      if font:getWidth(name) > W - 16 then name = name:sub(1, math.floor((W - 16) / 8)) end
      g.setColor(0, 0, 0, fade * 0.8)
      g.rectangle("fill", 0, H - 44, W, 18)
      textCenter(name, H - 40, { 1, 1, 1, fade })
      textCenter(shown.sys.name, H - 26, { PAL.yellow[1], PAL.yellow[2], PAL.yellow[3], fade * 0.9 })
    end
    -- A flashing DEMO in the empty strip above the picture. It used to say "PRESS ANY
    -- BUTTON TO PLAY", which reads as if the game on the screen is about to start.
    if math.floor(t * 1.5) % 2 == 0 then
      local w = font:getWidth("DEMO") + 12
      g.setColor(0, 0, 0, 0.85)
      g.rectangle("fill", W / 2 - w / 2, 5, w, 14)
      g.setColor(PAL.orange[1], PAL.orange[2], PAL.orange[3])
      g.rectangle("line", W / 2 - w / 2 + 0.5, 5.5, w - 1, 13)
      textCenter("DEMO", 8, PAL.orange)
    end
  end

  g.setCanvas()
  -- same as the game: a VGA monitor can cut the edges off, so the picture can be
  -- pulled in (OVERSCAN) and shifted (NUDGE_X / NUDGE_Y)
  local sw, sh = g.getDimensions()
  local sx, sy = (sw - PAD_X * 2) / W, (sh - PAD_Y * 2) / H
  if PAD_X == 0 and PAD_Y == 0 then
    local s = math.max(1, math.floor(math.min(sx, sy)))
    sx, sy = s, s
  end
  g.setColor(1, 1, 1)
  g.draw(screen, math.floor((sw - W * sx) / 2) + NUDGE_X,
                 math.floor((sh - H * sy) / 2) + NUDGE_Y, 0, sx, sy)
end

function love.update(dt)
  t = t + dt
  if tune and not tune:isPlaying() then playNextTune() end
  if messageTimer then messageTimer = messageTimer - dt end
  if shotMode then
    shotFrames = (shotFrames or 0) + 1
    scroll = cursor
    if shotFrames > 3 then
      love.graphics.captureScreenshot("shot_" .. shotMode .. ".png")
      if shotFrames > 5 then love.event.quit(0) end
    end
    return
  end

  scroll = scroll + (cursor - scroll) * math.min(1, dt * 14)
  if math.abs(cursor - scroll) < 0.01 then scroll = cursor end

  idle = idle + dt
  if attract then
    -- fade the picture in, hold it, fade it out, then find another
    local age = t - shownAt
    local hold = (shown and shown.video) and CLIP_HOLD or HOLD
    if age < FADE_TIME then fade = age / FADE_TIME
    elseif age > hold - FADE_TIME then fade = math.max(0, (hold - age) / FADE_TIME)
    else fade = 1 end
    if age > hold then
      dropVideo(shown)
      shown, shownAt = pickShowpiece(), t
      if not shown then stopShowingOff() end
    end
  elseif idle > ATTRACT_AFTER and state == "systems" and not someoneWatching() then
    shown, shownAt = pickShowpiece(), t
    if shown then attract, fade = true, 0 end
  end
  -- somebody started watching from a phone: stop the film and give the Pi back
  if attract and someoneWatching() then stopShowingOff() end

  local dx, dy = padDir()
  if attract and (dx ~= 0 or dy ~= 0) then stopShowingOff() return end

  if picker then
    local cols = 7
    local d = 0
    if dx ~= 0 then d = dx elseif dy ~= 0 then d = dy * cols end
    if d ~= 0 then
      if d ~= repeatDir then
        pickerAt = math.max(1, math.min(#pickerLetters, pickerAt + d))
        sound(blip)
        repeatDir, repeatTimer = d, 0.3
      else
        repeatTimer = repeatTimer - dt
        if repeatTimer <= 0 then
          pickerAt = math.max(1, math.min(#pickerLetters, pickerAt + d))
          sound(blip)
          repeatTimer = 0.12
        end
      end
    else
      repeatDir, repeatTimer = 0, 0
    end
    if padPressed("ok") then
      cursor = pickerLetters[pickerAt].at
      scroll = cursor
      picker = false
      sound(thunk)
    elseif padPressed("back") or padPressed("alt2") then
      picker = false
      sound(thunk)
    end
    idle = 0
    return
  end
  -- across moves one box; up and down jump a whole letter
  local d, jump = dx, false
  if d == 0 and dy ~= 0 then d, jump = dy, true end
  if d ~= 0 then
    local key = jump and (d * 2) or d
    if key ~= repeatDir then
      if jump then jumpLetter(d) else move(d) end
      repeatDir, repeatTimer, repeatCount = key, 0.34, 0
    else
      repeatTimer = repeatTimer - dt
      if repeatTimer <= 0 then
        if jump then jumpLetter(d) else move(d) end
        repeatCount = repeatCount + 1
        -- hold it and the shelf picks up speed, for a long row of games
        repeatTimer = jump and 0.22 or math.max(0.035, 0.13 - repeatCount * 0.006)
      end
    end
  else
    repeatDir, repeatTimer, repeatCount = 0, 0, 0
  end

  if padPressed("ok") then
    if attract then stopShowingOff() return end
    choose()
  end
  if padPressed("back") then
    if attract then stopShowingOff() return end
    back()
  end
  if padPressed("alt") then
    if attract then stopShowingOff() return end
    if state == "games" then toggleStar() else chooseOther() end
  end
  if padPressed("alt2") then
    if attract then stopShowingOff() return end
    if state == "games" and #menu > 12 then
      buildLetters()
      picker = true
      sound(thunk)
    end
  end
end

function love.keypressed(key)
  if attract then stopShowingOff() return end
  if picker then
    if key == "return" or key == "space" then
      cursor = pickerLetters[pickerAt].at
      scroll = cursor
    end
    picker = false
    return
  end
  for _, k in ipairs(KEYS.alt2) do
    if key == k and state == "games" and #menu > 12 then
      buildLetters()
      picker = true
      return
    end
  end
  for _, k in ipairs(KEYS.ok) do if key == k then choose() return end end
  for _, k in ipairs(KEYS.alt) do
    if key == k then
      if state == "games" then toggleStar() else chooseOther() end
      return
    end
  end
  for _, k in ipairs(KEYS.back) do
    if key == k then
      if state == "games" then
        back()
      elseif key == "escape" then
        -- a deliberate stop leaves a note. Without it the launcher cannot tell an
        -- ordinary exit from "shut the cabinet down", and killing the shelf for any
        -- reason took the whole cabinet dark.
        local f = io.open("/tmp/cab_stop", "w")
        if f then f:write("escape") f:close() end
        love.event.quit(0)
      end
      return
    end
  end
  if key == "f5" then scan() buildSystems() message, messageTimer = "LOOKED AGAIN", 2 end
end
