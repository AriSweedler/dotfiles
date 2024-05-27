local function prepend_to_package_path(runtimedir)
	package.path = runtimedir .. "/?/init.lua;" .. package.path
	package.path = runtimedir .. "/?.lua;" .. package.path
end

local local_runtime = os.getenv("HOME") .. "/.local/share/hammerspoon/site"
prepend_to_package_path(local_runtime)

hs.pathwatcher.new(local_runtime, ReloadConfig):start()

if local_runtime then
	require("ari_local")
	hs.alert.show("Local config loaded")
end
