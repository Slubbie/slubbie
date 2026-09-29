-- Skills: nine disciplines levelling from their own XP, each with a
-- per-level passive, titles and a branching tree (one branch per tier) to
-- spend points in. Respec is available for an escalating coin cost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Stats = require(Shared.Lib.Stats)
local Format = require(Shared.Lib.Format)
local Skills = require(Shared.Config.Skills)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local C = require(UI.Parent.Controllers)

local function respecCost(profile: any, skillId: string): number
	local entry = profile.Skills[skillId]
	local level = Stats.SkillLevel(profile, skillId)
	local cost = Skills.Respec.Base * level * Skills.Respec.Growth ^ (entry and entry.Respecs or 0)
	return math.min(math.floor(cost / 100) * 100, Skills.Respec.Max)
end

return {
	Id = "Skills",
	Title = "Skills",
	Icon = "🌟",
	Size = Vector2.new(1000, 620),
	Watch = { "Skills", "Coins" },
	Build = function(win, ctx)
		local content = win.Content :: Frame
		local selected = (ctx.Args and ctx.Args.Skill) or "Farming"

		local function render()
			Kit.Clear(content)
			local profile = C.State.Data()
			if not profile then
				return
			end
			-- Skill list
			local left = Kit.Scroll({ Size = UDim2.new(0, 280, 1, 0) })
			left.Parent = content
			Kit.List(left, "Y", 6)
			local estate = Kit.Label("🏡 Estate level " .. Stats.EstateLevel(profile) .. "  ·  total " .. Stats.TotalLevels(profile), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
			estate.Parent = left
			for i, skill in Skills.List do
				local entry = profile.Skills[skill.Id]
				local level, into, need = Stats.LevelFor(entry and entry.XP or 0)
				local points = Stats.PointsAvailable(profile, skill.Id)
				local row = Kit.new("TextButton", { AutoButtonColor = false, Text = "", Size = UDim2.new(1, -8, 0, 56), LayoutOrder = i, Selectable = true, Parent = left })
				Kit.Paint(row, "BackgroundColor3", if selected == skill.Id then "SlotHover" else "PanelAlt")
				Kit.Corner(row, 8)
				local name = Kit.Label(skill.Icon .. " " .. skill.Name .. "  " .. level, { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
				name.Position = UDim2.fromOffset(10, 4)
				name.Size = UDim2.new(1, -60, 0, 20)
				name.Parent = row
				if points > 0 then
					local badge = Kit.Label("+" .. points, { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Color = "Accent", Align = "Right" })
					badge.Size = UDim2.fromOffset(44, 20)
					badge.Position = UDim2.new(1, -52, 0, 4)
					badge.Parent = row
				end
				local bar = Kit.Progress({ Size = UDim2.new(1, -20, 0, 12), Color = "Accent" })
				bar.Frame.Position = UDim2.fromOffset(10, 32)
				bar.Frame.Parent = row
				bar.SetColor("Good")
				bar.Frame:FindFirstChild("Fill").BackgroundColor3 = skill.Color
				bar.Set(if need > 0 then into / need else 1, if need > 0 then Format.Short(into) .. " / " .. Format.Short(need) else "MAX", false)
				row.Activated:Connect(function()
					selected = skill.Id
					Kit.PlaySound("UIClick")
					render()
				end)
			end
			-- Selected skill
			local skill
			for _, s in Skills.List do
				if s.Id == selected then
					skill = s
				end
			end
			if not skill then
				return
			end
			local entry = profile.Skills[skill.Id] or { XP = 0, Nodes = {} }
			local level = Stats.SkillLevel(profile, skill.Id)
			local points = Stats.PointsAvailable(profile, skill.Id)
			local right = Kit.Scroll({ Size = UDim2.new(1, -292, 1, 0), Position = UDim2.fromOffset(292, 0) })
			right.Parent = content
			Kit.List(right, "Y", 8)
			Kit.Heading(skill.Icon .. " " .. skill.Name .. " · level " .. level .. " · " .. points .. " point" .. (if points == 1 then "" else "s") .. " to spend", 20).Parent = right
			local desc = Kit.Label(skill.Description .. "\nPassive: " .. skill.Passive.Text .. string.format(" (now +%.1f%%)", skill.Passive.PerLevel * level * 100), { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
			desc.LayoutOrder = 1
			desc.Parent = right
			local titles = {}
			for lvl, title in skill.Titles do
				table.insert(titles, { Level = lvl, Title = title })
			end
			table.sort(titles, function(a, b)
				return a.Level < b.Level
			end)
			local titleTexts = {}
			for _, t in titles do
				table.insert(titleTexts, (if level >= t.Level then "🏷️ " else "🔒 ") .. t.Title .. " (" .. t.Level .. ")")
			end
			local titleLine = Kit.Label("Titles: " .. table.concat(titleTexts, "   "), { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
			titleLine.LayoutOrder = 2
			titleLine.Parent = right
			for tier = 1, #Skills.TierLevels do
				local tierLevel = Skills.TierLevels[tier]
				local header = Kit.Label("Tier " .. tier .. (if level >= tierLevel then "" else "  🔒 level " .. tierLevel), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Color = if level >= tierLevel then "Text" else "SubText" })
				header.LayoutOrder = 10 + tier * 10
				header.Parent = right
				local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 116), LayoutOrder = 11 + tier * 10, Parent = right })
				local layout = Kit.List(row, "X", 8)
				layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				local chosenBranch = nil
				for _, node in skill.Tree do
					if node.Tier == tier and node.Branch and (entry.Nodes[node.Id] or 0) > 0 then
						chosenBranch = node.Branch
					end
				end
				for _, node in skill.Tree do
					if node.Tier == tier then
						local rank = entry.Nodes[node.Id] or 0
						local blocked = node.Branch ~= nil and chosenBranch ~= nil and chosenBranch ~= node.Branch
						local card = Kit.Card(116)
						card.Size = UDim2.new(if node.Branch then 0.5 else 1, -4, 0, 116)
						card.Parent = row
						if blocked or level < tierLevel then
							card.BackgroundTransparency = 0.5
						end
						local name = Kit.Label(node.Icon .. " " .. node.Name .. "   " .. string.rep("●", rank) .. string.rep("○", node.MaxRank - rank), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
						name.Size = UDim2.new(1, 0, 0, 20)
						name.Parent = card
						local d = Kit.Label(node.Description, { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
						d.Position = UDim2.fromOffset(0, 22)
						d.Size = UDim2.new(1, 0, 0, 44)
						d.AutomaticSize = Enum.AutomaticSize.None
						d.Parent = card
						local canBuy = level >= tierLevel and not blocked and rank < node.MaxRank and points >= node.Cost
						local text = if rank >= node.MaxRank then "Maxed" elseif blocked then "Other path chosen" elseif level < tierLevel then "Locked" else "Learn (" .. node.Cost .. " pt" .. (if node.Cost > 1 then "s" else "") .. ")"
						local button = Kit.Button(text, { Style = if canBuy then "Accent" else "Ghost", Size = UDim2.new(1, 0, 0, 30), TextSize = Theme.Sizes.Tiny, OnClick = function()
							if not canBuy then
								return
							end
							local ok, err = Net.Request("SkillUnlock", skill.Id, node.Id)
							if ok then
								C.Audio.PlayUI("LevelUp")
							else
								C.Notify.Toast(tostring(err), "Warning")
							end
						end })
						button.Position = UDim2.new(0, 0, 1, -30)
						button.Parent = card
						Kit.SetEnabled(button, canBuy)
					end
				end
			end
			local hasNodes = next(entry.Nodes) ~= nil
			if hasNodes then
				local cost = respecCost(profile, skill.Id)
				local respec = Kit.Button("↺ Respec " .. skill.Name .. " (" .. Kit.Money(cost) .. ")", { Style = "Danger", Size = UDim2.fromOffset(280, 36), TextSize = Theme.Sizes.Small, LayoutOrder = 100, OnClick = function()
					Kit.Confirm("Reset your " .. skill.Name .. " tree?", "All points come back so you can choose different paths. Costs " .. Kit.Money(cost) .. " and gets pricier each time.", function(yes)
						if yes then
							local ok, err = Net.Request("SkillRespec", skill.Id)
							if not ok then
								C.Notify.Toast(tostring(err), "Warning")
							end
						end
					end, "Respec", true)
				end })
				respec.Parent = right
			end
			Kit.RepaintGradients(content)
		end
		render()
		return { Refresh = render }
	end,
}
