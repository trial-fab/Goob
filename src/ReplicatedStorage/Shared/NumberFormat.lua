--!strict
-- =============================================================================
-- NumberFormat — number rendering (abbreviations, separators, multipliers).
--
-- [Contract] Owns: turning numbers into display strings — suffix abbreviation
--   to 1e303, exact thousands-separated integers, rate and multiplier styles.
-- [Contract] Never: renders currency symbols or icons — currency is an image
--   icon (Goo icon / Gem icon) beside a bare number, authored in Studio;
--   NumberFormat owns numbers only. Never game math — display only.
-- [Contract] Binds: DESIGN.md §6 reuse map (PORT-AS-IS from ClickGame).
-- =============================================================================

local NumberFormat = {}

export type AbbreviateOptions = {
	decimals: number?,
	lowercaseThousands: boolean?,
}

local SUFFIXES = {
	"k",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"Ud",
	"Dd",
	"Td",
	"Qad",
	"Qid",
	"Sxd",
	"Spd",
	"Ocd",
	"Nod",
	"Vg",
	"Uvg",
	"Dvg",
	"Tvg",
	"Qavg",
	"Qivg",
	"Sxvg",
	"Spvg",
	"Ocvg",
	"Novg",
	"Tg",
	"Utg",
	"Dtg",
	"Ttg",
	"Qatg",
	"Qitg",
	"Sxtg",
	"Sptg",
	"Octg",
	"Notg",
	"Qag",
	"Uqag",
	"Dqag",
	"Tqag",
	"Qaqag",
	"Qiqag",
	"Sxqag",
	"Spqag",
	"Ocqag",
	"Noqag",
	"Qig",
	"Uqig",
	"Dqig",
	"Tqig",
	"Qaqig",
	"Qiqig",
	"Sxqig",
	"Spqig",
	"Ocqig",
	"Noqig",
	"Sxg",
	"Usxg",
	"Dsxg",
	"Tsxg",
	"Qasxg",
	"Qisxg",
	"Sxsxg",
	"Spsxg",
	"Ocsxg",
	"Nosxg",
	"Spg",
	"Uspg",
	"Dspg",
	"Tspg",
	"Qaspg",
	"Qispg",
	"Sxspg",
	"Spspg",
	"Ocspg",
	"Nospg",
	"Ocg",
	"Uocg",
	"Docg",
	"Tocg",
	"Qaocg",
	"Qiocg",
	"Sxocg",
	"Spocg",
	"Ococg",
	"Noocg",
	"Nog",
	"Unog",
	"Dnog",
	"Tnog",
	"Qanog",
	"Qinog",
	"Sxnog",
	"Spnog",
	"Ocnog",
	"Nonog",
	"Ce",
}

local function trimTrailingZeroes(text: string): string
	local trimmed = text:gsub("(%..-)0+$", "%1")
	local result = trimmed:gsub("%.$", "")
	return result
end

local function formatCompact(compactValue: number, decimals: number): string
	local formatString = "%." .. tostring(decimals) .. "f"
	return trimTrailingZeroes(string.format(formatString, compactValue))
end

local function getSuffix(index: number, lowercaseThousands: boolean?): string?
	if index == 1 and lowercaseThousands ~= false then
		return "k"
	end

	return SUFFIXES[index]
end

function NumberFormat.abbreviate(value: any, options: AbbreviateOptions?): string
	local opts: AbbreviateOptions = options or {}
	local number = tonumber(value) or 0

	if number ~= number then
		return "0"
	end
	if number == math.huge then
		return "inf"
	elseif number == -math.huge then
		return "-inf"
	end

	local sign = number < 0 and "-" or ""
	local absolute = math.abs(number)
	if absolute < 1000 then
		if opts.decimals then
			return sign .. formatCompact(absolute, opts.decimals)
		end
		return sign .. tostring(math.floor(absolute + 0.5))
	end

	local suffixIndex = math.floor(math.log(absolute) / math.log(1000) + 1e-10)
	local suffix = getSuffix(suffixIndex, opts.lowercaseThousands)
	if not suffix then
		local exponent = math.floor(math.log(absolute) / math.log(10) + 1e-10)
		return sign .. formatCompact(absolute / (10 ^ exponent), 2) .. "e" .. tostring(exponent)
	end

	local compactValue = absolute / (10 ^ (suffixIndex * 3))
	local decimals = opts.decimals
	if decimals == nil then
		if compactValue >= 100 then
			decimals = 0
		elseif compactValue >= 10 then
			decimals = 1
		else
			decimals = 2
		end
	end

	return sign .. formatCompact(compactValue, decimals :: number) .. suffix
end

-- Full, un-abbreviated integer with thousands separators (e.g. 1234567 ->
-- "1,234,567"), for surfaces where players want the exact total. Uses %.0f so
-- large doubles render without scientific notation.
function NumberFormat.exact(value: any): string
	local number = tonumber(value) or 0
	if number ~= number then
		return "0"
	end
	if number == math.huge then
		return "inf"
	elseif number == -math.huge then
		return "-inf"
	end

	local sign = number < 0 and "-" or ""
	local digits = string.format("%.0f", math.abs(number))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if grouped:sub(1, 1) == "," then
		grouped = grouped:sub(2)
	end

	return sign .. grouped
end

function NumberFormat.rate(value: any): string
	local number = tonumber(value) or 0
	local absolute = math.abs(number)

	if absolute >= 1000 then
		return NumberFormat.abbreviate(number)
	elseif number == math.floor(number) then
		return tostring(number)
	elseif absolute >= 10 then
		return formatCompact(number, 1)
	end

	return formatCompact(number, 2)
end

function NumberFormat.multiplier(value: any): string
	local number = tonumber(value) or 1
	if number < 0 then
		number = 0
	end

	local text
	if number >= 1000 then
		text = NumberFormat.abbreviate(number)
	elseif number >= 100 then
		text = formatCompact(number, 0)
	elseif number >= 10 then
		text = formatCompact(number, 1)
	else
		text = formatCompact(number, 2)
	end

	return "x" .. text
end

NumberFormat.compact = NumberFormat.abbreviate

return NumberFormat
