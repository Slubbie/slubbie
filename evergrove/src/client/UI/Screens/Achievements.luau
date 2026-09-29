-- Achievements: every goal with live progress from your stats, its tier and
-- rewards (coins, titles, banners, frames, auras). Hidden achievements stay
-- secret until earned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Lib.Format)
local Achievements = require(Shared.Config.Achievements)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Describe = require(UI.Describe)
local C = require(UI.Parent.Controllers)

local TIER_COLOR = { Bronze = Color3.fromRGB(205, 127, 50), Silver = Color3.fromRGB(200, 205, 215), Gold = Color3.fromRGB(255, 205, 60), Platinum = Color3.fromRGB(170, 230, 255) }

local function rewardText(reward: any): string
	local parts = Describe.Rewards(reward)
	for _, key in { "Banner", "Frame", "Effect" } do
		if reward[key] then
			table.insert(parts, (({ Banner = "🚩", Frame = "🖼️", Effect = "✨" }) :: any)[key] .. " " .. key .. ": " .. string.gsub(reward[key], "_", " "))
		end
	end
	return table.concat(parts, "  ·  ")
end

return {
	Id = "Achievements",
	Title = "Achievements",
	Icon = "🏅",
	Size = Vector2.new(940, 620),
	Watch = { "Achievements", "Stats" },
	Build = function(win)
		local content = win.Content :: Frame
		local filter = "All"
		local function render()
			Kit.Clear(content)
			local profile = C.State.Data()
			local earned = (profile and profile.Achievements) or {}
			local stats = (profile and profile.Stats) or {}
			local total, got = #Achievements.List, 0
			for _, def in Achievements.List do
				if earned[def.Id] then
					got += 1
				end
			end
			local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = content })
			local progress = Kit.Progress({ Size = UDim2.new(1, -330, 0, 18), Color = "Accent" })
			progress.Frame.Position = UDim2.fromOffset(0, 8)
			progress.Frame.Parent = top
			progress.Set(got / total, "🏅 " .. got .. " / " .. total, false)
			local chips = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(320, 34), Position = UDim2.new(1, -320, 0, 0), Parent = top })
			Kit.List(chips, "X", 6, "Right")
			for i, name in { "All", "In progress", "Earned" } do
				local b = Kit.Button(name, { Style = if filter == name then "Primary" else "Secondary", Size = UDim2.fromOffset(100, 32), TextSize = Theme.Sizes.Tiny, LayoutOrder = i, OnClick = function()
					filter = name
					render()
				end })
				b.Parent = chips
			end
			local grid = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -44), Position = UDim2.fromOffset(0, 44) })
			grid.Parent = content
			local layout = Kit.new("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 96), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
			layout.FillDirectionMaxCells = 2
			for i, def in Achievements.List do
				local done = earned[def.Id] ~= nil
				local show = filter == "All" or (filter == "Earned" and done) or (filter == "In progress" and not done)
				if show then
					local secret = def.Hidden and not done
					local card = Kit.Card(96)
					card.LayoutOrder = if done then i + 10000 else i
					card.Parent = grid
					if done then
						local stroke = card:FindFirstChildOfClass("UIStroke")
						if stroke then
							stroke.Color = TIER_COLOR[def.Tier] or stroke.Color
							stroke.Thickness = 2
						end
					end
					local icon = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(52, 52), Text = if secret then "❔" else def.Icon, TextScaled = true, Font = Theme.Fonts.Body, Parent = card })
					icon.TextTransparency = if done then 0 else 0.45
					local name = Kit.Label((if secret then "Secret achievement" else def.Name) .. "  ·  " .. def.Tier, { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
					name.TextColor3 = TIER_COLOR[def.Tier] or name.TextColor3
					name.Position = UDim2.fromOffset(60, 0)
					name.Size = UDim2.new(1, -60, 0, 20)
					name.Parent = card
					local desc = Kit.Label(if secret then "Keep playing to discover it." else def.Description, { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
					desc.Position = UDim2.fromOffset(60, 20)
					desc.Size = UDim2.new(1, -60, 0, 0)
					desc.Parent = card
					if not secret then
						local reward = Kit.Label("🎁 " .. rewardText(def.Reward), { Size = Theme.Sizes.Tiny, Color = "Accent", Wrap = true })
						reward.Position = UDim2.fromOffset(60, 44)
						reward.Size = UDim2.new(1, -60, 0, 0)
						reward.Parent = card
					end
					if def.Stat and def.Goal and not done and not secret then
						local value = stats[def.Stat] or 0
						local bar = Kit.Progress({ Size = UDim2.new(1, -60, 0, 10), Color = "Info" })
						bar.Frame.Position = UDim2.new(0, 60, 1, -12)
						bar.Frame.Parent = card
						bar.Set(math.min(1, value / def.Goal), nil, false)
						Kit.AttachTooltip(card, function()
							return { { Text = Format.Commas(math.floor(value)) .. " / " .. Format.Commas(def.Goal) } }
						end)
					elseif done then
						local when = Kit.Label("✔ Earned", { Size = Theme.Sizes.Tiny, Color = "Good", Align = "Right" })
						when.Size = UDim2.new(0, 100, 0, 14)
						when.Position = UDim2.new(1, -100, 1, -14)
						when.Parent = card
					end
				end
			end
			Kit.RepaintGradients(content)
		end
		render()
		return { Refresh = render }
	end,
}
