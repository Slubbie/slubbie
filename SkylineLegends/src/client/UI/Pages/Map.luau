-- The map of Meridian: every district on its ring around the Guildhall, what
-- you've found and finished in each, where you are, where your pinned
-- objective is, and fast travel between plazas you've unlocked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Access = require(ReplicatedStorage.Shared.Logic.Access)
local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Net = require(ReplicatedStorage.Shared.Net)

local Bus = require(script.Parent.Parent.Parent.Core.Bus)
local State = require(script.Parent.Parent.Parent.Core.State)
local Controller = require(script.Parent.Parent.Parent.Movement.Controller)
local CourseClient = require(script.Parent.Parent.Parent.Gameplay.CourseClient)
local Explore = require(script.Parent.Parent.Parent.Gameplay.Explore)
local QuestClient = require(script.Parent.Parent.Parent.Gameplay.QuestClient)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors

local selected = "Hub"

local function medalSummary(districtId: string): (number, number, number)
	local profile = State.Profile
	local total, finished, gold = 0, 0, 0
	for _, course in Courses.Of(districtId) do
		total += 1
		local record = profile and profile.Courses and profile.Courses[course.Id]
		if record and (record.Completions or 0) > 0 then
			finished += 1
			if (record.Medal or 0) >= 3 then
				gold += 1
			end
		end
	end
	return total, finished, gold
end

local function travel(districtId: string, note: TextLabel)
	note.Text = "Travelling…"
	note.TextColor3 = C.Muted
	task.spawn(function()
		local ok, allowed, destination = pcall(Net.Invoke, "Travel.Go", districtId)
		if ok and allowed and typeof(destination) == "CFrame" then
			Bus.ClosePages:Fire()
			Controller.Teleport(destination)
		else
			note.Text = if ok and type(destination) == "string" then destination else "Can't travel right now"
			note.TextColor3 = C.Bad
		end
	end)
end

local function details(parent: Frame, districtId: string)
	Kit.Clear(parent)
	local district = Districts.ById[districtId]
	local profile = State.Profile
	if not district or not profile then
		return
	end
	local ok, reason = Access.District(State.Level(), profile.Quests.Completed, districtId)
	local visited = profile.Districts and profile.Districts.Visited and profile.Districts.Visited[districtId]
	Kit.Label(parent, district.Name, 22, { Font = Kit.Fonts.Black, TextColor3 = C.Accent })
	Kit.Paragraph(parent, district.Tagline, 15, C.Text)
	Kit.Paragraph(parent, district.Lore, 14, C.Muted)
	for _, trait in district.Traits do
		Kit.Paragraph(parent, "• " .. trait, 13, C.Muted)
	end
	local total, finished, gold = medalSummary(districtId)
	local foundAll, totalAll = Explore.Count(nil, districtId)
	Kit.Paragraph(
		parent,
		("Courses %d/%d finished · %d at gold or better\nDiscoveries %d/%d"):format(
			finished,
			total,
			gold,
			foundAll,
			totalAll
		),
		14,
		C.Text
	)
	local status = if not ok
		then "🔒 " .. tostring(reason)
		elseif visited then "✓ Visited"
		else "Unvisited — go and see it"
	Kit.Paragraph(parent, status, 14, if ok then C.Good else C.Warn)
	local note = Kit.Paragraph(parent, "", 13, C.Muted)
	if ok then
		local button = Kit.Button(parent, "Travel to the plaza", function()
			travel(districtId, note)
		end, "Primary", { Size = UDim2.fromOffset(200, 40) })
		if CourseClient.Run then
			button.Visible = false
			note.Text = "Finish or leave your run to travel."
		end
	end
end

return {
	Id = "Map",
	Title = "Map",
	Icon = "◎",
	Order = 1,
	Sections = { "Districts", "Quests", "Discoveries", "Courses" },
	Build = function(container: Frame, args: any)
		if type(args) == "table" and type(args.District) == "string" then
			selected = args.District
		end
		local canvas = Kit.new("Frame", {
			Size = UDim2.new(0.62, -10, 1, 0),
			BackgroundColor3 = Color3.fromRGB(16, 20, 30),
			BackgroundTransparency = 0.1,
			ClipsDescendants = true,
			Parent = container,
		})
		Kit.Corner(canvas, 12)
		local side = Kit.Scroll(container, { Position = UDim2.new(0.62, 10, 0, 0), Size = UDim2.new(0.38, -10, 1, 0) })
		Kit.List(side, false, 8)
		Kit.Padding(side, 4)

		-- Project world XZ onto the canvas.
		local extent = 1900
		local function project(position: Vector3): UDim2
			return UDim2.fromScale(0.5 + position.X / (extent * 2.2), 0.5 + position.Z / (extent * 2.2))
		end
		local hub = Districts.ById.Hub
		local profile = State.Profile
		for _, district in Districts.Ordered() do
			local ok = profile ~= nil and Access.District(State.Level(), profile.Quests.Completed, district.Id)
			local visited = profile
				and profile.Districts
				and profile.Districts.Visited
				and profile.Districts.Visited[district.Id]
			-- Spoke from the hub.
			if district.Id ~= "Hub" then
				local a, b = project(hub.Origin), project(district.Origin)
				local mid = UDim2.fromScale((a.X.Scale + b.X.Scale) / 2, (a.Y.Scale + b.Y.Scale) / 2)
				local dx = (b.X.Scale - a.X.Scale)
				local dy = (b.Y.Scale - a.Y.Scale)
				local line = Kit.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = mid,
					BackgroundColor3 = if ok then C.Signal else C.Line,
					BackgroundTransparency = 0.5,
					BorderSizePixel = 0,
					Parent = canvas,
				})
				-- Size and rotate once the canvas has a size.
				local function place()
					local size = canvas.AbsoluteSize
					local length = math.sqrt((dx * size.X) ^ 2 + (dy * size.Y) ^ 2)
					line.Size = UDim2.fromOffset(length, 3)
					line.Rotation = math.deg(math.atan2(dy * size.Y, dx * size.X))
				end
				place()
				canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
			end
			local node = Kit.Button(
				canvas,
				"",
				function()
					selected = district.Id
					details(side, selected)
				end,
				if selected == district.Id then "Primary" else "Secondary",
				{
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = project(district.Origin),
					Size = UDim2.fromOffset(150, 52),
					ZIndex = 3,
				}
			)
			node.Text = ("%s\n%s"):format(
				district.Short,
				if not ok then "🔒 locked" elseif visited then "✓ visited" else "new"
			)
			Kit.TextSize(node, 14)
		end
		-- You.
		local root = Controller.Info.Root
		if root then
			Kit.Label(canvas, "▲ YOU", 14, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = project(root.Position),
				Size = UDim2.fromOffset(70, 20),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = C.Good,
				Font = Kit.Fonts.Black,
				ZIndex = 4,
			})
		end
		local target = QuestClient.PinnedTarget()
		if target then
			Kit.Label(canvas, "◆ " .. string.sub(target.Label, 1, 28), 13, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = project(target.Position),
				Size = UDim2.fromOffset(220, 20),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = C.Accent,
				Font = Kit.Fonts.Bold,
				ZIndex = 4,
			})
		end
		Kit.Label(canvas, "Spire beside the Guildhall · Dreamline portal in the Commons", 12, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -20, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.Faint,
		})
		details(side, selected)
	end,
}
