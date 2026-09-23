-- render.lua : NES-style renderer. Everything is drawn at 1x on a small canvas with
-- 8-pixel cells and scaled up with nearest-neighbour filtering by main.lua.
--
-- Two layouts:
--   cocktail : each player gets a 240x160 landscape half; main.lua stacks them and
--              rotates player 2's half to face the opposite seat.
--   side     : one 256x240 screen, both bottles upright with the NES centre panel.
local Board = require("board")
local R = {}

local CELL = 8
local PAL = {
  red = { 0.97, 0.22, 0.00 },
  yellow = { 0.97, 0.72, 0.00 },
  blue = { 0.24, 0.74, 0.99 },
  bg1 = { 57 / 255, 0, 165 / 255 },
  bg2 = { 0, 0, 0 },
  glass = { 0.55, 0.95, 0.90 },
  glassDark = { 0.00, 0.50, 0.50 },
  panel = { 165 / 255, 231 / 255, 1.0 },
  panelEdge = { 0, 239 / 255, 222 / 255 },
  cardPink = { 248 / 255, 48 / 255, 88 / 255 },
  cardBlue = { 0, 144 / 255, 248 / 255 },
  cardFill = { 248 / 255, 160 / 255, 48 / 255 },
  bottleIn1 = { 0, 42 / 255, 136 / 255 },
  bottleIn2 = { 110 / 255, 0, 64 / 255 },
  ink = { 0.06, 0.06, 0.16 },
  frame = { 0.90, 0.20, 0.25 },
  black = { 0, 0, 0 },
  white = { 1, 1, 1 },
  -- title screen
  green1 = { 0, 82 / 255, 0 },
  green2 = { 0, 0, 0 },
  logoBlue = { 0.25, 0.45, 0.85 },
  logoPink = { 0.85, 0.15, 0.45 },
  logoText = { 0.98, 0.85, 0.25 },
  -- mode select screen
  pink1 = { 248 / 255, 48 / 255, 88 / 255 },
  pink2 = { 248 / 255, 144 / 255, 88 / 255 },
  orange = { 0.95, 0.60, 0.20 },
  hilite = { 0.85, 0.15, 0.45 },
  green = { 0.55, 0.85, 0.20 },
  -- sprites
  skin = { 0.98, 0.78, 0.60 },
  brown = { 0.55, 0.30, 0.10 },
  -- one-player screen
  grey1 = { 0.62, 0.62, 0.62 },
  grey2 = { 0.16, 0.16, 0.16 },
  clip = { 0.98, 0.80, 0.20 },
}
R.SCHEMES = {
  game = { PAL.bg1, PAL.bg2 },
  title = { PAL.green1, PAL.green2 },
  select = { PAL.pink1, PAL.pink2 },
  solo = { PAL.green1, PAL.green2 },
}
R.PAL = PAL

-------------------------------------------------------------------------------
-- bitmap font (5x7, built into an ImageFont at load)
-------------------------------------------------------------------------------
local GLYPHS = {
  A = { ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
  B = { "####.", "#...#", "#...#", "####.", "#...#", "#...#", "####." },
  C = { ".####", "#....", "#....", "#....", "#....", "#....", ".####" },
  D = { "####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####." },
  E = { "#####", "#....", "#....", "####.", "#....", "#....", "#####" },
  F = { "#####", "#....", "#....", "####.", "#....", "#....", "#...." },
  G = { ".####", "#....", "#....", "#.###", "#...#", "#...#", ".####" },
  H = { "#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
  I = { "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####" },
  J = { "....#", "....#", "....#", "....#", "....#", "#...#", ".###." },
  K = { "#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#" },
  L = { "#....", "#....", "#....", "#....", "#....", "#....", "#####" },
  M = { "#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#" },
  N = { "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#" },
  O = { ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###." },
  P = { "####.", "#...#", "#...#", "####.", "#....", "#....", "#...." },
  Q = { ".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#" },
  R = { "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#" },
  S = { ".####", "#....", "#....", ".###.", "....#", "....#", "####." },
  T = { "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.." },
  U = { "#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###." },
  V = { "#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.." },
  W = { "#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#" },
  X = { "#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#" },
  Y = { "#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.." },
  Z = { "#####", "....#", "...#.", "..#..", ".#...", "#....", "#####" },
  ["0"] = { ".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###." },
  ["1"] = { "..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###." },
  ["2"] = { ".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####" },
  ["3"] = { ".###.", "#...#", "....#", "..##.", "....#", "#...#", ".###." },
  ["4"] = { "...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#." },
  ["5"] = { "#####", "#....", "####.", "....#", "....#", "#...#", ".###." },
  ["6"] = { ".###.", "#....", "#....", "####.", "#...#", "#...#", ".###." },
  ["7"] = { "#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..." },
  ["8"] = { ".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###." },
  ["9"] = { ".###.", "#...#", "#...#", ".####", "....#", "....#", ".###." },
  [" "] = { "...", "...", "...", "...", "...", "...", "..." },
  ["."] = { ".....", ".....", ".....", ".....", ".....", ".##..", ".##.." },
  [","] = { ".....", ".....", ".....", ".....", ".##..", "..#..", ".#..." },
  ["-"] = { ".....", ".....", ".....", "#####", ".....", ".....", "....." },
  [":"] = { ".....", ".##..", ".##..", ".....", ".##..", ".##..", "....." },
  ["<"] = { "...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#." },
  [">"] = { ".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#..." },
  ["!"] = { "..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.." },
  ["?"] = { ".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.." },
  ["/"] = { "....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...." },
  ["'"] = { "..#..", "..#..", ".....", ".....", ".....", ".....", "....." },
  ["#"] = { ".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#." },
  ["@"] = { "..###..", ".#...#.", "#..##.#", "#.#...#", "#..##.#", ".#...#.", "..###.." }, -- copyright sign
}
local GLYPH_ORDER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,-:<>!?/'#@"

local function buildFont()
  local width = 1
  for ch in GLYPH_ORDER:gmatch(".") do width = width + #GLYPHS[ch][1] + 1 + 1 end
  local img = love.image.newImageData(width, 8)
  local x = 0
  local function sep() img:setPixel(x, 0, 1, 0, 1, 1) for y = 1, 7 do img:setPixel(x, y, 1, 0, 1, 1) end x = x + 1 end
  sep()
  for ch in GLYPH_ORDER:gmatch(".") do
    local rows = GLYPHS[ch]
    local w = #rows[1]
    for gy = 1, 7 do
      for gx = 1, w do
        if rows[gy]:sub(gx, gx) == "#" then img:setPixel(x + gx - 1, gy - 1, 1, 1, 1, 1) end
      end
    end
    x = x + w + 1 -- one blank column of letter spacing
    sep()
  end
  local font = love.graphics.newImageFont(img, GLYPH_ORDER)
  font:setFilter("nearest", "nearest")
  return font
end

-------------------------------------------------------------------------------
-- sprites (8x8, built into Images at load)
-------------------------------------------------------------------------------
-- The three NES characters. k = black, w = white, # = body colour.
-- Red: horns, wide fanged grin, arms out. Blue: hair tuft, heavy angled brows, frown.
-- Yellow: spiky crown, squinting eyes, toothy grin, arms up.
local VIRUS_SMALL = {
  red = { "#..##..#", "########", "#wk##kw#", "########", "#kkkkkk#", "#kwkkwk#", ".######.", ".#....#." },
  blue = { "...##...", ".######.", "#kk##kk#", "#wk##kw#", "########", "##kkkk##", ".######.", ".#....#." },
  yellow = { "#.#..#.#", ".######.", "#kk##kk#", "########", "#wkwkwk#", "#kkkkkk#", ".######.", ".#....#." },
}
-- Lens versions, 24x24 with black outlines, drawn after the NES lens artwork.
local VIRUS_BIG = {
  -- red: horns curling out, big round eyes, wide open mouth full of teeth, arms up
  red = {
    "..kk................kk..",
    ".k##k..............k##k.",
    ".k###k....kkkk....k###k.",
    "..k###kkkk####kkkk###k..",
    "...k################k...",
    "..k##################k..",
    "..k##kkkk######kkkk##k..",
    ".k##kwwwwk####kwwwwk##k.",
    ".k##kwwkwk####kwkwwk##k.",
    ".k##kwwwwk####kwwwwk##k.",
    ".k###kkkk######kkkk###k.",
    ".k####################k.",
    "kk####kkkkkkkkkkkk####kk",
    "k#k##kwkwkwkwkwkwkk##k#k",
    "k#k##kkkkkkkkkkkkkk##k#k",
    ".kk###kwkwkwkwkwkk###kk.",
    "...k###kkkkkkkkkk###k...",
    "....k##############k....",
    ".....k############k.....",
    "......kk########kk......",
    ".......k##k..k##k.......",
    "......k###k..k###k......",
    "......kkkkk..kkkkk......",
    "........................",
  },
  -- blue: curl on top, heavy brows over big eyes, frown, arms folded across the middle
  blue = {
    "..........kk............",
    ".........k##k...........",
    "........k##k............",
    "........k#k.............",
    ".....kkkk#kkkkkk........",
    "....k############k......",
    "...k###############k....",
    "..k#################k...",
    ".k###kkk#######kkk###k..",
    ".k##kkkkk#####kkkkk##k..",
    ".k##kwwwk#####kwwwk##k..",
    ".k##kwkwk#####kwkwk##k..",
    ".k##kwwwk#####kwwwk##k..",
    ".k###kkk#######kkk###k..",
    ".k###################k..",
    ".k####kkkkkkkkkkk####k..",
    ".k###kk#########kk###k..",
    "kk###################kk.",
    "k#kkkkkkkkkkkkkkkkkkk#k.",
    "kk###################kk.",
    "..k#################k...",
    ".......k##k..k##k.......",
    "......k###k..k###k......",
    "......kkkkk..kkkkk......",
  },
  -- yellow: spiky crown, big eyes glancing sideways, wide toothy grin, arms up
  yellow = {
    "...k....k..kk..k....k...",
    "..k#k..k#k.k##k.k#k.k#k.",
    "..k#k.k##k.k##k.k##k.k#k",
    "..k##kk##kkk##kkk##kk##k",
    "kk.k##################k.",
    "k#kk##################kk",
    "k###kkkk#######kkkk####k",
    "k##kwwwwk#####kwwwwk###k",
    ".k#kwwkwk#####kwwkwk##k.",
    "..k#kwwwwk####kwwwwk##k.",
    "..k##kkkk######kkkk###k.",
    "..k###################k.",
    "..k#kkkkkkkkkkkkkkkk#k..",
    "..k#kwkwkwkwkwkwkwkk#k..",
    "..k#kkkkkkkkkkkkkkkk#k..",
    "..k##kwkwkwkwkwkwkk##k..",
    "...k##kkkkkkkkkkkk##k...",
    "...k################k...",
    "....k##############k....",
    ".....kk##########kk.....",
    ".......k##k..k##k.......",
    "......k###k..k###k......",
    "......kkkkk..kkkkk......",
    "........................",
  },
}

-- Second frame: the legs shuffle (the renderer adds the bob).
local function wiggle(rows)
  local out = {}
  for i, r in ipairs(rows) do out[i] = r end
  local n = #rows
  if #rows[1] == 8 then
    out[n] = "..#..#.."
  else
    -- find the leg rows (the last three drawn rows) and squat them
    local last = n
    while last > 1 and rows[last]:find("^%.+$") do last = last - 1 end
    out[last - 2] = ".......k##k..k##k......."
    out[last - 1] = "......kkkkk..kkkkk......"
    out[last] = "........................"
  end
  return out
end
local FLASH = { "#.....#.", ".#...#..", "..#.#...", "...#....", "..#.#...", ".#...#..", "#.....#.", "........" }
local HEART = { ".##..##.", "########", "########", "########", ".######.", "..####..", "...##...", "........" }
-- the win-tally crown, 10x8
local CROWN = {
  "#...##...#",
  "##..##..##",
  "###.##.###",
  "##########",
  "#w##w##w##",
  "##########",
  ".########.",
  ".kkkkkkkk.",
}
local TRI_DOWN = { "########", ".######.", "..####..", "...##..." }
local TRI_UP = { "...##...", "..####..", ".######.", "########" }
-- the doctor: b hat band, w coat/hat, l head mirror, s skin, k eyes/buttons
local DOCTOR = {
  "....wwwwwwww....",
  "...wwwwwwwwww...",
  "...wwwwllwwww...",
  "...bbbbbbbbbb...",
  "....ssssssss....",
  "...ssskssskss...",
  "...ssssssssss...",
  "....sbbbbbbs....",
  ".....ssssss.....",
  "...wwwwwwwwwww..",
  "..wwwwwwkwwwwww.",
  "..wwwwwwkwwwwww.",
  "..wwwwwwkwwwwww.",
  "..wwwwwwwwwwwww.",
  "...wwww...wwww..",
  "...kkkk...kkkk..",
}

-- Capsule half with rounded corners on the free sides. sides: which edges are open.
-- seam: what to draw on the side joined to the other half. "none" leaves it open so
-- a capsule reads as one smooth pill; "dark" outlines it in the colour's dark shade;
-- "black" outlines it in black, the NES way, so the two halves read as a real capsule.
local function halfSprite(openLeft, openRight, openTop, openBottom, seam, carry)
  seam = seam or "none"
  -- which joined sides THIS half outlines. With a one-pixel seam only one half of the
  -- pair carries it (carry = true); with a two-pixel seam both do.
  local seamL = seam ~= "none" and carry and not openLeft
  local seamR = seam ~= "none" and carry and not openRight
  local seamT = seam ~= "none" and carry and not openTop
  local seamB = seam ~= "none" and carry and not openBottom
  local rows = {}
  for y = 1, 8 do
    local row = {}
    for x = 1, 8 do row[x] = "#" end
    rows[y] = row
  end
  local function cut(x, y) rows[y][x] = "." end
  if openLeft and openTop then cut(1, 1) cut(2, 1) cut(1, 2) end
  if openRight and openTop then cut(8, 1) cut(7, 1) cut(8, 2) end
  if openLeft and openBottom then cut(1, 8) cut(2, 8) cut(1, 7) end
  if openRight and openBottom then cut(8, 8) cut(7, 8) cut(8, 7) end
  -- dark outline on the open sides so touching pieces of one colour stay separate
  local function edge(x, y) if rows[y][x] == "#" then rows[y][x] = "k" end end
  for i = 1, 8 do
    if openTop then edge(i, 1) end
    if openBottom then edge(i, 8) end
    if openLeft then edge(1, i) end
    if openRight then edge(8, i) end
  end
  if openLeft and openTop then edge(2, 2) end
  if openRight and openTop then edge(7, 2) end
  if openLeft and openBottom then edge(2, 7) end
  if openRight and openBottom then edge(7, 7) end
  -- the seam on the joined side
  local ch = seam == "black" and "s" or "k"
  local function seamPx(x, y) if rows[y][x] == "#" then rows[y][x] = ch end end
  for i = 1, 8 do
    if seamL then seamPx(1, i) end
    if seamR then seamPx(8, i) end
    if seamT then seamPx(i, 1) end
    if seamB then seamPx(i, 8) end
  end
  -- highlight, kept inside whatever outline the half has on that side
  local hx = (openLeft or seamL) and 2 or 1
  local hy = (openTop or seamT) and 2 or 1
  rows[hy][hx + 1] = "w"
  rows[hy + 1][hx] = "w"
  for y = 1, 8 do rows[y] = table.concat(rows[y]) end
  return rows
end

-- SEAM: "none" | "dark" | "black".  SEAM_WIDTH: 1 = one half carries the line (the NES
-- look), 2 = both halves do. main.lua sets these from config before R.load().
R.SEAM, R.SEAM_WIDTH = "black", 1

local function buildHalfShapes(seam, width)
  local both = (width or 1) >= 2
  return {
    single = halfSprite(true, true, true, true, seam, false),
    left = halfSprite(true, false, true, true, seam, true),     -- partner to the right: carries the seam
    right = halfSprite(false, true, true, true, seam, both),    -- partner to the left
    top = halfSprite(true, true, true, false, seam, true),      -- partner below: carries the seam
    bottom = halfSprite(true, true, false, true, seam, both),   -- partner above
  }
end

-- board link -> which shape
local LINK_SHAPE = { right = "left", left = "right", down = "top", up = "bottom" }

local function shade(c, k) return { c[1] * k, c[2] * k, c[3] * k } end

local function buildSprite(rows, color, extra)
  local w, h = #rows[1], #rows
  local img = love.image.newImageData(w, h)
  local dark = shade(color, 0.55)
  for y = 1, h do
    for x = 1, w do
      local ch = rows[y]:sub(x, x)
      local c
      if ch == "#" then c = color
      elseif ch == "w" then c = PAL.white
      elseif ch == "s" then c = PAL.black
      elseif ch == "k" then c = extra and PAL.black or dark
      elseif extra and extra[ch] then c = extra[ch] end
      if c then img:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1) end
    end
  end
  local image = love.graphics.newImage(img)
  image:setFilter("nearest", "nearest")
  return image
end

local SPR = {}

-- (Re)build the capsule halves for the current R.SEAM. Called by R.load; a preview
-- can call it again after changing R.SEAM.
function R.buildHalves()
  local shapes = buildHalfShapes(R.SEAM, R.SEAM_WIDTH)
  for _, color in ipairs(Board.COLORS) do
    SPR[color] = SPR[color] or { virus = {}, big = {}, half = {} }
    for name, rows in pairs(shapes) do SPR[color].half[name] = buildSprite(rows, PAL[color]) end
  end
end

-- sprites/font.png: the real typeface, an ImageFont strip of 8x8 cells in GLYPH_ORDER
local function loadFontOverride()
  if not love.filesystem.getInfo("sprites/font.png") then return nil end
  local ok, font = pcall(love.graphics.newImageFont, "sprites/font.png", GLYPH_ORDER)
  if not ok then return nil end
  font:setFilter("nearest", "nearest")
  return font
end

function R.load()
  R.font = loadFontOverride() or buildFont()
  love.graphics.setFont(R.font)
  love.graphics.setLineStyle("rough")
  for _, color in ipairs(Board.COLORS) do
    SPR[color] = { virus = {}, big = {}, half = {} }
    SPR[color].virus[1] = buildSprite(VIRUS_SMALL[color], PAL[color], {})
    SPR[color].virus[2] = buildSprite(wiggle(VIRUS_SMALL[color]), PAL[color], {})
    SPR[color].big[1] = buildSprite(VIRUS_BIG[color], PAL[color], {})
    SPR[color].big[2] = buildSprite(wiggle(VIRUS_BIG[color]), PAL[color], {})
  end
  R.buildHalves()
  SPR.flash = buildSprite(FLASH, PAL.white)
  SPR.heart = buildSprite(HEART, PAL.logoPink)
  SPR.crown = buildSprite(CROWN, PAL.logoText, {})
  SPR.triDown = buildSprite(TRI_DOWN, PAL.orange)
  SPR.triUp = buildSprite(TRI_UP, PAL.orange)
  SPR.doctor = buildSprite(DOCTOR, PAL.white, { s = PAL.skin, b = PAL.brown, l = PAL.blue })
  R.bg = {}
  R.loadOverrides()
end

-- PNG overrides from the sprites/ folder. A file wider than it is tall is treated as
-- two animation frames side by side. Names:
--   virus_red.png / virus_blue.png / virus_yellow.png   in-bottle viruses (8x8 per frame)
--   lens_red.png  / lens_blue.png  / lens_yellow.png    lens viruses (any size, ~24x24)
--   doctor.png                                          the doctor (16x16)
local function loadOverride(name, single)
  local path = "sprites/" .. name .. ".png"
  if not love.filesystem.getInfo(path) then return nil end
  local ok, data = pcall(love.image.newImageData, path)
  if not ok then return nil end
  local w, h = data:getDimensions()
  local frames = {}
  -- wider than tall = frames side by side; a whole multiple of the height gives the count
  local count = 1
  if w > h and not single then
    count = (w % h == 0) and math.floor(w / h) or 2
  end
  local fw = math.floor(w / count)
  for f = 1, count do
    local piece = love.image.newImageData(fw, h)
    piece:paste(data, 0, 0, (f - 1) * fw, 0, fw, h)
    local img = love.graphics.newImage(piece)
    img:setFilter("nearest", "nearest")
    frames[f] = img
  end
  if count == 1 then frames[2] = frames[1] end
  return frames
end

function R.loadOverrides()
  R.overrides = {}
  for _, color in ipairs(Board.COLORS) do
    local small = loadOverride("virus_" .. color)
    if small then SPR[color].virus = small R.overrides[#R.overrides + 1] = "virus_" .. color end
    local big = loadOverride("lens_" .. color)
    if big then SPR[color].big = big R.overrides[#R.overrides + 1] = "lens_" .. color end
  end
  -- doctor.png poses: 1 idle (title), 2 holding the next capsule, 3 throwing, 4 arms out
  -- half_red.png etc: the capsule halves as a strip of six 8x8 frames in the sprite
  -- sheet's own order: top, bottom, left, right, the loose single, the cleared ring
  for _, color in ipairs(Board.COLORS) do
    local hv = loadOverride("half_" .. color)
    if hv and #hv >= 5 then
      local h = SPR[color].half
      h.top, h.bottom, h.left, h.right, h.single = hv[1], hv[2], hv[3], hv[4], hv[5]
      if hv[6] then SPR[color].clear = hv[6] end
      R.overrides[#R.overrides + 1] = "half_" .. color
    end
  end
  local doc = loadOverride("doctor")
  if doc then
    SPR.doctor = doc[1]
    SPR.doctorPoses = { idle = doc[1], hold = doc[2] or doc[1], throw = doc[3] or doc[2] or doc[1], shrug = doc[4] or doc[1] }
    R.overrides[#R.overrides + 1] = "doctor"
  end
  -- title screen: logo.png (capsule with lettering), logo_half.png (same at half size for
  -- the narrow per-seat halves), title_doctor.png and title_virus.png (menu pill icons)
  local ls = loadOverride("logo_small", true)
  if ls then SPR.logoSmall = ls[1] end
  -- the sheet's HUD pieces: glass, lens, clipboards, doctor's box, cards, tally, panels
  local bg, bs = loadOverride("bottle_game", true), loadOverride("bottle_solo", true)
  if bg then SPR.bottle = { game = bg[1], solo = bs and bs[1] or bg[1] } end
  local singles = {
    lens = "lens", doctorBox = "doctor_box", clipboard = "clipboard", clipboardTall = "clipboard_tall",
    cardStageClear = "card_stageclear", cardGameOver = "card_gameover", tally = "tally",
    panel = "panel", virusPanel = "virus_panel", virusLabel = "virus_label",
  }
  for key, file in pairs(singles) do
    local img = loadOverride(file, true)
    if img then SPR[key] = img[1] end
  end
  local crowns = loadOverride("crowns")
  if crowns and #crowns >= 2 then SPR.crowns = crowns end
  -- mode select: the sheet's bar, level box, markers, framed words and options panel
  local singles2 = { levelBar = "level_bar", levelBox = "level_box", optionsPanel = "options_panel" }
  for key, file in pairs(singles2) do
    local img = loadOverride(file, true)
    if img then SPR[key] = img[1] end
  end
  for key, files in pairs({ marks = { "mark_down", "mark_up" }, marksWide = { "mark_down_wide", "mark_up_wide" } }) do
    local d, u = loadOverride(files[1], true), loadOverride(files[2], true)
    if d and u then SPR[key] = { d[1], u[1] } end
  end
  local fever, chill, off = loadOverride("opt_fever", true), loadOverride("opt_chill", true), loadOverride("opt_off", true)
  if fever and chill and off then SPR.optBoxes = { fever[1], chill[1], off[1] } end
  SPR.labels = {}
  for key, file in pairs({ virus = "label_virus", speed = "label_speed", music = "label_music" }) do
    local on, offi = loadOverride(file .. "_on", true), loadOverride(file, true)
    if on and offi then SPR.labels[key] = { on = on[1], off = offi[1] } end
  end
  local logo = loadOverride("logo", true)
  if logo then SPR.logo = logo[1] R.overrides[#R.overrides + 1] = "logo" end
  local half = loadOverride("logo_half", true)
  if half then SPR.logoHalf = half[1] end
  local td = loadOverride("title_doctor")
  if td then SPR.titleDoctor = td end
  local tv = loadOverride("title_virus")
  if tv then SPR.titleVirus = tv end
end

-------------------------------------------------------------------------------
-- layouts
-------------------------------------------------------------------------------
R.LAYOUTS = {
  -- Both cocktail layouts are sized for a 5:4 monitor mounted sideways (4:5 as seen
  -- from either seat): "side" fills 320x256, "cocktail" fills 256x320.
  -- players at opposite short edges: halves stacked, player 2's half turned 180
  cocktail = {
    canvas = { 256, 160 },
    perPlayerCanvas = true,
    composite = "vertical",
    bottle = { 96, 24 },
    drawnBottle = true,
    region = { 0, 0, 256, 160 },
  },
  -- the cocktail default: portrait 256x320 between the two seats, bottles side by side in
  -- two tall strips, player 2's strip turned 180 to face the far end
  side = {
    canvas = { 128, 320 },
    perPlayerCanvas = true,
    composite = "horizontal",
    bottle = { 32, 104 },
    strip = true,
    region = { 0, 0, 128, 320 },
  },
  -- NES two-player screen, both upright, for tables where both players sit on one side
  upright = {
    canvas = { 256, 240 },
    perPlayerCanvas = false,
    bottles = { { 16, 56 }, { 176, 56 } },
    regions = { { 0, 0, 128, 240 }, { 128, 0, 128, 240 } },
    full = { 0, 0, 256, 240 },
  },
}

-- Size of the composed screen for a layout.
function R.screenSize(layout)
  local w, h = layout.canvas[1], layout.canvas[2]
  if layout.composite == "vertical" then return w, h * 2
  elseif layout.composite == "horizontal" then return w * 2, h end
  return w, h
end

-------------------------------------------------------------------------------
-- primitives
-------------------------------------------------------------------------------
local g = love.graphics

local function rect(color, x, y, w, h)
  g.setColor(color)
  g.rectangle("fill", x, y, w, h)
end

local function text(str, x, y, color, scale)
  g.setColor(color or PAL.white)
  g.print(str, math.floor(x), math.floor(y), 0, scale or 1, scale or 1)
end

local function textCenter(str, region, y, color, scale)
  scale = scale or 1
  local w = R.font:getWidth(str) * scale
  text(str, region[1] + (region[3] - w) / 2, region[2] + y, color, scale)
end
R.textCenter = textCenter

-- Right-aligned at x: the font is proportional, so number columns need this to line up.
local function textRight(str, x, y, color)
  text(str, x - R.font:getWidth(str), y, color)
end
R.textRight = textRight

local function checker(w, h, colors)
  local canvas = g.newCanvas(w, h)
  canvas:setFilter("nearest", "nearest")
  g.setCanvas(canvas)
  for y = 0, h - 1, CELL do
    for x = 0, w - 1, CELL do
      rect(((x + y) / CELL) % 2 == 0 and colors[1] or colors[2], x, y, CELL, CELL)
    end
  end
  g.setCanvas()
  return canvas
end

-- scheme: "game" (purple), "title" (green) or "select" (pink and orange)
function R.background(w, h, scheme)
  scheme = scheme or "game"
  local key = w .. "x" .. h .. scheme
  if not R.bg[key] then R.bg[key] = checker(w, h, R.SCHEMES[scheme]) end
  g.setColor(1, 1, 1)
  g.draw(R.bg[key], 0, 0)
end

local function sprite(name, x, y)
  g.setColor(1, 1, 1)
  g.draw(SPR[name], math.floor(x), math.floor(y))
end

-- black rounded panel with a thin light edge, like the NES menus
local function pill(x, y, w, h, r)
  g.setColor(PAL.white)
  g.rectangle("fill", x - 1, y - 1, w + 2, h + 2, r + 1, r + 1)
  g.setColor(PAL.black)
  g.rectangle("fill", x, y, w, h, r, r)
end

local function box(x, y, w, h)
  rect(PAL.black, x - 2, y - 2, w + 4, h + 4)
  rect(PAL.panelEdge, x - 1, y - 1, w + 2, h + 2)
  rect(PAL.panel, x, y, w, h)
end

local function drawVirus(x, y, color, t)
  local frame = (math.floor(t * 3) % 2) + 1
  g.setColor(1, 1, 1)
  g.draw(SPR[color].virus[frame], x, y)
end
R.drawVirus = drawVirus

-- The round magnifying lens: the three big viruses sit in a triangle, red on top,
-- blue bottom left, yellow bottom right, dancing in place. One hops when a virus of
-- its colour is killed and leaves for good once its colour is gone.
local LENS_SPOTS = { red = { 0, -15 }, blue = { -16, 11 }, yellow = { 16, 11 } }
local function lensViruses(cx, cy, r, t, b)
  local present = b:virusColors()
  local hits = b.lensHit or {}
  for i, color in ipairs({ "blue", "yellow", "red" }) do
    if present[color] then
      local spot = LENS_SPOTS[color]
      local sway = math.sin(t * 2.2 + i * 2.1) * 2
      local frame = (math.floor(t * 3 + i) % 2) + 1
      local hit = (hits[color] or 0) > 0
      local hop = hit and -6 or ((frame == 2) and -1 or 0)
      local img = SPR[color].big[hit and 1 or frame]
      local iw, ih = img:getDimensions()
      local scale = (iw <= 16) and 2 or 1
      local x = cx + spot[1] + sway
      local y = cy + spot[2] + hop
      g.setColor(1, 1, 1)
      g.draw(img, math.floor(x), math.floor(y), 0, scale, scale, math.floor(iw / 2), math.floor(ih / 2))
    end
  end
end

local function lens(cx, cy, r, t, b)
  if SPR.lens then
    g.setColor(1, 1, 1)
    g.draw(SPR.lens, cx - 44, cy - 38)
    lensViruses(cx, cy, r, t, b)
    return
  end
  -- handle: angled down-left out of the rim
  g.push()
  g.translate(cx - r * 0.72, cy + r * 0.72)
  g.rotate(math.pi / 4)
  g.setColor(PAL.ink)
  g.rectangle("fill", -5, -1, 24, 9, 2, 2)
  g.setColor(PAL.clip)
  g.rectangle("fill", -4, 0, 22, 7, 2, 2)
  g.setColor(PAL.ink)
  g.rectangle("fill", 6, 0, 1, 7)
  g.rectangle("fill", 10, 0, 1, 7)
  g.pop()
  -- glass
  g.setColor(PAL.ink)
  g.circle("fill", cx, cy, r + 3)
  g.setColor(PAL.white)
  g.circle("fill", cx, cy, r + 1)
  g.setColor(PAL.panel)
  g.circle("fill", cx, cy, r)
  g.setColor(PAL.white)
  g.arc("line", "open", cx, cy, r - 3, math.pi * 1.15, math.pi * 1.45)
  lensViruses(cx, cy, r, t, b)
end

local function drawHalf(x, y, color, shape)
  g.setColor(1, 1, 1)
  g.draw(SPR[color].half[shape or "single"], x, y)
end
R.drawHalf = drawHalf

-- a piece being cleared: the sheet's empty ring in its colour, else the white flash
function R.drawClear(x, y, color)
  g.setColor(1, 1, 1)
  local img = SPR[color] and SPR[color].clear or SPR.flash
  g.draw(img, x, y)
end

-------------------------------------------------------------------------------
-- bottle
-------------------------------------------------------------------------------
local BW, BH = Board.W * CELL, Board.H * CELL

R.bottleSkin = "game"          -- "game" (purple rim) or "solo" (green rim)
R.noBottleSprite = false       -- a layout too short for the 176-tall glass keeps the drawn one

local function drawBottleFrame(bx, by)
  local img = SPR.bottle and SPR.bottle[R.bottleSkin]
  if img and not R.noBottleSprite then
    g.setColor(1, 1, 1)
    g.draw(img, bx - 8, by - 40)
    rect(PAL.black, bx, by, BW, BH)
    return
  end
  -- glass outline with rounded shoulders, neck two cells wide above columns 4-5
  g.setColor(PAL.glassDark)
  g.rectangle("fill", bx - 4, by - 4, BW + 8, BH + 8, 4, 4)
  g.setColor(PAL.glass)
  g.rectangle("fill", bx - 3, by - 3, BW + 6, BH + 6, 3, 3)
  rect(PAL.black, bx, by, BW, BH)
  -- neck
  local nx = bx + 3 * CELL
  rect(PAL.black, nx, by - 4, 2 * CELL, 4)
  rect(PAL.glassDark, nx - 4, by - 18, 3, 16)
  rect(PAL.glass, nx - 3, by - 18, 3, 15)
  rect(PAL.glassDark, nx + 2 * CELL + 1, by - 18, 3, 16)
  rect(PAL.glass, nx + 2 * CELL, by - 18, 3, 15)
  rect(PAL.black, nx, by - 16, 2 * CELL, 16)
  -- cap ring
  rect(PAL.glassDark, nx - 5, by - 21, 2 * CELL + 10, 4)
  rect(PAL.glass, nx - 4, by - 20, 2 * CELL + 8, 2)
end

-- showNext: draw the next capsule in the neck (two-player screens). The one-player
-- screen leaves it out because the doctor is holding it. empty: just the glass.
function R.drawBottle(b, bx, by, t, showNext, empty)
  drawBottleFrame(bx, by)
  if empty then return end
  for y = 1, Board.H do
    for x = 1, Board.W do
      local c = b.grid[y][x]
      if c then
        local px, py = bx + (x - 1) * CELL, by + (y - 1) * CELL
        if c.kind == "virus" then drawVirus(px, py, c.color, t)
        else drawHalf(px, py, c.color, LINK_SHAPE[c.link]) end
      end
    end
  end
  if b.capsule then
    local c1, c2 = Board.capsuleCells(b.capsule)
    local flat = b.capsule.o % 2 == 0
    local s1, s2 = flat and "left" or "bottom", flat and "right" or "top"
    for _, cc in ipairs({ { c1, s1 }, { c2, s2 } }) do
      local cell = cc[1]
      if cell[2] >= 0 then
        drawHalf(bx + (cell[1] - 1) * CELL, by + (cell[2] - 1) * CELL, cell[3], cc[2])
      end
    end
  end
  if b.flash then
    for _, f in ipairs(b.flash) do
      R.drawClear(bx + (f[1] - 1) * CELL, by + (f[2] - 1) * CELL, f[3])
    end
  end
  -- next capsule sits in the neck
  if showNext ~= false then
    local nx = bx + 3 * CELL
    local ny = (SPR.bottle and not R.noBottleSprite) and (by - 24) or (by - 14)
    drawHalf(nx, ny, b.nextPair[1], "left")
    drawHalf(nx + CELL, ny, b.nextPair[2], "right")
  end
end

-- NES-style end card inside the bottle: yellow panel, pink frame, bold black text.
-- lines: e.g. { "YOU", "WON!" }. Returns the y just under the card for a hint line.
function R.drawEndCard(bx, by, lines)
  local key = table.concat(lines, " ")
  local card = (key == "STAGE CLEAR" and SPR.cardStageClear) or (key == "GAME OVER" and SPR.cardGameOver)
  if card then
    g.setColor(1, 1, 1)
    g.draw(card, bx + 2, by + 16)
    return by + 16 + card:getHeight() + 8
  end
  -- the same frame as the cards: pink, black, blue, black, orange
  local w, h = 60, 16 + #lines * 12
  local x, y = bx + 2, by + 16
  rect(PAL.cardPink, x, y, w, h)
  rect(PAL.black, x + 2, y + 2, w - 4, h - 4)
  rect(PAL.cardBlue, x + 3, y + 3, w - 6, h - 6)
  rect(PAL.black, x + 4, y + 4, w - 8, h - 8)
  rect(PAL.cardFill, x + 5, y + 5, w - 10, h - 10)
  for i, s in ipairs(lines) do
    local tw = R.font:getWidth(s)
    local tx = x + math.floor((w - tw) / 2)
    local ty = y + 9 + (i - 1) * 12
    text(s, tx, ty, PAL.black)
  end
  return y + h + 8
end

-- A short line of text centred in the bottle at a given y. Anything wider than the
-- glass is split at a space onto two lines.
function R.drawBottleLine(bx, y, str, color)
  local lines, cur = {}, nil
  for word in str:gmatch("%S+") do
    local try = cur and (cur .. " " .. word) or word
    if cur and R.font:getWidth(try) > BW - 2 then lines[#lines + 1] = cur cur = word else cur = try end
  end
  lines[#lines + 1] = cur or str
  for i, s in ipairs(lines) do
    local tw = R.font:getWidth(s)
    text(s, bx + math.floor((BW - tw) / 2), y + (i - 1) * 10, color or PAL.white)
  end
end

-- The doctor standing at the bottom of a bottle (the winner's).
function R.drawBottleDoctor(bx, by)
  local img = SPR.doctorPoses and SPR.doctorPoses.hold or SPR.doctor
  local iw, ih = img:getDimensions()
  local scale = (iw <= 16) and 2 or 1
  g.setColor(1, 1, 1)
  g.draw(img, bx + math.floor((BW - iw * scale) / 2), by + BH - ih * scale - 2, 0, scale, scale)
end

-------------------------------------------------------------------------------
-- panels
-------------------------------------------------------------------------------
local SPEED_NAME = { low = "LOW", med = "MED", hi = "HI" }

-- Versus win tally, set by main.lua before drawing: R.wins = {p1, p2}, R.roundsToWin.
R.wins, R.roundsToWin = { 0, 0 }, 3
local winBoard -- defined below, after the clipboard helper

-- present: set of virus colours still in the bottle; a colour vanishes from the
-- magnifier once it is wiped out, like the NES.
local function magnifier(x, y, t, present)
  box(x, y, 52, 52)
  rect(PAL.frame, x + 2, y + 2, 48, 48)
  rect(PAL.panel, x + 4, y + 4, 44, 44)
  rect(PAL.frame, x + 25, y + 4, 2, 44)
  rect(PAL.frame, x + 4, y + 25, 44, 2)
  if not present or present.red then drawVirus(x + 8, y + 8 + math.floor(math.sin(t * 2) * 2), "red", t) end
  if not present or present.yellow then drawVirus(x + 32, y + 10 + math.floor(math.cos(t * 2) * 2), "yellow", t) end
  if not present or present.blue then drawVirus(x + 20, y + 30 + math.floor(math.sin(t * 2.5) * 2), "blue", t) end
end

-- Side layout half: one info column to the right of the bottle.
local function drawInfoColumn(b, p, extra, x)
  text("PLAYER", x, 8, PAL.white)
  text(tostring(p), x + 52, 8, PAL.yellow)
  box(x, 22, 76, 34)
  text("LEVEL", x + 4, 25, PAL.ink)
  textRight(("%2d"):format(b.level), x + 72, 25, PAL.ink)
  text("SPEED", x + 4, 35, PAL.ink)
  textRight(SPEED_NAME[b.speed], x + 72, 35, PAL.ink)
  text("VIRUS", x + 4, 45, PAL.ink)
  textRight(("%2d"):format(b.viruses), x + 72, 45, PAL.ink)
  box(x, 64, 76, 22)
  text("SCORE", x + 4, 67, PAL.ink)
  textRight(("%d"):format(b.score), x + 72, 77, PAL.ink)
  if extra then text(extra, x, 96, PAL.white) end
  if #b.pendingGarbage > 0 then text(("INCOMING %d"):format(#b.pendingGarbage), x, 108, PAL.red) end
  winBoard(x + 15, 130, p)
end

-- Cocktail half: info columns either side of the bottle.
-- Tall strip (128 wide): everything stacked above and below the bottle.
local function drawStripInfo(b, p, extra)
  -- the tally shows the rounds; the strip only has room for DEMO / CPU beside the name
  if extra and extra:find("ROUNDS") then extra = extra:find("CPU") and "CPU" or nil end
  text("PLAYER", 8, 3, PAL.white)
  text(tostring(p), 60, 3, PAL.yellow)
  if extra then textRight(extra, 120, 3, PAL.white) end
  box(8, 14, 112, 46)
  text("LEVEL", 12, 16, PAL.ink)
  textRight(("%2d"):format(b.level), 116, 16, PAL.ink)
  text("SPEED", 12, 26, PAL.ink)
  textRight(SPEED_NAME[b.speed], 116, 26, PAL.ink)
  text("VIRUS", 12, 36, PAL.ink)
  textRight(("%2d"):format(b.viruses), 116, 36, PAL.ink)
  text("SCORE", 12, 48, PAL.ink)
  textRight(("%d"):format(b.score), 116, 48, PAL.ink)
  if #b.pendingGarbage > 0 then text(("IN %d"):format(#b.pendingGarbage), 4, 300, PAL.red) end
  winBoard(39, 244, p)
end

function R.drawCocktailInfo(b, p, extra, layout)
  if layout and layout.strip then return drawStripInfo(b, p, extra) end
  if layout and layout.infoColumn then return drawInfoColumn(b, p, extra, layout.infoColumn) end
  local bxl = layout and layout.bottle[1] or 88
  local lx, rx = bxl - 84, bxl + BW + 16
  text("PLAYER", lx, 10, PAL.white)
  text(tostring(p), lx + 52, 10, PAL.yellow)
  box(lx, 26, 76, 40)
  text("LEVEL", lx + 4, 30, PAL.ink)
  textRight(("%2d"):format(b.level), lx + 72, 30, PAL.ink)
  text("SPEED", lx + 4, 40, PAL.ink)
  textRight(SPEED_NAME[b.speed], lx + 72, 40, PAL.ink)
  text("VIRUS", lx + 4, 50, PAL.ink)
  textRight(("%2d"):format(b.viruses), lx + 72, 50, PAL.ink)
  box(rx, 26, 76, 22)
  text("SCORE", rx + 4, 30, PAL.ink)
  textRight(("%d"):format(b.score), rx + 72, 40, PAL.ink)
  if extra then text(extra, rx, 60, PAL.white) end
  if #b.pendingGarbage > 0 then text(("INCOMING %d"):format(#b.pendingGarbage), lx, 76, PAL.red) end
  winBoard(lx + 27, 100, p, true)
end

-- Side layout: the NES centre panel between the bottles.
function R.drawCenterPanel(b1, b2, t)
  if SPR.panel and SPR.virusPanel and SPR.virusLabel then
    local x = 91
    g.setColor(1, 1, 1)
    g.draw(SPR.panel, x, 8)
    text("1P", x + 4, 14, PAL.ink)
    text("2P", x + 54, 14, PAL.ink)
    text("LEVEL", x + 17, 24, PAL.ink)
    local l1 = b1 and ("%02d"):format(b1.level) or "--"
    local l2 = b2 and ("%02d"):format(b2.level) or "--"
    text(l1, x + 6, 32, PAL.ink)
    text(l2, x + 52, 32, PAL.ink)
    local s1 = b1 and SPEED_NAME[b1.speed] or "---"
    local s2 = b2 and SPEED_NAME[b2.speed] or "---"
    text(s1, x + 3, 42, PAL.ink)
    text(s2, x + 47, 42, PAL.ink)
    winBoard(103, 68)
    g.setColor(1, 1, 1)
    g.draw(SPR.virusLabel, 106, 150)
    g.draw(SPR.virusPanel, 107, 160)
    local v1 = (b1 and b1.viruses) and ("%02d"):format(b1.viruses) or "--"
    local v2 = (b2 and b2.viruses) and ("%02d"):format(b2.viruses) or "--"
    text(v1, 109, 172, PAL.ink)
    text(v2, 130, 172, PAL.ink)
    return
  end
  local x = 96
  box(x + 2, 6, 60, 44)
  text("1P", x + 8, 9, PAL.ink)
  text("2P", x + 42, 9, PAL.ink)
  text("LEVEL", x + 17, 19, PAL.ink)
  local l1 = b1 and ("%02d"):format(b1.level) or "--"
  local l2 = b2 and ("%02d"):format(b2.level) or "--"
  text(l1, x + 10, 29, PAL.ink)
  text(l2, x + 40, 29, PAL.ink)
  local s1 = b1 and SPEED_NAME[b1.speed] or "---"
  local s2 = b2 and SPEED_NAME[b2.speed] or "---"
  text(s1, x + 5, 39, PAL.ink)
  text(s2, x + 34, 39, PAL.ink)
  -- win tally clipboard: a crown per round won
  winBoard(x + 15, 66)
  box(x + 2, 128, 60, 36)
  text("VIRUS", x + 17, 132, PAL.ink)
  local v1 = (b1 and b1.viruses) and ("%02d"):format(b1.viruses) or "--"
  local v2 = (b2 and b2.viruses) and ("%02d"):format(b2.viruses) or "--"
  text(v1, x + 10, 148, PAL.ink)
  text(v2, x + 40, 148, PAL.ink)
end

-- Yellow-framed clipboard panel with the clip on top.
local function clipboard(x, y, w, h)
  rect(PAL.ink, x + 1, y + 1, w + 4, h + 4)
  rect(PAL.clip, x - 2, y - 2, w + 4, h + 4)
  rect(PAL.panel, x, y, w, h)
  rect(PAL.ink, x + math.floor(w / 2) - 11, y - 7, 22, 9)
  rect(PAL.clip, x + math.floor(w / 2) - 9, y - 6, 18, 6)
  rect(PAL.panel, x + math.floor(w / 2) - 5, y - 4, 10, 2)
end

-- Win tally clipboard: two columns (1P, 2P), one row per round needed, a crown per win.
-- owner: which player's tally this is. Their column is on the left, the opponent's on
-- the right, so it reads the same way from either seat. nil = 1P left, 2P right.
winBoard = function(x, y, owner, compact)
  local rows = math.max(1, math.min(5, R.roundsToWin or 3))
  local cols = owner == 2 and { 2, 1 } or { 1, 2 }
  if SPR.tally and SPR.crowns and rows == 3 and not compact then
    g.setColor(1, 1, 1)
    g.draw(SPR.tally, x, y)
    for r = 1, 3 do
      for c = 1, 2 do
        local won = (R.wins[cols[c]] or 0) >= r
        g.draw(SPR.crowns[won and 2 or 1], x + 9 + (c - 1) * 16, y + 23 + (r - 1) * 16)
      end
    end
    return
  end
  local cw, ch = 14, 11
  local w, h = cw * 2 + 6, rows * ch + 6
  clipboard(x, y, w, h)
  for r = 1, rows do
    for c = 1, 2 do
      local cx, cy = x + 3 + (c - 1) * cw, y + 3 + (r - 1) * ch
      rect(PAL.logoPink, cx, cy, cw, ch)
      rect({ 0.10, 0.02, 0.14 }, cx + 1, cy + 1, cw - 2, ch - 2)
      if (R.wins[cols[c]] or 0) >= r then
        g.setColor(1, 1, 1)
        g.draw(SPR.crown, cx + 2, cy + 2)
      end
    end
  end
end
R.WINBOARD_W = 50

-- One-player game on the whole screen, NES style: grey checkerboard, bottle centred,
-- clipboards for scores and level, the doctor top right, the round lens bottom left.
function R.drawSolo(b, W, H, t, topScore)
  local bx = math.floor((W - BW) / 2)
  local by = math.floor((H - BH) / 2) + 28
  R.bottleSkin = "solo"
  R.drawBottle(b, bx, by, t, false)
  R.bottleSkin = "game"

  local real = SPR.clipboard and SPR.clipboardTall and SPR.doctorBox
  local pw = 72
  local lx = bx - 88
  if real then
    g.setColor(1, 1, 1)
    g.draw(SPR.clipboard, lx, by - 40)
    text("TOP", lx + 10, by - 26, PAL.ink)
    textRight(("%07d"):format(topScore or 0), lx + 62, by - 14, PAL.ink)
    text("SCORE", lx + 10, by + 2, PAL.ink)
    textRight(("%07d"):format(b.score), lx + 62, by + 14, PAL.ink)
  else
    clipboard(lx + 4, by, pw, 42)
    text("TOP", lx + 8, by + 4, PAL.ink)
    textRight(("%07d"):format(topScore or 0), lx + pw, by + 13, PAL.ink)
    text("SCORE", lx + 8, by + 24, PAL.ink)
    textRight(("%07d"):format(b.score), lx + pw, by + 33, PAL.ink)
  end
  lens(bx - 48, by + 84, 40, t, b)

  local rx = bx + 80
  if SPR.logoSmall then
    g.setColor(1, 1, 1)
    g.draw(SPR.logoSmall, bx + 68, by - 68)
  else
    text("DR. MARIO", rx, by - 18, PAL.clip)
  end
  -- the doctor in his box. He holds the next capsule up in his hand; during the pause
  -- before it enters play he throws it, and it flies from his hand into the neck.
  local boxX, boxY, boxW, boxH
  if real then
    boxX, boxY, boxW, boxH = bx + 92, by - 40, 56, 56
    g.setColor(1, 1, 1)
    g.draw(SPR.doctorBox, boxX, boxY)
  else
    boxX, boxY, boxW, boxH = rx + 14, by - 2, 46, 54
    rect(PAL.ink, boxX, boxY, boxW + 4, boxH + 4)
    g.setColor(PAL.clip)
    g.rectangle("fill", boxX - 2, boxY - 2, boxW + 4, boxH + 4, 6, 6)
    g.setColor(PAL.black)
    g.rectangle("fill", boxX, boxY, boxW, boxH, 5, 5)
  end

  local poses = SPR.doctorPoses
  local throwing = b.state == "spawn" and b.spawnTimer > 0 and #b.pendingGarbage == 0
  local pose = (b.state == "dead") and "shrug" or (throwing and "throw" or "hold")
  local img = poses and poses[pose] or SPR.doctor
  local iw, ih = img:getDimensions()
  local scale = (iw <= 16) and 2 or 1
  local dw, dh = iw * scale, ih * scale
  local dx = boxX + math.floor((boxW - dw) / 2)
  local dy = boxY + boxH - dh - 2
  g.setColor(1, 1, 1)
  g.draw(img, dx, dy, 0, scale, scale)

  if b.state ~= "dead" then
    local capX, capY
    if poses then
      -- hand positions measured on the 40x40 frames
      local holdX, holdY = dx + 16, dy + 3
      local throwX, throwY = dx + 16, dy + 16
      if throwing then
        local p = 1 - b.spawnTimer / math.max(1, Board.spawnDelay)
        local sx, sy = throwX - 8, throwY - 4
        local ex, ey = bx + 3 * CELL, by - 14
        capX = sx + (ex - sx) * p
        capY = sy + (ey - sy) * p - math.sin(p * math.pi) * 18
      else
        capX, capY = holdX - 14, holdY - 9
      end
    else
      capX, capY = dx + dw - 4, dy - 6
    end
    drawHalf(math.floor(capX), math.floor(capY), b.nextPair[1], "left")
    drawHalf(math.floor(capX) + CELL, math.floor(capY), b.nextPair[2], "right")
  end

  if real then
    local cx, cy = bx + 88, by + 24
    g.setColor(1, 1, 1)
    g.draw(SPR.clipboardTall, cx, cy)
    text("LEVEL", cx + 10, cy + 14, PAL.ink)
    textRight(("%2d"):format(b.level), cx + 54, cy + 26, PAL.ink)
    text("SPEED", cx + 10, cy + 42, PAL.ink)
    textRight(SPEED_NAME[b.speed], cx + 54, cy + 54, PAL.ink)
    text("VIRUS", cx + 10, cy + 70, PAL.ink)
    textRight(("%2d"):format(b.viruses), cx + 54, cy + 82, PAL.ink)
  else
    clipboard(rx, by + 66, pw, 62)
    text("LEVEL", rx + 4, by + 70, PAL.ink)
    textRight(("%2d"):format(b.level), rx + pw - 6, by + 79, PAL.ink)
    text("SPEED", rx + 4, by + 90, PAL.ink)
    textRight(SPEED_NAME[b.speed], rx + pw - 6, by + 99, PAL.ink)
    text("VIRUS", rx + 4, by + 110, PAL.ink)
    textRight(("%2d"):format(b.viruses), rx + pw - 6, by + 119, PAL.ink)
  end
  return bx, by
end

function R.drawSideInfo(b, p, bx, extra)
  local y = 194
  text(("%dP"):format(p), bx, y, PAL.yellow)
  text(("%7d"):format(b.score), bx + 20, y, PAL.white)
  if extra then text(extra, bx, y + 12, PAL.white) end
  if #b.pendingGarbage > 0 then text(("IN %d"):format(#b.pendingGarbage), bx, y + 24, PAL.red) end
end

-------------------------------------------------------------------------------
-- screens (all take a region {x, y, w, h})
-------------------------------------------------------------------------------
-- The pause panel: a black card with a heart beside whichever line is picked. Drawn
-- into each seat's own region so it reads the right way up from either end, and sized
-- to its longest line so nothing runs off a 128-wide seat.
function R.drawPause(region, items, sel)
  local rx, ry, rw, rh = region[1], region[2], region[3], region[4]
  local HEART = 11
  local itemW = 0
  for _, s in ipairs(items) do itemW = math.max(itemW, R.font:getWidth(s)) end
  local w = math.min(rw - 6, itemW + HEART + 20)
  local rowH = 13
  local h = 24 + #items * rowH
  local x = rx + math.floor((rw - w) / 2)
  local y = ry + math.floor((rh - h) / 2)
  g.setColor(0, 0, 0, 0.72)
  g.rectangle("fill", rx, ry, rw, rh)
  pill(x, y, w, h, 8)
  textCenter("PAUSED", { x, y, w, h }, 6, PAL.logoText)
  rect(PAL.logoText, x + 10, y + 17, w - 20, 1)
  local left = x + math.floor((w - (HEART + itemW)) / 2) + HEART
  for i, s in ipairs(items) do
    local iy = y + 22 + (i - 1) * rowH
    if i == sel then sprite("heart", left - HEART, iy - 1) end
    text(s, left, iy, i == sel and PAL.white or PAL.panel)
  end
  return y + h
end

function R.drawOverlay(region, title, sub)
  local w = math.min(region[3] - 8, 120)
  local h = sub and 30 or 18
  local x = region[1] + math.floor((region[3] - w) / 2)
  local y = region[2] + math.floor(region[4] / 2) - math.floor(h / 2)
  box(x, y, w, h)
  textCenter(title, region, y - region[2] + 5, PAL.ink)
  if sub then textCenter(sub, region, y - region[2] + 17, PAL.ink) end
end

function R.drawMessage(region, title, sub)
  textCenter(title, region, math.floor(region[4] / 2) - 10, PAL.white)
  if sub then textCenter(sub, region, math.floor(region[4] / 2) + 4, PAL.panel) end
end

-- Title: capsule logo over the green checkerboard, black pill menu underneath.
-- sel: 1 = 1 PLAYER GAME, 2 = 2 PLAYER GAME (where the heart sits)
-- page: 0 = menu, 1 = high scores (main.lua flips it on a timer)
function R.drawTitle(region, credits, freePlay, t, scores, sel, page)
  page = page or 0
  local rx, ry, rw, rh = region[1], region[2], region[3], region[4]
  local vs = rh / 160 -- vertical stretch for taller regions

  -- logo capsule: the real one if sprites/logo.png exists, else drawn
  local logoImg = SPR.logo
  if logoImg and logoImg:getWidth() > rw - 8 and SPR.logoHalf then logoImg = SPR.logoHalf end
  local realLogo = logoImg and logoImg:getWidth() <= rw - 8
  local lh = realLogo and logoImg:getHeight() or 36

  -- the menu pill's size is needed first: the spare height is split between the two
  local wide = rw >= 200
  local tiny = rw < 140          -- 128-wide strip: no icons in the pill
  local pw = wide and 190 or math.min(rw - 4, 156)
  local showScores = page == 1 and scores
  -- the score panel is taller: it holds all five entries with room to breathe
  local ph = showScores and (18 + math.min(#scores, 5) * 12) or (wide and 56 or 68)
  local slack = math.max(0, rh - lh - ph)
  local ly = ry + math.floor(slack * 0.30)
  local px = rx + math.floor((rw - pw) / 2)
  local py = ry + rh - ph - math.floor(slack * 0.25)

  if realLogo then
    local lw = logoImg:getWidth()
    g.setColor(1, 1, 1)
    g.draw(logoImg, rx + math.floor((rw - lw) / 2), ly)
  else
    local lw = math.min(rw - 16, 200)
    lh = 36
    local lx = rx + math.floor((rw - lw) / 2)
    g.setColor(PAL.black)
    g.rectangle("fill", lx + 2, ly + 3, lw, lh, lh / 2, lh / 2)
    g.setColor(PAL.logoBlue)
    g.rectangle("fill", lx, ly, lw, lh, lh / 2, lh / 2)
    g.setColor(PAL.logoPink)
    g.rectangle("fill", lx + lw / 2, ly, lw / 2, lh, lh / 2, lh / 2)
    g.rectangle("fill", lx + lw / 2, ly, 4, lh)
    g.setColor(PAL.white)
    g.rectangle("fill", lx + 14, ly + 5, lw - 28, 2)
    local title = "DR. MARIO"
    local scale = (R.font:getWidth(title) * 2 <= lw - 16) and 2 or 1
    local tw = R.font:getWidth(title) * scale
    local tx, ty = lx + math.floor((lw - tw) / 2), ly + math.floor((lh - 7 * scale) / 2)
    text(title, tx + scale, ty + scale, PAL.black, scale)
    text(title, tx, ty, PAL.logoText, scale)
  end

  -- menu pill, laid out like the NES one: doctor left, heart cursor, three text rows,
  -- virus bottom right. Narrow seats (under 200 px) get a squeezed version.
  pill(px, py, pw, ph, 18)
  local credit = freePlay and "FREE PLAY" or ("CREDITS %d"):format(credits)
  text(credit, rx + rw - R.font:getWidth(credit) - 6, ry + 4, PAL.panel)
  if page == 0 or not scores then
    local row = (sel or 1) - 1
    local frame = (math.floor(t * 2) % 2) + 1
    local items = { "1 PLAYER GAME", "2 PLAYER GAME", "VS COMPUTER" }
    local itemW = 0
    for _, s in ipairs(items) do itemW = math.max(itemW, R.font:getWidth(s)) end
    local HEART = 11                      -- gutter the cursor sits in
    local copyA, copyB, gap = "@1996", "JIMTENDO", 8
    local copyW = R.font:getWidth(copyA) + gap + R.font:getWidth(copyB)

    -- the icons take the outer edges; everything else is centred in what is left
    local inL, inR = px + 4, px + pw - 4
    if not tiny then
      local docImg = SPR.titleDoctor and SPR.titleDoctor[frame] or SPR.doctor
      local dw, dh = docImg:getDimensions()
      g.setColor(1, 1, 1)
      g.draw(docImg, px + 4, py + math.floor((ph - dh) / 2))
      inL = px + 6 + dw
      local v = SPR.titleVirus and SPR.titleVirus[frame]
      if v then
        local vw, vh = v:getDimensions()
        g.setColor(1, 1, 1)
        g.draw(v, px + pw - vw - 6, py + math.floor((ph - vh) / 2))
        inR = px + pw - vw - 8
      end
    end

    local span = inR - inL
    local rowH = 11
    local blockH = #items * rowH + 5 + 8
    local top = py + math.floor((ph - blockH) / 2)
    local mx = inL + math.floor((span - (HEART + itemW)) / 2) + HEART
    for i, s in ipairs(items) do text(s, mx, top + (i - 1) * rowH, PAL.white) end
    sprite("heart", mx - HEART, top + row * rowH)
    local cx = inL + math.floor((span - copyW) / 2)
    local cy = top + #items * rowH + 5
    text(copyA, cx, cy, PAL.white)
    text(copyB, cx + R.font:getWidth(copyA) + gap, cy, PAL.orange)
  else
    -- Columns, not one padded string: the font is not monospaced, so a space (3px) and
    -- a digit (5px) would let the ranks, scores and levels drift apart.
    local shown = math.min(#scores, 5)
    local rowH = 12
    local top0 = py + 5
    textCenter("TOP DOCTORS", { px, py, pw, ph }, 5, PAL.logoText)
    rect(PAL.logoText, px + 14, top0 + 9, pw - 28, 1)
    local rowW = 110
    local left = px + math.floor((pw - rowW) / 2)
    for i = 1, shown do
      local e = scores[i]
      local y = top0 + 14 + (i - 1) * rowH
      textRight(("%d."):format(i), left + 16, y, PAL.panel)
      textRight(("%d"):format(e.score), left + 72, y, PAL.white)
      text("LV", left + 78, y, PAL.panel)
      textRight(("%d"):format(e.level), left + rowW, y, PAL.white)
    end
  end

  -- a few viruses wandering between logo and menu
  local band = py - (ly + lh)
  if band > 20 then
    for i = 0, 3 do
      local x = rx + 20 + i * math.floor((rw - 48) / 3) + math.floor(math.sin(t * 1.5 + i) * 4)
      local y = ly + lh + math.floor(band / 2) - 4 + math.floor(math.cos(t * 2 + i * 1.3) * 3)
      drawVirus(x, y, Board.COLORS[i % 3 + 1], t)
    end
  end
end

-- Mode select: the NES options panel. Both players' markers are on one panel,
-- so each player sees the same thing from their own seat.
-- sel = { mode = "solo"|"versus", settings = {p1, p2}, cursor = {row1, row2}, musicType = "fever"|"chill"|"off" }
local ROW_LEVEL, ROW_SPEED, ROW_MUSIC = 1, 2, 3
local MUSIC_LABELS = { fever = "FEVER", chill = "CHILL", off = "OFF" }
local MUSIC_ORDER = { "fever", "chill", "off" }
R.MUSIC_ORDER = MUSIC_ORDER

-- Row labels: the sheet's own framed words, pink when that row is the one being changed
-- and a thin outline when it is not. The sprites carry the word, so the text offsets
-- (8,7 highlighted / 4,4 plain) put the lettering where the drawn version put it.
local LABEL_KEY = { [ROW_LEVEL] = "virus", [ROW_SPEED] = "speed", [ROW_MUSIC] = "music" }

local function label(str, key, x, y, highlighted)
  local set = SPR.labels and SPR.labels[key]
  local img = set and set[highlighted and "on" or "off"]
  if img then
    g.setColor(1, 1, 1)
    g.draw(img, x - (highlighted and 8 or 4), y - (highlighted and 7 or 4))
    return
  end
  local w = R.font:getWidth(str) + 8
  if highlighted then
    g.setColor(PAL.hilite)
    g.rectangle("fill", x - 4, y - 3, w, 13, 3, 3)
  else
    g.setColor(PAL.panel)
    g.rectangle("line", x - 3.5, y - 2.5, w - 1, 12, 2, 2)
  end
  text(str, x, y, PAL.white)
end

-- The level bar: 21 notches four pixels apart, the marker for each player above and below.
local function levelBar(bx, by, barW)
  if SPR.levelBar then
    g.setColor(1, 1, 1)
    g.draw(SPR.levelBar, bx, by - 3)
    return
  end
  rect(PAL.white, bx, by, barW + 1, 2)
  for i = 0, 20 do rect(PAL.white, bx + i * 4, by - (i % 5 == 0 and 3 or 1), 1, (i % 5 == 0 and 7 or 4)) end
end

-- marker: set "marks" (the narrow pair, for the bar) or "marksWide" (over a word)
local function marker(set, down, x, y)
  local pair = SPR[set]
  if pair then
    g.setColor(1, 1, 1)
    g.draw(pair[down and 1 or 2], x, y)
  else
    sprite(down and "triDown" or "triUp", x + 2, y)
  end
end

local function levelValue(x, y, value)
  if SPR.levelBox then
    g.setColor(1, 1, 1)
    g.draw(SPR.levelBox, x, y)
    text(("%02d"):format(value), x + 5, y + 5, PAL.white)
    return
  end
  g.setColor(PAL.green)
  g.rectangle("line", x + 0.5, y + 3.5, 24, 12, 2, 2)
  text(("%02d"):format(value), x + 4, y + 5, PAL.white)
end

function R.drawSelect(region, sel, t)
  local rx, ry, rw, rh = region[1], region[2], region[3], region[4]
  local panel = SPR.optionsPanel
  local px, py, pw, ph, tab
  if panel and rw >= panel:getWidth() + 8 and rh >= panel:getHeight() + 8 then
    pw, ph = panel:getWidth(), panel:getHeight()
    px, py = rx + math.floor((rw - pw) / 2), ry + math.floor((rh - ph) / 2)
    g.setColor(1, 1, 1)
    g.draw(panel, px, py)
    tab = true                       -- the mode name goes in the panel's raised tab
  else
    pw, ph = rw - 12, rh - 12
    px, py = rx + 6, ry + 6
    pill(px, py, pw, ph, 8)
  end
  local narrow = pw < 140       -- 128-wide strip: level boxes go under the bar
  local base = narrow and 176 or 148   -- the height the rows were laid out for
  local sy = tab and 1 or math.min(ph / base, 1.5)
  local top = tab and (py + 26) or (py + math.floor((ph - base * sy) / 2))
  local function Y(v) return top + math.floor(v * sy) end
  local versus = sel.mode == "versus"
  local rows = { false, false, false }
  for p = 1, (versus and 2 or 1) do rows[sel.cursor[p]] = true end
  local hint = rows[ROW_LEVEL] and ROW_LEVEL or (rows[ROW_SPEED] and ROW_SPEED or ROW_MUSIC)

  local cpu = sel.cpu and sel.cpu[2]
  local mode = cpu and "VS COMPUTER" or (versus and "2 PLAYER GAME" or "1 PLAYER GAME")
  if tab then
    text(mode, px + 36 + math.floor((134 - R.font:getWidth(mode)) / 2), py + 6, PAL.white)
  else
    textCenter(mode, region, Y(5) - ry, PAL.white)
  end

  -- virus level
  local barW = 84
  local left = narrow and (px + 10) or (px + math.floor((pw - (barW + 56)) / 2))
  label("VIRUS LEVEL", "virus", left, Y(tab and 6 or 20), rows[ROW_LEVEL])
  local bx, by = left + 18, Y(tab and 32 or 44)
  text("1P", left, by - 6, PAL.white)
  if versus then text(cpu and "CP" or "2P", left, by + 3, cpu and PAL.orange or PAL.white) end
  levelBar(bx, by, barW)
  marker("marks", true, bx + sel.settings[1].level * 4 - 3, by - 8)
  if versus then marker("marks", false, bx + sel.settings[2].level * 4 - 3, by + 3) end
  for p = 1, (versus and 2 or 1) do
    local boxX, yy
    if narrow then
      boxX, yy = bx + 8 + (p - 1) * 44, by + 14
    else
      boxX, yy = bx + barW + 8, by - 12 + (p - 1) * 22
    end
    levelValue(boxX, yy, sel.settings[p].level)
  end

  -- speed
  local speedRow = narrow and 90 or 68
  label("SPEED", "speed", left, Y(speedRow), rows[ROW_SPEED])
  local sy0 = Y(speedRow + 22)
  text("1P", left, sy0 - 6, PAL.white)
  if versus then text(cpu and "CP" or "2P", left, sy0 + 3, cpu and PAL.orange or PAL.white) end
  local optX = narrow and { bx, bx + 32, bx + 64 } or { bx + 4, bx + 40, bx + 76 }
  for i, name in ipairs({ "low", "med", "hi" }) do
    text(SPEED_NAME[name], optX[i], sy0, PAL.white)
    local cx = optX[i] + math.floor(R.font:getWidth(SPEED_NAME[name]) / 2) - 10
    if sel.settings[1].speed == name then marker("marksWide", true, cx, sy0 - 8) end
    if versus and sel.settings[2].speed == name then marker("marksWide", false, cx, sy0 + 9) end
  end

  -- music type: the sheet's framed words where there is room, else the plain words
  -- with the same orange frame drawn round whichever one is chosen.
  local musicRow = narrow and 134 or 116
  label("MUSIC TYPE", "music", left, Y(musicRow), rows[ROW_MUSIC])
  local my = Y(musicRow + 22)
  local boxes = SPR.optBoxes
  local slots = { 52, 53, 39 }
  if boxes and not narrow and left + 144 > px + pw then boxes = nil end
  if boxes then
    -- a 128-wide seat has no room for three framed words in a row: stack them instead
    for i, name in ipairs(MUSIC_ORDER) do
      local str = MUSIC_LABELS[name]
      local mxx = narrow and left or (left + (i == 1 and 0 or (i == 2 and slots[1] or slots[1] + slots[2])))
      local myy = narrow and (my + (i - 1) * 11) or my
      if sel.musicType == name then
        g.setColor(1, 1, 1)
        g.draw(boxes[i], mxx, myy - 5)
      else
        text(str, mxx + math.floor((slots[i] - R.font:getWidth(str)) / 2), myy, PAL.white)
      end
    end
  else
    local mx = narrow and { left + 4, left + 46, left + 88 } or { bx, bx + 48, bx + 96 }
    for i, name in ipairs(MUSIC_ORDER) do
      local str = MUSIC_LABELS[name]
      if sel.musicType == name then
        g.setColor(PAL.orange)
        g.rectangle("line", mx[i] - 3.5, my - 3.5, R.font:getWidth(str) + 7, 14, 1, 1)
        g.rectangle("line", mx[i] - 2.5, my - 2.5, R.font:getWidth(str) + 5, 12, 1, 1)
      end
      text(str, mx[i], my, PAL.white)
    end
  end

  if math.floor(t * 2) % 2 == 0 then
    text("START", px + pw - 48, py + ph - 14, PAL.orange)
  end
  return hint
end

return R
