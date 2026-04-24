--[[ Profile system for switching named configuration sets ]]

local mp = require("mp")
local msg = require("mp.msg")

local Profiles = {}

-- Keys excluded from profile overwrites
local SKIP_KEYS = {
	current_profile = true,
	key_cycle_profile = true,
}

-- Read key-value pairs from .conf file
local function read_conf(path)
	local result = {}
	local file = io.open(path, "r")
	if not file then return nil end
	for line in file:lines() do
		-- Strip comments and blank lines
		local clean = line:match("^%s*([^#]-)%s*$")
		if clean and clean ~= "" then
			local key, val = clean:match("^([%w_]+)%s*=%s*(.-)%s*$")
			if key and val then
				result[key] = val
			end
		end
	end
	file:close()
	return result
end

-- Coerce string value to default type
local function coerce(raw, default)
	local t = type(default)
	if t == "boolean" then
		return raw == "yes" or raw == "true" or raw == "1"
	elseif t == "number" then
		return tonumber(raw) or default
	else
		return raw
	end
end

-- Apply configuration map to live table
local function apply_conf(config, conf_map, defaults)
	for key, raw_val in pairs(conf_map) do
		if not SKIP_KEYS[key] and defaults[key] ~= nil then
			config[key] = coerce(raw_val, defaults[key])
		end
	end
end

-- Locate script-opts directory
local function get_opts_dir()
	local path = mp.find_config_file("script-opts/yomipv.conf")
	if path then
		return path:match("^(.*[/\\])")
	end
	-- Fallback path expansion
	local expanded = mp.command_native({ "expand-path", "~~/script-opts/" })
	return expanded
end

-- List profiles from yomipv_*.conf files
function Profiles.list(opts_dir)
	local profiles = {}
	local dir = opts_dir or get_opts_dir()
	if not dir then return profiles end

	-- Use mpv utils to list directory
	local utils = require("mp.utils")
	local entries = utils.readdir(dir, "files")
	if not entries then return profiles end

	for _, fname in ipairs(entries) do
		local name = fname:match("^yomipv_(.+)%.conf$")
		if name and name ~= "" then
			table.insert(profiles, name)
		end
	end

	table.sort(profiles)
	return profiles
end

-- Load named profile into live table
function Profiles.load(name, config, defaults)
	local dir = get_opts_dir()
	if not dir then
		return false, "Cannot locate script-opts directory"
	end

	-- Reset to script defaults first
	for k, v in pairs(defaults) do
		if not SKIP_KEYS[k] then
			config[k] = v
		end
	end

	-- Apply base configuration (yomipv.conf)
	local base_path = dir .. "yomipv.conf"
	local base_map = read_conf(base_path)
	if base_map then
		apply_conf(config, base_map, defaults)
	end

	if name == "default" then
		config.current_profile = "default"
		msg.info("Loaded base profile (yomipv.conf)")
		return true
	end

	local path = dir .. "yomipv_" .. name .. ".conf"
	local conf_map = read_conf(path)
	if not conf_map then
		return false, "Profile file not found: " .. path
	end

	apply_conf(config, conf_map, defaults)
	config.current_profile = name
	msg.info("Loaded profile: " .. name .. " from " .. path)
	return true
end

-- Cycle through available profiles
function Profiles.cycle(config, defaults)
	local dir = get_opts_dir()
	local available = Profiles.list(dir)

	local all = { "default" }
	for _, p in ipairs(available) do
		table.insert(all, p)
	end

	if #all <= 1 then
		return nil, "No additional profiles found"
	end

	local current = config.current_profile or "default"
	local next_idx = 1

	for i, name in ipairs(all) do
		if name == current then
			next_idx = (i % #all) + 1
			break
		end
	end

	local next_name = all[next_idx]
	local ok, err = Profiles.load(next_name, config, defaults)
	if ok then
		return next_name
	else
		return nil, err
	end
end

-- Create profile from current configuration
function Profiles.create(name, config)
	local dir = get_opts_dir()
	if not dir then return false, "Cannot locate script-opts directory" end
	local path = dir .. "yomipv_" .. name .. ".conf"

	local file = io.open(path, "w")
	if not file then return false, "Failed to create file" end

	file:write("# Yomipv Profile: " .. name .. "\n")
	for k, v in pairs(config) do
		if type(v) ~= "function" and type(v) ~= "table" and not SKIP_KEYS[k] then
			local val_str = type(v) == "boolean" and (v and "yes" or "no") or tostring(v)
			file:write(k .. "=" .. val_str .. "\n")
		end
	end
	file:close()
	return true
end

-- Delete profile file
function Profiles.delete(name)
	if name == "default" then return false, "Cannot delete default profile" end
	local dir = get_opts_dir()
	if not dir then return false, "Cannot locate script-opts directory" end
	local path = dir .. "yomipv_" .. name .. ".conf"

	local success, err = os.remove(path)
	return success, err
end

return Profiles
