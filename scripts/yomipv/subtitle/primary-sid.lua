--[[ Primary Subtitle Manager ]]

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")
local StringOps = require("lib.string_ops")

local PrimarySid = {}

function PrimarySid.init(config)
	PrimarySid._config = config
	if not config.primary_autoload then
		return
	end

	mp.register_event("file-loaded", function()
		PrimarySid.auto_load_external_subtitles()
	end)
end

function PrimarySid.auto_load_external_subtitles()
	local path = mp.get_property("path")
	if not path or path == "" then return end

	local is_network = path:match("^http://") or path:match("^https://")
	if is_network then return end

	local dir, current_filename = utils.split_path(path)
	if not dir or dir == "" then return end

	local files = utils.readdir(dir, "files")
	if not files then return end

	local current_title = mp.get_property("media-title", "")
	local current_clean = StringOps.clean_title(current_title, path)
	local _, current_episode = StringOps.parse_season_episode(current_title, current_filename)

	if not current_episode or current_episode == "" then
		return
	end

	local sub_lang_opt = PrimarySid._config.primary_sub_lang or ""
	local requested_langs = {}
	for s in string.gmatch(sub_lang_opt, "([^,]+)") do
		table.insert(requested_langs, (s:lower():gsub("^%s+", ""):gsub("%s+$", "")))
	end

	local excluded_keywords = StringOps.parse_comma_list(PrimarySid._config.primary_sub_exclude)

	local valid_exts = { srt = true, ass = true, vtt = true }
	local found_matches = {}

	for _, file in ipairs(files) do
		local ext = file:match("%.([^%.]+)$")
		if ext and valid_exts[ext:lower()] and file ~= current_filename then
			if not StringOps.contains_any(file, excluded_keywords) then
				local full_path = utils.join_path(dir, file)
				local sub_clean = StringOps.clean_title(file, file)
				local _, sub_episode = StringOps.parse_season_episode(file, file)

				if sub_episode == current_episode and sub_clean == current_clean then
					table.insert(found_matches, full_path)
				end
			end
		end
	end

	if #found_matches > 0 then
		-- We use cached to avoid immediate overriding if multiple are appended
		-- Then we check track-list to select the best one.
		for _, sub_path in ipairs(found_matches) do
			msg.info("Auto-loading external subtitle: " .. sub_path)
			mp.commandv("sub-add", sub_path, "cached")
		end

		mp.add_timeout(0.5, function()
			PrimarySid.select_primary_track()
		end)
	end
end

function PrimarySid.select_primary_track()
	local tracks = mp.get_property_native("track-list")
	if not tracks then return end

	local current_sid = mp.get_property_number("sid") or 0

	local sub_lang_opt = PrimarySid._config.primary_sub_lang
	if not sub_lang_opt or sub_lang_opt == "" then
		return
	end

	local requested_langs = StringOps.parse_comma_list(sub_lang_opt)

	for _, pattern in ipairs(requested_langs) do
		for _, track in ipairs(tracks) do
			if track.type == "sub" and track.external then
				local lang = (track.lang or ""):lower()
				local title = (track.title or ""):lower()

				if lang == pattern or title:find(pattern, 1, true) or (lang == "" and title == "") then
					if track.id ~= current_sid then
						msg.info("Auto-selecting primary subtitle: " .. track.id .. " (" .. (track.lang or "unknown") .. ")")
						mp.set_property("sid", tostring(track.id))
					end
					return
				end
			end
		end
	end
end

return PrimarySid
