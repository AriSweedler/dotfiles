-- Getters
local function get_volume()
  return hs.audiodevice.defaultOutputDevice():outputVolume()
end
local function get_bright()
  -- Pretend brightness is on a scale of 0 to 100 instead of 0 to 1
  return hs.screen.mainScreen():getBrightness() * 100
end

-- Setters
local function set_volume(value)
  if (value < 0) then
    value = 0
  end
  hs.audiodevice.defaultOutputDevice():setVolume(value)
  msg = string.format("Volume set to: %3.2f", value)
  hs.alert.show(msg)
end
local function set_bright(value)
  if (value < 0) then
    value = 1
  end
  -- We pretend brightness is on a scale of 0 to 100 instead of 0 to 1
  hs.screen.mainScreen():setBrightness(value / 100)
  msg = string.format("Brightness set to: %.2f", value)
  hs.alert.show(msg)
end

--- Define the "words" in our "DSL"
volume = "V"
bright = "B"
k_abs = "command"
k_up = "shift"
down =     {"ctrl", "alt"}
abs_down = {k_abs, "ctrl", "alt"}
up =       {k_up, "ctrl", "alt"}
abs_up =   {k_abs, k_up, "ctrl", "alt"}
local function hot(key, mod, func)
  hs.hotkey.bind(mod, key, func)
end

-- All the capabilities
hot(volume, down, function() set_volume(get_volume() - 5) end)
hot(bright, down, function() set_bright(get_bright() - 5) end)
hot(volume, up,   function() set_volume(get_volume() + 5) end)
hot(bright, up,   function() set_bright(get_bright() + 5) end)
hot(volume, abs_down, function() set_volume(0)   end)
hot(bright, abs_down, function() set_bright(1)   end)
hot(volume, abs_up,   function() set_volume(100) end)
hot(bright, abs_up,   function() set_bright(100) end)
