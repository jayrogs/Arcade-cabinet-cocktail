-- Teaching the cabinet its own panel. It asks for one control at a time, watches which
-- button you press, and writes what it learns where the emulator reads it. Everything
-- it shows is live, so a button that does nothing here is not wired.
local g = love.graphics
local font
local GLYPH_ORDER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,-:<>!?/'#@"
local HOME = os.getenv("HOME") or "."
local DEVICE = "3H Dual Arcade 3H Dual Arcade"
local OUT = HOME .. "/.config/retroarch/autoconfig/udev/" .. DEVICE .. ".cfg"
-- The made-up panel on the web page is a real stick as far as this is concerned, and
-- learning from it would write the CABINET's settings from buttons that are not the
-- cabinet's. So it is ignored here, and this says so on screen when it is all there is.
local WEBPANEL = "Cab Web Panel"
local taught                       -- which panel actually taught us

local function realPanels()
  local out = {}
  for _, js in ipairs(love.joystick.getJoysticks()) do
    if js:getName():sub(1, #WEBPANEL) ~= WEBPANEL then out[#out + 1] = js end
  end
  return out
end

local STEPS = {
  { key = "select", label = "ADD A CREDIT", note = "THE COIN BUTTON" },
  { key = "start",  label = "START A GAME", note = "THE 1 PLAYER BUTTON" },
  { key = "b",      label = "FIRE",         note = "THE FIRST BUTTON" },
  { key = "a",      label = "FIRE TWO",     note = "THE SECOND BUTTON" },
  { key = "y",      label = "FIRE THREE",   note = "THE THIRD BUTTON" },
  { key = "x",      label = "FIRE FOUR",    note = "SKIP IF YOU HAVE ONLY THREE" },
}
local step, learned, saved, held = 1, {}, 0, {}
local skipTimer = 0
local watch = false            -- just show what the panel sends, teach nothing
local seen = {}                -- every button seen so far, per panel, in the order pressed
local seenSet = {}

function love.load(args)
  for _, a in ipairs(args or {}) do if a == "--watch" then watch = true end end
  love.mouse.setVisible(false)
  font = g.newImageFont("font.png", GLYPH_ORDER)
  font:setFilter("nearest", "nearest")
  g.setFont(font)
  g.setLineStyle("rough")
end

local function save()
  local lines = {
    'input_driver = "udev"',
    ('input_device = "%s"'):format(DEVICE),
    'input_vendor_id = "5824"',
    'input_product_id = "30177"',
    'input_up_axis = "-1"',
    'input_down_axis = "+1"',
    'input_left_axis = "-0"',
    'input_right_axis = "+0"',
  }
  for _, s in ipairs(STEPS) do
    local b = learned[s.key]
    if b then lines[#lines + 1] = ('input_%s_btn = "%d"'):format(s.key, b) end
  end
  -- NO hotkey button here on purpose: RetroArch reserves whatever is named as the
  -- hotkey key, so the coin button would stop putting credits in. Leaving a game is a
  -- combination instead (coin and start together), set in retroarch.cfg.
  -- write it under the name of the panel that taught us, so one panel's buttons can
  -- never end up in another panel's file
  local name = taught and taught:getName() or DEVICE
  local out = HOME .. "/.config/retroarch/autoconfig/udev/" .. name .. ".cfg"
  lines[2] = ('input_device = "%s"'):format(name)
  if name ~= DEVICE then
    table.remove(lines, 4)         -- product id
    table.remove(lines, 3)         -- vendor id, both belong to the cabinet's own panel
  end
  local f = io.open(out, "w")
  if f then
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
    saved = 2.5
  end
end

local function bigText(s, y, scale, color)
  g.setColor(color or { 1, 1, 1 })
  g.print(s, math.floor(g.getWidth() / 2 - font:getWidth(s) * scale / 2), math.floor(y), 0, scale, scale)
end

local function drawLive(y)
  local sticks = love.joystick.getJoysticks()
  bigText(("PANELS FOUND: %d"):format(#sticks), y, 2, { 0.5, 0.7, 1 })
  y = y + 28
  for i, js in ipairs(sticks) do
    local down = {}
    for b = 1, js:getButtonCount() do
      if js:isDown(b) then down[#down + 1] = tostring(b) end
    end
    for a = 1, math.min(2, js:getAxisCount()) do
      local v = js:getAxis(a)
      if v < -0.5 then down[#down + 1] = (a == 1) and "LEFT" or "UP" end
      if v > 0.5 then down[#down + 1] = (a == 1) and "RIGHT" or "DOWN" end
    end
    seen[i] = seen[i] or {}
    seenSet[i] = seenSet[i] or {}
    for _, name in ipairs(down) do
      if not seenSet[i][name] then
        seenSet[i][name] = true
        seen[i][#seen[i] + 1] = name
      end
    end
    bigText(("PANEL %d NOW: %s"):format(i, #down > 0 and table.concat(down, " ") or "-"), y, 2)
    y = y + 24
    local list = table.concat(seen[i], " ")
    if #list > 34 then list = list:sub(-34) end
    bigText(("  PRESSED SO FAR: %s"):format(list ~= "" and list or "-"), y, 2, { 0.2, 1, 0.3 })
    y = y + 28
  end
  return y
end

function love.draw()
  local W, H = g.getDimensions()
  g.clear(0, 0, 0)
  if watch then
    bigText("PRESS ANYTHING", 60, 3, { 1, 0.8, 0.1 })
    bigText("AND SEE WHAT IT SENDS", 100, 2)
    drawLive(H / 2 - 120)
    bigText("HOLD A DIRECTION 3 SECONDS", H - 90, 2, { 0.6, 0.6, 0.7 })
    bigText("TO GO BACK", H - 66, 2, { 0.6, 0.6, 0.7 })
    return
  end
  if step > #STEPS then
    bigText("ALL SET", H / 2 - 60, 4, { 1, 0.8, 0.1 })
    bigText("THE EMULATOR NOW KNOWS", H / 2 + 10, 2)
    bigText("YOUR PANEL", H / 2 + 34, 2)
    if saved > 0 then bigText("SAVED", H / 2 + 80, 3, { 0.2, 1, 0.3 }) end
    return
  end
  local s = STEPS[step]
  bigText(("STEP %d OF %d"):format(step, #STEPS), 60, 2, { 0.6, 0.6, 0.7 })
  bigText("PRESS THE BUTTON THAT", H / 2 - 120, 2)
  bigText(s.label, H / 2 - 88, 4, { 1, 0.8, 0.1 })
  bigText(s.note, H / 2 - 40, 2, { 0.6, 0.6, 0.7 })

  -- everything the sticks are sending, right now
  local y = H / 2 + 20
  local sticks = love.joystick.getJoysticks()
  bigText(("STICKS FOUND: %d"):format(#sticks), y, 2, { 0.5, 0.7, 1 })
  y = y + 26
  for i, js in ipairs(sticks) do
    local down = {}
    for b = 1, js:getButtonCount() do
      if js:isDown(b) then down[#down + 1] = tostring(b) end
    end
    local ax = {}
    for a = 1, math.min(2, js:getAxisCount()) do
      local v = js:getAxis(a)
      if math.abs(v) > 0.5 then ax[#ax + 1] = (a == 1 and "LEFT-RIGHT" or "UP-DOWN") end
    end
    bigText(("PANEL %d: %s"):format(i, (#down > 0 or #ax > 0)
      and (table.concat(down, " ") .. " " .. table.concat(ax, " ")) or "-"), y, 2)
    y = y + 24
  end
  -- the warning goes UNDER the panel lines, in its own empty space, never on top of them
  if #realPanels() == 0 then
    bigText("THE PANEL IS NOT PLUGGED IN", y + 16, 2, { 1, 0.5, 0.3 })
    bigText("NOTHING CAN BE LEARNED YET", y + 40, 2, { 1, 0.5, 0.3 })
  end
  local so_far = {}
  for _, st in ipairs(STEPS) do
    if learned[st.key] then so_far[#so_far + 1] = ("%s=%d"):format(st.label:sub(1, 5), learned[st.key] + 1) end
  end
  if #so_far > 0 then bigText(table.concat(so_far, "  "), H - 120, 2, { 0.2, 1, 0.3 }) end
  bigText("A BUTTON CAN DO MORE THAN ONE JOB", H - 90, 2, { 0.6, 0.6, 0.7 })
  bigText("HOLD A DIRECTION 2 SECONDS TO SKIP", H - 66, 2, { 0.6, 0.6, 0.7 })
end

function love.update(dt)
  if watch then
    local pushing = false
    for _, js in ipairs(love.joystick.getJoysticks()) do
      for a = 1, math.min(2, js:getAxisCount()) do
        if math.abs(js:getAxis(a)) > 0.5 then pushing = true end
      end
    end
    skipTimer = pushing and (skipTimer + dt) or 0
    if skipTimer > 3 then love.event.quit(0) end
    return
  end
  if saved > 0 then
    saved = saved - dt
    if saved <= 0 then love.event.quit(0) end
    return
  end
  if step > #STEPS then return end

  -- a held direction skips a control you have not got
  local pushing = false
  for _, js in ipairs(love.joystick.getJoysticks()) do
    for a = 1, math.min(2, js:getAxisCount()) do
      if math.abs(js:getAxis(a)) > 0.5 then pushing = true end
    end
  end
  if pushing then
    skipTimer = skipTimer + dt
    if skipTimer > 2 then
      step = step + 1
      skipTimer = 0
      if step > #STEPS then save() end
      return
    end
  else
    skipTimer = 0
  end

  for _, js in ipairs(realPanels()) do
    for b = 1, js:getButtonCount() do
      local id = tostring(js) .. b
      if js:isDown(b) then
        if not held[id] then
          held[id] = true
          -- the same button may do several jobs: on a small panel one button often
          -- puts the credit in AND starts the game AND fires
          taught = js
          learned[STEPS[step].key] = b - 1       -- the emulator counts from zero
          step = step + 1
          if step > #STEPS then save() end
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
end
