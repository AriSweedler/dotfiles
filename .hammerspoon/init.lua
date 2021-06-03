-- Author: Ari Sweedler

-- TODO get a lua linter/prettifier
require "easy-reload"
require "nethack-movement"

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "E", function()
  hs.alert.show("Hello World!")
end)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "H", function()
  local win = hs.window.focusedWindow()
  local f = win:frame()

  f.x = f.x - 10
  win:setFrame(f)
end)
