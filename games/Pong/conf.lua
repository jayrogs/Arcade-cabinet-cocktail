function love.conf(t)
  t.identity = "cabpong"
  t.window.title = "Pong"
  t.window.width = 384
  t.window.height = 512
  t.window.resizable = true
  t.window.vsync = 1
  t.modules.physics = false
end
