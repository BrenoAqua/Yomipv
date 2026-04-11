--[[ Subtitle Sync                               ]]
--[[ Aligns primary to secondary subtitle timing ]]

local mp = require("mp")
local msg = require("mp.msg")
local Player = require("lib.player")
local MediaUtils = require("media.helpers")
local SubUtils = require("subtitle.subtitle_utils")

local SubtitleSync = {}
local ffmpeg_exec = MediaUtils.resolve_binary("ffmpeg")

local SYNC_THRESHOLD = 0.1
local SAMPLE_COUNT   = 32
local BIN            = 0.25

-- Exclude known sign/lyric styles from timing extraction
local SONG_STYLES = {
	song = true, karaoke = true, op = true, ed = true,
	signs = true, sign = true, opening = true, ending = true,
}

local function push_time(times, t_start, t_end, max)
	-- Reject very short sign subtitles
	if (t_end - t_start) < 0.3 then return false end
	-- 1.0s gap filters out dense automated sign clusters
	if #times > 0 and math.abs(t_start - times[#times]) < 1.0 then return false end

	times[#times + 1] = t_start
	return #times >= max
end

local function native_extract_times(file_path, max)
	local f = io.open(file_path, "r")
	if not f then return {} end
	local content = f:read(131072) or "" -- Buffer limit for large script files
	f:close()

	local times = {}

	-- SRT path
	if content:find("%d+:%d+:%d+[,.]%d+ %-%->") then
		-- Fallback to literal search if line endings are mixed
		for block in (content .. "\n\n"):gmatch("(.-)\n\r?\n") do
			local start_str, end_str = block:match("(%d+:%d+:%d+[,.]%d+) %-%-> (%d+:%d+:%d+[,.]%d+)")
			if start_str and end_str then
				local text = block:match("%d+:%d+:%d+[,.]%d+ %-%-> %d+:%d+:%d+[,.]%d+[ \t]*\r?\n(.*)") or ""
				if SubUtils.clean_text(text) ~= "" then
					local ts = SubUtils.parse_srt_time(start_str)
					local te = SubUtils.parse_srt_time(end_str)
					if ts and te then
						if push_time(times, ts, te, max) then break end
					end
				end
			end
		end
		return times
	end

	-- ASS path
	for line in content:gmatch("[^\r\n]+") do
		if line:sub(1, 9) == "Dialogue:" then
			local parts = {}
			for p in (line .. ","):gmatch("([^,]*),") do parts[#parts + 1] = p end
			local style_name = (parts[4] or ""):lower():match("^%s*(.-)%s*$")
			local start_str  = parts[2] or ""
			local end_str    = parts[3] or ""
			if not SONG_STYLES[style_name] then
				local text_raw = table.concat(parts, ",", 10)
				if SubUtils.clean_text(text_raw) ~= "" then
					local ts = SubUtils.parse_ass_time(start_str)
					local te = SubUtils.parse_ass_time(end_str)
					if ts and te then
						if push_time(times, ts, te, max) then break end
					end
				end
			end
		end
	end

	return times
end

local function parse_srt_times(srt_text, max)
	local times = {}
	for block in (srt_text .. "\n\n"):gmatch("(.-)\n\r?\n") do
		local start_str, end_str = block:match("(%d+:%d+:%d+[,.]%d+) %-%-> (%d+:%d+:%d+[,.]%d+)")
		if start_str and end_str then
			local text = block:match("%d+:%d+:%d+[,.]%d+ %-%-> %d+:%d+:%d+[,.]%d+[ \t]*\r?\n(.*)") or ""
			if SubUtils.clean_text(text) ~= "" then
				local ts = SubUtils.parse_srt_time(start_str)
				local te = SubUtils.parse_srt_time(end_str)
				if ts and te then
					if push_time(times, ts, te, max) then break end
				end
			end
		end
	end
	return times
end

local function find_best_offset(primary_times, secondary_times)
	if #primary_times == 0 or #secondary_times == 0 then return nil, "failed" end

	-- Cluster s-p time pairs into bins to find dominant offset
	local bin_votes = {}
	for _, s in ipairs(secondary_times) do
		for _, p in ipairs(primary_times) do
			local offset = s - p
			local bin = math.floor(offset / BIN + 0.5)
			if not bin_votes[bin] then bin_votes[bin] = {} end
			bin_votes[bin][s] = true
		end
	end

	-- Identify result with highest neighborhood support
	local best_count, best_bin = 0, nil
	for bin in pairs(bin_votes) do
		local seen, sum = {}, 0
		for _, nb in ipairs({ bin - 1, bin, bin + 1 }) do
			if bin_votes[nb] then
				for s in pairs(bin_votes[nb]) do
					if not seen[s] then seen[s] = true; sum = sum + 1 end
				end
			end
		end
		if sum > best_count then
			best_count = sum
			best_bin   = bin
		end
	end

	msg.info(string.format("SubtitleSync telemetry: P=%d S=%d peak_votes=%d",
		#primary_times, #secondary_times, best_count))

	if not best_bin or best_count < 4 then return nil, "failed" end

	-- Select the chronologically first line in the target bin to stabilize offset
	local earliest_s, best_offset = math.huge, nil
	for _, s in ipairs(secondary_times) do
		for _, p in ipairs(primary_times) do
			local offset = s - p
			local bin    = math.floor(offset / BIN + 0.5)
			if (bin == best_bin or bin == best_bin - 1 or bin == best_bin + 1) and s < earliest_s then
				earliest_s  = s
				best_offset = offset
			end
		end
	end

	return best_offset, "ok"
end

local function extract_sub_times(track_id, callback)
	local path = mp.get_property("path")
	local tracks = mp.get_property_native("track-list")
	if not path or not tracks then callback(nil) return end

	local target = nil
	for _, track in ipairs(tracks) do
		if track.id == track_id and track.type == "sub" then
			target = track
			break
		end
	end

	if not target then callback(nil) return end

	if target["external-filename"] then
		local times = native_extract_times(target["external-filename"], SAMPLE_COUNT)
		if #times > 0 then callback(times) return end
	end

	if not target["ff-index"] then callback(nil) return end

	local src = target["external-filename"] or path
	local map = target["external-filename"] and "0:s:0" or string.format("0:%d", target["ff-index"])

	mp.command_native_async({
		name = "subprocess",
		capture_stdout = true,
		args = {
			ffmpeg_exec or "ffmpeg",
			"-hide_banner",
			"-v", "quiet",
			"-probesize", "1M",
			"-analyzeduration", "0",
			"-i", src,
			"-map", map,
			"-t", "180",
			"-f", "srt",
			"pipe:1",
		},
	}, function(success, result)
		if not success or result.status ~= 0 then
			msg.error("SubtitleSync: ffmpeg extraction failed for track " .. track_id)
			callback(nil)
			return
		end
		local times = result.stdout and parse_srt_times(result.stdout, SAMPLE_COUNT) or {}
		callback(#times > 0 and times or nil)
	end)
end

function SubtitleSync.execute_instant_sync()
	local p_sid = mp.get_property_number("sid")
	local s_sid = mp.get_property_number("secondary-sid")
	if not p_sid or not s_sid then return end

	local p_times, s_times = nil, nil
	local checks_done = 0

	local function on_extract_done()
		checks_done = checks_done + 1
		if checks_done < 2 then return end

		local offset, reason = find_best_offset(p_times, s_times)
		if not offset then
			if reason ~= "aligned" then Player.notify("Track synchronization failed", "error") end
			return
		end

		if math.abs(offset) >= SYNC_THRESHOLD then
			mp.set_property_number("sub-delay", offset)
			Player.notify(string.format("Synced Subtitle Timing (%.3fs)", offset), "info")
		end
	end

	extract_sub_times(p_sid, function(t) p_times = t; on_extract_done() end)
	extract_sub_times(s_sid, function(t) s_times = t; on_extract_done() end)
end

function SubtitleSync.init(config)
	if config.auto_sync_subtitles then
		local sync_timer = nil
		local function trigger()
			if not mp.get_property_number("sid") or not mp.get_property_number("secondary-sid") then return end
			if sync_timer then sync_timer:kill() end
			-- Brief delay to prevent race conditions during rapid track cycling
			sync_timer = mp.add_timeout(0.1, function() SubtitleSync.execute_instant_sync() end)
		end
		mp.observe_property("sid", "number", trigger)
		mp.observe_property("secondary-sid", "number", trigger)
	end

	if config.key_sync_subtitles and config.key_sync_subtitles ~= "" then
		mp.add_key_binding(config.key_sync_subtitles, "yomipv-sync-subtitles", function()
			SubtitleSync.execute_instant_sync()
		end)
	end
end

return SubtitleSync
