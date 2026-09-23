function love.conf(t)
  t.identity = "cabmenu"
  t.window.title = "Arcade Cabinet"
  t.window.width = 1024
  t.window.height = 1280
  t.window.fullscreen = true
  t.window.fullscreentype = "desktop"
  t.window.borderless = true
  t.window.resizable = true
  t.window.vsync = 1
  t.modules.physics = false
end
