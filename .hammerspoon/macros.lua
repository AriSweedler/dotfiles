local hyper = {"cmd", "alt", "ctrl", "shift"}

-- Send a key press - but just with more convenient syntax
--
-- I could make the keypress syntax an actual DSL (with Vim semantics - like
-- <C-x> and stuff), that may be worth it another day. And just translate the
-- DSL into these eventtap calls
local function keypress(mod_table, key, count)
  count = count or 1
  for _ = 1, count do
    hs.eventtap.keyStroke(mod_table, key, 10)
  end
end

-- Type in '$XDG_DATA_ROOT' with a single keystroke
hs.hotkey.bind(hyper, "x", function()
  hs.eventtap.keyStrokes("$XDG_DATA_HOME/")
  keypress({}, "tab")
end)

--------------------------------------------------------------------------------
------------------------------ macros for illumio ------------------------------
--------------------------------------------------------------------------------
-- Expecting 'https://jira.illum.io/browse/EYE-107591' on the clipboard. Will
-- end with 'EYE-107591'. Works well for pasting into slack (maintains link)
hs.hotkey.bind(hyper, "j", function()
  keypress({"cmd"}, "v")
  keypress({"alt"}, "left", 3)
  keypress({"alt", "shift"}, "left", 10)
  keypress({}, "delete")
  keypress({"alt"}, "right", 3)
end)

-- Expecting 'https://stash.ilabs.io/projects/EYE/repos/ventools-PR-6' on the
-- clipboard. Will end with 'ventools-PR-6'. Works well for pasting into slack
-- (maintains link)
function is_hit_pr()
  local s, e = string.find(hs.pasteboard.getContents(), "hawkeye")
  if s == nil then return false end
  local s, e = string.find(hs.pasteboard.getContents(), "hit")
  if s == nil then return false end
  return true
end
-- https://stash.ilabs.io/projects/EYE/repos/hawkeye-hit/pull-requests/61/overview
hs.hotkey.bind(hyper, "p", function()
  keypress({"cmd"}, "v")
  hs.timer.usleep(10000)
  keypress({"alt"}, "delete", 2)
  keypress({"alt"}, "left")
  keypress({"alt"}, "delete", 5)
  hs.eventtap.keyStrokes("-PR-")
  keypress({"alt"}, "left", 4)
  keypress({"alt", "shift"}, "left", 14)
  if is_hit_pr() then
    keypress({"alt", "shift"}, "left", 2)
  end
  keypress({}, "delete")
  keypress({"alt"}, "right", 5)
end)

-- When you add a zoom meeting to an Outlook email, it makes this huge long
-- text. I don't like that. I want to delete everything but the relevant part
-- (The link. And the text "Ari is inviting you to a meeting")
hs.hotkey.bind(hyper, "z", function()
  keypress({}, "return")
  keypress({"shift", "cmd"}, "down", 4)
  keypress({}, "delete", 2)
  keypress({"cmd"}, "left")
  keypress({}, "up", 4)
  keypress({}, "delete", 10)
  keypress({}, "-")
  keypress({}, "return")
  keypress({}, "up", 2)
end)
