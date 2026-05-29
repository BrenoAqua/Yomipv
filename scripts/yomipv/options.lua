--[[ Default options ]]

local mp = require("mp")

local default_options = {

	--[[ Anki settings ]]

	-- AnkiConnect
	ankiconnect_url = "127.0.0.1:8765",
	ankiconnect_api_key = "",

	-- Anki DB build settings
	ankidb_word_fields = "word Word expression Expression",
	ankidb_reading_fields = "",

	-- Deck and Note type
	deck = "Senren",
	note_type = "Senren",

	-- Note fields
	expression_field = "word",
	expression_furigana_field = "",
	reading_field = "reading",
	pitch_accents_field = "pitchAccents",
	pitch_position_field = "pitchPositions",
	pitch_categories_field = "pitchCategories",
	sentence_field = "sentence",
	sentence_furigana_field = "sentenceFurigana",
	secondary_sentence_field = "sentenceTranslation",
	expression_audio_field = "wordAudio",
	sentence_audio_field = "sentenceAudio",
	selection_text_field = "selectionText",
	definition_field = "definition",
	glossary_field = "glossary",
	image_field = "picture",
	freq_sort_field = "freqSort",
	freq_field = "frequencies",
	miscinfo_field = "miscInfo",
	dictionary_pref_field = "dictionaryPreference", -- Senren only

	-- State and behavior
	update_if_exists = true, -- Update card and append media if term exists
	-- Updated fields:
	-- sentence_field
	-- sentence_furigana_field
	-- secondary_sentence_field
	-- sentence_audio_field
	-- image_field
	-- miscinfo_field
	refresh_gui_after_update = true, -- Refresh Anki browser after note update

	--[[ Yomitan settings ]]

	yomitan_url = "127.0.0.1:19633",

	-- Field handlebars
	selection_text_handlebar = "",
	definition_handlebar = "",
	glossary_handlebar = "",

	-- Highlighting
	sentence_highlight_tag = '<b>', -- HTML tag for selected term

	-- HTML wrappers
	primary_sentence_wrapper = '<span class="group">%s</span>',
	secondary_sentence_wrapper = '<span class="group">%s</span>',
	miscinfo_wrapper = '<span class="group">%s</span>',

	-- Dictionary preferences
	dictionary_pref_value = "", -- Senren only

	--[[ Media templates ]]

	audio_template = "[sound:%s]",
	image_template = '<img src="%s" class="yomipv-image">',

	--[[ Picture settings ]]

	picture_use_ffmpeg = true, -- Use FFmpeg instead of MPV for extraction
	picture_timestamp_source = "subtitle_start", -- Capture timing: subtitle_start, current_position
	picture_animated = false, -- Use animated image capture

	-- Static screenshot settings
	picture_static_format = "avif", -- Format: jpg, avif, webp
	picture_static_quality = 85, -- Quality: 1-100
	picture_static_width = 1080, -- Width or 0 to disable scaling
	picture_static_offset = 0.0, -- Offset in seconds relative to subtitle start

	-- Animated picture settings
	animation_format = "avif", -- Format: webp, avif
	animation_quality = 50, -- Quality: 1-100
	animation_width = 720, -- Width or 0 to disable scaling
	animation_fps = 10, -- Frames per second
	animation_duration = "auto", -- Seconds or "auto" to match subtitle duration
	animation_offset = 0.0, -- Offset in seconds relative to subtitle start
	animation_end_offset = 0.0, -- Offset in seconds relative to subtitle end

	-- Advanced codec settings
	picture_webp_lossless = false,
	picture_webp_compression = 6, -- Compression from 0 to 6
	picture_avif_cpu_used = 4, -- CPU usage from 0 to 8

	--[[ Audio clip settings ]]

	audio_use_ffmpeg = true, -- Use FFmpeg instead of MPV for extraction
	audio_format = "opus", -- Format: mp3, opus
	audio_bitrate = "64k",
	audio_offset = 0.0, -- Offset in seconds relative to subtitle start
	audio_end_offset = 0.0, -- Offset in seconds relative to subtitle end
	filename_show_ms = true, -- Include milliseconds in filenames
	audio_match_volume = false, -- Match extracted audio volume to mpv volume

	--[[ Misc info settings ]]

	-- {name} Sanitized title
	-- {season} Season info
	-- {episode} Episode info
	-- {timestamp} Timestamp (HH:MM:SS)

	-- Bullet logic (miscinfo_episode_bullet):
	-- If both {season} and {episode}: Bullet matches {season}, comma separator added
	-- If only {episode}: Bullet matches {episode}

	-- Formatting examples:
	-- {name}{season}{episode} • {timestamp} -> Show Name • シーズン 2, エピソード 6 • 00:03:34
	-- {name}{episode} • {timestamp}         -> Show Name • エピソード 6 • 00:03:34

	-- Labels and formatting
	miscinfo_episode_bullet = true,
	miscinfo_show_season_one = false, -- Include season index for first season
	miscinfo_show_ms = false, -- Include milliseconds in timestamp
	miscinfo_episode_label = "エピソード",
	miscinfo_season_label = "シーズン",
	miscinfo_format = "{name}{season}{episode} • {timestamp}",

	--[[ Note tagging settings ]]

	-- Target tags for exported notes
	-- {name}, {season}, {episode}, and {timestamp} can also be used with the note tag
	note_tag = "アニメ",

	--[[ Selector settings ]]

	-- Behavior
	selector_show_history = true, -- Include recent lines in selector view
	selector_hide_ui = true, -- Hide player UI while selector is active
	selector_navigation_delay = 0.05, -- Input delay between repeated navigation actions
	selector_trigger_on_mouse_move = false, -- Automatically trigger selector on mouse movement after idle
	selector_trigger_mouse_idle_time = 5.0, -- Seconds mouse must be idle before movement triggers selector

	-- Colorizer
	colorizer_enabled = false, -- Replace MPV subtitles with Yomipv-rendered subtitles
	selector_colorize_words = false, -- Main toggle for word coloring
	colorizer_ignore_kana_only = false, -- Skip kana-only words with no database match
	selector_colorize_underline = false, -- Show colors on underlines instead of words
	selector_colorize_opacity = 100, -- Opacity of colorized underlines from 0 to 100

	-- Lookup
	pre_tokenize = true, -- Pre-tokenize subtitles as they appear
	selector_lookup_on_hover = false, -- Automatically show lookup on hover
	selector_lookup_on_navigation = false, -- Automatically show lookup on navigation
	selector_lookup_delay = 0.1, -- Delay in seconds before triggering lookup
	selector_mora_hover = true, -- Lookup sub-words while hovering individual characters
	selector_mora_navigation = false, -- Navigate through individual characters with arrow keys
	lookup_show_frequencies = true,
	lookup_show_pitch_accents = true,
	prioritize_kanji_match = false, -- Prioritize entries with Kanji over match length
	prioritize_hiragana_match = false, -- Prioritize hiragana-only entries when term is hiragana-only
	lookup_theme = "dark", -- "dark" or "light"

	-- Typography
	selector_font_name = "", -- Fallback to mpv sub-font if unset
	selector_font_size = 45, -- Fallback to mpv sub-font-size if 0 provided
	selector_line_height = 1.25,

	-- Appearance
	selector_selection_underline = false,
	selector_underline_thickness = 4,
	selector_underline_offset = -1,
	selector_border_size = 2,
	selector_shadow_offset = 0,

	-- Colors
	selector_color = "#FFFFFF",
	selector_selection_color = "#56FF68",
	selector_lock_color = "#FFD700",
	selector_persistent_color = "#FF8C00",
	selector_border_color = "#000000",
	selector_shadow_color = "#000000",

	-- Layout
	selector_pos_y = 100,
	selector_max_width_factor = 0.9, -- Max text block width relative to OSD width

	-- Keybindings
	key_toggle_colorizer = "S",
	key_open_selector = "c",
	key_selector_confirm = "ENTER,c",
	key_selector_cancel = "ESC",
	key_selector_left = "LEFT",
	key_selector_right = "RIGHT",
	key_selector_up = "UP",
	key_selector_down = "DOWN",
	key_expand_prev = "Shift+LEFT",
	key_expand_next = "Shift+RIGHT",
	key_selector_lookup = "Ctrl+c",
	key_selector_lock = "v",
	key_toggle_mora_navigation = "s",
	key_toggle_selector_trigger_on_mouse_move = "z",
	key_append_mode = "C",
	key_set_timing_start = "q",
	key_set_timing_end = "w",
	key_clear_timings = "e",
	key_build_ankidb = "B",
	key_toggle_picture_animated = "g",
	key_toggle_picture_timestamp_source = "Ctrl+g",

	--[[ History settings ]]

	-- Behavior
	history_show_secondary = true, -- Display secondary subtitles in history panel
	history_hide_volume = true, -- Hide UOSC volume slider while history panel is open
	history_max_entries = 200, -- Maximum subtitle entries to retain (0 to disable limit)

	-- Size
	history_width = 380,
	history_max_height = "60vh",

	-- Typography
	history_font_size = 16,
	history_secondary_font_size = 13,
	history_font_family = "", -- Comma-separated fonts

	-- Appearance
	history_accent_color = "#3db54a", -- Subtitle hover highlight color
	history_header_background_color = "rgba(255, 255, 255, 0.03)",
	history_background_color = "#111111",
	history_background_opacity = "86%",
	history_border_radius = 8,

	-- Keybindings
	key_toggle_history = "a",
	key_history_clear = "x",

	--[[ Subtitle settings ]]

	-- Behavior
	subtitle_filter_enabled = true, -- Filter signs, drawings and tags from OSD display

	-- Primary subtitles
	primary_autoload = true, -- Auto-load external subtitle files matching anime episode
	primary_sub_lang = "ja,jpn", -- Preferred languages for primary subtitles
	primary_sub_exclude = "signs,songs,forced,commentary,sdh,cc", -- Skip tracks with any of these keywords
	auto_sync_subtitles = true, -- Automatically sync primary subtitle timing to secondary if languages match

	-- Secondary subtitles
	secondary_sid = true, -- Track secondary subtitle stream for translations
	secondary_on_hover = true, -- Show secondary subtitles only during hover interactions
	secondary_sub_lang = "en,eng", -- Preferred languages for secondary subtitles
	secondary_sub_exclude = "signs,songs,forced,commentary,sdh,cc", -- Skip tracks with any of these keywords

	-- Keybindings
	key_sub_seek_next = "Alt+RIGHT",
	key_sub_seek_prev = "Alt+LEFT",
	key_sub_replay = "r",
	key_secondary_sub_next = "Ctrl+j",
	key_secondary_sub_prev = "Ctrl+J",
	key_sync_subtitles = "Ctrl+s",

	--[[ AniList settings ]]

	anilist_enabled = false,
	anilist_token = "",
	anilist_update_thresh_percent = 80,
	anilist_show_notifications = true,
	key_anilist_auth = "Ctrl+a",

	--[[ Updater settings ]]

	updater_enabled = true,
	updater_check_on_startup = true,
	updater_use_source = false,
	key_update = "U",

	--[[ MPV Settings ]]

	osd_messages = true, -- Show OSD messages

	--[[ Settings ]]

	auto_load = true, -- Automatically load Yomipv on startup
    current_profile = "default", -- Active profile

	-- Keybindings
	key_load_yomipv = "y", -- Key to load Yomipv manually
    key_open_settings = "Ctrl+i", -- Open settings menu
	key_cycle_profile = "Ctrl+p", -- Cycle through available profiles
}

local options = default_options
local mp_options = require("mp.options")
mp_options.read_options(options, "yomipv")

-- Snapshot defaults for type-coercion
options.defaults = {}
for k, v in pairs(default_options) do
	options.defaults[k] = v
end

function options.save(key, value)
	local filename = "yomipv.conf"
	if key ~= "current_profile" and options.current_profile and options.current_profile ~= "default" then
		filename = "yomipv_" .. options.current_profile .. ".conf"
	end

	local path = mp.find_config_file("script-opts/" .. filename)
	if not path then
		path = mp.command_native({ "expand-path", "~~/script-opts/" .. filename })
	end
	if not path then
		return false
	end

	local file = io.open(path, "r")
	if not file then
		return false
	end

	local lines = {}
	local updated = false
	for line in file:lines() do
		if line:match("^%s*" .. key .. "%s*=") then
			local val_str = type(value) == "boolean" and (value and "yes" or "no") or tostring(value)
			line = key .. "=" .. val_str
			updated = true
		end
		table.insert(lines, line)
	end
	file:close()

	if updated then
		file = io.open(path, "w")
		if file then
			for _, line in ipairs(lines) do
				file:write(line .. "\n")
			end
			file:close()
			return true
		end
	else
		-- Append new key if it doesn't exist
		file = io.open(path, "a")
		if file then
			local val_str = type(value) == "boolean" and (value and "yes" or "no") or tostring(value)
			file:write(key .. "=" .. val_str .. "\n")
			file:close()
			return true
		end
	end
	return false
end

return options
