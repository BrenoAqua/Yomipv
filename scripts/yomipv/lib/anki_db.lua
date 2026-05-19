--[[ Anki word database loader and color resolver ]]

local mp = require("mp")
local utils = require("mp.utils")
local msg = require("mp.msg")
local JSONFormat = require("lib.json_format")

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

local function is_term_match(hw)
	if type(hw) ~= "table" then return true end
	if not hw.sources or #hw.sources == 0 then return true end
	for _, src in ipairs(hw.sources) do
		if src.matchSource == "term" then
			return true
		end
	end
	return false
end

local function find_clean_term(db, term)
	if type(term) ~= "string" or term == "" then return nil, nil end
	local entry = db[term]
	if entry then return entry, term end

	local particles = { "が", "の", "に", "を", "と", "は", "も", "で", "へ", "から", "より" }
	for _, p in ipairs(particles) do
		if term:sub(1, #p) == p then
			local stripped = term:sub(#p + 1)
			if #stripped > 3 then
				local stripped_entry = db[stripped]
				if stripped_entry then return stripped_entry, stripped end
			end
		end
	end
	return nil, nil
end

local function resolve_term_color(db, hw)
	if type(hw) == "string" then
		if hw ~= "" then
			local entry, matched = find_clean_term(db, hw)
			if entry then return word_color(entry), matched end
		end
	elseif type(hw) == "table" then
		local term = hw.term or hw.expression
		if type(term) == "string" and term ~= "" then
			if is_term_match(hw) then
				local entry, matched = find_clean_term(db, term)
				if entry then return word_color(entry), matched end
			end
		end

		for _, v in ipairs(hw) do
			local color, found_term = resolve_term_color(db, v)
			if color then return color, found_term end
		end
	end
	return nil
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

local function get_token_reps(token)
	local reps = {}
	local seen = {}
	local function add_rep(r)
		if type(r) == "string" and r ~= "" and not seen[r] then
			seen[r] = true
			table.insert(reps, r)
		end
	end
	add_rep(token.text)
	local function collect_hw(hw)
		if type(hw) == "table" then
			local term = hw.term or hw.expression
			add_rep(term)
			for _, v in ipairs(hw) do
				collect_hw(v)
			end
		elseif type(hw) == "string" then
			add_rep(hw)
		end
	end
	collect_hw(token.headwords)
	return reps
end

local function generate_combinations(reps_list, idx, current_str, results)
	if idx > #reps_list then
		results[current_str] = true
		return
	end
	for _, rep in ipairs(reps_list[idx]) do
		generate_combinations(reps_list, idx + 1, current_str .. rep, results)
	end
end

function AnkiDB.get_tokens_colors(tokens)
	local db = load_db()
	if not db or not tokens then return {} end

	local colors = {}
	local n = #tokens
	local i = 1
	while i <= n do
		local matched_len = nil
		local matched_color = nil
		local matched_term = nil

		for len = math.min(6, n - i + 1), 2, -1 do
			local reps_list = {}
			local has_selectable = false
			for k = i, i + len - 1 do
				local reps = get_token_reps(tokens[k])
				if #reps > 0 then
					table.insert(reps_list, reps)
				end
				if tokens[k].is_term then
					has_selectable = true
				end
			end

			if #reps_list == len and has_selectable then
				local combinations = {}
				generate_combinations(reps_list, 1, "", combinations)

				for comb in pairs(combinations) do
					local entry, matched = find_clean_term(db, comb)
					if entry and matched == comb then
						local color = word_color(entry)
						if color then
							matched_len = len
							matched_color = color
							matched_term = matched
							break
						end
					end
				end
			end

			if matched_len then
				break
			end
		end

		if matched_len then
			for k = i, i + matched_len - 1 do
				colors[k] = { color = matched_color, term = matched_term }
			end
			i = i + matched_len
		else
			local token = tokens[i]
			if token.headwords then
				local color, term = resolve_term_color(db, token.headwords)
				if color then
					colors[i] = { color = color, term = term }
				end
			end
			i = i + 1
		end
	end

	return colors
end

-- Forces a reload on next access (call after anki_words.json is regenerated)
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
