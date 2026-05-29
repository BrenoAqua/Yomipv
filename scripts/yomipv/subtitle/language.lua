--[[ Primary subtitle language detection ]]

local mp = require("mp")
local StringOps = require("lib.string_ops")

local Language = {}

local japanese_langs = {
	ja = true,
	jp = true,
	jpn = true,
	japanese = true,
	nihongo = true,
	["日本語"] = true,
}

local function normalize_lang(lang)
	if type(lang) ~= "string" then return nil end
	local normalized = lang:lower():gsub("[%s_%-]+", "")
	return normalized ~= "" and normalized or nil
end

function Language.is_japanese_lang(lang)
	local normalized = normalize_lang(lang)
	return normalized ~= nil and japanese_langs[normalized] == true
end

function Language.get_primary_subtitle_track()
	if mp.get_property_native then
		local current_track = mp.get_property_native("current-tracks/sub")
		if type(current_track) == "table" then
			return current_track
		end
	end

	local sid = mp.get_property_number("sid")
	if not sid then
		return nil
	end

	local tracks = mp.get_property_native and mp.get_property_native("track-list") or nil
	if type(tracks) ~= "table" then
		return nil
	end

	for _, track in ipairs(tracks) do
		if track.type == "sub" and tonumber(track.id) == sid then
			return track
		end
	end

	return nil
end

function Language.is_primary_subtitle_japanese(text)
	local track = Language.get_primary_subtitle_track()
	local lang = track and track.lang

	if type(lang) == "string" and lang ~= "" then
		return Language.is_japanese_lang(lang)
	end

	return StringOps.has_japanese(text or mp.get_property("sub-text", ""))
end

return Language
