--[[ Mouse Handler ]]

local mp = require("mp")
local msg = require("mp.msg")

local MouseHandler = {
	idle_start = mp.get_time(),
	last_x = -1,
	last_y = -1,
}

function MouseHandler.init(config, handler, history, Selector)
	-- Periodic check for mouse movement and idle state
	mp.add_periodic_timer(0.1, function()
		if not config.selector_trigger_on_mouse_move then
			MouseHandler.idle_start = mp.get_time()
			return
		end

		if Selector.active then
			MouseHandler.idle_start = mp.get_time()
			return
		end

		local current_time = mp.get_time()
		local mx, my = mp.get_mouse_pos()

		-- Verify if movement has occurred since last tick
		if MouseHandler.last_x ~= mx or MouseHandler.last_y ~= my then
			-- Trigger selection if mouse has been stationary for the threshold period
			if MouseHandler.last_x ~= -1 and MouseHandler.last_y ~= -1 then
				local idle_time = current_time - MouseHandler.idle_start
				if idle_time >= config.selector_trigger_mouse_idle_time then
					msg.info("Mouse moved after idle, triggering selector")
					handler:start_export(history)
				end
			end

			MouseHandler.last_x = mx
			MouseHandler.last_y = my
			MouseHandler.idle_start = current_time
		end
	end)
end

return MouseHandler
