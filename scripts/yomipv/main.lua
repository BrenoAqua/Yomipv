--[[ Yomipv | https://github.com/BrenoAqua/Yomipv ]]

local mp = require("mp")
local msg = require("mp.msg")

local yomipv_version = "0.4.1"
mp.commandv("script-message", "yomipv-version", yomipv_version)

local script_dir = mp.get_script_directory()
package.path = script_dir .. "/?.lua;" .. script_dir .. "/?/init.lua;" .. package.path

local config = require("options")
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

mp.add_hook("on_pre_shutdown", 50, function()
	Launcher.shutdown_lookup_app()
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

-- Core user actions for content export and colorization
mp.add_key_binding(config.key_open_selector, "yomipv-export", function()
	if handler then handler:start_export(history) end
end)

mp.add_key_binding(config.key_toggle_colorizer, "yomipv-toggle-colorizer", function()
	handler:toggle_colorizer()
end)

mp.add_key_binding(config.key_append_mode, "yomipv-toggle-append-mode", function()
	handler:toggle_mark_range()
end)

if config.selector_show_history then
	mp.add_key_binding(config.key_toggle_history, "yomipv-toggle-history", function()
		if history.active then history:close() else history:open() end
	end)
end

-- Primary and secondary subtitle navigation
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

if config.key_secondary_sub_next ~= "" then
	mp.add_key_binding(config.key_secondary_sub_next, "yomipv-secondary-sub-next", function()
		SecondarySid.cycle_track(1)
	end)
end

if config.key_secondary_sub_prev ~= "" then
	mp.add_key_binding(config.key_secondary_sub_prev, "yomipv-secondary-sub-prev", function()
		SecondarySid.cycle_track(-1)
	end)
end

-- Update management and database background tasks
if config.key_update ~= "" then
	mp.add_key_binding(config.key_update, "yomipv-update", function()
		Updater.launch(config)
	end)
end

if config.key_build_ankidb ~= "" then
	mp.add_key_binding(config.key_build_ankidb, "yomipv-build-anki-db", function()
		AnkiDBBuilder.new(config, anki):build_with_notification(handler)
	end)
end

-- Manual timing overrides for card creation
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

-- Property overrides and UI feature toggles
if config.key_toggle_picture_animated ~= "" then
	mp.add_key_binding(config.key_toggle_picture_animated, "yomipv-toggle-picture-animated", function()
		config.picture_animated = not config.picture_animated
		config.save("picture_animated", config.picture_animated)
		Player.notify("Animated pictures: " .. (config.picture_animated and "Enabled" or "Disabled"), "info")
		if history and history.active then history:update(true) end
	end)
end

if config.key_toggle_mora_navigation ~= "" then
	mp.add_key_binding(config.key_toggle_mora_navigation, "yomipv-toggle-mora-navigation", function()
		config.selector_mora_navigation = not config.selector_mora_navigation
		config.save("selector_mora_navigation", config.selector_mora_navigation)
		Player.notify("Mora navigation: " .. (config.selector_mora_navigation and "Enabled" or "Disabled"), "info")
		if Selector.active then
			Selector.style.selector_mora_navigation = config.selector_mora_navigation
			Selector:render()
		end
	end)
end

if config.key_toggle_selector_trigger_on_mouse_move ~= "" then
	mp.add_key_binding(config.key_toggle_selector_trigger_on_mouse_move, "yomipv-toggle-selector-trigger-on-mouse-move",
		function()
			config.selector_trigger_on_mouse_move = not config.selector_trigger_on_mouse_move
			config.save("selector_trigger_on_mouse_move", config.selector_trigger_on_mouse_move)
			local status = config.selector_trigger_on_mouse_move and "Enabled" or "Disabled"
			Player.notify("Selector mouse trigger: " .. status, "info")
		end
	)
end

msg.info("Yomipv v" .. yomipv_version .. ": Initialized")
Player.notify("Yomipv v" .. yomipv_version .. " loaded", "success", 2)
