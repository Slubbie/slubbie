-- Text formatting helpers shared by the UI and server messages.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa" }

-- 1234 → "1,234"
function Format.Commas(n: number): string
	local negative = n < 0
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if negative then "-" else "") .. out
end

-- 1234 → "1.2K", 15300000 → "15.3M". Small numbers keep commas.
function Format.Short(n: number): string
	local abs = math.abs(n)
	if abs < 10000 then
		return Format.Commas(n)
	end
	local tier = math.min(#SUFFIXES - 1, math.floor(math.log10(abs) / 3))
	local scaled = n / 10 ^ (tier * 3)
	local text = if math.abs(scaled) >= 100 then string.format("%d", scaled) else string.format("%.1f", scaled)
	text = text:gsub("%.0$", "")
	return text .. SUFFIXES[tier + 1]
end

function Format.Coins(n: number): string
	return "🪙 " .. Format.Short(n)
end

-- Seconds → "2h 05m", "4m 10s", "12s".
function Format.Duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	if seconds >= 86400 then
		return string.format("%dd %02dh", seconds // 86400, (seconds % 86400) // 3600)
	elseif seconds >= 3600 then
		return string.format("%dh %02dm", seconds // 3600, (seconds % 3600) // 60)
	elseif seconds >= 60 then
		return string.format("%dm %02ds", seconds // 60, seconds % 60)
	end
	return string.format("%ds", seconds)
end

-- In-game clock: hour float → "6:30 AM".
function Format.Clock(hour: number, use24: boolean?): string
	local h = math.floor(hour) % 24
	local m = math.floor((hour % 1) * 60 / 10) * 10
	if use24 then
		return string.format("%02d:%02d", h, m)
	end
	local suffix = if h < 12 then "AM" else "PM"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%d:%02d %s", h12, m, suffix)
end

function Format.Percent(fraction: number, decimals: number?): string
	return string.format("%." .. (decimals or 0) .. "f%%", fraction * 100)
end

function Format.Plural(count: number, word: string, plural: string?): string
	if count == 1 then
		return "1 " .. word
	end
	return Format.Commas(count) .. " " .. (plural or (word .. "s"))
end

-- "2026-09-27" style date from a unix time (UTC).
function Format.Date(unix: number): string
	local t = os.date("!*t", math.floor(unix))
	return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

function Format.Weight(kg: number): string
	if kg >= 1000 then
		return string.format("%.2f t", kg / 1000)
	elseif kg >= 1 then
		return string.format("%.2f kg", kg)
	end
	return string.format("%d g", math.floor(kg * 1000 + 0.5))
end

-- Collapse runs of whitespace and trim; used before text filtering.
function Format.CleanName(text: string, maxLength: number): string
	text = text:gsub("[%c]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if #text > maxLength then
		text = text:sub(1, maxLength)
	end
	return text
end

return Format
