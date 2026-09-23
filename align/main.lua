-- Lining the picture up with the monitor. This monitor does not show everything it is
-- sent, so the picture is made smaller until all of it lands on the glass. Left and
-- right do that, and by default the height follows the width so nothing gets stretched
-- out of shape. Button 2 goes round the three jobs: SIZE, STRETCH (width and height
-- apart, for filling the glass at the cost of the shape) and SLIDE.
local g = love.graphics
local font
local GLYPH_ORDER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,-:<>!?/'#@"
local HOME = os.getenv("HOME") or "."
local CONF = HOME .. "/screen.conf"

local padX, padY, nudgeX, nudgeY = 0, 0, 0, 0
local mode = "size"          -- "size" (keeps the shape) | "stretch" | "slide"
local held, repeatTimer = {}, 0
local saved = 0

local STEPS = { 0, 20, 40, 60, 80, 100 }
local COLORS = {
  { 1, 1, 1 }, { 1, 0.3, 0.3 }, { 1, 0.8, 0.1 },
  { 0.2, 1, 0.3 }, { 0.3, 0.7, 1 }, { 1, 0.4, 1 },
}

local function load()
  local f = io.open(CONF, "r")
  if not f then return end
  for line in f:lines() do
    local k, v = line:match("^(%w+)%s*=%s*(-?%d+)")
    v = tonumber(v)
    if k == "padX" then padX = v end
    if k == "padY" then padY = v end
    if k == "nudgeX" then nudgeX = v end
    if k == "nudgeY" then nudgeY = v end
    if k == "overscan" then padX, padY = v, v end
  end
  f:close()
end

local function save()
  local f = io.open(CONF, "w")
  if not f then return end
  f:write(("padX = %d\npadY = %d\nnudgeX = %d\nnudgeY = %d\n"):format(padX, padY, nudgeX, nudgeY))
  f:close()
  saved = 1.6
end

function love.load()
  love.mouse.setVisible(false)
  font = g.newImageFont("font.png", GLYPH_ORDER)
  font:setFilter("nearest", "nearest")
  g.setFont(font)
  g.setLineStyle("rough")
  load()
end

local function bigText(s, x, y, scale)
  g.print(s, math.floor(x), math.floor(y), 0, scale, scale)
end

function love.draw()
  local W, H = g.getDimensions()
  g.clear(0, 0, 0)
  local x0, y0 = padX + nudgeX, padY + nudgeY
  local w, h = W - padX * 2, H - padY * 2

  for i = #STEPS, 1, -1 do
    local dx, dy = STEPS[i] * (w / W), STEPS[i] * (h / H)
    g.setColor(COLORS[i])
    g.setLineWidth(6)
    g.rectangle("line", x0 + dx + 3, y0 + dy + 3, w - dx * 2 - 6, h - dy * 2 - 6)
  end
  g.setLineWidth(1)

  g.setColor(1, 1, 1)
  local jobs = {
    size = { "NOW SETTING: SIZE", "STICK LEFT AND RIGHT",
             "THE SHAPE STAYS RIGHT" },
    stretch = { "NOW SETTING: STRETCH", "LEFT-RIGHT WIDTH, UP-DOWN HEIGHT",
                "FILLS MORE GLASS, SHAPE GOES OFF" },
    slide = { "NOW SETTING: WHERE IT SITS", "PUSH THE STICK ANY WAY",
              "TO CENTRE IT ON THE GLASS" },
  }
  local job = jobs[mode]
  local lines = {
    "GROW THE WHITE BOX UNTIL IT",
    "JUST FITS ON THE GLASS",
    "",
    job[1], job[2], job[3],
    "",
    ("WIDTH %d PER CENT    HEIGHT %d PER CENT"):format(
      math.floor((w / W) * 100 + 0.5), math.floor((h / H) * 100 + 0.5)),
    ("ACROSS %d    DOWN %d"):format(nudgeX, nudgeY),
    "",
    "BUTTON 2 FOR THE NEXT JOB",
    "BUTTON 3 STARTS OVER",
    "BUTTON 1 KEEPS IT",
  }
  for i, s in ipairs(lines) do
    bigText(s, W / 2 - font:getWidth(s) * 2 / 2, H / 2 - 150 + (i - 1) * 22, 2)
  end
  if saved > 0 then
    g.setColor(1, 0.8, 0.1)
    local s = "SAVED"
    bigText(s, W / 2 - font:getWidth(s) * 3 / 2, H / 2 + 170, 3)
  end
end

local function stick()
  local dx, dy = 0, 0
  for _, js in ipairs(love.joystick.getJoysticks()) do
    local x = js:getAxisCount() >= 1 and js:getAxis(1) or 0
    local y = js:getAxisCount() >= 2 and js:getAxis(2) or 0
    if x < -0.5 then dx = -1 elseif x > 0.5 then dx = 1 end
    if y < -0.5 then dy = -1 elseif y > 0.5 then dy = 1 end
  end
  if love.keyboard.isDown("left") then dx = -1 end
  if love.keyboard.isDown("right") then dx = 1 end
  if love.keyboard.isDown("up") then dy = -1 end
  if love.keyboard.isDown("down") then dy = 1 end
  return dx, dy
end

function love.update(dt)
  if saved > 0 then
    saved = saved - dt
    if saved <= 0 then love.event.quit(0) end
    return
  end
  local dx, dy = stick()
  if dx ~= 0 or dy ~= 0 then
    repeatTimer = repeatTimer - dt
    if repeatTimer <= 0 then
      local W, H = g.getDimensions()
      if mode == "size" then
        -- one control, and the height follows so the picture keeps its shape
        padX = math.max(0, math.min(W * 0.35, padX - dx * 2))
        padY = math.floor(padX * (H / W))
      elseif mode == "stretch" then
        padX = math.max(0, math.min(W * 0.35, padX - dx * 2))
        padY = math.max(0, math.min(H * 0.35, padY - dy * 2))
      else
        nudgeX = math.max(-200, math.min(200, nudgeX + dx * 2))
        nudgeY = math.max(-200, math.min(200, nudgeY + dy * 2))
      end
      repeatTimer = 0.04
    end
  else
    repeatTimer = 0
  end
  for _, js in ipairs(love.joystick.getJoysticks()) do
    for b = 1, math.min(10, js:getButtonCount()) do
      local id = tostring(js) .. b
      if js:isDown(b) then
        if not held[id] then
          held[id] = true
          if b == 2 then
            mode = (mode == "size") and "stretch" or ((mode == "stretch") and "slide" or "size")
          elseif b == 3 then padX, padY, nudgeX, nudgeY = 0, 0, 0, 0
          else save() end
          return
        end
      else
        held[id] = nil
      end
    end
  end
end

function love.keypressed(key)
  if key == "escape" then love.event.quit(0) end
  if key == "tab" then mode = (mode == "size") and "move" or "size" end
  if key == "return" or key == "space" then save() end
end
