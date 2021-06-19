local listener = hs.noises.new(function(num)
  hs.alert.show("noise detected")
  hs.alert.show(num)
end)

listener:start()
