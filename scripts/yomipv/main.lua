--[[ Yomipv | https://github.com/BrenoAqua/Yomipv ]]

local mp = require("mp")
local msg = require("mp.msg")

local yomipv_version = "1.0.0"
mp.commandv("script-message", "yomipv-version", yomipv_version)

local script_dir = mp.get_script_directory()
package.path = script_dir .. "/?.lua;" .. script_dir .. "/?/init.lua;" .. package.path

local config = require("options")
local Platform = require("lib.platform")
local Curl = require("lib.curl")
local Player = require("lib.player")
local Yomitan = require("api.yomitan")
local AnkiConnect = require("api.ankiconnect")
local Anilist = require("api.anilist")
local Monitor = require("capture.monitor")
local AnilistTracker = require("api.anilist_tracker")
local Observer = require("subtitle.observer")
local SubtitleFilter = require("subtitle.subtitle_filter")
local PrimarySid = require("subtitle.primary-sid")
local SecondarySid = require("subtitle.secondary-sid")
local SubtitleSync = require("subtitle.sync")
local Selector = require("interface.selector.selector")
local History = require("interface.history.panel")
local Builder = require("export.builder")
local AnkiDBBuilder = require("export.anki_db_builder")
local Formatter = require("export.formatter")
local Handler = require("export.handler")
local Picture = require("media.picture")
local Audio = require("media.audio")
local Launcher = require("lib.launcher")
local Updater = require("lib.updater")
local MouseHandler = require("interface.mouse_handler")
local Profiles = require("lib.profiles")

msg.info("Yomipv v" .. yomipv_version .. ": Initializing...")

local yomitan = Yomitan.new(config, Curl)
local anki = AnkiConnect.new(config, Curl)
local anilist = Anilist.new(config, Curl)

Picture.init(config)
Audio.init(config)
Monitor.init(config)
AnilistTracker.init(config, anilist)

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
PrimarySid.init(config)
SecondarySid.init(config)
SubtitleSync.init(config)
SubtitleFilter.init(config)

Launcher.launch_lookup_app(config)
Updater.check_for_updates(config, yomipv_version, Curl)
MouseHandler.init(config, handler, history, Selector)

mp.register_event("file-loaded", function()
	yomitan:clear_cache()
end)

mp.observe_property("focused", "bool", function(_, is_focused)
	if is_focused then
		Curl.post("http://127.0.0.1:19634/app-focus?state=true", "{}", function() end)
	else
		Curl.post("http://127.0.0.1:19634/app-focus?state=false", "{}", function() end)
	end
end)

mp.add_hook("on_pre_shutdown", 50, function()
	Launcher.shutdown_lookup_app()
end)

local function send_to_lookup_app(endpoint, data)
	local utils = require("mp.utils")
	local json = utils.format_json(data)
	local curl_cmd = Platform.get_curl_cmd()

	mp.command_native_async({
		name = "subprocess",
		playback_only = false,
		args = {
			curl_cmd,
			"-s",
			"-X",
			"POST",
			"-H",
			"Content-Type: application/json",
			"-d",
			json,
			"--connect-timeout",
			"1",
			"http://127.0.0.1:19634/" .. endpoint,
		},
	}, function(success, result, err)
		if not success or (result and result.status ~= 0) then
			msg.warn(string.format("Lookup App IPC failed (%s): %s", endpoint, err or (result and result.status or "unknown")))
		end
	end)
end

local function get_clean_config()
	local clean = {}
	for k, v in pairs(config) do
		if type(v) ~= "function" and k ~= "defaults" then
			clean[k] = v
		end
	end
	return clean
end

-- Settings and profiles communication
mp.register_script_message("yomipv-get-settings", function()
	send_to_lookup_app("settings-data", { config = get_clean_config() })
end)

mp.register_script_message("yomipv-set-setting", function(key, val)
	local default_val = config.defaults[key]
	if default_val ~= nil then
		local coerced = val
		if type(default_val) == "boolean" then
			coerced = val == "true" or val == "yes"
		elseif type(default_val) == "number" then
			coerced = tonumber(val) or default_val
		end
		config[key] = coerced
		config.save(key, coerced)
		Player.notify("Setting updated: " .. key, "info", 1)
	end
end)

mp.register_script_message("yomipv-list-profiles", function()
	local list = Profiles.list()
	send_to_lookup_app("profile-list-data", list)
end)

-- Process selection events and coordinate dictionary expansion
mp.register_script_message("yomipv-active-entry", function(exp, red)
	handler:set_active_entry(exp, red)
	if handler.deps.selector and handler.deps.selector.active then
		handler.deps.selector:expand_selection_to_match(exp, red)
	end
end)

mp.register_script_message("yomipv-sync-selection", function(text)
	handler:sync_selection(text)
end)

mp.register_script_message("yomipv-sync-selection-hint", function(text)
	handler:sync_selection_hint(text)
end)

mp.register_script_message("yomipv-dictionary-selected", function(text)
	handler:set_selected_dictionary(text)
end)

local function register_keybindings()
	local bindings = {
		{ config.key_open_settings, "yomipv-open-settings", function() send_to_lookup_app("settings-open", {}) end },
		{ config.key_open_selector, "yomipv-export", function() if handler then handler:start_export(history) end end },
		{ config.key_toggle_colorizer, "yomipv-toggle-colorizer", function() handler:toggle_colorizer() end },
		{ config.key_append_mode, "yomipv-toggle-append-mode", function() handler:toggle_mark_range() end },
		{ config.key_toggle_history, "yomipv-toggle-history", function()
			if history.active then history:close() else history:open() end
		end },
		{ config.key_sub_seek_next, "yomipv-sub-seek-next", function() mp.commandv("sub-seek", "1") end },
		{ config.key_sub_seek_prev, "yomipv-sub-seek-prev", function() mp.commandv("sub-seek", "-1") end },
		{ config.key_secondary_sub_next, "yomipv-secondary-sub-next", function() SecondarySid.cycle_track(1) end },
		{ config.key_secondary_sub_prev, "yomipv-secondary-sub-prev", function() SecondarySid.cycle_track(-1) end },
		{ config.key_update, "yomipv-update", function() Updater.launch(config) end },
		{ config.key_build_ankidb, "yomipv-build-anki-db", function()
			AnkiDBBuilder.new(config, anki):build_with_notification(handler)
		end },
		{ config.key_set_timing_start, "yomipv-set-timing-start", function() handler:set_manual_start() end },
		{ config.key_set_timing_end, "yomipv-set-timing-end", function() handler:set_manual_end() end },
		{ config.key_clear_timings, "yomipv-clear-timings", function() handler:clear_manual_timings() end },
		{ config.key_toggle_picture_animated, "yomipv-toggle-picture-animated", function()
			config.picture_animated = not config.picture_animated
			config.save("picture_animated", config.picture_animated)
			Player.notify("Animated pictures: " .. (config.picture_animated and "Enabled" or "Disabled"), "info")
			if history and history.active then history:update(true) end
		end },
		{ config.key_toggle_mora_navigation, "yomipv-toggle-mora-navigation", function()
			config.selector_mora_navigation = not config.selector_mora_navigation
			config.save("selector_mora_navigation", config.selector_mora_navigation)
			Player.notify("Mora navigation: " .. (config.selector_mora_navigation and "Enabled" or "Disabled"), "info")
			if Selector.active then
				Selector.style.selector_mora_navigation = config.selector_mora_navigation
				Selector:render()
			end
		end },
		{ config.key_toggle_selector_trigger_on_mouse_move, "yomipv-toggle-selector-trigger-on-mouse-move", function()
			config.selector_trigger_on_mouse_move = not config.selector_trigger_on_mouse_move
			config.save("selector_trigger_on_mouse_move", config.selector_trigger_on_mouse_move)
			local status = config.selector_trigger_on_mouse_move and "Enabled" or "Disabled"
			Player.notify("Selector mouse trigger: " .. status, "info")
		end },
		{ config.key_cycle_profile, "yomipv-cycle-profile", function()
			local new_name, err = Profiles.cycle(config, config.defaults)
			if new_name then
				config.save("current_profile", new_name)
				handler:sync_state()
				register_keybindings()
				Player.notify("Profile: " .. new_name, "info", 3)
				send_to_lookup_app("settings-data", { config = get_clean_config() })
			else
				Player.notify(err or "Profile switch failed", "warn", 3)
			end
		end }
	}

	for _, b in ipairs(bindings) do
		local key, name, fn = b[1], b[2], b[3]
		if key and key ~= "" then
			mp.add_key_binding(key, name, fn)
		else
			mp.remove_key_binding(name)
		end
	end
end

mp.register_script_message("yomipv-switch-profile", function(name)
	local ok, err = Profiles.load(name, config, config.defaults)

	if ok then
		config.save("current_profile", name)
		handler:sync_state()
		register_keybindings()
		Player.notify("Profile: " .. name, "success", 2)
		send_to_lookup_app("settings-data", { config = get_clean_config() })
	else
		Player.notify(err or "Failed to switch profile", "error", 3)
	end
end)

mp.register_script_message("yomipv-create-profile", function(name)
	local ok, err = Profiles.create(name, config)
	if ok then
		Player.notify("Profile created: " .. name, "success", 2)
		local list = Profiles.list()
		send_to_lookup_app("profile-list-data", list)
	else
		Player.notify(err or "Failed to create profile", "error", 3)
	end
end)

mp.register_script_message("yomipv-delete-profile", function(name)
	local ok, err = Profiles.delete(name)
	if ok then
		Player.notify("Profile deleted: " .. name, "info", 2)
		local list = Profiles.list()
		send_to_lookup_app("profile-list-data", list)
	else
		Player.notify(err or "Failed to delete profile", "error", 3)
	end
end)

-- Startup profile restoration
if config.current_profile and config.current_profile ~= "default" then
	local ok, err = Profiles.load(config.current_profile, config, config.defaults)
	if ok then
		handler:sync_state()
	else
		msg.warn("Startup profile load failed: " .. tostring(err))
		config.current_profile = "default"
	end
end

register_keybindings()

msg.info("Yomipv v" .. yomipv_version .. ": Initialized")
Player.notify("Yomipv v" .. yomipv_version .. " loaded", "success", 2)
