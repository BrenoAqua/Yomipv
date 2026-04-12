--[[ Subtitle history panel                                              ]]
--[[ Side-panel display and interaction management for subtitle history. ]]

local mp = require("mp")
local msg = require("mp.msg")
local Display = require("lib.display")
local StringOps = require("lib.string_ops")
local Monitor = require("capture.monitor")
local Player = require("lib.player")
local Renderer = require("interface.history.renderer")

local History = {
	active = false,
	keybindings = {},
	hit_boxes = {},
	hovered_id = nil,
	scroll_top_index = 1,
	auto_scroll = true,
	last_entries_count = 0,
	overlay = mp.create_osd_overlay and mp.create_osd_overlay("ass-events"),
	config = nil,
	exporter_handler = nil,
}

function History:new(o)
	local obj = o or {}
	setmetatable(obj, self)
	self.__index = self
	return obj
end

function History:init(config)
	self.config = config
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

function History:make_osd()
	local osd = Display:new()
	local ow, oh = mp.get_osd_size()
	if oh == 0 then
		return osd
	end
	local scale = oh / 720

	Renderer.draw(self, osd, scale, ow, oh)
	return osd
end

function History:handle_mouse_move()
	local mx, my = mp.get_mouse_pos()
	local old_hovered = self.hovered_id
	self.hovered_id = nil
	for _, box in ipairs(self.hit_boxes) do
		if mx >= box.x1 and mx <= box.x2 and my >= box.y1 and my <= box.y2 then
			self.hovered_id = box.id
			break
		end
	end
	if old_hovered ~= self.hovered_id then
		self:update()
	end
end

function History:handle_click()
	local mx, my = mp.get_mouse_pos()
	for _, box in ipairs(self.hit_boxes) do
		if mx >= box.x1 and mx <= box.x2 and my >= box.y1 and my <= box.y2 then
			if box.id == "clear" then
				self:clear_history()
				return true
			end
			if box.id == "toggle_anim" then
				self.config.picture_animated = not self.config.picture_animated
				self.config.save("picture_animated", self.config.picture_animated)
				local status = self.config.picture_animated and "Enabled" or "Disabled"
				Player.notify("Animated pictures: " .. status, "info")
				self:update(true)
				return true
			end
			if box.entry then
				if self.exporter_handler and self.exporter_handler.expand_to_subtitle then
					self.exporter_handler:expand_to_subtitle(box.entry)
				elseif box.entry.start and box.entry.start >= 0 then
					mp.set_property_number("time-pos", box.entry.start + 0.035)
					Player.notify("Jumped to " .. StringOps.format_duration(box.entry.start, true))
				end
				return true
			end
		end
	end
	return false
end

function History:clear_history()
	Monitor.clear_history()
	Player.notify("History cleared", "info", 2)
	self:update(true)
end

function History:update(force)
	if self.active == false then
		return
	end
	local ow, oh = mp.get_osd_size()
	local entries_key = Monitor.is_appending() and ("appending_" .. #Monitor.recorded_subs())
		or ("history_" .. #Monitor.get_history())
	local current_state =
		string.format("%d_%d_%s_%s_%s", ow, oh, tostring(self.hovered_id), entries_key, tostring(self.scroll_top_index))
	-- Force update during auto-scroll for immediate visibility
	if not force and not self.auto_scroll and self.last_state == current_state then
		return
	end
	self.overlay.res_x = ow
	self.overlay.res_y = oh
	self.overlay.data = self:make_osd():get_text()
	self.overlay:update()
	self.last_state = current_state
end

function History:open(request_state)
	if self.overlay == nil then
		Player.notify("OSD overlay is not supported", "error", 5)
		return
	end

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

	mp.add_forced_key_binding("MBTN_LEFT", "menu-hit-test", function()
		self:handle_click()
	end)
	mp.add_forced_key_binding("mouse_move", "menu-hover-test", function()
		self:handle_mouse_move()
	end)
	mp.add_forced_key_binding("WHEEL_UP", "menu-scroll-up", function()
		self.scroll_top_index = math.max(1, (self.scroll_top_index or 1) - 1)
		self.auto_scroll = false
		self:update()
	end)
	mp.add_forced_key_binding("WHEEL_DOWN", "menu-scroll-down", function()
		local max_idx = self.max_scroll_top_index or 1
		self.scroll_top_index = math.min(max_idx, (self.scroll_top_index or 1) + 1)
		self.auto_scroll = (self.scroll_top_index == max_idx)
		self:update()
	end)
	mp.add_forced_key_binding(self.config.key_history_clear, "menu-clear-history", function()
		self:clear_history()
	end)

	self.auto_scroll = true
	self.scroll_top_index = self.scroll_top_index or 1
	self.last_state = nil
	self.active = true

	-- Update in real-time when adding subtitles
	self._sub_observer = function()
		if self.active then
			-- Small delay ensures Monitor processed update
			mp.add_timeout(0.05, function()
				if self.active then
					self:update()
				end
			end)
		end
	end
	mp.observe_property("sub-text", "string", self._sub_observer)

	-- Periodic update timer to ensure display refresh without subtitle changes
	self._update_timer = mp.add_periodic_timer(0.1, function()
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
	mp.remove_key_binding("menu-hit-test")
	mp.remove_key_binding("menu-hover-test")
	mp.remove_key_binding("menu-scroll-up")
	mp.remove_key_binding("menu-scroll-down")
	mp.remove_key_binding("menu-clear-history")
	if self._sub_observer then
		mp.unobserve_property(self._sub_observer)
		self._sub_observer = nil
	end
	if self._update_timer then
		self._update_timer:kill()
		self._update_timer = nil
	end
	self.hovered_id = nil
	self.overlay:remove()
	self.active = false

	if self.config and self.config.history_hide_volume then
		mp.commandv("script-message-to", "uosc", "disable-elements", "yomipv_history", "")
	end
end

return History
