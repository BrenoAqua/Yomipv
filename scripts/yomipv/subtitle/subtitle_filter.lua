--[[ Subtitle Filter                           ]]
--[[ JSRE-based subtitle display sanitization. ]]

local mp = require("mp")
local Player = require("lib.player")

local SubtitleFilter = {}

function SubtitleFilter.apply_filters()
	if not SubtitleFilter._config or not SubtitleFilter._config.subtitle_filter_enabled then
		mp.set_property("sub-filter-jsre", "")
		return
	end

	mp.set_property("sub-ass-override", "force")

	local signs = [[.*\\(pos|move|p[0-9]|clip|an[0-9])\(.*]]
	local noise = [[^(\{.*\})?[(\[（【].*[)\]）】]\s*$]]
	local speaker = [[^(\{.*\})?🔊\s*$]]
	local arrows = [[^(\{.*\})?[➨➡➔➜➝➞]\s*$]]

	mp.set_property("sub-filter-jsre", table.concat({ signs, noise, speaker, arrows }, "|"))
end

function SubtitleFilter.init(config)
	SubtitleFilter._config = config

	mp.register_event("file-loaded", function()
		SubtitleFilter.apply_filters()
	end)

	mp.add_key_binding("b", "refresh_subs", function()
		SubtitleFilter.apply_filters()
		Player.notify("Native Filter Refreshed", "info")
	end)

	SubtitleFilter.apply_filters()
end

return SubtitleFilter
