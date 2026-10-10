--!strict
-- Number and time formatting shared by the server (leaderstats, signs) and
-- the client (HUD, panels).

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 1234567 -> "1,234,567"
function Format.Number(value: number): string
	local negative = value < 0
	local whole = tostring(math.floor(math.abs(value)))
	local out = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return if negative then "-" .. out else out
end

-- 999 -> "999", 1250 -> "1.25K", 12500 -> "12.5K", 125000 -> "125K"
function Format.Short(value: number): string
	local abs = math.abs(value)
	if abs < 1000 then
		if abs ~= math.floor(abs) and abs < 10 then
			return string.format("%.1f", value)
		end
		return tostring(math.floor(value))
	end
	local tier = math.min(math.floor(math.log10(abs) / 3), #SUFFIXES - 1)
	local scaled = value / 10 ^ (tier * 3)
	local text
	if math.abs(scaled) < 10 then
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	elseif math.abs(scaled) < 100 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = tostring(math.floor(scaled))
	end
	-- Trim trailing zeros: "1.50" -> "1.5", "2.00" -> "2"
	text = text:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
	return text .. SUFFIXES[tier + 1]
end

-- Income rates can be fractional ("0.5/s"), so keep one decimal under 100.
function Format.Rate(perSecond: number): string
	if perSecond < 100 and perSecond ~= math.floor(perSecond) then
		return string.format("%.1f", perSecond)
	end
	return Format.Short(perSecond)
end

-- 45 -> "45s", 125 -> "2m 05s", 4380 -> "1h 13m"
function Format.Duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return `{seconds}s`
	elseif seconds < 3600 then
		return string.format("%dm %02ds", seconds // 60, seconds % 60)
	end
	return string.format("%dh %02dm", seconds // 3600, (seconds % 3600) // 60)
end

-- 0.017 -> "1.7%", 0.003 -> "0.3%", 0.55 -> "55%"
function Format.Percent(fraction: number): string
	local percent = fraction * 100
	if percent >= 10 or percent == math.floor(percent) then
		return string.format("%d%%", math.floor(percent + 0.5))
	elseif percent >= 1 then
		return string.format("%.1f%%", percent)
	end
	return (string.format("%.2f%%", percent):gsub("0+%%$", "%%"):gsub("%.%%$", "%%"))
end

return Format
