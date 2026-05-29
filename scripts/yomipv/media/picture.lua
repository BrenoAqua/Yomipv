--[[ Picture extraction job creator                   ]]
--[[ Async job orchestration for video frame capture. ]]

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")
local MpvEncoder = require("media.extraction.mpv")
local MediaUtils = require("media.helpers")

local Picture = {
	output_dir = nil,
	config = nil,
}

function Picture.set_output_dir(dir)
	Picture.output_dir = dir
end

function Picture.init(config)
	Picture.config = config
end

function Picture.create_job(subtitle)
	if not Picture.config or not Picture.output_dir then
		msg.error("Picture module not initialized")
		return nil
	end

	local timestamp, duration
	if Picture.config.picture_animated then
		local offset = (not subtitle.is_manual_range) and (Picture.config.animation_offset or 0) or 0
		local end_offset = (not subtitle.is_manual_range) and (Picture.config.animation_end_offset or 0) or 0
		local subtitle_start = subtitle.start or 0
		local subtitle_end = subtitle["end"] or subtitle_start
		timestamp = subtitle_start + offset + 0.1

		if Picture.config.animation_duration == "auto" and subtitle.start and subtitle["end"] then
			duration = math.max(0.1, (subtitle_end + end_offset) - timestamp)
		else
			duration = tonumber(Picture.config.animation_duration) or 2.0
		end
	else
		local offset = (not subtitle.is_manual_range) and (Picture.config.picture_static_offset or 0) or 0
		if Picture.config.picture_timestamp_source == "current_position" then
			timestamp = subtitle.picture_timestamp or mp.get_property_number("time-pos", 0)
		else
			-- Offset by 0.1s to ensure text rendering and avoid previous subtitle bleeding
			timestamp = (subtitle.start or 0) + offset + 0.1
		end
		duration = 0
	end

	local format = Picture.config.picture_animated and Picture.config.animation_format
		or Picture.config.picture_static_format

	local source = mp.get_property("path", "")
	if not source or source == "" then
		msg.error("No media file loaded")
		return nil
	end

	local filename = MediaUtils.generate_filename("yomipv_picture", format or "jpg", Picture.config.filename_show_ms)

	local target_file = utils.join_path(Picture.output_dir, filename)

	local job = {
		target_file = filename,
		full_path = target_file,
		on_finish_callback = nil,
	}

	function job:on_finish(callback)
		self.on_finish_callback = callback
		return self
	end

	function job:run()
		msg.info(
			string.format(
				"Starting picture extraction: %s (timestamp: %.3f, duration: %.3f)",
				target_file,
				timestamp,
				duration
			)
		)

		local encoder = MpvEncoder
		if Picture.config.picture_use_ffmpeg and not MediaUtils.is_remote_path(source) then
			encoder = require("media.extraction.ffmpeg")
		end

		local args = encoder.generate_picture_args(Picture.config, source, target_file, timestamp, duration)

		mp.command_native_async({
			name = "subprocess",
			playback_only = false,
			args = args,
		}, function(success, result, error)
			msg.info("Picture args: " .. utils.to_string(args))
			if success and result.status == 0 then
				msg.info("Picture extracted: " .. filename)
				if self.on_finish_callback then
					self.on_finish_callback(true)
				end
			else
				msg.error("Picture extraction failed: " .. tostring(error or result.status))
				if self.on_finish_callback then
					self.on_finish_callback(false)
				end
			end
		end)
	end

	return job
end

return Picture
