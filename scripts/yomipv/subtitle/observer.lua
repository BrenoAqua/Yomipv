--[[ Subtitle event monitor                                          ]]
--[[ Observes player properties to coordinate subtitle capture flow. ]]

local mp = require("mp")
local msg = require("mp.msg")
local Prefetcher = require("subtitle.prefetcher")

local Observer = {
	monitor = nil,
	active = false,
}

-- Initialize subtitle observer state
function Observer.init(handler, yomitan, config)
	Observer.handler = handler
	Observer.monitor = handler.deps.tracker
	Observer.yomitan = yomitan
	Observer.config = config

	if config.pre_tokenize then
		Prefetcher.load()
	end

	mp.observe_property("sid", "native", function(_, val)
		if config.pre_tokenize then
			if val and val ~= "no" then
				mp.add_timeout(0.05, function()
					Prefetcher.load()
				end)
			else
				Prefetcher.reset()
			end
		end
	end)
end

-- Shared handler for subtitle changes
function Observer.handle_subtitle_change(name, value, is_proactive)
	local text = value or ""
	local StringOps = require("lib.string_ops")
	local cleaned = StringOps.clean_subtitle(text, true)

	-- Limit colorizer path to primary sub-text or proactive pre-render
	local is_colorizer_path = (is_proactive or name == "sub-text")
		and Observer.config and Observer.config.colorizer_enabled and Observer.yomitan
	if is_colorizer_path then
		if Observer._last_handled_text ~= cleaned then
			Observer._last_handled_text = cleaned
			if not cleaned or cleaned == "" then
				if Observer.handler and Observer.handler.clear_passive then
					Observer.handler:clear_passive()
				end
			else
				Observer.yomitan:tokenize(cleaned, function(tokens)
					-- Match tokens against current screen state or expected proactive text
					local current = mp.get_property("sub-text", "")
					local current_cleaned = StringOps.clean_subtitle(current, true)
					if tokens and (current_cleaned == cleaned or Observer._last_handled_text == cleaned) then
						if Observer.handler and Observer.handler.on_current_tokens_ready then
							Observer.handler:on_current_tokens_ready(tokens)
						end
					end
				end)
			end
		end
	end

	-- Bypass capture timer for proactive updates
	if is_proactive then return end

	-- Deferred capture to allow secondary subtitles to sync and avoid rapid changes
	if Observer.capture_timer then
		Observer.capture_timer:kill()
	end

	Observer.capture_timer = mp.add_timeout(0.2, function()
		local current_text = mp.get_property("sub-text", "")
		if not current_text or current_text == "" then
			return
		end

		local sub_start = mp.get_property_number("sub-start", 0)
		local sub_end = mp.get_property_number("sub-end", 0)
		local sub_delay = mp.get_property_number("sub-delay", 0)

		local secondary_sid = mp.get_property("secondary-sub-text", "")
		local secondary_sub_start = mp.get_property_number("secondary-sub-start", 0)
		local secondary_sub_end = mp.get_property_number("secondary-sub-end", 0)
		local secondary_sub_delay = mp.get_property_number("secondary-sub-delay", 0)

		local sub_data = {
			primary_sid = current_text,
			secondary_sid = secondary_sid,
			start = sub_start,
			["end"] = sub_end,
			delay = sub_delay,
			secondary_start = secondary_sub_start,
			secondary_end = secondary_sub_end,
			secondary_delay = secondary_sub_delay,
		}

		Observer.monitor.add_to_history(sub_data)

		if Observer.monitor.is_appending() then
			Observer.monitor.append_recorded(sub_data)
		end

		if not (Observer.config and Observer.config.pre_tokenize and Observer.yomitan) then
			return
		end

		-- Pre-tokenize based on the stable current text
		local stable_cleaned = StringOps.clean_subtitle(current_text, true)
		if stable_cleaned and stable_cleaned ~= "" then
			Observer.yomitan:tokenize(stable_cleaned, function()
				-- Skip if handled by proactive observer
			end)
		end

		-- Tokenize upcoming subtitles
		local current_pos = mp.get_property_number("time-pos", 0)
		local next_lines = Prefetcher.get_next_lines(current_pos, stable_cleaned, 2)
		for _, line in ipairs(next_lines) do
			local next_cleaned = StringOps.clean_subtitle(line, true)
			if next_cleaned and next_cleaned ~= "" then
				Observer.yomitan:tokenize(next_cleaned, function()
					msg.info("Background prefetch tokenization complete for: " .. next_cleaned)
				end)
			end
		end
	end)
end

function Observer.handle_time_pos(_, time_pos)
	if not Observer.config or not Observer.config.colorizer_enabled or not Observer.active then return end
	if not Prefetcher._ready or not Prefetcher._entries then return end
	if not time_pos then return end

	local sub_delay = mp.get_property_number("sub-delay", 0)
	local fps = mp.get_property_number("container-fps", 24)
	if fps <= 0 then fps = 24 end
	local frame_duration = 1.0 / fps

	-- Look ahead 1 frame to offset OSD render latency
	local lookahead_time = time_pos + frame_duration

	local active_text = ""
	for _, entry in ipairs(Prefetcher._entries) do
		if lookahead_time >= (entry.start_s + sub_delay) and time_pos <= (entry.end_s + sub_delay) then
			active_text = entry.text
			break
		end
	end

	local StringOps = require("lib.string_ops")
	local cleaned = StringOps.clean_subtitle(active_text, true)

	-- Restrict proactive triggers to visible subtitles
	if cleaned == "" then
		local current = mp.get_property("sub-text", "")
		local current_cleaned = StringOps.clean_subtitle(current, true)
		if current_cleaned == "" and Observer._last_handled_text and Observer._last_handled_text ~= "" then
			Observer._last_handled_text = ""
			if Observer.handler and Observer.handler.clear_passive then
				Observer.handler:clear_passive()
			end
		end
	elseif Observer._last_handled_text ~= cleaned then
		Observer.handle_subtitle_change("proactive", active_text, true)
	end
end

-- Start observing subtitle property changes
function Observer.start()
	if Observer.active then
		return
	end

	msg.info("Starting subtitle observer")

	Observer._last_handled_text = nil
	mp.observe_property("sub-text", "string", Observer.handle_subtitle_change)
	mp.observe_property("secondary-sub-text", "string", Observer.handle_subtitle_change)
	mp.observe_property("time-pos", "number", Observer.handle_time_pos)

	Observer.active = true
end

-- Stop observing subtitle property changes
function Observer.stop()
	if not Observer.active then
		return
	end

	mp.unobserve_property(Observer.handle_subtitle_change)
	mp.unobserve_property(Observer.handle_time_pos)
	Observer.active = false
	msg.info("Stopped subtitle observer")
end

return Observer
