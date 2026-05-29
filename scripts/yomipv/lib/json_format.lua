--[[ JSON Formatter for db builder ]]

local utils = require("mp.utils")

local JSONFormat = {}

local function get_priority(keys)
	if keys.generated_at or keys.fields or keys.words then
		return { generated_at = 1, fields = 2, words = 3 }
	end

	if keys.interval or keys.state or keys.reading then
		return { reading = 1, interval = 2, state = 3 }
	end

	return {}
end

local function is_scalar(value)
	return type(value) == "string" or type(value) == "number" or type(value) == "boolean" or value == nil
end

local function is_scalar_array(obj)
	if type(obj) ~= "table" or #obj == 0 then
		return false
	end

	for _, value in ipairs(obj) do
		if not is_scalar(value) then
			return false
		end
	end
	return true
end

function JSONFormat.format(obj, level)
	level = level or 0
	local indent = string.rep("  ", level)
	local next_indent = string.rep("  ", level + 1)

	if type(obj) == "table" then
		local is_array = #obj > 0
		local parts = {}
		if is_array then
			if is_scalar_array(obj) then
				table.insert(parts, "[")
				for i, v in ipairs(obj) do
					table.insert(parts, JSONFormat.format(v, 0))
					if i < #obj then
						table.insert(parts, ", ")
					end
				end
				table.insert(parts, "]")
			else
				table.insert(parts, "[\n")
				for i, v in ipairs(obj) do
					table.insert(parts, next_indent .. JSONFormat.format(v, level + 1))
					if i < #obj then
						table.insert(parts, ",")
					end
					table.insert(parts, "\n")
				end
				table.insert(parts, indent .. "]")
			end
		else
			table.insert(parts, "{\n")
			local keys = {}
			local key_set = {}
			for k in pairs(obj) do
				table.insert(keys, k)
				key_set[k] = true
			end

			local priority = get_priority(key_set)
			table.sort(keys, function(a, b)
				if priority[a] and priority[b] then return priority[a] < priority[b] end
				if priority[a] then return true end
				if priority[b] then return false end
				return a < b
			end)

			for i, k in ipairs(keys) do
				table.insert(parts, next_indent .. utils.format_json(k) .. ": " .. JSONFormat.format(obj[k], level + 1))
				if i < #keys then
					table.insert(parts, ",")
				end
				table.insert(parts, "\n")
			end
			table.insert(parts, indent .. "}")
		end
		return table.concat(parts)
	elseif type(obj) == "string" then
		return utils.format_json(obj)
	elseif type(obj) == "number" or type(obj) == "boolean" then
		return tostring(obj)
	elseif obj == nil then
		return "null"
	else
		return utils.format_json(obj)
	end
end

return JSONFormat
