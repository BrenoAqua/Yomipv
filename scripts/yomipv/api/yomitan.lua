--[[ Yomitan API Wrapper ]]

local msg = require("mp.msg")
local Api = require("lib.api")
local StringOps = require("lib.string_ops")
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

function Yomitan:clear_cache()
	msg.info("Yomitan: Clearing tokenization cache")
	self._tokenize_cache = {}
	self._tokenize_cache_keys = {}
end

local function is_selectable_term(token_text, headwords)
	if headwords and #headwords > 0 then return true end
	local clean_text = token_text:gsub(WHITESPACE_PATTERN, "")
	if clean_text == "" then return false end
	return token_text:gsub(PUNCTUATION_PATTERN, "") ~= ""
end

local function process_token_segment(segment)
	local token_text, reading, headwords = "", "", nil
	local items = (type(segment) == "table" and segment.text) and { segment } or segment

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
	local tokens, current_offset = {}, 0
	for _, segment in ipairs(content) do
		local token_text, headwords, reading = process_token_segment(segment)
		local char_count = StringOps.get_char_count(token_text)
		table.insert(tokens, {
			text = token_text,
			headwords = headwords,
			reading = reading,
			offset = current_offset,
			is_term = is_selectable_term(token_text, headwords),
		})
		current_offset = current_offset + char_count
	end
	return tokens
end

local function build_furigana_html(content)
	local html_parts = {}
	for _, segment in ipairs(content) do
		if type(segment) == "table" then
			for _, token in ipairs(segment) do
				local text_val, reading_val = token.text or "", token.reading or ""
				local content_str = text_val
				if text_val:find("[一-龯]") and reading_val ~= "" and reading_val ~= text_val then
					content_str = string.format("<ruby>%s<rt>%s</rt></ruby>", text_val, reading_val)
				end
				table.insert(html_parts, string.format('<span class="term">%s</span>', content_str))
			end
		end
	end
	return table.concat(html_parts)
end

function Yomitan:request(endpoint, params, callback)
	local url = self.config.yomitan_url:gsub("/$", "")
	if not url:find("^http") then url = "http://" .. url end
	Api.request(self.curl, url .. endpoint, params, callback)
end

function Yomitan:tokenize(text, callback, scan_length)
	local sl = scan_length or DEFAULT_SCAN_LENGTH
	local cache_key = tostring(text) .. "_" .. tostring(sl)

	if self._tokenize_cache[cache_key] then
		local entry = self._tokenize_cache[cache_key]
		local copy = {}
		for i, v in ipairs(entry.tokens) do copy[i] = v end
		return callback(copy, entry.content)
	end

	self:request("/tokenize", { text = text, scanLength = sl }, function(res, err)
		if err then return callback(nil, nil, err) end
		local content = res.content or (res[1] and res[1].content)
		if not content then return callback(nil, nil, "Tokenization failed") end

		local tokens = build_tokens_from_content(content)
		if #self._tokenize_cache_keys >= 100 then
			self._tokenize_cache[table.remove(self._tokenize_cache_keys, 1)] = nil
		end
		table.insert(self._tokenize_cache_keys, cache_key)
		self._tokenize_cache[cache_key] = { tokens = tokens, content = content }

		local copy = {}
		for i, v in ipairs(tokens) do copy[i] = v end
		callback(copy, content)
	end)
end

function Yomitan:tokenize_with_scan_length(text, sl, callback)
	self:tokenize(text, function(tokens, _, err) callback(tokens, err) end, sl)
end

function Yomitan:get_anki_fields(term, markers, context, callback, active_expression, active_reading)
	local lookup_text = (active_expression and active_expression ~= "") and active_expression or term
	local params = { text = lookup_text, type = "term", markers = markers, includeMedia = true }
	if context then
		params.context = context
		if context.selection then params.context.selectedText = context.selection end
	end

	self:request("/ankiFields", params, function(response, err)
		if err then return callback(nil, "ankiFields failed: " .. err) end
		local fields_list = response.fields or (response[1] and response[1].fields)
		if not fields_list or #fields_list == 0 then return callback(nil, "No dictionary entry found") end

		local selected_entry = fields_list[1]
		if active_expression and active_expression ~= "" then
			for _, entry in ipairs(fields_list) do
				if entry.expression == active_expression and
				   (not active_reading or active_reading == "" or entry.reading == active_reading) then
					selected_entry = entry
					break
				end
			end
		end

		if active_expression == selected_entry.expression then
			return callback({
				fields = selected_entry,
				dictionaryMedia = response.dictionaryMedia or (response[1] and response[1].dictionaryMedia),
				audioMedia = response.audioMedia or (response[1] and response[1].audioMedia),
			}, nil)
		end

		self:request("/termEntries", { term = lookup_text }, function(te_response)
			local orig_len_map = {}
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

			local term_cps = match_sort.to_normalized_codepoints(term)
			local term_is_h = StringOps.is_hiragana_only(term)
			local best_score = -1

			for _, entry in ipairs(fields_list) do
				local expr, reading = entry.expression or "", entry.reading or ""
				local clean_term = term:gsub("^[%s\226\128\139]+", "")
				local score = (expr == clean_term) and 10000000 or 0
				if self.config.prioritize_hiragana_match and term_is_h and expr == clean_term then
					score = score + 10000000
				end

				score = score + ((orig_len_map[expr .. "\0" .. reading] or 0) * 100000)
				local kp = clean_term:match("^[\227\130\160-\227\131\191]+") or ""
				if kp ~= "" and StringOps.is_katakana_only(expr) then
					score = score + 10000
				end

				local matched = match_sort.compute_matched_len(term_cps, expr, reading)
				if not self.config.prioritize_kanji_match then
					score = score + (matched * 100) + ((expr ~= reading and reading ~= "") and 10 or 0)
				else
					score = score + ((expr ~= reading and reading ~= "") and 10 or 0) + matched
				end

				if score > best_score then
					best_score = score
					selected_entry = entry
				end
			end

			callback({
				fields = selected_entry,
				dictionaryMedia = response.dictionaryMedia or (response[1] and response[1].dictionaryMedia),
				audioMedia = response.audioMedia or (response[1] and response[1].audioMedia),
			}, nil)
		end)
	end)
end

function Yomitan:get_sentence_furigana(text, callback, cached_content)
	if not text or text == "" then return callback("") end
	if cached_content then return callback(build_furigana_html(cached_content)) end

	self:tokenize(text, function(_, content, err)
		if err or not content then return callback(text) end
		callback(build_furigana_html(content))
	end)
end

return Yomitan
