function love.conf(t)
  t.identity = "cabflap"
  t.window.title = "Flap"
  t.window.width = 384
  t.window.height = 512
  t.window.resizable = true
  t.window.vsync = 1
  t.modules.physics = false
end
