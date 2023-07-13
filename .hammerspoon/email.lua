local hyper = {"cmd", "alt", "ctrl", "shift"}
-- Use 'hyper+@' to print my email
hs.hotkey.bind(hyper, "2", function()
  hs.eventtap.keyStrokes("ari@sweedler.com")
end)

-- And also... For work...
-- Use 'hyper+3' to print my email
hs.hotkey.bind(hyper, "3", function()
  hs.eventtap.keyStrokes("ari.sweedler@illumio.com")
end)
