-- The valley map: regions (locked ones show how to open them), fast-travel
-- signposts you've discovered, farms, and where you and other players are.
-- Opened at a signpost with { Travel = true }, discovered signposts become
-- travel buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Regions = require(Shared.Config.Regions)
local World = require(Shared.Config.World)
local WeatherMath = require(Shared.Lib.WeatherMath)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local C = require(UI.Parent.Controllers)

-- World bounds (from the regions) → map space.
local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
for _, region in Regions.List do
	minX = math.min(minX, region.Center.X - region.Radius)
	maxX = math.max(maxX, region.Center.X + region.Radius)
	minZ = math.min(minZ, region.Center.Z - region.Radius)
	maxZ = math.max(maxZ, region.Center.Z + region.Radius)
end
local spanX, spanZ = maxX - minX, maxZ - minZ

local function toMap(position: Vector3): UDim2
	return UDim2.fromScale((position.X - minX) / spanX, (position.Z - minZ) / spanZ)
end

local function unlockedText(profile: any, region: any): (boolean, string?)
	if not region.Unlock then
		return true, nil
	end
	if profile and profile.Regions and profile.Regions[region.Id] then
		return true, nil
	end
	return false, region.UnlockText
end

return {
	Id = "Map",
	Title = "Map of the Valley",
	Icon = "🗺️",
	Size = Vector2.new(1040, 660),
	Watch = { "Travel", "Regions", "Coins" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local travelMode = args.Travel == true
		local content = win.Content :: Frame
		local alive = true
		local selected: any = nil
		local render: () -> ()
		local mapFrame: Frame
		local dots: { [Player]: Frame } = {}

		local function travel(point: any)
			local ok, err = Net.Request("Travel", point.Id)
			if ok then
				ctx.Close()
				C.Audio.PlayUI("UIConfirm")
			else
				C.Notify.Toast(tostring(err), "Warning")
			end
		end

		render = function()
			Kit.Clear(content)
			table.clear(dots)
			local profile = C.State.Data()
			local side = math.min(560, 560)
			local holder = Kit.Panel({ Size = UDim2.fromOffset(side + 16, side + 16), Color = "Inset" })
			holder.Parent = content
			Kit.Padding(holder, 8, 8)
			mapFrame = Kit.new(
				"Frame",
				{ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, Parent = holder }
			)
			local aspect = Kit.new("UIAspectRatioConstraint", { AspectRatio = spanX / spanZ, Parent = mapFrame })
			aspect.DominantAxis = Enum.DominantAxis.Width
			-- Regions
			for _, region in Regions.List do
				local unlocked = unlockedText(profile, region)
				local circle = Kit.new("TextButton", {
					AutoButtonColor = false,
					Text = "",
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = toMap(region.Center),
					Size = UDim2.fromScale(region.Radius * 2 / spanX, region.Radius * 2 / spanZ),
					BackgroundColor3 = region.MapColor,
					BackgroundTransparency = if unlocked then 0.35 else 0.75,
					ZIndex = 2,
					Parent = mapFrame,
				})
				Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = circle })
				local label = Kit.new("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 16),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Text = region.Icon .. " " .. region.Name,
					Font = Theme.Fonts.Bold,
					TextSize = 11,
					TextColor3 = Color3.new(1, 1, 1),
					TextStrokeTransparency = 0.3,
					ZIndex = 3,
					Parent = circle,
				})
				label.TextTransparency = if unlocked then 0 else 0.4
				circle.Activated:Connect(function()
					selected = { Region = region }
					render()
				end)
			end
			-- Farms
			for _, lot in World.Farms.Lots do
				local origin = lot.Origin
				local center = origin + Vector3.new(120, 0, 100)
				local mine = Players.LocalPlayer:GetAttribute("Lot") == lot.Id
				local square = Kit.new("Frame", {
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = toMap(center),
					Size = UDim2.fromScale(240 / spanX, 280 / spanZ),
					BackgroundColor3 = if mine then Color3.fromRGB(255, 214, 90) else Color3.fromRGB(150, 190, 110),
					BackgroundTransparency = 0.3,
					ZIndex = 4,
					Parent = mapFrame,
				})
				Kit.Corner(square, 3)
				if mine then
					Kit.new("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						Text = "🏡",
						TextScaled = true,
						ZIndex = 5,
						Parent = square,
					})
				end
			end
			-- Signposts
			for _, point in World.Travel do
				local found = profile and profile.Travel and profile.Travel[point.Id]
				local b = Kit.new("TextButton", {
					AutoButtonColor = true,
					Text = if found then "🪧" else "·",
					TextScaled = true,
					Font = Theme.Fonts.Body,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = toMap(point.Position),
					Size = UDim2.fromOffset(if found then 22 else 10, if found then 22 else 10),
					BackgroundTransparency = 1,
					ZIndex = 6,
					TextColor3 = Color3.new(1, 1, 1),
					Parent = mapFrame,
				})
				b.Activated:Connect(function()
					selected = { Point = point }
					render()
				end)
				Kit.AttachTooltip(b, function()
					return {
						{ Text = if found then point.Name else "Undiscovered signpost", Bold = true },
						{
							Text = if found
								then (if travelMode then "Click to travel" else "Discovered")
								else "Walk near it to discover it",
							Color = "SubText",
							Size = Theme.Sizes.Tiny,
						},
					}
				end)
			end
			-- Detail panel
			local right = Kit.Panel({
				Size = UDim2.new(1, -(side + 28), 1, 0),
				Position = UDim2.fromOffset(side + 28, 0),
				Color = "PanelAlt",
			})
			right.Parent = content
			Kit.Padding(right, 12, 14)
			Kit.List(right, "Y", 8)
			if travelMode then
				local tip = Kit.Label(
					"🪧 Fast travel: "
						.. Kit.Money(World.TravelCost)
						.. " per trip (free with the Cartographer perk).",
					{ Size = Theme.Sizes.Small, Color = "Accent", Wrap = true }
				)
				tip.Parent = right
			end
			if selected and selected.Region then
				local region = selected.Region
				local unlocked, how = unlockedText(profile, region)
				local h = Kit.Heading(region.Icon .. " " .. region.Name, 20)
				h.LayoutOrder = 1
				h.Parent = right
				local d = Kit.Label(region.Description, { Size = Theme.Sizes.Small, Wrap = true })
				d.LayoutOrder = 2
				d.Parent = right
				local weather = WeatherMath.Def(WeatherMath.ForRegion(WeatherMath.Current(), region))
				local w = Kit.Label(
					"Weather now: "
						.. (if weather then weather.Icon .. " " .. weather.Name else "?")
						.. (if region.Hazard then "\n⚠️ " .. region.Hazard.Text else ""),
					{ Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }
				)
				w.LayoutOrder = 3
				w.Parent = right
				if not unlocked then
					local l = Kit.Label(
						"🔒 " .. (how or "Locked"),
						{ Size = Theme.Sizes.Small, Color = "Warn", Wrap = true }
					)
					l.LayoutOrder = 4
					l.Parent = right
				end
				local finds = {}
				for _, id in region.Forage or {} do
					local item = Registry.Items[id]
					if item and #finds < 8 then
						table.insert(finds, item.Icon)
					end
				end
				if #finds > 0 then
					local f = Kit.Label("Forage: " .. table.concat(finds, " "), { Size = Theme.Sizes.Small })
					f.LayoutOrder = 5
					f.Parent = right
				end
				local order = 10
				for _, point in World.Travel do
					if point.Region == region.Id then
						order += 1
						local found = profile and profile.Travel and profile.Travel[point.Id]
						local b = Kit.Button(
							(if found then "🪧 " else "❔ ")
								.. (if found then point.Name else "Undiscovered signpost"),
							{
								Style = if found and travelMode then "Primary" else "Secondary",
								Size = UDim2.new(1, 0, 0, 34),
								TextSize = Theme.Sizes.Tiny,
								LayoutOrder = order,
								OnClick = function()
									if found and travelMode then
										travel(point)
									end
								end,
							}
						)
						b.Parent = right
					end
				end
			elseif selected and selected.Point then
				local point = selected.Point
				local found = profile and profile.Travel and profile.Travel[point.Id]
				local h = Kit.Heading("🪧 " .. (if found then point.Name else "Undiscovered"), 20)
				h.LayoutOrder = 1
				h.Parent = right
				local region = Registry.Regions[point.Region]
				if region then
					local r =
						Kit.Label(region.Icon .. " " .. region.Name, { Size = Theme.Sizes.Small, Color = "SubText" })
					r.LayoutOrder = 2
					r.Parent = right
				end
				if found and travelMode then
					Kit.Button("Travel here (" .. Kit.Money(World.TravelCost) .. ")", {
						Style = "Accent",
						Size = UDim2.new(1, 0, 0, 40),
						LayoutOrder = 3,
						OnClick = function()
							travel(point)
						end,
					}).Parent =
						right
				elseif not found then
					local l = Kit.Label(
						"Walk near this signpost to add it to your map.",
						{ Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }
					)
					l.LayoutOrder = 3
					l.Parent = right
				end
			else
				local count = 0
				for _, point in World.Travel do
					if profile and profile.Travel and profile.Travel[point.Id] then
						count += 1
					end
				end
				local l = Kit.Label(
					"Select a region or signpost.\n\n🪧 "
						.. count
						.. " / "
						.. #World.Travel
						.. " signposts discovered.\n🟡 You  ·  ⚪ other farmers  ·  🏡 your farm",
					{ Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }
				)
				l.LayoutOrder = 1
				l.Parent = right
				if travelMode then
					local order = 10
					for _, point in World.Travel do
						if profile and profile.Travel and profile.Travel[point.Id] then
							order += 1
							Kit.Button("🪧 " .. point.Name, {
								Style = "Secondary",
								Size = UDim2.new(1, 0, 0, 32),
								TextSize = Theme.Sizes.Tiny,
								LayoutOrder = order,
								OnClick = function()
									travel(point)
								end,
							}).Parent =
								right
						end
					end
				end
			end
			Kit.RepaintGradients(content)
		end

		-- Live player dots
		task.spawn(function()
			while alive do
				if mapFrame and mapFrame.Parent then
					for _, other in Players:GetPlayers() do
						local character = other.Character
						local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
						if rootPart then
							local dot = dots[other]
							if not dot or not dot.Parent then
								local me = other == Players.LocalPlayer
								local d = Kit.new("Frame", {
									BorderSizePixel = 0,
									AnchorPoint = Vector2.new(0.5, 0.5),
									Size = UDim2.fromOffset(if me then 12 else 8, if me then 12 else 8),
									BackgroundColor3 = if me
										then Color3.fromRGB(255, 220, 60)
										else Color3.fromRGB(240, 240, 240),
									ZIndex = 8,
									Parent = mapFrame,
								})
								Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = d })
								Kit.new("UIStroke", { Thickness = 1.5, Color = Color3.new(0, 0, 0), Parent = d })
								if not me then
									Kit.new("TextLabel", {
										BackgroundTransparency = 1,
										Size = UDim2.fromOffset(100, 12),
										Position = UDim2.fromOffset(8, -4),
										Text = other.DisplayName,
										TextSize = 10,
										Font = Theme.Fonts.Bold,
										TextColor3 = Color3.new(1, 1, 1),
										TextStrokeTransparency = 0.3,
										TextXAlignment = Enum.TextXAlignment.Left,
										ZIndex = 8,
										Parent = d,
									})
								end
								dots[other] = d
								dot = d
							end
							(dot :: Frame).Position = toMap(rootPart.Position)
						end
					end
				end
				task.wait(0.25)
			end
		end)

		render()
		return {
			Refresh = render,
			Destroy = function()
				alive = false
			end,
		}
	end,
}
