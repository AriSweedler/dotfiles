local hyper = {"cmd", "alt", "ctrl", "shift"}

-- Expecting 'https://jira.illum.io/browse/EYE-107591' on the clipboard. Will
-- end with 'EYE-107591'. Works well for pasting into slack (maintains link)
hs.hotkey.bind(hyper, "j", function()
  hs.eventtap.keyStroke({"cmd"}, "v", 10)
  for _ = 1, 3 do hs.eventtap.keyStroke({"alt"}, "left", 10) end
  for _ = 1, 10 do hs.eventtap.keyStroke({"alt", "shift"}, "left", 10) end
  hs.eventtap.keyStroke({}, "delete", 10)
  for _ = 1, 3 do hs.eventtap.keyStroke({"alt"}, "right", 10) end
end)
