-- Text formatting used by the HUD, menus and results.

local Format = {}

-- 83.456 → "1:23.46"; 9.1 → "9.10"
function Format.Time(seconds: number?): string
	if not seconds or seconds ~= seconds or seconds == math.huge then
		return "--:--.--"
	end
	local negative = seconds < 0
	seconds = math.abs(seconds)
	local minutes = math.floor(seconds / 60)
	local rest = seconds - minutes * 60
	local text
	if minutes > 0 then
		text = ("%d:%05.2f"):format(minutes, rest)
	else
		text = ("%.2f"):format(rest)
	end
	return if negative then "-" .. text else text
end

-- Split delta: "+0.42" / "-1.05"
function Format.Delta(seconds: number): string
	local sign = if seconds >= 0 then "+" else "-"
	return sign .. Format.Time(math.abs(seconds))
end

-- 1234567 → "1,234,567"
function Format.Number(n: number): string
	local text = tostring(math.floor(n + 0.5))
	local negative = string.sub(text, 1, 1) == "-"
	if negative then
		text = string.sub(text, 2)
	end
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return if negative then "-" .. formatted else formatted
end

-- 3725 → "1h 2m"
function Format.Duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if hours > 0 then
		return ("%dh %dm"):format(hours, minutes)
	elseif minutes > 0 then
		return ("%dm %ds"):format(minutes, seconds % 60)
	end
	return ("%ds"):format(seconds)
end

function Format.Plural(count: number, word: string, plural: string?): string
	return ("%s %s"):format(Format.Number(count), if count == 1 then word else (plural or word .. "s"))
end

-- "WallRun" → "Wall Run"
function Format.Spaced(id: string): string
	return (string.gsub(id, "(%l)(%u)", "%1 %2"))
end

return Format
