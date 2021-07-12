-- hs.application.frontmostApplication()

local key_app = {
C = "Calendar",
F = "Firefox",
I = "Signal",
M = "Messages",
S = "Spotify",
T = "Terminal",
}

application_select = {"cmd", "alt"}
for key, app in pairs(key_app) do
  hs.hotkey.bind(application_select, key, function()
    hs.application.launchOrFocus(app)
  end)
end
