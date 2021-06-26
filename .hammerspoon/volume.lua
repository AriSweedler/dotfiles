-- Set the system volume
function get_volume()
  return hs.audiodevice.defaultOutputDevice():outputVolume()
end
function volume(value)
  if (value < 0) then
    value = 0.01
  end
  hs.audiodevice.defaultOutputDevice():setVolume(value)
  msg = string.format("Volume set to: %3.2f", value)
  hs.alert.show(msg)
end

hs.hotkey.bind({"cmd", "shift", "alt"}, "N", function()
  volume(0)
end)
hs.hotkey.bind({"cmd", "ctrl", "alt"}, "N", function()
  volume(30)
end)
hs.hotkey.bind({"cmd", "alt"}, "N", function()
  volume(get_volume() - 5)
end)

hs.hotkey.bind({"cmd", "shift", "alt"}, "M", function()
  volume(100)
end)
hs.hotkey.bind({"cmd", "ctrl", "alt"}, "M", function()
  volume(70)
end)
hs.hotkey.bind({"cmd", "alt"}, "M", function()
  volume(get_volume() + 5)
end)

-- TODO
-- 3 operations:
-- * absolute extreme
-- * absolute mid
-- * incremental change
--
-- 2 directions:
-- * Up
-- * Down
--
-- And generate the keybindings from there for:
-- [get_]volume()
-- [get_]brightness()
