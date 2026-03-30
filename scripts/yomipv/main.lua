--[[ Yomipv | https://github.com/BrenoAqua/Yomipv ]]

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")

local yomipv_version = "0.3.6"
mp.commandv("script-message", "yomipv-version", yomipv_version)

local script_dir = mp.get_script_directory()
package.path = script_dir .. "/?.lua;" .. script_dir .. "/?/init.lua;" .. package.path

local config = require("options")
local Curl = require("lib.curl")
local Player = require("lib.player")
local Platform = require("lib.platform")
local Yomitan = require("api.yomitan")
local AnkiConnect = require("api.ankiconnect")
local Monitor = require("capture.monitor")
local Observer = require("subtitle.observer")
local SubtitleFilter = require("subtitle.subtitle_filter")
local SecondarySid = require("subtitle.secondary-sid")
local Selector = require("interface.selector.selector")
local History = require("interface.history.panel")
local Builder = require("export.builder")
local AnkiDBBuilder = require("export.anki_db_builder")
local Formatter = require("export.formatter")
local Handler = require("export.handler")
local Picture = require("media.picture")
local Audio = require("media.audio")

msg.info("Yomipv v" .. yomipv_version .. ": Initializing...")

local yomitan = Yomitan.new(config, Curl)
local anki = AnkiConnect.new(config, Curl)

Picture.init(config)
Audio.init(config)
Monitor.init(config)

local builder = Builder.new(config)
local formatter = Formatter.new(config)

local history = History:new()
history:init(config)

local handler = Handler:new()
handler.config = config
handler.deps = {
	tracker = Monitor,
	history = history,
	selector = Selector,
	yomitan = yomitan,
	anki = anki,
	media = {
		picture = Picture,
		audio = Audio,
		set_output_dir = function(dir)
			Picture.set_output_dir(dir)
			Audio.set_output_dir(dir)
		end,
	},
	builder = builder,
	formatter = formatter,
	curl = Curl,
}
handler:init()

history:set_exporter_handler(handler)
Observer.init(handler, yomitan, config)
Observer.start()
SecondarySid.init(config)
SubtitleFilter.init(config)

mp.register_event("file-loaded", function()
	yomitan:clear_cache()
end)

local function launch_lookup_app()
	local app_path = config.lookup_app_path
	if not app_path or app_path == "" then
		return
	end

	if not app_path:find(":") and not app_path:find("^/") then
		app_path = utils.join_path(mp.get_script_directory(), app_path)
	end

	msg.info("Launching lookup app from: " .. app_path)

	mp.command_native_async({
		name = "subprocess",
		playback_only = false,
		args = {
			Platform.get_curl_cmd(),
			"-s",
			"-o",
			Platform.get_null_device(),
			"--connect-timeout",
			"1",
			"http://127.0.0.1:19634/",
		},
	}, function(success, result, _error)
		if success and result.status == 0 then
			msg.info("Lookup app already running, skipping startup")
			return
		end
		local mpv_pid = utils.getpid()
		local ipc_pipe = mp.get_property("input-ipc-server")

		local function is_valid_pipe(pipe)
			return pipe and pipe ~= ""
		end

		if not is_valid_pipe(ipc_pipe) then
			if Platform.IS_WINDOWS then
				ipc_pipe = "\\\\.\\pipe\\yomipv-" .. mpv_pid
			elseif Platform.IS_MACOS or Platform.IS_LINUX then
				ipc_pipe = "/tmp/yomipv-" .. mpv_pid
			end
			mp.set_property("input-ipc-server", ipc_pipe)
		end

		local electron_ipc_pipe = ipc_pipe
		if Platform.IS_WINDOWS and not electron_ipc_pipe:match("^\\\\.\\pipe\\") then
			electron_ipc_pipe = "\\\\.\\pipe\\" .. electron_ipc_pipe
		end

		Platform.launch_electron_app(
			app_path,
			mpv_pid,
			electron_ipc_pipe,
			function(launch_success, _launch_result, launch_error)
				if not launch_success then
					msg.error("Failed to launch lookup app: " .. tostring(launch_error))
				else
					msg.info("Lookup app launch command sent")
				end
			end
		)
	end)
end

launch_lookup_app()

mp.add_key_binding(config.key_toggle_colorizer, "yomipv-toggle-colorizer", function()
	handler:toggle_colorizer()
end)

mp.add_key_binding(config.key_open_selector, "yomipv-export", function()
	msg.info("Key pressed: " .. config.key_open_selector)
	if not handler then
		msg.error("Handler not initialized!")
		return
	end
	handler:start_export(history)
end)

local selector_mouse_idle_start = mp.get_time()
local last_mouse_pos_x, last_mouse_pos_y = -1, -1

mp.add_periodic_timer(0.1, function()
	if not config.selector_trigger_on_mouse_move then
		selector_mouse_idle_start = mp.get_time()
		return
	end

	if Selector.active then
		selector_mouse_idle_start = mp.get_time()
		return
	end

	local current_time = mp.get_time()
	local mx, my = mp.get_mouse_pos()

	if last_mouse_pos_x ~= mx or last_mouse_pos_y ~= my then
		if last_mouse_pos_x ~= -1 and last_mouse_pos_y ~= -1 then
			local idle_time = current_time - selector_mouse_idle_start
			if idle_time >= config.selector_trigger_mouse_idle_time then
				msg.info("Mouse moved after idle, triggering selector")
				handler:start_export(history)
			end
		end
		last_mouse_pos_x = mx
		last_mouse_pos_y = my
		selector_mouse_idle_start = current_time
	end
end)

mp.add_key_binding(config.key_append_mode, "yomipv-toggle-append-mode", function()
	handler:toggle_mark_range()
end)

if config.selector_show_history then
	mp.add_key_binding(config.key_toggle_history, "yomipv-toggle-history", function()
		if history.active then
			history:close()
		else
			history:open()
		end
	end)
end

if config.key_toggle_picture_animated ~= "" then
	mp.add_key_binding(config.key_toggle_picture_animated, "yomipv-toggle-picture-animated", function()
		config.picture_animated = not config.picture_animated
		config.save("picture_animated", config.picture_animated)
		local status = config.picture_animated and "Enabled" or "Disabled"
		Player.notify("Animated pictures: " .. status, "info")
		if history and history.active then
			history:update(true)
		end
	end)
end

if config.key_toggle_mora_navigation ~= "" then
	mp.add_key_binding(config.key_toggle_mora_navigation, "yomipv-toggle-mora-navigation", function()
		config.selector_mora_navigation = not config.selector_mora_navigation
		config.save("selector_mora_navigation", config.selector_mora_navigation)
		local status = config.selector_mora_navigation and "Enabled" or "Disabled"
		Player.notify("Mora navigation: " .. status, "info")
		if Selector.active then
			Selector.style.selector_mora_navigation = config.selector_mora_navigation
			Selector:render()
		end
	end)
end

if config.key_toggle_selector_trigger_on_mouse_move ~= "" then
	mp.add_key_binding(
		config.key_toggle_selector_trigger_on_mouse_move,
		"yomipv-toggle-selector-trigger-on-mouse-move",
		function()
			config.selector_trigger_on_mouse_move = not config.selector_trigger_on_mouse_move
			config.save("selector_trigger_on_mouse_move", config.selector_trigger_on_mouse_move)
			local status = config.selector_trigger_on_mouse_move and "Enabled" or "Disabled"
			Player.notify("Selector mouse trigger: " .. status, "info")
		end
	)
end

if config.key_set_timing_start ~= "" then
	mp.add_key_binding(config.key_set_timing_start, "yomipv-set-timing-start", function()
		handler:set_manual_start()
	end)
end

if config.key_set_timing_end ~= "" then
	mp.add_key_binding(config.key_set_timing_end, "yomipv-set-timing-end", function()
		handler:set_manual_end()
	end)
end

if config.key_clear_timings ~= "" then
	mp.add_key_binding(config.key_clear_timings, "yomipv-clear-timings", function()
		handler:clear_manual_timings()
	end)
end

local function version_to_number(v)
	if not v then return 0 end
	local v_clean = v:gsub("^v", "")
	local major, minor, patch = v_clean:match("(%d+)%.(%d+)%.(%d+)")
	if major and minor and patch then
		return tonumber(major) * 1000000 + tonumber(minor) * 1000 + tonumber(patch)
	end
	return 0
end

local function check_for_updates()
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
		local current_version = yomipv_version

		if version_to_number(latest_version) > version_to_number(current_version) then
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

local function launch_updater()
	if not config.updater_enabled then
		return
	end

	local is_windows = package.config:sub(1,1) == "\\"
	local root_dir = utils.join_path(script_dir, "../../")
	local updater_path = utils.join_path(root_dir, "yomipv-updater.bat")

	if is_windows then
		updater_path = updater_path:gsub("/", "\\")
	end

	msg.info("Launching updater: " .. updater_path)
	Player.notify("Checking for updates...", "info", 5)

	local args = { "cmd.exe", "/c", updater_path }
	if is_windows then
		-- Start batch file as admin using powershell
		args = { "powershell.exe", "-NoProfile", "-Command", "Start-Process", '"' .. updater_path .. '"', "-Verb", "RunAs" }
	end

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

if config.key_update ~= "" then
	mp.add_key_binding(config.key_update, "yomipv-update", function()
		launch_updater()
	end)
end

local function launch_anki_db_build()
	local db_builder = AnkiDBBuilder.new(config, anki)

	local function draw_progress_bar(current, total)
		local percent = math.floor((current / total) * 100)
		local width = 15
		local filled = math.floor((current / total) * width)
		local bar = string.rep("▰", filled) .. string.rep("▱", width - filled)
		return string.format("Building Anki database... %s %d%%", bar, percent)
	end

	db_builder.on_progress = function(current, total)
		Player.notify(draw_progress_bar(current, total), "info", 1)
	end

	msg.info("Building Anki database (Lua)...")
	Player.notify("Building Anki database...", "info", 5)

	db_builder:build(function(success, err)
		if success then
			msg.info("Anki database built successfully")
			Player.notify("Anki database built successfully", "success")
			-- Reload database in memory
			local AnkiDB = require("lib.anki_db")
			if AnkiDB then
				AnkiDB.reload()
			end
			if handler and handler.current_tokens then
				handler:on_current_tokens_ready(handler.current_tokens)
			end
		else
			local error_msg = "Failed to build Anki database"
			msg.error(error_msg .. ": " .. tostring(err))
			Player.notify(error_msg, "error")
		end
	end)
end

if config.key_build_ankidb ~= "" then
	mp.add_key_binding(config.key_build_ankidb, "yomipv-build-anki-db", function()
		launch_anki_db_build()
	end)
end

if config.key_sub_seek_next ~= "" then
	mp.add_key_binding(config.key_sub_seek_next, "yomipv-sub-seek-next", function()
		mp.commandv("sub-seek", "1")
	end)
end

if config.key_sub_seek_prev ~= "" then
	mp.add_key_binding(config.key_sub_seek_prev, "yomipv-sub-seek-prev", function()
		mp.commandv("sub-seek", "-1")
	end)
end

mp.register_script_message("yomipv-sync-selection", function(text)
	msg.info("Received selection sync: " .. tostring(text))
	handler:sync_selection(text)
end)

mp.register_script_message("yomipv-sync-selection-hint", function(text)
	msg.info("Received selection hint sync: " .. tostring(text))
	handler:sync_selection_hint(text)
end)

mp.register_script_message("yomipv-dictionary-selected", function(text)
	msg.info("Received dictionary selection")
	handler:set_selected_dictionary(text)
end)

mp.register_script_message("yomipv-active-entry", function(expression, reading)
	msg.info("Active entry: " .. tostring(expression) .. " / " .. tostring(reading))
	handler:set_active_entry(expression, reading)
	if handler.deps.selector and handler.deps.selector.active then
		handler.deps.selector:expand_selection_to_match(expression, reading)
	end
end)

check_for_updates()
msg.info("Yomipv v" .. yomipv_version .. ": Initialized")
Player.notify("Yomipv v" .. yomipv_version .. " loaded", "success", 2)

mp.add_hook("on_pre_shutdown", 50, function()
	msg.info("Sending shutdown signal to lookup app")
	mp.command_native_async({
		name = "subprocess",
		playback_only = false,
		args = {
			Platform.get_curl_cmd(),
			"-s",
			"-X",
			"POST",
			"--connect-timeout",
			"1",
			"http://127.0.0.1:19634/shutdown",
		},
	})
end)
