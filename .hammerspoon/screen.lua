-- Print all screens
-- for key,value in pairs(hs.screen.allScreens()) do
--   print(value)
-- end

-- Create a new 'Screen space'
function add_screen()
hs.osascript.applescript([[
do shell script "open -a 'Mission Control'"
delay 0.5
tell application "System Events" to
    click (every button whose value of attribute "AXDescription" is "add desktop")
      of UI element "Spaces Bar" of UI element 1 of group 1 of process "Dock"
delay 0.5
do shell script "open -a 'Mission Control'"
]])
end

-- Remove the current 'Screen space'
-- function remove_screen()
-- hs.osascript.applescript([[
-- do shell script "open -a 'Mission Control'"
-- delay 0.5
-- tell application "System Events" to
--     click (every button whose value of attribute "AXDescription" is "add desktop")
--       of UI element "Spaces Bar" of UI element 1 of group 1 of process "Dock"
-- delay 0.5
-- do shell script "open -a 'Mission Control'"
-- ]])
-- end

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "N", add_screen)
