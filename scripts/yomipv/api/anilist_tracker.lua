--[[ AniList episode tracker ]]

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")
local StringOps = require("lib.string_ops")
local Player = require("lib.player")
local Platform = require("lib.platform")

local AnilistTracker = {}

function AnilistTracker.init(config, anilist)
	AnilistTracker.config = config
	AnilistTracker.anilist = anilist
	AnilistTracker.has_updated = false
	AnilistTracker.threshold_percent = config.anilist_update_thresh_percent or 80

	mp.add_key_binding(config.key_anilist_auth or "Ctrl+a", "yomipv-anilist-auth", function()
		AnilistTracker.spawn_auth_terminal()
	end)

	if not config.anilist_enabled or config.anilist_token == "" then
		return
	end

	mp.register_event("file-loaded", function()
		AnilistTracker.has_updated = false
	end)

	mp.observe_property("percent-pos", "number", function(_, percent_pos)
		if not percent_pos or AnilistTracker.has_updated then
			return
		end

		if percent_pos >= AnilistTracker.threshold_percent then
			AnilistTracker:trigger_update()
		end
	end)
end

function AnilistTracker.spawn_auth_terminal()
	local conf_path = mp.command_native({ "expand-path", "~~/script-opts/yomipv.conf" })
	local root_dir = mp.get_script_directory()

	if Platform.IS_WINDOWS then
		local script_path = Platform.normalize_path(utils.join_path(root_dir, "export/auth_anilist.ps1"))
		local args = { "cmd", "/c", "start", "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
			script_path, conf_path }

		msg.info("Starting AniList auth terminal via PowerShell")
		mp.command_native_async(
			{ name = "subprocess", playback_only = false, detach = true, args = args },
			function() end
		)
	else
		local script_path = Platform.normalize_path(utils.join_path(root_dir, "export/auth_anilist.sh"))
		local chmod_args = { name = "subprocess", playback_only = false, args = { "chmod", "+x", script_path } }
		mp.command_native_async(chmod_args, function()
			local args
			if Platform.IS_MACOS then
				args = { "open", "-a", "Terminal.app", script_path, "--args", conf_path }
			else
				args = { "x-terminal-emulator", "-e", script_path, conf_path }
			end

			msg.info("Starting AniList auth terminal via bash")
			mp.command_native_async({ name = "subprocess", playback_only = false, detach = true, args = args }, function() end)
		end)
	end

	Player.notify("AniList setup started", "info", 5)
end

function AnilistTracker:trigger_update()
	self.has_updated = true

	local title = mp.get_property("media-title", "")
	local path = mp.get_property("path", "")

	local name = StringOps.clean_title(title, path)
	local season_num, episode_num = StringOps.parse_season_episode(title, path)

	if not name or name == "" then
		msg.warn("AniList Tracker: Could not extract anime title from file.")
		return
	end

	if not episode_num then
		msg.info("AniList Tracker: No episode number found, defaulting to 1 (likely a movie/special).")
		episode_num = 1
	end

	self.anilist:check_and_update(name, season_num, episode_num, function(success, err)
		if success then
			local msg_text = string.format("AniList: Updated %s to Ep %s", name, tostring(episode_num))
			if self.config.anilist_show_notifications then
				Player.notify(msg_text, "success", 3)
			end
			msg.info(msg_text)
		else
			msg.warn("AniList error: " .. tostring(err))
		end
	end)
end

return AnilistTracker
