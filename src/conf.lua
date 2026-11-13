function love.conf(t)
  t.identity = "chessing"
  t.window.title = "Chessing"
  t.window.width = 640
  t.window.height = 480
  t.window.resizable = true
  t.window.fullscreen = true
  t.window.fullscreentype = "desktop"
  t.window.vsync = 1
  t.modules.physics = false
  t.modules.video = false
  t.modules.touch = false
end
