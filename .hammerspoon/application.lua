-- hs.application.frontmostApplication()

local key_app = {
T = "Terminal",
F = "Firefox",
C = "Calendar",
-- M = "Messages",
S = "Signal",
}

for key, app in pairs(key_app) do
  hs.hotkey.bind({"cmd", "alt"}, key, function()
    hs.application.launchOrFocus(app)
  end)
end
