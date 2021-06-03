local movement_keys = {Y = {x = -10, y = -10},
                       K = {x = 0,   y = -10},
                       U = {x = 10,  y = -10},
                       H = {x = -10, y = 0},
                       L = {x = 10,  y = 0},
                       B = {x = -10, y = 10},
                       J = {x = 0,   y = 10},
                       N = {x = 10,  y = 10}}

local function makeMovementBinding(key, movement)
  local cb = function()
    local win = hs.window.focusedWindow()
    local f = win:frame()

    f.x = f.x + movement.x
    f.y = f.y + movement.y
    win:setFrame(f)
  end
  hs.hotkey.bind({"cmd", "alt", "ctrl"}, key, cb)
end

for key, movement in pairs(movement_keys) do
  makeMovementBinding(key, movement)
end

