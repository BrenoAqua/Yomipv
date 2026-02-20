--[[ Yomitan API client ]]

local utils = require("mp.utils")
local msg = require("mp.msg")

local DEFAULT_SCAN_LENGTH = 10
local DEFAULT_MAX_ENTRIES = 5
local PUNCTUATION_PATTERN = "[%s%p。、？！（）「」『』〜➨]"
local WHITESPACE_PATTERN = "[%z\1-\32\127]"

local Yomitan = {}

function Yomitan.new(config, curl)
	local obj = {
		config = config,
		curl = curl,
	}
	setmetatable(obj, Yomitan)
	Yomitan.__index = Yomitan
	return obj
end

local function count_utf8_chars(text)
	local _, char_count = text:gsub("[^\128-\191]", "")
	return char_count
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

	local params = {
		text = text,
		scanLength = scan_length or DEFAULT_SCAN_LENGTH,
	}

	-- Try alternate endpoints for compatibility
	local function try_endpoints(endpoints, idx)
		local endpoint = endpoints[idx]
		if not endpoint then
			return callback(nil, nil, "All tokenization endpoints failed")
		end

		msg.info(string.format("Tokenize attempt: %s", endpoint))

		self:request(endpoint, params, function(curl_output)
			local response, _ = Yomitan.parse_result(curl_output)

			local content = response and (response.content or (response[1] and response[1].content))

			if not content then
				msg.warn(string.format("Endpoint %s failed or returned no content", endpoint))
				return try_endpoints(endpoints, idx + 1)
			end

			msg.info(string.format("Endpoint %s succeeded", endpoint))
			local tokens = build_tokens_from_content(content)
			callback(tokens, content)
		end)
	end

	try_endpoints({ "/tokenize", "/api/tokenize" }, 1)
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
	local params = {
		text = term,
		type = "term",
		markers = markers,
		maxEntries = DEFAULT_MAX_ENTRIES,
		includeMedia = true,
	}

	if context then
		params.context = context
		if context.selection then
			params.context.selectedText = context.selection
		end
	end

	local function try_endpoints(endpoints, idx)
		local endpoint = endpoints[idx]
		if not endpoint then
			return callback(nil, "All ankiFields endpoints failed")
		end

		msg.info(string.format("ankiFields attempt: %s", endpoint))

		self:request(endpoint, params, function(curl_output)
			local response, error = Yomitan.parse_result(curl_output)
			if error then
				msg.warn(string.format("Endpoint %s parse failed: %s", endpoint, error))
				return try_endpoints(endpoints, idx + 1)
			end

			local fields_list = (response and response.fields) or (response and response[1] and response[1].fields)
			if not fields_list or #fields_list == 0 then
				msg.warn(string.format("Endpoint %s returned no fields", endpoint))
				return try_endpoints(endpoints, idx + 1)
			end

			msg.info(string.format("Endpoint %s succeeded", endpoint))

			local selected_entry = fields_list[1]

			-- Skip scoring if entry was explicitly navigated to
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
			else
				local best_score = -1
				for _, entry in ipairs(fields_list) do
					local score = 0
					local expr = entry.expression or ""
					local reading = entry.reading or ""
					local pitch = entry["pitch-accents"] or ""

					-- Mirrors lookup app sort order for consistency
					if pitch ~= "" then
						score = score + 2
					end
					if expr ~= reading then
						score = score + 1
					end

					if score > best_score then
						best_score = score
						selected_entry = entry
					end

					if score == 3 and expr == term then
						break
					end
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
				dictionaryMedia = response and response.dictionaryMedia,
				audioMedia = response and response.audioMedia,
			}, nil)
		end)
	end

	try_endpoints({ "/ankiFields", "/api/ankiFields" }, 1)
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
