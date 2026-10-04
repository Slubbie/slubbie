-- The skill tree: Endurance, Agility, Aerial Control and Exploration. Each
-- node shows its rank, cost and what it needs; upgrades shape how you move in
-- casual play, while ranked runs and races use standard attributes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Abilities = require(ReplicatedStorage.Shared.Config.Abilities)
local Leveling = require(ReplicatedStorage.Shared.Logic.Leveling)
local Net = require(ReplicatedStorage.Shared.Net)
local SkillTree = require(ReplicatedStorage.Shared.Config.SkillTree)

local State = require(script.Parent.Parent.Parent.Core.State)
local Sfx = require(script.Parent.Parent.Parent.Audio.Sfx)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors

local function freePoints(profile: any): number
	return Leveling.SkillPoints(State.Level()) - SkillTree.SpentPoints(profile.Skills or {})
end

return {
	Id = "Skills",
	Title = "Skill Tree",
	Icon = "✦",
	Order = 3,
	Sections = { "Skills", "XP", "Credits" },
	Build = function(container: Frame)
		local profile = State.Profile
		if not profile then
			return
		end
		local ranks = profile.Skills or {}
		local free = freePoints(profile)
		local header = Kit.Row(container, 40, 12)
		Kit.Label(header, ("Skill points: %d"):format(free), 18, { Font = Kit.Fonts.Black, Size = UDim2.fromOffset(220, 40), TextColor3 = if free > 0 then C.Accent else C.Muted })
		local message = Kit.Label(header, "Upgrades apply in casual play; ranked runs and races use standard attributes.", 13, { Size = UDim2.new(1, -470, 1, 0), TextColor3 = C.Muted })
		Kit.Button(header, ("Respec (%d ¢)"):format(SkillTree.RespecCost), function()
			task.spawn(function()
				local ok, success, reason = pcall(Net.Invoke, "Skill.Respec")
				message.Text = if ok and success then "Points refunded." else tostring(reason or "Can't respec")
			end)
		end, "Ghost", { Size = UDim2.fromOffset(170, 36) })

		local detail = Kit.Panel(container, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 86),
			BackgroundColor3 = C.PanelLight,
		})
		Kit.Padding(detail, 10, 14)
		local detailTitle = Kit.Label(detail, "Select a skill", 16, { Font = Kit.Fonts.Bold, Size = UDim2.new(1, 0, 0, 22) })
		local detailText = Kit.Label(detail, "Abilities unlock with your level; skills refine how they feel.", 14, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 40), TextColor3 = C.Muted, TextYAlignment = Enum.TextYAlignment.Top })

		local columns = Kit.new("Frame", {
			Position = UDim2.fromOffset(0, 50),
			Size = UDim2.new(1, 0, 1, -146),
			BackgroundTransparency = 1,
			Parent = container,
		})
		local grid = Kit.List(columns, true, 10)
		grid.VerticalAlignment = Enum.VerticalAlignment.Top
		for _, branch in SkillTree.Branches do
			local column = Kit.Scroll(columns, { Size = UDim2.new(0.25, -8, 1, 0) })
			Kit.List(column, false, 8)
			Kit.Label(column, branch.Name, 17, { Font = Kit.Fonts.Black, TextColor3 = branch.Color })
			Kit.Paragraph(column, branch.Blurb, 12, C.Muted)
			local nodes = {}
			for _, node in SkillTree.Nodes do
				if node.Branch == branch.Id then
					table.insert(nodes, node)
				end
			end
			table.sort(nodes, function(a, b)
				if a.Tier ~= b.Tier then
					return a.Tier < b.Tier
				end
				return a.Column < b.Column
			end)
			for _, node in nodes do
				local rank = ranks[node.Id] or 0
				local can, reason = SkillTree.CanUnlock(ranks, free, node.Id)
				local maxed = rank >= node.MaxRank
				local mark = if maxed then "✓" elseif can then "+" elseif rank > 0 then "◐" else "🔒"
				local button = Kit.Button(column, ("%s %s  %d/%d"):format(mark, node.Name, rank, node.MaxRank), nil, if can then "Primary" else "Secondary", {
					Size = UDim2.new(1, -8, 0, 44),
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundColor3 = if maxed then branch.Color:Lerp(C.PanelLight, 0.6) elseif can then C.Accent else C.PanelLight,
				})
				Kit.Padding(button, 0, 10)
				if node.Capstone then
					local stroke = button:FindFirstChildOfClass("UIStroke")
					if stroke then
						stroke.Color = branch.Color
						stroke.Transparency = 0
					end
				end
				local function describe()
					detailTitle.Text = ("%s  ·  rank %d/%d  ·  %d point%s"):format(node.Name, rank, node.MaxRank, node.Cost, if node.Cost == 1 then "" else "s")
					local status = if maxed then "Maxed." elseif can then "Click to learn the next rank." else (reason or "Locked")
					detailText.Text = node.Description .. "  " .. status
				end
				button.MouseEnter:Connect(describe)
				button.SelectionGained:Connect(describe)
				button.Activated:Connect(function()
					describe()
					if not can then
						Sfx.Stinger("Error")
						return
					end
					task.spawn(function()
						local ok, success, why = pcall(Net.Invoke, "Skill.Unlock", node.Id)
						if ok and success then
							Sfx.Stinger("Unlock")
						else
							detailText.Text = tostring(why or "Couldn't learn that")
						end
					end)
				end)
			end
		end
		-- Upcoming ability unlocks, so players always know what's next.
		local level = State.Level()
		local upcoming = nil
		for _, ability in Abilities.List do
			if ability.Level > level and (not upcoming or ability.Level < upcoming.Level) then
				upcoming = ability
			end
		end
		if upcoming then
			detailText.Text ..= ("\nNext ability: %s at level %d."):format(upcoming.Name, upcoming.Level)
		end
	end,
}
