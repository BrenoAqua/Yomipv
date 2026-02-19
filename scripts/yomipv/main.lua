--[[ Yomipv | https://github.com/BrenoAqua/Yomipv ]]

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")

local yomipv_version = "0.1.0"
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

history:set_exporter_handler(handler)
Observer.init(Monitor)
Observer.start()
SecondarySid.init(config)
SubtitleFilter.init(config)

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

		Player.notify("Yomipv: Starting lookup app...", "info")

		local electron_ipc_pipe = ipc_pipe
		if Platform.IS_WINDOWS and not electron_ipc_pipe:match("^\\\\.\\pipe\\") then
			electron_ipc_pipe = "\\\\.\\pipe\\" .. electron_ipc_pipe
		end

		Platform.launch_electron_app(app_path, mpv_pid, electron_ipc_pipe, function(launch_success, _launch_result, launch_error)
			if not launch_success then
				msg.error("Failed to launch lookup app: " .. tostring(launch_error))
			else
				msg.info("Lookup app launch command sent")
			end
		end)
	end)
end

launch_lookup_app()

mp.add_key_binding(config.key_open_selector, "yomipv-export", function()
	msg.info("Key pressed: " .. config.key_open_selector)
	if not handler then
		msg.error("Handler not initialized!")
		return
	end
	handler:start_export(history)
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

mp.register_script_message("yomipv-sync-selection", function(text)
	msg.info("Received selection sync: " .. tostring(text))
	handler:sync_selection(text)
end)

mp.register_script_message("yomipv-dictionary-selected", function(text)
	msg.info("Received dictionary selection")
	handler:set_selected_dictionary(text)
end)

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
