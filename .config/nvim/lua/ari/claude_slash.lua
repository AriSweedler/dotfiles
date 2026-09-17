-- Claude Code's bundled skills and builtin slash commands, for highlighting /name in
-- prompt buffers. They live inside the claude binary, not on disk, and its minified
-- constants resolve ambiguously, so the one reliable listing is the stream-json init
-- message of a print-mode run: this asks the binary itself. --bare never reads the
-- keychain or the network and runs no hooks, so the probe is offline, free and ~0.7 s.
-- It misses only skills gated on a login (schedule, artifact-*) or on the TUI/MCP
-- (keybindings-help, claude-in-chrome).
--
-- The list is cached per binary (realpath + size) and read back synchronously: a buffer
-- load costs one stat and one small file read. The probe runs only after a Claude Code
-- update, in the background, and re-highlights when it lands.
local M = {}

local cache_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "claude_slash_commands")

local names = nil
local probing = false

local function binary()
	local exe = vim.fn.exepath("claude")
	if exe == "" then
		return nil
	end
	local real = vim.uv.fs_realpath(exe) or exe
	local stat = vim.uv.fs_stat(real)
	if not stat then
		return nil
	end
	return real, stat.size
end

-- npm installs keep one path across versions, hence the size in the key.
local function cache_file(real, size)
	local key = vim.fn.sha256(real .. "\0" .. size):sub(1, 8)
	return vim.fs.joinpath(cache_dir, vim.fs.basename(real) .. "-" .. key .. ".txt")
end

local function read_set(path)
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		return nil
	end
	local set = {}
	for _, line in ipairs(lines) do
		if line ~= "" then
			set[line] = true
		end
	end
	return set
end

-- Any other file in the dir belongs to a binary that is gone.
local function write_list(path, list)
	vim.fn.mkdir(cache_dir, "p")
	for name, kind in vim.fs.dir(cache_dir) do
		if kind == "file" and name ~= vim.fs.basename(path) then
			os.remove(vim.fs.joinpath(cache_dir, name))
		end
	end
	vim.fn.writefile(list, path)
end

-- The init line comes first; the lines after it are the unauthenticated turn.
local function parse_init(stdout)
	for line in stdout:gmatch("[^\n]+") do
		local ok, msg = pcall(vim.json.decode, line)
		if ok and type(msg) == "table" and msg.type == "system" and msg.subtype == "init" then
			local set = {}
			for _, field in ipairs({ "slash_commands", "skills" }) do
				for _, name in ipairs(msg[field] or {}) do
					set[name] = true
				end
			end
			local list = vim.tbl_keys(set)
			table.sort(list)
			return list
		end
	end
	return nil
end

-- Set of known names; empty until a cache exists for the current binary.
function M.names()
	if names then
		return names
	end
	names = {}
	local real, size = binary()
	if real then
		names = read_set(cache_file(real, size)) or names
	end
	return names
end

-- Probes when the current binary has no cache. on_ready fires on the main loop once
-- the names are in; a warm cache never fires it.
function M.ensure(on_ready)
	local real, size = binary()
	if not real or probing then
		return
	end
	local path = cache_file(real, size)
	if vim.uv.fs_stat(path) then
		return
	end
	probing = true
	-- stdin defaults to /dev/null, which claude takes as instant EOF; a pipe makes it
	-- wait 3 s for input first.
	vim.system(
		{ real, "-p", "--bare", "--output-format", "stream-json", "--verbose", "/version" },
		{ text = true, timeout = 20000 },
		function(result)
			probing = false
			local list = parse_init(result.stdout or "")
			if not list then
				return
			end
			vim.schedule(function()
				write_list(path, list)
				names = {}
				for _, name in ipairs(list) do
					names[name] = true
				end
				on_ready()
			end)
		end
	)
end

return M
