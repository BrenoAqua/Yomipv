--[[ Note field builder                                                        ]]
--[[ Field construction for Anki notes including media templates and metadata. ]]

local mp = require("mp")
local StringOps = require("lib.string_ops")
local Collections = require("lib.collections")

local Builder = {}

function Builder.new(config)
	local obj = {
		config = config,
	}
	setmetatable(obj, Builder)
	Builder.__index = Builder
	return obj
end

function Builder:construct_note_fields(secondary_subtitle, picture_file, audio_file)
	local fields = {}

	if picture_file and not Collections.is_void(self.config.image_field) then
		fields[self.config.image_field] = string.format(self.config.image_template, picture_file)
	end

	if audio_file and not Collections.is_void(self.config.sentence_audio_field) then
		fields[self.config.sentence_audio_field] = string.format(self.config.audio_template, audio_file)
	end

	if not Collections.is_void(self.config.secondary_sentence_field) then
		fields[self.config.secondary_sentence_field] =
			string.format(self.config.secondary_sentence_wrapper, secondary_subtitle or "")
	end

	if not Collections.is_void(self.config.miscinfo_field) then
		fields[self.config.miscinfo_field] = self:generate_miscinfo()
	end

	return fields
end

function Builder:get_metadata()
	local title = mp.get_property("media-title", "")
	local path = mp.get_property("path", "")

	local sanitized_title = self._sanitize_title(title, path)
	local season_num, episode_num = StringOps.parse_season_episode(title, path)
	local timestamp = self:format_timestamp()

	return {
		name = sanitized_title,
		season_num = season_num,
		episode_num = episode_num,
		timestamp = timestamp,
	}
end

function Builder:generate_miscinfo()
	local metadata = self:get_metadata()

	local season_str = ""
	local episode_str = ""
	-- Use bullet for episode index and comma separator between components
	local bullet = self.config.miscinfo_episode_bullet and " • " or " "

	if metadata.season_num and (tonumber(metadata.season_num) > 1 or self.config.miscinfo_show_season_one) then
		season_str = self.config.miscinfo_season_label .. " " .. tonumber(metadata.season_num)
	end

	if metadata.episode_num then
		episode_str = self.config.miscinfo_episode_label .. " " .. tonumber(metadata.episode_num)
	end

	if season_str ~= "" and episode_str ~= "" then
		season_str = bullet .. season_str .. ", "
	elseif season_str ~= "" then
		season_str = bullet .. season_str
	elseif episode_str ~= "" then
		episode_str = bullet .. episode_str
	end

	local format = self.config.miscinfo_format

	format = format:gsub("{name}", metadata.name)
	format = format:gsub("{season}", season_str)
	format = format:gsub("{episode}", episode_str)
	format = format:gsub("{timestamp}", metadata.timestamp)

	return string.format(self.config.miscinfo_wrapper, format)
end

function Builder:format_tag(template)
	if not template or template == "" then
		return ""
	end

	local metadata = self:get_metadata()

	local function tag_safe(val)
		if not val then
			return ""
		end
		return tostring(val):gsub(" ", "_")
	end

	local name = tag_safe(metadata.name)
	local season_str = ""
	local episode_str = ""

	if metadata.season_num and (tonumber(metadata.season_num) > 1 or self.config.miscinfo_show_season_one) then
		season_str = tag_safe(self.config.miscinfo_season_label .. " " .. tonumber(metadata.season_num))
	end

	if metadata.episode_num then
		episode_str = tag_safe(self.config.miscinfo_episode_label .. " " .. tonumber(metadata.episode_num))
	end

	local result = template
	local replacements = {
		name = name,
		season = season_str,
		episode = episode_str,
		timestamp = tag_safe(metadata.timestamp),
	}

	for key, val in pairs(replacements) do
		result = result:gsub("%%?{" .. key .. "}", function()
			return val
		end)
	end

	result = result:gsub("%s+", "::")

	return result
end

function Builder._sanitize_title(title, path)
	return StringOps.clean_title(title, path)
end

function Builder:format_timestamp()
	local time_pos = mp.get_property_number("time-pos", 0)
	return StringOps.format_duration(time_pos, self.config.miscinfo_show_ms)
end

function Builder:_make_new_note_data(existing_fields, new_data)
	local result = {}

	for key, value in pairs(existing_fields) do
		result[key] = value
	end

	local update_fields = {
		[self.config.sentence_field] = true,
		[self.config.sentence_furigana_field] = true,
		[self.config.secondary_sentence_field] = true,
		[self.config.sentence_audio_field] = true,
		[self.config.image_field] = true,
		[self.config.miscinfo_field] = true,
	}

	for key, value in pairs(new_data) do
		if update_fields[key] then
			if not result[key] or result[key] == "" then
				result[key] = value
			else
				result[key] = result[key] .. "<br>" .. value
			end
		end
	end

	return result
end

return Builder
