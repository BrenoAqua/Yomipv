--[[ Export orchestration and Anki integration pipeline ]]

local mp = require("mp")
local msg = require("mp.msg")
local Collections = require("lib.collections")
local StringOps = require("lib.string_ops")
local Player = require("lib.player")
local Counter = require("lib.counter")
local Platform = require("lib.platform")

local Handler = {}

-- Module constants
local DEFAULT_YOMITAN_FIELDS = {
	"expression",
	"reading",
	"cloze-prefix",
	"cloze-body",
	"cloze-suffix",
	"sentence-furigana",
	"audio",
	"pitch-accents",
	"pitch-accent-positions",
	"pitch-accent-categories",
	"frequencies",
	"frequency-harmonic-rank",
}

local EXPANSION_TIMEOUT = 0.05

-- Get field value from entry data structure
local function get_field_value(entry, field_name)
	if not entry or not field_name then
		return nil
	end
	return entry[field_name]
end

-- Split context sentence for cloze highlighting (supports surface/offset matching)
local function split_cloze(context, target, surface, offset)
	local start_idx, end_idx

	-- Surface and offset matching
	if surface and offset then
		local sub = context:sub(offset + 1, offset + #surface)
		if sub == surface then
			return context:sub(1, offset), surface, context:sub(offset + #surface + 1)
		end
	end

	-- Fallback to searching surface form
	if surface then
		start_idx, end_idx = context:find(surface, 1, true)
	end

	-- Fallback to searching dictionary form
	if not start_idx then
		start_idx, end_idx = context:find(target, 1, true)
	end

	if start_idx then
		return context:sub(1, start_idx - 1), context:sub(start_idx, end_idx), context:sub(end_idx + 1)
	else
		return context, "", ""
	end
end

-- Format sentence HTML with primary highlight tag
local function format_sentence_html(self, prefix, body, suffix, tag)
	local closing_tag = tag:match("<(%w+)")
	closing_tag = closing_tag and ("</" .. closing_tag .. ">") or "</span>"
	local content = string.format("%s%s%s%s%s", prefix or "", tag or "", body or "", closing_tag, suffix or "")
	return string.format(self.config.primary_sentence_wrapper, content)
end

-- Merge raw subtitle content (prepend/append)
local function merge_raw_content(existing, new_content, direction)
	if not existing then
		return new_content
	end

	if direction < 0 then
		local merged = {}
		for _, segment in ipairs(new_content) do
			table.insert(merged, segment)
		end
		table.insert(merged, { { text = "\n", reading = "" } })
		for _, segment in ipairs(existing) do
			table.insert(merged, segment)
		end
		return merged
	else
		local merged = Collections.duplicate(existing)
		table.insert(merged, { { text = "\n", reading = "" } })
		for _, segment in ipairs(new_content) do
			table.insert(merged, segment)
		end
		return merged
	end
end
-- Entry points
function Handler:start_export(gui)
	local was_paused = mp.get_property_native("pause")
	mp.set_property_native("pause", true) -- Pauses video immediately

	local status, err = pcall(function()
		local context = self:initialize_export_context(gui)
		if not context then
			-- Cleanup if handled internally
			if not was_paused then
				mp.set_property_native("pause", false)
			end
			return
		end

		self:start_selector_flow(context, was_paused)
	end)

	if not status then
		msg.error("Error in start_export: " .. tostring(err))
		Player.notify("Export failed: " .. tostring(err), "error", 4)
		if not was_paused then
			mp.set_property_native("pause", false)
		end
	end
end

function Handler:toggle_mark_range()
	if self.deps.tracker.is_appending() then
		self.deps.tracker.clear_and_notify()
	else
		self.deps.tracker.set_to_current_sub()
	end
end
-- Export flow steps
-- Initialize context for new export session
function Handler:initialize_export_context(gui)
	Player.notify("Yomitan: Initializing...")
	msg.info("Starting Yomitan export flow")

	if not self.deps.tracker.is_appending() then
		self.deps.tracker.clear()
	end

	local sub = self.deps.tracker.export_current_session()
	local primary = StringOps.clean_subtitle(sub and sub.primary_sid or "", true)

	if not sub or primary == "" then
		msg.info("No current session content, attempting to get last from history relative to timeline")
		local history_subs = self.deps.tracker.get_synchronized_history()
		local time_pos = mp.get_property_number("time-pos", 0)

		if history_subs and #history_subs > 0 then
			local last_relevant = nil
			-- Find latest sub that started before or at current time
			for i = #history_subs, 1, -1 do
				local entry = history_subs[i]
				if entry.start <= time_pos then
					last_relevant = entry
					break
				end
			end

			-- Secondary fallback: find first sub starting after current time
			if not last_relevant then
				for i = 1, #history_subs do
					local entry = history_subs[i]
					if entry.start > time_pos then
						last_relevant = entry
						break
					end
				end
			end

			-- Final fallback: absolute last
			if not last_relevant then
				last_relevant = history_subs[#history_subs]
			end

			sub = {
				primary_sid = StringOps.clean_subtitle(last_relevant.primary_sid or "", true),
				secondary_sid = StringOps.clean_subtitle(last_relevant.secondary_sid or "", true),
				start = last_relevant.start,
				["end"] = last_relevant["end"],
			}
		else
			msg.warn("No valid subtitle context found")
			Player.notify("Nothing to export.", "warn", 1)
			return nil
		end
	else
		sub.primary_sid = primary
		sub.secondary_sid = StringOps.clean_subtitle(sub.secondary_sid or "", true)
	end

	local history_was_open = self.deps.history and self.deps.history.active
	if self.config.selector_show_history and self.deps.history then
		self.deps.history:open("open")
	end

	local hex_dump = ""
	for i = 1, math.min(#sub.primary_sid, 20) do
		hex_dump = hex_dump .. string.format("%02X ", sub.primary_sid:byte(i))
	end
	msg.info("Cleaned sub hex: " .. hex_dump)

	return {
		sub = Collections.duplicate(sub),
		first_subtitle = Collections.duplicate(sub),
		last_subtitle = Collections.duplicate(sub),
		current_subtitle_text = sub.primary_sid,
		raw_content = nil,
		expansion_occurred = false,
		history_was_open = history_was_open,
		gui = gui,
	}
end

-- Start interactive word selector flow
function Handler:start_selector_flow(context, was_paused)
	local hex_dump = ""
	for i = 1, math.min(#context.current_subtitle_text, 20) do
		hex_dump = hex_dump .. string.format("%02X ", context.current_subtitle_text:byte(i))
	end
	msg.info("Final tokenize text hex: " .. hex_dump)
	msg.info("Tokenizing subtitle: " .. context.current_subtitle_text)
	Player.notify("Yomitan: Tokenizing...")

	self.expand_to_subtitle = function(_, target)
		self:expand_to_subtitle_method(context, target)
	end

	self.deps.yomitan:tokenize(context.current_subtitle_text, function(tokens, raw_content_result, tokenization_error)
		msg.info("Tokenize callback received")
		if tokenization_error then
			msg.error("Tokenization error: " .. tokenization_error)
			self.expand_to_subtitle = nil
			return Player.notify("Yomitan tokenization failed: " .. tokenization_error, "error", 2)
		end

		context.raw_content = raw_content_result
		self:open_selector(context, tokens, was_paused)
	end)
end

-- Open selector interface with provided tokens
function Handler:open_selector(context, tokens, was_paused)
	-- Selectable term verification
	local has_term = false
	for _, token in ipairs(tokens) do
		if token.is_term then
			has_term = true
			break
		end
	end

	if not has_term then
		msg.error("No valid tokens found")
		self.expand_to_subtitle = nil
		return Player.notify("Error: No words to select", "error", 3)
	end

	msg.info("Starting selector with " .. #tokens .. " tokens")
	Player.notify("Yomitan: Select word...")

	local update_range_fn = function(direction)
		self:update_range_async(context, direction)
	end

	local selector_style = self:build_selector_style(update_range_fn, was_paused)

	self.deps.selector:start(tokens, function(selected_token)
		self:handle_selector_result(context, selected_token)
	end, selector_style)
end

-- Process selector result and initiate field retrieval
function Handler:handle_selector_result(context, selected_token)
	self.expand_to_subtitle = nil -- Cleanup state

	if self.deps.history then
		if self.config.selector_show_history and not context.history_was_open then
			self.deps.history:close()
		else
			self.deps.history:update(true)
		end
	end

	if not selected_token then
		msg.info("Selector cancelled")
		return
	end

	if selected_token == "prev_sub" or selected_token == "next_sub" then
		return
	end

	local yomitan_fields = self:build_yomitan_fields()

	self.deps.yomitan:get_anki_fields(selected_token.text, yomitan_fields, {
		text = context.current_subtitle_text,
		start = selected_token.offset,
		["end"] = selected_token.offset + selected_token.text:len(),
	}, function(data, error)
		self:handle_anki_fields_result(context, selected_token, data, error)
	end)
end

-- Handle retrieved Anki fields and initiate media capture
function Handler:handle_anki_fields_result(context, selected_token, data, error)
	if error then
		msg.error("Yomitan API error: " .. error)
		return Player.notify("Yomitan API error: " .. error, "error", 4)
	end

	local entry = data.fields
	if not entry then
		msg.warn("No dictionary entry for " .. selected_token.text)
		return Player.notify("Error: No dictionary entry.", "warn", 2)
	end

	Player.notify("Yomitan: Capturing media...")
	self.deps.anki:get_media_path(function(media_dir, media_err)
		if media_err or not media_dir or media_dir == "" then
			msg.error("Anki media path error: " .. tostring(media_err))
			return Player.notify("Error: Cannot access Anki media folder.", "error", 4)
		end

		self.deps.media.set_output_dir(media_dir)
		local picture = self.deps.media.picture.create_job(context.sub)
		local audio = self.deps.media.audio.create_job(context.sub, self.deps.builder:_safety_buffer())

		self:capture_media(context, entry, data, picture, audio, selected_token)
	end)
end

-- Capture picture and audio media for current context
function Handler:capture_media(context, entry, data, picture, audio, selected_token)
	msg.info("Starting media jobs")

	local media_counter = Counter.new(2):on_finish(function()
		self:process_note_content(context, entry, data, picture, audio, selected_token)
	end)

	local function on_job_finish(success)
		if not success then
			msg.warn("A media job failed, but proceeding with note creation")
		end
		media_counter:decrease()
	end

	if picture then
		picture:on_finish(on_job_finish):run()
	else
		media_counter:decrease()
	end

	if audio then
		audio:on_finish(on_job_finish):run()
	else
		media_counter:decrease()
	end
end

-- Process fields and format HTML content for final note
function Handler:process_note_content(context, entry, data, picture, audio, selected_token)
	local note_fields = self.deps.builder:construct_note_fields(
		context.sub.secondary_sid,
		picture and picture.target_file,
		audio and audio.result_file
	)
	msg.info("Secondary SID for note: '" .. tostring(context.sub.secondary_sid) .. "'")

	local cloze_prefix, cloze_body, cloze_suffix =
		get_field_value(entry, "cloze-prefix"),
		get_field_value(entry, "cloze-body"),
		get_field_value(entry, "cloze-suffix")

	if Collections.is_void(cloze_body) then
		cloze_prefix, cloze_body, cloze_suffix =
			split_cloze(context.sub.primary_sid, entry.expression, selected_token.text, selected_token.offset)
	end

	if not Collections.is_void(self.config.sentence_field) then
		note_fields[self.config.sentence_field] =
			format_sentence_html(self, cloze_prefix, cloze_body, cloze_suffix, self.config.sentence_highlight_tag)
	end

	-- Handling furigana
	local sentence_furigana = get_field_value(entry, "sentence-furigana")
	local furigana_key = self.config.sentence_furigana_field

	if Collections.is_void(furigana_key) then
		self:finalize_and_save_note(context, note_fields, entry, data)
	elseif context.expansion_occurred or Collections.is_void(sentence_furigana) then
		self.deps.yomitan:get_sentence_furigana(context.current_subtitle_text, function(furigana_html)
			note_fields[furigana_key] = string.format(self.config.primary_sentence_wrapper, furigana_html or "")
			self:finalize_and_save_note(context, note_fields, entry, data)
		end, context.raw_content)
	else
		note_fields[furigana_key] = string.format(self.config.primary_sentence_wrapper, sentence_furigana or "")
		self:finalize_and_save_note(context, note_fields, entry, data)
	end
end

-- Finalize note field values and persist to Anki
function Handler:finalize_and_save_note(context, note_fields, entry, data)
	self:apply_yomitan_fields(note_fields, entry)

	Player.notify("Yomitan: Saving media...")
	self:save_yomitan_media(data, function()
		self:perform_anki_save(context, note_fields)
	end)
end

-- Map Yomitan fields to target Anki fields based on configuration
function Handler:apply_yomitan_fields(note_fields, entry)
	local function set_field(config_key, value)
		if not Collections.is_void(config_key) then
			note_fields[config_key] = value
		end
	end

	set_field(self.config.expression_field, get_field_value(entry, "expression"))
	set_field(self.config.reading_field, get_field_value(entry, "reading"))
	set_field(self.config.pitch_accents_field, get_field_value(entry, "pitch-accents"))
	set_field(self.config.pitch_categories_field, get_field_value(entry, "pitch-accent-categories"))
	set_field(self.config.pitch_position_field, get_field_value(entry, "pitch-accent-positions"))
	set_field(self.config.freq_field, get_field_value(entry, "frequencies"))
	set_field(self.config.freq_sort_field, get_field_value(entry, "frequency-harmonic-rank"))

	-- Only set dictionary preference for Senren note types
	if self.config.note_type and self.config.note_type:find("Senren") then
		set_field(self.config.dictionary_pref_field, self.config.dictionary_pref_value)
	end

	if self.config.definition_handlebar and self.config.definition_handlebar ~= "" then
		set_field(self.config.definition_field, get_field_value(entry, self.config.definition_handlebar))
	end

	if self.config.glossary_handlebar and self.config.glossary_handlebar ~= "" then
		set_field(self.config.glossary_field, get_field_value(entry, self.config.glossary_handlebar))
	end

	if entry.audio and not Collections.is_void(self.config.expression_audio_field) then
		note_fields[self.config.expression_audio_field] = entry.audio
	end
end

-- Perform the final save to Anki

-- Async and expansion helpers
-- Expand selection to include target subtitle context
function Handler:expand_to_subtitle_method(context, target_subtitle)
	if not target_subtitle or not target_subtitle.start then
		return
	end

	-- Jumps to time if selector is inactive
	if not self.deps.selector.active then
		if target_subtitle.start >= 0 then
			mp.set_property_number("time-pos", target_subtitle.start)
			Player.notify("Jumped to " .. StringOps.format_duration(target_subtitle.start))
		end
		return
	end

	-- Expand step-by-step
	if target_subtitle.start < context.first_subtitle.start then
		local function step_back()
			msg.info(
				string.format(
					"Expanding back... current: %.3f, target: %.3f",
					context.first_subtitle.start,
					target_subtitle.start
				)
			)
			if context.first_subtitle.start > target_subtitle.start then
				self:update_range_async(context, -1, function()
					mp.add_timeout(EXPANSION_TIMEOUT, step_back)
				end)
			end
		end
		step_back()
	elseif target_subtitle.start > context.last_subtitle.start then
		local function step_forward()
			msg.info(
				string.format(
					"Expanding forward... current: %.3f, target: %.3f",
					context.last_subtitle.start,
					target_subtitle.start
				)
			)
			if context.last_subtitle.start < target_subtitle.start then
				self:update_range_async(context, 1, function()
					mp.add_timeout(EXPANSION_TIMEOUT, step_forward)
				end)
			end
		end
		step_forward()
	end
end

-- Update token range asynchronously in specified direction
function Handler:update_range_async(context, direction, completion_callback)
	if not self.deps.selector.active or self.is_expanding then
		return
	end

	self.is_expanding = true
	local target = direction < 0 and context.first_subtitle or context.last_subtitle

	-- Wrapper to clear lock before calling completion
	local function done()
		self.is_expanding = false
		if completion_callback then
			completion_callback()
		end
	end

	self.deps.tracker.get_adjacent_sub_async(target, direction, function(adjacent_subtitle)
		if not adjacent_subtitle then
			Player.notify("No more subtitles to include", "info", 1)
			done()
			return
		end

		Player.notify("Expanding...", "info", 1)

		self.deps.yomitan:tokenize(
			StringOps.clean_subtitle(adjacent_subtitle.primary_sid),
			function(new_tokens, new_raw_content, expansion_error)
				if expansion_error or not new_tokens then
					Player.notify("Expansion failed", "error")
					done()
					return
				end

				context.raw_content = merge_raw_content(context.raw_content, new_raw_content, direction)
				context.expansion_occurred = true

				local cleaned_adjacent_sid = StringOps.clean_subtitle(adjacent_subtitle.primary_sid)
				local cleaned_adjacent_secondary_sid = StringOps.clean_subtitle(adjacent_subtitle.secondary_sid)

				if direction < 0 then
					context.first_subtitle = adjacent_subtitle
					local shift = #cleaned_adjacent_sid + 1
					context.current_subtitle_text = cleaned_adjacent_sid .. "\n" .. context.current_subtitle_text

					context.sub["primary_sid"] = cleaned_adjacent_sid .. "\n" .. context.sub["primary_sid"]
					context.sub["secondary_sid"] = cleaned_adjacent_secondary_sid
						.. "\n"
						.. context.sub["secondary_sid"]
					context.sub["start"] = adjacent_subtitle["start"]

					self.deps.selector:prepend_tokens(new_tokens, shift)
				else
					context.last_subtitle = adjacent_subtitle
					context.current_subtitle_text = context.current_subtitle_text .. "\n" .. cleaned_adjacent_sid

					context.sub["primary_sid"] = context.sub["primary_sid"] .. "\n" .. cleaned_adjacent_sid
					context.sub["secondary_sid"] = context.sub["secondary_sid"]
						.. "\n"
						.. cleaned_adjacent_secondary_sid
					context.sub["end"] = adjacent_subtitle["end"]

					self.deps.selector:append_tokens(new_tokens)
				end

				done()
			end
		)
	end)
end
-- Builders and utilities
-- Build configuration style for selector UI
function Handler:build_selector_style(update_range_fn, was_paused)
	return {
		font_size = self.config.selector_font_size,
		font_name = self.config.selector_font_name,
		color = self.config.selector_color,
		selection_color = self.config.selector_selection_color,
		border_color = self.config.selector_border_color,
		shadow_color = self.config.selector_shadow_color,
		border_size = self.config.selector_border_size,
		shadow_offset = self.config.selector_shadow_offset,
		bold = self.config.selector_bold,
		pos_y = self.config.selector_pos_y,
		hide_ui = self.config.selector_hide_ui,
		max_width_factor = self.config.selector_max_width_factor,
		line_height = self.config.selector_line_height,
		key_confirm = self.config.key_selector_confirm,
		key_cancel = self.config.key_selector_cancel,
		key_left = self.config.key_selector_left,
		key_right = self.config.key_selector_right,
		key_up = self.config.key_selector_up,
		key_down = self.config.key_selector_down,
		key_expand_prev = self.config.key_expand_prev,
		key_expand_next = self.config.key_expand_next,
		key_lookup = self.config.key_selector_lookup,
		key_split = self.config.key_selector_split,
		navigation_delay = self.config.selector_navigation_delay,
		lookup_on_hover = self.config.selector_lookup_on_hover,
		lookup_on_navigation = self.config.selector_lookup_on_navigation,
		yomitan = self.deps.yomitan,
		on_expand_prev = function()
			update_range_fn(-1)
		end,
		on_expand_next = function()
			update_range_fn(1)
		end,
		on_click_fallback = function()
			if self.deps.history then
				self.deps.history:handle_click()
			end
		end,
		on_hover_fallback = function()
			if self.deps.history then
				self.deps.history:handle_mouse_move()
			end
		end,
		on_lookup = function(data)
			local json_body = require("mp.utils").format_json(data)
			-- Use direct subprocess for reliability with explicit UTF-8 header
			mp.command_native_async({
				name = "subprocess",
				playback_only = false,
				args = {
					Platform.get_curl_cmd(),
					"-s",
					"-X",
					"POST",
					"-H",
					"Content-Type: application/json; charset=utf-8",
					"-d",
					json_body,
					"--connect-timeout",
					"1",
					"http://127.0.0.1:19634",
				},
			}, function() end)
		end,
		on_hide = function()
			-- Use a direct subprocess call for maximal reliability
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
					"http://127.0.0.1:19634/hide",
				},
			}, function() end)
		end,
		should_resume = not was_paused,
	}
end

-- Build array of field names for retrieval
function Handler:build_yomitan_fields()
	local fields = Collections.duplicate(DEFAULT_YOMITAN_FIELDS)

	if self.config.definition_handlebar and self.config.definition_handlebar ~= "" then
		table.insert(fields, self.config.definition_handlebar)
	end

	if self.config.glossary_handlebar and self.config.glossary_handlebar ~= "" then
		table.insert(fields, self.config.glossary_handlebar)
	end

	return fields
end

function Handler:save_yomitan_media(data, completion_fn)
	local media_list = {}
	if data.dictionaryMedia then
		for _, m in ipairs(data.dictionaryMedia) do
			table.insert(media_list, m)
		end
	end
	if data.audioMedia then
		for _, m in ipairs(data.audioMedia) do
			table.insert(media_list, m)
		end
	end

	if #media_list == 0 then
		return completion_fn()
	end

	local counter = Counter.new(#media_list):on_finish(completion_fn)
	local on_done = function()
		counter:decrease()
	end
	for _, m in ipairs(media_list) do
		self.deps.anki:ingest_media(m.ankiFilename, m.content, on_done)
	end
end

function Handler:change_fields(note_ids, new_data)
	local change_notes_countdown = Counter.new(#note_ids):on_finish(function()
		self:notify_user_on_finish(note_ids)
	end)

	for _, note_id in ipairs(note_ids) do
		self.deps.anki:get_note_fields(note_id, function(existing_fields, error)
			if error then
				msg.warn("Failed to get fields for note " .. note_id .. ": " .. error)
				change_notes_countdown:decrease()
				return
			end

			local updated_data = self.deps.builder:_make_new_note_data(existing_fields, Collections.duplicate(new_data))

			self.deps.anki:sync_media_fields(
				note_id,
				updated_data,
				self.deps.formatter:substitute(self.config.note_tag),
				function()
					change_notes_countdown:decrease()
				end
			)
		end)
	end
end

-- Creates new Handler instance
function Handler:new()
	local obj = {
		config = nil,
		deps = nil,
		expand_to_subtitle = nil,
	}
	setmetatable(obj, self)
	self.__index = self
	return obj
end

-- Final note addition to Anki
function Handler:perform_anki_save(_context, note_fields)
	Player.notify("Yomitan: Saving to Anki...")

	self.deps.anki:add_note(
		self.config.deck,
		self.config.note_type,
		note_fields,
		self.config.note_tag,
		function(note_id, error)
			if error then
				if error:match("duplicate") and self.config.update_if_exists then
					msg.info("Note exists, attempting update...")
					self:handle_duplicate_note(note_fields, error)
				else
					msg.error("Failed to add note: " .. error)
					Player.notify("Failed to add note: " .. error, "error", 4)
				end
			else
				msg.info("Note added successfully: " .. tostring(note_id))
				Player.notify("Note added to Anki!", "success", 2)
				self.deps.anki:gui_browse("nid:" .. tostring(note_id), function() end)
			end
		end
	)
end

-- Handles duplicate note by updating if configured
function Handler:handle_duplicate_note(note_fields, _error_msg)
	local expression = note_fields[self.config.expression_field]
	if not expression then
		return Player.notify("Cannot update: no expression field", "error", 3)
	end

	self.deps.anki:find_notes(expression, function(note_ids, error)
		if error or not note_ids or #note_ids == 0 then
			return Player.notify("Cannot find existing note", "error", 3)
		end

		self:change_fields(note_ids, note_fields)
	end)
end

-- Notifies user on finish
function Handler:notify_user_on_finish(note_ids)
	Player.notify("Updated " .. #note_ids .. " note(s)", "success", 2)

	if self.config.refresh_gui_after_update and note_ids and #note_ids > 0 then
		-- Select single note to prevent UI instability
		local first_nid = note_ids[1]
		local query = "nid:" .. tostring(first_nid)

		-- Browse to note to ensure visibility
		self.deps.anki:gui_browse(query, function()
			-- Select explicitly to refresh editor pane
			self.deps.anki:gui_select_note(first_nid, function() end)
		end)
	end
end

return Handler
