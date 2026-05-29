--[[ Anki Database Builder ]]

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")
local Platform = require("lib.platform")
local JSONFormat = require("lib.json_format")

local AnkiDBBuilder = {}

local BATCH_SIZE = 50

local function trim(text)
	if type(text) ~= "string" then return nil end
	local trimmed = text:gsub("^%s*(.-)%s*$", "%1")
	return trimmed ~= "" and trimmed or nil
end

local function parse_field_list(raw)
	local fields = {}
	local text = trim(raw)
	if not text then
		return fields
	end

	local i = 1
	while i <= #text do
		while i <= #text and text:sub(i, i):match("%s") do
			i = i + 1
		end
		if i > #text then
			break
		end

		local char = text:sub(i, i)
		if char == '"' or char == "'" then
			local quote = char
			local j = i + 1
			while j <= #text and text:sub(j, j) ~= quote do
				j = j + 1
			end
			local value = trim(text:sub(i + 1, j - 1))
			if value then
				table.insert(fields, value)
			end
			i = j + 1
		else
			local j = i
			while j <= #text and not text:sub(j, j):match("%s") do
				j = j + 1
			end
			local value = trim(text:sub(i, j - 1))
			if value then
				table.insert(fields, value)
			end
			i = j
		end
	end

	return fields
end

local function get_word_fields(config)
	return parse_field_list(config.ankidb_word_fields)
end

local function get_reading_fields(config)
	local raw = config.ankidb_reading_fields
	if trim(raw) then
		return parse_field_list(raw)
	end

	local reading_field = trim(config.reading_field)
	if reading_field then
		return { reading_field }
	end

	return {}
end

local function add_reading(entry, reading)
	if not reading then
		return
	end

	if type(entry.reading) == "string" then
		if entry.reading == reading then
			return
		end
		entry.reading = { entry.reading, reading }
	elseif type(entry.reading) == "table" then
		for _, existing in ipairs(entry.reading) do
			if existing == reading then
				return
			end
		end
		table.insert(entry.reading, reading)
	else
		entry.reading = { reading }
	end
end

function AnkiDBBuilder.new(config, anki)
	local obj = {
		config = config,
		anki = anki,
	}
	setmetatable(obj, { __index = AnkiDBBuilder })
	return obj
end

function AnkiDBBuilder:build(callback)
	local fields = get_word_fields(self.config)
	local reading_fields = get_reading_fields(self.config)

	if #fields == 0 then
		return callback(false, "No fields configured for Anki database build")
	end

	local query_parts = {}
	for _, f in ipairs(fields) do
		table.insert(query_parts, f .. ":*")
	end
	local query = table.concat(query_parts, " OR ")

	msg.info("AnkiDBBuilder: Starting build with fields: " .. table.concat(fields, ", "))

	self.anki:find_cards(query, function(card_ids, err)
		if err then
			return callback(false, "AnkiConnect findCards error: " .. tostring(err))
		end

		if not card_ids or #card_ids == 0 then
			return callback(false, "No cards found for configured fields")
		end

		local total_cards = #card_ids
		msg.info("AnkiDBBuilder: Found " .. total_cards .. " cards")

		local note_data = {}
		local state_priority = { Review = 3, Learning = 2, New = 1, Suspended = 0 }

		local function process_cards_batch(index)
			if index > total_cards then
				return self:process_notes(note_data, fields, reading_fields, callback)
			end

			local batch = {}
			for i = index, math.min(index + BATCH_SIZE - 1, total_cards) do
				table.insert(batch, card_ids[i])
			end

			self.anki:cards_info(batch, function(cards, card_err)
				if card_err then
					return callback(false, "AnkiConnect cardsInfo error: " .. tostring(card_err))
				end

				for _, card in ipairs(cards) do
					local nid = card.note
					local interval = card.interval or 0
					local queue = card.queue or 0
					local state = "New"

					if queue == -1 then
						state = "Suspended"
					elseif queue == 0 then
						state = "New"
					elseif queue == 1 or queue == 3 then
						state = "Learning"
					elseif queue == 2 then
						state = "Review"
					end

					if not note_data[nid] then
						note_data[nid] = { interval = interval, state = state }
					else
						local old = note_data[nid]
						old.interval = math.max(old.interval, interval)
						if state_priority[state] > state_priority[old.state] then
							old.state = state
						end
					end
				end

				if self.on_progress then
					self.on_progress(index + #batch, total_cards * 2)
				end
				process_cards_batch(index + BATCH_SIZE)
			end)
		end

		process_cards_batch(1)
	end)
end

function AnkiDBBuilder:process_notes(note_data, fields, reading_fields, callback)
	local note_ids = {}
	for nid, _ in pairs(note_data) do
		table.insert(note_ids, nid)
	end

	local total_notes = #note_ids
	local word_data = {}

	local function process_notes_batch(index)
		if index > total_notes then
			return self:save_database(word_data, fields, callback)
		end

		local batch = {}
		for i = index, math.min(index + BATCH_SIZE - 1, total_notes) do
			table.insert(batch, note_ids[i])
		end

		self.anki:notes_info(batch, function(notes, err)
			if err then
				return callback(false, "AnkiConnect notesInfo error: " .. tostring(err))
			end

			for _, note in ipairs(notes) do
				local nid = tonumber(note.noteId)
				local note_fields = note.fields
				local word = nil
				local reading = nil

				for _, f in ipairs(fields) do
					local field_data = note_fields[f]
					if field_data and field_data.value and field_data.value:gsub("%s+", "") ~= "" then
						word = trim(field_data.value)
						break
					end
				end

				for _, reading_field in ipairs(reading_fields) do
					local field_data = note_fields[reading_field]
					if field_data and field_data.value then
						reading = trim(field_data.value)
						if reading then
							break
						end
					end
				end

				if word then
					local res = note_data[nid]
					if not word_data[word] then
						word_data[word] = { interval = res.interval, state = res.state }
						add_reading(word_data[word], reading)
					else
						local existing = word_data[word]
						if res.interval > existing.interval then
							existing.interval = res.interval
							existing.state = res.state
						end
						add_reading(existing, reading)
					end
				end
			end

			if self.on_progress then
				self.on_progress(total_notes + index + #batch, total_notes * 2)
			end
			process_notes_batch(index + BATCH_SIZE)
		end)
	end

	process_notes_batch(1)
end

function AnkiDBBuilder.save_database(_, word_data, fields, callback)
	local db = {
		generated_at = os.date("%Y-%m-%dT%H:%M:%S"),
		fields = fields,
		words = word_data,
	}

	local script_dir = mp.get_script_directory()
	local output_path = utils.join_path(script_dir, "../../script-opts/anki_words.json")
	local absolute_output_path = Platform.normalize_path(mp.command_native({ "expand-path", output_path }))

	local json_data = JSONFormat.format(db)
	local f = io.open(absolute_output_path, "w")
	if not f then
		return callback(false, "Failed to open output file for writing: " .. absolute_output_path)
	end

	f:write(json_data)
	f:close()

	msg.info("AnkiDBBuilder: Build completed. Saved " .. (function()
		local count = 0
		for _ in pairs(word_data) do
			count = count + 1
		end
		return count
	end)() .. " unique words to: " .. absolute_output_path)

	callback(true, nil)
end

function AnkiDBBuilder:build_with_notification(handler)
	local Player = require("lib.player")

	self.on_progress = function(current, total)
		local percent = math.floor((current / total) * 100)
		local progress = current / total
		local bar = string.rep("▰", math.floor(progress * 15)) .. string.rep("▱", 15 - math.floor(progress * 15))
		Player.notify(string.format("Building Anki database... %s %d%%", bar, percent), "info", 1)
	end

	Player.notify("Building Anki database...", "info", 5)

	self:build(function(success, err)
		if success then
			Player.notify("Anki database built successfully", "success")
			require("lib.anki_db").reload()
			if handler and handler.current_tokens then
				handler:on_current_tokens_ready(handler.current_tokens)
			end
		else
			Player.notify("Failed to build Anki database", "error")
			msg.error("AnkiDB build failed: " .. tostring(err))
		end
	end)
end

return AnkiDBBuilder
