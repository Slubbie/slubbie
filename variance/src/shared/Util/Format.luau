-- Text formatting helpers shared by UI, boards and server messages.

local Format = {}

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

function Format.roman(n: number): string
	return ROMAN[n] or tostring(n)
end

-- 0.4 -> "40%" ; keeps one decimal below 10% so tiny odds don't read as 0%.
function Format.percent(p: number): string
	local value = math.clamp(p, 0, 1) * 100
	if value > 0 and value < 10 then
		return string.format("%.1f%%", value)
	end
	return string.format("%d%%", math.floor(value + 0.5))
end

function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Long spans read as days/hours/minutes: "6d 9h", "9h 46m", "4:05".
function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	if seconds >= 86400 then
		return string.format("%dd %dh", seconds // 86400, (seconds % 86400) // 3600)
	elseif seconds >= 3600 then
		return string.format("%dh %dm", seconds // 3600, (seconds % 3600) // 60)
	end
	return Format.clock(seconds)
end

-- 1234567 -> "1,234,567"
function Format.thousands(n: number): string
	local s = tostring(math.floor(n))
	local negative = string.sub(s, 1, 1) == "-"
	if negative then
		s = string.sub(s, 2)
	end
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (negative and "-" or "") .. out
end

function Format.signed(n: number): string
	if n > 0 then
		return "+" .. tostring(n)
	end
	return tostring(n)
end

function Format.plural(n: number, singular: string, plural: string?): string
	if n == 1 then
		return "1 " .. singular
	end
	return tostring(n) .. " " .. (plural or (singular .. "s"))
end

-- Relative time for match history: "3m ago", "2h ago", "5d ago".
function Format.ago(seconds: number): string
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return string.format("%dm ago", seconds // 60)
	elseif seconds < 86400 then
		return string.format("%dh ago", seconds // 3600)
	end
	return string.format("%dd ago", seconds // 86400)
end

-- Strips anything that is not safe to show from a free-text field.
function Format.sanitize(text: string, maxLength: number): string
	local cleaned = string.gsub(text, "[%c]", "")
	cleaned = string.gsub(cleaned, "[<>]", "")
	if #cleaned > maxLength then
		cleaned = string.sub(cleaned, 1, maxLength)
	end
	return cleaned
end

-- Cell glyph words used in logs (the HUD draws shapes, never relies on color alone).
function Format.cell(charged: boolean): string
	return charged and "CHARGED" or "HOLLOW"
end

return Format
