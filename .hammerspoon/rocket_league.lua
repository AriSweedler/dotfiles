-- Define an array of possible chat messages
local messages = {
  "Great pass!",
  "Nice shot!",
  "What a save!",
  "Thanks!",
  "Wow!",
  "OMG!",
  "No problem.",
  "All yours.",
  "In position.",
  "Defending.",
  "Take the shot!",
  "Need boost!",
  "Go for it!",
  "Centering.",
  "I got it!",
  "On your left.",
  "On your right.",
  "Incoming!",
  "Sorry!",
  "Close one!",
  "Good game!",
  "Rematch!",
  ":)",
  ":(",
  "Nice one!",
  "Siiiick!",
  "Whew.",
  "Noooo!",
  "Okay.",
  "Oops.",
  "Wow! (Again.)",
  "Crap!",
  "Nice moves.",
  "One more game?",
  "What a play!",
  "gg",
  "gg ez",
  "ez",
  "ff",
  "Forfeit!"
}

-- Define the keybinding
local hyper = {"cmd", "alt", "ctrl", "shift"}
hs.hotkey.bind(hyper, "S", function()
  -- Repeat the loop three times
  for i = 1, 3 do
    -- Select a random message from the array
    local message = messages[math.random(#messages)]

    -- Send the message with a literal Enter key press
    hs.eventtap.keyStrokes(message)
    hs.eventtap.keyStroke({}, "return", 2)
  end
end)
