local hyper = {"cmd", "alt", "ctrl", "shift"}

-- Take a log like
--
--    PREAMBLE LEVEL:: Logtext and such | structured_data=values
--
-- And use 'hyper+v' to visually highlight the logtext. Works in vim normal
-- mode and tmux copy mode
hs.hotkey.bind(hyper, "v", function()
  hs.eventtap.keyStrokes("0f|")
  hs.eventtap.keyStroke({}, "left", 10)
  hs.eventtap.keyStroke({}, "left", 10)
  hs.eventtap.keyStrokes("vF:")
  hs.eventtap.keyStroke({}, "right", 10)
  hs.eventtap.keyStroke({}, "right", 10)
end)
