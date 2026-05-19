--[[ Selector rendering engine                              ]]
--[[ OSD measurement, line wrapping, and ASS tag generation ]]

local mp = require("mp")
local Display = require("lib.display")

local Renderer = {}

local measure_overlay = mp.create_osd_overlay("ass-events")
measure_overlay.compute_bounds = true
measure_overlay.hidden = true

function Renderer.measure_width(text, size, font, bold)
	if not text or text == "" then
		return 0
	end
	local ow, oh = mp.get_osd_size()
	if not ow or ow <= 0 then
		ow, oh = 1280, 720
	end
	measure_overlay.res_x = ow
	measure_overlay.res_y = oh

	-- OSD markers to prevent trimming
	local ass = string.format("{\\an7\\fs%d\\fn%s\\b%d}|%s|", size, font, bold and 1 or 0, text)
	measure_overlay.data = ass
	local res = measure_overlay:update()

	local ass_m = string.format("{\\an7\\fs%d\\fn%s\\b%d}||", size, font, bold and 1 or 0)
	measure_overlay.data = ass_m
	local res_m = measure_overlay:update()

	if not res or not res_m then
		return 0
	end
	return math.max(0, (res.x1 - res.x0) - (res_m.x1 - res_m.x0))
end

function Renderer.render(selector)
	if (not selector.active and not selector.passive) or not selector.tokens or #selector.tokens == 0 then
		return
	end

	local ow, oh = mp.get_osd_size()
	if oh == 0 then
		return
	end

	-- Scales to 720p base
	local scale_factor = oh / 720.0

	local base_font_size = mp.get_property_number("sub-font-size", 45)
	local sub_scale = mp.get_property_number("sub-scale", 1.0)
	local font_size = selector.style.font_size
			and selector.style.font_size ~= 0
			and math.floor(math.abs(selector.style.font_size) * scale_factor)
		or math.floor(base_font_size * sub_scale * scale_factor)
	selector.scaled_font_size = font_size

	local font_name = (selector.style.font_name and selector.style.font_name ~= "") and selector.style.font_name
		or mp.get_property("sub-font", "sans-serif")
	local sub_margin_y = mp.get_property_number("sub-margin-y", 22)
	local sub_pos = (selector.style.pos_y and selector.style.pos_y >= 0) and selector.style.pos_y
		or mp.get_property_number("sub-pos", 100)
	local sub_bold = selector.style.bold ~= nil and selector.style.bold or mp.get_property_bool("sub-bold", true)

	local u_thickness = (selector.style.underline_thickness or 4) * scale_factor
	local u_offset = (selector.style.underline_offset or 2) * scale_factor
	local u_color = Display.fix_color(selector.style.selection_color or "00FFFF", "00FFFF")
	local underlines = {}

	local border_size = (selector.style.border_size or mp.get_property_number("sub-border-size", 2)) * scale_factor
	local shadow_offset = (selector.style.shadow_offset or mp.get_property_number("sub-shadow-offset", 0))
		* scale_factor
	local border_color =
		Display.fix_color(selector.style.border_color or mp.get_property("sub-border-color", "000000"), "000000")
	local shadow_color =
		Display.fix_color(selector.style.shadow_color or mp.get_property("sub-shadow-color", "000000"), "000000")
	local main_color = Display.fix_color(selector.style.color or mp.get_property("sub-color", "FFFFFF"), "FFFFFF")

	local function get_line_spacing()
		measure_overlay.res_x = ow
		measure_overlay.res_y = oh
		local style = string.format("{\\an7\\fs%d\\fn%s\\b%d}", font_size, font_name, sub_bold and 1 or 0)
		measure_overlay.data = style .. "H"
		local r1 = measure_overlay:update()
		measure_overlay.data = style .. "H\\NH"
		local r2 = measure_overlay:update()
		if not r1 or not r2 then
			return font_size * 1.25
		end
		-- Spacing calculated as (height of 2 lines) - (height of 1 line)
		return (r2.y1 - r2.y0) - (r1.y1 - r1.y0)
	end
	local line_height = get_line_spacing()

	local lines = {}
	local current_line = { tokens = {}, width = 0 }
	table.insert(lines, current_line)

	local max_width = ow * (selector.style.max_width_factor or 0.9)
	for i, token in ipairs(selector.tokens) do
		local raw_text = token.text or ""
		local search_pos = 1

		while true do
			local next_nl = raw_text:find("\n", search_pos)
			local segment_text = raw_text:sub(search_pos, (next_nl and (next_nl - 1) or nil))

			if segment_text ~= "" then
				local tw = Renderer.measure_width(segment_text, font_size, font_name, sub_bold)

							if current_line.width > 0 and current_line.width + tw > max_width then
					current_line = { tokens = {}, width = 0 }
					table.insert(lines, current_line)
				end

				table.insert(current_line.tokens, { index = i, visual_text = segment_text, width = tw })
				current_line.width = current_line.width + tw
			end

			if not next_nl then
				break
			end

				current_line = { tokens = {}, width = 0 }
			table.insert(lines, current_line)
			search_pos = next_nl + 1
		end
	end

	while #lines > 1 and #lines[#lines].tokens == 0 do
		table.remove(lines)
	end

	selector.token_boxes = {}
	local margin_y = math.floor(sub_margin_y * scale_factor)
	local y_base = math.floor((oh * sub_pos / 100) - margin_y)

	-- Different color for persistent mode
	local function get_sel_color()
		if selector.persistent_mode then
			return Display.fix_color(selector.style.selector_persistent_color or "FF8C00", "FF8C00")
		end
		return Display.fix_color(selector.style.selection_color or "00FFFF", "00FFFF")
	end

	local osd = Display:new()
	osd:size(font_size)
	osd:font(font_name)
	local global_bold = sub_bold and "\\b1" or "\\b0"

	osd:append(
		string.format(
			"{\\an2\\pos(%d,%d)\\q2\\bord%g\\shad%g\\3c&H%s&\\4c&H%s&\\1c&H%s&%s}",
			ow / 2,
			y_base,
			border_size,
			shadow_offset,
			border_color,
			shadow_color,
			main_color,
			global_bold
		)
	)

	for l_idx, line in ipairs(lines) do
		local y_line = y_base - (#lines - l_idx) * line_height
		local current_x = (ow / 2) - (line.width / 2)

		for _, t_seg in ipairs(line.tokens) do
			local is_selected = (t_seg.index >= selector.index and t_seg.index < selector.index + selector.selection_len)
			local is_first = (t_seg.index == selector.index)
			local is_last = (t_seg.index == selector.index + selector.selection_len - 1)
			local has_front_slice = is_first and selector.mora_index
			local has_back_slice = is_last and selector.tail_mora_index
			local is_partially_selected = is_selected and (has_front_slice or has_back_slice)

			local is_locked = (
				selector.lookup_locked
				and t_seg.index == selector.locked_index
				and (
					not selector.locked_mora_index
					or (t_seg.visual_text and selector.get_mora_byte_pos(t_seg.visual_text, selector.locked_mora_index) > 0)
				)
			)

			local wc = selector.style.word_colors and selector.style.word_colors[t_seg.index]

			-- Handle underline collection
			local added_underline = false
			if not selector.passive and selector.style.selection_underline then
				if is_partially_selected then
					local start_char = has_front_slice and selector.mora_index or 1
					local end_char = nil
					if has_back_slice then
						if has_front_slice and selector.mora_index and selector.mora_index > 1 then
							end_char = selector.mora_index + selector.tail_mora_index - 1
						else
							end_char = selector.tail_mora_index
						end
					end

					local term = t_seg.visual_text
					local start_byte = selector.get_mora_byte_pos(term, start_char)
					local end_byte = end_char and selector.get_mora_byte_pos(term, end_char + 1) or (#term + 1)
					local prefix = term:sub(1, start_byte - 1)
					local colored = term:sub(start_byte, end_byte - 1)

					if colored ~= "" then
						local px = current_x + Renderer.measure_width(prefix, font_size, font_name, sub_bold)
						local cw = Renderer.measure_width(colored, font_size, font_name, sub_bold)
						table.insert(underlines, { x = px, y = y_line + u_offset, w = cw, color = u_color })
						added_underline = true
					end
				elseif is_selected then
					table.insert(underlines, {
						x = current_x,
						y = y_line + u_offset,
						w = t_seg.width,
						color = u_color,
					})
					added_underline = true
				end
			end

			if not added_underline and selector.style.colorize_underline and wc then
				local color = type(wc) == "table" and wc.color or wc
				local term = type(wc) == "table" and wc.term or nil
				local underline_x = current_x
				local underline_w = t_seg.width

				if term and t_seg.visual_text and t_seg.visual_text ~= term then
					local text_len = #t_seg.visual_text
					local term_len = #term
					if text_len > term_len and t_seg.visual_text:sub(text_len - term_len + 1) == term then
						local prefix = t_seg.visual_text:sub(1, text_len - term_len)
						local prefix_w = Renderer.measure_width(prefix, font_size, font_name, sub_bold)
						underline_x = current_x + prefix_w
						underline_w = t_seg.width - prefix_w
					end
				end

				table.insert(underlines, {
					x = underline_x,
					y = y_line + u_offset,
					w = underline_w,
					color = color,
					is_colorizer = true,
				})
			end

			-- Handle text rendering
			if not selector.passive and is_partially_selected and not selector.style.selection_underline then
				local start_char = has_front_slice and selector.mora_index or 1
				local end_char = nil
				if has_back_slice then
					if has_front_slice and selector.mora_index and selector.mora_index > 1 then
						end_char = selector.mora_index + selector.tail_mora_index - 1
					else
						end_char = selector.tail_mora_index
					end
				end

				local term = t_seg.visual_text
				local start_byte = selector.get_mora_byte_pos(term, start_char)
				local end_byte = end_char and selector.get_mora_byte_pos(term, end_char + 1) or (#term + 1)
				local prefix = term:sub(1, start_byte - 1)
				local colored = term:sub(start_byte, end_byte - 1)
				local suffix = term:sub(end_byte)
				local sel_color = get_sel_color()

				if prefix ~= "" then
					osd:append(prefix)
				end
				if colored ~= "" then
					osd:append(string.format("{\\1c&H%s&}%s{\\1c&H%s&}", sel_color, colored, main_color))
				end
				if suffix ~= "" then
					osd:append(suffix)
				end
			elseif not selector.passive and is_selected and not selector.style.selection_underline then
				local sel_color = get_sel_color()
				osd:append(string.format("{\\1c&H%s&}%s{\\1c&H%s&}", sel_color, t_seg.visual_text, main_color))
			elseif not selector.passive and is_locked then
				local lock_color = Display.fix_color(selector.style.selector_lock_color or "FFD700", "FFD700")
				if selector.locked_mora_index and selector.locked_mora_index > 1 then
					local term = t_seg.visual_text
					local start_byte = selector.get_mora_byte_pos(term, selector.locked_mora_index)
					local prefix = term:sub(1, start_byte - 1)
					local colored = term:sub(start_byte)
					if prefix ~= "" then
						osd:append(prefix)
					end
					if colored ~= "" then
						osd:append(string.format("{\\1c&H%s&}%s{\\1c&H%s&}", lock_color, colored, main_color))
					end
				else
					osd:append(string.format("{\\1c&H%s&}%s{\\1c&H%s&}", lock_color, t_seg.visual_text, main_color))
				end
			else
				if wc and not selector.style.colorize_underline then
					local color = type(wc) == "table" and wc.color or wc
					osd:append(string.format("{\\1c&H%s&}%s{\\1c&H%s&}", color, t_seg.visual_text, main_color))
				else
					osd:append(t_seg.visual_text)
				end
			end

			table.insert(selector.token_boxes, {
				index = t_seg.index,
				x1 = current_x,
				y1 = y_line - font_size - (font_size * 0.05),
				x2 = current_x + t_seg.width,
				y2 = y_line + (font_size * 0.05),
			})
			current_x = current_x + t_seg.width
		end

		if l_idx < #lines then
			osd:append("\\N")
		end
	end

	for _, u in ipairs(underlines) do
		osd:new_event()
		osd:reset()
		osd:pos(0, 0)
		osd:alignment(7)
		osd:color(u.color or u_color)

		local alpha = "00"
		if u.is_colorizer and selector.style.colorize_opacity then
			local opacity = selector.style.colorize_opacity
			local alpha_val = math.floor((100 - opacity) / 100 * 255 + 0.5)
			alpha = string.format("%02X", math.max(0, math.min(255, alpha_val)))
		end
		osd:alpha(alpha)

		osd:border(border_size)
		osd:shadow(0)
		osd:append(string.format("{\\3c&H%s&}", border_color))
		osd:append("{\\p1}")
		osd:append(
			string.format(
				"m %d %d l %d %d %d %d %d %d",
				u.x,
				u.y,
				u.x + u.w,
				u.y,
				u.x + u.w,
				u.y + u_thickness,
				u.x,
				u.y + u_thickness
			)
		)
		osd:append("{\\p0}")
	end

	mp.set_osd_ass(ow, oh, osd:get_text())
end

return Renderer
