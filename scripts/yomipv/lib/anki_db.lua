--[[ Anki word database loader and color resolver ]]

local mp = require("mp")
local utils = require("mp.utils")
local msg = require("mp.msg")
local JSONFormat = require("lib.json_format")
local Conjugations = require("lib.conjugations")
local StringOps = require("lib.string_ops")
local options = require("options")

local AnkiDB = {}

local _db = nil
local _reading_index = nil
local _loaded = false
local utf8_char_count
local is_kana_only
local contains_hiragana
local contains_katakana
local contains_kanji
local is_single_kana_script
local utf8_char_len_at

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

local function trim(text)
	if type(text) ~= "string" then return nil end
	local trimmed = text:gsub("^%s*(.-)%s*$", "%1")
	return trimmed ~= "" and trimmed or nil
end

local function each_entry_reading(entry, callback)
	if type(entry) ~= "table" then
		return
	end

	if type(entry.reading) == "string" then
		local reading = trim(entry.reading)
		if reading then callback(reading) end
	elseif type(entry.reading) == "table" then
		for _, value in ipairs(entry.reading) do
			local reading = trim(value)
			if reading then callback(reading) end
		end
	end
end

local function codepoint_to_utf8(code)
	if code <= 0x7F then
		return string.char(code)
	elseif code <= 0x7FF then
		return string.char(
			0xC0 + math.floor(code / 0x40),
			0x80 + (code % 0x40)
		)
	elseif code <= 0xFFFF then
		return string.char(
			0xE0 + math.floor(code / 0x1000),
			0x80 + (math.floor(code / 0x40) % 0x40),
			0x80 + (code % 0x40)
		)
	end
	return string.char(
		0xF0 + math.floor(code / 0x40000),
		0x80 + (math.floor(code / 0x1000) % 0x40),
		0x80 + (math.floor(code / 0x40) % 0x40),
		0x80 + (code % 0x40)
	)
end

local function normalize_kana(text)
	if type(text) ~= "string" or text == "" then
		return nil
	end

	local chars = {}
	for _, code in StringOps.utf8_codes(text) do
		if code >= 0x30A1 and code <= 0x30FA then
			code = code - 0x60
		end
		table.insert(chars, codepoint_to_utf8(code))
	end
	return table.concat(chars)
end

local yoon_initials = {
	["き"] = true, ["ぎ"] = true,
	["し"] = true, ["じ"] = true,
	["ち"] = true,
	["に"] = true,
	["ひ"] = true, ["び"] = true, ["ぴ"] = true,
	["み"] = true,
	["り"] = true,
}

local yoon_smalls = {
	["ゃ"] = true,
	["ゅ"] = true,
	["ょ"] = true,
}

local function is_single_yoon_mora(text)
	local normalized = normalize_kana(text)
	if not normalized or StringOps.get_char_count(normalized) ~= 2 then
		return false
	end

	local chars = {}
	for _, code in StringOps.utf8_codes(normalized) do
		table.insert(chars, codepoint_to_utf8(code))
	end
	return yoon_initials[chars[1]] == true and yoon_smalls[chars[2]] == true
end

local function build_reading_index(db)
	local unique_terms = {}
	local ambiguous = {}

	for term, entry in pairs(db) do
		if type(term) == "string" and type(entry) == "table" then
			each_entry_reading(entry, function(raw_reading)
				local reading = normalize_kana(raw_reading)
				if reading and not ambiguous[reading] then
					if unique_terms[reading] == nil or unique_terms[reading] == term then
						unique_terms[reading] = term
					else
						unique_terms[reading] = nil
						ambiguous[reading] = true
					end
				end
			end)
		end
	end

	return unique_terms
end

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
	_reading_index = build_reading_index(_db)
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

local should_reject_single_yoon_reading

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

	local stripped_entry, stripped, stripped_bytes, match_kind = Conjugations.each_deconjugated_term(
		term,
		{ contains_kanji = contains_kanji },
		function(base, base_stripped_bytes, kind)
			local entry_for_base = db[base]
			if entry_for_base then
				return entry_for_base, base, base_stripped_bytes, kind
			end

			if _reading_index and is_kana_only(base) and utf8_char_count(base) >= 3 then
				local reading_term = _reading_index[normalize_kana(base)]
				if reading_term and reading_term ~= base then
					local reading_entry = db[reading_term]
					local reject_mixed_kana_suru = contains_katakana(base)
						and reading_term:sub(-#"する") == "する"
						and contains_kanji(reading_term)
					if reading_entry
						and not reject_mixed_kana_suru
						and not should_reject_single_yoon_reading(db, base, reading_term) then
						return reading_entry, reading_term, base_stripped_bytes, kind
					end
				end
			end
		end
	)
	if stripped_entry then
		return stripped_entry, stripped, stripped_bytes, match_kind
	end

	if _reading_index
		and is_kana_only(term)
		and is_single_kana_script(term)
		and utf8_char_count(term) >= 2 then
		local reading_term = _reading_index[normalize_kana(term)]
		if reading_term and reading_term ~= term then
			local reading_entry = db[reading_term]
			if reading_entry and not should_reject_single_yoon_reading(db, term, reading_term) then
				return reading_entry, reading_term, 0, "exact"
			end
		end
	end

	if _reading_index then
		local reading_entry, reading_term, reading_stripped_bytes, reading_match_kind =
			Conjugations.each_kana_adj_reading_term(term, { is_kana_only = is_kana_only }, function(
				base,
				base_stripped_bytes,
				kind
			)
				local resolved_term = _reading_index[normalize_kana(base)]
				if resolved_term and resolved_term ~= base then
				local entry_for_reading = db[resolved_term]
				if entry_for_reading
					and not should_reject_single_yoon_reading(db, base, resolved_term) then
					return entry_for_reading, resolved_term, base_stripped_bytes, kind
				end
			end
		end)
		if reading_entry then
			return reading_entry, reading_term, reading_stripped_bytes, reading_match_kind
		end
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

local function get_particle_stripped_prefix_bytes(db, surface_text, matched_term)
	if type(surface_text) ~= "string" or surface_text == ""
		or type(matched_term) ~= "string" or matched_term == "" then
		return nil
	end

	for _, suffix in ipairs(Conjugations.verb_particle_suffixes or {}) do
		if #surface_text > #suffix and surface_text:sub(-#suffix) == suffix then
			local prefix = surface_text:sub(1, -(#suffix + 1))
			local entry, resolved_term = find_clean_term(db, prefix)
			if entry and resolved_term == matched_term then
				return #prefix
			end
		end
	end

	return nil
end

local function find_compound_verb_stem(db, term)
	if type(term) ~= "string" or term == "" then
		return nil, nil, nil
	end

	for _, stem in ipairs(Conjugations.compound_verb_stems or {}) do
		local ending = stem.ending
		if #term > #ending and term:sub(-#ending) == ending then
			local base = term:sub(1, -(#ending + 1)) .. stem.rep
			if #base >= 3 then
				for _, candidate in ipairs(Conjugations.get_base_candidates(base)) do
					local entry = db[candidate]
					if entry then
						return entry, candidate, #term
					end
				end
			end
		end
	end

	return nil, nil, nil
end

should_reject_single_yoon_reading = function(db, surface, matched_term)
	return is_single_yoon_mora(surface)
		and not db[surface]
		and contains_kanji(matched_term)
end

local function remove_last_utf8_char(text)
	if type(text) ~= "string" or text == "" then return nil end

	local last = 1
	local i = 1
	while i <= #text do
		last = i
		i = i + utf8_char_len_at(text, i)
	end
	return text:sub(1, last - 1)
end

local function get_surface_match_bytes(surface_text, stripped_bytes, match_kind)
	if match_kind == "suffix_strip" then
		return math.max(0, #surface_text - (stripped_bytes or 0))
	end
	return #surface_text
end

local function get_surface_match_text(surface_text, stripped_bytes, match_kind)
	local match_bytes = get_surface_match_bytes(surface_text, stripped_bytes, match_kind)
	if match_bytes <= 0 then return "" end
	return surface_text:sub(1, match_bytes)
end

local function get_literal_prefix_match_bytes(surface_text, matched_term)
	if type(surface_text) ~= "string" or surface_text == ""
		or type(matched_term) ~= "string" or matched_term == "" then
		return nil
	end

	if surface_text:sub(1, #matched_term) == matched_term then
		return #matched_term
	end

	local normalized_surface = normalize_kana(surface_text)
	local normalized_term = normalize_kana(matched_term)
	if normalized_surface and normalized_term
		and normalized_surface:sub(1, #normalized_term) == normalized_term then
		local i = 1
		local matched_bytes = 0
		local normalized_bytes = 0
		while i <= #surface_text and normalized_bytes < #normalized_term do
			local char_len = utf8_char_len_at(surface_text, i)
			local char = surface_text:sub(i, i + char_len - 1)
			local normalized_char = normalize_kana(char) or char
			normalized_bytes = normalized_bytes + #normalized_char
			matched_bytes = matched_bytes + char_len
			i = i + char_len
		end
		if normalized_bytes == #normalized_term then
			return matched_bytes
		end
	end

	return nil
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

local function get_headword_match_source(hw, surface)
	if type(hw) ~= "table" or type(hw.sources) ~= "table" then
		return nil
	end

	for _, source in ipairs(hw.sources) do
		if get_source_match_bytes(source, surface) then
			return source.matchSource
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
					get_headword_source_match_bytes(hw, surface_text),
					get_headword_match_source(hw, surface_text)
			end
		end
		for _, candidate in ipairs(get_reading_spelling_candidates(term, hw_reading)) do
			local entry, matched, stripped, match_kind = find_clean_term(db, candidate)
			if entry then
				return word_color(entry), matched, stripped, hw_reading, match_kind,
					get_headword_source_match_bytes(hw, surface_text),
					get_headword_match_source(hw, surface_text)
			end
		end
		if type(hw_reading) == "string" and hw_reading ~= "" and hw_reading ~= term then
			local entry, matched, stripped, match_kind = find_clean_term(db, hw_reading)
			if entry then
				return word_color(entry), matched, stripped, hw_reading, match_kind,
					get_headword_source_match_bytes(hw, surface_text),
					get_headword_match_source(hw, surface_text)
			end
		end

		for _, v in ipairs(hw) do
			local color, found_term, stripped, found_reading, match_kind, source_match_bytes, source_kind =
				resolve_term_color(db, v, surface_text)
			if color then
				return color, found_term, stripped, found_reading, match_kind, source_match_bytes, source_kind
			end
		end
	end
	return nil
end

contains_kanji = function(text)
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

contains_hiragana = function(text)
	if type(text) ~= "string" or text == "" then return false end
	local i = 1
	while i <= #text do
		local b1, b2, b3 = text:byte(i, i + 2)
		if b1 == 0xE3 and b2 == 0x81 and b3 and b3 >= 0x81 then
			return true
		end
		if b1 and b1 >= 0xF0 then
			i = i + 4
		elseif b1 and b1 >= 0xE0 then
			i = i + 3
		elseif b1 and b1 >= 0xC0 then
			i = i + 2
		else
			i = i + 1
		end
	end
	return false
end

contains_katakana = function(text)
	if type(text) ~= "string" or text == "" then return false end
	local i = 1
	while i <= #text do
		local b1, b2, b3 = text:byte(i, i + 2)
		if b1 == 0xE3 and (
			(b2 == 0x82 and b3 and b3 >= 0xA0) or
			(b2 == 0x83 and b3 and b3 <= 0xBF)
		) then
			return true
		end
		if b1 and b1 >= 0xF0 then
			i = i + 4
		elseif b1 and b1 >= 0xE0 then
			i = i + 3
		elseif b1 and b1 >= 0xC0 then
			i = i + 2
		else
			i = i + 1
		end
	end
	return false
end

is_single_kana_script = function(text)
	local has_hiragana = contains_hiragana(text)
	local has_katakana = contains_katakana(text)
	return (has_hiragana or has_katakana) and not (has_hiragana and has_katakana)
end

utf8_char_len_at = function(text, byte_index)
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

utf8_char_count = function(text)
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

is_kana_only = function(text)
	if type(text) ~= "string" or text == "" then
		return false
	end

	local i = 1
	while i <= #text do
		local b1, b2, b3 = text:byte(i, i + 2)
		if b1 == 0xE3 and b2 and b3 then
			local is_hiragana = (b2 == 0x81 and b3 >= 0x81 and b3 <= 0xBF)
				or (b2 == 0x82 and b3 >= 0x80 and b3 <= 0x9F)
			local is_katakana = (b2 == 0x82 and b3 >= 0xA0 and b3 <= 0xBF)
				or (b2 == 0x83 and b3 >= 0x80 and b3 <= 0xBF)
			if is_hiragana or is_katakana then
				i = i + 3
			else
				return false
			end
		else
			return false
		end
	end

	return true
end

local boundary_chars = {
	["。"] = true, ["、"] = true, ["？"] = true, ["！"] = true, ["…"] = true,
	["「"] = true, ["」"] = true, ["『"] = true, ["』"] = true,
	["（"] = true, ["）"] = true, ["【"] = true, ["】"] = true,
	["〔"] = true, ["〕"] = true, ["〈"] = true, ["〉"] = true,
	["《"] = true, ["》"] = true,
}

local function is_boundary_char(char)
	if type(char) ~= "string" or char == "" then return false end
	if #char == 1 then
		return char:match("[%s%p]") ~= nil
	end
	return boundary_chars[char] == true
end

local function matches_base_form(term, target)
	if type(term) ~= "string" or term == "" or type(target) ~= "string" or target == "" then
		return false
	end

	if term == target then
		return true
	end

	return Conjugations.each_deconjugated_term(term, { contains_kanji = contains_kanji }, function(base)
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
	local normalized_token_text = normalize_kana(token_text) or token_text
	local normalized_matched_term = normalize_kana(matched_term) or matched_term
	local normalized_reading = normalize_kana(reading) or reading
	local normalized_headword_reading = normalize_kana(headword_reading) or headword_reading

	if token_text == matched_term then
		return true
	end

	if normalized_token_text == normalized_matched_term then
		return true
	end

	if reading == headword_reading then
		return true
	end

	if normalized_reading == normalized_headword_reading then
		return true
	end

	if matches_base_form(token_text, matched_term) then
		return true
	end

	if matches_base_form(normalized_token_text, normalized_matched_term) then
		return true
	end

	if matches_base_form(reading, headword_reading) then
		return true
	end

	if matches_base_form(normalized_reading, normalized_headword_reading) then
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

	local function char_at(byte_offset)
		if type(byte_offset) ~= "number" or byte_offset > #full_text then return nil end
		local char_len = utf8_char_len_at(full_text, byte_offset)
		return full_text:sub(byte_offset, byte_offset + char_len - 1), char_len
	end

	local function char_before(byte_offset)
		if type(byte_offset) ~= "number" or byte_offset <= 1 then return nil end
		local last = nil
		local i = 1
		while i < byte_offset do
			last = i
			i = i + utf8_char_len_at(full_text, i)
		end
		if not last then return nil end
		return char_at(last)
	end

	local function is_pure_katakana_text(text)
		return is_kana_only(text) and contains_katakana(text) and not contains_hiragana(text)
	end

	local function is_katakana_char(char)
		return type(char) == "string" and char ~= "" and is_pure_katakana_text(char)
	end

	local function is_whole_katakana_run(start_byte, match_bytes)
		if type(match_bytes) ~= "number" or match_bytes <= 0 then return true end

		local matched_text = full_text:sub(start_byte, start_byte + match_bytes - 1)
		if not is_pure_katakana_text(matched_text) then
			return true
		end

		local prev_char = char_before(start_byte)
		if is_katakana_char(prev_char) then
			return false
		end

		local next_char = char_at(start_byte + match_bytes)
		return not is_katakana_char(next_char)
	end

	local function has_particle_kana_continuation(byte_offset)
		if byte_offset > #full_text then return true end

		local char, char_len = char_at(byte_offset)
		if not char then return true end
		if is_boundary_char(char) then return true end

		local normalized = normalize_kana(char)
		if normalized == "っ" then
			local next_char = char_at(byte_offset + char_len)
			return normalize_kana(next_char) == "て"
		end
		return normalized == "と" or normalized == "あ" or normalized == "ぁ"
	end

	local protected_particles = {}

	local function protect_kana_particle(start_byte)
		protected_particles[start_byte] = start_byte + #"かな" - 1
	end

	local function should_split_kana_particle(surface, matched, start_byte)
		if type(surface) ~= "string" or surface == ""
			or type(matched) ~= "string" or matched == "" then
			return false
		end
		if contains_kanji(surface) or not is_kana_only(surface) then
			return false
		end

		local normalized_surface = normalize_kana(surface)
		if not normalized_surface or normalized_surface:sub(-#"か") ~= "か" then
			return false
		end

		local next_byte = start_byte + #surface
		local next_char, next_len = char_at(next_byte)
		if normalize_kana(next_char) ~= "な" then
			return false
		end
		if not has_particle_kana_continuation(next_byte + next_len) then
			return false
		end

		local prefix = remove_last_utf8_char(surface)
		if has_database_match(db, prefix) then
			protect_kana_particle(start_byte + #prefix)
			return true
		end
		return false
	end

	local function kana_particle_prefix_match(surface, start_byte)
		if type(surface) ~= "string" or surface == "" then
			return nil, nil, nil
		end
		local prefix = remove_last_utf8_char(surface)
		if not prefix or prefix == "" then
			return nil, nil, nil
		end
		local entry, matched = find_clean_term(db, prefix)
		if entry and should_split_kana_particle(surface, matched, start_byte) then
			return entry, matched, #prefix
		end
		return nil, nil, nil
	end

	local function set_protected_particle_match(byte_offset)
		local protected_end = protected_particles[byte_offset]
		if not protected_end then return nil, nil, nil end

		local entry = db["かな"]
		local color = word_color(entry)
		if color then
			return #"かな", color, "かな"
		end
		return protected_end - byte_offset + 1, nil, nil
	end

	local intervals = {}

	while b <= #full_text do
		local matched_len_bytes, matched_color, matched_term = set_protected_particle_match(b)

		local t_idx = get_token_idx(b)

		if not matched_len_bytes and t_idx and b == token_starts[t_idx] then
			for len = math.min(6, n - t_idx + 1), 2, -1 do
				local has_selectable = false
				local combined = ""
				local has_boundary = false
				for k = t_idx, t_idx + len - 1 do
					local ttxt = tokens[k].text or ""
					if ttxt ~= "" then
						local ci = 1
						while ci <= #ttxt do
							local clen = utf8_char_len_at(ttxt, ci)
							if is_boundary_char(ttxt:sub(ci, ci + clen - 1)) then
								has_boundary = true
								break
							end
							ci = ci + clen
						end
					end
					if has_boundary then break end
					combined = combined .. ttxt
					if tokens[k].is_term then has_selectable = true end
				end

				if not has_boundary and has_selectable and combined ~= "" then
					local skip = options.colorizer_ignore_kana_only and not contains_kanji(combined)
					if skip and has_database_match(db, combined) then skip = false end

					if not skip then
						local entry, matched, stripped, match_kind = find_clean_term(db, combined)
						if entry then
							local color = word_color(entry)
							if color then
								local literal_prefix_bytes = get_literal_prefix_match_bytes(combined, matched)
								local combined_match_bytes = get_surface_match_bytes(combined, stripped, match_kind)
								if not literal_prefix_bytes and combined_match_bytes == #combined then
									matched_len_bytes = combined_match_bytes
									matched_color = color
									matched_term = matched
									break
								end
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
					local color, term_matched, stripped_bytes, hw_reading, match_kind, source_match_bytes, source_kind =
						resolve_term_color(db, token.headwords, txt)
					if color then
						local tok_reading = (token.reading ~= "" and token.reading) or txt
						local has_explicit_token_reading = type(token.reading) == "string" and token.reading ~= ""
						local mixed_kana = not contains_kanji(txt) and contains_hiragana(txt) and contains_katakana(txt)
						local reject_reading_mismatch = source_kind == "reading"
							and has_explicit_token_reading
							and hw_reading ~= nil
							and token.reading ~= hw_reading
						local reject_reading_kanji = mixed_kana
							and source_kind == "reading"
							and contains_kanji(term_matched)
						local headword_compatible
						if source_kind == "reading" then
							headword_compatible = has_explicit_token_reading
								and token_matches_headword(txt, token.reading, term_matched, hw_reading)
						else
							headword_compatible = token_matches_headword(txt, tok_reading, term_matched, hw_reading)
						end
						if not reject_reading_mismatch
							and not reject_reading_kanji
							and ((source_match_bytes and headword_compatible) or headword_compatible) then
							local preferred_match_bytes = get_surface_match_bytes(txt, stripped_bytes, match_kind)
							local literal_prefix_bytes = get_literal_prefix_match_bytes(txt, term_matched)
							local particle_prefix_bytes = get_particle_stripped_prefix_bytes(db, txt, term_matched)
							local prefix_entry, prefix_matched, prefix_bytes =
								kana_particle_prefix_match(
									get_surface_match_text(txt, stripped_bytes, match_kind),
									token_starts[t_idx]
								)
							if prefix_entry then
								matched_len_bytes = prefix_bytes
								matched_color = word_color(prefix_entry)
								matched_term = prefix_matched
							elseif literal_prefix_bytes and literal_prefix_bytes < preferred_match_bytes then
								matched_len_bytes = literal_prefix_bytes
							elseif particle_prefix_bytes and particle_prefix_bytes < preferred_match_bytes then
								matched_len_bytes = particle_prefix_bytes
							elseif source_match_bytes and match_kind ~= "suffix_strip" then
								matched_len_bytes = source_match_bytes
							else
								matched_len_bytes = preferred_match_bytes
							end
							if not prefix_entry then
								matched_color = color
								matched_term = term_matched
							end
							if matched_len_bytes
								and not is_whole_katakana_run(token_starts[t_idx], matched_len_bytes) then
								matched_len_bytes = nil
								matched_color = nil
								matched_term = nil
							end
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
				local char = full_text:sub(j, j + char_len - 1)
				if is_boundary_char(char) then
					break
				end
				j = j + char_len
				char_count = char_count + 1

				local sub = full_text:sub(b, j - 1)
				local is_single_kana = #full_text > 3 and is_single_kana_string(sub)
				local sub_char_count = utf8_char_count(sub)

				local sub_is_kana_only = options.colorizer_ignore_kana_only and not contains_kanji(sub)
				if not is_single_kana and (sub_char_count >= 2 or contains_kanji(sub)) then
					local entry, matched, stripped_bytes, match_kind = find_clean_term(db, sub)
					local compound_stem_entry, compound_stem_matched, compound_stem_bytes
					if j <= #full_text and not entry then
						compound_stem_entry, compound_stem_matched, compound_stem_bytes =
							find_compound_verb_stem(db, sub)
					end
					if compound_stem_entry then
						entry = compound_stem_entry
						matched = compound_stem_matched
						stripped_bytes = 0
						match_kind = "compound_stem"
					end
					if entry then
						if not (sub_is_kana_only and not has_database_match(db, sub)) then
							local color = word_color(entry)
							if color and not should_split_kana_particle(
								get_surface_match_text(sub, stripped_bytes, match_kind),
								matched,
								b
							) then
								local literal_prefix_bytes = get_literal_prefix_match_bytes(sub, matched)
								local candidate_match_bytes = literal_prefix_bytes
									or compound_stem_bytes
									or get_surface_match_bytes(sub, stripped_bytes, match_kind)
								if is_whole_katakana_run(b, candidate_match_bytes) then
									best_match_bytes = candidate_match_bytes
									best_color = color
									best_term = matched
								end
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
			if matched_color then
				table.insert(intervals, {
					start_byte = b,
					end_byte = b + matched_len_bytes - 1,
					color = matched_color,
					term = matched_term
				})
			end
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
	_reading_index = nil
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
