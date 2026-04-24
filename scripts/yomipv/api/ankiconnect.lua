--[[ AnkiConnect API Wrapper ]]

local utils = require("mp.utils")
local msg = require("mp.msg")
local Api = require("lib.api")

local AnkiConnect = {}
local DEFAULT_VERSION = 6

function AnkiConnect.new(config, curl)
	local obj = {
		config = config,
		curl = curl,
		media_dir_path = nil,
		_pending_media_path_callbacks = nil,
	}
	setmetatable(obj, AnkiConnect)
	AnkiConnect.__index = AnkiConnect
	return obj
end

function AnkiConnect:get_url()
	local url = self.config.ankiconnect_url or "127.0.0.1:8765"
	if not url:find("^http") then url = "http://" .. url end
	return url
end

function AnkiConnect:request(action, params, callback)
	local url = self:get_url()
	local body = { action = action, version = DEFAULT_VERSION, params = params or {} }
	if self.config.ankiconnect_api_key and self.config.ankiconnect_api_key ~= "" then
		body.key = self.config.ankiconnect_api_key
	end

	-- AnkiConnect requires empty params as {} not []
	local json_body, _ = utils.format_json(body)
	json_body = json_body:gsub('"params":%s*%[%s*%]', '"params":{}')

	Api.request(self.curl, url, json_body, function(response, err)
		if err then return callback(nil, err) end
		if response.error then return callback(nil, response.error) end
		callback(response.result, nil)
	end)
end

function AnkiConnect:add_note(deck, note_type, fields, tags, callback)
	local tag_array = (type(tags) == "string") and {} or tags
	if type(tags) == "string" then
		for tag in tags:gmatch("%S+") do table.insert(tag_array, tag) end
	end
	self:request("addNote", {
		note = {
			deckName = deck,
			modelName = note_type,
			fields = fields,
			tags = tag_array or {},
			options = { allowDuplicate = false }
		}
	}, callback)
end

function AnkiConnect:update_note_fields(note_id, fields, callback)
	self:request("updateNoteFields", { note = { id = note_id, fields = fields } }, function(_, err)
		callback(not err, err)
	end)
end

function AnkiConnect:store_media_file(filename, data, callback)
	self:request("storeMediaFile", { filename = filename, data = data }, function(_, err)
		callback(not err, err)
	end)
end

function AnkiConnect:ingest_media(filename, content, callback)
	-- Wrap the result of store_media_file
	self:store_media_file(filename, content, function(_, err)
		if err then msg.warn("Media store failed: " .. err) else msg.info("Stored media: " .. filename) end
		if callback then callback() end
	end)
end

function AnkiConnect:get_media_dir_path(callback)
	if self.media_dir_path then return callback(self.media_dir_path, nil) end
	if self._pending_media_path_callbacks then
		table.insert(self._pending_media_path_callbacks, callback)
		return
	end
	self._pending_media_path_callbacks = { callback }

	self:request("getMediaDirPath", {}, function(result, err)
		if not err then self.media_dir_path = result end
		local cbs = self._pending_media_path_callbacks
		self._pending_media_path_callbacks = nil
		for _, cb in ipairs(cbs) do cb(result, err) end
	end)
end

function AnkiConnect:get_media_path(cb) return self:get_media_dir_path(cb) end
function AnkiConnect:gui_browse(query, cb) self:request("guiBrowse", { query = query or "" }, cb) end

function AnkiConnect:gui_select_note(note_id, cb)
	self:request("guiSelectNote", { note = note_id }, function(res, err) cb(res, err) end)
end

function AnkiConnect:find_notes(query, cb) self:request("findNotes", { query = query }, cb) end
function AnkiConnect:find_cards(query, cb) self:request("findCards", { query = query }, cb) end
function AnkiConnect:cards_info(card_ids, cb) self:request("cardsInfo", { cards = card_ids }, cb) end
function AnkiConnect:notes_info(note_ids, cb) self:request("notesInfo", { notes = note_ids }, cb) end

function AnkiConnect:get_note_fields(note_id, callback)
	self:notes_info({ note_id }, function(notes, err)
		if err then return callback(nil, err) end
		if notes and #notes > 0 then
			local fields = {}
			for k, v in pairs(notes[1].fields or {}) do fields[k] = v.value end
			return callback(fields, nil)
		end
		callback(nil, "Note not found")
	end)
end

function AnkiConnect:sync_media_fields(note_id, fields, _, callback)
	self:update_note_fields(note_id, fields, function()
		if callback then callback() end
	end)
end

return AnkiConnect
