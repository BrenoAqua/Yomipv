--[[
  Matched-length sorting helpers for dictionary entry ranking.
  Algorithm must stay in sync with lookup-app/match-sort.js
]]

local M = {}

--- Strip parenthetical annotations: 食べる（たべる） → 食べる
---@param s string
---@return string
function M.strip_parens(s)
	return s:gsub("%s*[%(（].-[%)）]%s*", "")
end

--- Decode UTF-8 string into codepoints, normalizing katakana → hiragana
--- Covers U+30A1..U+30FA (ァ‥ヺ), including ヴヵヶヷヸヹヺ
---@param s string
---@return integer[]
function M.to_normalized_codepoints(s)
	local cps = {}
	local i = 1
	local len = #s
	while i <= len do
		local b = s:byte(i)
		local cp, size
		if b < 0x80 then
			cp, size = b, 1
		elseif b < 0xE0 then
			if i + 1 > len then break end
			cp = (b - 0xC0) * 64 + (s:byte(i + 1) - 0x80)
			size = 2
		elseif b < 0xF0 then
			if i + 2 > len then break end
			cp = (b - 0xE0) * 4096 + (s:byte(i + 1) - 0x80) * 64 + (s:byte(i + 2) - 0x80)
			size = 3
		else
			if i + 3 > len then break end
			cp = (b - 0xF0) * 262144 + (s:byte(i + 1) - 0x80) * 4096 + (s:byte(i + 2) - 0x80) * 64 + (s:byte(i + 3) - 0x80)
			size = 4
		end
		if cp >= 0x30A1 and cp <= 0x30FA then
			cp = cp - 0x60
		end
		cps[#cps + 1] = cp
		i = i + size
	end
	return cps
end

--- Common prefix length between two codepoint arrays
---@param a integer[]
---@param b integer[]
---@return integer
function M.prefix_match_len(a, b)
	local n = math.min(#a, #b)
	local i = 0
	while i < n and a[i + 1] == b[i + 1] do
		i = i + 1
	end
	return i
end

--- Compute match score: max prefix match of term against expr and reading (kana-normalized).
--- Compares against both expression (handles kanji lookup) and reading (handles kana lookup).
---@param term_cps integer[] pre-computed normalized codepoints of the lookup term
---@param expr string
---@param reading string
---@return integer
function M.compute_matched_len(term_cps, expr, reading)
	local expr_cps = M.to_normalized_codepoints(M.strip_parens(expr))
	local best = M.prefix_match_len(term_cps, expr_cps)

	if reading ~= "" and reading ~= expr then
		local reading_cps = M.to_normalized_codepoints(M.strip_parens(reading))
		local r = M.prefix_match_len(term_cps, reading_cps)
		if r > best then best = r end
	end

	return best
end

return M
