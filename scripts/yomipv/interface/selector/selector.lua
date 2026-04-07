--[[ Interactive word selector ]]

local mp = require("mp")
local StringOps = require("lib.string_ops")
local Renderer = require("interface.selector.renderer")
local Interaction = require("interface.selector.interaction")

local Selector = {
	tokens = {},
	index = 1,
	callback = nil,
	active = false,
	should_resume = false,
	token_boxes = {},
	input_timer = nil,
	last_mouse_x = -1,
	last_mouse_y = -1,
	style = {},
	ui_hidden_by_us = false,
	registered_keys = {},
	selection_len = 1,
	sub_visibility_before = "yes",
	lookup_locked = false,
	locked_index = nil,
	locked_mora_index = nil,
	passive = false,
	persistent_mode = false,
}

function Selector.utf8_codes(str)
	return StringOps.utf8_codes(str)
end

function Selector.get_mora_byte_pos(text, mora_index)
	return StringOps.get_char_byte_pos(text, mora_index)
end

function Selector.get_char_count(text)
	return StringOps.get_char_count(text)
end

function Selector:get_selection_state()
	local token = self.tokens[self.index]
	if not token then
		return nil
	end

	local text = ""
	local offset = token.offset
	local headwords = token.headwords
	local reading = token.reading or (token.headwords and token.headwords[1] and token.headwords[1].reading)

	for i = 0, self.selection_len - 1 do
		local t = self.tokens[self.index + i]
		if t then
			local tk_text = t.text
			if i == 0 and self.mora_index and self.mora_index > 1 then
				local byte_pos = Selector.get_mora_byte_pos(tk_text, self.mora_index)
				local skipped_text = tk_text:sub(1, byte_pos - 1)
				tk_text = tk_text:sub(byte_pos)
				offset = offset + Selector.get_char_count(skipped_text)
			end
			text = text .. tk_text
		end
	end

	local context_text = text
	local ctx_count = 0
	if self.selection_len == 1 then
		for i = 1, #self.tokens - self.index do
			local t = self.tokens[self.index + i]
			if t then
				context_text = context_text .. t.text
				ctx_count = ctx_count + Selector.get_char_count(t.text)
				if ctx_count > 15 then
					break
				end
			end
		end
	end

	return {
		text = text,
		context_text = context_text,
		offset = offset,
		headwords = headwords,
		reading = reading,
	}
end

local function render_cb()
	Selector:render()
end

function Selector:render()
	Renderer.render(self)
end

function Selector:update_style(style)
	self.style = style or {}
	self:render()
end

function Selector:clear()
	self.active = false
	self.passive = false
	if self.input_timer then
		self.input_timer:kill()
		self.input_timer = nil
	end
	mp.unobserve_property("osd-width", "native", render_cb)
	mp.unobserve_property("osd-height", "native", render_cb)
	if self.lookup_timer then
		self.lookup_timer:kill()
		self.lookup_timer = nil
	end
	mp.set_osd_ass(0, 0, "")

	if self.sub_visibility_before then
		mp.set_property("sub-visibility", self.sub_visibility_before)
		self.sub_visibility_before = nil
	end

	self.lookup_locked = false
	self.locked_index = nil
	self.locked_mora_index = nil

	Interaction.unbind(self)

	if self.ui_hidden_by_us then
		mp.commandv("script-message-to", "uosc", "disable-elements", "yomipv", "")
		self.ui_hidden_by_us = false
	end
	if self.should_resume then
		mp.set_property_native("pause", false)
		self.should_resume = false
	end

	if self.style.on_hide then
		self.style.on_hide()
	end
end

function Selector:display_passive(tokens, style)
	if self.active then
		return
	end
	self.passive = true
	self.tokens = tokens
	self.style = style or {}
	self:render()
end

function Selector:clear_passive()
	if self.active or not self.passive then
		return
	end
	self.passive = false
	mp.set_osd_ass(0, 0, "")
end

function Selector:expand_selection_to_match(expression, reading)
	if not self.active then
		return
	end

	local expr_no_space = expression and expression:gsub("[%s%p]", "") or ""
	local read_no_space = reading and reading:gsub("[%s%p]", "") or ""

	if expr_no_space == "" and read_no_space == "" then
		return
	end

	local combined_text = ""
	local combined_char_len = 0
	local match_len = 0
	local tail_mora = nil

	local expr_len = StringOps.get_char_count(expr_no_space)
	local read_len = StringOps.get_char_count(read_no_space)

	-- Use the locked index as the anchor when locked, otherwise use the current index
	local base_index = (self.lookup_locked and self.locked_index) or self.index
	local base_mora = (self.lookup_locked and self.locked_mora_index) or self.mora_index

	for i = 0, #self.tokens - base_index do
		local t = self.tokens[base_index + i]
		if t then
			local tk_text = t.text
			if i == 0 and base_mora and base_mora > 1 then
				local byte_pos = StringOps.get_char_byte_pos(tk_text, base_mora)
				tk_text = tk_text:sub(byte_pos)
			end

			local prev_char_len = combined_char_len
			combined_text = combined_text .. tk_text
			local check_text = combined_text:gsub("[%s%p]", "")
			combined_char_len = StringOps.get_char_count(check_text)

			local shared_expr = StringOps.count_shared_prefix(check_text, expr_no_space)
			local shared_read = StringOps.count_shared_prefix(check_text, read_no_space)

			if (shared_expr == expr_len and combined_char_len == expr_len) or
			   (shared_read == read_len and combined_char_len == read_len) then
				match_len = i + 1
				tail_mora = nil
				break
			end

			-- Entry is a subset of accumulated tokens
			if (expr_len > 0 and shared_expr == expr_len) then
				match_len = i + 1
				tail_mora = expr_len - prev_char_len
				break
			elseif (read_len > 0 and shared_read == read_len) then
				match_len = i + 1
				tail_mora = read_len - prev_char_len
				break
			end

			-- Conjugation fallback: match all but final character
			if combined_char_len >= expr_len and (
			   (read_len >= 2 and shared_read >= read_len - 1) or
			   (expr_len >= 2 and shared_expr >= expr_len - 1)) then
				match_len = i + 1
				tail_mora = nil
				break
			end

			if combined_char_len > expr_len and combined_char_len > read_len then
				break
			end
		end
	end

	if match_len > 0 then
		-- Update current visual selection
		self.index = base_index
		self.mora_index = base_mora
		self.selection_len = match_len
		self.tail_mora_index = tail_mora

		-- Synchronize with locked state if active so export reflects manual UI navigation
		if self.lookup_locked then
			self.locked_index = base_index
			self.locked_mora_index = base_mora
			self.locked_selection_len = match_len
			self.locked_tail_mora = tail_mora
		end

		self:render()
	end
end

function Selector:confirm()
	-- Use the locked selection snapshot so drifting the mouse doesn't affect the card
	local saved_index     = self.index
	local saved_mora      = self.mora_index
	local saved_sel_len   = self.selection_len
	local saved_tail_mora = self.tail_mora_index
	if self.lookup_locked and self.locked_index then
		self.index          = self.locked_index
		self.mora_index     = self.locked_mora_index
		self.selection_len  = self.locked_selection_len or self.selection_len
		self.tail_mora_index = self.locked_tail_mora
	end
	local state = self:get_selection_state()
	self.index          = saved_index
	self.mora_index     = saved_mora
	self.selection_len  = saved_sel_len
	self.tail_mora_index = saved_tail_mora
	if not state then
		return
	end

	local token = {
		text = state.text,
		headwords = state.headwords,
		offset = state.offset,
		is_term = true,
	}

	if self.persistent_mode then
		-- Export without closing, then reset to single-word selection for the next pick
		token.keep_open = true
		self.selection_len = 1
		self.tail_mora_index = nil
		self:render()
		self.callback(token)
	else
		local cb = self.callback
		self:clear()
		cb(token)
	end
end

function Selector:cancel()
	self:clear()
	if self.callback then
		self.callback(nil)
	end
end

function Selector:prepend_tokens(new_tokens, offset_shift)
	for i = #new_tokens, 1, -1 do
		table.insert(self.tokens, 1, new_tokens[i])
	end
	self.index = self.index + #new_tokens

	if offset_shift then
		for i = #new_tokens + 1, #self.tokens do
			if self.tokens[i].offset then
				self.tokens[i].offset = self.tokens[i].offset + offset_shift
			end
		end
	end
	self:render()
end

function Selector:append_tokens(new_tokens)
	for _, token in ipairs(new_tokens) do
		table.insert(self.tokens, token)
	end
	self:render()
end

function Selector:start(tokens, callback, style)
	if self.active then
		return
	end
	self.passive = false
	self.active = true
	self.tokens = tokens
	self.style = style or {}
	self.index = 1
	self.selection_len = 1
	self.lookup_timer = nil
	self.pending_initial_hover_lookup = true
	self.lookup_locked = false
	self.locked_index = nil
	self.locked_mora_index = nil
	for i, token in ipairs(tokens) do
		if token.is_term then
			self.index = i
			break
		end
	end
	self.callback = callback

	self.sub_visibility_before = mp.get_property("sub-visibility", "yes")
	mp.set_property("sub-visibility", "no")

	if style.should_pause ~= false then
		if not mp.get_property_native("pause") then
			mp.set_property_native("pause", true)
			self.should_resume = true
		else
			self.should_resume = style.should_resume == true
		end
	else
		self.should_resume = style.should_resume == true
	end

	if style.hide_ui then
		mp.commandv(
			"script-message-to",
			"uosc",
			"disable-elements",
			"yomipv",
			"timeline,controls,volume,top_bar,idle_indicator,audio_indicator,buffering_indicator,pause_indicator"
		)
		self.ui_hidden_by_us = true
	end

	Interaction.bind(self)

	mp.observe_property("osd-width", "native", render_cb)
	mp.observe_property("osd-height", "native", render_cb)

	self:render()
	self.input_timer = mp.add_periodic_timer(0.04, function()
		Interaction.check_hover(self)
	end)

	Interaction.trigger_initial_lookup(self)
end

return Selector
