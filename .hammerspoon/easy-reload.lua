-- Easy config reloading copied from
-- https://github.com/S1ngS1ng/HammerSpoon/blob/master/init.lua
-- -----------------------------------------------------------------------
--                            ** For Debug **                           --
-- -----------------------------------------------------------------------
local function reloadConfig(files)
  local doReload = false
  for _,file in pairs(files) do
    if file:sub(-4) == ".lua" then
      doReload = true
    end
  end
  if doReload then
    hs.reload()
  end
end
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()

-- Add a keyboard shortcut to reload
local hyper = {"cmd", "shift", "alt", "ctrl"}
hs.hotkey.bind(hyper, "R", function()
  hs.reload()
end)

-- Send an alert when we're reloaded
hs.alert.show('Config loaded')
