--[[ Yomitan API client ]]

local utils = require("mp.utils")
local msg = require("mp.msg")

local match_sort = require("api.match_sort")
local DEFAULT_SCAN_LENGTH = 10
local PUNCTUATION_PATTERN = "[%s%p。、？！（）「」『』〜➨]"
local WHITESPACE_PATTERN = "[%z\1-\32\127]"

local Yomitan = {}

function Yomitan.new(config, curl)
	local obj = {
		config = config,
		curl = curl,
		_tokenize_cache = {},
		_tokenize_cache_keys = {},
	}
	setmetatable(obj, Yomitan)
	Yomitan.__index = Yomitan
	return obj
end

local function count_utf8_chars(text)
	local _, char_count = text:gsub("[^\128-\191]", "")
	return char_count
end

function Yomitan:clear_cache()
	msg.info("Yomitan: Clearing tokenization cache")
	self._tokenize_cache = {}
	self._tokenize_cache_keys = {}
end

local function is_hiragana_only(s)
	if not s or s == "" then
		return false
	end

	local char_count = 0
	local hiragana_count = 0

	local i = 1
	while i <= #s do
		local b1 = s:byte(i)
		local b2 = s:byte(i + 1)
		local b3 = s:byte(i + 2)

		if b1 == 227 and b2 and b3 then
			-- Hiragana range: U+3041 to U+309F
			-- U+3041: E3 81 81 (227 129 129)
			-- U+309F: E3 82 9F (227 130 159)
			if (b2 == 129 and b3 >= 129) or (b2 == 130 and b3 <= 159) then
				hiragana_count = hiragana_count + 1
			end
			i = i + 3
		else
			if b1 < 128 then
				i = i + 1
			elseif b1 < 224 then
				i = i + 2
			elseif b1 < 240 then
				i = i + 3
			else
				i = i + 4
			end
		end
		char_count = char_count + 1
	end

	return char_count > 0 and char_count == hiragana_count
end

local function is_katakana_only(s)
	if not s or s == "" then
		return false
	end

	local char_count = 0
	local katakana_count = 0

	local i = 1
	while i <= #s do
		local b1 = s:byte(i)
		local b2 = s:byte(i + 1)
		local b3 = s:byte(i + 2)

		if b1 == 227 and b2 and b3 then
			if (b2 == 130 and b3 >= 160) or (b2 == 131 and b3 <= 191) then
				katakana_count = katakana_count + 1
			end
			i = i + 3
		else
			if b1 < 128 then
				i = i + 1
			elseif b1 < 224 then
				i = i + 2
			elseif b1 < 240 then
				i = i + 3
			else
				i = i + 4
			end
		end
		char_count = char_count + 1
	end

	return char_count > 0 and char_count == katakana_count
end

local function is_selectable_term(token_text, headwords)
	if headwords and #headwords > 0 then
		return true
	end

	local clean_text = token_text:gsub(WHITESPACE_PATTERN, "")
	if clean_text == "" then
		return false
	end

	local has_content = token_text:gsub(PUNCTUATION_PATTERN, "") ~= ""
	return has_content
end

local function process_token_segment(segment)
	local token_text = ""
	local reading = ""
	local headwords = nil

	local items = segment
	if type(segment) == "table" and segment.text then
		items = { segment }
	end

	for _, item in ipairs(items) do
		token_text = token_text .. (item.text or "")
		reading = reading .. (item.reading or item.text or "")
		if headwords == nil and item.headwords and type(item.headwords) == "table" then
			headwords = item.headwords
		end
	end

	return token_text, headwords, reading
end

local function build_tokens_from_content(content)
	local tokens = {}
	local current_offset = 0

	for _, segment in ipairs(content) do
		local token_text, headwords, reading = process_token_segment(segment)
		local char_count = count_utf8_chars(token_text)
		local is_term = is_selectable_term(token_text, headwords)

		table.insert(tokens, {
			text = token_text,
			headwords = headwords,
			reading = reading,
			offset = current_offset,
			is_term = is_term,
		})

		current_offset = current_offset + char_count
	end

	return tokens
end

local function build_furigana_html(content)
	msg.info("Processing " .. #content .. " segments for furigana")

	local html_parts = {}

	for _, segment in ipairs(content) do
		if type(segment) == "table" then
			for _, token in ipairs(segment) do
				local text_val = token.text or ""
				local reading_val = token.reading or ""

				local has_kanji = text_val:find("[一-龯]") ~= nil

				local content_str = text_val
				if has_kanji and reading_val ~= "" and reading_val ~= text_val then
					content_str = string.format("<ruby>%s<rt>%s</rt></ruby>", text_val, reading_val)
				end

				table.insert(html_parts, string.format('<span class="term">%s</span>', content_str))
			end
		end
	end

	return table.concat(html_parts)
end

function Yomitan:request(endpoint, params, completion_fn)
	if not self.config or not self.config.yomitan_url then
		msg.error("Yomitan: Config not initialized or yomitan_url missing")
		return completion_fn(nil, "Config error")
	end

	local base_url = self.config.yomitan_url:gsub("/$", "")
	if not base_url:find("^http") then
		base_url = "http://" .. base_url
	end

	local url = base_url .. endpoint
	msg.info("Yomitan Request: " .. url)

	local request_json, error = utils.format_json(params)
	if error ~= nil then
		msg.error("Failed to format JSON for Yomitan request: " .. tostring(error))
		return completion_fn(nil, "JSON error")
	end
	if request_json == "null" then
		msg.error("Failed to format JSON for Yomitan request: result is null")
		return completion_fn(nil, "JSON error")
	end

	msg.info("Yomitan API Request JSON: " .. request_json)

	return self.curl.request(url, request_json, function(success, curl_output, error_str)
		msg.info(string.format("Yomitan Response: %s", endpoint))

		if not success then
			msg.error("Yomitan request failed: " .. tostring(error_str))
		end

		completion_fn(curl_output)
	end)
end

function Yomitan.parse_result(curl_output)
	if curl_output == nil then
		return nil, "No response from curl"
	end

	if curl_output.status ~= 0 then
		return nil, "Yomitan API or curl error"
	end

	local response = utils.parse_json(curl_output.stdout)
	if response == nil then
		return nil, "Failed to parse JSON response"
	end

	return response, nil
end

function Yomitan:tokenize(text, callback, scan_length)
	msg.info("yomitan.tokenize called for: " .. tostring(text))

	local sl = scan_length or DEFAULT_SCAN_LENGTH
	local cache_key = tostring(text) .. "_" .. tostring(sl)

	-- Make a copy so modifying it later doesn't affect the cached tokens
	local function copy_tokens(tokens)
		local copy = {}
		for i = 1, #tokens do
			copy[i] = tokens[i]
		end
		return copy
	end

	if self._tokenize_cache[cache_key] then
		msg.info("yomitan.tokenize using cached result for: " .. tostring(text))
		local entry = self._tokenize_cache[cache_key]
		return callback(copy_tokens(entry.tokens), entry.content)
	end

	local params = {
		text = text,
		scanLength = sl,
	}

	self:request("/tokenize", params, function(curl_output)
		local response, _ = Yomitan.parse_result(curl_output)
		local content = response and (response.content or (response[1] and response[1].content))

		if not content then
			return callback(nil, nil, "Tokenization failed")
		end

		local tokens = build_tokens_from_content(content)

		if #self._tokenize_cache_keys >= 100 then
			local oldest = table.remove(self._tokenize_cache_keys, 1)
			self._tokenize_cache[oldest] = nil
		end

		table.insert(self._tokenize_cache_keys, cache_key)
		self._tokenize_cache[cache_key] = {
			tokens = tokens,
			content = content,
		}

		-- Don't modify the cached tokens
		callback(copy_tokens(tokens), content)
	end)
end

function Yomitan:tokenize_with_scan_length(text, scan_length, callback)
	self:tokenize(text, function(tokens, _content, error)
		if error then
			return callback(nil, error)
		end
		callback(tokens)
	end, scan_length)
end

function Yomitan:get_anki_fields(term, markers, context, callback, active_expression, active_reading)
	-- Prefer active_expression as search text to support manual narrowing in the UI
	local lookup_text = (active_expression and active_expression ~= "") and active_expression or term
	local params = {
		text = lookup_text,
		type = "term",
		markers = markers,
		includeMedia = true,
	}

	if context then
		params.context = context
		if context.selection then
			params.context.selectedText = context.selection
		end
	end

	self:request("/ankiFields", params, function(curl_output)
		local response, error = Yomitan.parse_result(curl_output)
		if error then
			return callback(nil, "ankiFields request failed: " .. error)
		end

		local fields_list = (response and response.fields) or (response and response[1] and response[1].fields)
		if not fields_list or #fields_list == 0 then
			return callback(nil, "No dictionary entry found")
		end

		local selected_entry = fields_list[1]

		-- Attempt to pin by explicit lookup selection (active_expression)
		if active_expression and active_expression ~= "" then
			for _, entry in ipairs(fields_list) do
				if
					entry.expression == active_expression
					and (not active_reading or active_reading == "" or entry.reading == active_reading)
				then
					selected_entry = entry
					msg.info(string.format("Pinned entry by lookup selection: %s", active_expression))
					break
				end
			end
		end

		local current_pinned = (active_expression == selected_entry.expression)
		if current_pinned then
			callback({
				fields = selected_entry,
				dictionaryMedia = (response and response.dictionaryMedia)
					or (response and response[1] and response[1].dictionaryMedia),
				audioMedia = (response and response.audioMedia) or (response and response[1] and response[1].audioMedia),
			}, nil)
			return
		end

		-- Fetch termEntries to obtain maxOriginalTextLength per headword
		-- Deconjugated entries consume more original-text characters than shorter
		-- literal prefix matches, so this correctly ranks them higher
		self:request("/termEntries", { term = lookup_text }, function(te_output)
			local orig_len_map = {}

			local te_response = Yomitan.parse_result(te_output)
			if te_response and te_response.dictionaryEntries then
				for _, de in ipairs(te_response.dictionaryEntries) do
					local orig_len = de.maxOriginalTextLength or 0
					if orig_len > 0 and de.headwords then
						for _, hw in ipairs(de.headwords) do
							local key = (hw.term or "") .. "\0" .. (hw.reading or "")
							if not orig_len_map[key] or orig_len_map[key] < orig_len then
								orig_len_map[key] = orig_len
							end
						end
					end
				end
			end

			local term_is_hiragana = is_hiragana_only(term)
			local term_cps = match_sort.to_normalized_codepoints(term)

			local function get_orig_len(entry)
				local key = (entry.expression or "") .. "\0" .. (entry.reading or "")
				return orig_len_map[key] or 0
			end

			local best_score = -1
			for _, entry in ipairs(fields_list) do
				local score = 0
				local expr = entry.expression or ""
				local reading = entry.reading or ""

				local clean_term = term:gsub("^[%s\226\128\139]+", "") -- remove leading spaces and ZWSP (\u200B)

				-- Exact-match priority
				if expr == clean_term then
					score = score + 10000000
				end

				-- Hiragana exact-match priority
				if self.config.prioritize_hiragana_match and term_is_hiragana and expr == clean_term then
					score = score + 10000000
				end

				-- Primary: characters consumed by Yomitan's deinflection
				local orig_len = get_orig_len(entry)
				score = score + (orig_len * 100000)

				-- Katakana priority when matched prefix is Katakana
				local term_kata_prefix = clean_term:match("^[\227\130\160-\227\131\191]+") -- U+30A0 to U+30FF
				if term_kata_prefix and #term_kata_prefix > 0 then
					if is_katakana_only(expr) then
						score = score + 10000
					end
				end

				-- Fallback: kana prefix-match length
				local matched = match_sort.compute_matched_len(term_cps, expr, reading)

				if not self.config.prioritize_kanji_match then
					-- Matched-length priority (common prefix with term, kana-normalized)
					score = score + (matched * 100)

					-- Kanji priority
					if expr ~= reading and reading ~= "" then
						score = score + 10
					end
				else
					-- Kanji priority
					if expr ~= reading and reading ~= "" then
						score = score + 10
					end

					-- Fallback to matched length
					score = score + matched
				end

				if score > best_score then
					best_score = score
					selected_entry = entry
				end
			end

			msg.info(
				string.format(
					"Selected entry: %s from %s",
					selected_entry.expression or "nil",
					selected_entry.dictionary or "unknown"
				)
			)

			callback({
				fields = selected_entry,
				dictionaryMedia = (response and response.dictionaryMedia)
					or (response and response[1] and response[1].dictionaryMedia),
				audioMedia = (response and response.audioMedia) or (response and response[1] and response[1].audioMedia),
			}, nil)
		end)
	end)
end

function Yomitan:get_sentence_furigana(text, callback, cached_content)
	if not text or text == "" then
		return callback("")
	end

	if cached_content then
		msg.info("get_sentence_furigana used cached content for: " .. text)
		local result = build_furigana_html(cached_content)
		msg.info("Furigana result: " .. result)
		return callback(result)
	end

	msg.info("get_sentence_furigana calling tokenize for: " .. text)

	self:tokenize(text, function(_tokens, content, error)
		if error or not content then
			msg.warn("Tokenize failed for furigana: " .. (error or "nil content"))
			return callback(text)
		end

		local result = build_furigana_html(content)
		msg.info("Furigana result: " .. result)
		callback(result)
	end)
end

return Yomitan
