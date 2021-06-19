-- hs.application.frontmostApplication()

hs.hotkey.bind({"cmd", "shift", "alt"}, "F", function()
  hs.application.launchOrFocus("Firefox")
end)

hs.hotkey.bind({"cmd", "shift", "alt"}, "T", function()
  hs.application.launchOrFocus("Terminal")
end)
