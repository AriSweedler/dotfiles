native_panel = "ok"
emoji_mod = {"command", "control"}
emoji_key = "\\"
-- Add a keyboard shortcut to reload
hs.hotkey.bind(emoji_mod, emoji_key, function()
  hs.alert.show("Hello you want emojis?")
end)
