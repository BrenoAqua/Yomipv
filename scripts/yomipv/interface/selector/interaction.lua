--[[ Selector interaction logic                                         ]]
--[[ Keyboard navigation, mouse hover tests, and keybinding management. ]]

local mp = require("mp")
local StringOps = require("lib.string_ops")
local Renderer = require("interface.selector.renderer")

local Interaction = {}

local function trigger_lookup_if_enabled(selector, trigger_source)
	local should_trigger
	if trigger_source == "hover" then
		should_trigger = selector.style.lookup_on_hover
	elseif trigger_source == "navigation" then
		should_trigger = selector.style.lookup_on_navigation
	else
		should_trigger = selector.style.lookup_on_navigation
	end

	if not should_trigger or selector.lookup_locked then
		return
	end

	-- Debounce to prevent lookups while moving mouse or navigating rapidly
	if selector.lookup_timer then
		selector.lookup_timer:kill()
	end

	local delay = selector.style.lookup_delay or 0.1
	selector.lookup_timer = mp.add_timeout(delay, function()
		selector.lookup_timer = nil
		selector.pending_initial_hover_lookup = nil
		local state = selector:get_selection_state()
		if state and selector.tokens[selector.index] and selector.tokens[selector.index].is_term then
			local data = {
				term = state.context_text or state.text,
				reading = state.reading,
			}
			if selector.style.on_lookup then
				selector.style.on_lookup(data)
			end
		end
	end)
end

local function hide_if_needed(selector, trigger_source)
	if selector.lookup_locked then
		return
	end

	local will_trigger_lookup = false
	if trigger_source == "hover" then
		will_trigger_lookup = selector.style.lookup_on_hover
	elseif trigger_source == "navigation" then
		will_trigger_lookup = selector.style.lookup_on_navigation
	end

	will_trigger_lookup = will_trigger_lookup
		and selector.tokens[selector.index]
		and selector.tokens[selector.index].is_term

	if selector.style.on_hide then
		local delay = selector.style.lookup_delay or 0.1
		if not will_trigger_lookup or delay > 0 then
			if selector.lookup_timer then
				selector.lookup_timer:kill()
				selector.lookup_timer = nil
			end
			selector.style.on_hide()
		end
	end
end

local function get_term_bounds(selector)
	local first, last = nil, nil
	for i, t in ipairs(selector.tokens) do
		if t.is_term then
			if not first then
				first = i
			end
			last = i
		end
	end
	return first, last
end

local function on_left(selector)
	selector.selection_len = 1

	local first_term_index, last_term_index = get_term_bounds(selector)

	local is_leftmost = false
	if first_term_index and selector.index == first_term_index then
		if selector.style.selector_mora_navigation then
			if not selector.mora_index or selector.mora_index <= 1 then
				is_leftmost = true
			end
		else
			is_leftmost = true
		end
	end

	if is_leftmost and last_term_index then
		selector.index = last_term_index
		if selector.style.selector_mora_navigation then
			local last_token = selector.tokens[last_term_index]
			selector.mora_index = selector.get_char_count(last_token.text)
		else
			selector.mora_index = nil
		end
		if first_term_index ~= last_term_index then
			hide_if_needed(selector, "navigation")
		end
		selector:render()
		trigger_lookup_if_enabled(selector, "navigation")
		return
	end

	if selector.style.selector_mora_navigation and selector.mora_index and selector.mora_index > 1 then
		selector.mora_index = selector.mora_index - 1
		selector:render()
		trigger_lookup_if_enabled(selector, "navigation")
		return
	end

	selector.mora_index = nil
	local old_index = selector.index
	repeat
		selector.index = math.max(1, selector.index - 1)
	until selector.index == 1 or selector.tokens[selector.index].is_term
	if not selector.tokens[selector.index].is_term then
		selector.index = old_index
	end

	if old_index ~= selector.index then
		if selector.style.selector_mora_navigation then
			local new_token = selector.tokens[selector.index]
			selector.mora_index = selector.get_char_count(new_token.text)
		end
		hide_if_needed(selector, "navigation")
	end

	selector:render()
	trigger_lookup_if_enabled(selector, "navigation")
end

local function on_right(selector)
	selector.selection_len = 1

	local first_term_index, last_term_index = get_term_bounds(selector)

	local is_rightmost = false
	if last_term_index and selector.index == last_term_index then
		if selector.style.selector_mora_navigation then
			local token = selector.tokens[selector.index]
			local char_count = selector.get_char_count(token.text)
			local current_mora = selector.mora_index or 1
			if current_mora >= char_count then
				is_rightmost = true
			end
		else
			is_rightmost = true
		end
	end

	if is_rightmost and first_term_index then
		selector.index = first_term_index
		if selector.style.selector_mora_navigation then
			selector.mora_index = 1
		else
			selector.mora_index = nil
		end
		if first_term_index ~= last_term_index then
			hide_if_needed(selector, "navigation")
		end
		selector:render()
		trigger_lookup_if_enabled(selector, "navigation")
		return
	end

	local token = selector.tokens[selector.index]

	if selector.style.selector_mora_navigation then
		local char_count = selector.get_char_count(token.text)
		local current_mora = selector.mora_index or 1
		if current_mora < char_count then
			selector.mora_index = current_mora + 1
			selector:render()
			trigger_lookup_if_enabled(selector, "navigation")
			return
		end
	end

	selector.mora_index = nil
	local old_index = selector.index
	repeat
		selector.index = math.min(#selector.tokens, selector.index + 1)
	until selector.index == #selector.tokens or selector.tokens[selector.index].is_term
	if not selector.tokens[selector.index].is_term then
		selector.index = old_index
	end

	if old_index ~= selector.index then
		if selector.style.selector_mora_navigation then
			selector.mora_index = 1
		end
		hide_if_needed(selector, "navigation")
	end

	selector:render()
	trigger_lookup_if_enabled(selector, "navigation")
end

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

	-- Use first box for up and last for down if word spans lines
	local ref_box = direction == "up" and current_boxes[1] or current_boxes[#current_boxes]
	local ref_x = (ref_box.x1 + ref_box.x2) / 2
	local ref_y = (ref_box.y1 + ref_box.y2) / 2

	local best_index = nil
	local min_y_dist = math.huge
	local min_x_dist = math.huge

	local min_y, max_y = math.huge, -math.huge
	-- 5px buffer prevents false positives from rounding and glyph overlap
	for _, box in ipairs(selector.token_boxes) do
		if selector.tokens[box.index].is_term then
			local by = (box.y1 + box.y2) / 2
			if by < min_y then min_y = by end
			if by > max_y then max_y = by end

			if box.index ~= selector.index then
				local is_in_direction = (direction == "up" and by < ref_y - 5) or (direction == "down" and by > ref_y + 5)
				if is_in_direction then
					local y_dist = math.abs(by - ref_y)
					if y_dist < min_y_dist then
						min_y_dist = y_dist
					end
				end
			end
		end
	end

	local target_y = nil
	local is_wrap = false
	if min_y_dist == math.huge then
		target_y = direction == "up" and (max_y ~= -math.huge and max_y or nil) or (min_y ~= math.huge and min_y or nil)
		is_wrap = true
	end

	-- Pick horizontally closest candidate on nearest line with 20px tolerance
	for _, box in ipairs(selector.token_boxes) do
		if selector.tokens[box.index].is_term and box.index ~= selector.index then
			local bx = (box.x1 + box.x2) / 2
			local by = (box.y1 + box.y2) / 2

			local is_valid_candidate
			if is_wrap then
				is_valid_candidate = target_y and math.abs(by - target_y) < 20
			else
				local is_in_direction = (direction == "up" and by < ref_y - 5) or (direction == "down" and by > ref_y + 5)
				is_valid_candidate = is_in_direction and math.abs(by - ref_y) < min_y_dist + 20
			end

			if is_valid_candidate then
				local x_dist = math.abs(bx - ref_x)
				if x_dist < min_x_dist then
					min_x_dist = x_dist
					best_index = box.index
				end
			end
		end
	end

	return best_index
end

local function on_up(selector)
	selector.selection_len = 1
	local best_candidate = find_vertical_neighbor(selector, "up")
	if best_candidate then
		selector.index = best_candidate
		selector.mora_index = selector.style.selector_mora_navigation and 1 or nil
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
		selector.mora_index = selector.style.selector_mora_navigation and 1 or nil
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
	if not selector.tokens[selector.index] or not selector.tokens[selector.index].is_term then
		return
	end

	-- Kill any pending automatic lookup to prevent double-triggering
	if selector.lookup_timer then
		selector.lookup_timer:kill()
		selector.lookup_timer = nil
	end

	local state = selector:get_selection_state()
	if not state then
		return
	end

	local data = {
		term = state.context_text or state.text,
		reading = state.reading,
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
			local char_index = nil
			if selector.style.selector_mora_hover then
				local token = selector.tokens[entry.index]
				if token and token.is_term then
					local relative_x = mx - entry.x1
					local scaled_font_size = selector.scaled_font_size or selector.style.font_size or 45
					local font_name = selector.style.font_name or ""
					local bold = selector.style.bold ~= nil and selector.style.bold
						or mp.get_property_bool("sub-bold", true)

					local count = 0
					for next_i, _ in selector.utf8_codes(token.text) do
						count = count + 1
						local text_up_to_char = token.text:sub(1, next_i - 1)
						local tw = Renderer.measure_width(text_up_to_char, scaled_font_size, font_name, bold)
						if relative_x <= tw then
							char_index = count
							break
						end
					end
				end
			end

			if selector.index ~= entry.index or selector.mora_index ~= char_index or selector.pending_initial_hover_lookup then
				selector.index = entry.index
				selector.mora_index = char_index
				selector.selection_len = 1
				selector.tail_mora_index = nil
				hide_if_needed(selector, "hover")
				selector:render()
				if not selector.lookup_locked then
					trigger_lookup_if_enabled(selector, "hover")
				end
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
		s:confirm()
	end)
	register(style.key_cancel or "ESC", "selector-cancel", function(s)
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

	register(style.key_selector_lock or "", "selector-persistent-mode", function(s)
		s.persistent_mode = not s.persistent_mode
		if s.style.on_persistent_toggle then
			s.style.on_persistent_toggle(s.persistent_mode)
		end
		s:render()
	end)

	mp.add_forced_key_binding("MOUSE_BTN2", "selector-lock-mouse", function()
		selector.lookup_locked = not selector.lookup_locked
		if selector.lookup_locked then
			selector.locked_index          = selector.index
			selector.locked_mora_index     = selector.mora_index
			selector.locked_selection_len  = selector.selection_len
			selector.locked_tail_mora      = selector.tail_mora_index
		else
			selector.locked_index         = nil
			selector.locked_mora_index    = nil
			selector.locked_selection_len = nil
			selector.locked_tail_mora     = nil
			trigger_lookup_if_enabled(selector, "hover")
		end
		selector:render()
	end)
	table.insert(keys, "selector-lock-mouse")

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
