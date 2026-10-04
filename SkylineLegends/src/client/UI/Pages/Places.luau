-- Pages opened from the world rather than the menu rail: the lift gates
-- (travel), the Spire lift (pick a floor) and district job boards (contracts).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Access = require(ReplicatedStorage.Shared.Logic.Access)
local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)

local Bus = require(script.Parent.Parent.Parent.Core.Bus)
local State = require(script.Parent.Parent.Parent.Core.State)
local Controller = require(script.Parent.Parent.Parent.Movement.Controller)
local Modes = require(script.Parent.Parent.Parent.Gameplay.Modes)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors

-- Travel -----------------------------------------------------------------------------------------------

local function buildTravel(container: Frame, args: any)
	local profile = State.Profile
	if not profile then
		return
	end
	local scroll = Kit.Scroll(container)
	Kit.List(scroll, false, 8)
	Kit.Padding(scroll, 4)
	Kit.Paragraph(
		scroll,
		"The lift gates connect every plaza you've opened. New districts open with your level and the story.",
		14,
		C.Muted
	)
	local message = Kit.Paragraph(scroll, "", 13, C.Bad)
	local preferred = if type(args) == "table" then args.Destination else nil
	for _, district in Districts.Ordered() do
		local ok, reason = Access.District(State.Level(), profile.Quests.Completed, district.Id)
		local row = Kit.Panel(scroll, {
			Size = UDim2.new(1, -8, 0, 64),
			BackgroundColor3 = if district.Id == preferred then C.Accent:Lerp(C.PanelLight, 0.7) else C.PanelLight,
		})
		Kit.Padding(row, 8, 12)
		Kit.Label(
			row,
			district.Name,
			16,
			{ Font = Kit.Fonts.Bold, Size = UDim2.new(1, -170, 0, 22), TextColor3 = if ok then C.Text else C.Faint }
		)
		Kit.Label(row, if ok then district.Tagline else ("🔒 " .. tostring(reason)), 13, {
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, -170, 0, 20),
			TextColor3 = if ok then C.Muted else C.Warn,
		})
		if ok then
			Kit.Button(
				row,
				"Travel",
				function()
					message.Text = "Travelling…"
					task.spawn(function()
						local okInvoke, allowed, destination = pcall(Net.Invoke, "Travel.Go", district.Id)
						if okInvoke and allowed and typeof(destination) == "CFrame" then
							Bus.ClosePages:Fire()
							Controller.Teleport(destination)
						else
							message.Text = if okInvoke and type(destination) == "string"
								then destination
								else "Can't travel right now"
						end
					end)
				end,
				"Primary",
				{
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Size = UDim2.fromOffset(140, 38),
				}
			)
		end
	end
end

-- The Spire ---------------------------------------------------------------------------------------------

local function buildTower(container: Frame)
	local profile = State.Profile
	if not profile then
		return
	end
	local tower = profile.Tower or {}
	local highest = tower.Highest or 0
	Kit.Paragraph(
		container,
		("25 floors, each a short route that asks for more of your kit. Highest cleared: %d. Every fifth floor is a milestone."):format(
			highest
		),
		14,
		C.Muted
	)
	local message = Kit.Label(container, "", 13, { Position = UDim2.fromOffset(0, 40), TextColor3 = C.Bad })
	local grid = Kit.Scroll(container, { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 1, -70) })
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(150, 64),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for floor = 1, 25 do
		local cleared = floor <= highest
		local open = floor <= highest + 1
		local best = tower.Best and tower.Best[tostring(floor)]
		local text = ("Floor %d\n%s"):format(
			floor,
			if cleared then "✓ " .. Format.Time(best) elseif open then "▶ next" else "🔒"
		)
		local button = Kit.Button(
			grid,
			text,
			function()
				if not open then
					return
				end
				message.Text = "Riding up…"
				task.spawn(function()
					local ok, reason = Modes.EnterTower(floor)
					if ok then
						Bus.ClosePages:Fire()
					else
						message.Text = reason or "The lift won't move"
					end
				end)
			end,
			if open and not cleared then "Primary" else "Secondary",
			{
				LayoutOrder = floor,
				BackgroundColor3 = if floor % 5 == 0 and cleared
					then C.Accent:Lerp(C.PanelLight, 0.6)
					elseif open and not cleared then C.Accent
					elseif cleared then C.PanelLight
					else C.Panel,
			}
		)
		Kit.TextSize(button, 14)
	end
end

-- Job board ----------------------------------------------------------------------------------------------

local function buildJobs(container: Frame, args: any)
	local district = if type(args) == "table" and type(args.District) == "string" then args.District else "Hub"
	local scroll = Kit.Scroll(container)
	Kit.List(scroll, false, 10)
	Kit.Padding(scroll, 4)
	Kit.Paragraph(
		scroll,
		("Job board · %s. Contracts are quick, repeatable work: deliveries against the clock, relay checks and route certifications."):format(
			Districts.ById[district] and Districts.ById[district].Name or district
		),
		14,
		C.Muted
	)
	local status = Kit.Paragraph(scroll, "Reading the board…", 13, C.Faint)
	task.spawn(function()
		local ok, data = pcall(Net.Invoke, "Contract.Take", district)
		if not scroll.Parent then
			return
		end
		if not ok or type(data) ~= "table" then
			status.Text = "The board is empty right now."
			return
		end
		status.Text = ("New offers in %s"):format(Format.Duration(math.max(data.Refresh or 0, 0)))
		if data.Active then
			local card = Kit.Card(scroll)
			Kit.Label(
				card,
				"Your contract: " .. tostring(data.Active.Name),
				16,
				{ Font = Kit.Fonts.Bold, TextColor3 = C.Good }
			)
			Kit.Paragraph(card, tostring(data.Active.Text), 14, C.Text)
			Kit.Button(card, "Abandon", function()
				task.spawn(pcall, Net.Invoke, "Contract.Take", nil)
				Bus.ClosePages:Fire()
			end, "Ghost", { Size = UDim2.fromOffset(120, 34) })
		end
		for index, offer in data.Offers or {} do
			local card = Kit.Card(scroll)
			Kit.Label(card, tostring(offer.Name), 16, { Font = Kit.Fonts.Bold, TextColor3 = C.Accent })
			Kit.Paragraph(card, tostring(offer.Text), 14, C.Text)
			Kit.Label(card, "Pays " .. Kit.Rewards(offer.Reward), 13, { TextColor3 = C.Accent })
			local note = Kit.Paragraph(card, "", 13, C.Bad)
			Kit.Button(card, "Take the job", function()
				task.spawn(function()
					local okTake, result = pcall(Net.Invoke, "Contract.Take", district, index)
					if okTake and type(result) == "table" and result.Active then
						Bus.ClosePages:Fire()
					else
						note.Text = if okTake
								and type(result) == "table"
								and result.Error
							then result.Error
							else "Couldn't take that job"
					end
				end)
			end, "Primary", { Size = UDim2.fromOffset(160, 36) })
		end
	end)
end

return {
	Pages = {
		{
			Id = "Travel",
			Title = "Lift Gates",
			Icon = "⇄",
			Order = 50,
			Hidden = true,
			Sections = { "Quests", "XP" },
			Build = buildTravel,
		},
		{
			Id = "Tower",
			Title = "The Spire",
			Icon = "▥",
			Order = 51,
			Hidden = true,
			Sections = { "Tower" },
			Build = buildTower,
		},
		{
			Id = "Jobs",
			Title = "Job Board",
			Icon = "✉",
			Order = 52,
			Hidden = true,
			Sections = { "Contracts" },
			Build = buildJobs,
		},
	},
}
