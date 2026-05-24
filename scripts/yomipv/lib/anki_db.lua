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

local function each_deconjugated_term(term, callback)
	if type(term) ~= "string" or term == "" then
		return nil
	end

	for _, p in ipairs(Conjugations.noun_suffixes) do
		if #term > #p and term:sub(-#p) == p then
			local stripped = term:sub(1, -(#p + 1))
			if #stripped >= 3 then
				local r1, r2, r3 = callback(stripped, #p)
				if r1 ~= nil then return r1, r2, r3 end
			end
		end
	end

	for _, adj in ipairs(Conjugations.adj_endings) do
		local p = adj.ending
		if #term > #p and term:sub(-#p) == p then
			local stripped = term:sub(1, -(#p + 1)) .. adj.rep
			if #stripped >= 3 then
				-- よい is the literary root of いい; normalize to the common card form.
				if stripped == "よい" then
					stripped = "いい"
				end
				local r1, r2, r3 = callback(stripped, 0)
				if r1 ~= nil then return r1, r2, r3 end
			end
		end
	end

	for _, p in ipairs(Conjugations.na_adj_endings) do
		if #term > #p and term:sub(-#p) == p then
			local stripped = term:sub(1, -(#p + 1))
			if #stripped >= 3 then
				local r1, r2, r3 = callback(stripped, 0)
				if r1 ~= nil then return r1, r2, r3 end
			end
		end
	end

	for _, verb in ipairs(Conjugations.verb_endings) do
		local p = verb.ending
		if #term > #p and term:sub(-#p) == p then
			local stripped = term:sub(1, -(#p + 1)) .. verb.rep
			if #stripped >= 3 then
				local r1, r2, r3 = callback(stripped, 0)
				if r1 ~= nil then return r1, r2, r3 end
			end
		end
	end

	return nil
end

local function find_clean_term(db, term)
	if type(term) ~= "string" or term == "" then return nil, nil, 0 end
	local entry = db[term]
	if entry then return entry, term, 0 end

	local stripped_entry, stripped, stripped_bytes = each_deconjugated_term(term, function(base, base_stripped_bytes)
		local entry_for_base = db[base]
		if entry_for_base then
			return entry_for_base, base, base_stripped_bytes
		end
	end)
	if stripped_entry then
		return stripped_entry, stripped, stripped_bytes
	end

	return nil, nil, 0
end

local function resolve_term_color(db, hw)
	if type(hw) == "string" then
		if hw ~= "" then
			local entry, matched, stripped = find_clean_term(db, hw)
			if entry then return word_color(entry), matched, stripped, hw end
		end
	elseif type(hw) == "table" then
		local term = hw.term or hw.expression
		local hw_reading = hw.reading or term
		if type(term) == "string" and term ~= "" then
			local entry, matched, stripped = find_clean_term(db, term)
			if entry then return word_color(entry), matched, stripped, hw_reading end
		end

		for _, v in ipairs(hw) do
			local color, found_term, stripped, found_reading = resolve_term_color(db, v)
			if color then return color, found_term, stripped, found_reading end
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
					if skip and db[combined] then skip = false end

					if not skip then
						local entry, matched, stripped = find_clean_term(db, combined)
						if entry then
							local color = word_color(entry)
							if color then
								matched_len_bytes = #combined - (stripped or 0)
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
				if skip_kana and token.text and token.text ~= "" and db[token.text] then
					skip_kana = false
				end

				if token.headwords and not text_is_single_kana and not skip_kana then
					local color, term_matched, stripped_bytes, hw_reading = resolve_term_color(db, token.headwords)
					if color then
						local txt = token.text or ""
						local tok_reading = (token.reading ~= "" and token.reading) or txt
						if token_matches_headword(txt, tok_reading, term_matched, hw_reading) then
							matched_len_bytes = #txt - (stripped_bytes or 0)
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

				local sub_is_kana_only = options.colorizer_ignore_kana_only and not contains_kanji(sub)
				if not is_single_kana then
					local entry, matched, stripped_bytes = find_clean_term(db, sub)
					if entry and (matched == sub or stripped_bytes == 0) then
						if not (sub_is_kana_only and matched ~= sub) then
							local color = word_color(entry)
							if color then
								best_match_bytes = j - b
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
