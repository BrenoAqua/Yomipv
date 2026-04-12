--[[ API Helper ]]

local utils = require("mp.utils")

local Api = {}

function Api.request(curl, url, body, callback)
	local json_body
	if type(body) == "table" then
		local err
		json_body, err = utils.format_json(body)
		if err then
			return callback(nil, "JSON format error: " .. tostring(err))
		end
	else
		json_body = body
	end

	return curl.request(url, json_body, function(success, output, err_str)
		if not success then
			return callback(nil, "CURL error: " .. tostring(err_str))
		end

		if not output or output.status ~= 0 then
			local status = output and output.status or "unknown"
			return callback(nil, "HTTP error status: " .. status)
		end

		local response = utils.parse_json(output.stdout)
		if not response then
			return callback(nil, "JSON parse error")
		end

		callback(response, nil)
	end)
end

return Api
