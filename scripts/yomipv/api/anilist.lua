--[[ AniList integration module ]]

local utils = require("mp.utils")
local msg = require("mp.msg")

local Anilist = {}

function Anilist.new(config, curl)
	local obj = {
		config = config,
		curl = curl,
		caching = {},
		base_url = "https://graphql.anilist.co",
	}
	setmetatable(obj, Anilist)
	Anilist.__index = Anilist
	return obj
end

local MEDIA_FIELDS = [[
	id
	episodes
	title {
		romaji
		english
	}
	relations {
		edges {
			relationType
			node {
				id
				episodes
				format
			}
		}
	}
]]

function Anilist:search_anime_by_title(query, callback)
	if self.caching[query] then
		callback(true, self.caching[query])
		return
	end

	local graphql_query = string.format([[
		query ($search: String) {
			Media (search: $search, type: ANIME) {
				%s
			}
		}
	]], MEDIA_FIELDS)

	local variables = { search = query }
	local body = utils.format_json({ query = graphql_query, variables = variables })
	local headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" }

	self.curl.request(self.base_url, body, function(success, result, err)
		if not success or not result or result.status ~= 0 then
			msg.warn("Anilist search failed: " .. tostring(err))
			callback(false, "Search request failed")
			return
		end
		local resp
		pcall(function() resp = utils.parse_json(result.stdout) end)
		if resp and resp.data and resp.data.Media and resp.data.Media.id then
			self.caching[query] = resp.data.Media
			callback(true, resp.data.Media)
		else
			callback(false, "No anime found for query: " .. query)
		end
	end, { headers = headers })
end

function Anilist:get_media_by_id(media_id, callback)
	local graphql_query = string.format([[
		query ($id: Int) {
			Media (id: $id, type: ANIME) {
				%s
			}
		}
	]], MEDIA_FIELDS)

	local variables = { id = media_id }
	local body = utils.format_json({ query = graphql_query, variables = variables })
	local headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" }

	self.curl.request(self.base_url, body, function(success, result, _err)
		if not success or not result or result.status ~= 0 then
			callback(false, "Request failed")
			return
		end
		local resp
		pcall(function() resp = utils.parse_json(result.stdout) end)
		if resp and resp.data and resp.data.Media then
			callback(true, resp.data.Media)
		else
			callback(false, "Media not found")
		end
	end, { headers = headers })
end

function Anilist:update_episode(media_id, episode_num, callback)
	local graphql_query = [[
		mutation ($mediaId: Int, $progress: Int) {
			SaveMediaListEntry (mediaId: $mediaId, progress: $progress) {
				id
				progress
			}
		}
	]]
	local variables = { mediaId = media_id, progress = episode_num }
	local body = utils.format_json({ query = graphql_query, variables = variables })

	local headers = {
		["Authorization"] = "Bearer " .. self.config.anilist_token,
		["Content-Type"] = "application/json",
		["Accept"] = "application/json",
	}

	self.curl.request(self.base_url, body, function(success, result, err)
		if not success or not result or result.status ~= 0 then
			msg.warn("Anilist update failed: " .. tostring(err))
			callback(false, err or "Request failed")
			return
		end

		local resp
		pcall(function() resp = utils.parse_json(result.stdout) end)
		if resp and resp.errors then
			msg.warn("Anilist API error: " .. utils.format_json(resp.errors))
			callback(false, "GraphQL Error")
		else
			callback(true, nil)
		end
	end, { headers = headers })
end

function Anilist:check_and_update(title, season_num, episode_num, callback)
	local query = title
	if season_num and tonumber(season_num) then
		if tonumber(season_num) > 1 then
			query = string.format("%s Season %s", title, tostring(season_num))
		end
	end

	episode_num = tonumber(episode_num)
	if not episode_num then
		if callback then callback(false, "Invalid episode") end
		return
	end

	msg.info(string.format("Looking up AniList for '%s' to update Episode %s", query, tostring(episode_num)))

	local function process_media(media, target_ep)
		if not media.episodes or target_ep <= media.episodes then
			msg.info(string.format("Updating Media [%d] %s to Episode %d", media.id, media.title.romaji, target_ep))
			self:update_episode(media.id, target_ep, function(success, err)
				if callback then callback(success, err) end
			end)
			return
		end

		msg.info(string.format(
			"Episode %d is higher than %s max episodes (%d). Searching for sequel...",
			target_ep, media.title.romaji, media.episodes
		))

		local sequel_id = nil
		if media.relations and media.relations.edges then
			for _, edge in ipairs(media.relations.edges) do
				if edge.relationType == "SEQUEL" then
					sequel_id = edge.node.id
					if edge.node.format == "TV" then
						break
					end
				end
			end
		end

		if sequel_id then
			local remaining_ep = target_ep - media.episodes
			self:get_media_by_id(sequel_id, function(success, next_media)
				if success then
					process_media(next_media, remaining_ep)
				else
					msg.warn("Failed to fetch sequel ID " .. tostring(sequel_id))
					self:update_episode(media.id, media.episodes, function(s, e) if callback then callback(s, e) end end)
				end
			end)
		else
			msg.warn("No further sequel found. Capping update to max episodes.")
			self:update_episode(media.id, media.episodes, function(s, e) if callback then callback(s, e) end end)
		end
	end

	self:search_anime_by_title(query, function(search_success, media_or_err)
		if not search_success then
			if callback then callback(false, media_or_err) end
			return
		end
		process_media(media_or_err, episode_num)
	end)
end

return Anilist