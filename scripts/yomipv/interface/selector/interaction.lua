--[[ Selector interaction logic                                         ]]
--[[ Keyboard navigation, mouse hover tests, and keybinding management. ]]

local mp = require("mp")
local StringOps = require("lib.string_ops")

local Interaction = {}

-- Trigger lookup based on specific trigger source
local function trigger_lookup_if_enabled(selector, trigger_source)
	local should_trigger = false
	if trigger_source == "hover" then
		should_trigger = selector.style.lookup_on_hover
	elseif trigger_source == "navigation" then
		should_trigger = selector.style.lookup_on_navigation
	else
		-- Trigger initial lookup if either option is enabled
		should_trigger = selector.style.lookup_on_navigation or selector.style.lookup_on_hover
	end

	if should_trigger and selector.tokens[selector.index] and selector.tokens[selector.index].is_term then
		local token = selector.tokens[selector.index]
		local data = {
			term = token.text,
			reading = token.reading or (token.headwords and token.headwords[1] and token.headwords[1].reading),
		}
		if selector.style.on_lookup then
			selector.style.on_lookup(data)
		end
	end
end

-- Hide lookup unless about to trigger it (prevents race condition)
local function hide_if_needed(selector, trigger_source)
	local will_trigger_lookup = false
	if trigger_source == "hover" then
		will_trigger_lookup = selector.style.lookup_on_hover
	elseif trigger_source == "navigation" then
		will_trigger_lookup = selector.style.lookup_on_navigation
	end

	will_trigger_lookup = will_trigger_lookup
		and selector.tokens[selector.index]
		and selector.tokens[selector.index].is_term

	if selector.style.on_hide and not will_trigger_lookup then
		selector.style.on_hide()
	end
end

local function on_left(selector)
	selector.selection_len = 1
	local old_index = selector.index
	repeat
		selector.index = math.max(1, selector.index - 1)
	until selector.index == 1 or selector.tokens[selector.index].is_term
	if not selector.tokens[selector.index].is_term then
		selector.index = old_index
	end

	if old_index ~= selector.index then
		hide_if_needed(selector, "navigation")
	end

	selector:render()
	trigger_lookup_if_enabled(selector, "navigation")
end

local function on_right(selector)
	selector.selection_len = 1
	local old_index = selector.index
	repeat
		selector.index = math.min(#selector.tokens, selector.index + 1)
	until selector.index == #selector.tokens or selector.tokens[selector.index].is_term
	if not selector.tokens[selector.index].is_term then
		selector.index = old_index
	end

	if old_index ~= selector.index then
		hide_if_needed(selector, "navigation")
	end

	selector:render()
	trigger_lookup_if_enabled(selector, "navigation")
end

-- Find best candidate for vertical navigation (up/down)
local function find_vertical_neighbor(selector, direction)
	local current_boxes = {}
	for _, box in ipairs(selector.token_boxes) do
		if box.index == selector.index then
			table.insert(current_boxes, box)
		end
	end
	if #current_boxes == 0 then
		return nil
	end

	-- Use first box for UP and last for DOWN if word spans lines
	local ref_box = direction == "up" and current_boxes[1] or current_boxes[#current_boxes]
	local ref_x = (ref_box.x1 + ref_box.x2) / 2
	local ref_y = (ref_box.y1 + ref_box.y2) / 2

	local best_index = nil
	local min_y_dist = math.huge
	local min_x_dist = math.huge

	-- Heuristic: find boxes clearly above or below
	-- 5px buffer to handle small overlaps or rounding
	for _, box in ipairs(selector.token_boxes) do
		if not selector.tokens[box.index].is_term or box.index == selector.index then
			goto continue
		end

		local by = (box.y1 + box.y2) / 2

		local is_in_direction = (direction == "up" and by < ref_y - 5) or (direction == "down" and by > ref_y + 5)

		if is_in_direction then
			local y_dist = math.abs(by - ref_y)
			if y_dist < min_y_dist then
				min_y_dist = y_dist
			end
		end
		::continue::
	end

	if min_y_dist == math.huge then
		return nil
	end

	-- Pick horizontally closest candidate on nearest line (within 20px tolerance)
	for _, box in ipairs(selector.token_boxes) do
		if not selector.tokens[box.index].is_term or box.index == selector.index then
			goto continue
		end

		local bx = (box.x1 + box.x2) / 2
		local by = (box.y1 + box.y2) / 2

		local is_in_direction = (direction == "up" and by < ref_y - 5) or (direction == "down" and by > ref_y + 5)

		if is_in_direction then
			local y_dist = math.abs(by - ref_y)
			if y_dist < min_y_dist + 20 then
				local x_dist = math.abs(bx - ref_x)
				if x_dist < min_x_dist then
					min_x_dist = x_dist
					best_index = box.index
				end
			end
		end
		::continue::
	end

	return best_index
end

local function on_up(selector)
	selector.selection_len = 1
	local best_candidate = find_vertical_neighbor(selector, "up")
	if best_candidate then
		selector.index = best_candidate
		hide_if_needed(selector, "navigation")
		selector:render()
		trigger_lookup_if_enabled(selector, "navigation")
	end
end

local function on_down(selector)
	selector.selection_len = 1
	local best_candidate = find_vertical_neighbor(selector, "down")
	if best_candidate then
		selector.index = best_candidate
		hide_if_needed(selector, "navigation")
		selector:render()
		trigger_lookup_if_enabled(selector, "navigation")
	end
end

local function on_click(selector)
	local mx, my = mp.get_mouse_pos()
	local hit = false
	for _, entry in ipairs(selector.token_boxes) do
		if mx >= entry.x1 and mx <= entry.x2 and my >= entry.y1 and my <= entry.y2 then
			selector.index = entry.index
			if selector.style.on_hide then
				selector.style.on_hide()
			end
			selector:confirm()
			hit = true
			break
		end
	end

	if not hit and selector.style.on_click_fallback then
		selector.style.on_click_fallback()
	end
end

local function on_lookup(selector)
	local token = selector.tokens[selector.index]
	if not token or not token.is_term then
		return
	end

	local combined_text = ""
	if selector.selection_len == 1 then
		combined_text = token.text
	else
		for i = 0, selector.selection_len - 1 do
			if selector.tokens[selector.index + i] then
				combined_text = combined_text .. selector.tokens[selector.index + i].text
			end
		end
	end

	local data = {
		term = combined_text,
		reading = token.reading or (token.headwords and token.headwords[1] and token.headwords[1].reading),
	}

	if selector.style.on_lookup then
		selector.style.on_lookup(data)
	end
end

function Interaction.check_hover(selector)
	if not selector.active then
		return
	end
	local mx, my = mp.get_mouse_pos()
	if mx == selector.last_mouse_x and my == selector.last_mouse_y then
		return
	end
	selector.last_mouse_x, selector.last_mouse_y = mx, my

	local hit = false
	for _, entry in ipairs(selector.token_boxes) do
		if mx >= entry.x1 and mx <= entry.x2 and my >= entry.y1 and my <= entry.y2 then
			if selector.index ~= entry.index then
				selector.index = entry.index
				hide_if_needed(selector, "hover")
				selector:render()
				trigger_lookup_if_enabled(selector, "hover")
			end
			hit = true
			break
		end
	end

	if not hit then
		if selector.style.on_hover_fallback then
			selector.style.on_hover_fallback()
		end
	end
end

function Interaction.bind(selector)
	local style = selector.style
	local keys = {}

	local last_action_time = 0
	local function register(key_str, name, callback, flags)
		if not key_str or key_str == "" then
			return
		end
		for key in key_str:gmatch("([^,]+)") do
			local binding_name = name .. "-" .. key
			mp.add_forced_key_binding(StringOps.trim(key), binding_name, function()
				if flags == "repeatable" then
					local now = mp.get_time()
					local delay = selector.style.navigation_delay or 0.05
					if now - last_action_time < delay then
						return
					end
					last_action_time = now
				end
				callback(selector)
			end, flags)
			table.insert(keys, binding_name)
		end
	end

	register(style.key_left or "LEFT", "selector-left", on_left, "repeatable")
	register(style.key_right or "RIGHT", "selector-right", on_right, "repeatable")
	register(style.key_up or "UP", "selector-up", on_up, "repeatable")
	register(style.key_down or "DOWN", "selector-down", on_down, "repeatable")
	register(style.key_confirm or "ENTER,c", "selector-confirm", function(s)
		if s.style.on_hide then
			s.style.on_hide()
		end
		s:confirm()
	end)
	register(style.key_cancel or "ESC", "selector-cancel", function(s)
		if s.style.on_hide then
			s.style.on_hide()
		end
		s:cancel()
	end)
	register(style.key_lookup or "d", "selector-lookup", on_lookup)

	register(style.key_expand_prev or "Shift+LEFT", "selector-expand-prev", function(s)
		if s.style.on_expand_prev then
			s.style.on_expand_prev()
		end
	end, "repeatable")
	register(style.key_expand_next or "Shift+RIGHT", "selector-expand-next", function(s)
		if s.style.on_expand_next then
			s.style.on_expand_next()
		end
	end, "repeatable")

	register("Ctrl+RIGHT", "selector-selection-next", function(s)
		if s.index + s.selection_len <= #s.tokens then
			s.selection_len = s.selection_len + 1
			s:render()
		end
	end, "repeatable")
	register("Ctrl+LEFT", "selector-selection-prev", function(s)
		if s.index > 1 then
			s.index = s.index - 1
			s.selection_len = s.selection_len + 1
			s:render()
		end
	end, "repeatable")

	register(style.key_split or "s", "selector-split", function(s)
		s:split()
	end)

	-- Mouse bindings
	mp.add_forced_key_binding("MOUSE_BTN2", "selector-split-mouse", function()
		selector:split()
	end)
	table.insert(keys, "selector-split-mouse")

	mp.add_forced_key_binding("MBTN_LEFT", "selector-click", function()
		on_click(selector)
	end)
	table.insert(keys, "selector-click")

	selector.registered_keys = keys
end

function Interaction.unbind(selector)
	if selector.registered_keys then
		for _, name in ipairs(selector.registered_keys) do
			mp.remove_key_binding(name)
		end
		selector.registered_keys = {}
	end
end

function Interaction.trigger_initial_lookup(selector)
	trigger_lookup_if_enabled(selector)
end

return Interaction
