-- Number and text formatting shared by UI and server messages.

local Format = {}

-- 1234 -> "1,234"; 123456 -> "123.5K"; 12345678 -> "12.3M". Keeps numbers short on screen.
function Format.Coins(n: number): string
	n = math.floor(n)
	local abs = math.abs(n)
	if abs >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif abs >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif abs >= 1e5 then
		return string.format("%.1fK", n / 1e3)
	end
	local s = tostring(abs)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-" else "") .. out
end

function Format.Seconds(s: number): string
	s = math.max(0, s)
	if s >= 60 then
		s = math.floor(s)
	end
	if s >= 3600 then
		return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
	elseif s >= 60 then
		return string.format("%dm %02ds", s // 60, s % 60)
	end
	return string.format("%ds", math.ceil(s))
end

-- Color3 from a config {r, g, b} list.
function Format.Color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

return Format
