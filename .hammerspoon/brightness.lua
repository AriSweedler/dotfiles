-- Set the active screen's brightness
function bright(value)
  hs.screen.mainScreen():setBrightness(value)
end

hs.hotkey.bind({"cmd", "shift", "alt"}, "V", function()
  bright(0.01)
end)

hs.hotkey.bind({"cmd", "shift", "alt"}, "B", function()
  bright(1)
end)
