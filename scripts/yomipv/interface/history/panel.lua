--[[ Subtitle history panel                             ]]
--[[ History data management and Electron frontend sync ]]

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")
local Monitor = require("capture.monitor")
local Player = require("lib.player")
local StringOps = require("lib.string_ops")
local Curl = require("lib.curl")

local History = {
	active = false,
	keybindings = {},
	config = nil,
	exporter_handler = nil,
	_registered_hooks = false
}

function History:new(o)
	local obj = o or {}
	setmetatable(obj, self)
	self.__index = self
	return obj
end

function History:init(config)
	self.config = config
	mp.observe_property("focused", "bool", function(_, is_focused)
		if self.active then
			if is_focused then
				Curl.post("http://127.0.0.1:19634/history-show", "{}", function() end)
			else
				Curl.post("http://127.0.0.1:19634/history-hide", "{}", function() end)
			end
		end
	end)
end

function History:set_exporter_handler(handler)
	self.exporter_handler = handler
end

function History:wrap_handler(callback, ...)
	local args = { ... }
	return function()
		local ok, err = pcall(callback, unpack(args))
		if not ok then
			msg.error("History UI Error: " .. tostring(err))
		end
		self:update()
	end
end

function History:clear_history()
	Monitor.clear_history()
	Player.notify("History cleared", "info", 2)
	self:update()
end

function History:update(force)
	if self.active == false then
		return
	end

	-- Extract state to push to the web view
	local entries = Monitor.is_appending() and Monitor.recorded_subs() or Monitor.get_history()

	local current_count = #entries
	local current_can_expand = (self.exporter_handler
		and self.exporter_handler.expand_to_subtitle ~= nil) and true or false
	local current_sig = ""
	for i = math.max(1, current_count - 5), current_count do
		local e = entries[i]
		if e then current_sig = current_sig .. (e.primary_sid or "") .. (e.secondary_sid or "") end
	end
	if not force
		and self._last_count == current_count
		and self._last_appending == Monitor.is_appending()
		and self._last_can_expand == current_can_expand
		and self._last_sig == current_sig
	then
		return
	end
	self._last_count = current_count
	self._last_appending = Monitor.is_appending()
	self._last_can_expand = current_can_expand
	self._last_sig = current_sig

	-- Pass only the config fields needed for rendering
	local safe_config = {}
	if self.config then
		safe_config.picture_animated = self.config.picture_animated
		safe_config.history_accent_color = self.config.history_accent_color
		safe_config.history_show_secondary = self.config.history_show_secondary
	end

	local payload = {
		is_appending = Monitor.is_appending(),
		can_expand = current_can_expand,
		entries = entries,
		config = safe_config
	}

	local payload_json = utils.format_json(payload)

	Curl.post("http://127.0.0.1:19634/history", payload_json, function() end)
end

function History:_register_ipc_hooks()
	if self._registered_hooks then return end
	self._registered_hooks = true

	mp.register_script_message("yomipv-history-jump", function(time_str)
		local time = tonumber(time_str)
		if time and time >= 0 then
			local current_delay = mp.get_property_number("sub-delay") or 0
			mp.set_property_number("time-pos", time + current_delay)
			Player.notify("Jumped to " .. StringOps.format_duration(time + current_delay, true))
		end
	end)

	mp.register_script_message("yomipv-history-expand", function(entry_json)
		if self.exporter_handler and self.exporter_handler.expand_to_subtitle then
			local entry = utils.parse_json(entry_json)
			if entry then
				self.exporter_handler:expand_to_subtitle(entry)
			end
		end
	end)

	mp.register_script_message("yomipv-history-clear", function()
		self:clear_history()
	end)

	mp.register_script_message("yomipv-history-toggle-anim", function()
		if self.config then
			self.config.picture_animated = not self.config.picture_animated
			self.config.save("picture_animated", self.config.picture_animated)
			local status = self.config.picture_animated and "Enabled" or "Disabled"
			Player.notify("Animated pictures: " .. status, "info")
			self:update(true)
		end
	end)
end

function History:open(request_state)
	self:_register_ipc_hooks()

	if self.active == true and request_state ~= "open" then
		self:close()
		return
	end

	if self.active == true and request_state == "open" then
		self:update(true)
		return
	end

	for _, val in pairs(self.keybindings) do
		mp.add_forced_key_binding(val.key, val.key, val.fn)
	end

	mp.add_forced_key_binding(self.config.key_history_clear, "menu-clear-history", function()
		self:clear_history()
	end)

	mp.add_forced_key_binding("ctrl+c", "menu-copy", function()
		Curl.post("http://127.0.0.1:19634/copy", "{}", function() end)
	end)

	self.active = true

	Curl.post("http://127.0.0.1:19634/history-show", "{}", function() end)

	self._sub_observer = function()
		if self.active then
			self:update()
			mp.add_timeout(0.05, function()
				if self.active then
					self:update()
				end
			end)
		end
	end
	mp.observe_property("sub-text", "string", self._sub_observer)

	self._update_timer = mp.add_periodic_timer(0.05, function()
		if self.active then
			self:update()
		end
	end)

	self:update(true)

	if self.config and self.config.history_hide_volume then
		mp.commandv("script-message-to", "uosc", "disable-elements", "yomipv_history", "volume")
	end
end

function History:close()
	if self.active == false then
		return
	end
	for _, val in pairs(self.keybindings) do
		mp.remove_key_binding(val.key)
	end
	mp.remove_key_binding("menu-clear-history")
	mp.remove_key_binding("menu-copy")
	if self._sub_observer then
		mp.unobserve_property(self._sub_observer)
		self._sub_observer = nil
	end
	if self._update_timer then
		self._update_timer:kill()
		self._update_timer = nil
	end

	Curl.post("http://127.0.0.1:19634/history-hide", "{}", function() end)

	self.active = false

	if self.config and self.config.history_hide_volume then
		mp.commandv("script-message-to", "uosc", "disable-elements", "yomipv_history", "")
	end
end

return History
