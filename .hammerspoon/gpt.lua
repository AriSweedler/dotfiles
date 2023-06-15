-- Helper function to generate the strings we wish to add to the prompt
function gptPromptLTEWords(numWords)
  return "Answer in less than or equal to " .. tostring(numWords) .. " words"
end

-- Define a table that maps key codes to argument values
local keyBindings = {
  ["0"] = gptPromptLTEWords(100)
  ,["2"] = gptPromptLTEWords(20)
  ,[","] = gptPromptLTEWords(50)
  ,["-"] = "Answer in as few words as possible"
  ,["b"] = "Give me a bulleted list"
  ,["c"] = "Answer in one line of code"
}

-- Returns the name of the currently focused application
function getFocusedAppName()
  local app = hs.application.frontmostApplication()
  if app == nil then
    return "'no focus'"
  end
  return app:name()
end

-- Define a function that creates a hotkey binding for a given key code
function bindKeyCode(keyCode)
  hs.hotkey.bind({"cmd", "shift", "alt"}, keyCode, function()
    hs.eventtap.keyStrokes(keyBindings[keyCode])
  end)
end

-- Create hotkey bindings for each key code in the table
for keyCode, _ in pairs(keyBindings) do
  bindKeyCode(keyCode)
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Usage:
function IsMacGPTMenuBarItemFocused()
  -- TODO how to get what MenuBarItem is focused
  isMenuBarItemFocused("MacGPT")
end
--------------------------------------------------------------------------------

function table.filter(tbl, filterFunc)
  local out = {}
  for i,v in ipairs(tbl) do
    if filterFunc(v, i, tbl) then
      table.insert(out, v)
    end
  end
  return out
end

function doThing()
  local logger = hs.logger.new('myScript', 'info')

  local apps = hs.application.runningApplications()
  local macGPT_apps = table.filter(apps, function(app)
    return string.find(app:name(), "MacGPT")
  end)

  for _, app in ipairs(macGPT_apps) do
    logger.i(hs.inspect(app))
  end
end

function doThing()
  hs.alert.show("The application is: " .. getFocusedAppName())
  hs.alert.show("The menubaritem is: " .. getMenuBarItem())
end

hs.hotkey.bind({"cmd", "shift"}, "n", function()
  doThing()
end)

function tprint (tbl, indent)
  if not indent then indent = 0 end
  local toprint = string.rep(" ", indent) .. "{\r\n"
  indent = indent + 2
  for k, v in pairs(tbl) do
    toprint = toprint .. string.rep(" ", indent)
    if (type(k) == "number") then
      toprint = toprint .. "[" .. k .. "] = "
    elseif (type(k) == "string") then
      toprint = toprint  .. k ..  "= "
    end
    if (type(v) == "number") then
      toprint = toprint .. v .. ",\r\n"
    elseif (type(v) == "string") then
      toprint = toprint .. "\"" .. v .. "\",\r\n"
    elseif (type(v) == "table") then
      toprint = toprint .. tprint(v, indent + 2) .. ",\r\n"
    else
      toprint = toprint .. "\"" .. tostring(v) .. "\",\r\n"
    end
  end
  toprint = toprint .. string.rep(" ", indent-2) .. "}"
  return toprint
end
