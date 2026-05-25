--[[ Anki word database loader and color resolver ]]

local mp = require("mp")
local utils = require("mp.utils")
local msg = require("mp.msg")
local JSONFormat = require("lib.json_format")
local Conjugations = require("lib.conjugations")
local options = require("options")

local AnkiDB = {}

local _db = nil
local _loaded = false

local function lerp_hex(r1, g1, b1, r2, g2, b2, t)
	local r = math.floor(r1 + (r2 - r1) * t + 0.5)
	local g = math.floor(g1 + (g2 - g1) * t + 0.5)
	local b = math.floor(b1 + (b2 - b1) * t + 0.5)
	-- Return as ASS BGR hex
	return string.format("%02X%02X%02X", b, g, r)
end

-- New: Red
local NEW_COLOR = "2020FF"

-- Suspended: Dark Red
local SUSPENDED_COLOR = "00008B"

-- Learning: Orange (#FF8C00) -> Yellow (#FFE000), keyed by interval days
local LEARNING_MAX = 21
local LEARNING_R1, LEARNING_G1, LEARNING_B1 = 0xFF, 0x8C, 0x00
local LEARNING_R2, LEARNING_G2, LEARNING_B2 = 0xFF, 0xE0, 0x00

-- Review: Yellow-Green (#AAFF00) -> Cyan (#00FFCC), keyed by interval days
local REVIEW_MAX = 2000
local REVIEW_R1, REVIEW_G1, REVIEW_B1 = 0xAA, 0xFF, 0x00
local REVIEW_R2, REVIEW_G2, REVIEW_B2 = 0x00, 0xFF, 0xCC

local function load_db()
	if _loaded then
		return _db
	end
	_loaded = true

	local path = mp.find_config_file("script-opts/anki_words.json")
	if not path then
		msg.warn("anki_db: anki_words.json not found in script-opts/")
		return nil
	end

	local file = io.open(path, "r")
	if not file then
		msg.warn("anki_db: cannot open " .. path)
		return nil
	end

	local content = file:read("*a")
	file:close()

	local ok, parsed = pcall(utils.parse_json, content)
	if not ok or type(parsed) ~= "table" or type(parsed.words) ~= "table" then
		msg.warn("anki_db: failed to parse anki_words.json")
		return nil
	end

	_db = parsed.words
	local count = 0
	for _ in pairs(_db) do count = count + 1 end
	msg.info("anki_db: loaded " .. tostring(count) .. " words")
	return _db
end

local function word_color(entry)
	if not entry then return nil end
	local state = entry.state
	local interval = entry.interval or 0

	if state == "New" then
		return NEW_COLOR
	elseif state == "Suspended" then
		return SUSPENDED_COLOR
	elseif state == "Learning" then
		local t = math.min(interval / LEARNING_MAX, 1.0)
		return lerp_hex(LEARNING_R1, LEARNING_G1, LEARNING_B1, LEARNING_R2, LEARNING_G2, LEARNING_B2, t)
	elseif state == "Review" then
		local t = math.min(interval / REVIEW_MAX, 1.0)
		return lerp_hex(REVIEW_R1, REVIEW_G1, REVIEW_B1, REVIEW_R2, REVIEW_G2, REVIEW_B2, t)
	end
	return nil
end

local function callback_deconjugated_base(base, stripped_bytes, kind, callback)
	for _, candidate in ipairs(Conjugations.get_base_candidates(base)) do
		local r1, r2, r3, r4 = callback(candidate, stripped_bytes, kind)
		if r1 ~= nil then return r1, r2, r3, r4 end
	end
	return nil
end

local function each_deconjugated_term(term, callback)
	if type(term) ~= "string" or term == "" then
		return nil
	end

	for _, p in ipairs(Conjugations.noun_suffixes) do
		if #term > #p and term:sub(-#p) == p then
			local stripped = term:sub(1, -(#p + 1))
			if #stripped >= 3 then
				local r1, r2, r3, r4 = callback_deconjugated_base(stripped, #p, "suffix_strip", callback)
				if r1 ~= nil then return r1, r2, r3, r4 end
			end
		end
	end

	for _, adj in ipairs(Conjugations.adj_endings) do
		local p = adj.ending
		if #term > #p and term:sub(-#p) == p then
			local stripped = term:sub(1, -(#p + 1)) .. adj.rep
			if #stripped >= 3 and not Conjugations.is_invalid_adj_base(term, stripped) then
				local r1, r2, r3, r4 = callback_deconjugated_base(stripped, 0, "inflection", callback)
				if r1 ~= nil then return r1, r2, r3, r4 end
			end
		end
	end

	for _, p in ipairs(Conjugations.na_adj_endings) do
		if #term > #p and term:sub(-#p) == p then
			local stripped = term:sub(1, -(#p + 1))
			if #stripped >= 3 then
				local r1, r2, r3, r4 = callback_deconjugated_base(stripped, 0, "inflection", callback)
				if r1 ~= nil then return r1, r2, r3, r4 end
			end
		end
	end

	for _, verb in ipairs(Conjugations.verb_endings) do
		local p = verb.ending
		if Conjugations.is_valid_verb_match(term, p, verb.rep) and term:sub(-#p) == p then
			local stripped = term:sub(1, -(#p + 1)) .. verb.rep
			if #stripped >= 3 then
				local r1, r2, r3, r4 = callback_deconjugated_base(stripped, 0, "inflection", callback)
				if r1 ~= nil then return r1, r2, r3, r4 end
			end
		end
	end

	return nil
end

local function find_clean_term(db, term)
	if type(term) ~= "string" or term == "" then return nil, nil, 0, nil end
	local entry = db[term]
	if entry then return entry, term, 0, "exact" end
	for _, candidate in ipairs(Conjugations.get_base_candidates(term)) do
		if candidate ~= term then
			entry = db[candidate]
			if entry then return entry, candidate, 0, "exact" end
		end
	end

	local stripped_entry, stripped, stripped_bytes, match_kind = each_deconjugated_term(
		term,
		function(base, base_stripped_bytes, kind)
		local entry_for_base = db[base]
		if entry_for_base then
			return entry_for_base, base, base_stripped_bytes, kind
		end
	end
	)
	if stripped_entry then
		return stripped_entry, stripped, stripped_bytes, match_kind
	end

	return nil, nil, 0, nil
end

local function has_database_match(db, term)
	if type(term) ~= "string" or term == "" then
		return false
	end

	local entry = find_clean_term(db, term)
	return entry ~= nil
end

local function get_surface_match_bytes(surface_text, stripped_bytes, match_kind)
	if match_kind == "suffix_strip" then
		return math.max(0, #surface_text - (stripped_bytes or 0))
	end
	return #surface_text
end

local function get_source_match_bytes(source, surface)
	if type(source) ~= "table" or type(surface) ~= "string" or surface == "" then
		return nil
	end

	local original = source.originalText or source.transformedText
	if type(original) ~= "string" or original == "" then
		return nil
	end

	if original == surface then
		return #original
	end

	if original:sub(1, #surface) == surface then
		return #original
	end

	return nil
end

local function get_headword_source_match_bytes(hw, surface)
	if type(hw) ~= "table" or type(hw.sources) ~= "table" then
		return nil
	end

	for _, source in ipairs(hw.sources) do
		local bytes = get_source_match_bytes(source, surface)
		if bytes then
			return bytes
		end
	end
	return nil
end

local get_reading_spelling_candidates

local function resolve_term_color(db, hw, surface_text)
	if type(hw) == "string" then
		if hw ~= "" then
			local entry, matched, stripped, match_kind = find_clean_term(db, hw)
			if entry then return word_color(entry), matched, stripped, hw, match_kind end
		end
	elseif type(hw) == "table" then
		local term = hw.term or hw.expression
		local hw_reading = hw.reading or term
		if type(term) == "string" and term ~= "" then
			local entry, matched, stripped, match_kind = find_clean_term(db, term)
			if entry then
				return word_color(entry), matched, stripped, hw_reading, match_kind,
					get_headword_source_match_bytes(hw, surface_text)
			end
		end
		for _, candidate in ipairs(get_reading_spelling_candidates(term, hw_reading)) do
			local entry, matched, stripped, match_kind = find_clean_term(db, candidate)
			if entry then
				return word_color(entry), matched, stripped, hw_reading, match_kind,
					get_headword_source_match_bytes(hw, surface_text)
			end
		end
		if type(hw_reading) == "string" and hw_reading ~= "" and hw_reading ~= term then
			local entry, matched, stripped, match_kind = find_clean_term(db, hw_reading)
			if entry then
				return word_color(entry), matched, stripped, hw_reading, match_kind,
					get_headword_source_match_bytes(hw, surface_text)
			end
		end

		for _, v in ipairs(hw) do
			local color, found_term, stripped, found_reading, match_kind, source_match_bytes =
				resolve_term_color(db, v, surface_text)
			if color then return color, found_term, stripped, found_reading, match_kind, source_match_bytes end
		end
	end
	return nil
end

local function contains_kanji(text)
	if type(text) ~= "string" or text == "" then return false end
	local i = 1
	local len = #text
	while i <= len do
		local b1 = text:byte(i)
		if b1 >= 0xE3 and b1 <= 0xEF then
			local b2 = text:byte(i + 1)
			-- Main Kanji block: U+4E00..U+9FFF (E4 B8 80 .. E9 BF BF)
			if b1 >= 0xE4 and b1 <= 0xE9 then
				return true
			-- Extension A: U+3400..U+4DBF (E3 90 80 .. E4 B6 BF)
			elseif b1 == 0xE3 and b2 and b2 >= 0x90 then
				return true
			-- CJK Compatibility Ideographs: U+F900..U+FAFF (EF A4 80 .. EF AB BF)
			elseif b1 == 0xEF and b2 and b2 >= 0xA4 and b2 <= 0xAB then
				return true
			end
			i = i + 3
		elseif b1 >= 0xF0 then
			-- 4-byte kanji Extensions
			return true
		elseif b1 >= 0xE0 then
			i = i + 3
		elseif b1 >= 0xC0 then
			i = i + 2
		else
			i = i + 1
		end
	end
	return false
end

local function split_utf8_chars(text)
	local chars = {}
	local i = 1
	while i <= #text do
		local byte = text:byte(i)
		local len = 1
		if byte and byte >= 0xC0 then
			if byte >= 0xF0 then
				len = 4
			elseif byte >= 0xE0 then
				len = 3
			else
				len = 2
			end
		end
		table.insert(chars, text:sub(i, i + len - 1))
		i = i + len
	end
	return chars
end

local function next_literal(chars, start_index)
	local literal = ""
	for i = start_index, #chars do
		if contains_kanji(chars[i]) then
			break
		end
		literal = literal .. chars[i]
	end
	return literal
end

local function build_reading_pieces(term, reading)
	if type(term) ~= "string" or type(reading) ~= "string"
		or term == "" or reading == "" or not contains_kanji(term) then
		return nil
	end

	local chars = split_utf8_chars(term)
	local pieces = {}
	local reading_pos = 1
	local i = 1
	local has_literal = false

	while i <= #chars do
		local char = chars[i]
		if contains_kanji(char) then
			local original = ""
			repeat
				original = original .. chars[i]
				i = i + 1
			until i > #chars or not contains_kanji(chars[i])

			local literal = next_literal(chars, i)
			local end_pos = #reading + 1
			if literal ~= "" then
				local found = reading:find(literal, reading_pos, true)
				if not found then return nil end
				end_pos = found
			end

			local replacement = reading:sub(reading_pos, end_pos - 1)
			if replacement == "" then return nil end
			table.insert(pieces, { original = original, replacement = replacement, replaceable = true })
			reading_pos = end_pos
		else
			if reading:sub(reading_pos, reading_pos + #char - 1) ~= char then
				return nil
			end
			has_literal = true
			table.insert(pieces, { original = char, replaceable = false })
			reading_pos = reading_pos + #char
			i = i + 1
		end
	end

	if reading_pos <= #reading then
		return nil
	end
	if not has_literal then
		return nil
	end
	return pieces
end

function get_reading_spelling_candidates(term, reading)
	local pieces = build_reading_pieces(term, reading)
	if not pieces then return {} end

	local group_count = 0
	for _, piece in ipairs(pieces) do
		if piece.replaceable then group_count = group_count + 1 end
	end
	if group_count == 0 or group_count > 8 then return {} end

	local candidates = {}
	local max_mask = (2 ^ group_count) - 1
	for mask = 1, max_mask do
		local group_index = 0
		local candidate = ""
		for _, piece in ipairs(pieces) do
			if piece.replaceable then
				group_index = group_index + 1
				local bit = 2 ^ (group_index - 1)
				if math.floor(mask / bit) % 2 == 1 then
					candidate = candidate .. piece.replacement
				else
					candidate = candidate .. piece.original
				end
			else
				candidate = candidate .. piece.original
			end
		end
		if candidate ~= term then
			table.insert(candidates, candidate)
		end
	end
	return candidates
end

local function is_single_kana_string(text)
	if type(text) ~= "string" or #text ~= 3 then return false end
	local b1, b2 = text:byte(1, 2)
	return b1 == 0xE3 and (b2 == 0x81 or b2 == 0x82 or b2 == 0x83)
end

local function utf8_char_len_at(text, byte_index)
	local byte = text:byte(byte_index)
	if not byte then return 1 end
	if byte >= 0xC0 then
		if byte >= 0xE0 then
			if byte >= 0xF0 then return 4 end
			return 3
		end
		return 2
	end
	return 1
end

local function utf8_char_count(text)
	if type(text) ~= "string" or text == "" then
		return 0
	end

	local count = 0
	local i = 1
	while i <= #text do
		i = i + utf8_char_len_at(text, i)
		count = count + 1
	end
	return count
end

local function matches_base_form(term, target)
	if type(term) ~= "string" or term == "" or type(target) ~= "string" or target == "" then
		return false
	end

	if term == target then
		return true
	end

	return each_deconjugated_term(term, function(base)
		if base == target then
			return true
		end
	end) == true
end

local function token_matches_headword(token_text, token_reading, matched_term, matched_reading)
	if type(token_text) ~= "string" or token_text == "" then
		return false
	end

	local reading = (type(token_reading) == "string" and token_reading ~= "") and token_reading or token_text
	local headword_reading = (type(matched_reading) == "string" and matched_reading ~= "")
		and matched_reading or matched_term

	if token_text == matched_term then
		return true
	end

	if reading == headword_reading then
		return true
	end

	if matches_base_form(token_text, matched_term) then
		return true
	end

	if matches_base_form(reading, headword_reading) then
		return true
	end

	return false
end

-- Returns ASS-formatted BGR color or nil for any headword match in the DB
function AnkiDB.get_word_color(headwords)
	local db = load_db()
	if not db or not headwords then return nil end

	local color, term = resolve_term_color(db, headwords)
	if color then
		msg.info("anki_db: found '" .. term .. "' -> color: " .. color)
		return color, term
	end
	return nil
end

function AnkiDB.get_tokens_colors(tokens)
	local db = load_db()
	if not db or not tokens then return {} end

	local colors = {}
	local n = #tokens

	local full_text = ""
	local token_starts = {}
	local token_ends = {}
	for i = 1, n do
		token_starts[i] = #full_text + 1
		full_text = full_text .. (tokens[i].text or "")
		token_ends[i] = #full_text
	end

	local b = 1
	local current_token_idx = 1

	local function get_token_idx(byte_offset)
		while current_token_idx <= n and byte_offset > token_ends[current_token_idx] do
			current_token_idx = current_token_idx + 1
		end
		if current_token_idx <= n and byte_offset >= token_starts[current_token_idx] then
			return current_token_idx
		end
		return nil
	end

	local intervals = {}

	while b <= #full_text do
		local matched_len_bytes = nil
		local matched_color = nil
		local matched_term = nil

		local t_idx = get_token_idx(b)

		if t_idx and b == token_starts[t_idx] then
			for len = math.min(6, n - t_idx + 1), 2, -1 do
				local has_selectable = false
				local combined = ""
				for k = t_idx, t_idx + len - 1 do
					combined = combined .. (tokens[k].text or "")
					if tokens[k].is_term then has_selectable = true end
				end

				if has_selectable and combined ~= "" then
					local skip = options.colorizer_ignore_kana_only and not contains_kanji(combined)
					if skip and has_database_match(db, combined) then skip = false end

					if not skip then
						local entry, matched, stripped, match_kind = find_clean_term(db, combined)
						if entry then
							local color = word_color(entry)
							if color then
								matched_len_bytes = get_surface_match_bytes(combined, stripped, match_kind)
								matched_color = color
								matched_term = matched
								break
							end
						end
					end
				end
			end

			if not matched_len_bytes then
				local token = tokens[t_idx]
				local text_is_single_kana = is_single_kana_string(token.text or "")
				local skip_kana = options.colorizer_ignore_kana_only and not contains_kanji(token.text or "")
				if skip_kana and has_database_match(db, token.text) then
					skip_kana = false
				end

				if token.headwords and not text_is_single_kana and not skip_kana then
					local txt = token.text or ""
					local color, term_matched, stripped_bytes, hw_reading, match_kind, source_match_bytes =
						resolve_term_color(db, token.headwords, txt)
					if color then
						local tok_reading = (token.reading ~= "" and token.reading) or txt
						if source_match_bytes or token_matches_headword(txt, tok_reading, term_matched, hw_reading) then
							matched_len_bytes = source_match_bytes or get_surface_match_bytes(txt, stripped_bytes, match_kind)
							matched_color = color
							matched_term = term_matched
						end
					end
				end
			end
		end

		if not matched_len_bytes then
			local best_match_bytes = nil
			local best_color = nil
			local best_term = nil

			local char_count = 0
			local j = b
			while j <= #full_text and char_count < 20 do
				local char_len = utf8_char_len_at(full_text, j)
				j = j + char_len
				char_count = char_count + 1

				local sub = full_text:sub(b, j - 1)
				local is_single_kana = #full_text > 3 and is_single_kana_string(sub)
				local sub_char_count = utf8_char_count(sub)

				local sub_is_kana_only = options.colorizer_ignore_kana_only and not contains_kanji(sub)
				if not is_single_kana and (sub_char_count >= 2 or contains_kanji(sub)) then
					local entry, matched, stripped_bytes, match_kind = find_clean_term(db, sub)
					if entry then
						if not (sub_is_kana_only and not has_database_match(db, sub)) then
							local color = word_color(entry)
							if color then
								best_match_bytes = get_surface_match_bytes(sub, stripped_bytes, match_kind)
								best_color = color
								best_term = matched
							end
						end
					end
				end
			end

			if best_match_bytes then
				matched_len_bytes = best_match_bytes
				matched_color = best_color
				matched_term = best_term
			end
		end

		if matched_len_bytes and matched_len_bytes > 0 then
			table.insert(intervals, {
				start_byte = b,
				end_byte = b + matched_len_bytes - 1,
				color = matched_color,
				term = matched_term
			})
			b = b + matched_len_bytes
		else
			b = b + utf8_char_len_at(full_text, b)
		end
	end

	for _, inv in ipairs(intervals) do
		for i = 1, n do
			if token_ends[i] >= inv.start_byte and token_starts[i] <= inv.end_byte then
				local t_start = math.max(inv.start_byte, token_starts[i])
				local t_end = math.min(inv.end_byte, token_ends[i])

				local rel_start = t_start - token_starts[i] + 1
				local rel_end = t_end - token_starts[i] + 1

				if not colors[i] then colors[i] = {} end
				table.insert(colors[i], {
					start_byte = rel_start,
					end_byte = rel_end,
					color = inv.color,
					term = inv.term
				})
			end
		end
	end

	return colors
end

-- Forces a reload on next access
function AnkiDB.reload()
	_db = nil
	_loaded = false
end

-- Immediately add or update a word in the local cache without a full rebuild
function AnkiDB.add_word(word, state, interval)
	if not _loaded then
		load_db()
	end
	if _db and type(word) == "string" and word ~= "" then
		local new_state = state or "New"
		local new_interval = interval or 0
		_db[word] = { state = new_state, interval = new_interval }
		msg.info("anki_db: incrementally added word: " .. word)

		local path = mp.find_config_file("script-opts/anki_words.json")
		if path then
			local file = io.open(path, "r")
			if file then
				local content = file:read("*a")
				file:close()
				local ok, parsed = pcall(utils.parse_json, content)
				if ok and type(parsed) == "table" and type(parsed.words) == "table" then
					parsed.words[word] = { state = new_state, interval = new_interval }
					local new_json = JSONFormat.format(parsed)
					if new_json then
						local out_file = io.open(path, "w")
						if out_file then
							out_file:write(new_json)
							out_file:close()
						end
					end
				end
			end
		end
	end
end

return AnkiDB
