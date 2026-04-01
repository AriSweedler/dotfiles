local M = {}

local HYDRA_PREFIX = "Hydra: "

local function refresh_lualine()
	if package.loaded['lualine'] then
		require('lualine').refresh()
	end
end

local function validate(cfg)
	for _, head in ipairs(cfg.heads) do
		local key = head[1]
		if key == "q" or key == "<Esc>" then
			error("Hydra config cannot contain 'q' or '<Esc>' keys - these are managed by the hydra loader")
		end
	end
end

local function inject_standard_heads(cfg)
	table.insert(cfg.heads, { "q", nil, { exit = true, nowait = true, desc = "Quit" } })
	table.insert(cfg.heads, { "<Esc>", nil, { exit = true, nowait = true, desc = false } })
	table.insert(cfg.heads, {
		"<Enter>",
		function()
			refresh_lualine()
			print(cfg.name)
		end,
		{ desc = false },
	})
end

local function prefix_descs(cfg)
	for _, head in ipairs(cfg.heads) do
		local opts = head[3]
		if opts and opts.desc and not opts.desc:match("^" .. HYDRA_PREFIX) then
			opts.desc = HYDRA_PREFIX .. opts.desc
		end
	end
end

local function configure_hint(cfg)
	if not cfg.config then cfg.config = {} end
	cfg.config.hint = {
		type = "window",
		position = "bottom",
		offset = 0,
		float_opts = { border = "rounded" },
	}
	local hint_lines = { cfg.name .. ":" }
	for _, head in ipairs(cfg.heads) do
		local key, _, opts = head[1], head[2], head[3]
		if opts and opts.desc and opts.desc ~= false then
			local desc = opts.desc:gsub("^" .. HYDRA_PREFIX, "")
			table.insert(hint_lines, string.format("  _%s_: %s", key, desc))
		end
	end
	cfg.hint = table.concat(hint_lines, "\n")
end

local function wrap_on_exit(cfg)
	local original = cfg.on_exit
	cfg.on_exit = function()
		if original then original() end
		refresh_lualine()
	end
end

--- Transform a raw hydra config table and register it.
--- @param cfg table Raw hydra config with name, body, heads, etc.
local function load_config(cfg)
	if not cfg or not cfg.heads then return end
	validate(cfg)
	inject_standard_heads(cfg)
	prefix_descs(cfg)
	configure_hint(cfg)
	wrap_on_exit(cfg)
	require("hydra")(cfg)
	return { body = cfg.body, name = cfg.name }
end

--- Load all hydra configs from lua/ari/hydra/configs/.
--- Returns a list of { body, name } for each registered hydra.
function M.setup()
	local registered = {}
	local hydra_dir = vim.fn.stdpath("config") .. "/lua/ari/hydra/configs"
	for _, file in ipairs(vim.fn.glob(hydra_dir .. "/*.lua", true, true)) do
		local module = "ari.hydra.configs." .. file:match("([^/]+)%.lua$")
		local info = load_config(require(module))
		if info then
			table.insert(registered, info)
		end
	end
	return registered
end

--- Show all registered hydra modes.
function M.help(registered)
	local lines = { "Available Hydra modes:" }
	for _, mapping in ipairs(registered) do
		table.insert(lines, "  " .. mapping.body .. " -> " .. mapping.name)
	end
	vim.notify(table.concat(lines, "\n"))
end

return M
