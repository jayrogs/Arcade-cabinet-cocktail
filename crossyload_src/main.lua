-- A loading screen for Crossy Road. The game takes a minute or more to get going and shows
-- only black while it does; this sits on top until the launcher sees it is ready.
local g = love.graphics
local pic, big, t = nil, nil, 0

function love.load()
  love.mouse.setVisible(false)
  g.setDefaultFilter("nearest", "nearest")
  pic = g.newImage("pic.png")
  big = g.newFont(40)
end

function love.update(dt) t = t + dt end

function love.draw()
  local W, H = g.getDimensions()
  g.clear(0.05, 0.07, 0.12)
  local s = math.floor(math.min(W * 0.8 / pic:getWidth(), H * 0.72 / pic:getHeight()))
  local pw, ph = pic:getWidth() * s, pic:getHeight() * s
  local py = H * 0.40 - ph / 2
  g.setColor(1, 1, 1)
  g.draw(pic, (W - pw) / 2, py, 0, s, s)
  -- a chicken-hop bar: three blocks that take turns jumping
  local y = py + ph + 60
  for i = 0, 2 do
    local phase = (t * 2.2 - i * 0.33) % 1
    local hop = phase < 0.5 and math.sin(phase * 2 * math.pi) * 18 or 0
    g.setColor(0.98, 0.98, 0.98)
    g.rectangle("fill", W / 2 - 70 + i * 50, y - hop, 30, 30)
  end
  g.setFont(big)
  g.setColor(1, 1, 1, 0.9)
  g.printf("LOADING", 0, y + 60, W, "center")
end

function love.keypressed(k) if k == "escape" then love.event.quit() end end
