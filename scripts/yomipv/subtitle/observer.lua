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

	-- Load the prefetcher whenever a new file starts
	mp.register_event("file-loaded", function()
		if config.pre_tokenize then
			Prefetcher.load()
		end
	end)
end

-- Shared handler for subtitle changes
function Observer.handle_subtitle_change(name, value)
	local text = value or ""
	local StringOps = require("lib.string_ops")
	local cleaned = StringOps.clean_subtitle(text, true)

	-- Immediate display update for colorizer mode
	if Observer.config and Observer.config.colorizer_enabled and Observer.yomitan and name == "sub-text" then
		if not cleaned or cleaned == "" then
			if Observer.handler and Observer.handler.clear_passive then
				Observer.handler:clear_passive()
			end
		else
			Observer.yomitan:tokenize(cleaned, function(tokens)
				-- Ensure this result still matches what's on screen
				local current = mp.get_property("sub-text", "")
				if tokens and current ~= "" and StringOps.clean_subtitle(current, true) == cleaned then
					if Observer.handler and Observer.handler.on_current_tokens_ready then
						Observer.handler:on_current_tokens_ready(tokens)
					end
				end
			end)
		end
	end

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
		local secondary_sid = mp.get_property("secondary-sub-text", "")
		local secondary_sub_start = mp.get_property_number("secondary-sub-start", 0)
		local secondary_sub_end = mp.get_property_number("secondary-sub-end", 0)

		local sub_data = {
			primary_sid = current_text,
			secondary_sid = secondary_sid,
			start = sub_start,
			["end"] = sub_end,
			secondary_start = secondary_sub_start,
			secondary_end = secondary_sub_end,
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
				-- Already handled by immediate update if colorizer is on
			end)
		end

		-- Tokenize upcoming subtitles
		local current_pos = mp.get_property_number("time-pos", 0)
		local next_lines = Prefetcher.get_next_lines(current_pos, current_text, 2)
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

-- Start observing subtitle property changes
function Observer.start()
	if Observer.active then
		return
	end

	msg.info("Starting subtitle observer")

	mp.observe_property("sub-text", "string", Observer.handle_subtitle_change)
	mp.observe_property("secondary-sub-text", "string", Observer.handle_subtitle_change)

	Observer.active = true
end

-- Stop observing subtitle property changes
function Observer.stop()
	if not Observer.active then
		return
	end

	mp.unobserve_property(Observer.handle_subtitle_change)
	Observer.active = false
	msg.info("Stopped subtitle observer")
end

return Observer
