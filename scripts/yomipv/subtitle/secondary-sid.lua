--[[ Secondary Subtitle Manager                                ]]
--[[ Tracking and auto-selection of secondary subtitle tracks. ]]

local mp = require("mp")
local msg = require("mp.msg")

local SecondarySid = {}

-- Initialize secondary track management
function SecondarySid.init(config)
	SecondarySid._config = config
	if not config.secondary_sid then
		return
	end

	mp.register_event("file-loaded", function()
		SecondarySid.select_secondary_track()
	end)

	if config.secondary_on_hover then
		SecondarySid.setup_hover_tracking()
	end
end

-- Internal state for hover tracking
local last_sid = "no"
local is_hovering = false

-- Initialize hover tracking
function SecondarySid.setup_hover_tracking()
	local function update_hover_state()
		local _, oh = mp.get_osd_size()
		if oh == 0 then
			return
		end

		local _, my = mp.get_mouse_pos()
		local hover_zone = oh * 0.2 -- Top 20% of screen
		local currently_hovering = my <= hover_zone

		if currently_hovering ~= is_hovering then
			is_hovering = currently_hovering
			if is_hovering then
				-- Show subtitles at the top
				mp.set_property_native("secondary-sub-visibility", true)
				mp.set_property_number("secondary-sub-pos", 10)
				msg.info("Hover: Showing secondary subtitles")
			else
				-- Hide subtitles but keep track active for capture
				mp.set_property_native("secondary-sub-visibility", false)
				msg.info("Hover: Hiding secondary subtitles")
			end
		end
	end

	-- Monitor manual track changes
	mp.observe_property("secondary-sid", "string", function(_, val)
		if val and val ~= "no" then
			last_sid = val
			-- Ensure visibility matches hover state
			if SecondarySid._config.secondary_on_hover then
				mp.set_property_native("secondary-sub-visibility", is_hovering)
				if is_hovering then
					mp.set_property_number("secondary-sub-pos", 10)
				end
			end
		end
	end)

	-- Check hover state periodically
	mp.add_periodic_timer(0.1, update_hover_state)
	update_hover_state() -- Initial check
end

-- Select secondary subtitle track
function SecondarySid.select_secondary_track()
	local tracks = mp.get_property_native("track-list")
	if not tracks then
		return
	end

	local current_sid = mp.get_property_number("sid") or 0
	local secondary_sid = mp.get_property("secondary-sid")

	-- Respect manual selection
	if secondary_sid and secondary_sid ~= "no" then
		msg.info("Secondary subtitle already set to: " .. secondary_sid)
		last_sid = secondary_sid
		if SecondarySid._config.secondary_on_hover then
			mp.set_property_native("secondary-sub-visibility", is_hovering)
			if is_hovering then
				mp.set_property_number("secondary-sub-pos", 10)
			end
		end
		return
	end

	local sub_lang_opt = SecondarySid._config.secondary_sub_lang
	if not sub_lang_opt or sub_lang_opt == "" then
		msg.info("Secondary subtitle auto-selection disabled (secondary_sub_lang empty)")
		mp.set_property("secondary-sid", "no")
		return
	end

	local requested_langs = {}
	for s in string.gmatch(sub_lang_opt, "([^,]+)") do
		table.insert(requested_langs, (s:lower():gsub("^%s+", ""):gsub("%s+$", "")))
	end

	local exclude_opt = SecondarySid._config.secondary_sub_exclude or ""
	local excluded_keywords = {}
	for s in string.gmatch(exclude_opt, "([^,]+)") do
		table.insert(excluded_keywords, (s:lower():gsub("^%s+", ""):gsub("%s+$", "")))
	end

	local function is_excluded(title)
		for _, kw in ipairs(excluded_keywords) do
			if title:find(kw, 1, true) then
				return true
			end
		end
		return false
	end

	for _, pattern in ipairs(requested_langs) do
		for _, track in ipairs(tracks) do
			if track.type == "sub" and track.id ~= current_sid then
				local lang = (track.lang or ""):lower()
				local title = (track.title or ""):lower()

				if not is_excluded(title) and (lang == pattern or title:find(pattern, 1, true)) then
					msg.info("Auto-selecting secondary subtitle: " .. track.id .. " (" .. (track.lang or "unknown") .. ")")

					last_sid = tostring(track.id)
					mp.set_property("secondary-sid", last_sid)

					if SecondarySid._config.secondary_on_hover then
						mp.set_property_native("secondary-sub-visibility", is_hovering)
						if is_hovering then
							mp.set_property_number("secondary-sub-pos", 10)
						end
					else
						mp.set_property_native("secondary-sub-visibility", true)
					end
					return
				end
			end
		end
	end

	msg.warn("No suitable secondary subtitle found matching: " .. sub_lang_opt)
	mp.set_property("secondary-sid", "no")
end

-- Manually cycle secondary subtitle track
function SecondarySid.cycle_track(direction)
	local tracks = mp.get_property_native("track-list")
	if not tracks then
		return
	end

	local sub_tracks = {}
	local current_index = 0
	local secondary_sid = tonumber(mp.get_property("secondary-sid"))

	for _, track in ipairs(tracks) do
		if track.type == "sub" then
			table.insert(sub_tracks, track)
			if secondary_sid and track.id == secondary_sid then
				current_index = #sub_tracks
			end
		end
	end

	if #sub_tracks == 0 then
		msg.warn("No subtitle tracks available to cycle")
		return
	end

	local new_index = current_index + direction

	if current_index == 0 then
		if direction > 0 then
			new_index = 1
		else
			new_index = #sub_tracks
		end
	else
		if new_index > #sub_tracks then
			new_index = 0
		elseif new_index < 0 then
			new_index = #sub_tracks
		end
	end

	if new_index == 0 then
		msg.info("Cycling secondary subtitle: disabled")
		mp.set_property("secondary-sid", "no")
		mp.osd_message("Secondary Sub: Disabled")
	else
		local new_track = sub_tracks[new_index]
		local lang = new_track.lang and (" [" .. new_track.lang .. "]") or ""
		local title = new_track.title and (" - " .. new_track.title) or ""

		msg.info(string.format("Cycling secondary subtitle: %d%s%s", new_track.id, lang, title))
		mp.set_property("secondary-sid", tostring(new_track.id))
		mp.osd_message(string.format("Secondary Sub: %d%s%s", new_track.id, lang, title))
	end
end

return SecondarySid
