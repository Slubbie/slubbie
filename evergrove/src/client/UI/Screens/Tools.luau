-- Bram's forge: every tool family, its current tier and the next upgrade
-- (cost, materials, skill requirement, what gets better).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local Tools = require(Shared.Config.Tools)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Describe = require(UI.Describe)
local C = require(UI.Parent.Controllers)

local function tierSummary(tier: any): string
	local parts = { "area " .. tier.MaxArea .. "×" .. tier.MaxArea, "energy " .. tier.Energy }
	if tier.Capacity then
		table.insert(parts, "holds " .. tier.Capacity)
	end
	if tier.Power then
		table.insert(parts, "power " .. tier.Power)
	end
	if tier.Speed and tier.Speed < 1 then
		table.insert(parts, math.floor((1 - tier.Speed) * 100) .. "% faster")
	end
	return table.concat(parts, " · ")
end

return {
	Id = "Tools",
	Title = "Bram's Forge",
	Icon = "⚒️",
	Size = Vector2.new(900, 600),
	Watch = { "Tools", "Coins", "Inventory", "Skills" },
	Build = function(win)
		local content = win.Content :: Frame
		local function render()
			Kit.Clear(content)
			local profile = C.State.Data()
			if not profile then
				return
			end
			local discount = Stats.ShopDiscount(profile, "forge")
			local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			list.Parent = content
			Kit.List(list, "Y", 8)
			for i, family in Tools.Families do
				local tierIndex = profile.Tools[family.Id] or 1
				local tier = family.Tiers[tierIndex]
				local nextTier = family.Tiers[tierIndex + 1]
				local card = Kit.Card(96)
				card.LayoutOrder = i
				card.Parent = list
				local icon = Kit.new("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(56, 56),
					Position = UDim2.fromOffset(0, 8),
					Text = family.Icon,
					TextScaled = true,
					Font = Theme.Fonts.Body,
					Parent = card,
				})
				icon.TextColor3 = tier.Color
				local name = Kit.Label(
					tier.Name
						.. " "
						.. family.Name
						.. "  "
						.. string.rep("★", tierIndex)
						.. string.rep("☆", #family.Tiers - tierIndex),
					{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold }
				)
				name.Position = UDim2.fromOffset(66, 0)
				name.Size = UDim2.new(0.5, -66, 0, 20)
				name.Parent = card
				local now = Kit.Label(
					tierSummary(tier) .. (if tier.Ability then "\n✨ " .. tier.Ability else ""),
					{ Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true }
				)
				now.Position = UDim2.fromOffset(66, 22)
				now.Size = UDim2.new(0.5, -66, 0, 0)
				now.Parent = card
				if nextTier then
					local price = math.floor(nextTier.Cost * (1 - discount))
					local mats = {}
					local haveAll = true
					for _, mat in nextTier.Mats do
						local def = Registry.Items[mat.Id]
						local have = Describe.CountInBag(profile, mat.Id)
						if have < mat.N then
							haveAll = false
						end
						table.insert(mats, (if def then def.Icon else mat.Id) .. " " .. have .. "/" .. mat.N)
					end
					local skillOk = Stats.SkillLevel(profile, family.Skill) >= nextTier.Level
					local nextText = "Next: "
						.. nextTier.Name
						.. " — "
						.. tierSummary(nextTier)
						.. (if nextTier.Ability then "\n✨ " .. nextTier.Ability else "")
						.. "\n"
						.. Kit.Money(price)
						.. "  "
						.. table.concat(mats, "  ")
						.. (if skillOk then "" else "   🔒 " .. family.Skill .. " " .. nextTier.Level)
					local nextLabel = Kit.Label(
						nextText,
						{ Size = Theme.Sizes.Tiny, Wrap = true, Color = if skillOk then "Text" else "Warn" }
					)
					nextLabel.Position = UDim2.new(0.5, 0, 0, 0)
					nextLabel.Size = UDim2.new(0.5, -130, 0, 0)
					nextLabel.Parent = card
					local upgrade = Kit.Button("Upgrade", {
						Style = "Accent",
						Size = UDim2.fromOffset(120, 38),
						TextSize = Theme.Sizes.Small,
						OnClick = function()
							local ok, err = Net.Request("ToolUpgrade", family.Id)
							if ok then
								C.Audio.PlayUI("LevelUp")
							else
								C.Notify.Toast(tostring(err), "Warning")
							end
						end,
					})
					upgrade.Position = UDim2.new(1, -120, 0.5, -19)
					upgrade.Parent = card
					Kit.SetEnabled(upgrade, skillOk and haveAll and profile.Coins >= price)
				else
					local maxed = Kit.Label("★ The finest there is.", { Size = Theme.Sizes.Small, Color = "Accent" })
					maxed.Position = UDim2.new(0.5, 0, 0, 30)
					maxed.Size = UDim2.new(0.5, 0, 0, 20)
					maxed.Parent = card
				end
			end
			Kit.RepaintGradients(list)
		end
		render()
		return { Refresh = render }
	end,
}
