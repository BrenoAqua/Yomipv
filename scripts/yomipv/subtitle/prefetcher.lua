--[[ Subtitle prefetcher                                          ]]
--[[ Extracts and caches subtitle text ahead of playback position ]]

local mp = require("mp")
local msg = require("mp.msg")
local SubUtils = require("subtitle.subtitle_utils")
local StringOps = require("lib.string_ops")
local MediaUtils = require("media.helpers")

local ffmpeg_exec = MediaUtils.resolve_binary("ffmpeg")

local Prefetcher = {
	_entries = {}, -- {start_s, end_s, text}
	_ready = false,
}

local function parse_srt(raw)
	local entries = {}

	-- Robust block splitting handles mixed LF and CRLF line endings
	for block in (raw .. "\n\n"):gmatch("(.-)\n\r?\n") do
		local t_line = block:match("\n?%d+:%d+:%d+[,.]%d+ %-%-> %d+:%d+:%d+[,.]%d+")
		if t_line then
			local t_start_str, t_end_str = t_line:match("(%d+:%d+:%d+[,.]%d+) %-%-> (%d+:%d+:%d+[,.]%d+)")
			local t_start = SubUtils.parse_srt_time(t_start_str)
			local t_end   = SubUtils.parse_srt_time(t_end_str)

			-- Multiline text capture
			local text_raw = block:match("%d+:%d+:%d+[,.]%d+ %-%-> %d+:%d+:%d+[,.]%d+[ \t]*\r?\n(.*)")
			if text_raw and not SubUtils.is_song_text(text_raw) then
				local text = StringOps.clean_subtitle(text_raw, true)
				if t_start and t_end and text ~= "" then
					table.insert(entries, { start_s = t_start, end_s = t_end, text = text })
				end
			end
		end
	end

	msg.info(string.format("Prefetcher: Parsed %d subtitle entries", #entries))
	return entries
end

function Prefetcher.reset()
	Prefetcher._entries = {}
	Prefetcher._ready = false
end

function Prefetcher.load()
	Prefetcher.reset()

	local path = mp.get_property("path")
	if not path then
		msg.warn("Prefetcher: No file path available")
		return
	end

	local sub_file = mp.get_property("current-tracks/sub/external-filename")
	if sub_file and sub_file ~= "" then
		msg.info("Prefetcher: Using external subtitle file: " .. sub_file)
		Prefetcher._extract_from_file(sub_file)
		return
	end

	local track_id = mp.get_property_number("current-tracks/sub/ff-index")
	if not track_id then
		msg.info("Prefetcher: No active subtitle track found")
		return
	end

	msg.info(string.format("Prefetcher: Extracting internal track (ff-index %d) via ffmpeg", track_id))
	Prefetcher._extract_from_video(path, track_id)
end

function Prefetcher._extract_from_file(file_path)
	mp.command_native_async({
		name = "subprocess",
		playback_only = false,
		capture_stdout = true,
		capture_stderr = true,
		args = {
			ffmpeg_exec,
			"-hide_banner",
			"-v", "quiet",
			"-i", file_path,
			"-map", "0:s:0",
			"-f", "srt",
			"pipe:1",
		},
	}, function(success, result, _err)
		if not success or result.status ~= 0 or not result.stdout or result.stdout == "" then
			msg.info("Prefetcher: ffmpeg failed on external file, trying plain read")
			local f = io.open(file_path, "r")
			if f then
				local raw = f:read("*a")
				f:close()
				Prefetcher._entries = parse_srt(raw)
				Prefetcher._ready = #Prefetcher._entries > 0
			end
			return
		end

		Prefetcher._entries = parse_srt(result.stdout)
		Prefetcher._ready = #Prefetcher._entries > 0
	end)
end

function Prefetcher._extract_from_video(video_path, ff_index)
	local map_arg = string.format("0:%d", ff_index)

	mp.command_native_async({
		name = "subprocess",
		playback_only = false,
		capture_stdout = true,
		capture_stderr = true,
		args = {
			ffmpeg_exec,
			"-hide_banner",
			"-v", "quiet",
			"-i", video_path,
			"-map", map_arg,
			"-f", "srt",
			"pipe:1",
		},
	}, function(success, result, _err)
		if not success or result.status ~= 0 or not result.stdout or result.stdout == "" then
			msg.warn("Prefetcher: ffmpeg extraction failed for internal track")
			return
		end

		Prefetcher._entries = parse_srt(result.stdout)
		Prefetcher._ready = #Prefetcher._entries > 0
	end)
end

function Prefetcher.get_next_lines(current_time, current_text, count)
	if not Prefetcher._ready then
		return {}
	end

	local results = {}
	local sub_delay = mp.get_property_number("sub-delay", 0)

	for _, entry in ipairs(Prefetcher._entries) do
		-- Avoid showing text that matches currently displayed dialogue
		if (entry.start_s + sub_delay) > current_time and entry.text ~= current_text then
			table.insert(results, entry.text)
			if #results >= count then
				break
			end
		end
	end

	return results
end

return Prefetcher
