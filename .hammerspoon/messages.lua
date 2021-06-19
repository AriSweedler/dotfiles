local msg = "Hello from Ari"
hs.hotkey.bind({"cmd", "shift", "alt"}, "M", function()
  hs.messages.iMessage("ari@sweedler.com", msg)
  -- hs.messages.SMS("+14083178058", xxx)
end)
