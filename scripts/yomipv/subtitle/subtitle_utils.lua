--[[ Subtitle Utilities                           ]]
--[[ Shared logic for text processing and parsing ]]

local SubtitleUtils = {}

function SubtitleUtils.is_song_text(text)
	if not text then return false end
	-- UTF-8 byte match check for ♪, ♫, ♬ to exclude lyrics from analysis
	return text:find("\226\153\170") ~= nil
		or text:find("\226\153\171") ~= nil
		or text:find("\226\153\172") ~= nil
end

function SubtitleUtils.strip_tags(text)
	if not text then return "" end
	return text
		:gsub("{[^}]-}", "") -- Remove ASS override blocks
		:gsub("<[^>]->", "") -- Remove HTML tags used in SRT/WebVTT
end

function SubtitleUtils.clean_text(text)
	if SubtitleUtils.is_song_text(text) then return "" end

	-- Remove non-dialogue elements to simplify text matching
	local clean = SubtitleUtils.strip_tags(text)
		:gsub("\\N", "")          -- Standard ASS newline
		:gsub("\\n", "")
		:gsub("\\h", "")          -- Non-breaking space
		:gsub("%s+", "")          -- Consolidate all whitespace for length check
		:gsub("\227\128\128", "") -- Full-width Japanese space

	return clean
end

function SubtitleUtils.parse_srt_time(ts_str)
	local h, m, s, ms = ts_str:match("(%d+):(%d+):(%d+)[,.](%d+)")
	if not h then return nil end
	return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + tonumber(ms) / 1000
end

function SubtitleUtils.parse_ass_time(ts_str)
	local h, m, s, cs = ts_str:match("(%d+):(%d%d):(%d%d)%.(%d%d)")
	if not h then return nil end
	return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + tonumber(cs) / 100
end

return SubtitleUtils
