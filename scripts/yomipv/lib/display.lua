--[[ OSD text builder                                  ]]
--[[ Subtitle and OSD formatting with ASS tag support. ]]

local Display = {}

-- Create display builder instance
function Display:new()
	local obj = {
		buffer = "",
		lines = {},
	}
	setmetatable(obj, self)
	self.__index = self
	return obj
end

-- Append text to buffer
function Display:append(str)
	self.buffer = self.buffer .. str
	return self
end

-- Append text with newline
function Display:append_line(str)
	self.buffer = self.buffer .. str .. "\\N"
	return self
end

-- Append formatted text (string.format)
function Display:append_format(fmt, ...)
	self.buffer = self.buffer .. string.format(fmt, ...)
	return self
end

-- Set ASS text color (hex)
function Display:color(color)
	self.buffer = self.buffer .. string.format("{\\c&H%s&}", color)
	return self
end

-- Set ASS opacity (00-FF)
function Display:alpha(alpha)
	self.buffer = self.buffer .. string.format("{\\alpha&H%s&}", alpha)
	return self
end

-- Set font size
function Display:font_size(size)
	self.buffer = self.buffer .. string.format("{\\fs%d}", size)
	return self
end

-- Set font name
function Display:font(name)
	self.buffer = self.buffer .. string.format("{\\fn%s}", name)
	return self
end

-- Apply bold formatting or append bolded text
function Display:bold(val)
	if type(val) == "string" then
		self.buffer = self.buffer .. "{\\b1}" .. val .. "{\\b0}"
	else
		local weight = val or 1
		self.buffer = self.buffer .. string.format("{\\b%d}", weight)
	end
	return self
end

-- Reset ASS formatting state
function Display:reset()
	self.buffer = self.buffer .. "{\\r}"
	return self
end

-- Set OSD position and optional alignment
function Display:pos(x, y, _, align)
	if align then
		self:alignment(align)
	end
	self.buffer = self.buffer .. string.format("{\\pos(%d,%d)}", x, y)
	return self
end

-- Set OSD position (legacy alias)
function Display:position(x, y)
	return self:pos(x, y)
end

-- Set ASS alignment (1-9)
function Display:alignment(align)
	self.buffer = self.buffer .. string.format("{\\an%d}", align)
	return self
end

-- Set border width
function Display:border(size)
	self.buffer = self.buffer .. string.format("{\\bord%f}", size)
	return self
end

-- Set shadow depth
function Display:shadow(depth)
	self.buffer = self.buffer .. string.format("{\\shad%f}", depth)
	return self
end

-- Set font size (alias)
function Display:size(sz)
	return self:font_size(sz)
end

-- Append plain text (alias)
function Display:text(str)
	return self:append(str)
end

-- Set rectangular clipping range
function Display:clip(x1, y1, x2, y2)
	self.buffer = self.buffer .. string.format("{\\clip(%d,%d,%d,%d)}", x1, y1, x2, y2)
	return self
end

-- Draw rectangle using ASS vector commands (supports rounded corners)
function Display:rect(x1, y1, x2, y2, color, alpha, radius, corners)
	self:new_event()
	self:reset()
	self:color(color)
	self:alpha(alpha)
	self:pos(0, 0)
	self:alignment(7)
	self:border(0)
	self:shadow(0)

	self.buffer = self.buffer .. "{\\p1}"

	if not radius or radius <= 0 then
		-- Plain rectangle
		self.buffer = self.buffer .. string.format("m %d %d l %d %d %d %d %d %d", x1, y1, x2, y1, x2, y2, x1, y2)
	else
		-- Rounded rectangle implementation using drawing commands
		corners = corners or { tl = true, tr = true, bl = true, br = true }

		-- Start at top-left, after the curve
		local start_x = corners.tl and (x1 + radius) or x1
		self.buffer = self.buffer .. string.format("m %d %d ", start_x, y1)

		-- Top edge and top-right corner
		local tr_x = corners.tr and (x2 - radius) or x2
		self.buffer = self.buffer .. string.format("l %d %d ", tr_x, y1)
		if corners.tr then
			self.buffer = self.buffer .. string.format("b %d %d %d %d %d %d ", x2, y1, x2, y1, x2, y1 + radius)
		end

		-- Right edge and bottom-right corner
		local br_y = corners.br and (y2 - radius) or y2
		self.buffer = self.buffer .. string.format("l %d %d ", x2, br_y)
		if corners.br then
			self.buffer = self.buffer .. string.format("b %d %d %d %d %d %d ", x2, y2, x2, y2, x2 - radius, y2)
		end

		-- Bottom edge and bottom-left corner
		local bl_x = corners.bl and (x1 + radius) or x1
		self.buffer = self.buffer .. string.format("l %d %d ", bl_x, y2)
		if corners.bl then
			self.buffer = self.buffer .. string.format("b %d %d %d %d %d %d ", x1, y2, x1, y2, x1, y2 - radius)
		end

		-- Left edge and top-left corner
		local tl_y = corners.tl and (y1 + radius) or y1
		self.buffer = self.buffer .. string.format("l %d %d ", x1, tl_y)
		if corners.tl then
			self.buffer = self.buffer .. string.format("b %d %d %d %d %d %d ", x1, y1, x1, y1, x1 + radius, y1)
		end
	end

	self.buffer = self.buffer .. "{\\p0}"
	return self
end

-- Close current event and start new dialogue line
function Display:new_event()
	if self.buffer ~= "" then
		table.insert(self.lines, self.buffer)
		self.buffer = ""
	end
	return self
end

-- Return complete OSD text string
function Display:get_text()
	local final = ""
	for _, line in ipairs(self.lines) do
		final = final .. line .. "\n"
	end
	return final .. self.buffer
end

-- Clear display buffer state
function Display:clear()
	self.buffer = ""
	return self
end

-- Fix color format for ASS (hex/BGR conversion)
function Display.fix_color(c, default)
	if not c then
		return default or "FFFFFF"
	end
	local s = tostring(c):gsub("[%#%']", ""):gsub("^0x", "")

	-- Handle rgb(r, g, b) and rgba(r, g, b, a)
	local r, g, b = s:match("rgb%s*%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)")
	if not r then
		r, g, b = s:match("rgba%s*%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*[%d%.]+%s*%)")
	end

	if r and g and b then
		return string.format(
			"%02X%02X%02X",
			math.min(255, math.max(0, tonumber(b))),
			math.min(255, math.max(0, tonumber(g))),
			math.min(255, math.max(0, tonumber(r)))
		)
	end

	local hex = s:match("%x%x%x%x%x%x")
	if hex then
		local rh, gh, bh = hex:sub(1, 2), hex:sub(3, 4), hex:sub(5, 6)
		return bh .. gh .. rh
	end
	return default or "FFFFFF"
end

return Display
