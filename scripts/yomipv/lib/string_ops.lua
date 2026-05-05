--[[ String operations and text utilities                 ]]
--[[ Text cleaning, subtitle sanitization, and formatting ]]

local StringOps = {}

-- Pattern for matching control characters and formatting codes
local CONTROL_CHARS_PATTERN = "[\1-\31\127]"
local WHITESPACE_PATTERN = "[ \t\n\r]+"
local SUBTITLE_TAGS_PATTERN = "{[^}]-}"
local SUBTITLE_SYMBOLS = { "🔊", "➨", "➡", "➔", "➜", "➝", "➞" }
local BRACKET_PATTERNS = {
	"（.-）", -- Full-width
	"%([^%)]-%)", -- ASCII
	"%[[^%]]-%]", -- Square brackets
	"【.-】", -- Lenticular brackets
}

-- Normalizes whitespace and optionally preserves newlines
function StringOps.clean_text(text, preserve_newlines)
	if not text or text == "" then
		return ""
	end

	local cleaned = text

	if preserve_newlines then
		cleaned = cleaned:gsub("\r\n", "\n")
		cleaned = cleaned:gsub("\r", "\n")
		cleaned = cleaned:gsub("[\1-\8\11-\12\14-\31]", "")
	else
		cleaned = cleaned:gsub(CONTROL_CHARS_PATTERN, "")
		cleaned = cleaned:gsub(WHITESPACE_PATTERN, " ")
	end

	cleaned = cleaned:gsub("^%s+", "")
	cleaned = cleaned:gsub("%s+$", "")

	return cleaned
end

-- Strips ASS tags and symbols from subtitle text
function StringOps.clean_subtitle(text, preserve_newlines)
	if not text or text == "" then
		return ""
	end

	local cleaned = text:gsub(SUBTITLE_TAGS_PATTERN, "")

	-- Strip symbols individually to avoid UTF-8 bracketed set issues
	for _, symbol in ipairs(SUBTITLE_SYMBOLS) do
		cleaned = cleaned:gsub(symbol, "")
	end

	-- Strip brackets individually
	for _, pattern in ipairs(BRACKET_PATTERNS) do
		cleaned = cleaned:gsub(pattern, "")
	end

	cleaned = StringOps.clean_text(cleaned, preserve_newlines)

	return cleaned
end

-- Formats duration to HH:MM:SS[:MS]
function StringOps.format_duration(seconds, show_ms)
	if not seconds or seconds < 0 then
		return "00:00:00"
	end

	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = math.floor(seconds % 60)
	local ms = math.floor((seconds % 1) * 1000)

	if show_ms then
		return string.format("%02d:%02d:%02d:%03d", hours, minutes, secs, ms)
	else
		return string.format("%02d:%02d:%02d", hours, minutes, secs)
	end
end

-- Convert seconds to MPV-compatible timestamp (HH:MM:SS.mmm)
function StringOps.to_timestamp(seconds)
	if not seconds or seconds < 0 then
		return "00:00:00.000"
	end

	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = math.floor(seconds % 60)
	local ms = math.floor((seconds % 1) * 1000)

	return string.format("%02d:%02d:%02d.%03d", hours, minutes, secs, ms)
end

-- Remove invalid filesystem characters from name
function StringOps.sanitize_filename(filename)
	if not filename or filename == "" then
		return "untitled"
	end

	local sanitized = filename:gsub('[<>:"/\\|?*]', "_")
	return StringOps.trim(sanitized)
end

-- Extract media title from metadata or path
function StringOps.clean_title(title, path)
	local s = title
	if not s or s == "" then
		s = path or "Unknown"
	end

	-- Strip path and only keep filename
	s = s:gsub("^.*[/\\]", "")

	-- Replace underscores with spaces
	s = s:gsub("_", " ")

	-- Strip extension once at the start
	s = s:gsub("%.%w+$", "")

	-- Truncate at SxxExx or compact Sxxxx
	s = s:gsub("[%.%s_%-]+[Ss]%d%d?[Ee]%d%d?.*", "")
	s = s:gsub("[%.%s_%-]+[Ss]%d%d%d%d.*", "")

	-- Strip hex checksums
	s = s:gsub("[%[%(]%x%x%x%x%x%x%x%x[%]%]%)]", "")

	-- Strip leading group tag
	s = s:gsub("^%[[^%]]+%]%s*", "")
	s = s:gsub("^%([^%)]+%)%s*", "")

	-- Strip quality and codec tags
	local tags = {
		"1080[pP]", "720[pP]", "480[pP]", "2160[pP]", "1440[pP]", "576[pP]",
		"[0-9]+[xX][0-9]+",
		"[xX]26[45]", "[hH]%.?26[45]", "[hH][eE][vV][cC]", "[aA][vV][cC]",
		"[eE]?[%-]?[aA][cC]3", "[aA][aA][cC]", "[mM][pP]3", "[fF][lL][aA][cC][0-9%.]*",
		"[dD][tT][sS]%-[hH][dD]", "[dD][tT][sS]", "[tT][rR][uU][eE][hH][dD]", "[oO][pP][uU][sS]",
		"[dD][dD][pP][0-9%.]*", "[hH][iI]10[pP]?", "[0-9]+%-?bit",
		"[nN][fF]", "[wW][eE][bB]%-?[dD][lL]", "[wW][eE][bB][rR][iI][pP]",
		"[hH][dD][rR][0-9]*", "[dD][vV]", "[bB][lL][uU]%-?[rR][aA][yY]",
		"[mM][uU][lL][tT][iI][^%s%.%-_]*", "[mM][sS][uU][bB][sS]?", "[dD][uU][aA][lL]", "[aA][uU][dD][iI][oO]",
		"[yY][uU][rR][aA][sS][uU][kK][aA]", "[tT][oO][oO][nN][sS]?[hH][uU][bB]?",
		"[0-9]+%-[bB][iI][tT]",
		"[uU][nN][cC][eE][nN][sS][oO][rR][eE][dD]", "[cC][eE][nN][sS][oO][rR][eE][dD]",
		"[bB][aA][tT][cC][hH]", "[rR][eE][pP][aA][cC][kK]", "[pP][rR][oO][pP][eE][rR]",
		"[bB][dD][rR][iI][pP]?", "[bB][dD]", "[tT][vV]", "[wW][eE][bB]",
		"[vV][pP]9", "[aA][vV]1", "[xX][vV][iI][dD]",
		"[sS][pP][eE][cC][iI][aA][lL]", "[oO][vV][aA]", "[oO][nN][aA]", "[oO][aA][dD]",
		"[aA][tT][mM][oO][sS]", "[rR][eE][mM][uU][xX]",
		"[aA][mM][zZ][nN]", "[jJ][pP][nN]", "[dD][sS][nN][pP]", "[cC][rR]", "[fF][uU][nN][iI]",
		"[aA][bB][eE][mM][aA]", "[wW][oO][wW][oO][wW]", "[bB][sS]%-?[0-9]*", "[aA][tT]%-?[xX]",
		"[mM][xX]", "[tT][vV][kK]", "[tT][vV][oO]", "[aA][nN][yY][iI][vV]", "[hH][iI][dD][iI][vV][eE]",
		"[pP][rR][iI][mM][eE]"
	}

	for _, tag in ipairs(tags) do
		-- Clean tags inside delimiters
		s = s:gsub("[%s%.%-%_%[%(]" .. tag .. "[%s%.%-%_%]%)/]", " ")
		s = s:gsub("[%s%.%-%_%[%(]" .. tag .. "$", "")
		s = s:gsub("^" .. tag .. "[%s%.%-%_%]%)/]", "")
	end

	-- Clean empty or punctuation brackets
	for _ = 1, 3 do -- Recursive cleanup for nested or sequential brackets
		s = s:gsub("%([%s%.%-_]*%)", "")
		s = s:gsub("%[[%s%.%-_]*%]", "")
		s = s:gsub("【[%s%.%-_]*】", "")
	end

	s = StringOps.trim(StringOps.normalize_spacing(s))

	-- Strip version tags
	s = s:gsub("[%[%s%.%-_][vV][0-9]+[%]%s%.%-_]*$", "")
	s = s:gsub("[%[%s%.%-_][Vv][0-9]+[%]%s%.%-_]*", " ")

	-- Strip release years
	s = s:gsub("[%[%s%.%-_%(][12][0-9][0-9][0-9][%]%s%.%-_%)]", " ")
	s = s:gsub("[%[%s%.%-_%(][12][0-9][0-9][0-9]$", "")

	-- Strip standalone info
	s = s:gsub("[%s%.%-_]%([Tt][Vv]%)", "")
	s = s:gsub("[%s%.%-_]%([Mm][Oo][Vv][Ii][Ee]%)", "")
	s = s:gsub("[%s%.%-_]%([Oo][Vv][Aa]%)", "")
	s = s:gsub("[%s%.%-_]%([Oo][Nn][Aa]%)", "")

	-- Clean empty brackets
	for _ = 1, 2 do
		s = s:gsub("%([%s%.%-_]*%)", "")
		s = s:gsub("%[[%s%.%-_]*%]", "")
		s = s:gsub("【[%s%.%-_]*】", " ")
	end

	-- Strip season, episode, and version tags
	local cleaner_patterns = {
		"[%.%s_]+[Ss]%d+[Ee]%d+",
		"[%.%s_]+[Ee]%d+",
		"[%.%s_]+[Ss]eason%s*%d+",
		"[%.%s_]+%d+[a-z][a-z]%s+[Ss]eason",
		"[%.%s_]+[Ss]%d+",
		"[%.%s_%[%(]+[0-9]+[vV][0-9]+[%]%)%s%.%-_]*$",
		"[%s%.%-%_]+[0-9]+$"
	}

	for _, pattern in ipairs(cleaner_patterns) do
		s = StringOps.trim(s)
		s = s:gsub(pattern, "")
	end

	-- Strip trailing group tags and bracketed info
	s = s:gsub("%s*[%[%(][^%]]-[%]%)]%s*$", "")

	-- Strip trailing punctuation and delimiters
	s = s:gsub("[%s%-%:_%.]+$", "")

	-- Replace dots with spaces and normalize
	s = s:gsub("%.", " ")
	return StringOps.trim(StringOps.normalize_spacing(s))
end

-- Extract season and episode from title or path
function StringOps.parse_season_episode(title, path)
	local source = title or path or ""
	source = source:gsub("%.%w+$", "")

	local season, episode

	-- Combined S01E01 format
	season, episode = source:match("[Ss](%d+)[Ee](%d+)")

	-- Fallback for compact 4-digit blocks
	if not season then
		local block = source:match("[Ss](%d%d%d%d)")
		if block then
			season = block:sub(1, 2)
			episode = block:sub(3, 4)
		end
	end

	-- Independent season detection (before stripping brackets/parentheses)
	if not season then
		season = source:match("[ _%.%-][Ss]eason%s*(%d+)")
			or source:match("^[Ss]eason%s*(%d+)")
			or source:match("[ _%.%-][Ss](%d+)[ _%.%-]")
			or source:match("[ _%.%-][Ss](%d+)$")
			or source:match("^(%d+)[a-z][a-z]%s+[Ss]eason")
			or source:match("[%( ][ _%.%-]?(%d+)[a-z][a-z]%s+[Ss]eason")
	end

	-- Strip common tags/info that interfere with episode detection
	source = source:gsub("%[[^%]]-%]", "")
	source = source:gsub("%([^%)]-%)", "")
	source = source:gsub("（.-）", "")
	source = source:gsub("【.-】", "")
	source = source:gsub("[vV][0-9]+", "") -- v2, v3
	source = source:gsub("[%s%.%-_][12][0-9][0-9][0-9][%s%.%-_]", " ") -- years
	source = source:gsub("[%s%.%-_][12][0-9][0-9][0-9]$", "") -- years at end
	source = source:gsub("[%s%.%-]1080[pP]", "")
	source = source:gsub("[%s%.%-]720[pP]", "")
	source = source:gsub("[%s%.%-]480[pP]", "")
	source = source:gsub("[%s%.%-_][xX]26[45]", "")
	source = source:gsub("[%s%.%-_][hH]%.?26[45]", "")
	source = source:gsub("[%s%.%-_][hH][eE][vV][cC]", "")
	source = source:gsub("[%s%.%-_][aA][vV][cC]", "")
	source = source:gsub("[%s%.%-_][aA][cC]3", "")
	source = source:gsub("[%s%.%-_][aA][aA][cC]", "")
	source = source:gsub("[%s%.%-_][mM][pP]3", "")
	source = source:gsub("[%s%.%-_][fF][lL][aA][cC][0-9%.]*", "")
	source = source:gsub("[%s%.%-_][dD][dD][pP][0-9%.]*", "")
	source = source:gsub("[%s%.%-_][hH][iI]10[pP]?", "")
	source = source:gsub("[%s%.%-_][nN][fF]", "")
	source = source:gsub("[%s%.%-_][wW][eE][bB]%-?[dD][lL]", "")
	source = source:gsub("[%s%.%-_][bB][lLuU]%-?[rR][aA][yY]", "")
	source = source:gsub("[%s%.%-_][mM][uU][lL][tT][iI][^%s%.%-_]*", "")

	-- Independent episode detection
	if not episode then
		episode = source:match("[ _%.%-][Ee][Pp]?%s*(%d+)")
			or source:match("^[Ee][Pp]?%s*(%d+)")
			-- Trailing number that isn't part of a season tag
			or source:match("[ _%.%-](%d+)[^0-9]*$")
	end

	return season, episode
end

-- Trim leading and trailing whitespace
function StringOps.trim(text)
	if not text then
		return ""
	end
	return text:gsub("^[ \t\n\r]+", ""):gsub("[ \t\n\r]+$", "")
end

-- Collapse multiple spaces into single space
function StringOps.normalize_spacing(text)
	if not text then
		return ""
	end
	return text:gsub("[ \t\n\r]+", " ")
end

-- Parse a comma-separated string into a table of lowercase, trimmed strings
function StringOps.parse_comma_list(str)
	local result = {}
	if not str or str == "" then return result end
	for s in string.gmatch(str, "([^,]+)") do
		table.insert(result, (s:lower():gsub("^%s+", ""):gsub("%s+$", "")))
	end
	return result
end

-- Check if text contains any of the provided lowercase keywords
function StringOps.contains_any(text, keywords)
	if not text or not keywords then return false end
	local lower = text:lower()
	for _, kw in ipairs(keywords) do
		if lower:find(kw, 1, true) then
			return true
		end
	end
	return false
end

function StringOps.has_japanese(text)
	if not text or text == "" then
		return false
	end

	-- UTF-8 byte match check for Hiragana, Katakana, and Kanji ranges
	return text:find("[\227][\128-\131]") ~= nil
		or text:find("[\228-\233]") ~= nil
		or text:find("[\239][\189-\190]") ~= nil
end

function StringOps.is_hiragana_only(text)
	if not text or text == "" then return false end
	local char_count, hiragana_count = 0, 0
	for _, code in StringOps.utf8_codes(text) do
		-- Hiragana range: U+3041 to U+309F
		if code >= 0x3041 and code <= 0x309F then
			hiragana_count = hiragana_count + 1
		end
		char_count = char_count + 1
	end
	return char_count > 0 and char_count == hiragana_count
end

function StringOps.is_katakana_only(text)
	if not text or text == "" then return false end
	local char_count, katakana_count = 0, 0
	for _, code in StringOps.utf8_codes(text) do
		-- Katakana range: U+30A0 to U+30FF
		if code >= 0x30A0 and code <= 0x30FF then
			katakana_count = katakana_count + 1
		end
		char_count = char_count + 1
	end
	return char_count > 0 and char_count == katakana_count
end

-- Iterator that yields (next_index, codepoint)
local function utf8_iter(s, i)
	if not s then
		return nil
	end
	i = i or 1
	if i > #s then
		return nil
	end
	local c = string.byte(s, i)
	local code
	local next_i
	if c < 128 then
		code = c
		next_i = i + 1
	elseif c >= 194 and c <= 223 then
		local c2 = string.byte(s, (i + 1)) or 0
		code = ((c - 192) * 64) + (c2 - 128)
		next_i = i + 2
	elseif c >= 224 and c <= 239 then
		local c2 = string.byte(s, (i + 1)) or 0
		local c3 = string.byte(s, (i + 2)) or 0
		code = ((c - 224) * 4096) + ((c2 - 128) * 64) + (c3 - 128)
		next_i = i + 3
	elseif c >= 240 and c <= 244 then
		local c2 = string.byte(s, (i + 1)) or 0
		local c3 = string.byte(s, (i + 2)) or 0
		local c4 = string.byte(s, (i + 3)) or 0
		code = ((c - 240) * 262144) + ((c2 - 128) * 4096) + ((c3 - 128) * 64) + (c4 - 128)
		next_i = i + 4
	else
		code = c
		next_i = i + 1
	end
	return next_i, code
end

function StringOps.utf8_codes(str)
	return utf8_iter, str, 1
end

function StringOps.get_char_count(text)
	local count = 0
	for _ in StringOps.utf8_codes(text) do
		count = count + 1
	end
	return count
end

function StringOps.get_char_byte_pos(text, char_index)
	if not char_index or char_index <= 1 then
		return 1
	end
	local i = 1
	local current_char = 0
	for next_i, _ in StringOps.utf8_codes(text) do
		current_char = current_char + 1
		if current_char == char_index then
			return i
		end
		i = next_i
	end
	return i
end

function StringOps.count_shared_prefix(a, b)
	if not a or not b then return 0 end
	local shared = 0
	local iter_b, state_b, cur_b = StringOps.utf8_codes(b)
	for _, code_a in StringOps.utf8_codes(a) do
		local n_b, code_b = iter_b(state_b, cur_b)
		if not n_b or code_a ~= code_b then
			break
		end
		shared = shared + 1
		cur_b = n_b
	end
	return shared
end

return StringOps
