-- Set the active screen's brightness
function get_bright()
  return hs.screen.mainScreen():getBrightness()
end
function bright(value)
  if (value < 0) then
    value = 0.01
  end
  hs.screen.mainScreen():setBrightness(value)
  msg = string.format("Brightness set to: %.2f", value)
  hs.alert.show(msg)
end

hs.hotkey.bind({"cmd", "alt", "shift"}, "V", function()
  bright(0.01)
end)
hs.hotkey.bind({"cmd", "alt"}, "V", function()
  bright(get_bright() - 0.05)
end)
hs.hotkey.bind({"cmd", "alt", "shift"}, "B", function()
  bright(1)
end)
hs.hotkey.bind({"cmd", "alt"}, "B", function()
  bright(get_bright() + 0.05)
end)
