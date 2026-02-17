--[[ Interactive word selector                     ]]
--[[ Selection flow and token split orchestration. ]]

local mp = require("mp")
local msg = require("mp.msg")
local Renderer = require("interface.selector.renderer")
local Interaction = require("interface.selector.interaction")

local Selector = {
	tokens = {},
	index = 1,
	callback = nil,
	active = false,
	should_resume = false,
	-- Layout and Interaction state
	token_boxes = {}, -- Stored OSD space coordinates {x1, y1, x2, y2}
	input_timer = nil,
	last_mouse_x = -1,
	last_mouse_y = -1,
	style = {},
	ui_hidden_by_us = false,
	registered_keys = {}, -- Binding track for cleanup
	split_history = {}, -- Undo stack
	selection_len = 1,
}

-- UTF-8 Iterator polyfill
local function utf8_iter(s, i)
	if not s then
		return nil
	end
	i = i or 1
	if i > #s then
		return nil
	end
	local c = string.byte(s, i)
	local code
	local next_i
	if c < 128 then
		code = c
		next_i = i + 1
	elseif c >= 194 and c <= 223 then
		local c2 = string.byte(s, (i + 1)) or 0
		code = ((c - 192) * 64) + (c2 - 128)
		next_i = i + 2
	elseif c >= 224 and c <= 239 then
		local c2 = string.byte(s, (i + 1)) or 0
		local c3 = string.byte(s, (i + 2)) or 0
		code = ((c - 224) * 4096) + ((c2 - 128) * 64) + (c3 - 128)
		next_i = i + 3
	elseif c >= 240 and c <= 244 then
		local c2 = string.byte(s, (i + 1)) or 0
		local c3 = string.byte(s, (i + 2)) or 0
		local c4 = string.byte(s, (i + 3)) or 0
		code = ((c - 240) * 262144) + ((c2 - 128) * 4096) + ((c3 - 128) * 64) + (c4 - 128)
		next_i = i + 4
	else
		code = c
		next_i = i + 1
	end
	return next_i, code
end

local function utf8_codes(str)
	return utf8_iter, str, 1
end

-- Split text into individual UTF-8 characters
local function split_into_characters(text)
	local chars = {}
	local i = 1
	for next_i, _ in utf8_codes(text) do
		local char = text:sub(i, next_i - 1)
		if char ~= "" then
			table.insert(chars, {
				text = char,
				headwords = nil,
				offset = 0, -- Recalculated during insertion
				is_term = true, -- All characters are selectable
			})
		end
		i = next_i
	end
	return chars
end

local function render_cb()
	Selector:render()
end

function Selector:render()
	Renderer.render(self)
end

function Selector:clear()
	self.active = false
	if self.input_timer then
		self.input_timer:kill()
		self.input_timer = nil
	end
	mp.unobserve_property(render_cb)
	mp.set_osd_ass(0, 0, "")
	mp.set_property("sub-visibility", "yes")

	Interaction.unbind(self)

	if self.ui_hidden_by_us then
		mp.commandv("script-message-to", "uosc", "disable-elements", "yomipv", "")
		self.ui_hidden_by_us = false
	end
	if self.should_resume then
		mp.set_property_native("pause", false)
		self.should_resume = false
	end
end

function Selector:confirm()
	local combined_text = ""
	local headwords = nil
	-- Extract headwords and combined text from range
	if self.selection_len == 1 then
		combined_text = self.tokens[self.index].text
		headwords = self.tokens[self.index].headwords
	else
		for i = 0, self.selection_len - 1 do
			if self.tokens[self.index + i] then
				combined_text = combined_text .. self.tokens[self.index + i].text
			end
		end
	end

	local token = {
		text = combined_text,
		headwords = headwords,
		offset = self.tokens[self.index].offset, -- Start offset tracking
		is_term = true,
	}

	local cb = self.callback
	self:clear()
	cb(token)
end

function Selector:cancel()
	-- Revert to previous split state if history exists
	if self.split_history and #self.split_history > 0 then
		local history_entry = table.remove(self.split_history)
		self.tokens = history_entry.tokens
		self.index = history_entry.index
		msg.info("Undo split: restored previous state")
		self:render()
	else
		-- Terminate selector session
		self:clear()
		if self.callback then
			self.callback(nil)
		end
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

function Selector:split()
	if not self.active or not self.tokens or #self.tokens == 0 then
		return
	end

	local current_token = self.tokens[self.index]
	if not current_token then
		return
	end

	local split_level = current_token.split_level or 0

	-- Save history for split
	local history_entry = {
		tokens = {},
		index = self.index,
	}
	for i, token in ipairs(self.tokens) do
		history_entry.tokens[i] = {
			text = token.text,
			headwords = token.headwords,
			offset = token.offset,
			is_term = token.is_term,
			split_level = token.split_level,
		}
	end
	table.insert(self.split_history, history_entry)

	if split_level == 0 then
		-- Retokenize with scanLength=1 via Yomitan API
		msg.info("Splitting token with Yomitan (scanLength=1): " .. current_token.text)

		-- Require Yomitan module
		if not self.style.yomitan then
			msg.warn("Yomitan module not available for splitting")
			-- Character split fallback
			local char_tokens = split_into_characters(current_token.text)
			for _, t in ipairs(char_tokens) do
				t.split_level = 2
			end

			-- Replace token with chars
			local new_tokens = {}
			for i = 1, self.index - 1 do
				table.insert(new_tokens, self.tokens[i])
			end
			for _, t in ipairs(char_tokens) do
				table.insert(new_tokens, t)
			end
			for i = self.index + 1, #self.tokens do
				table.insert(new_tokens, self.tokens[i])
			end

			self.tokens = new_tokens
			self:render()
			return
		end

		self.style.yomitan:tokenize_with_scan_length(current_token.text, 1, function(new_tokens, error)
			if error or not new_tokens or #new_tokens == 0 then
				msg.warn("Yomitan failed, fallback to char split: " .. tostring(error))
				-- Character split fallback on failure
				local char_tokens = split_into_characters(current_token.text)
				for _, t in ipairs(char_tokens) do
					t.split_level = 2
				end

				-- Replace current token
				local result_tokens = {}
				for i = 1, self.index - 1 do
					table.insert(result_tokens, self.tokens[i])
				end
				for _, t in ipairs(char_tokens) do
					table.insert(result_tokens, t)
				end
				for i = self.index + 1, #self.tokens do
					table.insert(result_tokens, self.tokens[i])
				end

				self.tokens = result_tokens
				self:render()
				return
			end

			-- Tag new tokens for tracking depth
			for _, t in ipairs(new_tokens) do
				t.split_level = 1
			end

			-- Replace target token with split results
			local result_tokens = {}
			for i = 1, self.index - 1 do
				table.insert(result_tokens, self.tokens[i])
			end
			for _, t in ipairs(new_tokens) do
				table.insert(result_tokens, t)
			end
			for i = self.index + 1, #self.tokens do
				table.insert(result_tokens, self.tokens[i])
			end

			self.tokens = result_tokens
			msg.info("Split complete: " .. #new_tokens .. " new tokens")
			self:render()
		end)
	elseif split_level == 1 then
		-- Individual character split depth
		msg.info("Splitting token into characters: " .. current_token.text)
		local char_tokens = split_into_characters(current_token.text)

		if #char_tokens <= 1 then
			msg.info("Token is already a single character, cannot split further")
			-- Discard redundant history entry
			table.remove(self.split_history)
			return
		end

		for _, t in ipairs(char_tokens) do
			t.split_level = 2
		end

		-- Character insertion for split range
		local new_tokens = {}
		for i = 1, self.index - 1 do
			table.insert(new_tokens, self.tokens[i])
		end
		for _, t in ipairs(char_tokens) do
			table.insert(new_tokens, t)
		end
		for i = self.index + 1, #self.tokens do
			table.insert(new_tokens, self.tokens[i])
		end

		self.tokens = new_tokens
		msg.info("Character split complete: " .. #char_tokens .. " characters")
		self:render()
	else
		-- Tokens at char level
		msg.info("Token already at character level, cannot split further")
		-- Discard redundant history entry
		table.remove(self.split_history)
	end
end

function Selector:start(tokens, callback, style)
	if self.active then
		return
	end
	self.active = true
	self.tokens = tokens
	self.style = style or {}
	self.index = 1
	self.selection_len = 1
	self.split_history = {}
	for i, token in ipairs(tokens) do
		if token.is_term then
			self.index = i
			break
		end
	end
	self.callback = callback

	mp.set_property("sub-visibility", "no")

	-- Interface pause logic
	if style.should_pause ~= false then
		if not mp.get_property_native("pause") then
			mp.set_property_native("pause", true)
			self.should_resume = true
		else
			-- Apply resume override if requested
			self.should_resume = style.should_resume == true
		end
	else
		-- Direct override from style
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

	-- Trigger initial lookup if auto-lookup is enabled
	Interaction.trigger_initial_lookup(self)
end

return Selector
