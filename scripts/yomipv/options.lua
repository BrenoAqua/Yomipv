--[[ Default configuration options ]]

local default_options = {

	--[[ Anki settings ]]

	-- AnkiConnect
	ankiconnect_url = "127.0.0.1:8765",
	ankiconnect_api_key = "",

	-- Deck and Note type
	deck = "Senren",
	note_type = "Senren",

	-- Note fields
	expression_field = "word",
	reading_field = "reading",
	pitch_accents_field = "pitchAccents",
	pitch_position_field = "pitchPositions",
	pitch_categories_field = "pitchCategories",
	sentence_field = "sentence",
	sentence_furigana_field = "sentenceFurigana",
	secondary_sentence_field = "sentenceTranslation",
	expression_audio_field = "wordAudio",
	sentence_audio_field = "sentenceAudio",
	definition_field = "definition",
	glossary_field = "glossary",
	image_field = "picture",
	freq_sort_field = "freqSort",
	freq_field = "frequencies",
	miscinfo_field = "miscInfo",
	dictionary_pref_field = "dictionaryPreference", -- Senren only

	-- State and behavior
	update_if_exists = true, -- Update card and append media if term exists
	-- Fields that are updated:
	-- sentence_field
	-- sentence_furigana_field
	-- secondary_sentence_field
	-- sentence_audio_field
	-- image_field
	-- miscinfo_field
	refresh_gui_after_update = true, -- Refresh Anki browser after updating note

	--[[ Yomitan settings ]]

	yomitan_url = "127.0.0.1:19633",

	-- Field handlebars; leave empty to disable
	definition_handlebar = "",
	glossary_handlebar = "glossary",

	-- Highlighting
	sentence_highlight_tag = '<span class="highlight">', -- HTML tag for selected term

	-- HTML wrappers
	primary_sentence_wrapper = '<span class="group">%s</span>',
	secondary_sentence_wrapper = '<span class="group">%s</span>',
	miscinfo_wrapper = '<span class="group">%s</span>',

	-- Dictionary preferences
	dictionary_pref_value = "", -- Senren only

	--[[ Media templates ]]

	-- Audio template
	audio_template = "[sound:%s]",

	-- Image template
	image_template = '<img src="%s" class="yomipv-image">',

	--[[ Misc info settings ]]

	-- Format specifiers:
	-- {name}: Sanitized title (removes episodes and brackets)
	-- {season}: Season info
	-- {episode}: Episode info
	-- {timestamp}: Timestamp (HH:MM:SS)

	-- Bullet logic (miscinfo_episode_bullet):
	-- Adapts dynamically to {season} and {episode} presence
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
	note_tag = "アニメ",

	--[[] Picture settings ]]

	picture_use_ffmpeg = true, -- Use FFmpeg instead of MPV for extraction
	picture_timestamp_source = "subtitle_start", -- Capture timing: subtitle_start, current_position
	picture_animated = false, -- Use animated image capture

	-- Static screenshot settings
	picture_static_format = "avif", -- Format: jpg, avif, webp
	picture_static_quality = 85, -- Quality: 1-100
	picture_static_width = 1080, -- Width (0 to disable scaling)
	picture_static_offset = 0.0, -- Offset in seconds relative to subtitle start

	-- Animated picture settings
	animation_format = "avif", -- Format: webp, avif
	animation_quality = 50, -- Quality: 1-100
	animation_width = 720, -- Width (0 to disable scaling)
	animation_fps = 10, -- Frames per second
	animation_duration = "auto", -- Seconds or "auto" to match subtitle duration
	animation_offset = 0.0, -- Offset in seconds relative to subtitle start

	-- Advanced codec settings
	picture_webp_lossless = false,
	picture_webp_compression = 6, -- Compression from 0 to 6
	picture_avif_cpu_used = 4, -- CPU usage from 0 to 8

	--[[] Audio clip settings ]]

	audio_use_ffmpeg = true, -- Use FFmpeg instead of MPV for extraction
	audio_format = "opus", -- Format: mp3, opus
	audio_bitrate = "64k",
	filename_show_ms = true, -- Include milliseconds in filenames

	--[[ Selector settings ]]

	-- Behavior
	selector_show_history = true, -- Include recent lines in selector view
	selector_hide_ui = true, -- Hide player UI while selector is active
	selector_navigation_delay = 0.05, -- Input delay between repeated navigation actions

	-- Lookup
	selector_lookup_on_hover = false, -- Automatically show lookup when hovering over terms
	selector_lookup_on_navigation = false, -- Automatically show lookup when navigating with keyboard

	-- Typography
	selector_font_name = "", -- Fallback to mpv sub-font if unset
	selector_font_size = 45, -- Fallback to mpv sub-font-size if 0 provided
	selector_line_height = 1.25,

	-- Appearance
	selector_color = "#FFFFFF",
	selector_selection_color = "#56FF68", -- Color of active term highlight
	selector_border_color = "#000000",
	selector_border_size = 2,
	selector_shadow_color = "#000000",
	selector_shadow_offset = 0,

	-- Layout
	selector_pos_y = 100,
	selector_max_width_factor = 0.9, -- Max text block width relative to OSD width

	-- Keybindings
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
	key_append_mode = "C",
	lookup_app_path = "lookup-app",

	--[[ History settings ]]

	-- Behavior
	history_show_secondary = true, -- Display secondary subtitles in history panel
	history_hide_volume = true, -- Hide UOSC volume slider while history panel is open
	history_max_entries = 200, -- Maximum subtitle entries to retain (0 to disable limit)

	-- Size
	history_width = 220, -- History panel width
	history_max_height = 400, -- History panel maximum height

	-- Typography
	history_font_size = 15,
	history_secondary_font_size = 12,

	-- Appearance
	history_accent_color = "#3db54a", -- Header and scrollbar accent color
	history_background_color = "#111111",
	history_background_opacity = "13%",

	-- Keybindings
	key_toggle_history = "a",

	--[[ Subtitle settings ]]

	-- Behavior
	subtitle_filter_enabled = true, -- Filter signs, drawings and tags from OSD display

	-- Secondary subtitles
	secondary_sid = true, -- Track secondary subtitle stream for translations
	secondary_on_hover = true, -- Show secondary subtitles only during hover interactions
}

local options = default_options
local mp_options = require("mp.options")
mp_options.read_options(options, "yomipv")

return options
