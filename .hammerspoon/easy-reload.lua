-- Easy config reloading copied from
-- https://github.com/S1ngS1ng/HammerSpoon/blob/master/init.lua
-- -----------------------------------------------------------------------
--                            ** For Debug **                           --
-- -----------------------------------------------------------------------
function reloadConfig(files)
  local doReload = false
  for _,file in pairs(files) do
    if file:sub(-4) == ".lua" then
      doReload = true
    end
  end
  if doReload then
    hs.reload()
    hs.alert.show('Config Reloaded')
  end
end
-- hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()

-- Well, sometimes auto-reload is not working
hs.hotkey.bind({"cmd", "shift", "alt"}, "R", function()
  hs.reload()
end)
hs.alert.show("Config loaded")
