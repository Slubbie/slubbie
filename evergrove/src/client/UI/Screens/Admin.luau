-- Admin console (Config/Gameplay.Debug.Hotkey, F8 by default; admins only —
-- the server checks every command).
--
-- Type a command with positional or key=value arguments:
--   give carrot 20 4        coins 50000        weather Thunderstorm 2
--   hour 21                 season 3           skip 6
--   xp Farming 5000         grow 0.5           ripen
--   mutate 12_7 Golden      animal cow         machines
--   festival SpringFair     quest story_1_1 complete
--   unlock Skyreach         tp Mine            inspect 12345     save
-- Quick buttons cover the common ones. Output from the server is logged here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)

local POSITIONAL: { [string]: { string } } = {
	give = { "Id", "N", "Q" },
	coins = { "N" },
	tokens = { "N" },
	weather = { "Id", "Hours" },
	hour = { "Hour" },
	season = { "Season" },
	skip = { "Hours" },
	xp = { "Skill", "N" },
	grow = { "Fraction" },
	mutate = { "Key", "Mutation" },
	animal = { "Species" },
	festival = { "Id" },
	quest = { "Id", "Action" },
	unlock = { "Region" },
	tp = { "Region" },
	inspect = { "UserId" },
}

local QUICK = {
	{ "Help", "help" },
	{ "+50k coins", "coins 50000" },
	{ "Energy", "energy" },
	{ "Ripen all", "ripen" },
	{ "Finish machines", "machines" },
	{ "Skip 6h", "skip 6" },
	{ "Night", "hour 21" },
	{ "Morning", "hour 7" },
	{ "Storm", "weather Thunderstorm 2" },
	{ "Clock", "clock" },
	{ "Save", "save" },
	{ "Server log", "log" },
}

local lines: { string } = {}
local refresh: (() -> ())? = nil

local Screen = {
	Id = "Admin",
	Title = "Admin Console",
	Icon = "🛠️",
	Size = Vector2.new(900, 580),
}

function Screen.Log(text: string)
	table.insert(lines, os.date("%H:%M:%S") .. "  " .. tostring(text))
	while #lines > 200 do
		table.remove(lines, 1)
	end
	if refresh then
		refresh()
	end
end

local function coerce(value: string): any
	local n = tonumber(value)
	if n then
		return n
	elseif value == "true" then
		return true
	elseif value == "false" then
		return false
	end
	return value
end

local function run(text: string)
	local words = string.split(string.gsub(text, "^%s+", ""), " ")
	local command = string.lower(table.remove(words, 1) or "")
	if command == "" then
		return
	end
	local args: { [string]: any } = {}
	local positional = POSITIONAL[command] or {}
	local index = 0
	for _, word in words do
		if word ~= "" then
			local key, value = string.match(word, "^(%w+)=(.+)$")
			if key and value then
				args[key] = coerce(value)
			else
				index += 1
				local name = positional[index]
				if name then
					args[name] = coerce(word)
				end
			end
		end
	end
	Screen.Log("> " .. text)
	task.spawn(function()
		local ok, result = Net.Request("Admin", command, args)
		Screen.Log((if ok then "" else "✖ ") .. tostring(result))
	end)
end

function Screen.Build(win)
	local content = win.Content :: Frame
	if not game:GetService("Players").LocalPlayer:GetAttribute("Admin") then
		Kit.Empty("Admins only.").Parent = content
		return nil
	end
	local quick = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 76), Parent = content })
	local grid = Kit.new("UIGridLayout", {
		CellSize = UDim2.new(1 / 6, -6, 0, 34),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = quick,
	})
	grid.FillDirectionMaxCells = 6
	for i, entry in QUICK do
		Kit.Button(entry[1], {
			Style = "Secondary",
			TextSize = Theme.Sizes.Tiny,
			LayoutOrder = i,
			OnClick = function()
				run(entry[2])
			end,
		}).Parent =
			quick
	end
	local output = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -130), Position = UDim2.fromOffset(0, 82) })
	output.Parent = content
	Kit.List(output, "Y", 2)
	local box = Kit.TextBox("command args…  (Enter to run)", { Size = UDim2.new(1, -100, 0, 38) })
	box.Position = UDim2.new(0, 0, 1, -38)
	box.Font = Enum.Font.Code
	box.Parent = content
	local runButton = Kit.Button("Run", {
		Style = "Primary",
		Size = UDim2.fromOffset(92, 38),
		OnClick = function()
			run(box.Text)
			box.Text = ""
		end,
	})
	runButton.Position = UDim2.new(1, -92, 1, -38)
	runButton.Parent = content
	box.FocusLost:Connect(function(enter)
		if enter then
			run(box.Text)
			box.Text = ""
			box:CaptureFocus()
		end
	end)
	local function render()
		Kit.Clear(output)
		for i, line in lines do
			local l = Kit.Label(line, {
				Size = Theme.Sizes.Tiny,
				Wrap = true,
				Font = Enum.Font.Code,
				Color = if string.sub(line, 11, 12) == "> "
					then "Accent"
					elseif string.find(line, "✖", 1, true) then "Bad"
					else "Text",
			})
			l.LayoutOrder = i
			l.Parent = output
		end
		output.CanvasPosition = Vector2.new(0, 1e6)
	end
	refresh = render
	render()
	task.defer(function()
		box:CaptureFocus()
	end)
	return {
		Destroy = function()
			refresh = nil
		end,
	}
end

return Screen
