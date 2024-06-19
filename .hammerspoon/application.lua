-- hs.application.frontmostApplication()

local key_app = {
	F = "Firefox",
	M = "Messages",
	S = "Spotify",
	T = "Terminal",
}

local application_select = { "cmd", "alt" }
for key, app in pairs(key_app) do
	hs.hotkey.bind(application_select, key, function()
		hs.application.launchOrFocus(app)
	end)
end
