--[[ Updater                                     ]]
--[[ GitHub release checking and update launcher ]]

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")
local Player = require("lib.player")
local Platform = require("lib.platform")

local Updater = {}

function Updater.version_to_number(v)
	if not v then return 0 end
	local v_clean = v:gsub("^v", "")
	local major, minor, patch = v_clean:match("(%d+)%.(%d+)%.(%d+)")
	if major and minor and patch then
		return tonumber(major) * 1000000 + tonumber(minor) * 1000 + tonumber(patch)
	end
	return 0
end

function Updater.check_for_updates(config, current_version, Curl)
	if not config.updater_enabled or not config.updater_check_on_startup then
		return
	end

	msg.info("Checking for updates in background...")
	local api_url = "https://api.github.com/repos/BrenoAqua/Yomipv/releases/latest"

	Curl.get(api_url, function(success, output, err)
		if not success or not output or output.status ~= 0 then
			msg.warn("Background update check failed: " .. tostring(err or "Unknown error"))
			return
		end

		local response = utils.parse_json(output.stdout)
		if not response or not response.tag_name then
			msg.warn("Failed to parse GitHub release data")
			return
		end

		local latest_version = response.tag_name
		if Updater.version_to_number(latest_version) > Updater.version_to_number(current_version) then
			msg.info("New version available: " .. latest_version)
			Player.notify(
				string.format("New Yomipv update available: %s (Press '%s' to update)", latest_version, config.key_update),
				"info",
				15
			)
		else
			msg.info("Yomipv is up to date")
		end
	end, { user_agent = "Yomipv-Updater-Bot" })
end

function Updater.launch(config)
	if not config.updater_enabled then
		return
	end

	local script_dir = mp.get_script_directory()
	local root_dir = utils.join_path(script_dir, "../../")
	local args

	if Platform.IS_WINDOWS then
		local updater_path = Platform.normalize_path(utils.join_path(root_dir, "yomipv-updater.bat"))
		-- Escalate privileges on Windows to allow file replacement in restricted directories
		args = { "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
			"Start-Process", '"' .. updater_path .. '"', "-Verb", "RunAs" }
	else
		local updater_path = utils.join_path(root_dir, "yomipv-updater.sh")
		mp.command_native_async({
			name = "subprocess",
			playback_only = false,
			args = { "chmod", "+x", updater_path },
		}, function()
			mp.command_native_async({
				name = "subprocess",
				playback_only = false,
				detach = true,
				args = { "/bin/bash", updater_path },
			}, function(success, _result, err)
				if not success then
					msg.error("Failed to launch updater: " .. tostring(err))
					Player.notify("Failed to launch updater", "error")
				end
			end)
		end)
		msg.info("Launching updater: " .. updater_path)
		Player.notify("Checking for updates...", "info", 5)
		return
	end

	local updater_path = Platform.normalize_path(utils.join_path(root_dir, "yomipv-updater.bat"))
	msg.info("Launching updater: " .. updater_path)
	Player.notify("Checking for updates...", "info", 5)

	mp.command_native_async({
		name = "subprocess",
		playback_only = false,
		detach = true,
		args = args,
	}, function(success, _result, err)
		if not success then
			msg.error("Failed to launch updater: " .. tostring(err))
			Player.notify("Failed to launch updater", "error")
		end
	end)
end

return Updater
